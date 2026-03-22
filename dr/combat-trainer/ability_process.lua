--- AbilityProcess — thief khri, barbarian buffs, paladin badge/glyph,
--- warhorn/egg, battle cries, and yiamura for combat-trainer.
-- Ported from AbilityProcess class in combat-trainer.lic
-- Original authors: DR-scripts contributors (github.com/rpherbig/dr-scripts)

local AbilityProcess = {}
AbilityProcess.__index = AbilityProcess

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

function AbilityProcess.new(settings)
    local self = setmetatable({}, AbilityProcess)

    -- Pull buff_nonspells hash; extract special sub-keys before iterating
    self._buffs = settings.buff_nonspells or {}

    -- Extract khri list from buffs (keyed as 'khri')
    self._khri = self._buffs['khri'] or {}
    self._buffs['khri'] = nil

    self._kneel_khri     = settings.kneel_khri
    self._khri_adaptation = settings.khri_adaptation

    -- Battle cries
    self._battle_cries    = settings.battle_cries or {}

    -- Build cycle from explicit list or derive from battle_cries names
    if settings.battle_cry_cycle then
        self._battle_cry_cycle = {}
        for _, name in ipairs(settings.battle_cry_cycle) do
            table.insert(self._battle_cry_cycle, name)
        end
    else
        self._battle_cry_cycle = {}
        for _, bc in ipairs(self._battle_cries) do
            if bc['name'] then
                table.insert(self._battle_cry_cycle, bc['name'])
            end
        end
    end

    self._battle_cry_cooldown = settings.battle_cry_cooldown or 0
    self._roar_helm_noun      = settings.roar_helm_noun

    -- Barbarian buffs: extract from buffs hash
    self._barb_buffs = self._buffs['barb_buffs'] or {}
    self._buffs['barb_buffs'] = nil

    self._barb_buffs_inner_fire_threshold = settings.barb_buffs_inner_fire_threshold or 0
    self._meditation_pause_timer          = settings.meditation_pause_timer

    -- Register per-buff expiry flags
    self:_setup_barb_buff_flags()

    -- Battle cry "not facing" flag
    Flags.add('ct-battle-cry-not-facing', 'You are not facing an enemy')

    -- Paladin badge
    self._paladin_use_badge   = settings.paladin_use_badge
    self._use_mana_glyph      = settings.paladin_use_mana_glyph

    if self._use_mana_glyph then
        Flags.add('glyph-mana-expired', 'You sense the holy power return to normal')
        Flags['glyph-mana-expired'] = true
    end

    -- Warhorn / egg
    self._warhorn          = settings.warhorn
    self._warhorn_cooldown = tonumber(settings.warhorn_cooldown) or 1200
    self._stomp_on_cooldown = settings.war_stomp_on_cooldown
    self._pounce_on_cooldown = settings.pounce_on_cooldown

    -- Yiamura
    self._yiamura_exists = settings.combat_trainer_use_yiamura

    self._egg = settings.egg

    -- Initialise warhorn/egg rotation if either is configured
    if self._warhorn or self._egg then
        self:_set_warhorn_or_egg()
    end

    -- Paladin badge verbs and cooldown
    if self._paladin_use_badge then
        if DRCI.wearing('pilgrim badge') then
            self._paladin_badge_get_verb   = 'remove'
            self._paladin_badge_store_verb = 'wear'
        else
            self._paladin_badge_get_verb   = 'get'
            self._paladin_badge_store_verb = 'stow'
        end
        UserVars.paladin_last_badge_use = UserVars.paladin_last_badge_use or os.time()
        self._badge_reuse_cooldown = 1860  -- 31 minutes
    end

    return self
end

---------------------------------------------------------------------------
-- Public: execute
---------------------------------------------------------------------------

function AbilityProcess:execute(game_state)
    self:_check_paladin_skills()
    if self._yiamura_exists then
        self:_check_yiamura()
    end
    self:_check_nonspell_buffs(game_state)
    self:_check_battle_cries(game_state)
    if self._warhorn_or_egg and #self._warhorn_or_egg > 0 then
        self:_use_warhorn_or_egg(game_state)
    end
    -- Barbarian war stomp
    if DRStats.barbarian() and self._stomp_on_cooldown
       and #game_state:npcs() > 0 and Flags['war-stomp-ready'] then
        game_state:stomp()
    end
    -- Ranger pounce
    if DRStats.ranger() and self._pounce_on_cooldown
       and #game_state:npcs() > 0 and Flags['pounce-ready'] then
        game_state:pounce()
    end
    return false
end

