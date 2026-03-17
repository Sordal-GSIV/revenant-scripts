--- @revenant-script
--- name: resource
--- version: 1.12.0
--- author: elanthia-online
--- contributors: Tysong, FFNG, Xanlin, Rinualdo, Maodan
--- game: gs
--- description: Universal resource calculator for enchanting, ensorcelling, sanctifying, and more
--- tags: resource,tears,enchant,enchanting,ensorcell,sanctify,recall,loresinging
---
--- Changelog (from Lich5):
---   v1.12.0 - Various updates and additions
---
--- Usage:
---   ;resource bonus <profession>  - Show profession success bonus formula
---   ;resource all                 - Show all known bonuses
---   ;resource chart <profession>  - Print cost chart
---   ;resource calc <start> <end> <rate> - Calculate enchant cost
---   ;resource item <noun>         - Recall item and show success chance
---   ;resource chance <difficulty> <type> <bonus> - Calculate success chance
---   ;resource rolls               - Show numeric roll descriptions
---   ;resource mats                - Show material difficulty modifiers

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PROFESSIONS = {
    "Wizard", "Sorcerer", "Cleric", "Empath", "Bard", "Ranger",
    "Paladin", "Rogue", "Warrior", "Monk",
}

-- Enchant difficulty modifiers by material
local MATERIAL_MODS = {
    { name = "Iron/Steel",       mod = 0 },
    { name = "Bronze",           mod = 0 },
    { name = "Mithril",          mod = -5 },
    { name = "Ora (White)",      mod = -10 },
    { name = "Ora (Black)",      mod = -20 },
    { name = "Imflass",          mod = -10 },
    { name = "Vultite",          mod = -15 },
    { name = "Rolaren",          mod = -20 },
    { name = "Faenor",           mod = -5 },
    { name = "Glaes",            mod = -15 },
    { name = "Gornar",           mod = -5 },
    { name = "Drakar",           mod = -10 },
    { name = "Rhimar",           mod = -10 },
    { name = "Zorchar",          mod = -10 },
    { name = "Vaalorn",          mod = -15 },
    { name = "Krodera/Kroderine", mod = -100 },
    { name = "Eonake",           mod = -25 },
    { name = "Mithglin",        mod = -20 },
    { name = "Golvern",         mod = -30 },
    { name = "Kelyn",           mod = -5 },
    { name = "Invar",           mod = 0 },
    { name = "Adamantine",      mod = -40 },
    { name = "Razern",          mod = -15 },
    { name = "Eahnor",          mod = -25 },
    { name = "Veil Iron",       mod = -30 },
    { name = "Urglaes",         mod = -50 },
    { name = "Coraesine",       mod = -60 },
}

-- Roll descriptions and numeric ranges
local ROLL_DESCRIPTIONS = {
    { desc = "Practically impossible",  range = "1-5" },
    { desc = "Extremely difficult",     range = "6-15" },
    { desc = "Very difficult",          range = "16-25" },
    { desc = "Difficult",               range = "26-40" },
    { desc = "Somewhat difficult",      range = "41-55" },
    { desc = "A toss-up",               range = "56-60" },
    { desc = "Better than even odds",   range = "61-75" },
    { desc = "Good chance",             range = "76-85" },
    { desc = "Very good chance",        range = "86-95" },
    { desc = "Practically certain",     range = "96-100" },
}

-- Enchant cost per step (cumulative essence cost)
local ENCHANT_STEPS = {
    { bonus = 5,   essence = 10000 },
    { bonus = 10,  essence = 10000 },
    { bonus = 15,  essence = 20000 },
    { bonus = 20,  essence = 40000 },
    { bonus = 25,  essence = 50000 },
    { bonus = 30,  essence = 100000 },
    { bonus = 35,  essence = 200000 },
    { bonus = 40,  essence = 250000 },
    { bonus = 45,  essence = 500000 },
    { bonus = 50,  essence = 750000 },
}

-- Ensorcell tiers
local ENSORCELL_TIERS = {
    { tier = 1, essence = 5000 },
    { tier = 2, essence = 10000 },
    { tier = 3, essence = 20000 },
    { tier = 4, essence = 40000 },
    { tier = 5, essence = 80000 },
}

