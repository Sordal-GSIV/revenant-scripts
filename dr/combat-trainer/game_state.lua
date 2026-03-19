--- GameState — centralized combat-trainer state.
-- Ported from GameState class in combat-trainer.lic.
local defs = require("defs")

local M = {}
M.__index = M

--- Create a new GameState instance.
-- @param settings table  Character settings from get_settings()
-- @param equip_mgr table EquipmentManager instance
function M.new(settings, equip_mgr)
    local self = setmetatable({}, M)
    self._equip_mgr = equip_mgr

    -- Combat state
    self.mob_died         = false
    self.last_weapon_skill  = nil
    self.danger           = false
    self.parrying         = false
    self.casting          = false
    self.need_bundle      = true
    self.cooldown_timers  = {}
    self.no_stab_current_mob = false
    self.loaded           = false
    self.cast_timer       = nil
    self.casting_moonblade = false
    self.casting_sorcery  = false
    self.casting_cyclic   = false
    self.hide_on_cast     = false
    self.casting_regalia  = false
    self.regalia_cancel   = false
    self.last_regalia_type = nil
    self.swap_regalia_type = nil
    self.starlight_values = nil
    self.casting_weapon_buff = false
    self.casting_consume  = false
    self.prepare_consume  = false
    self.prepare_nr       = false
    self.casting_nr       = false
    self.prepare_cfb      = false
    self.casting_cfb      = false
    self.prepare_cfw      = false
    self.casting_cfw      = false
    self.use_charged_maneuvers = false
    self.wounds           = {}
    self.blessed_room     = false
    self.charges_total    = nil
    self.skip_all_weapon_max_check = false
    self.reset_stance     = false
    self.focus_threshold_active = false
    self.offhand_last_exp = -1
    self.last_offhand_skill = ""

    -- Private state
    self._clean_up_step   = nil
    self._target_weapon_skill = -1
    self._no_skins        = {}
    self._no_dissect      = {}
    self._constructs      = {}
    self._no_stab_mobs    = {}
    self._no_loot         = {}
    self.dancing          = false
    self.retreating       = false
    self.action_count     = 0
    self.charges          = nil
    self.aim_queue        = {}
    self.dance_queue      = {}
    self.analyze_combo_array = {}
    self.currently_whirlwinding = false
    self._avtalia_cambrinth = {}
    self._barb_analyzes   = {accuracy=50, damage=125, balance=600, flame=0}
    self._no_gain_list    = {}
    self._offhand_blacklist = {}
    self._offhand_no_gain_list = {}
    self.last_exp         = -1
    self.last_action_count = 0

    -- Settings
    self._left_hand_free  = settings.left_hand_free
    self._dynamic_dance_skill = settings.dynamic_dance_skill
    self.dance_skill      = settings.dance_skill
    self.target_action_count = settings.combat_trainer_action_count or 5
    self._target_action_count_original = self.target_action_count
    self.dance_threshold  = (settings.dance_threshold or 0)
    self.retreat_threshold = settings.retreat_threshold
    self._damaris_weapon_sets = settings.damaris_weapon_sets or {}
    self._damaris_weapon_states = {}
    self.summoned_weapons = settings.summoned_weapons or {}
    self.target_increment = settings.combat_trainer_target_increment or 0
    self._target_increment_original = self.target_increment
    self._gain_check      = settings.combat_trainer_gain_check
    self._offhand_gain_check = settings.combat_trainer_offhand_gain_check
    self._strict_weapon_stance = settings.strict_weapon_stance
    self.stances          = settings.stances or {}
    self.weapons_to_train = settings.weapon_training or {}
    self.whirlwind_trainables = settings.whirlwind_trainables or {}
    self._combat_training_abilities_target = settings.combat_training_abilities_target or 34
    self.aiming_trainables = settings.aiming_trainables or {}
    self.doublestrike_trainables = settings.doublestrike_trainables or {}
    self._charged_maneuvers = settings.charged_maneuvers or {}
    self.use_analyze_combos = settings.use_analyze_combos or settings.use_barb_combos
    self.use_stealth_attacks = settings.use_stealth_attacks
    self._use_stealth_ranged = settings.use_stealth_ranged
    self.ambush           = settings.ambush
    self.backstab         = settings.backstab
    self._backstab_past_mindlock = settings.backstab_past_mindlock
    self._ambush_stun_weapons = settings.ambush_stun_weapons or {}
    self.use_weak_attacks = settings.use_weak_attacks
    self._skip_last_kill  = settings.skip_last_kill
    self._stop_on_bleeding = settings.stop_hunting_if_bleeding
    self._is_empath       = DRStats.empath
    self._construct_mode  = settings.construct or false
    self._undead_mode     = settings.undead or false
    self._innocence_mode  = settings.innocence or false
    self._is_permashocked = settings.permashocked
    self.dedicated_camb_use = settings.dedicated_camb_use
    self.stored_cambrinth = settings.stored_cambrinth
    self.cambrinth        = settings.cambrinth
    self.cambrinth_cap    = settings.cambrinth_cap
    self.aim_fillers      = settings.aim_fillers or {}
    self.aim_fillers_stealth = settings.aim_fillers_stealth or {}
    self.dance_actions    = settings.dance_actions or {}
    self.dance_actions_stealth = settings.dance_actions_stealth or {}
    self._ignored_npcs    = settings.ignored_npcs or {}
    self.dual_load        = settings.dual_load
    self.summoned_weapons_element = settings.summoned_weapons_element
    self.summoned_weapons_ingot   = settings.summoned_weapons_ingot
    self.fatigue_regen_threshold  = settings.fatigue_regen_threshold
    self.balance_regen_threshold  = settings.balance_regen_threshold
    self.target_action_count = settings.combat_trainer_action_count or 5
    self._focus_threshold = settings.combat_trainer_focus_threshold

    -- Weapon training list initialisation
    for skill_name, _ in pairs(self.weapons_to_train) do
        self._no_gain_list[skill_name] = 0
    end
    for _, skill_name in ipairs(self.aiming_trainables) do
        self._offhand_no_gain_list[skill_name] = 0
    end

    -- Brawling blowgun augmentation
    if self:_is_brawling_ranged() then
        if not defs.tcontains(defs.AIM_SKILLS, "Brawling") then
            table.insert(defs.AIM_SKILLS, "Brawling")
        end
        if not defs.tcontains(defs.RANGED_SKILLS, "Brawling") then
            table.insert(defs.RANGED_SKILLS, "Brawling")
        end
    end

    -- Offhand thrown augmentation
    if settings.offhand_thrown then
        if not defs.tcontains(defs.THROWN_SKILLS, "Offhand Weapon") then
            table.insert(defs.THROWN_SKILLS, "Offhand Weapon")
        end
    end

    -- Stance validation and normalization
    for weapon, stance_list in pairs(self.stances) do
        local full = {"Evasion", "Shield Usage", "Parry Ability"}
        for _, needed in ipairs(full) do
            if not defs.tcontains(stance_list, needed) then
                table.insert(stance_list, needed)
            end
        end
    end

    -- Initial weapon
    self._current_weapon_skill = nil
    self._current_whirlwind_offhand_skill = nil
    self._last_whirlwind_offhand_skill = nil

    return self
