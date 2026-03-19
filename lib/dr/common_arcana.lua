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

-------------------------------------------------------------------------------
-- Discern — mana discovery and caching
-- Mirrors Lich5 DRCA.check_discern(data, settings, spell_is_sorcery)
-------------------------------------------------------------------------------

--- Discern a spell's mana requirements and cache the result.
-- Issues the DISCERN verb if cached data is missing or stale.
-- Updates spell_data.mana with the calculated value.
-- Cache persisted in UserVars["discern_cache"] as JSON.
-- @param spell_data table Spell config with at least { abbrev }
-- @param settings table Character settings (check_discern_timer_in_hours, prep_scaling_factor, cambrinth_items)
-- @param spell_is_sorcery boolean|nil True forces a fresh discern regardless of cache age
-- @return table spell_data (mana field updated in-place)
function M.check_discern(spell_data, settings, spell_is_sorcery)
  if not spell_data then return spell_data end
  local abbrev = spell_data.abbrev
  if not abbrev then return spell_data end

  -- Load discern cache from UserVars
  local cache = {}
  local raw = UserVars and UserVars["discern_cache"]
  if raw and raw ~= "" then
    local ok, decoded = pcall(Json.decode, raw)
    if ok and type(decoded) == "table" then cache = decoded end
  end

  local cached = cache[abbrev] or {}
  local timer_hours = (settings and settings.check_discern_timer_in_hours) or 6
  local stale = not cached.timestamp
    or (os.time() - (cached.timestamp or 0)) > (timer_hours * 3600)

  if stale or spell_is_sorcery then
    local result = DRC.bput("discern " .. abbrev,
      "The spell requires at minimum",
      "you don't think you are able to cast this spell",
      "You have no idea how to cast that spell",
      "You don't seem to be able to move")

    local min_str, more_str = result:match(
      "at minimum (%d+) mana streams and you think you can reinforce it with (%d+)")

    if min_str then
      local min_mana  = tonumber(min_str)
      local more_mana = tonumber(more_str) or 0
      local scale     = (settings and settings.prep_scaling_factor) or 1.0
      local total     = math.floor((min_mana + more_mana) * scale)

      -- Without cambrinth the character casts everything; with cambrinth the
      -- character casts ~1/5 and cambrinth provides the rest (simplified).
      local camb = settings and settings.cambrinth_items
      if camb and type(camb) == "table" and #camb > 0 then
        cached.mana = math.max(math.ceil(total / 5.0), min_mana)
      else
        cached.mana = math.max(total, min_mana)
      end
      cached.min       = min_mana
      cached.timestamp = os.time()
    else
      -- Unable to cast or unknown spell — use existing cached value or 1
      cached.mana      = cached.mana or 1
      cached.timestamp = os.time()
    end

    cache[abbrev] = cached
    if waitrt then waitrt() end

    -- Persist updated cache
    if UserVars then
      local ok2, encoded = pcall(Json.encode, cache)
      if ok2 then UserVars["discern_cache"] = encoded end
    end
  end

  if cached.mana then
    spell_data.mana = cached.mana
  end
  return spell_data
end

-------------------------------------------------------------------------------
-- Waggle-set spell casting (hash format: {name → spell_data})
-- Mirrors Lich5 DRCA.cast_spells(spells, settings, force_cambrinth)
-------------------------------------------------------------------------------

--- Cast spells from a waggle_sets hash, skipping those still active.
-- @param spells table Hash of {[spell_name] = spell_data} from waggle_sets
-- @param settings table Character settings (waggle_spells_mana_threshold, etc.)
-- @param force_cambrinth boolean|nil Force cambrinth even when harnessing
function M.cast_spells(spells, settings, force_cambrinth)
  if not spells then return end
  local active = (DRSpells and DRSpells.active_spells) and DRSpells.active_spells() or {}
  local mana_threshold = (settings and settings.waggle_spells_mana_threshold) or 0
  local conc_threshold = (settings and settings.waggle_spells_concentration_threshold) or 0

  for name, data in pairs(spells) do
    -- Determine the recast threshold (minutes remaining below which we recast)
    local recast = data.recast or data["recast"]
    local remaining = active[name]

    -- Skip if spell is active with sufficient time remaining
    if remaining ~= nil and (recast == nil or tonumber(remaining) > tonumber(recast)) then
      -- still active, no recast needed
    else
      -- Wait for mana and concentration thresholds before casting
      while (DRStats and DRStats.mana and DRStats.mana < mana_threshold) or
            (DRStats and DRStats.concentration and DRStats.concentration < conc_threshold) do
        DRC.message("DRCA: waiting on mana >" .. mana_threshold .. " or concentration >" .. conc_threshold)
        pause(15)
      end
      M.cast_spell(data, settings)
    end
  end
