--- @revenant-script
--- name: bigshot
--- version: 1.0.0
--- author: Sordal
--- depends: go2 >= 1.0, eloot >= 1.0
--- description: Full hunting automation — combat, navigation, rest, bounty, group

local args_lib = require("lib/args")
local config = require("config")
local area_rooms = require("area_rooms")
local command_check = require("command_check")
local commands = require("commands")
local state_mod = require("state")
local navigation = require("navigation")
local recovery = require("recovery")
local group = require("group")

local state = config.load()
local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

local function show_help()
    respond("Usage: ;bigshot [mode] [options]")
    respond("")
    respond("Modes:")
    respond("  solo               Hunt solo (default)")
    respond("  quick              Hunt in current room only")
    respond("  bounty             Hunt with bounty tracking")
    respond("  single / once      One hunt cycle then exit")
    respond("  head N             Lead group of N followers")
    respond("  tail / follow      Follow group leader")
    respond("  setup              Open settings GUI")
    respond("  profile save NAME  Save settings profile")
    respond("  profile load NAME  Load settings profile")
    respond("  profile list       List saved profiles")
    respond("  display            Show all current settings")
    respond("  help               Show this help")
end

-- === Non-hunting command dispatch ===

if cmd == "help" then
    show_help()
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "display" then
    respond("[bigshot] Current settings:")
    local keys = {}
    for k in pairs(state) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = state[k]
        if type(v) == "table" then
            respond("  " .. k .. " = [" .. table.concat(v, ", ") .. "]")
        else
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "profile" then
    local subcmd = parsed.args[2]
    local name = parsed.args[3]
    if subcmd == "save" and name then
        config.save_profile(state, name)
    elseif subcmd == "load" and name then
        local profile = config.load_profile(name)
        if profile then
            for k, v in pairs(profile) do state[k] = v end
            config.save(state)
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
end

-- === Hunting modes ===

local mode = cmd or "solo"
local single_run = (mode == "single" or mode == "once")
local quick_mode = (mode == "quick")
local bounty_mode = (mode == "bounty")

-- Validate hunting config
if not quick_mode then
    if not state.hunting_room_id or state.hunting_room_id == 0 then
        respond("[bigshot] Error: no hunting room configured. Run ;bigshot setup")
        return
    end
end

-- Build boundary room set
if not quick_mode then
    local room_count = area_rooms.build(state.hunting_room_id, state.hunting_boundaries or {})
    respond("[bigshot] Hunting area: " .. room_count .. " rooms from anchor " .. state.hunting_room_id)
end

-- Select command routine based on targets map
local function find_routine(target)
    if not target then return state.hunting_commands or {} end

    -- Check targets map for creature → letter mapping
    local letter = nil
    for creature_name, l in pairs(state.targets or {}) do
        if target.name:lower():find(creature_name:lower(), 1, true) then
            letter = l:lower()
            break
        end
    end

    if letter and letter ~= "a" then
        local key = "hunting_commands_" .. letter
        if state[key] and #state[key] > 0 then
            return state[key]
        end
    end

    return state.hunting_commands or {}
end

-- === Main attack function ===

local function attack(target)
    if not target then return end

    local routine = find_routine(target)
    if #routine == 0 then
        respond("[bigshot] No commands configured for " .. (target.name or "target"))
        return
    end

    respond("[bigshot] Attacking: " .. (target.name or "unknown") .. " [#" .. (target.id or "?") .. "]")
    commands.execute_routine(routine, target, state)
end

-- === Main hunting loop ===

local function do_hunt()
    respond("[bigshot] Hunting...")

    while true do
        -- Check death
        if dead and dead() then
            respond("[bigshot] Dead — stopping")
            return
        end

        -- Check flee
        local should_flee, flee_reason = state_mod.should_flee(state)
        if should_flee then
            respond("[bigshot] Fleeing: " .. flee_reason)
            navigation.escape(state)
            return
        end

        -- Check rest
        local should_rest, rest_reason = state_mod.should_rest(state)
        if should_rest then
            respond("[bigshot] Need rest: " .. rest_reason)
            return
        end

        -- Find target
        local target = state_mod.find_target(state.targets or {}, state)
        if target then
            attack(target)
            -- Loot after kill
            recovery.loot(state)
        else
            -- No targets in room — wander to next room
            if quick_mode then
                -- In quick mode, stay in this room
                pause(1)
                -- Check if new targets appeared
                target = state_mod.find_target(state.targets or {}, state)
                if not target then
                    respond("[bigshot] No more targets in room")
                    return
                end
            else
                local moved = navigation.wander(state)
                if not moved then
                    respond("[bigshot] Cannot move — stopping")
                    return
                end
            end
        end

        pause(0.3)
    end
end

-- === Cleanup ===

before_dying(function()
    group.cleanup()
    config.save(state)
end)

-- === Pre-hunt setup ===

local function pre_hunt()
    -- Run hunting prep commands
    for _, cmd_str in ipairs(state.hunting_prep_commands or {}) do
        fput(cmd_str)
        pause(0.3)
    end

    -- Travel to hunting grounds
    if not quick_mode then
        -- Travel waypoints if configured
        navigation.travel_waypoints(state.waypoints)
        -- Go to hunting room
        navigation.goto_room(state.hunting_room_id)
    end
end

-- === Main execution ===

if mode == "tail" or mode == "follow" then
    -- Follower mode: listen for leader events
    group.install_listener()
    respond("[bigshot] Follower mode — listening for group commands")

    while true do
        local event = group.next_event()
        if event then
            if event.type == "ATTACK" then
                local target = state_mod.find_target(state.targets or {}, state)
                if target then attack(target) end
            elseif event.type == "FOLLOW_NOW" and event.room_id then
                navigation.goto_room(tonumber(event.room_id))
            elseif event.type == "LOOT" then
                recovery.loot(state)
            elseif event.type == "REST" then
                recovery.rest(state)
            elseif event.type == "GO2" and event.room_id then
                navigation.goto_room(tonumber(event.room_id))
            end
        end
        pause(0.1)
    end

elseif mode == "head" then
    -- Leader mode with group
    local count = tonumber(parsed.args[2]) or 1
    group.set_leader(true)
    respond("[bigshot] Leader mode — waiting for " .. count .. " followers")
    respond("[bigshot] (Group coordination via whisper — followers run ;bigshot tail)")

    -- Hunt loop with group broadcasts
    pre_hunt()
    while true do
        group.broadcast("FOLLOW_NOW", { room_id = Map.current_room() })
        do_hunt()

        group.broadcast("REST")
        recovery.rest(state)

        if not state_mod.ready_to_hunt(state) then
            respond("[bigshot] Not ready to hunt — waiting")
            recovery.wait_for_recovery(state)
        end

        pre_hunt()

        if single_run then
            respond("[bigshot] Single run complete")
            return
        end
    end

else
    -- Solo / quick / bounty / single mode
    respond("[bigshot] Starting in " .. mode .. " mode")

    pre_hunt()

    while true do
        do_hunt()
        recovery.rest(state)

        if single_run then
            respond("[bigshot] Single run complete")
            return
        end

        if not state_mod.ready_to_hunt(state) then
            recovery.wait_for_recovery(state)
        end

        pre_hunt()
    end
end
