--- DRCMM — DR Common Moon Mage utilities.
-- Ported from Lich5 common-moonmage.rb (module DRCMM).
-- Provides moon tracking, prediction, astrology, telescope, and divination.
-- @module lib.dr.common_moonmage
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Moon weapon detection (color prefix + moonblade/moonstaff).
M.MOON_WEAPON_NAMES = { "moonblade", "moonstaff" }

--- Color to moon name mapping for summoned moon weapons.
M.MOON_COLOR_TO_NAME = {
  black       = "katamba",
  ["red-hot"] = "yavash",
  ["blue-white"] = "xibar",
}

--- Divination tool verb mapping.
M.DIV_TOOL_VERBS = {
  charts = "review",
  bones  = "roll",
  mirror = "gaze",
  bowl   = "gaze",
  prism  = "raise",
}

--- Minimum minutes remaining before a celestial body sets to count as "visible."
M.MOON_VISIBILITY_TIMER_THRESHOLD = 4

--- Center telescope response patterns.
M.CENTER_TELESCOPE_MESSAGES = {
  "Center what",
  "You put your eye",
  "open it to make any use of it",
  "The pain is too much",
  "That's a bit tough to do when you can't see the sky",
  "You would probably need a periscope",
  "Your search for",
  "Your vision is too fuzzy",
  "You'll need to open it",
  "You must have both hands free",
}

--- Observe heavens response patterns.
M.OBSERVE_MESSAGES = {
  "Your search for",
  "You see nothing regarding the future",
  "Clouds obscure",
  "The following heavenly bodies are visible:",
  "That's a bit hard to do while inside",
  "too close to the sun",
  "too faint for you to pick out",
  "You learn nothing of the future",
  "below the horizon",
  "You have not pondered",
  "You are unable to make use",
  "While the sighting",
  "You learned something useful",
}

--- Moon wear messages (when trying to wear a moon weapon).
M.MOON_WEAR_MESSAGES = {
  "You're already", "You can't wear", "Wear what", "telekinetic",
}

--- Moon drop messages.
M.MOON_DROP_MESSAGES = {
  "As you open your hand", "What were you referring to",
}

-------------------------------------------------------------------------------
-- Moon weapon helpers
-------------------------------------------------------------------------------

--- Check if a string looks like a moon weapon.
-- @param item string|nil Item name
-- @return boolean
function M.is_moon_weapon(item)
  if not item then return false end
  item = item:lower()
  if Regex.test("^(black|red-hot|blue-white) moon", item) then
    return true
  end
  return false
end

--- Check if holding a moon weapon in either hand.
-- @return boolean
function M.holding_moon_weapon()
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  local lh = DRC and DRC.left_hand and DRC.left_hand()
  return M.is_moon_weapon(rh) or M.is_moon_weapon(lh)
end

--- Try to hold a worn moon weapon.
-- @return boolean true if now holding a moon weapon
function M.hold_moon_weapon()
  if M.holding_moon_weapon() then return true end

  for _, weapon in ipairs(M.MOON_WEAPON_NAMES) do
    local result = DRC.bput("glance my " .. weapon,
      "You glance at a", "I could not find")
    if result:find("You glance") then
      local hold_result = DRC.bput("hold my " .. weapon,
        "You grab", "You aren't wearing", "Hold hands with whom", "You need a free hand")
      return hold_result:find("You grab") ~= nil
    end
  end
  return false
end

--- Wear a held moon weapon (telekinetic suspension).
-- @return boolean true if weapon is now worn
function M.wear_moon_weapon()
  local wore_it = false
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  local lh = DRC and DRC.left_hand and DRC.left_hand()

  if M.is_moon_weapon(lh) then
    local result = DRC.bput("wear " .. lh, unpack(M.MOON_WEAR_MESSAGES))
    if result == "telekinetic" then wore_it = true end
  end
  if M.is_moon_weapon(rh) then
    local result = DRC.bput("wear " .. rh, unpack(M.MOON_WEAR_MESSAGES))
    if result == "telekinetic" then wore_it = true end
  end
  return wore_it
