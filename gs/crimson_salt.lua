--- @revenant-script
--- name: crimson_salt
--- version: 0.1
--- author: Zedarius
--- game: gs
--- description: Creates crimson salt crystals for Animate Dead using mortar, pestle, flasks, and moonflower
--- tags: alchemy, animate dead, necromancer
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 author: Zedarius (reach out to @Zedarius on Discord with any issues)
--- Ported to Revenant Lua from crimson_salt.lic
---
--- Setup: ;vars set csc_container=<noun>
--- Optional: ;vars set csc_mortar=<noun>  (default: mortar)
---           ;vars set csc_pestle=<noun>  (default: pestle)
---           ;vars set csc_vial=<noun>    (default: vial)
--- Usage: ;crimson_salt           -- make a batch
---        ;crimson_salt help      -- show help

local HELP = [[
  **  CRIMSON SALT  --  Animate Dead Crystal Maker  **

  Creates one batch of crimson salt crystals per run.
  Extends Animate Dead from 10 min to 20+ min.

  * INGREDIENTS *  (consumed each run)
      Sea water   -- one measure  (crystal flask)
      Troll blood -- one measure  (crystal flask)
      Moonflower  -- one, or a bundle

  * EQUIPMENT *  (kept in your container between runs)
      Mortar (converted to GRIND verb)
      Pestle
      Glass vial
      Two small crystal flasks (one water, one blood)

  * SETUP *  (run once per character)
      ;vars set csc_container=<noun>
      Example:  ;vars set csc_container=tube

  * Optional overrides * (only if items have unusual nouns):
      ;vars set csc_mortar=<noun>     (default: mortar)
      ;vars set csc_pestle=<noun>     (default: pestle)
      ;vars set csc_vial=<noun>       (default: vial)

  * USAGE *
      ;crimson_salt           -- make a batch
      ;crimson_salt help      -- show this screen

  Apply crystals with:  SPREAD CRYSTALS ON {dead target}
  Questions?  Reach out to @Zedarius on Discord.
]]

-- ---- Helpers ----------------------------------------------------------------

local function csc_abort(msg)
    respond("*** Crimson Salt: " .. msg)
    respond("*** Aborting.")
    exit()
end

--- Find an item inside a container's contents by noun or name
local function csc_find_in(container_obj, noun)
    if not container_obj or not container_obj.contents then return nil end
    for _, o in ipairs(container_obj.contents) do
        if o.noun and o.noun:lower():match(noun:lower()) then
            return o
        end
    end
    for _, o in ipairs(container_obj.contents) do
        if o.name and o.name:lower():match(noun:lower()) then
            return o
        end
    end
    return nil
end

-- ---- Argument parsing -------------------------------------------------------

local arg1 = (Script.vars[1] or ""):lower()
if arg1 == "help" or arg1 == "setup" then
    respond(HELP)
    respond("  Run \";crimson_salt help\" at any time to see this again.")
    exit()
elseif arg1 ~= "" then
    respond("*** Crimson Salt: Unknown argument '" .. arg1 .. "'.")
    respond("***   Valid arguments: help, setup")
    respond("***   To make crystals, run: ;crimson_salt")
    exit()
end

-- ---- Validate configuration -------------------------------------------------

local container_noun = UserVars.csc_container
local mortar_noun = (UserVars.csc_mortar and UserVars.csc_mortar ~= "") and UserVars.csc_mortar or "mortar"
local pestle_noun = (UserVars.csc_pestle and UserVars.csc_pestle ~= "") and UserVars.csc_pestle or "pestle"
local vial_noun = (UserVars.csc_vial and UserVars.csc_vial ~= "") and UserVars.csc_vial or "vial"

if not container_noun or container_noun == "" then
    respond(HELP)
    respond("  Run \";crimson_salt help\" at any time to see this again.")
    exit()
end

-- ---- Locate container and load its contents ---------------------------------

local container = nil
for _, o in ipairs(GameObj.inv()) do
    if o.noun and o.noun:lower():match(container_noun:lower()) then
        container = o
        break
    end
end
if not container then
    for _, o in ipairs(GameObj.inv()) do
        if o.name and o.name:lower():match(container_noun:lower()) then
            container = o
            break
        end
    end
