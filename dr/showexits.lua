--- @revenant-script
--- name: showexits
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Show map exits for a room with clickable links.
--- tags: navigation, exits, map
--- Converted from showexits.lic

local room_arg = Script.vars[1]
local room = nil
if room_arg then
    if room_arg:match("^u%d+$") then
        local uid = tonumber(room_arg:match("^u(%d+)$"))
        room = Room.from_uid(uid)
    else
        room = Room[tonumber(room_arg)]
    end
else
    room = Room.current
end
if not room then echo("Room not found.") return end

echo("=== Exits for Room " .. tostring(room.id) .. " ===")
if room.wayto then
    for key, value in pairs(room.wayto) do
        local dest = Room[tonumber(key)]
        local name = dest and dest.title and dest.title[1] or "unknown"
        echo(string.format("  %s -> %s (%s)", tostring(key), tostring(value), name))
    end
end
