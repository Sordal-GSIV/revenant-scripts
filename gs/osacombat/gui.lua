-- osacombat/gui.lua — GUI Setup Window for OSACombat
-- Original: osacombat.lic GTK3 window (populate_general through populate_gemstones1)
-- Ported to Revenant Gui module

local M = {}

local win = nil

---------------------------------------------------------------------------
-- Attack option lists (from original osacombat.lic)
---------------------------------------------------------------------------
local SETUP_ATTACK_OPTIONS = {
    "None","Berserk","Bertrandt's Bellow (Single Target)","Bertrandt's Bellow (Open)",
    "Bull Rush","Carn's Cry (Single Target)","Carn's Cry (Open)","Charge (Polearm)",
    "Cripple (Edged)","Crowd Press","Cutthroat",
    "Dark Energy Wings: Shadow Barb","Dark Energy Wings: Barbed Sweep","Dark Energy Wings: Rain of Thorns",
    "Dirtkick","Disarm Weapon","Dislodge","Dizzying Swing (Blunt)","Eviscerate","Excoriate",
    "Eyepoke","Feint","Footstomp",
    "Garrelle's Growl (Single Target)","Garrelle's Growl (Open)",
    "Groin Kick","Hamstring","Haymaker","Headbutt","Kneebash",
    "Light Energy Wings: Radiant Pulse","Light Energy Wings: Blast of Brilliance",
    "Light Energy Wings: Blinding Reprisal",
    "Mighty Blow","Mug","Nosetweak",
    "Shield Bash","Shield Charge","Shield Push","Shield Throw","Shield Trample",
    "Spell Cleave","Subdue","Sunder Shield","Sweep","Swiftkick","Tackle",
    "Templeshot","Throatchop","Trip","Twin Hammerfists (Brawling)","Vault Kick","Voln Sleep",
}

local SPECIAL_ATTACK_OPTIONS = {
    "None","Bearhug","Chastise",
    "Dark Energy Wings: Shadow Barb","Dark Energy Wings: Barbed Sweep","Dark Energy Wings: Rain of Thorns",
    "Excoriate","Exsanguinate","Leap Attack",
    "Light Energy Wings: Radiant Pulse","Light Energy Wings: Blast of Brilliance",
    "Light Energy Wings: Blinding Reprisal",
    "Shield Strike","Spin Attack","Staggering Blow","True Strike",
}

local AOE_ATTACK_OPTIONS = {
    "None","Bull Rush","Clash (Brawling)","Cyclone (Polearm)",
    "Dark Energy Wings: Barbed Sweep","Dark Energy Wings: Rain of Thorns",
    "Pin Down (Ranged)","Pound (Flare Gloves)","Pulverize (Blunt)",
    "Light Energy Wings: Radiant Pulse","Light Energy Wings: Blast of Brilliance",
    "Light Energy Wings: Blinding Reprisal",
    "Shield Throw","Shield Trample","Whirling Blade (Edged)","Whirlwind (Two-Handed)","Volley (Ranged)",
}

local ASSAULT_OPTIONS = {
    "None","Barrage (Ranged)","Dark Energy Wings: Shadow Barb",
    "Flurry (Edged)","Fury (Brawling)","Guardant Thrusts (Polearm)",
    "Light Energy Wings: Radiant Pulse","Pummel (Blunt)","Thrash (Two-Handed)",
}

local STANCE_OPTIONS_ATK = {"Offensive","Advance","Forward","Neutral","Guarded","Defensive"}
local STANCE_OPTIONS_DEF = {"Defensive","Guarded","Neutral","Forward","Advance","Offensive"}

local STEALTH_DISABLER_OPTIONS = {
    "Search (Default)","Dispel Invisibility","Searing Light","Light","Censure",
    "Divine Wrath","Elemental Wave","Major Elemental Wave","Cone of Elements","Sunburst",
    "Nature's Fury","Grasp of the Grave","Implosion","Tremors","Call Wind",
    "Aura of the Arkati","Judgement","Eviscerate","Carn's Cry (Open)","Symbol of Sleep",
}

