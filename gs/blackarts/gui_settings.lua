--- @module blackarts.gui_settings
-- Full tabbed settings GUI. Ported from BlackArts::Setup (BlackArts.lic v3.12.x)
-- Uses the Revenant Gui widget system (matches bigshot gui_settings.lua patterns).

local settings_mod = require("settings")

local M = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function section(parent, title)
    parent:add(Gui.section_header(title))
end

local function row_input(parent, label_text, value, tooltip)
    local row = Gui.hbox()
    row:add(Gui.label(label_text))
    local inp = Gui.input({ text = tostring(value or ""), placeholder = tooltip or "" })
    row:add(inp)
    parent:add(row)
    return inp
end

local function row_checkbox(parent, label_text, checked)
    local chk = Gui.checkbox(label_text, checked or false)
    parent:add(chk)
    return chk
end

local function row_combo(parent, label_text, value, options)
    local row = Gui.hbox()
    row:add(Gui.label(label_text))
    local combo = Gui.editable_combo({ text = tostring(value or ""), options = options })
    row:add(combo)
    parent:add(row)
    return combo
end

--------------------------------------------------------------------------------
-- Tab 1: Guild Skills
--------------------------------------------------------------------------------

local function build_guild_skills_tab(cfg)
    local vbox = Gui.vbox()

    section(vbox, "Skills to Train")
    local skill_checkboxes = {}
    local skill_opts = {"alchemy", "potions", "trinkets"}
    if Char.prof == "Sorcerer" then skill_opts[#skill_opts+1] = "illusions" end

    for _, sk in ipairs(skill_opts) do
        local enabled = false
        for _, s in ipairs(cfg.skill_types) do
            if s == sk then enabled = true; break end
        end
        local chk = row_checkbox(vbox, sk:sub(1,1):upper() .. sk:sub(2), enabled)
        skill_checkboxes[sk] = chk
    end

    section(vbox, "Behaviour")
    local vouchers = row_checkbox(vbox, "Use Task Trading Vouchers",  cfg.use_vouchers)
    local boost    = row_checkbox(vbox, "Use Guild Boost (login reward)", cfg.use_boost)
    local once     = row_checkbox(vbox, "Run One Task Only (once-and-done)", cfg.once_and_done)
    local no_alch  = row_checkbox(vbox, "No Alchemy Mode (trade tasks in)", cfg.no_alchemy)

    section(vbox, "Guild Travel")
    local guild_travel = row_checkbox(vbox, "Travel to Other Guilds", cfg.guild_travel)
    local rr_travel    = row_checkbox(vbox, "Include River's Rest", cfg.rr_travel)
    local pause_inp    = row_input(vbox, "Guild Pause (seconds):", cfg.guild_pause, "60")
    local home_combo   = row_combo(vbox, "Home Guild:", cfg.home_guild,
        {"Closest", "Wehnimer's Landing", "Solhaven", "Icemule Trace",
         "Ta'Illistim", "Ta'Vaalor", "Mist Harbor", "Zul Logoth", "Kharam-Dzu", "River's Rest"})

    local root = Gui.scroll(vbox)
    return root, function()
        cfg.skill_types = {}
        for sk, chk in pairs(skill_checkboxes) do
            if chk:get_checked() then cfg.skill_types[#cfg.skill_types+1] = sk end
        end
        cfg.use_vouchers   = vouchers:get_checked()
        cfg.use_boost      = boost:get_checked()
        cfg.once_and_done  = once:get_checked()
        cfg.no_alchemy     = no_alch:get_checked()
        cfg.guild_travel   = guild_travel:get_checked()
        cfg.rr_travel      = rr_travel:get_checked()
        cfg.guild_pause    = tonumber(pause_inp:get_text()) or 60
        cfg.home_guild     = home_combo:get_text()
    end
end

--------------------------------------------------------------------------------
-- Tab 2: Foraging
--------------------------------------------------------------------------------

local function build_foraging_tab(cfg)
    local vbox = Gui.vbox()

    section(vbox, "Foraging Options")
    local forage_opts_flags = {"run", "use_213", "use_709", "use_919", "use_140"}
    local forage_opt_labels = {
        run       = "Run through monsters while foraging",
        use_213   = "Cast spell 213 (Cleric sense) before foraging",
        use_709   = "Cast WoT (709) to clear limb-based monsters",
        use_919   = "Cast Floating Disk (919) for foraging bonus",
        use_140   = "Cast Haste (140) before foraging",
    }
    local forage_checks = {}
    for _, flag in ipairs(forage_opts_flags) do
        local enabled = false
        if cfg.forage_options then
            for _, v in ipairs(cfg.forage_options) do
                if v == flag then enabled = true; break end
            end
        end
        local chk = row_checkbox(vbox, forage_opt_labels[flag], enabled)
        forage_checks[flag] = chk
    end

    section(vbox, "Excluded Forage Rooms")
    local no_forage = row_input(vbox, "No-forage Room IDs:", cfg.no_forage_rooms or "",
        "Comma-separated room IDs")

    section(vbox, "Pre-Forage Commands")
    local prep_cmds = Gui.input({ text = cfg.forage_prep_commands or "",
        placeholder = "Comma-separated commands (use 'script NAME' for scripts)" })
    vbox:add(prep_cmds)

    section(vbox, "Pre-Forage Scripts")
    local prep_scripts = Gui.input({ text = cfg.forage_prep_scripts or "",
        placeholder = "Comma-separated script names" })
    vbox:add(prep_scripts)

    section(vbox, "Post-Forage Commands")
    local post_cmds = Gui.input({ text = cfg.forage_post_commands or "", placeholder = "" })
    vbox:add(post_cmds)

    section(vbox, "Post-Forage Scripts")
    local post_scripts = Gui.input({ text = cfg.forage_post_scripts or "", placeholder = "" })
    vbox:add(post_scripts)

    local root = Gui.scroll(vbox)
    return root, function()
        cfg.forage_options = {}
        for flag, chk in pairs(forage_checks) do
            if chk:get_checked() then cfg.forage_options[#cfg.forage_options+1] = flag end
        end
        cfg.no_forage_rooms        = no_forage:get_text()
        cfg.forage_prep_commands   = prep_cmds:get_text()
        cfg.forage_prep_scripts    = prep_scripts:get_text()
        cfg.forage_post_commands   = post_cmds:get_text()
        cfg.forage_post_scripts    = post_scripts:get_text()
    end
end

--------------------------------------------------------------------------------
-- Tab 3: Hunting Profiles (a–j)
--------------------------------------------------------------------------------

local function build_profiles_tab(cfg)
    local vbox = Gui.vbox()
    local letters = {"a","b","c","d","e","f","g","h","i","j"}
    local inputs = {}

    section(vbox, "BigShot Hunting Profiles")
    vbox:add(Gui.label("Map creature skin names to BigShot profiles."))
    vbox:add(Gui.label("Names = comma-separated creature skin names (e.g. 'fire cat claw')."))
    vbox:add(Gui.label("Profile = BigShot profile file (JSON export) or profile name."))
    vbox:add(Gui.label("Kill = only hunt target creature (not all targets in bigshot profile)."))
    vbox:add(Gui.label(""))

    for _, letter in ipairs(letters) do
        section(vbox, "Profile " .. letter:upper())
        local row = Gui.hbox()
        local names_inp   = Gui.input({ text = cfg["names_"   .. letter] or "",
                                        placeholder = "Skin names (comma-separated)" })
        local profile_inp = Gui.input({ text = cfg["profile_" .. letter] or "",
                                        placeholder = "BigShot profile name or path" })
        local kill_chk    = Gui.checkbox("Only required creatures",
                                          cfg["kill_" .. letter] or false)
        row:add(names_inp)
        row:add(profile_inp)
        row:add(kill_chk)
        vbox:add(row)
        inputs[letter] = {names=names_inp, profile=profile_inp, kill=kill_chk}
    end

    local root = Gui.scroll(vbox)
    return root, function()
        for _, letter in ipairs(letters) do
            cfg["names_"   .. letter] = inputs[letter].names:get_text()
            cfg["profile_" .. letter] = inputs[letter].profile:get_text()
            cfg["kill_"    .. letter] = inputs[letter].kill:get_checked()
        end
    end
end

--------------------------------------------------------------------------------
-- Tab 4: Lists (consignment, trash, no_magic, recipe_exclude)
--------------------------------------------------------------------------------

local function build_lists_tab(cfg)
    local vbox = Gui.vbox()

    section(vbox, "Consignment Items to Sell")
    local consign = Gui.input({
        text = table.concat(cfg.consignment_include or {}, "\n"),
        placeholder = "One item name per line"
    })
    vbox:add(consign)

    section(vbox, "Items to Trash")
    local trash = Gui.input({
        text = table.concat(cfg.trash or {}, "\n"),
        placeholder = "One item name per line"
    })
    vbox:add(trash)

    section(vbox, "Recipes to Exclude")
    local excl = Gui.input({
        text = table.concat(cfg.recipe_exclude or {}, "\n"),
        placeholder = "One recipe product name per line"
    })
    vbox:add(excl)

    section(vbox, "No-Magic Rooms (spell numbers)")
    local no_magic = Gui.input({
        text = table.concat(cfg.no_magic or {}, "\n"),
        placeholder = "One spell number per line"
    })
    vbox:add(no_magic)

    local function parse_lines(text)
        local lines = {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then lines[#lines+1] = line end
        end
        return lines
    end

    local root = Gui.scroll(vbox)
    return root, function()
        cfg.consignment_include = parse_lines(consign:get_text())
        cfg.trash               = parse_lines(trash:get_text())
        cfg.recipe_exclude      = parse_lines(excl:get_text())
        cfg.no_magic            = parse_lines(no_magic:get_text())
    end
end

--------------------------------------------------------------------------------
-- Tab 5: Banking & Mana
--------------------------------------------------------------------------------

local function build_banking_tab(cfg)
    local vbox = Gui.vbox()

    section(vbox, "Banking")
    local no_bank      = row_checkbox(vbox, "Do Not Use Bank", cfg.no_bank)
    local buy_reagents = row_checkbox(vbox, "Buy Elusive Reagents from Shop", cfg.buy_reagents)
    local sell_consign = row_checkbox(vbox, "Sell Items at Consignment Store", cfg.sell_consignment)
    local withdrawal   = row_input(vbox, "Note Withdrawal Amount:", cfg.note_withdrawal, "50000")
    local refresh      = row_input(vbox, "Note Refresh Threshold:", cfg.note_refresh, "5000")

    section(vbox, "Mana/Spirit Supplements")
    local wracking    = row_checkbox(vbox, "Use Wracking (9918) for mana", cfg.use_wracking)
    local sym_mana    = row_checkbox(vbox, "Use Symbol of Mana (9813)", cfg.use_symbol_mana)
    local sym_renew   = row_checkbox(vbox, "Use Symbol of Renewal", cfg.use_symbol_renewal)
    local sig_power   = row_checkbox(vbox, "Use Sigil of Power (9718)", cfg.use_sigil_power)
    local sig_conc    = row_checkbox(vbox, "Use Sigil of Concentration (9714)", cfg.use_sigil_concentration)

    section(vbox, "Output")
    local silence_chk = row_checkbox(vbox, "Silence Script Output", cfg.silence)
    local debug_chk   = row_checkbox(vbox, "Debug Mode", cfg.debug)

    local root = Gui.scroll(vbox)
    return root, function()
        cfg.no_bank                 = no_bank:get_checked()
        cfg.buy_reagents            = buy_reagents:get_checked()
        cfg.sell_consignment        = sell_consign:get_checked()
        cfg.note_withdrawal         = withdrawal:get_text()
        cfg.note_refresh            = refresh:get_text()
        cfg.use_wracking            = wracking:get_checked()
        cfg.use_symbol_mana         = sym_mana:get_checked()
        cfg.use_symbol_renewal      = sym_renew:get_checked()
        cfg.use_sigil_power         = sig_power:get_checked()
        cfg.use_sigil_concentration = sig_conc:get_checked()
        cfg.silence                 = silence_chk:get_checked()
        cfg.debug                   = debug_chk:get_checked()
    end
end

--------------------------------------------------------------------------------
-- Build and show the full settings window
--------------------------------------------------------------------------------

function M.show(cfg)
    local win = Gui.window("BlackArts Settings", { width = 560, height = 640 })

    local tabs = Gui.tab_bar({"Guild Skills", "Foraging", "Profiles", "Lists", "Banking"})

    local guild_root,    guild_save    = build_guild_skills_tab(cfg)
    local forage_root,   forage_save   = build_foraging_tab(cfg)
    local profiles_root, profiles_save = build_profiles_tab(cfg)
    local lists_root,    lists_save    = build_lists_tab(cfg)
    local banking_root,  banking_save  = build_banking_tab(cfg)

    tabs:set_tab_content(1, guild_root)
    tabs:set_tab_content(2, forage_root)
    tabs:set_tab_content(3, profiles_root)
    tabs:set_tab_content(4, lists_root)
    tabs:set_tab_content(5, banking_root)

    local vbox = Gui.vbox()
    vbox:add(tabs)

    -- Save button
    local save_btn = Gui.button("Save Settings")
    save_btn:on_click(function()
        guild_save()
        forage_save()
        profiles_save()
        lists_save()
        banking_save()
        settings_mod.save(cfg)
        respond("[BlackArts] Settings saved.")
        win:close()
    end)
    vbox:add(save_btn)

    win:set_root(vbox)
    win:show()
    Gui.wait(win, "close")
end

return M
