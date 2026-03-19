--- DRCA — DR Common Arcana / Magic utilities.
-- Ported from Lich5 common-arcana.rb (module DRCA).
-- Provides cast, prepare, harness, cambrinth, and spell management.
-- @module lib.dr.common_arcana
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Cyclic spell release success patterns (covers all guilds).
M.CYCLIC_RELEASE_SUCCESS = {
  "spirit of the cheetah escapes",
  "spirit of the bear leaves",
  "forces of nature .* no longer with you",
  "Aesandry Darlaeth loses cohesion",
  "Guardian Spirit weaken",
  "touch no longer deadly",
  "motes of energy fade away",
  "You sing, purposely warbling",
  "enchante end with an abrupt",
  "Albreda's Balm .* conclusion",
  "Blessing of the Fae stir",
  "warm air swirling .* stills",
  "lullaby slowly dies down",
  "You let your concentration on the enchante",
  "fading notes of your enchante",
}

--- Prepare spell patterns
M.PREPARE_SUCCESS = {
  "You begin to", "You raise your hand",
  "With quiet discipline",
  "already preparing", "You're already preparing",
  "You feel fully prepared",
}

--- Cast success patterns
M.CAST_SUCCESS = {
  "You gesture", "you direct", "With a sharp retort",
  "You trace a simple rune", "You hurl", "You deliver",
  "Roundtime",
}

--- Cast failure patterns
M.CAST_FAILURE = {
  "currently have a spell readied",
  "The spell pattern collapses",
  "fizzles and dies",
  "You can't cast that",
  "You don't have a spell prepared",
  "gestures at nothing",
}

--- Harness mana patterns
M.HARNESS_SUCCESS = {
  "You tap into the mana",
  "You are able to",
  "mana into your",
  "Roundtime",
}

--- Perceive mana patterns
M.PERCEIVE_SUCCESS = {
  "You reach out",
  "mana streams around you",
  "perceive that",
}

--- Cambrinth charge patterns
M.CHARGE_SUCCESS = {
  "You harness",
  "You tap .* to channel",
  "Roundtime",
}

--- Cambrinth invoke patterns
M.INVOKE_SUCCESS = {
  "The .* pulses with energy",
  "You feel the mana from",
  "draw energy from",
}

--- Focus patterns
M.FOCUS_SUCCESS = {
  "mana contained within",
  "You focus your magical senses",
  "no mana",
  "appears to be fully charged",
}

--- Release success patterns
M.RELEASE_SUCCESS = {
  "You release", "You feel the", "You let your concentration",
}

-------------------------------------------------------------------------------
-- Spell casting
-------------------------------------------------------------------------------

--- Prepare a spell.
-- @param abbrev string Spell abbreviation
-- @param mana number Mana to prepare at
-- @return boolean
function M.prepare(abbrev, mana)
  if not abbrev then return false end
  local cmd = "prepare " .. abbrev
  if mana and mana > 0 then
    cmd = cmd .. " " .. tostring(mana)
  end
  local result = DRC.bput(cmd, unpack(M.PREPARE_SUCCESS))
  return result ~= ""
end

