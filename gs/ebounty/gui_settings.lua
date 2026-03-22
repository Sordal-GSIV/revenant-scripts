local settings_mod = require("settings")
local data = require("data")

local M = {}

local function make_checkbox_list(parent, label_text, options, current_list, on_toggle)
    parent:add(Gui.section_header(label_text))
    for _, opt in ipairs(options) do
        local key, lbl = opt[1], opt[2]
        local cb = Gui.checkbox(lbl, settings_mod.list_contains(current_list, key))
        cb:on_change(function(val)
            if val then settings_mod.list_add(current_list, key)
            else settings_mod.list_remove(current_list, key) end
            if on_toggle then on_toggle(key, val) end
        end)
        parent:add(cb)
    end
end

local function make_input_row(parent, label_text, value, on_change)
    local row = Gui.hbox()
    row:add(Gui.label(label_text .. ": "))
    local inp = Gui.input({text = value or ""})
    inp:on_change(on_change)
    row:add(inp)
    parent:add(row)
    return inp
end

local function make_spell_checkbox(parent, spell_id, label_text, opt_key, opts)
    local known = Spell[spell_id] and Spell[spell_id].known
    local cb = Gui.checkbox(label_text, settings_mod.list_contains(opts, opt_key))
    if not known then cb:set_checked(false) end
    cb:on_change(function(val)
        if val then settings_mod.list_add(opts, opt_key)
        else settings_mod.list_remove(opts, opt_key) end
    end)
    parent:add(cb)
    return cb
end

