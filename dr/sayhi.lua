--- @revenant-script
--- name: sayhi
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Say hi to anyone who enters the room
--- tags: social, greeting

while true do
    local line = waitfor("just arrived")
    local name = line:match("^(%S+) just arrived")
    if name then
        put("'Hi there " .. name .. "!")
    end
end
