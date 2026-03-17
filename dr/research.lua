--- @revenant-script
--- name: research
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Train magic skills via research, then scholarship. Detects guild and cycles through magic types.
--- tags: research, magic, training, scholarship
---
--- Ported from research.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;research <mana_prep>   - Start research training with given mana prep amount
---
--- Start in a room where you can collect grass and rocks.

local mana_prep = Script.vars[1] or "20"
local instrument = "bones"
local song = "scales masterful"
local book = "blacksmith"

local counter = 0
local expcheck_idx = 0

-- Detect guild
local function detect_guild()
    local result = DRC.bput("info", {
        "Guild: Barbarian", "Guild: Bard", "Guild: Cleric",
        "Guild: Ranger", "Guild: Thief", "Guild: Empath",
        "Guild: War Mage", "Guild: Necromancer", "Guild: Moon Mage",
        "Guild: Paladin", "Guild: Trader",
    })
    if result:find("Barbarian") then return "barb"
    elseif result:find("Bard") then return "bard"
    elseif result:find("Cleric") then return "cler"
    elseif result:find("Ranger") then return "rang"
    elseif result:find("Thief") then return "thie"
    elseif result:find("Empath") then return "empa"
    elseif result:find("War Mage") or result:find("War mage") then return "warm"
    elseif result:find("Necromancer") then return "necr"
    elseif result:find("Moon Mage") or result:find("Moon mage") then return "moon"
    elseif result:find("Paladin") then return "pala"
    elseif result:find("Trader") then return "trad"
    end
    return "unknown"
end

local guild = detect_guild()
echo("Detected guild: " .. guild)

-- Research skill types to cycle through
local research_types = {
    { skill = "Primary Magic", research = "field" },
    { skill = "Augmentation",  research = "spell" },
    { skill = "Augmentation",  research = "augm" },
    { skill = "Warding",       research = "ward" },
    { skill = "Utility",       research = "util" },
    { skill = "Arcana",        research = "fund" },
}

local function check_skill_full(skill_name)
    local xp = DRSkill.getxp(skill_name)
    return xp and xp >= 17
end

local function do_research_cycle(research_type)
    -- Try to start research
    local result = DRC.bput("research " .. research_type .. " 300", {
        "don't have a strong enough grasp",
        "You confidently begin to bend",
        "You tentatively reach out",
    })

    if result:find("don't have a strong enough") then
        return false
    end

    -- Do training activities while researching
    if guild == "moon" then
        start_script("predict", {"research"})
        pause(0.1)
    end

    fput("stand")

    for i = 1, 4 do
        fput("collect rock")
        pause(1)
        waitrt()
        fput("kick pile")
        fput("forage grass")
        pause(1)
        waitrt()
        for j = 1, 5 do
            fput("braid my grass")
            pause(1)
            waitrt()
        end
        fput("hunt")
        pause(1)
        waitrt()
        fput("appraise leather")
        fput("appraise plate")
        fput("appraise mail")
        fput("appraise shirt")
        pause(1)
        waitrt()
        fput("appraise cowl")
        fput("appraise helm")
        pause(1)
        waitrt()
        fput("appraise gloves")
        fput("appraise gauntlets")
        pause(1)
        waitrt()
        fput("collect rock")
        pause(1)
        waitrt()
        fput("kick pile")
    end

    fput("drop my grass")
    fput("drop my other grass")
    return true
end

-- Main loop
local function main()
    while true do
        local did_research = false
        for _, rt in ipairs(research_types) do
            if not check_skill_full(rt.skill) then
                echo("Researching: " .. rt.research .. " for " .. rt.skill)

                -- Prep a spell and collect materials
                fput("prep gaf " .. mana_prep)
                fput("collect rock")
                pause(1)
                waitrt()
                fput("kick pile")
                fput("cast")
                fput("stow left")
                fput("stow right")

                if do_research_cycle(rt.research) then
                    did_research = true
                end
            end
        end

        if not did_research then
            echo("All research skills full or unavailable.")
            fput("dump junk")
            echo("Starting scholarship training...")
            start_script("scholarship", {instrument, song, book})
            wait_while(function() return running("scholarship") end)
        end
    end
end

main()
