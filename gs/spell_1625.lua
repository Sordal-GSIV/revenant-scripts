--- @revenant-script
--- name: spell_1625
--- version: 1.0
--- author: Hailye
--- game: gs
--- description: Infuse 1625 with spell 110 -- gird, prep, infuse, beseech conserve, store all.
--- @lic-certified: complete 2026-03-19

wait_until(function() return checkmana(30) end)

if Char.mana > 30 then
    fput("gird")
    fput("prep 110")
    fput("infuse my " .. checkright())
    pause(0.2)
    waitrt()
    waitcastrt()
    pause(0.2)
    fput("beseech my " .. checkright() .. " conserve")
    fput("store all")
end
