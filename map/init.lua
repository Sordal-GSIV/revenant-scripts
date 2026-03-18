--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: map
--- version: 2.1.0
--- author: elanthia-online (LostRanger: original narost author)
--- depends: go2 >= 1.0
--- description: Interactive map viewer with room tracking and click-to-navigate
---
--- Elanthia Online's fork of LostRanger's narost fork.
--- Tracks your current room on visual maps.
---
---   Key differences between this and ;narost:
---     * map has a better-organized map list with submenus, and uses 'proper' map names instead of filenames.
---     * map sorts the list of tags.
---
---   click on a room to go there
---   shift-click on a room to show its description
---   ctrl-click to show coordinates
---   ctrl+scroll to zoom in/out
---   right-click for options
---
--- changelog:
---   v2.1.0 (2026-03-08)
---     * Add map notes feature
---   v2.0.6 (2026-03-05)
---     * Fix tag and location markers not clearing when map image changes;
---       if the selected tag/location exists on the new map, markers are re-applied there
---     * Fix Tags/Locations menus showing all mapdb entries when no map is loaded
---     * Fix marker offsets when zoom level differs between maps
---     * Fix Scale menu not reflecting per-map zoom level after map change
---     * Fix maps only appearing under their first category tag; now indexed under all categories
---   v2.0.5 (2025-02-20)
---     * Fix map drag errors when no map currently shown
---   v2.0.4 (2025-02-20)
---     * Fix for nil map path in location/tag marker lookup
---     * re-correct temporary follow uncheck when using find room to not save on close
---   v2.0.3 (2025-02-16)
---     * Fix borderless toggle not restoring titlebar - added hide/show to force window redraw
---     * Fix Find room dialog deadlock - moved dialog.run to separate thread to avoid GTK main thread blocking
---   v2.0.2 (2025-02-12)
---     * Fix Linux window sticking to all workspaces - removed incorrect stick() calls
---     * Fix GTK menu detach warning on cleanup
---   v2.0.1 (2025-02-12)
---     * Fix GTK crash on long running sessions
---     * Fix follow_me getting disabled when opening with specific room#
---     * Fix showing empty canvas/layout around the map as toggleable option
---   v2.0.0 (2025-01-21)
---     * Complete refactor into ElanthiaMap namespace
---     * Added proper module/class architecture
---     * Added comprehensive YARD documentation
---     * Cleaned up GTK3 code
---     * Modernized Ruby idioms
---     * Renamed legacy 'narost' variables to descriptive names
---     * Added "Keep Centered" option (enabled by default) to auto-center viewport on room marker
---   v1.4.1 (2025-07-08)
---     * Handle a location of false
---   v1.4.0 (2025-07-04)
---     * Add Locations drop down (similar to tags)
---   v1.3.10 (2025-05-29)
---     * Fix for missing dark maps causing GTK errors and DR not having any dark maps
---   v1.3.9 (2025-05-10)
---     * Fix for default geometry and primary display saved settings forcing window back to primary monitor
---     * Correct MapData variable return to be class variable instead of instance variable
---   v1.3.8 (2025-04-20)
---     * Fix for initial default window position for tiling window managers that do not set monitor geometry
---   v1.3.7 (2025-04-15)
---     * Fix reset and initial default value/position of window to primary monitor location
---   v1.3.6 (2025-03-06)
---     * Bugfix for toggling dark mode when no map available for current room in mapdb
---   v1.3.5 (2025-02-23)
---     * Add opacity setting to reset option
---   v1.3.4 (2024-08-23)
---     * Bugfix on Find Room loading map file
---   v1.3.3 (2024-08-09)
---     * Update Settings to save location / size parameters per character
---   v1.3.2 (2024-07-12)
---     * Additional fixes for WSL and responsiveness
---   v1.3.1 (2024-06-29)
---     * fix popup menu crash under WSL
---     * fix pointer click offset issues in WSL
---   v1.3.0 (2024-06-26)
---     * add runtime toggle for opacity (ala orbuculum)
---     * add runtime toggle for borderless window and no scrollbar window (also orbuculum)
---   v1.2.0 (2024-05-19)
---     * fix crash when closing window after opening context menu
---     * add runtime togglable 'dark mode'
---     * added spacer to keep window position on Mac OS
---   v1.1.2 (2024-04-30)
---     * update to use File.join where appropriate
---     * change to use MAP_DIR instead of LICH_DIR+'maps' folder.
---     * change to use lich constants instead of global vars
---   v1.1.1 (2024-02-27)
---     * fix to unhide circle when doing a 'find room' search
---   v1.1.0 (2023-12-15)
---     * add RESET option to set all Settings back to default
---   v1.0.0 (2023-08-18)
---     * initial release and forking from xnarost v1.0.3

