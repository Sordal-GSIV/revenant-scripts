--- SpellProcess — spell casting and management for combat-trainer.
-- Ported from SpellProcess class in combat-trainer.lic
-- Original authors: Elanthia Online DR-Scripts contributors
local defs = require("defs")

local M = {}
M.__index = M

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function M.new(settings, equipment_manager)
    local self = setmetatable({}, M)
    self._equip_mgr = equipment_manager
    self._settings  = settings

    -- Buff spells: prefer a named waggle set if configured
    if settings.combat_buff_waggle
       and settings.waggle_sets
       and settings.waggle_sets[settings.combat_buff_waggle] then
        self._buff_spells = settings.waggle_sets[settings.combat_buff_waggle]
    else
        self._buff_spells = settings.buff_spells or {}
    end

    self._prioritize_offensive_spells = settings.prioritize_offensive_spells

    -- Offensive spells: prefer a named waggle set transformed to OST format
    if settings.OST_use_waggle
       and settings.waggle_sets
       and settings.waggle_sets[settings.OST_use_waggle] then
        self._offensive_spells = M._ost_waggle_transform(settings.waggle_sets[settings.OST_use_waggle])
    else
        self._offensive_spells = settings.offensive_spells or {}
    end

    self._training_spells                  = settings.combat_spell_training
    self._training_spells_max_threshold    = settings.combat_spell_training_max_threshold
    self._training_spells_wait             = settings.combat_spell_timer or 0
    self._magic_exp_training_max_threshold = settings.magic_exp_training_max_threshold or 34
    self._offensive_spell_cycle            = settings.offensive_spell_cycle or {}
    self._magic_last_spell                 = nil
    self._magic_last_exp                   = -1
    self._magic_gain_check                 = settings.combat_trainer_magic_gain_check or 0

    -- Per-skill no-gain counter (keyed by skill name)
    self._magic_no_gain_list = {}
    for _, spell in ipairs(self._offensive_spells) do
        if spell["skill"] then
            self._magic_no_gain_list[spell["skill"]] = 0
        end
    end

    self._necromancer_healing = settings.necromancer_healing
    self._corpse_healing      = (settings.waggle_sets or {})["corpse_healing"]
    self._necromancer_zombie  = (settings.waggle_sets or {})["zombie"] or {}
    self._necromancer_bonebug = (settings.waggle_sets or {})["bonebug"] or {}
    self._empath_spells        = settings.empath_healing or {}
    self._empath_vitality_threshold = settings.empath_vitality_threshold or 100

    self._osrel_timer            = os.time() - 1000
    self._osrel_amount           = settings.osrel_amount
    self._osrel_no_harness       = settings.osrel_no_harness
    self._osrel_mana_threshold   = settings.osrel_mana_threshold or 0
    self._osrel_need_mana        = false

    self._cast_only_to_train              = settings.cast_only_to_train
    self._offensive_spell_mana_threshold  = settings.offensive_spell_mana_threshold or 0
    self._training_spell_mana_threshold   = settings.training_spell_mana_threshold or 0
    self._training_spells_combat_sorcery  = settings.training_spells_combat_sorcery
    self._release_cyclic_on_low_mana      = settings.release_cyclic_on_low_mana
    self._release_cyclic_threshold        = settings.release_cyclic_threshold or 0
    self._buff_spell_mana_threshold       = settings.buff_spell_mana_threshold or 0

    self._cambrinth                   = settings.cambrinth
    self._cambrinth_cap               = settings.cambrinth_cap
    self._dedicated_camb_use          = settings.dedicated_camb_use
    self._stored_cambrinth            = settings.stored_cambrinth
    self._cambrinth_invoke_exact_amount = settings.cambrinth_invoke_exact_amount
    self._harness_for_attunement      = settings.use_harness_when_arcana_locked
    self._siphon_vit_threshold        = settings.necro_siphon_vit_threshold or 0
    self._ignored_npcs                = settings.ignored_npcs or {}
    self._hide_type                   = settings.hide_type
    self._buff_force_cambrinth        = settings.combat_trainer_buffs_force_cambrinth

    self._regalia_array = settings.cycle_armors_regalia
    self._regalia_spell = nil
    if settings.waggle_sets and settings.waggle_sets["regalia"] then
        self._regalia_spell = settings.waggle_sets["regalia"]["Regalia"]
    end

    self._aura_frequency    = settings.aura_frequency or 0
    self._barb_healing      = settings.barb_famine_healing or {}
    self._runestone_storage = settings.runestone_storage

    self._perc_health_timer   = os.time()
    self._aura_timer          = 0
    self._avtalia_timer       = os.time() - 290

    self._symbiosis_learning_threshold = settings.symbiosis_learning_threshold or 0

    -- Cast state tracking fields (cleared after each cast)
    self._custom_cast    = nil
    self._symbiosis      = nil
    self._barrage        = nil
    self._before         = nil
    self._after          = nil
    self._skill          = nil
    self._abbrev         = nil
    self._prep           = nil
    self._mana           = nil
    self._command        = nil
    self._prepared_spell = nil
    self._reset_expire   = nil
    self._use_auto_mana  = nil
    self._prep_time      = nil
    self._should_harness = nil
    self._should_invoke  = nil

    -- Sliver tracking
    self._checking_slivers    = false
    self._last_sliver_cast_time = nil

    -- Weapon buff tracking
    self._last_seen_weapon_buff_name = nil

    -- Spell timers (keyed by pet_type or abbrev)
    self._spell_timers = {}
    self._wounds       = {}

    -- TK (Telekinetic) ammo/spell
    self._tk_ammo  = settings.tk_ammo
    self._tk_spell = nil
    for _, spell in ipairs(self._offensive_spells) do
        if spell["abbrev"] and spell["abbrev"]:lower():match("tkt") or
           spell["abbrev"] and spell["abbrev"]:lower():match("tks") then
            self._tk_spell = spell
            break
        end
    end

    -- Timers set in the future so spells don't fire immediately on launch
    self._training_cast_timer   = os.time() + 45
    self._training_cyclic_timer = os.time() + 45

    -- Trader: regalia bespoke flag
    self._know_bespoke = false

    -- -----------------------------------------------------------------------
    -- Register Flags
    -- -----------------------------------------------------------------------
    Flags.add("ct-spelllost",
        "Your pattern dissipates with the loss of your target",
        "Your secondary spell pattern dissipates because your target is dead, but the main spell remains intact",
        "Your concentration lapses and you lose your targeting pattern")
    Flags.add("ct-need-bless", " passes through the .* with no effect")
    if DRStats.trader() then
        Flags.add("ct-starlight-depleted", "enough starlight")
        Flags.add("ct-regalia-expired", "Your .* glimmers? weakly")
        Flags.add("ct-regalia-succeeded", "You cup your palms skyward to bask in")
    end
    Flags.add("ct-shock-warning",
        "You are distinctly aware that completion of this spell pattern may bring you shock")
    Flags.add("ct-spellcast", "Cast Roundtime")

    -- Expire flags for offensive spells
    for _, spell in ipairs(self._offensive_spells) do
        if spell["expire"] then
            self:_add_spell_flag(spell["abbrev"], spell["expire"])
        end
    end
    -- Expire flags for buff spells (buff_spells is a hash of name->data)
    for _name, data in pairs(self._buff_spells) do
        if type(data) == "table" and data["expire"] then
            self:_add_spell_flag(data["abbrev"], data["expire"])
        end
    end

    -- Drop TK ammo so it can be thrown
    self:_drop_tkt_ammo()
    Flags.add("need-tkt-ammo", "There is nothing here that can be thrown")

    -- Trader: check for bespoke regalia
    if DRStats.trader() and self._regalia_array then
        if self._regalia_array and self._regalia_spell == nil then
            -- Will be fetched from spell data at runtime if needed
        end
        if checkprep ~= "None" then
            DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
        end
        local bspk_result = DRC.bput("pre bspk",
            "Bespoke Regalia", "You have no idea", "fully prepared", "already preparing")
        self._know_bespoke = (bspk_result == "Bespoke Regalia")
    end

    return self
