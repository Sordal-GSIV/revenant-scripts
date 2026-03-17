--- Bigshot Command Check — condition modifier system
-- Parses parenthesized modifiers like (m50)(undead)(prone) from command strings
-- and evaluates whether the command should execute.

local M = {}

-- Parse modifiers from a command string
-- "incant 509(m50)(undead)(prone)" → {"m50", "undead", "prone"}
function M.parse_modifiers(command)
    local mods = {}
    for mod_str in command:gmatch("%(([^%)]+)%)") do
        mods[#mods + 1] = mod_str
    end
    return mods
end

-- Strip modifiers from command string
-- "incant 509(m50)(undead)" → "incant 509"
function M.strip_modifiers(command)
    return command:gsub("%b()", ""):match("^%s*(.-)%s*$")
end

-- Evaluate a single modifier against current state
-- Returns true if the condition is MET (command should run)
-- Returns false if the condition FAILS (command should be skipped)
function M.check_modifier(mod_str, target, state)
    -- Amount checks: m50 = mana >= 50%, h80 = health >= 80%
    local mana_pct = mod_str:match("^m(%d+)$")
    if mana_pct then
        local pct = tonumber(mana_pct)
        return (Char.percent_mana or 100) >= pct
    end

    local health_pct = mod_str:match("^h(%d+)$")
    if health_pct then
        local pct = tonumber(health_pct)
        return (Char.percent_health or 100) >= pct
    end

    local stamina_pct = mod_str:match("^stamina(%d+)$")
    if stamina_pct then
        local pct = tonumber(stamina_pct)
        return (Char.percent_stamina or 100) >= pct
    end

    -- Buff time check: buff60 barrage = only if buff has <= 60 sec remaining
    local buff_time, buff_name = mod_str:match("^buff(%d+)%s+(.+)$")
    if buff_time and buff_name then
        local remaining = Effects.Buffs.time_left(buff_name)
        return remaining <= (tonumber(buff_time) / 60.0)
    end

    -- Effects checks
    local es_name = mod_str:match('^ES"(.+)"$')
    if es_name then return Effects.Spells.active(es_name) end

    local eb_name = mod_str:match('^EB"(.+)"$')
    if eb_name then return Effects.Buffs.active(eb_name) end

    local ec_name = mod_str:match('^EC"(.+)"$')
    if ec_name then return Effects.Cooldowns.active(ec_name) end

    local ed_name = mod_str:match('^ED"(.+)"$')
    if ed_name then return Effects.Debuffs.active(ed_name) end

    -- Negated effects
    local neb_name = mod_str:match('^!EB"(.+)"$')
    if neb_name then return not Effects.Buffs.active(neb_name) end

    local nec_name = mod_str:match('^!EC"(.+)"$')
    if nec_name then return not Effects.Cooldowns.active(nec_name) end

    -- Target state checks
    if mod_str == "undead" then
        return target and target.noun and target.noun:lower():find("undead") ~= nil
    end
    if mod_str == "!undead" then
        return not (target and target.noun and target.noun:lower():find("undead"))
    end
    if mod_str == "prone" then
        return target and target.status and target.status:find("prone")
    end
    if mod_str == "!prone" then
        return not (target and target.status and target.status:find("prone"))
    end

    -- Character state checks
    if mod_str == "hidden" then return hidden and hidden() end
    if mod_str == "!hidden" then return not (hidden and hidden()) end
    if mod_str == "fried" then
        return GameState.mind_value and GameState.mind_value >= (state.fried_threshold or 90)
    end

    -- Once per target
    if mod_str == "once" then
        if not state._once_used then state._once_used = {} end
        if target and target.id then
            local key = M.strip_modifiers(state._current_command or "") .. ":" .. target.id
            if state._once_used[key] then return false end
            state._once_used[key] = true
        end
        return true
    end

    -- Unknown modifier — pass through (don't block)
    return true
end

-- Check all modifiers on a command
-- Returns true if all conditions are met (command should execute)
-- Returns false if any condition fails (skip this command)
function M.should_execute(command, target, state)
    local mods = M.parse_modifiers(command)
    state._current_command = command

    for _, mod_str in ipairs(mods) do
        if not M.check_modifier(mod_str, target, state) then
            return false
        end
    end

    return true
end

return M