i_stand_alone()
clear()

local map_data = require("map_data")
local map_window = require("map_window")
local settings = require("settings")
local notes = require("notes")
local map_links = require("map_links")

-- Command-line mode handling
local arg1 = Script.vars[1]

if arg1 == "help" then
    respond("Version: 2.1.0")
    respond("   ;map help                   - this output")
    respond("   ;map <number>               - shows LichID# in map window instead of current room")
    respond("   ;map u<number>              - shows RealID# in map window instead of current room")
    respond("   ;map <text to search>       - shows room# that first matches text instead of current room")
    respond("   ;map fix                    - enables coordinate fix mode (ctrl+shift+click to set room)")
    respond("   ;map trouble                - enables debug output for troubleshooting window issues")
    respond("   ;map reset                  - resets map settings to default values")
    respond("                                      keep_above = true")
    respond("                                      keep_centered = true")
    respond("                                      expanded_canvas = true")
    respond("                                      follow_mode = true")
    respond("                                      global_scale = 1")
    respond("                                      global_scale_enabled = false")
    respond("                                      dynamic_indicator_size = false")
    respond("                                      opacity = 1.0")
    respond("                                      map_scale = {}")
    respond("                                      window_width = 400")
    respond("                                      window_height = 300")
    respond("                                      primary window_position = [0, 0]")
    respond("")
    respond("   In-Map Controls:")
    respond("      click                    - navigate to room or follow map link")
    respond("      shift+click              - show room description")
    respond("      ctrl+click               - show coordinates at click position")
    respond("      ctrl+shift+click (fix)   - set room coordinates (click twice for corners)")
    respond("      ctrl+scroll              - zoom in/out")
    return
end

if arg1 == "reset" then
    settings.reset()
    respond("[map: Please restart the script for changes to take effect]")
    return
end

local fix_mode = (arg1 == "fix")
local trouble_mode = (arg1 == "trouble")

-- State
local state = settings.load()
local game = GameState.game or "gs"
-- Sync theme from pkg setting if map hasn't set one
local pkg_theme = Settings.map_theme
if pkg_theme and pkg_theme ~= "" and not state.theme then
    state.theme = pkg_theme
end
notes.init(game)
local all_notes = notes.load()
local current_room_id = nil
local current_image = nil
local active_tag = nil
local active_tag_rooms = {}
local fix_click = nil  -- for fix mode: stores first corner

