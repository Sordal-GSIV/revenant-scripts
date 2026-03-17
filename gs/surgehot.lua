--- @revenant-script
--- name: surgehot
--- version: 1.0
--- author: Snoopy/Psycho, Kaldonis
--- game: gs
--- description: Keep Surge of Strength (9605) active. Handles popped muscles (9699) cooldown.

while true do
    wait_until(function()
        return not Spell[9605]:active() and checkstamina() > 60
    end)

    if Spell[9699]:active() then
        local poptime = Spell[9699]:remaining()
        echo("your muscles are popped, you must wait " .. tostring(poptime))
        wait_while(function() return Spell[9699]:active() end)
        fput("cman surge")
    else
        fput("cman surge")
    end

    pause(1)
end