end

-- ---------------------------------------------------------------------------
-- execute — main per-loop entry point
-- ---------------------------------------------------------------------------

function M:execute(game_state)
    if game_state:stowing() then return true end
    if game_state:dismiss_pet() then return false end

    self:_check_timer(game_state)

    if game_state:finish_spell_casting() then
        game_state:next_clean_up_step()
        if DRStats.guild() == "Bard" and self._settings.segue_spell_on_stop then
            DRCA.segue(self._settings.segue_spell_on_stop, self._settings.segue_prep_on_stop)
        end
        DRCA.release_cyclics(self._settings.cyclic_no_release)
        if not checkprep then
            DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
            DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
            if self._symbiosis then
                DRC.bput("release symb", "You release the", "But you haven't prepared a symbiosis")
            end
        end
        if self._tk_ammo then
            waitrt()
            pause(1)
            fput("stow " .. self._tk_ammo)
        end
        if self._regalia_array then
            DRCA.shatter_regalia()
        end
        return true
    end

    if Flags["ct-spelllost"] then
        game_state.casting = false
        Flags.reset("ct-spelllost")
    end

    self:_check_osrel(game_state)
    if self._osrel_need_mana then return false end

    -- When a mob dies, mark all non-cyclic, non-heavy expire offensive spells as needing recast
    if game_state.mob_died then
        for _, spell in ipairs(self._offensive_spells) do
            if spell["expire"] and not spell["cyclic"] and not spell["heavy"] then
                Flags["ct-" .. spell["abbrev"]] = true
            end
        end
    end

    if Flags["need-tkt-ammo"] then
        Flags.reset("need-tkt-ammo")
        self:_drop_tkt_ammo()
    end

    self:_check_slivers(game_state)
    self:_check_regalia(game_state)
    self:_check_consume(game_state)
    self:_check_cfw(game_state)
    self:_heal_corpse(game_state)
    self:_check_cfb(game_state)
    self:_check_bless(game_state)
    self:_check_ignite(game_state)
    self:_check_rutilors_edge(game_state)
    self:_check_health(game_state)
    self:_check_starlight(game_state)
    self:_check_avtalia(game_state)
    self:_check_buffs(game_state)

    if self._prioritize_offensive_spells then
        self:_check_offensive(game_state)
        self:_check_training(game_state)
    else
        self:_check_training(game_state)
        self:_check_offensive(game_state)
    end

    self:_check_current(game_state)
    return false
end

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

function M:_add_spell_flag(name, expire)
    Flags.add("ct-" .. name, expire)
    Flags["ct-" .. name] = true
end

function M:_drop_tkt_ammo()
    if not self._tk_ammo then return end
    fput("get my " .. self._tk_ammo)
    fput("drop " .. self._tk_ammo)
end

-- Transform waggle sets (hash of hashes) into offensive spell format (array of hashes)
function M._ost_waggle_transform(waggles)
    local offensive_spells = {}
    for name, spell_data in pairs(waggles) do
        local entry = {name = name}
        for k, v in pairs(spell_data) do entry[k] = v end
        table.insert(offensive_spells, entry)
    end
    return offensive_spells
end

function M:_check_osrel(game_state)
    if game_state.casting then return end
    if not self._osrel_amount then return end
    if not (DRSpells.active_spells and DRSpells.active_spells["Osrel Meraud"]) then return end
    if (os.time() - self._osrel_timer) <= 300 then return end
    if (DRSpells.active_spells["Osrel Meraud"] or 0) >= 90 then return end

    if DRStats.mana <= self._osrel_mana_threshold then
        self._osrel_need_mana = true
        return
    end

    self._osrel_timer = os.time()
    DRCA.infuse_om(not self._osrel_no_harness, self._osrel_amount)
    self._osrel_need_mana = false
