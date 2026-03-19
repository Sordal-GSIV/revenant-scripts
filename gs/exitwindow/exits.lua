--- Exit extraction logic for exitwindow.
--- Mirrors the ExitWindow module methods from exitwindow.lic.

local M = {}

-- Cardinal/standard movement directions to ignore when finding "Lich exits"
local IGNORED_DIRECTIONS = {
    o = true, d = true, u = true,
    n = true, ne = true, e = true, se = true,
    s = true, sw = true, w = true, nw = true,
    out = true, down = true, up = true,
    north = true, northeast = true, east = true, southeast = true,
    south = true, southwest = true, west = true, northwest = true,
}

--- Extract standard exits from room paths.
--- In Lich5 these come from Room.current.paths lines matching "Obvious paths/exits: ..."
--- In Revenant, room.paths is the list of exit display strings from the map DB,
--- and GameState.room_exits gives the live XML-parsed exits.
--- We use GameState.room_exits for live data (matches Lich5 behavior).
--- @param room table — room table from Map.find_room()
--- @return table — array of exit name strings (e.g. {"North", "East", "Out"})
function M.extract_standard(room)
    -- Use live room exits from XML parser (most accurate, matches what the game shows)
    local live_exits = GameState.room_exits
    if live_exits and #live_exits > 0 then
        local result = {}
        for _, exit in ipairs(live_exits) do
            -- Capitalize first letter to match Lich5 display style
            local capitalized = exit:sub(1, 1):upper() .. exit:sub(2)
            result[#result + 1] = capitalized
        end
        return result
    end

    -- Fallback: parse room.paths from map DB (like Lich5 extract_exits_from_paths)
    if room.paths then
        local result = {}
        for _, path in ipairs(room.paths) do
            local exits_str = path:match("[Oo]bvious%s+[Pp]aths?:?%s*(.*)")
                           or path:match("[Oo]bvious%s+[Ee]xits?:?%s*(.*)")
            if exits_str then
                for exit in exits_str:gmatch("[^,]+") do
                    local trimmed = exit:match("^%s*(.-)%s*$")
                    if trimmed and trimmed ~= "" then
                        local capitalized = trimmed:sub(1, 1):upper() .. trimmed:sub(2)
                        result[#result + 1] = capitalized
                    end
                end
            end
        end
        if #result > 0 then return result end
    end

    return {}
end

--- Extract non-cardinal "Lich exits" from room wayto data.
--- These are scripted/special exits that don't correspond to standard directions.
--- @param room table — room table from Map.find_room()
--- @return table — array of {label, cmd, destination} tables
function M.extract_lich(room)
    if not room or not room.wayto then return {} end

    local lich_exits = {}
    for dest_id, wayto in pairs(room.wayto) do
        local wayto_str = tostring(wayto)

        if type(wayto) == "string" and not IGNORED_DIRECTIONS[wayto_str] then
            -- String command exit (e.g. "go door", "climb ladder")
            local dest = Map.find_room(tonumber(dest_id))
            local dest_name = "?"
            if dest and dest.title then
                dest_name = type(dest.title) == "table" and dest.title[1] or tostring(dest.title)
                dest_name = dest_name:gsub("%[", ""):gsub("%]", "")
            end
            lich_exits[#lich_exits + 1] = {
                label = wayto_str,
                cmd = wayto_str,
                destination = dest_name,
            }
        elseif type(wayto) == "function" then
            -- StringProc/function exit — use go2 navigation
            local dest = Map.find_room(tonumber(dest_id))
            local dest_name = "?"
            if dest and dest.title then
                dest_name = type(dest.title) == "table" and dest.title[1] or tostring(dest.title)
                dest_name = dest_name:gsub("%[", ""):gsub("%]", "")
            end
            lich_exits[#lich_exits + 1] = {
                label = ";go2 " .. dest_id,
                cmd = ";go2 " .. dest_id,
                destination = dest_name,
            }
        end
    end

    return lich_exits
end

--- Extract trash containers from room tags.
--- Looks for tags matching "meta:trashcan:*" pattern.
--- @param room table — room table from Map.find_room()
--- @return table — array of trash container name strings
function M.extract_trash(room)
    if not room or not room.tags then return {} end

    local containers = {}
    for _, tag in ipairs(room.tags) do
        local container = tag:match("^meta:trashcan:(.+)")
        if container then
            containers[#containers + 1] = container:match("^%s*(.-)%s*$")
        end
    end
    return containers
end

return M
