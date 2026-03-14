--- @revenant-script
--- name: alias
--- version: 0.1.0
--- description: Pattern-based command aliases with Tier 1 (CLI) and Tier 2 (aliases.lua) support

local args = require("lib/args")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function load_aliases(key, store)
  local raw = store[key]
  if not raw then return {} end
  local ok, t = pcall(Json.decode, raw)
  return (ok and type(t) == "table") and t or {}
end

local function save_aliases(key, store, list)
  store[key] = Json.encode(list)
end

-- ── Command mode ─────────────────────────────────────────────────────────────

local input  = Script.vars[0] or ""
local parsed = args.parse(input)
local cmd    = parsed.args[1]

if input ~= "" and cmd then
  local is_global = (parsed["global"] == true)
  local store_key = is_global and "aliases_global" or "aliases"
  local store     = is_global and Settings or CharSettings
  local scope_lbl = is_global and "global" or "character"

  if cmd == "add" then
    -- ;alias add <name> <pattern> <replacement> [--global]
    local name    = parsed.args[2]
    local pattern = parsed.args[3]
    local repl    = parsed.args[4]
    if not name or not pattern or not repl then
      respond("Usage: ;alias add <name> <pattern> <replacement> [--global]")
    else
      local list = load_aliases(store_key, store)
      -- Replace existing entry with same name, or append
      local found = false
      for i, entry in ipairs(list) do
        if entry.name == name then
          list[i] = { name = name, pattern = pattern, replacement = repl }
          found = true
          break
        end
      end
      if not found then
        list[#list + 1] = { name = name, pattern = pattern, replacement = repl }
      end
      save_aliases(store_key, store, list)
      respond("Alias '" .. name .. "' saved to " .. scope_lbl .. " list.")
    end

  elseif cmd == "remove" then
    local name = parsed.args[2]
    if not name then
      respond("Usage: ;alias remove <name> [--global]")
    else
      local list = load_aliases(store_key, store)
      local new = {}
      for _, entry in ipairs(list) do
        if entry.name ~= name then new[#new + 1] = entry end
      end
      save_aliases(store_key, store, new)
      respond("Alias '" .. name .. "' removed from " .. scope_lbl .. " list.")
    end

  elseif cmd == "enable" then
    CharSettings["alias_enabled"] = "true"
    respond("Aliases enabled.")

  elseif cmd == "disable" then
    CharSettings["alias_enabled"] = "false"
    respond("Aliases disabled.")

  elseif cmd == "list" then
    local char_list   = load_aliases("aliases", CharSettings)
    local global_list = load_aliases("aliases_global", Settings)
    local enabled     = CharSettings["alias_enabled"] ~= "false"
    respond("Aliases: " .. (enabled and "enabled" or "disabled"))
    respond("Character aliases (" .. #char_list .. "):")
    for _, e in ipairs(char_list) do
      respond(string.format("  %-20s  %s  →  %s", e.name, e.pattern, e.replacement))
    end
    respond("Global aliases (" .. #global_list .. "):")
    for _, e in ipairs(global_list) do
      respond(string.format("  %-20s  %s  →  %s", e.name, e.pattern, e.replacement))
    end

  else
    respond("Usage: ;alias [list | add <name> <pattern> <repl> [--global] | remove <name> [--global] | enable | disable]")
  end

  return
end

-- ── Tier 2: Load personal aliases.lua config ─────────────────────────────────

local tier2_aliases = {}

-- aliases.lua lives in the scripts root alongside other scripts.
-- The user defines aliases via: alias("name", "^pattern$", replacement)
-- where replacement is a string, array of strings, or function.
local function alias(name, pattern, replacement)
  tier2_aliases[#tier2_aliases + 1] = { name = name, pattern = pattern, replacement = replacement }
end

-- Try to load the user's personal aliases.lua
local aliases_src, _ = File.read("aliases.lua")
if aliases_src then
  local fn, err = load(aliases_src, "aliases.lua", "t",
    setmetatable({ alias = alias }, { __index = _G }))
  if fn then
    local ok, load_err = pcall(fn)
    if not ok then
      respond("aliases.lua load error: " .. tostring(load_err))
    end
  else
    respond("aliases.lua syntax error: " .. tostring(err))
  end
end

-- ── Daemon mode: UpstreamHook ─────────────────────────────────────────────────

local function apply_alias(entry, line)
  local repl = entry.replacement
  local t = type(repl)

  if t == "string" then
    -- String: gsub pattern, then split on ; for multiple commands
    local result = line:gsub(entry.pattern, repl)
    if result == line then return nil end  -- no match
    return result  -- caller splits on ; if needed

  elseif t == "table" then
    -- Array: check match, then return all commands
    if not line:match(entry.pattern) then return nil end
    return repl  -- array of strings

  elseif t == "function" then
    -- Function: call with captures, return result
    local captures = { line:match(entry.pattern) }
    if #captures == 0 and not line:match(entry.pattern) then return nil end
    local ok, result = pcall(repl, table.unpack(captures))
    if not ok then
      respond("[alias] function error in '" .. entry.name .. "': " .. tostring(result))
      return nil
    end
    return result  -- string, array, or nil

  end
  return nil
end

local function send_commands(cmds)
  if type(cmds) == "string" then
    -- Split on ; for multi-command string aliases (Lich5 parity)
    for part in cmds:gmatch("[^;]+") do
      local trimmed = part:match("^%s*(.-)%s*$")
      if #trimmed > 0 then
        fput(trimmed)
      end
    end
  elseif type(cmds) == "table" then
    for _, c in ipairs(cmds) do fput(c) end
  end
end

UpstreamHook.add("alias_intercept", function(data)
  -- If aliases are disabled, pass through
  if CharSettings["alias_enabled"] == "false" then return data end

  local line = data:match("^(.-)\r?\n?$") or data

  -- Check precedence: char CLI → global CLI → tier2
  local lists = {
    load_aliases("aliases",        CharSettings),
    load_aliases("aliases_global", Settings),
    tier2_aliases,
  }

  for _, list in ipairs(lists) do
    for _, entry in ipairs(list) do
      local result = apply_alias(entry, line)
      if result ~= nil then
        -- Match found
        send_commands(result)
        return ""  -- swallow original input; fput has already sent commands
      end
    end
  end

  return data  -- no alias matched, pass through
end)

respond("alias: daemon running. Use ;alias list to see configured aliases.")
pause()
