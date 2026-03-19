--- @revenant-script
--- name: plantheal
--- version: 2.0.0
--- author: unknown (lich_repo_mirror original); community contributors (dr-scripts)
--- game: dr
--- description: Empath plant healing trainer - hug vela'tohr plant to transfer wounds, heal self, train Empathy
--- tags: empath, healing, empathy, training, vela'tohr
--- @lic-certified: complete 2026-03-18
---
--- Ported from plantheal.lic (dr-scripts community version) to Revenant Lua.
--- Changelog preserved from original: legacy flat settings migrated to plantheal_settings block;
--- waggle healing path (Heal+AC) added; hug command replaces touch; cast_room community EV added;
--- manual EV prep with backfire retry added; per-hug wound check and passive healing added.
---
--- YAML Settings (nested under plantheal_settings):
---   hug_count: 3                  # total hugs before exiting (default 3)
---   plant_room: <room_id>         # room with the plant (default: hometown NPC empath room)
---   healing_room: <room_id>       # room to heal in (default: safe_room)
---   prep_room: <room_id>          # room to prep EV separately from plant_room (0 = same)
---   cast_room: <room_id>          # room to cast community EV before exit (0 = skip)
---   empathy_threshold: 24         # stop when Empathy learning mindstate >= this value
---   heal_past_ml: false           # if true, keep cycling past threshold until plant is fully healed
---   ev_cast_mana: 600             # mana for community EV cast in cast_room
---   ev_extra_wait: 15             # extra seconds to wait after RT before casting EV
---   focus_container: null         # container to get/stow focus from (e.g. "backpack")
---
--- Required waggle_sets:
---   plantheal: Must contain "Embrace of the Vela'Tohr" spell entry.
---              If you know Heal + Adaptive Curing, must also contain Heal or Regenerate.
---
--- Legacy flat settings supported with deprecation warnings:
---   plant_total_touch_count -> hug_count
---   plant_custom_room       -> plant_room
---   plant_drop_room         -> plant_room
---   plant_healing_room      -> healing_room
---   plant_prep_room         -> prep_room
---   plant_heal_past_ML      -> heal_past_ml
---   plant_empathy_threshold -> empathy_threshold
---   cast_room               -> cast_room
---   ritual_ev_mana          -> ev_cast_mana
---   ritual_ev_extra_wait    -> ev_extra_wait
---   ritual_focus_container  -> focus_container

-- ---------------------------------------------------------------------------
-- Guard: Empaths only
-- ---------------------------------------------------------------------------

if not DRStats.empath() then
  DRC.message("**EXIT: Must be an Empath with the Embrace of the Vela'Tohr spell to run this!**")
  return
end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local EV_SPELL_KEY           = "Embrace of the Vela'Tohr"
local PASSIVE_HEAL_POLL_INTERVAL = 5
local PASSIVE_HEAL_MAX_WAIT  = 120
local MAX_BACKFIRE_RETRIES   = 2
local MAX_HUG_RETRIES        = 3

-- ---------------------------------------------------------------------------
-- Settings loading with legacy migration
-- ---------------------------------------------------------------------------

local function to_bool(val, default)
  if val == nil then return default end
  local s = tostring(val):match("^%s*(.-)%s*$"):lower()
  return s == "true" or s == "1" or s == "yes" or s == "y"
end

local function safe_setting(settings, key)
  local ok, val = pcall(function() return settings[key] end)
  if ok then return val end
  return nil
end

