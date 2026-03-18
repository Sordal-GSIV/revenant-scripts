--- @revenant-script
--- name: bigshot
--- version: 5.12.1
--- author: elanthia-online
--- contributors: SpiffyJr, Tillmen, Kalros, Hazado, Tysong, Athias, Falicor, Deysh, Nisugi
--- depends: go2 >= 1.0, eloot >= 1.0
--- description: Full hunting automation — combat, navigation, rest, bounty, group
--- game: gs
--- @lic-audit: validated 2026-03-18
---
--- Port of bigshot.lic v5.12.1 from Elanthia-Online
--- Setup Instructions: https://gswiki.play.net/Script_Bigshot
--- Full Changelog: https://gswiki.play.net/Script_Bigshot/Changelog
---
--- Changelog (from Lich5):
---   v5.12.1 (2026-02-08) — fix for cast_signs/cmd_rapid double casting
---   v5.12.0 (2026-02-08) — add ES/EB/EC/ED effect command checks
---   v5.11.4 (2026-01-14) — splashy, essence, unhide leader, ATTACK event, GROUP OPEN
---   v5.11.3 (2026-01-12) — follower rejoin/id bugfixes
---   v5.11.2 (2026-01-09) — optimize get_valid_neighbors
---   v5.11.1 (2026-01-09) — bugfix in sort_npcs
---   v5.11.0 (2025-11-29) — boon creatures, dead group members, refactors
---   v5.10.0 (2025-10-31) — BSAreaRooms, MA leader, head/tail order, gemstone support
---   Full prior changelog: https://gswiki.play.net/Script_Bigshot/Changelog

local config = require("config")
local area_rooms = require("area_rooms")
local command_check = require("command_check")
local commands = require("commands")
local state_mod = require("state")
local navigation = require("navigation")
local recovery = require("recovery")
local group = require("group")
local combat_monitor = require("combat_monitor")

---------------------------------------------------------------------------
-- Parse arguments
---------------------------------------------------------------------------

