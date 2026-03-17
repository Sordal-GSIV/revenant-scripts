local config = require("config")
local adapter = require("manifest_adapter")

local M = {}

local SUPPORTED_MANIFEST_VERSION = 1

local function parse_github_url(url)
    local owner, repo = url:match("github%.com/([^/]+)/([^/]+)")
    if not owner then return nil, nil end
    repo = repo:gsub("%.git$", "")
    return owner, repo
end

local function fetch_github_manifest(reg, use_cache)
    local cache_file = config.CACHE_DIR .. "/manifest_" .. reg.name .. ".json"

    -- Check cache
    if use_cache and File.exists(cache_file) then
        local mtime = File.mtime(cache_file)
        if mtime and (os.time() - mtime) < config.CACHE_TTL then
            local cached = File.read(cache_file)
            if cached then
                local data = Json.decode(cached)
                if data then return data end
            end
        end
    end

    local owner, repo = parse_github_url(reg.url)
    if not owner then
        respond("  Warning: could not parse GitHub URL: " .. reg.url)
        return nil
    end

    local branch = reg.github_branch or "main"
    local api_url = "https://api.github.com/repos/" .. owner .. "/" .. repo
        .. "/git/trees/" .. branch .. "?recursive=1"

    respond("Fetching file list from " .. reg.name .. "...")
    local data, err = Http.get_json(api_url)
    if not data or not data.tree then
        respond("  Warning: could not fetch " .. reg.name .. ": " .. tostring(err))
        return nil
    end

    local prefix = reg.github_path or ""
    if prefix ~= "" and not prefix:match("/$") then
        prefix = prefix .. "/"
    end

    local scripts = {}
    for _, entry in ipairs(data.tree) do
        if entry.type == "blob" and entry.path:sub(1, #prefix) == prefix then
            local filename = entry.path:match("[^/]+$") or ""
            if filename:match("%.png$") or filename:match("%.jpg$") or filename:match("%.gif$") then
                scripts[#scripts + 1] = {
                    name = filename,
                    path = entry.path,
                    type = "map_image",
                    hash = nil,
                    hash_type = "none",
                }
            end
        end
    end

    local manifest = { scripts = scripts }

    -- Cache the result
    File.write(cache_file, Json.encode(manifest))

    return manifest
end

function M.fetch_manifest(registry, use_cache)
    if registry.format == "github" then
        return fetch_github_manifest(registry, use_cache)
    end

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

function M.build_github_download_url(registry, path)
    local owner, repo = parse_github_url(registry.url)
    if not owner then return nil end
    local branch = registry.github_branch or "main"
    return "https://raw.githubusercontent.com/" .. owner .. "/" .. repo
        .. "/" .. branch .. "/" .. path
end

return M
