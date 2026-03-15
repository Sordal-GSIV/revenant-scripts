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
        respond(string.format("%-20s %-8s %-4s %s", "Name", "Format", "Map", "URL"))
        respond(string.rep("-", 72))
        for _, reg in ipairs(cfg.registries) do
            respond(string.format("%-20s %-8s %-4s %s",
                reg.name,
                reg.format or "revenant",
                reg.map_registry and "yes" or "",
                reg.url))
        end

    elseif subcmd == "add" then
        local name = positional[2]
        local url = positional[3]
        if not name or not url then
            respond("Usage: ;pkg repo add <name> <url> [--format=jinx] [--map]")
            return
        end
        -- Check for duplicate
        for _, reg in ipairs(cfg.registries) do
            if reg.name == name then
                respond("Error: registry '" .. name .. "' already exists")
                return
            end
        end
        local format = flags.format or "revenant"
        local is_map = flags.map or false
        cfg.registries[#cfg.registries + 1] = {
            name = name,
            url = url,
            format = format,
            map_registry = is_map,
        }
        config.save_config(cfg)
        respond("Added registry: " .. name .. " (" .. url .. ")"
            .. (format ~= "revenant" and " [format=" .. format .. "]" or "")
            .. (is_map and " [map]" or ""))

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
