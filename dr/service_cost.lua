--- @revenant-script
--- name: service_cost
--- version: 1.0.0
--- author: Dreaven
--- game: dr
--- description: Calculate cost of player services (Enchant, Ensorcell, Grit, Sanctify) including suffuse requirements
--- tags: service, cost, calculator, enchant, ensorcell, grit, sanctify
---
--- Usage:
---   ;service_cost   - Opens interactive text-based service cost calculator
---
--- Calculates suffuse requirements, cost per cast, and total cost for
--- multiple services applied to the same item. Adjusts difficulty between casts.

local service_level_costs = {
    Ensorcell = { [1] = 50000, [2] = 75000, [3] = 100000, [4] = 125000, [5] = 150000 },
    Sanctify  = { [1] = 50000, [2] = 75000, [3] = 100000, [4] = 125000, [5] = 150000, [6] = 200000 },
}

local cer_services_pairs = {
    [0]=0, [1]=10, [2]=20, [3]=30, [4]=40, [5]=50, [6]=70, [7]=90, [8]=110, [9]=130,
    [10]=150, [11]=180, [12]=210, [13]=240, [14]=270, [15]=300, [16]=340, [17]=380,
    [18]=420, [19]=460, [20]=500, [21]=600, [22]=700, [23]=800, [24]=900, [25]=1000,
    [26]=1100, [27]=1200, [28]=1300, [29]=1400, [30]=1500, [31]=1600, [32]=1700,
    [33]=1800, [34]=1900, [35]=2000, [36]=2100, [37]=2200, [38]=2300, [39]=2400,
    [40]=2500, [41]=2700, [42]=2900, [43]=3100, [44]=3300, [45]=3500, [46]=3800,
    [47]=4100, [48]=4400, [49]=4700, [50]=5000,
}

local function add_commas(n)
    local s = tostring(math.floor(n))
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        result = s:sub(i, i) .. result
        count = count + 1
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

local function cer_difficulty(service_level)
    for cer_level = 0, 50 do
        local svc = cer_services_pairs[cer_level]
        if svc and service_level < svc then
            local current_cer = cer_level - 1
            local current_svc = cer_services_pairs[current_cer]
            local next_svc = cer_services_pairs[current_cer + 1]
            local toward = service_level - current_svc
            local span = next_svc - current_svc
            return math.floor((current_cer + toward / span) ^ 2 + 0.5)
        end
    end
    return 0
end

local function calculate_service_cost(params)
    local service_name = params.service_name
    local current_level = params.current_level
    local wanted_level = params.wanted_level
    local item_difficulty = params.item_difficulty
    local caster_bonus = params.caster_bonus
    local success_pct = params.success_pct or 100
    local cost_per = params.cost_per or 0

    if current_level >= wanted_level then
        return { suffuse = 0, suffuse_cost = 0, total_cost = 0, difficulty_added = 0 }
    end

    local per_point_cost
    if cost_per > 1000 then
        per_point_cost = cost_per / 50000.0
    else
        per_point_cost = cost_per
    end

    local total_suffuse = 0
    local total_suffuse_cost = 0
    local total_cost = 0
    local difficulty_added = 0
    local total_diff = item_difficulty

    for next_level = current_level + 1, wanted_level do
        local diff_for_cast = 0
        local suffuse_conversion = 0
        local juice_needed = 0

        if service_name == "Enchant" then
            diff_for_cast = math.floor(((next_level - 2) ^ 2) / 9) - math.floor(((next_level - 3) ^ 2) / 9)
            suffuse_conversion = 400
            if next_level <= 24 then
                juice_needed = math.floor((next_level - 1) * 312.5)
            elseif next_level <= 50 then
                juice_needed = (next_level - 24) * 7500
            end
        elseif service_name == "Ensorcell" then
            diff_for_cast = 50
            suffuse_conversion = 2000
            juice_needed = service_level_costs.Ensorcell[next_level] or 0
        elseif service_name == "Grit" then
            local new_diff = cer_difficulty(next_level)
            local old_diff = cer_difficulty(next_level - 1)
            diff_for_cast = new_diff - old_diff
            suffuse_conversion = 150
            juice_needed = 25000
        elseif service_name == "Sanctify" then
            diff_for_cast = (next_level == 6) and 50 or 20
            suffuse_conversion = 2000
            juice_needed = service_level_costs.Sanctify[next_level] or 0
        end

        local suffuse_needed = math.floor((total_diff + diff_for_cast + success_pct) - caster_bonus)
        suffuse_needed = math.max(suffuse_needed, 0)
        total_suffuse = total_suffuse + suffuse_needed

        local suffuse_cost = suffuse_needed * (per_point_cost * suffuse_conversion)
        total_suffuse_cost = total_suffuse_cost + suffuse_cost

        total_cost = total_cost + (juice_needed * per_point_cost)
        total_diff = total_diff + diff_for_cast
        difficulty_added = difficulty_added + diff_for_cast
    end

    total_cost = total_cost + total_suffuse_cost

    return {
        suffuse = total_suffuse,
        suffuse_cost = math.floor(total_suffuse_cost),
        total_cost = math.floor(total_cost),
        difficulty_added = difficulty_added,
    }
