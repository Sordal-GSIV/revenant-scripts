--- @revenant-script
--- name: arcana_endless
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Endless arcana/utility training loop with cambrinth.
--- tags: magic, arcana, training
---
--- Usage: ;arcana_endless <Arcana|Utility> [spell]

local skill = Script.vars[1]
if not skill or (skill:lower() ~= "arcana" and skill:lower() ~= "utility") then
    echo("Expecting either Arcana or Utility")
    return
end
skill = skill:sub(1, 1):upper() .. skill:sub(2):lower()

local spell = Script.vars[2] or "Shadowling"
local cams = {"my cam armband", "my second cam armband"}
local cam_charge_amt = 11
local min_mana = 60

while true do
    fput("prepare " .. spell)
    for _, cam in ipairs(cams) do
        pause(2)
        fput("charge " .. cam .. " " .. cam_charge_amt)
        waitrt()
        pause(3)
        fput("invoke " .. cam)
        waitrt()
    end
    pause(18)
    fput("cast")
    waitrt()
    fput("perce shadowling")
    waitrt()
    while checkmana() < min_mana do
        pause(1)
    end
end