-- Sanctify tiers
local SANCTIFY_TIERS = {
    { tier = 1, essence = 5000 },
    { tier = 2, essence = 10000 },
    { tier = 3, essence = 25000 },
    { tier = 4, essence = 50000 },
    { tier = 5, essence = 100000 },
    { tier = 6, essence = 200000 },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(str, width)
    return str .. string.rep(" ", math.max(0, width - #str))
end

local function pad_left(str, width)
    return string.rep(" ", math.max(0, width - #str)) .. str
end

local function separator(width)
    return string.rep("-", width or 60)
end

local function show_header(title)
    respond("")
    respond(separator(60))
    respond("  " .. title)
    respond(separator(60))
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function cmd_rolls()
    show_header("Roll Descriptions")
    respond(string.format("  %-30s %s", "Description", "Roll Range"))
    respond("  " .. separator(45))
    for _, r in ipairs(ROLL_DESCRIPTIONS) do
        respond(string.format("  %-30s %s", r.desc, r.range))
    end
    respond("")
end

local function cmd_mats()
    show_header("Material Difficulty Modifiers")
    respond(string.format("  %-25s %s", "Material", "Modifier"))
    respond("  " .. separator(40))
    for _, m in ipairs(MATERIAL_MODS) do
        respond(string.format("  %-25s %+d", m.name, m.mod))
    end
    respond("")
end

local function cmd_chart(profession)
    profession = profession or Stats.prof or "Wizard"

    show_header("Enchant Cost Chart (" .. profession .. ")")
    respond(string.format("  %-10s %-15s %-15s", "Bonus", "Step Cost", "Cumulative"))
    respond("  " .. separator(45))

    local total = 0
    for _, step in ipairs(ENCHANT_STEPS) do
        total = total + step.essence
        respond(string.format("  +%-9d %-15s %-15s",
            step.bonus,
            string.format("%d", step.essence),
            string.format("%d", total)))
    end
    respond("")

    show_header("Ensorcell Cost Chart")
    respond(string.format("  %-10s %-15s", "Tier", "Essence Cost"))
    respond("  " .. separator(30))
    for _, t in ipairs(ENSORCELL_TIERS) do
        respond(string.format("  T%-9d %-15d", t.tier, t.essence))
    end
    respond("")

    show_header("Sanctify Cost Chart")
    respond(string.format("  %-10s %-15s", "Tier", "Essence Cost"))
    respond("  " .. separator(30))
    for _, t in ipairs(SANCTIFY_TIERS) do
        respond(string.format("  S%-9d %-15d", t.tier, t.essence))
    end
    respond("")
end

local function cmd_calc(start_bonus, end_bonus, silver_rate)
    start_bonus = tonumber(start_bonus) or 0
    end_bonus = tonumber(end_bonus) or 50
    silver_rate = tonumber(silver_rate) or 50

    show_header(string.format("Enchant Cost: +%d to +%d", start_bonus, end_bonus))

    local total_essence = 0
    for _, step in ipairs(ENCHANT_STEPS) do
        if step.bonus > start_bonus and step.bonus <= end_bonus then
            total_essence = total_essence + step.essence
        end
    end

    local silver_cost = total_essence * silver_rate

    respond(string.format("  Total Essence: %d", total_essence))
    respond(string.format("  Silver Cost:   %d (at %d silver/essence)", silver_cost, silver_rate))
    respond("")
end

local function cmd_chance(difficulty, cast_type, bonus)
    difficulty = difficulty or "E25"
    cast_type = cast_type or "enchant"
    bonus = tonumber(bonus) or 0

    show_header(string.format("Chance Calculator: %s %s bonus:%d", difficulty, cast_type, bonus))

    -- Parse difficulty code
    local dtype = difficulty:sub(1, 1):upper()
    local dlevel = tonumber(difficulty:sub(2)) or 1

    local base_difficulty = 0
    if dtype == "E" then
        base_difficulty = dlevel * 2
    elseif dtype == "T" then
        base_difficulty = dlevel * 10
    elseif dtype == "S" then
        base_difficulty = dlevel * 8
    elseif dtype == "M" then
        base_difficulty = dlevel * 10
    elseif dtype == "R" then
        base_difficulty = dlevel * 2
    elseif dtype == "A" then
        base_difficulty = dlevel * 2
    elseif dtype == "L" then
        base_difficulty = dlevel * 10
    elseif dtype == "B" then
        base_difficulty = dlevel * 10
    elseif dtype == "J" then
        base_difficulty = dlevel * 10
    end

    local chance = 50 + bonus - base_difficulty
    chance = math.max(1, math.min(100, chance))

    respond(string.format("  Base Difficulty: %d", base_difficulty))
    respond(string.format("  Your Bonus:      %d", bonus))
    respond(string.format("  Success Chance:  %d%%", chance))
    respond("")

    -- Show matching roll description
    for _, r in ipairs(ROLL_DESCRIPTIONS) do
        local low, high = r.range:match("(%d+)-(%d+)")
        if chance >= tonumber(low) and chance <= tonumber(high) then
            respond(string.format("  Assessment: %s", r.desc))
            break
        end
    end
    respond("")
end

local function cmd_item(noun)
    if not noun or noun == "" then
        respond("[resource] Please specify an item noun: ;resource item <noun>")
        return
    end

    show_header("Item Recall: " .. noun)
    fput("recall " .. noun)
    respond("")
end

local function cmd_bonus(profession)
    profession = profession or Stats.prof or "Wizard"

    show_header("Bonus Formula: " .. profession)

    local formulas = {
        Wizard    = "Arcane Symbols + (Magic Item Use / 2) + (Harness Power / 2) + Elemental Mana Control + Wizard Base (925 ranks * 2)",
        Sorcerer  = "Arcane Symbols + (Magic Item Use / 2) + Sorcerer Base (735 ranks * 2) + Elemental Mana Control + Spirit Mana Control",
        Cleric    = "Arcane Symbols + (Magic Item Use / 2) + Spiritual Lore (Religion) + Cleric Base (330 ranks * 2)",
        Empath    = "Arcane Symbols + (Magic Item Use / 2) + Mental Lore (Manipulation) + Empath Base (1120 ranks)",
        Bard      = "Arcane Symbols + (Magic Item Use / 2) + Bard Base (1020 ranks) + Elemental Lore",
        Ranger    = "Arcane Symbols + (Magic Item Use / 2) + Ranger Base (620 ranks * 2)",
        Paladin   = "Arcane Symbols + (Magic Item Use / 2) + Paladin Base (1620 ranks * 2)",
        Rogue     = "Arcane Symbols + (Magic Item Use / 2)",
        Warrior   = "Arcane Symbols + (Magic Item Use / 2)",
        Monk      = "Arcane Symbols + (Magic Item Use / 2)",
    }

    local formula = formulas[profession] or "Unknown profession"
    respond("  " .. formula)
    respond("")
end

local function cmd_all()
    show_header("All Known Profession Bonuses")
    for _, prof in ipairs(PROFESSIONS) do
        respond("  [" .. prof .. "]")
        cmd_bonus(prof)
    end
end

local function show_help()
    respond("")
    respond("=== Resource Calculator Help ===")
    respond("  ;resource bonus <profession>              - Show bonus formula")
    respond("  ;resource all                             - Show all bonuses")
    respond("  ;resource chart [profession]              - Print cost chart")
    respond("  ;resource calc <start> <end> [rate]       - Calculate enchant cost")
    respond("  ;resource item <noun>                     - Recall and show info")
    respond("  ;resource chance <difficulty> <type> <bonus> - Calculate chance")
    respond("  ;resource rolls                           - Show roll descriptions")
    respond("  ;resource mats                            - Show material modifiers")
    respond("")
    respond("  Difficulty codes: E1-E50 (enchant), T1-T5 (ensorcell), S1-S6 (sanctify)")
    respond("                    M1-M5 (tattoo), R1-R25 (resistance), A1-A25 (arts)")
    respond("                    L1-L6 (luck), B1-B6 (battle standard), J1-J5 (bloodstone)")
    respond("================================")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args = Script.args or {}
local cmd = (args[1] or ""):lower()

if cmd == "" or cmd == "help" then
    show_help()
elseif cmd == "bonus" then
    cmd_bonus(args[2])
elseif cmd == "all" then
    cmd_all()
elseif cmd == "chart" then
    cmd_chart(args[2])
elseif cmd == "calc" then
    cmd_calc(args[2], args[3], args[4])
elseif cmd == "chance" then
    cmd_chance(args[2], args[3], args[4])
elseif cmd == "item" then
    cmd_item(args[2])
elseif cmd == "rolls" then
    cmd_rolls()
elseif cmd == "mats" then
    cmd_mats()
else
    respond("[resource] Unknown command: " .. cmd)
    show_help()
end