---------------------------------------------------------------------------
-- Widget tracking for save
---------------------------------------------------------------------------
local widgets = {}

---------------------------------------------------------------------------
-- Helper functions
---------------------------------------------------------------------------

local function get_val(cfg, key)
    local v = cfg.get(key)
    if v == nil then return "" end
    return tostring(v)
end

local function get_bool(cfg, key)
    return cfg.get_bool(key)
end

--- Add a labeled input row and track the widget.
local function add_input_row(parent, label_text, key, cfg, width)
    local row = Gui.hbox()
    row:add(Gui.label(label_text))
    local inp = Gui.input({ text = get_val(cfg, key), placeholder = "" })
    row:add(inp)
    parent:add(row)
    widgets[key] = { type = "input", widget = inp }
    return inp
end

--- Add a checkbox and track it.
local function add_checkbox(parent, label_text, key, cfg)
    local cb = Gui.checkbox(label_text, get_bool(cfg, key))
    parent:add(cb)
    widgets[key] = { type = "checkbox", widget = cb }
    return cb
end

--- Add an editable combo (dropdown replacement) and track it.
local function add_combo(parent, label_text, key, cfg, options)
    local row = Gui.hbox()
    row:add(Gui.label(label_text))
    local combo = Gui.editable_combo({
        text = get_val(cfg, key),
        hint = "",
        options = options,
    })
    row:add(combo)
    parent:add(row)
    widgets[key] = { type = "combo", widget = combo }
    return combo
end

--- Add an attack row: combo + Min Stam + Min Mana + Min Enemy + Max Enemy
local function add_attack_row(parent, label_text, attack_key, options, stam_key, mana_key, enemy_min_key, enemy_max_key, cfg)
    local card = Gui.card({ title = label_text })
    local row1 = Gui.hbox()
    local combo = Gui.editable_combo({
        text = get_val(cfg, attack_key),
        hint = "Select attack",
        options = options,
    })
    row1:add(combo)
    card:add(row1)
    widgets[attack_key] = { type = "combo", widget = combo }

    local row2 = Gui.hbox()
    row2:add(Gui.label("Min Stam:"))
    local stam_inp = Gui.input({ text = get_val(cfg, stam_key) })
    row2:add(stam_inp)
    widgets[stam_key] = { type = "input", widget = stam_inp }

    row2:add(Gui.label("Min Mana:"))
    local mana_inp = Gui.input({ text = get_val(cfg, mana_key) })
    row2:add(mana_inp)
    widgets[mana_key] = { type = "input", widget = mana_inp }

    row2:add(Gui.label("Min Enemy:"))
    local emin_inp = Gui.input({ text = get_val(cfg, enemy_min_key) })
    row2:add(emin_inp)
    widgets[enemy_min_key] = { type = "input", widget = emin_inp }

    row2:add(Gui.label("Max Enemy:"))
    local emax_inp = Gui.input({ text = get_val(cfg, enemy_max_key) })
    row2:add(emax_inp)
    widgets[enemy_max_key] = { type = "input", widget = emax_inp }

    card:add(row2)
    parent:add(card)
end

