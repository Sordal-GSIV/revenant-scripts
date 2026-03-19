--- @revenant-script
--- name: smelt
--- version: 1.0.0
--- author: Elanthia Online (lic)
--- game: dr
--- description: Fire a loaded crucible to produce ingots — stirs, fuels, and bellows until smelting is complete.
--- tags: crafting, smelting, forging
--- @lic-certified: complete 2026-03-19
---
--- Called automatically by smelt-deeds and workorders when a crucible is loaded
--- and ready to fire. Can also be run manually.
---
--- Usage:
---   ;smelt [refine]
---
--- Arguments:
---   refine   (optional) Pour flux to refine the melt rather than stirring.
---
--- Settings (in your profile JSON):
---   crafting_container          — bag that holds crafting supplies
---   crafting_items_in_container — list of item names kept in that bag
---   forging_belt                — belt config { name, items } for forging tools
---   forging_tools               — list of tool names (must include a rod)
---   adjustable_tongs            — true if your tongs can switch to shovel mode

-------------------------------------------------------------------------------
-- Completion flag
-------------------------------------------------------------------------------

Flags.add("smelt-done", "At last the metal appears to be thoroughly mixed")

before_dying(function()
  Flags.delete("smelt-done")
end)

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local settings  = get_settings()
local bag       = settings.crafting_container
local bag_items = settings.crafting_items_in_container
local belt      = settings.forging_belt
local adjustable = settings.adjustable_tongs

-- Locate the rod in the forging tool list
local rod = "rod"
if settings.forging_tools then
  for _, t in ipairs(settings.forging_tools) do
    if t:find("rod") then rod = t; break end
  end
end

-------------------------------------------------------------------------------
-- Args
-------------------------------------------------------------------------------

local is_refine = Script.vars[1] and Script.vars[1]:lower() == "refine"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Swap the currently held tool for the target tool, using belt/bag.
local function swap_tool(target)
  local rh = DRC.right_hand()
  if rh ~= target then
    if rh then DRCC.stow_crafting_item(rh, bag, belt) end
    DRCC.get_crafting_item(target, bag, bag_items, belt)
  end
end

--- Main work loop — stirs and responds to game feedback until the smelt
--- completes (Flags["smelt-done"]) or the crucible is dry.
local function work(initial_command, initial_item)
  local command = initial_command
  local item    = initial_item

  while true do
    swap_tool(item)

    local result = DRC.bput(command,
      "Pour what",
      "You can only mix a crucible",
      "clumps of molten metal",
      "flickers and is unable to consume",
      "needs more fuel",
      "needs some more fuel",
      "think pushing that would have any effect",
      "roundtime")

    if result:find("Pour what") then
      -- Missing flux during a refine run
      DRC.message("Missing Flux")
      break

    elseif result:find("You can only mix a crucible") then
      -- Crucible is empty / smelting finished without the done-flag
      break

    elseif result:find("clumps of molten metal") then
      -- Metal is ready to turn; switch to turning
      command = "turn crucible with my " .. rod
      item    = rod

    elseif result:find("flickers and is unable to consume") then
      -- Fire is dying; bellows to revive it
      command = "push my bellows"
      item    = "bellows"

    elseif result:find("needs more fuel") or result:find("needs some more fuel") then
      -- Add fuel — shovel normally, tongs if adjustable
      item    = adjustable and "tongs" or "shovel"
      command = "push fuel with my " .. item

    elseif result:find("think pushing that would have any effect") then
      -- Shovel isn't working; fall back explicitly to shovel
      item = "shovel"

    else
      -- roundtime or other transient response — resume stirring
      command = "stir crucible with my " .. rod
      item    = rod
    end

    waitrt()
    if Flags["smelt-done"] then break end
  end
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

DRCI.stow_hands()

-- If using adjustable tongs, reset them to shovel mode for fueling
if adjustable then
  local got = DRCC.get_adjust_tongs("reset shovel", bag, bag_items, belt)
  if got then
    DRCC.stow_crafting_item("tongs", bag, belt)
  end
end

local command, item
if is_refine then
  command = "pour my flux in crucible"
  item    = "flux"
else
  command = "stir crucible with my " .. rod
  item    = rod
end

work(command, item)

-- Stow the rod when done
DRCC.stow_crafting_item(rod, bag, belt)
