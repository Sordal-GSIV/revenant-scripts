local config = require("config")
local registry = require("registry")

local M = {}

function M.run(positional, flags)
    local cfg = config.load_config()
    local installed = config.load_installed()

    -- Fetch fresh manifests (bypass cache)
    local manifests = registry.fetch_all_manifests(cfg, false)
    if #manifests == 0 then
        respond("Error: no registries available")
        return
    end

    local target_name = positional[1]
    local updated = 0
    local current = 0
    local errors = 0

    local scripts_to_check = {}
    if target_name then
        if not installed[target_name] then
            respond("Error: " .. target_name .. " is not installed")
            return
        end
        scripts_to_check[target_name] = installed[target_name]
    else
        scripts_to_check = installed
    end

    for name, info in pairs(scripts_to_check) do
        local channel = config.get_channel(cfg, name)
        local match, err = registry.find_script(manifests, name, info.registry)

        if not match then
            respond("  " .. name .. ": not found in registry (skipping)")
            errors = errors + 1
        else
            local channel_info = match.script.channels and match.script.channels[channel]
            if not channel_info then
                respond("  " .. name .. ": no '" .. channel .. "' channel available")
                errors = errors + 1
            elseif Version.compare(channel_info.version, info.version) > 0 then
                respond("  Updating " .. name .. " " .. info.version .. " -> " .. channel_info.version)
                -- Use install command to handle the actual download
                local install = require("cmd_install")
                install.run({ name }, { channel = channel, force = true })
                updated = updated + 1
            else
                current = current + 1
            end
        end
    end

    respond("")
    respond("Update complete: " .. updated .. " updated, " .. current .. " current, " .. errors .. " errors")
end

return M
