--- huntplan pathfinding.lua — MinHeap, BFS, Dijkstra, boundary helpers
-- Port of huntplan.lic lines 2138-2354 (MinHeap, BFS, Dijkstra)
-- and lines 2193-2204 (get_boundaries_from_room_ids)

local excluded = require("excluded")

local M = {}

---------------------------------------------------------------------------
-- MinHeap — min-priority queue for Dijkstra
-- Each element: {priority, value}
---------------------------------------------------------------------------

local MinHeap = {}
MinHeap.__index = MinHeap

function MinHeap.new()
    return setmetatable({ data = {} }, MinHeap)
end

function MinHeap:push(priority, value)
    local data = self.data
    data[#data + 1] = { priority, value }
    -- sift up
    local i = #data
    while i > 1 do
        local parent = math.floor(i / 2)
        if data[parent][1] > data[i][1] then
            data[parent], data[i] = data[i], data[parent]
            i = parent
        else
            break
        end
    end
end

function MinHeap:pop()
    local data = self.data
    if #data == 0 then return nil, nil end
    local top = data[1]
    local last = table.remove(data)
    if #data > 0 then
        data[1] = last
        -- sift down
        local i = 1
        while true do
            local left  = i * 2
            local right = i * 2 + 1
            local smallest = i
            if left  <= #data and data[left][1]  < data[smallest][1] then smallest = left  end
            if right <= #data and data[right][1] < data[smallest][1] then smallest = right end
            if smallest == i then break end
            data[i], data[smallest] = data[smallest], data[i]
            i = smallest
        end
    end
    return top[1], top[2]
end

function MinHeap:size() return #self.data end

M.MinHeap = MinHeap

---------------------------------------------------------------------------
-- get_boundaries_from_room_ids
-- Returns set of rooms *outside* the given set that are adjacent to it.
-- room_set: {[rid]=true, ...}
---------------------------------------------------------------------------

function M.get_boundaries_from_room_ids(room_set)
    local boundary = {}
    for rid in pairs(room_set) do
        local exits = Map.exits(rid) or {}
        for _, adj in pairs(exits) do
            if type(adj) == "function" then
                -- StringProc: call to get destination
                local ok, dst = pcall(adj)
                if ok and dst and not room_set[dst] then
                    boundary[dst] = true
                end
            elseif type(adj) == "number" then
                if not room_set[adj] then
                    boundary[adj] = true
                end
            end
        end
    end
    return boundary
end

---------------------------------------------------------------------------
-- BFS helpers
---------------------------------------------------------------------------

-- Build path array from came_from table
local function build_path(came_from, start_rid, end_rid)
    local path = {}
    local cur = end_rid
    while cur ~= start_rid do
        table.insert(path, 1, cur)
        cur = came_from[cur]
        if cur == nil then return nil end
    end
    table.insert(path, 1, start_rid)
    return path
end

--- BFS from start_rid, returns came_from table.
-- weightless_rids: set of rids treated as 0-cost (explored before others).
-- room_set: optional set to restrict traversal (nil = unrestricted).
-- max_depth: maximum BFS hops (nil = unlimited).
function M.bfs(start_rid, room_set, max_depth, weightless_rids)
    local came_from = { [start_rid] = start_rid }
    local depth     = { [start_rid] = 0 }
    -- Use two sub-queues: front (weightless) and back (normal)
    local front = { start_rid }
    local back  = {}

    while #front > 0 or #back > 0 do
        local current
        if #front > 0 then
            current = table.remove(front, 1)
        else
            current = table.remove(back, 1)
        end

        local cur_depth = depth[current]
        if max_depth and cur_depth >= max_depth then goto continue end

        local exits = Map.exits(current) or {}
        for _, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end

            if dst and not came_from[dst]
               and not excluded.is_excluded(current, dst)
               and (not room_set or room_set[dst]) then
                came_from[dst] = current
                depth[dst] = cur_depth + 1
                if weightless_rids and weightless_rids[dst] then
                    table.insert(front, 1, dst)
                else
                    back[#back + 1] = dst
                end
            end
        end
        ::continue::
    end
    return came_from
end

--- BFS path from start to end within optional room_set.
function M.bfs_path_to(start_rid, end_rid, room_set)
    local came_from = M.bfs(start_rid, room_set, nil, nil)
    if not came_from[end_rid] then return nil end
    return build_path(came_from, start_rid, end_rid)
end

--- BFS path from start to the nearest room in target_set.
-- Returns path array or nil.
function M.bfs_path_to_any(start_rid, target_set, room_set)
    local came_from = { [start_rid] = start_rid }
    local queue = { start_rid }
    while #queue > 0 do
        local current = table.remove(queue, 1)
        if target_set[current] and current ~= start_rid then
            return build_path(came_from, start_rid, current)
        end
        local exits = Map.exits(current) or {}
        for _, adj in pairs(exits) do
            local dst
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then dst = result end
            elseif type(adj) == "number" then
                dst = adj
            end
            if dst and not came_from[dst]
               and not excluded.is_excluded(current, dst)
               and (not room_set or room_set[dst]) then
                came_from[dst] = current
                queue[#queue + 1] = dst
            end
        end
    end
    return nil
end

--- BFS to find nearest room in target_set from start_rid.
-- Returns rid or nil.
function M.bfs_nearest(start_rid, target_set, room_set)
    local path = M.bfs_path_to_any(start_rid, target_set, room_set)
    if not path then return nil end
    return path[#path]
end

---------------------------------------------------------------------------
-- Dijkstra — time-weighted shortest path
---------------------------------------------------------------------------

--- Full Dijkstra from start_rid over the given room_set (nil = all rooms).
-- Returns dist table {[rid]=time} and came_from table.
function M.dijkstra(start_rid, room_set)
    local dist       = { [start_rid] = 0 }
    local came_from  = { [start_rid] = start_rid }
    local heap       = MinHeap.new()
    heap:push(0, start_rid)

    while heap:size() > 0 do
        local d, current = heap:pop()
        if d > (dist[current] or math.huge) then goto skip end

        local exits = Map.exits(current) or {}
        for dir, adj in pairs(exits) do
            local dst, cost
            if type(adj) == "function" then
                local ok, result = pcall(adj)
                if ok and result then
                    dst = result
                    -- StringProc: try timeto, fall back to 0.2
                    local tc = Map.timeto(current, dir)
                    if type(tc) == "function" then
                        local ok2, tv = pcall(tc)
                        cost = ok2 and tv or 0.2
                    else
                        cost = tonumber(tc) or 0.2
                    end
                end
            elseif type(adj) == "number" then
                dst = adj
                local tc = Map.timeto(current, dir)
                if type(tc) == "function" then
                    local ok2, tv = pcall(tc)
                    cost = ok2 and tv or 0.2
                else
                    cost = tonumber(tc) or 0.2
                end
            end

            if dst and not excluded.is_excluded(current, dst)
               and (not room_set or room_set[dst]) then
                local nd = d + (cost or 0.2)
                if nd < (dist[dst] or math.huge) then
                    dist[dst] = nd
                    came_from[dst] = current
                    heap:push(nd, dst)
                end
            end
        end
        ::skip::
    end
    return dist, came_from
end

--- Find nearest room to start_rid in target_set, using Dijkstra time cost.
-- Returns nearest_rid, travel_time or nil, nil.
function M.find_nearest_with_time(start_rid, target_set, room_set)
    local dist = M.dijkstra(start_rid, room_set)
    local best_rid, best_dist = nil, math.huge
    for rid in pairs(target_set) do
        local d = dist[rid]
        if d and d < best_dist then
            best_dist = d
            best_rid  = rid
        end
    end
    return best_rid, (best_rid and best_dist or nil)
end

--- Find nearest room in target_set with full path and time.
-- Returns path array, travel_time or nil, nil.
function M.find_nearest_with_path_and_time(start_rid, target_set, room_set)
    local dist, came_from = M.dijkstra(start_rid, room_set)
    local best_rid, best_dist = nil, math.huge
    for rid in pairs(target_set) do
        local d = dist[rid]
        if d and d < best_dist then
            best_dist = d
            best_rid  = rid
        end
    end
    if not best_rid then return nil, nil end
    return build_path(came_from, start_rid, best_rid), best_dist
end

return M