--- Add a spell row: spell number + Min Stam + Min Mana + Min Enemy + Max Enemy + Warding + Channel + Evoke + Open
local function add_spell_row(parent, label_text, spell_key, stam_key, mana_key, enemy_min_key, enemy_max_key, ward_key, chan_key, evoke_key, open_key, cfg)
    local card = Gui.card({ title = label_text })

    local row1 = Gui.hbox()
    row1:add(Gui.label("Spell #:"))
    local spell_inp = Gui.input({ text = get_val(cfg, spell_key), placeholder = "Spell number" })
    row1:add(spell_inp)
    widgets[spell_key] = { type = "input", widget = spell_inp }

    row1:add(Gui.label("Min Stam:"))
    local stam_inp = Gui.input({ text = get_val(cfg, stam_key) })
    row1:add(stam_inp)
    widgets[stam_key] = { type = "input", widget = stam_inp }

    row1:add(Gui.label("Min Mana:"))
    local mana_inp = Gui.input({ text = get_val(cfg, mana_key) })
    row1:add(mana_inp)
    widgets[mana_key] = { type = "input", widget = mana_inp }

    row1:add(Gui.label("Min Enemy:"))
    local emin_inp = Gui.input({ text = get_val(cfg, enemy_min_key) })
    row1:add(emin_inp)
    widgets[enemy_min_key] = { type = "input", widget = emin_inp }

    row1:add(Gui.label("Max Enemy:"))
    local emax_inp = Gui.input({ text = get_val(cfg, enemy_max_key) })
    row1:add(emax_inp)
    widgets[enemy_max_key] = { type = "input", widget = emax_inp }

    card:add(row1)

    local row2 = Gui.hbox()
    local ward_cb = Gui.checkbox("Warding", get_bool(cfg, ward_key))
    row2:add(ward_cb)
    widgets[ward_key] = { type = "checkbox", widget = ward_cb }

    local chan_cb = Gui.checkbox("Channel", get_bool(cfg, chan_key))
    row2:add(chan_cb)
    widgets[chan_key] = { type = "checkbox", widget = chan_cb }

    local evoke_cb = Gui.checkbox("Evoke", get_bool(cfg, evoke_key))
    row2:add(evoke_cb)
    widgets[evoke_key] = { type = "checkbox", widget = evoke_cb }

    local open_cb = Gui.checkbox("Open Cast", get_bool(cfg, open_key))
    row2:add(open_cb)
    widgets[open_key] = { type = "checkbox", widget = open_cb }

    card:add(row2)
    parent:add(card)
end

--- Add a gemstone ability row: enable checkbox + variable threshold fields
local function add_gemstone_row(parent, label_text, enable_key, fields, cfg)
    local card = Gui.card({ title = label_text })
    local row = Gui.hbox()

    local enable_cb = Gui.checkbox("Enable", get_bool(cfg, enable_key))
    row:add(enable_cb)
    widgets[enable_key] = { type = "checkbox", widget = enable_cb }

    for _, field in ipairs(fields) do
        row:add(Gui.label(field.label))
        local inp = Gui.input({ text = get_val(cfg, field.key) })
        row:add(inp)
        widgets[field.key] = { type = "input", widget = inp }
    end

    card:add(row)
    parent:add(card)
end

