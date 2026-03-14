--- @revenant-script
--- name: autostart
--- version: 0.1.0
--- description: Launch scripts automatically on character connect

local args = require("lib/args")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function load_list(key, store)
  local raw = store[key]
  if not raw then return {} end
  local ok, t = pcall(Json.decode, raw)
  return (ok and type(t) == "table") and t or {}
end

local function save_list(key, store, list)
  store[key] = Json.encode(list)
end

-- ── Command mode ─────────────────────────────────────────────────────────────
-- When arguments are present, handle as a management command and exit.

local input = Script.vars[0] or ""
local parsed = args.parse(input)
local cmd    = parsed.args[1]

if cmd then
  local target    = parsed.args[2]
  local is_global = (parsed["global"] == true)
  local store_key = is_global and "autostart_global" or "autostart"
  local store     = is_global and Settings or CharSettings
  local scope_lbl = is_global and "global" or "character"

  if cmd == "list" then
    local global_list = load_list("autostart_global", Settings)
    local char_list   = load_list("autostart", CharSettings)
    local enabled     = CharSettings["autostart_enabled"] ~= "false"
    respond("Autostart: " .. (enabled and "enabled" or "disabled"))
    respond("  Global:    " .. (#global_list > 0 and table.concat(global_list, ", ") or "(none)"))
    respond("  Character: " .. (#char_list   > 0 and table.concat(char_list,   ", ") or "(none)"))

  elseif cmd == "add" then
    if not target then
      respond("Usage: ;autostart add <script> [--global]")
    else
      local list = load_list(store_key, store)
      for _, v in ipairs(list) do
        if v == target then return end  -- silent no-op if already present
      end
      list[#list + 1] = target
      save_list(store_key, store, list)
      respond("Added " .. target .. " to " .. scope_lbl .. " autostart.")
    end

  elseif cmd == "remove" then
    if not target then
      respond("Usage: ;autostart remove <script> [--global]")
    else
      local list = load_list(store_key, store)
      local new = {}
      for _, v in ipairs(list) do
        if v ~= target then new[#new + 1] = v end
      end
      save_list(store_key, store, new)
      respond("Removed " .. target .. " from " .. scope_lbl .. " autostart.")
    end

  elseif cmd == "enable" then
    CharSettings["autostart_enabled"] = "true"
    respond("Autostart enabled.")

  elseif cmd == "disable" then
    CharSettings["autostart_enabled"] = "false"
    respond("Autostart disabled.")

  else
    respond("Usage: ;autostart [list | add <script> [--global] | remove <script> [--global] | enable | disable]")
  end

  return  -- exit after handling command
end

-- ── Daemon mode ───────────────────────────────────────────────────────────────
-- No arguments: show list, register connect hook, and block indefinitely.

do
  local global_list = load_list("autostart_global", Settings)
  local char_list   = load_list("autostart", CharSettings)
  local enabled     = CharSettings["autostart_enabled"] ~= "false"
  respond("Autostart: " .. (enabled and "enabled" or "disabled"))
  respond("  Global:    " .. (#global_list > 0 and table.concat(global_list, ", ") or "(none)"))
  respond("  Character: " .. (#char_list   > 0 and table.concat(char_list,   ", ") or "(none)"))
end

local last_connect_time = 0

DownstreamHook.add("autostart_connect", function(data)
  -- Only fire on <app ...> element (login confirmation)
  if not data:match("<app ") then return data end

  local now = os.time()
  if now - last_connect_time < 5 then return data end
  last_connect_time = now

  if CharSettings["autostart_enabled"] == "false" then return data end

  local global_list = load_list("autostart_global", Settings)
  local char_list   = load_list("autostart", CharSettings)

  -- Merge: global first, then character-specific
  local all = {}
  for _, v in ipairs(global_list) do all[#all + 1] = v end
  for _, v in ipairs(char_list)   do all[#all + 1] = v end

  local started, skipped, failed = 0, 0, {}

  for _, name in ipairs(all) do
    if Script.running(name) then
      skipped = skipped + 1
    else
      -- pcall catches load-time errors only; runtime errors are not captured
      local ok, err = pcall(Script.run, name)
      if ok then
        started = started + 1
      else
        failed[#failed + 1] = name .. ": " .. tostring(err)
      end
    end
  end

  respond(string.format(
    "autostart: started %d, skipped %d (already running), failed %d",
    started, skipped, #failed))

  if #failed > 0 then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local lines = { "[" .. timestamp .. "] Connect failures:" }
    for _, f in ipairs(failed) do lines[#lines + 1] = "  " .. f end
    -- Append to log (write overwrites; for append behaviour, read + concat)
    local existing = File.read("_data/autostart.log") or ""
    File.write("_data/autostart.log", existing .. table.concat(lines, "\n") .. "\n")
  end

  return data
end)

respond("autostart: daemon running. Use ;autostart list to see configured scripts.")
while true do pause() end
