--- @revenant-script
--- name: spellharness
--- version: 1.0
--- author: Demrin
--- game: dr
--- description: Harness mana alongside spellpractice to train attunement
--- tags: magic, attunement, harness, training
---
--- Usage: ;spellharness <amount>
--- Example: ;spellharness 4

local amount = Script.vars[1]
if not amount then
    echo("Usage: ;spellharness <amount of mana to harness>")
    return
end

while true do
    waitfor("You raise your head skyward")
    waitrt()
    fput("harness " .. amount)
end