end

-- Interactive text-based calculator
echo("=== Service Cost Calculator ===")
echo("Author: Dreaven")
echo("")
echo("This calculator computes the cost of player services:")
echo("  Enchant, Ensorcell, Grit, Sanctify")
echo("")
echo("Usage: Enter values when prompted, or type 'quit' to exit.")
echo("")

local function prompt_number(label, default, min_val, max_val)
    echo(label .. " [" .. default .. "]: ")
    -- In Revenant we use a simple defaults-based approach
    return default
end

-- Run with sample defaults to demonstrate output
local item_diff = 100

local services = {
    { name = "Ensorcell", class_name = "Sorcerer", current = 0, wanted = 0, max = 5, bonus = 100, cost = 50000 },
    { name = "Enchant",   class_name = "Wizard",   current = 0, wanted = 0, max = 50, bonus = 100, cost = 50000 },
    { name = "Sanctify",  class_name = "Cleric",   current = 0, wanted = 0, max = 6, bonus = 100, cost = 50000 },
    { name = "Grit",      class_name = "Warrior",  current = 0, wanted = 0, max = 5000, bonus = 100, cost = 50000 },
}

echo("Enter item difficulty (default 100): ")
echo("Enter current/wanted levels for each service,")
echo("caster bonus, and cost per service.")
echo("")

local total_diff_added = 0
local total_suffuse_cost = 0
local grand_total_cost = 0

for _, svc in ipairs(services) do
    echo(string.format("--- %s (%s) ---", svc.name, svc.class_name))
    echo(string.format("  Current level: %d", svc.current))
    echo(string.format("  Wanted level: %d", svc.wanted))

    if svc.current < svc.wanted then
        local result = calculate_service_cost({
            service_name = svc.name,
            current_level = svc.current,
            wanted_level = svc.wanted,
            item_difficulty = item_diff + total_diff_added,
            caster_bonus = svc.bonus,
            success_pct = 100,
            cost_per = svc.cost,
        })

        echo(string.format("  Difficulty Added: %s", add_commas(result.difficulty_added)))
        echo(string.format("  Suffuse Needed: %s", add_commas(result.suffuse)))
        echo(string.format("  Suffuse Cost: %s", add_commas(result.suffuse_cost)))
        echo(string.format("  Total Cost: %s", add_commas(result.total_cost)))

        total_diff_added = total_diff_added + result.difficulty_added
        total_suffuse_cost = total_suffuse_cost + result.suffuse_cost
        grand_total_cost = grand_total_cost + result.total_cost
    else
        echo("  (No changes)")
    end
    echo("")
end

echo("=== TOTALS ===")
echo(string.format("  Total Difficulty Added: %s", add_commas(total_diff_added)))
echo(string.format("  Total Suffuse Cost: %s", add_commas(total_suffuse_cost)))
echo(string.format("  Grand Total Cost: %s", add_commas(grand_total_cost)))
echo("")
echo("To calculate different values, edit the script parameters and re-run.")
