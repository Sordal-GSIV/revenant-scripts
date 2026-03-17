--- @revenant-script
--- name: roomexits
--- version: 1.0
--- author: Tysong
--- game: dr
--- description: Display non-cardinal room exits from map database.
--- tags: room, exits, navigation
---
--- Converted from roomexits.lic

local room_ready = false

DownstreamHook.add("roomexits_hook", function(line)
    if line:find('<style id="roomName"') then
        room_ready = true
    end
    if room_ready and line:find("^Obvious") then
        local room = Room.current
        if room and room.wayto then
            local exits = {}
            for key, value in pairs(room.wayto) do
                if type(value) == "string" then
                    local cardinal = value:match("^[nsew]+$") or value:match("^out$")
                        or value:match("^up$") or value:match("^down$")
                        or value:match("^north") or value:match("^south")
                        or value:match("^east") or value:match("^west")
                        or value:match("^northwest") or value:match("^northeast")
                        or value:match("^southwest") or value:match("^southeast")
                    if not cardinal then
                        table.insert(exits, value)
                    end
                end
            end
            if #exits > 0 then
                respond("Room Exits: " .. table.concat(exits, ", "))
            end
        end
        room_ready = false
    end
    return line
end)

before_dying(function()
    DownstreamHook.remove("roomexits_hook")
end)

while true do
    pause(5)
end