end

--- Internal helper: check if brawling weapon is a blowgun (ranged brawl).
function M:_is_brawling_ranged()
    local brawl_info = self.weapons_to_train["Brawling"]
    if not brawl_info then return false end
    local name = type(brawl_info) == "string" and brawl_info or ""
    return name:match("blowgun") ~= nil
end

---------------------------------------------------------------------------
-- Cleanup state machine
---------------------------------------------------------------------------

function M:next_clean_up_step()
    local step = self._clean_up_step
    if step == nil then
        if self._stop_on_bleeding and bleeding() then
            self._clean_up_step = "clear_magic"
        elseif self._skip_last_kill then
            self._clean_up_step = "clear_magic"
        else
            self._clean_up_step = "kill"
        end
    elseif step == "kill" then
        self._clean_up_step = "clear_magic"
    elseif step == "clear_magic" then
        self._clean_up_step = "dismiss_pet"
    elseif step == "dismiss_pet" then
        self._clean_up_step = "stow"
    elseif step == "stow" then
        self._clean_up_step = "done"
    end
end

function M:cleaning_up()   return self._clean_up_step ~= nil end
function M:finish_killing() return self._clean_up_step == "kill" end
function M:finish_spell_casting() return self._clean_up_step == "clear_magic" end
function M:dismiss_pet()   return self._clean_up_step == "dismiss_pet" end
function M:stowing()       return self._clean_up_step == "stow" end
function M:done_cleaning_up() return self._clean_up_step == "done" end

