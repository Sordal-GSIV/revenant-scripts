--- @revenant-script
--- name: spellwindows
--- version: 1.9.0
--- author: Nisugi
--- game: gs
--- description: Spell/buff/debuff/cooldown window manager for Wrayth frontend
--- tags: hunting,combat,tracking,spells,buffs,debuffs,cooldowns
---
--- Changelog (from Lich5):
---   v1.9 (2025-08-23): Multi-boxing optimizations, target window ordering, timer speed
---   v1.8 (2025-04-08): Room/inventory feed defaults, Spellsong duration
---   v1.7 (2025-04-06): Group.check fix, bard song progress bar fix
---   v1.6 (2025-03-18): Room window and inventory feed blocking
---   v1.5 (2025-03-13): adderall/removeall commands, Indef display fix
---
--- Usage:
---   ;spellwindows              - Start the script
---   ;spellwindows help         - Show all commands
---   ;spellwindows settings     - Show current settings
---   ;spellwindows add <spell>  - Add spell to missing tracker
---   ;spellwindows remove <sp>  - Remove spell from tracker
---   ;spellwindows targets      - Toggle target window
---   ;spellwindows combat       - Toggle combat window feed
---
--- NOTE: Requires Wrayth frontend for dialog windows.

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SETTINGS_FILE = "data/spellwindows.json"

local function default_settings()
    return {
        show_spells     = true,
        show_buffs      = true,
        show_debuffs    = true,
        show_cooldowns  = true,
        block_combat    = true,
        block_room      = false,
        block_inventory = false,
        block_betrayer  = false,
        block_bank      = false,
        show_missing    = false,
        show_targets    = false,
        show_players    = true,
        show_group      = true,
        show_arms       = false,
        debug           = false,
        my_buffs        = {},
        target_order    = { "players", "targets", "group" },
        update_interval = 0.25,
    }
end

local settings

local function load_settings()
    if File.exists(SETTINGS_FILE) then
        local ok, data = pcall(function() return Json.decode(File.read(SETTINGS_FILE)) end)
        if ok and type(data) == "table" then
            -- Merge with defaults for any missing keys
            local defaults = default_settings()
            for k, v in pairs(defaults) do
                if data[k] == nil then data[k] = v end
            end
            settings = data
            return
        end
    end
    settings = default_settings()
end

local function save_settings()
    File.write(SETTINGS_FILE, Json.encode(settings))
end

load_settings()

--------------------------------------------------------------------------------
-- Hook setup for blocking frontend XML feeds
--------------------------------------------------------------------------------

local HOOK_NAME = "spellwindows_downstream"
local UPSTREAM_HOOK = "spellwindows_upstream"

local blackout = false

local SWMIN_PATTERNS = Regex.new(
    "^<dialogData id='Active Spells'" ..
    "|^<dialogData id='Buffs'" ..
    "|^<dialogData id='Debuffs'" ..
    "|^<dialogData id='Cooldowns'" ..
    "|^<openDialog id=[^%s]+ location=['\"]quickBar" ..
    "|^<switchQuickBar" ..
    "|^<dialogData id=\"quick\">" ..
    "|^<dialogData id='mapViewMain'"
)

local COMBAT_RE = Regex.new("^<dialogData id='combat'>")
local ROOM_RE = Regex.new(
    "^<nav rm=" ..
    "|^<component id='room " ..
    "|^<compDef id='room " ..
    "|^<compDef id='sprite'>"
)
local INVENTORY_RE = Regex.new("^<streamWindow id='inv|^<clearStream id='inv")
local END_INVENTORY_RE = Regex.new("^You are wearing|^<popStream/>")
local BETRAYER_RE = Regex.new("^<dialogData id='BetrayerPanel'")
local BANK_RE = Regex.new("^<dialogData id='bank'>|^<openDialog type='dynamic' id='bank'")

DownstreamHook.add(HOOK_NAME, function(server_string)
    -- Inventory blackout
    if settings.block_inventory and INVENTORY_RE:test(server_string) then
        blackout = true
        return nil
    end
    if END_INVENTORY_RE:test(server_string) then
        blackout = false
        return server_string
    end
    if blackout then return nil end

    if SWMIN_PATTERNS:test(server_string) then return nil end
    if settings.block_combat and COMBAT_RE:test(server_string) then return nil end
    if settings.block_room and ROOM_RE:test(server_string) then return nil end
    if settings.block_betrayer and BETRAYER_RE:test(server_string) then return nil end
    if settings.block_bank and BANK_RE:test(server_string) then return nil end

    return server_string
end)

--------------------------------------------------------------------------------
-- Command queue via upstream hook
--------------------------------------------------------------------------------

local cmd_queue = {}

local CMD_RE = Regex.new("^(?:<c>)?;(?:spellwindows?|buff)(?: (.*))?$")