---------------------------------------------------------------------------
-- Tab 1: General
---------------------------------------------------------------------------
local function build_general_tab(cfg)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Combat Settings"))

    add_input_row(vbox, "Mana Leech Threshold:", "percentleech", cfg)
    add_input_row(vbox, "Wound Threshold:", "wound_level", cfg)
    add_input_row(vbox, "Symbol of Restore Threshold:", "percent_health", cfg)
    add_input_row(vbox, "Safe Room:", "safe_room", cfg)
    add_input_row(vbox, "UAC Hand Wraps:", "uachands", cfg)
    add_input_row(vbox, "UAC Foot Wraps:", "uacfeet", cfg)
    add_input_row(vbox, "Flare Gloves Noun:", "flareglovesnoun", cfg)
    add_input_row(vbox, "Energy Wing Pin Noun:", "energy_wings_noun", cfg)
    add_input_row(vbox, "Paladin Infuse Spell:", "infusespell", cfg)
    add_input_row(vbox, "Creature Exclusion List:", "exclusion", cfg)

    vbox:add(Gui.separator())
    add_combo(vbox, "Stealth Disabler:", "stealth_disabler", cfg, STEALTH_DISABLER_OPTIONS)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Combat Toggles"))

    -- Row 1
    local r1 = Gui.hbox()
    add_checkbox(r1, "Scripted Combat", "osacombat", cfg)
    add_checkbox(r1, "Enable Mana Leech", "use_mana_leech", cfg)
    add_checkbox(r1, "Use Stomp", "stomp", cfg)
    add_checkbox(r1, "Use Pound", "pound", cfg)
    vbox:add(r1)

    -- Row 2
    local r2 = Gui.hbox()
    add_checkbox(r2, "Use Tap", "tap", cfg)
    add_checkbox(r2, "Enable Attack Command", "noattack", cfg)
    add_checkbox(r2, "Enable Stance Dancing", "stance_dance", cfg)
    add_checkbox(r2, "Enable Fire Command", "osaarcher", cfg)
    vbox:add(r2)

    -- Row 3
    local r3 = Gui.hbox()
    add_checkbox(r3, "Enable Kneeling", "use_kneel", cfg)
    add_checkbox(r3, "Enable Mstrike", "use_mstrike", cfg)
    add_checkbox(r3, "Enable Stalking and Hiding (Ambush)", "use_stealth", cfg)
    add_checkbox(r3, "Enable Stalking and Hiding (Waylay)", "use_waylay", cfg)
    vbox:add(r3)

    -- Row 4
    local r4 = Gui.hbox()
    add_checkbox(r4, "Enable UAC W/ Weapons", "uacweapons", cfg)
    add_checkbox(r4, "Enable UAC W/O Weapons", "nouacweapons", cfg)
    add_checkbox(r4, "Enable Brief Combat", "usebriefcombat", cfg)
    add_checkbox(r4, "Enable Reactive Attacks", "use_reactive", cfg)
    vbox:add(r4)

    -- Row 5
    local r5 = Gui.hbox()
    add_checkbox(r5, "Enable Anti-Poaching", "check_for_group", cfg)
    add_checkbox(r5, "Enable Unstun", "use_unstun", cfg)
    add_checkbox(r5, "Enable Looting", "osalooter", cfg)
    add_checkbox(r5, "Disable Looting When Gemstone Found", "usekilltracker", cfg)
    vbox:add(r5)

    -- Row 6
    local r6 = Gui.hbox()
    add_checkbox(r6, "Enable Skinning Only", "skin_only", cfg)
    add_checkbox(r6, "Bless Caster", "givebless", cfg)
    add_checkbox(r6, "Need Bless", "needbless", cfg)
    vbox:add(r6)

    return Gui.scroll(vbox)
end