--- Cast a prepared spell.
-- @param cast_command string|nil Custom cast command (default "cast")
-- @return string Result text
function M.cast(cast_command)
  cast_command = cast_command or "cast"
  local all = {}
  for _, p in ipairs(M.CAST_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.CAST_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput(cast_command, unpack(all))
  if waitrt then waitrt() end
  return result
end

--- Full spell cast sequence: prepare, optional harness/cambrinth, then cast.
-- @param spell_data table Spell configuration:
--   { abbrev, mana, prep_time, cast, cambrinth, harness_mana }
-- @param settings table Character settings (for cambrinth config)
-- @return string Cast result
function M.cast_spell(spell_data, settings)
  if not spell_data or not spell_data.abbrev then
    respond("[DRCA] No spell data provided.")
    return ""
  end

  local abbrev = spell_data.abbrev
  local mana = spell_data.mana or 1
  local prep_time = spell_data.prep_time or 3
  local cast_cmd = spell_data.cast or "cast"

  -- Prepare
  M.prepare(abbrev, mana)

  -- Wait for preparation
  if prep_time > 0 then
    pause(prep_time)
  end

  -- Harness extra mana if specified
  if spell_data.harness_mana and spell_data.harness_mana > 0 then
    M.harness_mana(spell_data.harness_mana)
  end

  -- Charge cambrinth if specified
  if spell_data.cambrinth then
    M.charge_and_invoke_cambrinth(spell_data.cambrinth, settings)
  end

  -- Cast
  return M.cast(cast_cmd)
end

--- Harness additional mana.
-- @param amount number Mana to harness
function M.harness_mana(amount)
  if not amount or amount <= 0 then return end
  DRC.bput("harness " .. tostring(amount), unpack(M.HARNESS_SUCCESS))
end

--- Perceive mana in the area.
-- @return string Result text
function M.perceive_mana()
  return DRC.bput("perceive", unpack(M.PERCEIVE_SUCCESS))
end

--- Perceived mana level (simplified).
-- @return number Approximate mana level (0-100)
function M.perc_mana()
  -- TODO: parse perceive output for actual mana level
  -- For now, return a stub value
  return 50
end

-------------------------------------------------------------------------------
-- Cambrinth
-------------------------------------------------------------------------------

--- Charge a cambrinth item.
-- @param amount number Mana to charge
-- @param camb_name string|nil Cambrinth item name (default from settings)
function M.charge_cambrinth(amount, camb_name)
  camb_name = camb_name or "cambrinth"
  DRC.bput("charge my " .. camb_name .. " " .. tostring(amount), unpack(M.CHARGE_SUCCESS))
end

--- Invoke (draw from) a cambrinth item.
-- @param camb_name string|nil Cambrinth item name
function M.invoke_cambrinth(camb_name)
  camb_name = camb_name or "cambrinth"
  DRC.bput("invoke my " .. camb_name, unpack(M.INVOKE_SUCCESS))
end

--- Focus on a cambrinth item to check charge level.
-- @param camb_name string|nil Cambrinth item name
-- @return string Result text
function M.focus_cambrinth(camb_name)
  camb_name = camb_name or "cambrinth"
  return DRC.bput("focus my " .. camb_name, unpack(M.FOCUS_SUCCESS))
end

--- Charge and invoke cambrinth in one sequence.
-- @param camb_data table|number Cambrinth mana amount(s)
-- @param settings table Character settings (for item name)
function M.charge_and_invoke_cambrinth(camb_data, settings)
  local camb_name = settings and settings.cambrinth_name or "cambrinth"

  if type(camb_data) == "number" then
    M.charge_cambrinth(camb_data, camb_name)
    M.invoke_cambrinth(camb_name)
  elseif type(camb_data) == "table" then
    -- Multiple charges
    for _, amount in ipairs(camb_data) do
      M.charge_cambrinth(amount, camb_name)
    end
    M.invoke_cambrinth(camb_name)
  end
end

-------------------------------------------------------------------------------
-- Spell management
-------------------------------------------------------------------------------

--- Release a cyclic spell.
-- @param abbrev string|nil Spell abbreviation (nil releases all)
-- @return boolean true if released
function M.release_cyclic(abbrev)
  local cmd = "release cyclic"
  if abbrev then cmd = "release " .. abbrev end
  local result = DRC.bput(cmd, "You let your concentration",
    "You release", "You aren't preparing",
    "You don't have a cyclic spell active")
  return result:find("release") ~= nil or result:find("concentration") ~= nil
end

--- Release all active cyclic spells except those in the exclusion list.
-- Mirrors Lich5 DRCA.release_cyclics(cyclic_no_release).
-- @param cyclic_no_release table|nil Array of spell names NOT to release (default: release all)
function M.release_cyclics(cyclic_no_release)
  cyclic_no_release = cyclic_no_release or {}

  -- Build set of names to skip
  local skip = {}
  for _, name in ipairs(cyclic_no_release) do
    skip[name] = true
  end

  -- Walk active spells; release those tagged cyclic and not skipped
  if DRSpells and DRSpells.active_spells then
    local spells = DRSpells.active_spells
    if type(spells) == "function" then spells = spells() end
    if type(spells) == "table" then
      for name, data in pairs(spells) do
        if not skip[name] then
          local abbrev = type(data) == "table" and data.abbrev or nil
          if abbrev then
            DRC.bput("release " .. abbrev, unpack(M.CYCLIC_RELEASE_SUCCESS))
          end
        end
      end
    end
  end
end

--- Release the currently prepared spell.
function M.release_spell()
  DRC.bput("release", "You release", "You aren't preparing a spell",
    "You let your concentration")
end

--- Check if a spell is currently active on the character.
-- @param spell_name string Spell name
-- @return boolean
function M.spell_active(spell_name)
  if DRSpells and DRSpells.active_spells then
    local spells = DRSpells.active_spells
    if type(spells) == "function" then spells = spells() end
    if type(spells) == "table" then
      return spells[spell_name] ~= nil
    end
  end
  return false
end

--- Check if a buff needs refreshing (under a time threshold).
-- @param spell_name string Spell name
-- @param threshold number|nil Minutes remaining threshold (default 2)
-- @return boolean true if buff needs refresh
function M.buff_needs_refresh(spell_name, threshold)
  threshold = threshold or 2
  if DRSpells and DRSpells.active_spells then
    local spells = DRSpells.active_spells
    if type(spells) == "function" then spells = spells() end
    if type(spells) == "table" then
      local remaining = spells[spell_name]
      if not remaining then return true end  -- Not active
      return tonumber(remaining) and tonumber(remaining) <= threshold
    end
  end
  return true
end

--- Cast a list of buff spells that need refreshing.
-- @param buff_list table Array of spell_data tables
-- @param settings table Character settings
function M.refresh_buffs(buff_list, settings)
  if not buff_list then return end
  for _, spell_data in ipairs(buff_list) do
    if M.buff_needs_refresh(spell_data.name or spell_data.abbrev) then
      M.cast_spell(spell_data, settings)
      pause(0.5)
    end
  end
end

return M