UpstreamHook.add(UPSTREAM_HOOK, function(command)
    local m = CMD_RE:match(command)
    if m then
        table.insert(cmd_queue, m[1] or "")
        return nil
    end
    return command
end)

before_dying(function()
    UpstreamHook.remove(UPSTREAM_HOOK)
    DownstreamHook.remove(HOOK_NAME)
    save_settings()
end)

--------------------------------------------------------------------------------
-- Display time formatting
--------------------------------------------------------------------------------

local function format_time(timeleft_minutes)
    local seconds = timeleft_minutes * 60
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function display_time(timeleft_minutes)
    if timeleft_minutes > 300 then return "Indef" end
    local seconds = timeleft_minutes * 60
    if seconds < 120 then
        return tostring(math.floor(seconds)) .. "s"
    else
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%d:%02d", h, m)
    end
end

--------------------------------------------------------------------------------
-- Spell window building
--------------------------------------------------------------------------------

local function build_output(effect_type_name, title)
    local effects = Effects[effect_type_name]
    if not effects then return "" end
    local h = effects:to_hash()
    if not h or not next(h) then
        return "<dialogData id='" .. title .. "' clear='t'></dialogData>" ..
            "<dialogData id='" .. title .. "'>" ..
            "<label id='lblNone' value='No " .. string.lower(title) .. " found.' top='0' left='0' align='center'/>" ..
            "</dialogData>"
    end

    local output = "<dialogData id='" .. title .. "' clear='t'></dialogData><dialogData id='" .. title .. "'>"
    local top = 0

    for spell_num, end_time in pairs(h) do
        if type(spell_num) == "number" then
            local duration = (end_time - os.time()) / 60
            if duration > 0 then
                local spell_name = Spell[spell_num] and Spell[spell_num].name or tostring(spell_num)
                local max_dur = Spell[spell_num] and Spell[spell_num].max_duration or 5
                if max_dur == 0 then max_dur = 5 end
                local bar_val = math.min(100, math.floor((duration / max_dur) * 100))

                output = output .. string.format(
                    "<progressBar id='%d' value='%d' text=\"%s\" left='22%%' top='%d' width='76%%' height='15' time='%s'/>" ..
                    "<label id='l%d' value='%s ' top='%d' left='0' justify='2' anchor_right='spell'/>",
                    spell_num, bar_val, spell_name, top, format_time(duration),
                    spell_num, display_time(duration), top
                )
                top = top + 16
            end
        end
    end

    output = output .. "</dialogData>"
    return output
end

--------------------------------------------------------------------------------
-- Missing spells window
--------------------------------------------------------------------------------

local function build_missing_spells()
    local active_names = {}
    for _, s in ipairs(Spell.active()) do
        active_names[s.name] = true
    end

    local missing = {}
    for _, name in ipairs(settings.my_buffs) do
        if not active_names[name] then
            table.insert(missing, name)
        end
    end

    local output = "<dialogData id='Missing Spells' clear='t'></dialogData><dialogData id='Missing Spells'>"
    if #missing > 0 then
        table.sort(missing)
        for _, s in ipairs(missing) do
            local spell = Spell[s]
            local num = spell and spell.num or 0
            output = output .. "<label id='" .. num .. "' value='" .. s ..
                "' justify='3' left='0' height='1' width='187'/>"
        end
    else
        output = output .. "<label id='lblNone' value='No missing spells.' top='0' left='0' align='center'/>"
    end
    output = output .. "</dialogData>"
    return output
end

--------------------------------------------------------------------------------
-- Target window
--------------------------------------------------------------------------------

