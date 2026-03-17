local M = {}

--- Resolve a map image filename to a path, checking themed directory first.
--- Falls back to standard maps/ directory if themed image doesn't exist.
--- Uses Settings.map_theme for the active theme (set via `;pkg map-theme`).
--- @param filename string  The image filename (e.g. "en-ta_illistim_buildings.png")
--- @return string  The path to use with map_view:load_image()
function M.resolve_image(filename)
    local game = GameState.game
    local theme = Settings.map_theme
    if theme and theme ~= "" then
        local themed = "data/" .. game .. "/maps-" .. theme .. "/" .. filename
        if File.exists(themed) then return themed end
    end
    local standard = "data/" .. game .. "/maps/" .. filename
    if File.exists(standard) then return standard end
    -- Final fallback: old flat structure
    return "data/" .. game .. "/" .. filename
end

return M
