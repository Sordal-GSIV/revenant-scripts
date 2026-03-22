--- SetupProcess — weapon/stance/armor setup for combat-trainer.
-- Ported from SetupProcess class in combat-trainer.lic
local defs = require("defs")

local M = {}
M.__index = M

function M.new(settings, equip_mgr)
    local self = setmetatable({}, M)
    self._equip_mgr               = equip_mgr
    self._stance_override         = settings.stance_override
    self._priority_defense        = settings.priority_defense
    self._priority_weapons        = settings.priority_weapons or {}
    self._cycle_armors            = settings.cycle_armors or {}
    self._cycle_armors_time       = settings.cycle_armors_time or 300
    self._armor_hysteresis        = settings.cycle_armors_hysteresis
    self._last_cycle_time         = os.time() - (settings.cycle_armors_time or 300)
    self._combat_training_abilities_target = settings.combat_training_abilities_target or 34
    self._cycle_regalia           = settings.cycle_armors_regalia
    self._default_armor           = settings.default_armor_type
    self._ignore_weapon_mindstate = settings.combat_trainer_ignore_weapon_mindstate
    self._gearsets                = settings.gear_sets or {}
    self._offhand_trainables      = settings.combat_trainer_offhand_trainables
    self._last_worn_type          = nil
    self._override_done           = false
    self._firing_check            = 0

    -- Validate regalia
    self:_validate_regalia(settings)

    return self
end

function M:execute(game_state)
    if game_state:done_cleaning_up() then return true end

    if game_state:stowing() then
        DRC.retreat()
        local ws = game_state:weapon_skill()
        if game_state:summoned_info(ws) then
            if DRStats.moon_mage then
                DRCMM.wear_moon_weapon()
            else
                DRCS.break_summoned_weapon(game_state:weapon_name())
            end
        else
            self._equip_mgr.stow_weapon(game_state:weapon_name())
            game_state:sheath_whirlwind_offhand()
        end
        game_state:next_clean_up_step()
        return true
    end

    local was_retreating = game_state:retreating_p()
    game_state:update_room_npcs()

    if game_state:dancing_p() then
        game_state:dance()
    elseif game_state:retreating_p() then
        -- determine_next_to_train with retreat_weapons (for now use weapons_to_train)
        self:_determine_next_to_train(game_state, game_state.weapons_to_train, false)
    else
        self:_determine_next_to_train(game_state, game_state.weapons_to_train, was_retreating)
    end

    if game_state.parrying then
        self:_check_stance(game_state)
        self:_check_weapon(game_state)
    else
        self:_check_weapon(game_state)
        self:_check_stance(game_state)
    end

    if self._cycle_regalia then
        self:_check_regalia_swap(game_state)
    else
        self:_check_armor_swap(game_state)
    end

    return false
end

function M:_armor_hysteresis_check(game_state)
    if not self._armor_hysteresis then return false end
    for skill, _ in pairs(self._cycle_armors) do
        if DRSkill.getxp(skill) < 25 then return false end
    end

    local all_max = true
    for skill, _ in pairs(self._cycle_armors) do
        if DRSkill.getxp(skill) <= 32 then all_max = false; break end
    end

    if all_max then
        if self._last_worn_type ~= self._default_armor then
            local armor_keys = {}
            for _, pieces in pairs(self._cycle_armors) do
                for _, piece in ipairs(pieces) do
                    table.insert(armor_keys, piece)
                end
            end
            local worn = self._equip_mgr.worn_items(armor_keys)
            for _, item in ipairs(worn) do
                self._equip_mgr.remove_item(item)
            end
            local new_pieces = self._equip_mgr.desc_to_items(self._cycle_armors[self._default_armor] or {})
            self._equip_mgr.wear_items(new_pieces)
            self._last_worn_type = self._default_armor
        end
    end
    return true
end

function M:_check_armor_swap(game_state)
    if self:_armor_hysteresis_check(game_state) then return end
    if (os.time() - self._last_cycle_time) < self._cycle_armors_time then return end
    if game_state.loaded then return end

    local armor_types = {}
    for skill, _ in pairs(self._cycle_armors) do
        table.insert(armor_types, skill)
    end
    if #armor_types == 0 then return end

    local sorted = game_state:sort_by_rate_then_rank(armor_types)
    local next_type = sorted[1]
    if next_type == self._last_worn_type then return end
    if DRSkill.getxp(next_type) >= self._combat_training_abilities_target then return end

    self._last_cycle_time = os.time()
    game_state:sheath_whirlwind_offhand()

    if self._last_worn_type then
        local pieces = self._equip_mgr.desc_to_items(self._cycle_armors[self._last_worn_type] or {})
        for _, item in ipairs(pieces) do
            self._equip_mgr.remove_item(item)
        end
    else
        local all_pieces = {}
        for _, pieces in pairs(self._cycle_armors) do
            for _, p in ipairs(pieces) do table.insert(all_pieces, p) end
        end
        local worn = self._equip_mgr.worn_items(all_pieces)
        for _, item in ipairs(worn) do
            self._equip_mgr.remove_item(item)
        end
    end

    local new_pieces = self._equip_mgr.desc_to_items(self._cycle_armors[next_type] or {})
    self._equip_mgr.wear_items(new_pieces)
    self._last_worn_type = next_type
    game_state:wield_whirlwind_offhand()