local function build_target_window()
    local targets = GameObj.targets and GameObj.targets() or {}
    local group_members = Group and Group.members and Group.members() or {}
    local non_group = Group and Group.nonmembers and Group.nonmembers() or {}

    local output = "<dialogData id='Target Window' clear='t'></dialogData><dialogData id='Target Window'>"

    local order = settings.target_order or { "players", "targets", "group" }
    local sections = {}

    for _, section in ipairs(order) do
        local content = ""
        if section == "players" and settings.show_players then
            if #non_group > 0 then
                content = "<label id='pcs' value='Total Players: " .. #non_group ..
                    "' justify='3' left='0' align='center' height='15' width='187'/>"
                for _, pc in ipairs(non_group) do
                    local name = pc.name or "Unknown"
                    content = content .. "<link id='" .. pc.id .. "' value='" .. name ..
                        "' cmd='target #" .. pc.id .. "' echo='target #" .. pc.id ..
                        "' justify='3' left='0' align='center' height='15' width='187'/>"
                end
            else
                content = "<label id='noPcs' value='-= No Players =-' justify='3' left='0' align='center' width='187'/>"
            end
        elseif section == "targets" then
            if #targets > 0 then
                content = "<link id='total' value='Total Targets: " .. #targets ..
                    "' cmd='target next' echo='target next' justify='3' left='0' align='center' height='15' width='187'/>"
                for _, t in ipairs(targets) do
                    local name = t.name or "Unknown"
                    content = content .. "<link id='" .. t.id .. "' value='" .. name ..
                        "' cmd='target #" .. t.id .. "' echo='target #" .. t.id ..
                        "' justify='3' left='0' align='center' height='15' width='187'/>"
                end
            else
                content = "<label id='noTargets' value='-= No Targets =-' justify='3' left='0' align='center' width='187'/>"
            end
        elseif section == "group" and settings.show_group then
            if #group_members > 0 then
                content = "<label id='group' value='Group Size: " .. #group_members ..
                    "' justify='3' left='0' align='center' height='15' width='187'/>"
                for _, gm in ipairs(group_members) do
                    content = content .. "<link id='" .. gm.id .. "' value='" .. (gm.name or "") ..
                        "' cmd='target #" .. gm.id .. "' echo='target #" .. gm.id ..
                        "' justify='3' left='0' align='center' height='15' width='187'/>"
                end
            else
                content = "<label id='noGroup' value='-= No Group =-' justify='3' align='center' width='187'/>"
            end
        end
        if content ~= "" then
            table.insert(sections, content)
        end
    end

    for i, sec in ipairs(sections) do
        output = output .. sec
        if i < #sections then
            output = output .. "<label id='space" .. i .. "' value='---------------------------' justify='3' left='0' align='center' width='187'/>"
        end
    end

    output = output .. "</dialogData>"
    return output
end

--------------------------------------------------------------------------------
-- Command handler
--------------------------------------------------------------------------------

local function handle_command(args_str)
    if not args_str or args_str == "" then return end

    local action, arg = string.match(args_str, "^(%S+)%s*(.*)")
    if not action then return end
    action = string.lower(action)

    if action == "help" then
        respond("SpellWindows Commands:")
        respond("  ;spellwindows              - Start the script")
        respond("  ;spellwindows spells       - Toggle Active Spells window")
        respond("  ;spellwindows buffs        - Toggle Buffs window")
        respond("  ;spellwindows debuffs      - Toggle Debuffs window")
        respond("  ;spellwindows cooldowns    - Toggle Cooldowns window")
        respond("  ;spellwindows missing      - Toggle Missing Spells window")
        respond("  ;spellwindows add <spell>  - Add spell to missing tracking")
        respond("  ;spellwindows remove <sp>  - Remove from missing tracking")
        respond("  ;spellwindows list         - List tracked spells")
        respond("  ;spellwindows targets      - Toggle target window")
        respond("  ;spellwindows combat       - Toggle combat window feed")
        respond("  ;spellwindows room         - Toggle room window feed")
        respond("  ;spellwindows inventory    - Toggle inventory window feed")
        respond("  ;spellwindows settings     - Show current settings")
    elseif action == "settings" then
        respond(" Current Settings:")
        respond("     Spells: " .. tostring(settings.show_spells))
        respond("      Buffs: " .. tostring(settings.show_buffs))
        respond("    Debuffs: " .. tostring(settings.show_debuffs))
        respond("  Cooldowns: " .. tostring(settings.show_cooldowns))
        respond("    Missing: " .. tostring(settings.show_missing))
        respond("     Combat: " .. tostring(not settings.block_combat))
        respond("       Room: " .. tostring(not settings.block_room))
        respond("  Inventory: " .. tostring(not settings.block_inventory))
        respond("    Targets: " .. tostring(settings.show_targets))
        respond("    Players: " .. tostring(settings.show_players))
        respond("      Group: " .. tostring(settings.show_group))
        respond("      Speed: " .. tostring(settings.update_interval) .. " seconds")
    elseif action == "add" then
        local spell = Spell[arg]
        if spell and spell.num then
            local name = spell.name
            -- Check not already in list
            for _, b in ipairs(settings.my_buffs) do
                if b == name then
                    respond(name .. " is already tracked.")
                    return
                end
            end
            table.insert(settings.my_buffs, name)
            respond(name .. " added.")
            save_settings()
        else
            respond(tostring(arg) .. " is not a valid spell.")
        end
    elseif action == "adderall" then
        for _, s in ipairs(Spell.active()) do
            local found = false
            for _, b in ipairs(settings.my_buffs) do
                if b == s.name then found = true; break end
            end
            if not found then table.insert(settings.my_buffs, s.name) end
        end
        respond("Added all active spells to tracking.")
        save_settings()
    elseif action == "removeall" then
        settings.my_buffs = {}
        respond("All spells removed from watch list.")
        save_settings()
    elseif string.match(action, "^rem") then
        local spell = Spell[arg]
        if spell and spell.name then
            local new = {}
            for _, b in ipairs(settings.my_buffs) do
                if b ~= spell.name then table.insert(new, b) end
            end
            settings.my_buffs = new
            respond(spell.name .. " removed.")
            save_settings()
        else
            respond(tostring(arg) .. " is not a valid spell.")
        end
    elseif action == "list" then
        if #settings.my_buffs == 0 then
            respond("No spells monitored.")
        else
            respond(" Monitoring:")
            for _, b in ipairs(settings.my_buffs) do
                local s = Spell[b]
                respond(string.format("  %5s %s", s and s.num or "?", b))
            end
        end
    elseif action == "spells" then
        settings.show_spells = not settings.show_spells
        respond(settings.show_spells and "Active Spells window enabled" or "Active Spells window disabled")
        save_settings()
    elseif action == "buffs" then
        settings.show_buffs = not settings.show_buffs
        respond(settings.show_buffs and "Buffs window enabled" or "Buffs window disabled")
        save_settings()
    elseif action == "debuffs" then
        settings.show_debuffs = not settings.show_debuffs
        respond(settings.show_debuffs and "Debuffs window enabled" or "Debuffs window disabled")
        save_settings()
    elseif action == "cooldowns" then
        settings.show_cooldowns = not settings.show_cooldowns
        respond(settings.show_cooldowns and "Cooldowns window enabled" or "Cooldowns window disabled")
        save_settings()
    elseif action == "missing" then
        settings.show_missing = not settings.show_missing
        respond(settings.show_missing and "Missing spells window enabled" or "Missing spells window disabled")
        save_settings()
    elseif action == "combat" then
        settings.block_combat = not settings.block_combat
        respond(settings.block_combat and "Combat window feed disabled" or "Combat window feed enabled")
        save_settings()
    elseif action == "room" then
        settings.block_room = not settings.block_room
        respond(settings.block_room and "Room window disabled" or "Room window enabled")
        save_settings()
    elseif action == "inventory" then
        settings.block_inventory = not settings.block_inventory
        respond(settings.block_inventory and "Inventory window disabled" or "Inventory window enabled")
        save_settings()
    elseif action == "targets" then
        settings.show_targets = not settings.show_targets
        respond(settings.show_targets and "Targets window enabled" or "Targets window disabled")
        save_settings()
    elseif action == "players" then
        settings.show_players = not settings.show_players
        respond(settings.show_players and "Players display enabled" or "Players display disabled")
        save_settings()
    elseif action == "group" then
        settings.show_group = not settings.show_group
        respond(settings.show_group and "Group display enabled" or "Group display disabled")
        save_settings()
    elseif action == "speed" then
        local spd = tonumber(arg)
        if spd and spd >= 0.1 and spd <= 1.0 then
            settings.update_interval = spd
            respond("Timer update interval set to: " .. tostring(spd) .. " seconds")
            save_settings()
        else
            respond("Invalid speed. Use 0.1-1.0. Current: " .. tostring(settings.update_interval))
        end
    elseif action == "debug" then
        settings.debug = not settings.debug
        respond(settings.debug and "Debug enabled" or "Debug disabled")
        save_settings()
    end
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

