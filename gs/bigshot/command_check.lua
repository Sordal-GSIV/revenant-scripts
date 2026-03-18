--- Bigshot Command Check — condition modifier system
-- Parses parenthesized modifiers like (m50)(undead)(prone) from command strings
-- and evaluates whether the command should execute.
--
-- Port of bigshot.lic v5.12.1 command_check / check_state_condition.
-- Every modifier from the Ruby COMMAND_MODIFIER_REGEX is implemented.
--
-- Semantics: check_modifier() returns true when the condition is MET and the
-- command SHOULD execute. This is the inverse of the Ruby command_check() which
-- returns true when the command should be SKIPPED.

local M = {}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

--- Regex used by the (prone) / (!prone) target-state check.
M.PRONE_PATTERN = "sleeping|webbed|stunned|kneeling|sitting|lying|prone|frozen|held in place|entangled"

--- Map of ability keyword → Effects.Buffs name for per-ability buff checks.
--- Used by both the state-condition checks and the buffNN timed checks.
M.BUFF_MAP = {
    barrage     = "Enh. Dexterity (+10)",
    bearhug     = "Enh. Strength (+10)",
    coupdegrace = "Empowered (+%d+)",          -- pattern match
    flurry      = "Slashing Strikes",
    fury        = "Enh. Constitution (+10)",
    garrote     = "Enh. Agility (+10)",
    holler      = "Enh. Health (+20)",
    kweed       = "Tangleweed Vigor",
    momentum    = "Glorious Momentum",
    pummel      = "Concussive Blows",
    rapid       = "Rapid Fire",
    rebuke      = "Righteous Rebuke",
    scourge     = "Ardor of the Scourge",
    shout       = "Empowered (+20)",
    surge       = "Enh. Strength",             -- pattern match (any +N)
    burst       = "Enh. Dexterity",            -- pattern match (any +N)
    tailwind    = "Breeze Archery Tailwind",
    thrash      = "Forceful Blows",
    vigor       = "Tangleweed Vigor",
    weed        = "Tangleweed Vigor",
    yowlp       = "Yertie's Yowlp",
    berserk     = "Berserking",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Check if an Effects.Buffs name is active.  Handles both literal strings
--- and Lua-pattern strings (for coupdegrace / surge / burst).
local function buffs_active(name)
    if Effects and Effects.Buffs then
        -- Try literal first
        if Effects.Buffs.active and Effects.Buffs.active(name) then
            return true
        end
        -- If the name contains pattern chars, iterate the buff table
        if name:find("[%%%(%)%+%-%.]") then
            local h = Effects.Buffs.to_h and Effects.Buffs.to_h() or {}
            for k, _ in pairs(h) do
                if k:find(name) then return true end
            end
        end
    end
    return false
end

--- Check Effects.Spells.active (literal or pattern).
local function spells_active(name)
    if Effects and Effects.Spells then
        if Effects.Spells.active and Effects.Spells.active(name) then
            return true
        end
        if name:find("[%%%(%)%+%-%.]") then
            local h = Effects.Spells.to_h and Effects.Spells.to_h() or {}
            for k, _ in pairs(h) do
                if k:find(name) then return true end
            end
        end
    end
    return false
end

--- Check Effects.Cooldowns.active (literal or pattern).
local function cooldowns_active(name)
    if Effects and Effects.Cooldowns then
        if Effects.Cooldowns.active and Effects.Cooldowns.active(name) then
            return true
        end
        if name:find("[%%%(%)%+%-%.]") then
            local h = Effects.Cooldowns.to_h and Effects.Cooldowns.to_h() or {}
            for k, _ in pairs(h) do
                if k:find(name) then return true end
            end
        end
    end
    return false
end

--- Check Effects.Debuffs.active (literal or pattern).
local function debuffs_active(name)
    if Effects and Effects.Debuffs then
        if Effects.Debuffs.active and Effects.Debuffs.active(name) then
            return true
        end
        if name:find("[%%%(%)%+%-%.]") then
            local h = Effects.Debuffs.to_h and Effects.Debuffs.to_h() or {}
            for k, _ in pairs(h) do
                if k:find(name) then return true end
            end
        end
    end
    return false
end

--- Count valid (alive) NPCs in the room.
local function gameobj_npc_count()
    local npcs = GameObj and GameObj.npcs and GameObj.npcs() or {}
    local count = 0
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" and npc.status ~= "gone" then
            count = count + 1
        end
    end
    return count
end

--- Count NPCs that pass valid_target? equivalent.
local function valid_target_count(bigshot_state)
    local npcs = GameObj and GameObj.npcs and GameObj.npcs() or {}
    local count = 0
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" and npc.status ~= "gone" then
            -- Check critter exclusion list
            local dominated = false
            local name_lower = (npc.name or ""):lower()
            for _, excl in ipairs(bigshot_state.critter_exclude or {}) do
                if name_lower:find(excl:lower(), 1, true) then
                    dominated = true
                    break
                end
            end
            if not dominated then count = count + 1 end
        end
    end
    return count
end

--- Buffs time_left helper (returns minutes remaining, 0 if not active).
local function buffs_time_left(name)
    if Effects and Effects.Buffs and Effects.Buffs.time_left then
        return Effects.Buffs.time_left(name) or 0
    end
    return 0
end

---------------------------------------------------------------------------
-- Parse / strip modifiers
---------------------------------------------------------------------------

--- Extract all parenthesized modifier strings from a command.
-- "incant 509(m50)(undead)(prone)" → {"m50", "undead", "prone"}
function M.parse_modifiers(command)
    local mods = {}
    for mod_str in command:gmatch("%(([^%)]+)%)") do
        mods[#mods + 1] = mod_str
    end
    return mods
end

--- Remove all parenthesized modifiers from a command string.
-- "incant 509(m50)(undead)" → "incant 509"
function M.strip_modifiers(command)
    return command:gsub("%b()", ""):match("^%s*(.-)%s*$")
end

---------------------------------------------------------------------------
-- Amount checks   (m50, !m50, e80, h90, mob3, valid2, etc.)
---------------------------------------------------------------------------

--- Map of amount-check prefix → function(amount) → true if condition MET.
--- In the Ruby source these return true when condition blocks execution;
--- we invert: true = "OK to execute".
---
--- Ruby: 'm' => ->(amt) { Char.mana < amt }        (true = skip)
--- Lua:  m   => function(amt) return Char.mana >= amt end  (true = execute)
local AMOUNT_CHECKS = {
    ["e"]        = function(amt) return (Char.percent_encumbrance or 0)  < amt  end,  -- encumbrance below threshold → go
    ["!e"]       = function(amt) return (Char.percent_encumbrance or 0)  >= amt end,
    ["essence"]  = function(amt)
        local val = (Resources and Resources.shadow_essence) or 0
        return val >= amt
    end,
    ["!essence"] = function(amt)
        local val = (Resources and Resources.shadow_essence) or 0
        return val < amt
    end,
    ["h"]        = function(amt) return (Char.percent_health or 100)     >= amt end,
    ["!h"]       = function(amt) return (Char.percent_health or 100)     <  amt end,
    ["k"]        = function(_)
        local kneeling = checkkneeling and checkkneeling() or false
        return not kneeling
    end,
    ["!k"]       = function(_)
        local kneeling = checkkneeling and checkkneeling() or false
        return kneeling
    end,
    ["m"]        = function(amt) return (Char.mana or 0)                 >= amt end,
    ["!m"]       = function(amt) return (Char.mana or 0)                 <  amt end,
    ["mob"]      = function(amt) return gameobj_npc_count()              >= amt end,
    ["!mob"]     = function(amt) return gameobj_npc_count()              <  amt end,
    ["s"]        = function(amt) return (Char.stamina or 0)              >= amt end,
    ["!s"]       = function(amt) return (Char.stamina or 0)              <  amt end,
    ["v"]        = function(amt) return (Char.spirit or 0)               >= amt end,
    ["!v"]       = function(amt) return (Char.spirit or 0)               <  amt end,
}

--- Amount checks that need bigshot_state.
local AMOUNT_CHECKS_STATE = {
    ["tier"]   = function(amt, st) return ((st.unarmed_tier or 0)        >= amt) end,
    ["!tier"]  = function(amt, st) return ((st.unarmed_tier or 0)        <  amt) end,
    ["valid"]  = function(amt, st) return valid_target_count(st)         >= amt  end,
    ["!valid"] = function(amt, st) return valid_target_count(st)         <  amt  end,
}

--- Ordered list of amount-check prefixes, longest first so "!essence" matches
--- before "!e", "valid" before "v", "mob" before "m", etc.
local AMOUNT_KEYS_ORDERED = {
    "!essence", "essence",
    "!valid", "valid",
    "!mob", "mob",
    "!tier", "tier",
    "!e", "!h", "!k", "!m", "!s", "!v",
    "e", "h", "k", "m", "s", "v",
}

--- Try to match mod_str as an amount check.  Returns (true, result) on match.
local function try_amount_check(mod_str, bigshot_state)
    for _, prefix in ipairs(AMOUNT_KEYS_ORDERED) do
        -- Amount checks: prefix followed by digits (possibly negative for m)
        local rest = nil
        if mod_str:sub(1, #prefix):lower() == prefix:lower() then
            rest = mod_str:sub(#prefix + 1)
        end
        if rest and rest:match("^%-?%d+$") then
            local amount = tonumber(rest)
            local checker = AMOUNT_CHECKS[prefix]
            if checker then
                return true, checker(amount)
            end
            local state_checker = AMOUNT_CHECKS_STATE[prefix]
            if state_checker then
                return true, state_checker(amount, bigshot_state or {})
            end
        end
    end
    return false, false
end

---------------------------------------------------------------------------
-- Buff-duration checks   (buff60, barrage60, etc.)
---------------------------------------------------------------------------

--- Try to match mod_str as a buff-duration check (e.g. "buff60").
--- Returns (true, result) on match.
local function try_buff_duration_check(mod_str, command)
    -- Generic "buff" + number: check the buff mapped to the command keyword
    local buff_amt = mod_str:match("^[Bb][Uu][Ff][Ff](%d+)$")
    if buff_amt then
        local amount = tonumber(buff_amt)
        -- Determine which buff to check from the base command keyword
        local cmd_keyword = M.strip_modifiers(command or ""):match("^(%S+)"):lower()
        local buff_name = M.BUFF_MAP[cmd_keyword]
        if buff_name then
            local remaining = buffs_time_left(buff_name)
            return true, (remaining <= (amount / 60.0))
        end
        -- No mapping found — condition passes (don't block)
        return true, true
    end

    -- Per-ability buff duration: "barrage60", "flurry30", etc.
    for ability, _ in pairs(M.BUFF_MAP) do
        local pat = "^" .. ability .. "(%d+)$"
        local amt_str = mod_str:lower():match(pat)
        if amt_str then
            local amount = tonumber(amt_str)
            local buff_name = M.BUFF_MAP[ability]
            if buff_name then
                local remaining = buffs_time_left(buff_name)
                return true, (remaining <= (amount / 60.0))
            end
            return true, true
        end
    end

    return false, false
end

---------------------------------------------------------------------------
-- Effect checks   (ES"name", !EB"name", EC"name", ED"name")
---------------------------------------------------------------------------

local function try_effect_check(mod_str)
    -- Match: optional !, then E, then S/B/C/D, then quoted name
    local negated, etype, name = mod_str:match('^(!?)E([SBCD])"(.+)"$')
    if not etype then return false, false end

    local is_negated = (negated == "!")
    local active = false

    if etype == "S" then
        active = spells_active(name)
    elseif etype == "B" then
        active = buffs_active(name)
    elseif etype == "C" then
        active = cooldowns_active(name)
    elseif etype == "D" then
        active = debuffs_active(name)
    end

    -- Ruby: ES"x" → !active? means "execute when spell is NOT active" (recast)
    -- Ruby: !ES"x" → active? means "execute when spell IS active"
    -- Our convention: return true = execute.
    -- ES"x" in Ruby returns true (=skip) when spell is NOT active.
    -- Inverted for us: ES"x" → execute when spell IS NOT active → return not active.
    -- Wait, re-checking Ruby:
    --   'ES'  then return !Effects::Spells.active?(pattern)
    -- That returns true when spell is NOT active → command is SKIPPED.
    -- So the command should execute when the spell IS active → we return active.
    -- Actually no: Ruby command_check returns true = skip.
    --   ES"x": !active? → true when not active → skip when not active.
    --   That means: the command should only execute when the spell IS active.
    -- Hmm, that seems backwards for a recast scenario. Let me re-check...
    -- Actually in bigshot, ES"x" means "only execute if this spell is NOT active"
    -- (i.e., recast it). Ruby returns true=skip, so !active? = skip when active
    -- is false = skip when NOT active... wait:
    --   !active? = true when active? is false = when spell is NOT active
    --   So command_check returns true (=skip) when spell is NOT active.
    --   That means command executes when spell IS active. That's wrong for recast.
    --
    -- Looking more carefully at the Ruby flow:
    --   Line 3268: return false if command_check(command, npc)
    --   command_check returns true → cmd() returns false → command is skipped
    --   command_check returns false → execution continues
    --
    -- But wait, command_check has this structure:
    --   Each modifier is checked. If ANY check returns true → command_check returns true → skip.
    --   If no modifier returns true → returns false → execute.
    --
    -- For ES"Spell": returns !active? → true when NOT active → skip.
    -- For !ES"Spell": returns active? → true when active → skip.
    --
    -- So ES"x" = skip when spell is not active = execute when spell IS active.
    -- And !ES"x" = skip when spell is active = execute when spell is NOT active.
    --
    -- This matches the usage pattern: !ES"buff" on a buff command means
    -- "only recast when the buff is NOT active".
    -- ES"debuff" means "only use this attack when the debuff IS active on me".
    --
    -- Our return: true = execute.
    -- ES"x": execute when active → return active
    -- !ES"x": execute when NOT active → return not active

    if is_negated then
        return true, not active
    else
        return true, active
    end
end

---------------------------------------------------------------------------
-- State-condition checks   (keyword modifiers)
---------------------------------------------------------------------------

--- Evaluate a keyword-style modifier (undead, prone, hidden, 506, once, etc.)
--- Returns (matched, result) where matched=true if the keyword was recognized.
local function check_state_keyword(mod_lower, target, bigshot_state, original_command)
    local npc = target or {}
    local npc_name   = (npc.name or ""):lower()
    local npc_status = (npc.status or ""):lower()
    local npc_type   = (npc.type or ""):lower()

    -------------------------------------------------------------------
    -- Active spell / effect checks
    -------------------------------------------------------------------
    if mod_lower == "506" or mod_lower == "celerity" then
        local active = Spell and Spell[506] and Spell[506].active
        return true, (active == true)
    end
    if mod_lower == "!506" or mod_lower == "!celerity" then
        local active = Spell and Spell[506] and Spell[506].active
        return true, not active
    end

    -------------------------------------------------------------------
    -- Per-ability buff state checks (barrage, bearhug, etc.)
    -- Ruby: 'barrage' → !active? → true when NOT active → skip
    -- Our: execute when active → return active
    -------------------------------------------------------------------
    -- Check plain ability keywords and their negations
    local ability_plain = mod_lower
    local ability_negated = mod_lower:match("^!(.+)$")
    if ability_negated then
        ability_plain = ability_negated
    end

    if M.BUFF_MAP[ability_plain] then
        local buff_name = M.BUFF_MAP[ability_plain]
        local active = buffs_active(buff_name)

        -- Special cases that match Ruby exactly:
        -- bearhug checks both +10 and +20
        if ability_plain == "bearhug" then
            active = buffs_active("Enh. Strength (+10)") or buffs_active("Enh. Strength (+20)")
        -- surge: pattern match any "Enh. Strength"
        elseif ability_plain == "surge" then
            active = buffs_active("Enh%. Strength")
        -- burst: pattern match any "Enh. Dexterity"
        elseif ability_plain == "burst" then
            active = buffs_active("Enh%. Dexterity")
        -- coupdegrace: pattern match Empowered (+N)
        elseif ability_plain == "coupdegrace" then
            active = buffs_active("Empowered %(%+%d+%)")
        end

        -- For negated (!burst, !surge): Ruby returns cooldown active → skip when on CD
        -- Special handling for burst and surge negations per Ruby source
        if ability_negated then
            if ability_plain == "burst" then
                return true, not cooldowns_active("Burst of Swiftness")
            elseif ability_plain == "surge" then
                return true, not cooldowns_active("Surge of Strength")
            end
            return true, active
        else
            return true, active
        end
    end

    -------------------------------------------------------------------
    -- Character state checks
    -------------------------------------------------------------------
    if mod_lower == "disease" then
        local has_disease = checkdisease and checkdisease() or false
        return true, not has_disease
    end
    if mod_lower == "!disease" then
        local has_disease = checkdisease and checkdisease() or false
        return true, has_disease
    end
    if mod_lower == "hidden" then
        local is_hidden = hidden and hidden() or false
        return true, is_hidden
    end
    if mod_lower == "!hidden" then
        local is_hidden = hidden and hidden() or false
        return true, not is_hidden
    end
    if mod_lower == "outside" then
        local is_outside = outside and outside() or false
        return true, is_outside
    end
    if mod_lower == "!outside" then
        local is_outside = outside and outside() or false
        return true, not is_outside
    end
    if mod_lower == "poison" then
        local has_poison = checkpoison and checkpoison() or false
        return true, not has_poison
    end
    if mod_lower == "!poison" then
        local has_poison = checkpoison and checkpoison() or false
        return true, has_poison
    end

    -------------------------------------------------------------------
    -- NPC / target state checks
    -------------------------------------------------------------------
    if mod_lower == "ancient" then
        -- Ruby: returns true (=skip) when name does NOT start with grizzled/ancient
        -- (exception: "ancient ghoul master" is NOT considered ancient)
        -- Our: execute when target IS ancient
        local is_ancient = (npc_name:match("^grizzled ") or npc_name:match("^ancient "))
                           and npc_name ~= "ancient ghoul master"
        return true, (is_ancient == true)
    end
    if mod_lower == "!ancient" then
        local is_ancient = (npc_name:match("^grizzled ") or npc_name:match("^ancient "))
                           and npc_name ~= "ancient ghoul master"
        return true, not is_ancient
    end

    if mod_lower == "animate" then
        return true, spells_active("Animate Dead")
    end
    if mod_lower == "!animate" then
        return true, not spells_active("Animate Dead")
    end

    if mod_lower == "censer" then
        -- Censer is a special action modifier: it tries to cast Spell 320
        -- before the main command. We return true to allow execution to continue;
        -- the actual censer casting is handled by the command executor.
        local spell_320_known = Spell and Spell[320] and Spell[320].known
        if spell_320_known and not cooldowns_active("Ethereal Censer") then
            local cost = (Spell[320].cost or 0)
            if (Char.mana or 0) >= cost then
                -- Signal to caller that censer should be cast
                if bigshot_state then
                    bigshot_state._cast_censer = true
                end
            end
        end
        return true, true  -- censer never blocks; it's an augment
    end

    if mod_lower == "flying" then
        return true, not npc_status:find("flying")
    end
    if mod_lower == "!flying" then
        return true, (npc_status:find("flying") ~= nil)
    end

    if mod_lower == "frozen" then
        return true, (npc_status:find("frozen") ~= nil)
    end
    if mod_lower == "!frozen" then
        return true, not npc_status:find("frozen")
    end

    if mod_lower == "noncorporeal" then
        -- Ruby: skip if NOT noncorporeal → execute if IS noncorporeal
        local found = false
        for token in npc_type:gmatch("[^,]+") do
            if token:match("^%s*noncorporeal%s*$") then found = true; break end
        end
        return true, found
    end
    if mod_lower == "!noncorporeal" then
        local found = false
        for token in npc_type:gmatch("[^,]+") do
            if token:match("^%s*noncorporeal%s*$") then found = true; break end
        end
        return true, not found
    end

    if mod_lower == "prone" then
        return true, (npc_status:find(M.PRONE_PATTERN) ~= nil)
    end
    if mod_lower == "!prone" then
        return true, not npc_status:find(M.PRONE_PATTERN)
    end

    if mod_lower == "rooted" then
        local is_rooted = (bigshot_state and bigshot_state.rooted) or false
        return true, is_rooted
    end
    if mod_lower == "!rooted" then
        local is_rooted = (bigshot_state and bigshot_state.rooted) or false
        return true, not is_rooted
    end

    if mod_lower == "undead" then
        local found = false
        for token in npc_type:gmatch("[^,]+") do
            if token:match("^%s*undead%s*$") then found = true; break end
        end
        return true, found
    end
    if mod_lower == "!undead" then
        local found = false
        for token in npc_type:gmatch("[^,]+") do
            if token:match("^%s*undead%s*$") then found = true; break end
        end
        return true, not found
    end

    -------------------------------------------------------------------
    -- Tier-specific checks (tier1, tier2, tier3)
    -------------------------------------------------------------------
    if mod_lower == "tier1" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) == 1)
    end
    if mod_lower == "!tier1" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) ~= 1)
    end
    if mod_lower == "tier2" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) == 2)
    end
    if mod_lower == "!tier2" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) ~= 2)
    end
    if mod_lower == "tier3" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) == 3)
    end
    if mod_lower == "!tier3" then
        return true, ((bigshot_state and bigshot_state.unarmed_tier or 0) ~= 3)
    end

    -------------------------------------------------------------------
    -- Room / splashy checks
    -------------------------------------------------------------------
    if mod_lower == "splashy" then
        local tags = Room and Room.current and Room.current.tags or {}
        local found = false
        if type(tags) == "table" then
            for _, t in ipairs(tags) do
                if t == "meta:splashy" then found = true; break end
            end
        end
        return true, found
    end
    if mod_lower == "!splashy" then
        local tags = Room and Room.current and Room.current.tags or {}
        local found = false
        if type(tags) == "table" then
            for _, t in ipairs(tags) do
                if t == "meta:splashy" then found = true; break end
            end
        end
        return true, not found
    end

    -------------------------------------------------------------------
    -- PC checks
    -------------------------------------------------------------------
    if mod_lower == "pcs" then
        -- Ruby: skip when there are non-group PCs present
        -- execute when all PCs are group members (or no PCs)
        local non_group = 0
        if checkpcs then
            local pcs = checkpcs() or {}
            local group_members = {}
            if Lich and Lich.Gemstone and Lich.Gemstone.Group and Lich.Gemstone.Group.members then
                for _, m in ipairs(Lich.Gemstone.Group.members() or {}) do
                    group_members[(m.noun or ""):lower()] = true
                end
            end
            for _, pc in ipairs(pcs) do
                if not group_members[(pc or ""):lower()] then
                    non_group = non_group + 1
                end
            end
        end
        return true, (non_group == 0)
    end
    if mod_lower == "!pcs" then
        local non_group = 0
        if checkpcs then
            local pcs = checkpcs() or {}
            local group_members = {}
            if Lich and Lich.Gemstone and Lich.Gemstone.Group and Lich.Gemstone.Group.members then
                for _, m in ipairs(Lich.Gemstone.Group.members() or {}) do
                    group_members[(m.noun or ""):lower()] = true
                end
            end
            for _, pc in ipairs(pcs) do
                if not group_members[(pc or ""):lower()] then
                    non_group = non_group + 1
                end
            end
        end
        return true, (non_group > 0)
    end

    -------------------------------------------------------------------
    -- Special state variables
    -------------------------------------------------------------------
    if mod_lower == "justice" then
        local val = bigshot_state and bigshot_state.swift_justice or 0
        return true, (val == 0)
    end
    if mod_lower == "!justice" then
        local val = bigshot_state and bigshot_state.swift_justice or 0
        return true, (val >= 1)
    end
    if mod_lower == "reflex" then
        local val = bigshot_state and bigshot_state.arcane_reflex or false
        return true, not val
    end
    if mod_lower == "!reflex" then
        local val = bigshot_state and bigshot_state.arcane_reflex or false
        return true, (val == true)
    end
    if mod_lower == "voidweaver" then
        return true, buffs_active("Voidweaver")
    end
    if mod_lower == "!voidweaver" then
        return true, not buffs_active("Voidweaver")
    end

    -------------------------------------------------------------------
    -- Registry checks  (once, room)
    -------------------------------------------------------------------
    if mod_lower == "once" then
        if not bigshot_state then return true, true end
        if not bigshot_state._commands_registry then
            bigshot_state._commands_registry = {}
        end
        local target_id = npc.id
        if not target_id then return true, true end
        local reg = bigshot_state._commands_registry[target_id]
        if reg then
            for _, cmd in ipairs(reg) do
                if cmd == original_command then
                    return true, false  -- already used on this target → skip
                end
            end
        end
        return true, true  -- not yet used → execute
    end

    if mod_lower == "room" then
        if not bigshot_state then return true, true end
        if not bigshot_state._commands_registry then
            bigshot_state._commands_registry = {}
        end
        -- Check if command was used on ANY target in current room
        for _, cmds in pairs(bigshot_state._commands_registry) do
            for _, cmd in ipairs(cmds) do
                if cmd == original_command then
                    return true, false  -- already used in this room → skip
                end
            end
        end
        return true, true  -- not yet used → execute
    end

    -------------------------------------------------------------------
    -- Repetition modifiers: not condition checks, always pass
    -------------------------------------------------------------------
    if mod_lower:match("^x%d+$") or mod_lower == "xx" then
        return true, true
    end

    -- Not recognized
    return false, false
