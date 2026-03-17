--- DRSkill state machine — tracks per-skill experience data.
-- Ported from Lich5 drskill.rb
-- @module lib.dr.skills
local defs = require("lib/dr/defs")

local M = {}

-- Internal skill storage: name -> { name, rank, percent, learning_rate, rate_name, baseline }
local skills = {}

--- Resolve a learning rate name to its numeric index (0-19).
-- Returns 0 if the name is not recognized.
local function rate_name_to_index(rate_name)
  if not rate_name then return 0 end
  local lower = rate_name:lower()
  for i = 0, 19 do
    if defs.LEARNING_RATES[i] == lower then
      return i
    end
  end
  return 0
end

--- Update or create a skill entry.
-- @param name string Skill name (e.g. "Evasion")
-- @param rank number Earned ranks
-- @param percent number Percent to next rank (0-100)
-- @param rate_name string Learning rate text (e.g. "dabbling")
function M.update(name, rank, percent, rate_name)
  local idx = rate_name_to_index(rate_name)
  local entry = skills[name]
  if entry then
    entry.rank = tonumber(rank) or 0
    entry.percent = tonumber(percent) or 0
    entry.learning_rate = idx
    entry.rate_name = rate_name or defs.LEARNING_RATES[0]
  else
    skills[name] = {
      name          = name,
      rank          = tonumber(rank) or 0,
      percent       = tonumber(percent) or 0,
      learning_rate = idx,
      rate_name     = rate_name or defs.LEARNING_RATES[0],
      baseline      = (tonumber(rank) or 0) + ((tonumber(percent) or 0) / 100.0),
    }
  end
end

--- Get the rank for a skill.
-- @param name string Skill name
-- @return number Rank, or 0 if unknown
function M.getrank(name)
  local entry = skills[name]
  return entry and entry.rank or 0
end

--- Get the percent-to-next-rank for a skill.
-- @param name string Skill name
-- @return number Percent, or 0 if unknown
function M.getpercent(name)
  local entry = skills[name]
  return entry and entry.percent or 0
end

--- Get the learning rate index (0-19) for a skill.
-- @param name string Skill name
-- @return number Learning rate index, or 0 if unknown
function M.getlearning(name)
  local entry = skills[name]
  return entry and entry.learning_rate or 0
end

--- Get the full skill entry table.
-- @param name string Skill name
-- @return table|nil Copy of skill entry, or nil if unknown
function M.get(name)
  local entry = skills[name]
  if not entry then return nil end
  -- Return a shallow copy
  local copy = {}
  for k, v in pairs(entry) do copy[k] = v end
  return copy
end

--- Get a copy of all tracked skills.
-- @return table { name -> skill_entry }
function M.all()
  local copy = {}
  for name, entry in pairs(skills) do
    local e = {}
    for k, v in pairs(entry) do e[k] = v end
    copy[name] = e
  end
  return copy
end

--- Get skills whose current rank exceeds their baseline.
-- @return table { name -> skill_entry }
function M.gained_skills()
  local result = {}
  for name, entry in pairs(skills) do
    local current = entry.rank + (entry.percent / 100.0)
    if current > entry.baseline then
      local e = {}
      for k, v in pairs(entry) do e[k] = v end
      result[name] = e
    end
  end
  return result
end

--- Reset all baselines to current rank+percent.
function M.reset_baselines()
  for _, entry in pairs(skills) do
    entry.baseline = entry.rank + (entry.percent / 100.0)
  end
end

return M
