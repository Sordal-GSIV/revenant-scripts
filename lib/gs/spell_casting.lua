--- Spell casting engine for Revenant (Lich5 compatible).
--- Provides spell:cast(), spell:channel(), spell:putup(), spell:putdown(), etc.
---
--- Usage: require("lib/spell_casting") -- patches Spell metatable globally

local SpellEval = require("lib/spell_eval")

-- Cast lock: only one script can cast at a time
local _cast_lock = nil  -- script name holding lock, or nil

-- Track when each spell was last cast
_spell_last_cast = _spell_last_cast or {}  -- global: spell_num → os.time()

-- Manual spell overrides (putup/putdown)
local _spell_overrides = {}  -- spell_num → { activated_at, duration }

-- Prepare result patterns (from Lich5 @@prepare_regex)
local PREPARE_PATTERNS = {
    "Your spell[%w%s]* is ready",
    "You already have a spell readied",
    "You can't think clearly enough to prepare a spell",
    "You are concentrating too intently .* to prepare a spell",
    "You are too injured to make that dextrous of a movement",
    "The searing pain in your throat makes that impossible",
    "But you don't have any mana",
    "You can't make that dextrous of a move",
    "You do not know that spell",
    "All you manage to do is cough up some blood",
}

-- Cast result patterns (from Lich5 @@results_regex)
local CAST_PATTERNS = {
    "Cast Roundtime %d+ Seconds?%.",
    "Sing Roundtime %d+ Seconds?%.",
    "Cast at what",
    "But you don't have any mana",
    "You don't have a spell prepared",
    "keeps the spell from working",
    "Be at peace my child",
    "Your magic fizzles ineffectually",
    "All you manage to do is cough up some blood",
    "And give yourself away!  Never!",
    "You are unable to do that right now",
    "You feel a sudden rush of power as you absorb %d+ mana",
    "leaving you casting at nothing but thin air",
    "You don't seem to be able to move to do that",
    "You can't think clearly enough to prepare a spell",
    "You do not currently have a target",
}

--- Match a line against a list of patterns.
local function match_any(line, patterns)
    for _, pat in ipairs(patterns) do
        if string.find(line, pat) then return true end
    end
    return false
end

--- Acquire the cast lock. Polls until available.
local function acquire_cast_lock()
    local me = Script.name or "_unknown"
    while _cast_lock ~= nil and _cast_lock ~= me do
        pause(0.1)
    end
    _cast_lock = me
end

--- Release the cast lock.
local function release_cast_lock()
    _cast_lock = nil
end

-- Spell method table
local SpellMethods = {}

function SpellMethods:affordable(opts)
    local mc = SpellEval.mana_cost(self, opts)
    local sc = SpellEval.spirit_cost(self, opts)
    local stc = SpellEval.stamina_cost(self, opts)
    if mc > 0 and GameState.mana < mc then return false end
    if sc > 0 and GameState.spirit < sc then return false end
    if stc > 0 and GameState.stamina < stc then return false end
    return true
end

function SpellMethods:cost(opts)
    return {
        mana = SpellEval.mana_cost(self, opts),
        spirit = SpellEval.spirit_cost(self, opts),
        stamina = SpellEval.stamina_cost(self, opts),
    }
end

function SpellMethods:time_per(opts)
    return SpellEval.duration(self, opts)
end

function SpellMethods:cast(target, opts)
    opts = opts or {}

    -- Affordability check
    if not opts.force and not self:affordable(opts) then
        echo("Cannot afford to cast " .. self.name)
        return nil
    end

    acquire_cast_lock()
    local ok, result = pcall(function()
        -- Wait for roundtimes
        waitrt()
        waitcastrt()

        -- Stance management
        if self.stance and not opts.no_stance then
            fput("stance offensive")
        end

        -- Prepare
        fput("prep " .. self.num)
        -- Read lines until we see a prepare result
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end

        -- Cast
        local cast_cmd = "cast"
        if target then cast_cmd = cast_cmd .. " " .. target end
        fput(cast_cmd)

        -- Wait for cast result
        local cast_result = nil
        local result_patterns = opts.results or CAST_PATTERNS
        for _ = 1, 50 do
            local line = get()
            if match_any(line, result_patterns) then
                cast_result = line
                break
            end
        end

        -- Record last cast timestamp
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end

        -- After-stance
        if not opts.no_stance then
            local after = Spell.after_stance
            if after then
                fput("stance " .. after)
            end
        end

        return cast_result
    end)
    release_cast_lock()

    if not ok then error(result) end
    return result
end

function SpellMethods:channel(target, opts)
    opts = opts or {}
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()
        if self.stance and not opts.no_stance then
            fput("stance offensive")
        end
        fput("prep " .. self.num)
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end
        local cmd = "channel"
        if target then cmd = cmd .. " " .. target end
        fput(cmd)
        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, opts.results or CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        if not opts.no_stance then
            local after = Spell.after_stance
            if after then fput("stance " .. after) end
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

function SpellMethods:evoke(target, opts)
    opts = opts or {}
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()
        fput("prep " .. self.num)
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end
        local cmd = "evoke"
        if target then cmd = cmd .. " " .. target end
        fput(cmd)
        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, opts.results or CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