function M.show(st)
    local win = Gui.window("EBounty Setup v2.0", {width = 850, height = 700, resizable = true})

    local tab_names = {"General", "Resting", "Foraging", "Heirloom", "Bandits", "Escort", "Profiles"}
    local tabs = Gui.tab_bar(tab_names)

    -- Tab 1: General
    local gen = Gui.scroll(Gui.vbox())
    local gen_box = Gui.vbox()

    make_checkbox_list(gen_box, "Bounty Types", {
        {"boss_culling", "Boss Creature"}, {"culling", "Culling"},
        {"escort", "Escort"}, {"foraging", "Foraging"},
        {"gem_collecting", "Gem Collecting"}, {"heirloom_loot", "Heirloom (Loot)"},
        {"heirloom_search", "Heirloom (Search)"}, {"rescue", "Rescue"},
        {"skinning", "Skinning"}, {"kill_bandits", "Bandits"},
    }, st.bounty_types)

    gen_box:add(Gui.separator())
    gen_box:add(Gui.section_header("Behavior"))
    local toggle_keys = {
        {"exp_pause","Pause when mind full"}, {"skip_healing","Skip healing"},
        {"once_and_done","Run one bounty and quit"}, {"new_bounty_on_exit","Get new bounty before exit"},
        {"keep_hunting","Keep hunting after bounty"}, {"basic","Basic mode (no hunting)"},
        {"ranger_track","Use Ranger Track"}, {"return_to_group","Return to group on exit"},
        {"use_boosts","Use bounty boosts"}, {"use_vouchers","Use expedite vouchers"},
        {"remove_heirloom","Remove if heirloom lost"}, {"only_required_creatures","Only kill bounty creatures"},
    }
    local exp_cb, keep_cb
    for _, t in ipairs(toggle_keys) do
        local cb = Gui.checkbox(t[2], st[t[1]] or false)
        cb:on_change(function(v)
            st[t[1]] = v
            if t[1] == "exp_pause" and v and keep_cb then
                st.keep_hunting = false; keep_cb:set_checked(false)
            elseif t[1] == "keep_hunting" and v and exp_cb then
                st.exp_pause = false; exp_cb:set_checked(false)
            end
        end)
        if t[1] == "exp_pause" then exp_cb = cb end
        if t[1] == "keep_hunting" then keep_cb = cb end
        gen_box:add(cb)
    end

    gen_box:add(Gui.separator())
    local boost_row = Gui.hbox()
    boost_row:add(Gui.label("Boost Type: "))
    local boost_combo = Gui.editable_combo({
        text = st.boost_type or "",
        options = data.boost_types,
    })
    boost_combo:on_change(function(v) st.boost_type = v end)
    boost_row:add(boost_combo)
    gen_box:add(boost_row)

    gen_box:add(Gui.separator())
    gen_box:add(Gui.section_header("Task Limits"))
    for _, f in ipairs({
        {"culling_max","Max Culling"}, {"gem_max","Max Gems"},
        {"herb_max","Max Herbs"}, {"skin_max","Max Skins"}, {"extra_skin","Extra Skins"},
    }) do
        make_input_row(gen_box, f[2], tostring(st[f[1]] or 0), function(v) st[f[1]] = tonumber(v) or 0 end)
    end

    gen_box:add(Gui.separator())
    gen_box:add(Gui.section_header("Support Scripts"))
    for _, f in ipairs({
        {"selling_script","Selling"}, {"healing_script","Healing"},
        {"death_script","Death Recovery"}, {"hording_script","Gem Hoarding"},
        {"escort_script","Escort"}, {"rescue_script","Rescue"},
        {"gem_history","Gem History"}, {"buff_script","Buff"},
    }) do
        make_input_row(gen_box, f[2], st[f[1]] or "", function(v) st[f[1]] = v end)
    end

    gen_box:add(Gui.separator())
    gen_box:add(Gui.section_header("Exclusions (comma-separated)"))
    for _, f in ipairs({
        {"creature_exclude","Creatures"}, {"herb_exclude","Herbs"},
        {"gem_exclude","Gems"}, {"location_exclude","Locations"},
    }) do
        make_input_row(gen_box, f[2], table.concat(st[f[1]] or {}, ", "), function(v)
            local list = {}
            for item in v:gmatch("[^,]+") do
                item = item:match("^%s*(.-)%s*$")
                if item ~= "" then list[#list + 1] = item end
            end
            st[f[1]] = list
        end)
    end

    gen = Gui.scroll(gen_box)
    tabs:set_tab_content(1, gen)

    -- Tab 2: Resting
    local rest_box = Gui.vbox()

    rest_box:add(Gui.section_header("Resting Mode"))
    local rest_opts = {
        {"table_rest","Rest at nearest table"}, {"bigshot_rest","Use bigshot resting room"},
        {"custom_rest","Custom room(s)"}, {"rest_random","Random town spot"},
        {"use_script","Use resting script"},
    }
    local rest_cbs = {}
    for _, t in ipairs(rest_opts) do
        local cb = Gui.checkbox(t[2], st[t[1]] or false)
        rest_cbs[t[1]] = cb
        cb:on_change(function(v)
            st[t[1]] = v
            if v then
                for _, other in ipairs(rest_opts) do
                    if other[1] ~= t[1] then
                        st[other[1]] = false
                        rest_cbs[other[1]]:set_checked(false)
                    end
                end
            end
        end)
        rest_box:add(cb)
    end

    rest_box:add(Gui.separator())
    make_input_row(rest_box, "Custom Room IDs", st.resting_room or "", function(v) st.resting_room = v end)
    make_input_row(rest_box, "Resting Script", st.use_script_name or "", function(v) st.use_script_name = v end)

    rest_box:add(Gui.separator())
    local jp = Gui.checkbox("Join player when resting", st.join_player or false)
    jp:on_change(function(v) st.join_player = v end)
    rest_box:add(jp)
    make_input_row(rest_box, "Join Player Names", st.join_list or "", function(v) st.join_list = v end)

    local bs = Gui.checkbox("Run buff script when resting", st.use_buff_script or false)
    bs:on_change(function(v) st.use_buff_script = v end)
    rest_box:add(bs)

    rest_box:add(Gui.separator())
    rest_box:add(Gui.section_header("Per-Town Resting Rooms"))
    local town_fields = {
        {"landing_resting","Wehnimer's Landing"}, {"icemule_resting","Icemule Trace"},
        {"solhaven_resting","Solhaven"}, {"teras_resting","Kharam-Dzu"},
        {"illy_resting","Ta'Illistim"}, {"vaalor_resting","Ta'Vaalor"},
        {"zul_resting","Zul Logoth"}, {"rr_resting","River's Rest"},
        {"kf_resting","Kraken's Fall"}, {"fwi_resting","Mist Harbor"},
        {"hw_resting","Cold River"}, {"contempt_resting","Sailor's Grief"},
    }
    for _, f in ipairs(town_fields) do
        make_input_row(rest_box, f[2], st[f[1]] or "", function(v) st[f[1]] = v end)
    end

    tabs:set_tab_content(2, Gui.scroll(rest_box))

    -- Tab 3: Foraging
    local forage_box = Gui.vbox()
    forage_box:add(Gui.section_header("Foraging Spells & Options"))

    local forage_spells = {
        {608, "Camouflage (608)", "use_608"},
        {604, "Nature's Bounty (604)", "use_604"},
        {604, "Nature's Bounty Evoke (604)", "use_604evoke"},
        {619, "Untrampled Wilds (619)", "use_619"},
        {506, "Celerity (506)", "use_506"},
        {650, "Assume Aspect (650)", "use_650"},
        {709, "Quake (709)", "use_709"},
        {919, "Wizard's Shield (919)", "use_919"},
        {213, "Sanctuary (213)", "use_213"},
        {1011, "Song of Peace (1011)", "use_1011"},
        {140, "Wall of Force (140)", "use_140"},
        {1035, "Song of Tonis (1035)", "use_1035"},
        {9704, "Sigil of Resolve (9704)", "use_resolve"},
    }
    for _, sp in ipairs(forage_spells) do
        make_spell_checkbox(forage_box, sp[1], sp[2], sp[3], st.forage_options)
    end

    local hiding_cb = Gui.checkbox("Hide (no spell)", settings_mod.list_contains(st.forage_options, "hiding"))
    hiding_cb:on_change(function(v)
        if v then settings_mod.list_add(st.forage_options, "hiding")
        else settings_mod.list_remove(st.forage_options, "hiding") end
    end)
    forage_box:add(hiding_cb)

    local gambit_cb = Gui.checkbox("Use Rogue Gambit", settings_mod.list_contains(st.forage_options, "use_gambit"))
    gambit_cb:on_change(function(v)
        if v then settings_mod.list_add(st.forage_options, "use_gambit")
        else settings_mod.list_remove(st.forage_options, "use_gambit") end
    end)
    forage_box:add(gambit_cb)

    local run_cb = Gui.checkbox("Run from hostile NPCs", settings_mod.list_contains(st.forage_options, "run"))
    run_cb:on_change(function(v)
        if v then settings_mod.list_add(st.forage_options, "run")
        else settings_mod.list_remove(st.forage_options, "run") end
    end)
    forage_box:add(run_cb)

    forage_box:add(Gui.separator())
    forage_box:add(Gui.section_header("Forage Prep/Post"))
    make_input_row(forage_box, "Prep Commands", st.forage_prep_commands or "", function(v) st.forage_prep_commands = v end)
    make_input_row(forage_box, "Prep Scripts", st.forage_prep_scripts or "", function(v) st.forage_prep_scripts = v end)
    make_input_row(forage_box, "Post Commands", st.forage_post_commands or "", function(v) st.forage_post_commands = v end)
    make_input_row(forage_box, "Post Scripts", st.forage_post_scripts or "", function(v) st.forage_post_scripts = v end)

    tabs:set_tab_content(3, Gui.scroll(forage_box))

    -- Tab 4: Heirloom
    local heir_box = Gui.vbox()
    heir_box:add(Gui.section_header("Heirloom Search Spells"))

    local heir_spells = {
        {709, "Quake (709)", "use_709"},
        {140, "Wall of Force (140)", "use_140"},
        {402, "Presence (402)", "use_402"},
        {506, "Celerity (506)", "use_506"},
        {919, "Wizard's Shield (919)", "use_919"},
        {213, "Sanctuary (213)", "use_213"},
        {619, "Untrampled Wilds (619)", "use_619"},
        {1011, "Song of Peace (1011)", "use_1011"},
        {1035, "Song of Tonis (1035)", "use_1035"},
    }
    for _, sp in ipairs(heir_spells) do
        make_spell_checkbox(heir_box, sp[1], sp[2], sp[3], st.heirloom_options)
    end

    local use_right_cb = Gui.checkbox("Keep item in right hand", settings_mod.list_contains(st.heirloom_options, "use_right"))
    use_right_cb:on_change(function(v)
        if v then settings_mod.list_add(st.heirloom_options, "use_right")
        else settings_mod.list_remove(st.heirloom_options, "use_right") end
    end)
    heir_box:add(use_right_cb)

    heir_box:add(Gui.separator())
    heir_box:add(Gui.section_header("Heirloom Prep/Post"))
    make_input_row(heir_box, "Prep Commands", st.heirloom_prep_commands or "", function(v) st.heirloom_prep_commands = v end)
    make_input_row(heir_box, "Prep Scripts", st.heirloom_prep_scripts or "", function(v) st.heirloom_prep_scripts = v end)
    make_input_row(heir_box, "Post Commands", st.heirloom_post_commands or "", function(v) st.heirloom_post_commands = v end)
    make_input_row(heir_box, "Post Scripts", st.heirloom_post_scripts or "", function(v) st.heirloom_post_scripts = v end)

    tabs:set_tab_content(4, Gui.scroll(heir_box))

    -- Tab 5: Bandits
    local bandit_box = Gui.vbox()
    bandit_box:add(Gui.section_header("Bandit Locations"))
    for i = 1, 12 do
        local row = Gui.hbox()
        row:add(Gui.label("Location " .. i .. ": "))
        local loc_inp = Gui.input({text = st["location" .. i] or ""})
        loc_inp:on_change(function(v) st["location" .. i] = v end)
        row:add(loc_inp)
        row:add(Gui.label(" Bad Rooms: "))
        local bad_inp = Gui.input({text = st["bad_room" .. i] or ""})
        bad_inp:on_change(function(v) st["bad_room" .. i] = v end)
        row:add(bad_inp)
        bandit_box:add(row)
    end

    bandit_box:add(Gui.separator())
    make_input_row(bandit_box, "Wander Wait (seconds)", tostring(st.wander_wait or 0.5), function(v)
        st.wander_wait = tonumber(v) or 0.5
    end)

    tabs:set_tab_content(5, Gui.scroll(bandit_box))

    -- Tab 6: Escort
    local escort_box = Gui.vbox()
    escort_box:add(Gui.section_header("Escort Routes"))

    local towns = {"landing", "icemule", "zul", "solhaven", "vaalor", "illy"}
    local town_labels = {
        landing = "WL", icemule = "IMT", zul = "ZL",
        solhaven = "Sol", vaalor = "TV", illy = "TI",
    }
    for _, from in ipairs(towns) do
        for _, to in ipairs(towns) do
            if from ~= to then
                local route = from .. "_to_" .. to
                local label = (town_labels[from] or from) .. " -> " .. (town_labels[to] or to)
                local cb = Gui.checkbox(label, settings_mod.list_contains(st.escort_types, route))
                cb:on_change(function(v)
                    if v then settings_mod.list_add(st.escort_types, route)
                    else settings_mod.list_remove(st.escort_types, route) end
                end)
                escort_box:add(cb)
            end
        end
    end

    escort_box:add(Gui.separator())
    escort_box:add(Gui.section_header("Escort Prep/Post"))
    make_input_row(escort_box, "Prep Commands", st.escort_prep_commands or "", function(v) st.escort_prep_commands = v end)
    make_input_row(escort_box, "Prep Scripts", st.escort_prep_scripts or "", function(v) st.escort_prep_scripts = v end)
    make_input_row(escort_box, "Post Commands", st.escort_post_commands or "", function(v) st.escort_post_commands = v end)
    make_input_row(escort_box, "Post Scripts", st.escort_post_scripts or "", function(v) st.escort_post_scripts = v end)

    tabs:set_tab_content(6, Gui.scroll(escort_box))

    -- Tab 7: Profiles
    local prof_box = Gui.vbox()

    prof_box:add(Gui.section_header("Default & Bandits"))
    make_input_row(prof_box, "Default Profile", st.default_profile or "", function(v) st.default_profile = v end)
    make_input_row(prof_box, "Bandits Profile", st.bandits_profile or "", function(v) st.bandits_profile = v end)
    local kb = Gui.checkbox("Kill bandits only", st.kill_bandits or false)
    kb:on_change(function(v) st.kill_bandits = v end)
    prof_box:add(kb)

    prof_box:add(Gui.separator())
    prof_box:add(Gui.section_header("Creature Profiles (A-J)"))
    for _, letter in ipairs({"a","b","c","d","e","f","g","h","i","j"}) do
        local card = Gui.card({title = "Profile " .. letter:upper()})
        local inner = Gui.vbox()
        make_input_row(inner, "Creature Names", st["names_" .. letter] or "", function(v) st["names_" .. letter] = v end)
        make_input_row(inner, "Bigshot Profile", st["profile_" .. letter] or "", function(v) st["profile_" .. letter] = v end)
        local kc = Gui.checkbox("Kill only these creatures", st["kill_" .. letter] or false)
        kc:on_change(function(v) st["kill_" .. letter] = v end)
        inner:add(kc)
        card:add(inner)
        prof_box:add(card)
    end

    tabs:set_tab_content(7, Gui.scroll(prof_box))

    -- Bottom buttons
    local root = Gui.vbox()
    root:add(tabs)

    local btns = Gui.hbox()
    local save = Gui.button("Save & Close")
    save:on_click(function() settings_mod.save(st); win:close() end)
    btns:add(save)
    local cancel = Gui.button("Cancel")
    cancel:on_click(function() win:close() end)
    btns:add(cancel)
    root:add(btns)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
    return st
end

return M
