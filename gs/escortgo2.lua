--- @revenant-script
--- name: escortgo2
--- version: 1.0.4
--- author: elanthia-online
--- game: gs
--- tags: bounty, escort
--- depends: lib/args, lib/spell_casting
--- @lic-certified: complete 2026-03-18
---
--- Changelog (from Lich5):
---   v1.0.4 (2025-05-06)
---     - update silver_check to use Lich::Util.silver_count
---   v1.0.3 (2025-04-03)
---     - correct Icemule dropoff from 2486 to 2412
---     - add additional debug info for not able to find next path location
---   v1.0.2 (2025-03-06)
---     - remove Zul ferry logic, no longer needed
---     - remove Zul rope ladder logic, no longer needed
---   v1.0.1 (2025-02-02)
---     - remove EN ferry logic, no longer needed
---     - update to use eherbs instead of useherbs
---   v1.0.0 (2025-01-05)
---     - initial fork of ego2
---     - remove Zul rope bridge pathing as no longer needed
---     - rubocop cleanup
---   Prior ego2 changelog:
---     v0.6 (2020-10-10) - fix commas in silver check
---     v0.5 (2015-04-07) - ignore disabled people's disabled bandits, pay attention to disks
---     v0.4 (2014-11-04) - fixed poaching issue where escort id wasn't being checked
---     v0.3 (2014-09-29) - reworked ambush detection to prevent false positives

local args_lib = require("lib/args")
require("lib/spell_casting")

-- ============================================================
-- Local helpers (functions not provided by Revenant engine)
-- ============================================================

--- dothistimeout: send a command, wait up to `timeout` seconds for a line
--- matching any of the given patterns. Returns the matching line or nil.
local function dothistimeout(cmd, timeout, ...)
    local patterns = {...}
    put(cmd)
    local deadline = os.time() + timeout
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            for _, pat in ipairs(patterns) do
                if string.find(line, pat) then
                    return line
                end
            end
        else
            pause(0.1)
        end
    end
    return nil
end

--- empty_hands: stow whatever is in both hands
local function empty_hands()
    if righthand_p() then fput("stow right") end
    if lefthand_p() then fput("stow left") end
end

