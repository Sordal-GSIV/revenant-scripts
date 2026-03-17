--- @revenant-script
--- name: tremor
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Keep Tremor spell active, recast when it fades.
--- tags: magic, tremor, combat
---
--- Usage: ;tremor <prep_amount>

local prep_amount = tonumber(Script.vars[1])
if not prep_amount then
    echo("Please supply a prep amount")
    return
end

Flags.add("tremor-worn-off", "The violent heaving of the earth finally subsides")

local function cast_tremor(prep)
    DRC.bput("pre tremor " .. prep, "You trace an angular sigil in the air")
    Flags.reset("tremor-worn-off")
    waitfor("You feel fully prepared to cast your spell")
    DRC.bput("cast", "The earth beneath your feet begins to shake violently")
end

cast_tremor(prep_amount)

while true do
    local line = get()
    if Flags["tremor-worn-off"] then
        cast_tremor(prep_amount)
    end
end
