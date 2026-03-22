-- lib/gs/init.lua
-- Loaded conditionally when game is GemStone IV.
-- Registers all GS-specific modules as globals (matching Lich5 behavior).

-- Effect registries (Spells, Buffs, Debuffs, Cooldowns)
Effects = require("lib/gs/effects")

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

-- Combat tracker (minimal death-only hook)
CombatTracker = require("lib/gs/combat_tracker")

-- Combat tracking system (full HP/injury/status/UCS tracking)
require("lib/gs/combat/init")

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

-- Floating Disk tracker (spell 919)
Disk = require("lib/gs/disk")

-- Multi-group cluster coordination
Cluster = require("lib/gs/cluster")

-- Item stash/retrieve helper
Stash = require("lib/gs/stash")

-- Spell casting engine (patches Spell metatable)
require("lib/gs/spell_casting")

-- Society parser (extends Rust-registered Society global with hook)
require("lib/society")

-- Elemental Confluence zone navigation
Confluence = require("lib/gs/confluence")

-- Minotaur Maze solver
Maze = require("lib/gs/maze")

-- Lich5 compatibility shims for common check* functions
-- checkstamina(n) — returns stamina value, or true/false if n given
function checkstamina(n)
    if n == nil then return GameState.stamina end
    return GameState.stamina >= n
end

-- checkstance(s) — returns stance string, or true/false if s given
function checkstance(s)
    if s == nil then return GameState.stance end
    -- Support Lich5 abbreviated strings: "off" → "offensive", "adv" → "advanced", etc.
    local stance = GameState.stance or ""
    if s == "off" or s == "offensive" then
        return stance == "offensive"
    elseif s == "adv" or s == "advanced" then
        return stance == "advanced"
    elseif s == "neu" or s == "neutral" then
        return stance == "neutral"
    elseif s == "def" or s == "defensive" then
        return stance == "defensive"
    elseif s == "gua" or s == "guarded" then
        return stance == "guarded"
    end
    return stance == s
end

respond("[gsinfomon] GemStone IV modules loaded")
