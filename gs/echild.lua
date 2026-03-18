--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: echild
--- version: 1.20.3
--- author: elanthia-online
--- contributors: Drafix, Catrania, Kaldonis, Kalros, Hazado, Tysong, Xanlin
--- description: Automate Adventurer's Guild escort-a-child bounty task
--- tags: bounty,escort,adventurers-guild
--- depends: lib/args,lib/spell_casting,lib/watchfor
---
--- Changelog (from Lich5):
---   v1.20.3 (2025-05-23)
---     - fix for detecting familiars incorrectly
---   v1.20.2 (2025-01-19)
---     - fix for constant redefinition Ruby warnings
---   v1.20.1 (2024-09-12)
---     - convert to use RealID instead of LichID
---   v1.20.0 (2024-08-07)
---     - add customizable, always use, disabler option via --disabler=617
---     - convert min_mana, use_disablers to CharSettings instead of Settings
---   v1.19.1 (2024-07-06)
---     - bugfix in Maaghara routine for climb failure
---     - order spells by actual mana cost
---     - allow for usage of move2.lic instead of step2.lic
---   v1.19.0 (2024-03-12)
---     - add CLI option to disable disablers via ;echild nodisablers
---     - modify ;echild list to also trigger for help, expand output
---   v1.18.11 (2024-02-25)
---     - return child to correct location with manual ask of child
---   v1.18.10 (2024-02-15)
---     - bug in standing for Maaghara routine
---   v1.18.9 (2023-07-08)
---     - rubocop cleanup
---     - add Atoll creatures to 706 Mind Jolt exclusion
---   v1.18.8 (2023-02-23)
---     - Bugfix for Ruby v3.x compatibility
---   v1.18.7 (2022-11-03)
---     - Kill Song of Peace on exit
---   v1.18.6 (2022-09-21)
---     - removed Atoll code because fixed in GS now
---   v1.18.5 (2022-09-20)
---     - added a second check looking for the child
---   v1.18.4 (2022-09-03)
---     - better check for 9716
---   v1.18.3 (2022-09-03)
---     - fixed nil? typo, added 9716 check for can cast, skip wound check on script start
---   v1.18.2 (2022-09-01)
---     - moved killswitch to fix error
---   v1.18.1 (2022-08-25)
---     - fixed advguard2 typo
---   v1.17.0 (2022-08-15)
---     - moved into module, updated can_cast debuff list
---   v1.16.0 (2022-08-09)
---     - custom proc for Maaghara
---     - custom proc for Atoll
---     - added global $child_last_seen
---     - removed final pause if not Drafix, etc.
---     - added test mode
---     - added check for being able to cast before running justice check
---   v1.15.0 (2022-05-27)
---     - Updated to support KF rapids and guard, rebaselined as echild
---   v1.14 (2020-06-15)
---     - filter ghosts from 501
---   v1.13 (2020-06-08)
---     - fix mult-target filtering bug
---   v1.12 (2020-06-07)
---     - filter 410 for specific critters, allow 504 multi-target if airlore > 20
---   v1.11 (2020-05-21)
---     - add monk spells, move sanctuary to multi-target section only, add lullabye
---   v1.10 (2020-05-20)
---     - fix filtering of spells
---   v1.9 (2020-05-20)
---     - hide justice check
---   v1.8 (2020-05-15)
---     - Don't e-wave in town, use the cheapest spell mana-wise, prefer 213/1011
---   v1.7 (2017-10-12)
---     - Fix min mana comparison issue
---   v1.6 (2017-10-05)
---     - Fix RR for putting npc in room description
---   v1.5 (2017-09-09)
---     - Added min mana setting and fixed untargetable npc checking
---   v1.4 (2016-09-18)
---     - Return of maintenance
---   v1.3 (2016-05-17)
---     - deliver child to closest guard to specified room
---   v1.2 (2016-05-11)
---     - Hazado added specific child tracking
---   v1.1 (2015-11-04)
---     - Fixed purser in RR
---   v1.0 (2015-07-06)
---     - Rewrote parts for Vaalor guards, fixed loop for alternate rooms
---   v0.9 (2015-07-03)
---     - Rewrote for Pinefar v1.3
---   v0.8 (2015-06-25)
---     - Fix alternate drop off spot
---   v0.7 (2015-05-19)
---     - Drafix took over maintaining from Jeril
---     - added passive critter recognition, nearest guard drop-off
---   v0.6 (2012-12-10)
---     - fixed 213 casting, fixed purser bug
---   v0.5 (2012-05-18)
---     - made it work in RR
---   v0.4 (2012-04-17)
---     - added Vaalor
---   v0.3 (2011-06-04)
---     - added Teras, Helga's for landing guard
---   v0.2 (2010-12-16)
---     - bug fixes
---   v0.1 (2010-02-19)
---     - added Illistim, disabled automatic reward collection