---------------------------------------------------------------------------
-- Tab 2: Support
---------------------------------------------------------------------------
local function build_support_tab(cfg)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Buffs"))

    -- Row 1
    local r1 = Gui.hbox()
    add_checkbox(r1, "Seanette's Shout", "warcry_shout", cfg)
    add_checkbox(r1, "Horland's Holler", "warcry_holler", cfg)
    add_checkbox(r1, "Surge of Strength (Use Cooldown)", "cman_surge_of_strength_cooldown", cfg)
    vbox:add(r1)

    -- Row 2
    local r2 = Gui.hbox()
    add_checkbox(r2, "Surge of Strength (Ignore Cooldown)", "cman_surge_of_strength_no_cooldown", cfg)
    add_checkbox(r2, "Wall of Force (140)", "spell_wall_of_force", cfg)
    add_checkbox(r2, "Group Bravery (211)", "groupbravery", cfg)
    vbox:add(r2)

    -- Row 3
    local r3 = Gui.hbox()
    add_checkbox(r3, "Group Heroism (215)", "spell_heroism", cfg)
    add_checkbox(r3, "Sanctify Right Hand (330)", "sanctrighthand", cfg)
    add_checkbox(r3, "Sanctify Left Hand (330)", "sanctlefthand", cfg)
    vbox:add(r3)

    -- Row 4
    local r4 = Gui.hbox()
    add_checkbox(r4, "Mana Focus", "cast_spell_mana_focus", cfg)
    add_checkbox(r4, "Celerity (506)", "cast_spell_self_celerity", cfg)
    add_checkbox(r4, "Group Celerity (506)", "cast_spell_group_celerity", cfg)
    vbox:add(r4)

    -- Row 5
    local r5 = Gui.hbox()
    add_checkbox(r5, "Rapid Fire (515)", "spell_rapid_fire", cfg)
    add_checkbox(r5, "Barkskin (605)", "barkskin_spell", cfg)
    add_checkbox(r5, "Group Barkskin (605)", "barkskin_spell_group", cfg)
    vbox:add(r5)

    -- Row 6
    local r6 = Gui.hbox()
    add_checkbox(r6, "Song of Tonis (1035)", "song_song_of_tonis", cfg)
    add_checkbox(r6, "Mind Over Body (1213)", "mob", cfg)
    add_checkbox(r6, "Focus Barrier (1216)", "focus", cfg)
    vbox:add(r6)

    -- Row 7
    local r7 = Gui.hbox()
    add_checkbox(r7, "Beacon of Courage (1608)", "spell_beacon_of_courage", cfg)
    add_checkbox(r7, "Faith Shield (1619)", "spell_shield_faith", cfg)
    add_checkbox(r7, "DI Armor Emergency (1650)", "di_armor", cfg)
    vbox:add(r7)

    -- Row 8
    local r8 = Gui.hbox()
    add_checkbox(r8, "DI Zeal (1650)", "cast_spell_di_zeal", cfg)
    add_checkbox(r8, "Steely Resolve", "shield_steely", cfg)
    vbox:add(r8)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Society"))

    -- Society column headers
    local hdr = Gui.hbox()
    hdr:add(Gui.label("Council of Light"))
    hdr:add(Gui.label("Guardians of Sunfist"))
    hdr:add(Gui.label("Order of Voln"))
    vbox:add(hdr)

    -- Society row 1
    local s1 = Gui.hbox()
    add_checkbox(s1, "Sign of Warding", "sign_of_warding", cfg)
    add_checkbox(s1, "Sigil of Minor Bane", "sigil_of_minor_bane", cfg)
    add_checkbox(s1, "Symbol of Courage", "symbol_of_courage", cfg)
    vbox:add(s1)

    -- Society row 2
    local s2 = Gui.hbox()
    add_checkbox(s2, "Sign of Defending", "sign_of_defending", cfg)
    add_checkbox(s2, "Sigil of Offense", "sigil_of_offense", cfg)
    add_checkbox(s2, "Symbol of Protection", "symbol_of_protection", cfg)
    vbox:add(s2)

    -- Society row 3
    local s3 = Gui.hbox()
    add_checkbox(s3, "Sign of Shields", "sign_of_shields", cfg)
    add_checkbox(s3, "Sigil of Major Bane", "sigil_of_major_bane", cfg)
    add_checkbox(s3, "Symbol of Mana", "symbol_of_mana", cfg)
    vbox:add(s3)

    -- Society row 4
    local s4 = Gui.hbox()
    add_checkbox(s4, "Sign of Striking", "sign_of_striking", cfg)
    add_checkbox(s4, "Sigil of Minor Protection", "sigil_of_minor_protection", cfg)
    add_checkbox(s4, "Symbol of Retribution", "symbol_of_retribution", cfg)
    vbox:add(s4)

    -- Society row 5
    local s5 = Gui.hbox()
    add_checkbox(s5, "Sign of Smiting", "sign_of_smiting", cfg)
    add_checkbox(s5, "Sigil of Defense", "sigil_of_defense", cfg)
    add_checkbox(s5, "Symbol of Supremacy", "symbol_of_supremacy", cfg)
    vbox:add(s5)

    -- Society row 6
    local s6 = Gui.hbox()
    add_checkbox(s6, "Sign of Swords", "sign_of_swords", cfg)
    add_checkbox(s6, "Sigil of Major Protection", "sigil_of_major_protection", cfg)
    add_checkbox(s6, "Symbol of Restoration", "symbol_of_restore", cfg)
    vbox:add(s6)

    -- Society row 7
    local s7 = Gui.hbox()
    s7:add(Gui.label(""))  -- spacer for alignment
    add_checkbox(s7, "Sigil of Concentration", "sigil_of_concentration", cfg)
    add_checkbox(s7, "Symbol of Transcendence", "symbol_of_transcendance", cfg)
    vbox:add(s7)

    -- Society row 8
    local s8 = Gui.hbox()
    s8:add(Gui.label(""))  -- spacer for alignment
    add_checkbox(s8, "Sigil of Power", "sigil_of_power", cfg)
    add_checkbox(s8, "Symbol of Disruption", "symbol_of_disruption", cfg)
    vbox:add(s8)

    return Gui.scroll(vbox)
