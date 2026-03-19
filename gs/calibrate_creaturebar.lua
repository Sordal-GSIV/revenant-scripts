--- @revenant-script
--- name: calibrate_creaturebar
--- version: 1.0.0
--- author: Elanthia Online
--- contributors: Nisugi
--- game: gs
--- tags: hunting, combat, creatures, gui
--- description: Visual tool to calibrate body part coordinates for CreatureBar silhouettes
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Elanthia Online, Nisugi
--- Ported to Revenant Lua from calibrate_creaturebar.lic v1.0
---
--- Changelog:
---   v1.0 (2025/11/30) - initial release (Lich5 GTK3)
---   v1.0.0 (2026/03/19) - Full Revenant port with egui GUI
---     - Click-to-position wound markers on silhouette images via map_view
---     - Tabbed settings: Silhouette, Name, HP Bar, Status
---     - Silhouette selector dropdown with style/region scanning
---     - Scale, marker size, panel dimension controls
---     - Copy UI settings to all creature configs
---     - JSON config format (replacing YAML)

local VERSION = "1.0.0"

no_kill_all()
no_pause_all()

--------------------------------------------------------------------------------
-- Configuration paths (relative to scripts dir, used with File.* API)
--------------------------------------------------------------------------------

local DATA_DIR           = "data/gs/creature_bar"
local CONFIG_FILE        = DATA_DIR .. "/config.json"
local SILHOUETTE_DIR     = DATA_DIR .. "/silhouettes"
local SILHOUETTE_CFG_DIR = DATA_DIR .. "/configs"

local BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nerves",
}

