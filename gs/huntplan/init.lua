--- huntplan init.lua — entry point and command routing
-- Port of huntplan.lic main flow (lines 3044-3681)
-- Builds optimized hunting areas for bigshot and ebounty.

local data        = require("data")
local excluded    = require("excluded")
local hunting     = require("hunting")
local pathfinding = require("pathfinding")
local settings    = require("settings")
local targets     = require("targets")
local tsp         = require("tsp")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function print_msg(msg)
    respond("[huntplan] " .. msg)
end

local function format_list(list, max_len)
    max_len = max_len or 10
    local out = {}
    for i = 1, math.min(#list, max_len) do
        out[#out + 1] = tostring(list[i])
    end
    local s = table.concat(out, ",")
    if #list > max_len then
        s = s .. "..." .. (#list - max_len) .. " more"
    end
    return s
end

local function set_to_array(s)
    local a = {}
    for k in pairs(s) do a[#a + 1] = k end
    return a
end

local function array_join(arr, sep)
    local parts = {}
    for _, v in ipairs(arr) do parts[#parts + 1] = tostring(v) end
    return table.concat(parts, sep or ",")
end

---------------------------------------------------------------------------
-- ;huntplan help
---------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("------------------------------- Usage --------------------------------")
    respond("")
    respond("  ;huntplan setup     | open settings dialog (text-based)")
    respond("  ;huntplan bounty    | load boundary rooms for current bounty")
    respond("                      | into the *bounty* bigshot profile,")
    respond("                      | load bounty creature into ebounty settings")
    respond("  ;huntplan ice troll | load boundary rooms for creature into")
    respond("                      | the *default* bigshot profile")
    respond("")
    respond("---------------------------------------------------------------------")
    respond("")
end

---------------------------------------------------------------------------
-- ;huntplan setup — text-based settings
---------------------------------------------------------------------------

local function run_setup()
    local s = settings.load_settings()
    respond("")
    respond("[huntplan] Current settings:")
    respond("  default_profile = " .. tostring(s.default_profile))
    respond("  bounty_profile  = " .. tostring(s.bounty_profile))
    respond("  ebounty_slot    = " .. tostring(s.ebounty_slot))
    respond("")
    respond("[huntplan] To change settings, use:")
    respond("  ;huntplan set default_profile <name>")
    respond("  ;huntplan set bounty_profile <name>")
    respond("  ;huntplan set ebounty_slot <a-j>")
    respond("")
end

local function run_set(key, value)
    if not key or not value then
        print_msg("usage: ;huntplan set <key> <value>")
        return
    end
    if not settings.defaults[key] then
        print_msg("unknown setting: " .. key)
        return
    end
    if key == "ebounty_slot" and not settings.valid_ebounty_slot(value) then
        print_msg("invalid ebounty slot: " .. value .. " (must be a-j)")
        return
    end
    local s = settings.load_settings()
    s[key] = value
    settings.save_settings(s)
    print_msg("saved " .. key .. " = " .. value)
end

---------------------------------------------------------------------------
-- Main hunting plan logic
---------------------------------------------------------------------------

local function run_hunting_plan(args)
    local hp_settings = settings.load_settings()

    -- Parse mode and target creature
    local is_bounty = false
    local bounty_town = nil
    local bounty_location = nil
    local target_creature_name = nil
    local has_dangerous_creature_spawned = false
    local is_dangerous_creature_bounty = false

    if args[1] == "bounty" then
        is_bounty = true
        local task = Bounty.task
        if not task then
            print_msg("no active bounty task found")
            return
        end
        bounty_town = task.town
        bounty_location = task.requirements and task.requirements.area or nil
        target_creature_name = task.requirements and task.requirements.creature or nil
        has_dangerous_creature_spawned = (task.type == "dangerous_spawned")
        is_dangerous_creature_bounty = has_dangerous_creature_spawned or (task.type == "dangerous")
    else
        -- Join all args as creature name
        target_creature_name = table.concat(args, " ")
    end

    if not target_creature_name or target_creature_name == "" then
        print_msg("must supply a creature name or 'bounty'")
        return
    end

    target_creature_name = target_creature_name:lower()

    -- Apply level-based exclusions
    excluded.apply_level_exclusions(Char.level)

    -- Build creature index and look up target
    local creature_index = data.build_creature_index()
    local target_creature = creature_index[target_creature_name]

    if not target_creature then
        print_msg("creature not found: " .. target_creature_name)
        return
    end

    if not target_creature.spawn_ids or not next(target_creature.spawn_ids) then
        print_msg("no spawn areas found for: " .. target_creature_name)
        return
    end

    -- Safe room level: max(char_level, creature_level) + 2
    local char_level = Char.level
    local target_level = target_creature.level or char_level
    local safe_room_level = math.max(char_level, target_level) + 2

    -- Build room index from creature/spawn data
    local room_index = hunting.build_room_index(creature_index, data.spawn_index)

    -- Assemble data context for build functions
    local ctx = {
        is_bounty = is_bounty,
        bounty_location = bounty_location,
        has_dangerous_creature_spawned = has_dangerous_creature_spawned,
        target_creature = target_creature,
        safe_room_level = safe_room_level,
        room_index = room_index,
        spawn_index = data.spawn_index,
    }

    -- Build hunting plan (5-step pipeline)
    local hunting_area = hunting.build_hunting_plan(target_creature, ctx)

    if not hunting_area then
        print_msg("failed to build hunting area")
        return
    end

    local hunting_rids = set_to_array(hunting_area.hunting_rids)

    if #hunting_rids == 0 then
        print_msg("failed to build hunting area")
        return
    end

    local starting_rid = hunting_area.nearest_rid
    if not starting_rid then
        print_msg("hunting area not reachable")
        return
    end

    -- Get boundary rooms
    local boundary_set = pathfinding.get_boundaries_from_room_ids(hunting_area.hunting_rids)
    local hunting_boundary_rids = set_to_array(boundary_set)

    -- Build shortest route (TSP)
    local shortest_route = tsp.approximate_shortest_route(hunting_rids)
    if shortest_route then
        -- Rotate so starting_rid is first
        local start_idx = nil
        for i, rid in ipairs(shortest_route) do
            if rid == starting_rid then start_idx = i; break end
        end
        if start_idx and start_idx > 1 then
            local rotated = {}
            for i = start_idx, #shortest_route do
                rotated[#rotated + 1] = shortest_route[i]
            end
            for i = 1, start_idx - 1 do
                rotated[#rotated + 1] = shortest_route[i]
            end
            shortest_route = rotated
        end
    end

    -- Classify targets
    local kill_targets, flee_targets, safe_targets = targets.classify_targets(
        hunting_area, target_creature, room_index, creature_index,
        hunting_rids, is_bounty, is_dangerous_creature_bounty,
        has_dangerous_creature_spawned, char_level,
        hunting.find_creatures_in_vicinity
    )

    -- Format for bigshot
    local bs_kill_targets = targets.format_kill_targets_for_bigshot(kill_targets)

    -- Find resting room
    local resting_rid = settings.find_resting_room(bounty_town, starting_rid)

    -- Build results
    local spawn_rids = set_to_array(hunting_area.spawn_rids)
    local hunting_boundary_s = array_join(hunting_boundary_rids)
    local flee_targets_s = array_join(flee_targets)
    local safe_targets_s = array_join(safe_targets)
    local bs_targets_s = array_join(bs_kill_targets)

    -- Determine bigshot profile name
    local bigshot_profile = is_bounty and hp_settings.bounty_profile or hp_settings.default_profile

    -- Write bigshot profile
    local profile_data = {
        resting_room_id    = tostring(resting_rid or ""),
        hunting_room_id    = tostring(starting_rid),
        hunting_boundaries = hunting_boundary_s,
        targets            = bs_targets_s,
        always_flee_from   = flee_targets_s,
        invalid_targets    = safe_targets_s,
    }
    settings.write_bigshot_profile(profile_data, bigshot_profile)
    print_msg("saved bigshot profile '" .. bigshot_profile .. "'")

    -- Write ebounty settings if bounty mode
    if is_bounty then
        local slot = hp_settings.ebounty_slot
        if settings.valid_ebounty_slot(slot) then
            settings.write_ebounty_slot(slot, target_creature_name, bigshot_profile)
            print_msg("saved ebounty settings in slot '" .. slot .. "'")
        end
    end

    -- Store results in UserVars for cross-script access
    if UserVars then
        UserVars.hp = UserVars.hp or {}
        UserVars.hp.success = 1
        UserVars.hp.kill_targets = array_join(kill_targets)
        UserVars.hp.hunting_rids = array_join(hunting_rids)
        UserVars.hp.spawn_rids = array_join(spawn_rids)
        UserVars.hp.hunting_route = shortest_route and array_join(shortest_route) or ""
    end

    -- Print results
    respond("")
    if bounty_town then respond("  Bounty Town: " .. bounty_town) end
    if bounty_location then respond("  Bounty Location: " .. bounty_location) end
    respond("  Primary Target: " .. target_creature_name)
    respond("  Kill Targets: " .. array_join(kill_targets))
    if safe_targets_s ~= "" then respond("  Safe Targets: " .. safe_targets_s) end
    if flee_targets_s ~= "" then respond("  Flee Targets: " .. flee_targets_s) end
    respond("  Resting Room: " .. tostring(resting_rid or "N/A"))
    respond("  Starting Room: " .. tostring(starting_rid))
    respond("  Boundary Rooms: " .. hunting_boundary_s)
    respond("  Spawn Rooms: " .. format_list(spawn_rids))
    respond("  Hunting Rooms: " .. format_list(hunting_rids))
    if shortest_route then
        respond("  Shortest Route: " .. format_list(shortest_route))
    end
    respond("")
end

---------------------------------------------------------------------------
-- Command routing
---------------------------------------------------------------------------

local args = Script.args or {}

if #args == 0 or args[1] == "help" then
    show_help()
elseif args[1] == "setup" then
    run_setup()
elseif args[1] == "set" then
    run_set(args[2], args[3])
else
    run_hunting_plan(args)
end
