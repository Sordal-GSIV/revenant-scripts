--- DRCTH — DR Common Theurgy utilities.
-- Ported from Lich5 common-theurgy.rb (module DRCTH).
-- Provides commune, devotion, rituals, and cleric supply management.
-- @module lib.dr.common_theurgy
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Items used by clerics for theurgy rituals.
M.CLERIC_ITEMS = {
  "holy water", "holy oil", "wine", "incense", "flint",
  "chamomile", "sage", "jalbreth balm",
}

--- Error messages when attempting commune rituals.
M.COMMUNE_ERRORS = {
  "As you commune you sense that the ground is already consecrated.",
  "You stop as you realize that you have attempted a commune",
  "completed this commune too recently",
}

--- Devotion level messages from commune sense (lowest to highest).
M.DEVOTION_LEVELS = {
  "You sense nothing special from your communing",
  "You feel unclean and unworthy",
  "You close your eyes and start to concentrate",
  "You call out to your god, but there is no answer",
  "After a moment, you sense that your god is barely aware of you",
  "After a moment, you sense that your efforts have not gone unnoticed",
  "After a moment, you sense a distinct link between you and your god",
  "After a moment, you sense that your god is aware of your devotion",
  "After a moment, you sense that your god knows your name",
  "After a moment, you sense that your god is pleased with your devotion",
  "After a moment, you see a vision of your god, though the visage is cloudy",
  "After a moment, you sense a slight pressure on your shoulder",
  "After a moment, you see a silent vision of your god",
  "After a moment, you see a vision of your god who calls to you by name, \"Come here, my child",
  "After a moment, you see a vision of your god who calls to you by name, \"My child, though you may",
  "After a moment, you see a crystal-clear vision of your god who speaks slowly and deliberately",
  "After a moment, you feel a clear presence like a warm blanket covering you",
}

-------------------------------------------------------------------------------
-- CommuneSenseResult
-------------------------------------------------------------------------------

--- Create a CommuneSenseResult.
-- @param opts table { active_communes, recent_communes, commune_ready }
-- @return table
function M.CommuneSenseResult(opts)
  opts = opts or {}
  return {
    active_communes  = opts.active_communes or {},
    recent_communes  = opts.recent_communes or {},
    commune_ready    = opts.commune_ready ~= false,  -- default true

    is_commune_ready = function(self) return self.commune_ready end,
  }
end

-------------------------------------------------------------------------------
-- Supply checking
-------------------------------------------------------------------------------

--- Check if we have holy water in a holder.
-- @param supply_container string Container for theurgy supplies
-- @param water_holder string Item that holds holy water
-- @return boolean
function M.has_holy_water(supply_container, water_holder)
  if not DRCI then return false end
  if not DRCI.get_item(water_holder, supply_container) then return false end
  local has = DRCI.inside("holy water", water_holder)
  DRCI.put_away_item(water_holder, supply_container)
  return has
end

--- Check if we have flint.
-- @param supply_container string
-- @return boolean
function M.has_flint(supply_container)
  return DRCI and DRCI.have_item_by_look and DRCI.have_item_by_look("flint", supply_container) or false
end

--- Check if we have holy oil.
-- @param supply_container string
-- @return boolean
function M.has_holy_oil(supply_container)
  return DRCI and DRCI.have_item_by_look and DRCI.have_item_by_look("holy oil", supply_container) or false
end

--- Check if we have incense.
-- @param supply_container string
-- @return boolean
function M.has_incense(supply_container)
  return DRCI and DRCI.have_item_by_look and DRCI.have_item_by_look("incense", supply_container) or false
end

--- Check if we have jalbreth balm.
-- @param supply_container string
-- @return boolean
function M.has_jalbreth_balm(supply_container)
  return DRCI and DRCI.have_item_by_look and DRCI.have_item_by_look("jalbreth balm", supply_container) or false
end

-------------------------------------------------------------------------------
-- Supply purchasing
-------------------------------------------------------------------------------

