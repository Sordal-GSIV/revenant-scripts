--- @revenant-module
--- name: dr/parser
--- description: Main DR text parser hook — routes game output to subsystem parsers

local skills  = require("lib/dr/skills")
local stats   = require("lib/dr/stats")
local spells  = require("lib/dr/spells")
local banking = require("lib/dr/banking")
local room    = require("lib/dr/room")

local M = {}

local parsing_state = nil  -- nil, "spells", "abilities", etc.

--- Main dispatch function. Called for every downstream line.
function M.process(line)
    -- Multi-line spell/ability parsing (active state)
    if parsing_state then
        -- End on prompt or blank line
        if line:match("^>") or line:match("^%s*$") then
            spells.end_parse()
            parsing_state = nil
        else
            spells.parse_line(line)
        end
        return
    end

    -- EXP line: "  Evasion:         250 84% pondering"
    local skill_name, rank, pct, rate = line:match("^%s+(%S.-):%s+(%d+)%s+(%d+)%%%s+(%S+)")
    if skill_name then
        skills.update(skill_name, tonumber(rank), tonumber(pct), rate)
        return
    end

    -- EXP header: "  Circle: 42"
    local circle = line:match("^%s+Circle: (%d+)")
    if circle then
        stats.set("circle", tonumber(circle))
        return
    end

    -- INFO race/guild: "Name: Whoever  Race: Human  Guild: Warrior Mage"
    local race, guild = line:match("^Name:%s+.-%s+Race:%s+(.-)%s+Guild:%s+(.-)$")
    if race then
        stats.set("race", race)
        stats.set("guild", guild)
        return
    end

    -- INFO gender/age: "Gender: Male  Age: 30"
    local gender, age = line:match("^Gender:%s+(%w+)%s+Age:%s+(%d+)")
    if gender then
        stats.set("gender", gender)
        stats.set("age", tonumber(age))
        return
    end

    -- Also here
    if line:match("^Also here:%s+") then
        room.parse_also_here(line)
        return
    end

    -- Bank balance: "Your current balance is 42 gold Kronars."
    local balance_text = line:match("^Your current balance is (.+)")
    if balance_text then
        -- Detect DR currency from text (Kronars, Lirums, Dokoras)
        local amount = balance_text:match("([%d,]+)")
        if amount then
            amount = tonumber((amount:gsub(",", "")))
            if balance_text:find("Kronar") then
                banking.set_balance("kronars", amount)
            elseif balance_text:find("Lirum") then
                banking.set_balance("lirums", amount)
            elseif balance_text:find("Dokora") then
                banking.set_balance("dokoras", amount)
            end
        end
        return
    end

    -- Spellbook start
    if line:match("^You have the following spell") then
        parsing_state = "spells"
        spells.start_parse("spells")
        return
    end

    -- Ability start
    if line:match("^You have the following abilities") then
        local guild = stats.get and stats.get("guild") or ""
        if guild then guild = guild:lower() end
        if guild == "barbarian" then
            parsing_state = "abilities"
            spells.start_parse("barb_abilities")
        elseif guild == "thief" then
            parsing_state = "abilities"
            spells.start_parse("thief_abilities")
        else
            parsing_state = "abilities"
            spells.start_parse("abilities")
        end
        return
    end
end

return M
