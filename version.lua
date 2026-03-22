--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: version
--- version: 1.1.0
--- author: Sordal
--- lic-authors: elanthia-online, LostRanger, Doug, Tysong
--- description: Diagnostic reporter and engine update manager
--- tags: system,diagnostics,utility,version
---
--- Changelog:
---   v1.1.0 (2026-03-18): Add autostart lists + DR dependency to diagnostic output
---     Matches Ruby version.lic v1.2.2 autostart/dependency reporting
---   v1.0.0 (2026-03-17): Full rewrite as diagnostic reporter + update manager
---     Matches Ruby version.lic v1.2.2 diagnostic features:
---       default mode, info, <scriptname>, all, check, update, channel
---   v0.2.0: Engine updater only (replaced by this rewrite)
---
--- Usage:
---   ;version            — Show system diagnostics summary
---   ;version info       — Detailed diagnostics with data files and map info
---   ;version <script>   — Show version of a specific installed script/package
---   ;version all        — List all installed packages with versions
---   ;version check      — Check for engine updates
---   ;version update     — Download and install engine updates
---   ;version channel    — Show or set update channel (stable, beta, dev)

local args = require("lib/args")
local parsed = args.parse(Script.vars[0] or "")
local cmd = parsed.args[1]

local REGISTRY_BASE = "https://sordal-gsiv.github.io/revenant-scripts"
local REGISTRY_URL  = REGISTRY_BASE .. "/manifest.json"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function get_channel()
    return Settings["version_channel"] or "stable"
end

local function find_engine_entry(data, channel)
    for _, script in ipairs(data.scripts or {}) do
        if script.name == "engine" then
            local ch = script.channels and script.channels[channel]
            return ch
        end
    end
    return nil
end

local function pad_dots(label, width)
    local pad = width - #label
    if pad < 1 then pad = 1 end
    return label .. string.rep(".", pad)
end

local function fmt(label, value, width)
    return pad_dots(label, width) .. ": " .. tostring(value)
end

--- Load installed package data from data/pkg/installed.lua.
local function load_installed()
    local ok, result = pcall(function()
        local raw = File.read("data/pkg/installed.lua")
        if not raw then return {} end
        local fn = load(raw)
        if not fn then return {} end
        return fn() or {}
    end)
    return ok and result or {}
end