local function update_loop()
    local old_target_output = ""

    while true do
        -- Process commands
        while #cmd_queue > 0 do
            local cmd = table.remove(cmd_queue, 1)
            handle_command(cmd)
        end

        local output = ""

        -- Target window
        if settings.show_targets and not Script.running("go2") then
            local new_target = build_target_window()
            if new_target ~= old_target_output then
                output = output .. new_target
                old_target_output = new_target
            end
        end

        -- Spell windows (timer-based updates)
        if settings.show_spells then
            output = output .. build_output("Spells", "Active Spells")
        end
        if settings.show_buffs then
            output = output .. build_output("Buffs", "Buffs")
        end
        if settings.show_debuffs then
            output = output .. build_output("Debuffs", "Debuffs")
        end
        if settings.show_cooldowns then
            output = output .. build_output("Cooldowns", "Cooldowns")
        end
        if settings.show_missing then
            output = output .. build_missing_spells()
        end

        if #output > 0 then
            puts(output)
        end

        pause(settings.update_interval or 0.25)
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Open dialog windows if enabled
if settings.show_missing then
    puts("<closeDialog id='Missing Spells'/><openDialog type='dynamic' id='Missing Spells' title='Missing Spells' target='Missing Spells' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Missing Spells'></dialogData></openDialog>")
end
if settings.show_targets then
    puts("<closeDialog id='Target Window'/><openDialog type='dynamic' id='Target Window' title='Targets' target='Target Window' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Targets'></dialogData></openDialog>")
end

-- Process initial command if given
local initial_cmd = Script.vars[0] or ""
if initial_cmd ~= "" then
    handle_command(initial_cmd)
end

echo("SpellWindows v1.9 started.")
update_loop()
