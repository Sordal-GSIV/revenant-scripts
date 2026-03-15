local M = {}

local blacklisted = {}

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
        -- Diagnostics
        local from_room = Map.find_room(from_id)
        local to_room = Map.find_room(to_id)
        local msg = "no path found from " .. from_id .. " to " .. to_id
        if not from_room then
            msg = msg .. " (source room not in map)"
        end
        if not to_room then
            msg = msg .. " (destination room not in map)"
        end
        return nil, msg
    end

    -- Check if first step is blacklisted
    if #path > 0 and blacklisted[from_id .. ":" .. path[1]] then
        return nil, "path goes through a blacklisted edge — try a different route"
    end

    return path, nil
end

function M.estimate_steps(from_id, to_id)
    local path = Map.find_path(from_id, to_id)
    if path then return #path end
    return nil
end

function M.blacklist(from_id, command)
    blacklisted[from_id .. ":" .. command] = true
end

function M.clear_blacklist()
    blacklisted = {}
end

return M