end

--- Drop a held moon weapon.
-- @return boolean true if dropped
function M.drop_moon_weapon()
  local dropped = false
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  local lh = DRC and DRC.left_hand and DRC.left_hand()

  if M.is_moon_weapon(lh) then
    local result = DRC.bput("drop " .. lh, unpack(M.MOON_DROP_MESSAGES))
    if result:find("As you open your hand") then dropped = true end
  end
  if M.is_moon_weapon(rh) then
    local result = DRC.bput("drop " .. rh, unpack(M.MOON_DROP_MESSAGES))
    if result:find("As you open your hand") then dropped = true end
  end
  return dropped
end

--- Determine which moon was used to summon the held weapon.
-- @return string|nil Moon name ("katamba", "yavash", "xibar") or nil
function M.moon_used_to_summon_weapon()
  for _, weapon in ipairs(M.MOON_WEAPON_NAMES) do
    local result = DRC.bput("glance my " .. weapon,
      "You glance at a", "I could not find")
    if result:find("You glance") then
      for color, moon in pairs(M.MOON_COLOR_TO_NAME) do
        if result:find(color) then return moon end
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Celestial observation
-------------------------------------------------------------------------------

--- Observe a celestial body or the heavens.
-- @param thing string What to observe (e.g., "heavens", "katamba", planet name)
-- @return string Result text
function M.observe(thing)
  local cmd
  if thing == "heavens" then
    cmd = "observe heavens"
  else
    cmd = "observe " .. thing .. " in heavens"
  end
  return DRC.bput(cmd, unpack(M.OBSERVE_MESSAGES))
end

--- Make a prediction.
-- @param thing string What to predict (e.g., "weather", "all")
-- @return string Result text
function M.predict(thing)
  local cmd
  if thing == "all" then
    cmd = "predict state all"
  else
    cmd = "predict " .. thing
  end
  return DRC.bput(cmd,
    "You predict that", "You are far too",
    "you lack the skill", "Roundtime", "You focus inwardly")
end

--- Study the sky for astrology.
-- @return string Result text
function M.study_sky()
  return DRC.bput("study sky",
    "You feel a lingering sense", "You feel it is too soon",
    "Roundtime", "You are unable to sense additional",
    "detect any portents")
end

--- Align to a skill for astrology.
-- @param skill string Skill name
function M.align(skill)
  DRC.bput("align " .. skill, "You focus internally")
end

-------------------------------------------------------------------------------
-- Telescope management
-------------------------------------------------------------------------------

--- Get a telescope from storage.
-- @param telescope_name string|nil Telescope item name (default "telescope")
-- @param storage table Storage config { tied, container }
-- @return boolean true on success
function M.get_telescope(telescope_name, storage)
  telescope_name = telescope_name or "telescope"
  if DRCI and DRCI.in_hands and DRCI.in_hands(telescope_name) then return true end

  if storage and storage.tied then
    return DRCI and DRCI.untie_item and DRCI.untie_item(telescope_name, storage.tied) or false
  elseif storage and storage.container then
    return DRCI and DRCI.get_item and DRCI.get_item(telescope_name, storage.container) or false
  else
    return DRCI and DRCI.get_item and DRCI.get_item(telescope_name) or false
  end
end

--- Store a telescope.
-- @param telescope_name string|nil
-- @param storage table Storage config
-- @return boolean
function M.store_telescope(telescope_name, storage)
  telescope_name = telescope_name or "telescope"
  if DRCI and DRCI.in_hands and not DRCI.in_hands(telescope_name) then return true end

  if storage and storage.tied then
    return DRCI and DRCI.tie_item and DRCI.tie_item(telescope_name, storage.tied) or false
  elseif storage and storage.container then
    return DRCI and DRCI.put_away_item and DRCI.put_away_item(telescope_name, storage.container) or false
  else
    return DRCI and DRCI.put_away_item and DRCI.put_away_item(telescope_name) or false
  end