end

---------------------------------------------------------------------------
-- Main check_modifier
---------------------------------------------------------------------------

--- Evaluate a single modifier against current state.
--- Returns true if the condition is MET (command should run).
--- Returns false if the condition FAILS (command should be skipped).
---
--- @param mod_str      string   The modifier text (e.g. "m50", "undead", 'ES"Fire Spirit"')
--- @param target       table|nil  The NPC target object
--- @param bigshot_state table   Bigshot state table (mutable; registries stored here)
--- @param original_cmd string|nil The full original command (for once/room checks)
function M.check_modifier(mod_str, target, bigshot_state, original_cmd)
    bigshot_state = bigshot_state or {}
    original_cmd = original_cmd or ""

    -- 1. Try amount checks first (m50, !e80, valid2, etc.)
    local matched, result = try_amount_check(mod_str, bigshot_state)
    if matched then return result end

    -- 2. Try buff-duration checks (buff60, barrage30, etc.)
    matched, result = try_buff_duration_check(mod_str, original_cmd)
    if matched then return result end

    -- 3. Try effect checks (ES"name", !EB"name", etc.)
    matched, result = try_effect_check(mod_str)
    if matched then return result end

    -- 4. Try keyword state checks
    matched, result = check_state_keyword(mod_str:lower(), target, bigshot_state, original_cmd)
    if matched then return result end

    -- Unknown modifier — pass through (don't block execution)
    return true
end

---------------------------------------------------------------------------
-- should_execute — check all modifiers on a command
---------------------------------------------------------------------------

--- Check all modifiers on a command string.
--- Returns true if ALL conditions are met (command should execute).
--- Returns false if ANY condition fails (skip this command).
---
--- @param command       string   Full command with modifiers, e.g. "incant 903(m50)(undead)"
--- @param target        table|nil  The NPC target
--- @param bigshot_state table     Bigshot state table
function M.should_execute(command, target, bigshot_state)
    bigshot_state = bigshot_state or {}
    local mods = M.parse_modifiers(command)

    for _, mod_str in ipairs(mods) do
        -- Skip repetition modifiers — they don't gate execution
        local lower = mod_str:lower()
        if lower:match("^x%d+$") or lower == "xx" then
            -- no-op, these are handled by get_repetition
        else
            if not M.check_modifier(mod_str, target, bigshot_state, command) then
                return false
            end
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Repetition
---------------------------------------------------------------------------

--- Return the repeat count from (xN) or (xx) modifiers.
--- (x5) → 5, (xx) → math.huge (repeat until dead), default → 1.
function M.get_repetition(command)
    for mod_str in command:gmatch("%(([^%)]+)%)") do
        local lower = mod_str:lower()
        if lower == "xx" then
            return math.huge
        end
        local n = lower:match("^x(%d+)$")
        if n then
            return tonumber(n)
        end
    end
    return 1
end

---------------------------------------------------------------------------
-- Registry management
---------------------------------------------------------------------------

--- Mark a command as used on a specific target (for "once" checks).
--- Called after successful command execution.
function M.register_once(command, target_id, bigshot_state)
    if not bigshot_state or not target_id then return end
    if not bigshot_state._commands_registry then
        bigshot_state._commands_registry = {}
    end
    local reg = bigshot_state._commands_registry[target_id]
    if not reg then
        bigshot_state._commands_registry[target_id] = { command }
    else
        -- Don't add duplicates
        for _, cmd in ipairs(reg) do
            if cmd == command then return end
        end
        reg[#reg + 1] = command
    end
end

--- Mark a command as used in the current room (for "room" checks).
--- Uses a special "__room" key in the registry.
function M.register_room(command, room_id, bigshot_state)
    if not bigshot_state or not room_id then return end
    if not bigshot_state._commands_registry then
        bigshot_state._commands_registry = {}
    end
    local key = "__room_" .. tostring(room_id)
    local reg = bigshot_state._commands_registry[key]
    if not reg then
        bigshot_state._commands_registry[key] = { command }
    else
        for _, cmd in ipairs(reg) do
            if cmd == command then return end
        end
        reg[#reg + 1] = command
    end
end

--- Clear all room-based registry entries (call on room change).
function M.clear_room_registry(bigshot_state)
    if not bigshot_state or not bigshot_state._commands_registry then return end
    -- Remove all __room_ entries and per-target entries (new room = new targets)
    bigshot_state._commands_registry = {}
end

return M