local MARKER_COLORS = {
    [1] = "yellow",   -- rank 1 (minor)
    [2] = "red",      -- rank 2 (moderate)
    [3] = "red",      -- rank 3 (severe)
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local current_part_index  = 1
local current_rank        = 1
local current_family      = "default"
local current_subfolder   = "default"
local silhouette_file     = nil  -- absolute path for load_image
local running             = true

-- Config tables
local config      = nil   -- per-silhouette config (body_parts, scale, etc.)
local main_config = nil   -- global config (colors, HP ranges, etc.)

-- body_parts[part] = {x, y}  (normalized to scale 1.0)
local coordinates = {}

-- silhouette_map[display_name] = {family, subfolder, rel_path, style}
local silhouette_map = {}

-- GUI widget references
local win             = nil
local map             = nil
local info_label      = nil
local family_combo    = nil
local scale_input     = nil
local marker_input    = nil
local pw_input        = nil
local ph_input        = nil
local tab_bar         = nil
-- Name tab
local name_show_cb    = nil
local name_mode_cb    = nil  -- checkbox: checked=noun, unchecked=name
local name_size_input = nil
local name_weight_cb  = nil  -- checkbox: checked=bold
-- HP tab
local hp_show_cb      = nil
local hp_bar_cb       = nil
local hp_text_cb      = nil
local hp_style_combo  = nil
local hp_pos_combo    = nil
local hp_prefix_cb    = nil
local hp_numbers_cb   = nil
local hp_pct_cb       = nil
local hp_w_input      = nil
local hp_h_input      = nil
local hp_font_input   = nil
-- Status tab
local status_show_cb    = nil
local status_size_input = nil

-- Suppress callback processing during config load
local loading_config = false

--------------------------------------------------------------------------------
-- Utility helpers
--------------------------------------------------------------------------------

local function clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function ensure_dirs()
    File.mkdir(DATA_DIR)
    File.mkdir(SILHOUETTE_DIR)
    File.mkdir(SILHOUETTE_CFG_DIR)
end

--- Read a JSON file relative to scripts dir. Returns table or default.
local function read_json(path, default)
    local raw = File.read(path)
    if not raw then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

--- Write a JSON file relative to scripts dir.
local function write_json(path, tbl)
    local ok, json = pcall(Json.encode, tbl)
    if not ok then
        echo("Failed to encode JSON: " .. tostring(json))
        return false
    end
    local res, err = File.write(path, json)
    if not res then
        echo("Failed to write " .. path .. ": " .. tostring(err))
        return false
    end
    return true
end

--- Resolve a relative path to an absolute path (for load_image).
local function abs_path(rel)
    local p, err = File.resolve(rel)
    return p
end

--------------------------------------------------------------------------------
-- Silhouette scanning
--------------------------------------------------------------------------------

--- Recursively scan silhouette directory for PNG files.
--- Structure: silhouettes/{style}/{region}/{family}.png
--- Also checks for silhouettes/default.png at root.
local function scan_silhouettes()
    silhouette_map = {}

    if not File.exists(SILHOUETTE_DIR) then return {} end

    -- Check for default.png at root
    local default_path = SILHOUETTE_DIR .. "/default.png"
    if File.exists(default_path) then
        silhouette_map["default"] = {
            family = "default",
            subfolder = "default",
            rel_path = default_path,
            style = nil,
        }
    end

    -- Scan style directories (greyscale, color)
    local styles = {"greyscale", "color"}
    for _, style in ipairs(styles) do
        local style_dir = SILHOUETTE_DIR .. "/" .. style
        if File.exists(style_dir) and File.is_dir(style_dir) then
            local regions = File.list(style_dir)
            if regions then
                for _, region_entry in ipairs(regions) do
                    -- File.list appends "/" for directories
                    local region = region_entry:match("^(.+)/$")
                    if region and not region:match("^%.") then
                        local region_dir = style_dir .. "/" .. region
                        local files = File.list(region_dir)
                        if files then
                            for _, fname in ipairs(files) do
                                local family = fname:match("^(.+)%.png$")
                                if family then
                                    -- Skip rank markers and overlay files
                                    if not family:match("^rank%d+$") and family ~= "eyes_back_nerves" then
                                        local display = family .. " (" .. style .. "/" .. region .. ")"
                                        silhouette_map[display] = {
                                            family = family,
                                            subfolder = style .. "/" .. region,
                                            rel_path = region_dir .. "/" .. fname,
                                            style = style,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Build sorted list of display names
    local names = {}
    for name, _ in pairs(silhouette_map) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--------------------------------------------------------------------------------
-- Config loading / saving
--------------------------------------------------------------------------------

local function load_main_config()
    main_config = read_json(CONFIG_FILE, {})
end

local function save_main_config()
    write_json(CONFIG_FILE, main_config)
end

--- Find config file for a silhouette family.
local function find_config_path(family, subfolder)
    -- Check subfolder-specific config first
    if subfolder and subfolder ~= "default" then
        local path = SILHOUETTE_CFG_DIR .. "/" .. subfolder .. "/" .. family .. ".json"
        if File.exists(path) then return path end
    end
    -- Check root-level default
    if family == "default" then
        local path = SILHOUETTE_CFG_DIR .. "/default.json"
        if File.exists(path) then return path end
    end
    -- Search all style/region combos
    for _, style in ipairs({"greyscale", "color"}) do
        local style_dir = SILHOUETTE_CFG_DIR .. "/" .. style
        if File.exists(style_dir) and File.is_dir(style_dir) then
            local regions = File.list(style_dir)
            if regions then
                for _, entry in ipairs(regions) do
                    local region = entry:match("^(.+)/$")
                    if region then
                        local path = style_dir .. "/" .. region .. "/" .. family .. ".json"
                        if File.exists(path) then return path end
                    end
                end
            end
        end
    end
    return nil
end

local function default_config()
    return {
        scale = 1.0,
        panel_width = 100,
        panel_height = 220,
        marker_size = 12,
        body_parts = {},
        name_display = { show = true, font_size = 12, font_weight = "bold", mode = "name" },
        hp_bar = {
            show = true, show_bar = true, show_text = false,
            text_style = "overlay", text_position = "top",
            show_hp_prefix = true, show_numbers = true, show_percentage = true,
            width = 120, height = 16, font_size = 11,
        },
        status = { show = true, font_size = 12 },
    }
end

local function load_silhouette_config(family, subfolder)
    local path = find_config_path(family, subfolder)
    if path then
        config = read_json(path, default_config())
    else
        config = default_config()
    end

    -- Ensure all sections exist
    config.name_display = config.name_display or {}
    config.hp_bar       = config.hp_bar or {}
    config.status       = config.status or {}
    config.body_parts   = config.body_parts or {}

    -- Merge defaults for missing keys in each section
    local dc = default_config()
    for k, v in pairs(dc.name_display) do
        if config.name_display[k] == nil then config.name_display[k] = v end
    end
    for k, v in pairs(dc.hp_bar) do
        if config.hp_bar[k] == nil then config.hp_bar[k] = v end
    end
    for k, v in pairs(dc.status) do
        if config.status[k] == nil then config.status[k] = v end
    end

    -- Merge with main config for global display defaults
    if main_config.name_display then
        for k, v in pairs(main_config.name_display) do
            if config.name_display[k] == nil then config.name_display[k] = v end
        end
    end
    if main_config.hp_bar then
        for k, v in pairs(main_config.hp_bar) do
            if k ~= "ranges" and config.hp_bar[k] == nil then config.hp_bar[k] = v end
        end
    end
    if main_config.status then
        for k, v in pairs(main_config.status) do
            if config.status[k] == nil then config.status[k] = v end
        end
    end

    -- Extract coordinates
    coordinates = {}
    for part, coords in pairs(config.body_parts) do
        if type(coords) == "table" and coords[1] ~= nil then
            coordinates[part] = {coords[1], coords[2]}
        end
    end
    -- Initialize missing parts at center
    for _, part in ipairs(BODY_PARTS) do
        if not coordinates[part] then
            coordinates[part] = {50, 50}
        end
    end
end

local function save_silhouette_config(show_msg)
    if not config then config = default_config() end

    -- Write coordinates back into config
    config.body_parts = {}
    for part, coords in pairs(coordinates) do
        config.body_parts[part] = {coords[1], coords[2]}
    end

    -- Determine save path
    local save_path
    if current_family == "default" or current_subfolder == "default" then
        save_path = SILHOUETTE_CFG_DIR .. "/default.json"
    else
        -- Ensure subfolder exists
        local subfolder_path = SILHOUETTE_CFG_DIR .. "/" .. current_subfolder
        File.mkdir(subfolder_path)
        save_path = subfolder_path .. "/" .. current_family .. ".json"
    end

    if write_json(save_path, config) then
        if show_msg then
            echo("Saved config for " .. current_family .. " to " .. save_path)
        end
    end
end

--------------------------------------------------------------------------------
-- Marker management on map_view
--------------------------------------------------------------------------------

local function update_markers()
    if not map then return end
    map:clear_markers()

    local scale = config.scale or 1.0

    -- Show all body parts with small markers
    for i, part in ipairs(BODY_PARTS) do
        local coords = coordinates[part]
        if coords then
            local sx = coords[1] * scale
            local sy = coords[2] * scale
            local is_current = (i == current_part_index)
            -- Current part gets a bright colored marker, others get white
            local color = is_current and (MARKER_COLORS[current_rank] or "yellow") or "white"
            local shape = is_current and "circle" or "x"
            map:set_marker(i, {x = sx, y = sy, color = color, shape = shape})
        end
    end
end

local function update_info()
    if not info_label then return end
    local part = BODY_PARTS[current_part_index]
    local coords = coordinates[part] or {0, 0}
    local text = string.format("Calibrating: %s (%d/%d)  [%d, %d]  Rank: %d",
        part, current_part_index, #BODY_PARTS, coords[1], coords[2], current_rank)
    info_label:set_text(text)
end

--------------------------------------------------------------------------------
-- Apply functions (read from UI, update config)
--------------------------------------------------------------------------------

local function apply_scale()
    if loading_config or not scale_input then return end
    local val = tonumber(scale_input:get_text()) or 1.0
    val = clamp(val, 0.1, 5.0)
    config.scale = val

    -- Auto-calculate marker size
    local ms = clamp(math.floor(14 * val + 0.5), 2, 30)
    config.marker_size = ms
    if marker_input then marker_input:set_text(tostring(ms)) end

    -- Update map scale
    if map then map:set_scale(val) end
    update_markers()
end

local function apply_marker_size()
    if loading_config or not marker_input then return end
    local val = tonumber(marker_input:get_text()) or 12
    config.marker_size = clamp(val, 2, 30)
    update_markers()
end

local function apply_panel_width()
    if loading_config or not pw_input then return end
    local val = tonumber(pw_input:get_text()) or 100
    config.panel_width = clamp(val, 20, 300)
end

local function apply_panel_height()
    if loading_config or not ph_input then return end
    local val = tonumber(ph_input:get_text()) or 220
    config.panel_height = clamp(val, 20, 400)
end

local function apply_name_settings()
    if loading_config then return end
    config.name_display = config.name_display or {}
    if name_show_cb then config.name_display.show = name_show_cb:get_checked() end
    if name_mode_cb then config.name_display.mode = name_mode_cb:get_checked() and "noun" or "name" end
    if name_size_input then
        local v = tonumber(name_size_input:get_text()) or 12
        config.name_display.font_size = clamp(v, 6, 24)
    end
    if name_weight_cb then
        config.name_display.font_weight = name_weight_cb:get_checked() and "bold" or "normal"
    end
end

local function apply_hp_settings()
    if loading_config then return end
    config.hp_bar = config.hp_bar or {}
    if hp_show_cb then config.hp_bar.show = hp_show_cb:get_checked() end
    if hp_bar_cb then config.hp_bar.show_bar = hp_bar_cb:get_checked() end
    if hp_text_cb then config.hp_bar.show_text = hp_text_cb:get_checked() end
    if hp_style_combo then
        local txt = hp_style_combo:get_text()
        config.hp_bar.text_style = (txt == "embedded") and "embedded" or "overlay"
    end
    if hp_pos_combo then
        local txt = hp_pos_combo:get_text()
        config.hp_bar.text_position = (txt == "Bottom") and "bottom" or "top"
    end
    if hp_prefix_cb then config.hp_bar.show_hp_prefix = hp_prefix_cb:get_checked() end
    if hp_numbers_cb then config.hp_bar.show_numbers = hp_numbers_cb:get_checked() end
    if hp_pct_cb then config.hp_bar.show_percentage = hp_pct_cb:get_checked() end
    if hp_w_input then
        local v = tonumber(hp_w_input:get_text()) or 120
        config.hp_bar.width = clamp(v, 20, 200)
    end
    if hp_h_input then
        local v = tonumber(hp_h_input:get_text()) or 16
        config.hp_bar.height = clamp(v, 4, 40)
    end
    if hp_font_input then
        local v = tonumber(hp_font_input:get_text()) or 11
        config.hp_bar.font_size = clamp(v, 6, 20)
    end
end

local function apply_status_settings()
    if loading_config then return end
    config.status = config.status or {}
    if status_show_cb then config.status.show = status_show_cb:get_checked() end
    if status_size_input then
        local v = tonumber(status_size_input:get_text()) or 12
        config.status.font_size = clamp(v, 6, 24)
    end
end

local function apply_all()
    apply_scale()
    apply_panel_width()
    apply_panel_height()
    apply_marker_size()
    apply_name_settings()
    apply_hp_settings()
    apply_status_settings()
end

--------------------------------------------------------------------------------
-- UI population from config
--------------------------------------------------------------------------------

local function populate_ui()
    loading_config = true

    if scale_input then scale_input:set_text(tostring(config.scale or 1.0)) end
    if marker_input then marker_input:set_text(tostring(config.marker_size or 12)) end
    if pw_input then pw_input:set_text(tostring(config.panel_width or 100)) end
    if ph_input then ph_input:set_text(tostring(config.panel_height or 220)) end

    -- Name tab
    if name_show_cb then name_show_cb:set_checked(config.name_display.show ~= false) end
    if name_mode_cb then name_mode_cb:set_checked((config.name_display.mode or "name") == "noun") end
    if name_size_input then name_size_input:set_text(tostring(config.name_display.font_size or 12)) end
    if name_weight_cb then name_weight_cb:set_checked((config.name_display.font_weight or "bold") == "bold") end

    -- HP tab
    if hp_show_cb then hp_show_cb:set_checked(config.hp_bar.show ~= false) end
    if hp_bar_cb then hp_bar_cb:set_checked(config.hp_bar.show_bar ~= false) end
    if hp_text_cb then hp_text_cb:set_checked(config.hp_bar.show_text == true) end
    if hp_style_combo then hp_style_combo:set_text(config.hp_bar.text_style or "overlay") end
    if hp_pos_combo then
        hp_pos_combo:set_text((config.hp_bar.text_position or "top") == "bottom" and "Bottom" or "Top")
    end
    if hp_prefix_cb then hp_prefix_cb:set_checked(config.hp_bar.show_hp_prefix ~= false) end
    if hp_numbers_cb then hp_numbers_cb:set_checked(config.hp_bar.show_numbers ~= false) end
    if hp_pct_cb then hp_pct_cb:set_checked(config.hp_bar.show_percentage ~= false) end
    if hp_w_input then hp_w_input:set_text(tostring(config.hp_bar.width or 120)) end
    if hp_h_input then hp_h_input:set_text(tostring(config.hp_bar.height or 16)) end
    if hp_font_input then hp_font_input:set_text(tostring(config.hp_bar.font_size or 11)) end

    -- Status tab
    if status_show_cb then status_show_cb:set_checked(config.status.show ~= false) end
    if status_size_input then status_size_input:set_text(tostring(config.status.font_size or 12)) end

    loading_config = false
end

--------------------------------------------------------------------------------
-- Silhouette loading
--------------------------------------------------------------------------------

local function load_silhouette_image()
    if not map or not silhouette_file then return end

    local abs = abs_path(silhouette_file)
    if not abs then
        echo("Cannot resolve silhouette path: " .. silhouette_file)
        return
    end

    local ok, err = map:load_image(abs)
    if not ok then
        echo("Failed to load silhouette: " .. tostring(err))
        return
    end

    -- Apply scale
    if config and config.scale then
        map:set_scale(config.scale)
    end
end

local function change_family(display_name)
    local info = silhouette_map[display_name]
    if info then
        current_family = info.family
        current_subfolder = info.subfolder
        silhouette_file = info.rel_path
    else
        current_family = display_name
        current_subfolder = "default"
        silhouette_file = nil
    end

    -- Load config for new family
    load_silhouette_config(current_family, current_subfolder)
    populate_ui()

    -- Reload image
    load_silhouette_image()

    -- Reset to first body part
    current_part_index = 1
    update_markers()
    update_info()
end

--------------------------------------------------------------------------------
-- Copy UI settings to all creature configs
--------------------------------------------------------------------------------

local function copy_settings_to_all()
    apply_all()

    -- Settings to propagate (everything except body_parts)
    local ui_settings = {
        scale        = config.scale,
        marker_size  = config.marker_size,
        panel_width  = config.panel_width,
        panel_height = config.panel_height,
        name_display = config.name_display,
        hp_bar       = config.hp_bar,
        status       = config.status,
    }

    local updated = 0

    -- Helper to update one config file
    local function update_file(path)
        local existing = read_json(path, {})
        -- Preserve body_parts, replace everything else
        local merged = {}
        for k, v in pairs(ui_settings) do merged[k] = v end
        merged.body_parts = existing.body_parts or {}
        if write_json(path, merged) then updated = updated + 1 end
    end

    -- Update root default.json
    local default_path = SILHOUETTE_CFG_DIR .. "/default.json"
    if File.exists(default_path) then update_file(default_path) end

    -- Scan style/region subfolders
    for _, style in ipairs({"greyscale", "color"}) do
        local style_dir = SILHOUETTE_CFG_DIR .. "/" .. style
        if File.exists(style_dir) and File.is_dir(style_dir) then
            local regions = File.list(style_dir)
            if regions then
                for _, entry in ipairs(regions) do
                    local region = entry:match("^(.+)/$")
                    if region then
                        local region_dir = style_dir .. "/" .. region
                        local files = File.list(region_dir)
                        if files then
                            for _, fname in ipairs(files) do
                                if fname:match("%.json$") then
                                    update_file(region_dir .. "/" .. fname)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    echo("UI settings copied to " .. updated .. " config(s)")
end

--------------------------------------------------------------------------------
-- GUI construction
--------------------------------------------------------------------------------

local function build_ui()
    win = Gui.window("CreatureBar Calibrator", {width = 340, height = 700, resizable = true})

    local root = Gui.vbox()

    -- Silhouette selector
    local sel_row = Gui.hbox()
    sel_row:add(Gui.label("Silhouette:"))

    local available = scan_silhouettes()
    family_combo = Gui.editable_combo({
        text = current_family,
        options = available,
    })
    family_combo:on_change(function(text)
        if not loading_config and text and silhouette_map[text] then
            change_family(text)
        end
    end)
    sel_row:add(family_combo)
    root:add(sel_row)

    -- Settings tabs
    tab_bar = Gui.tab_bar({"Silhouette", "Name", "HP Bar", "Status"})

    -- Tab 1: Silhouette settings
    local sil_box = Gui.vbox()

    local scale_row = Gui.hbox()
    scale_row:add(Gui.label("Scale:"))
    scale_input = Gui.input({text = tostring(config.scale or 1.0), placeholder = "1.0"})
    scale_input:on_submit(function() apply_scale() end)
    scale_row:add(scale_input)
    sil_box:add(scale_row)

    local marker_row = Gui.hbox()
    marker_row:add(Gui.label("Marker Size (px):"))
    marker_input = Gui.input({text = tostring(config.marker_size or 12), placeholder = "12"})
    marker_input:on_submit(function() apply_marker_size() end)
    marker_row:add(marker_input)
    sil_box:add(marker_row)

    local pw_row = Gui.hbox()
    pw_row:add(Gui.label("Panel Width (px):"))
    pw_input = Gui.input({text = tostring(config.panel_width or 100), placeholder = "100"})
    pw_input:on_submit(function() apply_panel_width() end)
    pw_row:add(pw_input)
    sil_box:add(pw_row)

    local ph_row = Gui.hbox()
    ph_row:add(Gui.label("Panel Height (px):"))
    ph_input = Gui.input({text = tostring(config.panel_height or 220), placeholder = "220"})
    ph_input:on_submit(function() apply_panel_height() end)
    ph_row:add(ph_input)
    sil_box:add(ph_row)

    tab_bar:set_tab_content(0, sil_box)

    -- Tab 2: Name display settings
    local name_box = Gui.vbox()

    name_show_cb = Gui.checkbox("Show Name", config.name_display.show ~= false)
    name_show_cb:on_change(function() apply_name_settings() end)
    name_box:add(name_show_cb)

    name_mode_cb = Gui.checkbox("Noun Only (unchecked = Full Name)", (config.name_display.mode or "name") == "noun")
    name_mode_cb:on_change(function() apply_name_settings() end)
    name_box:add(name_mode_cb)

    local nsize_row = Gui.hbox()
    nsize_row:add(Gui.label("Font Size:"))
    name_size_input = Gui.input({text = tostring(config.name_display.font_size or 12), placeholder = "12"})
    name_size_input:on_submit(function() apply_name_settings() end)
    nsize_row:add(name_size_input)
    name_box:add(nsize_row)

    name_weight_cb = Gui.checkbox("Bold", (config.name_display.font_weight or "bold") == "bold")
    name_weight_cb:on_change(function() apply_name_settings() end)
    name_box:add(name_weight_cb)

    tab_bar:set_tab_content(1, name_box)

    -- Tab 3: HP Bar settings
    local hp_box = Gui.vbox()

    hp_show_cb = Gui.checkbox("Show HP Bar", config.hp_bar.show ~= false)
    hp_show_cb:on_change(function() apply_hp_settings() end)
    hp_box:add(hp_show_cb)

    local hp_style_row = Gui.hbox()
    hp_style_row:add(Gui.label("Style:"))
    hp_style_combo = Gui.editable_combo({
        text = config.hp_bar.text_style or "overlay",
        options = {"overlay", "embedded"},
    })
    hp_style_combo:on_change(function() apply_hp_settings() end)
    hp_style_row:add(hp_style_combo)

    hp_bar_cb = Gui.checkbox("Bar", config.hp_bar.show_bar ~= false)
    hp_bar_cb:on_change(function() apply_hp_settings() end)
    hp_style_row:add(hp_bar_cb)

    hp_text_cb = Gui.checkbox("Text", config.hp_bar.show_text == true)
    hp_text_cb:on_change(function() apply_hp_settings() end)
    hp_style_row:add(hp_text_cb)
    hp_box:add(hp_style_row)

    local hp_pos_row = Gui.hbox()
    hp_pos_row:add(Gui.label("Text Pos:"))
    hp_pos_combo = Gui.editable_combo({
        text = (config.hp_bar.text_position or "top") == "bottom" and "Bottom" or "Top",
        options = {"Top", "Bottom"},
    })
    hp_pos_combo:on_change(function() apply_hp_settings() end)
    hp_pos_row:add(hp_pos_combo)
    hp_box:add(hp_pos_row)

    local hp_fmt_row = Gui.hbox()
    hp_prefix_cb = Gui.checkbox("HP:", config.hp_bar.show_hp_prefix ~= false)
    hp_prefix_cb:on_change(function() apply_hp_settings() end)
    hp_fmt_row:add(hp_prefix_cb)
    hp_numbers_cb = Gui.checkbox("###/###", config.hp_bar.show_numbers ~= false)
    hp_numbers_cb:on_change(function() apply_hp_settings() end)
    hp_fmt_row:add(hp_numbers_cb)
    hp_pct_cb = Gui.checkbox("(##%)", config.hp_bar.show_percentage ~= false)
    hp_pct_cb:on_change(function() apply_hp_settings() end)
    hp_fmt_row:add(hp_pct_cb)
    hp_box:add(hp_fmt_row)

    local hp_dims_row = Gui.hbox()
    hp_dims_row:add(Gui.label("W:"))
    hp_w_input = Gui.input({text = tostring(config.hp_bar.width or 120), placeholder = "120"})
    hp_w_input:on_submit(function() apply_hp_settings() end)
    hp_dims_row:add(hp_w_input)
    hp_dims_row:add(Gui.label("H:"))
    hp_h_input = Gui.input({text = tostring(config.hp_bar.height or 16), placeholder = "16"})
    hp_h_input:on_submit(function() apply_hp_settings() end)
    hp_dims_row:add(hp_h_input)
    hp_dims_row:add(Gui.label("Font:"))
    hp_font_input = Gui.input({text = tostring(config.hp_bar.font_size or 11), placeholder = "11"})
    hp_font_input:on_submit(function() apply_hp_settings() end)
    hp_dims_row:add(hp_font_input)
    hp_box:add(hp_dims_row)

    tab_bar:set_tab_content(2, hp_box)

    -- Tab 4: Status settings
    local stat_box = Gui.vbox()

    status_show_cb = Gui.checkbox("Show Status", config.status.show ~= false)
    status_show_cb:on_change(function() apply_status_settings() end)
    stat_box:add(status_show_cb)

    local ssize_row = Gui.hbox()
    ssize_row:add(Gui.label("Font Size:"))
    status_size_input = Gui.input({text = tostring(config.status.font_size or 12), placeholder = "12"})
    status_size_input:on_submit(function() apply_status_settings() end)
    ssize_row:add(status_size_input)
    stat_box:add(ssize_row)

    tab_bar:set_tab_content(3, stat_box)

    root:add(tab_bar)

    -- Info label
    info_label = Gui.label("Calibrating: head (1/16)")
    root:add(info_label)

    -- Rank selector row
    local rank_row = Gui.hbox()
    rank_row:add(Gui.label("Rank:"))
    for r = 1, 3 do
        local btn = Gui.button(tostring(r))
        btn:on_click(function()
            current_rank = r
            update_markers()
            update_info()
        end)
        rank_row:add(btn)
    end
    root:add(rank_row)

    -- Navigation + Save buttons
    local nav_row = Gui.hbox()

    local prev_btn = Gui.button("< Prev")
    prev_btn:on_click(function()
        current_part_index = current_part_index - 1
        if current_part_index < 1 then current_part_index = #BODY_PARTS end
        update_markers()
        update_info()
    end)
    nav_row:add(prev_btn)

    local next_btn = Gui.button("Next >")
    next_btn:on_click(function()
        current_part_index = current_part_index + 1
        if current_part_index > #BODY_PARTS then current_part_index = 1 end
        update_markers()
        update_info()
    end)
    nav_row:add(next_btn)

    local save_btn = Gui.button("Save")
    save_btn:on_click(function()
        apply_all()
        save_silhouette_config(true)
    end)
    nav_row:add(save_btn)

    root:add(nav_row)

    -- Copy to all button
    local copy_btn = Gui.button("Copy UI Settings to All Creatures")
    copy_btn:on_click(function()
        copy_settings_to_all()
    end)
    root:add(copy_btn)

    -- Map view for silhouette
    map = Gui.map_view({width = 300, height = 300})
    map:on_click(function(evt)
        if type(evt) == "table" and evt.x and evt.y then
            -- evt.x, evt.y are in image-space (already divided by scale)
            local ms = (config.marker_size or 12) / 2
            local scale = config.scale or 1.0
            -- Coordinates are stored normalized to scale 1.0
            local nx = math.floor(evt.x - ms / scale + 0.5)
            local ny = math.floor(evt.y - ms / scale + 0.5)

            local part = BODY_PARTS[current_part_index]
            coordinates[part] = {nx, ny}

            update_markers()
            update_info()
        end
    end)

    root:add(map)

    -- Instructions
    root:add(Gui.label("Click silhouette to position wound markers"))

    win:set_root(Gui.scroll(root))
    win:show()

    -- Load initial silhouette image
    load_silhouette_image()
    update_markers()
    update_info()
end

--------------------------------------------------------------------------------
-- Upstream hook for ;calibrate commands (terminal fallback)
--------------------------------------------------------------------------------

local function on_upstream(line)
    local cmd = line:match("^;calibrate%s*(.*)")
    if not cmd then cmd = line:match("^;cal%s*(.*)") end
    if cmd then
        cmd = cmd:match("^%s*(.-)%s*$") or ""
        if cmd == "save" then
            apply_all()
            save_silhouette_config(true)
        elseif cmd == "done" or cmd == "quit" then
            apply_all()
            save_silhouette_config(true)
            running = false
        elseif cmd == "next" then
            current_part_index = current_part_index + 1
            if current_part_index > #BODY_PARTS then current_part_index = 1 end
            update_markers()
            update_info()
        elseif cmd == "prev" then
            current_part_index = current_part_index - 1
            if current_part_index < 1 then current_part_index = #BODY_PARTS end
            update_markers()
            update_info()
        elseif cmd:match("^rank%s+(%d+)$") then
            local r = tonumber(cmd:match("^rank%s+(%d+)$"))
            if r and r >= 1 and r <= 3 then
                current_rank = r
                update_markers()
                update_info()
            end
        elseif cmd:match("^set%s+(%-?%d+)%s+(%-?%d+)$") then
            local x, y = cmd:match("^set%s+(%-?%d+)%s+(%-?%d+)$")
            local part = BODY_PARTS[current_part_index]
            coordinates[part] = {tonumber(x), tonumber(y)}
            update_markers()
            update_info()
        elseif cmd:match("^family%s+(%S+)$") then
            local fam = cmd:match("^family%s+(%S+)$")
            -- Find the display name that matches
            for display, info in pairs(silhouette_map) do
                if info.family == fam then
                    change_family(display)
                    break
                end
            end
        elseif cmd == "list" then
            respond("\n--- " .. current_family .. " coordinates ---")
            for _, part in ipairs(BODY_PARTS) do
                local c = coordinates[part] or {0, 0}
                respond(string.format("  %s: [%d, %d]", part, c[1], c[2]))
            end
            respond("---\n")
        elseif cmd == "" or cmd == "help" or cmd == "status" then
            respond("\n=== CreatureBar Calibrator v" .. VERSION .. " ===")
            respond("Family: " .. current_family)
            respond("Part:   " .. BODY_PARTS[current_part_index] .. " (" .. current_part_index .. "/" .. #BODY_PARTS .. ")")
            respond("Commands: ;cal next|prev|rank N|set X Y|save|list|family NAME|done")
        else
            echo("Unknown: " .. cmd)
        end
        return nil
    end
    return line
end

UpstreamHook.add("calibrate_creaturebar", on_upstream)

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

before_dying(function()
    UpstreamHook.remove("calibrate_creaturebar")
    running = false
    if win then
        win:close()
        win = nil
    end
end)

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

ensure_dirs()
load_main_config()

-- Initialize with first available silhouette
local available = scan_silhouettes()
if #available > 0 then
    local first = available[1]
    local info = silhouette_map[first]
    if info then
        current_family = info.family
        current_subfolder = info.subfolder
        silhouette_file = info.rel_path
    end
end

load_silhouette_config(current_family, current_subfolder)

respond("Starting CreatureBar Calibrator v" .. VERSION)
respond("  Click on silhouette to position wound markers")
respond("  Use Prev/Next buttons or ;cal next/prev to navigate body parts")
respond("  Press rank buttons (1/2/3) to preview wound severity")
respond("  Click Save to persist all settings")
respond("  Type ;cal help for terminal commands")

build_ui()

-- Keep script alive
while running do
    pause(1)
end