---------------------------------------------------------------------------
-- NPC tracking
---------------------------------------------------------------------------

function M:update_room_npcs()
    local all = DRRoom.npcs or {}
    local filtered = {}
    for _, npc in ipairs(all) do
        local noun = type(npc) == "table" and npc.noun or npc
        if not defs.tcontains(self._ignored_npcs, noun)
           and not defs.tcontains(self._constructs, noun) then
            table.insert(filtered, noun)
        end
    end
    self._npcs = filtered
end

function M:npcs()
    return self._npcs or {}
end

---------------------------------------------------------------------------
-- Weapon management
---------------------------------------------------------------------------

function M:weapon_skill()
    return self._current_weapon_skill
end

function M:weapon_name()
    if not self._current_weapon_skill then return nil end
    return self.weapons_to_train[self._current_weapon_skill]
end

function M:last_weapon_name()
    if not self.last_weapon_skill then return nil end
    return self.weapons_to_train[self.last_weapon_skill]
end

function M:update_weapon_info(skill)
    self.last_weapon_skill = self._current_weapon_skill
    self._current_weapon_skill = skill
end

function M:update_target_weapon_skill()
    -- Force target_weapon_skill recalculation
    self._target_weapon_skill = -1
end

function M:whirlwind_offhand_skill()
    return self._current_whirlwind_offhand_skill
end

function M:whirlwind_offhand_name()
    if not self._current_whirlwind_offhand_skill then return nil end
    return self.weapons_to_train[self._current_whirlwind_offhand_skill]
end

function M:update_whirlwind_weapon_info(skill)
    self._last_whirlwind_offhand_skill = self._current_whirlwind_offhand_skill
    self._current_whirlwind_offhand_skill = skill
end

function M:whirlwind_trainable()
    if not self.whirlwind_trainables or #self.whirlwind_trainables == 0 then return false end
    return defs.tcontains(self.whirlwind_trainables, self:weapon_skill())
end

function M:sheath_whirlwind_offhand()
    if not self.currently_whirlwinding then return end
    local name = self:whirlwind_offhand_name()
    if not name then return end
    if not DRC.left_hand then return end
    self._equip_mgr.stow_weapon(name)
end

function M:wield_whirlwind_offhand()
    if not self.currently_whirlwinding then return end
    local skill = self:whirlwind_offhand_skill()
    local name = self:whirlwind_offhand_name()
    if not skill or not name then return end
    self._equip_mgr.wield_weapon(name, skill)
end

function M:wield_weapon()
    local name = self:weapon_name()
    local skill = self:weapon_skill()
    if name and skill then
        self._equip_mgr.wield_weapon(name, skill)
    end
end

--- Wield an offhand weapon for dual-wielding purposes. Returns weapon name.
function M:wield_offhand_weapon(skill)
    local name = self.weapons_to_train[skill]
    if not name then return nil end
    self._equip_mgr.wield_weapon(name, skill)
    return name
