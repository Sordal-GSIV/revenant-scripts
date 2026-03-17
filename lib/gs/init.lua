-- lib/gs/init.lua
-- Loaded conditionally when game is GemStone IV.
-- Registers all GS-specific modules as globals (matching Lich5 behavior).

-- PSM modules (CMan, Feat, Shield, Armor, Weapon, Ascension, Warcry)
require("lib/gs/psm")

-- Currency tracking
Currency = require("lib/gs/currency")

-- Spell circle ranks
SpellRanks = require("lib/gs/spellranks")

-- Experience tracking
Experience = require("lib/gs/experience")

-- Creature data
Creature = require("lib/gs/creature")

-- Combat tracker
CombatTracker = require("lib/gs/combat_tracker")

-- Room claim system
Claim = require("lib/gs/claim")

-- Hidden creature tracking
Overwatch = require("lib/gs/overwatch")

-- Stat knowledge
SK = require("lib/gs/sk")

-- Gift experience
Gift = require("lib/gs/gift")

-- Bard spellsong
Spellsong = require("lib/gs/spellsong")

-- Enhancive tracking
Enhancive = require("lib/gs/enhancive")

-- Ready/Stow list
ReadyList = require("lib/gs/readylist")
StowList = require("lib/gs/stowlist")

-- Armaments lookup
Armaments = require("lib/gs/armaments")

-- Critical rank tables
CritRanks = require("lib/gs/critranks")

-- Spell casting engine (patches Spell metatable)
require("lib/gs/spell_casting")

-- Society parser (extends Rust-registered Society global with hook)
require("lib/society")

respond("[gsinfomon] GemStone IV modules loaded")
