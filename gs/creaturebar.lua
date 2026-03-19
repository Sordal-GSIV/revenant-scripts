--- @revenant-script
--- name: creaturebar
--- version: 2.1.0
--- author: elanthia-online
--- contributors: Nisugi
--- game: gs
--- @lic-certified: complete 2026-03-19
--- description: Visual creature status bar with HP, wounds, status effects, and targeting
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
--- v2.1.0 (revenant)
---   - Full rewrite for Revenant widget-based GUI API
---   - HP progress bar with color-coded ranges (via CombatCreature tracker)
---   - Wound/injury indicators per body part (text-based, 16 parts)
---   - Status effects from CombatCreature + GameObj.status parsing
---   - Current target via GameState.current_target_id (XML dropdown box)
---   - Multi-tab settings dialog (Layout, HP/Wounds, Status, Behavior)
---   - Grid layout: horizontal/vertical with max_columns/max_rows wrapping
---   - Click-to-target using put("target #id")
---   - All 15 status effects from original (+ sunburst, frozen, calmed, etc.)
---   - Per-character settings via CharSettings/Json
---   - Auto-enables CombatTracker if not running
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

local BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nsys",
}

local BODY_PART_ABBREV = {
    head = "HD", neck = "NK", chest = "CH", abdomen = "AB", back = "BK",
    leftArm = "LA", rightArm = "RA", leftHand = "LH", rightHand = "RH",
    leftLeg = "LL", rightLeg = "RL", leftFoot = "LF", rightFoot = "RF",
    leftEye = "LE", rightEye = "RE", nsys = "NS",
}

