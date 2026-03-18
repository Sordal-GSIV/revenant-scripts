local M = {}

local function normalize_key(filename)
    if not filename then return nil end
    -- Strip extension, trailing -N digits, lowercase
    local key = filename:gsub("%.[^%.]+$", "")  -- strip extension
    key = key:gsub("%-[0-9]+$", "")              -- strip trailing -N
    return key:lower()
end

function M.build_index()
    local index = {
        maps = {},
        categories = {},
        all_tags = {},
        all_locations = {},
    }

    local tag_set = {}
    local location_set = {}
    local room_ids = Map.list()

    for _, room_id in ipairs(room_ids) do
        local room = Map.find_room(room_id)
        if room and room.image then
            local img = room.image
            -- Initialize map entry if not seen
            if not index.maps[img] then
                index.maps[img] = {
                    name = nil,  -- filled from meta:mapname or defaults to img
                    shortname = nil,
                    categories = {},  -- supports multiple categories
                    filename = img,
                }
            end

            -- Extract metadata from tags
            if room.tags then
                for _, tag in ipairs(room.tags) do
                    local mapname = tag:match("^meta:mapname:(.+)$")
                    if mapname then
                        index.maps[img].name = index.maps[img].name or mapname
                    end
                    local shortname = tag:match("^meta:mapshortname:(.+)$")
                    if shortname then
                        index.maps[img].shortname = index.maps[img].shortname or shortname
                    end
                    -- Support multiple categories per map (mapcategory:Cat or mapcategory:Cat:SubName)
                    local category = tag:match("^meta:mapcategory:(.+)$")
                    if category then
                        if not index.maps[img].categories then
                            index.maps[img].categories = {}
                        end
                        -- Parse "Category:SubName" format
                        local cat, subname = category:match("^(.-):(.*)")
                        if cat then
                            index.maps[img].categories[cat] = subname
                        else
                            index.maps[img].categories[category] = nil
                        end
                    end
                    -- Collect non-meta tags
                    if not tag:match("^meta:") then
                        tag_set[tag] = true
                    end
                end
            end

            -- Collect locations
            if room.location and room.location ~= "" then
                location_set[room.location] = true
            end
        end
    end

    -- Build category index — maps can appear under multiple categories
    for img, info in pairs(index.maps) do
        -- Fill in defaults for name/shortname
        info.name = info.name or info.filename or img
        info.shortname = info.shortname or info.name

        if info.categories and next(info.categories) then
            -- Map has categories — index under each one
            for cat, subname in pairs(info.categories) do
                if not index.categories[cat] then
                    index.categories[cat] = {}
                end
                local list = index.categories[cat]
                list[#list + 1] = img
                -- Store the per-category subname if available
                if subname and subname ~= "" then
                    info.categories[cat] = subname
                else
                    info.categories[cat] = info.shortname
                end
            end
        else
            -- No categories: put in Uncategorized
            if not index.categories["Uncategorized"] then
                index.categories["Uncategorized"] = {}
            end
            local list = index.categories["Uncategorized"]
            list[#list + 1] = img
        end
    end
    -- Sort each category's map list
    for _, list in pairs(index.categories) do
        table.sort(list)
    end

    -- Build sorted tag and location lists
    for tag in pairs(tag_set) do
        index.all_tags[#index.all_tags + 1] = tag
    end
    table.sort(index.all_tags)

    for loc in pairs(location_set) do
        index.all_locations[#index.all_locations + 1] = loc
    end
    table.sort(index.all_locations)

    return index
end

function M.image_for_room(room)
    if room and room.image then
        return room.image
    end
    return nil
end

function M.room_coords(room)
    if room and room.image_coords then
        return room.image_coords
    end
    return nil
end

function M.rooms_with_tag(tag)
    return Map.tags(tag) or {}
end

function M.rooms_in_location(location)
    local result = {}
    local room_ids = Map.list()
    for _, room_id in ipairs(room_ids) do
        local room = Map.find_room(room_id)
        if room and room.location == location then
            result[#result + 1] = room_id
        end
    end
    return result
end

function M.find_room_at(index, current_image, click_x, click_y)
    local room_ids = Map.list()
    for _, room_id in ipairs(room_ids) do
        local room = Map.find_room(room_id)
        if room and room.image == current_image and room.image_coords then
            local c = room.image_coords
            if click_x >= c[1] and click_x <= c[3]
               and click_y >= c[2] and click_y <= c[4] then
                return room_id
            end
        end
    end
    return nil
end

--- Resolve a map image path using the theme set by `pkg map-theme`.
--- Falls back: themed dir → standard maps/ dir.
--- @param image string  The image filename (e.g., "town_square.png")
--- @param game string   Game identifier (e.g., "gs" or "dr")
--- @param theme string|nil  Theme name (from Settings.map_theme), nil for default
--- @return string  The resolved path for map_view:load_image()
function M.resolve_image_path(image, game, theme)
    -- Check themed directory first (maps-dark/, maps-light/, etc.)
    if theme and theme ~= "" then
        local themed = "data/" .. game .. "/maps-" .. theme .. "/" .. image
        if File.exists(themed) then return themed end
    end
    -- Fall back to standard maps/ directory
    local standard = "data/" .. game .. "/maps/" .. image
    if File.exists(standard) then return standard end
    -- Final fallback: old flat structure (pre-migration)
    return "data/" .. game .. "/" .. image
end

--- List available map themes by scanning for maps-*/ directories.
--- @param game string  Game identifier
--- @return table  Array of theme names (e.g., {"dark", "light"})
function M.available_themes(game)
    local themes = {}
    local base = "data/" .. game .. "/"
    local entries = File.list(base)
    if entries then
        for _, entry in ipairs(entries) do
            local theme_name = entry:match("^maps%-(.+)$")
            if theme_name and File.is_dir(base .. entry) then
                themes[#themes + 1] = theme_name
            end
        end
    end
    table.sort(themes)
    return themes
end

return M
