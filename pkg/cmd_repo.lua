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
        respond(string.format("%-20s %-8s %-8s %s", "Name", "Format", "Map", "URL"))
        respond(string.rep("-", 76))
        for _, reg in ipairs(cfg.registries) do
            local map_col = ""
            if reg.image_theme then
                map_col = reg.image_theme
            elseif reg.map_registry then
                map_col = "yes"
            end
            respond(string.format("%-20s %-8s %-8s %s",
                reg.name,
                reg.format or "revenant",
                map_col,
                reg.url))
        end

    elseif subcmd == "add" then
        local name = positional[2]
        local url = positional[3]
        if not name or not url then
            respond("Usage: ;pkg repo add <name> <url> [--format=<fmt>] [--map] [--theme=<t>] [--path=<p>] [--branch=<b>]")
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
        local image_theme = flags.theme or nil
        local github_path = flags.path or nil
        local github_branch = flags.branch or nil

        -- Validate github format requirements
        if format == "github" then
            if not github_path then
                respond("Error: --path is required for github format registries")
                return
            end
            if not image_theme then
                respond("Error: --theme is required for github format registries")
                return
            end
            is_map = true  -- github repos are always map registries
        end

        local entry = {
            name = name,
            url = url,
            format = format,
            map_registry = is_map,
        }
        if image_theme then entry.image_theme = image_theme end
        if github_path then entry.github_path = github_path end
        if github_branch then entry.github_branch = github_branch end

        cfg.registries[#cfg.registries + 1] = entry
        config.save_config(cfg)

        local notes = {}
        if format ~= "revenant" then notes[#notes + 1] = "format=" .. format end
        if is_map then notes[#notes + 1] = "map" end
        if image_theme then notes[#notes + 1] = "theme=" .. image_theme end
        respond("Added registry: " .. name .. " (" .. url .. ")"
            .. (#notes > 0 and " [" .. table.concat(notes, ", ") .. "]" or ""))

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
