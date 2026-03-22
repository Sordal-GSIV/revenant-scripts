--- tpick Information Window GUI
-- Live info window showing box status, stats, messages, and Start/Stop controls.
-- Ported from tpick.lic lines 806-907, 913-956, 983-1200, 1627-1774, 4011-4028.
local M = {}
local data = require("tpick/data")
local stats_mod = require("tpick/stats")

---------------------------------------------------------------------------
-- Internal state
---------------------------------------------------------------------------

local win = nil
local labels = {}           -- widget references by name
local controls = {}         -- buttons, combos, checkboxes
local tables = {}           -- table widgets by tab name
local messages = {}         -- message history (newest first, max 100)
local messages_label = nil  -- label widget for Messages tab
local current_vars = nil    -- last vars snapshot for live updates
local current_stats = nil   -- stats_data reference
local current_settings = nil -- settings reference

-- Box info fields displayed on the Main tab
local BOX_INFO_LABELS = {
    "Box Name", "Box ID", "Lock Difficulty", "Trap Difficulty",
    "Current Trap", "Tip Amount", "Critter Name", "Critter Level",
    "Putty Remaining", "Cotton Remaining", "Vials Remaining",
    "Window Message",
}

-- Picking mode options
local PICKING_MODES = {
    "Pool Picking", "Ground Picking", "Ground Picking + Loot",
    "Solo Picking", "Other Picking", "Drop Off Boxes",
    "Pick Up Boxes", "Refill Locksmith's Container", "Repair Lockpicks",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Format a number with comma separators.
local function add_commas(n)
    local s = tostring(math.floor(n))
    local pos = #s % 3
    if pos == 0 then pos = 3 end
    local parts = { s:sub(1, pos) }
    for i = pos + 1, #s, 3 do
        parts[#parts + 1] = s:sub(i, i + 2)
    end
    return table.concat(parts, ",")
end

--- Format seconds as HH:MM:SS.
local function fmt_time(seconds)
    seconds = math.floor(seconds or 0)
    return string.format("%02d:%02d:%02d",
        math.floor(seconds / 3600),
        math.floor(seconds / 60) % 60,
        seconds % 60)
end

---------------------------------------------------------------------------
-- Tab builders
---------------------------------------------------------------------------

--- Build the Main tab with box info, controls, and Start/Stop.
local function build_main_tab(vars, settings)
    local vbox = Gui.vbox()

    -- Instructions
    vbox:add(Gui.label("Choose the picking mode and option below."))
    vbox:add(Gui.separator())

    -- Picking Mode combo
    local mode_row = Gui.hbox()
    mode_row:add(Gui.label("Mode: "))
    local mode_combo = Gui.editable_combo({
        text = settings["Picking Mode"] or settings["Default Mode"] or "Pool Picking",
        hint = "Picking mode",
        options = PICKING_MODES,
    })
    controls["Picking Mode"] = mode_combo
    mode_row:add(mode_combo)
    vbox:add(mode_row)

    -- Picking Options combo
    local opts_row = Gui.hbox()
    opts_row:add(Gui.label("Option: "))
    local opts_combo = Gui.editable_combo({
        text = "None",
        hint = "Picking option",
        options = { "None" },
    })
    controls["Picking Options"] = opts_combo
    opts_row:add(opts_combo)
    vbox:add(opts_row)

    -- Tip Amount + Tip Percent
    local tip_row = Gui.hbox()
    tip_row:add(Gui.label("Tip Amount: "))
    local tip_combo = Gui.editable_combo({
        text = tostring(settings["Tip Amount"] or 1),
        hint = "Tip silvers",
        options = {},
    })
    controls["Tip Amount"] = tip_combo
    tip_row:add(tip_combo)

    local tip_pct = Gui.checkbox("Tip Percent", settings["Tip Percent"] == "Yes")
    controls["Tip Percent"] = tip_pct
    tip_row:add(tip_pct)
    vbox:add(tip_row)

    vbox:add(Gui.separator())

    -- Start / Stop buttons
    local btn_row = Gui.hbox()
    local start_btn = Gui.button("Start")
    local stop_btn = Gui.button("Stop")

    start_btn:on_click(function()
        if _G then _G.tpick_commands_set = true end
    end)

    stop_btn:on_click(function()
        if _G then _G.tpick_stop_immediately = true end
        M.add_message("'Stop' clicked. Script will finish the current box and then stop.")
    end)

    controls["Start"] = start_btn
    controls["Stop"] = stop_btn
    btn_row:add(start_btn)
    btn_row:add(stop_btn)
    vbox:add(btn_row)

    vbox:add(Gui.separator())

    -- Box info labels
    vbox:add(Gui.section_header("Current Box"))
    for _, name in ipairs(BOX_INFO_LABELS) do
        local lbl
        if name == "Window Message" then
            lbl = Gui.label("")
        else
            lbl = Gui.label(name .. ": ")
        end
        labels[name] = lbl
        vbox:add(lbl)
    end

    -- Wire up mode change to update options
    mode_combo:on_change(function()
        M.change_menu_options()
    end)

    -- Initial options population
    M.change_menu_options()

    return vbox
end

--- Build a stat sub-tab as a 2-column table.
local function build_stat_table(stat_names, stats_info)
    local tbl = Gui.table({ "Stat", "Value" })
    for _, name in ipairs(stat_names) do
        local display_name = name:gsub("^Non%-Pool ", ""):gsub("^Pool ", ""):gsub("^Total ", "")
        local val = stats_info[name]
        local display_val = ""
        if name:find("Time Spent") then
            display_val = fmt_time(val or 0)
        elseif type(val) == "number" then
            display_val = add_commas(val)
        elseif type(val) == "string" then
            display_val = val
        end
        tbl:add_row({ display_name, display_val })
    end
    return tbl
end

--- Build the Stats tab with nested sub-tabs.
local function build_stats_tab(stats_data, settings)
    local stats_info = stats_mod.set_stat_info(stats_data)
    if settings then
        stats_info["Scarab Value"] = tonumber(settings["Scarab Value"]) or 5000
        -- Recompute with scarab value
        stats_info = stats_mod.set_stat_info(stats_data)
    end

    local sub_tabs = Gui.tab_bar({
        "Lockpicking", "Locksmith Pool", "Non-Pool", "Total",
    })

    -- Lockpicking sub-tab: overall picking stats
    local lp_names = { "Total Boxes Picked", "Total Time Spent Picking" }
    local lp_tbl = build_stat_table(lp_names, stats_info)
    tables["Lockpicking"] = lp_tbl
    sub_tabs:set_tab_content(1, Gui.scroll(lp_tbl))

    -- Locksmith Pool sub-tab
    local pool_names = {
        "Pool Boxes Picked", "Pool Time Spent Picking", "Pool Time Spent Waiting",
        "Pool Scarabs Received", "Pool Scarab Silvers", "Pool Tips Silvers",
        "Pool Total Silvers", "Pool Silvers/Hour",
    }
    local pool_tbl = build_stat_table(pool_names, stats_info)
    tables["Locksmith Pool"] = pool_tbl
    sub_tabs:set_tab_content(2, Gui.scroll(pool_tbl))

    -- Non-Pool sub-tab
    local np_names = { "Non-Pool Boxes Picked", "Non-Pool Time Spent Picking" }
    local np_tbl = build_stat_table(np_names, stats_info)
    tables["Non-Pool"] = np_tbl
    sub_tabs:set_tab_content(3, Gui.scroll(np_tbl))

    -- Total sub-tab
    local tot_names = { "Total Boxes Picked", "Total Time Spent Picking" }
    local tot_tbl = build_stat_table(tot_names, stats_info)
    tables["Total"] = tot_tbl
    sub_tabs:set_tab_content(4, Gui.scroll(tot_tbl))

    return sub_tabs
end

--- Build the Loot (Total) tab.
local function build_loot_total_tab(stats_data)
    local tbl = Gui.table({ "Item", "Count" })
    tables["Loot Total"] = tbl
    local loot = stats_data["Loot Total"] or {}

    -- Show Silver and Scarabs first, then the rest alphabetically
    local priority = { "Silver", "Scarabs" }
    local shown = {}
    for _, key in ipairs(priority) do
        if loot[key] then
            tbl:add_row({ key, add_commas(loot[key]) })
            shown[key] = true
        end
    end
    local sorted_keys = {}
    for k in pairs(loot) do
        if not shown[k] then
            sorted_keys[#sorted_keys + 1] = k
        end
    end
    table.sort(sorted_keys)
    for _, k in ipairs(sorted_keys) do
        tbl:add_row({ k, add_commas(loot[k]) })
    end

    return Gui.scroll(tbl)
end

--- Build the Loot (Session) tab.
local function build_loot_session_tab(stats_data)
    local tbl = Gui.table({ "Item", "Count" })
    tables["Loot Session"] = tbl
    local loot = stats_data["Loot Session"] or {}

    local priority = { "Silver", "Scarabs" }
    local shown = {}
    for _, key in ipairs(priority) do
        if loot[key] then
            tbl:add_row({ key, add_commas(loot[key]) })
            shown[key] = true
        end
    end
    local sorted_keys = {}
    for k in pairs(loot) do
        if not shown[k] then
            sorted_keys[#sorted_keys + 1] = k
        end
    end
    table.sort(sorted_keys)
    for _, k in ipairs(sorted_keys) do
        tbl:add_row({ k, add_commas(loot[k]) })
    end

    return Gui.scroll(tbl)
end

--- Build the Traps tab.
local function build_traps_tab(stats_data)
    local tbl = Gui.table({ "Trap Type", "Count" })
    tables["Traps"] = tbl

    local total = 0
    for _, trap in ipairs(data.TRAP_NAMES) do
        total = total + (stats_data[trap] or 0)
    end

    for _, trap in ipairs(data.TRAP_NAMES) do
        local count = stats_data[trap] or 0
        local pct = total > 0 and string.format(" (%.1f%%)", (count / total) * 100) or ""
        tbl:add_row({ trap, add_commas(count) .. pct })
    end

    return Gui.scroll(tbl)
end

--- Build the Lockpicks tab.
local function build_lockpicks_tab(stats_data)
    local tbl = Gui.table({ "Lockpick", "Picks Since Break" })
    tables["Lockpicks"] = tbl

    local per_pick = stats_data["Opened/Broke For Each Pick"] or {}
    -- Show current since-last-break counter
    tbl:add_row({
        "Since Last Break (any)",
        add_commas(stats_data["Locks Opened Since Last Pick Broke"] or 0),
    })
    tbl:add_row({ "", "" }) -- spacer

    -- Per-tier breakdown
    for _, name in ipairs(data.LOCKPICK_NAMES) do
        local count = per_pick[name]
        if count and count > 0 then
            tbl:add_row({ name, add_commas(count) })
        end
    end

    return Gui.scroll(tbl)
end

--- Build the Messages tab.
local function build_messages_tab()
    local lbl = Gui.label("")
    messages_label = lbl
    return Gui.scroll(lbl)
end

--- Build the Settings tab (window position/size/behavior).
local function build_settings_tab(settings)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Window Position & Size"))

    -- Numeric inputs for window geometry
    local geom_fields = { "Width", "Height", "Horizontal", "Vertical" }
    for _, name in ipairs(geom_fields) do
        local row = Gui.hbox()
        row:add(Gui.label(name .. ": "))
        local inp = Gui.editable_combo({
            text = tostring(settings[name] or 0),
            hint = name,
            options = {},
        })
        controls["Setting_" .. name] = inp
        row:add(inp)
        vbox:add(row)
    end

    -- Scarab Value
    local sv_row = Gui.hbox()
    sv_row:add(Gui.label("Scarab Value: "))
    local sv_inp = Gui.editable_combo({
        text = tostring(settings["Scarab Value"] or 5000),
        hint = "Scarab silver value",
        options = {},
    })
    controls["Setting_Scarab Value"] = sv_inp
    sv_row:add(sv_inp)
    vbox:add(sv_row)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Behavior"))

    -- Checkboxes
    local check_fields = {
        "Show Window", "Track Loot", "Close Window/Script",
        "Keep Window Open", "One & Done", "Show Tooltips",
    }
    for _, name in ipairs(check_fields) do
        local checked = (settings[name] == "Yes")
        local cb = Gui.checkbox(name, checked)
        controls["Setting_" .. name] = cb
        vbox:add(cb)
    end

    -- Default Mode
    vbox:add(Gui.separator())
    local dm_row = Gui.hbox()
    dm_row:add(Gui.label("Default Mode: "))
    local dm_inp = Gui.editable_combo({
        text = settings["Default Mode"] or "",
        hint = "Default picking mode",
        options = PICKING_MODES,
    })
    controls["Setting_Default Mode"] = dm_inp
    dm_row:add(dm_inp)
    vbox:add(dm_row)

    -- Save / Defaults / Reset Stats buttons
    vbox:add(Gui.separator())
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save")
    save_btn:on_click(function()
        M.collect_settings()
    end)
    btn_row:add(save_btn)

    local defaults_btn = Gui.button("Defaults")
    defaults_btn:on_click(function()
        -- Signal defaults load (handled by caller)
        if _G then _G.tpick_load_defaults = true end
    end)
    btn_row:add(defaults_btn)
    vbox:add(btn_row)

    -- Reset Stats row
    local reset_row = Gui.hbox()
    local reset_btn = Gui.button("Reset Stats")
    local reset_inp = Gui.editable_combo({
        text = "",
        hint = "Type 'reset' to confirm",
        options = {},
    })
    controls["Reset Stats Input"] = reset_inp
    reset_btn:on_click(function()
        local txt = reset_inp:get_text()
        if txt and txt:lower() == "reset" then
            if current_stats then
                stats_mod.reset(current_stats)
                M.refresh_stats()
                M.add_message("Stats have been reset.")
            end
            reset_inp:set_text("")
        end
    end)
    reset_row:add(reset_btn)
    reset_row:add(reset_inp)
    vbox:add(reset_row)

    return vbox
end

--- Build the Version History tab.
local function build_version_tab()
    local lbl = Gui.label(data.VERSION_HISTORY or "")
    return Gui.scroll(lbl)
end

---------------------------------------------------------------------------
-- Stats refresh
---------------------------------------------------------------------------

--- Refresh all stat tables with current data.
function M.refresh_stats()
    if not current_stats then return end
    if not win then return end

    local stats_info = stats_mod.set_stat_info(current_stats)

    -- Helper to repopulate a stat table
    local function refresh_table(tab_name, stat_names, is_time_key)
        local tbl = tables[tab_name]
        if not tbl then return end
        tbl:clear()
        for _, name in ipairs(stat_names) do
            local display_name = name:gsub("^Non%-Pool ", ""):gsub("^Pool ", ""):gsub("^Total ", "")
            local val = stats_info[name]
            local display_val = ""
            if name:find("Time Spent") then
                display_val = fmt_time(val or 0)
            elseif type(val) == "number" then
                display_val = add_commas(val)
            end
            tbl:add_row({ display_name, display_val })
        end
    end

    refresh_table("Lockpicking", { "Total Boxes Picked", "Total Time Spent Picking" })
    refresh_table("Locksmith Pool", {
        "Pool Boxes Picked", "Pool Time Spent Picking", "Pool Time Spent Waiting",
        "Pool Scarabs Received", "Pool Scarab Silvers", "Pool Tips Silvers",
        "Pool Total Silvers", "Pool Silvers/Hour",
    })
    refresh_table("Non-Pool", { "Non-Pool Boxes Picked", "Non-Pool Time Spent Picking" })
    refresh_table("Total", { "Total Boxes Picked", "Total Time Spent Picking" })

    -- Refresh loot tables
    local function refresh_loot(tab_name, loot_key)
        local tbl = tables[tab_name]
        if not tbl then return end
        tbl:clear()
        local loot = current_stats[loot_key] or {}
        local priority = { "Silver", "Scarabs" }
        local shown = {}
        for _, key in ipairs(priority) do
            if loot[key] then
                tbl:add_row({ key, add_commas(loot[key]) })
                shown[key] = true
            end
        end
        local sorted_keys = {}
        for k in pairs(loot) do
            if not shown[k] then sorted_keys[#sorted_keys + 1] = k end
        end
        table.sort(sorted_keys)
        for _, k in ipairs(sorted_keys) do
            tbl:add_row({ k, add_commas(loot[k]) })
        end
    end

    refresh_loot("Loot Total", "Loot Total")
    refresh_loot("Loot Session", "Loot Session")

    -- Refresh traps table
    local traps_tbl = tables["Traps"]
    if traps_tbl then
        traps_tbl:clear()
        local total = 0
        for _, trap in ipairs(data.TRAP_NAMES) do
            total = total + (current_stats[trap] or 0)
        end
        for _, trap in ipairs(data.TRAP_NAMES) do
            local count = current_stats[trap] or 0
            local pct = total > 0 and string.format(" (%.1f%%)", (count / total) * 100) or ""
            traps_tbl:add_row({ trap, add_commas(count) .. pct })
        end
    end

    -- Refresh lockpicks table
    local lp_tbl = tables["Lockpicks"]
    if lp_tbl then
        lp_tbl:clear()
        lp_tbl:add_row({
            "Since Last Break (any)",
            add_commas(current_stats["Locks Opened Since Last Pick Broke"] or 0),
        })
        lp_tbl:add_row({ "", "" })
        local per_pick = current_stats["Opened/Broke For Each Pick"] or {}
        for _, name in ipairs(data.LOCKPICK_NAMES) do
            local count = per_pick[name]
            if count and count > 0 then
                lp_tbl:add_row({ name, add_commas(count) })
            end
        end
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Create and show the information window.
-- @param vars          The tpick_vars working state table.
-- @param settings      The load_data settings table.
-- @param stats_data    The stats_data table.
function M.show(vars, settings, stats_data)
    if win then
        win:close()
        win = nil
    end

    current_vars = vars
    current_stats = stats_data
    current_settings = settings

    -- Reset internal state
    labels = {}
    controls = {}
    tables = {}
    messages = {}
    messages_label = nil

    local width = tonumber(settings["Width"]) or 500
    local height = tonumber(settings["Height"]) or 600
    local char_name = ""
    if GameState and GameState.name then
        char_name = " - " .. GameState.name
    end

    win = Gui.window("tpick" .. char_name, { width = width, height = height, resizable = true })

    -- Build all tabs
    local main_content     = build_main_tab(vars, settings)
    local stats_content    = build_stats_tab(stats_data, settings)
    local loot_tot_content = build_loot_total_tab(stats_data)
    local loot_ses_content = build_loot_session_tab(stats_data)
    local traps_content    = build_traps_tab(stats_data)
    local picks_content    = build_lockpicks_tab(stats_data)
    local msgs_content     = build_messages_tab()
    local settings_content = build_settings_tab(settings)
    local version_content  = build_version_tab()

    local tab_bar = Gui.tab_bar({
        "Main", "Stats", "Loot (Total)", "Loot (Session)",
        "Traps", "Lockpicks", "Messages", "Settings", "Version",
    })
    tab_bar:set_tab_content(1, Gui.scroll(main_content))
    tab_bar:set_tab_content(2, stats_content)
    tab_bar:set_tab_content(3, loot_tot_content)
    tab_bar:set_tab_content(4, loot_ses_content)
    tab_bar:set_tab_content(5, traps_content)
    tab_bar:set_tab_content(6, picks_content)
    tab_bar:set_tab_content(7, msgs_content)
    tab_bar:set_tab_content(8, Gui.scroll(settings_content))
    tab_bar:set_tab_content(9, version_content)

    local root = Gui.vbox()
    root:add(tab_bar)
    win:set_root(root)
    win:show()
end

--- Update the Main tab labels with current box state.
-- Called from 8+ locations throughout other modules whenever box state changes.
-- @param vars  The tpick_vars working state (or a table with box info fields).
function M.update_box_for_window(vars)
    if not win then return end

    local info = {}
    if vars["Current Box"] then
        info["Box Name"]    = vars["Current Box"].name or ""
        info["Box ID"]      = vars["Current Box"].id or ""
    else
        info["Box Name"]    = ""
        info["Box ID"]      = ""
    end
    info["Lock Difficulty"]   = vars["Lock Difficulty"] or ""
    info["Trap Difficulty"]   = vars["Trap Difficulty"] or ""
    info["Current Trap"]      = vars["Current Trap Type"] or ""
    info["Tip Amount"]        = vars["Offered Tip Amount"] or ""
    info["Critter Name"]      = vars["Critter Name"] or ""
    info["Critter Level"]     = vars["Critter Level"] or ""
    info["Putty Remaining"]   = vars["Putty Remaining"] or ""
    info["Cotton Remaining"]  = vars["Cotton Remaining"] or ""
    info["Vials Remaining"]   = vars["Vials Remaining"] or ""
    info["Window Message"]    = vars["Window Message"] or ""

    -- Also push Window Message into the messages list
    if info["Window Message"] ~= "" then
        -- Skip adding "Number of locks" messages to the display label
        local msg = info["Window Message"]
        if not msg:find("Number of locks successfully opened") then
            M.add_message(msg)
        end
    end

    -- Update all labels
    for _, name in ipairs(BOX_INFO_LABELS) do
        local lbl = labels[name]
        if lbl then
            if name == "Window Message" then
                lbl:set_text(info[name])
            else
                lbl:set_text(name .. ": " .. tostring(info[name]))
            end
        end
    end

    -- Keep vars reference current
    current_vars = vars
end

--- Add a message to the Messages tab (newest at top, max 100).
-- @param text  The message string to add.
function M.add_message(text)
    if not text or text == "" then return end

    -- Prepend timestamp
    local timestamp = os.date("%H:%M:%S")
    local entry = "[" .. timestamp .. "] " .. text

    table.insert(messages, 1, entry)
    if #messages > 100 then
        table.remove(messages, 101)
    end

    -- Update display
    if messages_label then
        messages_label:set_text(table.concat(messages, "\n\n"))
    end
end

--- Get the current picking mode and options from GUI controls.
-- Returns an array of command strings matching the original get_tpick_commands.
-- @return commands  Array of strings: {mode, [option], [tip_amount], ["Percent"]}
function M.get_tpick_commands()
    local commands = {}

    local mode_combo = controls["Picking Mode"]
    local opts_combo = controls["Picking Options"]

    if mode_combo then
        local mode_text = mode_combo:get_text()
        commands[#commands + 1] = mode_text

        if opts_combo then
            local opt_text = opts_combo:get_text()
            if opt_text and opt_text ~= "" and opt_text ~= "None" then
                commands[#commands + 1] = opt_text
            end
        end

        if mode_text == "Drop Off Boxes" then
            local tip_combo = controls["Tip Amount"]
            if tip_combo then
                local tip_val = tonumber(tip_combo:get_text()) or 1
                commands[#commands + 1] = tostring(math.floor(tip_val))
            end
            local tip_pct = controls["Tip Percent"]
            if tip_pct and tip_pct:get_checked() then
                commands[#commands + 1] = "Percent"
            end
        end
    end

    return commands
end

--- Update the Picking Options combo based on the currently selected mode.
-- Mirrors the original change_menu_options (lines 913-941).
function M.change_menu_options()
    local mode_combo = controls["Picking Mode"]
    local opts_combo = controls["Picking Options"]
    local tip_combo = controls["Tip Amount"]
    local tip_pct = controls["Tip Percent"]

    if not mode_combo or not opts_combo then return end

    local mode = mode_combo:get_text() or ""

    -- Enable/disable tip controls based on mode
    -- (Gui widgets may not support set_sensitive; we track state for get_tpick_commands)

    -- Build options list based on mode
    local no_options_modes = {
        ["Drop Off Boxes"] = true,
        ["Pick Up Boxes"] = true,
        ["Refill Locksmith's Container"] = true,
        ["Repair Lockpicks"] = true,
    }

    if no_options_modes[mode] then
        -- No picking options for these modes
        opts_combo:set_text("None")
        return
    end

    local options = { "None", "Always Use Vaalin", "Start With Copper" }

    -- Relock available for ground/solo modes
    if mode == "Ground Picking" or mode == "Ground Picking + Loot" or mode == "Solo Picking" then
        options[#options + 1] = "Relock Boxes"
    end

    -- Wedge available for rogues
    if Stats and Stats.prof and Stats.prof == "Rogue" then
        options[#options + 1] = "Always Use Wedge"
    end

    -- Pop available if 416 is known
    if Spell and Spell[416] and Spell[416].known then
        options[#options + 1] = "Pop Boxes"
    end

    -- Plinites not available for pool/ground modes
    if mode ~= "Pool Picking" and mode ~= "Ground Picking" and mode ~= "Ground Picking + Loot" then
        options[#options + 1] = "Plinites"
    end

    -- Disarm Only for ground modes
    if mode == "Ground Picking" or mode == "Ground Picking + Loot" then
        options[#options + 1] = "Disarm Only"
    end

    -- Bash for warriors in ground/solo
    if Stats and Stats.prof and Stats.prof == "Warrior" then
        if mode == "Solo Picking" or mode == "Ground Picking" or mode == "Ground Picking + Loot" then
            options[#options + 1] = "Bash Only"
        end
        if mode == "Ground Picking" or mode == "Ground Picking + Loot" then
            options[#options + 1] = "Bash + Disarm"
        end
    end

    -- Update the combo with new options
    -- The editable_combo doesn't have a remove_all/set_options, so we set text to None
    opts_combo:set_text("None")
end

--- Collect settings from the Settings tab widgets back into the settings table.
function M.collect_settings()
    if not current_settings then return end

    -- Geometry
    for _, name in ipairs({ "Width", "Height", "Horizontal", "Vertical" }) do
        local ctrl = controls["Setting_" .. name]
        if ctrl then
            current_settings[name] = tonumber(ctrl:get_text()) or current_settings[name]
        end
    end

    -- Scarab Value
    local sv_ctrl = controls["Setting_Scarab Value"]
    if sv_ctrl then
        current_settings["Scarab Value"] = tonumber(sv_ctrl:get_text()) or current_settings["Scarab Value"]
    end

    -- Checkboxes
    for _, name in ipairs({
        "Show Window", "Track Loot", "Close Window/Script",
        "Keep Window Open", "One & Done", "Show Tooltips",
    }) do
        local ctrl = controls["Setting_" .. name]
        if ctrl then
            current_settings[name] = ctrl:get_checked() and "Yes" or "No"
        end
    end

    -- Default Mode
    local dm_ctrl = controls["Setting_Default Mode"]
    if dm_ctrl then
        current_settings["Default Mode"] = dm_ctrl:get_text()
    end

    -- Signal save
    if _G then _G.tpick_save_settings = true end
end

--- Set the Start/Stop button enabled states.
-- Called when picking starts/stops to toggle UI controls.
-- @param running  Boolean; true = picking is running.
function M.set_running(running)
    if not win then return end
    -- The original disables Start and mode/options when running,
    -- enables Stop; and reverses when stopped.
    -- Store state for callers to query.
    controls._running = running
end

--- Check whether the Start button state indicates running.
-- @return boolean
function M.is_running()
    return controls._running or false
end

--- Close the information window.
function M.close()
    if win then
        -- Collect menu settings before closing
        if current_settings and controls["Picking Mode"] then
            current_settings["Picking Mode"] = controls["Picking Mode"]:get_text()
            local opts = controls["Picking Options"]
            if opts then
                current_settings["Picking Options"] = opts:get_text()
            end
        end
        win:close()
        win = nil
    end
end

--- Check if the information window is still open.
-- @return boolean
function M.is_open()
    return win ~= nil
end

--- Wait for the window to close (blocking).
function M.wait_for_close()
    if win then
        Gui.wait(win, "close")
    end
end

--- Get the current settings reference (for saving on close).
-- @return settings table or nil
function M.get_settings()
    return current_settings
end

--- Get the current stats reference.
-- @return stats_data table or nil
function M.get_stats()
    return current_stats
end

return M
