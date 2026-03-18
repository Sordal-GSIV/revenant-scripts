--- Bigshot GUI Settings — full tabbed settings interface
-- Port of Setup class from bigshot.lic v5.12.1
-- Uses Revenant Gui widget system (Gui.window, Gui.tab_bar, etc.)

local config = require("config")

local M = {}

---------------------------------------------------------------------------
-- Helper: create a labeled input row
---------------------------------------------------------------------------
local function labeled_input(parent, label_text, value, tooltip)
    local row = Gui.hbox()
    local lbl = Gui.label(label_text)
    row:add(lbl)
    local inp = Gui.input({ text = tostring(value or ""), placeholder = tooltip or "" })
    row:add(inp)
    parent:add(row)
    return inp
end

local function labeled_checkbox(parent, label_text, checked, tooltip)
    local chk = Gui.checkbox(label_text, checked or false)
    parent:add(chk)
    return chk
end

local function section(parent, title)
    parent:add(Gui.section_header(title))
end

---------------------------------------------------------------------------
-- Build Resting Tab
---------------------------------------------------------------------------
local function build_resting_tab(state)
    local root = Gui.scroll(Gui.vbox())
    local vbox = Gui.vbox()

    section(vbox, "Return Path")
    local waypoints = labeled_input(vbox, "Return Waypoint IDs:", state.return_waypoint_ids or "", "Comma-separated room IDs")
    local rest_room = labeled_input(vbox, "Resting Room ID:", state.resting_room_id or "", "Room ID or UID (e.g. u7000)")

    section(vbox, "Pre-Rest Commands")
    local rest_cmds = Gui.input({ text = table.concat(state.resting_commands or {}, "\n"), placeholder = "One command per line" })
    vbox:add(rest_cmds)

    section(vbox, "Resting Scripts")
    local rest_scripts = Gui.input({ text = table.concat(state.resting_scripts or {}, "\n"), placeholder = "One script per line" })
    vbox:add(rest_scripts)

    section(vbox, "Fog Return")
    local fog_combo = Gui.editable_combo({
        text = tostring(state.fog_return or "0"),
        hint = "Fog type",
        options = {"0 - None", "1 - Spirit Guide (130)", "2 - Voln Symbol of Return", "3 - Traveler's Song (1020)", "4 - GoS Sigil of Escape", "5 - Familiar Gate (930)", "6 - Custom"}
    })
    vbox:add(fog_combo)
    local custom_fog = labeled_input(vbox, "Custom Fog Commands:", state.custom_fog or "", "Comma-separated commands")
    local fog_optional = labeled_checkbox(vbox, "Fog only if wounded/encumbered", state.fog_optional)
    local fog_rift = labeled_checkbox(vbox, "Double-cast from Rift", state.fog_rift)

    section(vbox, "Rest Thresholds")
    local fried = labeled_input(vbox, "Fried at mind %:", state.fried or 100, "101 = never stop for mind")
    local overkill = labeled_input(vbox, "Overkill (extra kills):", state.overkill or "", "Blank = 0 extra")
    local lte_boost = labeled_input(vbox, "LTE Boosts to use:", state.lte_boost or "", "Blank = 0")
    local oom = labeled_input(vbox, "OOM at mana %:", state.oom or "", "Blank = ignore mana")
    local encumbered = labeled_input(vbox, "Encumbered at %:", state.encumbered or 101, "101 = ignore")
    local wounded_eval = labeled_input(vbox, "Wound eval:", state.wounded_eval or "", "Lua expression")
    local crushing_dread = labeled_input(vbox, "Crushing Dread level:", state.crushing_dread or "")
    local creeping_dread = labeled_input(vbox, "Creeping Dread level:", state.creeping_dread or "")
    local wot_poison = labeled_checkbox(vbox, "Rest on Wall of Thorns poison", state.wot_poison)
    local confusion = labeled_checkbox(vbox, "Rest on confusion", state.confusion)
    local box_in_hand = labeled_checkbox(vbox, "Rest if box in hand after looting", state.box_in_hand)

    root = Gui.scroll(vbox)

    return root, function()
        state.return_waypoint_ids = waypoints:get_text()
        state.resting_room_id = rest_room:get_text()
        state.resting_commands = config.parse_lines(rest_cmds:get_text())
        state.resting_scripts = config.parse_lines(rest_scripts:get_text())
        state.fog_return = fog_combo:get_text():match("^(%d+)") or "0"
        state.custom_fog = custom_fog:get_text()
        state.fog_optional = fog_optional:get_checked()
        state.fog_rift = fog_rift:get_checked()
        state.fried = config.parse_int(fried:get_text(), 100)
        state.overkill = overkill:get_text()
        state.lte_boost = lte_boost:get_text()
        state.oom = oom:get_text()
        state.encumbered = config.parse_int(encumbered:get_text(), 101)
        state.wounded_eval = wounded_eval:get_text()
        state.crushing_dread = crushing_dread:get_text()
        state.creeping_dread = creeping_dread:get_text()
        state.wot_poison = wot_poison:get_checked()
        state.confusion = confusion:get_checked()
        state.box_in_hand = box_in_hand:get_checked()
    end
