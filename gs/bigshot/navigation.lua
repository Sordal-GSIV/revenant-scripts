--- Bigshot Navigation — room movement within hunting boundaries
-- Handles wandering to new rooms, returning to anchor, fog return home.

local area_rooms = require("area_rooms")

local M = {}

-- Move to a random valid neighbor
function M.wander(state)
    local current = Map.current_room()
    if not current then return false end

    -- Check if current room is valid
    if not area_rooms.valid(current) then
        respond("[bigshot] Out of bounds — returning to anchor")
        M.goto_room(area_rooms.get_anchor())
        return true
    end

    -- Get valid neighbors
    local neighbors = area_rooms.get_valid_neighbors(current)
    if #neighbors == 0 then
        respond("[bigshot] No valid exits — returning to anchor")
        M.goto_room(area_rooms.get_anchor())
        return true
    end

    -- Pick random neighbor
    math.randomseed(os.time())
    local choice = neighbors[math.random(#neighbors)]

    -- Wait before moving if configured
    if state.wander_wait and state.wander_wait > 0 then
        pause(state.wander_wait)
    end

    -- Move
    waitrt()
    local ok, err = pcall(move, choice.command)
    return ok
end

-- Navigate to a specific room via go2
function M.goto_room(room_id)
    if not room_id or room_id == 0 then return false end
    local current = Map.current_room()
    if current == room_id then return true end

    Script.run("go2", tostring(room_id))
    pause(0.5)
    return Map.current_room() == room_id
end

-- Travel through waypoints in order
function M.travel_waypoints(waypoints)
    if not waypoints or #waypoints == 0 then return end
    for _, wp in ipairs(waypoints) do
        local room_id = tonumber(wp)
        if room_id then
            M.goto_room(room_id)
        end
    end
end

-- Fog return: fast travel home
function M.fog_return(state)
    local fog_type = state.fog_return or ""

    if fog_type == "" then
        return false
    end

    respond("[bigshot] Fog return: " .. fog_type)

    if fog_type == "130" then
        -- Spirit Guide
        fput("incant 130")
        pause(2)
    elseif fog_type == "1020" then
        -- Traveler's Song
        fput("incant 1020")
        pause(2)
    elseif fog_type == "9825" then
        -- Symbol of Return (Voln)
        fput("symbol of return")
        pause(2)
    elseif fog_type == "sigil" then
        -- Sigil of Escape (GoS)
        fput("sigil of escape")
        pause(2)
    elseif fog_type == "custom" then
        -- Execute custom fog commands
        for _, cmd in ipairs(state.fog_return_commands or {}) do
            fput(cmd)
            pause(0.5)
        end
    end

    return true
end

-- Escape: leave combat area safely
function M.escape(state)
    -- If fog return is available, use it
    if state.fog_return and state.fog_return ~= "" then
        return M.fog_return(state)
    end
    -- Otherwise just go2 the rest room
    if state.rest_room and state.rest_room ~= "" then
        return M.goto_room(tonumber(state.rest_room))
    end
    return false
end

return M
