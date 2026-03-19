--- @revenant-script
--- name: efamgo2
--- version: 2.0.0
--- author: elanthia-online
--- original-author: Drafix
--- game: any
--- description: Navigate your familiar/eye companion to a room via pathfinding
--- tags: movement,go2,familiar,eye
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from Lich5):
---   v1.0.0 (2025-05-01) - Fork from famgo2.lic, added u##### UID support
---   v2.0.0 (Revenant)   - Full Lua port with room-by-details matching, Familiar API
---
--- Usage: ;efamgo2 <room_id>  or  ;efamgo2 u<uid>

--------------------------------------------------------------------------------
-- Companion type detection
--------------------------------------------------------------------------------

local PROFESSION_MAP = {
    Wizard   = "familiar",
    Sorcerer = "eye",
}

local companion_type = PROFESSION_MAP[Stats.prof]
if not companion_type then
    echo("Your profession (" .. (Stats.prof or "unknown") .. ") doesn't have a companion.")
    return
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
-- Room resolution from argument
--------------------------------------------------------------------------------

local function resolve_room(arg)
    if not arg or arg == "" then return nil end

    -- UID format: u12345
    if arg:match("^u%d+$") then
        local uid = tonumber(arg:sub(2))
        local ids = Map.ids_from_uid(uid)
        if ids and #ids > 0 then
            return Map.find_room(ids[1])
        end
        echo("Room with UID " .. uid .. " not found in map database.")
        return nil
    end

    -- Numeric room ID
    if arg:match("^%d+$") then
        local room = Map.find_room(tonumber(arg))
        if room then return room end
        echo("Room " .. arg .. " not found in map database.")
        return nil
    end

    echo("Invalid room format: " .. arg .. " (use a number or u<uid>)")
    return nil
end

--------------------------------------------------------------------------------
-- Locate companion's current room
--------------------------------------------------------------------------------

--- Try to find room by UID embedded in the familiar room title.
--- Lich5 pattern: title ends with "] (<id>)" where id is a server UID.
local function find_room_by_uid()
    local title = Familiar.room_title
    if not title or title == "" then return nil end

    local id_str = title:match("%] %((-?%d+)%)$")
    if not id_str then return nil end

    local uid = tonumber(id_str)
    if not uid then return nil end

    local ids = Map.ids_from_uid(uid)
    if ids and #ids > 0 then
        return Map.find_room(ids[1])
    end
    return nil
end

--- Try to find room by matching title, description, and exits against the map.
local function find_room_by_details()
    local title = Familiar.room_title
    local description = Familiar.room_description
    local exits = Familiar.room_exits

    if not title or title == "" then return nil end
    if not description or description == "" then return nil end

    title = title:match("^%s*(.-)%s*$") or title
    description = description:match("^%s*(.-)%s*$") or description

    -- Build an exits string for matching
    local exits_str = nil
    if exits and type(exits) == "table" and #exits > 0 then
        exits_str = table.concat(exits, ", ")
    end

    -- Search all rooms for a match
    local room_ids = Map.list()
    if not room_ids then return nil end

    -- First pass: exact match on title + description + exits
    for _, rid in ipairs(room_ids) do
        local room = Map.find_room(rid)
        if room then
            -- Title match (room title may contain brackets, compare substring)
            local room_title = room.title or ""
            if room_title:find(title, 1, true) then
                -- Description match
                local room_desc = room.description or ""
                if room_desc:find(description, 1, true) then
                    -- Exits match (if we have exits info)
                    if not exits_str or (room.paths and #room.paths > 0) then
                        if not exits_str then
                            return room
                        end
                        for _, path in ipairs(room.paths) do
                            if path:find(exits_str, 1, true) then
                                return room
                            end
                        end
                    end
                end
            end
        end
    end

    -- Second pass: regex-relaxed description match (periods become wildcards)
    if description and description ~= "" then
        -- Escape the description for use as a Lua pattern, then relax periods
        local desc_pattern = description:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
        desc_pattern = desc_pattern:gsub("%%%.", ".")  -- periods become single-char wildcard

        for _, rid in ipairs(room_ids) do
            local room = Map.find_room(rid)
            if room then
                local room_title = room.title or ""
                if room_title:find(title, 1, true) then
                    if not exits_str or (room.paths and #room.paths > 0) then
                        local exits_ok = not exits_str
                        if not exits_ok then
                            for _, path in ipairs(room.paths) do
                                if path:find(exits_str, 1, true) then
                                    exits_ok = true
                                    break
                                end
                            end
                        end
                        if exits_ok then
                            local room_desc = room.description or ""
                            if room_desc:find(desc_pattern) then
                                return room
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

--- Locate the companion's current room by having it look around.
local function locate_companion()
    companion_cmd("look")

    -- Wait briefly for the server to respond with familiar room data
    pause(1)

    -- Try UID-based lookup first (fastest, most reliable)
    local room = find_room_by_uid()
    if room then return room end

    -- Fall back to matching by title/description/exits
    room = find_room_by_details()
    if room then return room end

    echo("Could not determine companion's location.")
    echo("Make sure your companion is summoned and visible.")
    return nil
end

--------------------------------------------------------------------------------
-- Parse direction from a wayto command string
--------------------------------------------------------------------------------

local function parse_direction(wayto_cmd)
    if not wayto_cmd or wayto_cmd == "" then return nil end

    -- Strip leading "go " or "climb " prefix
    local stripped = wayto_cmd:match("^go%s+(.+)$")
        or wayto_cmd:match("^climb%s+(.+)$")
        or wayto_cmd

    return stripped
end

--------------------------------------------------------------------------------
-- Navigate companion step-by-step along wayto path
--------------------------------------------------------------------------------

local function navigate(start_room, dest_room)
    if start_room.id == dest_room.id then
        echo("Companion is already at the destination.")
        return true
    end

    -- Get the command path from pathfinder
    local commands = Map.find_path(start_room.id, dest_room.id)
    if not commands or #commands == 0 then
        echo("No path found between room " .. start_room.id .. " and room " .. dest_room.id)
        return false
    end

    -- Step through each command in the path
    for i, cmd in ipairs(commands) do
        local direction = parse_direction(cmd)
        if direction then
            companion_move(direction)
        else
            echo("Warning: could not parse direction from '" .. cmd .. "' (step " .. i .. ")")
            echo("Script pausing — resolve the situation manually, then unpause.")
            pause_script(Script.name)
        end
        pause(0.5)
    end

    echo("Navigation complete.")
    return true
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local dest_arg = Script.vars[1]

if not dest_arg or dest_arg == "" then
    echo("Usage: ;" .. Script.name .. " <room_id>  or  ;" .. Script.name .. " u<uid>")
    return
end

local dest_room = resolve_room(dest_arg)
if not dest_room then return end

echo("Locating " .. companion_type .. "...")

local start_room = locate_companion()
if not start_room then return end

echo("Navigating " .. companion_type .. " from room " .. start_room.id .. " to room " .. dest_room.id .. "...")

local ok, err = pcall(navigate, start_room, dest_room)
if not ok then
    echo("Navigation error: " .. tostring(err))
end

echo("Finished.")
