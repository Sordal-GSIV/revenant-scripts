--- @revenant-script
--- name: randowalk
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Walk in a random direction each time. Pass a direction as argument to go that way first.

if Script.vars[1] then
    fput(Script.vars[1])
end

local dirs = { "n", "s", "e", "w", "ne", "nw", "se", "sw", "up", "down", "out" }

while true do
    local dir = dirs[math.random(#dirs)]
    fput(dir)
    pause(0.5)
end
