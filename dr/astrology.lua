--- @revenant-script
--- name: astrology
--- version: 1.0.0
--- author: Tillmen, Chatpop (original Lich5); DR-scripts community (maintained)
--- maintained-by: Sordal-GSIV
--- game: dr
--- tags: magic, astrology, training, moon mage, telescope, prediction
--- description: Moon Mage astrology training — observations, RtR, predictions, attunement
---
--- Original Lich5 author: Tillmen, Chatpop (community-maintained)
--- Ported to Revenant Lua from astrology.lic
--- Documented: https://elanthipedia.play.net/Lich_script_repository#astrology
---
--- Usage:
---   ;astrology          — full training loop (observe, predict, attune)
---   ;astrology rtr      — Read the Ripples observation mode
---
--- CharSettings keys (all optional, sensible defaults):
---   astrology_waggle_set       string  waggle_sets key (default "astrology")
---   astrology_force_visions    bool    force predict future instead of divination tool
---   divination_tool            JSON    {name, tied, worn, container}
---   divination_bones_storage   JSON    {tied, container}
---   have_telescope             bool
---   telescope_storage          JSON    {tied, container}
---   telescope_name             string  (default "telescope")
---   astral_plane_training      JSON    {train_source="...", train_destination="..."}
---   astrology_use_full_pools   bool    target pool 10 if true
---   astrology_pool_target      number  (default 5)
---   astrology_prediction_skills JSON   {magic, lore, offense, defense, survival}
---   astrology_training         JSON    array of tasks: observe|weather|events|attunement|ways|rtr
---
--- @lic-certified: complete 2026-03-18

Script.unique()

local Args = require("lib/args")

-------------------------------------------------------------------------------
-- XP thresholds
-- DRSkill.getxp returns 0-19 (Revenant) vs 0-34 (Lich5).
-- > 30 (Lich5) → > 16; >= 32 → >= 17
-------------------------------------------------------------------------------

local XP_SKIP = 16   -- skip a sub-task when Astrology XP is above this
local XP_DONE = 17   -- exit training loop when Astrology XP reaches this

-------------------------------------------------------------------------------
-- Pool understanding patterns  (predict state all output)
-------------------------------------------------------------------------------

local POOL_PATTERNS = {
  { pattern = "no understanding",          value = 0  },
  { pattern = "feeble understanding",      value = 1  },
  { pattern = "weak understanding",        value = 2  },
  { pattern = "fledgling understanding",   value = 3  },
  { pattern = "modest understanding",      value = 4  },
  { pattern = "decent understanding",      value = 5  },
  { pattern = "significant understanding", value = 6  },
  { pattern = "potent understanding",      value = 7  },
  { pattern = "insightful understanding",  value = 8  },
  { pattern = "powerful understanding",    value = 9  },
  { pattern = "complete understanding",    value = 10 },
}

-- Observation completion patterns (telescope peer results)
local OBSERVE_FINISHED_MESSAGES = {
  "You learned something useful from your observation",
  "Clouds obscure the sky",
  "While the sighting wasn't quite",
  "You peer aimlessly through your telescope",
  "Too many futures cloud your mind - you learn nothing.",
  "you still learned more",
  "You have not pondered your last observation sufficiently",
}

local OBSERVE_SUCCESS_MESSAGES = {
  "You learned something useful from your observation",
  "While the sighting wasn't quite",
  "you still learned more",
}

local OBSERVE_INJURED_MESSAGES = {
  "The pain is too much",
  "Your vision is too fuzzy",
}

-- Observation success patterns for the naked-eye (non-telescope) path
local OBSERVE_NAKED_SUCCESS = {
  "While the sighting",
  "You learned something useful",
  "Clouds obscure",
  "You learn nothing",
  "too close to the sun",
  "too faint for you",
  "below the horizon",
  "You have not pondered",
  "You are unable to make use",
}

-- Perceive targets for attunement training
local PERCEIVE_TARGETS = {
  "", "mana", "moons", "planets", "psychic",
  "transduction", "perception", "moonlight",
}

-------------------------------------------------------------------------------
-- Constellation data  (base-constellations.yaml, all 65 entries)
-------------------------------------------------------------------------------