end

function M:_check_regalia_swap(game_state)
    -- Regalia cycling for traders
    if (os.time() - self._last_cycle_time) < self._cycle_armors_time
       and not Flags["ct-regalia-expired"] then return end
    if game_state.regalia_cancel then
        if Flags["ct-regalia-expired"] then
            -- shutdown
            DRCA.shatter_regalia()
            game_state.last_regalia_type = nil
            game_state.swap_regalia_type = nil
            game_state.regalia_cancel = nil
            self._cycle_regalia = nil
            Flags.reset("ct-regalia-expired")
            self._equip_mgr.wear_equipment_set("standard")
        end
        return
    end

    local armor_types = self._cycle_regalia
    local sorted = game_state:sort_by_rate_then_rank(armor_types)
    local next_type = sorted[1]

    if not Flags["ct-regalia-expired"] and next_type == self._last_worn_type then return end
    if not Flags["ct-regalia-expired"]
       and game_state.last_regalia_type
       and DRSkill.getxp(next_type) >= self._combat_training_abilities_target then return end

    self._last_cycle_time = os.time()
    game_state.swap_regalia_type = next_type
end

function M:_determine_next_to_train(game_state, weapon_training, ending_ranged)
    local ws = game_state:weapon_skill()
    if not (game_state:skill_done() or not weapon_training[ws] or ending_ranged) then
        return
    end

    if not self._ignore_weapon_mindstate and not game_state.skip_all_weapon_max_check then
        -- Check if all weapons are maxed
        local any_not_maxed = false
        for skill, _ in pairs(weapon_training) do
            if DRSkill.getxp(skill) ~= 34 then
                any_not_maxed = true
                break
            end
        end
        if not any_not_maxed then
            echo("all weapons locked, not switching")
            return
        end
    end
    game_state.skip_all_weapon_max_check = false

    game_state:reset_action_count()
    game_state.last_exp = -1
    game_state.last_action_count = 0

    -- Skip summoned weapons if no moonblade available
    local skills_list = {}
    for skill, _ in pairs(weapon_training) do
        if skill ~= ws then  -- exclude current skill
            local summoned = game_state:summoned_info(skill)
            if not summoned or not DRStats.moon_mage or DRCMM.moon_used_to_summon_weapon() then
                table.insert(skills_list, skill)
            end
        end
    end

    local new_skill
    if self._offhand_trainables and game_state.focus_threshold_active then
        -- Advanced multi-pool selection
        local mainhand_skills = defs.tdiff(
            defs.tmerge(defs.MELEE_SKILLS, defs.THROWN_SKILLS),
            game_state.aiming_trainables)
        local offhand_skills = defs.tmerge(game_state.aiming_trainables, {"Offhand Weapon"})

        local bow_pool = {}
        local mainhand_pool = {}
        local offhand_pool = {}
        for _, skill in ipairs(skills_list) do
            local xp = DRSkill.getxp(skill)
            if defs.tcontains(defs.AIM_SKILLS, skill) and xp < 30 then
                table.insert(bow_pool, skill)
            elseif defs.tcontains(mainhand_skills, skill) and xp < 30 then
                table.insert(mainhand_pool, skill)
            elseif defs.tcontains(offhand_skills, skill) and xp < 30 then
                table.insert(offhand_pool, skill)
            end
        end

        if #bow_pool > 0 then
            new_skill = game_state:sort_by_rate_then_rank(bow_pool)[1]
        elseif #mainhand_pool > 0 then
            new_skill = game_state:sort_by_rate_then_rank(mainhand_pool)[1]
        elseif #offhand_pool > 0 then
            new_skill = game_state:sort_by_rate_then_rank(offhand_pool)[1]
        else
            new_skill = game_state:sort_by_rate_then_rank(skills_list, self._priority_weapons)[1]
        end
    else
        new_skill = game_state:sort_by_rate_then_rank(skills_list, self._priority_weapons)[1]
    end

    if new_skill then
        game_state:update_weapon_info(new_skill)
        game_state:update_target_weapon_skill()
    end
end

function M:_last_stance()
    local flag = Flags["last-stance"]
    if not flag then return {EVASION=0, PARRY=0, SHIELD=0, SPARE=0} end
    local line = type(flag) == "table" and flag[1] or tostring(flag)
    local ev, pa, sh, sp = line:match("(%d+)%%.* (%d+)%%.* (%d+)%%.* (%d+)")
    return {
        EVASION = tonumber(ev) or 0,
        PARRY   = tonumber(pa) or 0,
        SHIELD  = tonumber(sh) or 0,
        SPARE   = tonumber(sp) or 0,
    }
end

function M:_build_stance_string(vals)
    return string.format("stance set %d %d %d", vals.EVASION, vals.PARRY, vals.SHIELD)