---------------------------------------------------------------------------
-- Private: yiamura
---------------------------------------------------------------------------

function AbilityProcess:_check_yiamura()
    if not self._yiamura_exists then return end
    -- Respect 2-hour cooldown tracked in UserVars
    if UserVars.yiamura and UserVars.yiamura['last_raised'] then
        local elapsed = os.time() - tonumber(UserVars.yiamura['last_raised'])
        if elapsed <= 7200 then return end
    end
    -- Verify the item exists in the room / inventory
    if not DRCI.exists('yiamura') then
        self._yiamura_exists = false
        return
    end
    DRC.wait_for_script_to_complete('yiamura', {'raise'})
end

---------------------------------------------------------------------------
-- Private: warhorn / egg setup
---------------------------------------------------------------------------

function AbilityProcess:_set_warhorn_or_egg()
    -- Build rotation list from non-nil entries
    self._warhorn_or_egg = {}
    if self._warhorn then table.insert(self._warhorn_or_egg, self._warhorn) end
    if self._egg     then table.insert(self._warhorn_or_egg, self._egg)     end

    -- Initialise persistent timers in UserVars
    UserVars.warhorn = UserVars.warhorn or {}
    if not UserVars.warhorn['last_warhorn'] then
        UserVars.warhorn['last_warhorn'] = os.time() - self._warhorn_cooldown
    end
    if not UserVars.warhorn['last_egg'] then
        UserVars.warhorn['last_egg'] = os.time() - 900
    end
    if not UserVars.warhorn['last_warhorn_or_egg'] then
        UserVars.warhorn['last_warhorn_or_egg'] = os.time() - 600
    end

    -- If both are configured, put the one with more elapsed time first (i.e. longest overdue)
    if #self._warhorn_or_egg > 1 then
        local egg_elapsed  = os.time() - UserVars.warhorn['last_egg']
        local horn_elapsed = os.time() - UserVars.warhorn['last_warhorn']
        -- If egg elapsed > horn elapsed, egg is more overdue → rotate so egg is first
        if egg_elapsed > horn_elapsed then
            -- move first element to end
            local first = table.remove(self._warhorn_or_egg, 1)
            table.insert(self._warhorn_or_egg, first)
        end
    end

    -- Determine activation command (legacy egg specified as warhorn: egg)
    if self._warhorn and string.find(self._warhorn, 'egg') then
        self._warhorn_activation_command = 'invoke my ' .. self._warhorn
    else
        self._warhorn_activation_command = 'exhale ' .. (self._warhorn or '') .. ' lure'
    end

    -- Verb pair depends on whether warhorn is worn
    if self._warhorn and DRCI.wearing(self._warhorn) then
        self._warhorn_get_verb   = 'remove'
        self._warhorn_store_verb = 'wear'
    else
        self._warhorn_get_verb   = 'get'
        self._warhorn_store_verb = 'stow'
    end
end

---------------------------------------------------------------------------
-- Private: warhorn / egg use controller
---------------------------------------------------------------------------

function AbilityProcess:_use_warhorn_or_egg(game_state)
    -- Room effect lasts 10 minutes; don't use until it has expired
    if os.time() <= (UserVars.warhorn['last_warhorn_or_egg'] + 600) then return end

    local noun = self._warhorn_or_egg[1]
    if not noun then return end

    if string.find(string.lower(noun), 'egg') then
        -- Egg cooldown is 15 minutes
        if os.time() <= (UserVars.warhorn['last_egg'] + 900) then return end
        if self:_use_egg() then
            UserVars.warhorn['last_egg']             = os.time()
            UserVars.warhorn['last_warhorn_or_egg']  = os.time()
        end
    else
        -- Warhorn cooldown is configurable (default 20 min)
        if os.time() <= (UserVars.warhorn['last_warhorn'] + self._warhorn_cooldown) then return end
        if self:_use_warhorn(game_state) then
            UserVars.warhorn['last_warhorn']          = os.time()
            UserVars.warhorn['last_warhorn_or_egg']   = os.time()
        end
    end

    -- Rotate: move first element to end
    local first = table.remove(self._warhorn_or_egg, 1)
    table.insert(self._warhorn_or_egg, first)
end

---------------------------------------------------------------------------
-- Private: egg activation
---------------------------------------------------------------------------