end

--- Center a telescope on a target.
-- Returns the matched response line so callers can handle errors (no telescope,
-- closed telescope, injuries, etc.).  Lich5 DRCMM.center_telescope also returns
-- the raw result; callers are responsible for branching on it.
-- @param target string Target to center on
-- @return string Matched response line
function M.center_telescope(target)
  return DRC.bput("center telescope on " .. target, unpack(M.CENTER_TELESCOPE_MESSAGES))
end

--- Peer through a telescope.
-- Returns the matched response line so callers can detect injuries or closed telescope.
-- @return string Matched response line
function M.peer_telescope()
  local result = DRC.bput("peer my telescope",
    "The pain is too much", "You see nothing regarding the future",
    "You believe you've learned all", "open it",
    "Your vision is too fuzzy", "Roundtime")
  if waitrt then waitrt() end
  return result
end

-------------------------------------------------------------------------------
-- Divination tools
-------------------------------------------------------------------------------

--- Get a divination tool from storage.
-- @param tool table Tool config { name, tied, worn, container }
-- @return boolean
function M.get_div_tool(tool)
  if not tool then return false end
  if tool.tied then
    return DRCI and DRCI.untie_item and DRCI.untie_item(tool.name, tool.container) or false
  elseif tool.worn then
    return DRCI and DRCI.remove_item and DRCI.remove_item(tool.name) or false
  else
    return DRCI and DRCI.get_item and DRCI.get_item(tool.name, tool.container) or false
  end
end

--- Store a divination tool.
-- @param tool table Tool config
-- @return boolean
function M.store_div_tool(tool)
  if not tool then return false end
  if tool.tied then
    return DRCI and DRCI.tie_item and DRCI.tie_item(tool.name, tool.container) or false
  elseif tool.worn then
    return DRCI and DRCI.wear_item and DRCI.wear_item(tool.name) or false
  else
    return DRCI and DRCI.put_away_item and DRCI.put_away_item(tool.name, tool.container) or false
  end
end

--- Use a divination tool (bones, charts, mirror, etc.).
-- @param tool_storage table Tool config
function M.use_div_tool(tool_storage)
  if not M.get_div_tool(tool_storage) then
    respond("[DRCMM] Failed to get divination tool: " .. tostring(tool_storage and tool_storage.name))
    return
  end

  for tool_keyword, verb in pairs(M.DIV_TOOL_VERBS) do
    if tool_storage.name and tool_storage.name:find(tool_keyword) then
      DRC.bput(verb .. " my " .. tool_keyword, "roundtime", "Roundtime")
      if waitrt then waitrt() end
    end
  end

  if not M.store_div_tool(tool_storage) then
    respond("[DRCMM] Failed to store divination tool.")
  end
end

--- Get prediction bones from storage.
-- @param storage table { tied, container }
-- @return boolean
function M.get_bones(storage)
  if storage and storage.tied then
    return DRCI and DRCI.untie_item and DRCI.untie_item("bones", storage.tied) or false
  elseif storage and storage.container then
    return DRCI and DRCI.get_item and DRCI.get_item("bones", storage.container) or false
  else
    return DRCI and DRCI.get_item and DRCI.get_item("bones") or false
  end
end

--- Store prediction bones.
-- @param storage table
-- @return boolean
function M.store_bones(storage)
  if storage and storage.tied then
    return DRCI and DRCI.tie_item and DRCI.tie_item("bones", storage.tied) or false
  elseif storage and storage.container then
    return DRCI and DRCI.put_away_item and DRCI.put_away_item("bones", storage.container) or false
  else
    return DRCI and DRCI.put_away_item and DRCI.put_away_item("bones") or false
  end
end

--- Roll prediction bones.
-- @param storage table Bone storage config
function M.roll_bones(storage)
  if not M.get_bones(storage) then
    respond("[DRCMM] Failed to get bones.")
    return
  end
  DRC.bput("roll my bones", "roundtime", "Roundtime")
  if waitrt then waitrt() end
  if not M.store_bones(storage) then
    respond("[DRCMM] Failed to store bones.")
  end
