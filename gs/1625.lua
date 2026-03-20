--- @revenant-script
--- name: 1625
--- version: 1.0
--- author: Hailye
--- game: gs
--- description: One-shot infuse 1625 (or any spell in right hand) — waits for mana, girds, preps 110, infuses, beseeches conserve, stores.
--- @lic-certified: complete 2026-03-19

wait_until("Waiting until 30 mana or more!", function() return checkmana(30) end)
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
