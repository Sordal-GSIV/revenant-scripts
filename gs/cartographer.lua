--- @revenant-script
--- name: cartographer
--- version: 1.0.0
--- author: Ondreian
--- contributor: Claude Code
--- game: gs
--- description: Downloads and loads Elanthia Online mapdb releases from GitHub with version management
--- tags: map,navigation,mapdb
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from Lich5):
---   v1.0.0: initial Revenant Lua conversion
---   - Http.get/Http.request used in place of Ruby Net::HTTP
---   - File.* API (sandboxed) replaces FileUtils/File
---   - Map.load() used directly (replaces Map.load_json + Map.clear pattern)
---   - stringprocs.tar.gz skipped: contains Ruby .rb eval files, not applicable in Lua
---   - Version tracked in CharSettings.cartographer_version across sessions
---   - Http.get timeout raised to 120s for large mapdb.json downloads
---
--- Usage:
---   ;cartographer                   -- Download and load latest release
---   ;cartographer --version 0.2.0   -- Download and load specific version
---   ;cartographer --list            -- List downloaded versions
---   ;cartographer --load 0.2.0      -- Load specific downloaded version
---   ;cartographer --check           -- Check current loaded version
---   ;cartographer --force           -- Force re-download of latest version
---   ;cartographer --info            -- Show architecture and storage information
---   ;cartographer --prune           -- Remove all but the 3 newest versions
---   ;cartographer --help            -- Show this help

local VERSION         = "1.0.0"
local GITHUB_API_BASE = "https://api.github.com/repos/elanthia-online/mapdb"

-- ============================================================
-- Storage paths (all relative to scripts_dir, sandboxed)
-- ============================================================
local function cart_dir()
    return "data/" .. GameState.game .. "/_cartographer"
end

local function version_dir(ver)
    return cart_dir() .. "/" .. ver
end

local function version_mapdb_path(ver)
    return version_dir(ver) .. "/mapdb.json"
end

-- ============================================================
-- Version tracking (persisted in CharSettings across sessions)
-- ============================================================
local _loaded_version = CharSettings.cartographer_version or nil

local function set_loaded_version(ver)
    _loaded_version = ver
    CharSettings.cartographer_version = ver
end

-- ============================================================
-- Semver comparison
-- ============================================================
local function parse_version_parts(v)
    local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)$")
    if a then return tonumber(a), tonumber(b), tonumber(c) end
    return tonumber(v) or 0, 0, 0
end

local function version_compare(a, b)
    local a1, a2, a3 = parse_version_parts(a)
    local b1, b2, b3 = parse_version_parts(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

-- ============================================================
-- Format bytes as human-readable string
-- ============================================================
local function format_size(bytes)
    if bytes < 1024 then
        return bytes .. "B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1fKB", bytes / 1024.0)
    else
        return string.format("%.1fMB", bytes / (1024.0 * 1024.0))
    end
end

-- ============================================================
-- get_local_versions() → table of version strings, newest first
-- File.list appends "/" to directory entries; strip it before matching.
-- ============================================================
local function get_local_versions()
    local entries, _ = File.list(cart_dir())
    if not entries then return {} end

    local versions = {}
    for _, entry in ipairs(entries) do
        local name = entry:gsub("/$", "")   -- strip trailing "/" added by File.list
        if File.is_dir(cart_dir() .. "/" .. name) and name:match("^%d+%.%d+%.%d+$") then
            table.insert(versions, name)
        end
    end

    table.sort(versions, function(a, b) return version_compare(a, b) > 0 end)
    return versions
end

-- ============================================================
-- show_help
-- ============================================================
local function show_help()
    respond("Cartographer v" .. VERSION)
    respond("Downloads and manages Elanthia Online mapdb releases from GitHub")
    respond("")
    respond("Usage:")
    respond("  ;cartographer                   -- Download and load latest release")
    respond("  ;cartographer --version 0.2.0   -- Download and load specific version")
    respond("  ;cartographer --list            -- List downloaded versions")
    respond("  ;cartographer --load 0.2.0      -- Load specific downloaded version")
    respond("  ;cartographer --check           -- Check current loaded version")
    respond("  ;cartographer --force           -- Force re-download of latest version")
    respond("  ;cartographer --info            -- Show architecture and storage information")
    respond("  ;cartographer --prune           -- Remove all but the 3 newest versions")
    respond("  ;cartographer --help            -- Show this help")
    respond("")
    respond("Data directory: " .. cart_dir())
end

-- ============================================================
-- check_current_version
-- ============================================================
local function check_current_version()
    if _loaded_version then
        respond("Currently loaded cartographer version: " .. _loaded_version)
    else
        respond("No cartographer version currently loaded")
    end
