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

return M
