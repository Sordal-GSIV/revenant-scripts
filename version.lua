--- @revenant-script
--- name: version
--- version: 0.2.0
--- author: Sordal
--- description: Check/update the Revenant engine and show system diagnostics
--- tags: system,diagnostics

local args = require("lib/args")
local parsed = args.parse(Script.vars[0] or "")
local cmd = parsed.args[1]

local REGISTRY_BASE = "https://sordal-gsiv.github.io/revenant-scripts"
local REGISTRY_URL  = REGISTRY_BASE .. "/manifest.json"

local function get_channel()
  return Settings["version_channel"] or "stable"
end

--- Find the engine entry for a given channel in the manifest data.
local function find_engine_entry(data, channel)
  for _, script in ipairs(data.scripts or {}) do
    if script.name == "engine" then
      local ch = script.channels and script.channels[channel]
      return ch  -- may be nil if channel not present
    end
  end
  return nil
end

local function cmd_check()
  local current = Version.current()
  local channel  = get_channel()
  respond("Revenant engine: " .. current .. "  (channel: " .. channel .. ")")

  local data, err = Http.get_json(REGISTRY_URL)
  if not data then
    respond("Could not reach registry: " .. tostring(err))
    return
  end

  local entry = find_engine_entry(data, channel)
  if not entry then
    respond("No engine release in registry for channel: " .. channel)
    return
  end

  local cmp = Version.compare(current, entry.version)
  if cmp < 0 then
    respond("Update available: " .. entry.version ..
            "  (run ;version update to install)")
  elseif cmp == 0 then
    respond("Already up to date.")
  else
    respond("Running ahead of registry: " .. current .. " > " .. entry.version)
  end
end

local function cmd_update()
  local channel = get_channel()
  respond("Checking registry for channel: " .. channel .. " ...")

  local data, err = Http.get_json(REGISTRY_URL)
  if not data then
    respond("Could not fetch registry: " .. tostring(err))
    return
  end

  local entry = find_engine_entry(data, channel)
  if not entry then
    respond("No engine release found for channel: " .. channel)
    return
  end

  local current = Version.current()
  if Version.compare(current, entry.version) >= 0 then
    respond("Already at " .. current .. " — nothing to do.")
    return
  end

  respond("Downloading engine " .. entry.version .. " ...")
  local resp, dl_err = Http.get(entry.url)
  if not resp then
    respond("Download failed: " .. tostring(dl_err))
    return
  end
  if resp.status ~= 200 then
    respond("Download failed: HTTP " .. tostring(resp.status))
    return
  end

  local tmp = "_pkg/revenant.new"
  local ok, wr_err = File.write(tmp, resp.body)
  if not ok then
    respond("Failed to write temp file: " .. tostring(wr_err))
    return
  end

  local hash, hash_err = Crypto.sha256_file(tmp)
  if not hash then
    File.remove(tmp)
    respond("Failed to compute checksum: " .. tostring(hash_err))
    return
  end
  if hash ~= entry.sha256 then
    File.remove(tmp)
    respond("Checksum mismatch — download corrupted. Aborting.")
    return
  end

  local engine_path = Version.engine_path()
  local ok2, rn_err = File.replace(tmp, engine_path)
  if not ok2 then
    File.remove(tmp)
    respond("Failed to replace binary: " .. tostring(rn_err))
    return
  end

  respond("Updated to " .. entry.version .. ". Please restart Revenant to apply.")
  Script.exit()
end

local function cmd_channel(name)
  if not name then
    respond("Current update channel: " .. get_channel())
    return
  end
  if name ~= "stable" and name ~= "beta" and name ~= "dev" then
    respond("Unknown channel: " .. name .. ". Valid choices: stable, beta, dev")
    return
  end
  Settings["version_channel"] = name
  respond("Update channel set to: " .. name)
end

local function cmd_info()
  respond("════════════════════════════════════════════")
  respond("  Revenant System Report")
  respond("════════════════════════════════════════════")
  respond("")

  -- Engine identity
  local current = Version.current()
  local channel = get_channel()
  respond("Engine version:    " .. current)
  respond("Engine path:       " .. Version.engine_path())
  respond("Update channel:    " .. channel)
  respond("")

  -- Game state
  local game = GameState.game or "unknown"
  local charname = GameState.name or "unknown"
  local lvl = GameState.level or 0
  respond("Game:              " .. game)
  respond("Character:         " .. charname)
  respond("Level:             " .. tostring(lvl))
  respond("")

  -- Data file timestamps
  respond("── Data Files ──")
  local data_files = {
    {"effect-list.xml",  "data/effect-list.xml"},
    {"gameobj-data.xml", "data/gameobj-data.xml"},
  }
  local game_short = (game:lower():sub(1, 2) == "dr") and "DR" or "GS3"
  local map_dir = "data/" .. game_short
  local map_entries = File.list(map_dir)
  if type(map_entries) == "table" then
    for _, entry in ipairs(map_entries) do
      if entry:match("^map%-.*%.json$") then
        table.insert(data_files, {"Map: " .. entry, map_dir .. "/" .. entry})
      end
    end
  end

  for _, pair in ipairs(data_files) do
    local label, path = pair[1], pair[2]
    if File.exists(path) then
      local mtime = File.mtime(path)
      local ts = mtime and os.date("%Y-%m-%d %H:%M", mtime) or "unknown"
      respond("  " .. string.format("%-22s", label) .. ts)
    else
      respond("  " .. string.format("%-22s", label) .. "(not found)")
    end
  end
  respond("")

  -- Running scripts
  respond("── Running Scripts ──")
  local running = Script.list()
  if #running == 0 then
    respond("  (none)")
  else
    for _, sname in ipairs(running) do
      respond("  " .. sname)
    end
  end
  respond("")

  -- Hooks
  respond("── Downstream Hooks ──")
  local dh = DownstreamHook.list()
  if #dh == 0 then
    respond("  (none)")
  else
    for _, hname in ipairs(dh) do
      respond("  " .. hname)
    end
  end
  respond("")

  respond("── Upstream Hooks ──")
  local uh = UpstreamHook.list()
  if #uh == 0 then
    respond("  (none)")
  else
    for _, hname in ipairs(uh) do
      respond("  " .. hname)
    end
  end
  respond("")

  -- Installed packages
  respond("── Installed Packages ──")
  local inst_ok, inst_data = pcall(function()
    local raw = File.read("_pkg/installed.lua")
    if not raw then return {} end
    local fn = load(raw)
    if not fn then return {} end
    return fn() or {}
  end)
  local installed = inst_ok and inst_data or {}

  if not next(installed) then
    respond("  (none)")
  else
    local names = {}
    for k in pairs(installed) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
      local info = installed[k]
      local ver = info.version or "?"
      local ch = info.channel or "?"
      respond("  " .. string.format("%-20s %-10s (%s)", k, ver, ch))
    end
  end

  respond("")
  respond("════════════════════════════════════════════")
end

-- Dispatch
if not cmd or cmd == "check" then
  cmd_check()
elseif cmd == "update" then
  cmd_update()
elseif cmd == "channel" then
  cmd_channel(parsed.args[2])
elseif cmd == "info" or cmd == "all" or cmd == "full" or cmd == "details" then
  cmd_info()
else
  respond("Usage: ;version [check | update | info | channel <stable|beta|dev>]")
end
