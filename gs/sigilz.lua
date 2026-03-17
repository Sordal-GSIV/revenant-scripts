--- @revenant-script
--- name: sigilz
--- version: 2.0.0
--- author: Hailye
--- contributors: Ifor Get, SpiffyJr, Tillmen, elanthia-online
--- game: gs
--- description: GoS sigil maintenance with GUI setup support
--- tags: GoS, sigils, society
---
--- Usage:
---   ;sigilz        - Run with current settings
---   ;sigilz setup  - Configure (text mode in Revenant)

CharSettings["sigilz_spells"] = CharSettings["sigilz_spells"] or {}

if script.vars[1] == "setup" then
    echo("Sigilz Setup - configure which sigils to maintain:")
    echo("Set via: ;e CharSettings['sigilz_spells']['9703'] = true")
    echo("Available sigils: 9703-9719")
    for num, active in pairs(CharSettings["sigilz_spells"]) do
        if active then echo("  " .. num .. ": ACTIVE") end
    end
    exit()
end

echo("Sigilz running. Use ;kill sigilz to stop.")

while true do
    if checkdead and checkdead() then exit() end
    waitrt(); waitcastrt()

    for num_str, active in pairs(CharSettings["sigilz_spells"]) do
        if active then
            local num = tonumber(num_str)
            local spell = Spell[num]
            if spell and spell.known and not spell.active and spell.affordable then
                spell.cast()
                waitrt(); waitcastrt()
                pause(0.2)
            end
        end
    end
    pause(3)
end
