local config = require("config")
local registry = require("registry")

local M = {}

function M.run(positional, flags)
    if #positional == 0 then
        respond("Usage: ;pkg search <query>")
        return
    end

    local query = positional[1]:lower()
    local cfg = config.load_config()
    local manifests = registry.fetch_all_manifests(cfg, false)

    if #manifests == 0 then
        respond("Error: no registries available")
        return
    end

    local results = {}
    for _, entry in ipairs(manifests) do
        for _, script in ipairs(entry.manifest.scripts or {}) do
            local match = false
            if script.name:lower():find(query, 1, true) then match = true end
            if script.description and script.description:lower():find(query, 1, true) then match = true end
            if script.tags then
                for _, tag in ipairs(script.tags) do
                    if tag:lower():find(query, 1, true) then match = true end
                end
            end
            if match then
                results[#results + 1] = {
                    name = script.name,
                    description = script.description or "",
                    registry = entry.registry.name,
                    channels = script.channels,
                }
            end
        end
    end

    if #results == 0 then
        respond("No scripts found matching '" .. query .. "'")
        return
    end

    respond(string.format("%-20s %-12s %s", "Name", "Registry", "Description"))
    respond(string.rep("-", 70))
    for _, r in ipairs(results) do
        local desc = r.description
        if #desc > 36 then desc = desc:sub(1, 33) .. "..." end
        respond(string.format("%-20s %-12s %s", r.name, r.registry, desc))
    end
    respond("")
    respond(#results .. " result(s)")
end

return M
