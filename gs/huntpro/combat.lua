-- huntpro/combat.lua — Combat loop, target selection, attack execution
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara — combat_unique_to_huntpro, style dispatch,
-- uac_round, mstrike, chicken_attack/ambush/fire, crowd_control, cman_control,
-- weapon_control, shield_control (lines ~2050-6000)

local Combat = {}

---------------------------------------------------------------------------
-- State shared across combat module
---------------------------------------------------------------------------
local state = {
    current_target      = nil,
    current_id_targets  = {},
    current_name_targets = {},
    current_noun_targets = {},
    weak_targets        = {},
    s9_override_targets = {},
    sev1_targets        = {},
    uac_current_attack  = "jab",
    mstrike_focus       = 0,
    mstrike_open        = 0,
    cman_cooldown       = 0,
    cman_bearhug_cd     = 0,
    cman_cheapshot_tog  = 0,
    cman_cheapshot_tog2 = 0,
    shield_cooldown     = 0,
    weapon_cooldown     = 0,
    cc_cooldown         = 0,
    society_cc_cooldown = 0,
    ragemode            = false,
    disable_mstrike     = false,
    combat_wands        = false,
}

Combat.state = state

---------------------------------------------------------------------------
-- Helpers — stance management
---------------------------------------------------------------------------
function Combat.stance_offensive(hp)
    waitrt()
    waitcastrt()
    local target_stance = hp.stance_offensive or "offensive"
    if GameState.stance ~= target_stance then
        pause(0.1)
        fput("stance " .. target_stance)
    end
end

function Combat.stance_guarded(hp)
    if hp.stay_offensive then return end
    waitrt()
    waitcastrt()
    local target_stance = hp.stance_defensive or "guarded"
    if GameState.stance ~= target_stance then
        pause(0.1)
        fput("stance " .. target_stance)
    end
end

function Combat.stance_defensive(hp)
    if hp.stay_offensive then return end
    waitrt()
    waitcastrt()
    local target_stance = hp.stance_defensive or "defensive"
    if GameState.stance ~= target_stance then
        pause(0.1)
        fput("stance " .. target_stance)
    end
end

---------------------------------------------------------------------------
-- Stand check
---------------------------------------------------------------------------
function Combat.stand_check()
    if not GameState.standing then
        fput("stand")
        pause(0.25)
        waitrt()
    end
end

---------------------------------------------------------------------------
-- Prep reset — release any prepared spell
---------------------------------------------------------------------------
function Combat.prep_reset()
    if GameState.prepared_spell and GameState.prepared_spell ~= "None" then
        fput("release")
    end
end

---------------------------------------------------------------------------
-- Target scanning — populates state tables from GameObj
---------------------------------------------------------------------------
function Combat.scan_targets(hp)
    state.current_target       = nil
    state.current_id_targets   = {}
    state.current_name_targets = {}
    state.current_noun_targets = {}
    state.weak_targets         = {}
    state.s9_override_targets  = {}
    state.sev1_targets         = {}

    local targets = GameObj.targets and GameObj.targets() or {}

    for _, npc in ipairs(targets) do
        table.insert(state.current_id_targets, npc.id)
        table.insert(state.current_name_targets, npc.name)
        table.insert(state.current_noun_targets, npc.noun)

        -- Weak target detection (sleeping, stunned, prone)
        if npc.status and (
            npc.status:find("sleeping") or
            npc.status:find("frozen in place") or
            npc.status:find("stunned") or
            npc.status:find("lying down")
        ) then
            table.insert(state.weak_targets, {id = npc.id, name = npc.name})
        end

        -- S9 override check (creatures with prefixes)
        if npc.name:find("rune%-covered") or npc.name:find("tattooed") or
           npc.name:find("sparkling") or npc.name:find("shining") or
           npc.name:find("ethereal") or npc.name:find("wispy") or
           npc.name:find("ghostly") then
            table.insert(state.s9_override_targets, {id = npc.id, name = npc.name})
        end
    end

    -- Check force skip list
    if hp.force_skip_array and #hp.force_skip_array > 0 then
        for _, noun in ipairs(state.current_noun_targets) do
            for _, skip in ipairs(hp.force_skip_array) do
                if noun == skip then
                    return "flee"  -- trigger room change
                end
            end
        end
    end

    -- Check compound ignore list
    if hp.compound_ignore_array and #hp.compound_ignore_array > 0 then
        for _, name in ipairs(state.current_name_targets) do
            for _, ignore in ipairs(hp.compound_ignore_array) do
                if name == ignore then
                    return "flee"
                end
            end
        end
    end

    -- Flee counter check
    if hp.flee_counter and hp.flee_counter > 0 then
        if #targets >= hp.flee_counter then
            return "flee"
        end
    end

    -- Pick current target — prefer weak targets, then first available
    if #state.weak_targets > 0 then
        state.current_target = state.weak_targets[1].name
    elseif #state.current_name_targets > 0 then
        -- If force_target is set, prefer matching target
        if hp.force_target and hp.force_target ~= "0" then
            for _, name in ipairs(state.current_name_targets) do
                if name:find(hp.force_target) then
                    state.current_target = name
                    break
                end
            end
        end
        if not state.current_target then
            state.current_target = state.current_name_targets[1]
        end
    end

    return "ok"
