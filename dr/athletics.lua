--- @revenant-script
--- name: athletics
--- version: 1.0
--- author: elanthia-online
--- original-authors: Ondreian, Nisugi, and dr-scripts contributors
--- game: dr
--- description: Train Athletics skill via location-appropriate climbing, swimming, or rope practice
--- tags: athletics, training, climbing, swimming, rope
--- source: https://elanthipedia.play.net/Lich_script_repository#athletics
--- @lic-certified: complete 2026-03-19
---
--- Conversion notes vs Lich5:
---   * DRSkill.getxp uses 0-19 scale (Lich5 used 0-34).
---     end_exp ceiling scaled accordingly (29 → ~16, 32 → ~17).
---   * Flags.delete → Flags.remove; Flags['key']=val → Flags.set(key, val).
---   * before_dying block preserved via before_dying(function() ... end).
---   * DRC.play_song? → DRC.play_song_managed (newly implemented in lib/dr/common.lua).
---   * Script.running?/start_script/stop_script → Script.running/Script.run/Script.kill.
---   * Time.now → os.time(); Room.current.id → Room.id.
---   * DRRoom.npcs.length → #DRRoom.npcs.
---   * parse_args regex definitions → positional Script.vars matching.
---   * get_data("athletics") / get_data("perform") used for all data tables.
---
--- Usage:
---   ;athletics [wyvern|undergondola|xalas|stationary|cliffs|max] [skip_magic]
---
--- Settings keys used:
---   performance_pause, athletics_town, fang_cove_override_town, hometown,
---   climbing_target, swimming_target, have_climbing_rope, climbing_rope_adjective,
---   athletics_outdoorsmanship_rooms, held_athletics_items, worn_instrument,
---   avoid_athletics_in_justice, safe_room, athletics_debug

-- ============================================================================
-- Data and settings
-- ============================================================================

local settings       = get_settings()
local athletics_data = get_data("athletics")
local perform_data   = get_data("perform")

local athletics_options  = athletics_data and athletics_data.athletics_options or {}
local practice_options   = athletics_data and athletics_data.practice_options  or {}
local swimming_options   = athletics_data and athletics_data.swimming_options   or {}
local song_list          = perform_data   and perform_data.perform_options      or {}

local performance_pause  = settings.performance_pause or 3
local athletics_location = settings.athletics_town
                        or settings.fang_cove_override_town
                        or settings.hometown

local climbing_target_key = settings.climbing_target
local swimming_target_key = settings.swimming_target
local climbing_target     = climbing_target_key and practice_options[climbing_target_key]
local swimming_target     = swimming_target_key and swimming_options[swimming_target_key]
local have_climbing_rope  = settings.have_climbing_rope
local outdoorsmanship_rooms = settings.athletics_outdoorsmanship_rooms or {}

-- XP thresholds: Revenant uses 0-19 (Lich5 used 0-34).  We cap at 16 (≈29/34).
local start_exp = DRSkill.getxp("Athletics")
local end_exp   = math.min(start_exp + 8, 16)   -- +8 steps ≈ +15 Lich5 steps

-- ============================================================================
-- Argument parsing
-- ============================================================================

local args = {
  wyvern      = false,
  undergondola = false,
  xalas       = false,
  stationary  = false,
  cliffs      = false,
  max         = false,
  skip_magic  = false,
}

for i = 1, #Script.vars do
  local v = Script.vars[i]:lower()
  if     v:match("^wy")         then args.wyvern       = true
  elseif v:match("^un")         then args.undergondola = true
  elseif v:match("^xala")       then args.xalas        = true
  elseif v:match("^stat")       then args.stationary   = true
  elseif v:match("^cliff")      then args.cliffs       = true
  elseif v:match("^max")        then args.max          = true
  elseif v:find("skip_magic")   then args.skip_magic   = true
  end
end

if args.max then end_exp = 17 end  -- ~32/34 in Lich5

-- ============================================================================
-- Helpers
-- ============================================================================

--- Return true when we have trained enough for this session.
local function done_training()
  return DRSkill.getxp("Athletics") >= end_exp
