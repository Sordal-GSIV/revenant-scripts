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

local function image_dir(game, theme)
    if theme then
        return "data/" .. game .. "/maps-" .. theme
    end
    return "data/" .. game .. "/maps"
end

local function ensure_image_dirs(game, theme)
    if not File.exists("data") then File.mkdir("data") end
    local data_dir = "data/" .. game
    if not File.exists(data_dir) then File.mkdir(data_dir) end
    local img_dir = image_dir(game, theme)
    if not File.exists(img_dir) then File.mkdir(img_dir) end
end

local function migrate_flat_images(game)
    local data_dir = "data/" .. game
    local maps_dir = data_dir .. "/maps"
    if File.exists(maps_dir) then return end  -- already migrated
    local files = File.list(data_dir) or {}
    local images = {}
    for _, f in ipairs(files) do
        if f:match("%.png$") or f:match("%.jpg$") or f:match("%.gif$") then
            images[#images + 1] = f
        end
    end
    if #images == 0 then return end
    File.mkdir(maps_dir)
    for _, f in ipairs(images) do
        File.replace(data_dir .. "/" .. f, maps_dir .. "/" .. f)
    end
    respond("Migrated " .. #images .. " images to " .. maps_dir)
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

local function count_local_images(manifest, game, theme)
    local dir = image_dir(game, theme)
    local total = 0
    local present = 0
    for _, script in ipairs(manifest.scripts or {}) do
        if script.type == "map_image" then
            total = total + 1
            if File.exists(dir .. "/" .. script.name) then
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

    local local_maps = find_local_maps(game)

    respond("Map Database (" .. game_label(game) .. ")")

    if #local_maps > 0 then
        local local_mtime, _ = File.mtime(local_maps[1].path)
        respond("  Local:     " .. local_maps[1].name .. " (" .. epoch_to_date(local_mtime or 0) .. ")")
    else
        respond("  Local:     (none)")
    end

    for _, entry in ipairs(manifests) do
        local reg = entry.registry
        local manifest = entry.manifest
        local theme = reg.image_theme

        if not theme and reg.format ~= "github" then
            local map_entry = find_map_entry(manifest)
            if map_entry then
                local remote_name = "map-" .. map_entry.last_updated .. ".json"
                respond("  Remote:    " .. remote_name .. " (" .. epoch_to_date(map_entry.last_updated) .. ") [" .. reg.name .. "]")

                local local_epoch = 0
                if #local_maps > 0 then
                    local_epoch = tonumber(local_maps[1].name:match("map%-(%d+)%.json")) or 0
                end
                if local_epoch >= map_entry.last_updated then
                    respond("  Status:    Up to date")
                else
                    respond("  Status:    Update available")
                end
            end

            local present, total = count_local_images(manifest, game, nil)
            if total > 0 then
                respond("  Images:    " .. present .. " / " .. total .. " [" .. reg.name .. "]"
                    .. (total - present > 0
                        and " (" .. (total - present) .. " missing)"
                        or ""))
            end
        elseif theme then
            local present, total = count_local_images(manifest, game, theme)
            respond("  Images:    " .. present .. " / " .. total .. " [" .. reg.name .. ", theme=" .. theme .. "]"
                .. (total - present > 0
                    and " (" .. (total - present) .. " missing)"
                    or ""))
        end
    end
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

    -- Ensure base dirs and migrate flat images
    if not File.exists("data") then File.mkdir("data") end
    local data_dir = "data/" .. game
    if not File.exists(data_dir) then File.mkdir(data_dir) end
    migrate_flat_images(game)
    ensure_image_dirs(game, nil)  -- ensure maps/ exists even without jinx registry

    local manifests = registry.fetch_all_manifests(cfg, false, { map_only = true })
    if #manifests == 0 then
        respond("Error: could not fetch any map registry manifests")
        return
    end

    -- Pass 1: mapdb + standard images from non-themed, non-github registries
    for _, entry in ipairs(manifests) do
        local reg = entry.registry
        local manifest = entry.manifest
        if not reg.image_theme and reg.format ~= "github" then
            -- Download mapdb.json if present
            local map_entry = find_map_entry(manifest)
            if map_entry then
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

                    -- Verify hash
                    if map_entry.hash and map_entry.hash_type ~= "none" then
                        local computed
                        if map_entry.hash_type == "md5" then
                            computed = Crypto.md5(resp.body)
                        elseif map_entry.hash_type == "sha1_base64" then
                            computed = Crypto.sha1_base64(resp.body)
                        elseif map_entry.hash_type == "sha256" then
                            computed = Crypto.sha256(resp.body)
                        end
                        if computed and computed ~= map_entry.hash then
                            respond("Error: hash mismatch (expected " .. map_entry.hash .. ", got " .. computed .. ")")
                            return
                        end
                    end

                    local dest = data_dir .. "/map-" .. map_entry.last_updated .. ".json"
                    File.write(dest, resp.body)
                    respond("Map saved to " .. dest)

                    local all_maps = find_local_maps(game)
                    for i = 4, #all_maps do
                        File.remove(all_maps[i].path)
                    end

                    Map.load(dest)
                    respond("Map reloaded.")

                    local ok_sp, stringproc = pcall(require, "lib/stringproc")
                    if ok_sp then
                        local result = stringproc.verify_all(game)
                        if result and result.stale and #result.stale > 0 then
                            respond("Warning: " .. #result.stale .. " StringProc translations may be stale")
                            for _, e in ipairs(result.stale) do
                                respond("  Room " .. e.from .. " -> " .. e.to)
                            end
                        elseif result and result.total > 0 then
                            respond("StringProc translations: " .. result.verified .. "/" .. result.total .. " verified")
                        end
                    end
                end
            end

            -- Download standard images to maps/
            ensure_image_dirs(game, nil)
            local imgs_dir = image_dir(game, nil)
            local base_url = reg.url:gsub("/$", ""):gsub("/manifest%.json$", "")
            local downloaded, skipped = 0, 0
            for _, script in ipairs(manifest.scripts or {}) do
                if script.type == "map_image" then
                    local local_path = imgs_dir .. "/" .. script.name
                    if File.exists(local_path) then
                        skipped = skipped + 1
                    else
                        local img_url = base_url .. script.path
                        local resp = Http.get(img_url)
                        if resp and resp.status == 200 then
                            File.write(local_path, resp.body)
                            downloaded = downloaded + 1
                        end
                    end
                end
            end
            respond("Standard images: " .. downloaded .. " new, " .. skipped .. " present.")
        end
    end

    -- Pass 2: themed images from themed registries
    for _, entry in ipairs(manifests) do
        local reg = entry.registry
        local manifest = entry.manifest
        if reg.image_theme then
            ensure_image_dirs(game, reg.image_theme)
            local imgs_dir = image_dir(game, reg.image_theme)
            local downloaded, skipped = 0, 0
            for _, script in ipairs(manifest.scripts or {}) do
                if script.type == "map_image" then
                    local local_path = imgs_dir .. "/" .. script.name
                    if File.exists(local_path) then
                        skipped = skipped + 1
                    else
                        local img_url
                        if reg.format == "github" then
                            img_url = registry.build_github_download_url(reg, script.path)
                        else
                            local base_url = reg.url:gsub("/$", ""):gsub("/manifest%.json$", "")
                            img_url = base_url .. script.path
                        end
                        if img_url then
                            local resp = Http.get(img_url)
                            if resp and resp.status == 200 then
                                File.write(local_path, resp.body)
                                downloaded = downloaded + 1
                            end
                        end
                    end
                end
            end
            respond(reg.image_theme .. " images: " .. downloaded .. " new, " .. skipped .. " present.")
        end
    end

    respond("")
    respond("Map update complete.")
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
