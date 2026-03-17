--- @revenant-script
--- name: nautical_charts_update
--- version: 1.1.0
--- author: Peggyanne
--- game: gs
--- tags: maps, nautical, updater, installer
--- description: Installer/updater for nautical charts map files from GitHub repos
---
--- Original Lich5 authors: Peggyanne
--- Ported to Revenant Lua from nautical-charts-update.lic v1.1.0
---
--- Usage: ;nautical_charts_update
--- Note: Requires network access to GitHub API (stubbed for Revenant)

-- This script downloads map/background/JSON/icon files from GitHub repos.
-- In Revenant, network operations are handled differently than Ruby's open-uri.
-- This is a structural port; actual HTTP fetching requires Revenant's fetch API.

local MAP_DIR = GameState.map_dir or "maps"

local repos = {
    { user = "jmbreitfeld", repo = "OSAMaps",           local_dir = MAP_DIR .. "/OSAMaps/Maps" },
    { user = "jmbreitfeld", repo = "OSA-Backgrounds",   local_dir = MAP_DIR .. "/OSAMaps/Backgrounds" },
    { user = "jmbreitfeld", repo = "OSA-Ocean-Database", local_dir = MAP_DIR .. "/OSAMaps/Database" },
    { user = "jmbreitfeld", repo = "OSA-Ship-Icons",    local_dir = MAP_DIR .. "/OSAMaps/Icons" },
}

local function sync_echo(msg)
    respond("[MapSync: " .. msg .. "]")
end

local function download_folder(user, repo, local_dir)
    local api_url = "https://api.github.com/repos/" .. user .. "/" .. repo .. "/contents/"
    sync_echo("Would download from " .. api_url .. " to " .. local_dir)
    sync_echo("Network downloads require Revenant fetch API - please use ;repo download nautical-charts-update")
    return 0
end

local function sync_all()
    sync_echo("Connecting to GitHub APIs...")
    local total = 0
    for _, r in ipairs(repos) do
        total = total + download_folder(r.user, r.repo, r.local_dir)
    end
    if total > 0 then
        sync_echo("Success! Updated " .. total .. " files.")
    else
        sync_echo("All files are up to date (or network fetch not available in Revenant).")
    end
end

sync_all()
