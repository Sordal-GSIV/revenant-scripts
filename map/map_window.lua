local M = {}

function M.build(state, map_index)
    local win = Gui.window("Map", {
        width = state.window_width,
        height = state.window_height,
        resizable = true,
    })

    -- Root layout
    local root = Gui.vbox()

    -- Toolbar
    local toolbar = Gui.hbox()
    local follow_btn = Gui.button(state.follow_mode and "Following" or "Follow")
    local tags_btn = Gui.button("Tags")
    local locations_btn = Gui.button("Locations")
    local maps_btn = Gui.button("Maps")
    local scale_pct = math.floor((state.global_scale or 1.0) * 100)
    local scale_btn = Gui.button("Scale: " .. scale_pct .. "%")
    local find_btn = Gui.button("Find")
    local notes_btn = Gui.button("Notes")
    local dark_btn = Gui.button(state.dark_mode and "Light" or "Dark")

    -- Add toolbar children
    toolbar:add(follow_btn)
    toolbar:add(tags_btn)
    toolbar:add(locations_btn)
    toolbar:add(maps_btn)
    toolbar:add(scale_btn)
    toolbar:add(find_btn)
    toolbar:add(notes_btn)
    toolbar:add(dark_btn)
    root:add(toolbar)

    -- Map view
    local map_view = Gui.map_view({ width = 600, height = 400 })
    root:add(map_view)

    -- Status label
    local status_label = Gui.label("")
    root:add(status_label)

    -- Assemble widget tree
    win:set_root(root)

    return {
        win = win,
        map_view = map_view,
        follow_btn = follow_btn,
        tags_btn = tags_btn,
        locations_btn = locations_btn,
        maps_btn = maps_btn,
        scale_btn = scale_btn,
        find_btn = find_btn,
        notes_btn = notes_btn,
        dark_btn = dark_btn,
        status_label = status_label,
    }
end

function M.update_map(widgets, image_path, scale)
    local ok, err = widgets.map_view:load_image(image_path)
    if not ok then
        respond("Map: failed to load image: " .. tostring(err))
        return false
    end
    widgets.map_view:set_scale(scale)
    -- Expanded canvas: MapView scroll area is automatically sized larger than
    -- the image to allow centering rooms at map edges. This is handled by the
    -- MapView widget's internal scroll behavior when scroll_padding is supported.
    return true
end

function M.update_marker(widgets, x1, y1, x2, y2)
    -- Place current room marker at the center of the bounding box
    -- map_view:set_marker uses room_id internally, but we need the room
    -- associated with these coords. The caller should pass room_id instead.
end

function M.update_room_marker(widgets, room)
    widgets.map_view:clear_markers()
    if room and room.id then
        widgets.map_view:set_marker(room.id, { color = "red", shape = "circle" })
    end
    -- Re-apply any active tag markers would need to be handled by caller
end

function M.show_tag_markers(widgets, room_ids)
    -- Add blue X markers for each room in the list
    for _, room_id in ipairs(room_ids) do
        widgets.map_view:set_marker(room_id, { color = "blue", shape = "x" })
    end
end

function M.show_location_markers(widgets, room_ids)
    for _, room_id in ipairs(room_ids) do
        widgets.map_view:set_marker(room_id, { color = "green", shape = "x" })
    end
end

function M.clear_tag_markers(widgets)
    -- Clear all markers, then re-add the current room marker
    -- Caller must re-add room marker after this
    widgets.map_view:clear_markers()
end

function M.update_title(widgets, room)
    if room then
        local title = "Map"
        if room.title and room.title ~= "" then
            title = "Map - " .. room.title
        end
        if room.id then
            title = title .. " [" .. room.id .. "]"
        end
        widgets.win:set_title(title)
    end
end

function M.center_on_room(widgets, room)
    if room and room.id then
        widgets.map_view:center_on(room.id)
    end
end

return M