function AbilityProcess:_use_egg()
    local result = DRC.bput('invoke my egg',
        'light envelops the area briefly',
        'The red light within the egg is dim and moves about sluggishly',
        'Something about the area inhibits',
        'Invoke what?',
        'You cannot stay hidden while using the egg.')

    if string.find(result, 'The red light within the egg is dim') then
        return false
    elseif string.find(result, 'Something about the area inhibits') then
        DRC.message("Egg can't be used in this area. Removing from hunt.")
        -- Remove 'egg' noun from rotation
        for i = #self._warhorn_or_egg, 1, -1 do
            if string.find(string.lower(self._warhorn_or_egg[i]), 'egg') then
                table.remove(self._warhorn_or_egg, i)
            end
        end
        return false
    elseif string.find(result, 'What were you referring to') or string.find(result, 'Invoke what') then
        DRC.message("Can't find egg, removing from hunt.")
        for i = #self._warhorn_or_egg, 1, -1 do
            if string.find(string.lower(self._warhorn_or_egg[i]), 'egg') then
                table.remove(self._warhorn_or_egg, i)
            end
        end
        return false
    end

    return true
end

---------------------------------------------------------------------------
-- Private: warhorn activation
---------------------------------------------------------------------------

function AbilityProcess:_use_warhorn(game_state)
    game_state:sheath_whirlwind_offhand()

    local get_result = DRC.bput(
        self._warhorn_get_verb .. ' my ' .. self._warhorn,
        'You get.*warhorn',
        'You remove.*warhorn',
        'You take.*warhorn',
        'What were you referring to',
        'You need a free hand',
        'Remove what')

    if string.find(get_result, 'What were you referring to') then
        DRC.message(self._warhorn .. ' NOT FOUND! Removing from hunt.')
        -- Remove this warhorn noun from rotation
        for i = #self._warhorn_or_egg, 1, -1 do
            if self._warhorn_or_egg[i] == self._warhorn then
                table.remove(self._warhorn_or_egg, i)
            end
        end
        return false
    end

    -- Did not successfully retrieve the warhorn (need free hand, unknown target, etc.)
    if not (string.find(get_result, 'You get') or
            string.find(get_result, 'You remove') or
            string.find(get_result, 'You take')) then
        return false
    end

    -- Warhorn retrieved — activate it
    local activate_result = DRC.bput(
        self._warhorn_activation_command,
        'Something about the area inhibits',
        'You sound a series of bursts from the',
        'Your lungs are tired from having sounded a',
        'not accomplishing much and looking rather silly')

    if string.find(activate_result, 'Your lungs are tired from having sounded a') then
        -- Still counts as a successful use (cooldown tracked server-side)
        self:_stow_warhorn(game_state)
        return true
    elseif string.find(activate_result, 'Something about the area inhibits') then
        DRC.message("Can't use " .. self._warhorn .. " in this area. Removing from hunt.")
        self:_stow_warhorn(game_state)
        for i = #self._warhorn_or_egg, 1, -1 do
            if self._warhorn_or_egg[i] == self._warhorn then
                table.remove(self._warhorn_or_egg, i)
            end
        end
        return false
    elseif string.find(activate_result, 'not accomplishing much') then
        DRC.message("You can't use a warhorn. Removing from hunt.")
        self:_stow_warhorn(game_state)
        for i = #self._warhorn_or_egg, 1, -1 do
            if self._warhorn_or_egg[i] == self._warhorn then
                table.remove(self._warhorn_or_egg, i)
            end
        end
        return false
    end

    waitrt()
    self:_stow_warhorn(game_state)
    return true
end

---------------------------------------------------------------------------
-- Private: stow warhorn
---------------------------------------------------------------------------

function AbilityProcess:_stow_warhorn(game_state)
    DRC.bput(self._warhorn_store_verb .. ' my ' .. self._warhorn,
        'You put', 'You attach')
    game_state:wield_whirlwind_offhand()
end

---------------------------------------------------------------------------
-- Private: paladin skills
---------------------------------------------------------------------------

function AbilityProcess:_check_paladin_skills()
    if not DRStats.paladin() then return end
    self:_pray_badge()
    self:_check_mana_glyph()
end

function AbilityProcess:_pray_badge()
    if not self._paladin_use_badge then return end
    if (os.time() - UserVars.paladin_last_badge_use) <= self._badge_reuse_cooldown then return end

    local result = DRC.bput(
        self._paladin_badge_get_verb .. ' my pilgrim badge',
        'You take off',
        'You get',
        'You remove',
        'What were you referring to',
        'You need a free hand',
        'Remove what')

    if string.find(result, 'You get') or
       string.find(result, 'You remove') or
       string.find(result, 'You take off') then
        DRC.retreat()
        DRC.bput('pray my pilgrim badge', 'You think upon the immortals')
        UserVars.paladin_last_badge_use = os.time()
        waitrt()
        DRC.bput(self._paladin_badge_store_verb .. ' my pilgrim badge',
            'You put', 'You attach')
    elseif string.find(result, 'What were you referring to') then
        DRC.message('***PILGRIM BADGE NOT FOUND! REMOVING FROM HUNT.***')
        self._paladin_use_badge = false
    end
