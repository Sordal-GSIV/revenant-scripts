--- @revenant-script
--- name: showexits
--- version: 1.0.1
--- author: elanthia-online
--- description: Show current map DB exits for a room with clickable links
--- tags: mapdb,exits,paths,utility
---
--- Usage:
---   ;showexits         show exits for current room
---   ;showexits 228     show exits for Lich room 228
---   ;showexits u3003   show exits for UID 3003

local TableRender = require("lib/table_render")

local function resolve_room(arg)
    if not arg or arg == "" then
        return Map.current_room()
    end
    local uid = arg:match("^u(%d+)$")
    if uid then
        local ids = Map.ids_from_uid(tonumber(uid))
        return ids and ids[1] or nil
    end
    return tonumber(arg)
end

local CARDINAL_DIRS = {
    o = true, d = true, u = true,
    n = true, ne = true, e = true, se = true,
    s = true, sw = true, w = true, nw = true,
    out = true, down = true, up = true,
    north = true, northeast = true, east = true, southeast = true,
    south = true, southwest = true, west = true, northwest = true,
}

local LONGDIR = {
    n = "north", ne = "northeast", e = "east", se = "southeast",
    s = "south", sw = "southwest", w = "west", nw = "northwest",
    u = "up", d = "down", o = "out",
}

local function show_exits(room_id)
    if not room_id then
        echo("Room not found.")
        return
    end
    local room = Map.find_room(room_id)
    if not room or not room.wayto then
        echo("No room data for " .. tostring(room_id))
        return
    end

    local tbl = TableRender.new({"Room #", "Wayto", "Room Name", "Room Location"})
    local has_rows = false

    -- Cardinal directions first
    for dest_id, wayto in pairs(room.wayto) do
        local w = tostring(wayto)
        if CARDINAL_DIRS[w] then
            local dest = Map.find_room(tonumber(dest_id))
            local title = dest and dest.title and dest.title[1] or "?"
            title = title:gsub("%[", ""):gsub("%]", "")
            local loc = dest and dest.location or ""
            local display_dir = LONGDIR[w] or w
            tbl:add_row({dest_id, display_dir, title, loc})
            has_rows = true
        end
    end

    -- Non-cardinal string commands
    for dest_id, wayto in pairs(room.wayto) do
        local w = tostring(wayto)
        if not CARDINAL_DIRS[w] and type(wayto) == "string" then
            local dest = Map.find_room(tonumber(dest_id))
            local title = dest and dest.title and dest.title[1] or "?"
            title = title:gsub("%[", ""):gsub("%]", "")
            local loc = dest and dest.location or ""
            tbl:add_row({dest_id, w, title, loc})
            has_rows = true
        end
    end

    -- StringProc/function waytos
    for dest_id, wayto in pairs(room.wayto) do
        if type(wayto) == "function" then
            local dest = Map.find_room(tonumber(dest_id))
            local title = dest and dest.title and dest.title[1] or "?"
            title = title:gsub("%[", ""):gsub("%]", "")
            local loc = dest and dest.location or ""
            tbl:add_row({dest_id, "StringProc", title, loc})
            has_rows = true
        end
    end

    if not has_rows then
        echo("No exits found.")
        return
    end

    respond(tbl:render())
end

show_exits(resolve_room(Script.vars[1]))
