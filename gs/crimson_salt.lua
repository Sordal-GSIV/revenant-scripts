--- @revenant-script
--- name: crimson_salt
--- version: 0.1
--- author: Zedarius
--- game: gs
--- description: Creates crimson salt crystals for Animate Dead using mortar, pestle, flasks, and moonflower
--- tags: alchemy, animate dead, necromancer
---
--- Setup: ;vars set csc_container=<noun>
--- Usage: ;crimson_salt

if script.vars[1] == "help" then
    respond("CRIMSON SALT - Animate Dead Crystal Maker")
    respond("Setup: ;vars set csc_container=<container noun>")
    respond("Ingredients: sea water flask, troll blood flask, moonflower, mortar, pestle, vial")
    exit()
end

local container_noun = Vars.csc_container
if not container_noun or container_noun == "" then
    echo("Set your container: ;vars set csc_container=<noun>")
    echo("Use ;crimson_salt help for details")
    exit()
end

local mortar_noun = Vars.csc_mortar or "mortar"
local pestle_noun = Vars.csc_pestle or "pestle"
local vial_noun = Vars.csc_vial or "vial"

-- Find container
local container = GameObj.inv_find(container_noun)
if not container then echo("Cannot find container: " .. container_noun); exit() end

fput("look in #" .. container.id)
pause(2)

echo("* Crimson Salt: Beginning crystal creation.")

-- Stow hands
waitrt()
if checkright() then fput("stow right"); pause(0.75) end
if checkleft() then fput("stow left"); pause(0.75) end

-- Add first liquid
echo("* Adding first liquid...")
fput("get flask from #" .. container.id); pause(0.75)
fput("get " .. vial_noun .. " from #" .. container.id); pause(0.75)
fput("turn my " .. vial_noun); pause(0.75)
fput("pour my flask in my " .. vial_noun); pause(0.75)
fput("put my flask in #" .. container.id); pause(0.75)
fput("get " .. mortar_noun .. " from #" .. container.id); pause(0.75)
fput("pour my " .. vial_noun .. " in my " .. mortar_noun); pause(0.75)
fput("put my " .. mortar_noun .. " in #" .. container.id); pause(0.75)

-- Add second liquid
echo("* Adding second liquid...")
fput("get flask from #" .. container.id); pause(0.75)
fput("pour my flask in my " .. vial_noun); pause(0.75)
fput("put my flask in #" .. container.id); pause(0.75)
fput("get " .. mortar_noun .. " from #" .. container.id); pause(0.75)
fput("pour my " .. vial_noun .. " in my " .. mortar_noun); pause(0.75)
fput("put my " .. vial_noun .. " in #" .. container.id); pause(0.75)

-- Add moonflower
echo("* Adding moonflower...")
fput("get moonflower from #" .. container.id); pause(0.75)
fput("put moonflower in my " .. mortar_noun); pause(0.75)

-- Get pestle and grind
fput("get " .. pestle_noun .. " from #" .. container.id); pause(0.75)
echo("* Grinding...")
fput("grind moonflower"); pause(1); waitrt()
fput("grind mash"); pause(1); waitrt()
fput("grind mash"); pause(1); waitrt()
fput("grind solution"); pause(1); waitrt()

-- Cast 719
echo("* Casting 719...")
fput("prep 719"); pause(1); waitcastrt()
fput("cast at solution"); pause(1); waitrt()

fput("put my " .. pestle_noun .. " in #" .. container.id); pause(0.75)

-- Wait for reaction
echo("* Waiting for reaction (may take several minutes)...")
while true do
    local line = get()
    if line:match("dark flames.*die down") then break end
    if line:match("shadowy flames arise") then echo("* Reaction begun...") end
end

-- Collect crystals
echo("* Collecting crystals...")
waitrt()
fput("get crystals from my " .. mortar_noun); pause(0.75)
fput("put my " .. mortar_noun .. " in #" .. container.id)
echo("* Done! Apply with: SPREAD CRYSTALS ON <target>")
