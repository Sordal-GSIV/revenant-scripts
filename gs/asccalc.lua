--- @revenant-script
--- name: asccalc
--- version: 1.0.4
--- author: Kaetel
--- game: gs
--- tags: ascension, utility, calculator
--- description: Parse ascension skill allocations and report ATP/EXP costs
---
--- Original Lich5 authors: Kaetel
--- Ported to Revenant Lua from AscCalc.lic v1.0.4
---
--- Usage: ;asccalc

local function format_small(v, width)
    width = width or 4
    return string.format("%" .. width .. "d", v)
end

local function to_exp(v, width)
    width = width or 12
    local n = v * 50000
    -- Add commas
    local s = tostring(n)
    local pos = #s % 3
    if pos == 0 then pos = 3 end
    local result = s:sub(1, pos)
    for i = pos + 1, #s, 3 do
        result = result .. "," .. s:sub(i, i + 2)
    end
    return string.format("%" .. width .. "s", result)
end

local function calc_cost(skill, ranks)
    if skill == "Transcend Destiny" then
        local cost = 0
        for rank = 1, ranks do
            cost = cost + math.min(rank * 10, 50)
        end
        return cost
    end

    local tier = math.floor(ranks / 5)
    local depth = ranks % 5
    local cost = 0
    for t = 1, tier do
        cost = cost + 5 * t
    end
    if depth > 0 then
        cost = cost + depth * (tier + 1)
    end
    return cost
end

-- Gather data
local results = quiet_command("ASC INFO", "your Ascension Abilities are as follows")
local milestone_results = quiet_command("ASC MILESTONE", "your Ascension Milestones are as follows")
local gemstone_results = quiet_command("GEMSTONE SLOTS", "You have not yet unlocked Gemstones|You have %d+ Gemstone slot")

local report = {}
local cost_subtotal = 0
local ranks_total = 0
local unused = 0
local milestones_total = 0
local gemstone_slots = 0

-- Parse ascension skills
for _, line in ipairs(results or {}) do
    local skill, cur = line:match("([A-Za-z%-%s]+)%s+<d.-(%d+)/%d+")
    if skill and cur then
        skill = skill:match("^%s*(.-)%s*$")
        local ranks = tonumber(cur)
        local cost = calc_cost(skill, ranks)
        report[#report + 1] = { skill, format_small(ranks), format_small(cost), to_exp(cost) }
        ranks_total = ranks_total + ranks
        cost_subtotal = cost_subtotal + cost
    end
    local u = line:match("Available Ascension Abilities Points: (%d+)")
    if u then unused = tonumber(u) end
end

-- Parse milestones
for _, line in ipairs(milestone_results or {}) do
    if line:match("%d+%..*Yes") then
        milestones_total = milestones_total + 1
    end
end

-- Parse gemstone slots
for _, line in ipairs(gemstone_results or {}) do
    local slots = line:match("You have (%d+) Gemstone slot")
    if slots then gemstone_slots = tonumber(slots) end
end

local cost_total = cost_subtotal - milestones_total + unused

report[#report + 1] = { "------", "", "", "" }
report[#report + 1] = { "Subtotal", "", format_small(cost_subtotal), to_exp(cost_subtotal) }
report[#report + 1] = { "- Milestones", "", format_small(-milestones_total), to_exp(-milestones_total) }
report[#report + 1] = { "+ Unallocated", "", format_small(unused), to_exp(unused) }
report[#report + 1] = { "Total", format_small(ranks_total), format_small(cost_total), to_exp(cost_total) }

-- Display table
echo(string.format("%-25s %6s %6s %14s", "Skill", "Ranks", "ATPs", "EXP"))
echo(string.rep("-", 55))
for _, row in ipairs(report) do
    echo(string.format("%-25s %6s %6s %14s", row[1], row[2], row[3], row[4]))
end

if gemstone_slots > 0 then
    echo("")
    echo("You have unlocked " .. gemstone_slots .. " gemstone slot(s).")
end
