--- huntplan hunting.lua — core hunting area builder
-- Port of huntplan.lic lines 2355-2892
-- Builds RoomData, SpawnRoom, HuntingArea structures and the 5-step pipeline.

local pathfinding = require("pathfinding")

local M = {}

---------------------------------------------------------------------------
-- Obvious directions for wander/vicinity checks
---------------------------------------------------------------------------

local OBVIOUS_DIRS = {
    n = true, ne = true, e = true, se = true,
    s = true, sw = true, w = true, nw = true,
    u = true, d = true, out = true,
}

--- Check if a direction string is "obvious" — either a cardinal/simple dir,
--- or a short StringProc (< 30 chars) that contains one of those directions.
local function is_obvious_dir(dir)
    if OBVIOUS_DIRS[dir] then return true end
    if type(dir) == "string" and #dir < 30 then
        for d in pairs(OBVIOUS_DIRS) do
            if dir:find(d, 1, true) then return true end
        end
    end
    return false
end

--- Check if a room has a 'node' or 'supernode' tag.
local function is_node_room(rid)
    local tags = Map.tags(rid)
    if not tags then return false end
    for _, tag in ipairs(tags) do
        if tag == "node" or tag == "supernode" then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- merge_creature_level helper
---------------------------------------------------------------------------

local function merge_creature_level(t, level)
    if level and (t.max_creature_level == nil or level > t.max_creature_level) then
        t.max_creature_level = level
    end
end

---------------------------------------------------------------------------
-- RoomData
---------------------------------------------------------------------------

function M.new_room_data()
    return {
        spawn_ids = {},
        creature_names = {},
        max_creature_level = nil,
        merge_creature_level = merge_creature_level,
    }
end

---------------------------------------------------------------------------
-- SpawnRoom
---------------------------------------------------------------------------

function M.new_spawn_room(rid, max_creature_level)
    local sr = {
        rid = rid,
        max_creature_level = max_creature_level,
        hunting_rids = { [rid] = true },
        reachable_rids = { [rid] = true },
        merge_creature_level = merge_creature_level,
    }
    return sr
end

---------------------------------------------------------------------------
-- HuntingArea
---------------------------------------------------------------------------

function M.new_hunting_area()
    return {
        spawn_rooms = {},
        spawn_rids = {},
        hunting_rids = {},
        reachable_rids = {},
        max_creature_level = nil,
        nearest_rid = nil,
        travel_time = nil,
        merge_creature_level = merge_creature_level,
    }
end

---------------------------------------------------------------------------
-- insert_spawn_room — add a SpawnRoom into a HuntingArea
---------------------------------------------------------------------------