local function load_settings(settings)
  local ps = {}
  if settings.plantheal_settings then
    for k, v in pairs(settings.plantheal_settings) do
      ps[k] = v
    end
  end

  -- Legacy migration table: old_key -> new_key
  local migrate = {
    { "plant_total_touch_count", "hug_count"      },
    { "plant_custom_room",       "plant_room"     },
    { "plant_drop_room",         "plant_room"     },
    { "plant_healing_room",      "healing_room"   },
    { "plant_prep_room",         "prep_room"      },
    { "plant_heal_past_ML",      "heal_past_ml"   },
    { "plant_empathy_threshold", "empathy_threshold" },
    { "cast_room",               "cast_room"      },
    { "ritual_ev_mana",          "ev_cast_mana"   },
    { "ritual_ev_extra_wait",    "ev_extra_wait"  },
    { "ritual_focus_container",  "focus_container"},
  }

  for _, pair in ipairs(migrate) do
    local old_key, new_key = pair[1], pair[2]
    local old_val = safe_setting(settings, old_key)
    if old_val ~= nil and ps[new_key] == nil then
      DRC.message("*** Deprecated setting '" .. old_key .. "' -- migrate to plantheal_settings." .. new_key)
      ps[new_key] = old_val
    end
  end

  -- Apply defaults and type coercion
  return {
    hug_count         = tonumber(ps["hug_count"])         or 3,
    plant_room        = tonumber(ps["plant_room"])        or 0,
    healing_room      = tonumber(ps["healing_room"])      or 0,
    prep_room         = tonumber(ps["prep_room"])         or 0,
    cast_room         = tonumber(ps["cast_room"])         or 0,
    empathy_threshold = tonumber(ps["empathy_threshold"]) or 24,
    heal_past_ml      = to_bool(ps["heal_past_ml"], false),
    ev_cast_mana      = tonumber(ps["ev_cast_mana"])      or 600,
    ev_extra_wait     = tonumber(ps["ev_extra_wait"])     or 15,
    focus_container   = (ps["focus_container"] or ""):match("^%s*(.-)%s*$"),
  }
end

-- ---------------------------------------------------------------------------
-- Resolve configuration
-- ---------------------------------------------------------------------------

local settings = get_settings()
local ps = load_settings(settings)

-- Resolve plant room
local plantroom = ps.plant_room
if plantroom == 0 then
  local town_data = get_data("town")
  local ht = safe_setting(settings, "force_healer_town") or safe_setting(settings, "hometown")
  if ht and town_data and town_data[ht] and town_data[ht]["npc_empath"] then
    plantroom = tonumber(town_data[ht]["npc_empath"]["id"]) or 0
  end
  if plantroom == 0 then
    DRC.message("**EXIT: Can't resolve plant room. Set plantheal_settings.plant_room.**")
    return
  end
end

-- Resolve healing room
local healingroom = ps.healing_room
if healingroom == 0 then
  healingroom = tonumber(safe_setting(settings, "safe_room")) or 0
end

local preproom      = ps.prep_room
local castroom      = ps.cast_room
local hug_count     = ps.hug_count
local heal_past_ml  = ps.heal_past_ml
local threshold     = ps.empathy_threshold
local ev_cast_mana  = ps.ev_cast_mana
local ev_extra_wait = ps.ev_extra_wait
local focus_container = ps.focus_container

-- Waggle set
local waggle = safe_setting(settings, "waggle_sets") or {}
local ev_waggle = waggle["plantheal"]

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