end

function M:sheath_offhand_weapon(skill)
    if skill == "Brawling" or skill == "Tactics" then return end
    local name = self.weapons_to_train[skill]
    if name then self._equip_mgr.stow_weapon(name) end
end

---------------------------------------------------------------------------
-- Skill predicate helpers
---------------------------------------------------------------------------

function M:melee_weapon_skill()
    return defs.tcontains(defs.MELEE_SKILLS, self:weapon_skill())
end

function M:ranged_skill()
    return self:aimed_skill() or self:thrown_skill()
end

function M:aimed_skill()
    return defs.tcontains(defs.AIM_SKILLS, self:weapon_skill())
end

function M:thrown_skill()
    return defs.tcontains(defs.THROWN_SKILLS, self:weapon_skill())
end

function M:twohanded_weapon_skill()
    return defs.tcontains(defs.TWOHANDED_SKILLS, self:weapon_skill())
end

function M:offhand()
    -- Using offhand attack
    return self._left_hand_free == false and DRC.left_hand ~= nil
end

function M:dual_load_p()
    return self.dual_load == true
end

---------------------------------------------------------------------------
-- Action counting
---------------------------------------------------------------------------

function M:action_taken(count)
    count = count or 1
    self.action_count = self.action_count + count
end

function M:reset_action_count()
    self.action_count = 0
end

function M:skill_done()
    if self.action_count < self.target_action_count then return false end
    -- Check XP gain since last switch
    local current_xp = DRSkill.getxp(self:weapon_skill() or "")
    if self._gain_check and current_xp <= self.last_exp and self.action_count >= self.last_action_count + 3 then
        -- No gain — blacklist this weapon temporarily
        self._no_gain_list[self:weapon_skill()] = (self._no_gain_list[self:weapon_skill()] or 0) + 1
        self.skip_all_weapon_max_check = true
    end
    self.last_exp = current_xp
    self.last_action_count = self.action_count
    self.target_action_count = self.target_action_count + (self.target_increment or 0)
    return true
end

function M:stop_weak_attacks()
    self.analyze_combo_array = {}
end

function M:stop_analyze_combo()
    self.analyze_combo_array = {}
end

---------------------------------------------------------------------------
-- Stance helpers
---------------------------------------------------------------------------

function M:current_weapon_stance()
    local skill = self:weapon_skill()
    if not skill then return nil end
    return self.stances[skill]
end

function M:strict_weapon_stance()
    return self._strict_weapon_stance
end

---------------------------------------------------------------------------
-- Dancing / retreating
---------------------------------------------------------------------------