end
if not container then
    csc_abort("Cannot find your container ('" .. container_noun .. "') in inventory.")
end

-- Wait for the full container listing so the engine can parse contents
dothistimeout("look in #" .. container.id, 10, "Total items:")
local deadline = os.time() + 5
while not container.contents and os.time() < deadline do
    pause(0.1)
end
if not container.contents then
    csc_abort("Could not read the contents of your " .. container_noun .. ". Is it open?")
end

-- ---- Check equipment and ingredients ----------------------------------------

respond("* Crimson Salt: Checking equipment and ingredients...")

local mortar = csc_find_in(container, mortar_noun)
local pestle = csc_find_in(container, pestle_noun)
local vial = csc_find_in(container, vial_noun)

-- Find all flasks
local flasks = {}
for _, o in ipairs(container.contents) do
    if o.noun and o.noun:lower():match("flask") then
        table.insert(flasks, o)
    end
end

-- Find moonflower
local moonflower = nil
for _, o in ipairs(container.contents) do
    if (o.noun and o.noun:lower():match("moonflower")) or (o.name and o.name:lower():match("moonflower")) then
        moonflower = o
        break
    end
end

if not mortar then
    csc_abort("Cannot find mortar ('" .. mortar_noun .. "') in your " .. container_noun .. ".\n"
        .. "          Override with: ;vars set csc_mortar=<noun>")
end

if not pestle then
    csc_abort("Cannot find pestle ('" .. pestle_noun .. "') in your " .. container_noun .. ".\n"
        .. "          Override with: ;vars set csc_pestle=<noun>")
end

if not vial then
    csc_abort("Cannot find glass vial ('" .. vial_noun .. "') in your " .. container_noun .. ".\n"
        .. "          Override with: ;vars set csc_vial=<noun>")
end

if #flasks < 2 then
    csc_abort("Expected 2 crystal flasks in your " .. container_noun .. " but found " .. #flasks .. ".\n"
        .. "          Make sure both your sea water flask and troll blood flask are in the container.")
end

if not moonflower then
    csc_abort("No moonflower found in your " .. container_noun .. ".\n"
        .. "          Moonflowers are forageable only at night in Icemule Trace\n"
        .. "          or the Veythorne Manor garden. Also, check player shops!")
end

-- Check flasks are not empty
for i = 1, 2 do
    local flask = flasks[i]
    local look = dothistimeout("look in #" .. flask.id, 5, ".+")
    if look and (look:lower():match("empty") or look:lower():match("nothing")) then
        csc_abort("One of your flasks (" .. (flask.name or flask.noun) .. ") appears to be empty.\n"
            .. "          Fill your flasks:\n"
            .. "            Sea water:   HARVEST WATER WITH FLASK at a coastal area\n"
            .. "            Troll blood: HARVEST BLOOD FROM {troll} WITH FLASK")
    end
end

respond("* Crimson Salt: All equipment and ingredients confirmed. Beginning crystal creation.")

-- ---- Stow hands -------------------------------------------------------------

waitrt()
if checkright() then fput("stow right"); pause(0.75) end
if checkleft() then fput("stow left"); pause(0.75) end

-- ---- First liquid: flask[1] -> vial -> mortar -------------------------------

respond("* Crimson Salt: Adding first liquid...")
waitrt()
fput("get #" .. flasks[1].id .. " from #" .. container.id); pause(0.75)
fput("get #" .. vial.id .. " from #" .. container.id); pause(0.75)
fput("turn #" .. vial.id); pause(0.75)
fput("pour #" .. flasks[1].id .. " in #" .. vial.id); pause(0.75)
fput("put #" .. flasks[1].id .. " in #" .. container.id); pause(0.75)
fput("get #" .. mortar.id .. " from #" .. container.id); pause(0.75)
fput("pour #" .. vial.id .. " in #" .. mortar.id); pause(0.75)
fput("put #" .. mortar.id .. " in #" .. container.id); pause(0.75)

-- ---- Second liquid: flask[2] -> vial -> mortar ------------------------------

