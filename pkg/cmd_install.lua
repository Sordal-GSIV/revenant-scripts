local config = require("config")
local registry = require("registry")

local M = {}

-- Track scripts currently being installed to detect circular dependencies
local installing = {}

-- Compute the local install path for a single-file entry.
-- If the entry path starts with lib/, preserve that prefix so library files
-- land in scripts/lib/ rather than scripts/.
-- lib/ dependencies in entry.depends go through the same registry lookup and
-- download flow as regular scripts — the lib/ path convention is sufficient.
local function install_path(entry_path)
    if entry_path:match("^lib/") then
        return "lib/" .. entry_path:match("^lib/(.+)$")
    end
    return entry_path
end

local function download_single_file(base_url, channel, script_info)
    local url = registry.build_download_url(base_url, channel, script_info.path or (script_info.name .. ".lua"))
    local resp, err = Http.get(url)
    if not resp then
        return nil, "download failed: " .. tostring(err)
    end
    if resp.status ~= 200 then
        return nil, "download failed: HTTP " .. resp.status
    end
    return resp.body
end

local function download_package(base_url, channel, script_info, channel_info)
    local files = channel_info.files
    if not files or #files == 0 then
        return nil, "package has no file list in manifest"
    end

    local path = script_info.path or (script_info.name .. "/")
    local downloaded = {}

    for _, file_entry in ipairs(files) do
        local fname = type(file_entry) == "table" and file_entry.name or file_entry
        local url = registry.build_download_url(base_url, channel, path .. fname)
        local resp, err = Http.get(url)
        if not resp then
            return nil, "failed to download " .. fname .. ": " .. tostring(err)
        end
        if resp.status ~= 200 then
            return nil, "failed to download " .. fname .. ": HTTP " .. resp.status
        end

        -- Verify per-file hash if available
        if type(file_entry) == "table" and file_entry.sha256 then
            local hash = Crypto.sha256(resp.body)
            if hash ~= file_entry.sha256 then
                return nil, "SHA256 mismatch for " .. fname
                    .. " (expected " .. file_entry.sha256 .. ", got " .. hash .. ")"
            end
        end

        downloaded[#downloaded + 1] = { name = fname, content = resp.body }
    end

    return downloaded
end

local function is_package(channel_info)
    return channel_info.files and #channel_info.files > 0
end

function M.run(positional, flags)
    if #positional == 0 then
        respond("Usage: ;pkg install <name> [--channel=<ch>] [--repo=<name>] [--force]")
        return
    end

    local name = positional[1]

    -- Circular dependency detection
    if installing[name] then
        respond("Error: circular dependency detected: " .. name)
        return
    end
    installing[name] = true

    -- Wrap in pcall so installing[name] is always cleaned up
    local ok, err = pcall(function()
        local cfg = config.load_config()
        local installed = config.load_installed()

        -- Fetch manifests
        local manifests = registry.fetch_all_manifests(cfg, true)
        if #manifests == 0 then
            respond("Error: no registries available")
            return
        end

        -- Find script
        local match, find_err = registry.find_script(manifests, name, flags.repo)
        if not match then
            respond("Error: " .. find_err)
            return
        end

        -- Resolve channel
        local channel = flags.channel or config.get_channel(cfg, name)
        local channel_info = match.script.channels and match.script.channels[channel]
        if not channel_info then
            respond("Error: script '" .. name .. "' has no '" .. channel .. "' channel")
            local available = {}
            if match.script.channels then
                for ch, _ in pairs(match.script.channels) do
                    available[#available + 1] = ch
                end
            end
            if #available > 0 then
                respond("  Available channels: " .. table.concat(available, ", "))
            end
            return
        end

        -- Check if already installed
        if not flags.force and installed[name] then
            if installed[name].version == channel_info.version then
                respond(name .. " " .. channel_info.version .. " is already installed (use --force to reinstall)")
                return
            end
        end

        -- Check dependencies
        local depends = channel_info.depends or {}
        for _, dep_str in ipairs(depends) do
            local dep_name, dep_constraint = dep_str:match("^(%S+)%s*(.*)$")
            if dep_name then
                local dep_installed = installed[dep_name]
                if not dep_installed then
                    respond("  Installing dependency: " .. dep_name)
                    M.run({ dep_name }, { channel = flags.channel })
                    installed = config.load_installed()
                    dep_installed = installed[dep_name]
                end
                if dep_installed and dep_constraint ~= "" then
                    if not Version.satisfies(dep_installed.version, dep_constraint) then
                        respond("Warning: " .. dep_name .. " " .. dep_installed.version
                            .. " does not satisfy " .. dep_str)
                    end
                end
                -- Warn about transitive deps
                if dep_installed then
                    local dep_match, _ = registry.find_script(manifests, dep_name, nil)
                    if dep_match then
                        local dep_ch = config.get_channel(cfg, dep_name)
                        local dep_ch_info = dep_match.script.channels and dep_match.script.channels[dep_ch]
                        if dep_ch_info and dep_ch_info.depends and #dep_ch_info.depends > 0 then
                            for _, transitive in ipairs(dep_ch_info.depends) do
                                local t_name = transitive:match("^(%S+)")
                                if t_name and not installed[t_name] then
                                    respond("Warning: " .. dep_name .. " depends on " .. transitive
                                        .. " (not installed). Run: ;pkg install " .. t_name)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Download
        respond("Installing " .. name .. " " .. channel_info.version .. " (" .. channel .. ")...")
        local base_url = match.manifest.url

        if is_package(channel_info) then
            local files, dl_err = download_package(base_url, channel, match.script, channel_info)
            if not files then
                respond("Error: " .. dl_err)
                return
            end

            if channel_info.sha256 then
                table.sort(files, function(a, b) return a.name < b.name end)
                local combined = ""
                for _, f in ipairs(files) do
                    combined = combined .. f.content
                end
                local hash = Crypto.sha256(combined)
                if hash ~= channel_info.sha256 then
                    respond("Error: SHA256 mismatch for package " .. name)
                    return
                end
            end

            File.mkdir(name)
            for _, f in ipairs(files) do
                File.write(name .. "/" .. f.name, f.content)
            end

            installed[name] = {
                version = channel_info.version,
                channel = channel,
                registry = match.registry.name,
                sha256 = channel_info.sha256 or "",
                installed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                type = "package",
            }
        else
            local path = channel_info.path or (name .. ".lua")
            local content, dl_err = download_single_file(base_url, channel, { name = name, path = path })
            if not content then
                respond("Error: " .. dl_err)
                return
            end

            if channel_info.sha256 then
                local hash = Crypto.sha256(content)
                if hash ~= channel_info.sha256 then
                    respond("Error: SHA256 mismatch for " .. name
                        .. " (expected " .. channel_info.sha256 .. ", got " .. hash .. ")")
                    return
                end
            end

            local raw_dest = path:match("%.lua$") and path or (name .. ".lua")
            local dest = install_path(raw_dest)
            -- Ensure lib/ subdirectory exists for library files
            if dest:match("^lib/") then
                File.mkdir("lib")
            end
            File.write(dest, content)

            installed[name] = {
                version = channel_info.version,
                channel = channel,
                registry = match.registry.name,
                sha256 = channel_info.sha256 or "",
                installed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                type = "single",
                path = dest,
            }
        end

        config.save_installed(installed)
        respond("Installed " .. name .. " " .. channel_info.version .. " from " .. match.registry.name)
    end)

    -- Always clean up the installing flag
    installing[name] = nil

    if not ok then
        respond("Error installing " .. name .. ": " .. tostring(err))
    end
end

return M
