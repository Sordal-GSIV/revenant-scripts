--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: nautical_charts_update
--- version: 1.1.1
--- author: Peggyanne
--- game: gs
--- tags: maps, nautical, updater, installer
--- description: Installer/updater for nautical charts map files from GitHub repos
---
--- Original Lich5 authors: Peggyanne
--- Ported to Revenant Lua from nautical-charts-update.lic v1.1.0
---
--- Usage: ;nautical_charts_update
---
--- Change Log:
---   March 4, 2026  - Initial Release (Peggyanne)
---   March 7, 2026  - Updated Map File Folders And Added Repo Info (Peggyanne)
---   March 18, 2026 - Implemented actual HTTP downloads for Revenant (port fix)

no_kill_all()

local MAP_DIR = GameState.map_dir or "maps"

local repos = {
    { user = "jmbreitfeld", repo = "OSAMaps",             path = "", local_dir = MAP_DIR .. "/OSAMaps/Maps" },
    { user = "jmbreitfeld", repo = "OSA-Backgrounds",     path = "", local_dir = MAP_DIR .. "/OSAMaps/Backgrounds" },
    { user = "jmbreitfeld", repo = "OSA-Ocean-Database",  path = "", local_dir = MAP_DIR .. "/OSAMaps/Database" },
    { user = "jmbreitfeld", repo = "OSA-Ship-Icons",      path = "", local_dir = MAP_DIR .. "/OSAMaps/Icons" },
}

local function sync_echo(msg)
    respond("[MapSync: " .. msg .. "]")
end

--- Download a single GitHub repo folder, comparing file sizes to skip unchanged files.
--- Returns number of files updated.
local function download_folder(user, repo, api_path, local_dir)
    -- Ensure local directory exists
    File.mkdir(local_dir)

    local api_url = "https://api.github.com/repos/" .. user .. "/" .. repo .. "/contents/" .. api_path

    -- Fetch directory listing from GitHub API
    local ok, result = pcall(Http.get_json, api_url)
    if not ok then
        sync_echo("Error fetching " .. repo .. "/" .. api_path .. ": " .. tostring(result))
        return 0
    end

    local data = result
    if type(data) ~= "table" then
        sync_echo("Error: " .. api_path .. " in " .. repo .. " is not a folder.")
        return 0
    end

    -- If the response is a table with a "message" key, it's an error (e.g., rate limit)
    if data.message then
        sync_echo("GitHub API error for " .. repo .. ": " .. tostring(data.message))
        return 0
    end

    local count = 0
    for _, file in ipairs(data) do
        -- Only download files, skip subdirectories
        if file.type == "file" and file.download_url then
            local file_name    = file.name
            local remote_size  = tonumber(file.size) or 0
            local download_url = file.download_url
            local local_path   = local_dir .. "/" .. file_name

            -- Only download if file is missing or size has changed
            local need_download = false
            if not File.exists(local_path) then
                need_download = true
            else
                -- Read existing file to check size
                local existing = File.read(local_path)
                if not existing or #existing ~= remote_size then
                    need_download = true
                end
            end

            if need_download then
                sync_echo("Downloading: " .. file_name .. " from " .. repo .. "...")
                local dl_ok, dl_result = pcall(Http.get, download_url)
                if dl_ok and dl_result and dl_result.body then
                    File.write(local_path, dl_result.body)
                    count = count + 1
                else
                    sync_echo("Failed to download " .. file_name .. ": " .. tostring(dl_result))
                end
            end
        end
    end

    return count
end

local function sync_all()
    sync_echo("Connecting to GitHub APIs...")

    local total = 0
    for _, r in ipairs(repos) do
        local updated = download_folder(r.user, r.repo, r.path, r.local_dir)
        total = total + updated
    end

    if total > 0 then
        sync_echo("Success! Updated " .. total .. " files from repositories.")
    else
        sync_echo("All files are up to date.")
    end
end

sync_all()