end

-- ============================================================
-- list_versions
-- ============================================================
local function list_versions()
    local versions = get_local_versions()

    if #versions == 0 then
        respond("No cartographer versions downloaded")
        respond("Use ';cartographer' to download the latest version")
        return
    end

    respond("Downloaded cartographer versions:")
    for _, ver in ipairs(versions) do
        local vmapdb = version_mapdb_path(ver)
        local components = {}
        local size_str   = ""

        if File.exists(vmapdb) then
            table.insert(components, "mapdb")
            local content, _ = File.read(vmapdb)
            size_str = content and format_size(#content) or "unknown size"
        end

        local mtime, _ = File.mtime(version_dir(ver))
        local mtime_str = mtime and os.date("%Y-%m-%d %H:%M:%S", mtime) or "unknown"
        local current   = (_loaded_version == ver) and " (current)" or ""
        local comps     = #components > 0 and table.concat(components, "+") or "empty"

        respond("  " .. ver .. " (" .. size_str .. ", " .. mtime_str .. ", " .. comps .. ")" .. current)
    end
end

-- ============================================================
-- show_info
-- ============================================================
local function show_info()
    respond("Cartographer Architecture Information")
    respond("====================================")
    respond("")
    respond("Data Directory: " .. cart_dir())
    respond("Directory exists: " .. (File.is_dir(cart_dir()) and "Yes" or "No"))

    if File.is_dir(cart_dir()) then
        local versions = get_local_versions()
        if #versions > 0 then
            respond("Downloaded versions: " .. #versions)
            respond("Newest version: " .. versions[1])
            respond("Oldest version: " .. versions[#versions])

            if _loaded_version then
                local vmapdb = version_mapdb_path(_loaded_version)
                if File.exists(vmapdb) then
                    local content, _ = File.read(vmapdb)
                    local size_str   = content and format_size(#content) or "unknown"
                    respond("Currently loaded: " .. _loaded_version .. " (" .. size_str .. ")")
                end
            else
                respond("Currently loaded: None")
            end
        else
            respond("No versions downloaded")
        end
    end

    respond("")
    respond("GitHub Repository: https://github.com/elanthia-online/mapdb")
    respond("Release API: " .. GITHUB_API_BASE .. "/releases")
    respond("")
    respond("Map class integration: Available")
    respond("Currently loaded rooms: " .. Map.room_count())
end

-- ============================================================
-- prune_old_versions: keep the 3 newest
-- ============================================================
local function prune_old_versions()
    local versions = get_local_versions()

    if #versions <= 3 then
        respond("Only " .. #versions .. " version(s) downloaded, nothing to prune")
        return
    end

    local to_keep   = {}
    local to_remove = {}
    for i, ver in ipairs(versions) do
        if i <= 3 then
            table.insert(to_keep, ver)
        else
            table.insert(to_remove, ver)
        end
    end

    respond("Keeping " .. #to_keep .. " newest versions: " .. table.concat(to_keep, ", "))
    respond("Removing " .. #to_remove .. " older versions: " .. table.concat(to_remove, ", "))

    if _loaded_version then
        for _, ver in ipairs(to_remove) do
            if ver == _loaded_version then
                respond("Warning: Currently loaded version " .. _loaded_version .. " will be removed!")
                respond("You may want to load a newer version first with: ;cartographer --load " .. to_keep[1])
                break
            end
        end
    end

    -- Calculate space to be freed (sum of mapdb.json sizes in affected dirs)
    local freed = 0
    for _, ver in ipairs(to_remove) do
        local vmapdb = version_mapdb_path(ver)
        if File.exists(vmapdb) then
            local content, _ = File.read(vmapdb)
            if content then freed = freed + #content end
        end
    end
    respond("Space to be freed: " .. format_size(freed))
    respond("")
    respond("Pruning old versions...")

    local removed = 0
    for _, ver in ipairs(to_remove) do
        local vdir = version_dir(ver)
        if File.is_dir(vdir) then
            local ok, err = File.remove(vdir)
            if ok then
                respond("  Removed version " .. ver)
                removed = removed + 1
            else
                respond("  Error removing " .. ver .. ": " .. (err or "unknown"))
            end
        else
            respond("  Version " .. ver .. " directory already missing")
        end
    end

    respond("")
    respond("Pruning complete: removed " .. removed .. " version(s), freed " .. format_size(freed))

    local remaining = get_local_versions()
    if #remaining > 0 then
        respond("Remaining versions: " .. table.concat(remaining, ", "))
    end
end

-- ============================================================
-- validate_mapdb: check JSON is a non-empty array of rooms
-- ============================================================
local function validate_mapdb(content)
    respond("Validating downloaded mapdb...")

    local ok, data = pcall(function() return Json.decode(content) end)
    if not ok or not data then
        respond("Error: Invalid JSON in mapdb")
        return false
    end

    if type(data) ~= "table" or #data == 0 then
        respond("Error: mapdb should be a non-empty array of rooms")
        return false
    end

    -- Sample the first 5 rooms for required fields
    for i = 1, math.min(5, #data) do
        local room = data[i]
        if type(room) ~= "table" or room.id == nil or room.title == nil then
            respond("Error: Room " .. i .. " missing required fields (id, title)")
            return false
        end
    end

    respond("Validation passed: " .. #data .. " rooms")
    return true
end

-- ============================================================
-- test_map_functionality: quick sanity check after load
-- ============================================================
local function test_map_functionality()
    respond("Testing map functionality...")

    local room_count = Map.room_count()
    respond("  [ok] Total rooms: " .. room_count)

    if room_count > 0 then
        local ids = Map.list()
        if #ids > 0 then
            local sample_id = ids[1]
            local room      = Map.find_room(sample_id)
            if room then
                respond("  [ok] Sample room: #" .. sample_id .. " - " .. (room.title or "(no title)"))
                respond("  [ok] Room lookup working")
            end
        end
    end

    respond("Map functionality test completed!")
end

-- ============================================================
-- map_post_install_hooks: run dependent scripts if present
-- ============================================================
local function map_post_install_hooks()
    if Script.exists("teleport")                then Script.run("teleport") end
    if Script.exists("cartographer_post_install") then Script.run("cartographer_post_install") end
end

-- ============================================================
-- load_version: load a previously downloaded version by name
-- ============================================================
local function load_version(ver)
    ver = ver:gsub("^v", "")   -- normalize: strip leading 'v'

    local mapdb_path = version_mapdb_path(ver)
    if not File.exists(mapdb_path) then
        respond("Error: Version " .. ver .. " not found locally")
        local versions = get_local_versions()
        respond("Available versions: " .. (#versions > 0 and table.concat(versions, ", ") or "(none)"))
        respond("Use ';cartographer --version " .. ver .. "' to download it first")
        return false
    end

    respond("Loading cartographer version " .. ver .. "...")

    -- Map.load accepts relative paths (resolved from scripts_dir by Rust engine)
    if Map.load(mapdb_path) then
        set_loaded_version(ver)
        respond("Successfully loaded " .. Map.room_count() .. " rooms from cartographer version " .. ver)
        respond("Map database is now ready for use!")
        test_map_functionality()
        map_post_install_hooks()
        return true
    else
        respond("Error: Map.load() failed for cartographer version " .. ver)
        return false
    end
end

-- ============================================================
-- fetch_json: GET a GitHub API endpoint, return parsed table
-- Uses Http.request to set a proper User-Agent header.
-- ============================================================
local function fetch_json(url)
    local result, err = Http.request("GET", url, nil, {
        ["User-Agent"]  = "Revenant-Cartographer/" .. VERSION,
        ["Accept"]      = "application/vnd.github+json",
    })
    if not result then
        respond("Error fetching " .. url .. ": " .. (err or "unknown"))
        return nil
    end

    if result.status ~= 200 then
        respond("Error: HTTP " .. result.status .. " for " .. url)
        return nil
    end

    local ok, data = pcall(function() return Json.decode(result.body) end)
    if not ok or not data then
        respond("Error: Failed to parse JSON response from " .. url)
        return nil
    end

    return data
end

-- ============================================================
-- download_asset: GET binary/text content and save to a local path.
-- Uses Http.get with a 300-second timeout for large file support.
-- ============================================================
local function download_asset(url, local_path, description)
    respond("Downloading " .. description .. "...")

    -- 300 second (5 minute) timeout: mapdb.json can be 10+ MB on slow connections
    local result, err = Http.get(url, 300)
    if not result then
        respond("Error downloading " .. description .. ": " .. (err or "unknown"))
        return nil
    end

    if result.status ~= 200 then
        respond("Error: HTTP " .. result.status .. " downloading " .. description)
        return nil
    end

    local content = result.body
    respond("  Downloaded: " .. format_size(#content))

    local ok, werr = File.write(local_path, content)
    if not ok then
        respond("Error saving " .. description .. ": " .. (werr or "unknown"))
        return nil
    end

    return content   -- return content so caller can validate without re-reading
end

-- ============================================================
-- download_and_load_release: download assets and load
-- ============================================================
local function download_and_load_release(release_info, ver)
    local assets = release_info.assets
    if not assets then
        respond("Error: No assets in release info")
        return
    end

    -- Find mapdb.json asset
    local mapdb_asset      = nil
    local has_stringprocs  = false
    for _, asset in ipairs(assets) do
        if asset.name == "mapdb.json" then
            mapdb_asset = asset
        elseif asset.name == "stringprocs.tar.gz" then
            has_stringprocs = true
        end
    end

    if not mapdb_asset then
        respond("Error: mapdb.json not found in release assets")
        local names = {}
        for _, asset in ipairs(assets) do table.insert(names, asset.name) end
        respond("Available assets: " .. table.concat(names, ", "))
        return
    end

    -- Create version directory (File.mkdir uses create_dir_all)
    local vdir = version_dir(ver)
    if not File.is_dir(vdir) then
        File.mkdir(vdir)
    end

    local tmp_path   = vdir .. "/mapdb.tmp"
    local final_path = version_mapdb_path(ver)
    local mapdb_size = mapdb_asset.size and format_size(mapdb_asset.size) or "unknown size"

    -- Download
    local content = download_asset(
        mapdb_asset.browser_download_url,
        tmp_path,
        "mapdb.json (" .. mapdb_size .. ") for version " .. ver
    )
    if not content then
        File.remove(vdir)
        return
    end

    -- Validate before committing
    if not validate_mapdb(content) then
        File.remove(tmp_path)
        File.remove(vdir)
        respond("Error: Downloaded mapdb.json failed validation")
        return
    end

    -- Rename to final path
    File.replace(tmp_path, final_path)
    respond("Successfully downloaded and validated mapdb.json")

    -- stringprocs.tar.gz contains Ruby .rb eval files — not applicable in Lua runtime
    if has_stringprocs then
        respond("Note: stringprocs.tar.gz found but skipped (Ruby-only, not applicable in Lua runtime)")
        respond("      Complex wayto routes using Ruby StringProcs will use default timing.")
    else
        respond("Note: No stringprocs.tar.gz in this release (legacy format)")
    end

    load_version(ver)
end

-- ============================================================
-- download_and_load_latest
-- ============================================================
local function download_and_load_latest(force)
    respond("Fetching latest release information...")

    local release_info = fetch_json(GITHUB_API_BASE .. "/releases/latest")
    if not release_info then return end

    if not release_info.tag_name then
        respond("Error: No tag_name in release info")
        return
    end

    local ver = release_info.tag_name:gsub("^v", "")
    respond("Latest version: " .. ver)

    if not force and File.exists(version_mapdb_path(ver)) then
        respond("Version " .. ver .. " already downloaded, loading...")
        load_version(ver)
        return
    end

    download_and_load_release(release_info, ver)
end

-- ============================================================
-- download_and_load_version: fetch a specific named release
-- ============================================================
local function download_and_load_version(ver, force)
    local normalized = ver:gsub("^v", "")
    local api_ver    = ver:match("^v") and ver or ("v" .. ver)

    if not force and File.exists(version_mapdb_path(normalized)) then
        respond("Version " .. normalized .. " already downloaded, loading...")
        load_version(normalized)
        return
    end

    respond("Fetching release information for " .. api_ver .. "...")
    local release_info = fetch_json(GITHUB_API_BASE .. "/releases/tags/" .. api_ver)
    if not release_info then return end

    download_and_load_release(release_info, normalized)
end

-- ============================================================
-- Bootstrap: ensure cartographer storage directory exists
-- ============================================================
if not File.is_dir(cart_dir()) then
    File.mkdir(cart_dir())
end

-- ============================================================
-- Command dispatch
-- ============================================================
local cmd  = Script.vars[1]
local arg2 = Script.vars[2]

if cmd == "--help" or cmd == "-h" then
    show_help()
elseif cmd == "--list" or cmd == "-l" then
    list_versions()
elseif cmd == "--check" or cmd == "-c" then
    check_current_version()
elseif cmd == "--info" or cmd == "-i" then
    show_info()
elseif cmd == "--prune" or cmd == "-p" then
    prune_old_versions()
elseif cmd == "--force" then
    download_and_load_latest(true)
elseif cmd == "--load" then
    if arg2 then
        load_version(arg2)
    else
        respond("Error: --load requires a version number")
        respond("Example: ;cartographer --load 0.2.0")
    end
elseif cmd == "--version" or cmd == "-v" then
    if arg2 then
        download_and_load_version(arg2, false)
    else
        respond("Error: --version requires a version number")
        respond("Example: ;cartographer --version 0.2.0")
    end
else
    -- No command: download and load latest (skip if already current)
    download_and_load_latest(false)
end
