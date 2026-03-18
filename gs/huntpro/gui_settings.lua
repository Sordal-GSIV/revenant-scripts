-- huntpro/gui_settings.lua — Gui.* setup window for huntpro settings
-- @revenant-script
-- @lic-certified: complete 2026-03-18

local GuiSettings = {}

local Config = require("gs.huntpro.config")

---------------------------------------------------------------------------
-- Build and show settings window
---------------------------------------------------------------------------
function GuiSettings.show()
    local settings = Config.load()

    local win = Gui.window("Huntpro Settings", { width = 600, height = 700, resizable = true })
    local tabs = Gui.side_tab_bar(
        {"General", "Combat", "Spells", "Society", "Group", "Bounty", "Advanced"},
        { tab_width = 120 }
    )

    -- ===== General Tab =====
    local gen = Gui.scroll(Gui.vbox())
    local gen_box = Gui.vbox()

    gen_box:add(Gui.section_header("General Settings"))

    -- Loot script
    local loot_input = Gui.input({ text = settings.loot_script or "eloot", placeholder = "eloot" })
    local loot_row = Gui.hbox()
    loot_row:add(Gui.label("Loot Script:"))
    loot_row:add(loot_input)
    gen_box:add(loot_row)

    -- Clean loot script
    local cloot_input = Gui.input({ text = settings.cleanloot_script or "0", placeholder = "same as loot" })
    local cloot_row = Gui.hbox()
    cloot_row:add(Gui.label("Cleanup Loot Script:"))
    cloot_row:add(cloot_input)
    gen_box:add(cloot_row)

    -- Rest room
    local rest_input = Gui.input({ text = settings.rest_room or "0", placeholder = "room ID or 0" })
    local rest_row = Gui.hbox()
    rest_row:add(Gui.label("Rest Room:"))
    rest_row:add(rest_input)
    gen_box:add(rest_row)

    gen_box:add(Gui.separator())

    -- Toggles
    local cleanup_cb = Gui.checkbox("Combat Cleanup on Return", settings.combat_cleanup ~= "0")
    gen_box:add(cleanup_cb)

    local fried_cb = Gui.checkbox("Hunt While Fried (mind full)", settings.hunt_while_fried ~= "0")
    gen_box:add(fried_cb)

    local meditate_cb = Gui.checkbox("Meditate After Hunt", settings.meditate ~= "0")
    gen_box:add(meditate_cb)

    local taxi_cb = Gui.checkbox("Taxi Mode (go to zone then stop)", settings.taxi ~= "0")
    gen_box:add(taxi_cb)

    gen_box:add(Gui.separator())
    gen_box:add(Gui.section_header("Thresholds"))

    local enc_input = Gui.input({ text = tostring(settings.value_encumbrance or 50), placeholder = "50" })
    local enc_row = Gui.hbox()
    enc_row:add(Gui.label("Encumbrance %:"))
    enc_row:add(enc_input)
    gen_box:add(enc_row)

    local stam_input = Gui.input({ text = tostring(settings.value_stamina or 10), placeholder = "10" })
    local stam_row = Gui.hbox()
    stam_row:add(Gui.label("Stamina %:"))
    stam_row:add(stam_input)
    gen_box:add(stam_row)

    local disable_enc_cb = Gui.checkbox("Disable Encumbrance Check", settings.disable_encumbrance ~= "0")
    gen_box:add(disable_enc_cb)
    local disable_stam_cb = Gui.checkbox("Disable Stamina Check", settings.disable_stamina ~= "0")
    gen_box:add(disable_stam_cb)
    local disable_mana_cb = Gui.checkbox("Disable Mana Check", settings.disable_mana ~= "0")
    gen_box:add(disable_mana_cb)

    gen:set_root(gen_box)
    tabs:set_tab_content(1, gen)

    -- ===== Combat Tab =====
    local cbt = Gui.scroll(Gui.vbox())
    local cbt_box = Gui.vbox()

    cbt_box:add(Gui.section_header("Stance"))
    local off_cb = Gui.checkbox("Stay Offensive (never stance guard)", settings.stay_offensive ~= "0")
    cbt_box:add(off_cb)

    local def_input = Gui.input({ text = settings.defensive_stance or "guarded", placeholder = "guarded" })
    local def_row = Gui.hbox()
    def_row:add(Gui.label("Defensive Stance:"))
    def_row:add(def_input)
    cbt_box:add(def_row)

    local off_input = Gui.input({ text = settings.offensive_stance or "offensive", placeholder = "offensive" })
    local off_row = Gui.hbox()
    off_row:add(Gui.label("Offensive Stance:"))
    off_row:add(off_input)
    cbt_box:add(off_row)

    cbt_box:add(Gui.separator())
    cbt_box:add(Gui.section_header("Weapon & Shield"))

    local attune_input = Gui.editable_combo({
        text = settings.weapon_attune or "0",
        hint = "auto-detected",
        options = {"0", "brawling", "blunt", "edged", "polearm", "ranged", "2hw"}
    })
    local att_row = Gui.hbox()
    att_row:add(Gui.label("Weapon Attune:"))
    att_row:add(attune_input)
    cbt_box:add(att_row)

    local no_shield_cb = Gui.checkbox("Disable Shield Techniques", settings.no_shield_control ~= "0")
    cbt_box:add(no_shield_cb)
    local no_weapon_cb = Gui.checkbox("Disable Weapon Techniques", settings.no_weapon_control ~= "0")
    cbt_box:add(no_weapon_cb)
    local no_mstrike_cb = Gui.checkbox("Disable MStrike", settings.no_mstrike_control ~= "0")
    cbt_box:add(no_mstrike_cb)
    local no_cc_cb = Gui.checkbox("Disable Crowd Control", settings.no_crowd_control ~= "0")
    cbt_box:add(no_cc_cb)
    local no_cman_cb = Gui.checkbox("Disable CMan Techniques", settings.no_cman_control ~= "0")
    cbt_box:add(no_cman_cb)

    cbt_box:add(Gui.separator())
    cbt_box:add(Gui.section_header("Equipment Detection"))

    local rh_input = Gui.input({ text = settings.right_hand_detect or "0", placeholder = "noun or 0" })
    local rh_row = Gui.hbox()
    rh_row:add(Gui.label("Right Hand Item:"))
    rh_row:add(rh_input)
    cbt_box:add(rh_row)

    local lh_input = Gui.input({ text = settings.left_hand_detect or "0", placeholder = "noun or 0" })
    local lh_row = Gui.hbox()
    lh_row:add(Gui.label("Left Hand Item:"))
    lh_row:add(lh_input)
    cbt_box:add(lh_row)

    local no_cock_cb = Gui.checkbox("Disable Auto-Cock (ranged)", settings.no_cock ~= "0")
    cbt_box:add(no_cock_cb)

    cbt_box:add(Gui.separator())
    cbt_box:add(Gui.section_header("Targeting"))

    local ftarget_input = Gui.input({ text = settings.force_target or "0", placeholder = "creature name or 0" })
    local ft_row = Gui.hbox()
    ft_row:add(Gui.label("Force Target:"))
    ft_row:add(ftarget_input)
    cbt_box:add(ft_row)

    local flee_input = Gui.input({ text = settings.flee or "0", placeholder = "mob count or 0" })
    local flee_row = Gui.hbox()
    flee_row:add(Gui.label("Flee at # Mobs:"))
    flee_row:add(flee_input)
    cbt_box:add(flee_row)

    local skip_input = Gui.input({ text = settings.force_skip_list or "0", placeholder = "noun to skip" })
    local skip_row = Gui.hbox()
    skip_row:add(Gui.label("Skip Creature 1:"))
    skip_row:add(skip_input)
    cbt_box:add(skip_row)

    cbt:set_root(cbt_box)
    tabs:set_tab_content(2, cbt)

    -- ===== Spells Tab =====
    local spl = Gui.scroll(Gui.vbox())
    local spl_box = Gui.vbox()

    spl_box:add(Gui.section_header("Spell Defaults"))

    local spell_input = Gui.input({ text = settings.spell_default or "0", placeholder = "spell # or 0 for auto" })
    local sp_row = Gui.hbox()
    sp_row:add(Gui.label("Default Spell:"))
    sp_row:add(spell_input)
    spl_box:add(sp_row)

    local evoke_cb = Gui.checkbox("Default to Evoke (bolt spells)", settings.evoke_default ~= "0")
    spl_box:add(evoke_cb)

    local no_waggle_cb = Gui.checkbox("Disable End-Hunt Waggle", settings.no_waggle ~= "0")
    spl_box:add(no_waggle_cb)

    spl_box:add(Gui.separator())
    spl_box:add(Gui.section_header("Spell Upkeep"))

    local upkeep_spells = {
        {key = "upkeep140",  label = "140 - Spirit Defense"},
        {key = "upkeep240",  label = "240 - Mana Spear"},
        {key = "upkeep515",  label = "515 - Rapid Fire"},
        {key = "upkeep506",  label = "506 - Animate Dead"},
        {key = "upkeep919",  label = "919 - Phase"},
        {key = "upkeep1035", label = "1035 - Bless Item"},
        {key = "upkeep650",  label = "650 - Song of Tonis"},
    }

    local upkeep_cbs = {}
    for _, sp in ipairs(upkeep_spells) do
        local cb = Gui.checkbox(sp.label, settings[sp.key] ~= "0")
        upkeep_cbs[sp.key] = cb
        spl_box:add(cb)
    end

    spl_box:add(Gui.separator())
    spl_box:add(Gui.section_header("Style 9 Options"))

    local arcane_cb = Gui.checkbox("Use Arcane Blast at low mana", settings.style9_arcaneblast ~= "0")
    spl_box:add(arcane_cb)
    local arcane_cs_cb = Gui.checkbox("Arcane CS mode", settings.style9_arcanecs ~= "0")
    spl_box:add(arcane_cs_cb)
    local noquartz_cb = Gui.checkbox("Disable Quartz Orb", settings.noquartz ~= "0")
    spl_box:add(noquartz_cb)
    local wands_cb = Gui.checkbox("Use Wands at Low Mana", settings.use_wands ~= "0")
    spl_box:add(wands_cb)

    local deadwand_input = Gui.input({ text = settings.dead_wands or "0", placeholder = "container noun" })
    local dw_row = Gui.hbox()
    dw_row:add(Gui.label("Dead Wand Container:"))
    dw_row:add(deadwand_input)
    spl_box:add(dw_row)

    spl:set_root(spl_box)
    tabs:set_tab_content(3, spl)

    -- ===== Society Tab =====
    local soc = Gui.scroll(Gui.vbox())
    local soc_box = Gui.vbox()

    soc_box:add(Gui.section_header("Society"))

    local soc_combo = Gui.editable_combo({
        text = settings.character_society or "0",
        hint = "auto-detected",
        options = {"0", "Voln", "Col", "Gos", "None"}
    })
    local soc_row = Gui.hbox()
    soc_row:add(Gui.label("Society:"))
    soc_row:add(soc_combo)
    soc_box:add(soc_row)

    local no_soc_cb = Gui.checkbox("Disable All Society Abilities", settings.no_society ~= "0")
    soc_box:add(no_soc_cb)

    local no_stun_cb = Gui.checkbox("Disable Stun Abilities", settings.no_stun ~= "0")
    soc_box:add(no_stun_cb)

    soc_box:add(Gui.separator())
    soc_box:add(Gui.section_header("Voln Options"))

    local fog_cb = Gui.checkbox("Use Voln Fog Return", settings.voln_fog ~= "0")
    soc_box:add(fog_cb)
    local deed_cb = Gui.checkbox("Deed Mana (Symbol of Mana)", settings.deedmana ~= "0")
    soc_box:add(deed_cb)
    local fog130_cb = Gui.checkbox("Use Spirit Guide (130) for Return", settings.fog_130 ~= "0")
    soc_box:add(fog130_cb)

    soc_box:add(Gui.separator())
    soc_box:add(Gui.section_header("Council of Light Options"))
    local wrack_cb = Gui.checkbox("Use Wrack for Mana", settings.wrack ~= "0")
    soc_box:add(wrack_cb)

    soc_box:add(Gui.separator())
    soc_box:add(Gui.section_header("Herbs"))
    local herb_cb = Gui.checkbox("Use Herbs in Combat", settings.use_herbs ~= "0")
    soc_box:add(herb_cb)
    local no_herb_cb = Gui.checkbox("No Herbs (rely on healing)", settings.no_herbs ~= "0")
    soc_box:add(no_herb_cb)
    local no_cleanup_herb_cb = Gui.checkbox("Skip Herb Cleanup After Hunt", settings.nocleanupherbs ~= "0")
    soc_box:add(no_cleanup_herb_cb)

    soc:set_root(soc_box)
    tabs:set_tab_content(4, soc)

    -- ===== Group Tab =====
    local grp = Gui.scroll(Gui.vbox())
    local grp_box = Gui.vbox()

    grp_box:add(Gui.section_header("Group Leader"))

    local leader_input = Gui.input({ text = settings.leader or "0", placeholder = "character name or 0" })
    local ldr_row = Gui.hbox()
    ldr_row:add(Gui.label("Leader Name:"))
    ldr_row:add(leader_input)
    grp_box:add(ldr_row)

    grp_box:add(Gui.separator())
    grp_box:add(Gui.section_header("Group Members (up to 9)"))

    local member_inputs = {}
    for i = 1, 9 do
        local keys = {"group_one", "group_two", "group_three", "group_four", "group_five",
                       "group_six", "group_seven", "group_eight", "group_nine"}
        local inp = Gui.input({ text = settings[keys[i]] or "0", placeholder = "name or 0" })
        member_inputs[i] = inp
        local row = Gui.hbox()
        row:add(Gui.label("Member " .. i .. ":"))
        row:add(inp)
        grp_box:add(row)
    end

    grp_box:add(Gui.separator())
    local quiet_cb = Gui.checkbox("Quiet Mode (no whispers)", settings.group_quiet ~= "0")
    grp_box:add(quiet_cb)
    local peace_cb = Gui.checkbox("Peace Mode", settings.group_peace ~= "0")
    grp_box:add(peace_cb)
    local share_cb = Gui.checkbox("Share Mana", settings.group_sharemana ~= "0")
    grp_box:add(share_cb)

    grp:set_root(grp_box)
    tabs:set_tab_content(5, grp)

    -- ===== Bounty Tab =====
    local bnt = Gui.scroll(Gui.vbox())
    local bnt_box = Gui.vbox()

    bnt_box:add(Gui.section_header("Bounty Options"))

    local no_herb_bounty_cb = Gui.checkbox("Skip Herb Bounties", settings.bounty_noherb ~= "0")
    bnt_box:add(no_herb_bounty_cb)
    local no_skin_bounty_cb = Gui.checkbox("Skip Skin Bounties", settings.bounty_noskin ~= "0")
    bnt_box:add(no_skin_bounty_cb)
    local no_bandit_cb = Gui.checkbox("Skip Bandit Bounties", settings.bounty_nobandit ~= "0")
    bnt_box:add(no_bandit_cb)
    local no_group_bounty_cb = Gui.checkbox("Skip Group Bounties", settings.bounty_nogroup ~= "0")
    bnt_box:add(no_group_bounty_cb)
    local lite_cb = Gui.checkbox("Bounty Lite Mode", settings.bounty_lite ~= "0")
    bnt_box:add(lite_cb)

    bnt:set_root(bnt_box)
    tabs:set_tab_content(6, bnt)

    -- ===== Advanced Tab =====
    local adv = Gui.scroll(Gui.vbox())
    local adv_box = Gui.vbox()

    adv_box:add(Gui.section_header("Companion Scripts"))

    local s1_input = Gui.input({ text = settings.run_script or "0", placeholder = "script name" })
    local s1_row = Gui.hbox()
    s1_row:add(Gui.label("Script 1:"))
    s1_row:add(s1_input)
    adv_box:add(s1_row)

    local s2_input = Gui.input({ text = settings.run_script2 or "0", placeholder = "script name" })
    local s2_row = Gui.hbox()
    s2_row:add(Gui.label("Script 2:"))
    s2_row:add(s2_input)
    adv_box:add(s2_row)

    local s3_input = Gui.input({ text = settings.run_script3 or "0", placeholder = "script name" })
    local s3_row = Gui.hbox()
    s3_row:add(Gui.label("Script 3:"))
    s3_row:add(s3_input)
    adv_box:add(s3_row)

    adv_box:add(Gui.separator())
    adv_box:add(Gui.section_header("Boosts"))

    local boost_long_cb = Gui.checkbox("Boost Long (use at saturation)", settings.boost_long ~= "0")
    adv_box:add(boost_long_cb)

    local boost_loot_combo = Gui.editable_combo({
        text = settings.boost_loot or "0",
        hint = "off",
        options = {"0", "minor", "major"}
    })
    local bl_row = Gui.hbox()
    bl_row:add(Gui.label("Boost Loot:"))
    bl_row:add(boost_loot_combo)
    adv_box:add(bl_row)

    adv_box:add(Gui.separator())
    adv_box:add(Gui.section_header("Debug"))

    local debug_cb = Gui.checkbox("Debug Mode", settings.qc_debug ~= "0")
    adv_box:add(debug_cb)
    local test_cb = Gui.checkbox("QC Testing Mode", settings.qc_testing ~= "0")
    adv_box:add(test_cb)

    adv_box:add(Gui.separator())

    -- Save button
    local save_btn = Gui.button("Save All Settings")
    save_btn:on_click(function()
        -- General
        settings.loot_script         = loot_input:get_text()
        settings.cleanloot_script    = cloot_input:get_text()
        settings.rest_room           = rest_input:get_text()
        settings.combat_cleanup      = cleanup_cb:get_checked() and "1" or "0"
        settings.hunt_while_fried    = fried_cb:get_checked() and "1" or "0"
        settings.meditate            = meditate_cb:get_checked() and "1" or "0"
        settings.taxi                = taxi_cb:get_checked() and "1" or "0"
        -- Thresholds
        settings.value_encumbrance   = enc_input:get_text()
        settings.value_stamina       = stam_input:get_text()
        settings.disable_encumbrance = disable_enc_cb:get_checked() and "1" or "0"
        settings.disable_stamina     = disable_stam_cb:get_checked() and "1" or "0"
        settings.disable_mana        = disable_mana_cb:get_checked() and "1" or "0"
        -- Combat / Stance
        settings.stay_offensive      = off_cb:get_checked() and "1" or "0"
        settings.defensive_stance    = def_input:get_text()
        settings.offensive_stance    = off_input:get_text()
        settings.weapon_attune       = attune_input:get_text()
        settings.no_shield_control   = no_shield_cb:get_checked() and "1" or "0"
        settings.no_weapon_control   = no_weapon_cb:get_checked() and "1" or "0"
        settings.no_mstrike_control  = no_mstrike_cb:get_checked() and "1" or "0"
        settings.no_crowd_control    = no_cc_cb:get_checked() and "1" or "0"
        settings.no_cman_control     = no_cman_cb:get_checked() and "1" or "0"
        settings.right_hand_detect   = rh_input:get_text()
        settings.left_hand_detect    = lh_input:get_text()
        settings.no_cock             = no_cock_cb:get_checked() and "1" or "0"
        settings.force_target        = ftarget_input:get_text()
        settings.flee                = flee_input:get_text()
        settings.force_skip_list     = skip_input:get_text()
        -- Spells
        settings.spell_default       = spell_input:get_text()
        settings.evoke_default       = evoke_cb:get_checked() and "1" or "0"
        settings.no_waggle           = no_waggle_cb:get_checked() and "1" or "0"
        for _, sp in ipairs(upkeep_spells) do
            settings[sp.key] = upkeep_cbs[sp.key]:get_checked() and "1" or "0"
        end
        settings.style9_arcaneblast  = arcane_cb:get_checked() and "1" or "0"
        settings.style9_arcanecs     = arcane_cs_cb:get_checked() and "1" or "0"
        settings.noquartz            = noquartz_cb:get_checked() and "1" or "0"
        settings.use_wands           = wands_cb:get_checked() and "1" or "0"
        settings.dead_wands          = deadwand_input:get_text()
        -- Society
        settings.character_society   = soc_combo:get_text()
        settings.no_society          = no_soc_cb:get_checked() and "1" or "0"
        settings.no_stun             = no_stun_cb:get_checked() and "1" or "0"
        settings.voln_fog            = fog_cb:get_checked() and "1" or "0"
        settings.deedmana            = deed_cb:get_checked() and "1" or "0"
        settings.fog_130             = fog130_cb:get_checked() and "1" or "0"
        settings.wrack               = wrack_cb:get_checked() and "1" or "0"
        settings.use_herbs           = herb_cb:get_checked() and "1" or "0"
        settings.no_herbs            = no_herb_cb:get_checked() and "1" or "0"
        settings.nocleanupherbs      = no_cleanup_herb_cb:get_checked() and "1" or "0"
        -- Group
        settings.leader              = leader_input:get_text()
        local group_keys = {"group_one","group_two","group_three","group_four","group_five",
                            "group_six","group_seven","group_eight","group_nine"}
        for i, key in ipairs(group_keys) do
            settings[key] = member_inputs[i]:get_text()
        end
        settings.group_quiet         = quiet_cb:get_checked() and "1" or "0"
        settings.group_peace         = peace_cb:get_checked() and "1" or "0"
        settings.group_sharemana     = share_cb:get_checked() and "1" or "0"
        -- Bounty
        settings.bounty_noherb       = no_herb_bounty_cb:get_checked() and "1" or "0"
        settings.bounty_noskin       = no_skin_bounty_cb:get_checked() and "1" or "0"
        settings.bounty_nobandit     = no_bandit_cb:get_checked() and "1" or "0"
        settings.bounty_nogroup      = no_group_bounty_cb:get_checked() and "1" or "0"
        settings.bounty_lite         = lite_cb:get_checked() and "1" or "0"
        -- Advanced
        settings.run_script          = s1_input:get_text()
        settings.run_script2         = s2_input:get_text()
        settings.run_script3         = s3_input:get_text()
        settings.boost_long          = boost_long_cb:get_checked() and "1" or "0"
        settings.boost_loot          = boost_loot_combo:get_text()
        settings.qc_debug            = debug_cb:get_checked() and "1" or "0"
        settings.qc_testing          = test_cb:get_checked() and "1" or "0"

        Config.save_all(settings)
        respond(Char.name .. ", all huntpro settings saved.")
    end)
    adv_box:add(save_btn)

    -- Reset button
    local reset_btn = Gui.button("Reset to Defaults")
    reset_btn:on_click(function()
        Config.reset()
        respond(Char.name .. ", all huntpro settings reset to defaults. Please restart.")
        win:close()
    end)
    adv_box:add(reset_btn)

    adv:set_root(adv_box)
    tabs:set_tab_content(7, adv)

    win:set_root(tabs)
    win:show()
    Gui.wait(win, "close")
end

return GuiSettings
