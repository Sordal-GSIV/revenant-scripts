local M = {}

function M.build(state, map_index)
    local win = Gui.window("Map", {
        width = state.window_width,
        height = state.window_height,
        resizable = true,
    })

    -- Root layout
    local root = Gui.vbox()

    -- Toolbar row 1: navigation
    local toolbar = Gui.hbox()
    local follow_btn = Gui.button(state.follow_mode and "Following" or "Follow")
    local tags_btn = Gui.button("Tags")
    local locations_btn = Gui.button("Locations")
    local maps_btn = Gui.button("Maps")
    local scale_pct = math.floor((state.global_scale or 1.0) * 100)
    local scale_btn = Gui.button("Scale: " .. scale_pct .. "%")
    local find_btn = Gui.button("Find")
    local notes_btn = Gui.button("Notes")
    local theme_label = state.theme and ("Theme: " .. state.theme) or "Theme: default"
    local dark_btn = Gui.button(theme_label)
    local settings_btn = Gui.button("Settings")

    -- Add toolbar children
    toolbar:add(follow_btn)
    toolbar:add(tags_btn)
    toolbar:add(locations_btn)
    toolbar:add(maps_btn)
    toolbar:add(scale_btn)
    toolbar:add(find_btn)
    toolbar:add(notes_btn)
    toolbar:add(dark_btn)
    toolbar:add(settings_btn)
    root:add(toolbar)

    -- Map view
    local map_view = Gui.map_view({ width = 600, height = 400 })
    root:add(map_view)

    -- Status label
    local status_label = Gui.label("")
    root:add(status_label)

    -- Settings panel widgets (created lazily on first click)
    local centered_toggle = nil
    local expanded_toggle = nil
    local ontop_toggle = nil
    local dynamic_toggle = nil
    local borderless_toggle = nil
    local opacity_combo = nil

    -- Settings button opens a settings sub-window
    settings_btn:on_click(function()
        local settings_win = Gui.window("Map Settings", { width = 320, height = 380 })
        local svbox = Gui.vbox()

        svbox:add(Gui.section_header("Display"))

        local ct = Gui.toggle("Keep Centered", state.keep_centered or false)
        centered_toggle = ct
        svbox:add(ct)

        local et = Gui.toggle("Expanded Canvas", state.expanded_canvas or false)
        expanded_toggle = et
        svbox:add(et)

        local ot = Gui.toggle("Keep on Top", state.keep_above or false)
        ontop_toggle = ot
        svbox:add(ot)

        local dt = Gui.toggle("Dynamic Indicator Size", state.dynamic_indicator_size or false)
        dynamic_toggle = dt
        svbox:add(dt)

        local bt = Gui.toggle("Borderless", state.borderless or false)
        borderless_toggle = bt
        svbox:add(bt)

        local hst = Gui.toggle("Hide Scrollbars", state.hide_scrollbars or false)
        svbox:add(hst)

        svbox:add(Gui.separator())
        svbox:add(Gui.section_header("Scale Mode"))

        local gst = Gui.toggle("Global Scale (same zoom for all maps)", state.global_scale_enabled or false)
        svbox:add(gst)

        svbox:add(Gui.separator())
        svbox:add(Gui.section_header("Opacity"))

        local opacity_options = {}
        for i = 1, 10 do
            opacity_options[i] = tostring(i * 10) .. "%"
        end
        local current_opacity_text = tostring(math.floor((state.opacity or 1.0) * 100)) .. "%"
        local oc = Gui.editable_combo({
            text = current_opacity_text,
            hint = "Opacity",
            options = opacity_options,
        })
        opacity_combo = oc
        svbox:add(oc)

        local apply_btn = Gui.button("Apply & Close")
        apply_btn:on_click(function()
            -- Read toggle states back into state
            state.keep_centered = ct:get_checked()
            state.expanded_canvas = et:get_checked()
            state.keep_above = ot:get_checked()
            state.dynamic_indicator_size = dt:get_checked()
            state.borderless = bt:get_checked()
            state.hide_scrollbars = hst:get_checked()
            state.global_scale_enabled = gst:get_checked()
            local otext = oc:get_text()
            local oval = tonumber(otext:match("(%d+)"))
            if oval then
                state.opacity = oval / 100.0
            end
            settings_win:close()
        end)
        svbox:add(apply_btn)

        settings_win:set_root(svbox)
        settings_win:show()
    end)

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
        settings_btn = settings_btn,
        status_label = status_label,
        -- These are set dynamically when settings panel opens
        centered_toggle = centered_toggle,
        expanded_toggle = expanded_toggle,
        ontop_toggle = ontop_toggle,
        dynamic_toggle = dynamic_toggle,
        borderless_toggle = borderless_toggle,
        opacity_combo = opacity_combo,
    }
end

function M.update_map(widgets, image_path, scale)
    local ok, err = widgets.map_view:load_image(image_path)
    if not ok then
        respond("Map: failed to load image: " .. tostring(err))
        return false
    end
    widgets.map_view:set_scale(scale)
    return true
end

function M.update_room_marker(widgets, room)
    widgets.map_view:clear_markers()
    if room and room.id then
        widgets.map_view:set_marker(room.id, { color = "red", shape = "circle" })
    end
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