--- Load autostart list from a settings store (global or char).
--- Returns a formatted string of entries, or "(none)".
local function fmt_autostart(store, key)
    local raw = store[key]
    if not raw then return "(none)" end
    local ok, t = pcall(Json.decode, raw)
    if not ok or type(t) ~= "table" or #t == 0 then return "(none)" end
    local parts = {}
    for _, entry in ipairs(t) do
        if type(entry) == "table" and entry.name then
            if type(entry.args) == "table" and #entry.args > 0 then
                parts[#parts + 1] = entry.name .. "(args: " .. table.concat(entry.args, " ") .. ")"
            else
                parts[#parts + 1] = entry.name
            end
        elseif type(entry) == "string" then
            parts[#parts + 1] = entry
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "(none)"
end

--- Read the version tag from a script file header.
--- Looks for "--- version: X.Y.Z" in the leading comment block.
local function get_script_file_version(path)
    local ok, content = pcall(File.read, path)
    if not ok or not content then return nil end
    for line in content:gmatch("[^\r\n]+") do
        -- Stop at the first non-comment, non-blank line
        if not line:match("^%-%-%-") and not line:match("^%s*$") then
            break
        end
        local ver = line:match("^%-%-%-.*version:%s*([%d%.]+)")
        if ver then return ver end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Subcommand: check  (engine update check)
-- ---------------------------------------------------------------------------

local function cmd_check()
    local current = Version.current()
    local channel = get_channel()
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

-- ---------------------------------------------------------------------------
-- Subcommand: update  (engine binary update)
-- ---------------------------------------------------------------------------

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

    local tmp = "data/pkg/revenant.new"
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

-- ---------------------------------------------------------------------------
-- Subcommand: channel  (manage update channel)
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Subcommand: default  (diagnostic summary)
-- ---------------------------------------------------------------------------

local function cmd_default()
    local msg = {}
    msg[#msg + 1] = "```"

    -- Engine / runtime
    local W1 = 22
    msg[#msg + 1] = fmt("Engine version",  Version.current(), W1)
    msg[#msg + 1] = fmt("Update channel",  get_channel(), W1)
    msg[#msg + 1] = fmt("Lua version",     _VERSION or "unknown", W1)
    msg[#msg + 1] = fmt("Platform",        (jit and jit.os .. "/" .. jit.arch) or "standard Lua", W1)
    msg[#msg + 1] = fmt("SQLite version",  Version.sqlite(), W1)
    local ok_gv, gv = pcall(Gui.version)
    msg[#msg + 1] = fmt("egui version",    ok_gv and gv or "n/a", W1)
    msg[#msg + 1] = ""

    -- Game state
    local game     = GameState.game or "unknown"
    local charname = GameState.name or "unknown"
    local lvl      = GameState.level or 0
    msg[#msg + 1] = fmt("Game",       game, W1)
    msg[#msg + 1] = fmt("Character",  charname, W1)
    msg[#msg + 1] = fmt("Level",      tostring(lvl), W1)
    msg[#msg + 1] = ""

    -- Frontend
    local ok_fe, frontend = pcall(function() return GameState.frontend end)
    if ok_fe and frontend and frontend ~= "" then
        msg[#msg + 1] = fmt("FrontEnd", frontend, W1)
    else
        msg[#msg + 1] = fmt("FrontEnd", "unknown", W1)
    end

    -- ;version self
    local self_version = get_script_file_version("version.lua")
    msg[#msg + 1] = fmt(";version", self_version or "unknown", W1)
    msg[#msg + 1] = ""

    -- Autostart lists
    local W1b = 22
    msg[#msg + 1] = fmt("Autostart global",  fmt_autostart(Settings, "autostart_global"), W1b)
    msg[#msg + 1] = fmt("Autostart " .. (charname ~= "unknown" and charname or "char"),
                         fmt_autostart(CharSettings, "autostart"), W1b)
    msg[#msg + 1] = ""

    -- Running scripts
    local running = Script.list()
    if type(running) == "table" and #running > 0 then
        msg[#msg + 1] = fmt("Running scripts", table.concat(running, ", "), W1b)
    else
        msg[#msg + 1] = fmt("Running scripts", "(none)", W1b)
    end

    -- Hooks
    local W2 = 22
    local ok_dh, dh = pcall(DownstreamHook.list)
    if ok_dh and type(dh) == "table" and #dh > 0 then
        msg[#msg + 1] = fmt("Downstream hooks", table.concat(dh, ", "), W2)
    else
        msg[#msg + 1] = fmt("Downstream hooks", "(none)", W2)
    end

    local ok_uh, uh = pcall(UpstreamHook.list)
    if ok_uh and type(uh) == "table" and #uh > 0 then
        msg[#msg + 1] = fmt("Upstream hooks", table.concat(uh, ", "), W2)
    else
        msg[#msg + 1] = fmt("Upstream hooks", "(none)", W2)
    end
    msg[#msg + 1] = ""

    -- Installed packages count
    local installed = load_installed()
    local pkg_count = 0
    for _ in pairs(installed) do pkg_count = pkg_count + 1 end
    msg[#msg + 1] = fmt("Installed packages", tostring(pkg_count), W2)

    -- DR: dependency script status (matches Ruby $DEPENDENCY_VERSION report)
    if game:upper():sub(1, 2) == "DR" then
        msg[#msg + 1] = ""
        local dep_status = Script.running("dependency") and "running" or "not running"
        msg[#msg + 1] = fmt("DR dependency", dep_status, W2)
    end

    msg[#msg + 1] = "```"
    msg[#msg + 1] = ""
    msg[#msg + 1] = "Use ;version info for detailed diagnostics."
    msg[#msg + 1] = "Use ;version <script> to check a specific script's version."
    msg[#msg + 1] = "Use ;version all to list all installed packages."
    msg[#msg + 1] = "Use ;version check to check for engine updates."

    respond(table.concat(msg, "\n"))
end

-- ---------------------------------------------------------------------------
-- Subcommand: info  (detailed diagnostics)
-- ---------------------------------------------------------------------------

local function cmd_info()
    local msg = {}
    msg[#msg + 1] = "```"

    -- Engine / runtime
    local W1 = 26
    msg[#msg + 1] = fmt("Engine version",  Version.current(), W1)
    msg[#msg + 1] = fmt("Engine path",     Version.engine_path(), W1)
    msg[#msg + 1] = fmt("Update channel",  get_channel(), W1)
    msg[#msg + 1] = fmt("Lua version",     _VERSION or "unknown", W1)
    msg[#msg + 1] = fmt("Platform",        (jit and jit.os .. "/" .. jit.arch) or "standard Lua", W1)
    msg[#msg + 1] = fmt("SQLite version",  Version.sqlite(), W1)
    local ok_gv, gv = pcall(Gui.version)
    msg[#msg + 1] = fmt("egui version",    ok_gv and gv or "n/a", W1)
    msg[#msg + 1] = ""

    -- Game state
    local game     = GameState.game or "unknown"
    local charname = GameState.name or "unknown"
    local lvl      = GameState.level or 0
    msg[#msg + 1] = fmt("Game",       game, W1)
    msg[#msg + 1] = fmt("Character",  charname, W1)
    msg[#msg + 1] = fmt("Level",      tostring(lvl), W1)

    -- Frontend
    local ok_fe, frontend = pcall(function() return GameState.frontend end)
    if ok_fe and frontend and frontend ~= "" then
        msg[#msg + 1] = fmt("FrontEnd", frontend, W1)
    else
        msg[#msg + 1] = fmt("FrontEnd", "unknown", W1)
    end

    -- ;version self
    local self_version = get_script_file_version("version.lua")
    msg[#msg + 1] = fmt(";version", self_version or "unknown", W1)
    msg[#msg + 1] = ""

    -- Data files
    local W3 = 32
    local game_short = game
    if game:lower():sub(1, 2) == "dr" then
        game_short = "DR"
    elseif game:lower():sub(1, 2) == "gs" then
        game_short = "GS3"
    end
    local data_prefix = "data/" .. game_short

    -- Map DB
    local map_found = false
    local ok_map, map_entries = pcall(File.list, data_prefix)
    if ok_map and type(map_entries) == "table" then
        for _, entry in ipairs(map_entries) do
            if entry:match("^map%-.*%.json$") or entry:match("^map%-.*%.dat$") or entry:match("^map%-.*%.xml$") then
                local full_path = data_prefix .. "/" .. entry
                local ok_mt, mtime = pcall(File.mtime, full_path)
                local ts = (ok_mt and mtime) and os.date("%Y-%m-%d %H:%M", mtime) or "unknown"
                msg[#msg + 1] = fmt("MapDB " .. entry, ts, W3)
                map_found = true
            end
        end
    end
    if not map_found then
        msg[#msg + 1] = fmt("MapDB", "not found", W3)
    end

    -- Data XML files
    local data_files = { "gameobj-data", "spell-list", "effect-list" }
    for _, basename in ipairs(data_files) do
        local found = false
        for _, dir in ipairs({ data_prefix, "scripts" }) do
            local path = dir .. "/" .. basename .. ".xml"
            local ok_ex, exists = pcall(File.exists, path)
            if ok_ex and exists then
                local ok_mt, mtime = pcall(File.mtime, path)
                local ts = (ok_mt and mtime) and os.date("%Y-%m-%d %H:%M", mtime) or "unknown"
                msg[#msg + 1] = fmt(basename .. " last modified", ts, W3)
                found = true
                break
            end
        end
        if not found then
            -- Skip silently if file doesn't exist (matches Ruby behavior)
        end
    end
    msg[#msg + 1] = ""

    -- Running scripts
    local W2 = 26
    local running = Script.list()
    if type(running) == "table" and #running > 0 then
        msg[#msg + 1] = fmt("Running scripts", table.concat(running, ", "), W2)
    else
        msg[#msg + 1] = fmt("Running scripts", "(none)", W2)
    end

    -- Hooks
    local ok_dh, dh = pcall(DownstreamHook.list)
    if ok_dh and type(dh) == "table" and #dh > 0 then
        msg[#msg + 1] = fmt("Downstream hooks", table.concat(dh, ", "), W2)
    else
        msg[#msg + 1] = fmt("Downstream hooks", "(none)", W2)
    end

    local ok_uh, uh = pcall(UpstreamHook.list)
    if ok_uh and type(uh) == "table" and #uh > 0 then
        msg[#msg + 1] = fmt("Upstream hooks", table.concat(uh, ", "), W2)
    else
        msg[#msg + 1] = fmt("Upstream hooks", "(none)", W2)
    end
    msg[#msg + 1] = ""

    -- Autostart lists (matches Ruby version.lic "Autostart global" / "Autostart <char>" lines)
    local char_label = "Autostart " .. (GameState.name or "char")
    msg[#msg + 1] = fmt("Autostart global", fmt_autostart(Settings, "autostart_global"), W2)
    msg[#msg + 1] = fmt(char_label,          fmt_autostart(CharSettings, "autostart"), W2)

    -- DR: dependency script status
    if (GameState.game or ""):upper():sub(1, 2) == "DR" then
        local dep_status = Script.running("dependency") and "running" or "not running"
        msg[#msg + 1] = fmt("DR dependency", dep_status, W2)
    end
    msg[#msg + 1] = ""

    -- Installed packages
    local installed = load_installed()
    local pkg_count = 0
    local pkg_names = {}
    for k in pairs(installed) do
        pkg_count = pkg_count + 1
        pkg_names[#pkg_names + 1] = k
    end
    table.sort(pkg_names)

    msg[#msg + 1] = fmt("Installed packages", tostring(pkg_count), W2)

    if pkg_count > 0 then
        for _, name in ipairs(pkg_names) do
            local info = installed[name]
            local ver = info.version or "?"
            msg[#msg + 1] = "  " .. string.format("%-24s %s", name, ver)
        end
    end

    msg[#msg + 1] = "```"
    respond(table.concat(msg, "\n"))
end

-- ---------------------------------------------------------------------------
-- Subcommand: all  (list all installed packages with versions)
-- ---------------------------------------------------------------------------

local function cmd_all()
    local installed = load_installed()
    local names = {}
    for k in pairs(installed) do
        names[#names + 1] = k
    end
    table.sort(names)

    if #names == 0 then
        respond("No packages installed.")
        return
    end

    local msg = {}
    msg[#msg + 1] = "```"
    msg[#msg + 1] = "Installed packages (" .. #names .. "):"
    msg[#msg + 1] = ""

    local known = {}
    local unknown = {}

    for _, name in ipairs(names) do
        local info = installed[name]
        local ver = info.version
        if ver then
            known[#known + 1] = name .. "==" .. ver
        else
            unknown[#unknown + 1] = name
        end
    end

    if #known > 0 then
        msg[#msg + 1] = "Installed script versions: " .. table.concat(known, ", ")
    end
    if #unknown > 0 then
        msg[#msg + 1] = "Unknown script versions: " .. table.concat(unknown, ", ")
    end

    msg[#msg + 1] = "```"
    respond(table.concat(msg, "\n"))
end

-- ---------------------------------------------------------------------------
-- Subcommand: <scriptname>  (check version of specific script(s))
-- ---------------------------------------------------------------------------

local function cmd_script_version(script_names)
    local msg = {}
    msg[#msg + 1] = "```"

    local known = {}
    local unknown = {}
    local errors = {}

    local installed = load_installed()

    for _, prefix in ipairs(script_names) do
        local found = false

        -- Check installed packages first (exact and prefix match)
        for pkg_name, info in pairs(installed) do
            if pkg_name == prefix or pkg_name:sub(1, #prefix) == prefix then
                local ver = info.version
                if ver then
                    known[#known + 1] = pkg_name .. "==" .. ver
                else
                    unknown[#unknown + 1] = pkg_name
                end
                found = true
            end
        end

        -- Check script files on disk (exact name match then prefix)
        local paths_to_check = {
            prefix .. ".lua",
            "lib/" .. prefix .. ".lua",
            "lib/gs/" .. prefix .. ".lua",
            "lib/dr/" .. prefix .. ".lua",
        }

        for _, path in ipairs(paths_to_check) do
            local ok_ex, exists = pcall(File.exists, path)
            if ok_ex and exists then
                local ok_ver, ver = pcall(get_script_file_version, path)
                if ok_ver and ver then
                    known[#known + 1] = prefix .. "==" .. ver
                    found = true
                elseif ok_ver then
                    unknown[#unknown + 1] = prefix
                    found = true
                else
                    errors[#errors + 1] = prefix
                    found = true
                end
                break
            end
        end

        if not found then
            -- Try listing scripts directory for prefix matches
            local ok_ls, entries = pcall(File.list, ".")
            if ok_ls and type(entries) == "table" then
                for _, entry in ipairs(entries) do
                    if entry:match("^" .. prefix) and entry:match("%.lua$") then
                        local name = entry:gsub("%.lua$", "")
                        local ok_ver, ver = pcall(get_script_file_version, entry)
                        if ok_ver and ver then
                            known[#known + 1] = name .. "==" .. ver
                        elseif ok_ver then
                            unknown[#unknown + 1] = name
                        else
                            errors[#errors + 1] = name
                        end
                        found = true
                    end
                end
            end
        end

        if not found then
            echo(prefix .. ": No matching scripts found!")
        end
    end

    if #known > 0 then
        msg[#msg + 1] = "Installed script versions: " .. table.concat(known, ", ")
    end
    if #unknown > 0 then
        msg[#msg + 1] = "Unknown script versions: " .. table.concat(unknown, ", ")
    end
    if #errors > 0 then
        msg[#msg + 1] = "Failed to retrieve data for: " .. table.concat(errors, ", ")
    end

    msg[#msg + 1] = "```"
    respond(table.concat(msg, "\n"))
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------

if not cmd then
    -- No arguments: show diagnostic summary (matches Ruby ;version with no args)
    cmd_default()
elseif cmd == "check" then
    cmd_check()
elseif cmd == "update" then
    cmd_update()
elseif cmd == "channel" then
    cmd_channel(parsed.args[2])
elseif cmd == "info" or cmd == "details" or cmd == "detail" or cmd == "full" then
    cmd_info()
elseif cmd == "all" then
    cmd_all()
else
    -- Treat remaining args as script names to look up
    local script_names = {}
    for i = 1, #parsed.args do
        script_names[#script_names + 1] = parsed.args[i]
    end
    cmd_script_version(script_names)
end
