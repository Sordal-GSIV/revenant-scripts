--- @revenant-script
--- name: moonie_attunement
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Train Attunement via perceive + shadowling cycle until locked
--- tags: moonmage, attunement, training

local start_time = os.time()
echo("Script for Attunement training beginning")

local perceives = {"psych", "trans", "perce", "moonlight", "moons"}

while DRSkill.getxp("Attunement") < 34 do
    for _, perce in ipairs(perceives) do
        fput("perceive " .. perce)
        waitrt()
    end
    fput("prep shadowling")
    pause(15)
    fput("cast")
    waitrt()
    fput("perce shadowling")
    waitrt()
end

local elapsed = os.time() - start_time
echo("Locked Attunement in: " .. elapsed .. " seconds.")
