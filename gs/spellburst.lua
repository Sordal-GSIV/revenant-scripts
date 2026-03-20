--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: spellburst
--- version: 1.0.1
--- author: elanthia-online
--- contributors: Omnirus, Tysong
--- game: gs
--- description: Show how many spell ranks of buffs you can safely wear in Spellburst areas
--- tags: spellburst,magic,utility,buffs
---
--- Original Lich5 author: elanthia-online
---
--- Description:
---   Calculates how many 'spell ranks' worth of defensive buffs you can safely wear
---   in Spellburst areas. Uses magic ranks and level (not mana) with diminishing returns.
---   Foreign spells cost 3x the spell rank; untrained native spells cost 1.5x (floored).
---
--- Usage:
---   ;spellburst           show spellburst information
---   ;spellburst debug     show debug details (tier-by-tier breakdown)
---   ;spellburst cost <#>  show rank cost of a specific spell number
---   ;spellburst safe <#>  check if a specific spell number would be safe to wear
---
--- Changelog (from Lich5):
---   v1.0.1 (2025-08-15) - force a SKILL refresh to ensure updated skills prior to calc
---   v1.0.0 (2025-03-07) - Initial release

local TableRender = require("lib/table_render")
local Messaging   = require("lib/messaging")

-- Circle-to-profession pattern for native spell detection.
-- Derived from Lich5 is_spell_native() logic.
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

-- Force a SKILL refresh then sum all magical skill ranks.
-- Mirrors Lich5's Lich::Util.issue_command("skill", ...) call.
local function total_magical_ranks()
    quiet_command("skill", GameState.name, nil, 5)
    return Skills.arcanesymbols + Skills.magicitemuse + Skills.spellaiming + Skills.harnesspower +
           Skills.emc + Skills.smc + Skills.mmc +
           Skills.elair + Skills.elearth + Skills.elfire + Skills.elwater +
           Skills.slblessings + Skills.slreligion + Skills.slsummoning +
           Skills.sldemonology + Skills.slnecromancy +
           Skills.mldivination + Skills.mlmanipulation + Skills.mltelepathy +
           Skills.mltransference + Skills.mltransformation
end

-- Returns true if the spell circle is native to the character's profession.
local function is_spell_native(spell_num)
    local circle = math.floor(spell_num / 100)
    local prof_pattern = NATIVE_CIRCLES[circle]
    if not prof_pattern then return false end
    local prof = Stats.profession
    return prof ~= nil and prof:match(prof_pattern) ~= nil
end

-- Returns true if the spell should be excluded from spellburst cost calculations.
-- Excluded: known spells, attack spells, arcane/society circles (>=17), Bard songs (10),
-- and specific group/buff spells that don't count against spellburst limits.
local function is_spell_excluded(spell_num)
    local spell = Spell[spell_num]
    if not spell then return true end                       -- unrecognized
    if spell.known then return true end                    -- player knows this spell
    if spell.type == "attack" then return true end         -- offensive/combat spells
    local circle = math.floor(spell_num / 100)
    if circle >= 17 then return true end                   -- arcane, lost arts, society, etc.
    if circle == 10 then return true end                   -- Bard group songs
    -- Major Spiritual group spells: only exclude when nearly expired (<= 2 min timeleft)
    if (spell_num == 211 or spell_num == 215 or spell_num == 219) and spell.timeleft <= 2 then
        return true
    end
    if spell_num == 307 or spell_num == 310 or spell_num == 317 then return true end  -- Cleric group
    if spell_num == 318 then return true end               -- Raise Dead
    if spell_num == 620 then return true end               -- Resist Nature (Ranger group)
    if spell_num == 735 then return true end               -- Ensorcell flares
    if spell_num == 1125 then return true end              -- Troll's Blood (Empath group)
    if spell_num == 1213 or spell_num == 1216 then return true end  -- Monk group spells
    if spell_num == 1605 or spell_num == 1609 or spell_num == 1613 or
       spell_num == 1617 or spell_num == 1618 or spell_num == 1699 then return true end  -- Paladin group
    if spell_num == 1640 then return true end              -- Divine Word
    return false
end

-- Returns the spellburst rank cost for spell_num.
-- Foreign spell: 3x rank. Untrained native: floor(1.5x rank).
local function spell_cost(spell_num)
    if is_spell_excluded(spell_num) then return 0 end
    local rank = spell_num % 100
    if is_spell_native(spell_num) then
        return math.floor(rank * 1.5)
    end
    return rank * 3