local CONSTELLATIONS = {
  { name="Elanthian Sun", telescope=false, circle=1,   constellation=false, pools={Survival=1} },
  { name="Heart",         telescope=false, circle=1,   constellation=true,  pools={Survival=1} },
  { name="Yavash",        telescope=false, circle=1,   constellation=false, pools={Magic=1} },
  { name="Xibar",         telescope=false, circle=1,   constellation=false, pools={Lore=1} },
  { name="Katamba",       telescope=false, circle=1,   constellation=false, pools={Defense=1} },
  { name="Wolf",          telescope=false, circle=2,   constellation=true,  pools={Magic=1} },
  { name="Lion",          telescope=false, circle=3,   constellation=true,  pools={Defense=1, Survival=1} },
  { name="Raven",         telescope=false, circle=4,   constellation=true,  pools={Lore=1} },
  { name="Unicorn",       telescope=false, circle=5,   constellation=true,  pools={Survival=1} },
  { name="Boar",          telescope=false, circle=6,   constellation=true,  pools={Offense=1, Survival=1} },
  { name="Panther",       telescope=false, circle=7,   constellation=true,  pools={Offense=1, Survival=1} },
  { name="Cobra",         telescope=false, circle=8,   constellation=true,  pools={Magic=1, Lore=1} },
  { name="Ox",            telescope=false, circle=9,   constellation=true,  pools={Survival=1, Magic=1} },
  { name="Scorpion",      telescope=true,  circle=10,  constellation=true,  pools={Offense=2, Defense=1} },
  { name="Wren",          telescope=true,  circle=11,  constellation=true,  pools={Magic=2, Lore=1} },
  { name="Cat",           telescope=false, circle=12,  constellation=true,  pools={Offense=1} },
  { name="Ram",           telescope=false, circle=13,  constellation=true,  pools={Survival=2} },
  { name="Dolphin",       telescope=false, circle=14,  constellation=true,  pools={Survival=1, Lore=1} },
  { name="Shardstar",     telescope=true,  circle=15,  constellation=true,  pools={Defense=1, Lore=2} },
  { name="Nightingale",   telescope=false, circle=15,  constellation=true,  pools={Defense=1, Magic=2} },
  { name="Wolverine",     telescope=false, circle=16,  constellation=false, pools={Offense=1, Survival=1} },
  { name="Centaur",       telescope=true,  circle=17,  constellation=true,  pools={Offense=2, Defense=1} },
  { name="Magpie",        telescope=false, circle=18,  constellation=true,  pools={Defense=1} },
  { name="Weasel",        telescope=false, circle=19,  constellation=true,  pools={Offense=1, Lore=2} },
  { name="King Snake",    telescope=true,  circle=20,  constellation=true,  pools={Defense=1, Lore=2} },
  { name="Viper",         telescope=true,  circle=21,  constellation=true,  pools={Offense=2} },
  { name="Albatross",     telescope=false, circle=22,  constellation=true,  pools={Defense=1, Lore=1} },
  { name="Shark",         telescope=false, circle=23,  constellation=true,  pools={Offense=1, Survival=1} },
  { name="Donkey",        telescope=false, circle=24,  constellation=true,  pools={Magic=1, Lore=1} },
  { name="Coyote",        telescope=false, circle=25,  constellation=true,  pools={Offense=1, Magic=1} },
  { name="Dove",          telescope=false, circle=26,  constellation=true,  pools={Defense=1, Magic=1} },
  { name="Phoenix",       telescope=true,  circle=27,  constellation=true,  pools={Magic=1, Lore=2} },
  { name="Heron",         telescope=false, circle=28,  constellation=true,  pools={Survival=2, Lore=1} },
  { name="Mongoose",      telescope=false, circle=29,  constellation=true,  pools={Offense=1, Defense=1} },
  { name="Goshawk",       telescope=false, circle=30,  constellation=true,  pools={Defense=1, Survival=1} },
  { name="Owl",           telescope=true,  circle=31,  constellation=true,  pools={Offense=1, Magic=2} },
  { name="Welkin",        telescope=false, circle=32,  constellation=true,  pools={Defense=1, Lore=1} },
  { name="Raccoon",       telescope=false, circle=33,  constellation=true,  pools={Defense=1, Survival=1} },
  { name="Cow",           telescope=false, circle=34,  constellation=true,  pools={Survival=2, Magic=1} },
  { name="Adder",         telescope=true,  circle=35,  constellation=true,  pools={Offense=2, Magic=2} },
  { name="Vulture",       telescope=true,  circle=36,  constellation=true,  pools={Defense=2, Survival=2} },
  { name="Shrew",         telescope=true,  circle=37,  constellation=true,  pools={Offense=1, Magic=2} },
  { name="Shrike",        telescope=false, circle=38,  constellation=true,  pools={Survival=2, Magic=1} },
  { name="Jackal",        telescope=false, circle=39,  constellation=true,  pools={Defense=2, Magic=1} },
  { name="Spider",        telescope=false, circle=40,  constellation=true,  pools={Offense=2} },
  { name="Giant",         telescope=false, circle=41,  constellation=true,  pools={Defense=2} },
  { name="Hare",          telescope=false, circle=42,  constellation=true,  pools={Defense=1, Lore=2} },
  { name="Verena",        telescope=false, circle=43,  constellation=false, pools={Lore=3} },
  { name="Toad",          telescope=false, circle=44,  constellation=true,  pools={Magic=2} },
  { name="Archer",        telescope=true,  circle=45,  constellation=true,  pools={Offense=2, Survival=2} },
  { name="Estrilda",      telescope=false, circle=46,  constellation=false, pools={Offense=3} },
  { name="Brigantine",    telescope=false, circle=47,  constellation=true,  pools={Survival=1, Lore=2} },
  { name="Scales",        telescope=false, circle=48,  constellation=true,  pools={Offense=1, Lore=2} },
  { name="Durgaulda",     telescope=false, circle=49,  constellation=false, pools={Magic=3} },
  { name="Triquetra",     telescope=false, circle=50,  constellation=true,  pools={Offense=1, Survival=1} },
  { name="Yoakena",       telescope=false, circle=52,  constellation=false, pools={Survival=3} },
  { name="Penhetia",      telescope=false, circle=55,  constellation=false, pools={Defense=3} },
  { name="Szeldia",       telescope=false, circle=60,  constellation=false, pools={Offense=3, Survival=1} },
  { name="Merewalda",     telescope=true,  circle=65,  constellation=false, pools={Offense=1, Defense=3} },
  { name="Ismenia",       telescope=true,  circle=70,  constellation=false, pools={Magic=3, Lore=1} },
  { name="Morleena",      telescope=true,  circle=75,  constellation=false, pools={Defense=1, Survival=3} },
  { name="Amlothi",       telescope=true,  circle=80,  constellation=false, pools={Magic=1, Lore=3} },
  { name="Dawgolesh",     telescope=false, circle=85,  constellation=false, pools={Defense=3, Magic=2} },
  { name="Er'qutra",      telescope=true,  circle=90,  constellation=false, pools={Offense=3, Survival=2} },
  { name="Forge",         telescope=true,  circle=100, constellation=true,  pools={Offense=2, Defense=1, Lore=3} },
  { name="Eye",           telescope=true,  circle=125, constellation=true,  pools={Offense=1, Defense=1, Survival=1, Magic=2, Lore=1} },
  -- Special multi-pool constellations (available at circle 1)
  { name="Issendar",      telescope=false, circle=1,   constellation=true,  pools={Offense=1, Defense=1, Survival=1, Magic=1, Lore=1} },
  { name="Elide",         telescope=false, circle=1,   constellation=true,  pools={Offense=1, Defense=1, Survival=1, Magic=1, Lore=1} },
  { name="Kirmhara",      telescope=false, circle=1,   constellation=true,  pools={Offense=1, Defense=1, Survival=1, Magic=1, Lore=1} },
}

