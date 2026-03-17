--- @revenant-script
--- name: looker
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Periodically sends LOOK at random intervals to stay active
--- tags: afk, idle

local delays = {30, 40, 50, 60, 35, 45, 55, 65, 37, 47, 57}

while true do
    fput("look")
    pause(delays[math.random(#delays)])
end
