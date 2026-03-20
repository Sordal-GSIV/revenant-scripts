--- @revenant-script
--- name: registergear
--- version: 1.0.0
--- author: dr-scripts community (original registergear.lic)
--- original-authors: dr-scripts community contributors
--- game: dr
--- description: Registers gear sets with the DragonRealms registrar. Walks to room 14670, goes through the registrar's curtain, then taps/removes/registers/re-wears each item in the configured gear set.
--- tags: gear,registration,equipment
--- source: https://github.com/rpherbig/dr-scripts
--- @lic-certified: complete 2026-03-19
---
--- USAGE:
---   ;registergear              — register items from settings.set_name (default: "standard")
---   ;registergear <set_name>   — register items from a named gear set
---
--- SETTINGS (in your character profile JSON):
---   {
---     "set_name": "standard",
---     "gear_sets": {
---       "standard": ["my boots", "my cloak", "my helm"],
---       "combat":   ["my shield", "my sword", "my helm"]
---     }
---   }

-- ============================================================================
-- Load settings
-- ============================================================================

local settings  = get_settings()
local gearsets  = settings.gear_sets

if not gearsets then
  echo("[registergear] No 'gear_sets' defined in settings.")
  return
end

-- Allow set name override via script argument; fall back to settings.set_name
local set_name = Script.vars[1] or settings.set_name or "standard"

local items = gearsets[set_name]
if not items then
  echo("[registergear] Gear set '" .. set_name .. "' not found in settings.")
  return
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function stow_item(item_name)
  echo("[registergear] stowing " .. item_name)
  fput("stow " .. item_name)
end

--- Register one item: tap → identify → remove → get → register ×2 → re-wear.
local function register_item(item_name)
  echo("[registergear] Tapping: " .. item_name)
  local tap_output = DRC.bput(
    "tap " .. item_name,
    "You tap ",
    "What were you referring",
    "The faces on your stick pause"
  )

  if tap_output:find("What were you referring") then
    echo("[registergear] Could not identify item: " .. item_name)
    return
  end

  if tap_output:find("The faces on your stick pause") then
    echo("[registergear] Cannot tap " .. item_name .. " — skipping (locked/animated)")
    return
  end

  local description = tap_output:match("You tap (.+)%.")
  if not description then
    echo("[registergear] Could not match description for " .. item_name)
    return
  end
  echo("[registergear] Matched item: " .. description)

  -- Remove the item
  echo("[registergear] Removing " .. item_name .. "...")
  local remove_result = DRC.bput(
    "remove " .. item_name,
    "You remove", "You loosen", "You take off", "You unstrap",
    "You pull off", "You place", "You detach", "You strip off",
    "slide.*off", "You take", "Hmm, you don't seem",
    "What were you referring", "You can't remove"
  )
  if not Regex.test(
    "(?i)(remove|loosen|take off|unstrap|pull off|You place|.*off|detach|strip off|slide.*off)",
    remove_result
  ) then
    echo("[registergear] Failed to remove " .. item_name)
  end

  -- Get the item in hand
  local get_result = DRC.bput(
    "get " .. item_name,
    "already holding",
    "need a free hand",
    "You pick up", "You get", "You grab", "You reach",
    "What were you referring"
  )

  if get_result:find("already holding") then
    echo("[registergear] Already holding " .. item_name)
  elseif get_result:find("need a free hand") then
    echo("[registergear] Hands are full, cannot get " .. item_name .. ". Skipping.")
    return
  else
    echo("[registergear] Got " .. item_name)
  end

  -- First register
  echo("[registergear] Registering " .. item_name .. " (1st time)...")
  local reg_result = DRC.bput(
    "register " .. item_name,
    "do not have enough Kronars",
    "You cannot register, I am sorry",
    "did the paperwork for that",
    "There appears to be some problems",
    "You register", "confirm", "Are you sure", "you sure",
    "Register what", "I don't see"
  )

  if reg_result:find("do not have enough Kronars") then
    echo("[registergear] Not enough Kronars to register " .. item_name .. ". Skipping.")
    return
  end

  if reg_result:find("You cannot register, I am sorry") then
    echo("[registergear] Cannot register items in this room.")
    fput("go curtain")
    return
  end

  if reg_result:find("did the paperwork for that") then
    echo("[registergear] " .. item_name .. " is already registered. Skipping re-registration.")
    fput("wear " .. item_name)
    return
  end

  if reg_result:find("There appears to be some problems") then
    echo("[registergear] Cannot register " .. item_name .. " — has attached or contained items. Skipping.")
    return
  end

  -- Second register (confirms the transaction)
  echo("[registergear] Registering " .. item_name .. " (2nd time)...")
  fput("register " .. item_name)

  -- Re-wear
  echo("[registergear] Rewearing " .. item_name .. "...")
  local wear_result = DRC.bput(
    "wear " .. item_name,
    "You wear", "You strap", "You place", "You slip", "You put", "You already",
    "cannot figure out how", "What were you referring"
  )

  if not Regex.test("(?i)(You wear|strap|place|slip|put|You already)", wear_result) then
    echo("[registergear] WARNING: Failed to rewear " .. item_name)
    if not wear_result:find("already in your inventory") then
      stow_item(item_name)
    end
  else
    echo("[registergear] " .. item_name .. " registered successfully.")
  end
end

-- ============================================================================
-- Main
-- ============================================================================

echo("[registergear] Walking to registrar...")
DRCT.walk_to(14670)
fput("go curtain")

for _, item in ipairs(items) do
  register_item(item)
  pause(1)
end

echo("[registergear] Done.")