end

---------------------------------------------------------------------------
-- Build Hunting Tab
---------------------------------------------------------------------------
local function build_hunting_tab(state)
    local vbox = Gui.vbox()

    section(vbox, "Hunting Area")
    local hunt_room = labeled_input(vbox, "Starting Room ID:", state.hunting_room_id or "", "Room ID or UID")
    local rally_rooms = labeled_input(vbox, "Rally Point IDs:", table.concat(state.rallypoint_room_ids or {}, ", "), "Comma-separated")
    local boundaries = labeled_input(vbox, "Boundary Room IDs:", table.concat(state.hunting_boundaries or {}, ", "), "Comma-separated")

    section(vbox, "Recovery Thresholds")
    local rest_exp = labeled_input(vbox, "Rest until mind %:", state.rest_till_exp or "", "Mind % to recover to")
    local rest_mana = labeled_input(vbox, "Rest until mana %:", state.rest_till_mana or "", "Mana % to recover to")
    local rest_spirit = labeled_input(vbox, "Rest until spirit:", state.rest_till_spirit or "", "Spirit amount")
    local rest_stam = labeled_input(vbox, "Rest until stamina %:", state.rest_till_percentstamina or "", "Stamina %")

    section(vbox, "Stances")
    local hunt_stance = labeled_input(vbox, "Hunting Stance:", state.hunting_stance or "", "offensive/defensive/10-100")
    local wander_stance = labeled_input(vbox, "Wander Stance:", state.wander_stance or "", "Stance while moving")
    local stand_stance = labeled_input(vbox, "Stand-up Stance:", state.stand_stance or "", "Stance when standing")

    section(vbox, "Pre-Hunt Commands")
    local hunt_prep = Gui.input({ text = table.concat(state.hunting_prep_commands or {}, "\n") })
    vbox:add(hunt_prep)

    section(vbox, "Hunting Scripts")
    local hunt_scripts = Gui.input({ text = table.concat(state.hunting_scripts or {}, "\n") })
    vbox:add(hunt_scripts)

    section(vbox, "Society Signs/Sigils/Symbols")
    local signs = labeled_input(vbox, "Signs:", table.concat(state.signs or {}, ", "), "Comma-separated spell numbers")

    section(vbox, "Loot & Wracking")
    local loot_script = labeled_input(vbox, "Loot Script:", state.loot_script or "eloot")
    local wracking = labeled_input(vbox, "Wracking Spirit:", state.wracking_spirit or "", "Min spirit for wracking")

    section(vbox, "Hunting Options")
    local priority = labeled_checkbox(vbox, "Priority targeting (highest priority first)", state.priority)
    local delay_loot = labeled_checkbox(vbox, "Delay looting until combat done", state.delay_loot)
    local troub = labeled_checkbox(vbox, "Troubadour's Rally (1040) for incapacitated", state.troubadours_rally)
    local sneaky = labeled_checkbox(vbox, "Sneaky hunting (autosneak)", state.sneaky_sneaky)
    local wrack_chk = labeled_checkbox(vbox, "Use Wracking/Power/Mana", state.use_wracking)
    local loot_stance_chk = labeled_checkbox(vbox, "Defensive stance before looting", state.loot_stance)
    local pull_chk = labeled_checkbox(vbox, "Pull group members to feet", state.pull)
    local deader_chk = labeled_checkbox(vbox, "Stop for dead group members", state.deader)
    local favor_chk = labeled_checkbox(vbox, "Check Voln favor before symbol use", state.check_favor)

    local root = Gui.scroll(vbox)

    return root, function()
        state.hunting_room_id = hunt_room:get_text()
        state.rallypoint_room_ids = config.parse_csv(rally_rooms:get_text())
        state.hunting_boundaries = config.parse_csv(boundaries:get_text())
        state.rest_till_exp = rest_exp:get_text()
        state.rest_till_mana = rest_mana:get_text()
        state.rest_till_spirit = rest_spirit:get_text()
        state.rest_till_percentstamina = rest_stam:get_text()
        state.hunting_stance = hunt_stance:get_text()
        state.wander_stance = wander_stance:get_text()
        state.stand_stance = stand_stance:get_text()
        state.hunting_prep_commands = config.parse_lines(hunt_prep:get_text())
        state.hunting_scripts = config.parse_lines(hunt_scripts:get_text())
        state.signs = config.parse_csv(signs:get_text())
        state.loot_script = loot_script:get_text()
        state.wracking_spirit = wracking:get_text()
        state.priority = priority:get_checked()
        state.delay_loot = delay_loot:get_checked()
        state.troubadours_rally = troub:get_checked()
        state.sneaky_sneaky = sneaky:get_checked()
        state.use_wracking = wrack_chk:get_checked()
        state.loot_stance = loot_stance_chk:get_checked()
        state.pull = pull_chk:get_checked()
        state.deader = deader_chk:get_checked()
        state.check_favor = favor_chk:get_checked()
    end