--- fill_hands: not practical to track what was stowed; skip in Revenant
--- (original Lich5 tracks last-held items via global state we don't have)
local function fill_hands()
    -- no-op: Revenant doesn't track previously-held items
end

--- silver_count: check how much silver the character is carrying
local function silver_count()
    local line = dothistimeout("coins", 5, "silver")
    if not line then return 0 end
    local amount = line:match("(%d[%d,]*) silver")
    if not amount then return 0 end
    return tonumber((amount:gsub(",", ""))) or 0
end

--- format_time: format seconds into "Xm Ys" string
local function format_time(secs)
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    if m > 0 then
        return string.format("%dm %ds", m, s)
    end
    return string.format("%ds", s)
end

--- has_exit: check if a direction is in room exits
local function has_exit(dir)
    local exits = GameState.room_exits
    if type(exits) ~= "table" then return false end
    for _, e in ipairs(exits) do
        if e == dir then return true end
    end
    return false
end

--- max_wound: return max severity across wound body parts
local function max_wound()
    return math.max(
        Wounds.head or 0, Wounds.neck or 0,
        Wounds.chest or 0, Wounds.abdomen or 0, Wounds.back or 0,
        Wounds.left_arm or 0, Wounds.right_arm or 0,
        Wounds.left_hand or 0, Wounds.right_hand or 0,
        Wounds.left_leg or 0, Wounds.right_leg or 0,
        Wounds.left_foot or 0, Wounds.right_foot or 0,
        Wounds.nerves or 0
    )
end

--- max_scar: return max severity across scar body parts
local function max_scar()
    return math.max(
        Scars.head or 0, Scars.neck or 0,
        Scars.chest or 0, Scars.abdomen or 0, Scars.back or 0,
        Scars.left_arm or 0, Scars.right_arm or 0,
        Scars.left_hand or 0, Scars.right_hand or 0,
        Scars.left_leg or 0, Scars.right_leg or 0,
        Scars.left_foot or 0, Scars.right_foot or 0,
        Scars.nerves or 0
    )
end

--- find_nearest: from a list of room IDs, find the one closest to current room
local function find_nearest(target_list)
    local current = Map.current_room()
    if not current then return nil end
    for _, id in ipairs(target_list) do
        if id == current then return id end
    end
    local nearest_id = nil
    local shortest = nil
    for _, id in ipairs(target_list) do
        local p = Map.find_path(current, id)
        if p and (not shortest or #p < shortest) then
            nearest_id = id
            shortest = #p
        end
    end
    return nearest_id
end

-- ============================================================
-- Settings & CLI parsing
-- ============================================================

local fix_setting = {
    on = true, off = false,
    ["true"] = true, ["false"] = false,
    yes = true, no = false,
}

local parsed = args_lib.parse(Script.vars[0] or "")
local cmd = parsed.args[1]

-- "set" command: save a setting and exit
if cmd == "set" then
    local key = parsed.args[2]
    local val = parsed.args[3]
    if key == "attack-script" and val then
        if val:lower() == "none" then
            CharSettings["attack-script"] = nil
        else
            CharSettings["attack-script"] = val
        end
        echo("setting saved (attack-script = " .. (CharSettings["attack-script"] or "none") .. ")")
    elseif key == "poach" and val and fix_setting[val:lower()] ~= nil then
        CharSettings.poach = tostring(fix_setting[val:lower()])
        echo("setting saved (poach = " .. CharSettings.poach .. ")")
    elseif key == "hide" and val and fix_setting[val:lower()] ~= nil then
        CharSettings.hide = tostring(fix_setting[val:lower()])
        echo("setting saved (hide = " .. CharSettings.hide .. ")")
    elseif key == "haste" and val and fix_setting[val:lower()] ~= nil then
        CharSettings.haste = tostring(fix_setting[val:lower()])
        echo("setting saved (haste = " .. CharSettings.haste .. ")")
    elseif key == "useherbs" and val and fix_setting[val:lower()] ~= nil then
        CharSettings.useherbs = tostring(fix_setting[val:lower()])
        echo("setting saved (useherbs = " .. CharSettings.useherbs .. ")")
    else
        echo("You're doing it wrong.  (;" .. Script.name .. " help)")
    end
    return
end

-- "list" command: show saved options
if cmd == "list" then
    respond("")
    respond("   attack-script: " .. (CharSettings["attack-script"] or "none"))
    respond("           poach: " .. (CharSettings.poach or "false"))
    respond("           haste: " .. (CharSettings.haste or "false"))
    respond("            hide: " .. (CharSettings.hide or "false"))
    respond("        useherbs: " .. (CharSettings.useherbs or "false"))
    respond("")
    return
end

-- "help" or any unrecognized positional arg: show usage
if cmd and cmd ~= "" then
    respond("")
    respond("   ;" .. Script.name .. "                                   start an escort")
    respond("   ;" .. Script.name .. " list                              show saved options")
    respond("")
    respond("These commands will save an option and exit:")
    respond("")
    respond("   ;" .. Script.name .. " set attack-script <script name>   set attack script for bandits")
    respond("   ;" .. Script.name .. " set attack-script none            pause instead of attacking")
    respond("   ;" .. Script.name .. " set poach <yes/no>                attack even if other PCs present")
    respond("   ;" .. Script.name .. " set haste <yes/no>                cast haste before moving")
    respond("   ;" .. Script.name .. " set hide <yes/no>                 hide before moving")
    respond("   ;" .. Script.name .. " set useherbs <yes/no>             use ;eherbs when injured")
    respond("")
    respond("Runtime options (not saved):")
    respond("")
    respond("   ;" .. Script.name .. " --attack-script=<name>")
    respond("   ;" .. Script.name .. " --poach=<yes/no>")
    respond("   ;" .. Script.name .. " --travel-cost=<number>")
    respond("   ;" .. Script.name .. " --haste=<yes/no>")
    respond("   ;" .. Script.name .. " --hide=<yes/no>")
    respond("   ;" .. Script.name .. " --useherbs=<yes/no>")
    respond("")
    return
end

-- Load settings (CharSettings stores strings; convert to booleans)
local function bool_setting(key)
    local v = CharSettings[key]
    if v == "true" then return true end
    return false
end

local poach = bool_setting("poach")
local attack_script = CharSettings["attack-script"]
local do_hide = bool_setting("hide")
local do_haste = bool_setting("haste")
local useherbs = bool_setting("useherbs")

-- Override from CLI flags
if parsed.poach ~= nil then poach = fix_setting[tostring(parsed.poach):lower()] or poach end
if parsed.hide ~= nil then do_hide = fix_setting[tostring(parsed.hide):lower()] or do_hide end
if parsed.haste ~= nil then do_haste = fix_setting[tostring(parsed.haste):lower()] or do_haste end
if parsed.useherbs ~= nil then useherbs = fix_setting[tostring(parsed.useherbs):lower()] or useherbs end
if parsed.attack_script then
    if parsed.attack_script == "none" then
        attack_script = nil
    elseif parsed.attack_script ~= true then
        attack_script = parsed.attack_script
    end
end
local travel_cost = parsed.travel_cost and tonumber(parsed.travel_cost) or nil

-- ============================================================
-- Data tables
-- ============================================================

local justice = true
local justice_count = 0
local lost_escort = 0
local fell_off_rope = false
local sanct_count = -1
local wait_num = 45
local escort_id = nil
local destination_room = nil
local path = nil

-- Init targetable/untargetable tracking in CharSettings (JSON-encoded tables)
if not CharSettings.targetable then CharSettings.targetable = "[]" end
if not CharSettings.untargetable then CharSettings.untargetable = "[]" end
local targetable = Json.decode(CharSettings.targetable)
local untargetable = Json.decode(CharSettings.untargetable)

local no_hide_rooms = { [1156]=true, [1155]=true, [1154]=true, [1153]=true }
local no_haste_rooms = { [1191]=true }

local DISABLED_PATTERN = "dead|sleeping|calm|stunned|lying down|prone|sitting|frozen"
local ESCORT_NOUNS = { traveller=true, magistrate=true, merchant=true, scribe=true, dignitary=true, official=true }
local IGNORABLE_NPCS = { kobold=true, rolton=true, urgh=true, ["ridge orc"]=true, hobgoblin=true, velnalin=true, ["fire ant"]=true }

local function is_disabled(status)
    if not status then return false end
    for word in DISABLED_PATTERN:gmatch("[^|]+") do
        if status:find(word) then return true end
    end
    return false
end

local function is_escort(noun)
    return ESCORT_NOUNS[noun] or false
end

local function is_ignorable(name)
    return IGNORABLE_NPCS[name] or false
end

local escort_pickup = {
    ["area just inside the Sapphire Gate"]                   = { town = "Ta'Illistim",        room = 34 },
    ["area just inside the North Gate"]                      = { town = "Wehnimer's Landing",  room = 223 },
    ["south end of North Market"]                            = { town = "Solhaven",            room = 1472 },
    ["area just north of the South Gate, past the barbican"] = { town = "Icemule Trace",       room = 2412 },
    ["Kresh'ar Deep monument"]                               = { town = "Zul Logoth",          room = 1005 },
    ["area just inside the Amaranth Gate"]                   = { town = "Ta'Vaalor",           room = 3483 },
}

local escort_dropoff = {
    ["Wehnimer's Landing"] = { 223 },
    ["Icemule Trace"]      = { 2412 },
    ["Zul Logoth"]         = { 992, 1266 },
    ["Solhaven"]           = { 3902 },
    ["Ta'Vaalor"]          = { 5907 },
    ["Ta'Illistim"]        = { 37 },
}

local default_travel_cost = {
    ["Wehnimer's Landing"] = {
        ["Icemule Trace"] = 0, ["Zul Logoth"] = 20, ["Solhaven"] = 0,
        ["Ta'Vaalor"] = 4020, ["Ta'Illistim"] = 4020,
    },
    ["Icemule Trace"] = {
        ["Wehnimer's Landing"] = 0, ["Zul Logoth"] = 20, ["Solhaven"] = 0,
        ["Ta'Vaalor"] = 4020, ["Ta'Illistim"] = 4020,
    },
    ["Zul Logoth"] = {
        ["Wehnimer's Landing"] = 2020, ["Icemule Trace"] = 2020, ["Solhaven"] = 2020,
        ["Ta'Vaalor"] = 2000, ["Ta'Illistim"] = 2000,
    },
    ["Solhaven"] = {
        ["Wehnimer's Landing"] = 0, ["Icemule Trace"] = 0, ["Zul Logoth"] = 20,
        ["Ta'Vaalor"] = 4020, ["Ta'Illistim"] = 4020,
    },
    ["Ta'Vaalor"] = {
        ["Wehnimer's Landing"] = 4020, ["Icemule Trace"] = 4020, ["Zul Logoth"] = 2000,
        ["Solhaven"] = 4020, ["Ta'Illistim"] = 0,
    },
    ["Ta'Illistim"] = {
        ["Wehnimer's Landing"] = 4020, ["Icemule Trace"] = 4020, ["Zul Logoth"] = 2000,
        ["Solhaven"] = 4020, ["Ta'Vaalor"] = 0,
    },
}

-- ============================================================
-- Ambush detection (replaces Lich5 start_exec_script thread)
-- ============================================================

local my_ambush = false
local staggered_ambush = false

local AMBUSH_HOOK_NAME = "ego2_ambush_" .. (Script.name or "escortgo2")

DownstreamHook.add(AMBUSH_HOOK_NAME, function(line)
    -- Room change: reset ambush state
    if Regex.test([=[<pushStream id=['"]room['"]]=], line) then
        my_ambush = false
        staggered_ambush = false
    end
    -- Ambush triggers
    -- Staggered ambush NPCs arrive via <compass> element (e.g. "A bandit quickly approaches")
    local compass_ambush = line:find("<compass>")
        and Regex.test("quickly approaches|suddenly leaps from|leaps out of|suddenly jumps out of the shadows", line)
    if (escort_id and line:find(escort_id) and line:find("fearfully exclaims"))
       or compass_ambush
       or line:find("carefully concealed metal jaws")
       or line:find("nearly invisible length of razor wire")
       or line:find("length of nearly invisible razor wire")
       or line:find("carefully concealed inflated pouch")
       or line:find("carefully concealed looped rope")
       or line:find("a carefully concealed net")
       or line:find("carefully concealed pit")
       or line:find("the ground gives out from under you") then
        my_ambush = true
        if compass_ambush then
            staggered_ambush = true
        end
    end
    return line  -- pass through, don't squelch
end)

before_dying(function()
    DownstreamHook.remove(AMBUSH_HOOK_NAME)
end)

-- ============================================================
-- Core action functions
-- ============================================================

local function hide_me()
    if not do_hide then return end
    local room_id = Map.current_room()
    if hidden() or invisible() or (room_id and no_hide_rooms[room_id]) then return end
    waitrt()
    fput("hide")
    pause(0.5)
    waitrt()
end

local function haste_me()
    if not do_haste then return end
    -- Don't cast if hidden (would break hide)
    if hidden() then return end
    local spell = Spell[506]
    if not spell then return end
    local room_id = Map.current_room()
    if room_id and no_haste_rooms[room_id] then return end
    if not spell.active and spell.known and spell:affordable() then
        spell:cast()
    end
end

local function protect_me()
    -- Only useful if hiding is enabled
    if not do_hide then return end
    -- Don't cast if hidden (would break hide)
    if hidden() then return end
    local spell = Spell[919]
    if not spell then return end
    if spell.known and not spell.active and mana() > 150 then
        spell:cast()
    end
end

local function check_escort()
    if not escort_id then return false end
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.id == escort_id then return true end
    end
    return false
end

local function save_targetable()
    CharSettings.targetable = Json.encode(targetable)
    CharSettings.untargetable = Json.encode(untargetable)
end

local function check_room()
    while true do
        -- Learn targetability of unknown NPCs
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            local known = false
            for _, name in ipairs(targetable) do
                if name == npc.name then known = true; break end
            end
            if not known then
                for _, name in ipairs(untargetable) do
                    if name == npc.name then known = true; break end
                end
            end
            if not known then
                local result = dothistimeout("target #" .. npc.id, 10,
                    "You are now targeting", "You can't target", "Usage:  TARGET")
                if result and result:find("You are now targeting") then
                    table.insert(targetable, npc.name)
                    save_targetable()
                elseif result and result:find("You can't target") then
                    table.insert(untargetable, npc.name)
                    save_targetable()
                end
            end
        end

        -- Gather targetable, non-escort, non-ignorable, non-disabled, non-dead NPCs
        npcs = GameObj.npcs()
        local hostile = {}
        for _, npc in ipairs(npcs) do
            local is_target = false
            for _, name in ipairs(targetable) do
                if name == npc.name then is_target = true; break end
            end
            if is_target
               and not is_ignorable(npc.name)
               and not is_escort(npc.noun)
               and npc.status ~= "dead"
               and ((my_ambush and npc.type and npc.type:find("bandit")) or not is_disabled(npc.status)) then
                table.insert(hostile, npc)
            end
        end

        -- Collect PCs with nil or hidden status (innocuous bystanders)
        -- Original: pcs = all_pcs.find_all { |pc| pc.status.nil? or pc.status =~ /hiding|hidden/ }
        -- If this list is empty, it means all PCs present have active status -> safe to attack
        local all_pcs = GameObj.pcs()
        local innocuous_pcs = {}
        for _, pc in ipairs(all_pcs) do
            if not pc.status or (pc.status and pc.status:find("hid")) then
                table.insert(innocuous_pcs, pc)
            end
        end

        -- Check for disks belonging to unknown owners
        local loot = GameObj.loot()
        local unknown_disks = {}
        local char_name = GameState.name or ""
        for _, item in ipairs(loot) do
            if item.noun == "disk" and not item.name:find(char_name) then
                local owned_by_present_pc = false
                for _, pc in ipairs(all_pcs) do
                    if item.name:find(pc.noun) then owned_by_present_pc = true; break end
                end
                if not owned_by_present_pc then
                    table.insert(unknown_disks, item)
                end
            end
        end

        -- Check for hostile PCs who have attacked us before (jerks)
        local jerks = {}
        local attacked_me_raw = UserVars.attacked_me
        if attacked_me_raw and attacked_me_raw ~= "" then
            local attacked_list = Json.decode(attacked_me_raw) or {}
            for _, pc in ipairs(all_pcs) do
                if pc.status ~= "dead" then
                    for _, attacker_noun in ipairs(attacked_list) do
                        if pc.noun == attacker_noun then
                            table.insert(jerks, pc)
                            break
                        end
                    end
                end
            end
        end

        -- Justice check for jerks (can we legally fight them?)
        if #jerks > 0 then
            if justice_count ~= GameState.room_count then
                local result = dothistimeout("justice status", 1,
                    "no justice other than your own", "your surroundings are calm enough")
                if result and result:find("no justice other than your own") then
                    justice = false
                else
                    justice = true
                end
                justice_count = GameState.room_count
            end
            if justice then
                jerks = {}  -- can't attack in justice zones
            end
        end

        -- Sanctuary check
        if sanct_count == GameState.room_count then break end

        -- Decide whether to fight
        local should_fight = false
        if (poach and #hostile > 0)
           or (#hostile > 0 and (my_ambush or (#innocuous_pcs == 0 and #unknown_disks == 0)))
           or (attack_script and #jerks > 0) then
            should_fight = true
        end

        if should_fight then
            if attack_script then
                if checkrt() > 0 then waitrt() end
                if checkcastrt() > 0 then waitcastrt() end
                local ids = {}
                for _, npc in ipairs(jerks) do table.insert(ids, npc.id) end
                for _, npc in ipairs(hostile) do table.insert(ids, npc.id) end
                Script.run(attack_script, table.concat(ids, " "))
                wait_while(function() return running(attack_script) end)
                local lines = clear()
                for _, l in ipairs(lines) do
                    if Regex.test("Be at peace my child|Spells of War cannot be cast", l) then
                        sanct_count = GameState.room_count
                        break
                    end
                end
            else
                respond("")
                respond("*** Kill! ***")
                respond("")
                Script.pause(Script.name)
            end
        else
            break
        end
        pause(0.1)
    end
end

local function use_herbs()
    if not useherbs then return end
    if not Script.exists("eherbs") then
        echo("-------------------")
        echo("--- ALERT ALERT ---")
        echo("-------------------")
        echo("You've enabled the useherbs option, but you do not have eherbs downloaded.")
        echo("Please install eherbs and try again.")
        echo("-------------------")
        useherbs = false
        return
    end
    if max_wound() > 0 or max_scar() > 0 or (health() + 50) < max_health() then
        Script.run("eherbs", "--buy=off")
        wait_while(function() return running("eherbs") end)
        if max_wound() > 0 or max_scar() > 0 or (health() + 50) < max_health() then
            useherbs = false
        end
    end
end

-- ============================================================
-- Room-specific movement overrides
-- ============================================================

--- Check if any line in a table matches a pattern
local function any_line_matches(lines, pattern)
    for _, line in ipairs(lines) do
        if line:find(pattern) then return true end
    end
    return false
end

--- Wait for escort to catch up, checking room periodically.
--- If extra_checks is true (default), also does 10 additional check_room passes.
local function wait_for_escort(iterations, delay, extra_checks)
    delay = delay or 0.2
    if extra_checks == nil then extra_checks = true end
    for _ = 1, iterations do
        check_room()
        pause(delay)
        if check_escort() then return true end
    end
    if extra_checks then
        for _ = 1, 10 do
            check_room()
            pause(0.1)
        end
    end
    return false
end

--- Handle mining cart ride (used by multiple room pairs)
local function mining_cart_ride()
    dothistimeout("buy ticket", 10,
        "You already bought a ticket", "You now have passage")
    -- Wait to board cart
    local boarded = false
    for _ = 1, 300 do
        pause(0.1)
        if any_line_matches(clear(), "You hastily enter the mining cart") then
            boarded = true
            break
        end
    end
    if boarded then
        -- Wait for cart to arrive
        for _ = 1, 3600 do
            pause(0.1)
            if any_line_matches(clear(), "You hastily exit the cart") then break end
            check_room()
        end
    end
    -- Wait for escort
    wait_for_escort(100)
end

--- Handle icy path room (retry sneak movement until room changes)
local function icy_path_move(direction)
    local room_count = GameState.room_count
    while room_count == GameState.room_count do
        check_room()
        haste_me()
        check_room()
        if not standing() then fput("stand") end
        hide_me()
        dothistimeout(direction, 3,
            "Trying to sneak over", "Obvious", "Running heedlessly")
    end
end

--- Handle ferry wait and disembark
local function ferry_ride(start_id)
    move("go gangplank")
    if Map.current_room() == start_id then
        echo("Waiting for ferry... ")
        for _ = 1, 6000 do
            if any_line_matches(clear(), "lowers the gangplank") then break end
            check_room()
            pause(0.1)
        end
        move("go gangplank")
    end
    for _ = 1, 6000 do
        if any_line_matches(clear(), "lowers the gangplank") then break end
        check_room()
        pause(0.1)
    end
    haste_me()
    check_room()
    hide_me()
    check_room()
    hide_me()
    check_room()
    move("out")
end

local better_miniscript = {
    -- Climb transitions
    ["2524,2523"] = function() move("climb rockslide"); hide_me() end,
    ["2510,2509"] = function() move("climb bank"); hide_me() end,
    ["2509,2510"] = function() move("climb bank"); hide_me() end,
    ["2502,2503"] = function() move("climb branch"); hide_me() end,
    ["2505,2504"] = function() move("climb tree"); hide_me() end,
    ["75,74"]     = function() move("climb wall"); hide_me() end,
    ["74,75"]     = function() move("climb wall"); hide_me() end,
    ["884,883"]   = function() move("climb boulders"); hide_me() end,
    ["883,884"]   = function() move("climb boulders"); hide_me() end,
    ["964,963"]   = function() move("climb boulders"); hide_me() end,
    ["963,964"]   = function() move("climb boulders"); hide_me() end,
    ["1030,1029"] = function() move("climb cliff"); hide_me() end,
    ["1029,1030"] = function() move("climb cliff"); hide_me() end,
    ["1020,1019"] = function() move("climb crevice"); hide_me() end,
    ["1019,1020"] = function() move("climb crevice"); hide_me() end,
    ["1018,1017"] = function() move("climb precipice"); hide_me() end,
    ["1017,1018"] = function() move("climb cliff"); hide_me() end,
    ["1074,1075"] = function() move("southeast"); hide_me() end,

    -- Climb with protect/haste/empty_hands
    ["991,990"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb trail"); waitrt(); fill_hands()
    end,
    ["990,991"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb trail"); waitrt(); fill_hands()
    end,
    ["990,989"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb path"); waitrt(); fill_hands()
    end,
    ["989,990"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb path"); waitrt(); fill_hands()
    end,
    ["989,988"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb mountainside"); waitrt(); fill_hands()
    end,
    ["988,989"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb mountainside"); waitrt(); fill_hands()
    end,
    ["1224,1223"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb boulder"); waitrt(); fill_hands()
    end,
    ["1223,1224"] = function()
        protect_me(); check_room(); haste_me()
        empty_hands(); move("climb boulder"); waitrt(); fill_hands()
    end,

    -- Go with protect/haste
    ["971,970"] = function()
        protect_me(); check_room(); haste_me()
        move("go fissure"); waitrt(); hide_me()
    end,
    ["970,971"] = function()
        protect_me(); check_room(); haste_me()
        move("go fissure"); waitrt(); hide_me()
    end,
    ["902,901"] = function()
        protect_me(); check_room(); haste_me()
        move("go crevasse"); hide_me()
    end,
    ["1024,1025"] = function()
        protect_me(); check_room(); haste_me()
        move("climb ledge"); waitrt()
    end,
    ["1025,1024"] = function()
        protect_me(); check_room(); haste_me()
        move("climb cliff"); waitrt()
    end,
    ["1156,1155"] = function()
        protect_me(); check_room(); haste_me()
        move("north"); waitrt()
    end,
    ["1153,1154"] = function()
        protect_me(); check_room(); haste_me()
        move("south"); waitrt()
    end,
    ["1236,1237"] = function()
        protect_me(); check_room(); haste_me()
        move("go stream")
    end,
    ["1239,1238"] = function()
        protect_me(); check_room(); haste_me()
        move("go stream")
    end,

    -- Search-then-move transitions
    ["1219,1220"] = function()
        haste_me()
        for _ = 1, 3 do
            local result = dothistimeout("search", 3, "don't find anything", "discover a northwest path", "Roundtime")
            waitrt()
            check_room()
            if result and result:find("discover a northwest path") then break end
        end
        haste_me(); hide_me(); check_room(); hide_me(); check_room()
        move("go path")
    end,
    ["1242,1241"] = function()
        haste_me()
        for _ = 1, 5 do
            local result = dothistimeout("search", 5, "discover a", "don't find anything", "Roundtime")
            waitrt()
            check_room()
            if result and result:find("discover a") then break end
        end
        check_room(); haste_me(); check_room(); hide_me(); check_room(); hide_me(); check_room()
        move("go path")
    end,
    ["1216,1217"] = function()
        for _ = 1, 5 do
            local result = dothistimeout("search", 5, "don't find anything", "discover a small footpath", "Roundtime")
            fput("search")  -- Ruby sends search twice per iteration here
            waitrt()
            check_room()
            if result and result:find("discover a small footpath") then break end
        end
        check_room(); haste_me(); check_room(); hide_me(); check_room(); hide_me(); check_room()
        move("go footpath")
    end,
    ["1230,1231"] = function()
        haste_me()
        dothistimeout("search", 5, "You search")
        waitrt(); check_room(); haste_me(); check_room(); hide_me()
        move("go crack")
        haste_me()
        dothistimeout("search", 5, "You search")
        waitrt()
        wait_for_escort(15, 0.1)
        haste_me(); hide_me()
        move("go opening")
    end,
    ["1232,1231"] = function()
        haste_me()
        dothistimeout("search", 5, "You search")
        waitrt(); check_room(); haste_me(); check_room(); hide_me()
        move("go crack")
        haste_me()
        dothistimeout("search", 5, "You search")
        waitrt()
        wait_for_escort(15, 0.1)
        haste_me(); hide_me()
        move("go opening")
    end,

    -- Icy path rooms (all use icy_path_move helper)
    ["2547,2546"] = function() icy_path_move("northeast") end,
    ["2547,2548"] = function() icy_path_move("southwest") end,
    ["2545,2544"] = function() icy_path_move("north") end,
    ["2545,2546"] = function() icy_path_move("southwest") end,
    ["2536,2535"] = function() icy_path_move("east") end,
    ["2536,2537"] = function() icy_path_move("west") end,
    ["2535,2534"] = function() icy_path_move("southeast") end,
    ["2535,2536"] = function() icy_path_move("west") end,
    ["2534,2533"] = function() icy_path_move("southeast") end,
    ["2534,2535"] = function() icy_path_move("northwest") end,
    ["2526,2525"] = function() icy_path_move("east") end,
    ["2526,2527"] = function() icy_path_move("west") end,
    ["2525,2524"] = function() icy_path_move("northeast") end,
    ["2525,2526"] = function() icy_path_move("west") end,
    ["2524,2525"] = function() icy_path_move("southwest") end,
    ["2522,2521"] = function() icy_path_move("northeast") end,
    ["2522,2523"] = function() icy_path_move("west") end,
    ["2521,2520"] = function() icy_path_move("northeast") end,
    ["2521,2522"] = function() icy_path_move("southwest") end,
    ["2518,2519"] = function() icy_path_move("west") end,
    ["2518,2517"] = function() icy_path_move("northeast") end,
    ["2516,2515"] = function() icy_path_move("north") end,
    ["2516,2517"] = function() icy_path_move("south") end,
    ["2513,2512"] = function() icy_path_move("northwest") end,
    ["2513,2514"] = function() icy_path_move("south") end,
    ["2507,2508"] = function() icy_path_move("southwest") end,
    ["2506,2505"] = function() icy_path_move("north") end,
    ["2502,2501"] = function() icy_path_move("north") end,
    ["2500,2499"] = function() icy_path_move("northeast") end,
    ["2500,2501"] = function() icy_path_move("south") end,
    ["2497,2498"] = function() icy_path_move("southwest") end,
    ["2497,2496"] = function() icy_path_move("west") end,

    -- Mining cart rides
    ["1012,1013"] = mining_cart_ride,
    ["1260,1261"] = mining_cart_ride,
    ["1266,1267"] = mining_cart_ride,
    ["992,993"]   = mining_cart_ride,

    -- Ferry rides
    ["10117,10119"] = function() ferry_ride(10117) end,
    ["10119,10117"] = function() ferry_ride(10119) end,

    -- Multi-room transitions with escort wait
    ["784,786"] = function()
        haste_me(); hide_me()
        move("south"); wait_for_escort(10)
        haste_me(); hide_me()
        move("south"); wait_for_escort(10)
        haste_me(); hide_me()
        move("west")
    end,
    ["786,784"] = function()
        haste_me(); hide_me()
        move("east"); wait_for_escort(10)
        haste_me(); hide_me()
        move("east"); wait_for_escort(10)
        haste_me(); hide_me()
        move("north"); wait_for_escort(10)
        haste_me(); hide_me()
        move("east"); wait_for_escort(10)
        haste_me(); hide_me()
        move("north")
    end,
    ["1042,1041"] = function()
        move("climb boulder")
        check_room(); hide_me(); wait_for_escort(10)
        local result = dothistimeout("look trail", 5, "You peer into the mist")
        local dir = result and result:match("heads off to the (%w+)") or "north"
        haste_me(); hide_me()
        move("down"); wait_for_escort(10)
        haste_me(); hide_me()
        move(dir)
    end,
    ["1808,1811"] = function()
        haste_me(); hide_me()
        move("southwest"); wait_for_escort(10)
        haste_me(); hide_me()
        move("southwest"); wait_for_escort(10)
        haste_me(); hide_me()
        move("southwest"); wait_for_escort(10)
        haste_me(); hide_me()
        move("northwest"); wait_for_escort(10)
        haste_me(); hide_me()
        move("northwest")
    end,
    ["1811,1808"] = function()
        haste_me(); hide_me()
        move("southeast"); wait_for_escort(10)
        haste_me(); hide_me()
        move("southeast"); wait_for_escort(10)
        haste_me(); hide_me()
        move("northeast"); wait_for_escort(10)
        haste_me(); hide_me()
        move("northeast"); wait_for_escort(10)
        haste_me(); hide_me()
        move("northeast")
    end,

    -- Ladder transitions
    ["1074,1073"] = function()
        empty_hands(); haste_me()
        move("climb ladder"); waitrt()
        move("climb down"); waitrt()
        move("climb down"); waitrt()
        move("climb down"); waitrt()
        fill_hands()
    end,
    ["1070,1071"] = function()
        empty_hands(); haste_me()
        move("climb ladder"); waitrt()
        move("climb up"); waitrt()
        move("climb up"); waitrt()
        move("climb up"); waitrt()
        fill_hands()
    end,

    -- Variable-length swamp paths
    ["785,786"] = function()
        while has_exit("s") do
            move("south"); wait_for_escort(10)
            haste_me(); hide_me()
            move("west"); wait_for_escort(10)
            haste_me(); hide_me()
        end
    end,
    ["785,784"] = function()
        while has_exit("n") do
            move("east"); wait_for_escort(10)
            haste_me(); hide_me()
            move("north"); wait_for_escort(10)
            haste_me(); hide_me()
        end
    end,
}

-- ============================================================
-- Pathfinding & Navigation
-- ============================================================

--- Build a room-ID path from current location to destination.
-- Rooms that escort NPCs cannot follow through (portals, Vaalor shortcut).
-- Ruby suppressed these by setting timeto = 15000 before pathfinding.
-- Revenant's Map.find_path runs server-side and cannot have edge weights
-- overridden per-session, so instead we validate the path post-hoc and
-- error out with a clear message if a restricted transition is found.
local restricted_transitions = {
    -- Vaalor shortcut (rooms 16745 <-> 16746)
    ["16745,16746"] = true, ["16746,16745"] = true,
    -- Chronomage portal hub rooms (seeking / portal links)
    ["16200,16201"] = true, ["16201,16200"] = true,
    ["16202,16203"] = true, ["16203,16202"] = true,
    ["16204,16205"] = true, ["16205,16204"] = true,
    ["16206,16207"] = true, ["16207,16206"] = true,
    ["16208,16209"] = true, ["16209,16208"] = true,
}

--- Map.find_path returns a command list. We reconstruct room IDs by
--- walking the map graph: for each command, find which wayto dest matches.
--- If a command is ambiguous or doesn't match (e.g. StringProc exits),
--- we stop reconstruction early and fall back to command-only navigation.
local function find_path_to_dest()
    local current = Map.current_room()
    if not current then
        echo("Current room is not in the map database.")
        if hidden() then fput("unhide") end
        error("no current room")
    end
    if not destination_room then
        echo("No destination room set.")
        error("no destination")
    end

    local raw_path = Map.find_path(current, destination_room)
    if not raw_path or #raw_path == 0 then
        echo("You can't get there (" .. destination_room .. ") from here (" .. current .. ").")
        if hidden() then fput("unhide") end
        error("no path")
    end

    -- Reconstruct room ID sequence from commands.
    -- This is needed for better_miniscript lookup (keyed by "from_id,to_id").
    local room_ids = { current }
    local walk_id = current
    for _, c in ipairs(raw_path) do
        local room = Map.find_room(walk_id)
        local found = false
        if room and room.wayto then
            for dest_str, wayto_cmd in pairs(room.wayto) do
                if type(wayto_cmd) == "string" and wayto_cmd == c then
                    walk_id = tonumber(dest_str)
                    if walk_id then
                        table.insert(room_ids, walk_id)
                        found = true
                    end
                    break
                end
            end
        end
        if not found then
            -- Can't reconstruct further (StringProc or ambiguous exit).
            -- Append destination as final node so miniscript can still
            -- match the last segment.
            if room_ids[#room_ids] ~= destination_room then
                table.insert(room_ids, destination_room)
            end
            break
        end
    end

    -- Validate no restricted transitions (portals/Vaalor shortcut) in path.
    -- Escort NPCs cannot follow through these links.
    for i = 1, #room_ids - 1 do
        local key = tostring(room_ids[i]) .. "," .. tostring(room_ids[i+1])
        if restricted_transitions[key] then
            echo("Path routes through a restricted transition (" .. key .. ").")
            echo("Escort NPCs cannot use portals or the Vaalor shortcut.")
            echo("Check your map data — this transition should not appear in escort paths.")
            if hidden() then fput("unhide") end
            error("restricted transition in path: " .. key)
        end
    end

    path = { ids = room_ids, commands = raw_path }
    respond("ETA: ~" .. #raw_path .. " rooms to move through.")
end

local function go_next_room()
    local current = Map.current_room()
    if not current then
        echo("Current room is not in the map database.")
        if hidden() then fput("unhide") end
        error("no current room")
    end

    -- Find our position in the path
    local idx = nil
    if path and path.ids then
        for i, id in ipairs(path.ids) do
            if id == current then idx = i; break end
        end
    end
    if not idx then
        find_path_to_dest()
        for i, id in ipairs(path.ids) do
            if id == current then idx = i; break end
        end
        if not idx then
            echo("Cannot find current room in path after recalculation.")
            error("lost in path")
        end
    end

    if idx >= #path.ids then return end  -- already at destination

    local next_id = path.ids[idx + 1]
    local key = tostring(current) .. "," .. tostring(next_id)

    -- Check for room-specific override
    local override = better_miniscript[key]
    if override then
        override()
    else
        -- Normal movement
        local room = Map.find_room(current)
        if room and room.wayto then
            local way_cmd = room.wayto[tostring(next_id)]
            if way_cmd then
                local count = 0
                while true do
                    local ok, err = pcall(move, way_cmd)
                    if ok then
                        break
                    else
                        if Map.current_room() ~= current then break end
                        -- Don't count movement failures caused by status effects
                        -- (webbed, bound, rooted) as map errors — matches Ruby muckled? guard
                        if webbed() or bound() then pause(0.5); break end
                        count = count + 1
                        if count > 5 then
                            echo("fixing map database...")
                            echo("deleting: " .. current .. " -> " .. way_cmd .. " -> " .. next_id)
                            break
                        end
                        pause(0.2)
                    end
                end
            else
                -- No wayto found -- recalculate
                path = nil
            end
        else
            path = nil
        end
    end
    pause(0.1)
end

local function backtrack()
    local current = Map.current_room()
    if not current or not path or not path.ids then
        echo("Cannot backtrack -- lost position.")
        return
    end

    local idx = nil
    for i, id in ipairs(path.ids) do
        if id == current then idx = i; break end
    end
    if not idx or idx <= 1 then
        echo("Cannot backtrack further.")
        return
    end

    local prev_id = path.ids[idx - 1]
    local room = Map.find_room(current)
    if room and room.wayto then
        local way_cmd = room.wayto[tostring(prev_id)]
        if way_cmd then
            local ok, _ = pcall(move, way_cmd)
            if not ok and Map.current_room() == current then
                echo("Backtrack movement failed.")
                -- Ruby also deleted wayto+timeto entries here to repair map DB;
                -- Revenant map data is read-only from Lua (SQLite-backed).
            end
        else
            -- Try go2 fallback
            Script.run("go2", tostring(prev_id))
            wait_while(function() return running("go2") end)
        end
    end
    pause(0.1)
end

-- ============================================================
-- Main execution
-- ============================================================

-- Parse bounty task
local bounty_text = checkbounty()
if not bounty_text or not bounty_text:find("provide a protective escort") then
    echo("You don't have an escort task.")
    if hidden() then fput("unhide") end
    return
end

local pickup_string = bounty_text:match("Go to the (.-) and WAIT")
local destination_town = bounty_text:match("guarantee .- safety to (.-) as soon as you can")

if not pickup_string or not destination_town then
    echo("Could not parse escort bounty task.")
    if hidden() then fput("unhide") end
    return
end

local pickup_info = escort_pickup[pickup_string]
if not pickup_info then
    echo("error: unmatched pickup location: " .. pickup_string)
    if hidden() then fput("unhide") end
    return
end

local start_town = pickup_info.town
local pickup_room = pickup_info.room

if not escort_dropoff[destination_town] then
    echo("error: unmatched destination town: " .. destination_town)
    if hidden() then fput("unhide") end
    return
end

if not Map.current_room() then
    echo("error: current room was not found in the map database")
    if hidden() then fput("unhide") end
    return
end

-- Check if escort is already in the room
for _, npc in ipairs(GameObj.npcs()) do
    if is_escort(npc.noun) then
        if hidden() or invisible() then fput("unhide") end
        local result = dothistimeout("tell #" .. npc.id .. " to follow", 8,
            npc.noun .. " nods and says to you",
            npc.noun .. ' says to you, "But I already am!"',
            npc.noun .. " says to you, \"The guild didn't hire you",
            "gives you a strange look")
        if result and Regex.test("nods and says to you|But I already am", result) then
            escort_id = npc.id
            break
        end
    end
end

-- If no escort yet, go get silver and pick them up
if not escort_id then
    -- Get money for travel
    travel_cost = travel_cost or (default_travel_cost[start_town] and default_travel_cost[start_town][destination_town]) or 0
    local silvers = silver_count()
    if silvers < travel_cost then
        -- Go to bank
        local bank = Room.find_nearest_by_tag("bank")
        if bank then
            Script.run("go2", tostring(bank.id))
            wait_while(function() return running("go2") end)
            if hidden() or invisible() then fput("unhide") end
            fput("withdraw " .. (travel_cost - silvers))
        end
    end

    -- Go to pickup room
    Script.run("go2", tostring(pickup_room))
    wait_while(function() return running("go2") end)

    -- Wait for escort
    dothistimeout("wait", 20, "Time drags on by")
    local checked_ids = {}
    for _ = 1, 130 do
        pause(0.1)
        for _, npc in ipairs(GameObj.npcs()) do
            if is_escort(npc.noun) and not checked_ids[npc.id] then
                checked_ids[npc.id] = true
                if hidden() or invisible() then fput("unhide") end
                local result = dothistimeout("tell #" .. npc.id .. " to follow", 8,
                    npc.noun .. " nods and says to you",
                    npc.noun .. ' says to you, "But I already am!"',
                    npc.noun .. " says to you, \"The guild didn't hire you",
                    "gives you a strange look")
                if result and Regex.test("nods and says to you|But I already am", result) then
                    escort_id = npc.id
                    break
                end
            end
        end
        if escort_id then break end
    end
end

if not escort_id then
    echo("error: failed to find escort")
    if hidden() then fput("unhide") end
    return
end

-- Find destination room (nearest dropoff)
destination_room = find_nearest(escort_dropoff[destination_town])
if not destination_room then
    echo("error: failed to find destination room")
    if hidden() then fput("unhide") end
    return
end

-- Calculate initial path
find_path_to_dest()

local start_time = os.time()

-- Main escort loop
while true do
    -- Death check (replaces Lich5 background thread)
    if dead() then
        echo("Character is dead -- stopping escort.")
        break
    end

    -- Stand if needed
    if not standing() and not stunned() and checkrt() == 0 then
        fput("stand")
        pause(0.5)
    end

    haste_me()
    check_room()
    use_herbs()
    check_room()
    hide_me()
    check_room()
    use_herbs()
    check_room()
    hide_me()

    go_next_room()

    -- Wait for escort to catch up
    wait_for_escort(10, 0.1)

    -- Check bounty status
    local current_bounty = checkbounty()
    if not current_bounty or not current_bounty:find("provide a protective escort") then
        break
    end

    if check_escort() then
        lost_escort = 0
        fell_off_rope = false
        -- Brief pause with room checking
        local end_time = os.time() + 1
        while os.time() < end_time do
            pause(0.1)
            check_room()
        end
        wait_num = 45
    else
        lost_escort = lost_escort + 1
        if lost_escort > 10 then
            echo("error: lost escort")
            break
        end
        -- Check for other PCs
        local pcs = GameObj.pcs()
        if #pcs > 0 then
            backtrack()
            if check_escort() then lost_escort = 0 end
            for _ = 1, wait_num + 5 do check_room(); pause(0.2) end
            wait_num = wait_num + 5
        else
            backtrack()
            if check_escort() then lost_escort = 0 end
            check_room()
        end
    end
end

echo("travel time: " .. format_time(os.time() - start_time))

if hidden() then fput("unhide") end