function M.insert_spawn_room(hunting_area, spawn_room)
    hunting_area.spawn_rooms[#hunting_area.spawn_rooms + 1] = spawn_room
    hunting_area.spawn_rids[spawn_room.rid] = true

    for rid in pairs(spawn_room.hunting_rids) do
        hunting_area.hunting_rids[rid] = true
    end
    for rid in pairs(spawn_room.reachable_rids) do
        hunting_area.reachable_rids[rid] = true
    end

    merge_creature_level(hunting_area, spawn_room.max_creature_level)
end

---------------------------------------------------------------------------
-- insert_hunting_area — merge another HuntingArea into this one
---------------------------------------------------------------------------

function M.insert_hunting_area(hunting_area, other)
    for _, sr in ipairs(other.spawn_rooms) do
        hunting_area.spawn_rooms[#hunting_area.spawn_rooms + 1] = sr
        hunting_area.spawn_rids[sr.rid] = true
    end
    for rid in pairs(other.hunting_rids) do
        hunting_area.hunting_rids[rid] = true
    end
    for rid in pairs(other.reachable_rids) do
        hunting_area.reachable_rids[rid] = true
    end
    merge_creature_level(hunting_area, other.max_creature_level)
end

---------------------------------------------------------------------------
-- insert_hunting_path — add path rooms to hunting_rids, merge levels
---------------------------------------------------------------------------

function M.insert_hunting_path(hunting_area, path, room_index)
    if not path then return end
    for _, rid in ipairs(path) do
        hunting_area.hunting_rids[rid] = true
        if room_index and room_index[rid] then
            merge_creature_level(hunting_area, room_index[rid].max_creature_level)
        end
    end
end

---------------------------------------------------------------------------
-- build_reachable_rids — BFS outward from spawn_room.rid
---------------------------------------------------------------------------

function M.build_reachable_rids(spawn_room, wander_radius, room_index, target_creature_level, safe_room_level)
    local queue = { { rid = spawn_room.rid, depth = 0 } }
    local visited = { [spawn_room.rid] = true }

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local cur_rid = node.rid
        local cur_depth = node.depth

        if cur_depth >= wander_radius then goto continue end

        local exits = Map.exits(cur_rid) or {}
        for dir, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end

            if not dst then goto next_exit end
            if visited[dst] then goto next_exit end
            if spawn_room.reachable_rids[dst] then goto next_exit end

            -- Check StringProc nav: Map.timeto returns a function for StringProcs
            local nav = Map.timeto(cur_rid, dir)
            if type(nav) == "function" then
                local ok, result = pcall(nav)
                if not ok or not result then goto next_exit end
            end

            -- Level safety check
            if room_index and room_index[dst] and safe_room_level then
                local adj_level = room_index[dst].max_creature_level
                if adj_level and adj_level > safe_room_level then
                    -- Allow if adj room matches spawn room's level or target level is nil
                    if target_creature_level ~= nil and spawn_room.max_creature_level ~= nil then
                        if adj_level ~= spawn_room.max_creature_level then
                            goto next_exit
                        end
                    end
                end
            end

            visited[dst] = true
            spawn_room.reachable_rids[dst] = true
            queue[#queue + 1] = { rid = dst, depth = cur_depth + 1 }

            ::next_exit::
        end
        ::continue::
    end
end

---------------------------------------------------------------------------
-- build_wander_rids — like build_reachable_rids but for hunting_rids
---------------------------------------------------------------------------

function M.build_wander_rids(spawn_room, wander_radius, valid_spawn_ids, room_index, target_creature_level, safe_room_level)
    local queue = { { rid = spawn_room.rid, depth = 0 } }
    local visited = { [spawn_room.rid] = true }

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local cur_rid = node.rid
        local cur_depth = node.depth

        if cur_depth >= wander_radius then goto continue end

        local exits = Map.exits(cur_rid) or {}
        for dir, adj in pairs(exits) do
            -- Only follow obvious directions
            if not is_obvious_dir(dir) then goto next_exit end

            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end

            if not dst then goto next_exit end
            if visited[dst] then goto next_exit end

            -- Skip node/supernode rooms
            if is_node_room(dst) then goto next_exit end

            -- Check return path exists (adj has exit back to current)
            local adj_exits = Map.exits(dst) or {}
            local has_return = false
            for _, rev_adj in pairs(adj_exits) do
                local rev_dst
                if type(rev_adj) == "function" then
                    local ok, result = pcall(rev_adj)
                    if ok and result then rev_dst = result end
                elseif type(rev_adj) == "number" then
                    rev_dst = rev_adj
                end
                if rev_dst == cur_rid then
                    has_return = true
                    break
                end
            end
            if not has_return then goto next_exit end

            -- Check valid_spawn_ids filter
            if valid_spawn_ids and room_index and room_index[dst] then
                local room_data = room_index[dst]
                local has_invalid = false
                for sid in pairs(room_data.spawn_ids) do
                    if not valid_spawn_ids[sid] then
                        has_invalid = true
                        break
                    end
                end
                if has_invalid then goto next_exit end
            end

            -- Level safety check
            if room_index and room_index[dst] and safe_room_level then
                local adj_level = room_index[dst].max_creature_level
                if adj_level and adj_level > safe_room_level then
                    if target_creature_level ~= nil and spawn_room.max_creature_level ~= nil then
                        if adj_level ~= spawn_room.max_creature_level then
                            goto next_exit
                        end
                    end
                end
            end

            visited[dst] = true
            spawn_room.hunting_rids[dst] = true

            -- Merge creature level from room_index
            if room_index and room_index[dst] then
                merge_creature_level(spawn_room, room_index[dst].max_creature_level)
            end

            queue[#queue + 1] = { rid = dst, depth = cur_depth + 1 }

            ::next_exit::
        end
        ::continue::
    end
end

---------------------------------------------------------------------------
-- find_creatures_in_vicinity — BFS from hunting_rids collecting names
---------------------------------------------------------------------------

function M.find_creatures_in_vicinity(hunting_rids_set, wander_radius, room_index)
    local creature_names = {}
    local visited = {}

    -- Seed with all hunting rids
    local queue = {}
    for rid in pairs(hunting_rids_set) do
        visited[rid] = true
        queue[#queue + 1] = { rid = rid, depth = 0 }
        -- Collect creatures from seed rooms too
        if room_index[rid] then
            for name in pairs(room_index[rid].creature_names) do
                creature_names[name] = true
            end
        end
    end

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local cur_rid = node.rid
        local cur_depth = node.depth

        if cur_depth >= wander_radius then goto continue end

        local exits = Map.exits(cur_rid) or {}
        for dir, adj in pairs(exits) do
            -- Only follow obvious directions
            if not is_obvious_dir(dir) then goto next_exit end

            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end

            if not dst then goto next_exit end
            if visited[dst] then goto next_exit end

            -- Skip node/supernode rooms
            if is_node_room(dst) then goto next_exit end

            visited[dst] = true

            -- Collect creature names
            if room_index[dst] then
                for name in pairs(room_index[dst].creature_names) do
                    creature_names[name] = true
                end
            end

            queue[#queue + 1] = { rid = dst, depth = cur_depth + 1 }

            ::next_exit::
        end
        ::continue::
    end

    return creature_names
end

---------------------------------------------------------------------------
-- build_room_index — {[rid]=RoomData} from creature_index and spawn_index
---------------------------------------------------------------------------

function M.build_room_index(creature_index, spawn_index)
    local idx = {}

    for _, creature in pairs(creature_index) do
        for _, sid in ipairs(creature.spawn_ids) do
            local rooms = spawn_index[sid]
            if rooms then
                for _, rid in ipairs(rooms) do
                    if not idx[rid] then
                        idx[rid] = M.new_room_data()
                    end
                    local rd = idx[rid]
                    rd.spawn_ids[sid] = true
                    for _, name in ipairs(creature.names) do
                        rd.creature_names[name] = true
                    end
                    merge_creature_level(rd, creature.level)
                end
            end
        end
    end

    return idx
end

---------------------------------------------------------------------------
-- build_spawn_locales — group spawn rooms into locale arrays
---------------------------------------------------------------------------

function M.build_spawn_locales(target_creature, data)
    local spawn_locales = {}

    for _, sid in ipairs(target_creature.spawn_ids) do
        local rooms = data.spawn_index[sid]
        if not rooms then goto next_sid end

        local locale = {}
        for _, rid in ipairs(rooms) do
            -- Bounty location check
            if data.is_bounty and data.bounty_location then
                local loc = Map.location(rid)
                if loc ~= data.bounty_location then
                    goto next_room
                end
            end

            local spawn_room = M.new_spawn_room(rid, target_creature.level)

            -- Build reachable from this spawn
            M.build_reachable_rids(
                spawn_room, 8, data.room_index,
                data.target_creature_level, data.safe_room_level
            )

            -- If dangerous creatures have spawned, also expand wander rids
            if data.has_dangerous_creature_spawned then
                M.build_wander_rids(
                    spawn_room, 8, nil, data.room_index,
                    data.target_creature_level, data.safe_room_level
                )
            end

            locale[#locale + 1] = spawn_room
            ::next_room::
        end

        if #locale > 0 then
            spawn_locales[#spawn_locales + 1] = locale
        end

        ::next_sid::
    end

    return spawn_locales
end

---------------------------------------------------------------------------
-- build_hunting_areas — merge SpawnRooms into HuntingAreas
---------------------------------------------------------------------------

function M.build_hunting_areas(spawn_locales)
    local areas = {}

    -- Flatten all spawn rooms from all locales
    for _, locale in ipairs(spawn_locales) do
        for _, sr in ipairs(locale) do
            -- Try to merge into an existing area whose reachable_rids overlap
            local merged = false
            for _, area in ipairs(areas) do
                if area.reachable_rids[sr.rid] then
                    M.insert_spawn_room(area, sr)
                    merged = true
                    break
                end
                -- Check if any of sr's reachable rids overlap with area's spawn_rids
                local found = false
                for rid in pairs(sr.reachable_rids) do
                    if area.spawn_rids[rid] then
                        found = true
                        break
                    end
                end
                if found then
                    M.insert_spawn_room(area, sr)
                    merged = true
                    break
                end
            end

            if not merged then
                local area = M.new_hunting_area()
                M.insert_spawn_room(area, sr)
                areas[#areas + 1] = area
            end
        end
    end

    -- Iteratively merge areas that can reach each other
    local changed = true
    while changed do
        changed = false
        local i = 1
        while i <= #areas do
            local j = i + 1
            while j <= #areas do
                -- Check if area i's reachable_rids overlap area j's spawn_rids or vice versa
                local should_merge = false
                for rid in pairs(areas[i].reachable_rids) do
                    if areas[j].spawn_rids[rid] then
                        should_merge = true
                        break
                    end
                end
                if not should_merge then
                    for rid in pairs(areas[j].reachable_rids) do
                        if areas[i].spawn_rids[rid] then
                            should_merge = true
                            break
                        end
                    end
                end

                if should_merge then
                    M.insert_hunting_area(areas[i], areas[j])
                    table.remove(areas, j)
                    changed = true
                else
                    j = j + 1
                end
            end
            i = i + 1
        end
    end

    -- Filter out areas with fewer than 5 spawn_rooms, unless all are small
    local large = {}
    local largest = nil
    local largest_count = 0
    for _, area in ipairs(areas) do
        if #area.spawn_rooms >= 5 then
            large[#large + 1] = area
        end
        if #area.spawn_rooms > largest_count then
            largest_count = #area.spawn_rooms
            largest = area
        end
    end

    if #large > 0 then
        return large
    elseif largest then
        return { largest }
    else
        return {}
    end
end

---------------------------------------------------------------------------
-- consolidate_hunting_areas — merge bidirectionally reachable areas
---------------------------------------------------------------------------

function M.consolidate_hunting_areas(hunting_areas)
    local changed = true
    while changed do
        changed = false
        local i = 1
        while i <= #hunting_areas do
            local j = i + 1
            while j <= #hunting_areas do
                -- Check bidirectional reachability
                local i_reaches_j = false
                local j_reaches_i = false

                for rid in pairs(hunting_areas[i].reachable_rids) do
                    if hunting_areas[j].reachable_rids[rid] then
                        i_reaches_j = true
                        break
                    end
                end
                for rid in pairs(hunting_areas[j].reachable_rids) do
                    if hunting_areas[i].reachable_rids[rid] then
                        j_reaches_i = true
                        break
                    end
                end

                if i_reaches_j and j_reaches_i then
                    M.insert_hunting_area(hunting_areas[i], hunting_areas[j])
                    table.remove(hunting_areas, j)
                    changed = true
                else
                    j = j + 1
                end
            end
            i = i + 1
        end
    end
    return hunting_areas
end

---------------------------------------------------------------------------
-- internally_link_hunting_areas — BFS-path between spawn rooms
---------------------------------------------------------------------------

function M.internally_link_hunting_areas(hunting_areas, room_index)
    for _, area in ipairs(hunting_areas) do
        if #area.spawn_rooms < 2 then goto next_area end

        -- BFS-path from each spawn room to the nearest other spawn room
        local spawn_rid_set = {}
        for _, sr in ipairs(area.spawn_rooms) do
            spawn_rid_set[sr.rid] = true
        end

        for _, sr in ipairs(area.spawn_rooms) do
            -- Find path to any other spawn room through reachable territory
            local other_spawns = {}
            for rid in pairs(spawn_rid_set) do
                if rid ~= sr.rid then
                    other_spawns[rid] = true
                end
            end

            if not next(other_spawns) then goto next_sr end

            local path = pathfinding.bfs_path_to_any(sr.rid, other_spawns, area.reachable_rids)
            if path then
                M.insert_hunting_path(area, path, room_index)
            end

            ::next_sr::
        end

        ::next_area::
    end
end

---------------------------------------------------------------------------
-- sort_hunting_areas — rank areas by travel time, spawn count, level, density
---------------------------------------------------------------------------

function M.sort_hunting_areas(hunting_areas, current_rid)
    -- Compute nearest_rid and travel_time for each area
    for _, area in ipairs(hunting_areas) do
        local nearest, time = pathfinding.find_nearest_with_time(current_rid, area.spawn_rids, nil)
        area.nearest_rid = nearest
        area.travel_time = time or math.huge
    end

    table.sort(hunting_areas, function(a, b)
        -- Travel time: within 10s tolerance, consider them equal
        local time_diff = (a.travel_time or math.huge) - (b.travel_time or math.huge)
        if math.abs(time_diff) > 10 then
            return time_diff < 0
        end

        -- Spawn count: areas with >=5 spawns are preferred
        local a_enough = #a.spawn_rooms >= 5
        local b_enough = #b.spawn_rooms >= 5
        if a_enough ~= b_enough then
            return a_enough
        end

        -- Max creature level: within safe_room_level tolerance (use 3 as default)
        local a_level = a.max_creature_level or 0
        local b_level = b.max_creature_level or 0
        local level_diff = a_level - b_level
        if math.abs(level_diff) > 3 then
            return level_diff < 0
        end

        -- Density: spawn_rooms / hunting_rids count, within 0.15 tolerance
        local a_hunting_count = 0
        for _ in pairs(a.hunting_rids) do a_hunting_count = a_hunting_count + 1 end
        local b_hunting_count = 0
        for _ in pairs(b.hunting_rids) do b_hunting_count = b_hunting_count + 1 end

        local a_density = a_hunting_count > 0 and (#a.spawn_rooms / a_hunting_count) or 0
        local b_density = b_hunting_count > 0 and (#b.spawn_rooms / b_hunting_count) or 0
        local density_diff = a_density - b_density
        if math.abs(density_diff) > 0.15 then
            return density_diff > 0  -- higher density is better
        end

        -- Final tiebreaker: more spawn rooms is better
        return #a.spawn_rooms > #b.spawn_rooms
    end)

    return hunting_areas
end

---------------------------------------------------------------------------
-- build_hunting_plan — the 5-step pipeline
---------------------------------------------------------------------------

function M.build_hunting_plan(target_creature, data)
    -- Step 1: Build spawn locales
    local spawn_locales = M.build_spawn_locales(target_creature, data)
    if #spawn_locales == 0 then return nil end

    -- Step 2: Build hunting areas from locales
    local hunting_areas = M.build_hunting_areas(spawn_locales)
    if #hunting_areas == 0 then return nil end

    -- Step 3: Consolidate bidirectionally reachable areas
    M.consolidate_hunting_areas(hunting_areas)

    -- Step 4: Internally link spawn rooms within each area
    M.internally_link_hunting_areas(hunting_areas, data.room_index)

    -- Step 5: Sort by travel time / quality and pick best
    local current_rid = Map.current_room()
    M.sort_hunting_areas(hunting_areas, current_rid)

    -- Return the best (first) hunting area
    return hunting_areas[1]
end

return M
