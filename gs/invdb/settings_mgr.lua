-- settings_mgr.lua — invdb settings loading, parsing, and mutation
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

-- ---------------------------------------------------------------------------
-- Default settings definitions
-- type: "boolean" | "integer" | "string" | "array"
-- internal: true = not shown in --settings output
-- ---------------------------------------------------------------------------
local DEFAULTS = {
  confirm_large_output = { type = "integer", default = 100,     internal = false,
    desc = "require unpause when row count exceeds this number" },
  hide_legend          = { type = "boolean", default = false,   internal = false,
    desc = "hide abbreviation legend before search results" },
  jar                  = { type = "boolean", default = true,    internal = false,
    desc = "check contents of jars" },
  stack                = { type = "boolean", default = false,   internal = false,
    desc = "check number of stacked notes" },
  silence_stack        = { type = "boolean", default = true,    internal = false,
    desc = "silence lines from checking jars/stacks" },
  open_containers      = { type = "boolean", default = true,    internal = false,
    desc = "opens and closes containers during inventory check" },
  container_noopen     = { type = "array",   default = {"locket"}, internal = false,
    desc = "names/nouns of containers NOT to open" },
  boh                  = { type = "array",
    default = {"large treasure sack with a blood crystal clasp"}, internal = false,
    desc = "names of bags of holding" },
  date_format          = { type = "string",  default = "%m/%d/%y", internal = false,
    desc = "date format, e.g. %m/%d/%y or %Y-%m-%d" },
  lumnis               = { type = "boolean", default = true,    internal = false,
    desc = "include lumnis tracking in 'refresh all'" },
  resource             = { type = "boolean", default = true,    internal = false,
    desc = "include resource tracking in 'refresh all'" },
  move_rooms           = { type = "boolean", default = false,   internal = false,
    desc = "move rooms when encountering 'Too many windows' error" },
  use_old_quiet_command = { type = "boolean", default = false,  internal = true,
    desc = "fallback to old quiet command for scanning issues" },
  last_vacuum          = { type = "integer", default = 0,       internal = true,
    desc = "timestamp of last SQLite vacuum" },
}

-- Key for persistent storage: per-game (cross-character) via UserVars
local SETTINGS_KEY_PREFIX = "invdb_setting_"

-- ---------------------------------------------------------------------------
-- Load all settings from UserVars, filling defaults for missing keys
-- Returns: table of setting_name → value
-- ---------------------------------------------------------------------------
function M.load()
  local settings = {}
  for k, def in pairs(DEFAULTS) do
    local stored = UserVars[SETTINGS_KEY_PREFIX .. k]
    if stored ~= nil then
      -- Deserialize from JSON if it's an array
      if def.type == "array" then
        local ok, decoded = pcall(function() return Json.decode(stored) end)
        settings[k] = (ok and type(decoded) == "table") and decoded or def.default
      elseif def.type == "boolean" then
        settings[k] = stored == "true" or stored == "1"
      elseif def.type == "integer" then
        settings[k] = tonumber(stored) or def.default
      else
        settings[k] = stored
      end
    else
      -- Write the default
      settings[k] = def.default
      M._save_one(k, def.default, def.type)
    end
  end
  return settings
end

-- ---------------------------------------------------------------------------
-- Save a single setting to UserVars
-- ---------------------------------------------------------------------------
function M._save_one(key, value, type_hint)
  type_hint = type_hint or (DEFAULTS[key] and DEFAULTS[key].type) or "string"
  local serialized
  if type_hint == "array" then
    serialized = Json.encode(value)
  elseif type_hint == "boolean" then
    serialized = value and "true" or "false"
  else
    serialized = tostring(value)
  end
  UserVars[SETTINGS_KEY_PREFIX .. key] = serialized
end

