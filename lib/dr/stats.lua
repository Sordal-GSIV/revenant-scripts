--- DRStats — character stat tracking with property-style access.
-- Ported from Lich5 drstats.rb
-- @module lib.dr.stats
local defs = require("lib/dr/defs")

local M = {}

-- Set of valid stat keys (needed because pairs() skips nil-valued entries)
local VALID_KEYS = {}
for _, k in ipairs({
  "race", "guild", "gender", "age", "circle",
  "strength", "stamina", "reflex", "agility",
  "intelligence", "wisdom", "discipline", "charisma",
  "tdps", "favors", "balance", "mana_type",
}) do
  VALID_KEYS[k] = true
end

-- Internal state
local state = {
  age          = 0,
  circle       = 0,
  strength     = 0,
  stamina      = 0,
  reflex       = 0,
  agility      = 0,
  intelligence = 0,
  wisdom       = 0,
  discipline   = 0,
  charisma     = 0,
  tdps         = 0,
  favors       = 0,
  balance      = 8,
  -- race, guild, gender, mana_type start as nil (not in table)
}

--- Set a stat value.
-- When guild is changed, mana_type is automatically recomputed.
-- @param key string Stat name (e.g. "race", "strength")
-- @param value any New value
function M.set(key, value)
  if not VALID_KEYS[key] then return end
  state[key] = value
  if key == "guild" then
    state.mana_type = defs.GUILD_MANA_TYPES[value]
  end
end

-- Metatable: allow DRStats.race, DRStats.strength, etc. as property access
setmetatable(M, {
  __index = function(_, key)
    if VALID_KEYS[key] then
      return state[key]  -- returns nil for unset keys, which is correct
    end
    return nil
  end,
})

-------------------------------------------------------------------------------
-- Guild predicates (mirrors Lich5 DRStats.barbarian?, DRStats.thief?, etc.)
-------------------------------------------------------------------------------

--- Check if character is a Barbarian.
-- @return boolean
function M.barbarian() return state.guild == "Barbarian" end

--- Check if character is a Thief.
-- @return boolean
function M.thief() return state.guild == "Thief" end

--- Check if character is a Trader.
-- @return boolean
function M.trader() return state.guild == "Trader" end

--- Check if character is a Moon Mage.
-- @return boolean
function M.moon_mage() return state.guild == "Moon Mage" end

--- Check if character is a Warrior Mage.
-- @return boolean
function M.warrior_mage() return state.guild == "Warrior Mage" end

--- Check if character is an Empath.
-- @return boolean
function M.empath() return state.guild == "Empath" end

--- Check if character is a Cleric.
-- @return boolean
function M.cleric() return state.guild == "Cleric" end

--- Check if character is a Paladin.
-- @return boolean
function M.paladin() return state.guild == "Paladin" end

--- Check if character is a Ranger.
-- @return boolean
function M.ranger() return state.guild == "Ranger" end

--- Check if character is a Bard.
-- @return boolean
function M.bard() return state.guild == "Bard" end

--- Check if character is a Necromancer.
-- @return boolean
function M.necromancer() return state.guild == "Necromancer" end

--- Check if character is a Commoner.
-- @return boolean
function M.commoner() return state.guild == "Commoner" end

return M
