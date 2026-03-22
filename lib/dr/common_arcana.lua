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

--- Infuse OM success patterns (Warrior Mage off-mana infusion)
M.INFUSE_OM_SUCCESS = {
  "having reached its full capacity",
  "A sense of fullness",
  "Something in the area is interfering with your attempt to harness",
}

--- Infuse OM failure patterns
M.INFUSE_OM_FAILURE = {
  "as if it hungers for more",
  "Your infusion fails completely",
  "You don't have enough harnessed mana to infuse that much",
  "You have no harnessed",
}

--- Starlight aura messages (Trader perceive aura, ordered by level 0-9)
M.STARLIGHT_MESSAGES = {
  "The smallest hint of starlight flickers within your aura",
  "A bare flicker of starlight plays within your aura",
  "A faint amount of starlight illuminates your aura",
  "Your aura pulses slowly with starlight",
  "A steady pulse of starlight runs through your aura",
  "Starlight dances vividly across the confines of your aura",
  "Strong pulses of starlight flare within your aura",
  "Your aura seethes with brilliant starlight",
  "Your aura is blinding",
  "The power contained in your aura",
}

--- Warrior Mage elemental charge levels (ordered 0-11)
M.CHARGE_LEVELS = {
  "You sense nothing out of the ordinary",
  "A small charge lingers within your body, just above the threshold of perception",
  "A small charge lingers within your body",
  "A charge dances through your body",
  "A charge dances just below the threshold of discomfort",
  "A charge circulates through your body, causing a low hum",
  "Elemental essence floats freely within your body, leaving little untouched",
  "Elemental essence has infused every inch of your body",
  "Extraplanar power crackles within your body, leaving you feeling mildly feverish",
  "Extraplanar power crackles within your body, leaving you feeling acutely ill",
  "Your body sings and crackles with a barely contained charge",
  "You have reached the limits of your body's capacity to store a charge",
}

--- Symbiosis pattern for perceive research
M.SYMBIOSIS_PATTERN = "combine the weaves of the (%w+) symbiosis"

--- Useless runestone patterns
M.USELESS_RUNESTONE = { "You get a useless" }

--- Get runestone success patterns
M.GET_RUNESTONE_SUCCESS = { "You get", "You pick up" }

--- Get runestone failure patterns
M.GET_RUNESTONE_FAILURE = { "What were you referring to", "I could not find" }

--- Segue messages (Bard enchante segue)
M.SEGUE_SUCCESS = { "You segue", "Roundtime" }
M.SEGUE_FAILURE = {
  "You must be performing a cyclic spell to segue from",
  "It is too soon to segue",
  "You are lacking the bardic flair",
}

--- Retry limits
M.INFUSE_OM_MAX_RETRIES = 20
M.PREPARE_MAX_RETRIES = 3
M.CAST_MAX_RETRIES = 3

--- Mana level descriptors for parse_mana_message
-- Lich5 uses $MANA_MAP; we inline the data here.
M.MANA_MAP = {
  weak       = { "dim", "faint", "muted", "thin", "sparse", "feeble", "tenuous", "scant", "meager", "weak" },
  developing = { "modest", "fair", "nascent", "building", "developing", "steady", "budding", "growing", "emerging", "forming" },
  improving  = { "improving", "notable", "significant", "substantial", "marked", "considerable", "pronounced", "strong", "vigorous", "robust" },
  good       = { "good", "potent", "plentiful", "abundant", "rich", "powerful", "overwhelming", "tremendous", "brilliant", "superb" },
}

-------------------------------------------------------------------------------
-- Internal state
-------------------------------------------------------------------------------
M._backfired_status = false

-------------------------------------------------------------------------------
-- Spell casting
-------------------------------------------------------------------------------

--- Prepare a spell (simple).
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

