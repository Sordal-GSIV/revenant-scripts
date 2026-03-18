--- @revenant-script
--- name: show
--- version: 1.0
--- author: Drafix
--- game: dr
--- description: Shows the room matching a room ID or tag, like a whereis command.
--- tags: room, map, navigation
---
--- Usage:
---   ;show town
---   ;show 228

local arg1 = Script.vars[1]
if not arg1 then
    echo("Usage: ;show <room_id or tag>")
    return
end

if arg1:match("^%d+$") then
    local room = Room[tonumber(arg1)]
    if not room then
        echo("Destination room was not found in the map database.")
        return
    end
    echo(tostring(room))
else
    local room = Room.current()
    local id = room and room.find_nearest_by_tag and room.find_nearest_by_tag(arg1)
    if not id then
        echo(tostring(arg1) .. " was not found in the map database.")
        return
    end
    local room = Room[id]
    echo(tostring(room))
end