end

---------------------------------------------------------------------------
-- Build Attack Tab
---------------------------------------------------------------------------
local function build_attack_tab(state)
    local vbox = Gui.vbox()

    section(vbox, "Aiming")
    local ambush = labeled_input(vbox, "Ambush aim location:", state.ambush or "")
    local archery = labeled_input(vbox, "Archery aim location:", state.archery_aim or "")

    section(vbox, "Flee Settings")
    local flee_count = labeled_input(vbox, "Flee at enemy count:", state.flee_count or 100)
    local invalid_targets = labeled_input(vbox, "Invalid targets:", table.concat(state.invalid_targets or {}, ", "), "Comma-separated creature names")
    local always_flee = labeled_input(vbox, "Always flee from:", table.concat(state.always_flee_from or {}, ", "), "Comma-separated")
    local flee_msg = labeled_input(vbox, "Flee on message:", state.flee_message or "", "Pipe-separated patterns")

    section(vbox, "Movement")
    local wander_wait = labeled_input(vbox, "Wander wait (seconds):", state.wander_wait or 0.3)

    section(vbox, "Flee Options")
    local flee_clouds = labeled_checkbox(vbox, "Flee from clouds", state.flee_clouds)
    local flee_vines = labeled_checkbox(vbox, "Flee from vines", state.flee_vines)
    local flee_webs = labeled_checkbox(vbox, "Flee from webs", state.flee_webs)
    local flee_voids = labeled_checkbox(vbox, "Flee from voids", state.flee_voids)
    local lone_targets = labeled_checkbox(vbox, "Approach lone targets only", state.lone_targets_only)
    local weapon_react = labeled_checkbox(vbox, "Activate weapon reactions", state.weapon_reaction)
    local bless_chk = labeled_checkbox(vbox, "Stop hunt when bless runs out", state.bless)

    local root = Gui.scroll(vbox)

    return root, function()
        state.ambush = ambush:get_text()
        state.archery_aim = archery:get_text()
        state.flee_count = config.parse_int(flee_count:get_text(), 100)
        state.invalid_targets = config.parse_csv(invalid_targets:get_text())
        state.always_flee_from = config.parse_csv(always_flee:get_text())
        state.flee_message = flee_msg:get_text()
        state.wander_wait = config.parse_float(wander_wait:get_text(), 0.3)
        state.flee_clouds = flee_clouds:get_checked()
        state.flee_vines = flee_vines:get_checked()
        state.flee_webs = flee_webs:get_checked()
        state.flee_voids = flee_voids:get_checked()
        state.lone_targets_only = lone_targets:get_checked()
        state.weapon_reaction = weapon_react:get_checked()
        state.bless = bless_chk:get_checked()
    end
