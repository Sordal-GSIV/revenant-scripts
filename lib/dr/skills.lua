--- DRSkill state machine — tracks per-skill experience data.
-- Ported from Lich5 drskill.rb
-- @module lib.dr.skills
local defs = require("lib/dr/defs")

local M = {}

-- Internal skill storage: name -> { name, rank, percent, learning_rate, rate_name, baseline }
local skills = {}

-- Event queue: array of { skill=name, change=delta } pushed when learning rate increases.
-- Drained by DRExpMon.report_skill_gains().
local _gained_events = {}

-- When true, handle_exp_change pushes events to _gained_events.
-- Controlled by DRExpMon.start()/stop().
local _display_expgains = false

-- Push an event when a skill's learning rate increases.
local function handle_exp_change(name, new_rate_idx)
  if not _display_expgains then return end
  local entry = skills[name]
  if not entry then return end  -- skip initial login discovery
  local change = new_rate_idx - entry.learning_rate
  if change > 0 then
    _gained_events[#_gained_events + 1] = { skill = name, change = change }
  end
end

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
  handle_exp_change(name, idx)  -- must run BEFORE updating entry.learning_rate
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

--- Get the modified rank for a skill.
-- Lich5 getmodrank includes stat bonuses; Revenant only tracks base rank,
-- so this is an alias for getrank.
-- @param name string Skill name
-- @return number Rank, or 0 if unknown
function M.getmodrank(name)
  return M.getrank(name)
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

--- Get the learning rate index for a skill (alias for getlearning).
-- Returns 0-19 where 0 = clear and 19 = mind lock.
-- Note: Lich5's DRSkill.getxp used a 0-34 scale; Revenant uses 0-19.
-- Adjust yaml threshold settings accordingly (e.g. 34 → 19, 25 → ~13).
-- @param name string Skill name
-- @return number Learning rate index 0-19
function M.getxp(name)
  return M.getlearning(name)
end

--- Get all tracked skills as an array of {name, rank, exp} tables.
-- Mirrors Lich5's DRSkill.list which returns skill objects with .name, .rank, .exp.
-- exp is the learning rate index (0-19, same as getxp/getlearning).
-- @return table Array of {name=string, rank=number, exp=number}
function M.list()
  local result = {}
  for name, entry in pairs(skills) do
    result[#result + 1] = {
      name = name,
      rank = entry.rank,
      exp  = entry.learning_rate,
    }
  end
  return result
end

--- Returns the cumulative rank gain since last reset for a skill.
-- Equivalent to Lich5's DRSkill.gained_exp(val).
-- @param name string Skill name
-- @return number Ranks gained (float, 2 decimal places), 0.0 if unknown
function M.gained_exp(name)
  local entry = skills[name]
  if not entry then return 0.0 end
  local current = entry.rank + (entry.percent / 100.0)
  local diff = current - entry.baseline
  return math.floor(diff * 100 + 0.5) / 100
end

--- Drain and return all pending learning-rate-increase events.
-- Each event is { skill=name, change=delta }. Resets the queue.
-- Called by DRExpMon.report_skill_gains().
-- @return table Array of event tables
function M.gained_events_drain()
  local events = _gained_events
  _gained_events = {}
  return events
end

--- Enable or disable learning-rate-increase event tracking.
-- Called by DRExpMon.start() / DRExpMon.stop().
-- @param enabled boolean
function M.set_display_expgains(enabled)
  _display_expgains = enabled and true or false
end

--- Check if learning-rate-increase event tracking is active.
-- @return boolean
function M.get_display_expgains()
  return _display_expgains
end

--- Reset all baselines to current values and clear the event queue.
-- Equivalent to Lich5's DRSkill.reset.
function M.reset()
  _gained_events = {}
  M.reset_baselines()
end

-- Lazy-built reverse map: lowercase skill name -> capitalized category name
local _skill_to_category = nil

local function build_skill_map()
  _skill_to_category = {}
  for cat, skill_list in pairs(defs.SKILL_CATEGORIES) do
    if type(cat) == "string" and type(skill_list) == "table" then
      local display = cat:sub(1, 1):upper() .. cat:sub(2)
      for _, skill_name in ipairs(skill_list) do
        if type(skill_name) == "string" then
          _skill_to_category[skill_name:lower()] = display
        end
      end
    end
  end
end

--- Get the skillset category name for a skill (e.g. "Armor", "Weapon", "Magic").
-- @param name string Skill name (case-insensitive)
-- @return string Category name or "Unknown"
function M.getskillset(name)
  if not name then return "Unknown" end
  if not _skill_to_category then build_skill_map() end
  local map = _skill_to_category or {}
  return map[name:lower()] or "Unknown"
end

return M
