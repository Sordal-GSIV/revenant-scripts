--- @revenant-script
--- name: spellcharge
--- version: 1.0
--- author: Demrin
--- game: dr
--- description: Charge and invoke cambrinth alongside spellpractice.
--- tags: magic, cambrinth, training
---
--- Usage: ;spellcharge <cambrinth_item> <mana_amount> [harness]

local item = Script.vars[1]
local amount = Script.vars[2]
local mode = Script.vars[3]

if not item or not amount then
    echo("Usage: ;spellcharge <cambrinth_item> <mana_amount> [harness]")
    return
end

local trigger = mode == "harness" and "You tap into" or "You raise your head skyward"

while true do
    local line = waitfor(trigger)
    waitrt()
    fput("charge my " .. item .. " " .. amount)
    waitfor("attempt to channel it into")
    waitrt()
    fput("invoke my " .. item)
    waitfor("You reach for its center")
end
