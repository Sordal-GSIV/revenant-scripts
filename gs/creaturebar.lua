--- @revenant-script
--- name: creaturebar
--- version: 1.1.0
--- author: elanthia-online
--- contributors: Nisugi
--- game: gs
--- description: Visual creature status bar display with injury tracking, HP bar, and status effects
--- tags: hunting,combat,creatures,gui
---
--- Ported from Lich5 Ruby creaturebar.lic v1.1
---
--- Usage:
---   ;creaturebar           - Start creature bar display
---   ;creaturebar config    - Start with settings dialog
---   ;creaturebar help      - Show help
---
--- Features:
---   - Shows current target with name and HP bar
---   - Visual wound/injury indicators per body part
---   - Status effect display (stunned, prone, etc.)
---   - Multi-creature panel support
---   - Click to target creature
---   - Color-coded HP ranges

no_kill_all()
no_pause_all()

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

local DEFAULT_CONFIG = {
    update_interval  = 250,
    max_creatures    = 5,
    layout_mode      = "horizontal",
    max_columns      = 5,
    window_x         = 100,
    window_y         = 100,
    window_width     = 500,
    window_height    = 200,
    show_hp_bar      = true,
    show_hp_text     = true,
    show_hp_numbers  = true,
    show_hp_percent  = true,
    show_name        = true,
    show_status      = true,
    show_wounds      = true,
    name_mode        = "noun",
    -- Colors
    color_bg         = "#2E2E2E",
    color_name_font  = "#FFFFFF",
    color_name_bg    = "#000000",
    color_target_border = "#FFD700",
    color_other_border  = "#555555",
    color_hp_bg      = "#3C1414",
    color_hp_high    = "#2E7D32",
    color_hp_mid     = "#FFB000",
    color_hp_low     = "#FF4444",
    color_hp_text    = "#FFFFFF",
    hp_high_min      = 75,
    hp_mid_min       = 40,
    -- Status effects
    status_effects = {
        { name = "stunned",     symbol = "S", color = "#FFD700" },
        { name = "immobilized", symbol = "I", color = "#FF69B4" },
        { name = "webbed",      symbol = "W", color = "#C0C0C0" },
        { name = "prone",       symbol = "P", color = "#FFA500" },
        { name = "blind",       symbol = "B", color = "#8B4513" },
        { name = "sleeping",    symbol = "Z", color = "#9370DB" },
        { name = "poisoned",    symbol = "T", color = "#32CD32" },
        { name = "dead",        symbol = "D", color = "#000000" },
        { name = "bleeding",    symbol = "X", color = "#DC143C" },
    },
}

local config = load_json("creaturebar_config", DEFAULT_CONFIG)
for k, v in pairs(DEFAULT_CONFIG) do
    if config[k] == nil then config[k] = v end
end

--------------------------------------------------------------------------------
-- Status effect helpers
--------------------------------------------------------------------------------

local function get_status_symbol(status_name)
    status_name = (status_name or ""):lower()
    for _, se in ipairs(config.status_effects or {}) do
        if se.name:lower() == status_name then
            return se.symbol
        end
    end
    return status_name:sub(1, 1):upper()
end

local function get_status_color(status_name)
    status_name = (status_name or ""):lower()
    for _, se in ipairs(config.status_effects or {}) do
        if se.name:lower() == status_name then
            return se.color
        end
    end
    return "#FFFFFF"
end

--------------------------------------------------------------------------------
-- HP color calculation
--------------------------------------------------------------------------------

local function get_hp_color(percentage)
    if percentage >= config.hp_high_min then
        return config.color_hp_high
    elseif percentage >= config.hp_mid_min then
        return config.color_hp_mid
    else
        return config.color_hp_low
    end
end

--------------------------------------------------------------------------------
-- Body parts for wound display
--------------------------------------------------------------------------------

local BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nsys",
}

local WOUND_COLORS = {
    [1] = "#FFFF00",  -- yellow (minor)
    [2] = "#FFA500",  -- orange (moderate)
    [3] = "#FF0000",  -- red (severe)
}

--------------------------------------------------------------------------------
-- Panel State
--------------------------------------------------------------------------------

local panels = {}       -- creature_id => panel data
local window = nil
local main_box = nil
local update_timer = nil
local running = true

--------------------------------------------------------------------------------
-- GUI Construction
--------------------------------------------------------------------------------