end

-- Compute diminishing returns across tiers of avg magical ranks per level.
-- Returns (running_total, last_diminishing_return).
-- Prints tier-by-tier breakdown when debug=true.
local function calculate_diminishing_returns(magic_ranks, level, debug)
    local rate  = 0.95
    local upper = math.floor(magic_ranks / level)
    if upper < 1 then upper = 1 end
    local running_total = 0
    local last_dr = 0
    for tier = 1, upper do
        last_dr = 1 / (tier * rate)
        running_total = running_total + last_dr
        if debug then
            respond(string.format(
                "Tier: %d, ((%d * %.4f [+%.4f]) * 4) / 3 = %d",
                tier, level, running_total, last_dr,
                math.floor(level * running_total * 1.3333)
            ))
        end
    end
    return running_total, last_dr
end

-- Returns the maximum allowed spell ranks based on magical training and level.
local function max_ranks(magic_ranks, level)
    if magic_ranks < level then
        return magic_ranks
    end
    local per_level = calculate_diminishing_returns(magic_ranks, level, false)
    return math.floor(level * per_level * 1.3333)
end

-- Iterate active spells (Effects.Spells) and compute rank cost for each counted spell.
-- Returns a table of { [spell_num] = cost }.
local function active_spell_costs(debug)
    local costs  = {}
    local active = Effects.Spells.to_h()
    if not active then return costs end
    for spell_name, _ in pairs(active) do
        local spell = Spell[spell_name]
        if spell and spell.num then
            local num = spell.num
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

-- Returns (total_worn_ranks, costs_table).
local function total_worn_ranks(debug)
    local costs = active_spell_costs(debug)
    local total = 0
    for _, cost in pairs(costs) do total = total + cost end
    return total, costs
end

-- Display the full spellburst information table.
local function display(debug)
    local magic_ranks = total_magical_ranks()
    local level       = Stats.level
    local worn, costs = total_worn_ranks(debug)

    local tbl = TableRender.new({"SPELLBURST INFORMATION", ""})
    tbl:add_row({"Total magical ranks trained",        tostring(magic_ranks)})
    tbl:add_row({"Average magical ranks per level",    tostring(math.floor(magic_ranks / level))})

    local allowed
    if magic_ranks < level then
        -- Low training: each spell rank costs 1 slot; allowed = total magical ranks
        tbl:add_row({"Spell ranks allowed per rank",  "1"})
        tbl:add_row({"Spell ranks allowed per level", string.format("%.4f", magic_ranks / level)})
        allowed = magic_ranks
    else
        -- Normal path: diminishing returns on avg ranks per level
        local per_level, dr = calculate_diminishing_returns(magic_ranks, level, debug)
        tbl:add_row({"Diminishing returns from avg",  string.format("%.4f", dr)})
        tbl:add_row({"Spell ranks allowed per level", string.format("%.4f", per_level)})
        allowed = math.floor(level * per_level * 1.3333)
    end

    tbl:add_separator()
    tbl:add_row({"CURRENT OUTSIDE SPELLS WORN", "COST"})
    tbl:add_separator()

    for num, cost in pairs(costs) do
        local spell = Spell[num]
        local name  = spell and spell.name or tostring(num)
        tbl:add_row({name .. " (" .. num .. ")", tostring(cost)})
    end

    tbl:add_separator()
    tbl:add_row({"Total spell ranks worn",    tostring(worn)})
    tbl:add_row({"Total allowed spell ranks", tostring(allowed)})
    tbl:add_separator()

    if worn > allowed then
        tbl:add_row({"DANGER!  Ranks you are OVER", tostring(worn - allowed)})
    else
        tbl:add_row({"SAFE!  Ranks you are UNDER",  tostring(allowed - worn)})
    end

    Messaging.mono(tbl:render())
end

-- Main dispatch
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
        local level       = Stats.level
        local worn        = total_worn_ranks()
        local allowed     = max_ranks(magic_ranks, level)
        local safe        = worn + spell_cost(num) <= allowed
        echo("Spell " .. num .. " safe? " .. tostring(safe))
    else
        echo("Usage: ;spellburst safe <spell_number>")
    end

else
    display(false)
end
