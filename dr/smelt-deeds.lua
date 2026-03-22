--- @revenant-script
--- name: smelt-deeds
--- version: 1.0.0
--- author: Elanthia Online (lic)
--- game: dr
--- description: Process deed-based ore smelting — groups deeds by metal, loads crucibles, and runs smelt child script for each qualifying metal.
--- tags: crafting, smelting, forging, deeds
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;smelt-deeds [material]
---
--- Arguments:
---   material   (optional) Single metal type to process.
---              By default alloys (steel, bronze, pewter, brass) are skipped.
---              Name an alloy explicitly to include it (e.g., ;smelt-deeds steel).
---
--- Requires smelt.lua peer script to be present (fires the crucible).
---
--- Settings (in your profile JSON):
---   adjustable_tongs  — true if your tongs can switch between shovel and tongs mode
---   hometown          — your base city (used to locate an empty crucible)

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

local ALLOYS = { steel = true, bronze = true, pewter = true, brass = true }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Try to put an item into the crucible.
-- Returns true if loaded (or item is nil/empty), false if crucible is full.
local function load_crucible(item)
  if not item then return true end
  local result = DRC.bput("put my " .. item .. " in cruc",
    "You put", "at once would be dangerous")
  if result:find("at once would be dangerous") then
    echo("***CRUCIBLE IS FULL***")
    DRCI.stow_hands()
    return false
  end
  return true
end

--- Tap the deed currently in hand to confirm type and handle edge cases.
-- Returns false if the crucible is already full (worker explains), true otherwise.
-- If an ingot was on the floor, picks it up and recovers standing.
local function tap_deed()
  local result = DRC.bput("tap my deed",
    "You pick up", "The worker explains", "The ingot rests safely at your feet")
  if result:find("worker explains") then
    -- Crucible is full — stow this deed and signal prepare_crucible to stop loading
    DRC.bput("stow my deed", "You put")
    return false
  end
  if result:find("ingot rests safely") then
    -- Deed was already processed and the resulting ingot is on the floor
    DRC.bput("get my ingot", "You pick up")
    waitrt()
    DRC.fix_standing()
  end
  return true
end

--- Attempt to retrieve a deed by ordinal position and metal type.
-- Returns true if the deed was successfully gotten, false if none found.
local function get_deed(ordinal, metal)
  local result = DRC.bput("get my " .. ordinal .. " " .. metal .. " deed",
    "You get", "What were you referring to")
  return not result:find("What were you referring to")
end

--- Inner loading loop for one ordinal slot.
-- Retrieves and loads the deed at this ordinal position into the crucible
-- until the slot is empty or the crucible is full.
-- Returns true to signal the prepare loop to continue to the next ordinal,
-- false to stop (either no deed here or crucible full during load).
local function more_deeds(ordinal, metal)
  while true do
    if not get_deed(ordinal, metal) then return false end
    -- tap_deed returns false if crucible is full; signal caller to skip ahead
    if not tap_deed() then return true end
    if not load_crucible(DRC.right_hand()) then return false end
    if not load_crucible(DRC.left_hand()) then return false end
  end
end

--- Iterate ORDINALS, loading deeds into the crucible until full or deeds exhausted.
local function prepare_crucible(metal)
  for _, ordinal in ipairs(ORDINALS) do
    if not more_deeds(ordinal, metal) then break end
  end
end

--- Get the deed packet if one exists. If not, stow the ingot instead.
-- Returns true if a packet was retrieved (caller should push ingot + stow packet).
local function get_packet()
  local result = DRC.bput("get my packet",
    "You get", "What were you referring to")
  if result:find("What were you referring to") then
    DRC.bput("stow my ingot", "You put")
    return false
  end
  return true
end

--- Smelt all deeds for one metal type.
-- Verifies tools, navigates to an empty crucible, loads deeds, fires smelt
-- child script, then packages or stows the resulting ingot.
-- Returns false on fatal error (missing tools), true on success.
local function smelt(metal)
  local settings = get_settings()
  local tools = settings.adjustable_tongs
    and { "rod", "bellows", "tongs" }
    or  { "rod", "bellows", "shovel" }

  for _, tool in ipairs(tools) do
    if not DRCI.exists(tool) then
      echo("A TOOL WAS MISSING. FIND IT AND RESTART")
      return false
    end
  end

  DRCC.find_empty_crucible(settings.hometown)
  prepare_crucible(metal)
  DRC.wait_for_script_to_complete("smelt")

  if not get_packet() then return true end

  DRC.bput("push my ingot with my packet", "You push")
  DRC.bput("stow my deed", "You put")
  DRC.bput("stow my packet", "You put")  -- note: last deed in packet handled gracefully by game
  return true
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

-- Optional: restrict to a single material (allows alloys when named explicitly)
local material = Script.vars[1] and Script.vars[1]:lower() or nil

-- Build the list of metals to process (all non-alloy metals by default)
local item_data = get_data("items") or {}
local all_metal_types = item_data.metal_types or {}

local metals = {}
for _, m in ipairs(all_metal_types) do
  if not ALLOYS[m] then
    metals[#metals + 1] = m
  end
end

-- If user explicitly names an alloy, include it
if material and ALLOYS[material] then
  metals[#metals + 1] = material
end

-- Bail early if no deeds are in inventory at all
if not DRCI.exists("deed") then
  echo("***NO DEEDS FOUND TO SMELT***")
  return
end

-- Empty hands before scanning so reget captures accurate inventory descriptions
DRCI.stow_hands()

-- Scan recent game output for deed lines
-- Game format: "A deed for <qty> <metal...> <material-type> is in <location>."
-- e.g. "A deed for 15 iron ore is in your left hand."
--      "A deed for 30 yellow gold ore is in your forger's pouch."
local deed_lines = reget(100, "A deed for") or {}
waitrt()

-- Count deeds per metal, handling both single-word and multi-word metal names
local counts = {}
for _, line in ipairs(deed_lines) do
  -- Capture everything between quantity and " is in", then drop the last word
  -- (the material type, e.g. "ore") to isolate the metal name.
  -- "15 iron ore" → between="iron ore" → metal="iron"
  -- "15 yellow gold ore" → between="yellow gold ore" → metal="yellow gold"
  local between = line:match("A deed for %S+ (.+) is in")
  if between then
    local metal = between:match("^(.+)%s+%S+$") or between
    metal = metal:lower()
    counts[metal] = (counts[metal] or 0) + 1
  end
end

-- Build a fast lookup of valid target metals
local valid = {}
for _, m in ipairs(metals) do valid[m] = true end

-- Process each qualifying metal
for metal, count in pairs(counts) do
  -- Need at least 2 deeds (game mechanic: ore quantity requires multiple deeds)
  if count <= 1 then goto continue end
  -- Must be a metal we want to smelt
  if not valid[metal] then goto continue end
  -- If a material filter was given, metal must match it
  if material and not metal:find(material, 1, true) then goto continue end

  if not smelt(metal) then break end
  ::continue::
end
