--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: move2
--- version: 1.0.0
---       author: elanthia-online
---     original: Tillmen (step2.lic)
---         port: Sordal (Revenant Lua conversion)
---         game: any
---         tags: movement, step2, go2
---  description: One-step map-aware movement with room-ID path caching and 3x retry
---
--- Fork of step2.lic by Tillmen. Adds u###### (real/UID) support and 3x retry.
---
--- Usage:
---   ;move2 <room_id>   — advance one step toward Lich map ID
---   ;move2 u<uid>      — advance one step toward real/UID room
---
--- Path is cached across invocations in UserVars._step2_path (JSON room-ID array).
--- Cache is reused if current room and destination both appear in forward order.
---
--- changelog:
---   v1.0.0 (2024-07-06)
---     * initial release, fork from step2.lic
---     * add u##### real-ID support
---     * attempt movement up to 3x before giving up

local ok_sp, stringproc = pcall(require, "lib/stringproc")
if not ok_sp then stringproc = nil end

-- Validate argument: must be numeric or u-prefixed numeric
local dest_arg = Script.vars[1]
if not dest_arg or not dest_arg:match("^u?%d+$") then
    echo("usage: ;move2 <room number>")
    return
end

-- Resolve current room
local start_id = Map.current_room()
if not start_id then
    echo("current room was not found in the map database")
    return
end

-- Resolve destination room ID
local dest_id = nil
if dest_arg:match("^u%d+$") then
    local uid_num = tonumber(dest_arg:match("^u(%d+)$"))
    -- Prefer engine helper if available
    if Map.ids_from_uid then
        local ids = Map.ids_from_uid(uid_num)
        if ids and #ids > 0 then dest_id = ids[1] end
    end
    -- Manual scan fallback
    if not dest_id then
        for _, id in ipairs(Map.list()) do
            local r = Map.find_room(id)
            if r and r.uid then
                if type(r.uid) == "number" and r.uid == uid_num then
                    dest_id = id; break
                elseif type(r.uid) == "string" and tonumber(r.uid) == uid_num then
                    dest_id = id; break
                elseif type(r.uid) == "table" then
                    for _, u in ipairs(r.uid) do
                        if tonumber(u) == uid_num then dest_id = id; break end
                    end
                end
            end
            if dest_id then break end
        end
    end
    if not dest_id then
        echo("destination room was not found in the map database")
        return
    end
else
    dest_id = tonumber(dest_arg)
    if not Map.find_room(dest_id) then
        echo("destination room was not found in the map database")
        return
    end
end

if start_id == dest_id then
    echo("start room and destination room are the same")
    return
end

-------------------------------------------------------------------------------
-- Path cache — UserVars._step2_path: JSON-encoded array of room IDs.
-- Valid if start_id and dest_id appear in path in forward order (start < dest).
-------------------------------------------------------------------------------

local path = nil  -- array of room IDs from start to destination

local cached_raw = UserVars._step2_path
if cached_raw and cached_raw ~= "" then
    local ok, cached = pcall(Json.decode, cached_raw)
    if ok and type(cached) == "table" then
        local start_idx, dest_idx = nil, nil
        for i, rid in ipairs(cached) do
            if rid == start_id  then start_idx = i end
            if rid == dest_id   then dest_idx  = i end
        end
        if start_idx and dest_idx and start_idx < dest_idx then
            path = cached
        end
    end
end

if not path then
    -- Compute path: Map.find_path returns command strings
    local commands = Map.find_path(start_id, dest_id)
    if not commands or #commands == 0 then
        echo("error: failed to find a path between your current room ("
            .. start_id .. ") and destination room (" .. dest_id .. ")")
        return
    end

    -- Reconstruct room-ID sequence by matching commands against wayto entries
    local room_ids = { start_id }
    local current = start_id
    for _, cmd in ipairs(commands) do
        local room = Map.find_room(current)
        if not room or not room.wayto then break end
        local next_id = nil
        for dest_str, wt_cmd in pairs(room.wayto) do
            if wt_cmd == cmd then
                next_id = tonumber(dest_str)
                break
            end
        end
        if not next_id then break end
        room_ids[#room_ids + 1] = next_id
        current = next_id
    end

    path = room_ids
    UserVars._step2_path = Json.encode(path)
end

-------------------------------------------------------------------------------
-- Find next room from current position in path
-------------------------------------------------------------------------------

local start_idx = nil
for i, rid in ipairs(path) do
    if rid == start_id then start_idx = i; break end
end

local next_room_id = start_idx and path[start_idx + 1]
if not next_room_id then
    echo("error: failed to find a path between your current room ("
        .. start_id .. ") and destination room (" .. dest_id .. ")")
    return
end

-- Look up wayto command for the next room
local start_room = Map.find_room(start_id)
if not start_room or not start_room.wayto then
    echo("error in the map database")
    return
end
local way = start_room.wayto[tostring(next_room_id)]
if not way then
    echo("error in the map database")
    return
end

-------------------------------------------------------------------------------
-- Execute movement — up to 3 attempts (parity: 3.times loop in original)
-------------------------------------------------------------------------------

for _ = 1, 3 do
    if Map.current_room() ~= start_id then break end
    waitrt()
    if stringproc and stringproc.is_stringproc(way) then
        -- Proc equivalent: StringProc wayto entry (;e <ruby_code>)
        local fn, _ = stringproc.translate(way)
        if fn then
            stringproc.execute(fn)
        else
            echo("error in the map database")
            break
        end
    else
        -- Plain string command
        pcall(move, way)
    end
end

if Map.current_room() == start_id then
    echo("Movement failed! Please move yourself manually!")
end
