--- Bigshot Area Rooms — BFS boundary builder
-- Given a hunting anchor room and boundary room IDs, builds the set of valid
-- rooms by flood-filling the map graph. Used to keep the character in-bounds.

local M = {}

local valid_rooms = {}
local boundary_set = {}
local anchor_id = nil

function M.build(hunting_room_id, boundaries)
    anchor_id = hunting_room_id
    valid_rooms = {}
    boundary_set = {}

    -- Build boundary lookup set
    for _, id in ipairs(boundaries or {}) do
        boundary_set[id] = true
    end

    -- BFS flood-fill from anchor
    local queue = { hunting_room_id }
    local visited = { [hunting_room_id] = true }

    while #queue > 0 do
        local room_id = table.remove(queue, 1)
        valid_rooms[room_id] = true

        local room = Map.find_room(room_id)
        if room and room.wayto then
            for dest_str, _ in pairs(room.wayto) do
                local dest_id = tonumber(dest_str)
                if dest_id and not visited[dest_id] and not boundary_set[dest_id] then
                    -- Only include exits with numeric timeto (traversable)
                    local timeto = room.timeto and room.timeto[dest_str]
                    if timeto and type(timeto) == "number" then
                        visited[dest_id] = true
                        queue[#queue + 1] = dest_id
                    end
                end
            end
        end
    end

    return M.count()
end

function M.valid(room_id)
    return valid_rooms[room_id] == true
end

function M.count()
    local n = 0
    for _ in pairs(valid_rooms) do n = n + 1 end
    return n
end

function M.get_valid_neighbors(room_id)
    local neighbors = {}
    local room = Map.find_room(room_id)
    if not room or not room.wayto then return neighbors end

    for dest_str, command in pairs(room.wayto) do
        local dest_id = tonumber(dest_str)
        if dest_id and valid_rooms[dest_id] then
            neighbors[#neighbors + 1] = { id = dest_id, command = command }
        end
    end

    return neighbors
end

function M.get_anchor()
    return anchor_id
end

function M.is_boundary(room_id)
    return boundary_set[room_id] == true
end

return M
