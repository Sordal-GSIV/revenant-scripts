--- Spell formula evaluator for Lich5 effect-list.xml formulas.
--- Translates Ruby-ish formula strings to Lua and evaluates in a sandbox.

local M = {}

-- Sandbox environment: only safe math/game globals
local function make_sandbox()
    return {
        math = math,
        tonumber = tonumber,
        tostring = tostring,
        Stats = Stats,
        Skills = Skills,
        Spells = Spells,
        Spell = Spell,
        GameState = GameState,
        Char = Char,
    }
end

--- Transform a Lich5 Ruby formula string into evaluable Lua.
function M.transform(formula)
    if not formula or formula == "" then return "0" end
    local expr = formula

    -- Replace Ruby ternary: `cond ? a : b` is not valid Lua
    -- This is complex in general; handle the common pattern:
    -- `(Spell[N].known? ? X : Y)` → `(Spell.known_p(N) and (X) or (Y))`
    expr = expr:gsub("Spell%[(%d+)%]%.known%?%s*%?%s*([%d%.]+)%s*:%s*([%d%.]+)",
        function(num, a, b)
            return "((Spell.known_p(" .. num .. ") and " .. a .. " or " .. b .. "))"
        end)

    -- Replace @Variable references
    expr = expr:gsub("@Skills%.(%w+)", "Skills.%1")
    expr = expr:gsub("@Stats%.(%w+)", "Stats.%1")
    expr = expr:gsub("@Spells%.(%w+)", "Spells.%1")
    expr = expr:gsub("@Level", "Stats.level")

    -- Replace .to_i with math.floor wrapper
    expr = expr:gsub("%(([^)]+)%)%.to_i", "math.floor(%1)")

    -- Replace .to_f — no-op in Lua (numbers are floats)
    expr = expr:gsub("%.to_f", "")

    -- Replace Ruby array max: [a, b].max → math.max(a, b)
    expr = expr:gsub("%[([^%]]+)%]%.max", function(inner)
        return "math.max(" .. inner .. ")"
    end)

    -- Replace Ruby array min: [a, b].min → math.min(a, b)
    expr = expr:gsub("%[([^%]]+)%]%.min", function(inner)
        return "math.min(" .. inner .. ")"
    end)

    -- Replace Spells.minorspiritual etc. (no-underscore aliases work via Lua metatable)
    -- These should work as-is since the Spells table handles both forms

    return expr
end

--- Evaluate a formula string, returning a number.
--- Returns 0 on error.
function M.eval(formula)
    local expr = M.transform(formula)
    local sandbox = make_sandbox()
    local fn, err = load("return " .. expr, "spell_formula", "t", sandbox)
    if not fn then
        -- Formula too complex for simple transform (e.g., Ruby blocks, if/else chains)
        -- Return 0 rather than crashing
        return 0
    end
    local ok, result = pcall(fn)
    if not ok then return 0 end
    return tonumber(result) or 0
end

--- Evaluate mana cost for a spell.
--- opts.cast_type: "self" (default) or "target"
function M.mana_cost(spell, opts)
    local ct = (opts and opts.cast_type) or "self"
    local formula = spell.mana_cost  -- self-cast formula from build_spell_table
    if ct == "target" then
        -- Would need full cost table access; for now use self-cast
        formula = spell.mana_cost
    end
    if not formula then return 0 end
    return M.eval(formula)
end

--- Evaluate spirit cost for a spell.
function M.spirit_cost(spell, opts)
    if not spell.spirit_cost then return 0 end
    return M.eval(spell.spirit_cost)
end

--- Evaluate stamina cost for a spell.
function M.stamina_cost(spell, opts)
    if not spell.stamina_cost then return 0 end
    return M.eval(spell.stamina_cost)
end

--- Evaluate duration for a spell (returns seconds).
function M.duration(spell, opts)
    if not spell.duration_formula then return 0 end
    return M.eval(spell.duration_formula)
end

--- Evaluate a specific bonus formula.
function M.bonus(spell, bonus_type)
    -- bonus_list contains the names; would need the formula from the Rust side
    -- For now return 0 as the bonus formulas aren't individually exposed yet
    return 0
end

return M