end

function M:_check_timer(game_state)
    if game_state.cast_timer == nil then return end
    if (os.time() - game_state.cast_timer) <= 70 then return end

    game_state.cast_timer = nil
    if game_state.casting then
        DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
        DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
    end
    game_state.casting = false
end

function M:_check_avtalia(game_state)
    if not self._settings.avtalia_array or #self._settings.avtalia_array == 0 then return end
    if (os.time() - self._avtalia_timer) <= 360 then return end
    if DRStats.mana >= 90 then return end
    if game_state.casting then return end

    DRCA.update_avtalia()
    self._avtalia_timer = os.time()
end

function M:_check_regalia(game_state)
    if not self._regalia_array then return end
    if not game_state.swap_regalia_type then return end
    if game_state.swap_regalia_type == game_state.last_regalia_type
       and not Flags["ct-regalia-expired"] then return end
    if game_state.casting then return end
    if game_state.loaded then return end
    if DRStats.mana < self._buff_spell_mana_threshold then return end

    local armor_word
    local swt = game_state.swap_regalia_type
    if swt == "Light Armor" then
        armor_word = "light"
    elseif swt == "Chain Armor" then
        armor_word = "chain"
    elseif swt == "Brigandine" then
        armor_word = "brigandine"
    elseif swt == "Plate Armor" then
        armor_word = "plate"
    end

    if self._regalia_spell then
        self._regalia_spell["cast"] = self._know_bespoke
            and ("cast " .. (armor_word or "") .. " all")
            or "cast"
        self:_prepare_spell(self._regalia_spell, game_state)
    end
end

function M:_check_bless(game_state)
    if game_state.casting then return end
    if not self._buff_spells["Bless"] then return end
    if not Flags["ct-need-bless"] then return end

    Flags.reset("ct-need-bless")
    DRCA.prepare("Bless", 1)
    local target = DRC.right_hand or DRC.left_hand
    if target then
        DRCA.cast("cast " .. target)
    else
        DRCA.cast("cast")
    end
end

function M:_check_ignite(game_state)
    if self._last_seen_weapon_buff_name == game_state:weapon_name() then return end
    if not (DRSpells.active_spells and DRSpells.active_spells["Ignite"]) then return end

    DRC.bput("release ignite",
        "The warm feeling in your hand goes away", "Release what")
    pause(1)
end

function M:_check_rutilors_edge(game_state)
    if self._last_seen_weapon_buff_name == game_state:weapon_name() then return end
    if not (DRSpells.active_spells and DRSpells.active_spells["Rutilor's Edge"]) then return end

    DRC.bput("release rue",
        "You sense the Rutilor's Edge spell fade away", "Release what")
    pause(1)
end

function M:_ready_to_cast(game_state)
    return Flags["ct-spellcast"]
        or (self._prep_time and game_state.cast_timer
            and (os.time() - game_state.cast_timer) >= self._prep_time)
end

function M:_check_current(game_state)
    if not game_state.casting then return end

    if game_state.casting_cyclic then
        game_state:avtalia_cyclic(self._mana)
    end
    if self._should_invoke then
        if game_state:check_charging() then return end
    end

    if not self:_ready_to_cast(game_state) then return end

    if self._should_harness then
        game_state:check_harness()
    end
    self:_cast_spell(game_state)
end

function M:_check_invoke(game_state)
    if not self._should_invoke then return end
    if self._cambrinth_invoke_exact_amount and game_state.charges_total == 0 then return end

    DRCA.find_cambrinth(self._cambrinth, self._stored_cambrinth, self._cambrinth_cap)
    local invoke_amount = self._cambrinth_invoke_exact_amount and game_state.charges_total or nil
    self._should_invoke = nil
    game_state.charges_total = nil
    DRCA.invoke(self._cambrinth, self._dedicated_camb_use, invoke_amount)
    DRCA.stow_cambrinth(self._cambrinth, self._stored_cambrinth, self._cambrinth_cap)
end

