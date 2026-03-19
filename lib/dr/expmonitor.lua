--- @revenant-module
--- name: dr/expmonitor
--- description: Background exp gain reporter — real-time skill learning-rate tracking
--
-- Ported from Lich5 lib/dragonrealms/drinfomon/drexpmonitor.rb
-- Original module: Lich::DragonRealms::DRExpMonitor
--
-- Usage (from scripts or DR init):
--   DRExpMon.start()         -- begin tracking and reporting
--   DRExpMon.stop()          -- halt tracking
--   DRExpMon.active()        -- boolean: is reporting running?
--   DRExpMon.set_inline_display(true)  -- show gained ranks on exp lines
--
-- Inline display settings persisted to CharSettings:
--   CharSettings.drexpmon_active  = "true"/"false"
--   CharSettings.drexpmon_inline  = "true"/"false"

local M = {}

-- Whether the background reporting hook is registered.
local _running = false

-- Lazy-loaded inline display flag (persisted to CharSettings).
-- nil means "not yet loaded from settings".
local _inline_display = nil

-- Longest DR learning rate word, for BRIEFEXP OFF padding.
-- "concentrating" / "investigating" / "contemplating" = 13 chars.
local LONGEST_RATE_LEN = 13

-- Downstream hook name
local HOOK_NAME = "drexpmon"

-------------------------------------------------------------------------------
-- Settings helpers
-------------------------------------------------------------------------------

local function parse_bool(val)
  if val == nil then return false end
  local s = tostring(val):lower()
  return s == "true" or s == "on" or s == "yes" or s == "1"
end

-------------------------------------------------------------------------------
-- Inline display
-------------------------------------------------------------------------------

--- Get whether inline exp gain display is enabled.
-- Lazy-loaded from CharSettings; defaults to false.
-- @return boolean
function M.inline_display()
  if _inline_display == nil then
    _inline_display = parse_bool(CharSettings.drexpmon_inline)
  end
  return _inline_display
end

--- Enable or disable inline display and persist to CharSettings.
-- @param value boolean|string  truthy = on
function M.set_inline_display(value)
  _inline_display = parse_bool(value)
  CharSettings.drexpmon_inline = _inline_display and "true" or "false"
end

-------------------------------------------------------------------------------
-- BRIEFEXP line formatters
-------------------------------------------------------------------------------

--- Append cumulative gained exp to a BRIEFEXP ON line.
-- BRIEFEXP ON format: "     Aug:  565 39%  [ 2/34]"
-- Modified format:    "     Aug:  565 39%  [ 2/34] 0.12"
-- @param line string   Raw exp line
-- @param skill string  Full skill name (used to look up gained_exp)
-- @return string       Modified line, or original if inline display is off
function M.format_briefexp_on(line, skill)
  if not M.inline_display() then return line end
  local gained = (DRSkill and DRSkill.gained_exp(skill)) or 0.0
  -- Append after the closing bracket of the mindstate fraction (e.g. "/34]")
  return (line:gsub("(%/%d+%])", "%1 " .. string.format("%0.2f", gained), 1))
end