end

---------------------------------------------------------------------------
-- MStrike setup — configure based on MOC ranks
---------------------------------------------------------------------------
function Combat.mstrike_setup(hp)
    local style = hp.my_style
    local mstrike_defaults = {
        ["1"] = "jab",    ["2"] = "grapple",
        ["3"] = "attack", ["4"] = "attack",
        ["5"] = "fire",   ["6"] = "fire",
        ["7"] = "fire",   ["8"] = "fire",
    }

    if mstrike_defaults[style] then
        fput("mstrike set recovery off")
        fput("mstrike set default " .. mstrike_defaults[style])
    end

    local moc = Skills.multi_opponent_combat or 0
    if     moc >= 190 then state.mstrike_focus = 6; state.mstrike_open = 7
    elseif moc >= 155 then state.mstrike_focus = 5; state.mstrike_open = 7
    elseif moc >= 135 then state.mstrike_focus = 5; state.mstrike_open = 6
    elseif moc >= 100 then state.mstrike_focus = 4; state.mstrike_open = 6
    elseif moc >=  90 then state.mstrike_focus = 4; state.mstrike_open = 5
    elseif moc >=  60 then state.mstrike_focus = 3; state.mstrike_open = 5
    elseif moc >=  55 then state.mstrike_focus = 3; state.mstrike_open = 4
    elseif moc >=  35 then state.mstrike_focus = 2; state.mstrike_open = 4
    elseif moc >=  30 then state.mstrike_focus = 2; state.mstrike_open = 3
    elseif moc >=  15 then state.mstrike_focus = 0; state.mstrike_open = 3
    elseif moc >=   5 then state.mstrike_focus = 0; state.mstrike_open = 2
    else return end

    fput("mstrike set focus " .. state.mstrike_focus)
    fput("mstrike set open " .. state.mstrike_open)
end

---------------------------------------------------------------------------
-- MStrike routine
---------------------------------------------------------------------------
function Combat.mstrike_routine(hp)
    if state.disable_mstrike then return end
    local moc = Skills.multi_opponent_combat or 0
    if moc < 5 then return end
    if Spell.active_p(9005) then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    local stamina_pct = Char.percent_stamina or 100

    if stamina_pct >= 50 then
        if #targets >= 2 and state.mstrike_open >= 1 then
            Combat.stance_offensive(hp)
            fput("mstrike")
        elseif #targets == 1 and state.mstrike_focus >= 1 then
            Combat.stance_offensive(hp)
            fput("mstrike target")
        end
    end
    waitrt()
end

