--- @revenant-script
--- name: autostart
--- version: 0.2.0
--- description: Launch scripts automatically on character connect

-- ── Game-agnostic module loading ────────────────────────────────────────────
Flags = require("lib/flags")
Watchfor = require("lib/watchfor")
Messaging = require("lib/messaging")
Webhooks = require("lib/webhooks")
MapHelpers = require("lib/map_helpers")
TableRender = require("lib/table_render")
UserVarHelpers = require("lib/uservars")
require("lib/group")  -- registers DownstreamHook for GROUP verb parsing

-- ── Game-specific module loading ────────────────────────────────────────────
if GameState.game == "DR" then
    local ok, err = pcall(require, "lib/dr/init")
    if not ok then
        respond("[warning] Failed to load DR modules: " .. tostring(err))
    end
else
    local ok, err = pcall(require, "lib/gs/init")
    if not ok then
        respond("[warning] Failed to load GS modules: " .. tostring(err))
    end
end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function load_list(key, store)
  local raw = store[key]
  if not raw then return {} end
  local ok, t = pcall(Json.decode, raw)
  if not ok or type(t) ~= "table" then return {} end
  -- Migration: upgrade bare strings to {name, args} objects
  local migrated = false
  for i, entry in ipairs(t) do
    if type(entry) == "string" then
      t[i] = { name = entry, args = {} }
      migrated = true
    end
  end
  if migrated then
    store[key] = Json.encode(t)
  end
  return t
end

local function save_list(key, store, list)
  store[key] = Json.encode(list)
end

local function format_entry(entry)
  if #entry.args > 0 then
    return entry.name .. " (args: " .. table.concat(entry.args, " ") .. ")"
  end
  return entry.name
end

local function find_entry(list, name)
  for i, entry in ipairs(list) do
    if entry.name == name then return i end
  end
  return nil
end

