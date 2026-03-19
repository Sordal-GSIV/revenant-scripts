--- @revenant-script
--- name: pick_setup
--- version: 2.0.0
--- author: Seped
--- game: dr
--- description: Configure CharSettings for the pick script (lockpicking automation).
--- tags: locksmithing, setup, configuration
--- Ported from pick-setup.lic (Lich5/dr-scripts)
---
--- Run this once to configure your character's lockpicking settings.
--- Edit the values below for your character, then run: ;pick_setup

-- ============================================================
-- REQUIRED: Box source(s)
-- ============================================================

-- Single source container (backpack, bag, sack, etc.)
CharSettings.set("picking_box_source", "backpack")

-- OR multiple sources (comment out the above and uncomment below):
-- CharSettings.set("pick", {
--   picking_box_sources = {"backpack", "sack"},
-- })

-- ============================================================
-- LOCKPICK SETTINGS
-- ============================================================

CharSettings.set("use_lockpick_ring", true)
CharSettings.set("lockpick_container", "lockpick ring")
CharSettings.set("lockpick_type", "ordinary")   -- ordinary, stout, slim
CharSettings.set("refill_town", "Crossing")      -- Crossing, Riverhaven, Shard, Ain Ghazal, Hibarnhvidar, Muspar'i
CharSettings.set("skip_lockpick_ring_refill", false)

-- ============================================================
-- PICKING BEHAVIOR
-- ============================================================

CharSettings.set("stop_pick_on_mindlock", false) -- stop at locksmithing mindlock
CharSettings.set("harvest_traps", false)          -- analyze and harvest trap components
CharSettings.set("component_container", nil)      -- where to put trap parts (nil = dispose)
CharSettings.set("lockpick_dismantle", "")        -- dismantle type suffix (blank = default)
CharSettings.set("trash_empty_boxes", false)      -- true = trash boxes after looting; false = dismantle

-- Armor/gear to remove before picking (list of item names)
-- These are worn items that hinder lockpicking
CharSettings.set("lockpicking_armor", {})  -- e.g. {"balaclava", "leathers", "targe"}

-- ============================================================
-- DIFFICULTY THRESHOLDS
-- Difficulty is 0-16 (0=easiest, 16=hardest)
-- ============================================================

CharSettings.set("pick", {
  -- Pick speed thresholds (index into pick_messages_by_difficulty array)
  pick_quick_threshold   = 2,   -- 0..1 = blind, 2..3 = quick, 4..6 = normal, 7+ = careful
  pick_normal_threshold  = 4,
  pick_careful_threshold = 7,

  -- Disarm speed thresholds
  disarm_quick_threshold    = 0,   -- 0 = blind
  disarm_normal_threshold   = 2,
  disarm_careful_threshold  = 5,
  disarm_too_hard_threshold = 10,  -- >= this = skip box

  -- Retry limits
  max_identify_attempts = 5,
  max_disarm_attempts   = 5,

  -- Trap handling
  trap_blacklist        = {},    -- list of trap type names to always stow (e.g. {"shadowling", "reaper"})
  blacklist_container   = nil,   -- container for blacklisted trap boxes
  trap_greylist         = {},    -- list of trap types to force careful disarm
  too_hard_container    = nil,   -- container for too-hard boxes (nil = trash)

  -- Advanced features
  assumed_difficulty    = nil,   -- nil = identify; "quick"/"normal"/"careful" = skip identification
  use_glance            = nil,   -- nil = auto (thieves circle >= 13); true/false to override
  balance_lockpick_container = false,  -- turn lockpick ring to best before each box
  tend_own_wounds       = false, -- run tendme after trap is sprung
  debug                 = false, -- verbose debug output

  -- Buff bot (whisper another PC for buffs before each box)
  buff_bot_buff         = "hol", -- buff abbreviation to request
})

CharSettings.set("lockpick_buff_bot", nil)  -- PC name to whisper, or nil

-- ============================================================
-- LOOT SETTINGS
-- ============================================================

-- Items to stow (gems, treasure) — list of noun strings
CharSettings.set("lootables", {
  "gem", "crystal", "stone", "ruby", "sapphire", "emerald", "diamond",
  "amethyst", "topaz", "opal", "pearl", "jasper", "garnet",
})

-- Items to trash — list of noun strings
CharSettings.set("trash_nouns", {
  "skin", "hide", "pelt", "tusk", "bone", "claw", "fang", "eye",
  "brain", "wing", "tail", "ear", "horn", "ichor", "gland",
})

-- Special routing: { name = "keyword", bag = "container" }
CharSettings.set("loot_specials", {})
-- Example: { { name = "scroll", bag = "scroll pouch" }, { name = "herb", bag = "herb pouch" } }

-- ============================================================
-- GEM POUCH SETTINGS
-- ============================================================

CharSettings.set("gem_pouch_noun", "pouch")
CharSettings.set("gem_pouch_adjective", nil)         -- e.g. "silken" if "silken pouch"
CharSettings.set("fill_pouch_with_box", false)        -- fill pouch from box first, then loot remainder
CharSettings.set("tie_gem_pouches", false)            -- tie pouch when swapping
CharSettings.set("spare_gem_pouch_container", nil)    -- container holding spare pouches
CharSettings.set("full_pouch_container", nil)         -- where to put full pouches

-- ============================================================
-- TRASH / DISPOSAL SETTINGS
-- ============================================================

CharSettings.set("worn_trashcan", nil)       -- worn trashcan item name (nil = use room bins)
CharSettings.set("worn_trashcan_verb", nil)  -- verb to use with worn trashcan (nil = "put")

-- ============================================================
-- SKELETON KEY (optional, use to auto-unlock without picking)
-- ============================================================

CharSettings.set("use_skeleton_key", false)
CharSettings.set("skeleton_key", nil)  -- e.g. "skeleton key"

-- ============================================================
-- HEALTH / SAFETY
-- ============================================================

CharSettings.set("saferoom_health_threshold", 30)  -- health % to trigger safe-room

-- ============================================================
-- CONFIRM SETUP
-- ============================================================

echo("pick_setup: Configuration saved.")
echo("  picking_box_source: " .. tostring(CharSettings.get("picking_box_source")))
echo("  use_lockpick_ring:  " .. tostring(CharSettings.get("use_lockpick_ring")))
echo("  lockpick_container: " .. tostring(CharSettings.get("lockpick_container")))
echo("  lockpick_type:      " .. tostring(CharSettings.get("lockpick_type")))
echo("  refill_town:        " .. tostring(CharSettings.get("refill_town")))
echo("Run ;pick to start picking boxes.")
