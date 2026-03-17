--- @revenant-script
--- name: roomnumbers
--- version: 1.0
--- author: Geldan, adapted by Tysong
--- game: dr
--- description: Append Lich room ID to in-game room title.
--- tags: room, navigation, utility

local room_ready = false

DownstreamHook.add("roomnumbers_hook", function(line)
    if line:find('<style id="roomName"') then
        room_ready = true
    end
    if room_ready and line:find("^Obvious") then
        local room_id = Room.current and Room.current.id
        if room_id then
            respond("Room ID: " .. tostring(room_id))
        end
        room_ready = false
    end
    return line
end)

before_dying(function()
    DownstreamHook.remove("roomnumbers_hook")
end)

while true do
    pause(5)
end
