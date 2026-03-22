--- @revenant-script
--- name: spellwindows
--- version: 1.9.0
--- author: Nisugi
--- game: gs
--- description: Spell/buff/debuff/cooldown window manager for Wrayth frontend
--- tags: hunting,combat,tracking,spells,buffs,debuffs,cooldowns
--- @lic-certified: complete 2026-03-20
---
--- Changelog (from Lich5):
---   v1.9 (2025-08-23): Multi-boxing optimizations, target window ordering, timer speed
---   v1.8 (2025-04-08): Room/inventory feed defaults, Spellsong duration
---   v1.7 (2025-04-06): Group.check fix, bard song progress bar fix
---   v1.6 (2025-03-18): Room window and inventory feed blocking
---   v1.5 (2025-03-13): adderall/removeall commands, Indef display fix
---
--- Revenant port notes:
---   - puts() → _respond() for raw XML injection (puts not defined in Revenant)
---   - Effects:to_h() keys are strings (spell names), values are seconds_remaining
---   - CMD_RE:captures() used instead of :match() for group extraction
---   - Group.members is a plain table of names; nonmembers derived from GameObj.pcs()
---   - Spellsong.duration() available via lib/gs/spellsong.lua (returns seconds)
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

local HOOK_NAME    = "spellwindows_downstream"
local UPSTREAM_HOOK = "spellwindows_upstream"

local blackout = false

local SWMIN_PATTERNS = Regex.new(
    "^<dialogData id='Active Spells'" ..
    "|^<dialogData id='Buffs'" ..
    "|^<dialogData id='Debuffs'" ..
    "|^<dialogData id='Cooldowns'" ..
    "|^<openDialog id=[^\\s]+ location=['\"]quickBar" ..
    "|^<switchQuickBar" ..
    "|^<dialogData id=\"quick\">" ..
    "|^<dialogData id='mapViewMain'"
)

local COMBAT_RE    = Regex.new("^<dialogData id='combat'>")
local ROOM_RE      = Regex.new(
    "^<nav rm=" ..
    "|^<component id='room desc'>" ..
    "|^<component id='room players'>" ..
    "|^<component id='room objs'>" ..
    "|^<component id='room exits'>" ..
    "|^<compDef id='room desc'>" ..
    "|^<compDef id='room objs'>" ..
    "|^<compDef id='room players'>" ..
    "|^<compDef id='room exits'>" ..
    "|^<compDef id='sprite'>"
)
local INVENTORY_RE     = Regex.new("^<streamWindow id='inv|^<clearStream id='inv")
local END_INVENTORY_RE = Regex.new("^You are wearing|^<popStream/>")
local BETRAYER_RE      = Regex.new("^<dialogData id='BetrayerPanel'")
local BANK_RE          = Regex.new("^<dialogData id='bank'>|^<openDialog type='dynamic' id='bank'")
-- Grasp of the Grave arm/appendage nouns to filter from target window
local GRASP_ARMS_RE    = Regex.new("(?:arm|appendage|claw|limb|pincer|tentacle|palpus|palpi)s?")

DownstreamHook.add(HOOK_NAME, function(server_string)
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
    if settings.block_combat   and COMBAT_RE:test(server_string)   then return nil end
    if settings.block_room     and ROOM_RE:test(server_string)     then return nil end
    if settings.block_betrayer and BETRAYER_RE:test(server_string) then return nil end
    if settings.block_bank     and BANK_RE:test(server_string)     then return nil end

    return server_string
end)

--------------------------------------------------------------------------------
-- Command queue via upstream hook
--------------------------------------------------------------------------------

local cmd_queue = {}

local CMD_RE = Regex.new("^(?:<c>)?;(?:spellwindows?|buff)(?: (.*))?$")