function M:_cast_spell(game_state)
    self:_check_invoke(game_state)

    if game_state.casting_weapon_buff then
        self._custom_cast = "cast my " .. tostring(game_state:weapon_name())
        self._last_seen_weapon_buff_name = game_state:weapon_name()
    end

    if game_state.casting_consume then
        if self._necromancer_healing
           and self._necromancer_healing["Consume Flesh"]
           and not self._necromancer_healing["Devour"] then
            -- Target the most severely wounded body part
            local wounds = game_state.wounds or {}
            local max_sev, max_wound = -1, nil
            for sev, wound_list in pairs(wounds) do
                if type(sev) == "number" and sev > max_sev then
                    max_sev  = sev
                    max_wound = wound_list
                end
            end
            if max_wound and max_wound[1] and max_wound[1].body_part then
                self._custom_cast = "cast " .. max_wound[1].body_part
            end
        end
    end

    if game_state.hide_on_cast and game_state:use_stealth() then
        DRC.hide(self._hide_type)
    end

    if game_state.casting_sorcery then
        self._equip_mgr.stow_weapon(game_state:weapon_name())
    end

    if game_state.casting_regalia then
        local result = DRCA.parse_regalia()
        if not result or result == "" then
            -- Not wearing regalia yet: retreat, swap gear set, re-wield
            DRC.retreat()
            self._equip_mgr.wear_equipment_set("regalia")
            if self._settings.gear_sets
               and self._settings.gear_sets["regalia"]
               and defs.tcontains(self._settings.gear_sets["regalia"], game_state:weapon_name()) then
                self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
            end
        else
            -- Already wearing regalia: shatter first, then recast
            DRCA.shatter_regalia(result)
        end
    end

    -- Warrior Mage elemental barrage
    if self._prep == "target" and self._barrage and game_state:can_use_barrage_attack() then
        self._custom_cast = "barrage " .. tostring(game_state:melee_attack_verb())
    end

    if game_state:is_offense_allowed() or (self._prepared_spell and self._prepared_spell["harmless"]) then
        local snapshot = DRSkill.getxp(self._skill or "")
        local success = DRCA.cast(self._custom_cast, self._symbiosis, self._before, self._after)
        if (self._symbiosis or self:_spell_is_sorcery(self._prepared_spell)) and self._use_auto_mana then
            if not success then
                if UserVars.discerns and UserVars.discerns[self._abbrev] then
                    UserVars.discerns[self._abbrev]["more"] =
                        math.max((UserVars.discerns[self._abbrev]["more"] or 0) - 1, 0)
                end
                if self._prepared_spell then
                    self._prepared_spell["failed"] = true
                end
            elseif DRSkill.getxp(self._skill or "") - snapshot < self._symbiosis_learning_threshold
                   and not (self._prepared_spell and self._prepared_spell["failed"]) then
                if UserVars.discerns and UserVars.discerns[self._abbrev] then
                    UserVars.discerns[self._abbrev]["more"] =
                        (UserVars.discerns[self._abbrev]["more"] or 0) + 1
                end
            end
        end
    else
        DRC.message("Dropping spell: Offensive magic is not allowed right now...")
        DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
        DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
    end

    -- Clear all cast-state fields
    local abbrev_was    = self._abbrev
    local command_was   = self._command
    local reset_expire  = self._reset_expire

    self._custom_cast    = nil
    self._symbiosis      = nil
    self._barrage        = nil
    self._before         = nil
    self._after          = nil
    self._skill          = nil
    self._abbrev         = nil
    self._use_auto_mana  = nil
    self._prepared_spell = nil
    self._reset_expire   = nil
    self._command        = nil

    game_state.hide_on_cast      = false
    game_state.casting           = false
    game_state.cast_timer        = nil
    game_state.casting_weapon_buff = false
    game_state.casting_consume   = false
    game_state.casting_nr        = false
    game_state.casting_cfb       = false
    game_state.casting_cfw       = false
    game_state.casting_cyclic    = false

    -- Post-cast actions
    self:_blacklist_spells(game_state)

    if game_state.casting_sorcery then
        game_state.casting_sorcery = false
        self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
    end

    if game_state.casting_moonblade then
        local lh = DRC.left_hand or ""
        if lh:match("moon") or game_state:brawling() or game_state:offhand() then
            DRCMM.wear_moon_weapon()
        end
        game_state.casting_moonblade = false
    end

    self:_check_trader_magic(game_state)

    if reset_expire then
        Flags.reset("ct-" .. reset_expire)
    end

    if command_was then
        -- Escape valve in case spell immediately fails (anti-magic, etc.)
        local temp_count = 0
        while not defs.tcontains(DRRoom.npcs or {}, "warrior") and temp_count < 20 do
            pause(0.5)
            temp_count = temp_count + 1
        end
        fput("command " .. command_was)
    end
end

function M:_check_spell_timer(data)
    local key = data["pet_type"] or data["abbrev"]
    local last = self._spell_timers[key] or 0
    return (os.time() - last) >= (data["recast_every"] or 0)
end

function M:_check_buff_conditions(name, game_state)
    if defs.tcontains(defs.WEAPON_BUFFS, name) then
        if game_state:aimed_skill() or game_state:brawling() then
            return false
        end
    end
    -- Resonance doesn't appear in active spells; track by last weapon name
    if name == "Resonance" and self._last_seen_weapon_buff_name == game_state:weapon_name() then
        return false
    end
    return true
end

function M:_check_training(game_state)
    if game_state.casting then return end
    if not self._training_spells then return end
    if self._training_spells_max_threshold then
        local npcs = game_state:npcs() or {}
        if #npcs > self._training_spells_max_threshold then return end
    end

    if self._release_cyclic_on_low_mana and DRStats.mana < self._release_cyclic_threshold then
        DRCA.release_cyclics()
    end
    if DRStats.mana < self._training_spell_mana_threshold then return end

    local skill_order = {"Warding", "Utility", "Augmentation", "Sorcery", "Debilitation", "Targeted Magic"}
    local now = os.time()
    local npcs = game_state:npcs() or {}

    local needs_training = nil
    local eligible = {}
    for _, skill in ipairs(skill_order) do
        local data = self._training_spells[skill]
        if not data then goto continue end
        if not game_state:is_offense_allowed() and not data["harmless"] then goto continue end
        -- Non-combat skills only need a mob for Sorcery (unless training_spells_combat_sorcery)
        if skill == "Sorcery" and self._training_spells_combat_sorcery then goto continue end
        if (skill == "Sorcery" or skill == "Debilitation" or skill == "Targeted Magic")
           and #npcs == 0 then goto continue end
        if DRSkill.getxp(skill) >= self._magic_exp_training_max_threshold then goto continue end
        local timer = data["cyclic"] and self._training_cyclic_timer or self._training_cast_timer
        if now <= timer then goto continue end
        if data["night"]  and not (UserVars.sun and UserVars.sun["night"]) then goto continue end
        if data["day"]    and not (UserVars.sun and UserVars.sun["day"])   then goto continue end
        if data["bright_celestial_object"] and not DRCMM.bright_celestial_object() then goto continue end
        if data["any_celestial_object"]    and not DRCMM.any_celestial_object()    then goto continue end
        if data["no_bright_celestial_object"] and DRCMM.bright_celestial_object()  then goto continue end
        if data["no_celestial_object"]     and DRCMM.any_celestial_object()        then goto continue end
        if data["must_be_true"]            and not (load("return " .. data["must_be_true"])()) then goto continue end
        table.insert(eligible, skill)
        ::continue::
    end

    if #eligible == 0 then return end

    -- Sort by rate then rank; pick first
    local sorted = game_state:sort_by_rate_then_rank(eligible)
    needs_training = sorted and sorted[1] or nil
    if not needs_training then return end

    local data = self._training_spells[needs_training]
    self._training_cast_timer = now + self._training_spells_wait
    if data["cyclic"] then
        self._training_cyclic_timer = now + 325
    elseif self._training_cyclic_timer < self._training_cast_timer then
        self._training_cyclic_timer = self._training_cast_timer
    end

    if data["use_stealth"] then game_state.hide_on_cast = true end

    if self:_spell_is_sorcery(data) then
        game_state.casting_sorcery = true
    end

    self:_prepare_spell(data, game_state)
    Flags.reset("ct-spelllost")
