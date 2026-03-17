local M = {}

function M.run(positional, flags)
    local theme = positional[1]

    if not theme then
        local current = Settings.map_theme
        if current and current ~= "" then
            respond("Current map theme: " .. current)
        else
            respond("Current map theme: default")
        end
        return
    end

    if theme == "default" or theme == "none" or theme == "standard" then
        Settings.map_theme = nil
        respond("Map theme reset to default.")
    else
        Settings.map_theme = theme
        respond("Map theme set to: " .. theme)
    end
end

return M