UpstreamHook.add(UPSTREAM_HOOK, function(command)
    local m = CMD_RE:captures(command)
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
-- Spell max duration lookup (mirrors Lich5 get_spell_max_duration)
--------------------------------------------------------------------------------

local CUSTOM_DURATIONS = {
    ["Celerity"]                    = 1,
    ["Barkskin"]                    = 1,
    ["Assume Aspect"]               = 10,
    ["Nature's Touch Arcane Ref"]   = 0.5,
    ["Nature's Touch Physical P"]   = 0.5,
    ["Tangleweed Vigor"]            = 2,
    ["Slashing Strikes"]            = 2,
    ["Evasiveness"]                 = 0.05,
    ["Wall of Force"]               = 1.5,
}

local function get_spell_max_duration(name)
    -- Armor spells have indefinite durations: treat as 250 min
    if name:match("^Armor") then return 250 end
    -- Bard spellsong durations are character-level dependent
    if name:match("^Song of") then
        return Spellsong and Spellsong.duration() / 60 or 5
    end
    -- Script-specific custom overrides
    if CUSTOM_DURATIONS[name] then return CUSTOM_DURATIONS[name] end
    -- Fall back to spell definition, then 5 min
    local spell = Spell[name]
    local max_dur = spell and spell.max_duration or 5
    return (max_dur == 0) and 5 or max_dur
end

--------------------------------------------------------------------------------
-- Spell window building
--------------------------------------------------------------------------------

-- Stable numeric ID for a progress bar: uses spell number if known,
-- otherwise a polynomial hash (unique enough within a single dialog).
local function effect_id(name)
    local spell = Spell[name]
    if spell and spell.num then return spell.num end
    local h = 0
    for i = 1, #name do
        h = (h * 31 + string.byte(name, i)) % 99991
    end
    return h
end

local function build_output(effect_type_name, title)
    local effects = Effects[effect_type_name]
    if not effects then return "" end
    -- to_h() returns { name_string = seconds_remaining }
    local h = effects:to_h()
    if not h or not next(h) then
        return "<dialogData id='" .. title .. "' clear='t'></dialogData>" ..
            "<dialogData id='" .. title .. "'>" ..
            "<label id='lblNone' value='No " .. string.lower(title) .. " found.' top='0' left='0' align='center'/>" ..
            "</dialogData>"
    end

    -- Collect and sort by time remaining descending for stable display
    local entries = {}
    for name, secs in pairs(h) do
        table.insert(entries, { name = name, secs = secs })
    end
    table.sort(entries, function(a, b) return a.secs > b.secs end)

    local output = "<dialogData id='" .. title .. "' clear='t'></dialogData><dialogData id='" .. title .. "'>"
    local top = 0

    for _, entry in ipairs(entries) do
        local name     = entry.name
        local duration = entry.secs / 60  -- seconds_remaining → minutes
        if duration > 0 then
            local bar_id  = effect_id(name)
            local max_dur = get_spell_max_duration(name)
            local bar_val = math.min(100, math.floor((duration / max_dur) * 100))

            output = output .. string.format(
                "<progressBar id='%d' value='%d' text=\"%s\" left='22%%' top='%d' width='76%%' height='15' time='%s'/>" ..
                "<label id='l%d' value='%s ' top='%d' left='0' justify='2' anchor_right='spell'/>",
                bar_id, bar_val, name, top, format_time(duration),
                bar_id, display_time(duration), top
            )
            top = top + 16
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
-- Target window helpers
--------------------------------------------------------------------------------

-- Compact status label for display alongside target name.
local STATUS_MAP = {
    { Regex.new("rather calm"),           "calmed"   },
    { Regex.new("to be frozen in place"), "frozen"   },
    { Regex.new("held in place"),         "held"     },
    { Regex.new("lying down"),            "prone"    },
    { Regex.new("entangled by"),          "entangled"},
}

local function status_fix(status)
    if not status then return nil end
    for _, pair in ipairs(STATUS_MAP) do
        if pair[1]:test(status) then return "(" .. pair[2] .. ")" end
    end
    return "(" .. status .. ")"
end

-- Build link XML for a list of GameObj entities.
-- strip_title=true drops all but the last word of the name (removes NPC/player titles).
local function build_target_links(entities, strip_title)
    local result = ""
    for _, entity in ipairs(entities) do
        local raw_name = entity.name or "Unknown"
        local name
        if strip_title then
            -- Last word only, capitalised (strips honorifics/titles)
            name = raw_name:match("(%S+)%s*$") or raw_name
            name = name:sub(1,1):upper() .. name:sub(2)
        else
            -- Capitalise each word
            name = raw_name:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b end)
        end
        local status_str = status_fix(entity.status)
        local display = status_str and (status_str .. " " .. name) or name
        result = result ..
            "<link id='" .. entity.id .. "' value='" .. display ..
            "' cmd='target #" .. entity.id ..
            "' echo='target #" .. entity.id ..
            "' justify='3' left='0' align='center' height='15' width='187'/>"
    end
    return result
