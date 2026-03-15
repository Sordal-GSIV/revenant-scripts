local config = require("config")
local adapter = require("manifest_adapter")

local M = {}

local SUPPORTED_MANIFEST_VERSION = 1

function M.fetch_manifest(registry, use_cache)
    local cache_file = config.CACHE_DIR .. "/manifest_" .. registry.name .. ".json"

    -- Check cache
    if use_cache and File.exists(cache_file) then
        local mtime, err = File.mtime(cache_file)
        if mtime then
            local now = os.time()
            if (now - mtime) < config.CACHE_TTL then
                local cached, read_err = File.read(cache_file)
                if cached then
                    local data, json_err = Json.decode(cached)
                    if data then
                        return adapter.normalize(data, registry.format)
                    end
                end
            end
        end
    end

    -- Fetch from network
    respond("Fetching manifest from " .. registry.name .. "...")
    local data, err = Http.get_json(registry.url)
    if not data then
        respond("  Warning: could not fetch " .. registry.name .. ": " .. tostring(err))
        return nil
    end

    -- Check manifest version (only for revenant-format registries)
    local fmt = registry.format or "revenant"
    if fmt == "revenant" and data.manifest_version
        and data.manifest_version > SUPPORTED_MANIFEST_VERSION then
        respond("  Warning: " .. registry.name .. " uses manifest version "
            .. data.manifest_version .. " (supported: " .. SUPPORTED_MANIFEST_VERSION
            .. "). Skipping — you may need to update pkg.")
        return nil
    end

    -- Cache the raw data (before normalization)
    local json_str = Json.encode(data)
    File.write(cache_file, json_str)

    return adapter.normalize(data, registry.format)
end

function M.get_registries(cfg, opts)
    opts = opts or {}
    local result = {}
    for _, reg in ipairs(cfg.registries) do
        local is_map = reg.map_registry or false
        if opts.map_only and is_map then
            result[#result + 1] = reg
        elseif opts.scripts_only and not is_map then
            result[#result + 1] = reg
        elseif not opts.map_only and not opts.scripts_only then
            result[#result + 1] = reg
        end
    end
    return result
end

function M.fetch_all_manifests(cfg, use_cache, opts)
    local registries = M.get_registries(cfg, opts)
    local manifests = {}
    for _, registry in ipairs(registries) do
        local manifest = M.fetch_manifest(registry, use_cache)
        if manifest then
            manifests[#manifests + 1] = {
                registry = registry,
                manifest = manifest,
            }
        end
    end
    return manifests
end

function M.find_script(manifests, name, repo_filter)
    local matches = {}

    for _, entry in ipairs(manifests) do
        if not repo_filter or entry.registry.name == repo_filter then
            for _, script in ipairs(entry.manifest.scripts or {}) do
                if script.name == name then
                    matches[#matches + 1] = {
                        registry = entry.registry,
                        manifest = entry.manifest,
                        script = script,
                    }
                end
            end
        end
    end

    if #matches == 0 then
        return nil, "script '" .. name .. "' not found in any registry"
    elseif #matches == 1 then
        return matches[1]
    else
        local names = {}
        for _, m in ipairs(matches) do
            names[#names + 1] = m.registry.name
        end
        return nil, "script '" .. name .. "' found in multiple registries: "
            .. table.concat(names, ", ") .. ". Use --repo=<name> to specify."
    end
end

function M.build_download_url(base_url, channel, path)
    local branch = config.channel_to_branch(channel)
    -- Remove trailing slash from base_url
    base_url = base_url:gsub("/$", "")
    return base_url .. "/" .. branch .. "/" .. path
end

return M
