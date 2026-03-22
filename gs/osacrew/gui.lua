-- OSACrew GUI Setup Window
-- Original: OsaCrew GTK3 window (osacrew.lic lines 3042-3545)
-- Ported to Revenant Gui module

local M = {}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Read a boolean value from the osa table, falling back to a default.
local function get_bool(osa, key, default)
    local v = osa[key]
    if v == nil then return default or false end
    return not not v
end

-- Read a string value from the osa table, falling back to a default.
local function get_str(osa, key, default)
    local v = osa[key]
    if v == nil or v == "" then return default or "" end
    return tostring(v)
end

-- ---------------------------------------------------------------------------
-- Tab builders
-- ---------------------------------------------------------------------------

local function build_general_tab(osa)
    local vbox = Gui.vbox()

    -- Chain of Command section
    vbox:add(Gui.section_header("Chain Of Command Settings:"))

    local commander_input = Gui.input({
        text = get_str(osa, "$osa_commander", GameState.name),
        placeholder = "Commander name",
    })
    local commander_row = Gui.hbox()
    commander_row:add(Gui.label("Ship's Commander:"))
    commander_row:add(commander_input)
    vbox:add(commander_row)

    local crew_input = Gui.input({
        text = get_str(osa, "$osa_crew", GameState.name),
        placeholder = "Crew channel name",
    })
    local crew_row = Gui.hbox()
    crew_row:add(Gui.label("Ship's Crew Channel:"))
    crew_row:add(crew_input)
    vbox:add(crew_row)

    local medic_input = Gui.input({
        text = get_str(osa, "$osa_medicalofficer", ""),
        placeholder = "Medical officer name",
    })
    local medic_row = Gui.hbox()
    medic_row:add(Gui.label("Ship's Medical Officer:"))
    medic_row:add(medic_input)
    vbox:add(medic_row)

    -- General settings section
    vbox:add(Gui.section_header("General Settings:"))

    local mana_input = Gui.input({
        text = get_str(osa, "$osa_checkformana", "80"),
        placeholder = "80",
    })
    local mana_row = Gui.hbox()
    mana_row:add(Gui.label("Underway Mana Threshold:"))
    mana_row:add(mana_input)
    vbox:add(mana_row)

    -- Checkboxes: 2-column rows
    -- Row 1
    local row1 = Gui.hbox()
    local cb_crewtasks  = Gui.checkbox("Perform Crew Tasks",  get_bool(osa, "$osa_osacrewtasks",  false))
    local cb_windsails  = Gui.checkbox("Wind The Sails",      get_bool(osa, "$osa_windedsails",   false))
    row1:add(cb_crewtasks)
    row1:add(cb_windsails)
    vbox:add(row1)

    -- Row 2
    local row2 = Gui.hbox()
    local cb_manaspell  = Gui.checkbox("Use Mana Spellup",    get_bool(osa, "$osa_mana_spellup",  false))
    local cb_groupspell = Gui.checkbox("Spellup Crew",        get_bool(osa, "$osa_groupspellup",  false))
    row2:add(cb_manaspell)
    row2:add(cb_groupspell)
    vbox:add(row2)

    -- Row 3
    local row3 = Gui.hbox()
    local cb_selfspell  = Gui.checkbox("Spellup Self",        get_bool(osa, "$osa_selfspellup",   false))
    local cb_uselte     = Gui.checkbox("Use LTE Boost",       get_bool(osa, "$osa_uselte",        false))
    row3:add(cb_selfspell)
    row3:add(cb_uselte)
    vbox:add(row3)

    -- Row 4
    local row4 = Gui.hbox()
    local cb_lootsell   = Gui.checkbox("Sell Loot",           get_bool(osa, "$osa_lootsell",      false))
    row4:add(cb_lootsell)
    vbox:add(row4)

    -- Return widget tree + a collector function used by the save handler
    local function collect(osa_out)
        osa_out["$osa_commander"]     = commander_input:get_text()
        osa_out["$osa_crew"]          = crew_input:get_text()
        osa_out["$osa_medicalofficer"]= medic_input:get_text()
        osa_out["$osa_checkformana"]  = mana_input:get_text()
        osa_out["$osa_osacrewtasks"]  = cb_crewtasks:get_checked()
        osa_out["$osa_windedsails"]   = cb_windsails:get_checked()
        osa_out["$osa_mana_spellup"]  = cb_manaspell:get_checked()
        osa_out["$osa_groupspellup"]  = cb_groupspell:get_checked()
        osa_out["$osa_selfspellup"]   = cb_selfspell:get_checked()
        osa_out["$osa_uselte"]        = cb_uselte:get_checked()
        osa_out["$osa_lootsell"]      = cb_lootsell:get_checked()
    end

    return Gui.scroll(vbox), collect
end