end

function M:_spell_is_sorcery(spell_data)
    if not spell_data then return false end
    if spell_data["sorcery"] then return true end
    if not spell_data["mana_type"] then return false end
    if DRStats.native_mana and
       DRStats.native_mana:lower() == spell_data["mana_type"]:lower() then
        return false
    end
    if spell_data["mana_type"]:lower() == "ap" then return false end
    return true
end

function M:_cast_runestone(data, game_state)
    DRCA.prepare_to_cast_runestone(data, self._settings)
    if not DRCI.in_hands(data["runestone_name"]) then return end

    self:_prepare_spell(data, game_state, self._buff_force_cambrinth)
    if not DRCI.in_hands(data["runestone_name"]) then return end

    DRCI.put_away_item(data["runestone_name"], self._runestone_storage)
end

function M:_check_buffs(game_state)
    if game_state.casting then return end
    if DRStats.mana < self._buff_spell_mana_threshold then return end

    -- Collect recastable buffs
    local recastable = {}
    for name, data in pairs(self._buff_spells) do
        if type(data) ~= "table" then goto continue end
        if not (data["recast"] or data["recast_every"] or data["expire"]) then goto continue end
        if data["expire"] and not Flags["ct-" .. (data["abbrev"] or "")] then goto continue end
        if not self:_check_buff_conditions(name, game_state) then goto continue end
        if data["night"]  and not (UserVars.sun and UserVars.sun["night"]) then goto continue end
        if data["day"]    and not (UserVars.sun and UserVars.sun["day"])   then goto continue end
        if data["starlight_threshold"] and not self:_enough_starlight(game_state, data) then goto continue end
        if data["must_be_true"] and not (load("return " .. data["must_be_true"])()) then goto continue end
        -- Cyclic that is already active and doesn't have recast_every: skip
        if data["cyclic"] and not data["recast_every"] then
            if DRSpells.active_spells and DRSpells.active_spells[data["name"] or name] then
                goto continue
            end
        end
        table.insert(recastable, {name = name, data = data})
        ::continue::
    end

    -- Find the first buff that actually needs casting
    local found_name, found_data = nil, nil
    for _, entry in ipairs(recastable) do
        local name = entry.name
        local data = entry.data
        local needs_cast = false
        if data["pet_type"] then
            needs_cast = self:_check_spell_timer(data)
                and defs.tcontains(DRRoom.npcs or {}, data["pet_type"])
        elseif data["recast_every"] then
            needs_cast = self:_check_spell_timer(data)
        elseif data["expire"] then
            needs_cast = true
        else
            local active_val = DRSpells.active_spells and DRSpells.active_spells[name]
            needs_cast = not active_val
                or (data["recast"] and tonumber(active_val) and tonumber(active_val) <= data["recast"])
        end
        if needs_cast then
            found_name = name
            found_data = data
            break
        end
    end

    if not found_name or not found_data then return end

    game_state.casting_weapon_buff = defs.tcontains(defs.WEAPON_BUFFS, found_name)

    if found_data["ritual"] then
        self:_cast_ritual(found_data, game_state)
    elseif found_data["runestone_name"] then
        if DRCI.inside(found_data["runestone_name"], self._runestone_storage) then
            found_data["runestone_for_combat_exists"] = true
            self:_cast_runestone(found_data, game_state)
        else
            found_data["runestone_for_combat_exists"] = false
            -- Remove all buff spells whose runestone is missing
            local to_remove = {}
            for n, d in pairs(self._buff_spells) do
                if type(d) == "table" and d["runestone_for_combat_exists"] == false then
                    table.insert(to_remove, n)
                end
            end
            for _, n in ipairs(to_remove) do self._buff_spells[n] = nil end
        end
    else
        self:_prepare_spell(found_data, game_state, self._buff_force_cambrinth)
    end
end

function M:_check_health(game_state)
    if game_state.casting then return end
    if DRStats.barbarian() then
        self:_check_health_barbarian(game_state)
    elseif DRStats.empath() then
        self:_check_health_empath(game_state)
    end
end

function M:_check_health_barbarian(_game_state)
    if not self._barb_healing or not next(self._barb_healing) then return end
    if DRSpells.active_spells and DRSpells.active_spells["Famine"] then return end
    if DRStats.health > (self._barb_healing["health_threshold"] or 100) then return end
    if DRStats.mana < (self._barb_healing["inner_fire_threshold"] or 0) then return end

    DRCA.activate_barb_buff("Famine")
end

