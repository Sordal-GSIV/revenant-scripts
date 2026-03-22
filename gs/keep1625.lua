--- @revenant-script
--- name: keep1625
--- version: 1.0
--- author: Hailye
--- game: gs
--- description: Re-infuse 1625 when violet flames are extinguished. Pauses bigshot during cast.
--- @lic-certified: complete 2026-03-19

silence_me()

while true do
    waitfor("violet flames surrounding it are extinguished")
    if Char.mana > 30 then
        if running("bigshot") then pause_script("bigshot") end
        waitrt()
        waitcastrt()
        fput("prep 110")
        fput("infuse my " .. checkright())
        pause(0.2)
        waitrt()
        waitcastrt()
        pause(0.2)
        fput("beseech my " .. checkright() .. " conserve")
        if running("bigshot") then unpause_script("bigshot") end
    end
end