end

--- Retrieve held athletics items from container.
local function get_athletics_items()
  if not settings.held_athletics_items or #settings.held_athletics_items == 0 then return end
  for _, item in ipairs(settings.held_athletics_items) do
    DRC.bput("get my " .. item, "You", "What were")
  end
end

--- Stow held athletics items.
local function stow_athletics_items()
  if not settings.held_athletics_items or #settings.held_athletics_items == 0 then return end
  for _, item in ipairs(settings.held_athletics_items) do
    DRC.bput("stow my " .. item, "You", "Stow what?")
  end
end

--- Walk to one of the outdoorsmanship rooms, run outdoorsmanship, and wait out
--- the per-session pause so the two skills interleave cleanly.
-- @param number number  Minutes to pass to outdoorsmanship (affects RT pause estimate)
local function outdoorsmanship_waiting(number)
  local skip_magic = args.skip_magic and "skip_magic" or ""
  local start_time = os.time()
  if #outdoorsmanship_rooms > 0 then
    local idx = math.random(1, #outdoorsmanship_rooms)
    DRCT.walk_to(outdoorsmanship_rooms[idx])
  end
  stow_athletics_items()
  DRC.wait_for_script_to_complete("outdoorsmanship",
    { tostring(number), "room=" .. (Room and tostring(Room.id) or "0"), "rock", skip_magic })
  local remaining_pause = (number * 15) - (os.time() - start_time)
  if remaining_pause > 0 then pause(remaining_pause) end
  get_athletics_items()
end

--- Climb a single target, walking to the room first.
-- @param room number Target room ID
-- @param targets table Array of climb target strings to attempt in order
-- @return boolean false if done_training after any attempt, true to keep going
local function climb(room, targets)
  for _, target in ipairs(targets) do
    DRCT.walk_to(room)
    if DRRoom and DRRoom.npcs and #DRRoom.npcs >= 3 then return true end
    DRC.bput("climb " .. target, ".*")
    pause(0.1)
    waitrt()
    if done_training() then return false end
  end
  return true
end

--- Offset the climbing song by one step.
-- @param direction number  1 = harder, -1 = easier
local function offset_climbing_song(direction)
  if not UserVars.climbing_song_offset then return end
  if not (song_list and next(song_list)) then return end

  if direction == 1 then
    local next_song = song_list[UserVars.climbing_song]
    if next_song then UserVars.climbing_song = next_song end
  elseif direction == -1 then
    -- Find the key whose value is the current song
    for k, v in pairs(song_list) do
      if v == UserVars.climbing_song and k ~= UserVars.climbing_song then
        UserVars.climbing_song = k
        break
      end
    end
  else
    echo("athletics: invalid offset direction " .. tostring(direction))
  end
end

--- Check whether the climbing rope is still usable today.
-- Reads the rope's daily-use message and returns false if exhausted.
local function check_rope()
  Flags.add("climbing-dead-rope",
    "You believe you can use it for %d+ minutes per day%.")
  Flags.add("climbing-live-rope",
    "You believe you haven't yet used it today")
  DRC.bput("study " .. settings.climbing_rope_adjective .. " rope",
    "You're certain you can")
  pause(1)
  local dead = Flags["climbing-dead-rope"]
  local live = Flags["climbing-live-rope"]
  if dead and not live then
    DRC.message("Your rope is dead tired! Get a better one, you poor slob!")
    return false
  end
  return true
end

--- Pick the starting climbing song based on current Athletics rank.
local function pick_climbing_song()
  local rank = DRSkill.getrank("Athletics")
  if     rank < 100  then return "lament"
  elseif rank < 250  then return "psalm"
  elseif rank < 350  then return "tarantella"
  elseif rank < 450  then return "rondo"
  else                    return "concerto masterful"
  end
end

-- ============================================================================
-- Practice routines
-- ============================================================================

--- Simple swim loop — walk through a set of swim rooms until done.
local function swim_loop(rooms)
  if not rooms then return end
  repeat
    for _, room in ipairs(rooms) do
      DRCT.walk_to(room)
    end
  until done_training()
end

--- Dedicated climbing-practice loop at a single room/target (hide or performance).
-- @param room number   Room ID of the climb target
-- @param target string Climb target noun
-- @param to_hide boolean  If true, hide before practicing; else start performance
local function climb_practice(room, target, to_hide)
  if not target then return end
  DRCT.walk_to(room)
  while not done_training() do
    DRC.retreat()
    if to_hide then
      local hidden = false
      for _ = 1, 5 do
        if DRC.hide() then hidden = true; break end
      end
      if not hidden then return end
    else
      if not Script.running("performance") then
        Script.run("performance", "noclean")
      end
      pause(performance_pause)  -- ensure playing before starting climb practice
    end

    Flags.add("ct-climbing-finished", "You finish practicing your climbing")
    Flags.add("ct-climbing-combat",   "You are engaged in combat")

    DRC.bput("climb practice " .. target, "You begin to practice ")
    while true do
      pause(0.5)
      if Flags["ct-climbing-finished"] then break end
      if Flags["ct-climbing-combat"]   then
        DRC.bput("stop climb",
          "You stop practicing your climbing skills.",
          "You weren't practicing your climbing skills anyway.")
        return
      end
      if done_training() then break end
    end
    DRC.bput("stop climb",
      "You stop practicing your climbing skills.",
      "You weren't practicing your climbing skills anyway.")
  end
  if to_hide then
    DRC.bput("unhide", "You come out of hiding", "You slip out of hiding", "But you are not")
  end
end

--- Helper: override the configured climbing target and call climb_practice.
local function override_location_and_practice(place)
  local target_data = practice_options[place]
  if not target_data then
    DRC.message("athletics: no practice_options entry for '" .. place .. "'")
    return
  end
  climb_practice(target_data.id, target_data.target, target_data.hide)
end

--- Train with a climbing rope (rope + instrument combo required).
local function train_with_rope(stationary)
  if not DRCI.exists(settings.climbing_rope_adjective .. " rope") then return end
  if not DRCI.exists(settings.worn_instrument) then return end

  -- Pick an initial climbing song if not set
  UserVars.climbing_song = UserVars.climbing_song or pick_climbing_song()
  if UserVars.athletics_debug then
    echo("athletics: climbing_song = " .. tostring(UserVars.climbing_song))
    echo("athletics: song_list size = " .. tostring(#(song_list or {})))
  end

  Flags.add("climbing-finished",
    "You finish practicing your climbing",
    "The rope's will quickly fades away",
    "Your focus diverts away from the rope")
  Flags.add("climbing-too-hard",  "This climb is too difficult")
  Flags.add("climbing-too-easy",  "This climb is no challenge at all, so you stop practicing")
  Flags.add("climbing-dead-rope", "You believe you can use it for %d+ minutes per day%.")
  Flags.add("climbing-live-rope", "You believe you haven't yet used it today")

  DRCI.stow_hands()
  if not stationary then DRCT.walk_to(settings.safe_room) end

  local get_result = DRC.bput("get " .. settings.climbing_rope_adjective .. " rope",
    "You are already holding that", "You get", "What were you", "But that is already")
  if get_result:find("But that is already") then
    DRC.bput("remove my " .. settings.climbing_rope_adjective .. " rope", "You remove")
  end

  -- Seed the dead-rope flag based on initial check
  if not check_rope() then
    Flags.set("climbing-dead-rope", true)
  end

  while not done_training() do
    if Flags["climbing-dead-rope"] then break end

    DRC.fix_standing()
    Flags.reset("climbing-finished")
    DRC.stop_playing()

    if not DRC.play_song_managed(settings, song_list, true, true, true) then break end

    local climb_result = DRC.bput(
      "climb practice " .. settings.climbing_rope_adjective .. " rope",
      "You begin to practice ",
      "you mime a convincing climb while pulling the rope hand over hand",
      "Directing your attention toward your rope",
      "Allows you to climb various things like a tree",
      "But you aren't holding",
      "You should stop practicing")

    if climb_result:find("you mime") then
      if not check_rope() then break end
      if not DRC.play_song_managed(settings, song_list, true, true, true) then break end

    elseif climb_result:find("Directing your") or climb_result:find("You should stop practicing") then
      -- Wait for climb to finish or a difficulty signal
      while true do
        pause(1)
        if Flags["climbing-finished"] then break end

        if Flags["climbing-too-hard"] then
          Flags.reset("climbing-too-hard")
          UserVars.climbing_song_offset = true
          DRC.stop_playing()
          offset_climbing_song(-1)
          break
        elseif Flags["climbing-too-easy"] then
          Flags.reset("climbing-too-easy")
          UserVars.climbing_song_offset = true
          DRC.stop_playing()
          offset_climbing_song(1)
          break
        elseif Flags["climbing-dead-rope"] then
          if not check_rope() then break end
          if not DRC.play_song_managed(settings, song_list, true, true, true) then break end
        end
      end

    elseif climb_result:find("Allows you to climb various things like a tree") then
      echo("athletics: waiting for rope to become climbable again")
      pause(20)

    elseif climb_result:find("But you aren't holding") then
      DRC.bput("get " .. settings.climbing_rope_adjective .. " rope",
        "You are already holding that", "You get", "What were you")
    end
  end

  DRC.bput("stop climb",
    "You stop practicing your climbing skills.",
    "You weren't practicing your climbing skills anyway.")
  DRC.stop_playing()
  DRC.fix_standing()
  DRCI.stow_hands()
end

-- ============================================================================
-- Location-specific routines
-- ============================================================================

--- Crossing athletics: rank-gated choice of swim, urban climb, or rock practice.
local function crossing_athletics()
  local modrank = DRSkill.getmodrank("Athletics")
  if modrank <= 50 then
    swim_loop(swimming_options["arthe_dale"] and swimming_options["arthe_dale"].rooms)
  elseif modrank < 290 then
    waitrt()
    pause(performance_pause)
    if not Script.running("performance") then Script.run("performance", "") end
    local crossing_data = athletics_options["crossing"] or {}
    while not done_training() do
      for _, data in ipairs(crossing_data) do
        if not (settings.avoid_athletics_in_justice and data.justice) then
          if not climb(data.room, data.targets) then break end
        end
      end
    end
  elseif modrank < 450 then
    override_location_and_practice("segoltha_bank")
  else
    if modrank > 650 then
      DRC.message("The xalas argument will train faster at 650+ athletics.  Be aware that it's potentially dangerous.")
    end
    override_location_and_practice("arthelun_rocks")
    if modrank > 650 then
      DRC.message("The xalas argument will train faster at 650+ athletics.  Be aware that it's potentially dangerous.")
    end
  end
end

--- Hibarnhvidar athletics: swim Liirewsag River.
-- (Intermittent map errors can cause go2 to get stuck; manual moves are a workaround.)
local function swim_liirewsag()
  DRCT.walk_to(4155)
  move("nw")
  while not done_training() do
    move("climb bank")
    for _ = 1, 3 do move("south"); waitrt() end
    DRCT.walk_to(4155)
    move("nw")
  end
  move("climb bank")
  waitrt()
end

--- Ratha athletics: rock gorge for low ranks; deep crack with Stealth prereq.
local function ratha_athletics()
  while not done_training() do
    if DRSkill.getrank("Athletics") <= 185 then
      override_location_and_practice("ratha_rock_gorge")
    elseif DRSkill.getrank("Stealth") >= 130 then
      override_location_and_practice("ratha_deep_crack")
    else
      DRC.message("You don't meet current requirements for Ratha climbing. You need at least 130 stealth.")
      break
    end
  end
end

--- Undergondola branch route (540+ uses full route; lower uses practice spot).
local function climb_branch()
  local modrank = DRSkill.getmodrank("Athletics")
  if modrank < 540 then
    override_location_and_practice("undergondola_branch")
  else
    if modrank > 850 then
      DRC.message("Warning: Using the undergondola arg with more than 850 athletics is not best use and you may consider the wyvern option instead.")
    end
    DRCT.walk_to(9607)
    DRCT.walk_to(9515)
    while not done_training() do
      DRCT.walk_to(2245)
      DRCT.walk_to(9607)
      DRCT.walk_to(11126)
      DRCT.walk_to(9515)
      if done_training() then break end
      outdoorsmanship_waiting(4)
    end
  end
end

--- Shard undergondola cliffs route (no branch).
local function climb_cliffs()
  while not done_training() do
    DRCT.walk_to(9525)
    DRCT.walk_to(9609)
    DRCT.walk_to(9607)
    DRCT.walk_to(2900)
    if done_training() then break end
    outdoorsmanship_waiting(4)
  end
end

--- Wyvern Cliffs full circuit (best exp at high ranks).
local function climb_wyvern()
  DRCT.walk_to(19464)
  while not done_training() do
    if DRSkill.getmodrank("Athletics") > 540 then DRCT.walk_to(2245) end
    DRCT.walk_to(9607)
    DRCT.walk_to(11126)
    DRCT.walk_to(19464)
    DRCT.walk_to(13558)
    DRCT.walk_to(14010)
    DRCT.walk_to(13117)
    DRCT.walk_to(6443)
    if done_training() then break end
    outdoorsmanship_waiting(3)
  end
end

--- Zoluren Xalas route (faster at 650+ but dangerous).
local function climb_xalas()
  DRCT.walk_to(6154)
  while not done_training() do
    DRCT.walk_to(12838)
    DRCT.walk_to(6154)
    if done_training() then break end
    outdoorsmanship_waiting(4)
  end
end

--- Shard athletics: rank-gated city climb, undergondola cliffs, branch, or wyvern route.
-- Must be defined after climb_cliffs / climb_branch / climb_wyvern.
local function shard_athletics()
  while not done_training() do
    local modrank = DRSkill.getmodrank("Athletics")
    if modrank < 240 then
      local shard_data = athletics_options["shard"] or {}
      while not done_training() do
        for _, data in ipairs(shard_data) do
          if not (settings.avoid_athletics_in_justice and data.justice) then
            if not climb(data.room, data.targets) then break end
          end
        end
      end
    elseif modrank < 540 then
      climb_cliffs()
    elseif modrank < 850 then
      climb_branch()
    else
      climb_wyvern()
    end
  end
end

-- ============================================================================
-- Cleanup (before_dying equivalent)
-- ============================================================================

before_dying(function()
  if Script.running("performance") then Script.kill("performance") end
  put("stop climb")
  Flags.remove("climbing-finished")
  Flags.remove("climbing-too-easy")
  Flags.remove("climbing-too-hard")
  Flags.remove("climbing-dead-rope")
  Flags.remove("climbing-live-rope")
  Flags.remove("ct-climbing-finished")
  Flags.remove("ct-climbing-combat")
end)

-- ============================================================================
-- Main dispatch
-- ============================================================================

get_athletics_items()

if not args.skip_magic then
  DRC.wait_for_script_to_complete("buff", { "athletics" })
end

if args.wyvern or settings.climbing_target == "wyvern" then
  climb_wyvern()
elseif args.undergondola or settings.climbing_target == "undergondola" then
  climb_branch()
elseif args.xalas or settings.climbing_target == "xalas" then
  climb_xalas()
elseif args.cliffs or settings.climbing_target == "cliffs" then
  climb_cliffs()
elseif have_climbing_rope then
  train_with_rope(args.stationary)
elseif swimming_target then
  swim_loop(swimming_target.rooms)
elseif climbing_target then
  climb_practice(climbing_target.id, climbing_target.target, climbing_target.hide)
elseif athletics_location == "Crossing" then
  crossing_athletics()
elseif athletics_location == "Riverhaven" then
  if DRSkill.getrank("Athletics") > 140 then crossing_athletics() end
elseif athletics_location == "Shard" then
  shard_athletics()
elseif athletics_location == "Hibarnhvidar" then
  swim_liirewsag()
elseif athletics_location == "Ratha" then
  ratha_athletics()
else
  DRC.message("athletics: no training path found for hometown=" .. tostring(athletics_location))
end

stow_athletics_items()
