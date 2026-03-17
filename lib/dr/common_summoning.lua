--- DRCS — DR Common Summoning utilities.
-- Ported from Lich5 common-summoning.rb (module DRCS).
-- Provides summon/break/shape summoned weapons, admittance, and planar magic.
-- @module lib.dr.common_summoning
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Shared message for elemental charge depletion.
M.LACK_CHARGE = "You lack the elemental charge"

--- Summon weapon responses.
M.SUMMON_WEAPON_RESPONSES = {
  M.LACK_CHARGE,
  "you draw out",
}

--- Break weapon responses.
M.BREAK_WEAPON_RESPONSES = {
  "Focusing your will",
  "disrupting its matrix",
  "You can't break",
  "Break what",
}

--- Moon Mage skill-to-shape mapping for moonblades/staves.
M.MOON_SKILL_TO_SHAPE = {
  Staves           = "blunt",
  ["Twohanded Edged"] = "huge",
  ["Large Edged"]  = "heavy",
  ["Small Edged"]  = "normal",
}

--- Moon weapon shape responses.
M.MOON_SHAPE_RESPONSES = {
  "you adjust the magic that defines its shape",
  "already has",
  "You fumble around",
}

--- Warrior Mage shape failure patterns.
M.WM_SHAPE_FAILURES = {
  M.LACK_CHARGE,
  "You reach out",
  "You fumble around",
  "You don't know how to manipulate",
}

--- Turn/push/pull weapon responses.
M.TURN_WEAPON_RESPONSES  = { M.LACK_CHARGE, "You reach out" }
M.PUSH_WEAPON_RESPONSES  = { M.LACK_CHARGE, "Closing your eyes", "That's as" }
M.PULL_WEAPON_RESPONSES  = { M.LACK_CHARGE, "Closing your eyes", "That's as" }

--- Summon admittance responses (Warrior Mage planar access).
M.SUMMON_ADMITTANCE_RESPONSES = {
  "You align yourself to it",
  "further increasing your proximity",
  "Going any further while in this plane would be fatal",
  "Summon allows Warrior Mages to draw",
  "You are a bit too distracted",
}

--- Default element adjectives for Warrior Mage summoned weapons.
M.WM_ELEMENT_ADJECTIVES = { "stone", "fiery", "icy", "electric" }

-------------------------------------------------------------------------------
-- Summon admittance
-------------------------------------------------------------------------------

--- Summon admittance to access the elemental plane (Warrior Mage).
function M.summon_admittance()
  for _ = 1, 10 do
    local result = DRC.bput("summon admittance", unpack(M.SUMMON_ADMITTANCE_RESPONSES))
    if result:find("too distracted") then
      DRC.retreat()
    else
      break
    end
  end
  pause(1)
  if waitrt then waitrt() end
  DRC.fix_standing()
end

-------------------------------------------------------------------------------
-- Summoned weapons
-------------------------------------------------------------------------------

--- Summon a weapon.
-- Moon Mages: hold existing moon weapon. Warrior Mages: summon with element/skill.
-- @param moon string|nil Moon target (unused for WM)
-- @param element string|nil Element type (WM only)
-- @param ingot string|nil Ingot material (WM only)
-- @param skill string|nil Weapon skill (WM only)
function M.summon_weapon(moon, element, ingot, skill)
  if DRStats and DRStats.guild then
    local guild = DRStats.guild
    if type(guild) == "function" then guild = guild() end

    if guild == "Moon Mage" then
      if DRCMM and DRCMM.hold_moon_weapon then
        DRCMM.hold_moon_weapon()
      end
    elseif guild == "Warrior Mage" then
      if ingot then
        if not M.get_ingot(ingot, true) then return end
      end
      local cmd = "summon weapon"
      if element then cmd = cmd .. " " .. element end
      if skill then cmd = cmd .. " " .. skill end

      local result = DRC.bput(cmd, unpack(M.SUMMON_WEAPON_RESPONSES))
      if result:find(M.LACK_CHARGE) then
        M.summon_admittance()
        DRC.bput(cmd, unpack(M.SUMMON_WEAPON_RESPONSES))
      end
      if ingot then M.stow_ingot(ingot) end
    else
      respond("[DRCS] Unable to summon weapons as a " .. tostring(guild))
    end
  end
  pause(1)
  if waitrt then waitrt() end
  DRC.fix_standing()
end

--- Break a summoned weapon.
-- @param item string Item noun to break
function M.break_summoned_weapon(item)
  if not item then return end
  DRC.bput("break my " .. item, unpack(M.BREAK_WEAPON_RESPONSES))
end