respond("* Crimson Salt: Adding second liquid...")
waitrt()
fput("get #" .. flasks[2].id .. " from #" .. container.id); pause(0.75)
fput("pour #" .. flasks[2].id .. " in #" .. vial.id); pause(0.75)
fput("put #" .. flasks[2].id .. " in #" .. container.id); pause(0.75)
fput("get #" .. mortar.id .. " from #" .. container.id); pause(0.75)
fput("pour #" .. vial.id .. " in #" .. mortar.id); pause(0.75)
fput("put #" .. vial.id .. " in #" .. container.id); pause(0.75)

-- ---- Moonflower -------------------------------------------------------------

respond("* Crimson Salt: Adding moonflower...")
waitrt()
if moonflower.name and moonflower.name:lower():match("bundle") then
    -- Bundle handling: need both hands free
    fput("put #" .. mortar.id .. " in #" .. container.id); pause(0.75)
    fput("get #" .. moonflower.id .. " from #" .. container.id); pause(0.75)
    fput("bundle remove"); pause(1); waitrt()
    -- If bundle still has moonflowers, right hand has the remaining bundle
    local rh = GameObj.right_hand()
    if rh then
        fput("put #" .. rh.id .. " in #" .. container.id); pause(0.75)
    end
    fput("get #" .. mortar.id .. " from #" .. container.id); pause(0.75)
else
    -- Single moonflower
    fput("get #" .. moonflower.id .. " from #" .. container.id); pause(0.75)
end
fput("put moonflower in #" .. mortar.id); pause(0.75)

-- ---- Pestle -----------------------------------------------------------------

waitrt()
fput("get #" .. pestle.id .. " from #" .. container.id); pause(0.75)

-- ---- Grind sequence ---------------------------------------------------------

respond("* Crimson Salt: Grinding moonflower...")
fput("grind moonflower"); pause(1); waitrt()

respond("* Crimson Salt: Grinding mash (1 of 2)...")
fput("grind mash"); pause(1); waitrt()

respond("* Crimson Salt: Grinding mash (2 of 2)...")
fput("grind mash"); pause(1); waitrt()

respond("* Crimson Salt: Grinding solution...")
fput("grind solution"); pause(1); waitrt()

-- ---- Cast Animate Dead (719) at the solution --------------------------------

respond("* Crimson Salt: Casting 719 at solution...")
fput("prep 719"); pause(1); waitcastrt()
fput("cast at solution"); pause(1); waitrt()

-- Stow the pestle while the reaction builds
respond("* Crimson Salt: Stowing pestle while the reaction builds...")
fput("put #" .. pestle.id .. " in #" .. container.id); pause(0.75)

-- Watch for the three intermediate flame stages, then the final die-down.
-- Give the reaction up to 10 minutes.
respond("* Crimson Salt: Waiting for reaction (may take several minutes)...")
local reaction_deadline = os.time() + 600
while true do
    local line = get()
    if line:match("shadowy flames arise") then
        respond("* Crimson Salt: The reaction has begun! This can take several minutes -- be patient...")
    elseif line:match("flames of pure essence") then
        respond("* Crimson Salt: Still cooking...")
    elseif line:match("black flames rise") then
        respond("* Crimson Salt: Almost there -- the solution is nearly cooked down...")
    elseif line:match("dark flames.*die down") then
        break
    elseif line:match("fumble") or line:match("spell.*fail") or line:match("not enough") then
        csc_abort("Spell cast failed: " .. line:match("^%s*(.-)%s*$") .. "\n"
            .. "          Check your mana, spell knowledge, and mortar contents.")
    end
    if os.time() > reaction_deadline then
        csc_abort("Timed out (10 min) waiting for the crystal reaction to complete.\n"
            .. "          The cast may have failed. Check your mortar.")
    end
end

-- ---- Collect crystals and return equipment to container ---------------------

respond("* Crimson Salt: Collecting crystals and returning equipment...")
waitrt()
fput("get crystals from my mortar"); pause(0.75)
fput("put #" .. mortar.id .. " in #" .. container.id)

respond("* Crimson Salt: Done! You now have a bunch of crimson salt crystals in your left hand.")
respond("* Apply them with: SPREAD CRYSTALS ON {target}")
