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
-- @return table Array of moon name strings
function M.visible_moons()
  -- TODO: integrate with moonwatch script / UserVars when available
  -- For now, use observe heavens to check
  local result = M.observe("heavens")
  local moons = {}
  if Regex.test("(?i)katamba", result) then moons[#moons + 1] = "katamba" end
  if Regex.test("(?i)yavash", result) then moons[#moons + 1] = "yavash" end
  if Regex.test("(?i)xibar", result) then moons[#moons + 1] = "xibar" end
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
-- @return boolean
function M.bright_celestial_object()
  -- TODO: integrate with moonwatch for sun tracking
  return M.moon_visible("xibar") or M.moon_visible("yavash")
end

--- Check if any celestial object is visible.
-- @return boolean
function M.any_celestial_object()
  return M.moons_visible()
end

--- Update astral data for a spell (set moon or planet target).
-- @param data table Spell data with 'moon' or 'stats' key
-- @param settings table|nil Character settings
-- @return table Updated spell data (or nil if unavailable)
function M.update_astral_data(data, settings)
  if not data then return nil end

  if data.moon then
    local moons = M.visible_moons()
    if #moons > 0 then
      data.cast = "cast " .. moons[1]
    elseif data.name and data.name:lower() == "cage of light" then
      data.cast = "cast ambient"
    else
      respond("[DRCMM] No moon available to cast " .. tostring(data.name or data.abbrev))
      return nil
    end
  end

  -- Planet-based spells would need telescope observation
  -- TODO: implement planet visibility checking via telescope

  return data
end

--- Ensure the moonwatch script is running so UserVars.sun is populated.
-- Mirrors Lich5's DRCMM.check_moonwatch.
-- moonwatch tracks sun/moon positions and writes UserVars.sun = JSON {day=bool, ...}
function M.check_moonwatch()
  if Script and not Script.running("moonwatch") then
    Script.run("moonwatch")
    pause(1)
  end
end

return M