end

function AbilityProcess:_check_mana_glyph()
    if not self._use_mana_glyph then return end
    if not Flags['glyph-mana-expired'] then return end
    DRC.bput('glyph mana', 'You trace a glyph', 'You begin to trace')
    Flags.reset('glyph-mana-expired')
end

---------------------------------------------------------------------------
-- Private: barbarian buff flags setup
---------------------------------------------------------------------------

function AbilityProcess:_setup_barb_buff_flags()
    local spell_data = get_data('spells')
    for _, name in ipairs(self._barb_buffs) do
        local ability_data = spell_data.barb_abilities and spell_data.barb_abilities[name]
        if ability_data and ability_data['expired_message'] then
            Flags.add('ap-' .. name .. '-expired', ability_data['expired_message'])
            -- Pre-set expired if not currently active
            if not DRSpells.active_spells[name] then
                Flags['ap-' .. name .. '-expired'] = true
            end
        end
    end
end

---------------------------------------------------------------------------
-- Private: non-spell buffs (generic timed commands + khri + barb_buffs)
---------------------------------------------------------------------------

function AbilityProcess:_check_nonspell_buffs(game_state)
    -- Generic timed buff commands
    -- Settings format: action => cooldown_seconds
    -- Extended format: action => "cooldown && \"conditional_lua_expression\""
    for action, blob in pairs(self._buffs) do
        -- Skip the special sub-keys already extracted
        if action == 'khri' or action == 'barb_buffs' then goto continue end

        local timer = game_state.cooldown_timers[action]
        local blob_str = tostring(blob)

        -- Split on ' && ' (max 2 parts) to separate cooldown from optional conditional
        local sep_pos = string.find(blob_str, ' && ', 1, true)
        local cooldown_str, conditional_str
        if sep_pos then
            cooldown_str    = string.sub(blob_str, 1, sep_pos - 1)
            conditional_str = string.sub(blob_str, sep_pos + 4)
            -- Strip surrounding double-quotes from conditional
            if string.sub(conditional_str, 1, 1) == '"' and
               string.sub(conditional_str, -1) == '"' then
                conditional_str = string.sub(conditional_str, 2, -2)
            end
        else
            cooldown_str    = blob_str
            conditional_str = nil
        end

        local cooldown = tonumber(cooldown_str) or 0

        if timer and (os.time() - timer) <= cooldown then goto continue end

        game_state.cooldown_timers[action] = os.time()

        -- Execute if no conditional, or if the conditional expression evaluates truthy
        local should_act = true
        if conditional_str then
            local fn, err = load('return (' .. conditional_str .. ')')
            if fn then
                local ok, val = pcall(fn)
                should_act = ok and val
            else
                echo('AbilityProcess: conditional parse error for "' .. action .. '": ' .. tostring(err))
                should_act = false
            end
        end

        if should_act then
            fput(action)
            waitrt()
        end

        ::continue::
    end

    -- Khri Adaptation
    if self._khri_adaptation and self._khri_adaptation ~= '' then
        -- Build the khri adaptation command following Lich5 logic:
        -- split the value, capitalize each word, prepend 'Adaptation' or insert after 'Delay'
        local parts = {}
        for word in string.gmatch(self._khri_adaptation, '%S+') do
            local cap = word:sub(1,1):upper() .. word:sub(2)
            table.insert(parts, cap)
        end
        -- If first token is 'Delay', insert 'Adaptation' at position 2; else prepend 'Adaptation'
        if parts[1] == 'Delay' then
            table.insert(parts, 2, 'Adaptation')
        else
            table.insert(parts, 1, 'Adaptation')
        end
        -- Only generate command if we have more than just 'Adaptation'
        if #parts > 1 then
            local command = 'khri ' .. table.concat(parts, ' ')
            if not DRSpells.active_spells['Khri Adaptation'] then
                if not (game_state.danger and DRCA.kneel_for_khri(self._kneel_khri, command)) then
                    local timer = game_state.cooldown_timers['Adaptation']
                    if not timer or (os.time() - timer) > 20 then
                        if DRCA.activate_khri(self._kneel_khri, command) then
                            game_state.cooldown_timers['Adaptation'] = os.time()
                        end
                    end
                end
            end
        end
    end

    -- Khri buffs
    for _, name in ipairs(self._khri) do
        local full_name = 'Khri ' .. name
        if not (game_state.danger and DRCA.kneel_for_khri(self._kneel_khri, full_name)) then
            local timer = game_state.cooldown_timers[full_name]
            if not timer or (os.time() - timer) > 30 then
                if DRCA.activate_khri(self._kneel_khri, full_name) then
                    game_state.cooldown_timers[full_name] = os.time()
                end
            end
        end
    end

    -- Barbarian buffs
    for _, name in ipairs(self._barb_buffs) do
        if Flags['ap-' .. name .. '-expired'] and not DRSpells.active_spells[name] then
            local timer = game_state.cooldown_timers[name]
            if not timer or (os.time() - timer) > 30 then
                -- Tsunami requires a wielded melee weapon
                if name == 'Tsunami' then
                    if not game_state:melee_weapon_skill() or
                       not DRC.right_hand or DRC.right_hand == '' then
                        -- Not ready to activate Tsunami; skip silently
                        goto barb_continue
                    end
                end
                -- Inner fire threshold check
                if DRStats.mana < self._barb_buffs_inner_fire_threshold then
                    -- Below threshold; skip
                    goto barb_continue
                end
                if DRCA.activate_barb_buff(name, self._meditation_pause_timer) then
                    Flags.reset('ap-' .. name .. '-expired')
                    game_state.cooldown_timers[name] = os.time()
                end
            end
        end
        ::barb_continue::
    end
