local config = require("config")

local M = {}

function M.run(positional, flags)
    local subcmd = positional[1]
    local cfg = config.load_config()

    if not subcmd or subcmd == "list" then
        if #cfg.registries == 0 then
            respond("No registries configured.")
            return
        end
        respond(string.format("%-20s %s", "Name", "URL"))
        respond(string.rep("-", 60))
        for _, reg in ipairs(cfg.registries) do
            respond(string.format("%-20s %s", reg.name, reg.url))
        end

    elseif subcmd == "add" then
        local name = positional[2]
        local url = positional[3]
        if not name or not url then
            respond("Usage: ;pkg repo add <name> <url>")
            return
        end
        -- Check for duplicate
        for _, reg in ipairs(cfg.registries) do
            if reg.name == name then
                respond("Error: registry '" .. name .. "' already exists")
                return
            end
        end
        cfg.registries[#cfg.registries + 1] = { name = name, url = url }
        config.save_config(cfg)
        respond("Added registry: " .. name .. " (" .. url .. ")")

    elseif subcmd == "remove" then
        local name = positional[2]
        if not name then
            respond("Usage: ;pkg repo remove <name>")
            return
        end
        local found = false
        for i, reg in ipairs(cfg.registries) do
            if reg.name == name then
                table.remove(cfg.registries, i)
                found = true
                break
            end
        end
        if found then
            config.save_config(cfg)
            respond("Removed registry: " .. name)
        else
            respond("Error: registry '" .. name .. "' not found")
        end

    else
        respond("Usage: ;pkg repo <list|add|remove>")
    end
end

return M