end

-------------------------------------------------------------------------------
-- Moon visibility
-------------------------------------------------------------------------------

--- Get list of currently visible moons.
-- Uses UserVars.moons data from moonwatch script (populated by check_moonwatch).
-- A moon is "visible" if it appears in UserVars.moons.visible and its timer
-- is above the MOON_VISIBILITY_TIMER_THRESHOLD (~4 min before setting).
-- @return table Array of moon name strings
function M.visible_moons()
  M.check_moonwatch()
  local moons = {}
  if not UserVars or not UserVars.moons then return moons end

  local visible = UserVars.moons.visible or {}
  for moon_name, moon_data in pairs(UserVars.moons) do
    if moon_name ~= "visible" and type(moon_data) == "table" then
      -- Check moon is in visible list and has enough time remaining
      local is_visible = false
      if type(visible) == "table" then
        for _, v in ipairs(visible) do
          if v == moon_name then is_visible = true; break end
        end
      end
      if is_visible and moon_data.timer and moon_data.timer >= M.MOON_VISIBILITY_TIMER_THRESHOLD then
        moons[#moons + 1] = moon_name
      end
    end
  end
  return moons
end

--- Check if any moons are visible.
-- @return boolean
function M.moons_visible()
  return #M.visible_moons() > 0
end

--- Check if a specific moon is visible.
-- @param moon_name string
-- @return boolean
function M.moon_visible(moon_name)
  for _, m in ipairs(M.visible_moons()) do
    if m == moon_name then return true end
  end
  return false
end

--- Check if a bright celestial object is visible (sun, xibar, yavash).
-- Returns true if the sun is up or a bright moon (xibar/yavash) is visible
-- and won't set for at least MOON_VISIBILITY_TIMER_THRESHOLD minutes.
-- @return boolean
function M.bright_celestial_object()
  M.check_moonwatch()
  if UserVars and UserVars.sun and UserVars.sun.day
      and UserVars.sun.timer and UserVars.sun.timer >= M.MOON_VISIBILITY_TIMER_THRESHOLD then
    return true
  end
  return M.moon_visible("xibar") or M.moon_visible("yavash")
end

--- Check if any celestial object is visible (sun or any moon).
-- @return boolean
function M.any_celestial_object()
  M.check_moonwatch()
  if UserVars and UserVars.sun and UserVars.sun.day
      and UserVars.sun.timer and UserVars.sun.timer >= M.MOON_VISIBILITY_TIMER_THRESHOLD then
    return true
  end
  return M.moons_visible()
end

--- Parse telescope planet observation output to determine planet visibility.
-- Called by update_astral_data for planet-targeted spells. Searches constellation
-- data for planets matching the requested stats, then uses the telescope to
-- check which planets are currently visible.
-- @param data table Spell data with 'stats' key (list of stat names)
-- @param settings table|nil Character settings (telescope_name, telescope_storage)
-- @return table|nil Updated spell data with 'cast' field, or nil on failure
function M.set_planet_data(data, settings)
  if not data or not data.stats then return data end

  local constellations = get_data and get_data("constellations")
  if not constellations or not constellations.constellations then
    respond("[DRCMM] Could not load constellation data for planet targeting.")
    return nil
  end

  -- Find planets (constellations with stats)
  local planets = {}
  for _, planet in ipairs(constellations.constellations) do
    if planet.stats then
      planets[#planets + 1] = planet
    end
  end

  -- Get names for telescope observation
  local planet_names = {}
  for _, planet in ipairs(planets) do
    planet_names[#planet_names + 1] = planet.name
  end

  -- Find which planets are actually visible via telescope
  local visible_planets = M.find_visible_planets(planet_names, settings)
  if not visible_planets then return nil end

  -- Match requested stats to a visible planet
  for _, stat in ipairs(data.stats) do
    for _, planet in ipairs(planets) do
      -- Check if this planet provides the requested stat
      local provides_stat = false
      for _, planet_stat in ipairs(planet.stats) do
        if planet_stat == stat then provides_stat = true; break end
      end
      -- Check if planet is visible
      if provides_stat then
        for _, vp in ipairs(visible_planets) do
          if vp == planet.name then
            data.cast = "cast " .. planet.name
            return data
          end
        end
      end
    end
  end

  respond("[DRCMM] Could not set planet data. Cannot cast " .. tostring(data.abbrev or data.name) .. ".")
  return nil
end

--- Find which planets are currently visible using a telescope.
-- Gets the telescope, centers on each planet, tracks which ones are found,
-- then stores the telescope again.
-- @param planet_names table Array of planet name strings to check
-- @param settings table Character settings (telescope_name, telescope_storage)
-- @return table|nil Array of visible planet name strings, or nil on failure
function M.find_visible_planets(planet_names, settings)
  if not settings then return {} end

  local telescope_name = settings.telescope_name or "telescope"
  local telescope_storage = settings.telescope_storage or {}

  if not M.get_telescope(telescope_name, telescope_storage) then
    respond("[DRCMM] Could not get telescope to find visible planets.")
    return nil
  end

  if Flags and Flags.add then
    Flags.add("planet-not-visible", "turns up fruitless")
  end

  local observed = {}
  local ok, err = pcall(function()
    for _, planet in ipairs(planet_names) do
      M.center_telescope(planet)
      if not (Flags and Flags["planet-not-visible"]) then
        observed[#observed + 1] = planet
      end
      if Flags and Flags.reset then
        Flags.reset("planet-not-visible")
      end
    end
  end)

  if Flags and Flags.delete then
    Flags.delete("planet-not-visible")
  end

  if not M.store_telescope(telescope_name, telescope_storage) then
    respond("[DRCMM] Could not store telescope after finding visible planets.")
  end

  if not ok then error(err) end
  return observed
end

--- Update astral data for a spell (set moon or planet target).
-- Dispatches to set_moon_data for moon spells or set_planet_data for planet spells.
-- @param data table Spell data with 'moon' or 'stats' key
-- @param settings table|nil Character settings
-- @return table Updated spell data (or nil if unavailable)
function M.update_astral_data(data, settings)
  if not data then return nil end

  if data.moon then
    return M.set_moon_data(data)
  elseif data.stats then
    return M.set_planet_data(data, settings)
  end

  return data
end

--- Set moon target for a moon-based spell.
-- @param data table Spell data with 'moon' key
-- @return table|nil Updated spell data or nil if no moon available
function M.set_moon_data(data)
  if not data or not data.moon then return data end

  local moons = M.visible_moons()
  if #moons > 0 then
    data.cast = "cast " .. moons[1]
  elseif data.name and data.name:lower() == "cage of light" then
    data.cast = "cast ambient"
  else
    respond("[DRCMM] No moon available to cast " .. tostring(data.name or data.abbrev))
    return nil
  end
  return data
end

--- Ensure the moonwatch script is running and UserVars.moons is populated.
-- Mirrors Lich5's DRCMM.check_moonwatch. Starts moonwatch if not running,
-- then polls until UserVars.moons is populated (up to 30 seconds).
-- moonwatch tracks sun/moon positions and writes UserVars.moons and UserVars.sun.
-- @return boolean true if moon data is available
function M.check_moonwatch()
  if Script and Script.running and not Script.running("moonwatch") then
    respond("[DRCMM] moonwatch is not running. Starting it now.")
    if UserVars then UserVars.moons = {} end
    if Script.run then
      Script.run("moonwatch")
    end
    respond("[DRCMM] Run autostart('moonwatch') to avoid this in the future.")
  end

  -- Poll until moon data is available (up to 30s)
  local timeout = os.time() + 30
  while os.time() < timeout do
    if UserVars and UserVars.moons and next(UserVars.moons) then
      return true
    end
    pause(1)
  end
  respond("[DRCMM] moonwatch timed out waiting for moon data.")
  return false
end

return M
