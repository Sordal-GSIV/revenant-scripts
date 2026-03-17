--- @revenant-script
--- name: efamgo2
--- version: 1.0.0
--- author: elanthia-online
--- game: any
--- description: Navigate your familiar/eye companion to a room via pathfinding
--- tags: movement,go2,familiar,eye
---
--- Changelog (from Lich5):
---   v1.0.0 (2025-05-01) - Fork from famgo2.lic, added u##### UID support
---
--- Usage: ;efamgo2 <room_id>  or  ;efamgo2 u<uid>

--------------------------------------------------------------------------------
-- Companion type detection
--------------------------------------------------------------------------------

local PROFESSION_MAP = {
    Wizard   = "familiar",
    Sorcerer = "eye",
}

local companion_type = PROFESSION_MAP[Char.prof]
if not companion_type then
    echo("Your profession (" .. (Char.prof or "unknown") .. ") doesn't have a companion.")
    return
end

--------------------------------------------------------------------------------
-- Room resolution
--------------------------------------------------------------------------------

local function resolve_room(arg)
    if not arg or arg == "" then return nil end

    -- UID format: u12345
    if arg:match("^u%d+$") then
        local uid = tonumber(arg:sub(2))
        local room_id = Map.id_from_uid(uid)
        if room_id then return Room[room_id] end
        echo("Room with UID " .. uid .. " not found in map database.")
        return nil
    end

    -- Numeric room ID
    if arg:match("^%d+$") then
        local room = Room[tonumber(arg)]
        if room then return room end
        echo("Room " .. arg .. " not found in map database.")
        return nil
    end

    echo("Invalid room format: " .. arg .. " (use a number or u<uid>)")
    return nil
end

--------------------------------------------------------------------------------
-- Companion commands
--------------------------------------------------------------------------------

local function companion_cmd(action)
    fput("tell " .. companion_type .. " to " .. action)
end

local function companion_move(direction)
    companion_cmd("go " .. direction)
end

--------------------------------------------------------------------------------
-- Locate companion's current room
--------------------------------------------------------------------------------

local function locate_companion()
    companion_cmd("look")
    fput("look " .. Char.name)
    pause(1)

    -- Try to find room from familiar room title (XMLData equivalent)
    -- In Revenant, we check GameState.familiar_room if available
    if GameState.familiar_room then
        return Room[GameState.familiar_room]
    end

    -- Fallback: try to detect from output
    echo("Could not determine companion's location automatically.")
    echo("Make sure your companion is summoned and try again.")
    return nil
end

--------------------------------------------------------------------------------
-- Pathfinding and navigation
--------------------------------------------------------------------------------

local function navigate(start_room, dest_room)
    if start_room.id == dest_room.id then
        echo("Companion is already at the destination.")
        return true
    end

    -- Calculate path using Dijkstra
    local previous = Map.dijkstra(start_room.id, dest_room.id)
    if not previous or not previous[dest_room.id] then
        echo("No path found between room " .. start_room.id .. " and " .. dest_room.id)
        return false
    end

    -- Build path
    local path = { dest_room.id }
    while previous[path[#path]] do
        path[#path + 1] = previous[path[#path]]
    end
    -- Reverse
    local reversed = {}
    for i = #path, 1, -1 do reversed[#reversed + 1] = path[i] end
    path = reversed

    -- Walk the path
    local current = start_room
    for i = 2, #path do
        local next_id = path[i]
        local wayto = current.wayto and current.wayto[tostring(next_id)]

        if type(wayto) == "string" then
            -- Parse direction from wayto string
            local direction = wayto:match("^go%s+(.+)$") or wayto:match("^climb%s+(.+)$") or wayto
            companion_move(direction)
        else
            -- Try to extract direction from proc inspection
            echo("Warning: complex procedure at room " .. current.id .. ", may need manual intervention.")
        end

        pause(0.5)
        current = Room[next_id]
        if not current then break end
    end

    echo("Navigation complete.")
    return true
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local dest_arg = Script.vars[1]

if not dest_arg or dest_arg == "" then
    echo("Usage: ;efamgo2 <room_id>  or  ;efamgo2 u<uid>")
    return
end

local dest_room = resolve_room(dest_arg)
if not dest_room then return end

local start_room = locate_companion()
if not start_room then return end

echo("Navigating " .. companion_type .. " from room " .. start_room.id .. " to room " .. dest_room.id .. "...")

navigate(start_room, dest_room)
echo("Finished.")