local function build_support_tab(osa)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Armor Specializations"))

    -- Column header row
    local hdr_row = Gui.hbox()
    hdr_row:add(Gui.label("Known"))
    hdr_row:add(Gui.label("Use"))
    hdr_row:add(Gui.label("Request"))
    vbox:add(hdr_row)

    -- One row per specialization: label + have/use/need checkboxes
    local specs = {
        { name = "Blessing",      have = "$osa_have_armor_blessing",      use = "$osa_use_armor_blessing",      need = "$osa_need_armor_blessing"      },
        { name = "Reinforcement", have = "$osa_have_armor_reinforcement",  use = "$osa_use_armor_reinforcement",  need = "$osa_need_armor_reinforcement"  },
        { name = "Support",       have = "$osa_have_armor_support",        use = "$osa_use_armor_support",        need = "$osa_need_armor_support"        },
        { name = "Casting",       have = "$osa_have_armor_casting",        use = "$osa_use_armor_casting",        need = "$osa_need_armor_casting"        },
        { name = "Evasion",       have = "$osa_have_armor_evasion",        use = "$osa_use_armor_evasion",        need = "$osa_need_armor_evasion"        },
        { name = "Fluidity",      have = "$osa_have_armor_fluidity",       use = "$osa_use_armor_fluidity",       need = "$osa_need_armor_fluidity"       },
        { name = "Stealth",       have = "$osa_have_armor_stealth",        use = "$osa_use_armor_stealth",        need = "$osa_need_armor_stealth"        },
    }

    local spec_widgets = {}   -- { have=cb, use=cb, need=cb, have_key, use_key, need_key }

    for _, spec in ipairs(specs) do
        local row = Gui.hbox()
        row:add(Gui.label("Armor " .. spec.name .. ":"))
        local cb_have = Gui.checkbox("", get_bool(osa, spec.have, false))
        local cb_use  = Gui.checkbox("", get_bool(osa, spec.use,  false))
        local cb_need = Gui.checkbox("", get_bool(osa, spec.need, false))
        row:add(cb_have)
        row:add(cb_use)
        row:add(cb_need)
        vbox:add(row)
        table.insert(spec_widgets, {
            have = cb_have, use = cb_use, need = cb_need,
            have_key = spec.have, use_key = spec.use, need_key = spec.need,
        })
    end

    -- "Use Armor Specializations On Crew" global checkbox
    local cb_armor_specs = Gui.checkbox(
        "Use Armor Specializations On Crew",
        get_bool(osa, "$osa_armor_specs", false)
    )
    vbox:add(cb_armor_specs)

    local function collect(osa_out)
        for _, sw in ipairs(spec_widgets) do
            osa_out[sw.have_key] = sw.have:get_checked()
            osa_out[sw.use_key]  = sw.use:get_checked()
            osa_out[sw.need_key] = sw.need:get_checked()
        end
        osa_out["$osa_armor_specs"] = cb_armor_specs:get_checked()
    end

    return Gui.scroll(vbox), collect
end

local function build_cannons_tab(osa)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Cannon Settings"))

    -- "Use Cannons" master toggle
    local cb_cannoneer = Gui.checkbox("Use Cannons", get_bool(osa, "$osa_cannoneer", false))
    vbox:add(cb_cannoneer)

    -- Duty / position rows (2 columns each)
    local row1 = Gui.hbox()
    local cb_loadonly      = Gui.checkbox("Load Only",        get_bool(osa, "$osa_loadonly",       false))
    local cb_maincannons   = Gui.checkbox("Main Cannons",     get_bool(osa, "$osa_maincannons",    false))
    row1:add(cb_loadonly)
    row1:add(cb_maincannons)
    vbox:add(row1)

    local row2 = Gui.hbox()
    local cb_fireonly      = Gui.checkbox("Fire Only",        get_bool(osa, "$osa_fireonly",       false))
    local cb_midcannons    = Gui.checkbox("Mid Cannons",      get_bool(osa, "$osa_midcannons",     false))
    row2:add(cb_fireonly)
    row2:add(cb_midcannons)
    vbox:add(row2)

    local row3 = Gui.hbox()
    local cb_loadandfire   = Gui.checkbox("Load And Fire",    get_bool(osa, "$osa_loadandfire",    false))
    local cb_forwardcannons= Gui.checkbox("Forward Cannons",  get_bool(osa, "$osa_forwardcannons", false))
    row3:add(cb_loadandfire)
    row3:add(cb_forwardcannons)
    vbox:add(row3)

    local function collect(osa_out)
        osa_out["$osa_cannoneer"]       = cb_cannoneer:get_checked()
        osa_out["$osa_loadonly"]        = cb_loadonly:get_checked()
        osa_out["$osa_maincannons"]     = cb_maincannons:get_checked()
        osa_out["$osa_fireonly"]        = cb_fireonly:get_checked()
        osa_out["$osa_midcannons"]      = cb_midcannons:get_checked()
        osa_out["$osa_loadandfire"]     = cb_loadandfire:get_checked()
        osa_out["$osa_forwardcannons"]  = cb_forwardcannons:get_checked()
    end

    return Gui.scroll(vbox), collect
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open the OSACrew setup window.
-- @param osa      table — current osa settings; populated into widgets as initial values.
-- @param save_fn  function(osa) — called with the updated osa table when Save is clicked.
function M.open(osa, save_fn)
    local win = Gui.window("OSACrew Setup", { width = 800, height = 600 })

    -- Tab bar: General / Support / Cannons
    local tabs = Gui.tab_bar({ "General", "Support", "Cannons" })

    local general_widget,  collect_general  = build_general_tab(osa)
    local support_widget,  collect_support  = build_support_tab(osa)
    local cannons_widget,  collect_cannons  = build_cannons_tab(osa)

    tabs:set_tab_content(1, general_widget)
    tabs:set_tab_content(2, support_widget)
    tabs:set_tab_content(3, cannons_widget)

    -- Save button
    local save_btn = Gui.button("Save")
    save_btn:on_click(function()
        collect_general(osa)
        collect_support(osa)
        collect_cannons(osa)
        save_fn(osa)
        win:close()
    end)

    -- Root layout
    local root = Gui.vbox()
    root:add(tabs)
    root:add(save_btn)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

return M
