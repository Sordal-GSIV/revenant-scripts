--- @revenant-script
--- name: arcana
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Arcana/Utility training via spell casting with cambrinth.
--- tags: magic, arcana, utility, training
---
--- Usage: ;arcana <Arcana|Utility> [spell]

local skill = Script.vars[1]
if not skill or (skill:lower() ~= "arcana" and skill:lower() ~= "utility") then
    echo("Expecting either Arcana or Utility")
    return
end
skill = skill:sub(1, 1):upper() .. skill:sub(2):lower()

local start_time = os.time()
local spell = Script.vars[2] or "Shadowling"
local cams = {"my cam armband", "my second cam armband", "my cam orb"}
local cam_charge_amt = 10
local min_mana = 60

echo(tostring(start_time))
while DRSkill.getxp(skill) < 34 do
    fput("prepare " .. spell)
    for _, cam in ipairs(cams) do
        fput("charge " .. cam .. " " .. cam_charge_amt)
        waitrt()
        fput("invoke " .. cam)
        waitrt()
    end
    pause(1)
    waitfor("fully prepared to cast")
    pause(3)
    fput("cast")
    waitrt()
    while checkmana() < min_mana do
        pause(1)
    end
end
local end_time = os.time()
echo("Locked " .. skill .. " in: " .. tostring(end_time - start_time) .. " seconds..")
