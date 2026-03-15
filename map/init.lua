--- @revenant-script
--- name: map
--- version: 1.0.0
--- author: Sordal
--- depends: go2 >= 1.0
--- description: Interactive map viewer with room tracking and click-to-navigate

local map_data = require("map_data")
local map_window = require("map_window")
local settings = require("settings")

-- State
local state = settings.load()
local game = GameState.game or "GS3"
local current_room_id = nil
local current_image = nil
local active_tag = nil
local active_tag_rooms = {}

-- Build metadata index (one-time scan)
respond("Map: building room index...")
local index = map_data.build_index()
respond("Map: " .. #index.all_tags .. " tags, " .. #index.all_locations .. " locations indexed")

-- Build GUI
local widgets = map_window.build(state, index)

-- === Callbacks ===

-- Follow toggle
widgets.follow_btn:on_click(function()
    state.follow_mode = not state.follow_mode
    widgets.follow_btn:set_label(state.follow_mode and "Following" or "Follow")
end)

-- Click-to-navigate
widgets.map_view:on_click(function(room_id)
    if room_id then
        Script.run("go2", tostring(room_id))
    end
end)

-- Scale cycling
local scale_steps = { 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0 }
widgets.scale_btn:on_click(function()
    local current = settings.get_scale(state, current_image)
    local next_scale = scale_steps[1]
    for i, s in ipairs(scale_steps) do
        if s > current + 0.01 then
            next_scale = s
            break
        end
        if i == #scale_steps then
            next_scale = scale_steps[1]  -- wrap around
        end
    end
    settings.set_scale(state, current_image, next_scale)
    widgets.scale_btn:set_label("Scale: " .. math.floor(next_scale * 100) .. "%")
    if current_image then
        local image_path = map_data.resolve_image_path(current_image, game, state.dark_mode)
        map_window.update_map(widgets, image_path, next_scale)
        -- Re-apply markers
        local room = current_room_id and Map.find_room(current_room_id)
        if room then
            map_window.update_room_marker(widgets, room)
        end
        if active_tag and #active_tag_rooms > 0 then
            map_window.show_tag_markers(widgets, active_tag_rooms)
        end
    end
end)

-- Dark mode toggle
widgets.dark_btn:on_click(function()
    state.dark_mode = not state.dark_mode
    widgets.dark_btn:set_label(state.dark_mode and "Light" or "Dark")
    if current_image then
        local image_path = map_data.resolve_image_path(current_image, game, state.dark_mode)
        local scale = settings.get_scale(state, current_image)
        map_window.update_map(widgets, image_path, scale)
        local room = current_room_id and Map.find_room(current_room_id)
        if room then
            map_window.update_room_marker(widgets, room)
        end
        if active_tag and #active_tag_rooms > 0 then
            map_window.show_tag_markers(widgets, active_tag_rooms)
        end
    end
end)

-- Tags button — open selection sub-window
widgets.tags_btn:on_click(function()
    if #index.all_tags == 0 then
        respond("Map: no tags found in map data")
        return
    end
    local rows = {}
    for _, tag in ipairs(index.all_tags) do
        rows[#rows + 1] = { tag }
    end
    local tag_win = Gui.window("Select Tag", { width = 250, height = 400 })
    local tag_vbox = Gui.vbox()
    local clear_btn = Gui.button("Clear Tag Markers")
    local tag_table = Gui.table({ columns = { "Tag" }, rows = rows })
    tag_win:set_root(tag_vbox)

    clear_btn:on_click(function()
        active_tag = nil
        active_tag_rooms = {}
        map_window.clear_tag_markers(widgets)
        local room = current_room_id and Map.find_room(current_room_id)
        if room then
            map_window.update_room_marker(widgets, room)
        end
        tag_win:close()
    end)

    tag_table:on_click(function(row_idx)
        if row_idx and index.all_tags[row_idx] then
            active_tag = index.all_tags[row_idx]
            active_tag_rooms = map_data.rooms_with_tag(active_tag)
            map_window.clear_tag_markers(widgets)
            local room = current_room_id and Map.find_room(current_room_id)
            if room then
                map_window.update_room_marker(widgets, room)
            end
            map_window.show_tag_markers(widgets, active_tag_rooms)
            respond("Map: showing " .. #active_tag_rooms .. " rooms tagged '" .. active_tag .. "'")
            tag_win:close()
        end
    end)

    tag_win:show()
end)

-- Locations button — open selection sub-window
widgets.locations_btn:on_click(function()
    if #index.all_locations == 0 then
        respond("Map: no locations found in map data")
        return
    end
    local rows = {}
    for _, loc in ipairs(index.all_locations) do
        rows[#rows + 1] = { loc }
    end
    local loc_win = Gui.window("Select Location", { width = 300, height = 400 })
    local loc_vbox = Gui.vbox()
    local loc_table = Gui.table({ columns = { "Location" }, rows = rows })
    loc_win:set_root(loc_vbox)

    loc_table:on_click(function(row_idx)
        if row_idx and index.all_locations[row_idx] then
            local location = index.all_locations[row_idx]
            local loc_rooms = map_data.rooms_in_location(location)
            map_window.clear_tag_markers(widgets)
            local room = current_room_id and Map.find_room(current_room_id)
            if room then
                map_window.update_room_marker(widgets, room)
            end
            map_window.show_location_markers(widgets, loc_rooms)
            respond("Map: showing " .. #loc_rooms .. " rooms in '" .. location .. "'")
            loc_win:close()
        end
    end)

    loc_win:show()
end)

-- Maps button — open map selection sub-window
widgets.maps_btn:on_click(function()
    local rows = {}
    local map_list = {}
    for cat, maps in pairs(index.categories) do
        for _, img in ipairs(maps) do
            local info = index.maps[img]
            local display = info.name or img
            rows[#rows + 1] = { display, cat }
            map_list[#map_list + 1] = img
        end
    end
    if #rows == 0 then
        respond("Map: no maps found in index")
        return
    end
    local map_sel_win = Gui.window("Select Map", { width = 400, height = 500 })
    local map_vbox = Gui.vbox()
    local map_table = Gui.table({ columns = { "Map", "Category" }, rows = rows })
    map_sel_win:set_root(map_vbox)

    map_table:on_click(function(row_idx)
        if row_idx and map_list[row_idx] then
            local img = map_list[row_idx]
            current_image = img
            local image_path = map_data.resolve_image_path(img, game, state.dark_mode)
            local scale = settings.get_scale(state, img)
            map_window.update_map(widgets, image_path, scale)
            widgets.scale_btn:set_label("Scale: " .. math.floor(scale * 100) .. "%")
            -- Disable follow mode when manually selecting a map
            state.follow_mode = false
            widgets.follow_btn:set_label("Follow")
            map_sel_win:close()
        end
    end)

    map_sel_win:show()
end)

-- Find button — open find room sub-window
widgets.find_btn:on_click(function()
    local find_win = Gui.window("Find Room", { width = 350, height = 80 })
    local find_hbox = Gui.hbox()
    local find_input = Gui.input({ placeholder = "Room ID or name..." })
    local find_go_btn = Gui.button("Go")
    find_win:set_root(find_hbox)

    local function do_find()
        local text = find_input:get_text()
        if not text or text == "" then return end
        local room_id = tonumber(text)
        local room = nil
        if room_id then
            room = Map.find_room(room_id)
        else
            room = Map.find_room(text)
        end
        if room then
            local image = map_data.image_for_room(room)
            if image then
                current_image = image
                current_room_id = room.id
                local image_path = map_data.resolve_image_path(image, game, state.dark_mode)
                local scale = settings.get_scale(state, image)
                map_window.update_map(widgets, image_path, scale)
                map_window.update_room_marker(widgets, room)
                map_window.center_on_room(widgets, room)
                map_window.update_title(widgets, room)
                widgets.scale_btn:set_label("Scale: " .. math.floor(scale * 100) .. "%")
                -- Temporarily disable follow
                state.follow_mode = false
                widgets.follow_btn:set_label("Follow")
            end
            respond("Map: found room " .. room.id .. " — " .. (room.title or ""))
        else
            respond("Map: room not found: " .. text)
        end
        find_win:close()
    end

    find_go_btn:on_click(do_find)
    find_input:on_submit(do_find)
    find_win:show()
end)

-- === Room Tracking Hook ===

DownstreamHook.add("map_room_tracker", function(line)
    local new_id = GameState.room_id
    if new_id and new_id ~= current_room_id then
        current_room_id = new_id
        local room = Map.find_room(new_id)
        if room and state.follow_mode then
            local image = map_data.image_for_room(room)
            if image then
                local image_path = map_data.resolve_image_path(image, game, state.dark_mode)
                if image ~= current_image then
                    current_image = image
                    local scale = settings.get_scale(state, image)
                    map_window.update_map(widgets, image_path, scale)
                    widgets.scale_btn:set_label("Scale: " .. math.floor(scale * 100) .. "%")
                    if active_tag and #active_tag_rooms > 0 then
                        map_window.show_tag_markers(widgets, active_tag_rooms)
                    end
                end
                map_window.update_room_marker(widgets, room)
                if state.keep_centered then
                    map_window.center_on_room(widgets, room)
                end
            end
            map_window.update_title(widgets, room)
        end
    end
    return line
end)

-- === Cleanup ===

before_dying(function()
    DownstreamHook.remove("map_room_tracker")
    settings.save(state)
end)

-- === Startup ===

-- If a room arg was passed, jump to it
local target_arg = Script.vars[1]
if target_arg then
    local room_id = tonumber(target_arg)
    local room = room_id and Map.find_room(room_id) or Map.find_room(target_arg)
    if room then
        local image = map_data.image_for_room(room)
        if image then
            current_image = image
            current_room_id = room.id
            local image_path = map_data.resolve_image_path(image, game, state.dark_mode)
            local scale = settings.get_scale(state, image)
            map_window.update_map(widgets, image_path, scale)
            map_window.update_room_marker(widgets, room)
            map_window.center_on_room(widgets, room)
            map_window.update_title(widgets, room)
        end
        -- Don't follow when started with a specific room
        state.follow_mode = false
        widgets.follow_btn:set_label("Follow")
    else
        respond("Map: room not found: " .. target_arg)
    end
else
    -- Try to show current room on startup
    local room_id = GameState.room_id
    if room_id then
        local room = Map.find_room(room_id)
        if room then
            current_room_id = room_id
            local image = map_data.image_for_room(room)
            if image then
                current_image = image
                local image_path = map_data.resolve_image_path(image, game, state.dark_mode)
                local scale = settings.get_scale(state, image)
                map_window.update_map(widgets, image_path, scale)
                map_window.update_room_marker(widgets, room)
                map_window.center_on_room(widgets, room)
                map_window.update_title(widgets, room)
            end
        end
    end
end

-- Show window and block until closed
widgets.win:show()
Gui.wait(widgets.win, "close")