end

---------------------------------------------------------------------------
-- Build Commands Tab
---------------------------------------------------------------------------
local function build_commands_tab(state)
    local vbox = Gui.vbox()

    section(vbox, "Hunting Commands (A-J)")
    local cmd_inputs = {}
    local labels = {"A (default)", "B", "C", "D", "E", "F", "G", "H", "I", "J"}
    local keys = {"hunting_commands", "hunting_commands_b", "hunting_commands_c", "hunting_commands_d",
                  "hunting_commands_e", "hunting_commands_f", "hunting_commands_g", "hunting_commands_h",
                  "hunting_commands_i", "hunting_commands_j"}

    for i, label in ipairs(labels) do
        local val = state[keys[i]]
        local text = ""
        if type(val) == "table" then
            text = table.concat(val, ", ")
        elseif type(val) == "string" then
            text = val
        end
        cmd_inputs[i] = labeled_input(vbox, "Commands " .. label .. ":", text,
            "e.g. incant 903, kill(x5)")
    end

    section(vbox, "Special Commands")
    local disable_cmds = labeled_input(vbox, "Fried Commands (group):",
        type(state.disable_commands) == "table" and table.concat(state.disable_commands, ", ") or (state.disable_commands or ""))
    local quick_cmds = labeled_input(vbox, "Quick Commands:",
        type(state.quick_commands) == "table" and table.concat(state.quick_commands, ", ") or (state.quick_commands or ""))

    section(vbox, "Target Mapping")
    local targets = labeled_input(vbox, "Valid Targets:", state.targets or "",
        "creature(A), creature(B) or creature=a, creature=b")
    local qtargets = labeled_input(vbox, "Quickhunt Targets:", state.quickhunt_targets or "")

    local root = Gui.scroll(vbox)

    return root, function()
        for i, key in ipairs(keys) do
            state[key] = config.parse_commands(cmd_inputs[i]:get_text())
        end
        state.disable_commands = config.parse_commands(disable_cmds:get_text())
        state.quick_commands = config.parse_commands(quick_cmds:get_text())
        state.targets = targets:get_text()
        state.quickhunt_targets = qtargets:get_text()
    end
end

