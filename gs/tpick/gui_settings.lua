--- tpick settings GUI
-- Tabbed settings window exposing all 60+ tpick settings.
-- Uses the Revenant Gui widget system.
local M = {}
local settings_mod = require("tpick/settings")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Boolean settings use "Yes"/"No" strings.
local function bool_val(st, key)
    local v = st[key]
    if v == "Yes" or v == true then return true end
    return false
end

local function to_yesno(b)
    return b and "Yes" or "No"
end

--- Populate all widgets from a settings table.
local function populate_all(widgets, st)
    for key, w in pairs(widgets) do
        local val = st[key]
        if w.kind == "checkbox" then
            w.widget:set_checked(bool_val(st, key))
        elseif w.kind == "input" or w.kind == "combo" then
            w.widget:set_text(tostring(val or ""))
        end
    end
end

--- Collect all widget values into a settings table.
local function collect_all(widgets, st)
    for key, w in pairs(widgets) do
        if w.kind == "checkbox" then
            st[key] = to_yesno(w.widget:get_checked())
        elseif w.kind == "input" then
            local txt = w.widget:get_text()
            -- If the default is numeric, coerce
            if type(settings_mod.DEFAULTS[key]) == "number" then
                st[key] = tonumber(txt) or 0
            else
                st[key] = txt
            end
        elseif w.kind == "combo" then
            st[key] = w.widget:get_text()
        end
    end
    return st
end

--- Register a checkbox widget.
local function reg_cb(widgets, key, widget)
    widgets[key] = { kind = "checkbox", widget = widget }
end

--- Register an input widget.
local function reg_inp(widgets, key, widget)
    widgets[key] = { kind = "input", widget = widget }
end

--- Register a combo widget.
local function reg_combo(widgets, key, widget)
    widgets[key] = { kind = "combo", widget = widget }
end

--- Make a labelled input row.
local function input_row(label_text, value, placeholder)
    local row = Gui.hbox()
    row:add(Gui.label(label_text .. ": "))
    local inp = Gui.input({ text = tostring(value or ""), placeholder = placeholder or "" })
    row:add(inp)
    return row, inp
end

--- Make a labelled checkbox.
local function make_checkbox(label_text, checked)
    local cb = Gui.checkbox(label_text, checked)
    return cb
end

