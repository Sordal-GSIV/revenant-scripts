--- @revenant-script
--- name: version
--- version: 0.1.0
--- description: Check and update the Revenant engine version

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
  local content, dl_err = Http.get(entry.url)
  if not content then
    respond("Download failed: " .. tostring(dl_err))
    return
  end

  local tmp = "_pkg/revenant.new"
  local ok, wr_err = File.write(tmp, content)
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

-- Dispatch
if not cmd or cmd == "check" then
  cmd_check()
elseif cmd == "update" then
  cmd_update()
elseif cmd == "channel" then
  cmd_channel(parsed.args[2])
else
  respond("Usage: ;version [check | update | channel <stable|beta|dev>]")
end
