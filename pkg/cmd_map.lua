local config = require("config")
local registry = require("registry")

local M = {}

local function get_game()
    local ok, gs = pcall(function() return GameState and GameState.game end)
    if ok and gs and gs ~= "" then return gs end
    return nil
end

local function game_label(game)
    if game == "GS3" then return "GemStone IV"
    elseif game == "DR" then return "DragonRealms"
    else return game or "Unknown"
    end
end

local function epoch_to_date(epoch)
    return os.date("%Y-%m-%d", epoch)
end

local function find_local_maps(game)
    local dir = "data/" .. game
    if not File.exists(dir) then return {} end
    local files = File.list(dir) or {}
    local maps = {}
    for _, f in ipairs(files) do
        if f:match("^map%-%d+%.json$") then
            maps[#maps + 1] = { name = f, path = dir .. "/" .. f }
        end
    end
    table.sort(maps, function(a, b) return a.name > b.name end)
    return maps
end

local function find_map_entry(manifest)
    for _, script in ipairs(manifest.scripts or {}) do
        if script.type == "map" then
            return script
        end
    end
    return nil
end

local function count_local_images(manifest, game)
    local dir = "data/" .. game
    local total = 0
    local present = 0
    for _, script in ipairs(manifest.scripts or {}) do
        if script.type == "map_image" then
            total = total + 1
            local fname = script.name
            if File.exists(dir .. "/" .. fname) then
                present = present + 1
            end
        end
    end
    return present, total
end

function M.run_info(game)
    local cfg = config.load_config()
    local map_regs = registry.get_registries(cfg, { map_only = true })
    if #map_regs == 0 then
        respond("No map registries configured. Log in to a game first, then run ;pkg map-update.")
        return
    end

    game = game or get_game()
    if not game then
        respond("Error: cannot determine game. Log in first.")
        return
    end

    local manifests = registry.fetch_all_manifests(cfg, true, { map_only = true })
    if #manifests == 0 then
        respond("Error: could not fetch any map registry manifests")
        return
    end

    local manifest = manifests[1].manifest
    local reg_name = manifests[1].registry.name
    local map_entry = find_map_entry(manifest)

    local local_maps = find_local_maps(game)
    local local_present, total_images = count_local_images(manifest, game)

    respond("Map Database (" .. game_label(game) .. ")")
    respond("  Registry:  " .. reg_name)

    if #local_maps > 0 then
        local local_mtime, _ = File.mtime(local_maps[1].path)
        respond("  Local:     " .. local_maps[1].name .. " (" .. epoch_to_date(local_mtime or 0) .. ")")
    else
        respond("  Local:     (none)")
    end

    if map_entry then
        local remote_name = "map-" .. map_entry.last_updated .. ".json"
        respond("  Remote:    " .. remote_name .. " (" .. epoch_to_date(map_entry.last_updated) .. ")")

        local local_epoch = 0
        if #local_maps > 0 then
            local_epoch = tonumber(local_maps[1].name:match("map%-(%d+)%.json")) or 0
        end
        if local_epoch >= map_entry.last_updated then
            respond("  Status:    Up to date")
        else
            respond("  Status:    Update available")
        end
    else
        respond("  Remote:    (not found in manifest)")
    end

    respond("  Images:    " .. local_present .. " / " .. total_images
        .. (total_images - local_present > 0
            and " (" .. (total_images - local_present) .. " missing — run ;pkg map-update to fetch)"
            or ""))
end

function M.run_update(game)
    local cfg = config.load_config()
    local map_regs = registry.get_registries(cfg, { map_only = true })
    if #map_regs == 0 then
        respond("No map registries configured. Log in to a game first, then run ;pkg map-update.")
        return
    end

    game = game or get_game()
    if not game then
        respond("Error: cannot determine game. Log in first.")
        return
    end

    local manifests = registry.fetch_all_manifests(cfg, false, { map_only = true })
    if #manifests == 0 then
        respond("Error: could not fetch any map registry manifests")
        return
    end

    local manifest = manifests[1].manifest
    local reg = manifests[1].registry
    local map_entry = find_map_entry(manifest)
    if not map_entry then
        respond("Error: no map database found in " .. reg.name)
        return
    end

    -- Ensure data directory exists
    local data_dir = "data/" .. game
    if not File.exists("data") then File.mkdir("data") end
    if not File.exists(data_dir) then File.mkdir(data_dir) end

    -- Check local state
    local local_maps = find_local_maps(game)
    local needs_update = true
    if #local_maps > 0 then
        local local_epoch = tonumber(local_maps[1].name:match("map%-(%d+)%.json")) or 0
        if local_epoch >= map_entry.last_updated then
            respond("Map database is already up to date.")
            needs_update = false
        end
    end

    if needs_update then
        local base_url = reg.url:gsub("/$", ""):gsub("/manifest%.json$", "")
        local download_url = base_url .. map_entry.path
        respond("Downloading map database from " .. reg.name .. "...")
        local resp, err = Http.get(download_url)
        if not resp or resp.status ~= 200 then
            respond("Error: download failed: " .. tostring(err or ("HTTP " .. (resp and resp.status or "?"))))
            return
        end

        -- Verify hash on in-memory body
        if map_entry.hash_type == "sha1_base64" and map_entry.hash then
            local computed = Crypto.sha1_base64(resp.body)
            if computed ~= map_entry.hash then
                respond("Error: SHA1 mismatch (expected " .. map_entry.hash .. ", got " .. computed .. ")")
                return
            end
        end

        -- Write to disk
        local dest = data_dir .. "/map-" .. map_entry.last_updated .. ".json"
        File.write(dest, resp.body)
        respond("Map saved to " .. dest)

        -- Clean up old map files (keep 3 most recent)
        local all_maps = find_local_maps(game)
        for i = 4, #all_maps do
            File.remove(all_maps[i].path)
        end

        -- Hot-swap map data
        Map.load(dest)
        respond("Map reloaded.")

        -- Verify StringProc translations against new map data
        local ok_sp, stringproc = pcall(require, "lib/stringproc")
        if ok_sp then
            local result = stringproc.verify_all(game)
            if result and result.stale and #result.stale > 0 then
                respond("Warning: " .. #result.stale .. " StringProc translations may be stale")
                for _, entry in ipairs(result.stale) do
                    respond("  Room " .. entry.from .. " -> " .. entry.to)
                end
            elseif result and result.total > 0 then
                respond("StringProc translations: " .. result.verified .. "/" .. result.total .. " verified")
            end
        end
    end

    -- Download missing images
    local images_downloaded = 0
    local images_skipped = 0
    local base_url = reg.url:gsub("/$", ""):gsub("/manifest%.json$", "")

    for _, script in ipairs(manifest.scripts or {}) do
        if script.type == "map_image" then
            local local_path = data_dir .. "/" .. script.name
            if File.exists(local_path) then
                images_skipped = images_skipped + 1
            else
                local img_url = base_url .. script.path
                local resp, err = Http.get(img_url)
                if resp and resp.status == 200 then
                    File.write(local_path, resp.body)
                    images_downloaded = images_downloaded + 1
                end
            end
        end
    end

    respond("")
    respond("Map update complete. " .. images_downloaded .. " new images downloaded, "
        .. images_skipped .. " already present.")
end

function M.run(positional, flags)
    local subcmd = positional[1]
    if subcmd == "update" or not subcmd then
        M.run_update()
    elseif subcmd == "info" then
        M.run_info()
    else
        respond("Usage: ;pkg map-update | ;pkg map-info")
    end
end

return M