--- Shape a summoned weapon to a different form.
-- @param skill string Target weapon skill
-- @param ingot string|nil Ingot material (WM only)
-- @param settings table|nil Character settings
function M.shape_summoned_weapon(skill, ingot, settings)
  local weapon = M.identify_summoned_weapon(settings)
  if not weapon then return end

  if DRStats and DRStats.guild then
    local guild = DRStats.guild
    if type(guild) == "function" then guild = guild() end

    if guild == "Moon Mage" then
      local shape = M.MOON_SKILL_TO_SHAPE[skill]
      if shape and DRCMM and DRCMM.hold_moon_weapon and DRCMM.hold_moon_weapon() then
        DRC.bput("shape " .. weapon .. " to " .. shape, unpack(M.MOON_SHAPE_RESPONSES))
      end
    elseif guild == "Warrior Mage" then
      if ingot and not M.get_ingot(ingot, false) then return end

      local all = {}
      for _, p in ipairs(M.WM_SHAPE_FAILURES) do all[#all + 1] = p end
      all[#all + 1] = "What type of weapon were you trying"

      local result = DRC.bput("shape my " .. weapon .. " to " .. skill, unpack(all))
      if result:find(M.LACK_CHARGE) then
        M.summon_admittance()
        DRC.bput("shape my " .. weapon .. " to " .. skill, unpack(M.WM_SHAPE_FAILURES))
      end
      if ingot then M.stow_ingot(ingot) end
    else
      respond("[DRCS] Unable to shape weapons as a " .. tostring(guild))
    end
  end
  pause(1)
  if waitrt then waitrt() end
end

--- Identify what summoned weapon is currently held.
-- @param settings table|nil Character settings
-- @return string|nil Item description (e.g., "red-hot moonblade", "electric sword")
function M.identify_summoned_weapon(settings)
  if DRStats and DRStats.guild then
    local guild = DRStats.guild
    if type(guild) == "function" then guild = guild() end

    if guild == "Moon Mage" then
      local rh = DRC and DRC.right_hand and DRC.right_hand()
      local lh = DRC and DRC.left_hand and DRC.left_hand()
      if DRCMM and DRCMM.is_moon_weapon then
        if DRCMM.is_moon_weapon(rh) then return rh end
        if DRCMM.is_moon_weapon(lh) then return lh end
      end
    elseif guild == "Warrior Mage" then
      -- Check if what's in hand matches a summoned element adjective
      local rh = DRC and DRC.right_hand and DRC.right_hand()
      local lh = DRC and DRC.left_hand and DRC.left_hand()
      for _, adj in ipairs(M.WM_ELEMENT_ADJECTIVES) do
        if rh and rh:lower():find(adj) then return rh end
        if lh and lh:lower():find(adj) then return lh end
      end
    end
  end
  return nil
end

--- Turn a summoned weapon (changes damage type).
function M.turn_summoned_weapon()
  local rh_noun = DRC and DRC.right_hand and DRC.right_hand()
  if not rh_noun then return end
  -- Extract noun from full name
  local noun = rh_noun:match("(%S+)$") or rh_noun

  local result = DRC.bput("turn my " .. noun, unpack(M.TURN_WEAPON_RESPONSES))
  if result:find(M.LACK_CHARGE) then
    M.summon_admittance()
    DRC.bput("turn my " .. noun, unpack(M.TURN_WEAPON_RESPONSES))
  end
  pause(1)
  if waitrt then waitrt() end
end

--- Push a summoned weapon (increases weight).
function M.push_summoned_weapon()
  local rh_noun = DRC and DRC.right_hand and DRC.right_hand()
  if not rh_noun then return end
  local noun = rh_noun:match("(%S+)$") or rh_noun

  local result = DRC.bput("push my " .. noun, unpack(M.PUSH_WEAPON_RESPONSES))
  if result:find(M.LACK_CHARGE) then
    M.summon_admittance()
    DRC.bput("push my " .. noun, unpack(M.PUSH_WEAPON_RESPONSES))
  end
  pause(1)
  if waitrt then waitrt() end
end

--- Pull a summoned weapon (decreases weight).
function M.pull_summoned_weapon()
  local rh_noun = DRC and DRC.right_hand and DRC.right_hand()
  if not rh_noun then return end
  local noun = rh_noun:match("(%S+)$") or rh_noun

  local result = DRC.bput("pull my " .. noun, unpack(M.PULL_WEAPON_RESPONSES))
  if result:find(M.LACK_CHARGE) then
    M.summon_admittance()
    DRC.bput("pull my " .. noun, unpack(M.PULL_WEAPON_RESPONSES))
  end
  pause(1)
  if waitrt then waitrt() end
end

-------------------------------------------------------------------------------
-- Ingot helpers (Warrior Mage)
-------------------------------------------------------------------------------

--- Get an ingot for summoning.
-- @param ingot string Ingot material name
-- @param swap boolean Whether to swap to off-hand
-- @return boolean true on success
function M.get_ingot(ingot, swap)
  if not ingot then return true end
  if not (DRCI and DRCI.get_item) then return false end
  if not DRCI.get_item(ingot .. " ingot") then
    respond("[DRCS] Could not get " .. ingot .. " ingot")
    return false
  end
  if swap then DRC.bput("swap", "You move") end
  return true
end

--- Stow an ingot after summoning.
-- @param ingot string Ingot material name
-- @return boolean
function M.stow_ingot(ingot)
  if not ingot then return true end
  if not (DRCI and DRCI.put_away_item) then return false end
  if not DRCI.put_away_item(ingot .. " ingot") then
    respond("[DRCS] Could not stow " .. ingot .. " ingot")
    return false
  end
  return true
end

return M
