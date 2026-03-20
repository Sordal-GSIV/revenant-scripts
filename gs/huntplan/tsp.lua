--- huntplan tsp.lua — Traveling Salesman Problem solver
-- Port of huntplan.lic TSP functions (BFS distances, 2-opt, simulated annealing)
-- Uses Map.exits() for adjacency and pathfinding.bfs_path_to() for gap filling.

local pathfinding = require("pathfinding")

local M = {}

---------------------------------------------------------------------------
-- BFS distances from a starting room to all rooms in a set
-- Returns {[rid]=distance, ...} for every reachable room in rooms_set
---------------------------------------------------------------------------

function M.bfs_distances_from(starting_rid, rooms_set)
    local visited = { [starting_rid] = 0 }
    local queue   = { starting_rid }
    local qi      = 1

    while qi <= #queue do
        local current = queue[qi]
        qi = qi + 1
        local cur_dist = visited[current]
        local exits = Map.exits(current) or {}

        for _, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end

            if dst and rooms_set[dst] and visited[dst] == nil then
                visited[dst] = cur_dist + 1
                queue[#queue + 1] = dst
            end
        end
    end

    return visited
end

---------------------------------------------------------------------------
-- Calculate all pairwise BFS distances between rooms
-- rooms: array of room ids
-- Returns {[rid]={[other_rid]=dist, ...}, ...}
---------------------------------------------------------------------------

function M.calculate_all_distances(rooms)
    -- Build rooms_set for BFS restriction
    local rooms_set = {}
    for _, rid in ipairs(rooms) do
        rooms_set[rid] = true
    end

    local distance_hash = {}
    for _, rid in ipairs(rooms) do
        distance_hash[rid] = M.bfs_distances_from(rid, rooms_set)
    end
    return distance_hash
end

---------------------------------------------------------------------------
-- Compute cost of a path given distance_hash
---------------------------------------------------------------------------

function M.path_cost(path, distance_hash)
    local cost = 0
    for i = 1, #path - 1 do
        local from_dists = distance_hash[path[i]]
        cost = cost + (from_dists and from_dists[path[i + 1]] or 999999)
    end
    return cost
end

---------------------------------------------------------------------------
-- 2-opt local improvement
-- Repeatedly reverses segments to reduce total path cost
---------------------------------------------------------------------------

function M.two_opt(path, distance_hash)
    local improved = true
    local best_path = {}
    for i = 1, #path do best_path[i] = path[i] end
    local best_cost = M.path_cost(best_path, distance_hash)

    while improved do
        improved = false
        for i = 2, #best_path - 2 do
            for k = i + 1, #best_path - 1 do
                -- Build new path: [1..i-1] + reverse[i..k] + [k+1..#]
                local new_path = {}
                for x = 1, i - 1 do
                    new_path[#new_path + 1] = best_path[x]
                end
                for x = k, i, -1 do
                    new_path[#new_path + 1] = best_path[x]
                end
                for x = k + 1, #best_path do
                    new_path[#new_path + 1] = best_path[x]
                end

                local new_cost = M.path_cost(new_path, distance_hash)
                if new_cost < best_cost then
                    best_path = new_path
                    best_cost = new_cost
                    improved = true
                    break
                end
            end
            if improved then break end
        end
    end

    return best_path, best_cost
end

---------------------------------------------------------------------------
-- Simulated annealing TSP
-- distance_hash: pairwise distances from calculate_all_distances
-- Returns best_path (array of rids), best_cost
---------------------------------------------------------------------------

function M.simulated_annealing_tsp(distance_hash, initial_temperature, cooling_rate, iterations)
    initial_temperature = initial_temperature or 1000
    cooling_rate        = cooling_rate or 0.995
    iterations          = iterations or 10000

    -- Collect all nodes from the distance_hash keys
    local nodes = {}
    for rid in pairs(distance_hash) do
        nodes[#nodes + 1] = rid
    end

    if #nodes == 0 then return {}, 0 end
    if #nodes == 1 then return { nodes[1] }, 0 end

    local start_node = nodes[1]

    -- Shuffle middle nodes (Fisher-Yates on nodes[2..#nodes])
    for i = #nodes, 2, -1 do
        local j = math.random(1, i)
        nodes[i], nodes[j] = nodes[j], nodes[i]
    end

    -- Ensure start_node is first; move it if it got shuffled away
    for i = 1, #nodes do
        if nodes[i] == start_node then
            nodes[i], nodes[1] = nodes[1], nodes[i]
            break
        end
    end

    -- Build circular tour: start → shuffled middle → start
    local current_path = {}
    for i = 1, #nodes do
        current_path[i] = nodes[i]
    end
    current_path[#current_path + 1] = start_node

    local current_cost = M.path_cost(current_path, distance_hash)
    local best_path = {}
    for i = 1, #current_path do best_path[i] = current_path[i] end
    local best_cost = current_cost

    local temperature = initial_temperature

    for _ = 1, iterations do
        -- Pick two random indices in the middle portion (not first or last)
        if #current_path <= 3 then break end

        local i = math.random(2, #current_path - 1)
        local k = math.random(2, #current_path - 1)
        if i > k then i, k = k, i end
        if i == k then goto next_iter end

        -- Build candidate by reversing segment i..k
        local candidate = {}
        for x = 1, i - 1 do
            candidate[#candidate + 1] = current_path[x]
        end
        for x = k, i, -1 do
            candidate[#candidate + 1] = current_path[x]
        end
        for x = k + 1, #current_path do
            candidate[#candidate + 1] = current_path[x]
        end

        local candidate_cost = M.path_cost(candidate, distance_hash)
        local delta = candidate_cost - current_cost

        if delta < 0 or math.random() < math.exp(-delta / temperature) then
            current_path = candidate
            current_cost = candidate_cost

            if current_cost < best_cost then
                best_path = {}
                for x = 1, #current_path do best_path[x] = current_path[x] end
                best_cost = current_cost
            end
        end

        temperature = temperature * cooling_rate
        ::next_iter::
    end

    -- Remove trailing start_node (circular → open path)
    if #best_path > 1 and best_path[#best_path] == best_path[1] then
        best_path[#best_path] = nil
    end

    -- Apply 2-opt local improvement
    best_path, best_cost = M.two_opt(best_path, distance_hash)

    return best_path, best_cost
end

---------------------------------------------------------------------------
-- Fill gaps in path where rooms aren't directly adjacent
-- Uses pathfinding.bfs_path_to to find connecting paths within rooms_set
-- Also connects last → first for a circular route
---------------------------------------------------------------------------

function M.connect_gaps_in_path(path, rooms_set)
    if #path <= 1 then return path end

    local expanded = {}

    for i = 1, #path - 1 do
        local a, b = path[i], path[i + 1]
        expanded[#expanded + 1] = a

        -- Check if a and b are directly adjacent
        local directly_adjacent = false
        local exits = Map.exits(a) or {}
        for _, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end
            if dst == b then
                directly_adjacent = true
                break
            end
        end

        if not directly_adjacent then
            -- BFS to find connecting path within rooms_set
            local connecting = pathfinding.bfs_path_to(a, b, rooms_set)
            if connecting then
                -- connecting includes a and b; skip first (already added) and last (added next iter)
                for j = 2, #connecting - 1 do
                    expanded[#expanded + 1] = connecting[j]
                end
            end
        end
    end

    -- Add last room
    expanded[#expanded + 1] = path[#path]

    -- Connect last → first
    local last  = path[#path]
    local first = path[1]
    if last ~= first then
        local directly_adjacent = false
        local exits = Map.exits(last) or {}
        for _, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end
            if dst == first then
                directly_adjacent = true
                break
            end
        end

        if not directly_adjacent then
            local connecting = pathfinding.bfs_path_to(last, first, rooms_set)
            if connecting then
                -- Skip first (already in expanded as last element)
                for j = 2, #connecting do
                    expanded[#expanded + 1] = connecting[j]
                end
            end
        end
    end

    return expanded
end

---------------------------------------------------------------------------
-- Main entry point: given array of room ids, find approximate shortest route
-- Returns the expanded path array, or nil if fewer than 2 rooms
---------------------------------------------------------------------------

function M.approximate_shortest_route(rooms)
    if not rooms or #rooms < 2 then return nil end

    -- 1. Calculate all pairwise BFS distances
    local distance_hash = M.calculate_all_distances(rooms)

    -- 2. Run simulated annealing TSP
    local best_path, _ = M.simulated_annealing_tsp(distance_hash)

    if not best_path or #best_path == 0 then return nil end

    -- 3. Build rooms_set for gap filling
    local rooms_set = {}
    for _, rid in ipairs(rooms) do
        rooms_set[rid] = true
    end

    -- 4. Connect gaps in the path
    local shortest_path = M.connect_gaps_in_path(best_path, rooms_set)

    return shortest_path
end

return M
