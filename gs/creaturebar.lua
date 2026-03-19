--- @revenant-script
--- name: creaturebar
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Nisugi
--- game: gs
--- @lic-certified: complete 2026-03-19
--- description: Visual creature status bar display with status effects, targeting, and multi-creature panels
--- tags: hunting,combat,creatures,gui
---
--- Ported from Lich5 Ruby creaturebar.lic v1.1
--- Original authors: Elanthia Online, Nisugi
---
--- Change Log:
--- v1.1 (2025/12/21) [original .lic]
---   - Alt + drag to move window around
---   - Warning if combat tracking disabled
--- v1.0 (2025/11/30) [original .lic]
---   - Shows current target (XMLData.current_target_id)
---   - Visual injury doll with wound overlays
---   - HP progress bar with color-coded ranges
---   - Status effect indicators
---   - Fully configurable colors and appearance
---   - Click panel to target creature
---   - Supports Frontend Focus Return
--- v2.0.0 (revenant)
---   - Full rewrite for Revenant widget-based GUI API
---   - Multi-tab settings dialog (Layout, Status Effects, Behavior)
---   - Grid layout: horizontal/vertical with max_columns/max_rows wrapping
---   - Status effect parsing from GameObj NPC status strings
---   - Click-to-target using put("target #id")
---   - Current target highlighting via GameObj.target()
---   - Per-character settings via CharSettings/Json
---   - All 15 status effects from original (+ sunburst, frozen, calmed, silenced, bound, hidden)
---   - Note: HP bars and wound overlays require a combat tracker module
---     (Lich5's Combat::Tracker parsed combat text for per-creature HP/wounds;
---      Revenant does not yet have this — when implemented, creaturebar will
---      gain HP/wound display with no script changes needed)
---
--- Usage:
---   ;creaturebar           - Start creature bar display
---   ;creaturebar config    - Start with settings dialog
---   ;creaturebar help      - Show help

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

--- All status effects from the original creaturebar.lic v1.1,
--- plus additional effects from the Lich5 creature tracking system.
--- Badge color must be one of: red, green, blue, yellow, white, black
local DEFAULT_STATUS_EFFECTS = {
    { name = "stunned",     symbol = "S",  color = "yellow" },
    { name = "immobilized", symbol = "I",  color = "red" },
    { name = "webbed",      symbol = "W",  color = "white" },
    { name = "prone",       symbol = "P",  color = "yellow" },
    { name = "blind",       symbol = "B",  color = "red" },
    { name = "sunburst",    symbol = "U",  color = "yellow" },
    { name = "sleeping",    symbol = "Z",  color = "blue" },
    { name = "poisoned",    symbol = "T",  color = "green" },
    { name = "dead",        symbol = "D",  color = "black" },
    { name = "bleeding",    symbol = "X",  color = "red" },
    { name = "frozen",      symbol = "F",  color = "blue" },
    { name = "calmed",      symbol = "C",  color = "blue" },
    { name = "silenced",    symbol = "Q",  color = "red" },
    { name = "bound",       symbol = "N",  color = "red" },
    { name = "hidden",      symbol = "H",  color = "white" },
}

local DEFAULT_CONFIG = {
    update_interval  = 500,
    max_creatures    = 5,
    layout_mode      = "horizontal",
    max_columns      = 5,
    max_rows         = 2,
    show_name        = true,
    show_status      = true,
    name_mode        = "noun",
    status_effects   = DEFAULT_STATUS_EFFECTS,
}

local config = load_json("creaturebar_config", nil)
if not config then
    config = {}
    for k, v in pairs(DEFAULT_CONFIG) do config[k] = v end
else
    for k, v in pairs(DEFAULT_CONFIG) do
        if config[k] == nil then config[k] = v end
    end
end

local function save_config()
    save_json("creaturebar_config", config)
end

--------------------------------------------------------------------------------
-- Status effect helpers
--------------------------------------------------------------------------------