end

local function build_target_window()
    -- Filter targets: exclude Grasp of the Grave arms and certain animated objects
    local raw_targets = GameObj.targets() or {}
    local targets = {}
    for _, t in ipairs(raw_targets) do
        local is_arm = t.noun and GRASP_ARMS_RE:test(t.noun)
        local is_animated = t.name and t.name:match("^animated ") and t.name ~= "animated slush"
        if not is_arm and not is_animated then
            table.insert(targets, t)
        end
    end

    -- Group.members is a plain table of name strings (populated by lib/group.lua).
    -- Separate all room PCs into group members vs non-group using GameObj.pcs().
    local member_names = Group and Group.members or {}
    local in_group = {}
    for _, mname in ipairs(member_names) do
        in_group[mname] = true
    end

    local all_pcs = GameObj.pcs() or {}
    local group_members = {}
    local non_group = {}
    for _, pc in ipairs(all_pcs) do
        if in_group[pc.name] then
            table.insert(group_members, pc)
        else
            table.insert(non_group, pc)
        end
    end

    local output = "<dialogData id='Target Window' clear='t'></dialogData><dialogData id='Target Window'>"
    local order = settings.target_order or { "players", "targets", "group" }
    local sections = {}

    for _, section in ipairs(order) do
        local content = ""
        if section == "players" and settings.show_players then
            if #non_group > 0 then
                content = "<label id='pcs' value='Total Players: " .. #non_group ..
                    "' justify='3' left='0' align='center' height='15' width='187'/>"
                content = content .. build_target_links(non_group, true)
            else
                content = "<label id='noPcs' value='-= No Players =-' justify='3' left='0' align='center' width='187'/>"
            end
        elseif section == "targets" then
            if #targets > 0 then
                content = "<link id='total' value='Total Targets: " .. #targets ..
                    "' cmd='target next' echo='target next' justify='3' left='0' align='center' height='15' width='187'/>"
                content = content .. build_target_links(targets, false)
            else
                content = "<label id='noTargets' value='-= No Targets =-' justify='3' left='0' align='center' width='187'/>"
            end
        elseif section == "group" and settings.show_group then
            if #group_members > 0 then
                content = "<label id='group' value='Group Size: " .. #group_members ..
                    "' justify='3' left='0' align='center' height='15' width='187'/>"
                content = content .. build_target_links(group_members, true)
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
            output = output .. "<label id='space" .. i ..
                "' value='---------------------------' justify='3' left='0' align='center' width='187'/>"
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
    if arg == "" then arg = nil end

    if action == "help" then
        _respond('<output class="mono"/>')
        local cmds = {
            { "",                  "Start the script." },
            { "spells",            "Toggle the Active Spells window." },
            { "buffs",             "Toggle the Buffs window." },
            { "debuffs",           "Toggle the Debuffs window." },
            { "cooldowns",         "Toggle the Cooldowns window." },
            { "missing",           "Toggle the Missing Spells window." },
            { "add <spell>",       "Add to missing spells tracking. Accepts spell number or name." },
            { "remove <spell>",    "Remove from missing spells tracking. Accepts spell number or name." },
            { "list",              "List spells you are currently tracking." },
            { "quickload",         "Adds all currently self-known worn spells to the list." },
            { "adderall",          "Adds all currently worn spells to the list." },
            { "removeall",         "Removes all spells from tracking." },
            { "combat",            "Toggle combat window feed." },
            { "room",              "Toggle room window feed." },
            { "inventory",         "Toggle inventory window feed." },
            { "betrayer",          "Toggle betrayer panel feed." },
            { "bank",              "Toggle bank dialog feed." },
            { "targets",           "Toggle targets window." },
            { "players",           "Toggle players display in target window." },
            { "group",             "Toggle group members display in target window." },
            { "arms",              "Show Grasp of the Grave arm count in the target window." },
            { "order <layout>",    "Set target window order. Ex: \"targets players group\" or \"default\"" },
            { "speed <value>",     "Set timer update speed (0.1-1.0 sec)." },
            { "settings",          "Lists current settings." },
            { "abort",             "Emergency: re-enable inventory stream if blackout stuck." },
        }
        for _, pair in ipairs(cmds) do
            local line = string.format("%8s %-18s %s", ";spellwindows", pair[1], pair[2])
            line = line:gsub("<", "&lt;"):gsub(">", "&gt;")
            respond(line)
        end
        _respond('<output class=""/>')

    elseif action == "settings" then
        _respond('<output class="mono"/>')
        respond(" Current Settings:")
        respond("     Spells: " .. tostring(settings.show_spells))
        respond("      Buffs: " .. tostring(settings.show_buffs))
        respond("    Debuffs: " .. tostring(settings.show_debuffs))
        respond("  Cooldowns: " .. tostring(settings.show_cooldowns))
        respond("    Missing: " .. tostring(settings.show_missing))
        respond("     Combat: " .. tostring(not settings.block_combat))
        respond("       Room: " .. tostring(not settings.block_room))
        respond("  Inventory: " .. tostring(not settings.block_inventory))
        respond("   Betrayer: " .. tostring(not settings.block_betrayer))
        respond("       Bank: " .. tostring(not settings.block_bank))
        respond("    Targets: " .. tostring(settings.show_targets))
        respond("    Players: " .. tostring(settings.show_players))
        respond("      Group: " .. tostring(settings.show_group))
        respond("  Arm Count: " .. tostring(settings.show_arms))
        local order_strs = {}
        for _, s in ipairs(settings.target_order or { "players", "targets", "group" }) do
            table.insert(order_strs, s:sub(1,1):upper() .. s:sub(2))
        end
        respond("      Order: " .. table.concat(order_strs, " -> "))
        respond("      Speed: " .. tostring(settings.update_interval) .. " seconds")
        _respond('<output class=""/>')

    elseif action == "add" then
        if not arg then
            respond("Usage: ;spellwindows add <spell name or number>")
            return
        end
        local spell = Spell[arg]
        if spell and spell.num then
            local name = spell.name
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

    elseif action == "quickload" then
        -- Add only self-known (worn by self) active spells
        for _, s in ipairs(Spell.active()) do
            if s.known then
                local found = false
                for _, b in ipairs(settings.my_buffs) do
                    if b == s.name then found = true; break end
                end
                if not found then table.insert(settings.my_buffs, s.name) end
            end
        end
        respond("Added all self-known active spells to tracking.")
        save_settings()

    elseif action == "removeall" then
        settings.my_buffs = {}
        respond("All spells removed from watch list.")
        save_settings()

    elseif action:match("^rem") then
        if not arg then
            respond("Usage: ;spellwindows remove <spell name or number>")
            return
        end
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
        _respond('<output class="mono"/>')
        if #settings.my_buffs == 0 then
            respond("No spells monitored.")
        else
            respond(" Monitoring:")
            for _, b in ipairs(settings.my_buffs) do
                local s = Spell[b]
                respond(string.format("  %5s %s", s and s.num or "?", b))
            end
        end
        _respond('<output class=""/>')

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
        if settings.show_missing then
            _respond("<closeDialog id='Missing Spells'/><openDialog type='dynamic' id='Missing Spells' title='Missing Spells' target='Missing Spells' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Missing Spells'></dialogData></openDialog>")
        else
            _respond("<closeDialog id='Missing Spells'/>")
        end
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

    elseif action == "betrayer" then
        settings.block_betrayer = not settings.block_betrayer
        respond(settings.block_betrayer and "Betrayer panel disabled" or "Betrayer panel enabled")
        save_settings()

    elseif action == "bank" then
        settings.block_bank = not settings.block_bank
        respond(settings.block_bank and "Bank dialog disabled" or "Bank dialog enabled")
        save_settings()

    elseif action == "targets" then
        settings.show_targets = not settings.show_targets
        respond(settings.show_targets and "Targets window enabled" or "Targets window disabled")
        if settings.show_targets then
            _respond("<closeDialog id='Target Window'/><openDialog type='dynamic' id='Target Window' title='Target Window' target='Target Window' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Target Window'></dialogData></openDialog>")
        else
            _respond("<closeDialog id='Target Window'/>")
        end
        save_settings()

    elseif action == "players" then
        settings.show_players = not settings.show_players
        respond(settings.show_players and "Players display enabled" or "Players display disabled")
        save_settings()

    elseif action == "group" then
        settings.show_group = not settings.show_group
        respond(settings.show_group and "Group display enabled" or "Group display disabled")
        save_settings()

    elseif action == "arms" then
        settings.show_arms = not settings.show_arms
        respond(settings.show_arms and "Grasp of the Grave arms will display in target window" or "Grasp of the Grave arms will not display in target window")
        save_settings()

    elseif action == "order" then
        if not arg or arg == "default" then
            if arg == "default" then
                settings.target_order = { "players", "targets", "group" }
                respond("Target window order set to: Players -> Targets -> Group")
                save_settings()
            else
                local order_strs = {}
                for _, s in ipairs(settings.target_order or { "players", "targets", "group" }) do
                    table.insert(order_strs, s:sub(1,1):upper() .. s:sub(2))
                end
                respond("Current order: " .. table.concat(order_strs, " -> "))
                respond("To change: ;spellwindows order <targets players group>")
            end
        else
            local valid = { targets = true, players = true, group = true }
            local parts = {}
            for word in arg:lower():gmatch("%S+") do
                table.insert(parts, word)
            end
            if #parts == 3 then
                local ok = true
                local seen = {}
                for _, p in ipairs(parts) do
                    if not valid[p] or seen[p] then ok = false; break end
                    seen[p] = true
                end
                if ok then
                    settings.target_order = parts
                    local order_strs = {}
                    for _, s in ipairs(parts) do
                        table.insert(order_strs, s:sub(1,1):upper() .. s:sub(2))
                    end
                    respond("Target window order set to: " .. table.concat(order_strs, " -> "))
                    save_settings()
                    return
                end
            end
            respond("Invalid order. Please specify all three sections: players, targets, group")
            respond("Example: ;spellwindows order targets players group")
        end

    elseif action == "speed" then
        local spd = tonumber(arg)
        if spd and spd >= 0.1 and spd <= 1.0 then
            settings.update_interval = spd
            respond("Timer update interval set to: " .. tostring(spd) .. " seconds")
            respond("Note: This only affects countdown timers. Spell changes and targets update immediately.")
            save_settings()
        else
            respond("Invalid speed. Use 0.1-1.0. Current: " .. tostring(settings.update_interval))
        end

    elseif action == "debug" then
        settings.debug = not settings.debug
        respond(settings.debug and "Debug enabled" or "Debug disabled")
        save_settings()

    elseif action == "abort" then
        -- Emergency: clears blackout state if inventory stream got stuck
        blackout = false
        settings.block_inventory = false
        respond("Inventory stream re-enabled.")
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

        -- Target window: update immediately on any change; skip during go2
        if settings.show_targets and not Script.running("go2") then
            local new_target = build_target_window()
            if new_target ~= old_target_output then
                output = output .. new_target
                old_target_output = new_target
            end
        end

        -- Spell windows (always rebuild on each tick; timers count down)
        if settings.show_spells    then output = output .. build_output("Spells",    "Active Spells") end
        if settings.show_buffs     then output = output .. build_output("Buffs",     "Buffs")         end
        if settings.show_debuffs   then output = output .. build_output("Debuffs",   "Debuffs")       end
        if settings.show_cooldowns then output = output .. build_output("Cooldowns", "Cooldowns")     end
        if settings.show_missing   then output = output .. build_missing_spells()                     end

        if #output > 0 then
            _respond(output)
            if settings.debug then respond("[spellwindows debug] sent " .. #output .. " bytes") end
        end

        pause(settings.update_interval or 0.25)
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Open dialog windows if enabled at startup
if settings.show_missing then
    _respond("<closeDialog id='Missing Spells'/><openDialog type='dynamic' id='Missing Spells' title='Missing Spells' target='Missing Spells' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Missing Spells'></dialogData></openDialog>")
end
if settings.show_targets then
    _respond("<closeDialog id='Target Window'/><openDialog type='dynamic' id='Target Window' title='Target Window' target='Target Window' scroll='manual' location='main' justify='3' height='68' resident='true'><dialogData id='Target Window'></dialogData></openDialog>")
end

-- Process initial command argument if given
local initial_cmd = Script.vars[0] or ""
if initial_cmd ~= "" then
    handle_command(initial_cmd)
end

echo("SpellWindows v1.9 started.")
update_loop()