require("lib/spell_casting")
local Watchfor = require("lib/watchfor")

--------------------------------------------------------------------------------
-- Utility helpers
--------------------------------------------------------------------------------

local function load_untargetable()
    local raw = Settings.untargetable
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_untargetable(list)
    Settings.untargetable = Json.encode(list)
end

local function get_bool_setting(key, default)
    local v = CharSettings[key]
    if v == nil then return default end
    return v == "true"
end

local function set_bool_setting(key, val)
    CharSettings[key] = tostring(val)
end

local function get_int_setting(key, default)
    local v = CharSettings[key]
    if v == nil then return default end
    return tonumber(v) or default
end

local function set_int_setting(key, val)
    CharSettings[key] = tostring(val)
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function table_remove_value(t, val)
    for i = #t, 1, -1 do
        if t[i] == val then
            table.remove(t, i)
        end
    end
end

local function table_unique(t)
    local seen = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            seen[v] = true
            result[#result + 1] = v
        end
    end
    return result
end

--- Merge two tables (set union), preserving order, no duplicates
local function table_union(a, b)
    local result = {}
    local seen = {}
    for _, v in ipairs(a) do
        if not seen[v] then
            seen[v] = true
            result[#result + 1] = v
        end
    end
    for _, v in ipairs(b) do
        if not seen[v] then
            seen[v] = true
            result[#result + 1] = v
        end
    end
    return result
end

local function max_of(...)
    local vals = {...}
    local m = vals[1]
    for i = 2, #vals do
        if vals[i] > m then m = vals[i] end
    end
    return m
end

--------------------------------------------------------------------------------
-- Find hostile NPCs (replaces GameObj.targets which does not exist)
--------------------------------------------------------------------------------

local function get_hostile_npcs(untargetable_list, guard_pattern)
    local dominated = {"dead", "prone", "lying down", "stunned", "sleeping", "webbed", "calm", "sitting", "frozen"}
    local npcs = GameObj.npcs()
    local hostiles = {}
    for _, npc in ipairs(npcs) do
        local is_dominated = false
        for _, d in ipairs(dominated) do
            if npc.status and npc.status:find(d) then
                is_dominated = true
                break
            end
        end
        if not is_dominated then
            local is_untargetable = false
            for _, u in ipairs(untargetable_list) do
                if npc.name == u then
                    is_untargetable = true
                    break
                end
            end
            if not is_untargetable and not (guard_pattern and npc.name:find(guard_pattern)) then
                hostiles[#hostiles + 1] = npc
            end
        end
    end
    return hostiles
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- Determine step script
local step_script
if File.exists("move2.lua") then
    step_script = "move2"
elseif File.exists("step2.lua") then
    step_script = "step2"
else
    echo("A supplemental movement script is required and is missing.")
    echo("Either download move2.lua (preferred) or step2.lua")
    echo("Exiting!")
    return
end

local untargetable = load_untargetable()
local min_mana = get_int_setting("min_mana", 0)
local use_disablers = get_bool_setting("use_disablers", true)
local custom_disabler_raw = CharSettings.custom_disabler
local custom_disabler = false
if custom_disabler_raw and custom_disabler_raw ~= "" and custom_disabler_raw ~= "false" then
    local n = tonumber(custom_disabler_raw)
    if n and n > 0 then
        custom_disabler = n
    end
end
local stop_1011 = false

-- Save go2 seeking state and disable for this escort run (parity: $go2_use_seeking)
local seeking_save = UserVars.mapdb_use_seeking
UserVars.mapdb_use_seeking = false

--------------------------------------------------------------------------------
-- CLI argument handling
--------------------------------------------------------------------------------

local vars0 = Script.vars[0] or ""

if vars0:find("list") or vars0:find("help") then
    echo("Current Disabler Usage: " .. tostring(use_disablers))
    echo("Current Minimum mana to reserve: " .. tostring(min_mana))
    echo("Current Forced Disabler: " .. tostring(custom_disabler))
    echo("Current untargetables: " .. table.concat(untargetable, ", "))
    echo("To modify this list, use one of the following:")
    echo("   ;echild clear - clears entire untargetable list")
    echo("   ;echild remove <target1> <target2> <target3> <etc> - clears targets from list")
    echo("   ;echild nodisable    - disables usage of disablers")
    echo("   ;echild --disabler=<NUM>   - forces use of specific disabler, set to 0, nil, false to turn off")
    return
elseif vars0:find("clear") then
    save_untargetable({})
    return
elseif vars0:find("remove") then
    -- Remove targets specified in args 2+
    local to_remove = {}
    local i = 2
    while Script.vars[i] do
        to_remove[#to_remove + 1] = Script.vars[i]
        i = i + 1
    end
    local remove_str = table.concat(to_remove, " ")
    table_remove_value(untargetable, remove_str)
    save_untargetable(untargetable)
    echo("Removed: " .. remove_str)
    return
elseif vars0:find("mana") then
    local new_mana = tonumber(Script.vars[2]) or 0
    set_int_setting("min_mana", new_mana)
    min_mana = new_mana
    echo("Minimum mana to reserve: " .. tostring(min_mana))
    return
elseif vars0:find("nodisable") then
    use_disablers = not use_disablers
    set_bool_setting("use_disablers", use_disablers)
    echo("Disablers Usage now set to " .. tostring(use_disablers))
    return
end

-- Check for --disabler=NUM inline flag
local disabler_match = vars0:match("%-%-disabler[=:](%w+)")
if disabler_match then
    if disabler_match == "nil" or disabler_match == "false" or disabler_match == "0" then
        custom_disabler = false
        CharSettings.custom_disabler = "false"
    else
        local n = tonumber(disabler_match)
        if n then
            custom_disabler = n
            CharSettings.custom_disabler = tostring(n)
        end
    end
end

--------------------------------------------------------------------------------
-- Justice check
--------------------------------------------------------------------------------

local function check_justice()
    local justice = nil
    DownstreamHook.add(Script.name .. "_check_justice", function(server_string)
        if server_string:find("You sense that your surroundings are calm") then
            justice = true
            return nil
        elseif server_string:find("There is no justice") then
            justice = false
            return nil
        end
        return server_string
    end)
    put("justice status")
    wait_until(function() return justice ~= nil end)
    DownstreamHook.remove(Script.name .. "_check_justice")
    return justice
end

--------------------------------------------------------------------------------
-- Can-cast check
--------------------------------------------------------------------------------

local function echild_can_cast()
    if stunned() or dead() then return false end

    local wounds_prevent_cast = false
    if Spell[9716].active then
        wounds_prevent_cast = max_of(
            Wounds.head, Scars.head,
            Wounds.leftEye, Scars.leftEye,
            Wounds.rightEye, Scars.rightEye,
            Wounds.nsys, Scars.nsys
        ) > 2
    else
        wounds_prevent_cast = (
            max_of(
                Wounds.head, Scars.head,
                Wounds.leftEye, Scars.leftEye,
                Wounds.rightEye, Scars.rightEye,
                Wounds.nsys, Scars.nsys
            ) > 1
        ) or (
            max_of(
                Wounds.leftArm, Wounds.leftHand,
                Wounds.rightArm, Wounds.rightHand,
                Scars.leftArm, Scars.leftHand,
                Scars.rightArm, Scars.rightHand
            ) > 2
        ) or (
            max_of(
                Wounds.leftArm, Wounds.leftHand,
                Scars.leftArm, Scars.leftHand
            ) > 1
        ) or (
            max_of(
                Wounds.rightArm, Wounds.rightHand,
                Scars.leftArm, Scars.leftHand
            ) > 1
        )
    end
    if wounds_prevent_cast then return false end

    -- Note: Effects::Debuffs does not exist in Revenant.
    -- Check specific debuff spells that would prevent casting.
    -- Skipping debuff check as there is no equivalent API.

    return true
end

--------------------------------------------------------------------------------
-- Disablers
--------------------------------------------------------------------------------

local elair = Skills.elemental_lore_air or 0

local DISABLERS = {
    { num = 135,  town_safe = false, single_target = false },
    { num = 201,  town_safe = true,  single_target = true },
    { num = 213,  town_safe = true,  single_target = false },
    { num = 316,  town_safe = false, single_target = false },
    { num = 410,  town_safe = false, single_target = false },
    { num = 501,  town_safe = true,  single_target = true },
    { num = 504,  town_safe = true,  single_target = (elair >= 20) and false or true },
    { num = 505,  town_safe = true,  single_target = true },
    { num = 519,  town_safe = true,  single_target = true },
    { num = 619,  town_safe = false, single_target = false },
    { num = 706,  town_safe = true,  single_target = true },
    { num = 709,  town_safe = false, single_target = false },
    { num = 912,  town_safe = true,  single_target = false },
    { num = 1005, town_safe = true,  single_target = true },
    { num = 1011, town_safe = true,  single_target = false },
    { num = 1207, town_safe = true,  single_target = true },
    { num = 1219, town_safe = false, single_target = false },
    { num = 1608, town_safe = false, single_target = false },
}

local function find_best_disabler(skip_can_cast)
    if not skip_can_cast and not echild_can_cast() then
        return nil
    end

    -- Find all eligible spells
    local candidates = {}
    for _, disabler in ipairs(DISABLERS) do
        local spell = Spell[disabler.num]
        if spell and spell.known and spell:affordable() and ((mana() - spell.mana_cost) >= min_mana) then
            candidates[#candidates + 1] = disabler
        end
    end

    if #candidates == 0 then return nil end

    -- Check for custom disabler override
    if custom_disabler and type(custom_disabler) == "number" then
        local cs = Spell[custom_disabler]
        if cs and cs.known and cs:affordable() then
            return { num = custom_disabler }
        end
    end

    -- Filter town-safe spells if in town
    local justice = check_justice()
    if justice then
        local filtered = {}
        for _, disabler in ipairs(candidates) do
            if disabler.town_safe then
                filtered[#filtered + 1] = disabler
            end
        end
        candidates = filtered
    end

    -- Filter single target spells if more than 1 hostile NPC
    local npcs = get_hostile_npcs(untargetable, nil)
    if #npcs > 1 then
        local filtered = {}
        for _, c in ipairs(candidates) do
            if not c.single_target then
                filtered[#filtered + 1] = c
            end
        end
        candidates = filtered

        -- Multi-target filtering: exclude 410 for specific critter types
        local immune_410_re = Regex.new("\\b(?:glacei|wraith|elemental|cold guardian)\\b")
        local all_npcs = GameObj.npcs()
        local has_immune_410 = false
        for _, npc in ipairs(all_npcs) do
            if immune_410_re:test(npc.name) then
                has_immune_410 = true
                break
            end
        end
        if has_immune_410 then
            local f2 = {}
            for _, c in ipairs(candidates) do
                if c.num ~= 410 then f2[#f2 + 1] = c end
            end
            candidates = f2
        end

        -- Prefer sanctuary spells 213 or 1011
        for _, c in ipairs(candidates) do
            if c.num == 213 or c.num == 1011 then
                return c
            end
        end
    elseif #npcs == 1 then
        local npc = npcs[1]
        local name = npc.name or ""

        -- Single target filtering with compiled regex patterns
        local immune_501_re = Regex.new("\\b(?:glacei|corpse|wraith|elemental|ghost)\\b")
        local immune_505_re = Regex.new("\\b(?:glacei|elemental|wraith)\\b")
        local immune_410_single_re = Regex.new("\\b(?:glacei|griffin|grifflet|elemental)\\b")
        local immune_709_re = Regex.new("\\b(?:glacei|griffin|grifflet|elemental)\\b")
        local immune_706_re = Regex.new("\\b(?:glacei|construct|elemental|brawler|protector|psionicist|fanatic)\\b")
        local immune_201_re = Regex.new("\\b(?:grimswarm|construct)\\b")

        local function filter_out_re(spell_num, re)
            if re:test(name) then
                local f = {}
                for _, c in ipairs(candidates) do
                    if c.num ~= spell_num then f[#f + 1] = c end
                end
                candidates = f
            end
        end

        filter_out_re(501, immune_501_re)
        filter_out_re(505, immune_505_re)
        filter_out_re(410, immune_410_single_re)
        filter_out_re(709, immune_709_re)
        filter_out_re(706, immune_706_re)
        filter_out_re(201, immune_201_re)
    end

    -- Sort by mana cost (ascending)
    table.sort(candidates, function(a, b)
        return Spell[a.num].mana_cost < Spell[b.num].mana_cost
    end)

    return candidates[1] or nil
end

-- Determine at startup if we can cast disablers
local can_cast_disabler
if use_disablers then
    can_cast_disabler = (find_best_disabler(true) ~= nil)
    if not can_cast_disabler then
        echo("Note: No disablers known")
    end
else
    can_cast_disabler = false
end

--------------------------------------------------------------------------------
-- before_dying cleanup
--------------------------------------------------------------------------------

before_dying(function()
    DownstreamHook.remove(Script.name .. "_check_justice")
    UserVars.mapdb_use_seeking = seeking_save  -- restore go2 seeking state
    if stop_1011 then
        waitrt()
        fput("stop 1011")
    end
end)

--------------------------------------------------------------------------------
-- Find the child
--------------------------------------------------------------------------------

local child_id = nil
local child_last_seen = nil
local test_mode = false

local test_match = vars0:match("%-%-test[=:](%S+)")
if test_match then
    test_mode = true
    local npc_noun = test_match
    echo("testing " .. npc_noun)
    for _, n in ipairs(GameObj.npcs()) do
        if n.noun == npc_noun then
            child_id = n.id
            break
        end
    end
    child_last_seen = Map.current_room()
else
    for _, n in ipairs(GameObj.npcs()) do
        if n.noun and n.noun:lower():find("child") then
            child_id = n.id
            break
        end
    end
    if child_id then
        child_last_seen = Map.current_room()
    end
end

if not child_id then
    echo("child not found, waiting a few")
    local timeout = os.time() + 5
    while not child_id and os.time() < timeout do
        for _, n in ipairs(GameObj.npcs()) do
            if n.noun and n.noun:lower():find("child") then
                child_id = n.id
                break
            end
        end
        if not child_id then pause(0.1) end
    end
    if not child_id then
        echo("child not found, quitting")
        return
    end
end

--------------------------------------------------------------------------------
-- Dropoff points
--------------------------------------------------------------------------------

local advguard = Map.find_all_nearest_by_tag("advguard") or {}
local advguard2 = Map.find_all_nearest_by_tag("advguard2") or {}

local uid_list = {4564003, 4564004, 4564010, 4564005, 4564011, 4564008, 4564006, 4564007, 4564013, 4564014, 4564009}
local uid_rooms = {}
for _, uid in ipairs(uid_list) do
    local ids = Map.ids_from_uid(uid)
    if ids and ids[1] then
        uid_rooms[#uid_rooms + 1] = ids[1]
    end
end

local dropoff_points = table_union(table_union(advguard, advguard2), uid_rooms)

local child_homes = {}
local function add_home(name, uid)
    local ids = Map.ids_from_uid(uid)
    if ids and ids[1] then
        child_homes[name] = ids[1]
    end
end
add_home("Icemule Trace",        4042150)
add_home("Kharam Dzu",           3001025)
add_home("Kraken's Fall",        7118221)
add_home("Mist Harbor",          3201029)
add_home("the County of Torre",  2101008)
add_home("Vornavis",             4209030)
add_home("Ta'Illistim",          13100042)
add_home("Ta'Vaalor",            14100047)
add_home("Wehnimer's Landing",   7120)
add_home("Kharag 'doth Dzulthu", 13006016)

local reportee_re = Regex.new("sergeant|guard|purser|Belle|Luthrek")

--------------------------------------------------------------------------------
-- Determine destination
--------------------------------------------------------------------------------

local place
local room_num_match = vars0:match("(%d+)")
if room_num_match then
    local from_room = tonumber(room_num_match)
    place = Map.find_nearest_room(from_room, dropoff_points)
else
    local child_response = 'The child says, "Please, take me home to ([^!]+)!"'
    local line = dothistimeout("ask child about destination", 5, {child_response})
    if line then
        local dest_name = line:match(child_response)
        if dest_name and child_homes[dest_name] then
            place = Map.find_nearest_room(child_homes[dest_name], dropoff_points)
        elseif dest_name then
            respond("** missing child_homes entry for [" .. dest_name .. "], please report to elanthia-online. **")
            place = Map.find_nearest_room(Map.current_room(), dropoff_points)
        else
            place = Map.find_nearest_room(Map.current_room(), dropoff_points)
        end
    else
        place = Map.find_nearest_room(Map.current_room(), dropoff_points)
    end
end

-- Remove chosen dropoff from list so we can try alternates
for i = #dropoff_points, 1, -1 do
    if dropoff_points[i] == place then
        table.remove(dropoff_points, i)
    end
end

local original_place = place

--------------------------------------------------------------------------------
-- Kill switch: if task fails, go back to original place and exit
--------------------------------------------------------------------------------

Watchfor.new("You have failed your current Adventurer's Guild task", function()
    Script.run("go2", tostring(original_place))
    pause(1)
    Script.kill(Script.name)
end)

--------------------------------------------------------------------------------
-- Maaghara Labyrinth
--------------------------------------------------------------------------------

local maaghara_exits = {}
local function add_maaghara(from_uid, to_uid)
    local from_ids = Map.ids_from_uid(from_uid)
    local to_ids = Map.ids_from_uid(to_uid)
    if from_ids and from_ids[1] and to_ids and to_ids[1] then
        maaghara_exits[from_ids[1]] = to_ids[1]
    end
end
add_maaghara(13022005, 13022015)
add_maaghara(13022025, 13022015)
add_maaghara(13022015, 13022035)
add_maaghara(13022035, 13022045)
add_maaghara(13022045, 13022005)

local maaghara_success = "rootlike tendrils as thick as your thumb snake out and encircle"
local maaghara_fail = "seem to be any way to do that at the moment"
local maaghara_retry = "You step into the root, but can see no way to climb the slippery tendrils inside"

local maaghara_exit_room_ids = Map.ids_from_uid(13021008)
local maaghara_exit_room = maaghara_exit_room_ids and maaghara_exit_room_ids[1]

local function maaghara_move()
    local counter = 0
    while true do
        if counter == 3 then break end
        local move_result = dothistimeout("go root", 3, {maaghara_success, maaghara_fail, maaghara_retry})
        if move_result and move_result:find(maaghara_success, 1, true) then
            -- Restore original destination
            place = original_place
            if maaghara_exit_room then
                wait_until(function() return Map.current_room() == maaghara_exit_room end)
            end
            while not standing() do
                fput("stand")
                waitrt()
            end
            break
        elseif move_result and move_result:find(maaghara_fail, 1, true) then
            -- Set destination to next way out
            local cur = Map.current_room()
            if maaghara_exits[cur] then
                place = maaghara_exits[cur]
            end
            break
        elseif move_result and move_result:find(maaghara_retry, 1, true) then
            pause(1)
            -- retry (continue loop)
        else
            echo("maaghara_move failed")
            counter = counter + 1
        end
    end
end

--------------------------------------------------------------------------------
-- Helper: check if child is in room
--------------------------------------------------------------------------------

local function child_in_room()
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.id == child_id then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Helper: find reportee NPC in room
--------------------------------------------------------------------------------

local function find_reportee()
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.name and reportee_re:test(npc.name) then
            return npc
        end
    end
    for _, obj in ipairs(GameObj.room_desc()) do
        if obj.name and obj.name:find("purser") then
            return obj
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local child_no_wait = {}

while true do
    -- Inner navigation loop
    while true do
        -- Maaghara check
        local cur = Map.current_room()
        if maaghara_exits[cur] then
            maaghara_move()
        end

        cur = Map.current_room()
        if cur ~= place then
            local thatroom = cur
            waitrt()
            Script.run(step_script, tostring(place))
            wait_while(function() return running(step_script) end)
            wait_until(function() return thatroom ~= Map.current_room() end)
            waitrt()

            -- Check for hostile NPCs (replaces GameObj.targets check)
            local npcs_hostile = get_hostile_npcs(untargetable, nil)
            -- Remove child from hostile list
            local real_hostiles = {}
            for _, npc in ipairs(npcs_hostile) do
                if npc.id ~= child_id then
                    real_hostiles[#real_hostiles + 1] = npc
                end
            end
            local has_pcs = #GameObj.pcs() > 0
            local guard_present = find_reportee() ~= nil

            if #real_hostiles > 0 and not has_pcs and not guard_present then
                -- Make sure it's not just the child alone
                local all_npcs = GameObj.npcs()
                local only_child = (#all_npcs == 1 and all_npcs[1].id == child_id)

                if not only_child and can_cast_disabler then
                    local found = false
                    put("target random")
                    while true do
                        local line = get()
                        if line:find("Could not find a valid target") then
                            -- Add all NPCs to untargetable list
                            for _, npc in ipairs(GameObj.npcs()) do
                                if not table_contains(untargetable, npc.name) then
                                    untargetable[#untargetable + 1] = npc.name
                                end
                            end
                            untargetable = table_unique(untargetable)
                            save_untargetable(untargetable)
                            break
                        elseif line:find("You are now targeting") then
                            found = true
                            break
                        end
                    end

                    if found then
                        local candidate_spell = find_best_disabler()
                        if candidate_spell then
                            local spell = Spell[candidate_spell.num]
                            if spell.num == 1011 then
                                stop_1011 = true
                                fput("spell active")
                                if spell.active then
                                    fput("renew 1011")
                                else
                                    spell:cast()
                                end
                            else
                                spell:cast()
                            end
                        end
                    end
                end
            end

            -- Wait for child to catch up
            local thisroom = Map.current_room()
            local wait_timeout = os.time() + 5
            wait_until(function()
                return child_in_room()
                    or (os.time() > wait_timeout and table_contains(child_no_wait, Map.current_room()))
                    or thisroom ~= Map.current_room()
            end)

            if child_in_room() then
                child_last_seen = Map.current_room()
            end

            if Map.current_room() ~= place then
                waitrt()
                -- redo inner loop (continue)
            else
                waitrt()
                break
            end
        else
            break
        end
    end

    -- At destination: look for reportee
    local npc = find_reportee()
    if Map.current_room() == place and not npc then
        -- Guard not here, try next dropoff point
        place = Map.find_nearest_room(Map.current_room(), dropoff_points)
        for i = #dropoff_points, 1, -1 do
            if dropoff_points[i] == place then
                table.remove(dropoff_points, i)
            end
        end
    else
        if npc then
            fput("ask #" .. tostring(npc.id) .. " about bounty")
        end
        child_last_seen = nil
        break
    end
end