---------------------------------------------------------------------------
-- Build Misc Tab
---------------------------------------------------------------------------
local function build_misc_tab(state)
    local vbox = Gui.vbox()

    section(vbox, "Unarmed Combat (UAC)")
    local tier3 = labeled_input(vbox, "Tier 3 Attack:", state.tier3 or "")
    local aim = labeled_input(vbox, "Aim Locations:", state.aim or "", "Comma-separated body parts")
    local uac_smite = labeled_checkbox(vbox, "Use Voln Smite in UAC", state.uac_smite)
    local uac_mstrike = labeled_checkbox(vbox, "Prevent MStrike during unarmed", state.uac_mstrike)

    section(vbox, "Multi-Strike")
    local ms_stam_cd = labeled_input(vbox, "MStrike Stamina (cooldown):", state.mstrike_stamina_cooldown or "")
    local ms_stam_qs = labeled_input(vbox, "Quickstrike Stamina:", state.mstrike_stamina_quickstrike or "")
    local ms_mob = labeled_input(vbox, "MStrike mob count:", state.mstrike_mob or "", "Min enemies for unfocused")
    local ms_cd = labeled_checkbox(vbox, "MStrike during cooldown", state.mstrike_cooldown)
    local ms_qs = labeled_checkbox(vbox, "Use Quickstrike for MStrike", state.mstrike_quickstrike)

    section(vbox, "Ammo / Wands")
    local ammo_cont = labeled_input(vbox, "Ammo Container:", state.ammo_container or "")
    local ammo = labeled_input(vbox, "Ammo Noun:", state.ammo or "")
    local fresh_wand = labeled_input(vbox, "Fresh Wand Container:", state.fresh_wand_container or "")
    local dead_wand = labeled_input(vbox, "Dead Wand Container:", state.dead_wand_container or "")
    local wand_noun = labeled_input(vbox, "Wand Noun:", state.wand or "")
    local hide_ammo = labeled_checkbox(vbox, "Hide to pick up ammo", state.hide_for_ammo)
    local wand_oom = labeled_checkbox(vbox, "Use wands when OOM", state.wand_if_oom)

    section(vbox, "Multi-Account Group")
    local indep_travel = labeled_checkbox(vbox, "Independent travel", state.independent_travel)
    local indep_return = labeled_checkbox(vbox, "Independent return", state.independent_return)
    local ma_looter = labeled_input(vbox, "Designated Looter:", state.ma_looter or "")
    local never_loot = labeled_input(vbox, "Never Loot:", state.never_loot or "", "Comma-separated names")
    local random_loot = labeled_checkbox(vbox, "Random loot by encumbrance", state.random_loot)
    local quiet = labeled_checkbox(vbox, "Quiet followers", state.quiet_followers)
    local final_loot = labeled_checkbox(vbox, "Final room loot (leader)", state.final_loot)
    local group_deader = labeled_checkbox(vbox, "Stop for dead group members", state.group_deader)

    section(vbox, "Monitoring")
    local dms = labeled_checkbox(vbox, "Dead man switch", state.dead_man_switch)
    local depart = labeled_checkbox(vbox, "Auto-depart and rerun", state.depart_switch)
    local monitor = labeled_checkbox(vbox, "Monitor interactions", state.monitor_interaction)
    local ignore_disks = labeled_checkbox(vbox, "Ignore other player disks", state.ignore_disks)

    section(vbox, "Debug")
    local dbg_combat = labeled_checkbox(vbox, "Debug: Combat", state.debug_combat)
    local dbg_commands = labeled_checkbox(vbox, "Debug: Commands", state.debug_commands)
    local dbg_status = labeled_checkbox(vbox, "Debug: Status", state.debug_status)
    local dbg_system = labeled_checkbox(vbox, "Debug: System", state.debug_system)

    local root = Gui.scroll(vbox)

    return root, function()
        state.tier3 = tier3:get_text()
        state.aim = aim:get_text()
        state.uac_smite = uac_smite:get_checked()
        state.uac_mstrike = uac_mstrike:get_checked()
        state.mstrike_stamina_cooldown = ms_stam_cd:get_text()
        state.mstrike_stamina_quickstrike = ms_stam_qs:get_text()
        state.mstrike_mob = ms_mob:get_text()
        state.mstrike_cooldown = ms_cd:get_checked()
        state.mstrike_quickstrike = ms_qs:get_checked()
        state.ammo_container = ammo_cont:get_text()
        state.ammo = ammo:get_text()
        state.fresh_wand_container = fresh_wand:get_text()
        state.dead_wand_container = dead_wand:get_text()
        state.wand = wand_noun:get_text()
        state.hide_for_ammo = hide_ammo:get_checked()
        state.wand_if_oom = wand_oom:get_checked()
        state.independent_travel = indep_travel:get_checked()
        state.independent_return = indep_return:get_checked()
        state.ma_looter = ma_looter:get_text()
        state.never_loot = never_loot:get_text()
        state.random_loot = random_loot:get_checked()
        state.quiet_followers = quiet:get_checked()
        state.final_loot = final_loot:get_checked()
        state.group_deader = group_deader:get_checked()
        state.dead_man_switch = dms:get_checked()
        state.depart_switch = depart:get_checked()
        state.monitor_interaction = monitor:get_checked()
        state.ignore_disks = ignore_disks:get_checked()
        state.debug_combat = dbg_combat:get_checked()
        state.debug_commands = dbg_commands:get_checked()
        state.debug_status = dbg_status:get_checked()
        state.debug_system = dbg_system:get_checked()
    end