--- Append cumulative gained exp to a BRIEFEXP OFF line.
-- BRIEFEXP OFF format: "    Augmentation:  565 39% learning     "
-- Modified format:     "    Augmentation:  565 39% learning       0.12"
-- The rate word is padded to LONGEST_RATE_LEN so the gained column aligns.
-- @param line      string  Raw exp line
-- @param skill     string  Full skill name
-- @param rate_word string  Learning rate word as it appears in the line
-- @return string           Modified line, or original if inline display is off
function M.format_briefexp_off(line, skill, rate_word)
  if not M.inline_display() then return line end
  if not rate_word or rate_word == "" then return line end
  local gained = (DRSkill and DRSkill.gained_exp(skill)) or 0.0
  local pad = math.max(0, LONGEST_RATE_LEN - #rate_word)
  local padded = rate_word .. string.rep(" ", pad)
  -- Escape special Lua pattern chars in rate_word
  local esc = rate_word:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  -- Match: percent + spaces + rate_word → replace with padded rate + gained
  local result = line:gsub("(%%%s+)" .. esc, "%1" .. padded .. " " .. string.format("%0.2f", gained), 1)
  return result
end

-------------------------------------------------------------------------------
-- Gain reporting
-------------------------------------------------------------------------------

--- Aggregate and format a list of learning-rate-increase events.
-- Multiple events for the same skill are summed.
-- Output is sorted alphabetically.
-- @param events table  Array of { skill=string, change=number }
-- @return table        Array of "SkillName(+N)" strings
function M.format_gains(events)
  local agg = {}
  for _, ev in ipairs(events) do
    agg[ev.skill] = (agg[ev.skill] or 0) + ev.change
  end
  local keys = {}
  for k in pairs(agg) do keys[#keys + 1] = k end
  table.sort(keys)
  local result = {}
  for _, k in ipairs(keys) do
    result[#result + 1] = k .. "(+" .. agg[k] .. ")"
  end
  return result
end

--- Drain the DRSkill event queue and report any gains to the client.
-- Equivalent to Lich5's DRExpMonitor.report_skill_gains.
-- No output when the queue is empty.
function M.report_skill_gains()
  if not DRSkill then return end
  local events = DRSkill.gained_events_drain()
  if #events == 0 then return end
  local formatted = M.format_gains(events)
  respond("[DRExpMon] " .. table.concat(formatted, ", "))
end

-------------------------------------------------------------------------------
-- Downstream hook
-- Registered when active; handles two responsibilities:
--   1. On game prompt (">") — drain event queue and report gains.
--   2. On exp lines       — apply inline display formatting if enabled.
-------------------------------------------------------------------------------

local function build_hook()
  return function(line)
    -- 1. Drain and report on prompt
    if line:match("^>") then
      M.report_skill_gains()
      return line
    end

    -- 2. Inline display: intercept exp lines
    if M.inline_display() then
      -- BRIEFEXP ON: has [ N/NN] mindstate bracket, e.g. "[ 2/34]"
      if line:find("%[%s*%d+/%d+%]") then
        -- Extract skill name (abbreviated) up to the colon
        local skill = line:match("^%s+(%S.-):%s+%d+%s+%d+%%%s+%[")
        if skill then
          return M.format_briefexp_on(line, skill)
        end
      else
        -- BRIEFEXP OFF: "SkillName: rank pct% rate_word..."
        -- Capture rate as everything after percent (trimmed), allowing multi-word rates like "mind lock"
        local skill, rate = line:match("^%s+(%S.-):%s+%d+%s+%d+%%%s+(.-)%s*$")
        if skill and rate and rate ~= "" then
          return M.format_briefexp_off(line, skill, rate)
        end
      end
    end

    return line
  end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

--- Check if exp gain reporting is active.
-- @return boolean
function M.active()
  return _running
end

--- Start background exp gain reporting.
-- Registers a downstream hook that:
--   - Reports learning-rate-increase events on each game prompt.
--   - Optionally formats exp lines with cumulative gained ranks (inline display).
-- Persists active state to CharSettings.drexpmon_active.
-- No-op if already running.
function M.start()
  if _running then
    respond("[DRExpMon] Experience gain reporting is already active.")
    return
  end
  _running = true
  if DRSkill then
    DRSkill.set_display_expgains(true)
  end
  DownstreamHook.add(HOOK_NAME, build_hook())
  CharSettings.drexpmon_active = "true"
  respond("[DRExpMon] Exp gain reporting started.")
end

--- Stop exp gain reporting and remove the downstream hook.
-- Persists inactive state to CharSettings.drexpmon_active.
-- No-op if not running.
function M.stop()
  if not _running then
    respond("[DRExpMon] Experience gain reporting is already inactive.")
    return
  end
  _running = false
  if DRSkill then
    DRSkill.set_display_expgains(false)
  end
  DownstreamHook.remove(HOOK_NAME)
  CharSettings.drexpmon_active = "false"
  respond("[DRExpMon] Exp gain reporting stopped.")
end

-------------------------------------------------------------------------------
-- Auto-start from persisted settings (called by dr/init.lua)
-------------------------------------------------------------------------------

--- Auto-start if CharSettings.drexpmon_active is "true".
-- Called once at DR module load time.
function M.autostart()
  if parse_bool(CharSettings.drexpmon_active) then
    M.start()
  end
end

return M