local function show_config()
  local global_list = load_list("autostart_global", Settings)
  local char_list   = load_list("autostart", CharSettings)
  local enabled     = CharSettings["autostart_enabled"] ~= "false"
  local pkg_update  = CharSettings["autostart_pkg_update"] ~= "false"

  local global_str = "(none)"
  if #global_list > 0 then
    local parts = {}
    for _, e in ipairs(global_list) do parts[#parts + 1] = format_entry(e) end
    global_str = table.concat(parts, ", ")
  end

  local char_str = "(none)"
  if #char_list > 0 then
    local parts = {}
    for _, e in ipairs(char_list) do parts[#parts + 1] = format_entry(e) end
    char_str = table.concat(parts, ", ")
  end

  respond("Autostart: " .. (enabled and "enabled" or "disabled") .. " | pkg-update: " .. (pkg_update and "on" or "off"))
  respond("  Global:    " .. global_str)
  respond("  Character: " .. char_str)
end

-- ── CLI: add command (manual parsing) ────────────────────────────────────────

local function cmd_add(input)
  -- Tokenize first, then filter for exact --global match (avoids substring matching)
  local is_global = false
  local raw_tokens = {}
  for token in input:gmatch("%S+") do
    raw_tokens[#raw_tokens + 1] = token
  end

  local tokens = {}
  for _, token in ipairs(raw_tokens) do
    if token == "--global" then
      is_global = true
    elseif token ~= "add" then
      tokens[#tokens + 1] = token
    end
  end

  local script_name = tokens[1]
  if not script_name then
    respond("Usage: ;autostart add <script> [args...] [--global]")
    return
  end

  -- Validate script exists
  if not Script.exists(script_name) then
    respond("Error: script '" .. script_name .. "' does not exist.")
    return
  end

  local script_args = {}
  for i = 2, #tokens do
    script_args[#script_args + 1] = tokens[i]
  end

  local store_key = is_global and "autostart_global" or "autostart"
  local store     = is_global and Settings or CharSettings
  local scope_lbl = is_global and "global" or "character"

  local list = load_list(store_key, store)

  -- Check for duplicates
  if find_entry(list, script_name) then
    respond(script_name .. " is already in " .. scope_lbl .. " autostart.")
    return
  end

  list[#list + 1] = { name = script_name, args = script_args }
  save_list(store_key, store, list)
  respond("Added " .. script_name .. " to " .. scope_lbl .. " autostart.")
end

-- ── CLI: other commands ──────────────────────────────────────────────────────

local function cmd_remove(input)
  -- Tokenize and filter for exact --global match
  local is_global = false
  local script_name

  for token in input:gmatch("%S+") do
    if token == "--global" then
      is_global = true
    elseif token ~= "remove" and token ~= "rem" and token ~= "delete" and token ~= "del" then
      script_name = script_name or token
    end
  end

  if not script_name then
    respond("Usage: ;autostart remove <script> [--global]")
    return
  end

  local store_key = is_global and "autostart_global" or "autostart"
  local store     = is_global and Settings or CharSettings
  local scope_lbl = is_global and "global" or "character"

  local list = load_list(store_key, store)
  local idx = find_entry(list, script_name)
  if idx then
    table.remove(list, idx)
    save_list(store_key, store, list)
    respond("Removed " .. script_name .. " from " .. scope_lbl .. " autostart.")
  else
    respond(script_name .. " was not in " .. scope_lbl .. " autostart.")
  end
end

local function cmd_pkg_update(val)
  if val == "true" or val == "on" then
    CharSettings["autostart_pkg_update"] = "true"
    respond("Autostart: pkg-update enabled.")
  elseif val == "false" or val == "off" then
    CharSettings["autostart_pkg_update"] = "false"
    respond("Autostart: pkg-update disabled.")
  else
    local current = CharSettings["autostart_pkg_update"] ~= "false"
    respond("Autostart: pkg-update is " .. (current and "on" or "off") .. ".")
  end
end

local function show_help()
  respond("Usage:")
  respond("  ;autostart                              Show config + start daemon")
  respond("  ;autostart list                          Show configured scripts")
  respond("  ;autostart add <script> [args] [--global] Add script to autostart")
  respond("  ;autostart remove <script> [--global]    Remove script from autostart")
  respond("  ;autostart enable                        Enable autostart")
  respond("  ;autostart disable                       Disable autostart")
  respond("  ;autostart pkg-update [true|false]        Toggle pkg update on connect")
  respond("  ;autostart help                          Show this help")
end

-- ── Command routing ──────────────────────────────────────────────────────────

local input = Script.vars[0] or ""
local first_word = input:match("^%s*(%S+)")

if first_word then
  if first_word == "list" then
    show_config()

  elseif first_word == "add" then
    cmd_add(input)

  elseif first_word == "remove" or first_word == "rem" or first_word == "delete" or first_word == "del" then
    cmd_remove(input)

  elseif first_word == "enable" then
    CharSettings["autostart_enabled"] = "true"
    respond("Autostart enabled.")

  elseif first_word == "disable" then
    CharSettings["autostart_enabled"] = "false"
    respond("Autostart disabled.")

  elseif first_word == "pkg-update" then
    local val = input:match("^%s*pkg%-update%s+(%S+)")
    cmd_pkg_update(val)

  elseif first_word == "help" then
    show_help()

  else
    show_help()
  end

  return  -- exit after handling command
end

-- ── Daemon mode ──────────────────────────────────────────────────────────────
-- No arguments: show config, register connect hook, block indefinitely.

-- TODO: GUI management panel (Gui.window)
--   - Checkbox list of scripts (toggle on/off)
--   - Add/remove buttons
--   - Drag reorder
--   - Args editing per script
--   - pkg-update toggle

show_config()

local last_connect_time = 0

DownstreamHook.add("autostart_connect", function(data)
  -- Only fire on <app ...> element (login confirmation)
  if not data:match("<app ") then return data end

  local now = os.time()
  if now - last_connect_time < 5 then return data end
  last_connect_time = now

  if CharSettings["autostart_enabled"] == "false" then return data end

  -- Step 1: pkg update (if enabled)
  if CharSettings["autostart_pkg_update"] ~= "false" then
    local ok, err = pcall(Script.run, "pkg", "update")
    if ok then
      -- Wait for pkg to finish (20 second timeout)
      local waited = 0
      while Script.running("pkg") and waited < 20 do
        pause(0.5)
        waited = waited + 0.5
      end
      if waited >= 20 then
        respond("autostart: pkg update timed out after 20s, continuing.")
      end
    else
      respond("autostart: pkg update failed: " .. tostring(err))
    end
  end

  -- Step 2: Sync infomon data from game server
  Infomon.sync()
  local sync_timeout = 30
  local waited = 0
  while not Infomon.synced and waited < sync_timeout do
    pause(0.5)
    waited = waited + 0.5
  end
  if not Infomon.synced then
    respond("autostart: infomon sync timed out, launching scripts anyway")
  end

  -- Step 2: Merge global + character lists (deduplicate by name)
  local global_list = load_list("autostart_global", Settings)
  local char_list   = load_list("autostart", CharSettings)

  local all = {}
  local seen = {}
  for _, entry in ipairs(global_list) do
    if not seen[entry.name] then
      all[#all + 1] = entry
      seen[entry.name] = true
    end
  end
  for _, entry in ipairs(char_list) do
    if not seen[entry.name] then
      all[#all + 1] = entry
      seen[entry.name] = true
    end
  end

  -- Step 3: Launch scripts
  local started, skipped, failed = 0, 0, {}

  for _, entry in ipairs(all) do
    if Script.running(entry.name) then
      skipped = skipped + 1
    else
      local args_str = table.concat(entry.args, " ")
      local ok, err
      if #args_str > 0 then
        ok, err = pcall(Script.run, entry.name, args_str)
      else
        ok, err = pcall(Script.run, entry.name)
      end
      if ok then
        started = started + 1
      else
        failed[#failed + 1] = entry.name .. ": " .. tostring(err)
      end
    end
  end

  respond(string.format(
    "autostart: started %d, skipped %d (already running), failed %d",
    started, skipped, #failed))

  -- Log failures
  if #failed > 0 then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local lines = { "[" .. timestamp .. "] Connect failures:" }
    for _, f in ipairs(failed) do lines[#lines + 1] = "  " .. f end
    local existing = File.read("_data/autostart.log") or ""
    File.write("_data/autostart.log", existing .. table.concat(lines, "\n") .. "\n")
  end

  return data
end)

before_dying(function()
  DownstreamHook.remove("autostart_connect")
end)

respond("autostart: daemon running. Use ;autostart help for commands.")
while true do pause() end