--- Buy a cleric supply item from a town's shop.
-- @param town string Town name
-- @param item_name string Item to buy (e.g., "holy water", "incense")
-- @param stackable boolean Whether the item stacks
-- @param num_to_buy number Quantity
-- @param supply_container string Container for supplies
-- @return boolean true on success
function M.buy_cleric_item(town, item_name, stackable, num_to_buy, supply_container)
  -- TODO: integrate with theurgy data files for shop locations
  respond("[DRCTH] buy_cleric_item: stub for " .. tostring(item_name) .. " in " .. tostring(town))

  for _ = 1, num_to_buy do
    -- Would walk to shop and buy via DRCT.buy_item
    if stackable and DRCI and DRCI.get_item then
      if DRCI.get_item(item_name, supply_container) then
        DRC.bput("combine " .. item_name .. " with " .. item_name,
          "You combine", "You can't combine", "You must be holding")
      end
    end
    if DRCI and DRCI.put_away_item then
      DRCI.put_away_item(item_name, supply_container)
    end
  end
  return true
end

--- Quick bless an item using the Bless spell.
-- @param item_name string Item to bless
function M.quick_bless_item(item_name)
  if DRCA and DRCA.cast_spell then
    DRCA.cast_spell(
      { abbrev = "bless", mana = 1, prep_time = 2, cast = "cast my " .. item_name },
      {}
    )
  end
end

-------------------------------------------------------------------------------
-- Hand management for cleric rituals
-------------------------------------------------------------------------------

--- Empty both hands, putting cleric items in the supply container.
-- @param supply_container string
function M.empty_cleric_hands(supply_container)
  DRC.bput("glance", "You glance")
  M.empty_cleric_right_hand(supply_container)
  M.empty_cleric_left_hand(supply_container)
end

--- Empty right hand, routing cleric items to supply container.
-- @param supply_container string
function M.empty_cleric_right_hand(supply_container)
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  if not rh then return end

  local container = nil
  for _, item in ipairs(M.CLERIC_ITEMS) do
    if rh:lower():find(item:lower()) then
      container = supply_container
      break
    end
  end
  if DRCI and DRCI.put_away_item then
    DRCI.put_away_item(rh, container)
  end
end

--- Empty left hand, routing cleric items to supply container.
-- @param supply_container string
function M.empty_cleric_left_hand(supply_container)
  local lh = DRC and DRC.left_hand and DRC.left_hand()
  if not lh then return end

  local container = nil
  for _, item in ipairs(M.CLERIC_ITEMS) do
    if lh:lower():find(item:lower()) then
      container = supply_container
      break
    end
  end
  if DRCI and DRCI.put_away_item then
    DRCI.put_away_item(lh, container)
  end
end

-------------------------------------------------------------------------------
-- Ritual actions
-------------------------------------------------------------------------------

--- Sprinkle an item on a target.
-- @param item string Item to sprinkle (e.g., water holder name or "oil")
-- @param target string Target of sprinkling
-- @return boolean
function M.sprinkle(item, target)
  local result = DRC.bput("sprinkle " .. item .. " on " .. target,
    "You sprinkle", "Sprinkle what", "Sprinkle that",
    "What were you referring to")
  return result:find("You sprinkle") ~= nil
end

--- Sprinkle holy water on a target (full ritual with get/put).
-- @param supply_container string
-- @param water_holder string
-- @param target string
-- @return boolean
function M.sprinkle_holy_water(supply_container, water_holder, target)
  if not DRCI then return false end
  if not DRCI.get_item(water_holder, supply_container) then
    respond("[DRCTH] Can't get " .. water_holder .. " to sprinkle.")
    return false
  end
  local ok = M.sprinkle(water_holder, target)
  DRCI.put_away_item(water_holder, supply_container)
  return ok
end

--- Sprinkle holy oil on a target.
-- @param supply_container string
-- @param target string
-- @return boolean
function M.sprinkle_holy_oil(supply_container, target)
  if not DRCI then return false end
  if not DRCI.get_item("holy oil", supply_container) then
    respond("[DRCTH] Can't get holy oil to sprinkle.")
    return false
  end
  local ok = M.sprinkle("oil", target)
  M.empty_cleric_hands(supply_container)
  return ok
