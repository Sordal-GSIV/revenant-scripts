--- @revenant-script
--- name: spellburst
--- version: 1.0.1
--- author: elanthia-online
--- contributors: Omnirus, Tysong
--- game: gs
--- description: Show how many spell ranks of buffs you can safely wear in Spellburst areas
--- tags: spellburst,magic,utility,buffs
---
--- Usage:
---   ;spellburst           show spellburst information
---   ;spellburst debug     show debug details
---   ;spellburst cost <#>  show cost of a specific spell
---   ;spellburst safe <#>  check if a specific spell is safe to wear

local TableRender = require("lib/table_render")
local Messaging = require("lib/messaging")

-- Circle-to-profession mapping for native spell detection
local NATIVE_CIRCLES = {
    [1]  = "Cleric|Empath|Monk|Paladin|Rogue|Sorcerer|Warrior",
    [2]  = "Cleric|Empath",
    [3]  = "Cleric",
    [4]  = "Bard|Rogue|Sorcerer|Warrior|Wizard",
    [5]  = "Wizard",
    [6]  = "Ranger",
    [7]  = "Sorcerer",
    [8]  = "Empath",
    [9]  = "Wizard",
    [10] = "Bard",
    [11] = "Empath",
    [12] = "Monk|Savant",
    [13] = "Savant",
    [14] = "Savant",
    [16] = "Paladin",
}

local function total_magical_ranks()
    -- Force skill refresh
    quiet_command("skill", GameState.name, 5)

    return Skills.arcanesymbols() + Skills.magicitemuse() + Skills.spellaiming() + Skills.harnesspower() +
           Skills.emc() + Skills.smc() + Skills.mmc() +
           Skills.elair() + Skills.elearth() + Skills.elfire() + Skills.elwater() +
           Skills.slblessings() + Skills.slreligion() + Skills.slsummoning() +
           Skills.sldemonology() + Skills.slnecromancy() +
           Skills.mldivination() + Skills.mlmanipulation() + Skills.mltelepathy() +
           Skills.mltransference() + Skills.mltransformation()
end

local function is_spell_native(spell_num)
    local circle = math.floor(spell_num / 100)
    local prof_pattern = NATIVE_CIRCLES[circle]
    if not prof_pattern then return false end
    return Stats.profession() and Stats.profession():match(prof_pattern) ~= nil
end

local function is_spell_excluded(spell_num)
    local spell = Spell[spell_num]
    if not spell then return true end
    if spell.known() then return true end
    if spell.type and spell.type() == "attack" then return true end
    local circle = math.floor(spell_num / 100)
    if circle >= 17 then return true end
    if circle == 10 then return true end -- Bard songs
    -- Specific exclusions
    local num = spell_num
    if num == 211 or num == 215 or num == 219 then return true end
    if num == 307 or num == 310 or num == 317 then return true end
    if num == 318 or num == 620 or num == 735 then return true end
    if num == 1125 or num == 1213 or num == 1216 then return true end
    if num == 1605 or num == 1609 or num == 1613 or num == 1617 or num == 1618 or num == 1699 then return true end
    if num == 1640 then return true end
    return false
end

local function spell_cost(spell_num)
    if is_spell_excluded(spell_num) then return 0 end
    local rank = spell_num % 100
    if is_spell_native(spell_num) then
        return math.floor(rank * 1.5)
    end
    return rank * 3
end

local function calculate_diminishing_returns(magic_ranks, level, debug)
    local rate = 0.95
    local upper = math.floor(magic_ranks / level)
    if upper < 1 then upper = 1 end
    local running_total = 0
    local last_dr = 0
    for tier = 1, upper do
        last_dr = 1 / (tier * rate)
        running_total = running_total + last_dr
        if debug then
            respond(string.format("Tier: %d, ((level * %.4f) * 4/3) = %d",
                tier, running_total, math.floor(level * running_total * 1.3333)))
        end
    end
    return running_total, last_dr
end

local function max_ranks(magic_ranks, level, debug)
    if magic_ranks < level then
        return magic_ranks
    end
    local per_level = calculate_diminishing_returns(magic_ranks, level, debug)
    return math.floor(level * per_level * 1.3333)
end

local function active_spell_costs(debug)
    local costs = {}
    local active = Effects.active_spells()
    if not active then return costs end
    for spell_name, _ in pairs(active) do
        local spell = Spell[spell_name]
        if spell and spell.num then
            local num = spell.num()
            if not is_spell_excluded(num) then
                local cost = spell_cost(num)
                costs[num] = cost
                if debug then
                    respond(string.format("  %s (%d): cost %d", spell_name, num, cost))
                end
            end
        end
    end
    return costs
end

local function total_worn_ranks(debug)
    local costs = active_spell_costs(debug)
    local total = 0
    for _, cost in pairs(costs) do total = total + cost end
    return total, costs
end

local function display(debug)
    local magic_ranks = total_magical_ranks()
    local level = Stats.level()
    local worn, costs = total_worn_ranks(debug)
    local allowed = max_ranks(magic_ranks, level, debug)

    local tbl = TableRender.new({"SPELLBURST INFORMATION", ""})
    tbl:add_row({"Total magical ranks trained", tostring(magic_ranks)})
    tbl:add_row({"Average magical ranks per level", tostring(math.floor(magic_ranks / level))})

    if magic_ranks >= level then
        local per_level, dr = calculate_diminishing_returns(magic_ranks, level, debug)
        tbl:add_row({"Diminishing returns from avg", string.format("%.4f", dr)})
        tbl:add_row({"Spell ranks allowed per level", string.format("%.4f", per_level)})
    end

    tbl:add_separator()
    tbl:add_row({"CURRENT OUTSIDE SPELLS WORN", "COST"})
    tbl:add_separator()

    for num, cost in pairs(costs) do
        local spell = Spell[num]
        local name = spell and spell.name and spell.name() or tostring(num)
        tbl:add_row({name .. " (" .. num .. ")", tostring(cost)})
    end

    tbl:add_separator()
    tbl:add_row({"Total spell ranks worn", tostring(worn)})
    tbl:add_row({"Total allowed spell ranks", tostring(allowed)})
    tbl:add_separator()

    if worn > allowed then
        tbl:add_row({"DANGER! Ranks OVER", tostring(worn - allowed)})
    else
        tbl:add_row({"SAFE! Ranks UNDER", tostring(allowed - worn)})
    end

    Messaging.mono(tbl:render())
end

-- Main
local action = Script.vars[1]

if action and action:lower() == "debug" then
    display(true)
elseif action and action:lower() == "cost" then
    local num = tonumber(Script.vars[2])
    if num then
        echo("Spell " .. num .. " cost: " .. spell_cost(num))
    else
        echo("Usage: ;spellburst cost <spell_number>")
    end
elseif action and action:lower() == "safe" then
    local num = tonumber(Script.vars[2])
    if num then
        local magic_ranks = total_magical_ranks()
        local level = Stats.level()
        local worn = total_worn_ranks()
        local allowed = max_ranks(magic_ranks, level)
        local safe = worn + spell_cost(num) <= allowed
        echo("Spell " .. num .. " safe? " .. tostring(safe))
    else
        echo("Usage: ;spellburst safe <spell_number>")
    end
else
    display(false)
end