--- Gather worn container names for dropdown options.
local function container_options()
    local opts = {}
    if GameObj and GameObj.inv then
        local inv = GameObj.inv()
        if inv then
            for _, item in ipairs(inv) do
                local noun = item.noun or ""
                local name = item.name or noun
                if name ~= "" then
                    opts[#opts + 1] = name
                end
            end
        end
    end
    if #opts == 0 then
        opts = { "(no containers found)" }
    end
    return opts
end

---------------------------------------------------------------------------
-- Tab builders
---------------------------------------------------------------------------

local function build_main_tab(st, widgets)
    local vbox = Gui.vbox()

    -- Profile selector
    vbox:add(Gui.section_header("Profile"))
    local profile_row = Gui.hbox()
    local profiles = settings_mod.load_all_profiles()
    local profile_names = {}
    for name in pairs(profiles) do
        profile_names[#profile_names + 1] = name
    end
    table.sort(profile_names)
    local current_name = GameState and GameState.name or ""
    local profile_combo = Gui.editable_combo({
        text = current_name,
        hint = "Select character profile",
        options = profile_names,
    })
    profile_row:add(Gui.label("Profile: "))
    profile_row:add(profile_combo)
    vbox:add(profile_row)

    -- Load / Save / Defaults buttons
    local btn_row = Gui.hbox()
    local load_btn = Gui.button("Load")
    local save_btn = Gui.button("Save")
    local defaults_btn = Gui.button("Defaults")

    load_btn:on_click(function()
        local sel = profile_combo:get_text()
        local loaded = settings_mod.load_profile(sel, profiles)
        if loaded then
            for k, v in pairs(loaded) do st[k] = v end
            populate_all(widgets, st)
        end
    end)

    save_btn:on_click(function()
        collect_all(widgets, st)
        settings_mod.save(st)
    end)

    defaults_btn:on_click(function()
        local defs = settings_mod.load_defaults()
        for k, v in pairs(defs) do st[k] = v end
        populate_all(widgets, st)
    end)

    btn_row:add(load_btn)
    btn_row:add(save_btn)
    btn_row:add(defaults_btn)
    vbox:add(btn_row)

    -- Reset Stats
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Reset Stats"))
    local reset_row = Gui.hbox()
    local reset_inp = Gui.input({ placeholder = "Type 'reset' to confirm" })
    local reset_btn = Gui.button("Reset Stats")
    reset_btn:on_click(function()
        if reset_inp:get_text():lower() == "reset" then
            settings_mod.save_stats({})
            reset_inp:set_text("")
        end
    end)
    reset_row:add(reset_inp)
    reset_row:add(reset_btn)
    vbox:add(reset_row)

    -- Required settings status
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Required Settings Status"))
    local change_me = "REQUIRED CHANGE ME"
    for _, key in ipairs(settings_mod.REQUIRED_SETTINGS) do
        local val = st[key] or ""
        local status = (val == "" or val == change_me) and "[MISSING]" or "[OK]"
        vbox:add(Gui.label("  " .. status .. "  " .. key))
    end

    return vbox
end

local function build_lockpicks_tab(st, widgets)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Lockpick Names"))
    vbox:add(Gui.label("Enter the FULL name of each lockpick (without 'a'/'an')."))
    vbox:add(Gui.label("Separate multiple lockpicks with commas. Vaalin is required."))
    vbox:add(Gui.separator())

    for _, name in ipairs(settings_mod.LOCKPICK_NAMES) do
        local row, inp = input_row(name, st[name] or "", "lockpick name")
        reg_inp(widgets, name, inp)
        vbox:add(row)
    end

    vbox:add(Gui.separator())
    local scan_btn = Gui.button("Scan Lockpicks")
    scan_btn:on_click(function()
        -- Trigger lockpick scan via game command
        if Game and Game.puts then
            Game.puts("lmaster scan")
        end
    end)
    vbox:add(scan_btn)

    return vbox
end

local function build_repairs_tab(st, widgets)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Repair Material Lockpick Names"))
    vbox:add(Gui.label("Enter lockpick names grouped by repair material."))
    vbox:add(Gui.label("Same format as Lockpicks tab."))
    vbox:add(Gui.separator())

    for _, name in ipairs(settings_mod.REPAIR_NAMES) do
        local row, inp = input_row(name, st[name] or "", "lockpick name")
        reg_inp(widgets, name, inp)
        vbox:add(row)
    end

    vbox:add(Gui.separator())
    local copy_btn = Gui.button("Copy from Lockpicks")
    copy_btn:on_click(function()
        -- Map repair materials to lockpick tiers by material
        local material_map = {
            ["Repair Copper"]  = "Copper",
            ["Repair Brass"]   = "Steel",   -- brass repairs use steel tier
            ["Repair Steel"]   = "Steel",
            ["Repair Gold"]    = "Gold",
            ["Repair Silver"]  = "Silver",
            ["Repair Mithril"] = "Mithril",
            ["Repair Ora"]     = "Ora",
            ["Repair Laje"]    = "Laje",
            ["Repair Vultite"] = "Vultite",
            ["Repair Rolaren"] = "Rolaren",
            ["Repair Veniom"]  = "Veniom",
            ["Repair Invar"]   = "Invar",
            ["Repair Alum"]    = "Alum",
            ["Repair Golvern"] = "Golvern",
            ["Repair Kelyn"]   = "Kelyn",
            ["Repair Vaalin"]  = "Vaalin",
        }
        for repair_key, pick_key in pairs(material_map) do
            if widgets[pick_key] and widgets[repair_key] then
                local val = widgets[pick_key].widget:get_text()
                widgets[repair_key].widget:set_text(val)
                st[repair_key] = val
            end
        end
    end)
    vbox:add(copy_btn)

    return vbox
end

local function build_containers_tab(st, widgets)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Container Assignments"))
    vbox:add(Gui.label("Select containers for each category. Wear containers to see them listed."))
    vbox:add(Gui.separator())

    local opts = container_options()

    local container_keys = {
        "Lockpick Container", "Broken Lockpick Container",
        "Wedge Container", "Calipers Container",
        "Scale Weapon Container", "Locksmith's Container",
    }
    for _, key in ipairs(container_keys) do
        local row = Gui.hbox()
        row:add(Gui.label(key .. ": "))
        local combo = Gui.editable_combo({
            text = st[key] or "",
            hint = "Select container",
            options = opts,
        })
        reg_combo(widgets, key, combo)
        row:add(combo)
        vbox:add(row)
    end

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Container Open/Close"))
    local oc_pairs = {
        { "Lockpick Open", "Lockpick Close" },
        { "Broken Open", "Broken Close" },
        { "Wedge Open", "Wedge Close" },
        { "Calipers Open", "Calipers Close" },
        { "Weapon Open", "Weapon Close" },
    }
    for _, pair in ipairs(oc_pairs) do
        local row = Gui.hbox()
        local open_cb = make_checkbox(pair[1], bool_val(st, pair[1]))
        local close_cb = make_checkbox(pair[2], bool_val(st, pair[2]))
        reg_cb(widgets, pair[1], open_cb)
        reg_cb(widgets, pair[2], close_cb)
        row:add(open_cb)
        row:add(close_cb)
        vbox:add(row)
    end

    vbox:add(Gui.separator())
    local row, inp = input_row("Other Containers", st["Other Containers"] or "",
        "gem: sack, diamond: cloak")
    reg_inp(widgets, "Other Containers", inp)
    vbox:add(row)

    return vbox
end

local function build_spells_tab(st, widgets)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Buff Spells"))
    vbox:add(Gui.label("Check spells to keep active while picking."))
    vbox:add(Gui.separator())

    -- Simple on/off spell checkboxes
    local spell_checks = {
        "Light (205)", "Presence (402)", "Celerity (506)",
        "Rapid Fire (515)", "Self Control (613)",
        "Song of Luck (1006)", "Song of Tonis (1035)",
    }
    for _, key in ipairs(spell_checks) do
        local cb = make_checkbox(key, bool_val(st, key))
        reg_cb(widgets, key, cb)
        vbox:add(cb)
    end

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Enhancement Spells"))

    -- 403 / 404 text inputs
    local row403, inp403 = input_row("Lock Pick Enhancement (403)",
        st["Lock Pick Enhancement (403)"] or "", "never/yes/no/cancel/auto/<number>")
    reg_inp(widgets, "Lock Pick Enhancement (403)", inp403)
    vbox:add(row403)

    local row404, inp404 = input_row("Disarm Enhancement (404)",
        st["Disarm Enhancement (404)"] or "", "never/yes/no/cancel/auto/<number>")
    reg_inp(widgets, "Disarm Enhancement (404)", inp404)
    vbox:add(row404)

    -- Unlock (407) dropdown
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Unlock / Disarm"))
    local row407 = Gui.hbox()
    row407:add(Gui.label("Unlock (407): "))
    local combo407 = Gui.editable_combo({
        text = st["Unlock (407)"] or "Never",
        hint = "Mode",
        options = { "Never", "Plate", "Vial", "All" },
    })
    reg_combo(widgets, "Unlock (407)", combo407)
    row407:add(combo407)
    vbox:add(row407)

    -- Disarm (408) checkbox
    local disarm_cb = make_checkbox("Disarm (408)", bool_val(st, "Disarm (408)"))
    reg_cb(widgets, "Disarm (408)", disarm_cb)
    vbox:add(disarm_cb)

    -- Phase (704) checkbox
    local phase_cb = make_checkbox("Phase (704)", bool_val(st, "Phase (704)"))
    reg_cb(widgets, "Phase (704)", phase_cb)
    vbox:add(phase_cb)

    -- Use Lmaster Focus
    local lmaster_cb = make_checkbox("Use Lmaster Focus", bool_val(st, "Use Lmaster Focus"))
    reg_cb(widgets, "Use Lmaster Focus", lmaster_cb)
    vbox:add(lmaster_cb)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Mana"))

    -- Numeric spell settings
    local spell_nums = {
        { "Unlock (407) Mana", "Mana % before giving up" },
        { "Percent Mana To Keep", "-1 = always cast" },
        { "Number Of 416 Casts", "Times to check with 416" },
    }
    for _, entry in ipairs(spell_nums) do
        local row, inp = input_row(entry[1], st[entry[1]] or 0, entry[2])
        reg_inp(widgets, entry[1], inp)
        vbox:add(row)
    end

    -- Use 403/404 on level
    vbox:add(Gui.separator())
    local row403lvl, inp403lvl = input_row("Use 403 On Level",
        st["Use 403 On Level"] or 200, "critter level")
    reg_inp(widgets, "Use 403 On Level", inp403lvl)
    vbox:add(row403lvl)

    local row404lvl, inp404lvl = input_row("Use 404 On Level",
        st["Use 404 On Level"] or 200, "critter level")
    reg_inp(widgets, "Use 404 On Level", inp404lvl)
    vbox:add(row404lvl)

    return vbox
end

local function build_other_tab(st, widgets)
    local vbox = Gui.vbox()

    -- Picking numerics
    vbox:add(Gui.section_header("Picking"))
    local picking_nums = {
        { "Max Lock", "Highest lock to attempt" },
        { "Max Lock Roll", "Min roll before upgrading pick" },
        { "Trap Roll", "Trap difficulty threshold" },
        { "Lock Roll", "Roll threshold for current pick" },
        { "Vaalin Lock Roll", "Roll threshold for vaalin" },
        { "Lock Buffer", "Extra buffer on caliper readings" },
        { "Trap Check Count", "Manual trap checks" },
        { "Calibrate Count", "Boxes between calibrations" },
    }
    for _, entry in ipairs(picking_nums) do
        local row, inp = input_row(entry[1], st[entry[1]] or 0, entry[2])
        reg_inp(widgets, entry[1], inp)
        vbox:add(row)
    end

    -- Picking behaviors
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Behaviors"))
    local behavior_checks = {
        "Trash Boxes", "Keep Trying", "Open Boxes",
        "Auto Bundle Vials", "Auto Repair Bent Lockpicks",
        "Calibrate On Startup", "Calibrate Auto",
        "Use Vaalin When Fried", "Only Disarm Safe", "Pick Enruned",
        "Use Calipers", "Use Loresinging",
    }
    for _, key in ipairs(behavior_checks) do
        local cb = make_checkbox(key, bool_val(st, key))
        reg_cb(widgets, key, cb)
        vbox:add(cb)
    end

    -- Display
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Display"))
    local display_checks = {
        "Run Silently", "Use Monster Bold",
        "Don't Show Messages", "Don't Show Commands",
    }
    for _, key in ipairs(display_checks) do
        local cb = make_checkbox(key, bool_val(st, key))
        reg_cb(widgets, key, cb)
        vbox:add(cb)
    end

    -- Experience dropdowns
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Experience"))
    local pct_options = { "Never", "clear as a bell", "fresh and clear",
        "clear", "muddled", "becoming numbed", "numbed",
        "must rest", "saturated", "Always" }

    local rest_row = Gui.hbox()
    rest_row:add(Gui.label("Rest At Percent: "))
    local rest_combo = Gui.editable_combo({
        text = st["Rest At Percent"] or "Never",
        hint = "Mind state",
        options = pct_options,
    })
    reg_combo(widgets, "Rest At Percent", rest_combo)
    rest_row:add(rest_combo)
    vbox:add(rest_row)

    local pick_row = Gui.hbox()
    pick_row:add(Gui.label("Pick At Percent: "))
    local pick_combo = Gui.editable_combo({
        text = st["Pick At Percent"] or "Always",
        hint = "Mind state",
        options = pct_options,
    })
    reg_combo(widgets, "Pick At Percent", pick_combo)
    pick_row:add(pick_combo)
    vbox:add(pick_row)

    -- Pool settings
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Pool"))
    local pool_nums = {
        { "Max Level", "Max critter level" },
        { "Minimum Tip Start", "Starting tip amount" },
        { "Minimum Tip Interval", "Tip decrement amount" },
        { "Minimum Tip Floor", "Minimum tip floor" },
        { "Time To Wait", "Seconds to wait" },
    }
    for _, entry in ipairs(pool_nums) do
        local row, inp = input_row(entry[1], st[entry[1]] or 0, entry[2])
        reg_inp(widgets, entry[1], inp)
        vbox:add(row)
    end

    local sw_cb = make_checkbox("Standard Wait", bool_val(st, "Standard Wait"))
    reg_cb(widgets, "Standard Wait", sw_cb)
    vbox:add(sw_cb)

    -- Equipment
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Equipment"))
    local equip_inputs = {
        { "Scale Trap Weapon", "weapon name" },
        { "Remove Armor", "armor name" },
        { "Bashing Weapon", "weapon name" },
        { "Gnomish Bracer", "bracer name" },
        { "Fossil Charm", "adjective noun" },
        { "Auto Deposit Silvers", "yes or script name" },
    }
    for _, entry in ipairs(equip_inputs) do
        local row, inp = input_row(entry[1], st[entry[1]] or "", entry[2])
        reg_inp(widgets, entry[1], inp)
        vbox:add(row)
    end

    local bracer2_cb = make_checkbox("Bracer Tier 2", bool_val(st, "Bracer Tier 2"))
    reg_cb(widgets, "Bracer Tier 2", bracer2_cb)
    vbox:add(bracer2_cb)

    local bracer_ov_cb = make_checkbox("Bracer Override", bool_val(st, "Bracer Override"))
    reg_cb(widgets, "Bracer Override", bracer_ov_cb)
    vbox:add(bracer_ov_cb)

    -- Messaging
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Messaging"))
    local msg_inputs = {
        { "Ready", "What to say when ready" },
        { "Can't Open Box", "What to say when can't open" },
        { "Scarab Found", "What to say for scarab" },
        { "Scarab Safe", "What to say when scarab safe" },
    }
    for _, entry in ipairs(msg_inputs) do
        local row, inp = input_row(entry[1], st[entry[1]] or "", entry[2])
        reg_inp(widgets, entry[1], inp)
        vbox:add(row)
    end

    -- Trick dropdown
    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Other"))
    local trick_row = Gui.hbox()
    trick_row:add(Gui.label("Trick: "))
    local trick_combo = Gui.editable_combo({
        text = st["Trick"] or "pick",
        hint = "Lock mastery trick",
        options = { "pick", "spin", "twist", "turn", "twirl", "toss", "bend", "flip", "random" },
    })
    reg_combo(widgets, "Trick", trick_combo)
    trick_row:add(trick_combo)
    vbox:add(trick_row)

    local rest_fried_row, rest_fried_inp = input_row("Rest When Fried",
        st["Rest When Fried"] or "", "room# or room#:command")
    reg_inp(widgets, "Rest When Fried", rest_fried_inp)
    vbox:add(rest_fried_row)

    local pol_row, pol_inp = input_row("Picks On Level",
        st["Picks On Level"] or "", "10 copper, 20 steel, ...")
    reg_inp(widgets, "Picks On Level", pol_inp)
    vbox:add(pol_row)

    local rog_row, rog_inp = input_row(";rogues Lockpick",
        st[";rogues Lockpick"] or "", "lockpick quality")
    reg_inp(widgets, ";rogues Lockpick", rog_inp)
    vbox:add(rog_row)

    local dm_row, dm_inp = input_row("Default Mode",
        st["Default Mode"] or "", "pool v, ground loot, etc.")
    reg_inp(widgets, "Default Mode", dm_inp)
    vbox:add(dm_row)

    return vbox
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function M.show(current_settings, on_save_callback)
    local st = {}
    -- Deep copy current settings
    for k, v in pairs(current_settings) do st[k] = v end

    local widgets = {} -- key -> { kind, widget }

    local win = Gui.window("tpick Settings", { width = 650, height = 600, resizable = true })

    -- Build tab contents
    local main_content    = build_main_tab(st, widgets)
    local picks_content   = build_lockpicks_tab(st, widgets)
    local repair_content  = build_repairs_tab(st, widgets)
    local contain_content = build_containers_tab(st, widgets)
    local spells_content  = build_spells_tab(st, widgets)
    local other_content   = build_other_tab(st, widgets)

    -- Tab bar
    local tabs = Gui.tab_bar({
        "Main", "Lockpicks", "Repairs", "Containers", "Spells", "Other",
    })
    tabs:set_tab_content(1, Gui.scroll(main_content))
    tabs:set_tab_content(2, Gui.scroll(picks_content))
    tabs:set_tab_content(3, Gui.scroll(repair_content))
    tabs:set_tab_content(4, Gui.scroll(contain_content))
    tabs:set_tab_content(5, Gui.scroll(spells_content))
    tabs:set_tab_content(6, Gui.scroll(other_content))

    -- Root layout: tabs + bottom button bar
    local root = Gui.vbox()
    root:add(tabs)

    -- Bottom save/cancel bar
    root:add(Gui.separator())
    local bottom = Gui.hbox()
    local save_close = Gui.button("Save & Close")
    save_close:on_click(function()
        collect_all(widgets, st)
        settings_mod.save(st)
        if on_save_callback then
            on_save_callback(st)
        end
        win:close()
    end)
    bottom:add(save_close)

    local cancel = Gui.button("Cancel")
    cancel:on_click(function()
        win:close()
    end)
    bottom:add(cancel)
    root:add(bottom)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
    return st
end

return M