end

---------------------------------------------------------------------------
-- Main GUI entry point
---------------------------------------------------------------------------
function M.open(state)
    local win = Gui.window("Bigshot Settings v5.12.1", { width = 700, height = 600, resizable = true })
    local root = Gui.vbox()

    -- Build all tabs
    local rest_tab, save_rest = build_resting_tab(state)
    local hunt_tab, save_hunt = build_hunting_tab(state)
    local atk_tab, save_atk = build_attack_tab(state)
    local cmd_tab, save_cmd = build_commands_tab(state)
    local misc_tab, save_misc = build_misc_tab(state)

    -- Tab bar
    local tabs = Gui.tab_bar({"Resting", "Hunting", "Attack", "Commands", "Misc"})
    tabs:set_tab_content(1, rest_tab)
    tabs:set_tab_content(2, hunt_tab)
    tabs:set_tab_content(3, atk_tab)
    tabs:set_tab_content(4, cmd_tab)
    tabs:set_tab_content(5, misc_tab)
    root:add(tabs)

    -- Profile section
    root:add(Gui.separator())
    local prof_row = Gui.hbox()
    local prof_input = Gui.input({ placeholder = "Profile name" })
    prof_row:add(prof_input)
    local save_prof_btn = Gui.button("Save Profile")
    prof_row:add(save_prof_btn)
    local load_prof_btn = Gui.button("Load Profile")
    prof_row:add(load_prof_btn)
    root:add(prof_row)

    -- Save & Close
    root:add(Gui.separator())
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save & Close")
    btn_row:add(save_btn)
    local cancel_btn = Gui.button("Cancel")
    btn_row:add(cancel_btn)
    root:add(btn_row)

    win:set_root(root)

    -- Callbacks
    save_prof_btn:on_click(function()
        local name = prof_input:get_text()
        if name and name ~= "" then
            -- Collect all tab data first
            save_rest(); save_hunt(); save_atk(); save_cmd(); save_misc()
            config.save_profile(state, name)
        end
    end)

    load_prof_btn:on_click(function()
        local name = prof_input:get_text()
        if name and name ~= "" then
            local profile = config.load_profile(name)
            if profile then
                for k, v in pairs(profile) do state[k] = v end
                respond("[bigshot] Loaded profile: " .. name)
                -- Close and reopen to refresh
                win:close()
                M.open(state)
            end
        end
    end)

    save_btn:on_click(function()
        save_rest(); save_hunt(); save_atk(); save_cmd(); save_misc()
        config.save(state)
        respond("[bigshot] Settings saved")
        win:close()
    end)

    cancel_btn:on_click(function()
        respond("[bigshot] Settings not saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