end

-------------------------------------------------------------------------------
-- Barbarian ability activation
-- Mirrors Lich5 DRCA.start_barb_abilities / activate_barb_buff?
-------------------------------------------------------------------------------

local BARB_BUFF_MAX_RETRIES = 3

--- Activate a single barbarian ability/meditation.
-- @param name string Ability name (key in barb_abilities data)
-- @param settings table Character settings
-- @param spell_data table|nil Loaded barb_abilities data from get_data("spells")
-- @param retries number|nil Remaining retry count
-- @return boolean true if activated
function M.activate_barb_buff(name, settings, spell_data, retries)
  if retries == nil then retries = BARB_BUFF_MAX_RETRIES end
  local active = (DRSpells and DRSpells.active_spells) and DRSpells.active_spells() or {}
  if active[name] then return true end

  if retries <= 0 then
    DRC.message("DRCA: exhausted retries for barbarian ability: " .. tostring(name))
    return false
  end

  local ability_data = spell_data and spell_data[name]
  if not ability_data then
    DRC.message("DRCA: no data for barbarian ability: " .. tostring(name))
    return false
  end

  local meditation_pause_timer = (settings and settings.meditation_pause_timer) or 20
  local sit_to_meditate = (settings and settings.sit_to_meditate) or false

  if ability_data.type == "meditation" and sit_to_meditate then
    DRC.retreat()
    DRC.bput("sit", "You sit", "You are already", "You rise", "While swimming?")
  end

  local activated_msg = ability_data.activated_message or "You feel"
  local result = DRC.bput(ability_data.start_command or ("meditate " .. name),
    activated_msg,
    "You have not been trained",
    "But you are already",
    "Your inner fire lacks",
    "find yourself lacking the inner fire",
    "You should stand",
    "You must be sitting",
    "You must be unengaged",
    "While swimming?")

  if result:find("must be unengaged") then
    DRC.retreat()
    return M.activate_barb_buff(name, settings, spell_data, retries - 1)
  elseif result:find("must be sitting") then
    DRC.retreat()
    local sit_result = DRC.bput("sit", "You sit", "You are already", "You rise", "While swimming?")
    if sit_result:find("swimming") then
      DRC.message("DRCA: cannot sit to activate '" .. name .. "' — too deep")
      return false
    end
    return M.activate_barb_buff(name, settings, spell_data, retries - 1)
  elseif result:find("should stand") then
    DRC.fix_standing()
    return M.activate_barb_buff(name, settings, spell_data, retries - 1)
  end

  if ability_data.type == "meditation" and meditation_pause_timer and meditation_pause_timer > 0 then
    pause(meditation_pause_timer)
  end
  if waitrt then waitrt() end
  DRC.fix_standing()
  return true
end

--- Activate all barbarian abilities from a waggle_sets hash.
-- @param abilities table Hash of {[ability_name] = data} from waggle_sets
-- @param settings table Character settings
function M.start_barb_abilities(abilities, settings)
  local spell_data = nil
  if get_data then
    local spells_db = get_data("spells")
    spell_data = spells_db and spells_db.barb_abilities
  end
  for name, _ in pairs(abilities) do
    M.activate_barb_buff(name, settings, spell_data)
  end
end

-------------------------------------------------------------------------------
-- Thief khri activation
-- Mirrors Lich5 DRCA.start_khris / activate_khri?
-------------------------------------------------------------------------------

--- Default khri preparation response patterns (overridden by get_data("spells").khri_preps).
local DEFAULT_KHRI_PREPS = {
  "Your mind and body are willing",
  "Your body is willing",
  "You have not recovered",
  "You haven't fully recovered",
  "Khri Hasten would have you moving",
  "You use a bit of mental energy",
  "You feel a sense of",
}