local function validate_ev_waggle()
  if not ev_waggle then
    DRC.message("**EXIT: waggle_set 'plantheal' is required! Define a 'plantheal' waggle_set with an '" .. EV_SPELL_KEY .. "' entry.**")
    return false
  end
  if not ev_waggle[EV_SPELL_KEY] then
    local keys = {}
    for k, _ in pairs(ev_waggle) do keys[#keys + 1] = k end
    DRC.message("**EXIT: waggle_set 'plantheal' must contain an '" .. EV_SPELL_KEY .. "' spell entry!**")
    DRC.message("   Found keys: " .. table.concat(keys, ", "))
    return false
  end
  return true
end

-- Determine healing strategy and validate spell config.
-- Returns waggle_healing boolean (true = use Heal/Regenerate waggle, false = use healme).
local function validate_healing_spells()
  local waggle_healing = DRSpells.known_p("Heal") and DRSpells.known_p("Adaptive Curing")

  if waggle_healing then
    if not (ev_waggle["Heal"] or ev_waggle["Regenerate"]) then
      DRC.message("**EXIT: You know Heal+AC but neither Heal nor Regenerate is in your plantheal waggle_set!**")
      DRC.message("   Add a Heal or Regenerate entry to waggle_sets.plantheal so the script can keep healing spells active.")
      return nil  -- signal fatal error
    end
  else
    if not DRSpells.known_p("Heal Wounds") then
      DRC.message("**WARNING: You don't know Heal Wounds (HW)!** healme may not work properly.")
    end
    if not DRSpells.known_p("Heal Scars") then
      DRC.message("**WARNING: You don't know Heal Scars (HS)!** healme may not work properly.")
    end
  end

  return waggle_healing
end

if not validate_ev_waggle() then return end
local waggle_healing = validate_healing_spells()
if waggle_healing == nil then return end

-- ---------------------------------------------------------------------------
-- Focus configuration (from plantheal waggle_set EV entry)
-- ---------------------------------------------------------------------------

local ev_spell_data = ev_waggle[EV_SPELL_KEY] or {}
local focus_item     = (ev_spell_data["focus"]         or ""):match("^%s*(.-)%s*$")
local focus_worn     = ev_spell_data["worn_focus"]   or false
local focus_tied     = (ev_spell_data["tied_focus"]    or ""):match("^%s*(.-)%s*$")
local focus_sheathed = ev_spell_data["sheathed_focus"] or false
local focus_invoke   = (focus_item ~= "") and ("invoke my " .. focus_item) or ""

-- Manual EV casting is required when a separate prep_room is set
-- (buff script can't switch rooms mid-cast).
local manual_ev = (preproom ~= 0)

-- Running hug total
local total_hugs = 0

-- ---------------------------------------------------------------------------
-- Display mode message
-- ---------------------------------------------------------------------------

local function display_mode_message()
  if waggle_healing then
    DRC.message("** Healing via Heal/Regenerate (waggle) — healme will not be used. **")
  else
    DRC.message("** Healing via healme script (HW/HS). **")
  end

  if heal_past_ml then
    DRC.message("** heal_past_ml is ON **")
    DRC.message("   Will cycle until the plant is FULLY HEALED (ignoring hug_count and threshold).")
    DRC.message("   To stop at a threshold, set heal_past_ml: false and configure empathy_threshold.")
    DRC.message("   To stop after N hugs, set heal_past_ml: false and configure hug_count.")
  else
    DRC.message("Will stop at FIRST of: " .. hug_count .. " total hugs OR empathy mindstate " .. threshold .. ".")
  end
end

display_mode_message()

-- ---------------------------------------------------------------------------
-- Focus management helpers
-- ---------------------------------------------------------------------------

local function do_get_focus()
  if focus_item == "" then return end
  if focus_worn or (focus_tied ~= "") or focus_sheathed then
    DRCA.find_focus(focus_item, focus_worn,
                    focus_tied ~= "" and focus_tied or nil,
                    focus_sheathed)
  elseif focus_container ~= "" then
    DRC.bput("get " .. focus_item .. " from " .. focus_container,
             "You get", "You are already holding", "What were you referring")
  else
    DRCA.find_focus(focus_item, false, nil, false)
  end
end

local function do_invoke_focus()
  if focus_item == "" or focus_invoke == "" then return end
  local result = DRC.bput(focus_invoke,
    "Roundtime", "You focus your will", "You begin attuning",
    "is already prepared", "need a ritual focus",
    "You must be holding", "You are not holding", "Invoke what?")
  if result:find("need a ritual focus") or result:find("must be holding") or
     result:find("are not holding") or result:find("Invoke what?") then
    do_get_focus()
    DRC.bput(focus_invoke,
             "Roundtime", "You focus your will", "You begin attuning", "is already prepared")
  end
end

local function do_stow_focus()
  if focus_item == "" then return end
  if focus_worn or (focus_tied ~= "") or focus_sheathed then
    DRCA.stow_focus(focus_item, focus_worn,
                    focus_tied ~= "" and focus_tied or nil,
                    focus_sheathed)
  elseif focus_container ~= "" then
    fput("stow " .. focus_item .. " in " .. focus_container)
  else
    DRCA.stow_focus(focus_item, false, nil, false)
  end
end

-- ---------------------------------------------------------------------------
-- Manual EV casting
-- ---------------------------------------------------------------------------

local function cast_ev_manual(mana)
  local attempts = 0
  while true do
    -- Walk to prep room if configured (saving plantroom as return target)
    local origin = nil
    if preproom ~= 0 then
      origin = plantroom
      DRCT.walk_to(preproom)
    end

    do_get_focus()
    DRCA.prepare("EV", mana)
    do_invoke_focus()
    waitrt()
    pause(ev_extra_wait)
    do_stow_focus()

    -- Walk back to cast in plant room if we prepped elsewhere
    if origin then
      DRCT.walk_to(origin)
    end

    local result = DRC.bput("cast",
      "You gesture",
      "You strain, but are too mentally fatigued",
      "You aren't harnessing any mana",
      "You lose your concentration",
      "backfires",
      "Roundtime")
    waitrt()

    if result:find("backfires") then
      attempts = attempts + 1
      if attempts > MAX_BACKFIRE_RETRIES then
        DRC.message("**EV backfired " .. attempts .. " times -- giving up.**")
        return false
      end
      DRC.message("**EV backfired** (attempt " .. attempts .. "/" .. (MAX_BACKFIRE_RETRIES + 1) .. "). Re-preparing...")
      pause(1)
    else
      pause(3)
      return result:find("You gesture") ~= nil or result:find("Roundtime") ~= nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Plant finding
-- ---------------------------------------------------------------------------

local function refresh_room_objs()
  fput("look")
  pause(0.5)
end

local PLANT_NOUNS_RE = Regex.new("vela'tohr (plant|thicket|bush|briar|shrub|thornbush)")

local function plant_noun_in_room()
  local objs = DRRoom.room_objs
  if not objs then return nil end
  for _, obj in ipairs(objs) do
    local caps = PLANT_NOUNS_RE:captures(obj)
    if caps then
      return caps[1]:lower()
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- EV management
-- ---------------------------------------------------------------------------

local function ensure_ev()
  if DRSpells.active_spells()[EV_SPELL_KEY] ~= nil then return end
  if manual_ev then
    cast_ev_manual(tonumber(ev_spell_data["mana"]) or 0)
  else
    DRC.wait_for_script_to_complete("buff", {"plantheal"})
  end
end

local function release_and_recast_ev()
  fput("release ev")
  pause(1)
  -- Force active spell list refresh via perceive self
  fput("perceive self")
  waitrt()
  pause(1)
  -- Bypass ensure_ev's active-check since we just released
  if manual_ev then
    cast_ev_manual(tonumber(ev_spell_data["mana"]) or 0)
  else
    DRC.wait_for_script_to_complete("buff", {"plantheal"})
  end
end

local function recast_ev_if_needed()
  local recast = tonumber(ev_spell_data["recast"])
  if not recast then return end
  local remaining = tonumber(DRSpells.active_spells()[EV_SPELL_KEY]) or 0
  if remaining > recast then return end
  if manual_ev then
    cast_ev_manual(tonumber(ev_spell_data["mana"]) or 0)
  else
    DRC.wait_for_script_to_complete("buff", {"plantheal"})
  end
end

-- ---------------------------------------------------------------------------
-- Healing helpers
-- ---------------------------------------------------------------------------

local function do_bleeding()
  return DRCH.check_health():bleeding()
end

local function ensure_healing_spells()
  if not waggle_healing then return end
  local active = DRSpells.active_spells()
  if active["Heal"] ~= nil or active["Regenerate"] ~= nil then return end
  DRC.wait_for_script_to_complete("buff", {"plantheal"})
end

local function wait_for_passive_healing()
  local elapsed = 0
  while DRCH.check_health().score > 0 do
    if elapsed >= PASSIVE_HEAL_MAX_WAIT then
      DRC.message("**WARNING: Still wounded after " .. PASSIVE_HEAL_MAX_WAIT .. "s of passive healing.** Running healme as fallback.")
      DRCT.walk_to(healingroom)
      DRC.wait_for_script_to_complete("healme")
      return
    end
    pause(PASSIVE_HEAL_POLL_INTERVAL)
    elapsed = elapsed + PASSIVE_HEAL_POLL_INTERVAL
  end
end

local function heal_now()
  if waggle_healing then
    ensure_healing_spells()
    wait_for_passive_healing()
  else
    DRCT.walk_to(healingroom)
    DRC.wait_for_script_to_complete("healme")
  end
end

local function heal_between_hugs()
  DRC.message("**Wounds detected** (score: " .. DRCH.check_health().score .. "), healing before next hug.")
  if waggle_healing then
    ensure_healing_spells()
    wait_for_passive_healing()
  else
    DRCT.walk_to(healingroom)
    DRC.wait_for_script_to_complete("healme")
    DRCT.walk_to(plantroom)
  end
end

-- ---------------------------------------------------------------------------
-- Exit condition check
-- ---------------------------------------------------------------------------

-- Perform community EV cast in cast_room if configured, then exit.
local function cast_for_others()
  if castroom == 0 then return end
  DRCT.walk_to(castroom)
  cast_ev_manual(ev_cast_mana)
  DRC.message("**EXIT: Cast community EV in cast_room.**")
end

-- Returns true if the script should stop.
local function check_exit_conditions()
  if heal_past_ml then return false end

  if total_hugs >= hug_count then
    cast_for_others()
    DRC.message("**EXIT: Total hug count reached (" .. total_hugs .. "/" .. hug_count .. ").**")
    return true
  end

  local current_xp = DRSkill.getxp("Empathy") or 0
  if current_xp >= threshold then
    cast_for_others()
    DRC.message("**EXIT: Empathy mindstate " .. current_xp .. " already at or above threshold (" .. threshold .. ").**")
    return true
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Pre-hug check
-- ---------------------------------------------------------------------------

-- Returns plant noun (truthy) if safe to hug, or false/nil to stop.
local function pre_hug_check()
  if do_bleeding() then
    DRC.message("**Bleeding detected**, stopping hugs to go heal.")
    return false
  end

  if not heal_past_ml then
    if total_hugs >= hug_count then
      DRC.message("**Total hug count reached** (" .. hug_count .. "), stopping hugs.")
      return false
    end
    if (DRSkill.getxp("Empathy") or 0) >= threshold then
      DRC.message("**Empathy threshold reached** (" .. threshold .. "), stopping hugs.")
      return false
    end
  end

  -- Heal to full before each hug
  if DRCH.check_health().score > 0 then
    heal_between_hugs()
  end

  ensure_ev()
  ensure_healing_spells()

  -- Refresh room objects after ensure_ev (EV cast may have updated plant state)
  refresh_room_objs()

  local noun = plant_noun_in_room()
  if not noun then
    DRC.message("**Plant disappeared** from room during cycle.")
    return false
  end
  return noun
end

-- ---------------------------------------------------------------------------
-- Hug plant once
-- ---------------------------------------------------------------------------

-- Returns: hugs (0 or 1), reason ("ok"|"no_plant"|"fully_healed"|"stopped_early")
local function hug_plant_once(retries)
  if retries == nil then retries = MAX_HUG_RETRIES end
  if retries <= 0 then
    DRC.message("**Max hug retries reached** — stopping to prevent infinite loop.")
    return 0, "stopped_early"
  end

  -- Resolve plant noun from room objects
  local noun = plant_noun_in_room()

  if not noun then
    -- If EV is active, try a LOOK refresh before assuming plant is missing
    if DRSpells.active_spells()[EV_SPELL_KEY] ~= nil then
      DRC.message("Plant not visible in room objects — refreshing with LOOK...")
      fput("look")
      pause(0.5)
      noun = plant_noun_in_room()
    end

    if not noun then
      DRC.message("*** No plant found in room! Re-casting EV.")
      release_and_recast_ev()
      noun = plant_noun_in_room()
      if not noun then
        DRC.message("*** Still no plant. Skipping to heal phase.")
        return 0, "no_plant"
      end
    end
  end

  -- Pre-hug check: bleeding, limits, wounds, EV, healing spells, plant noun
  noun = pre_hug_check()
  if not noun then
    DRC.message("pre_hug_check state: bleeding=" .. tostring(do_bleeding()) ..
                " hugs=" .. total_hugs .. "/" .. hug_count ..
                " empathy=" .. (DRSkill.getxp("Empathy") or 0) .. "/" .. threshold ..
                " plant=" .. tostring(plant_noun_in_room()))
    return 0, "stopped_early"
  end

  local result = DRC.bput("hug " .. noun,
    "Roundtime",
    "has no need of healing",
    "you have no empathic bond",
    "Hug what?",
    "appreciates the sentiment")

  if result:find("has no need of healing") then
    DRC.message("**Plant fully healed.**")
    return 0, "fully_healed"

  elseif result:find("you have no empathic bond") then
    DRC.message("Lost empathic bond — releasing and recasting EV.")
    release_and_recast_ev()
    return hug_plant_once(retries - 1)

  elseif result:find("appreciates the sentiment") then
    DRC.message("Hug returned 'appreciates the sentiment' — **releasing and recasting EV**.")
    release_and_recast_ev()
    return hug_plant_once(retries - 1)

  elseif result:find("Hug what?") then
    -- Stale noun despite pre_hug_check — rare race condition
    recast_ev_if_needed()
    return 0, "stopped_early"

  elseif result:find("Roundtime") then
    waitrt()
    total_hugs = total_hugs + 1
    DRC.message("Hug " .. total_hugs .. "/" .. hug_count .. " complete.")
    return 1, "ok"

  else
    DRC.message("**Unexpected hug response:** " .. result)
    return 0, "stopped_early"
  end
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------

DRCI.stow_hands()

Flags.add("heal-expire", "You feel the warmth in your flesh gradually subside.")

before_dying(function()
  Flags.delete("heal-expire")
end)

while true do
  -- Check exit conditions at the top of each cycle
  if check_exit_conditions() then break end

  -- Ensure we start each cycle with no wounds
  if DRCH.check_health().score > 0 then
    DRC.message("Wounds detected, healing before next cycle.")
    heal_now()
  end

  -- Walk to plant room
  DRCT.walk_to(plantroom)

  -- Hug the plant once
  local hugs, reason = hug_plant_once()

  -- Always heal after hugging
  heal_now()

  -- If zero hugs, exit with context-specific message
  if hugs == 0 then
    if reason == "no_plant" then
      DRC.message("**No plant found in room after EV recast.** Check your plant_room setting or cast EV manually.")
    elseif reason == "fully_healed" then
      DRC.message("**Plant fully healed** — no wounds to transfer. Cast a new EV or wait for plant to accumulate wounds.")
    elseif reason == "stopped_early" then
      DRC.message("**Stopped before hugging** (bleeding, threshold, hug_count, or plant disappeared). Check logs above for details.")
    else
      DRC.message("**No wounds transferred.** Exiting after health check.")
    end
    break
  end

  -- Check exit conditions again after healing
  if check_exit_conditions() then break end
end
