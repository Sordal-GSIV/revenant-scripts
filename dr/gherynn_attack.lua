--- @revenant-script
--- name: gherynn_attack
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Melee attack loop with Disturb Outcast spell for sprite hunting
--- tags: combat, magic, sprite

while true do
    while checkstamina() > 85 do
        fput("attack")
        waitrt()
    end
    fput("ret")
    fput("ret")
    fput("prep do 10")
    fput("targ sprite")
    fput("hide")
    waitrt()
    fput("advance")
    pause(6)
    fput("cast")
    waitrt()
    pause(3)
end
