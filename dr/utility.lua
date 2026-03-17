--- @revenant-script
--- name: utility
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Train Utility skill via Perception Guardian charge/invoke/cast cycle
--- tags: magic, utility, training

echo("##############UTILITY SKILL BEGINNING####################")
local camitem = "cam armband"
local charge_amount = 15
local container = "pack"

fput("stow left")
fput("stow right")
fput("remove my " .. camitem)

while DRSkill.getxp("Utility") < 34 do
    while checkmana() > 75 do
        fput("prep pg 15")
        fput("charge my " .. camitem .. " " .. charge_amount)
        waitrt()
        pause(1)
        fput("invoke my " .. camitem)
        waitrt()
        pause(1)
        waitfor("You feel fully prepared to cast")
        fput("cast " .. container)
        waitrt()
    end
end

echo("##############UTILITY SKILL LOCKED####################")
