local config = require("config")
local registry = require("registry")

local M = {}

function M.run(positional, flags)
    if #positional == 0 then
        respond("Usage: ;pkg info <name>")
        return
    end

    local name = positional[1]
    local cfg = config.load_config()
    local manifests = registry.fetch_all_manifests(cfg, true)
    local installed = config.load_installed()

    local match, err = registry.find_script(manifests, name, flags.repo)
    if not match then
        respond("Error: " .. err)
        return
    end

    local script = match.script
    respond("Name:        " .. script.name)
    respond("Author:      " .. (script.author or "unknown"))
    respond("Description: " .. (script.description or ""))
    respond("Registry:    " .. match.registry.name)

    if script.tags and #script.tags > 0 then
        respond("Tags:        " .. table.concat(script.tags, ", "))
    end

    respond("")
    respond("Channels:")
    if script.channels then
        for ch, info in pairs(script.channels) do
            local marker = ""
            if installed[name] and installed[name].version == info.version then
                marker = " [installed]"
            end
            local deps = ""
            if info.depends and #info.depends > 0 then
                deps = " (deps: " .. table.concat(info.depends, ", ") .. ")"
            end
            respond("  " .. ch .. ": " .. info.version .. marker .. deps)
        end
    end

    if installed[name] then
        respond("")
        respond("Installed:   " .. installed[name].version .. " (" .. (installed[name].channel or "?") .. ")")
        respond("Installed at: " .. (installed[name].installed_at or "?"))
    end
end

return M