local DEFAULT_CONFIG = {
    update_interval  = 500,
    max_creatures    = 5,
    layout_mode      = "horizontal",
    max_columns      = 5,
    max_rows         = 2,
    show_name        = true,
    show_status      = true,
    show_hp          = true,
    show_wounds      = true,
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

--- Merge status data from CombatCreature tracker and GameObj.status string.
local function get_creature_statuses(npc_id, gameobj_status_str)
    local seen = {}
    local result = {}

    -- Primary source: CombatCreature tracker (parsed from combat text)
    if CreatureInstance then
        local statuses = CreatureInstance.statuses(npc_id) or {}
        for _, s in ipairs(statuses) do
            if not seen[s] then
                seen[s] = true
                result[#result + 1] = s
            end
        end
    end

    -- Secondary source: GameObj.status string (from XML)
    if gameobj_status_str and gameobj_status_str ~= "" then
        local s = gameobj_status_str:lower()
        for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
            local name = se.name:lower()
            if string.find(s, name, 1, true) and not seen[name] then
                seen[name] = true
                result[#result + 1] = se.name
            end
        end
    end

    return result
end

local function get_status_badge_color(status_name)
    local sn = (status_name or ""):lower()
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        if se.name:lower() == sn then return se.color end
    end
    return "white"
end

local function get_status_symbol(status_name)
    local sn = (status_name or ""):lower()
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        if se.name:lower() == sn then return se.symbol end
    end
    return status_name:sub(1, 1):upper()
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local window = nil
local running = true
local settings_win = nil
local displayed_ids = {}

--------------------------------------------------------------------------------
-- Build display
--------------------------------------------------------------------------------

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

    local function make_panel(npc)
        local card = Gui.card({})
        local vbox = Gui.vbox()

        -- Target indicator
        local is_current = (tostring(npc.id) == tostring(current_target_id))
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

        -- HP bar (from CombatCreature tracker)
        local hp_bar = nil
        local hp_label = nil
        if config.show_hp then
            local cc = CombatCreature and CombatCreature[npc.id]
            if cc then
                local pct = cc.hp_percent or 100
                hp_bar = Gui.progress(pct / 100.0)
                vbox:add(hp_bar)
                hp_label = Gui.label(string.format("HP: %d/%d (%d%%)",
                    cc.current_hp or 0, cc.max_hp or 0, pct))
            else
                hp_bar = Gui.progress(1.0)
                vbox:add(hp_bar)
                hp_label = Gui.label("HP: --/--")
            end
            vbox:add(hp_label)
        end

        -- Wound indicators (from CombatCreature tracker)
        local wound_label = nil
        if config.show_wounds then
            local cc = CombatCreature and CombatCreature[npc.id]
            local wound_parts = {}
            if cc and cc.injuries then
                for _, part in ipairs(BODY_PARTS) do
                    local level = cc.injuries[part]
                    if level and level > 0 then
                        local abbrev = BODY_PART_ABBREV[part] or part:sub(1, 2):upper()
                        wound_parts[#wound_parts + 1] = string.format("[%s:%d]", abbrev, level)
                    end
                end
            end
            wound_label = Gui.label(table.concat(wound_parts, " "))
            vbox:add(wound_label)
        end

        -- Status badges
        local status_label = nil
        if config.show_status then
            local statuses = get_creature_statuses(npc.id, npc.status)
            if #statuses > 0 then
                local badge_box = Gui.hbox()
                for _, s in ipairs(statuses) do
                    badge_box:add(Gui.badge(get_status_symbol(s),
                        { color = get_status_badge_color(s), outlined = false }))
                end
                vbox:add(badge_box)
            end
            local parts = {}
            for _, s in ipairs(statuses) do parts[#parts + 1] = s end
            status_label = Gui.label(table.concat(parts, ", "))
            vbox:add(status_label)
        end

        -- Target button
        local btn = Gui.button("Target")
        btn:on_click(function()
            put("target #" .. tostring(npc.id))
        end)
        vbox:add(btn)

        card:add(vbox)

        local pd = {
            creature_id = npc.id,
            target_label = target_label,
            name_label = name_label,
            hp_bar = hp_bar,
            hp_label = hp_label,
            wound_label = wound_label,
            status_label = status_label,
            last_name = (config.name_mode == "noun") and (npc.noun or "") or (npc.name or ""),
            last_status = "",
            last_hp_pct = -1,
            last_wounds = "",
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

    local tabs = Gui.tab_bar({ "Layout", "HP & Wounds", "Status Effects", "Behavior" })

    -- Tab 1: Layout
    local layout_box = Gui.vbox()
    layout_box:add(Gui.section_header("Display"))

    local show_name_cb = Gui.checkbox("Show creature name", config.show_name)
    show_name_cb:on_change(function(v) config.show_name = v; save_config() end)
    layout_box:add(show_name_cb)

    local show_status_cb = Gui.checkbox("Show status effects", config.show_status)
    show_status_cb:on_change(function(v) config.show_status = v; save_config() end)
    layout_box:add(show_status_cb)

    local show_hp_cb = Gui.checkbox("Show HP bar", config.show_hp)
    show_hp_cb:on_change(function(v) config.show_hp = v; save_config() end)
    layout_box:add(show_hp_cb)

    local show_wounds_cb = Gui.checkbox("Show wound indicators", config.show_wounds)
    show_wounds_cb:on_change(function(v) config.show_wounds = v; save_config() end)
    layout_box:add(show_wounds_cb)

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

    -- Tab 2: HP & Wounds
    local hp_box = Gui.vbox()
    hp_box:add(Gui.section_header("HP Tracking"))
    hp_box:add(Gui.label("HP is estimated by tracking damage dealt to creatures."))
    hp_box:add(Gui.label("Max HP comes from bestiary data or a configurable fallback."))
    hp_box:add(Gui.separator())

    local tracker_status = "DISABLED"
    if CombatTracker and CombatTracker.enabled_p and CombatTracker.enabled_p() then
        tracker_status = "ENABLED"
    end
    hp_box:add(Gui.label("Combat Tracker: " .. tracker_status))

    if CombatTracker and CombatTracker.stats then
        local stats = CombatTracker.stats()
        hp_box:add(Gui.label("Creatures tracked: " .. tostring(stats.creatures_tracked or 0)))
        hp_box:add(Gui.label("Chunks processed: " .. tostring(stats.chunks_processed or 0)))
    end

    hp_box:add(Gui.separator())
    hp_box:add(Gui.section_header("Wound Display"))
    hp_box:add(Gui.label("Body parts tracked (16):"))
    local parts_str = {}
    for _, p in ipairs(BODY_PARTS) do
        parts_str[#parts_str + 1] = BODY_PART_ABBREV[p] .. "=" .. p
    end
    hp_box:add(Gui.label(table.concat(parts_str, ", ")))
    hp_box:add(Gui.label("Wound ranks: 1=minor, 2=moderate, 3=severe"))

    tabs:set_tab_content(2, Gui.scroll(hp_box))

    -- Tab 3: Status Effects
    local status_box = Gui.vbox()
    status_box:add(Gui.section_header("Configured Status Effects"))
    status_box:add(Gui.label("Detected from combat text + NPC status XML:"))
    status_box:add(Gui.separator())

    local st = Gui.table({ columns = { "Name", "Symbol", "Badge Color" } })
    for _, se in ipairs(config.status_effects or DEFAULT_STATUS_EFFECTS) do
        st:add_row({ se.name, se.symbol, se.color })
    end
    status_box:add(st)

    tabs:set_tab_content(3, Gui.scroll(status_box))

    -- Tab 4: Behavior
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
    behavior_box:add(Gui.label("CreatureBar v2.1.0 — Revenant port"))
    behavior_box:add(Gui.label("Original: creaturebar.lic v1.1 by Elanthia Online / Nisugi"))

    tabs:set_tab_content(4, Gui.scroll(behavior_box))

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
    respond(" Features:")
    respond("   - HP bar with damage-based estimation")
    respond("   - Wound indicators for 16 body parts")
    respond("   - Status effect badges (stunned, prone, etc.)")
    respond("   - Current target highlighting")
    respond("   - Click to target creature")
    respond("")
    respond(" Requires CombatTracker for HP/wound tracking.")
    respond(" CombatTracker is auto-enabled on startup.")
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

if not GameObj then
    echo("Error: GameObj module not available.")
    return
end

-- Auto-enable combat tracker for HP/wound tracking
if CombatTracker and CombatTracker.enable then
    if not CombatTracker.enabled_p() then
        CombatTracker.enable()
        respond("[CreatureBar] Combat tracker enabled for HP/wound tracking.")
    end
end

respond("Starting CreatureBar...")

window = Gui.window("CB", { width = 400, height = 250, resizable = true })

local initial = Gui.vbox()
initial:add(Gui.label("Waiting for creatures..."))
window:set_root(initial)
window:on_close(function() running = false end)
window:show()

if cmd == "config" or cmd == "setup" then
    open_settings()
end

before_dying(function()
    running = false
    if window then pcall(function() window:close() end) end
    if settings_win then pcall(function() settings_win:close() end) end
end)

local panel_data = {}
local force_rebuild = true

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

    local max = config.max_creatures or 5
    local targets = {}
    for i, t in ipairs(all_targets) do
        if i > max then break end
        if t.id and t.noun then
            targets[#targets + 1] = t
        end
    end

    -- Get current target ID from GameState (parsed from XML dropdown)
    local current_target_id = GameState.current_target_id
    -- Fallback to GameObj.target() if XML target not available
    if not current_target_id and GameObj.target then
        local ok, ct = pcall(GameObj.target)
        if ok and ct then current_target_id = ct.id end
    end

    local need_rebuild = force_rebuild or targets_changed(targets)

    if need_rebuild then
        force_rebuild = false
        displayed_ids = {}
        for _, t in ipairs(targets) do
            displayed_ids[#displayed_ids + 1] = t.id
        end

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
        -- Incremental updates
        for _, pd in ipairs(panel_data) do
            local npc = nil
            for _, t in ipairs(targets) do
                if t.id == pd.creature_id then npc = t; break end
            end
            if not npc then goto next_panel end

            -- Update target indicator
            local is_current = (tostring(npc.id) == tostring(current_target_id))
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

            -- Update HP from CombatCreature tracker
            if config.show_hp and pd.hp_bar and pd.hp_label then
                local cc = CombatCreature and CombatCreature[npc.id]
                if cc then
                    local pct = cc.hp_percent or 100
                    if pct ~= pd.last_hp_pct then
                        pd.last_hp_pct = pct
                        pd.hp_bar:set_value(pct / 100.0)
                        pd.hp_label:set_text(string.format("HP: %d/%d (%d%%)",
                            cc.current_hp or 0, cc.max_hp or 0, pct))
                    end
                end
            end

            -- Update wounds from CombatCreature tracker
            if config.show_wounds and pd.wound_label then
                local cc = CombatCreature and CombatCreature[npc.id]
                local wound_parts = {}
                if cc and cc.injuries then
                    for _, part in ipairs(BODY_PARTS) do
                        local level = cc.injuries[part]
                        if level and level > 0 then
                            local abbrev = BODY_PART_ABBREV[part] or part:sub(1, 2):upper()
                            wound_parts[#wound_parts + 1] = string.format("[%s:%d]", abbrev, level)
                        end
                    end
                end
                local wound_str = table.concat(wound_parts, " ")
                if wound_str ~= pd.last_wounds then
                    pd.last_wounds = wound_str
                    pd.wound_label:set_text(wound_str)
                end
            end

            -- Update status
            if pd.status_label then
                local statuses = get_creature_statuses(npc.id, npc.status)
                local status_str = table.concat(statuses, ",")
                if status_str ~= pd.last_status then
                    pd.last_status = status_str
                    pd.status_label:set_text(table.concat(statuses, ", "))
                end
            end

            ::next_panel::
        end
    end
end