end

--- Apply jalbreth balm to a target.
-- @param supply_container string
-- @param target string
function M.apply_jalbreth_balm(supply_container, target)
  if not DRCI then return end
  DRCI.get_item("jalbreth balm", supply_container)
  DRC.bput("apply balm to " .. target, ".*")
  if DRCI.in_hands and DRCI.in_hands("balm") then
    DRCI.put_away_item("jalbreth balm", supply_container)
  end
end

--- Wave incense at a target (light it first).
-- @param supply_container string
-- @param flint_lighter string Flint lighter item name
-- @param target string
-- @return boolean
function M.wave_incense(supply_container, flint_lighter, target)
  if not DRCI then return false end
  M.empty_cleric_hands(supply_container)

  if not M.has_flint(supply_container) then
    respond("[DRCTH] Can't find flint.")
    return false
  end
  if not M.has_incense(supply_container) then
    respond("[DRCTH] Can't find incense.")
    return false
  end

  if not DRCI.get_item(flint_lighter) then
    respond("[DRCTH] Can't get " .. flint_lighter)
    return false
  end
  if not DRCI.get_item("incense", supply_container) then
    respond("[DRCTH] Can't get incense.")
    M.empty_cleric_hands(supply_container)
    return false
  end

  -- Try to light the incense
  for attempt = 1, 5 do
    local result = DRC.bput("light my incense with my flint",
      "nothing happens", "bursts into flames",
      "much too dark", "What were you referring to")
    if waitrt then waitrt() end
    if result:find("bursts into flames") then break end
    if attempt >= 5 then
      respond("[DRCTH] Can't light incense after 5 tries.")
      M.empty_cleric_hands(supply_container)
      return false
    end
  end

  DRC.bput("wave my incense at " .. target, "You wave")
  if DRCI.in_hands and DRCI.in_hands("incense") then
    DRC.bput("snuff my incense", "You snuff out")
  end

  DRCI.put_away_item(flint_lighter)
  M.empty_cleric_hands(supply_container)
  return true
end

-------------------------------------------------------------------------------
-- Commune sense
-------------------------------------------------------------------------------

--- Issue 'commune sense' and parse the output.
-- @return CommuneSenseResult
function M.commune_sense()
  put("commune sense")
  local lines = {}
  local timeout_at = os.time() + 10
  while os.time() < timeout_at do
    local line = get()
    if line then
      lines[#lines + 1] = line
      if line:find("Roundtime") then break end
    else
      pause(0.1)
    end
  end
  if waitrt then waitrt() end
  return M.parse_commune_sense_lines(lines)
end

--- Parse commune sense output lines into a CommuneSenseResult.
-- @param lines table Array of text lines
-- @return CommuneSenseResult
function M.parse_commune_sense_lines(lines)
  local commune_ready = true
  local active = {}
  local recent = {}

  for _, line in ipairs(lines) do
    if line:find("will not be able to open another divine conduit") then
      commune_ready = false
    end
    if line:find("Tamsine's benevolent eyes") or line:find("miracle of Tamsine") then
      active[#active + 1] = "Tamsine"
    elseif line:find("auspices of Kertigen") then
      active[#active + 1] = "Kertigen"
    elseif line:find("Meraud's influence") then
      active[#active + 1] = "Meraud"
    end
    if line:find("waters of Eluned are still") then
      recent[#recent + 1] = "Eluned"
    elseif line:find("recently enlightened by Tamsine") then
      recent[#recent + 1] = "Tamsine"
    elseif line:find("Kertigen's forge still ring") then
      recent[#recent + 1] = "Kertigen"
    elseif line:find("captivated by Truffenyi") then
      recent[#recent + 1] = "Truffenyi"
    end
  end

  return M.CommuneSenseResult({
    active_communes = active,
    recent_communes = recent,
    commune_ready   = commune_ready,
  })
end

return M