end

function M:_check_stance(game_state, override_points)
    if self._override_done and not game_state.reset_stance then return end

    if self._stance_override then
        game_state.reset_stance = false
        pause(1)
        waitrt()
        DRC.bput("stance set " .. tostring(self._stance_override), "Setting your")
        self._override_done = true
        return
    end

    local vals = {EVASION=0, PARRY=0, SHIELD=0, SPARE=0}
    local skill_map = {["Parry Ability"]="PARRY", ["Shield Usage"]="SHIELD", ["Evasion"]="EVASION"}
    local previous = self:_last_stance()
    local points = override_points or (previous.EVASION + previous.PARRY + previous.SHIELD + previous.SPARE)

    local current_weapon_stance = game_state:current_weapon_stance()
    local priority
    if current_weapon_stance then
        if game_state:strict_weapon_stance() then
            priority = current_weapon_stance
        else
            local top2 = game_state:sort_by_rate_then_rank({current_weapon_stance[1], current_weapon_stance[2]})
            priority = {top2[1], top2[2], current_weapon_stance[3]}
        end
    elseif self._priority_defense then
        local rest = {}
        for _, s in ipairs({"Evasion", "Parry Ability", "Shield Usage"}) do
            if s ~= self._priority_defense then table.insert(rest, s) end
        end
        local sorted_rest = game_state:sort_by_rate_then_rank(rest)
        priority = {self._priority_defense, sorted_rest[1], sorted_rest[2]}
    else
        priority = game_state:sort_by_rate_then_rank({"Evasion", "Parry Ability", "Shield Usage"})
    end

    -- Set parrying state
    local parry_idx = nil
    for i, s in ipairs(priority) do
        if s == "Parry Ability" then parry_idx = i; break end
    end
    game_state.parrying = (parry_idx ~= nil and parry_idx < 3)

    for _, skill in ipairs(priority) do
        local key = skill_map[skill] or skill:upper()
        if key == "PARRY ABILITY" then key = "PARRY" end
        local allot = math.min(points, 100)
        vals[key] = allot
        points = points - allot
    end

    -- Check if same as previous
    if vals.EVASION == previous.EVASION
       and vals.PARRY == previous.PARRY
       and vals.SHIELD == previous.SHIELD then
        return
    end

    local result = DRC.bput(self:_build_stance_string(vals),
        "Setting your Evasion stance to",
        "is above your maximum number of points")
    local max_pts = result and result:match("maximum number of points %((%d+)") or nil
    if max_pts then
        self:_check_stance(game_state, tonumber(max_pts))
    end
end

function M:_check_weapon(game_state)
    local ws = game_state:weapon_skill()
    if self._last_seen_weapon_skill == ws then return end
    self._last_seen_weapon_skill = ws

    local last_summoned = game_state:summoned_info(game_state.last_weapon_skill)
    local next_summoned = game_state:summoned_info(ws)

    -- Clean up previous weapon
    if not last_summoned then
        self._equip_mgr.stow_weapon(game_state:last_weapon_name())
        game_state:sheath_whirlwind_offhand()
    elseif not next_summoned and not DRStats.moon_mage then
        DRCS.break_summoned_weapon(game_state:last_weapon_name())
    elseif not next_summoned and DRStats.moon_mage then
        DRCMM.wear_moon_weapon()
    end

    -- Reset state for new weapon
    game_state.loaded = false
    self._firing_check = 0

    -- Prepare new weapon
    if next_summoned then
        game_state:prepare_summoned_weapon(last_summoned)
    else
        DRC.bput("aim stop", "But you're not aiming", "You stop concentrating", "You are already")
        game_state:wield_weapon()
        if game_state:whirlwind_trainable() then
            game_state.currently_whirlwinding = true
            self:_determine_whirlwind_weapon(game_state)
        else
            game_state.currently_whirlwinding = false
        end
    end

    -- Targeted Magic invoke
    if ws == "Targeted Magic" and game_state:weapon_name() then
        if DRCI.get_item(game_state:weapon_name()) then
            DRC.bput("invoke " .. game_state:weapon_name(), "You")
            waitrt()
        end
    end
end

function M:_determine_whirlwind_weapon(game_state)
    if game_state:twohanded_weapon_skill() then return end
    local offhand_skill = game_state:determine_whirlwind_weapon_skill()
    game_state:update_whirlwind_weapon_info(offhand_skill)
    game_state:wield_whirlwind_offhand()
end

function M:_validate_regalia(settings)
    if not self._cycle_regalia then return end
    if self._cycle_armors and next(self._cycle_armors) then
        DRC.message("ERROR - Regalia cycling and armorswap cycling at the same time not supported!")
        self._cycle_regalia = nil
        return
    end
    local gearsets = settings.gear_sets or {}
    if not gearsets["regalia"] or #gearsets["regalia"] == 0 then
        DRC.message("ERROR - Regalia cycling requires a gear_set named 'regalia'")
        self._cycle_regalia = nil
    end
end

return M