end

---------------------------------------------------------------------------
-- Tab 3/4: Living / Undead combat (shared builder)
---------------------------------------------------------------------------
local function build_combat_tab(cfg, prefix)
    local vbox = Gui.vbox()

    local p = prefix  -- "" for living, "undead_" for undead

    vbox:add(Gui.section_header("Combat Settings"))

    add_combo(vbox, "Attacking Stance:", p .. "attack_stance", cfg, STANCE_OPTIONS_ATK)
    add_combo(vbox, "Defending Stance:", p .. "defending_stance", cfg, STANCE_OPTIONS_DEF)

    vbox:add(Gui.separator())

    -- Setup Attacks
    add_attack_row(vbox, "Setup Attack 1", p .. "setup_attack", SETUP_ATTACK_OPTIONS,
        p .. "setup_attack_stam_min", p .. "setup_attack_man_min",
        p .. "setup_attack_enemy_min", p .. "setup_attack_enemy_max", cfg)
    add_attack_row(vbox, "Setup Attack 2", p .. "setup_attack2", SETUP_ATTACK_OPTIONS,
        p .. "setup_attack2_stam_min", p .. "setup_attack2_man_min",
        p .. "setup_attack2_enemy_min", p .. "setup_attack2_enemy_max", cfg)

    vbox:add(Gui.separator())

    -- Special Attacks
    add_attack_row(vbox, "Special Attack 1", p .. "special_attack", SPECIAL_ATTACK_OPTIONS,
        p .. "special_attack_stam_min", p .. "special_attack_man_min",
        p .. "special_attack_enemy_min", p .. "special_attack_enemy_max", cfg)
    add_attack_row(vbox, "Special Attack 2", p .. "special_attack2", SPECIAL_ATTACK_OPTIONS,
        p .. "special_attack2_stam_min", p .. "special_attack2_man_min",
        p .. "special_attack2_enemy_min", p .. "special_attack2_enemy_max", cfg)

    vbox:add(Gui.separator())

    -- AOE Attacks
    add_attack_row(vbox, "AOE Attack 1", p .. "aoe_attack", AOE_ATTACK_OPTIONS,
        p .. "aoe_attack_stam_min", p .. "aoe_attack_man_min",
        p .. "aoe_attack_enemy_min", p .. "aoe_attack_enemy_max", cfg)
    add_attack_row(vbox, "AOE Attack 2", p .. "aoe_attack2", AOE_ATTACK_OPTIONS,
        p .. "aoe_attack2_stam_min", p .. "aoe_attack2_man_min",
        p .. "aoe_attack2_enemy_min", p .. "aoe_attack2_enemy_max", cfg)

    vbox:add(Gui.separator())

    -- Assaults
    add_attack_row(vbox, "Assault 1", p .. "assault", ASSAULT_OPTIONS,
        p .. "assault_stam_min", p .. "assault_man_min",
        p .. "assault_enemy_min", p .. "assault_enemy_max", cfg)
    add_attack_row(vbox, "Assault 2", p .. "assault2", ASSAULT_OPTIONS,
        p .. "assault2_stam_min", p .. "assault2_man_min",
        p .. "assault2_enemy_min", p .. "assault2_enemy_max", cfg)

    vbox:add(Gui.separator())
    vbox:add(Gui.section_header("Spell Settings"))

    -- Spell Openers
    add_spell_row(vbox, "Spell Opener 1",
        p .. "spell_opener",
        p .. "spell_opener_stam_min", p .. "spell_opener_man_min",
        p .. "spell_opener_enemy_min", p .. "spell_opener_enemy_max",
        p .. "spell_opener_warding", p .. "spell_opener_channel",
        p .. "spell_opener_evoke", p .. "spell_opener_open_cast", cfg)
    add_spell_row(vbox, "Spell Opener 2",
        p .. "spell_opener2",
        p .. "spell_opener2_stam_min", p .. "spell_opener2_man_min",
        p .. "spell_opener2_enemy_min", p .. "spell_opener2_enemy_max",
        p .. "spell_opener2_warding", p .. "spell_opener2_channel",
        p .. "spell_opener2_evoke", p .. "spell_opener2_open_cast", cfg)

    vbox:add(Gui.separator())

    -- Attack Spells 1-5
    local spell_suffixes = { "", "2", "3", "4", "5" }
    for i, sfx in ipairs(spell_suffixes) do
        add_spell_row(vbox, "Attack Spell " .. i,
            p .. "attack_spell" .. sfx,
            p .. "attack_spell" .. sfx .. "_stam_min", p .. "attack_spell" .. sfx .. "_man_min",
            p .. "attack_spell" .. sfx .. "_enemy_min", p .. "attack_spell" .. sfx .. "_enemy_max",
            p .. "attack_spell" .. sfx .. "_warding", p .. "attack_spell" .. sfx .. "_channel",
            p .. "attack_spell" .. sfx .. "_evoke", p .. "attack_spell" .. sfx .. "_open_cast", cfg)
    end

    return Gui.scroll(vbox)