end

---------------------------------------------------------------------------
-- Private: battle cries
---------------------------------------------------------------------------

function AbilityProcess:_check_battle_cries(game_state)
    if not self._battle_cries or #self._battle_cries == 0 then return end
    if not self._battle_cry_cooldown then return end

    local timer = game_state.cooldown_timers['Battle Cry']
    if timer and (os.time() - timer) <= self._battle_cry_cooldown then return end

    -- Need a facing enemy target to use a battle cry
    if not game_state:can_face() then return end

    Flags.reset('ct-battle-cry-not-facing')

    local npcs = game_state:npcs()
    local npc_count = #npcs

    -- Helper: check if a noun is in npcs list
    local function npc_present(noun)
        for _, n in ipairs(npcs) do
            if n == noun then return true end
        end
        return false
    end

    -- Filter battle cries by target_enemy, min_threshold, max_threshold
    local ready_cries = {}
    for _, bc in ipairs(self._battle_cries) do
        local ok = true
        if bc['target_enemy'] and not npc_present(bc['target_enemy']) then
            ok = false
        end
        if ok and bc['min_threshold'] and npc_count < bc['min_threshold'] then
            ok = false
        end
        if ok and bc['max_threshold'] and npc_count > bc['max_threshold'] then
            ok = false
        end
        if ok then table.insert(ready_cries, bc) end
    end

    -- Find next cry to use by walking the cycle order
    local selected_name = nil
    for _, cycle_name in ipairs(self._battle_cry_cycle) do
        for _, rc in ipairs(ready_cries) do
            if rc['name'] == cycle_name then
                selected_name = cycle_name
                break
            end
        end
        if selected_name then break end
    end

    if not selected_name then return end  -- no ready cry matches cycle

    -- Find full data for the selected cry
    local selected_data = nil
    for _, bc in ipairs(ready_cries) do
        if bc['name'] == selected_name then
            selected_data = bc
            break
        end
    end

    if not selected_data then return end

    -- Use roar helm if configured
    if self._roar_helm_noun then
        fput('scream ' .. self._roar_helm_noun)
        pause(1)
        waitrt()
    end

    -- Build the command, appending target enemy if specified
    local command = selected_data['command']
    if selected_data['target_enemy'] then
        command = command .. ' at ' .. selected_data['target_enemy']
    end

    fput(command)
    pause(1)
    waitrt()

    if Flags['ct-battle-cry-not-facing'] then
        -- Not facing an enemy — try to face the next one and retry once
        local face_result = DRC.bput('face next',
            'You turn',
            'There is nothing else to face',
            'Face what')
        if string.find(face_result, 'You turn') then
            -- Recurse once to retry with correct facing
            self:_check_battle_cries(game_state)
        end
        -- If nothing to face, give up silently until next cycle
    else
        -- Success: record timestamp and advance cycle
        game_state.cooldown_timers['Battle Cry'] = os.time()
        -- Rotate battle_cry_cycle: move first to end
        local first = table.remove(self._battle_cry_cycle, 1)
        table.insert(self._battle_cry_cycle, first)
    end
end

---------------------------------------------------------------------------

return AbilityProcess
