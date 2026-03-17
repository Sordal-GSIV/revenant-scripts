local M = {}

--- Resolve a map image filename to a path, checking themed directory first.
--- Falls back to standard maps/ directory if themed image doesn't exist.
--- @param filename string  The image filename (e.g. "en-ta_illistim_buildings.png")
--- @return string  The path to use with map_view:load_image()
function M.resolve_image(filename)
    local game = GameState.game
    local theme = Settings.map_theme
    if theme and theme ~= "" then
        local themed = "data/" .. game .. "/maps-" .. theme .. "/" .. filename
        if File.exists(themed) then return themed end
    end
    return "data/" .. game .. "/maps/" .. filename
end

return M
