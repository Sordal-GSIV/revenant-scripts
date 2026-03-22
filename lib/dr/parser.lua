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

-------------------------------------------------------------------------------
-- Room object XML parsers
-- Parses <component id='room objs'>...</component> lines from the game stream.
-- Populates DRRoom.npcs, DRRoom.dead_npcs, and DRRoom.room_objs.
-------------------------------------------------------------------------------

-- Gelapod constant: in DR, the domesticated gelapod trash bin is tagged as an
-- NPC (bold) but should be treated as a room object.
local GELAPOD_BOLD = "<pushBold/>a domesticated gelapod<popBold/>"
local GELAPOD_PLAIN = "domesticated gelapod"

local function room_extract_npcs(content)
    local c = content:gsub(GELAPOD_BOLD, GELAPOD_PLAIN)
    local npcs = {}
    for raw in c:gmatch("<pushBold/>(.-)<popBold/>") do
        if not (raw:find("which appears dead", 1, true) or raw:find("(dead)", 1, true)) then
            local name = raw
                :gsub(" with a .+ sitting astride its back", "")
                :gsub(" who .+", "")
                :gsub("^the ", ""):gsub("^a ", "")
                :match("^%s*(.-)%s*$")
            if name and name ~= "" then
                table.insert(npcs, name)
            end
        end
    end
    return npcs
end

local function room_extract_dead_npcs(content)
    local dead = {}
    for raw in content:gmatch("<pushBold/>(.-)<popBold/>") do
        if raw:find("which appears dead", 1, true) or raw:find("(dead)", 1, true) then
            local name = raw
                :gsub(" which appears dead", ""):gsub(" %(dead%)", "")
                :gsub("^the ", ""):gsub("^a ", "")
                :match("^%s*(.-)%s*$")
            if name and name ~= "" then
                table.insert(dead, name)
            end
        end
    end
    return dead
end

local function room_extract_objects(content)
    -- Promote gelapod from NPC to plain object before stripping bold sections
    local c = content:gsub(GELAPOD_BOLD, GELAPOD_PLAIN)
    -- Remove remaining NPC entries (bold-tagged)
    c = c:gsub("<pushBold/>.-<popBold/>", "")
    -- Remove all remaining XML tags
    c = c:gsub("<[^>]+>", "")
    -- Strip "You also see" prefix variants
    c = c:gsub("^You also see%s*,?%s*", "")
    -- Normalize " and " to comma for uniform splitting
    c = c:gsub("%s+and%s+", ",")
    local objs = {}
    for part in c:gmatch("[^,]+") do
        part = part:match("^%s*(.-)%s*$")
        part = part:gsub("%.$", ""):match("^%s*(.-)%s*$")
        -- Strip mount description
        part = part:gsub(" with a .+ sitting astride its back", "")
        -- Strip leading articles
        part = part:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", ""):gsub("^[Tt]he ", "")
        part = part:match("^%s*(.-)%s*$")
        if part ~= "" then
            table.insert(objs, part)
        end
    end
    return objs
end

--- Main dispatch function. Called for every downstream line.
function M.process(line)
    -- <component id='room objs'>: room NPCs and objects from XML game stream
    if line:find("component id='room objs'", 1, true) then
        if DRRoom then
            local content = line:match("<component id='room objs'>(.+)</component>")
            if content then
                DRRoom.npcs      = room_extract_npcs(content)
                DRRoom.dead_npcs = room_extract_dead_npcs(content)
                DRRoom.room_objs = room_extract_objects(content)
            else
                DRRoom.npcs      = {}
                DRRoom.dead_npcs = {}
                DRRoom.room_objs = {}
            end
        end
        return line
    end

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
        local current_guild = stats.get and stats.get("guild") or ""
        if current_guild then current_guild = current_guild:lower() end
        if current_guild == "barbarian" then
            parsing_state = "abilities"
            spells.start_parse("barb_abilities")
        elseif current_guild == "thief" then
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
