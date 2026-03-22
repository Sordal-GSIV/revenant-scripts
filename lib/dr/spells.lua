--- DRSpells — guild-specific spell/ability tracking.
-- Ported from Lich5 drspells.rb
-- @module lib.dr.spells
local M = {}

-- Internal state
local known_spells = {}   -- array of spell names
local known_feats = {}    -- array of feat names
local active_spells = {}  -- array of { name=string, duration=number }
local parse_mode = nil    -- "spells", "barbarian", "thief", or nil

--- Begin parsing a spell/ability list.
-- Resets the appropriate list based on mode.
-- @param mode string "spells", "barbarian", or "thief"
function M.start_parse(mode)
  parse_mode = mode
  if mode == "spells" then
    known_spells = {}
    known_feats = {}
  elseif mode == "barbarian" then
    known_spells = {}
  elseif mode == "thief" then
    known_spells = {}
  end
end

--- Add a known spell/ability during parsing.
-- @param name string Spell or ability name
function M.add_spell(name)
  if not parse_mode then return end
  known_spells[#known_spells + 1] = name
end

--- Add a known feat during parsing.
-- @param name string Feat name
function M.add_feat(name)
  if not parse_mode then return end
  known_feats[#known_feats + 1] = name
end

--- End the current parse session.
function M.end_parse()
  parse_mode = nil
end

--- Set the active spell list.
-- @param spells table Array of { name=string, duration=number }
function M.set_active(spells)
  active_spells = spells or {}
end

--- Get a copy of the known spells list.
-- @return table Array of spell name strings
function M.known_spells_list()
  local copy = {}
  for i, v in ipairs(known_spells) do copy[i] = v end
  return copy
end

--- Get a copy of the known feats list.
-- @return table Array of feat name strings
function M.known_feats_list()
  local copy = {}
  for i, v in ipairs(known_feats) do copy[i] = v end
  return copy
end

--- Get a copy of the active spells list.
-- @return table Array of { name=string, duration=number }
function M.active_spells_list()
  local copy = {}
  for i, v in ipairs(active_spells) do
    copy[i] = { name = v.name, duration = v.duration }
  end
  return copy
end

--- Get active spells as a hash (name → duration_minutes).
-- Compatible with Lich5 DRSpells.active_spells hash access pattern.
-- Used by DRCA.cast_spells, DRCA.spell_active, and buff.lua strict mode.
-- @return table {[name]=duration_minutes} for all active spells
function M.active_spells()
  local hash = {}
  for _, entry in ipairs(active_spells) do
    if entry.name and entry.duration ~= nil then
      hash[entry.name] = entry.duration
    end
  end
  return hash
end

--- Check if a spell is known.
-- @param spell_name string Spell name to check
-- @return boolean True if the spell is in the known list
function M.known_p(spell_name)
  for _, name in ipairs(known_spells) do
    if name == spell_name then return true end
  end
  return false
end

return M