local function create_creature_panel(creature_id)
    local creature = Creature and Creature[creature_id]
    if not creature then return nil end

    local panel = {
        creature_id = creature_id,
        last_hp_frac = -1,
        last_hp_color = "",
        last_name = "",
        last_status = "",
        is_current = false,
    }

    -- Frame for border
    panel.frame = Gui.frame(main_box, "")

    local vbox = Gui.vbox(panel.frame)

    -- Name label
    if config.show_name then
        panel.name_label = Gui.label(vbox, "")
    end

    -- HP bar
    if config.show_hp_bar then
        panel.hp_bar = Gui.progress(vbox, 0.0)
    end

    -- HP text
    if config.show_hp_text then
        panel.hp_label = Gui.label(vbox, "")
    end

    -- Wound indicators
    if config.show_wounds then
        panel.wound_label = Gui.label(vbox, "")
    end

    -- Status effects
    if config.show_status then
        panel.status_label = Gui.label(vbox, "")
    end

    -- Click to target
    Gui.on_click(panel.frame, function()
        fput("target #" .. tostring(creature_id))
    end)

    return panel
end

local function update_panel(panel)
    local creature_id = panel.creature_id
    local creature = Creature and Creature[creature_id]
    if not creature then return end

    -- Update name
    if panel.name_label then
        local name
        if config.name_mode == "noun" then
            name = creature.noun or "unknown"
        else
            name = creature.name or "Unknown"
        end
        if name ~= panel.last_name then
            panel.last_name = name
            Gui.set_text(panel.name_label, name)
        end
    end

    -- Update border (current target vs other)
    local current_target_id = GameState.current_target_id
    local is_current = (tostring(creature_id) == tostring(current_target_id))
    if is_current ~= panel.is_current then
        panel.is_current = is_current
        local border_color = is_current and config.color_target_border or config.color_other_border
        Gui.set_style(panel.frame, "border-color", border_color)
    end

    -- Update HP
    local max_hp = creature.max_hp
    local current_hp = creature.current_hp

    if max_hp and max_hp > 0 and current_hp then
        local frac = math.max(current_hp / max_hp, 0.0)
        local pct = math.floor(frac * 100)
        local hp_color = get_hp_color(pct)

        if math.abs(frac - (panel.last_hp_frac or -1)) > 0.001 or hp_color ~= panel.last_hp_color then
            panel.last_hp_frac = frac
            panel.last_hp_color = hp_color

            if panel.hp_bar then
                Gui.set_progress(panel.hp_bar, frac)
                Gui.set_style(panel.hp_bar, "color", hp_color)
            end

            if panel.hp_label then
                local parts = {}
                if config.show_hp_numbers then
                    parts[#parts + 1] = string.format("%d/%d", current_hp, max_hp)
                end
                if config.show_hp_percent then
                    parts[#parts + 1] = string.format("(%d%%)", pct)
                end
                Gui.set_text(panel.hp_label, "HP: " .. table.concat(parts, " "))
            end
        end
    else
        if panel.hp_bar then Gui.set_progress(panel.hp_bar, 1.0) end
        if panel.hp_label then Gui.set_text(panel.hp_label, "HP: --/--") end
    end

    -- Update wounds
    if panel.wound_label and config.show_wounds then
        local injuries = creature.injuries or {}
        local wound_parts = {}
        for _, part in ipairs(BODY_PARTS) do
            local level = injuries[part]
            if level and level > 0 then
                local rank = math.min(level, 3)
                local color = WOUND_COLORS[rank] or "#FFFFFF"
                local abbrev = part:sub(1, 2):upper()
                wound_parts[#wound_parts + 1] = string.format("[%s:%d]", abbrev, rank)
            end
        end
        local wound_str = table.concat(wound_parts, " ")
        if wound_str ~= (panel.last_wounds or "") then
            panel.last_wounds = wound_str
            Gui.set_text(panel.wound_label, wound_str)
        end
    end

    -- Update status effects
    if panel.status_label and config.show_status then
        local statuses = creature.status or {}
        local status_parts = {}
        for _, s in ipairs(statuses) do
            local sym = get_status_symbol(s)
            status_parts[#status_parts + 1] = sym
        end
        local status_str = table.concat(status_parts, " ")
        if status_str ~= panel.last_status then
            panel.last_status = status_str
            Gui.set_text(panel.status_label, status_str)
        end
    end
end

--------------------------------------------------------------------------------
-- Display update loop
--------------------------------------------------------------------------------

local function update_display()
    if not running then return end

    local targets = {}
    if GameObj and GameObj.targets then
        targets = GameObj.targets() or {}
    end

    -- Get creature IDs (up to max)
    local target_ids = {}
    for _, t in ipairs(targets) do
        if t.id and t.noun and t.name then
            target_ids[#target_ids + 1] = t.id
            if #target_ids >= config.max_creatures then break end
        end
    end

    -- Build set for quick lookup
    local id_set = {}
    for _, id in ipairs(target_ids) do id_set[id] = true end

    -- Remove panels for creatures no longer present
    for cid, panel in pairs(panels) do
        if not id_set[cid] then
            Gui.remove(panel.frame)
            panels[cid] = nil
        end
    end

    -- Add/update panels
    for _, cid in ipairs(target_ids) do
        if not panels[cid] then
            local panel = create_creature_panel(cid)
            if panel then
                panels[cid] = panel
            end
        end
        if panels[cid] then
            update_panel(panels[cid])
        end
    end

    -- Resize window hint
    if window then
        local count = 0
        for _ in pairs(panels) do count = count + 1 end
        if count == 0 then
            Gui.set_size(window, config.window_width, 30)
        end
    end
end

--------------------------------------------------------------------------------
-- Settings dialog
--------------------------------------------------------------------------------

local function configure_settings()
    local dlg = Gui.window("CreatureBar Settings", 350, 500)
    local box = Gui.vbox(dlg)

    Gui.label(box, "=== CreatureBar Settings ===")
    Gui.label(box, "")

    Gui.label(box, "Display:")
    Gui.checkbox(box, "Show HP Bar", config.show_hp_bar, function(v)
        config.show_hp_bar = v; save_json("creaturebar_config", config)
    end)
    Gui.checkbox(box, "Show HP Text", config.show_hp_text, function(v)
        config.show_hp_text = v; save_json("creaturebar_config", config)
    end)
    Gui.checkbox(box, "Show Name", config.show_name, function(v)
        config.show_name = v; save_json("creaturebar_config", config)
    end)
    Gui.checkbox(box, "Show Wounds", config.show_wounds, function(v)
        config.show_wounds = v; save_json("creaturebar_config", config)
    end)
    Gui.checkbox(box, "Show Status", config.show_status, function(v)
        config.show_status = v; save_json("creaturebar_config", config)
    end)

    Gui.label(box, "")
    Gui.label(box, "Layout:")
    Gui.entry(box, "Max creatures:", tostring(config.max_creatures), function(v)
        config.max_creatures = tonumber(v) or 5
        save_json("creaturebar_config", config)
    end)
    Gui.entry(box, "Update interval (ms):", tostring(config.update_interval), function(v)
        config.update_interval = tonumber(v) or 250
        save_json("creaturebar_config", config)
    end)

    Gui.label(box, "")
    Gui.label(box, "HP Thresholds:")
    Gui.entry(box, "High HP min %:", tostring(config.hp_high_min), function(v)
        config.hp_high_min = tonumber(v) or 75
        save_json("creaturebar_config", config)
    end)
    Gui.entry(box, "Mid HP min %:", tostring(config.hp_mid_min), function(v)
        config.hp_mid_min = tonumber(v) or 40
        save_json("creaturebar_config", config)
    end)

    Gui.show(dlg)
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("=== CreatureBar - Visual creature tracking ===")
    respond("")
    respond("  ;creaturebar           Start the display")
    respond("  ;creaturebar config    Open settings dialog")
    respond("  ;creaturebar help      Show this help")
    respond("")
    respond("  While running:")
    respond("    Click a panel to target that creature")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cmd = (Script.vars[1] or ""):lower()

if cmd == "help" then
    show_help()
    return
end

-- Check for Creature module
if not Creature then
    echo("Error: Creature module not found. Make sure creature tracking is enabled.")
    return
end

respond("Starting CreatureBar...")

-- Create the main window
window = Gui.window("CB", config.window_width, config.window_height)
Gui.set_position(window, config.window_x, config.window_y)
main_box = Gui.hbox(window)

Gui.show(window)

-- Open settings if requested
if Regex.test(cmd, "^config|^setup") then
    pause(0.5)
    configure_settings()
end

-- Start update timer
update_timer = Timer.add(config.update_interval, function()
    if not running then return false end
    update_display()
    return true  -- keep running
end)

-- Cleanup on exit
before_dying(function()
    running = false
    if update_timer then
        Timer.remove(update_timer)
    end
    -- Save window position
    if window then
        local x, y = Gui.get_position(window)
        if x and y then
            config.window_x = x
            config.window_y = y
        end
        local w, h = Gui.get_size(window)
        if w and h then
            config.window_width = w
            config.window_height = h
        end
        save_json("creaturebar_config", config)
        Gui.close(window)
    end
end)

-- Keep alive
while running do
    pause(1)
    if not Script.running(Script.name) then break end
end