---------------------------------------------------------------------------
-- UAC round (styles 1-2: jab/punch/kick/grapple chain)
---------------------------------------------------------------------------
function Combat.uac_round(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end

    if not state.uac_current_attack or state.uac_current_attack == "0" then
        state.uac_current_attack = "jab"
    end

    Combat.stance_offensive(hp)

    local result = dothistimeout(state.uac_current_attack, 2,
        "excellent positioning", "followup jab", "followup punch",
        "followup grapple", "followup kick", "Roundtime")

    if result then
        if result:find("excellent positioning") then
            if Stats.prof == "Bard" then
                state.uac_current_attack = "punch"
            else
                state.uac_current_attack = "kick"
            end
        elseif result:find("followup jab") then
            state.uac_current_attack = "jab"
        elseif result:find("followup punch") then
            state.uac_current_attack = "punch"
        elseif result:find("followup grapple") then
            state.uac_current_attack = "grapple"
        elseif result:find("followup kick") then
            state.uac_current_attack = "kick"
        elseif result:find("Roundtime") then
            state.uac_current_attack = "jab"
        end
    end
end

---------------------------------------------------------------------------
-- Chicken attack (styles 3-4: melee weapon attack)
---------------------------------------------------------------------------
function Combat.chicken_attack(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    Combat.stance_offensive(hp)
    fput("attack target")
    waitrt()
    Combat.stance_guarded(hp)
end

---------------------------------------------------------------------------
-- Chicken ambush (style 4: hidden melee)
---------------------------------------------------------------------------
function Combat.chicken_ambush(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    Combat.stance_offensive(hp)
    fput("ambush target")
    waitrt()
    Combat.stance_guarded(hp)
end

---------------------------------------------------------------------------
-- Chicken fire (styles 5-8: ranged attack)
---------------------------------------------------------------------------
function Combat.chicken_fire(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    Combat.stance_offensive(hp)
    fput("fire target")
    waitrt()
    Combat.stance_guarded(hp)
end

---------------------------------------------------------------------------
-- Hide routine
---------------------------------------------------------------------------
function Combat.hide_time(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    if GameState.hidden then return end

    -- Ranger camo check
    if hp.camo and Spell[608] and Spell[608].affordable then
        if not GameState.hidden then
            if GameState.prepared_spell and GameState.prepared_spell ~= "None" then
                fput("release")
            end
            fput("prep 608")
            pause(0.2)
            fput("cast")
            waitrt()
            waitcastrt()
        end
    else
        fput("hide")
        waitrt()
    end
end

---------------------------------------------------------------------------
-- CMan control — execute combat maneuvers on cooldown rotation
---------------------------------------------------------------------------
function Combat.cman_control(hp)
    local stamina_pct = Char.percent_stamina or 100
    if stamina_pct < 50 then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end

    -- Rotate through cooldown tiers 0-4
    local cd = state.cman_cooldown

    local function do_cman(cmd)
        waitrt()
        Combat.stance_offensive(hp)
        if (Char.percent_stamina or 100) >= 50 then
            fput(cmd)
        end
        waitrt()
        Combat.stance_guarded(hp)
    end

    if cd == 0 then
        if hp.cman_tackle then do_cman("tackle target") end
        if hp.cman_sweep and (Stats.prof:find("Rogue") or Stats.prof:find("Ranger") or
           Stats.prof:find("Bard") or Stats.prof:find("Monk")) then
            do_cman("sweep target")
        end
        if hp.cman_mightyblow then do_cman("cman mblow target") end
        if hp.cman_footstomp then do_cman("cman footstomp target") end
        if hp.cman_trip then do_cman("cman trip target") end
        if hp.cman_vaultkick then do_cman("cman vaultkick target") end
        if state.cman_cooldown == 0 then state.cman_cooldown = 5 end

    elseif cd == 1 then
        if hp.cman_bearhug and state.cman_bearhug_cd == 0 then
            do_cman("cman bearhug target")
            state.cman_bearhug_cd = 5
        end
        if hp.cman_nosetweak then do_cman("cman nosetweak target") end
        if hp.cman_suckerpunch then do_cman("cman spunch target") end

    elseif cd == 2 then
        if hp.cman_disarm then do_cman("cman disarm target") end
        if hp.cman_spellcleave then do_cman("cman scleave target") end
        if hp.cman_berserk and not hp.no_berserk then
            waitrt()
            state.ragemode = true
            Combat.stance_offensive(hp)
            fput("berserk")
            waitrt()
            -- Wait for berserk to end
            local timeout = 0
            while state.ragemode and timeout < 40 do
                pause(0.25)
                timeout = timeout + 1
            end
            Combat.stance_guarded(hp)
        end
        if hp.cman_kneebash then do_cman("cman kneebash target") end
        if hp.cman_headbutt then do_cman("cman headbutt target") end

    elseif cd == 3 then
        if hp.cman_mug then do_cman("cman mug target") end
        if hp.cman_bullrush then do_cman("cman bullrush target") end
        if hp.cman_spinattack then do_cman("cman sattack target") end
        if hp.cman_staggeringblow then do_cman("cman sblow target") end
        if hp.cman_truestrike then do_cman("cman truestrike target") end
        if hp.cman_crowdpress then do_cman("cman cpress target") end
        if hp.cman_dirtkick then do_cman("cman dirtkick target") end

    elseif cd == 4 then
        if hp.cman_swiftkick then do_cman("cman swiftkick target") end
        if hp.cman_feint then do_cman("cman feint target") end
        if hp.cman_groinkick then do_cman("cman gkick target") end
        if hp.cman_haymaker then do_cman("cman haymaker target") end
        if hp.cman_sundershield then do_cman("cman sunder target") end
    end

    if state.cman_cooldown > 0 then
        state.cman_cooldown = state.cman_cooldown - 1
    end
    if state.cman_bearhug_cd > 0 then
        state.cman_bearhug_cd = state.cman_bearhug_cd - 1
    end
end

---------------------------------------------------------------------------
-- Shield control — shield bash, charge, trample, etc.
---------------------------------------------------------------------------
function Combat.shield_control(hp)
    if hp.no_shield_control then return end
    if (Skills.shield_use or 0) < 1 then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end

    local stamina_pct = Char.percent_stamina or 100
    if stamina_pct < 50 then return end

    local cd = state.shield_cooldown

    local function do_shield(cmd)
        waitrt()
        waitcastrt()
        Combat.stance_offensive(hp)
        fput(cmd)
        waitrt()
        waitcastrt()
        Combat.stance_guarded(hp)
    end

    if cd == 0 then
        if hp.shield_shieldbash then do_shield("shield bash") end
        if hp.shield_shieldstrike then do_shield("shield strike") end
        if state.shield_cooldown == 0 then state.shield_cooldown = 10 end
    elseif cd == 2 then
        if hp.shield_steelyresolve then do_shield("shield steely") end
    elseif cd == 4 then
        if hp.shield_shieldpin then do_shield("shield pin") end
        if hp.shield_shieldpush then do_shield("shield push") end
    elseif cd == 6 then
        if hp.shield_shieldtrample then do_shield("shield trample") end
        if hp.shield_shieldthrow then do_shield("shield throw") end
    elseif cd == 8 then
        if hp.shield_shieldcharge then do_shield("shield charge") end
    end

    if state.shield_cooldown > 0 then
        state.shield_cooldown = state.shield_cooldown - 1
    end
end

---------------------------------------------------------------------------
-- Weapon control — weapon techniques based on attunement
---------------------------------------------------------------------------
function Combat.weapon_control(hp)
    if hp.no_weapon_control then return end
    local attune = hp.weapon_attune
    if not attune or attune == "0" then return end

    local stamina_pct = Char.percent_stamina or 100
    if stamina_pct < 50 then return end

    local cd = state.weapon_cooldown

    local function do_weapon(cmd)
        state.disable_mstrike = true
        waitrt()
        waitcastrt()
        Combat.stance_offensive(hp)
        fput(cmd)
        waitrt()
        waitcastrt()
        Combat.stance_guarded(hp)
    end

    -- Weapon techniques by attunement and cooldown tier
    local techniques = {
        brawling = {[0] = "weapon twinhammer", [2] = "weapon fury", [4] = "weapon clash"},
        blunt    = {[0] = "weapon dizzyingswing", [4] = "weapon pummel", [6] = "weapon pulverize"},
        edged    = {[0] = "weapon cripple", [4] = "weapon flurry", [6] = "weapon wblade"},
        polearm  = {[0] = "weapon charge", [2] = "weapon gthrusts", [4] = "weapon cyclone"},
        ranged   = {[2] = "weapon pindown", [4] = "weapon barrage", [6] = "weapon volley"},
        ["2hw"]  = {[2] = "weapon thrash", [6] = "weapon whirlwind"},
    }

    local tech = techniques[attune]
    if tech and tech[cd] then
        do_weapon(tech[cd])
    end

    if cd == 0 then
        state.weapon_cooldown = 10
    elseif state.weapon_cooldown > 0 then
        state.weapon_cooldown = state.weapon_cooldown - 1
    end
end

---------------------------------------------------------------------------
-- Crowd control — society-based CC on 3+ mobs
---------------------------------------------------------------------------
function Combat.crowd_control(hp)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 3 then return end

    waitrt()

    if hp.my_society == "Voln" and state.society_cc_cooldown == 0 then
        waitrt()
        waitcastrt()
        fput("sym sleep")
        state.society_cc_cooldown = 10
    elseif hp.my_society == "Gos" and state.society_cc_cooldown == 0 then
        waitrt()
        waitcastrt()
        fput("sigil diminish")
        state.society_cc_cooldown = 10
    elseif hp.my_society == "Col" and state.society_cc_cooldown == 0 then
        waitrt()
        waitcastrt()
        fput("sign wracking")
        state.society_cc_cooldown = 10
    end

    if state.society_cc_cooldown > 0 then
        state.society_cc_cooldown = state.society_cc_cooldown - 1
    end
end

---------------------------------------------------------------------------
-- Master combat dispatch — called per combat round
-- Executes style-specific combat based on hp.my_style (1-9)
---------------------------------------------------------------------------
function Combat.execute_round(hp)
    Combat.stand_check()

    -- Paladin stamina recovery
    if Stats.prof == "Paladin" and Spell[1607] and Spell[1607].known and
       Spell[1607]:affordable() and (Char.percent_stamina or 100) <= 50 and
       not Spell.active_p(1607) then
        Spell[1607]:cast()
    end

    -- Sub-systems
    Combat.shield_control(hp)
    Combat.weapon_control(hp)

    if not hp.no_crowd_control and hp.crowd_control_enabled then
        Combat.crowd_control(hp)
    end

    if not hp.no_cman_control and hp.cman_control_enabled then
        Combat.cman_control(hp)
    end

    -- Style dispatch
    local style = hp.my_style

    if style == "1" then
        -- UAC melee
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        Combat.uac_round(hp)

    elseif style == "2" then
        -- UAC melee + hide
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        Combat.hide_time(hp)
        Combat.uac_round(hp)

    elseif style == "3" then
        -- Melee weapon
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        waitrt(); waitcastrt()
        Combat.stance_offensive(hp)
        Combat.chicken_attack(hp)

    elseif style == "4" then
        -- Melee weapon + ambush from hiding
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        waitrt(); waitcastrt()
        Combat.hide_time(hp)
        Combat.stance_offensive(hp)
        if GameState.hidden then
            Combat.chicken_ambush(hp)
        else
            Combat.chicken_attack(hp)
        end

    elseif style == "5" then
        -- Ranged
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        waitrt(); waitcastrt()
        Combat.stance_offensive(hp)
        Combat.chicken_fire(hp)

    elseif style == "6" then
        -- Ranged + hide
        waitrt(); waitcastrt()
        Combat.mstrike_routine(hp)
        waitrt(); waitcastrt()
        Combat.hide_time(hp)
        Combat.stance_offensive(hp)
        Combat.chicken_fire(hp)

    elseif style == "7" then
        -- Ranged kneeling
        waitrt(); waitcastrt()
        if not GameState.kneeling then fput("kneel"); pause(0.25); waitrt() end
        Combat.mstrike_routine(hp)
        Combat.stance_offensive(hp)
        Combat.chicken_fire(hp)

    elseif style == "8" then
        -- Ranged kneeling + hide
        waitrt(); waitcastrt()
        if not GameState.kneeling then fput("kneel"); pause(0.25); waitrt() end
        Combat.mstrike_routine(hp)
        Combat.hide_time(hp)
        Combat.stance_offensive(hp)
        Combat.chicken_fire(hp)

    elseif style == "9" then
        -- Pure caster
        if state.combat_wands then
            Combat.stand_check()
            -- Wand usage delegated to spells module
            return "wands"
        else
            Combat.stance_guarded(hp)
            Combat.prep_reset()
            -- Spell choice delegated to spells module
            return "cast"
        end
    end

    Combat.stance_guarded(hp)
    return "melee_done"
end

---------------------------------------------------------------------------
-- Loot trigger — run loot script after combat
---------------------------------------------------------------------------
function Combat.run_loot(hp)
    waitrt()
    Combat.stance_guarded(hp)
    local dead = GameObj.dead and GameObj.dead() or {}
    if #dead >= 1 then
        local loot_script = hp.loot_script or "eloot"
        Script.run(loot_script)
        wait_while(function() return Script.running(loot_script) end)
    end
end

---------------------------------------------------------------------------
-- End combat action reset
---------------------------------------------------------------------------
function Combat.endcombat_reset(hp)
    Combat.stance_guarded(hp)
    -- Preserve special action codes (95-99)
    if hp.action and hp.action >= 95 then
        return
    end
    hp.action = 0
end

return Combat