local raw_input = Script.vars[0] or ""
local args = {}
for word in raw_input:gmatch("%S+") do
    args[#args + 1] = word:lower()
end
local cmd = args[1]

---------------------------------------------------------------------------
-- Load configuration
---------------------------------------------------------------------------

local bstate = config.load()

-- Runtime state (not persisted)
bstate._quick_mode = false
bstate._single_mode = false
bstate._bounty_mode = false
bstate._sneaky_mode = false
bstate._bandits = false
bstate._ambusher_here = false
bstate._flee = false
bstate._should_rest = false
bstate._rest_reason = nil
bstate._reaction = nil
bstate._arcane_reflex = false
bstate._rooted = false
bstate._bond_return = false
bstate._cast902 = false
bstate._cast411 = false
bstate._overkill_counter = 0
bstate._lte_boost_counter = 0
bstate._unarmed_tier = 1
bstate._unarmed_followup = false
bstate._unarmed_followup_attack = ""
bstate._aim_index = 0
bstate._ambush_index = 0
bstate._archery_aim_index = 0
bstate._archery_stuck = {}
bstate._archery_location = nil
bstate._smite_list = {}
bstate._703_list = {}
bstate._1614_list = {}
bstate._bless_needed = {}
bstate._swift_justice = 0
bstate._dislodge_target = nil
bstate._dislodge_location = {}
bstate._commands_registry = {}
bstate._boon_cache = {}
bstate._correct_percent_mind = 0

-- Parse compound settings into tables
bstate.hunting_commands = config.parse_commands(bstate.hunting_commands)
bstate.hunting_commands_b = config.parse_commands(bstate.hunting_commands_b)
bstate.hunting_commands_c = config.parse_commands(bstate.hunting_commands_c)
bstate.hunting_commands_d = config.parse_commands(bstate.hunting_commands_d)
bstate.hunting_commands_e = config.parse_commands(bstate.hunting_commands_e)
bstate.hunting_commands_f = config.parse_commands(bstate.hunting_commands_f)
bstate.hunting_commands_g = config.parse_commands(bstate.hunting_commands_g)
bstate.hunting_commands_h = config.parse_commands(bstate.hunting_commands_h)
bstate.hunting_commands_i = config.parse_commands(bstate.hunting_commands_i)
bstate.hunting_commands_j = config.parse_commands(bstate.hunting_commands_j)
bstate.disable_commands = config.parse_commands(bstate.disable_commands)
bstate.quick_commands = config.parse_commands(bstate.quick_commands)
bstate.targets = config.parse_targets(bstate.targets)
bstate.quickhunt_targets = config.parse_targets(bstate.quickhunt_targets)
bstate.signs = config.parse_csv(bstate.signs)
bstate.hunting_boundaries = config.parse_csv(bstate.hunting_boundaries)
bstate.rallypoint_room_ids = config.parse_csv(bstate.rallypoint_room_ids)
bstate.return_waypoint_ids = config.parse_csv(bstate.return_waypoint_ids)
bstate.invalid_targets = config.parse_csv(bstate.invalid_targets)
bstate.always_flee_from = config.parse_csv(bstate.always_flee_from)
bstate.hunting_prep_commands = config.parse_lines(bstate.hunting_prep_commands)
bstate.resting_commands = config.parse_lines(bstate.resting_commands)
bstate.hunting_scripts = config.parse_lines(bstate.hunting_scripts)
bstate.resting_scripts = config.parse_lines(bstate.resting_scripts)
bstate.aim = config.parse_csv(bstate.aim)
bstate.never_loot = config.parse_csv(bstate.never_loot)

-- Convert numeric thresholds
bstate.fried = config.parse_int(bstate.fried, 100)
bstate.overkill = config.parse_int(bstate.overkill, 0)
bstate.lte_boost = config.parse_int(bstate.lte_boost, 0)
bstate.oom = config.parse_int(bstate.oom, 0)
bstate.encumbered = config.parse_int(bstate.encumbered, 101)
bstate.flee_count = config.parse_int(bstate.flee_count, 100)
bstate.wander_wait = config.parse_float(bstate.wander_wait, 0.3)
bstate.rest_till_exp = config.parse_int(bstate.rest_till_exp, 0)
bstate.rest_till_mana = config.parse_int(bstate.rest_till_mana, 0)
bstate.rest_till_spirit = config.parse_int(bstate.rest_till_spirit, 0)
bstate.rest_till_percentstamina = config.parse_int(bstate.rest_till_percentstamina, 0)

---------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------

local function show_help()
    respond("Bigshot v5.12.1 — GemStone IV Hunting Automation")
    respond("")
    respond("Usage: ;bigshot [mode] [options]")
    respond("")
    respond("Modes:")
    respond("  (blank) / solo      Hunt solo (default)")
    respond("  quick               Hunt in current room only")
    respond("  bounty              Hunt with bounty tracking")
    respond("  single / once       One hunt cycle then exit")
    respond("  head [N]            Lead group of N followers")
    respond("  tail / follow       Follow group leader")
    respond("  setup               Open settings GUI")
    respond("  profile save NAME   Save settings profile")
    respond("  profile load NAME   Load settings profile")
    respond("  profile list        List saved profiles")
    respond("  display / list      Show all current settings")
    respond("  debug [opts]        Toggle debug options")
    respond("  test METHOD [args]  Test a specific method")
    respond("  help                Show this help")
end

---------------------------------------------------------------------------
-- Debug command
---------------------------------------------------------------------------

local function handle_debug()
    local subcmd = args[2]
    if not subcmd or subcmd == "help" then
        respond("[bigshot] Debug Options:")
        respond("  ;bigshot debug all true/false    Toggle all debug")
        respond("  ;bigshot debug combat true/false Combat logging")
        respond("  ;bigshot debug commands true/false Command logging")
        respond("  ;bigshot debug status true/false  Status logging")
        respond("  ;bigshot debug system true/false  System logging")
        respond("  ;bigshot debug check             Show current settings")
    elseif subcmd == "check" then
        respond("[bigshot] Debug settings:")
        respond("  combat   = " .. tostring(bstate.debug_combat))
        respond("  commands = " .. tostring(bstate.debug_commands))
        respond("  status   = " .. tostring(bstate.debug_status))
        respond("  system   = " .. tostring(bstate.debug_system))
    else
        local value = (args[#args] == "true")
        if subcmd == "all" then
            bstate.debug_combat = value
            bstate.debug_commands = value
            bstate.debug_status = value
            bstate.debug_system = value
        elseif subcmd == "combat" then bstate.debug_combat = value
        elseif subcmd == "commands" then bstate.debug_commands = value
        elseif subcmd == "status" then bstate.debug_status = value
        elseif subcmd == "system" then bstate.debug_system = value
        end
        config.save(bstate)
        respond("[bigshot] Debug updated. Run ;bigshot debug check to verify.")
    end
end

---------------------------------------------------------------------------
-- Non-hunting command dispatch
---------------------------------------------------------------------------

if cmd == "help" then
    show_help()
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(bstate)
    return

elseif cmd == "display" or cmd == "list" then
    respond("[bigshot] Current settings:")
    local keys = {}
    for k in pairs(bstate) do
        if not k:find("^_") then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = bstate[k]
        if type(v) == "table" then
            respond("  " .. k .. " = [" .. table.concat(v, ", ") .. "]")
        else
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "profile" then
    local subcmd = args[2]
    local name = args[3]
    if subcmd == "save" and name then
        config.save_profile(bstate, name)
    elseif subcmd == "load" and name then
        local profile = config.load_profile(name)
        if profile then
            for k, v in pairs(profile) do bstate[k] = v end
            config.save(bstate)
            respond("[bigshot] Loaded and saved profile: " .. name)
        end
    elseif subcmd == "list" then
        local profiles = config.list_profiles()
        if #profiles == 0 then
            respond("[bigshot] No saved profiles")
        else
            respond("[bigshot] Saved profiles:")
            for _, p in ipairs(profiles) do respond("  " .. p) end
        end
    else
        respond("Usage: ;bigshot profile <save|load|list> [name]")
    end
    return

elseif cmd == "debug" then
    handle_debug()
    return
end

---------------------------------------------------------------------------
-- Hunting modes setup
---------------------------------------------------------------------------

local mode = cmd or "solo"

-- Detect mode from args
if mode == "single" or mode == "once" then
    bstate._single_mode = true
    mode = "solo"
elseif mode == "quick" then
    bstate._quick_mode = true
elseif mode == "bounty" then
    bstate._bounty_mode = true
end

-- Ranger tracking creature from additional args
for i = 2, #args do
    local word = args[i]
    if word and word ~= "" and not tonumber(word) then
        bstate._tracking_creature = word
    end
end

---------------------------------------------------------------------------
-- Validate hunting config
---------------------------------------------------------------------------

if not bstate._quick_mode and mode ~= "head" and mode ~= "tail" and mode ~= "follow" then
    local hunt_id = tonumber(bstate.hunting_room_id)
    if not hunt_id or hunt_id == 0 then
        respond("[bigshot] Error: no hunting room configured. Run ;bigshot setup")
        return
    end
end

---------------------------------------------------------------------------
-- Build boundary room set
---------------------------------------------------------------------------

if not bstate._quick_mode then
    local hunt_id = tonumber(bstate.hunting_room_id) or 0
    if hunt_id > 0 then
        local room_count = area_rooms.build(hunt_id, bstate.hunting_boundaries)
        if room_count == 0 then
            return -- boundary_break already displayed error
        end
        respond("[bigshot] Hunting area: " .. room_count .. " rooms from anchor " .. hunt_id)
    end
end

---------------------------------------------------------------------------
-- Cleanup on exit
---------------------------------------------------------------------------

before_dying(function()
    combat_monitor.stop()
    group.cleanup()
    recovery.stop_hunting_scripts(bstate)
    if bstate._sneaky_mode then
        fput("movement autosneak off")
    end
    config.save(bstate)
end)

---------------------------------------------------------------------------
-- Interaction monitor (GM/player interaction detection)
---------------------------------------------------------------------------

local function install_interaction_monitor()
    if not bstate.monitor_interaction then return end

    local safe_patterns = config.parse_pipe(bstate.monitor_safe_strings or "")
    local watch_patterns = config.parse_pipe(bstate.monitor_strings or "")

    DownstreamHook.add("bigshot_interaction", function(line)
        -- Check safe strings first (whitelist)
        for _, safe in ipairs(safe_patterns) do
            if safe ~= "" and line:find(safe) then return line end
        end
        -- Check watch strings (triggers)
        for _, pattern in ipairs(watch_patterns) do
            if pattern ~= "" and line:find(pattern) then
                respond("[bigshot] INTERACTION DETECTED: " .. line:sub(1, 80))
                -- Could pause script here based on dead_man_switch
                if bstate.dead_man_switch then
                    respond("[bigshot] Dead man switch triggered — pausing")
                    pause(999999)
                end
                break
            end
        end
        return line
    end)

    before_dying(function() DownstreamHook.remove("bigshot_interaction") end)
end

---------------------------------------------------------------------------
-- Main attack function
---------------------------------------------------------------------------

local function attack(target)
    if not target then return end

    local routine = state_mod.find_routine(target, bstate)
    if #routine == 0 then
        respond("[bigshot] No commands configured for " .. (target.name or "target"))
        return
    end

    -- Target the NPC
    fput("target #" .. target.id)

    -- Change to hunting stance
    commands.change_stance(bstate.hunting_stance, bstate)

    -- Execute command routine
    commands.execute_routine(routine, target, bstate)

    -- Loot if needed
    if state_mod.need_to_loot(bstate, false) then
        recovery.loot(bstate)
    end
end

---------------------------------------------------------------------------
-- Main hunting loop
---------------------------------------------------------------------------

local function do_hunt()
    recovery.start_watch()
    respond("[bigshot] Hunting...")

    local just_entered = true
    local last_target_time = os.time()

    while true do
        -- Check death
        if dead and dead() then
            respond("[bigshot] Dead — stopping")
            return
        end

        -- Check flee
        local should_flee, flee_reason = state_mod.should_flee(bstate, just_entered)
        if should_flee then
            respond("[bigshot] Fleeing: " .. (flee_reason or "unknown"))
            -- Move to a random neighbor (away)
            navigation.wander(bstate)
            just_entered = true
            goto continue_hunt
        end

        -- Check rest
        local should_rest, rest_reason = state_mod.should_rest(bstate)
        if should_rest then
            respond("[bigshot] Need rest: " .. (rest_reason or "unknown"))
            return
        end

        -- Also check commands module rest flag
        if commands.should_rest() then
            return
        end

        -- Find target
        local target = state_mod.find_target(bstate, just_entered)
        if target then
            just_entered = false
            last_target_time = os.time()

            -- Check priority (switch if higher priority available)
            local better = state_mod.priority_target(target, bstate)
            if better then target = better end

            -- Attack
            attack(target)

            -- Wrack if available
            recovery.wrack(bstate)
        else
            -- No targets in room
            if bstate._quick_mode then
                -- In quick mode, wait briefly for new spawns
                pause(1)
                target = state_mod.find_target(bstate, false)
                if not target then
                    respond("[bigshot] No more targets in room")
                    return
                end
            else
                -- Wander to next room
                local _, moved = navigation.wander(bstate)
                if not moved then
                    respond("[bigshot] Cannot move — returning to anchor")
                    navigation.goto_room(area_rooms.get_anchor())
                end
                just_entered = true

                -- Clear room-specific registries
                command_check.clear_room_registry(bstate)
                state_mod.reset_variables(bstate, true)
            end
        end

        pause(0.3)
        ::continue_hunt::
    end
end

---------------------------------------------------------------------------
-- === Main Execution ===
---------------------------------------------------------------------------

if mode == "tail" or mode == "follow" then
    -- ========== FOLLOWER MODE ==========
    group.install_listener()
    install_interaction_monitor()
    combat_monitor.start(Script.name, bstate)
    respond("[bigshot] Follower mode — listening for group commands")

    while true do
        local event = group.wait_event(5)
        if event and not group.event_stale(event) then
            local etype = event.type

            if etype == "ATTACK" then
                local target = state_mod.find_target(bstate, false)
                if target then attack(target) end

            elseif etype == "FOLLOW_NOW" and event.room_id then
                navigation.goto_room(tonumber(event.room_id))

            elseif etype == "LOOT" then
                recovery.loot(bstate)

            elseif etype == "HUNTING_PREP_COMMANDS" then
                recovery.hunting_prep(bstate)

            elseif etype == "CAST_SIGNS" then
                recovery.cast_signs(bstate)

            elseif etype == "HUNTING_SCRIPTS_START" then
                recovery.start_hunting_scripts(bstate)

            elseif etype == "HUNTING_SCRIPTS_STOP" then
                recovery.stop_hunting_scripts(bstate)

            elseif etype == "RESTING_SCRIPTS_START" then
                recovery.start_resting_scripts(bstate)

            elseif etype == "RESTING_PREP_COMMANDS" then
                recovery.resting_prep(bstate)

            elseif etype == "PREP_REST" then
                recovery.prepare_for_movement(bstate)

            elseif etype == "FOG_RETURN" then
                navigation.fog_return(bstate)

            elseif etype == "GO2_WAYPOINTS" then
                navigation.travel_waypoints(bstate.return_waypoint_ids)

            elseif etype == "GO2_RESTING_ROOM" then
                local rest_id = tonumber(bstate.resting_room_id)
                if rest_id and rest_id > 0 then
                    navigation.goto_room_loop(rest_id)
                end

            elseif etype == "GO2_RALLY_ROOM" then
                navigation.travel_waypoints(bstate.rallypoint_room_ids)

            elseif etype == "GO2_HUNTING_ROOM" then
                local hunt_id = tonumber(bstate.hunting_room_id)
                if hunt_id and hunt_id > 0 then
                    navigation.goto_room_loop(hunt_id)
                end

            elseif etype == "DISPLAY_WATCH" then
                recovery.display_watch()

            elseif etype == "START_WATCH" then
                recovery.start_watch()

            elseif etype == "STOP_WATCH" then
                recovery.stop_watch()

            elseif etype == "HUNT_MONITOR_START" then
                combat_monitor.start(Script.name, bstate)

            elseif etype == "HUNT_MONITOR_STOP" then
                combat_monitor.stop()

            elseif etype == "CUSTOM_PUT" and event.cmd then
                fput(event.cmd)

            elseif etype == "CUSTOM_CMD" and event.cmd then
                commands.bs_put(event.cmd, bstate)

            elseif etype == "CHECK_MIND" then
                state_mod.check_mind(bstate)

            elseif etype == "SINGLE_STOP" then
                respond("[bigshot] Single run complete (follower)")
                return

            elseif etype == "LEAVE_GROUP" then
                fput("leave group")
                break

            elseif etype == "FOLLOWER_OVERKILL" then
                bstate._overkill_counter = (bstate._overkill_counter or 0) + 1
            end
        end
    end

elseif mode == "head" then
    -- ========== LEADER MODE ==========
    local count = tonumber(args[2]) or 1
    group.set_leader(true, count)
    install_interaction_monitor()
    combat_monitor.start(Script.name, bstate)
    respond("[bigshot] Leader mode — group of " .. (count + 1))

    -- Open group for followers
    group.group_open()
    respond("[bigshot] Waiting for " .. count .. " followers...")
    respond("[bigshot] Followers should run: ;bigshot tail")

    -- Wait for followers to join
    pause(10)

    -- Main leader hunt loop
    recovery.pre_hunt(bstate)
    group.broadcast("HUNTING_PREP_COMMANDS")
    group.broadcast("CAST_SIGNS")
    group.broadcast("HUNTING_SCRIPTS_START")
    group.broadcast("HUNT_MONITOR_START")

    while true do
        group.broadcast("FOLLOW_NOW", { room_id = Map.current_room() })
        group.broadcast("START_WATCH")

        do_hunt()

        -- Rest cycle
        group.broadcast("HUNT_MONITOR_STOP")
        group.broadcast("HUNTING_SCRIPTS_STOP")
        group.broadcast("PREP_REST")

        local rest_result = recovery.rest(bstate)

        if bstate.independent_return then
            group.broadcast("FOG_RETURN")
            group.broadcast("GO2_WAYPOINTS")
            group.broadcast("GO2_RESTING_ROOM")
        end

        group.broadcast("RESTING_PREP_COMMANDS")
        group.broadcast("RESTING_SCRIPTS_START")
        group.broadcast("DISPLAY_WATCH")

        if bstate._single_mode then
            group.broadcast("SINGLE_STOP")
            respond("[bigshot] Single run complete")
            return
        end

        if rest_result == "bounty_done" then
            group.broadcast("SINGLE_STOP")
            return
        end

        -- Wait for recovery
        if not state_mod.ready_to_hunt(bstate) then
            recovery.wait_for_recovery(bstate)
        end

        recovery.stop_resting_scripts(bstate)
        recovery.pre_hunt(bstate)
        group.broadcast("HUNTING_PREP_COMMANDS")
        group.broadcast("CAST_SIGNS")
        group.broadcast("HUNTING_SCRIPTS_START")
        group.broadcast("HUNT_MONITOR_START")
    end

else
    -- ========== SOLO / QUICK / BOUNTY / SINGLE ==========
    install_interaction_monitor()
    combat_monitor.start(Script.name, bstate)
    respond("[bigshot] Starting in " .. mode .. " mode")

    recovery.pre_hunt(bstate)

    while true do
        do_hunt()

        local rest_result = recovery.rest(bstate)

        if bstate._single_mode then
            respond("[bigshot] Single run complete")
            return
        end

        if rest_result == "bounty_done" then
            return
        end

        if not state_mod.ready_to_hunt(bstate) then
            recovery.wait_for_recovery(bstate)
        end

        recovery.stop_resting_scripts(bstate)
        recovery.pre_hunt(bstate)
    end
end