function M:_check_health_empath(game_state)
    if DRStats.health > self._empath_vitality_threshold and not next(self._wounds) then return end

    if DRSpells.active_spells and DRSpells.active_spells["Regeneration"] then
        if self._empath_spells["VH"] and DRStats.health <= self._empath_vitality_threshold then
            local vh = self._empath_spells["VH"]
            local data = {
                abbrev   = "vh",
                mana     = vh[1],
                cambrinth = {table.unpack(vh, 2)},
                harmless = true,
            }
            self:_prepare_spell(data, game_state)
        end
        return
    end

    if (os.time() - self._perc_health_timer) > 30
       and (self._empath_spells["FOC"] or self._empath_spells["HEAL"]) then
        self._perc_health_timer = os.time()
        local health_data = DRCH.perceive_health()
        self._wounds = (health_data and health_data["wounds"]) or {}
    end

    if next(self._wounds) then
        local data = nil
        if self._empath_spells["FOC"] then
            local foc = self._empath_spells["FOC"]
            data = {abbrev = "foc", mana = foc[1], cambrinth = {table.unpack(foc, 2)}, harmless = true}
        elseif self._empath_spells["HEAL"] then
            local heal = self._empath_spells["HEAL"]
            data = {abbrev = "heal", mana = heal[1], cambrinth = {table.unpack(heal, 2)}, harmless = true}
        end
        self._wounds = {}
        if data then
            self:_prepare_spell(data, game_state, true)
        end
    elseif self._empath_spells["VH"] then
        local vh = self._empath_spells["VH"]
        local data = {
            abbrev   = "vh",
            mana     = vh[1],
            cambrinth = {table.unpack(vh, 2)},
            harmless = true,
        }
        self:_prepare_spell(data, game_state, true)
    end
end

function M:_check_starlight(game_state)
    if not DRStats.trader() then return end
    if self._aura_frequency <= 0 then return end
    if (os.time() - self._aura_timer) <= self._aura_frequency then return end

    self._aura_timer = os.time()
    game_state.starlight_values = DRCA.perc_aura()
end

function M:_enough_starlight(game_state, data)
    if not DRStats.trader() then
        return UserVars.sun and UserVars.sun["night"] or false
    end
    if not game_state.starlight_values then return true end
    return (data["starlight_threshold"] or 0) <= (game_state.starlight_values["level"] or 0)
end

function M:_check_trader_magic(game_state)
    if not DRStats.trader() then return end

    if Flags["ct-starlight-depleted"] then
        DRC.message("----OUT OF STARLIGHT - DELETING STARLIGHT MAGIC----")
        -- Remove all buff spells and offensive spells that depend on starlight
        local to_remove = {}
        for name, data in pairs(self._buff_spells) do
            if type(data) == "table" and data["starlight_threshold"]
               and data["starlight_threshold"] > -1 then
                table.insert(to_remove, name)
            end
        end
        for _, name in ipairs(to_remove) do self._buff_spells[name] = nil end
        local new_off = {}
        for _, spell in ipairs(self._offensive_spells) do
            if not (spell["starlight_threshold"] and spell["starlight_threshold"] > -1) then
                table.insert(new_off, spell)
            end
        end
        self._offensive_spells = new_off
        self._aura_frequency = 0
        game_state.regalia_cancel = true
    end

    if game_state.casting_regalia then
        if Flags["ct-starlight-depleted"] then
            DRCA.shatter_regalia()
            self._equip_mgr.wear_equipment_set("standard")
            if self._settings.gear_sets and self._settings.gear_sets["standard"]
               and defs.tcontains(self._settings.gear_sets["standard"], game_state:weapon_name()) then
                self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
            end
            game_state.last_regalia_type = nil
            game_state.swap_regalia_type = nil
        end
        if Flags["ct-regalia-succeeded"] then
            Flags.reset("ct-regalia-expired")
            Flags.reset("ct-regalia-succeeded")
            game_state.last_regalia_type = game_state.swap_regalia_type
            game_state.swap_regalia_type = nil
        end
        game_state.casting_regalia = false
    end

    Flags.reset("ct-starlight-depleted")
end

function M:_check_cfb(game_state)
    if not DRStats.necromancer() then return end
    if not self._necromancer_zombie["Call from Beyond"] then return end
    if game_state.casting then return end
    if not game_state.prepare_cfb then return end

    game_state.casting_cfb  = true
    game_state.prepare_cfb  = false
    self:_prepare_spell(self._necromancer_zombie["Call from Beyond"], game_state, true)
end

function M:_check_cfw(game_state)
    if not DRStats.necromancer() then return end
    if not self._necromancer_bonebug["Call from Within"] then return end
    if game_state.casting then return end
    if not game_state.prepare_cfw then return end

    game_state.casting_cfw  = true
    game_state.prepare_cfw  = false
    self:_prepare_spell(self._necromancer_bonebug["Call from Within"], game_state, true)
end

function M:_heal_corpse(game_state)
    if not DRStats.necromancer() then return end
    if not self._corpse_healing then return end
    if not self._corpse_healing["Necrotic Reconstruction"] then return end
    if game_state.casting then return end
    if not game_state.prepare_nr then return end

    game_state.casting_nr   = true
    game_state.prepare_nr   = false
    self:_prepare_spell(self._corpse_healing["Necrotic Reconstruction"], game_state, true)
end

function M:_check_consume(game_state)
    if not DRStats.necromancer() then return end
    if not self._necromancer_healing then return end
    if game_state.casting then return end

    -- Siphon Vitality: fires whenever health is low and there are NPCs present
    if self._necromancer_healing["Siphon Vitality"]
       and DRStats.health <= self._siphon_vit_threshold
       and #(game_state:npcs() or {}) > 0 then
        self._necromancer_healing["Siphon Vitality"]["prep"] = "target"
        self:_prepare_spell(self._necromancer_healing["Siphon Vitality"], game_state, true)
        return
    end

    if not game_state.prepare_consume then return end
    if self._necromancer_healing["Devour"]
       and DRSpells.active_spells and DRSpells.active_spells["Devour"] then return end

    local data = self._necromancer_healing["Devour"] or self._necromancer_healing["Consume Flesh"]
    game_state.casting_consume = true
    game_state.prepare_consume = false
    self:_prepare_spell(data, game_state, true)
end

function M:_slivers_exist()
    local line = dothistimeout("perc self", 15, "slivers")
    return line and line:lower():match("slivers") or false
end

