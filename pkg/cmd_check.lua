local config = require("config")
local registry = require("registry")

local M = {}

function M.run(positional, flags)
    local cfg = config.load_config()
    local installed = config.load_installed()

    local count = 0
    for _ in pairs(installed) do count = count + 1 end

    if count == 0 then
        respond("No scripts installed via pkg.")
        return
    end

    -- Fetch fresh manifests
    local manifests = registry.fetch_all_manifests(cfg, false)
    if #manifests == 0 then
        respond("Error: no registries available")
        return
    end

    local updates_available = 0

    for name, info in pairs(installed) do
        local channel = config.get_channel(cfg, name)
        local match, _ = registry.find_script(manifests, name, info.registry)

        if match then
            local channel_info = match.script.channels and match.script.channels[channel]
            if channel_info and Version.compare(channel_info.version, info.version) > 0 then
                respond("  " .. name .. ": " .. info.version .. " -> " .. channel_info.version .. " (" .. channel .. ")")
                updates_available = updates_available + 1
            end
        end
    end

    if updates_available == 0 then
        respond("All " .. count .. " installed scripts are up to date.")
    else
        respond("")
        respond(updates_available .. " update(s) available. Run ;pkg update to install them.")
    end
end

return M
