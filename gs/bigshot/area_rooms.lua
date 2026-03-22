--- Bigshot Area Rooms — BFS boundary builder
-- Given a hunting anchor room and boundary room IDs, builds the set of valid
-- rooms by flood-filling the map graph. Used to keep the character in-bounds.
-- Port of BSAreaRooms from bigshot.lic v5.12.1

local M = {}

local valid_rooms = {}
local boundary_set = {}
local anchor_id = nil
local location_changes = {}
local last_location = nil

local MAX_AREA_ROOMS = 200

function M.build(hunting_room_id, boundaries)
    anchor_id = hunting_room_id
    valid_rooms = {}
    boundary_set = {}
    location_changes = {}
    last_location = nil

    -- Build boundary lookup set
    for _, id in ipairs(boundaries or {}) do
        boundary_set[tonumber(id) or id] = true
    end

    -- BFS flood-fill from anchor
    local queue = { hunting_room_id }
    local visited = { [hunting_room_id] = true }

    -- Get initial location
    local start_room = Map.find_room(hunting_room_id)
    if start_room then
        last_location = start_room.location
    end

    while #queue > 0 do
        local room_id = table.remove(queue, 1)
        valid_rooms[room_id] = true

        -- Track location changes
        M._track_location(room_id)

        local room = Map.find_room(room_id)
        if room and room.wayto then
            for dest_str, _ in pairs(room.wayto) do
                local dest_id = tonumber(dest_str)
                if dest_id and not visited[dest_id] and not boundary_set[dest_id] then
                    local timeto = room.timeto and room.timeto[dest_str]
                    -- Only include exits with valid numeric travel times
                    local is_numeric = false
                    if type(timeto) == "number" then
                        is_numeric = true
                    elseif type(timeto) == "function" then
                        local ok, val = pcall(timeto)
                        is_numeric = ok and type(val) == "number"
                    end
                    if is_numeric then
                        visited[dest_id] = true
                        queue[#queue + 1] = dest_id
                    end
                end
            end
        end

        -- Safety: abort if too many rooms (likely missing boundaries)
        if M.count() >= MAX_AREA_ROOMS then
            M._boundary_break()
            return 0
        end
    end

    return M.count()
end

function M._track_location(room_id)
    local room = Map.find_room(room_id)
    if not room then return end
    local loc = room.location
    if loc and loc ~= last_location then
        last_location = loc
        if #location_changes < 3 then
            location_changes[#location_changes + 1] = { id = room_id, location = loc }
        end
    end
end

function M._boundary_break()
    respond("")
    respond("[bigshot] WARNING: Hunting area has " .. M.count() .. "+ rooms (limit " .. MAX_AREA_ROOMS .. ")")
    respond("[bigshot] This likely means missing boundary rooms.")
    respond("")
    if #location_changes > 0 then
        respond("[bigshot] Location changes detected:")
        for _, change in ipairs(location_changes) do
            respond("  Room " .. change.id .. " → " .. change.location)
        end
    end
    respond("[bigshot] Please review boundary settings in Hunting tab.")
    respond("")
end

function M.valid(room_id)
    if room_id == nil then return false end
    return valid_rooms[tonumber(room_id) or room_id] == true
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
    return boundary_set[tonumber(room_id) or room_id] == true
end

function M.get_rooms()
    return valid_rooms
end

return M
