--- @revenant-script
--- name: constellations
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Observe constellations and predict via telescope.
--- tags: moonmage, astronomy, training
--- Converted from constellations.lic

-- Constellation data map (name -> {level, {skill categories}})
-- Core observation and prediction loop

echo("=== Constellations ===")
echo("Observing sky and predicting...")

fput("observe sky")
pause(1)

-- Get telescope ready
if checkright() ~= "telescope" then
    fput("get telescope")
end
fput("open tele")

local targets = {"sun", "Katamba", "Xibar", "Yavash"}
for _, target in ipairs(targets) do
    waitrt()
    fput("center tele on " .. target)
    fput("focus tele")
    pause(5)
    waitrt()
    fput("peer tele")
    local line = get()
    if line and (line:find("learned something useful") or line:find("learned more")) then
        fput("predict state all")
        waitrt()
        break
    end
end

fput("close tele")
fput("stow tele")
