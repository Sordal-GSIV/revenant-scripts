--- @revenant-script
--- name: deedcalc
--- version: 1.1.0
--- author: elanthia-online
--- game: gs
--- description: Calculate deed costs and optionally acquire deeds automatically
--- tags: deeds, utility, calculator
---
--- Usage:
---   ;deedcalc              - Show deed cost chart
---   ;deedcalc --get        - Acquire 10 deeds
---   ;deedcalc --get=5      - Acquire 5 deeds
---   ;deedcalc --help       - Show help

local MAX_DEEDS = 200
local RUBY_COST = 4500
local RUBY_VALUE = 13500

local function calc_cost(deeds, gs3_level)
    return (deeds * deeds) * 20 + gs3_level * 100 + 101
end

local function gs3_level()
    local exp = Experience.exp or 0
    if exp < 50000 then return math.floor(exp / 10000)
    elseif exp < 150000 then return 5 + math.floor((exp - 50000) / 20000)
    elseif exp < 300000 then return 10 + math.floor((exp - 150000) / 30000)
    elseif exp < 500000 then return 15 + math.floor((exp - 300000) / 40000)
    else return 20 + math.floor((exp - 500000) / 50000)
    end
end

local function format_silver(n)
    local s = tostring(n)
    local result = ""
    for i = #s, 1, -1 do
        result = s:sub(i, i) .. result
        if (#s - i + 1) % 3 == 0 and i > 1 then result = "," .. result end
    end
    return result
end

local args = script.vars

if args[1] == "--help" or args[1] == "help" then
    echo("DeedCost - Calculate deed costs")
    echo(";deedcalc              - Show chart")
    echo(";deedcalc --get        - Acquire 10 deeds")
    echo(";deedcalc --get=N      - Acquire N deeds")
    echo("Max deeds: " .. MAX_DEEDS)
    exit()
end

local get_num = nil
if args[1] then
    local n = args[1]:match("%-%-get=(%d+)")
    if n then get_num = tonumber(n)
    elseif args[1] == "--get" then get_num = 10 end
end

fput("experience")
local level = gs3_level()
local current = Experience.deeds or 0

if get_num then
    local actual = math.min(get_num, MAX_DEEDS - current)
    if actual <= 0 then echo("Already at max deeds!"); exit() end

    local total_rubies = 0
    for i = current, current + actual - 1 do
        local cost = calc_cost(i, level)
        total_rubies = total_rubies + math.ceil(cost / RUBY_VALUE)
    end
    local silver = total_rubies * RUBY_COST

    echo("Deeds to acquire: " .. actual)
    echo("Rubies needed: " .. total_rubies)
    echo("Silver needed: " .. format_silver(silver))
else
    echo("Deed Cost Chart (GS3 Level " .. level .. ", Current: " .. current .. ")")
    echo("Deed#  |  Cost")
    echo("-------+-----------")
    for i = current + 1, math.min(current + 20, MAX_DEEDS) do
        echo(string.format("%5d  | %s", i, format_silver(calc_cost(i - 1, level))))
    end
end