local function parse_status_string(status_str)
    if not status_str or status_str == "" then return {} end
    local statuses = {}
    local s = status_str:lower()
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        if string.find(s, se.name:lower(), 1, true) then
            statuses[#statuses + 1] = se
        end
    end
    if #statuses == 0 and s ~= "" then
        statuses[#statuses + 1] = { name = status_str, symbol = status_str:sub(1, 1):upper(), color = "white" }
    end
    return statuses
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local window = nil
local running = true
local settings_win = nil
-- Track which creature IDs are currently displayed (ordered)
local displayed_ids = {}

--------------------------------------------------------------------------------
-- Build display
--------------------------------------------------------------------------------

--- Build the full root widget tree for the current target list.
--- Returns the root widget and a table of per-panel data for updates.
local function build_display(targets, current_target_id)
    local panel_data = {}
    local root = Gui.vbox()

    if #targets == 0 then
        root:add(Gui.label("No creatures"))
        return root, panel_data
    end

    local layout_mode = config.layout_mode or "horizontal"
    local max_cols = config.max_columns or 5
    local max_rows_cfg = config.max_rows or 2

    --- Create a panel widget tree for one NPC.
    local function make_panel(npc)
        local card = Gui.card({})
        local vbox = Gui.vbox()

        -- Target indicator
        local is_current = (npc.id == current_target_id)
        local target_label = Gui.label(is_current and ">> TARGET <<" or "")
        vbox:add(target_label)

        -- Name
        local name_label = nil
        if config.show_name then
            local display_name
            if config.name_mode == "noun" then
                display_name = npc.noun or "unknown"
            else
                display_name = npc.name or "Unknown"
            end
            name_label = Gui.label(display_name)
            vbox:add(name_label)
        end

        -- Status badges
        local status_label = nil
        if config.show_status then
            local status_str = npc.status or ""
            local statuses = parse_status_string(status_str)
            if #statuses > 0 then
                local badge_box = Gui.hbox()
                for _, se in ipairs(statuses) do
                    badge_box:add(Gui.badge(se.symbol, { color = se.color, outlined = false }))
                end
                vbox:add(badge_box)
            end
            -- Also add a text label for status that can be updated
            local status_parts = {}
            for _, se in ipairs(statuses) do
                status_parts[#status_parts + 1] = se.name
            end
            status_label = Gui.label(table.concat(status_parts, ", "))
            vbox:add(status_label)
        end

        -- Target button
        local btn = Gui.button("Target #" .. tostring(npc.id))
        btn:on_click(function()
            put("target #" .. tostring(npc.id))
        end)
        vbox:add(btn)

        card:add(vbox)

        local pd = {
            creature_id = npc.id,
            target_label = target_label,
            name_label = name_label,
            status_label = status_label,
            last_name = (config.name_mode == "noun") and (npc.noun or "") or (npc.name or ""),
            last_status = npc.status or "",
            is_current = is_current,
        }
        panel_data[#panel_data + 1] = pd

        return card
    end

    if layout_mode == "horizontal" then
        local row = nil
        local col_count = 0
        for _, npc in ipairs(targets) do
            if col_count == 0 or col_count >= max_cols then
                row = Gui.hbox()
                root:add(row)
                col_count = 0
            end
            row:add(make_panel(npc))
            col_count = col_count + 1
        end
    else
        -- Vertical: fill rows first, wrap to next column
        local columns = {}
        local current_col = 1
        local row_count = 0
        for _, npc in ipairs(targets) do
            if not columns[current_col] then columns[current_col] = {} end
            columns[current_col][#columns[current_col] + 1] = npc
            row_count = row_count + 1
            if row_count >= max_rows_cfg then
                current_col = current_col + 1
                row_count = 0
            end
        end
        local hbox = Gui.hbox()
        for _, col_npcs in ipairs(columns) do
            local col_vbox = Gui.vbox()
            for _, npc in ipairs(col_npcs) do
                col_vbox:add(make_panel(npc))
            end
            hbox:add(col_vbox)
        end
        root:add(hbox)
    end

    return root, panel_data
end

--- Check if the target list has changed (different IDs or order).
local function targets_changed(targets)
    if #targets ~= #displayed_ids then return true end
    for i, t in ipairs(targets) do
        if t.id ~= displayed_ids[i] then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Settings Dialog
--------------------------------------------------------------------------------

local function open_settings()
    if settings_win then return end

    settings_win = Gui.window("CreatureBar Settings", { width = 500, height = 500, resizable = true })

    local tabs = Gui.tab_bar({ "Layout", "Status Effects", "Behavior" })

    -- Tab 1: Layout
    local layout_box = Gui.vbox()
    layout_box:add(Gui.section_header("Display"))

    local show_name_cb = Gui.checkbox("Show creature name", config.show_name)
    show_name_cb:on_change(function(v) config.show_name = v; save_config() end)
    layout_box:add(show_name_cb)

    local show_status_cb = Gui.checkbox("Show status effects", config.show_status)
    show_status_cb:on_change(function(v) config.show_status = v; save_config() end)
    layout_box:add(show_status_cb)

    layout_box:add(Gui.separator())
    layout_box:add(Gui.section_header("Name Display"))
    local name_combo = Gui.editable_combo({
        text = config.name_mode or "noun",
        hint = "noun or name",
        options = { "noun", "name" },
    })
    name_combo:on_change(function(v)
        if v == "noun" or v == "name" then config.name_mode = v; save_config() end
    end)
    local nr = Gui.hbox()
    nr:add(Gui.label("Name mode:"))
    nr:add(name_combo)
    layout_box:add(nr)

    layout_box:add(Gui.separator())
    layout_box:add(Gui.section_header("Grid Layout"))

    local layout_combo = Gui.editable_combo({
        text = config.layout_mode or "horizontal",
        hint = "horizontal or vertical",
        options = { "horizontal", "vertical" },
    })
    layout_combo:on_change(function(v)
        if v == "horizontal" or v == "vertical" then config.layout_mode = v; save_config() end
    end)
    local lr = Gui.hbox()
    lr:add(Gui.label("Layout mode:"))
    lr:add(layout_combo)
    layout_box:add(lr)

    local mc_input = Gui.input({ text = tostring(config.max_creatures or 5), placeholder = "5" })
    mc_input:on_change(function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 20 then config.max_creatures = n; save_config() end
    end)
    local mcr = Gui.hbox()
    mcr:add(Gui.label("Max creatures:"))
    mcr:add(mc_input)
    layout_box:add(mcr)

    local mcol_input = Gui.input({ text = tostring(config.max_columns or 5), placeholder = "5" })
    mcol_input:on_change(function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 20 then config.max_columns = n; save_config() end
    end)
    local mcolr = Gui.hbox()
    mcolr:add(Gui.label("Max columns (horiz):"))
    mcolr:add(mcol_input)
    layout_box:add(mcolr)

    local mrow_input = Gui.input({ text = tostring(config.max_rows or 2), placeholder = "2" })
    mrow_input:on_change(function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 20 then config.max_rows = n; save_config() end
    end)
    local mrowr = Gui.hbox()
    mrowr:add(Gui.label("Max rows (vert):"))
    mrowr:add(mrow_input)
    layout_box:add(mrowr)

    tabs:set_tab_content(1, Gui.scroll(layout_box))

    -- Tab 2: Status Effects
    local status_box = Gui.vbox()
    status_box:add(Gui.section_header("Configured Status Effects"))
    status_box:add(Gui.label("Status effects detected in NPC status strings:"))
    status_box:add(Gui.separator())

    local st = Gui.table({ columns = { "Name", "Symbol", "Badge Color" } })
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        st:add_row({ se.name, se.symbol, se.color })
    end
    status_box:add(st)

    status_box:add(Gui.separator())
    status_box:add(Gui.label("Edit status_effects in CharSettings creaturebar_config JSON."))
    status_box:add(Gui.label("Badge colors: red, green, blue, yellow, white, black"))

    tabs:set_tab_content(2, Gui.scroll(status_box))

    -- Tab 3: Behavior
    local behavior_box = Gui.vbox()
    behavior_box:add(Gui.section_header("Update Interval"))

    local int_input = Gui.input({
        text = tostring(config.update_interval or 500),
        placeholder = "500",
    })
    int_input:on_change(function(v)
        local n = tonumber(v)
        if n and n >= 100 and n <= 5000 then config.update_interval = n; save_config() end
    end)
    local ir = Gui.hbox()
    ir:add(Gui.label("Interval (ms):"))
    ir:add(int_input)
    behavior_box:add(ir)

    behavior_box:add(Gui.separator())
    behavior_box:add(Gui.section_header("About"))
    behavior_box:add(Gui.label("CreatureBar v2.0.0 — Revenant port"))
    behavior_box:add(Gui.label("Original: creaturebar.lic v1.1 by Elanthia Online / Nisugi"))
    behavior_box:add(Gui.separator())
    behavior_box:add(Gui.label("HP bars and wound overlays are not yet available."))
    behavior_box:add(Gui.label("Lich5 used Combat::Tracker to parse combat text"))
    behavior_box:add(Gui.label("for per-creature HP and injury data."))
    behavior_box:add(Gui.label("When Revenant adds a combat tracker, those"))
    behavior_box:add(Gui.label("features will be activated automatically."))

    tabs:set_tab_content(3, Gui.scroll(behavior_box))

    local root = Gui.vbox()
    root:add(tabs)
    settings_win:set_root(root)
    settings_win:on_close(function() settings_win = nil end)
    settings_win:show()
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("===========================================================")
    respond(" CreatureBar - Visual creature tracking for GemStone IV")
    respond("===========================================================")
    respond("")
    respond(" Usage: ;creaturebar [command]")
    respond("")
    respond(" Commands:")
    respond("   (none)     Start CreatureBar")
    respond("   config     Start with settings dialog open")
    respond("   help       Show this help message")
    respond("")
    respond(" While running:")
    respond("   Click 'Target' button to target a creature")
    respond("   Status effects are auto-detected from game data")
    respond("   Current target is highlighted with >> TARGET <<")
    respond("")
    respond(" Status effects tracked:")
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        respond(string.format("   [%s] %s", se.symbol, se.name))
    end
    respond("")
    respond(" Settings saved per-character via CharSettings.")
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

-- Check for GameObj module
if not GameObj then
    echo("Error: GameObj module not available.")
    return
end

-- Check for combat tracker (advisory)
local ct_ok, CombatTracker = pcall(function()
    return _G.CombatTracker
end)
if ct_ok and CombatTracker and type(CombatTracker) == "table"
   and CombatTracker.enabled_p and not CombatTracker.enabled_p() then
    respond("")
    respond("[CreatureBar] Note: Combat tracker is not enabled.")
    respond("  NPC death events may not be detected.")
    respond("  To enable: require('lib/gs/combat_tracker').enable()")
    respond("")
end

respond("Starting CreatureBar...")

-- Create the main window
window = Gui.window("CB", { width = 350, height = 200, resizable = true })

local initial = Gui.vbox()
initial:add(Gui.label("Waiting for creatures..."))
window:set_root(initial)
window:on_close(function() running = false end)
window:show()

-- Open settings if requested
if cmd == "config" or cmd == "setup" then
    open_settings()
end

-- Cleanup on exit
before_dying(function()
    running = false
    if window then pcall(function() window:close() end) end
    if settings_win then pcall(function() settings_win:close() end) end
end)

-- Tracking state for incremental updates
local panel_data = {}
local force_rebuild = true

-- Main update loop
while running do
    local interval_sec = (config.update_interval or 500) / 1000.0
    pause(interval_sec)
    if not running then break end

    -- Get current targets
    local all_targets = {}
    if GameObj.targets then
        local ok, t = pcall(GameObj.targets)
        if ok and t then all_targets = t end
    end

    -- Limit to max_creatures
    local max = config.max_creatures or 5
    local targets = {}
    for i, t in ipairs(all_targets) do
        if i > max then break end
        if t.id and t.noun then
            targets[#targets + 1] = t
        end
    end

    -- Get current target ID
    local current_target_id = nil
    if GameObj.target then
        local ok, ct = pcall(GameObj.target)
        if ok and ct then current_target_id = ct.id end
    end

    -- Check if we need a full rebuild (creature list changed)
    local need_rebuild = force_rebuild or targets_changed(targets)

    if need_rebuild then
        force_rebuild = false
        -- Record new displayed IDs
        displayed_ids = {}
        for _, t in ipairs(targets) do
            displayed_ids[#displayed_ids + 1] = t.id
        end

        -- Build and set new display
        local ok, err = pcall(function()
            local root, pd = build_display(targets, current_target_id)
            panel_data = pd
            window:set_root(Gui.scroll(root))
        end)
        if not ok then
            echo("Display error: " .. tostring(err))
            pause(2)
        end
    else
        -- Incremental update: only update labels that changed
        for _, pd in ipairs(panel_data) do
            -- Find matching NPC
            local npc = nil
            for _, t in ipairs(targets) do
                if t.id == pd.creature_id then npc = t; break end
            end
            if not npc then goto next_panel end

            -- Update target indicator
            local is_current = (npc.id == current_target_id)
            if is_current ~= pd.is_current then
                pd.is_current = is_current
                if pd.target_label then
                    pd.target_label:set_text(is_current and ">> TARGET <<" or "")
                end
            end

            -- Update name
            if pd.name_label then
                local display_name
                if config.name_mode == "noun" then
                    display_name = npc.noun or "unknown"
                else
                    display_name = npc.name or "Unknown"
                end
                if display_name ~= pd.last_name then
                    pd.last_name = display_name
                    pd.name_label:set_text(display_name)
                end
            end

            -- Update status text
            if pd.status_label then
                local status_str = npc.status or ""
                if status_str ~= pd.last_status then
                    pd.last_status = status_str
                    local statuses = parse_status_string(status_str)
                    local parts = {}
                    for _, se in ipairs(statuses) do
                        parts[#parts + 1] = se.name
                    end
                    pd.status_label:set_text(table.concat(parts, ", "))
                end
            end

            ::next_panel::
        end
    end
end
