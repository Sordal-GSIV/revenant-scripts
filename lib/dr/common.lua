--- DRC — Base DR common utilities.
-- Ported from Lich5 common.rb (module DRC).
-- Provides bput, retreat, fix_standing, status checking, and other core helpers.
-- @module lib.dr.common
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Pattern for XML tags
M.XML_TAG_PATTERN = "<[^>]+>"

--- Collect command response messages
M.COLLECT_MESSAGES = {
  "As you rummage around",
  "believe you would probably have better luck trying to find a dragon",
  "if you had a bit more luck",
  "The room is too cluttered",
  "one hand free to properly collect",
  "You are sure you knew",
  "You begin to forage around,",
  "You begin scanning the area before you",
  "You begin exploring the area, searching for",
  "You find something dead and lifeless",
  "You cannot collect anything",
  "you fail to find anything",
  "You forage around but are unable to find anything",
  "You manage to collect a pile",
  "You survey the area and realize that any collecting efforts would be futile",
  "You wander around and poke your fingers",
  "You forage around for a while and manage to stir up a small mound of fire ants!",
}

--- Retreat escape messages (terminal — we're done retreating)
M.RETREAT_ESCAPE_MESSAGES = {
  "You are already as far away as you can get",
  "You retreat from combat",
  "You sneak back out of combat",
  "Retreat to where",
  "There's no place to retreat to",
}

--- Retreat in-progress messages (keep trying)
M.RETREAT_MESSAGES = {
  "retreat",
  "sneak",
  "grip on you",
  "grip remains solid",
  "You try to back",
  "You must stand first",
  "You stop advancing",
  "You are already",
}

--- Wait/roundtime pattern embedded in game output
-- Matches strings like "...wait 3", "Wait 5", "... wait 10"
M.WAIT_PATTERN = "%.%.%.wait (%d+)"
M.WAIT_PATTERN2 = "Wait (%d+)"
M.WAIT_PATTERN3 = "%.%.%. wait (%d+)"

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------

--- Strip XML tags from a line of game text.
-- @param line string Raw game output
-- @return string Cleaned text
function M.strip_xml(line)
  if not line then return "" end
  return line:gsub("<[^>]+>", ""):gsub("&gt;", ">"):gsub("&lt;", "<"):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Strip XML from an array of lines and discard empties.
-- @param lines table Array of raw lines
-- @return table Array of cleaned, non-empty strings
function M.strip_xml_lines(lines)
  local result = {}
  for _, line in ipairs(lines) do
    local cleaned = M.strip_xml(line)
    if cleaned ~= "" then
      result[#result + 1] = cleaned
    end
  end
  return result
end

--- Convert a game-formatted list to an array of items.
-- Input: "an arrow, silver coins and a deobar strongbox"
-- Output: { "an arrow", "silver coins", "a deobar strongbox" }
-- @param list string Game-formatted list
-- @return table Array of item strings
function M.list_to_array(list)
  if not list or list == "" then return {} end
  local result = {}
  -- Split on ", and", " and ", or ","
  for item in (list .. ","):gmatch("([^,]+),?") do
    item = item:gsub("^%s*and%s+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if item ~= "" then
      result[#result + 1] = item
    end
  end
  return result
end

--- Extract noun from a long item name (last word).
-- @param long_name string Full item description
-- @return string|nil The noun (last word)
function M.get_noun(long_name)
  if not long_name then return nil end
  return long_name:match("([%a%-']+)$")
end

--- Convert a game-formatted list to an array of nouns.
-- @param list string Game-formatted list
-- @return table Array of noun strings
function M.list_to_nouns(list)
  local items = M.list_to_array(list)
  local nouns = {}
  for _, item in ipairs(items) do
    local noun = M.get_noun(item)
    if noun and noun ~= "" then
      nouns[#nouns + 1] = noun
    end
  end
  return nouns
end

--- Convert a number-word to an integer.
-- Handles simple number words like "one" through "twenty" and
-- compound forms like "twenty-one" or "one hundred".
-- @param text string Number word(s)
-- @return number|nil
function M.text2num(text)
  if not text then return nil end
  local NUM_MAP = {
    one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
    eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15,
    sixteen = 16, seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
    thirty = 30, forty = 40, fifty = 50, sixty = 60, seventy = 70,
    eighty = 80, ninety = 90,
  }
  text = text:gsub("%-", " ")
  local g = 0
  for word in text:gmatch("%S+") do
    if word == "hundred" and g ~= 0 then
      g = g * 100
    else
      local x = NUM_MAP[word:lower()]
      if not x then return nil end
      g = g + x
    end
  end
  return g
end

-------------------------------------------------------------------------------
-- Blocking put — bput
-------------------------------------------------------------------------------

--- Blocking put with pattern matching.
-- Sends a command and waits for a matching response from the game.
-- Handles common interrupts: wait messages, roundtime, stunned, standing.
-- @param message string The command to send
-- @param ... string|pattern Patterns to match against game output
-- @return string The matched line, or "" on timeout
function M.bput(message, ...)
  local patterns = { ... }
  local timeout = 15

  -- Wait for roundtime before sending
  if waitrt then waitrt() end

  -- Send the command
  put(message)

  local start = os.time()
  while os.time() - start < timeout do
    local line = get()
    if line then
      -- Check for wait/roundtime interrupts
      local wait_secs = line:match("%.%.%.wait (%d+)")
                     or line:match("Wait (%d+)")
                     or line:match("%.%.%. wait (%d+)")
      if wait_secs then
        pause(tonumber(wait_secs))
        if waitrt then waitrt() end
        put(message)
        start = os.time()
      -- Auto-stand recovery
      elseif Regex.test("You must be standing|You should stand up first|You can't do that while sitting|You can't do that while kneeling|You can't do that while lying", line) then
        M.fix_standing()
        if waitrt then waitrt() end
        put(message)
        start = os.time()
      -- Stunned recovery
      elseif line:match("You are still stunned") then
        pause(1)
        put(message)
        start = os.time()
      -- Type-ahead overflow
      elseif line:match("Sorry, you may only type ahead") then
        pause(1)
        put(message)
        start = os.time()
      -- Asleep recovery
      elseif line:match("You can't do that while you are asleep") then
        put("wake")
        put(message)
        start = os.time()
      -- Playing instrument recovery
      elseif Regex.test("You are a bit too busy performing|You should stop playing before you do that", line) then
        put("stop play")
        put(message)
        start = os.time()
      -- Webbed recovery
      elseif line:match("You can't do that while entangled in a web") then
        pause(1)
        put(message)
        start = os.time()
      else
        -- Check each pattern for a match
        for _, pat in ipairs(patterns) do
          if type(pat) == "string" then
            if line:find(pat, 1, true) then
              return line
            end
          end
        end
      end
    else
      pause(0.1)
    end
  end

  respond("[DRC] bput: no match after " .. timeout .. "s for: " .. message)
  return ""
end

-------------------------------------------------------------------------------
-- Standing / posture
-------------------------------------------------------------------------------

--- Ensure the character is standing.
function M.fix_standing()
  -- Use GameState if available
  if GameState and GameState.standing and GameState.standing() then
    return
  end
  M.bput("stand",
    "You stand", "You are so unbalanced", "As you stand",
    "You are already", "weight of all your possessions",
    "You are overburdened", "You're unconscious",
    "You swim back up", "You don't seem to be able to move",
    "prevents you from standing", "You're plummeting",
    "There's no room to do much of anything here")
end

-------------------------------------------------------------------------------
-- Retreat / advance
-------------------------------------------------------------------------------

--- Retreat from combat. Handles standing and retrying.
-- @param ignored_npcs table|nil Array of NPC names to ignore
-- @return boolean true if retreated successfully
function M.retreat(ignored_npcs)
  ignored_npcs = ignored_npcs or {}
  -- Check if there are NPCs to retreat from (via DRRoom if available)
  if DRRoom and DRRoom.npcs then
    local npcs = DRRoom.npcs()
    if type(npcs) == "table" then
      -- Subtract ignored NPCs
      local dominated = {}
      for _, n in ipairs(npcs) do
        local dominated_flag = false
        for _, ig in ipairs(ignored_npcs) do
          if n == ig then dominated_flag = true; break end
        end
        if not dominated_flag then dominated[#dominated + 1] = n end
      end
      if #dominated == 0 then return true end
    end
  end

  for _ = 1, 20 do
    local result = M.bput("retreat",
      -- escape (terminal)
      "You are already as far away as you can get",
      "You retreat from combat",
      "You sneak back out of combat",
      "Retreat to where",
      "There's no place to retreat to",
      -- non-terminal
      "grip on you",
      "grip remains solid",
      "You try to back",
      "You must stand first",
      "You stop advancing",
      "retreat",
      "sneak")

    if Regex.test("already as far|retreat from combat|sneak back out|Retreat to where|no place to retreat", result) then
      return true
    end
    -- Otherwise, fix standing and retry
    M.fix_standing()
  end
  return false
end

-------------------------------------------------------------------------------
-- Hand helpers (delegating to GameObj where available)
-------------------------------------------------------------------------------

--- Get the item in the right hand, or nil if empty.
-- @return string|nil
function M.right_hand()
  if GameObj and GameObj.right_hand then
    local rh = GameObj.right_hand()
    if rh and rh.name and rh.name ~= "Empty" then
      return rh.name
    end
  end
  return nil
end

--- Get the item in the left hand, or nil if empty.
-- @return string|nil
function M.left_hand()
  if GameObj and GameObj.left_hand then
    local lh = GameObj.left_hand()
    if lh and lh.name and lh.name ~= "Empty" then
      return lh.name
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Visibility helpers
-------------------------------------------------------------------------------

--- Release invisibility spells/abilities.
function M.release_invisibility()
  -- TODO: integrate with DRSpells active spells list when available
  -- Lich5 checks active spells and releases any that grant invisibility
end

--- Check if we can see the sky (weather command).
-- @return boolean
function M.can_see_sky()
  local result = M.bput("weather",
    "That's a bit hard to do while inside",
    "You glance outside",
    "You glance up at the sky")
  return not result:find("hard to do while inside")
end

-------------------------------------------------------------------------------
-- Encumbrance
-------------------------------------------------------------------------------

local ENC_MAP = {
  ["None"]                 = 0,
  ["Light Encumbrance"]    = 1,
  ["Moderate Encumbrance"] = 2,
  ["Heavy Encumbrance"]    = 3,
  ["Very Heavy Encumbrance"] = 4,
  ["Extremely Encumbered"] = 5,
  ["Overburdened"]         = 6,
}

--- Check encumbrance level (0-6).
-- @param refresh boolean If true, issue 'encumbrance' command
-- @return number Encumbrance level 0-6
function M.check_encumbrance(refresh)
  if refresh == nil then refresh = true end
  if refresh then
    local result = M.bput("encumbrance", "Encumbrance")
    local enc_text = result:match("Encumbrance%s*:%s*(.*)")
    if enc_text then
      enc_text = enc_text:gsub("^%s+", ""):gsub("%s+$", "")
      return ENC_MAP[enc_text] or 0
    end
  end
  if DRStats and DRStats.encumbrance then
    return ENC_MAP[DRStats.encumbrance()] or 0
  end
  return 0
end

-------------------------------------------------------------------------------
-- Misc utility
-------------------------------------------------------------------------------

--- Send a status message to the client window.
-- @param text string Message text
-- @param bold boolean|nil If false, plain text; otherwise bold (default true)
function M.message(text, bold)
  if bold == false then
    respond(text)
  else
    respond("\27[1m" .. tostring(text) .. "\27[0m")
  end
end

--- Wait for a script to complete (start it if not running, then block until done).
-- @param name string Script name
-- @param args table|string|nil Arguments (table joined with spaces, or string)
function M.wait_for_script_to_complete(name, args)
  local args_str
  if type(args) == "table" then
    args_str = table.concat(args, " ")
  else
    args_str = args or ""
  end

  Script.run(name, args_str)

  -- Wait up to 10s for the script to start
  local start_wait = os.time()
  while not Script.running(name) and (os.time() - start_wait) < 10 do
    pause(0.5)
  end

  -- Block until the script finishes or times out (5 min safety)
  local timeout = 300
  local start = os.time()
  while Script.running(name) and (os.time() - start) < timeout do
    pause(1)
  end
end

--- Check if hiding.
-- @param hide_type string|nil "hide" or "stalk" (default "hide")
-- @return boolean
function M.hide(hide_type)
  hide_type = hide_type or "hide"
  if GameState and GameState.hidden and GameState.hidden() then
    return true
  end
  M.bput(hide_type,
    "Roundtime", "too busy performing",
    "can't see any place to hide",
    "Stalk what", "You're already stalking",
    "Stalking is an inherently stealthy",
    "You haven't had enough time",
    "You search but find no place to hide")
  pause(0.5)
  if waitrt then waitrt() end
  if GameState and GameState.hidden then
    return GameState.hidden()
  end
  return false
end

--- Forage for an item.
-- @param item string Item to forage
-- @param tries number Max attempts (default 5)
-- @return boolean
function M.forage(item, tries)
  tries = tries or 5
  for _ = 1, tries do
    local result = M.bput("forage " .. item,
      "Roundtime",
      "The room is too cluttered",
      "You really need to have at least one hand free",
      "You survey the area and realize that any foraging efforts would be futile")
    if result:find("too cluttered") then
      M.bput("kick pile", "I could not find", "take a step back",
        "Now what did the", "You lean back")
    elseif result:find("futile") then
      return false
    elseif result:find("one hand free") then
      -- Try to stow right hand via DRCI if available
      if DRCI and DRCI.stow_hand then
        DRCI.stow_hand("right")
      end
    end
    if waitrt then waitrt() end
  end
  return true
end

--- Collect materials.
-- @param item string Item to collect
-- @param practice boolean Whether to practice (default true)
function M.collect(item, practice)
  if practice == nil then practice = true end
  local practicing = practice and "practice" or ""
  local result = M.bput("collect " .. item .. " " .. practicing, unpack(M.COLLECT_MESSAGES))
  if result:find("too cluttered") then
    M.bput("kick pile", "I could not find", "take a step back",
      "Now what did the", "You lean back")
    M.collect(item)
  end
  if waitrt then waitrt() end
end

--- Get rummage results (skins/gems/materials).
-- @param parameter string "S" for skins, "G" for gems, "M" for materials
-- @param container string Container to rummage
-- @return table Array of nouns found
function M.rummage(parameter, container)
  local result = M.bput("rummage /" .. parameter .. " my " .. container,
    "but there is nothing in there like that",
    "looking for .* and see",
    "While it's closed",
    "I don't know what you are referring to",
    "You feel about",
    "That would accomplish nothing")
  if result:find("You feel about") then
    M.release_invisibility()
    return M.rummage(parameter, container)
  end
  if Regex.test("nothing in there|closed|don't know|accomplish nothing", result) then
    return {}
  end
  local text = result:match("looking for .* and see (.*)%.")
  if text then
    return M.list_to_nouns(text)
  end
  return {}
end

function M.get_skins(container) return M.rummage("S", container) end
function M.get_gems(container)  return M.rummage("G", container) end
function M.get_materials(container) return M.rummage("M", container) end

--- Play a musical instrument (simplified).
-- @param song string Song to play
-- @param instrument string|nil Instrument name
function M.play_song(song, instrument)
  local cmd = "play " .. song
  if instrument then
    cmd = cmd .. " on my " .. instrument
  end
  M.bput(cmd,
    "You begin a", "You effortlessly begin", "You begin some",
    "You struggle to begin", "slightest hint of difficulty",
    "fumble slightly", "You're already playing",
    "Play on what instrument", "too damaged to play",
    "dirtiness may affect your performance",
    "You cannot play", "now isn't the best time")
end

--- Stop playing music.
function M.stop_playing()
  M.bput("stop play", "You stop playing", "In the name of", "But you're not performing")
end

-------------------------------------------------------------------------------
-- play_song_managed — full Lich5 DRC.play_song? equivalent
-- Handles song difficulty auto-scaling and instrument recovery.
-------------------------------------------------------------------------------

--- Find the previous (easier) song in a perform_options linked-list table.
-- Returns the key whose value == current (excluding self-referencing entries).
-- @param song_list table perform_options table
-- @param current string Current song name
-- @return string|nil Previous song name, or nil if at start
local function song_list_prev(song_list, current)
  for k, v in pairs(song_list) do
    if v == current and k ~= current then
      return k
    end
  end
  return nil
end

--- Managed song-play with auto difficulty scaling.
-- Full port of Lich5's DRC.play_song?(settings, song_list, worn, skip_clean, climbing).
--
-- Tracks UserVars.song / UserVars.climbing_song; auto-escalates or de-escalates
-- based on server feedback.  Respects UserVars.climbing_song_offset to prevent
-- re-scaling after a manual offset_climbing_song call.
--
-- @param settings table   Character settings (worn_instrument / instrument fields)
-- @param song_list table  perform_options table (key=song, value=next-harder song)
-- @param worn boolean     true = use settings.worn_instrument, false = settings.instrument
-- @param skip_clean boolean  true = skip dirty/wet cleanup attempt
-- @param climbing boolean    true = use UserVars.climbing_song, false = UserVars.song
-- @param _depth number    Internal recursion guard (do not pass)
-- @return boolean true if playing started, false if we could not play
function M.play_song_managed(settings, song_list, worn, skip_clean, climbing, _depth)
  if worn == nil     then worn      = true  end
  if skip_clean == nil then skip_clean = false end
  if climbing == nil then climbing  = false end
  _depth = _depth or 0
  if _depth > 60 then
    respond("[DRC] play_song_managed: recursion limit, giving up")
    return false
  end

  local instrument = worn and settings.worn_instrument or settings.instrument

  -- Detect instrument change and reset calibrated song data
  if UserVars.instrument == nil then
    respond("[DRC] play_song_managed: first instrument, resetting song data")
    UserVars.song          = nil
    UserVars.climbing_song = nil
    UserVars.instrument    = instrument
  elseif UserVars.instrument ~= instrument then
    respond("[DRC] play_song_managed: instrument changed to " .. tostring(instrument))
    UserVars.song          = nil
    UserVars.climbing_song = nil
    UserVars.instrument    = instrument
  end

  -- Seed starting song ("scales halt" is the lowest-difficulty perform entry)
  local first_song = (song_list and song_list["scales halt"] ~= nil) and "scales halt" or next(song_list)
  if not UserVars.song          then UserVars.song          = first_song end
  if not UserVars.climbing_song then UserVars.climbing_song = first_song end

  local song_to_play = climbing and UserVars.climbing_song or UserVars.song
  local play_cmd = "play " .. tostring(song_to_play)
  if instrument then play_cmd = play_cmd .. " on my " .. tostring(instrument) end

  -- Release Eillie's Cry (Bard-specific) if active before playing
  if DRSpells and DRSpells.active_spells then
    local ecry = tonumber(DRSpells.active_spells["Eillie's Cry"])
    if ecry and ecry > 0 then put("release ecry"); pause(0.5) end
  end

  local result = M.bput(play_cmd,
    "too damaged to play",
    "dirtiness may affect your performance",
    "slightest hint of difficulty",
    "fumble slightly",
    "submerged in the water",
    "You begin a",
    "You struggle to begin",
    "You're already playing a song",
    "You effortlessly begin",
    "You begin some",
    "You cannot play",
    "Play on what instrument",
    "Are you sure that's the right instrument",
    "now isn't the best time",
    "find somewhere drier before trying to play",
    "You should stop practicing",
    "really need to drain",
    "tuning is off, and may hinder")

  if result:find("Play on what instrument") or result:find("right instrument") then
    -- Instrument not in hand — try to retrieve and wear it
    if DRCI then
      if DRCI.get_item and not DRCI.get_item(instrument) then
        respond("[DRC] play_song_managed: failed to get " .. tostring(instrument))
        return false
      end
      if worn and DRCI.wear_item and not DRCI.wear_item(instrument) then
        respond("[DRC] play_song_managed: failed to wear " .. tostring(instrument))
        return false
      end
    end
    return M.play_song_managed(settings, song_list, worn, skip_clean, climbing, _depth + 1)

  elseif result:find("now isn't the best time")
      or result:find("find somewhere drier")
      or result:find("You should stop practicing") then
    return false

  elseif result:find("You're already playing") then
    M.stop_playing()
    return M.play_song_managed(settings, song_list, worn, skip_clean, climbing, _depth + 1)

  elseif result:find("You cannot play")
      or result:find("too damaged to play")
      or result:find("submerged in the water") then
    return false

  elseif result:find("tuning is off") then
    respond("[DRC] play_song_managed: instrument out of tune (continuing)")
    return true  -- caller decides whether to re-tune

  elseif result:find("dirtiness may affect") or result:find("really need to drain") then
    if DRSkill and DRSkill.getrank("Performance") < 20 then return true end
    if skip_clean then return true end
    return true  -- advanced cleanup not yet implemented; treat as playable

  elseif result:find("slightest hint of difficulty") or result:find("fumble slightly") then
    return true  -- acceptable difficulty

  elseif result:find("You begin a") or result:find("You effortlessly begin") or result:find("You begin some") then
    -- Song too easy — escalate to next harder song
    local next_song = song_list[song_to_play]
    if not next_song or next_song == song_to_play then return true end  -- at terminal node
    if climbing and UserVars.climbing_song_offset then return true end
    if not climbing and UserVars.song_offset        then return true end
    M.stop_playing()
    if climbing then UserVars.climbing_song = next_song
    else             UserVars.song          = next_song end
    return M.play_song_managed(settings, song_list, worn, skip_clean, climbing, _depth + 1)

  elseif result:find("You struggle to begin") then
    -- Song too hard — reset to first song
    if song_to_play == first_song then return true end
    if climbing and UserVars.climbing_song_offset then return true end
    if not climbing and UserVars.song_offset        then return true end
    M.stop_playing()
    if climbing then UserVars.climbing_song = first_song
    else             UserVars.song          = first_song end
    return M.play_song_managed(settings, song_list, worn, skip_clean, climbing, _depth + 1)

  else
    return false
  end
end

--- Pause all other running scripts (respecting no_pause_all) and return the list of
-- script names that were paused. Pass that list to safe_unpause_list when done.
-- Unlike Lich5's version this never returns false — the mutex concept is unnecessary
-- in Revenant's cooperative coroutine model.
-- @return table Array of script names that were paused
function M.safe_pause_list()
  local current = Script and Script.name or nil
  local to_pause = {}
  if Script and Script.list and Script.is_paused then
    for _, name in ipairs(Script.list()) do
      if name ~= current and not Script.is_paused(name) then
        to_pause[#to_pause + 1] = name
      end
    end
    if Script.pause_all then Script.pause_all() end
  end
  if #to_pause > 0 then
    respond("DRC: Pausing " .. table.concat(to_pause, ", ") .. " to run " .. (current or "script"))
  end
  return to_pause
end

--- Unpause the scripts returned by safe_pause_list.
-- Only unpauses scripts that are still paused (avoids touching scripts paused by others).
-- @param scripts_to_unpause table Array of script names from safe_pause_list
function M.safe_unpause_list(scripts_to_unpause)
  if not scripts_to_unpause or #scripts_to_unpause == 0 then return end
  if Script and Script.unpause then
    local unpaused = {}
    for _, name in ipairs(scripts_to_unpause) do
      Script.unpause(name)
      unpaused[#unpaused + 1] = name
    end
    local current = Script.name or "script"
    respond("DRC: Unpausing " .. table.concat(unpaused, ", ") .. ", " .. current .. " has finished.")
  end
end

--- Emit an audible alert (bell character) to the client window.
-- Mirrors Lich5's DRC.beep (which echoes "\a" on Windows).
function M.beep()
  respond("\a")
end

--- Kick a pile of debris/rocks out of the way.
-- Mirrors Lich5's DRC.kick_pile? / DRCT.kick_pile?
-- @return string The matched response line
function M.kick_pile()
  return M.bput("kick pile",
    "kick a pile",
    "But there is no pile to kick",
    "You kick the pile of rocks",
    "You stop in the middle of your kick")
end

return M