-- Build metadata index (one-time scan)
respond("Map: building room index...")
local index = map_data.build_index()
respond("Map: " .. #index.all_tags .. " tags, " .. #index.all_locations .. " locations indexed")

-- Build GUI
local widgets = map_window.build(state, index)

-- === Helper: refresh note pins on current map ===

local function refresh_note_pins()
    widgets.map_view:clear_markers()
    -- Re-add current room marker
    if current_room_id then
        local room = Map.find_room(current_room_id)
        if room then
            widgets.map_view:set_marker(room.id, { color = "red", shape = "circle" })
        end
    end
    -- Re-add tag markers
    if active_tag and #active_tag_rooms > 0 then
        for _, rid in ipairs(active_tag_rooms) do
            widgets.map_view:set_marker(rid, { color = "blue", shape = "x" })
        end
    end
    -- Add note pin markers for rooms with notes on the current map
    if current_image and all_notes then
        for room_id_str, _ in pairs(all_notes) do
            local rid = tonumber(room_id_str)
            if rid then
                local room = Map.find_room(rid)
                if room and room.image == current_image then
                    widgets.map_view:set_marker(rid, { color = "orange", shape = "pin" })
                end
            end
        end
    end
end

-- === Helper: filter tags/locations to current map ===

local function tags_on_current_map()
    if not current_image then return {} end
    local tag_set = {}
    local room_ids = Map.list()
    for _, rid in ipairs(room_ids) do
        local room = Map.find_room(rid)
        if room and room.image == current_image and room.tags then
            for _, tag in ipairs(room.tags) do
                if not tag:match("^meta:") and not tag:match("^silver%-cost") then
                    tag_set[tag] = true
                end
            end
        end
    end
    local result = {}
    for tag in pairs(tag_set) do
        result[#result + 1] = tag
    end
    table.sort(result, function(a, b) return a:lower() < b:lower() end)
    return result
end

local function locations_on_current_map()
    if not current_image then return {} end
    local loc_set = {}
    local room_ids = Map.list()
    for _, rid in ipairs(room_ids) do
        local room = Map.find_room(rid)
        if room and room.image == current_image and room.location and room.location ~= "" then
            loc_set[room.location] = true
        end
    end
    local result = {}
    for loc in pairs(loc_set) do
        result[#result + 1] = loc
    end
    table.sort(result, function(a, b) return a:lower() < b:lower() end)
    return result
end

-- === Callbacks ===

-- Follow toggle
widgets.follow_btn:on_click(function()
    state.follow_mode = not state.follow_mode
    widgets.follow_btn:set_text(state.follow_mode and "Following" or "Follow")
end)

-- Click-to-navigate with shift+click, ctrl+click, and map link support
widgets.map_view:on_click(function(info)
    -- info may be: room_id (number), or a table with {room_id, x, y, shift, ctrl, scroll_delta}
    -- depending on the Gui.map_view implementation
    local room_id = nil
    local click_x, click_y = nil, nil
    local shift_held = false
    local ctrl_held = false
    local scroll_delta = nil

    if type(info) == "number" then
        room_id = info
    elseif type(info) == "table" then
        room_id = info.room_id
        click_x = info.x
        click_y = info.y
        shift_held = info.shift or false
        ctrl_held = info.ctrl or false
        scroll_delta = info.scroll_delta
    end

    -- Ctrl+scroll zoom
    if ctrl_held and scroll_delta and scroll_delta ~= 0 then
        local factor = scroll_delta > 0 and 1.1 or 0.9
        local current_scale = settings.get_scale(state, current_image)
        local new_scale = current_scale * factor
        new_scale = math.max(0.1, math.min(10.0, new_scale))
        settings.set_scale(state, current_image, new_scale)
        widgets.scale_btn:set_text("Scale: " .. math.floor(new_scale * 100) .. "%")
        if current_image then
            local image_path = map_data.resolve_image_path(current_image, game, state.theme)
            map_window.update_map(widgets, image_path, new_scale)
            refresh_note_pins()
        end
        return
    end

    -- Fix mode: ctrl+shift+click to set room coordinates
    if fix_mode and ctrl_held and shift_held and click_x and click_y then
        if not fix_click then
            fix_click = { click_x, click_y }
            respond("[map fix: First corner set at (" .. math.floor(click_x) .. ", " .. math.floor(click_y) .. "). Click second corner.]")
        else
            local x = math.floor((click_x + fix_click[1]) / 2)
            local y = math.floor((click_y + fix_click[2]) / 2)
            local size = math.floor(((math.max(click_x, fix_click[1]) - math.min(click_x, fix_click[1]))
                + (math.max(click_y, fix_click[2]) - math.min(click_y, fix_click[2]))) / 2)
            local target_room = current_room_id and Map.find_room(current_room_id)
            if target_room then
                respond(target_room.id .. "; x: " .. x .. ", y: " .. y .. ", size: " .. size)
            end
            fix_click = nil
            respond("[map fix: Room coordinates set.]")
        end
        return
    end

    -- Ctrl+click: show coordinates
    if ctrl_held and click_x and click_y then
        respond("x: " .. math.floor(click_x) .. ", y: " .. math.floor(click_y))
        return
    end

    -- Shift+click: show room description in game window
    if shift_held and room_id then
        local room = Map.find_room(room_id)
        if room then
            respond("")
            respond(room.title or "(untitled)")
            if room.description then
                respond(room.description)
            end
            respond("")
        else
            respond("[map: no matching room found]")
        end
        return
    end

    -- Check for map links first (regular click on link zone)
    if click_x and click_y and current_image then
        local link = map_links.find_link_at(current_image, click_x, click_y)
        if link then
            current_image = link.target_image
            local image_path = map_data.resolve_image_path(link.target_image, game, state.theme)
            local scale = settings.get_scale(state, link.target_image)
            map_window.update_map(widgets, image_path, scale)
            widgets.scale_btn:set_text("Scale: " .. math.floor(scale * 100) .. "%")
            refresh_note_pins()
            return
        end
    end

    -- Regular click: navigate to room
    if room_id then
        Script.run("go2", tostring(room_id))
    end
end)

-- Scale cycling - all 16 levels from the original
local scale_steps = { 0.10, 0.25, 0.33, 0.50, 0.66, 0.75, 0.90, 1.0, 1.10, 1.25, 1.33, 1.50, 1.66, 1.75, 1.90, 2.0 }
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
    widgets.scale_btn:set_text("Scale: " .. math.floor(next_scale * 100) .. "%")
    if current_image then
        local image_path = map_data.resolve_image_path(current_image, game, state.theme)
        map_window.update_map(widgets, image_path, next_scale)
        refresh_note_pins()
    end
end)

-- Theme cycle button: default -> dark -> light -> ... -> default
-- Also respects Settings.map_theme set via `;pkg map-theme`
local available_themes = map_data.available_themes(game)
widgets.dark_btn:on_click(function()
    if #available_themes == 0 then
        respond("Map: no alternate themes found (install via ;pkg map-theme)")
        return
    end
    -- Find current theme index
    local current_idx = 0
    for i, t in ipairs(available_themes) do
        if t == state.theme then current_idx = i; break end
    end
    -- Cycle to next theme (0 = default, 1..N = themes)
    local next_idx = current_idx + 1
    if next_idx > #available_themes then
        state.theme = nil  -- back to default
    else
        state.theme = available_themes[next_idx]
    end
    -- Also update the global setting so pkg knows
    Settings.map_theme = state.theme or ""
    local label = state.theme and ("Theme: " .. state.theme) or "Theme: default"
    widgets.dark_btn:set_text(label)
    if current_image then
        local image_path = map_data.resolve_image_path(current_image, game, state.theme)
        local scale = settings.get_scale(state, current_image)
        map_window.update_map(widgets, image_path, scale)
        refresh_note_pins()
    end
end)

-- Tags button -- filtered to current map
widgets.tags_btn:on_click(function()
    local filtered_tags = tags_on_current_map()
    if #filtered_tags == 0 then
        if not current_image then
            respond("Map: no map loaded")
        else
            respond("Map: no tags on this map")
        end
        return
    end
    local rows = {}
    for _, tag in ipairs(filtered_tags) do
        rows[#rows + 1] = { tag }
    end
    local tag_win = Gui.window("Select Tag", { width = 250, height = 400 })
    local tag_vbox = Gui.vbox()
    local clear_btn = Gui.button("Clear Tag Markers")
    tag_vbox:add(clear_btn)
    local tag_table = Gui.table({ columns = { "Tag" } })
    for _, row in ipairs(rows) do
        tag_table:add_row(row)
    end
    tag_vbox:add(tag_table)
    tag_win:set_root(tag_vbox)

    clear_btn:on_click(function()
        active_tag = nil
        active_tag_rooms = {}
        map_window.clear_tag_markers(widgets)
        refresh_note_pins()
        tag_win:close()
    end)

    tag_table:on_click(function(row_idx)
        if row_idx and filtered_tags[row_idx] then
            active_tag = filtered_tags[row_idx]
            -- Only get rooms on current map with this tag
            active_tag_rooms = {}
            local room_ids = Map.list()
            for _, rid in ipairs(room_ids) do
                local room = Map.find_room(rid)
                if room and room.image == current_image and room.tags then
                    for _, t in ipairs(room.tags) do
                        if t == active_tag then
                            active_tag_rooms[#active_tag_rooms + 1] = rid
                            break
                        end
                    end
                end
            end
            map_window.clear_tag_markers(widgets)
            refresh_note_pins()
            map_window.show_tag_markers(widgets, active_tag_rooms)
            respond("Map: showing " .. #active_tag_rooms .. " rooms tagged '" .. active_tag .. "'")
            tag_win:close()
        end
    end)

    tag_win:show()
end)

-- Locations button -- filtered to current map
widgets.locations_btn:on_click(function()
    local filtered_locs = locations_on_current_map()
    if #filtered_locs == 0 then
        if not current_image then
            respond("Map: no map loaded")
        else
            respond("Map: no locations on this map")
        end
        return
    end
    local rows = {}
    for _, loc in ipairs(filtered_locs) do
        rows[#rows + 1] = { loc }
    end
    local loc_win = Gui.window("Select Location", { width = 300, height = 400 })
    local loc_vbox = Gui.vbox()
    local clear_loc_btn = Gui.button("Clear Location Markers")
    loc_vbox:add(clear_loc_btn)
    local loc_table = Gui.table({ columns = { "Location" } })
    for _, row in ipairs(rows) do
        loc_table:add_row(row)
    end
    loc_vbox:add(loc_table)
    loc_win:set_root(loc_vbox)

    clear_loc_btn:on_click(function()
        map_window.clear_tag_markers(widgets)
        refresh_note_pins()
        loc_win:close()
    end)

    loc_table:on_click(function(row_idx)
        if row_idx and filtered_locs[row_idx] then
            local location = filtered_locs[row_idx]
            -- Only get rooms on current map with this location
            local loc_rooms = {}
            local room_ids = Map.list()
            for _, rid in ipairs(room_ids) do
                local room = Map.find_room(rid)
                if room and room.image == current_image and room.location and room.location == location then
                    loc_rooms[#loc_rooms + 1] = rid
                end
            end
            map_window.clear_tag_markers(widgets)
            refresh_note_pins()
            map_window.show_location_markers(widgets, loc_rooms)
            respond("Map: showing " .. #loc_rooms .. " rooms in '" .. location .. "'")
            loc_win:close()
        end
    end)

    loc_win:show()
end)

-- Maps button -- supports maps appearing under multiple categories
widgets.maps_btn:on_click(function()
    local rows = {}
    local map_list = {}
    -- Maps can appear under multiple categories; show each appearance
    for cat, maps in pairs(index.categories) do
        for _, img in ipairs(maps) do
            local info = index.maps[img]
            local display = info and info.name or img
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
    local map_table = Gui.table({ columns = { "Map", "Category" } })
    for _, row in ipairs(rows) do
        map_table:add_row(row)
    end
    map_vbox:add(map_table)
    map_sel_win:set_root(map_vbox)

    map_table:on_click(function(row_idx)
        if row_idx and map_list[row_idx] then
            local img = map_list[row_idx]
            current_image = img
            local image_path = map_data.resolve_image_path(img, game, state.theme)
            local scale = settings.get_scale(state, img)
            map_window.update_map(widgets, image_path, scale)
            widgets.scale_btn:set_text("Scale: " .. math.floor(scale * 100) .. "%")
            -- Disable follow mode when manually selecting a map
            state.follow_mode = false
            widgets.follow_btn:set_text("Follow")
            refresh_note_pins()
            map_sel_win:close()
        end
    end)

    map_sel_win:show()
end)

-- Find button -- open find room sub-window
widgets.find_btn:on_click(function()
    local find_win = Gui.window("Find Room", { width = 450, height = 400 })
    local vbox = Gui.vbox()
    local search_box = Gui.hbox()
    local find_input = Gui.input({ placeholder = "Room ID or name..." })
    search_box:add(find_input)
    local find_go_btn = Gui.button("Search")
    search_box:add(find_go_btn)
    vbox:add(search_box)
    local results_table = Gui.table({ columns = { "ID", "Title", "Map" } })
    vbox:add(results_table)
    find_win:set_root(vbox)

    local result_rooms = {}

    local function do_search()
        local text = find_input:get_text()
        if not text or text == "" then return end
        result_rooms = {}

        -- Handle u-prefix room lookup (real ID)
        local u_id = text:match("^u(%d+)$")
        if u_id then
            text = u_id
        end

        -- Try exact ID first
        local exact_id = tonumber(text)
        if exact_id then
            local room = Map.find_room(exact_id)
            if room then
                result_rooms[#result_rooms + 1] = room
            end
        end

        -- Text search across room titles (limited to first 50 matches)
        if #result_rooms == 0 or not exact_id then
            local all_ids = Map.list()
            local count = 0
            for _, rid in ipairs(all_ids) do
                if count >= 50 then break end
                local room = Map.find_room(rid)
                if room and room.title and room.title:lower():find(text:lower(), 1, true) then
                    -- Avoid duplicates if exact ID also matched
                    local dup = false
                    for _, existing in ipairs(result_rooms) do
                        if existing.id == room.id then dup = true; break end
                    end
                    if not dup then
                        result_rooms[#result_rooms + 1] = room
                        count = count + 1
                    end
                end
            end
        end

        respond("Map: found " .. #result_rooms .. " rooms")
    end

    find_go_btn:on_click(do_search)
    find_input:on_submit(do_search)

    results_table:on_click(function(row_idx)
        if row_idx and result_rooms[row_idx] then
            local room = result_rooms[row_idx]
            local image = map_data.image_for_room(room)
            if image then
                current_image = image
                current_room_id = room.id
                local image_path = map_data.resolve_image_path(image, game, state.theme)
                local scale = settings.get_scale(state, image)
                map_window.update_map(widgets, image_path, scale)
                map_window.update_room_marker(widgets, room)
                map_window.center_on_room(widgets, room)
                map_window.update_title(widgets, room)
                state.follow_mode = false
                widgets.follow_btn:set_text("Follow")
                refresh_note_pins()
            end
            find_win:close()
        end
    end)

    find_win:show()
end)

-- Notes button -- open per-room annotation editor
widgets.notes_btn:on_click(function()
    if current_room_id then
        notes.open_editor(current_room_id, all_notes, function()
            respond("Map: note saved for room " .. current_room_id)
            -- Reload notes and refresh pins
            all_notes = notes.load()
            refresh_note_pins()
        end)
    else
        respond("Map: no current room")
    end
end)

-- Note: settings panel toggles (keep_centered, expanded_canvas, etc.) are applied
-- via the "Apply & Close" button inside the settings sub-window (map_window.lua).
-- State is read directly from the toggle widgets in that closure.

-- === Room Tracking Hook ===

DownstreamHook.add("map_room_tracker", function(line)
    local new_id = GameState.room_id
    if new_id and new_id ~= current_room_id then
        current_room_id = new_id
        local room = Map.find_room(new_id)
        if room and state.follow_mode then
            local image = map_data.image_for_room(room)
            if image then
                local image_path = map_data.resolve_image_path(image, game, state.theme)
                if image ~= current_image then
                    current_image = image
                    local scale = settings.get_scale(state, image)
                    map_window.update_map(widgets, image_path, scale)
                    widgets.scale_btn:set_text("Scale: " .. math.floor(scale * 100) .. "%")
                    refresh_note_pins()
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
    -- Capture window geometry if the on_close callback provides it
    -- (The on_close callback below captures geometry into state before this runs)
    settings.save(state)
end)

-- Window close callback to capture geometry
widgets.win:on_close(function()
    -- Save window geometry to state before the before_dying hook persists it
    -- The Gui framework provides the window's final dimensions
    settings.save(state)
end)

-- === Startup ===

-- If a room arg was passed, jump to it
local target_arg = Script.vars[1]
-- Skip mode args
if target_arg and not target_arg:match("^(help|fix|trouble|reset)$") then
    -- Handle u-prefix for real room ID
    local u_id = target_arg:match("^u(%d+)$")
    local search = u_id or target_arg

    local room_id = tonumber(search)
    local room = room_id and Map.find_room(room_id) or Map.find_room(search)
    if room then
        local image = map_data.image_for_room(room)
        if image then
            current_image = image
            current_room_id = room.id
            local image_path = map_data.resolve_image_path(image, game, state.theme)
            local scale = settings.get_scale(state, image)
            map_window.update_map(widgets, image_path, scale)
            map_window.update_room_marker(widgets, room)
            map_window.center_on_room(widgets, room)
            map_window.update_title(widgets, room)
            refresh_note_pins()
        end
        -- Don't follow when started with a specific room
        state.follow_mode = false
        widgets.follow_btn:set_text("Follow")
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
                local image_path = map_data.resolve_image_path(image, game, state.theme)
                local scale = settings.get_scale(state, image)
                map_window.update_map(widgets, image_path, scale)
                map_window.update_room_marker(widgets, room)
                map_window.center_on_room(widgets, room)
                map_window.update_title(widgets, room)
                refresh_note_pins()
            end
        end
    end
end

-- Debug output in trouble mode
if trouble_mode then
    respond("[map: trouble mode enabled - debug output active]")
    respond("[map: game=" .. tostring(game) .. " room=" .. tostring(GameState.room_id) .. "]")
    respond("[map: state = " .. Json.encode({
        follow_mode = state.follow_mode,
        keep_centered = state.keep_centered,
        keep_above = state.keep_above,
        expanded_canvas = state.expanded_canvas,
        dynamic_indicator_size = state.dynamic_indicator_size,
        opacity = state.opacity,
        borderless = state.borderless,
        hide_scrollbars = state.hide_scrollbars,
        global_scale = state.global_scale,
        global_scale_enabled = state.global_scale_enabled,
        theme = state.theme,
        window_width = state.window_width,
        window_height = state.window_height,
        window_x = state.window_x,
        window_y = state.window_y,
    }) .. "]")
    respond("[map: index: " .. #index.all_tags .. " tags, " .. #index.all_locations
        .. " locations, " .. (function()
            local n = 0; for _ in pairs(index.maps) do n = n + 1 end; return n
        end)() .. " maps in " .. (function()
            local n = 0; for _ in pairs(index.categories) do n = n + 1 end; return n
        end)() .. " categories]")
end

-- Show window and block until closed
widgets.win:show()
Gui.wait(widgets.win, "close")