function M:_check_slivers(game_state)
    if not DRStats.moon_mage() then return end
    if not self._tk_spell then return end
    if self._checking_slivers then return end
    if game_state.casting then return end
    if self:_slivers_exist() then return end

    if self._last_sliver_cast_time then
        local elapsed  = os.time() - self._last_sliver_cast_time
        local cooldown = (self._settings.sliver_duration and tonumber(self._settings.sliver_duration) ~= 0
                          and tonumber(self._settings.sliver_duration)) or 100
        if elapsed < cooldown then return end
    end

    self._checking_slivers = true
    local ok, err = pcall(function()
        local moonblade_spell = {mana = 1}
        -- Set prep_time based on Lunar Magic rank
        local lunar_rank = DRSkill.getrank("Lunar Magic") or 0
        local prep_time
        if     lunar_rank >= 400 then prep_time = 1
        elseif lunar_rank >= 300 then prep_time = 2
        elseif lunar_rank >= 200 then prep_time = 3
        else                          prep_time = 4
        end
        moonblade_spell["prep_time"] = prep_time
        moonblade_spell["abbrev"] = "moonblade"
        moonblade_spell["name"]   = "Moonblade"

        DRCA.cast_spell(moonblade_spell, self._settings)

        DRC.bput("tap moon", nil, 15,
            "A shaft of intense",
            "You are aided by the strength",
            "diamond-hard metal",
            "moonblade.*fiery.*liquid",
            "moonblade.*substance",
            "coalesces into a long narrow moonblade",
            "oozes into existence.*moonblade",
            "moonblade of glossy blue-white diamond-hard metal",
            "You are already holding a moonblade",
            "a shadow coalesces")

        DRC.bput("break moonblade", nil, 5)
        self._last_sliver_cast_time = os.time()
    end)
    self._checking_slivers = false
    if not ok then
        DRC.message("check_slivers error: " .. tostring(err))
    end
end

function M:_blacklist_spells(game_state)
    if self._magic_gain_check <= 0 then return end
    if game_state.casting then return end
    if not self._magic_last_spell then return end

    local skill     = self._magic_last_spell["skill"]
    local current   = DRSkill.getxp(skill or "") or 0
    local cast_only = self._magic_last_spell["cast_only_to_train"] or self._cast_only_to_train

    if current <= self._magic_last_exp and cast_only and current < 34 then
        self._magic_no_gain_list[skill] = (self._magic_no_gain_list[skill] or 0) + 1
    else
        self._magic_no_gain_list[skill] = 0
    end

    if (self._magic_no_gain_list[skill] or 0) > self._magic_gain_check then
        DRC.message("***STATUS*** Suppressing " .. tostring(skill)
            .. " due to cast_only_to_train spells within that skill not gaining mindstates.")
        local new_off = {}
        for _, spell in ipairs(self._offensive_spells) do
            if spell["skill"] ~= skill then
                table.insert(new_off, spell)
            end
        end
        self._offensive_spells = new_off
    end

    self._magic_last_spell = nil
    self._magic_last_exp   = -1
end

function M:_check_offensive(game_state)
    if game_state.casting then return end
    local npcs = game_state:npcs() or {}
    if #npcs == 0 then return end
    if DRStats.mana < self._offensive_spell_mana_threshold then return end

    -- Filter candidate spells
    local ready_spells = {}
    for _, spell in ipairs(self._offensive_spells) do
        if spell["target_enemy"] and not defs.tcontains(npcs, spell["target_enemy"]) then goto skip end
        if spell["min_threshold"] and #npcs < spell["min_threshold"] then goto skip end
        if spell["max_threshold"] and #npcs > spell["max_threshold"] then goto skip end
        if spell["expire"] and not Flags["ct-" .. (spell["abbrev"] or "")] then goto skip end
        if not game_state:is_offense_allowed() and not spell["harmless"] then goto skip end
        if game_state:dancing() and not spell["harmless"] then goto skip end
        if spell["recast_every"] and not self:_check_spell_timer(spell) then goto skip end
        if (self._cast_only_to_train or spell["cast_only_to_train"])
           and DRSkill.getxp(spell["skill"] or "") > self._magic_exp_training_max_threshold then goto skip end
        if spell["cyclic"] and DRSpells.active_spells and DRSpells.active_spells[spell["name"] or ""] then goto skip end
        if spell["night"] and not (UserVars.sun and UserVars.sun["night"]) then goto skip end
        if spell["day"]   and not (UserVars.sun and UserVars.sun["day"])   then goto skip end
        if spell["slivers"] and not (DRSpells.slivers or self._tk_ammo) then goto skip end
        if spell["starlight_threshold"] and not self:_enough_starlight(game_state, spell) then goto skip end
        if spell["bright_celestial_object"] and not DRCMM.bright_celestial_object() then goto skip end
        if spell["any_celestial_object"]    and not DRCMM.any_celestial_object()    then goto skip end
        if spell["no_bright_celestial_object"] and DRCMM.bright_celestial_object()  then goto skip end
        if spell["no_celestial_object"]     and DRCMM.any_celestial_object()        then goto skip end
        if spell["must_be_true"] and not (load("return " .. spell["must_be_true"])()) then goto skip end
        table.insert(ready_spells, spell)
        ::skip::
    end

    if #ready_spells == 0 then return end

    local data = nil
    if not self._offensive_spell_cycle or #self._offensive_spell_cycle == 0 then
        -- Sort skills by rate then rank; pick spell for highest-priority skill
        local skills = {}
        local seen   = {}
        for _, spell in ipairs(ready_spells) do
            local sk = spell["skill"]
            if sk and not seen[sk] then
                table.insert(skills, sk)
                seen[sk] = true
            end
        end
        local sorted = game_state:sort_by_rate_then_rank(skills)
        local best_skill = sorted and sorted[1]
        if best_skill then
            for _, spell in ipairs(ready_spells) do
                if spell["skill"] == best_skill then
                    data = spell; break
                end
            end
        end
    else
        -- Cycle through configured spell order
        local found_name = nil
        for _, spell_name in ipairs(self._offensive_spell_cycle) do
            for _, spell in ipairs(ready_spells) do
                if spell["name"] == spell_name then
                    found_name = spell_name; break
                end
            end
            if found_name then break end
        end
        -- Rotate the cycle list
        if #self._offensive_spell_cycle > 0 then
            local first = table.remove(self._offensive_spell_cycle, 1)
            table.insert(self._offensive_spell_cycle, first)
        end
        if found_name then
            for _, spell in ipairs(ready_spells) do
                if spell["name"] == found_name then
                    data = spell; break
                end
            end
        end
    end

    if not data then return end

    if data["use_stealth"] then game_state.hide_on_cast = true end

    if data["runestone_name"] then
        if DRCI.inside(data["runestone_name"], self._runestone_storage) then
            data["runestone_for_combat_exists"] = true
            self:_cast_runestone(data, game_state)
        else
            data["runestone_for_combat_exists"] = false
            local new_off = {}
            for _, spell in ipairs(self._offensive_spells) do
                if spell["runestone_for_combat_exists"] ~= false then
                    table.insert(new_off, spell)
                end
            end
            self._offensive_spells = new_off
        end
    else
        self._magic_last_spell = data
        self._magic_last_exp   = DRSkill.getxp(data["skill"] or "") or -1
        self:_prepare_spell(data, game_state)
    end

    Flags.reset("ct-spelllost")
