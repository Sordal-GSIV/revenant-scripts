--- @revenant-script
--- name: safety
--- version: 1.0.0
--- author: Alastir
--- game: gs
--- description: Room safety assessment and creature disabling based on profession
--- tags: combat, safety, utility
---
--- Provides Safety module functions for other scripts to call.
--- Safety.unsafe() returns true if room has 3+ creatures.

local Safety = {}

function Safety.unsafe()
    local count = #GameObj.targets()
    if count >= 3 then
        echo("Room: " .. Room.id .. " -- Creatures: " .. count .. " -- Danger!")
        return true
    else
        echo("Room: " .. Room.id .. " -- Creatures: " .. count .. " -- Acceptable.")
        return false
    end
end

function Safety.stance_offensive()
    while checkstance() ~= "offensive" do
        waitrt()
        fput("stance offensive")
        pause(0.3)
    end
end

function Safety.depress()
    if Spell[1015] and Spell[1015].known and Spell[1015].affordable and not Spell[1015].active then
        Spell[1015].cast()
        waitcastrt()
    end
end

-- Run assessment
Safety.unsafe()

return Safety