function SpellMethods:incant(opts)
    opts = opts or {}
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()
        fput("incant " .. self.num)
        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, opts.results or CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

--- Force-cast: prepare then cast at target with optional extra args.
--- Skips affordability check (the "force" in force_cast).
--- Matches Lich5: Spell[num].force_cast(target, extra)
function SpellMethods:force_cast(target, extra)
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()

        -- Prepare the spell
        fput("prepare " .. self.num)
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end

        -- Build cast command
        local cmd = "cast"
        if target and target ~= "" then
            cmd = cmd .. " " .. target
        end
        if extra and extra ~= "" then
            cmd = cmd .. " " .. extra
        end
        fput(cmd)

        -- Wait for cast result
        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

--- Force-incant: send incant command with optional extra args (verb, count, etc.).
--- Skips affordability check. Extra can be "channel 3", "evoke", "3", etc.
--- Matches Lich5: Spell[num].force_incant(extra)
function SpellMethods:force_incant(extra)
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()

        -- Build incant command
        local cmd = "incant " .. self.num
        if extra and extra ~= "" then
            cmd = cmd .. " " .. extra
        end
        fput(cmd)

        -- Wait for cast result
        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

--- Force-channel: prepare then channel at target with optional extra args.
--- Matches Lich5: Spell[num].force_channel(target, extra)
function SpellMethods:force_channel(target, extra)
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()

        fput("prepare " .. self.num)
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end

        local cmd = "channel"
        if target and target ~= "" then
            cmd = cmd .. " " .. target
        end
        if extra and extra ~= "" then
            cmd = cmd .. " " .. extra
        end
        fput(cmd)

        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

--- Force-evoke: prepare then evoke at target with optional extra args.
--- Matches Lich5: Spell[num].force_evoke(target, extra)
function SpellMethods:force_evoke(target, extra)
    acquire_cast_lock()
    local ok, result = pcall(function()
        waitrt()
        waitcastrt()

        fput("prepare " .. self.num)
        for _ = 1, 50 do
            local line = get()
            if match_any(line, PREPARE_PATTERNS) then break end
        end

        local cmd = "evoke"
        if target and target ~= "" then
            cmd = cmd .. " " .. target
        end
        if extra and extra ~= "" then
            cmd = cmd .. " " .. extra
        end
        fput(cmd)

        local cast_result = nil
        for _ = 1, 50 do
            local line = get()
            if match_any(line, CAST_PATTERNS) then
                cast_result = line
                break
            end
        end
        if cast_result then
            _spell_last_cast[self.num] = os.time()
        end
        return cast_result
    end)
    release_cast_lock()
    if not ok then error(result) end
    return result
end

function SpellMethods:putup(opts)
    local dur = self:time_per(opts)
    _spell_overrides[self.num] = {
        activated_at = os.clock(),
        duration = dur,
    }
end

function SpellMethods:putdown()
    _spell_overrides[self.num] = nil
end

-- Metatable for spell tables with methods
local SpellMT = { __index = SpellMethods }

--- Check if a spell has an active override (putup).
local function check_override(spell_num)
    local ov = _spell_overrides[spell_num]
    if not ov then return nil end
    local elapsed = os.clock() - ov.activated_at
    if ov.duration > 0 and elapsed >= ov.duration then
        _spell_overrides[spell_num] = nil
        return nil
    end
    return ov
end

--- Wrap a spell table with casting methods and override-aware active/timeleft.
local function wrap_spell(t)
    if type(t) ~= "table" then return t end

    -- Check for putup override
    local num = t.num
    if num then
        local ov = check_override(num)
        if ov then
            -- Override active state
            if not t.active then
                t.active = true
            end
            local elapsed = os.clock() - ov.activated_at
            local secs_left = ov.duration > 0 and (ov.duration - elapsed) or 0
            t.secsleft = math.max(0, secs_left)
            t.timeleft = t.secsleft / 60.0
        end
    end

    -- Attach last_cast timestamp if available
    if num and _spell_last_cast[num] then
        t.last_cast = _spell_last_cast[num]
    end

    setmetatable(t, SpellMT)
    return t
end

-- Patch Spell's __index to wrap returned tables with casting methods.
-- We save the original metamethod and intercept lookups.
local spell_mt = getmetatable(Spell)
if spell_mt then
    local original_index = spell_mt.__index
    if type(original_index) == "function" then
        spell_mt.__index = function(tbl, key)
            local result = original_index(tbl, key)
            if type(result) == "table" then
                return wrap_spell(result)
            end
            return result
        end
    end
end

-- Also wrap Spell.active() results
local original_active = Spell.active
if original_active then
    Spell.active = function()
        local result = original_active()
        if type(result) == "table" then
            for i, spell_t in ipairs(result) do
                if type(spell_t) == "table" then
                    result[i] = wrap_spell(spell_t)
                end
            end
        end
        return result
    end
end

return {
    wrap_spell = wrap_spell,
    SpellMethods = SpellMethods,
    PREPARE_PATTERNS = PREPARE_PATTERNS,
    CAST_PATTERNS = CAST_PATTERNS,
}
