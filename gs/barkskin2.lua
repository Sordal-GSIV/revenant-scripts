--- @revenant-script
--- name: barkskin2
--- version: 1.0
--- author: Ralkean
--- game: gs
--- description: Activate and refresh Barkskin (605). Waits for 2s idle before casting. Skips while hidden.

local function able_to_cast()
    return checkrt() == 0
        and checkcastrt() == 0
        and not hidden()
        and not stunned()
        and not webbed()
        and not Effects.Debuffs.active("Silenced")
        and not Effects.Debuffs.active("Bind")
        and not dead()
end

while true do
    if able_to_cast() then
        pause(1)
        if able_to_cast() then
            pause(1)
            if able_to_cast() and not Spell[605]:active() and not Effects.Cooldowns.active("Barkskin") then
                if (not checkgrouped() or Skills.spiritual_lore_blessings < 50) and checkmana() >= 5 then
                    put("incant 605")
                    pause(1)
                elseif checkmana() >= 15 then
                    put("incant 605 evoke")
                    pause(1)
                end
                if Spell[605]:active() then
                    pause(57)
                end
            end
        end
    end
    pause(1)
end