-- ---------------------------------------------------------------------------
-- Apply a boolean setting from command-line argument string
-- e.g. "--jar=on" or "--open_containers=false"
-- Returns: true if handled, false otherwise
-- ---------------------------------------------------------------------------
function M.apply_boolean(settings, arg)
  -- --key=on|off|true|false
  local key, val_str = arg:match("^%-%-(%w+)[=: ]*(%w+)$")
  if not key then return false end
  key = key:lower()
  if not DEFAULTS[key] or DEFAULTS[key].type ~= "boolean" then return false end

  local new_val
  if val_str:match("^(true|on)$") then
    new_val = true
  elseif val_str:match("^(false|off)$") then
    new_val = false
  else
    respond("invdb: unknown value '" .. val_str .. "' for " .. key .. ". Use true/false/on/off.")
    return true
  end

  if settings[key] ~= new_val then
    settings[key] = new_val
    M._save_one(key, new_val, "boolean")
    respond("invdb: " .. key .. " is now " .. tostring(new_val))
  else
    respond("invdb: " .. key .. " was already " .. tostring(new_val))
  end
  return true
end

-- Apply a string setting from arg
function M.apply_string(settings, arg)
  local key, val = arg:match("^%-%-(%w+)[=: ]*(.*)")
  if not key then return false end
  key = key:lower()
  if not DEFAULTS[key] or DEFAULTS[key].type ~= "string" then return false end
  if val and #val > 0 then
    settings[key] = val
    M._save_one(key, val, "string")
    respond("invdb: " .. key .. " is now " .. val)
  end
  return true
end

-- Apply an integer setting from arg
function M.apply_integer(settings, arg)
  local key, val = arg:match("^%-%-(%w+)[=: ]*(%d+)")
  if not key then return false end
  key = key:lower()
  if not DEFAULTS[key] or DEFAULTS[key].type ~= "integer" then return false end
  local n = tonumber(val)
  if n then
    settings[key] = n
    M._save_one(key, n, "integer")
    respond("invdb: " .. key .. " is now " .. n)
  end
  return true
end

-- Add item to an array setting (+boh name, +container_noopen name)
function M.array_add(settings, key, items_str)
  if not DEFAULTS[key] or DEFAULTS[key].type ~= "array" then return end
  local arr = settings[key] or {}
  for _, item in ipairs(parse_list(items_str)) do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then
      local found = false
      for _, existing in ipairs(arr) do
        if existing == item then found = true; break end
      end
      if not found then
        table.insert(arr, item)
        respond("invdb: '" .. item .. "' added to " .. key)
      else
        respond("invdb: '" .. item .. "' is already in " .. key)
      end
    end
  end
  settings[key] = arr
  M._save_one(key, arr, "array")
end

-- Remove item from an array setting
function M.array_remove(settings, key, items_str)
  if not DEFAULTS[key] or DEFAULTS[key].type ~= "array" then return end
  local arr = settings[key] or {}
  for _, item in ipairs(parse_list(items_str)) do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then
      local new_arr = {}
      local removed = false
      for _, existing in ipairs(arr) do
        if existing == item then removed = true
        else table.insert(new_arr, existing) end
      end
      arr = new_arr
      if removed then
        respond("invdb: '" .. item .. "' removed from " .. key)
      else
        respond("invdb: '" .. item .. "' is not in " .. key)
      end
    end
  end
  settings[key] = arr
  M._save_one(key, arr, "array")
end

-- ---------------------------------------------------------------------------
-- Print all current settings
-- ---------------------------------------------------------------------------
function M.print_settings(settings, script_name)
  local lines = {}
  table.insert(lines, string.format("  %s settings:", script_name))
  table.insert(lines, string.rep("-", 60))
  table.insert(lines, string.format("  %-25s | %-10s | %s", "setting", "value", "description"))
  table.insert(lines, string.rep("-", 60))

  for k, def in pairs(DEFAULTS) do
    if not def.internal and def.type ~= "array" then
      table.insert(lines, string.format("  %-25s | %-10s | %s",
        k, tostring(settings[k] or def.default), def.desc))
    end
  end
  table.insert(lines, string.rep("-", 60))
  for k, def in pairs(DEFAULTS) do
    if not def.internal and def.type == "array" then
      local arr = settings[k] or def.default or {}
      table.insert(lines, string.format("  %s: %s", k, def.desc))
      for i, v in ipairs(arr) do
        table.insert(lines, string.format("    %d. %s", i, v))
      end
    end
  end

  respond('<output class="mono" />\n' .. table.concat(lines, "\n") .. '\n<output class="" />')
end

-- helper: split comma/pipe/semicolon-separated string
function parse_list(s)
  local result = {}
  for item in s:gmatch("[^,;|]+") do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then table.insert(result, item) end
  end
  return result
end

return M