end

---------------------------------------------------------------------------
-- Tab 5: Gemstones
---------------------------------------------------------------------------
local function build_gemstones_tab(cfg)
    local vbox = Gui.vbox()

    vbox:add(Gui.section_header("Gemstone Settings"))

    add_gemstone_row(vbox, "Arcane Aegis", "gemstone_arcane_aegis", {
        { label = "Mana Threshold:", key = "activate_arcane_aegis_mana_if" },
    }, cfg)

    add_gemstone_row(vbox, "Arcanist's Ascendancy", "gemstone_arcanists_ascendancy", {
        { label = "Enemy Threshold:", key = "activate_arcanists_ascendancy_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Arcanist's Blade", "gemstone_arcanists_blade", {
        { label = "Enemy Threshold:", key = "activate_arcanists_blade_enemy_if" },
        { label = "Mana Threshold:", key = "activate_arcanists_blade_mana_if" },
        { label = "Stamina Threshold:", key = "activate_arcanists_blade_stamina_if" },
    }, cfg)

    add_gemstone_row(vbox, "Arcanist's Will", "gemstone_arcanists_will", {
        { label = "Enemy Threshold:", key = "activate_arcanists_will_enemy_if" },
        { label = "Mana Threshold:", key = "activate_arcanists_will_mana_if" },
        { label = "Stamina Threshold:", key = "activate_arcanists_will_stamina_if" },
    }, cfg)

    add_gemstone_row(vbox, "Blood Boil", "gemstone_blood_boil", {
        { label = "Enemy Threshold:", key = "activate_blood_boil_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Blood Siphon", "gemstone_blood_siphon", {
        { label = "Enemy Threshold:", key = "activate_blood_siphon_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Blood Wellspring", "gemstone_blood_wellspring", {
        { label = "Health Threshold:", key = "activate_blood_wellspring_health_if" },
    }, cfg)

    add_gemstone_row(vbox, "Evanescent Possession", "gemstone_evanescent_possession", {
        { label = "Enemy Threshold:", key = "activate_evanescent_possession_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Force of Will", "gemstone_force_of_will", {}, cfg)

    add_gemstone_row(vbox, "Geomancer's Spite", "gemstone_geomancers_spite", {
        { label = "Enemy Threshold:", key = "activate_geomancers_spite_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Mana Shield", "gemstone_mana_shield", {
        { label = "Mana Threshold:", key = "activate_mana_shield_mana_if" },
    }, cfg)

    add_gemstone_row(vbox, "Mana Wellspring", "gemstone_mana_wellspring", {
        { label = "Mana Threshold:", key = "activate_mana_wellspring_mana_if" },
    }, cfg)

    add_gemstone_row(vbox, "Reckless Precision", "gemstone_reckless_precision", {
        { label = "Enemy Threshold:", key = "activate_reckless_precision_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Spellblade's Fury", "gemstone_spellblades_fury", {
        { label = "Enemy Threshold:", key = "activate_spellblades_fury_enemy_if" },
        { label = "Mana Threshold:", key = "activate_spellblades_fury_mana_if" },
    }, cfg)

    add_gemstone_row(vbox, "Spirit Wellspring", "gemstone_spirit_wellspring", {
        { label = "Spirit Threshold:", key = "activate_spirit_wellspring_spirit_if" },
    }, cfg)

    add_gemstone_row(vbox, "Unearthly Chains", "gemstone_unearthly_chains", {
        { label = "Enemy Threshold:", key = "activate_unearthly_chains_enemy_if" },
    }, cfg)

    add_gemstone_row(vbox, "Witchhunter's Ascendancy", "gemstone_witchhunters_ascendancy", {
        { label = "Enemy Threshold:", key = "activate_witchhunters_ascendancy_enemy_if" },
    }, cfg)

    return Gui.scroll(vbox)
end

---------------------------------------------------------------------------
-- Save: iterate all tracked widgets, write back to cfg
---------------------------------------------------------------------------
local function save_all(cfg)
    for key, entry in pairs(widgets) do
        if entry.type == "checkbox" then
            cfg.set(key, entry.widget:get_checked())
        elseif entry.type == "input" then
            cfg.set(key, entry.widget:get_text())
        elseif entry.type == "combo" then
            cfg.set(key, entry.widget:get_text())
        end
    end
    cfg.save()
    respond("[osacombat] Settings saved")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Show the OSACombat setup window.
-- @param cfg  config module with cfg.get(key), cfg.set(key, val), cfg.save(), cfg.get_bool(key)
function M.show_setup(cfg)
    if win then
        win:close()
        win = nil
    end

    -- Reset widget tracking
    widgets = {}

    win = Gui.window("OSACombat Setup", { width = 1100, height = 800, resizable = true })

    -- Build tabs
    local tabs = Gui.tab_bar({ "General", "Support", "Living", "Undead", "Gemstones" })

    tabs:set_tab_content(1, build_general_tab(cfg))
    tabs:set_tab_content(2, build_support_tab(cfg))
    tabs:set_tab_content(3, build_combat_tab(cfg, ""))
    tabs:set_tab_content(4, build_combat_tab(cfg, "undead_"))
    tabs:set_tab_content(5, build_gemstones_tab(cfg))

    -- Bottom buttons
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save")
    save_btn:on_click(function()
        save_all(cfg)
    end)
    btn_row:add(save_btn)

    local close_btn = Gui.button("Close")
    close_btn:on_click(function()
        win:close()
        win = nil
    end)
    btn_row:add(close_btn)

    -- Root layout
    local root = Gui.vbox()
    root:add(tabs)
    root:add(Gui.separator())
    root:add(btn_row)

    win:set_root(root)
    win:on_close(function()
        win = nil
    end)
    win:show()
    Gui.wait(win, "close")
end

--- Close the setup window if open.
function M.close()
    if win then
        win:close()
        win = nil
    end
end

return M