function M:dance()
    -- Perform a dance action
    local actions = self:_dance_action_list()
    if #actions == 0 then return end
    local action = actions[math.random(#actions)]
    fput(action)
    waitrt()
end

function M:_dance_action_list()
    if self:_dance_stealth_p() then
        return self.dance_actions_stealth
    end
    return self.dance_actions
end

function M:_dance_stealth_p()
    return self.dance_actions_stealth
        and #self.dance_actions_stealth > 0
        and self:_use_stealth_p()
end

function M:_use_stealth_p()
    return DRSkill.getxp("Stealth") < self._combat_training_abilities_target
end

function M:dancing_p()
    return self.dancing
end

function M:retreating_p()
    return self.retreating
end

---------------------------------------------------------------------------
-- Retreat / engage
---------------------------------------------------------------------------

function M:engage()
    if not self:can_engage() then return end
    if not self:_stomp() then
        if not self:_pounce() then
            local result = DRC.bput("engage",
                "You are already advancing", "You begin to advance",
                "You begin to stealthily advance",
                "There is nothing else", "is already quite dead",
                "What do you want to advance towards")
            if result:match("advancing") or result:match("advance") then
                pause(2)
            end
        end
    end
end

function M:can_engage()
    return self:can_face() and not self:retreating_p()
end

function M:can_face()
    if self._innocence_mode then return false end
    return #self:npcs() > 0
end

function M:_stomp()
    -- Placeholder — stomp logic is in GameState
    return false
end

function M:_pounce()
    -- Placeholder — pounce logic is in GameState
    return false
end

---------------------------------------------------------------------------
-- Empathy / offense permission
---------------------------------------------------------------------------

function M:is_offense_allowed()
    if self:_is_permashocked_p() then return true end
    if self._construct_mode then return true end
    if self._undead_mode and DRSpells.active_spells["Absolution"] then return true end
    if not self._is_empath then return true end
    return false
end

function M:_is_permashocked_p()
    if not self._is_empath then return true end
    return self._is_permashocked == true
end

function M:construct_mode_p()
    return self._construct_mode
end

---------------------------------------------------------------------------
-- Skinning / dissect / loot state
---------------------------------------------------------------------------

function M:skinnable(noun)
    return not defs.tcontains(self._no_skins, noun)
end

function M:unskinnable(noun)
    if not defs.tcontains(self._no_skins, noun) then
        table.insert(self._no_skins, noun)
    end
end

function M:dissectable(noun)
    return not defs.tcontains(self._no_dissect, noun)
end

function M:undissectable(noun)
    if not defs.tcontains(self._no_dissect, noun) then
        table.insert(self._no_dissect, noun)
    end
end

function M:construct(noun)
    if not defs.tcontains(self._constructs, noun) then
        table.insert(self._constructs, noun)
    end
end

function M:construct_p(noun)
    return defs.tcontains(self._constructs, noun)
end

function M:stabbable(noun)
    return not defs.tcontains(self._no_stab_mobs, noun)
end

function M:unstabbable(noun)
    if not defs.tcontains(self._no_stab_mobs, noun) then
        table.insert(self._no_stab_mobs, noun)
    end
end

function M:lootable(item)
    return not defs.tcontains(self._no_loot, item)
end

function M:unlootable(item)
    if not defs.tcontains(self._no_loot, item) then
        table.insert(self._no_loot, item)
    end
end

---------------------------------------------------------------------------
-- Necromancer state helpers
---------------------------------------------------------------------------

function M:necro_casting()
    return self.casting_cfb or self.casting_cfw or self.casting_nr or self.casting_consume
end

function M:cfb_active()
    return DRSpells.active_spells["Consume the Flesh"] ~= nil
end

function M:cfw_active()
    return DRSpells.active_spells["Consume the Flesh"] ~= nil  -- bonebug relies on same spell
end

---------------------------------------------------------------------------
-- Charged maneuvers
---------------------------------------------------------------------------

function M:charged_maneuver()
    return self._charged_maneuvers
end

function M:charged_maneuver_off_cooldown(maneuver)
    local key = maneuver:lower()
    local t = self.cooldown_timers[key]
    if not t then return true end
    return (os.time() - t) >= 30  -- default 30s cooldown
end

function M:determine_charged_maneuver()
    local skill = self:weapon_skill()
    if not skill then return nil end
    local maneuver = self._charged_maneuvers[skill]
    if not maneuver then return nil end
    if self:charged_maneuver_off_cooldown(maneuver) then
        return maneuver
    end
    return nil
end

function M:use_charged_maneuver(maneuver)
    local result = DRC.bput("maneuver " .. maneuver,
        "You feel the adrenaline",
        "You launch into a", "You step into", "You sweep",
        "You perform a", "You attempt a",
        "Roundtime", "cannot repeat", "not ready", "must be closer",
        "must be wielding", "You need to hold", "not enough focus")
    waitrt()
    if result:match("cannot repeat") or result:match("not ready") then
        return false
    end
    self.cooldown_timers[maneuver:lower()] = os.time()
    return true
end

---------------------------------------------------------------------------
-- Summoned weapon helpers
---------------------------------------------------------------------------

function M:summoned_info(skill)
    if not skill then return nil end
    for _, info in ipairs(self.summoned_weapons) do
        if info["skill"] == skill or info["name"] == skill then
            return info
        end
    end
    return nil
end

function M:prepare_summoned_weapon(last_summoned)
    -- Signal spell process to cast summoned weapon spell
    self.prepare_nr = false  -- will be set by spell process as needed
end

---------------------------------------------------------------------------
-- Aiming
---------------------------------------------------------------------------

function M:set_aim_queue()
    local skill = self:weapon_skill()
    local fillers
    if self:_aim_stealth_p() then
        fillers = self.aim_fillers_stealth[skill] or {}
    else
        fillers = self.aim_fillers[skill] or {}
    end
    self.aim_queue = {}
    for _, f in ipairs(fillers) do
        table.insert(self.aim_queue, f)
    end
end

function M:next_aim_action()
    if #self.aim_queue == 0 then return "" end
    -- Rotate the queue
    local action = table.remove(self.aim_queue, 1)
    table.insert(self.aim_queue, action)
    return action
end

function M:clear_aim_queue()
    self.aim_queue = {}
end

function M:_aim_stealth_p()
    if not self.aim_fillers_stealth then return false end
    local skill = self:weapon_skill()
    return self.aim_fillers_stealth[skill] ~= nil and self:_use_stealth_p()
end

---------------------------------------------------------------------------
-- Dancing queue
---------------------------------------------------------------------------

--- Populate the dance queue from dance_actions / dance_actions_stealth.
--- No-ops if the queue is already in progress.
function M:set_dance_queue()
    if #self.dance_queue > 0 then return end
    local actions
    if self.dance_actions_stealth
        and #self.dance_actions_stealth > 0
        and self:_use_stealth_p() then
        actions = self.dance_actions_stealth
    else
        actions = self.dance_actions
    end
    self.dance_queue = {}
    for _, a in ipairs(actions or {}) do
        table.insert(self.dance_queue, a)
    end
end

--- Return and remove the next action from the dance queue.
-- Returns nil when the queue is empty.
function M:next_dance_action()
    if #self.dance_queue == 0 then return nil end
    return table.remove(self.dance_queue, 1)
end

---------------------------------------------------------------------------
-- Fatigue / balance
---------------------------------------------------------------------------

function M:fatigue_low()
    if not self.fatigue_regen_threshold then return false end
    return GameState.stamina < self.fatigue_regen_threshold
end

function M:balance_low()
    if not self.balance_regen_threshold then return false end
    -- No direct balance check in Revenant — use stamina proxy
    return false
end

---------------------------------------------------------------------------
-- Backstab / ambush
---------------------------------------------------------------------------

function M:backstab_p()
    if not self.backstab then return false end
    if self._backstab_past_mindlock then return true end
    return DRSkill.getxp("Backstab") < self._combat_training_abilities_target
end

function M:ambush_p()
    return self.ambush == true
end

function M:use_stealth_attack()
    return self.use_stealth_attacks == true
end

function M:use_stealth_ranged()
    return self._use_stealth_ranged == true
end

function M:ambush_stun_training()
    if not self._ambush_stun_weapons then return false end
    local wname = self:weapon_name()
    if not wname then return false end
    return defs.tcontains(self._ambush_stun_weapons, wname)
end

function M:melee_attack_verb()
    local skill = self:weapon_skill()
    if not skill then return "attack" end
    local overrides = self._attack_overrides or {}
    return overrides[skill] or "attack"
end

function M:thrown_attack_verb()
    local wname = self:weapon_name() or ""
    if wname:match("whip") then return "snap" end
    if wname:match("blades") then return "throw blade" end
    return "throw"
end

function M:thrown_retrieve_verb()
    local wname = self:weapon_name() or ""
    if self:_bound_weapon_p() then return "invoke" end
    return "get my " .. wname
end

function M:_bound_weapon_p(name)
    name = name or self:weapon_name()
    if not name then return false end
    local item = self._equip_mgr.item_by_desc(name)
    return item and item.bound
end

---------------------------------------------------------------------------
-- Sorting helpers
---------------------------------------------------------------------------

--- Sort skills by learning rate (XP) then rank, with optional priorities.
-- Matches sort_by_rate_then_rank from Lich5.
function M:sort_by_rate_then_rank(skills, priorities)
    priorities = priorities or {}
    local scored = {}
    for _, skill in ipairs(skills) do
        table.insert(scored, {
            skill = skill,
            xp    = DRSkill.getxp(skill),
            prio  = defs.tcontains(priorities, skill) and -1 or 0,
            rank  = DRSkill.getrank(skill),
        })
    end
    table.sort(scored, function(a, b)
        if a.xp ~= b.xp then return a.xp < b.xp end
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.rank < b.rank
    end)
    local result = {}
    for _, s in ipairs(scored) do
        table.insert(result, s.skill)
    end
    return result
end

---------------------------------------------------------------------------
-- Whirlwind
---------------------------------------------------------------------------

function M:determine_whirlwind_weapon_skill()
    local weapon_skill = self:weapon_skill()
    if not weapon_skill then return nil end
    local options = {}
    for skill, _ in pairs(self.weapons_to_train) do
        table.insert(options, skill)
    end
    -- Exclude current main weapon skill
    options = defs.tdiff(options, {weapon_skill})
    -- Exclude two-handed
    options = defs.tdiff(options, defs.TWOHANDED_SKILLS)
    -- Exclude summoned weapons
    local summoned_names = {}
    for _, info in ipairs(self.summoned_weapons) do
        if info["name"] then table.insert(summoned_names, info["name"]) end
    end
    options = defs.tdiff(options, summoned_names)
    -- Filter to whirlwind_trainables candidates
    local ww_options = {}
    for _, skill in ipairs(options) do
        if defs.tcontains(self.whirlwind_trainables, skill) then
            table.insert(ww_options, skill)
        end
    end
    options = #ww_options > 0 and ww_options or options
    return self:sort_by_rate_then_rank(options)[1]
end

function M:determine_aiming_skill()
    local skill = self:weapon_skill()
    if not skill then return nil end
    local candidates = {}
    for _, s in ipairs(self.aiming_trainables) do
        if s ~= skill then
            table.insert(candidates, s)
        end
    end
    if #candidates == 0 then return nil end
    -- Filter out blacklisted
    local valid = {}
    for _, s in ipairs(candidates) do
        if not defs.tcontains(self._offhand_blacklist, s) then
            table.insert(valid, s)
        end
    end
    if #valid == 0 then return nil end
    return self:sort_by_rate_then_rank(valid)[1]
end

function M:determine_doublestrike_skill()
    local candidates = {}
    for _, s in ipairs(self.doublestrike_trainables) do
        if s ~= self:weapon_skill() then
            table.insert(candidates, s)
        end
    end
    if #candidates == 0 then return nil end
    return self:sort_by_rate_then_rank(candidates)[1]
end

---------------------------------------------------------------------------
-- Barbarian whirlwind flags
---------------------------------------------------------------------------

function M:reset_barb_whirlwind_flags_if_needed()
    if not DRStats.barbarian then return end
    if Flags["ct-barbarian-whirlwind-expired"] then
        Flags.reset("ct-barbarian-whirlwind")
        Flags.reset("ct-barbarian-whirlwind-expired")
    end
end

---------------------------------------------------------------------------
-- Attack override
---------------------------------------------------------------------------

function M:attack_override(skill)
    if not self._attack_overrides then return nil end
    skill = skill or self:weapon_skill() or ""
    return self._attack_overrides[skill]
end

return M