--- Activate a single khri ability string.
-- Handles "Khri X Y", "Delay X", etc.
-- @param kneel boolean|table Whether/which abilities require kneeling
-- @param ability string Ability string from waggle_sets key
-- @return boolean true if activated or already active
function M.activate_khri(kneel, ability)
  -- Parse: capitalize each word
  local abilities = {}
  for word in ability:gmatch("%S+") do
    abilities[#abilities + 1] = word:sub(1,1):upper() .. word:sub(2):lower()
  end

  -- Drop leading "Khri" token if present
  if abilities[1] and abilities[1]:lower() == "khri" then
    table.remove(abilities, 1)
  end

  -- Handle "Delay" modifier
  local should_delay = false
  if abilities[1] and abilities[1]:lower() == "delay" then
    should_delay = true
    table.remove(abilities, 1)
  end

  -- Check which abilities are not yet active
  local active = (DRSpells and DRSpells.active_spells) and DRSpells.active_spells() or {}
  local needed = {}
  for _, a in ipairs(abilities) do
    if not active["Khri " .. a] then
      needed[#needed + 1] = a
    end
  end
  if #needed == 0 then return true end

  -- Load khri prep patterns from data if available
  local preps = DEFAULT_KHRI_PREPS
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.khri_preps and type(spells_db.khri_preps) == "table" then
      preps = spells_db.khri_preps
    end
  end

  -- Check if any needed ability requires kneeling
  local needs_kneel = false
  if type(kneel) == "boolean" and kneel then
    needs_kneel = true
  elseif type(kneel) == "table" then
    for _, a in ipairs(needed) do
      for _, k in ipairs(kneel) do
        if string.lower(a) == string.lower(k:gsub("^[Kk]hri ", "")) then
          needs_kneel = true
          break
        end
      end
      if needs_kneel then break end
    end
  end

  if needs_kneel then
    DRC.retreat()
    DRC.bput("kneel", "You kneel", "You are already", "You rise", "While swimming?")
  end

  local cmd = "Khri " .. (should_delay and "Delay " or "") .. table.concat(needed, " ")
  DRC.bput(cmd, table.unpack(preps))
  if waitrt then waitrt() end
  DRC.fix_standing()
  return true
end

--- Activate all khri abilities from a waggle_sets hash.
-- @param khris table Hash of {[ability_string] = data} from waggle_sets
-- @param settings table Character settings (kneel_khri)
function M.start_khris(khris, settings)
  local kneel = (settings and settings.kneel_khri) or false
  for khri_set, _ in pairs(khris) do
    M.activate_khri(kneel, khri_set)
  end
end

-------------------------------------------------------------------------------
-- Crafting magic routine
-- Mirrors Lich5 DRCA.crafting_magic_routine(settings)
-------------------------------------------------------------------------------

--- Cast crafting training spells if configured in settings.
-- Called periodically during crafting loops to maintain buff uptime.
-- Uses settings.crafting_training_spells (a waggle_sets-style table) if present,
-- otherwise falls back to do_buffs with the "crafting" set name.
-- @param settings table Character settings
function M.crafting_magic_routine(settings)
  if not settings then return end
  if settings.crafting_training_spells then
    if type(settings.crafting_training_spells) == "table" then
      M.cast_spells(settings.crafting_training_spells, settings)
    else
      M.do_buffs(settings, "crafting")
    end
  elseif settings.waggle_sets and settings.waggle_sets["crafting"] then
    M.do_buffs(settings, "crafting")
  end
end

-------------------------------------------------------------------------------
-- do_buffs — main waggle buff entry point
-- Mirrors Lich5 DRCA.do_buffs(settings, set_name)
-------------------------------------------------------------------------------

--- Cast all buffs in a waggle_sets entry, dispatching by guild type.
-- For barbarians: activates barb meditations/abilities.
-- For thieves: activates khri abilities.
-- For all others: casts spells, skipping those still active, with day/night filtering.
-- @param settings table Character settings (must have waggle_sets)
-- @param set_name string Which waggle set to use (e.g. "default")
function M.do_buffs(settings, set_name)
  if not settings or not settings.waggle_sets then return end
  if not settings.waggle_sets[set_name] then return end

  local spells = settings.waggle_sets[set_name]

  if DRStats and DRStats.barbarian and DRStats.barbarian() then
    M.start_barb_abilities(spells, settings)
  elseif DRStats and DRStats.thief and DRStats.thief() then
    M.start_khris(spells, settings)
  else
    -- Day/night filtering: decode UserVars.sun JSON if present
    local sun = nil
    if UserVars and UserVars.sun and UserVars.sun ~= "" then
      local ok, decoded = pcall(Json.decode, UserVars.sun)
      if ok and type(decoded) == "table" then sun = decoded end
    end

    if sun then
      local filtered = {}
      for name, data in pairs(spells) do
        local include = true
        if data.night and not sun.night then include = false end
        if data.day and not sun.day then include = false end
        if include then filtered[name] = data end
      end
      spells = filtered
    end

    M.cast_spells(spells, settings, settings.waggle_force_cambrinth)
  end
end

return M