-------------------------------------------------------------------------------
-- Settings loader
-------------------------------------------------------------------------------

local function get_settings()
  local function json_read(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, val = pcall(Json.decode, raw)
    return (ok and type(val) == type(default)) and val or default
  end
  local function bool_read(key, default)
    local raw = CharSettings[key]
    if raw == nil or raw == "" then return default end
    return raw == "true"
  end

  local waggle_set_name = CharSettings["astrology_waggle_set"] or "astrology"
  local all_waggle      = json_read("waggle_sets", {})

  return {
    waggle_sets              = all_waggle,
    waggle_set_name          = waggle_set_name,
    astrology_force_visions  = bool_read("astrology_force_visions", false),
    divination_tool          = json_read("divination_tool", nil),
    divination_bones_storage = json_read("divination_bones_storage", nil),
    have_telescope           = bool_read("have_telescope", false),
    telescope_storage        = json_read("telescope_storage", nil),
    telescope_name           = CharSettings["telescope_name"] or "telescope",
    astral_plane_training    = json_read("astral_plane_training", {}),
    astrology_use_full_pools = bool_read("astrology_use_full_pools", false),
    astrology_pool_target    = tonumber(CharSettings["astrology_pool_target"]) or 5,
    astrology_prediction_skills = json_read("astrology_prediction_skills", {
      magic    = "magic",
      lore     = "lore",
      offense  = "offensive combat",
      defense  = "defensive combat",
      survival = "survival",
    }),
    astrology_training = json_read("astrology_training",
      { "observe", "weather", "events", "attunement" }),
  }
end

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------

--- Count non-nil pool values.
local function pool_size(pools)
  local n = 0
  for _, v in pairs(pools) do if v then n = n + 1 end end
  return n
end

--- Capture multi-line output for a command using get_noblock polling.
-- @return table|nil Lines matching filter_pat (plain find), or nil
local function issue_command(cmd, filter_pat, end_pat, timeout)
  local captured = {}
  fput(cmd)
  local deadline = os.time() + (timeout or 10)
  local done = false
  while not done and os.time() < deadline do
    local line = get_noblock()
    if line then
      captured[#captured + 1] = line
      if Regex.test(end_pat, line) then done = true end
    else
      pause(0.05)
    end
  end
  local result = {}
  for _, line in ipairs(captured) do
    if line:find(filter_pat, 1, true) then result[#result + 1] = line end
  end
  return #result > 0 and result or nil
end

--- Check if observation is finished (telescope path).
local function observation_finished(result)
  if not result then return false end
  for _, msg in ipairs(OBSERVE_FINISHED_MESSAGES) do
    if result:find(msg, 1, true) then return true end
  end
  return false
end

--- Check if observation succeeded (telescope path).
local function observation_success(result)
  if not result then return false end
  for _, msg in ipairs(OBSERVE_SUCCESS_MESSAGES) do
    if result:find(msg, 1, true) then return true end
  end
  return false
end

--- Inspect a telescope peer result for injuries or closed telescope.
-- @return boolean injured, boolean closed
local function telescope_result_status(result)
  if not result then return false, false end
  for _, msg in ipairs(OBSERVE_INJURED_MESSAGES) do
    if result:find(msg, 1, true) then return true, false end
  end
  if result:find("open it", 1, true) or result:find("You'll need to open", 1, true) then
    return false, true
  end
  return false, false
end

--- Poll briefly to confirm Read the Ripples is active in DRSpells.
local function rtr_active()
  for _ = 1, 100 do
    pause(0.01)
    local active = DRSpells.active_spells()
    if active and active["Read the Ripples"] then return true end
  end
  return false
end

local function debug(msg)
  if UserVars["astrology_debug"] then respond("Astrology: " .. msg) end
end

-------------------------------------------------------------------------------
-- Equipment
-------------------------------------------------------------------------------

--- Stow telescope if in-hand, then empty both hands.
local function empty_hands(telescope_name, telescope_storage, equipment_manager)
  if telescope_name and DRCI.in_hands(telescope_name) then
    DRCMM.store_telescope(telescope_name, telescope_storage)
  end
  if equipment_manager then
    equipment_manager:empty_hands()
  end
end

-------------------------------------------------------------------------------
-- get_healed
-------------------------------------------------------------------------------

--- Walk to safe-room for healing, return to original room, restore buffs/telescope.
local function get_healed(settings, telescope_name, telescope_storage, equipment_manager)
  if settings.have_telescope then
    DRCMM.store_telescope(telescope_name, telescope_storage)
  end
  local snapshot = Map.current_room()
  DRC.wait_for_script_to_complete("safe-room", { "force" })
  DRCT.walk_to(snapshot)
  -- Restore buffs (ignore rtr_data return here; re-buff only)
  local waggle_set = settings.waggle_sets[settings.waggle_set_name]
  if waggle_set then
    local buffs = {}
    for name, data in pairs(waggle_set) do
      if name ~= "Read the Ripples" then buffs[name] = data end
    end
    local active = DRSpells.active_spells()
    local to_cast = {}
    for name, data in pairs(buffs) do
      if not (active and active[name]) then to_cast[name] = data end
    end
    if next(to_cast) then DRCA.cast_spells(to_cast, settings) end
  end
  if settings.have_telescope then
    DRCMM.get_telescope(telescope_name, telescope_storage)
  end
end

-------------------------------------------------------------------------------
-- Observation
-------------------------------------------------------------------------------

--- Full observation routine for one body name.
-- Handles telescope path (center→peer) and naked-eye path.
-- Recursively retries on telescope not in hand, closed telescope, or injuries.
-- @return string|boolean result string (telescope) or bool (naked-eye)
local function observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
  Flags.add("bad-search", "is foiled by the (daylight|darkness)", "turns up fruitless")

  local result
  if settings.have_telescope then
    local center_result = DRCMM.center_telescope(body_name) or ""

    if center_result:find("Center what", 1, true) then
      DRCMM.get_telescope(telescope_name, telescope_storage)
      Flags.reset("bad-search")
      return observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
    elseif center_result:find("open it", 1, true) then
      DRC.bput("open my telescope", "extend your telescope")
      Flags.reset("bad-search")
      return observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
    elseif center_result:find("The pain is too much", 1, true)
        or center_result:find("Your vision is too fuzzy", 1, true) then
      get_healed(settings, telescope_name, telescope_storage, equipment_manager)
      Flags.reset("bad-search")
      return observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
    end

    local peer_result = DRCMM.peer_telescope()
    local injured, closed = telescope_result_status(peer_result)
    if injured then
      get_healed(settings, telescope_name, telescope_storage, equipment_manager)
      Flags.reset("bad-search")
      return observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
    elseif closed then
      DRC.bput("open my telescope", "extend your telescope")
      Flags.reset("bad-search")
      return observe_routine(body_name, settings, telescope_name, telescope_storage, equipment_manager)
    end

    result = peer_result
  else
    -- Naked-eye path
    local observe_result = DRCMM.observe(body_name)
    result = false
    if observe_result then
      for _, pat in ipairs(OBSERVE_NAKED_SUCCESS) do
        if observe_result:find(pat, 1, true) then
          result = true
          break
        end
      end
    end
  end

  -- Reset bad-search flag after each observation attempt
  Flags.reset("bad-search")
  return result
end

--- Observe the heavens and return visible bodies within character circle.
-- Returns nil if indoors or unable to observe.
local function visible_bodies()
  local result  = {}
  local circle  = DRStats.circle or 0

  fput("observe heavens")

  local deadline = os.time() + 15
  local done     = false
  while not done do
    local line = get_noblock()
    if not line then
      if os.time() > deadline then break end
      pause(0.05)
    else
      if line:find("That's a bit hard to do while inside", 1, true) then
        Messaging.msg("bold", "Astrology: Must be outdoors to observe sky. Exiting.")
        return nil
      end
      for _, body in ipairs(CONSTELLATIONS) do
        -- Match on the last word of the body name (e.g. "Forge" for "Maelshyve's Forge")
        local last_word = body.name:match("([^%s]+)$") or body.name
        if Regex.test("(?i)\\b" .. last_word .. "\\b", line)
           and not line:find("below the horizon", 1, true) then
          if body.circle <= circle then
            result[#result + 1] = body
          end
          break
        end
      end
      if line:lower():find("roundtime") then done = true end
    end
  end

  return result
end

--- Pick and observe the best available celestial body.
-- Handles telescope candidate selection (most pools, highest circle first),
-- bad-search flag handling, injuries, and fallback to naked-eye.
local function check_heavens(settings, telescope_name, telescope_storage, equipment_manager)
  empty_hands(telescope_name, telescope_storage, equipment_manager)

  local vis = visible_bodies()
  if not vis then
    Messaging.msg("bold", "Astrology: Could not observe visible bodies. Aborting.")
    return
  end

  -- night = any constellation is visible (allows constellation-only telescope targets)
  local night = false
  for _, body in ipairs(vis) do
    if body.constellation then night = true; break end
  end

  -- Select the best naked-eye body: consider all visible bodies (telescope-required
  -- ones included only if we have a telescope), rank by pool count then circle.
  local best_eye = nil
  for _, data in ipairs(vis) do
    if settings.have_telescope or not data.telescope then
      if not best_eye
         or pool_size(data.pools) > pool_size(best_eye.pools)
         or (pool_size(data.pools) == pool_size(best_eye.pools) and data.circle > best_eye.circle) then
        best_eye = data
      end
    end
  end

  if not best_eye then
    Messaging.msg("bold", "Astrology: No observable celestial bodies found. Aborting.")
    return
  end

  debug("best_eye = " .. best_eye.name)
  waitrt()

  if settings.have_telescope then
    -- Build candidate list: telescope bodies superior to best_eye, plus best_eye as fallback.
    local circle = DRStats.circle or 0
    local candidates = {}

    for _, data in ipairs(CONSTELLATIONS) do
      if data.telescope
         and data.circle <= circle
         and data.circle > best_eye.circle
         and (night or not data.constellation)
         and pool_size(data.pools) > pool_size(best_eye.pools) then
        candidates[#candidates + 1] = data
      end
    end
    candidates[#candidates + 1] = best_eye

    -- Sort descending by circle — try the most advanced body first
    table.sort(candidates, function(a, b) return a.circle > b.circle end)

    debug("telescope candidates: " .. #candidates)

    DRCMM.get_telescope(telescope_name, telescope_storage)

    local found_success = false
    for _, data in ipairs(candidates) do
      if found_success then break end

      local finished = false
      local peer_result = nil

      while not finished do
        local bad = Flags["bad-search"]
        if bad == "is foiled by the daylight" then
          -- Body not visible in daylight — restart with fresh sky check
          DRCMM.store_telescope(telescope_name, telescope_storage)
          check_heavens(settings, telescope_name, telescope_storage, equipment_manager)
          return
        end
        if bad == "turns up fruitless" then
          -- Fruitless search — retry the same body
          Flags.reset("bad-search")
          -- continue the while loop
        else
          peer_result = observe_routine(
            data.name, settings, telescope_name, telescope_storage, equipment_manager)
          debug("observe result: " .. tostring(peer_result))
          finished = observation_finished(type(peer_result) == "string" and peer_result or "")
        end
      end

      if observation_success(type(peer_result) == "string" and peer_result or "") then
        found_success = true
      end
    end

    DRCMM.store_telescope(telescope_name, telescope_storage)
  else
    -- Naked-eye only
    local done = false
    while not done do
      if Flags["bad-search"] then
        Flags.reset("bad-search")
        check_heavens(settings, telescope_name, telescope_storage, equipment_manager)
        return
      end
      local r = observe_routine(best_eye.name, settings, telescope_name, telescope_storage, equipment_manager)
      done = (r == true)
    end
  end

  pause(2)
  waitrt()
end

-------------------------------------------------------------------------------
-- Prediction / pools
-------------------------------------------------------------------------------

--- Read all pool levels from "predict state all".
local function check_pools()
  local pools = {
    ["lore"]             = 0,
    ["magic"]            = 0,
    ["survival"]         = 0,
    ["offensive combat"] = 0,
    ["defensive combat"] = 0,
    ["future events"]    = 0,
  }

  local lines = issue_command(
    "predict state all",
    "celestial influences",
    "(?i)roundtime",
    10
  )

  if not lines then
    Messaging.msg("bold", "Astrology: Failed to capture predict state output. Using defaults.")
    waitrt()
    return pools
  end

  for pool_name in pairs(pools) do
    for _, line in ipairs(lines) do
      if line:find(pool_name, 1, true) then
        for _, entry in ipairs(POOL_PATTERNS) do
          if line:find(entry.pattern, 1, true) then
            pools[pool_name] = entry.value
            break
          end
        end
        break
      end
    end
  end

  if UserVars["astrology_debug"] then
    for k, v in pairs(pools) do debug("pools[" .. k .. "] = " .. v) end
  end

  waitrt()
  return pools
end

--- Study sky to fill the future-events pool, then predict an event.
local function check_events(pools)
  waitrt()
  local prev_size = pools["future events"]
  local deadline  = os.time() + 10

  while os.time() < deadline do
    local result = DRCMM.study_sky()
    waitrt()
    if result:find("You are unable to sense additional", 1, true)
    or result:find("detect any portents", 1, true) then
      break
    end
    local new_pools = check_pools()
    if new_pools["future events"] == prev_size or new_pools["future events"] == 10 then
      break
    end
    prev_size = new_pools["future events"]
  end

  DRCMM.predict("event")
end

--- Align then predict/roll/read for the given skill pool.
-- Dispatches to divination bones, divination tool, or predict future
-- based on settings configuration.
local function align_routine(skill, settings)
  debug("align_routine skill=" .. tostring(skill))
  if skill == "future events" then
    DRCMM.predict("event")
    return
  end

  DRCMM.align(skill)
  waitrt()

  local bones   = settings.divination_bones_storage
  local div     = settings.divination_tool
  local force   = settings.astrology_force_visions

  if bones and type(bones) == "table" and next(bones) and not force then
    DRCMM.roll_bones(bones)
  elseif div and div.name and not force then
    DRCMM.use_div_tool(div)
  else
    DRCMM.predict("future")
  end

  waitrt()
  pause(1)
  while GameState.stunned do pause(0.5) end
  DRC.fix_standing()
end

--- Run predictions for all pools at or above the configured target.
local function predict_all(pools, settings)
  local target      = settings.astrology_use_full_pools and 10 or settings.astrology_pool_target
  local pred_skills = settings.astrology_prediction_skills

  local pool_to_skill = {
    ["offensive combat"] = pred_skills.offense  or "offensive combat",
    ["defensive combat"] = pred_skills.defense  or "defensive combat",
    ["magic"]            = pred_skills.magic    or "magic",
    ["survival"]         = pred_skills.survival or "survival",
    ["lore"]             = pred_skills.lore     or "lore",
    ["future events"]    = "future events",
  }

  for pool_name, pool_level in pairs(pools) do
    if pool_level >= target then
      if DRSkill.getxp("Astrology") > XP_SKIP then break end
      align_routine(pool_to_skill[pool_name], settings)
    end
  end
end

-------------------------------------------------------------------------------
-- Attunement
-------------------------------------------------------------------------------

--- Perceive all attunement targets to train Attunement, if XP permits.
local function check_attunement()
  if DRSkill.getxp("Attunement") > XP_SKIP then return end
  for _, target in ipairs(PERCEIVE_TARGETS) do
    local cmd = (target == "") and "perceive" or ("perceive " .. target)
    DRC.bput(cmd, "roundtime", "Roundtime")
    waitrt()
  end
end

--- Predict weather.
local function check_weather()
  debug("Checking the weather.")
  DRCMM.predict("weather")
  waitrt()
end

-------------------------------------------------------------------------------
-- Astral plane
-------------------------------------------------------------------------------

--- Travel to the astral plane destination and back for training.
local function check_astral(settings)
  if (DRStats.circle or 0) <= 99 then return end

  local src  = settings.astral_plane_training.train_source
  local dest = settings.astral_plane_training.train_destination
  if not src or not dest then
    debug("No astral_plane_training configured. Skipping.")
    return
  end

  local timer = tonumber(UserVars["astral_plane_exp_timer"])
  if timer and (os.time() - timer) < 3600 then
    debug("Astral plane training on cooldown. Skipping.")
    return
  end

  DRC.wait_for_script_to_complete("bescort", { "ways", dest })
  UserVars["astral_plane_exp_timer"] = tostring(os.time())
  DRC.wait_for_script_to_complete("bescort", { "ways", src })
  respond("Astrology: Completed astral plane training.")
end

-------------------------------------------------------------------------------
-- Buff management
-------------------------------------------------------------------------------

--- Cast waggle-set buffs for the astrology session.
-- Extracts Read the Ripples data for the RtR routine and returns it.
-- @return table|nil rtr_data (RtR spell config, or nil if not configured)
local function do_buffs(settings, telescope_name, telescope_storage, equipment_manager)
  local waggle_set = settings.waggle_sets[settings.waggle_set_name]
  if not waggle_set then return nil end

  empty_hands(telescope_name, telescope_storage, equipment_manager)

  -- Split RtR from other buffs
  local rtr_data = waggle_set["Read the Ripples"]
  local buffs    = {}
  for name, data in pairs(waggle_set) do
    if name ~= "Read the Ripples" then buffs[name] = data end
  end

  -- Short-circuit if all auto-mana buffs are already active
  -- (waggle_sets keys ARE the spell names)
  local active     = DRSpells.active_spells()
  local all_active = true
  for name, data in pairs(buffs) do
    if data.use_auto_mana and not (active and active[name]) then
      all_active = false; break
    end
  end
  if all_active then
    debug("All buffs already active.")
    return rtr_data
  end

  -- Discern mana costs for auto-mana spells that haven't been discerned recently
  for _, data in pairs(buffs) do
    if data.use_auto_mana then
      DRCA.check_discern(data, settings)
    end
  end

  -- Remove spells already active
  active = DRSpells.active_spells()
  local to_cast = {}
  for name, data in pairs(buffs) do
    if not (active and active[name]) then to_cast[name] = data end
  end

  if next(to_cast) then
    DRCA.cast_spells(to_cast, settings)
  end

  return rtr_data
end

-------------------------------------------------------------------------------
-- Read the Ripples
-------------------------------------------------------------------------------

--- Read the Ripples observation loop.
-- Casts RtR, then observes each body as consciousness drifts to it.
-- Continues until RtR expires.
local function check_ripples(settings, rtr_data, telescope_name, telescope_storage, equipment_manager)
  if not rtr_data then
    Messaging.msg("bold", "Astrology: No Read the Ripples spell data configured. Skipping.")
    return
  end

  -- If the rtr-expire flag has already fired (matched), the spell recently faded;
  -- skip re-cast for this cycle to let the spell recover.
  -- Flags["key"] returns the matched line and clears to nil; a non-nil return here
  -- means it just triggered, so consume the match and bail.
  if Flags["rtr-expire"] ~= nil then
    debug("RtR expire flag fired — spell recently expired. Skipping.")
    return
  end

  empty_hands(telescope_name, telescope_storage, equipment_manager)
  DRCA.cast_spell(rtr_data, settings)

  -- Register expire-detection flag for the RtR spell
  Flags.add("rtr-expire",
    "Read the Ripples spell fades",
    "your concentration on Read the Ripples")

  if settings.have_telescope and rtr_active() then
    DRCMM.get_telescope(telescope_name, telescope_storage)
  end

  local perc_time = os.time() - 61

  while rtr_active() do
    local line = get_noblock()
    if line then
      -- Perceive mana every 60s to maintain awareness
      if os.time() - perc_time >= 60 then
        DRCA.perceive_mana()
        perc_time = os.time()
      end

      -- Look for consciousness drifting to a constellation
      for _, body in ipairs(CONSTELLATIONS) do
        local last_word = body.name:match("([^%s]+)$") or body.name
        if Regex.test(
          "(?i)As your consciousness drifts amongst the currents of Fate.*" .. last_word,
          line) then
          observe_routine(body.name, settings, telescope_name, telescope_storage, equipment_manager)
          break
        end
      end
    else
      pause(0.05)
    end
  end

  if settings.have_telescope then
    DRCMM.store_telescope(telescope_name, telescope_storage)
  end
end

-------------------------------------------------------------------------------
-- Main training loop
-------------------------------------------------------------------------------

local function train_astrology(settings, rtr_data, telescope_name, telescope_storage, equipment_manager)
  local training = settings.astrology_training
  if type(training) ~= "table" or #training == 0 then
    Messaging.msg("bold", "Astrology: astrology_training is empty or not configured. Exiting.")
    return
  end

  while true do
    for _, task in ipairs(training) do
      if DRSkill.getxp("Astrology") >= XP_DONE then break end

      if     task == "ways"       then check_astral(settings)
      elseif task == "observe"    then check_heavens(settings, telescope_name, telescope_storage, equipment_manager)
      elseif task == "rtr"        then check_ripples(settings, rtr_data, telescope_name, telescope_storage, equipment_manager)
      elseif task == "weather"    then check_weather()
      elseif task == "events"     then check_events(check_pools())
      elseif task == "attunement" then check_attunement()
      else
        Messaging.msg("bold", "Astrology: Unknown training task '" .. task .. "'. Skipping.")
      end
    end

    if DRSkill.getxp("Astrology") >= XP_DONE then
      respond("Astrology: Reached target XP. Training complete.")
      break
    end

    predict_all(check_pools(), settings)
    DRCMM.predict("analyze")
    waitrt()
  end
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------

-- Guild guard
if not DRStats.moon_mage() then
  Messaging.msg("bold", "Astrology: This script is only for Moon Mages. Exiting.")
  Script.exit()
end

-- Force circle refresh for brand-new guild members
if (DRStats.circle or 0) == 0 then
  DRC.bput("info", "Circle:")
end

-- Parse args
local parsed  = Args.parse(Script.vars[0] or "")
local mode_rtr = (parsed.args[1] or ""):lower() == "rtr"

-- Load settings and create equipment manager
local settings          = get_settings()
local equipment_manager = DREMgr.EquipmentManager(settings)
local telescope_name    = settings.telescope_name
local telescope_storage = settings.telescope_storage

-- Cleanup handler
Script.at_exit(function()
  Flags.remove("bad-search")
  Flags.remove("rtr-expire")
  if telescope_name and DRCI.in_hands(telescope_name) then
    DRCMM.store_telescope(telescope_name, telescope_storage)
  end
  local div = settings.divination_tool
  if div and div.name and DRCI.in_hands(div.name) then
    DRCMM.store_div_tool(div)
  end
end)

debug("Flags['rtr-expire'] = " .. tostring(Flags["rtr-expire"]))

-- Cast buffs and extract RtR data
local rtr_data = do_buffs(settings, telescope_name, telescope_storage, equipment_manager)

-- Run
if mode_rtr then
  check_ripples(settings, rtr_data, telescope_name, telescope_storage, equipment_manager)
else
  train_astrology(settings, rtr_data, telescope_name, telescope_storage, equipment_manager)
end
