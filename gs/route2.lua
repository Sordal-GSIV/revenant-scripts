--- @revenant-script
--- name: route2
--- version: 0.4
--- author: elanthia-online
--- contributors: LostRanger, Deysh, Tysong
--- game: gs
--- description: Show the route between two rooms for mapDB troubleshooting
--- tags: utility,mapdb,route,path
---
--- Usage:
---   ;route2 <target>            show route from current room to target
---   ;route2 <source> <target>   show route between two rooms
---
--- Target can be a room number, tag, or description.

local TableRender = require("lib/table_render")

local function find_room(what, src_id)
    -- Numeric room ID
    if what:match("^%d+$") then
        local id = tonumber(what)
        local rm = Map.find_room(id)
        if rm then return id end
        echo("Room #" .. what .. " does not exist.")
        return nil
    end

    -- Tag lookup
    if src_id then
        local nearest = Map.find_nearest_by_tag(src_id, what)
        if nearest then
            echo("Nearest room tagged '" .. what .. "' is room #" .. nearest)
            return nearest
        end
    end

    -- Description match
    local ids = Map.list()
    if ids then
        for _, id in ipairs(ids) do
            local rm = Map.find_room(id)
            if rm and rm.title then
                for _, t in ipairs(rm.title) do
                    if t:find(what) then
                        echo("First room matching '" .. what .. "' is room #" .. id)
                        return id
                    end
                end
            end
        end
    end

    echo("Could not find room '" .. what .. "'")
    return nil
end

-- Parse arguments
local src_id, tgt_id

if Script.vars[2] and Script.vars[2] ~= "" then
    src_id = find_room(Script.vars[1])
    if not src_id then return end
    tgt_id = find_room(Script.vars[2], src_id)
    if not tgt_id then return end
elseif Script.vars[1] and Script.vars[1] ~= "" then
    src_id = Map.current_room()
    if not src_id then
        echo("Could not identify your current room.")
        echo("Usage: ;route2 [source] target")
        return
    end
    tgt_id = find_room(Script.vars[1], src_id)
    if not tgt_id then return end
else
    echo("Usage: ;route2 [source] target")
    return
end

if src_id == tgt_id then
    echo("Source and target rooms match.")
    return
end

-- Find path
local path = Map.find_path(src_id, tgt_id)
if not path or #path == 0 then
    echo("Path from " .. src_id .. " to " .. tgt_id .. " not found.")
    return
end

-- Build table
local is_gs = GameState.game and GameState.game:match("^GS")
local headers
if is_gs then
    headers = {"STEP", "TRIP", "TIME", "MOVE", "ROOM", "NAME", "LOCATION"}
else
    headers = {"STEP", "TRIP", "TIME", "MOVE", "ROOM", "NAME"}
end

local tbl = TableRender.new(headers)

local src_room = Map.find_room(src_id)
local src_title = src_room and src_room.title and src_room.title[1] or "?"
if is_gs then
    tbl:add_row({"   0:", "", "", "", src_id, src_title, src_room and src_room.location or ""})
else
    tbl:add_row({"   0:", "", "", "", src_id, src_title})
end

local total_time = 0
local rm = src_room

for step, cmd in ipairs(path) do
    -- cmd is the movement command; we need to figure out the destination room
    -- In Revenant, Map.find_path returns commands; extract destination from wayto
    local wayto_str = tostring(cmd)
    if #wayto_str > 20 then
        wayto_str = wayto_str:sub(1, 17) .. "..."
    end

    local stime = "0"
    local sttime = string.format("%8.1f   ", total_time)
    local sstep = string.format("%4d:", step)

    if step % 10 == 0 then
        tbl:add_separator()
    end

    if is_gs then
        tbl:add_row({sstep, sttime, stime, wayto_str, "", "", ""})
    else
        tbl:add_row({sstep, sttime, stime, wayto_str, "", ""})
    end
end

respond(tbl:render())