end

function M:_cast_ritual(data, game_state)
    local summoned = game_state:summoned_info(game_state:weapon_skill())
    if summoned then
        DRCS.break_summoned_weapon(game_state:weapon_name())
    else
        self._equip_mgr.stow_weapon(game_state:weapon_name())
    end

    data = DRCMM.update_astral_data(data, self._settings)
    if data then
        self:_check_invoke(game_state)
        DRCA.ritual(data, self._settings)
    end

    if summoned then
        game_state:prepare_summoned_weapon(false)
    else
        self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
    end
    game_state.reset_stance = true
end

function M:_prepare_spell(data, game_state, force_cambrinth)
    if not data then return end

    if data["use_auto_mana"] then
        data = DRCA.check_discern(data, self._settings, self:_spell_is_sorcery(data))
    end

    game_state.cast_timer = os.time()
    self._prep_time = data["prep_time"]

    if data["target_enemy"] then
        fput("face " .. tostring(data["target_enemy"]))
    end

    local command = data["prep"] or data["prep_type"] or "prep"

    if command == "segue" then
        if DRCA.segue(data["abbrev"], data["mana"]) then return end
        command = "prep"
    end

    if data["cyclic"] then
        DRCA.release_cyclics()
        game_state.casting_cyclic = true
    end

    if data["recast_every"] then
        local key = data["pet_type"] or data["abbrev"]
        self._spell_timers[key] = os.time()
    end

    if data["moon"] then
        DRCMM.check_moonwatch()
        local moon = UserVars.moons and UserVars.moons["visible"] and UserVars.moons["visible"][1]
        local spell_name_lower = (data["name"] or ""):lower()

        if spell_name_lower == "moonblade" then
            game_state.casting_moonblade = true
            local last_moon = DRCMM.moon_used_to_summon_weapon()
            if DRCMM.hold_moon_weapon()
               and UserVars.moons and UserVars.moons["visible"]
               and defs.tcontains(UserVars.moons["visible"], last_moon)
               and UserVars.moons[last_moon]
               and (UserVars.moons[last_moon]["timer"] or 0) >= 4 then
                moon = last_moon
                data["cast"] = "cast " .. moon .. " refresh"
            else
                DRCMM.drop_moon_weapon()
                data["cast"] = "cast " .. (moon or "")
            end
        elseif not moon and spell_name_lower == "cage of light" then
            data["cast"] = "cast ambient"
        elseif not moon then
            if not (UserVars.moons and UserVars.moons["visible"] and UserVars.moons["visible"][1]) then
                return
            end
        else
            data["cast"] = "cast " .. moon
        end
    end

    game_state.casting_regalia = (data["abbrev"] or ""):lower() == "regal"

    Flags.reset("ct-shock-warning")
    DRCA.prepare(
        data["abbrev"], data["mana"], data["symbiosis"],
        command, data["tattoo_tm"], data["runestone_name"], data["runestone_tm"])

    if Flags["ct-shock-warning"] and not game_state:is_permashocked() then
        DRC.message("Dropping spell: Got shock warning.")
        DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
        DRC.bput("release mana", "You release all", "You aren't harnessing any mana")
        return
    end

    game_state.casting = true
    game_state:cambrinth_charges(data["cambrinth"])

    if data["cambrinth"] then
        local can_harness = DRCA.check_to_harness(self._harness_for_attunement)
        self._should_harness = can_harness and not force_cambrinth
        if not self._should_harness then
            self._should_invoke = data["cambrinth"]
        end
    end

    self._custom_cast    = data["cast"]
    self._symbiosis      = data["symbiosis"]
    self._barrage        = data["barrage"]
    self._after          = data["after"]
    self._before         = data["before"]
    self._skill          = data["skill"]
    self._prep           = data["prep"]
    self._mana           = data["mana"]
    self._command        = data["command"]
    self._prepared_spell = data
    self._abbrev         = data["abbrev"]
    self._use_auto_mana  = data["use_auto_mana"]
    self._reset_expire   = data["expire"] and data["abbrev"] or nil

    Flags.reset("ct-spellcast")

    -- If this is targeted magic and the weapon skill matches, count it as an action
    if (self._skill == "Targeted Magic" or self._prep == "target")
       and game_state:weapon_skill() == "Targeted Magic" then
        game_state:action_taken()
    end
end

return M
