-- pathfinder.lua — go2 path computation utilities

local M = {}

local blacklisted = {}

-------------------------------------------------------------------------------
-- get_path_rooms: reconstruct room ID sequence from a command path
-- Map.find_path returns commands; wayto is {dest_id_str -> command}
-- We walk the wayto entries to find which room each command leads to.
-------------------------------------------------------------------------------

function M.get_path_rooms(from_id, commands)
    local rooms = { from_id }
    local current = from_id
    for _, cmd in ipairs(commands) do
        local room = Map.find_room(current)
        if not room or not room.wayto then break end
        local found = false
        for dest_str, wt_cmd in pairs(room.wayto) do
            if wt_cmd == cmd then
                current = tonumber(dest_str)
                table.insert(rooms, current)
                found = true
                break
            end
        end
        if not found then break end
    end
    return rooms
end

-------------------------------------------------------------------------------
-- find: return command list path from from_id to to_id, or nil, err
-------------------------------------------------------------------------------

function M.find(from_id, to_id)
    if not from_id then
        return nil, "current room unknown — not in map database"
    end
    if not to_id then
        return nil, "destination room not specified"
    end
    if from_id == to_id then
        return {}, nil  -- already there
    end

    local path = Map.find_path(from_id, to_id)
    if not path or #path == 0 then
        local from_room = Map.find_room(from_id)
        local to_room   = Map.find_room(to_id)
        local msg = "no path found from " .. from_id .. " to " .. to_id
        if not from_room then msg = msg .. " (source room not in map)"   end
        if not to_room   then msg = msg .. " (destination room not in map)" end
        return nil, msg
    end

    -- Blacklist check on first step
    if #path > 0 and blacklisted[from_id .. ":" .. path[1]] then
        return nil, "path goes through a blacklisted edge — try a different route"
    end

    return path, nil
end

-------------------------------------------------------------------------------
-- estimate_steps
-------------------------------------------------------------------------------

function M.estimate_steps(from_id, to_id)
    local path = Map.find_path(from_id, to_id)
    if path then return #path end
    return nil
end

-------------------------------------------------------------------------------
-- estimate_silver_cost: sum silver-cost tags along path
-- Tag format: "silver-cost:<dest_room_id>:<amount>"
-------------------------------------------------------------------------------

function M.estimate_silver_cost(from_id, to_id)
    local path = Map.find_path(from_id, to_id)
    if not path or #path == 0 then return 0 end

    local room_ids = M.get_path_rooms(from_id, path)
    local total = 0

    for i = 1, #room_ids - 1 do
        local cur_id  = room_ids[i]
        local next_id = room_ids[i + 1]
        local room = Map.find_room(cur_id)
        if room and room.tags then
            local pattern = "^silver%-cost:" .. tostring(next_id) .. ":(%d+)$"
            for _, tag in ipairs(room.tags) do
                local cost_str = tag:match(pattern)
                if cost_str then
                    total = total + tonumber(cost_str)
                end
            end
        end
    end

    return total
end

-------------------------------------------------------------------------------
-- find_nearest_tag: find nearest room with the given tag, return room_id or nil
-------------------------------------------------------------------------------

function M.find_nearest_tag(tag, from_id)
    local result = Map.find_nearest_by_tag(tag)
    if result and result.id then
        return result.id, result.path and #result.path or nil
    end
    return nil, nil
end

-------------------------------------------------------------------------------
-- find_nearest_in_list: find nearest of a list of room IDs
-- Returns best_id, best_step_count or nil
-------------------------------------------------------------------------------

function M.find_nearest_in_list(from_id, id_list)
    local best_id    = nil
    local best_steps = math.huge
    for _, id in ipairs(id_list) do
        local path = Map.find_path(from_id, id)
        if path and #path < best_steps then
            best_steps = #path
            best_id    = id
        end
    end
    return best_id, (best_id and best_steps or nil)
end

-------------------------------------------------------------------------------
-- Blacklist helpers
-------------------------------------------------------------------------------

function M.blacklist(from_id, command)
    blacklisted[from_id .. ":" .. command] = true
end

function M.clear_blacklist()
    blacklisted = {}
end

return M