--- Prepare a spell with full Lich5 parity (retries, symbiosis, runestone, custom prep).
-- Mirrors Lich5 DRCA.prepare?(abbrev, mana, symbiosis, command, tattoo_tm, runestone_name, runestone_tm, custom_prep).
-- @param abbrev string Spell abbreviation
-- @param mana number Mana amount
-- @param symbiosis boolean|nil Prepare symbiosis first
-- @param command string|nil Prep command (default "prepare")
-- @param tattoo_tm boolean|nil Target after prep for tattoo TM
-- @param runestone_name string|nil If set, invoke runestone instead of prepare
-- @param runestone_tm boolean|nil Target after prep for runestone TM
-- @param custom_prep string|nil Custom prep message to add to match list
-- @param retries number|nil Remaining retry count
-- @return string|false Match result or false on failure
function M.prepare_spell(abbrev, mana, symbiosis, command, tattoo_tm, runestone_name, runestone_tm, custom_prep, retries)
  if not abbrev then return false end
  retries = retries or M.PREPARE_MAX_RETRIES
  command = command or "prepare"

  -- Load prep messages from data or use defaults
  local prep_messages = {}
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.prep_messages then
      for _, p in ipairs(spells_db.prep_messages) do prep_messages[#prep_messages + 1] = p end
    end
  end
  if #prep_messages == 0 then
    prep_messages = {
      "You begin to", "You raise your hand", "With quiet discipline",
      "already preparing", "You're already preparing", "You feel fully prepared",
      "Your desire to prepare this offensive spell suddenly slips away",
      "Something in the area interferes with your spell preparations",
      "You shouldn't disrupt the area right now",
      "You have no idea how to cast that spell",
      "You have yet to receive any training in the magical arts",
      "Please don't do that here",
      "You cannot use the tattoo while maintaining the effort to stay hidden",
      "Well, that was fun",
      "You'll have to hold it",
    }
  end
  if custom_prep then prep_messages[#prep_messages + 1] = custom_prep end

  if symbiosis then
    DRC.bput("prepare symbiosis", "You recall the exact details of the",
      "But you've already prepared", "Please don't do that here")
  end

  local match
  if not runestone_name then
    match = DRC.bput(command .. " " .. abbrev .. " " .. tostring(mana or ""), table.unpack(prep_messages))
  else
    local invoke_messages = { "The .* pulses", "Roundtime", "Invoke what" }
    if get_data then
      local spells_db = get_data("spells")
      if spells_db and spells_db.invoke_messages then invoke_messages = spells_db.invoke_messages end
    end
    match = DRC.bput(command .. " my " .. runestone_name, table.unpack(invoke_messages))
  end

  if match:find("Your desire to prepare this offensive spell suddenly slips away") then
    if retries <= 0 then
      DRC.message("DRCA: prepare_spell exhausted retries for '" .. abbrev .. "'")
      return false
    end
    pause(1)
    return M.prepare_spell(abbrev, mana, symbiosis, command, tattoo_tm, runestone_name, runestone_tm, custom_prep, retries - 1)
  end

  if match:find("Something in the area interferes")
    or match:find("You shouldn't disrupt the area")
    or match:find("You have no idea how to cast that spell")
    or match:find("You have yet to receive any training")
    or match:find("Please don't do that here")
    or match:find("You cannot use the tattoo") then
    if symbiosis then
      DRC.bput("release symbiosis", "You release the", "But you haven't")
    end
    return false
  end

  if match:find("Well, that was fun") then
    if DRCI and runestone_name then DRCI.dispose_trash(runestone_name) end
    return false
  end

  if match:find("You'll have to hold it") then
    return false
  end

  if tattoo_tm or runestone_tm then
    DRC.bput("target", table.unpack(prep_messages))
  end

  return match
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

--- Cast with full Lich5 parity (retries, symbiosis, before/after actions, backfire detection).
-- Mirrors Lich5 DRCA.cast?(cast_command, symbiosis, before, after).
-- @param cast_command string|nil Cast command (default "cast")
-- @param symbiosis boolean|nil Whether symbiosis is active
-- @param before table|nil Array of {message=, matches=} actions to run before cast
-- @param after table|nil Array of {message=, matches=} actions to run after cast
-- @param retries number|nil Remaining retry count
-- @return boolean true if cast succeeded (no spell-fail)
function M.cast_spell_check(cast_command, symbiosis, before, after, retries)
  retries = retries or M.CAST_MAX_RETRIES
  before = before or {}
  after = after or {}

  for _, action in ipairs(before) do
    if action.message and action.matches then
      DRC.bput(action.message, table.unpack(action.matches))
    end
  end

  -- Load cast messages from data or use defaults
  local cast_messages = {}
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.cast_messages then
      cast_messages = spells_db.cast_messages
    end
  end
  if #cast_messages == 0 then
    for _, p in ipairs(M.CAST_SUCCESS) do cast_messages[#cast_messages + 1] = p end
    for _, p in ipairs(M.CAST_FAILURE) do cast_messages[#cast_messages + 1] = p end
    cast_messages[#cast_messages + 1] = "Your target pattern dissipates"
    cast_messages[#cast_messages + 1] = "You can't cast that at yourself"
    cast_messages[#cast_messages + 1] = "You need to specify a body part to consume"
    cast_messages[#cast_messages + 1] = "There is nothing else to face"
    cast_messages[#cast_messages + 1] = "Currently lacking the skill to complete the pattern"
    cast_messages[#cast_messages + 1] = "You don't have a spell prepared"
    cast_messages[#cast_messages + 1] = "Your spell .- backfires"
    cast_messages[#cast_messages + 1] = "Something is interfering with the spell"
    cast_messages[#cast_messages + 1] = "You strain, but are too mentally fatigued"
    cast_messages[#cast_messages + 1] = "The spell pattern resists the influx"
    cast_messages[#cast_messages + 1] = "The mental strain of initiating a cyclic spell so recently"
    cast_messages[#cast_messages + 1] = "This pattern may only be cast with full preparation"
  end

  local result = DRC.bput(cast_command or "cast", table.unpack(cast_messages))

  -- Handle target-pattern / self-cast failures
  if result:find("Your target pattern dissipates")
    or result:find("You can't cast that at yourself")
    or result:find("You need to specify a body part")
    or result:find("There is nothing else to face") then
    DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
    DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
  end

  if result:find("You gesture") then
    pause(0.25)
  end
  if waitrt then waitrt() end

  -- Cyclic-too-recent or full-prep retry
  if result:find("mental strain of initiating a cyclic")
    or result:find("This pattern may only be cast with full preparation") then
    if retries <= 0 then
      DRC.message("DRCA: cast_spell_check exhausted retries — giving up")
      return false
    end
    pause(1)
    return M.cast_spell_check(cast_command, symbiosis, {}, after, retries - 1)
  end

  for _, action in ipairs(after) do
    if action.message and action.matches then
      DRC.bput(action.message, table.unpack(action.matches))
    end
  end

  -- Detect spell failure
  local spell_fail = result:find("Currently lacking the skill")
    or result:find("You don't have a spell prepared")
    or result:find("backfires")
    or result:find("Something is interfering with the spell")
    or result:find("There is nothing else to face")
    or result:find("You strain, but are too mentally fatigued")
    or result:find("The spell pattern resists the influx")
    or result:find("Your target pattern dissipates")

  if symbiosis and spell_fail then
    DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
    DRC.bput("release symbiosis", "You release", "But you haven't prepared")
  elseif spell_fail then
    DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
  end

  -- Track backfire
  M._backfired_status = result:find("backfires") ~= nil

  return not spell_fail
end

--- Check if the last cast backfired.
-- Mirrors Lich5 DRCA.backfired?
-- @return boolean
function M.backfired()
  return M._backfired_status or false
end

--- Harness with boolean result.
-- Mirrors Lich5 DRCA.harness?(mana).
-- @param mana number Amount to harness
-- @return boolean true if harness succeeded
function M.harness_check(mana)
  local result = DRC.bput("harness " .. tostring(mana), "You tap into", "Strain though you may")
  pause(0.5)
  if waitrt then waitrt() end
  return result:find("You tap into") ~= nil
end

--- Harness a list of mana amounts, stopping on first failure.
-- Mirrors Lich5 DRCA.harness_mana(amounts).
-- @param amounts table Array of mana amounts
function M.harness_mana_list(amounts)
  if not amounts then return end
  for _, mana in ipairs(amounts) do
    if not M.harness_check(mana) then break end
  end
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
-- Uses spell_data from get_data("spells") to identify cyclic spells,
-- then releases any that are currently active and not in the skip list.
-- @param cyclic_no_release table|nil Array of spell names NOT to release (default: release all)
function M.release_cyclics(cyclic_no_release)
  cyclic_no_release = cyclic_no_release or {}

  -- Build set of names to skip
  local skip = {}
  for _, name in ipairs(cyclic_no_release) do
    skip[name] = true
  end

  -- Get active spells
  local active = {}
  if DRSpells and DRSpells.active_spells then
    local spells = DRSpells.active_spells
    if type(spells) == "function" then spells = spells() end
    if type(spells) == "table" then active = spells end
  end

  -- Get spell database to identify cyclic spells
  local spell_data = nil
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.spell_data then spell_data = spells_db.spell_data end
  end

  if spell_data then
    -- Lich5 approach: filter spell_data for cyclic, check if active, reject skipped
    for name, props in pairs(spell_data) do
      if props.cyclic and active[name] and not skip[name] then
        local abbrev = props.abbrev or name
        DRC.bput("release " .. abbrev,
          table.unpack(M.CYCLIC_RELEASE_SUCCESS),
          "Release what?")
      end
    end
  else
    -- Fallback: walk active spells directly (pre-existing behavior)
    for name, data in pairs(active) do
      if not skip[name] then
        local abbrev = type(data) == "table" and data.abbrev or nil
        if abbrev then
          DRC.bput("release " .. abbrev, table.unpack(M.CYCLIC_RELEASE_SUCCESS))
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

-------------------------------------------------------------------------------
-- Focus item management
-- Mirrors Lich5 DRCA.find_focus / DRCA.stow_focus
-------------------------------------------------------------------------------

--- Patterns for wielding (unsheathing) a focus item.
local WIELD_FOCUS_SUCCESS = { "You wield", "You remove", "You grab", "You are already holding" }
local WIELD_FOCUS_FAILURE = { "Wield what", "I could not find", "You can't seem" }

--- Patterns for sheathing a focus item.
local SHEATHE_FOCUS_SUCCESS = { "You sheathe", "You push", "You slide" }
local SHEATHE_FOCUS_FAILURE = { "Sheathe what", "I could not find", "You can't seem" }

--- Get (find and hold) a ritual focus item.
-- Mirrors Lich5 DRCA.find_focus(focus, worn, tied, sheathed).
-- worn → remove item; tied → untie from tied anchor; sheathed → wield item; else → get item.
-- @param focus string Focus item name
-- @param worn boolean If true, focus is worn (remove it to hold)
-- @param tied string|nil If set, focus is tied to this anchor (untie it)
-- @param sheathed boolean If true, focus is sheathed (wield it)
-- @return boolean true on success
function M.find_focus(focus, worn, tied, sheathed)
  if not focus or focus == "" then return false end
  if worn then
    return DRCI.remove_item(focus)
  elseif tied and tied ~= "" then
    return DRCI.untie_item(focus, tied)
  elseif sheathed then
    local all = {}
    for _, p in ipairs(WIELD_FOCUS_SUCCESS) do all[#all + 1] = p end
    for _, p in ipairs(WIELD_FOCUS_FAILURE) do all[#all + 1] = p end
    local result = DRC.bput("wield my " .. focus, unpack(all))
    for _, p in ipairs(WIELD_FOCUS_FAILURE) do
      if result:find(p) then return false end
    end
    return true
  else
    return DRCI.get_item(focus)
  end
end

--- Stow (put away) a ritual focus item.
-- Mirrors Lich5 DRCA.stow_focus(focus, worn, tied, sheathed).
-- worn → wear item; tied → tie to anchor; sheathed → sheathe item; else → stow item.
-- @param focus string Focus item name
-- @param worn boolean If true, focus should be worn
-- @param tied string|nil If set, focus should be tied to this anchor
-- @param sheathed boolean If true, focus should be sheathed
-- @return boolean true on success
function M.stow_focus(focus, worn, tied, sheathed)
  if not focus or focus == "" then return false end
  if worn then
    return DRCI.wear_item(focus)
  elseif tied and tied ~= "" then
    return DRCI.tie_item(focus, tied)
  elseif sheathed then
    local all = {}
    for _, p in ipairs(SHEATHE_FOCUS_SUCCESS) do all[#all + 1] = p end
    for _, p in ipairs(SHEATHE_FOCUS_FAILURE) do all[#all + 1] = p end
    local result = DRC.bput("sheathe my " .. focus, unpack(all))
    for _, p in ipairs(SHEATHE_FOCUS_FAILURE) do
      if result:find(p) then return false end
    end
    return true
  else
    return DRCI.put_away_item(focus)
  end
end

-------------------------------------------------------------------------------
-- Cambrinth core — advanced item management
-- Mirrors Lich5 DRCA.find_cambrinth / stow_cambrinth / charge? / invoke /
--   find_charge_invoke_stow / skilled_to_charge_while_worn? /
--   normalize_cambrinth_items / charge_cambrinth_items / charge_and_invoke
-------------------------------------------------------------------------------

--- Check if Arcana skill is high enough to charge cambrinth while worn.
-- Mirrors Lich5 DRCA.skilled_to_charge_while_worn?(cambrinth_cap).
-- @param cambrinth_cap number Cambrinth capacity
-- @return boolean
function M.skilled_to_charge_while_worn(cambrinth_cap)
  if not DRSkill then return false end
  local arcana = 0
  if DRSkill.getrank then
    arcana = tonumber(DRSkill.getrank("Arcana")) or 0
  end
  return arcana >= ((tonumber(cambrinth_cap) or 0) * 2 + 100)
end

--- Find (get into hands) a cambrinth item based on storage configuration.
-- Mirrors Lich5 DRCA.find_cambrinth(cambrinth, stored_cambrinth, cambrinth_cap).
-- @param cambrinth string Cambrinth item name
-- @param stored_cambrinth boolean Whether cambrinth is normally stowed
-- @param cambrinth_cap number Cambrinth capacity (for skill check)
-- @return boolean
function M.find_cambrinth_item(cambrinth, stored_cambrinth, cambrinth_cap)
  if not cambrinth then return false end
  if not DRCI then return false end

  if stored_cambrinth then
    -- Config says stowed: get it, or try removing if worn by accident
    return (DRCI.get_item_if_not_held and DRCI.get_item_if_not_held(cambrinth))
      or (DRCI.remove_item and DRCI.remove_item(cambrinth))
      or false
  elseif not M.skilled_to_charge_while_worn(cambrinth_cap) then
    -- Worn but not skilled enough: need it in hands
    if DRCI.in_hands and DRCI.in_hands(cambrinth) then return true end
    return (DRCI.remove_item and DRCI.remove_item(cambrinth))
      or (DRCI.get_item and DRCI.get_item(cambrinth))
      or false
  else
    -- Worn and skilled: assume it's on you
    return true
  end
end

--- Stow a cambrinth item back to its configured location.
-- Mirrors Lich5 DRCA.stow_cambrinth(cambrinth, stored_cambrinth, cambrinth_cap).
-- @param cambrinth string Cambrinth item name
-- @param stored_cambrinth boolean Whether cambrinth is normally stowed
-- @param cambrinth_cap number Cambrinth capacity (unused, kept for signature parity)
-- @return boolean
function M.stow_cambrinth_item(cambrinth, stored_cambrinth, cambrinth_cap)
  if not cambrinth then return false end
  if not DRCI then return false end

  if stored_cambrinth then
    -- Config says stowed: get it to hands if needed, then stow
    if DRCI.in_hands and not DRCI.in_hands(cambrinth) then
      if not (DRCI.get_item_if_not_held and DRCI.get_item_if_not_held(cambrinth)) then
        if DRCI.remove_item then DRCI.remove_item(cambrinth) end
      end
    end
    if DRCI.stow_item then return DRCI.stow_item(cambrinth) end
    return false
  elseif DRCI.in_hands and DRCI.in_hands(cambrinth) then
    -- Config says worn but it's in hands: wear it, or stow as fallback
    if DRCI.wear_item and DRCI.wear_item(cambrinth) then return true end
    if DRCI.stow_item then return DRCI.stow_item(cambrinth) end
    return false
  else
    -- Config says worn and it's not in hands: assume wearing, nothing to do
    return true
  end
end

--- Charge a cambrinth item with boolean result and retry logic.
-- Mirrors Lich5 DRCA.charge?(cambrinth, mana).
-- @param cambrinth string Cambrinth item name
-- @param mana number Mana amount to charge
-- @return boolean true if charge absorbed successfully
function M.charge_check(cambrinth, mana)
  -- Load charge messages from data or use defaults
  local charge_messages = {}
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.charge_messages then
      charge_messages = spells_db.charge_messages
    end
  end
  if #charge_messages == 0 then
    charge_messages = {
      "absorbs all of the energy",
      "You harness", "You tap .* to channel", "Roundtime",
      "You are in no condition to do that",
      "You'll have to hold it",
      "you find it too clumsy",
      "I could not find",
    }
  end

  local result = DRC.bput("charge my " .. cambrinth .. " " .. tostring(mana), table.unpack(charge_messages))
  pause(1)
  if waitrt then waitrt() end

  local charged = false
  local retry_find = false

  if result:find("You are in no condition") then
    charged = M.harness_check(mana)
  elseif result:find("You'll have to hold it") then
    DRC.message("DRCA: where did your cambrinth go?")
    retry_find = true
  elseif result:find("you find it too clumsy") then
    DRC.message("DRCA: your arcana skill is too low to charge your cambrinth while worn")
    retry_find = true
  else
    charged = result:find("absorb") ~= nil
      or result:find("You harness") ~= nil
      or result:find("You tap") ~= nil
  end

  if retry_find and DRCI then
    if not (DRCI.in_hands and DRCI.in_hands(cambrinth)) then
      M.find_cambrinth_item(cambrinth, false, 999)
      if DRCI.in_hands and DRCI.in_hands(cambrinth) then
        charged = M.charge_check(cambrinth, mana)
        M.stow_cambrinth_item(cambrinth, false, 999)
      end
    end
  end

  return charged
end

--- Invoke a cambrinth item with full Lich5 parity.
-- Mirrors Lich5 DRCA.invoke(cambrinth, dedicated_camb_use, invoke_amount).
-- @param cambrinth string Cambrinth item name
-- @param dedicated_camb_use string|nil Dedicated cambrinth use string
-- @param invoke_amount number|nil Exact amount to invoke
function M.invoke_full(cambrinth, dedicated_camb_use, invoke_amount)
  if not cambrinth then return end

  local cmd = "invoke my " .. cambrinth
  if invoke_amount then cmd = cmd .. " " .. tostring(invoke_amount) end
  if dedicated_camb_use and dedicated_camb_use ~= "" then cmd = cmd .. " " .. dedicated_camb_use end

  local invoke_messages = {}
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.invoke_messages then
      invoke_messages = spells_db.invoke_messages
    end
  end
  if #invoke_messages == 0 then
    invoke_messages = {
      "The .* pulses with energy", "You feel the mana from",
      "draw energy from", "you find it too clumsy", "Invoke what?",
    }
  end

  local result = DRC.bput(cmd, table.unpack(invoke_messages))
  pause(1)
  if waitrt then waitrt() end

  if result:find("you find it too clumsy") then
    DRC.message("DRCA: your arcana skill is too low to invoke your cambrinth while worn")
    if DRCI and not (DRCI.in_hands and DRCI.in_hands(cambrinth)) then
      M.find_cambrinth_item(cambrinth, false, 999)
      if DRCI.in_hands and DRCI.in_hands(cambrinth) then
        M.invoke_full(cambrinth, dedicated_camb_use, invoke_amount)
        M.stow_cambrinth_item(cambrinth, false, 999)
      end
    end
  end
end

--- Charge and invoke a cambrinth item (charges array + single invoke).
-- Mirrors Lich5 DRCA.charge_and_invoke(cambrinth, dedicated_camb_use, charges, invoke_exact_amount).
-- @param cambrinth string Cambrinth item name
-- @param dedicated_camb_use string|nil Dedicated cambrinth use string
-- @param charges table Array of mana amounts to charge
-- @param invoke_exact_amount number|nil If set, invoke the sum of charges
function M.charge_and_invoke_full(cambrinth, dedicated_camb_use, charges, invoke_exact_amount)
  if not charges or #charges == 0 then return end

  for _, mana in ipairs(charges) do
    if not M.charge_check(cambrinth, mana) then break end
  end

  local invoke_amount = nil
  if invoke_exact_amount then
    invoke_amount = 0
    for _, c in ipairs(charges) do invoke_amount = invoke_amount + c end
  end

  M.invoke_full(cambrinth, dedicated_camb_use, invoke_amount)
end

--- Full find->charge->invoke->stow workflow for a single cambrinth item.
-- Mirrors Lich5 DRCA.find_charge_invoke_stow(cambrinth, stored, cap, dedicated, charges, invoke_exact).
-- @param cambrinth string Cambrinth item name
-- @param stored_cambrinth boolean Whether cambrinth is normally stowed
-- @param cambrinth_cap number Cambrinth capacity
-- @param dedicated_camb_use string|nil Dedicated cambrinth use string
-- @param charges table Array of mana amounts
-- @param invoke_exact_amount number|nil If set, invoke exact sum
function M.find_charge_invoke_stow(cambrinth, stored_cambrinth, cambrinth_cap, dedicated_camb_use, charges, invoke_exact_amount)
  if not charges then return end

  M.find_cambrinth_item(cambrinth, stored_cambrinth, cambrinth_cap)
  M.charge_and_invoke_full(cambrinth, dedicated_camb_use, charges, invoke_exact_amount)
  M.stow_cambrinth_item(cambrinth, stored_cambrinth, cambrinth_cap)
end

--- Normalize cambrinth_items in settings to structured form.
-- Mirrors Lich5 DRCA.normalize_cambrinth_items(settings).
-- Converts legacy single-item settings into the cambrinth_items array format.
-- @param settings table Character settings
function M.normalize_cambrinth_items(settings)
  if not settings then return end
  if not settings.cambrinth_items then
    settings.cambrinth_items = {}
  end
  if #settings.cambrinth_items == 0 then return end

  -- Already normalized if first item has 'name'
  local first = settings.cambrinth_items[1]
  if type(first) == "table" and first.name then return end

  -- Convert from legacy format
  settings.cambrinth_items = { {
    name   = settings.cambrinth or "cambrinth",
    cap    = settings.cambrinth_cap or 0,
    stored = settings.stored_cambrinth or false,
  } }
end

--- Charge all cambrinth items for a spell.
-- Mirrors Lich5 DRCA.charge_cambrinth_items(data, settings).
-- @param data table Spell data with cambrinth charge array
-- @param settings table Character settings (cambrinth_items, dedicated_camb_use, etc.)
function M.charge_cambrinth_items(data, settings)
  if not data or not data.cambrinth then return end
  if not settings or not settings.cambrinth_items then return end

  for index, item in ipairs(settings.cambrinth_items) do
    local charges = nil
    -- Check if cambrinth is array-of-arrays or flat array
    if type(data.cambrinth[1]) == "table" then
      charges = data.cambrinth[index]
    else
      charges = data.cambrinth
    end
    if charges then
      M.find_charge_invoke_stow(
        item.name, item.stored, item.cap,
        settings.dedicated_camb_use, charges,
        settings.cambrinth_invoke_exact_amount
      )
    end
  end
end

--- Check whether to harness instead of using cambrinth.
-- Mirrors Lich5 DRCA.check_to_harness(should_harness).
-- Returns true if should_harness is set and Attunement XP <= Arcana XP.
-- @param should_harness boolean|nil Whether harness-when-locked is enabled
-- @return boolean
function M.check_to_harness(should_harness)
  if not should_harness then return false end
  if not DRSkill then return false end
  local att_xp = DRSkill.getxp and tonumber(DRSkill.getxp("Attunement")) or 0
  local arc_xp = DRSkill.getxp and tonumber(DRSkill.getxp("Arcana")) or 0
  return att_xp <= arc_xp
end

-------------------------------------------------------------------------------
-- Cast variants — crafting, ritual, segue
-------------------------------------------------------------------------------

--- Prepare a spell for crafting (release existing, prep fresh).
-- Mirrors Lich5 DRCA.crafting_prepare_spell(data, settings).
-- @param data table Spell data
-- @param settings table Character settings
-- @return string|false Result of prepare, or false
function M.crafting_prepare_spell(data, settings)
  if not data or not settings then return false end

  -- Release existing spells
  if data.cyclic then M.release_cyclics() end
  DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
  DRC.bput("release mana", "You release all", "You aren't harnessing any mana")

  local command = "prep"
  if data.prep then command = data.prep end
  if data.prep_type then command = data.prep_type end

  return M.prepare_spell(data.abbrev, data.mana, data.symbiosis, command,
    data.tattoo_tm, data.runestone_name, data.runestone_tm,
    settings.custom_spell_prep)
end

--- Cast a spell for crafting (charge cambrinth + cast).
-- Mirrors Lich5 DRCA.crafting_cast_spell(data, settings).
-- @param data table Spell data
-- @param settings table Character settings
-- @return boolean
function M.crafting_cast_spell(data, settings)
  if not data or not settings then return false end

  M.normalize_cambrinth_items(settings)
  if M.check_to_harness(settings.use_harness_when_arcana_locked) then
    local flat = data.cambrinth
    if type(flat) == "table" and type(flat[1]) == "table" then
      -- Flatten nested arrays
      local flattened = {}
      for _, arr in ipairs(flat) do
        for _, v in ipairs(arr) do flattened[#flattened + 1] = v end
      end
      flat = flattened
    end
    M.harness_mana_list(flat)
  else
    M.charge_cambrinth_items(data, settings)
  end

  return M.cast_spell_check(data.cast, data.symbiosis, data.before, data.after)
end

--- Bard enchante segue check.
-- Mirrors Lich5 DRCA.segue?(abbrev, mana).
-- @param abbrev string Spell abbreviation
-- @param mana number Mana amount
-- @return boolean true if segue succeeded (should skip normal prep)
function M.segue(abbrev, mana)
  local all = {}
  for _, p in ipairs(M.SEGUE_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.SEGUE_FAILURE) do all[#all + 1] = p end

  -- Load from data if available
  if get_data then
    local spells_db = get_data("spells")
    if spells_db and spells_db.segue_messages then
      all = spells_db.segue_messages
    end
  end

  local result = DRC.bput("segue " .. abbrev .. " " .. tostring(mana), table.unpack(all))

  for _, p in ipairs(M.SEGUE_FAILURE) do
    if result:find(p, 1, true) then return false end
  end
  return true
end

--- Generic ritual dispatch.
-- Mirrors Lich5 DRCA.ritual(data, settings).
-- @param data table Ritual spell data
-- @param settings table Character settings
function M.ritual(data, settings)
  if not data or not settings then return end

  if not data.skip_retreat then
    DRC.retreat(settings.ignored_npcs)
  end
  if DRC.release_invisibility then DRC.release_invisibility() end
  if not data.skip_retreat and DRC.set_stance then
    DRC.set_stance("shield")
  end

  local command = "prepare"
  if data.prep then command = data.prep end
  if data.prep_type then command = data.prep_type end

  local prep_result = M.prepare_spell(data.abbrev, data.mana, data.symbiosis, command,
    data.tattoo_tm, data.runestone_name, data.runestone_tm,
    settings.custom_spell_prep)
  if not prep_result then return end

  local prepare_time = os.time()

  M.find_focus(data.focus, data.worn_focus, data.tied_focus, data.sheathed_focus)
  M.invoke_full(data.focus, nil, nil)
  M.stow_focus(data.focus, data.worn_focus, data.tied_focus, data.sheathed_focus)

  if not data.skip_retreat then
    DRC.retreat(settings.ignored_npcs)
  end

  if data.prep_time then
    while os.time() - prepare_time < data.prep_time do
      pause(1)
    end
  elseif waitcastrt then
    waitcastrt()
  end

  local cast_ok = M.cast_spell_check(data.cast, data.symbiosis, data.before, data.after)
  if not cast_ok then return end

  if not data.skip_retreat then
    DRC.retreat(settings.ignored_npcs)
  end
end

-------------------------------------------------------------------------------
-- Paladin runestone methods
-------------------------------------------------------------------------------

--- Prepare to cast from a runestone (check storage, get it).
-- Mirrors Lich5 DRCA.prepare_to_cast_runestone?(spell, settings).
-- @param spell table Spell data with runestone_name
-- @param settings table Character settings with runestone_storage
-- @return boolean true if runestone is ready
function M.prepare_to_cast_runestone(spell, settings)
  if not spell or not spell.runestone_name then return false end
  if not settings or not settings.runestone_storage then return false end

  if DRCI and DRCI.inside and DRCI.inside(spell.runestone_name, settings.runestone_storage) then
    return M.get_runestone(spell.runestone_name, settings)
  else
    DRC.message("DRCA: out of " .. spell.runestone_name .. "!")
    return false
  end
end

--- Get a runestone from storage.
-- Mirrors Lich5 DRCA.get_runestone?(runestone, settings).
-- @param runestone string Runestone item name
-- @param settings table Character settings with runestone_storage
-- @return boolean true if runestone obtained
function M.get_runestone(runestone, settings)
  if not runestone or not settings then return false end
  if DRCI and DRCI.in_hands and DRCI.in_hands(runestone) then return true end

  local all = {}
  for _, p in ipairs(M.USELESS_RUNESTONE) do all[#all + 1] = p end
  for _, p in ipairs(M.GET_RUNESTONE_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.GET_RUNESTONE_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput("get my " .. runestone .. " from my " .. settings.runestone_storage, table.unpack(all))

  for _, p in ipairs(M.USELESS_RUNESTONE) do
    if result:find(p, 1, true) then
      if DRCI and DRCI.dispose_trash then DRCI.dispose_trash(runestone) end
      DRC.message("DRCA: got a useless " .. runestone .. " — disposing")
      return false
    end
  end
  for _, p in ipairs(M.GET_RUNESTONE_FAILURE) do
    if result:find(p, 1, true) then
      DRC.message("DRCA: could not find " .. runestone .. " in " .. settings.runestone_storage)
      return false
    end
  end

  return true
end

-------------------------------------------------------------------------------
-- Guild-specific methods
-------------------------------------------------------------------------------

--- Warrior Mage: infuse Osrel Meraud off-mana.
-- Mirrors Lich5 DRCA.infuse_om(harness, amount).
-- @param harness boolean Whether to harness mana before infusing
-- @param amount number Mana amount to infuse
function M.infuse_om(harness, amount)
  if not amount then return end
  -- Check if Osrel Meraud is active and under 90 minutes
  if DRSpells and DRSpells.active_spells then
    local spells = DRSpells.active_spells
    if type(spells) == "function" then spells = spells() end
    if type(spells) == "table" then
      local om = spells["Osrel Meraud"]
      if not om or (tonumber(om) and tonumber(om) >= 90) then return end
    else
      return
    end
  else
    return
  end

  local all_patterns = {}
  for _, p in ipairs(M.INFUSE_OM_SUCCESS) do all_patterns[#all_patterns + 1] = p end
  for _, p in ipairs(M.INFUSE_OM_FAILURE) do all_patterns[#all_patterns + 1] = p end

  for retry = 1, M.INFUSE_OM_MAX_RETRIES do
    -- Wait for mana
    while DRStats and DRStats.mana and DRStats.mana <= 40 do
      pause(5)
    end

    if harness then M.harness_mana_list({ amount }) end

    local result = DRC.bput("infuse om " .. tostring(amount), table.unpack(all_patterns))

    -- Check if success
    for _, p in ipairs(M.INFUSE_OM_SUCCESS) do
      if result:find(p, 1, true) then return end
    end

    pause(0.5)
    if waitrt then waitrt() end
  end

  DRC.message("DRCA: infuse_om exhausted " .. tostring(M.INFUSE_OM_MAX_RETRIES) .. " retries — giving up")
end

--- Warrior Mage: check elemental charge level (0-11).
-- Mirrors Lich5 DRCA.check_elemental_charge.
-- @return number Charge level 0-11
function M.check_elemental_charge()
  if DRStats and DRStats.warrior_mage then
    local is_wm = DRStats.warrior_mage
    if type(is_wm) == "function" then is_wm = is_wm() end
    if not is_wm then return 0 end
  else
    return 0
  end

  local result = DRC.bput("pathway sense", table.unpack(M.CHARGE_LEVELS))
  for i, pattern in ipairs(M.CHARGE_LEVELS) do
    if result:find(pattern, 1, true) then
      return i - 1  -- 0-based index
    end
  end
  return 0
end

--- Trader: perceive aura (starlight level).
-- Mirrors Lich5 DRCA.perc_aura. (Lich5 checks trader?.)
-- @return table { level=0-9, capped=bool, growing=bool }
function M.perc_aura()
  if DRStats and DRStats.trader then
    local is_trader = DRStats.trader
    if type(is_trader) == "function" then is_trader = is_trader() end
    if not is_trader then return nil end
  else
    return nil
  end

  local aura = { level = 0, capped = false, growing = false }

  DRC.bput("perceive aura", "Roundtime")

  -- Check recent game lines for the starlight patterns
  if reget then
    local lines = reget(20)
    if lines then
      for _, line in ipairs(lines) do
        for i, msg in ipairs(M.STARLIGHT_MESSAGES) do
          if line:find(msg, 1, true) then
            aura.level = i - 1
          end
        end
        if line:find("as much starlight as you can safely handle", 1, true) then
          aura.capped = true
        end
        if line:find("Local conditions permit optimal growth", 1, true) then
          aura.growing = true
        end
        if line:find("Local conditions are hindering the growth", 1, true) then
          aura.growing = false
        end
      end
    end
  end

  return aura
end

--- Necromancer: perceive symbiotic research type.
-- Mirrors Lich5 DRCA.perc_symbiotic_research.
-- @return string|nil Research type or nil
function M.perc_symbiotic_research()
  local result = DRC.bput("perceive", "combine the weaves of the %w+ symbiosis", "Roundtime")
  local symtype = result:match("combine the weaves of the (%w+) symbiosis")
  return symtype
end

--- Necromancer: release magical/symbiotic research.
-- Mirrors Lich5 DRCA.release_magical_research.
function M.release_magical_research()
  DRC.bput("release symbiosis", "Are you sure", "You intentionally wipe", "But you haven't")
  DRC.bput("release symbiosis", "Are you sure", "You intentionally wipe", "But you haven't")
end

--- Trader: parse regalia items from inventory.
-- Mirrors Lich5 DRCA.parse_regalia.
-- @return table Array of regalia item nouns
function M.parse_regalia()
  if DRStats and DRStats.trader then
    local is_trader = DRStats.trader
    if type(is_trader) == "function" then is_trader = is_trader() end
    if not is_trader then return {} end
  else
    return {}
  end

  local regalia = {}
  DRC.bput("inv combat", "All of your worn combat", "You aren't wearing anything like that")
  if reget then
    local lines = reget(30)
    if lines then
      for _, line in ipairs(lines) do
        if line:find("rough%-cut crystal", 1, false)
          or line:find("faceted crystal", 1, false)
          or line:find("resplendent crystal", 1, false) then
          local noun = DRC.get_noun and DRC.get_noun(line)
          if noun then regalia[#regalia + 1] = noun end
        end
      end
    end
  end

  return regalia
end

--- Trader: shatter regalia.
-- Mirrors Lich5 DRCA.shatter_regalia?(worn_regalia).
-- @param worn_regalia table|nil Array of regalia nouns (auto-detects if nil)
-- @return boolean true if any regalia shattered
function M.shatter_regalia(worn_regalia)
  if DRStats and DRStats.trader then
    local is_trader = DRStats.trader
    if type(is_trader) == "function" then is_trader = is_trader() end
    if not is_trader then return false end
  else
    return false
  end

  worn_regalia = worn_regalia or M.parse_regalia()
  if not worn_regalia or #worn_regalia == 0 then return false end

  for _, item in ipairs(worn_regalia) do
    DRC.bput("remove my " .. item, "into motes of silvery", "Remove what", "You .* " .. item)
  end
  return true
end

--- Parse a mana level from a perceive message string.
-- Mirrors Lich5 DRCA.parse_mana_message(mana_msg).
-- @param mana_msg string Perceive output line
-- @return number Mana level (1-10)
function M.parse_mana_message(mana_msg)
  if not mana_msg then return 1 end

  local manalevels
  if mana_msg:find("weak") then
    manalevels = M.MANA_MAP.weak
  elseif mana_msg:find("developing") then
    manalevels = M.MANA_MAP.developing
  elseif mana_msg:find("improving") then
    manalevels = M.MANA_MAP.improving
  else
    manalevels = M.MANA_MAP.good
  end

  -- Last word of the message is the adjective
  local adj = mana_msg:match("(%S+)%s*$") or ""

  for i, level_adj in ipairs(manalevels) do
    if level_adj == adj then return i end
  end
  return 1
end

-------------------------------------------------------------------------------
-- Avtalia methods (Barbarian/Thief spirit cambrinth)
-- Mirrors Lich5 DRCA.update_avtalia / invoke_avtalia / charge_avtalia / choose_avtalia
-------------------------------------------------------------------------------

--- Update avtalia cambrinth focus data.
-- Mirrors Lich5 DRCA.update_avtalia.
function M.update_avtalia()
  DRC.bput("focus cambrinth",
    "The .+ pulses? .+ %d+", "dim, almost magically null",
    "You let your magical senses wander")
  if waitrt then waitrt() end
end

--- Invoke avtalia cambrinth (only if avtalia data available).
-- Mirrors Lich5 DRCA.invoke_avtalia(cambrinth, dedicated_camb_use, invoke_amount).
-- @param cambrinth string Cambrinth item name
-- @param dedicated_camb_use string|nil Dedicated cambrinth use string
-- @param invoke_amount number|nil Amount to invoke
function M.invoke_avtalia(cambrinth, dedicated_camb_use, invoke_amount)
  if not cambrinth then return end
  if not (UserVars and UserVars.avtalia and UserVars.avtalia[cambrinth]) then return end

  M.invoke_full(cambrinth, dedicated_camb_use, invoke_amount)

  -- Update tracking
  local current_mana = (DRStats and DRStats.mana) or 0
  local deducted = math.min(current_mana, invoke_amount or 0)
  UserVars.avtalia[cambrinth].mana = (UserVars.avtalia[cambrinth].mana or 0) - deducted
end

--- Charge avtalia cambrinth with decay tracking.
-- Mirrors Lich5 DRCA.charge_avtalia(cambrinth, charge_amount).
-- @param cambrinth string Cambrinth item name
-- @param charge_amount number Amount to charge
function M.charge_avtalia(cambrinth, charge_amount)
  if not cambrinth then return end
  if not (UserVars and UserVars.avtalia and UserVars.avtalia[cambrinth]) then return end

  local data = UserVars.avtalia[cambrinth]
  if not M.charge_check(cambrinth, charge_amount) then
    data.mana = data.cap or 0
  else
    -- Rough 10% decay per 5 minutes
    local time_seen = data.time_seen or os.time()
    local time_diff = os.time() - time_seen
    local time_mod = math.floor(time_diff / 300.0)
    local time_adjust = 1 - math.min(time_mod * 0.10, 1.0)
    local assumed_reserve = math.floor((data.mana or 0) * time_adjust) + charge_amount
    data.mana = math.min(assumed_reserve, data.cap or 0)
  end
  data.time_seen = os.time()
end

--- Choose best avtalia cambrinth for a given charge need.
-- Mirrors Lich5 DRCA.choose_avtalia(charge_needed, mana_percentage).
-- @param charge_needed number Minimum charge needed
-- @param mana_percentage number Minimum mana percentage (0-100)
-- @return string|nil,table|nil Cambrinth name and data, or nil
function M.choose_avtalia(charge_needed, mana_percentage)
  if not (UserVars and UserVars.avtalia) then return nil, nil end

  local best_name, best_data = nil, nil
  local best_mana = -1

  for camb, data in pairs(UserVars.avtalia) do
    if data.time_seen and data.cap and data.mana then
      local age = os.time() - data.time_seen
      if age < 600
        and (data.mana / data.cap) * 100 >= mana_percentage
        and data.mana > charge_needed / 10 then
        if data.mana > best_mana then
          best_mana = data.mana
          best_name = camb
          best_data = data
        end
      end
    end
  end

  return best_name, best_data
end

--- Spell preparing check (is a spell currently being prepared?).
-- Mirrors Lich5 DRCA.spell_preparing?.
-- @return boolean
function M.spell_preparing()
  if XMLData and XMLData.prepared_spell then
    local name = XMLData.prepared_spell
    return name ~= "" and name ~= "None"
  end
  -- Fallback: check via checkprep if available
  if checkprep then
    local p = checkprep()
    return p and p ~= "None" and p ~= ""
  end
  return false
end

--- Spell prepared check (prepared and no more cast RT).
-- Mirrors Lich5 DRCA.spell_prepared?.
-- @return boolean
function M.spell_prepared()
  if not M.spell_preparing() then return false end
  if checkcastrt then
    return checkcastrt() <= 0
  end
  return true
end

return M
