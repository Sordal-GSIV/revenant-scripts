--- @revenant-script
--- name: skin
--- version: 1.0.0
--- author: Crannach
--- game: dr
--- description: Skinning script with arrange/ritual support for all guilds including Necromancer
--- tags: skinning, loot, hunting, necromancer
---
--- Ported from skin.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;skin   - Skin the nearest dead creature
---
--- Requires drinfomon to be running for guild detection.

local perform_preserve = true
local perform_harvest = false

local arrange_corpses = true
local skinning_tool = "blade"
local worn_skinning_tool = false

-- Detect guild and equipment
local guild = DRStats.guild or "unknown"
if guild == "unknown" then
    DRC.bput("info", "Guild:")
    guild = DRStats.guild or "unknown"
end

local shield = nil
local rh = GameObj.right_hand()
local weapon = (rh and rh.name) or "Empty"
local moonblade = weapon:find("moonblade") and true or false

local lh = GameObj.left_hand()
if lh and lh.name then
    if lh.name:find("shield") or lh.name:find("sipar") then
        shield = lh.name
    end
end

-- Skin message patterns
local skin_success = {
    "Moving with impressive skill",
    "Your .* moves as a fluid extension",
    "You skillfully peel",
    "With preternatural poise",
    "Working deftly",
    "You slice away a bloody trophy",
    "You work diligently at skinning",
    "You work hard at peeling",
    "You skin .* fairly well",
    "You struggle with .* and manage",
}

local skin_fail = {
    "cannot be skinned",
    "You hideously bungle",
    "You struggle with .*, making a bloody mess",
}

local all_skin_patterns = {}
for _, p in ipairs(skin_success) do table.insert(all_skin_patterns, p) end
for _, p in ipairs(skin_fail) do table.insert(all_skin_patterns, p) end

-- Arrange the corpse
local function arrange_corpse()
    local arranged = false
    local skinnable = nil
    local critter_name = nil

    while not arranged do
        waitrt()
        local result = DRC.bput("arrange", {
            "cannot be skinned",
            "You begin to arrange",
            "You continue arranging",
            "You complete arranging",
            "already been arranged",
            "You make a mistake .* but manage not to damage",
            "You make a serious mistake",
            "Arrange what",
        })

        if result:find("cannot be skinned") then
            skinnable = false
            arranged = true
        elseif result:find("already been arranged") then
            arranged = true
        elseif result:find("You complete arranging") then
            arranged = true
            skinnable = true
        elseif result:find("You begin to arrange") or result:find("You continue arranging") then
            skinnable = true
        elseif result:find("Arrange what") then
            echo("No corpse found to arrange.")
            fput("loot")
            return nil, false
        elseif result:find("serious mistake") then
            arranged = true
            skinnable = false
        end
    end
    return critter_name, skinnable ~= false
end

-- Necromancer rituals
local function preserve_ritual()
    waitrt()
    DRC.bput("perform preserve", {"You bend over", "Rituals do not work"})
    waitrt()
end

local function harvest_ritual()
    waitrt()
    DRC.bput("perform harvest", {"You bend over"})
    waitrt()
    fput("drop mat")
end

-- Main skin logic
local function do_skin()
    waitrt()
    fput("retreat")
    waitrt()
    fput("retreat")
    waitrt()

    local skinnable = true
    if arrange_corpses then
        _, skinnable = arrange_corpse()
        if not skinnable then
            -- Still try necro rituals
            if guild == "Necromancer" and perform_preserve then
                preserve_ritual()
            end
            if guild == "Necromancer" and perform_harvest then
                harvest_ritual()
            end
            fput("loot")
            return
        end
    end

    if guild == "Necromancer" then
        if perform_preserve then preserve_ritual() end
        if perform_harvest then harvest_ritual() end
    end

    -- Equip skinning tool
    if weapon ~= "Empty" and not moonblade then
        fput("sheath " .. weapon)
    end
    if not moonblade and not worn_skinning_tool then
        fput("wield " .. skinning_tool)
    end
    if shield and not worn_skinning_tool then
        fput("wear " .. shield)
    end

    -- Skin
    if not perform_harvest then
        fput("skin")
        while true do
            local line = get()
            if line then
                local matched = false
                for _, pat in ipairs(all_skin_patterns) do
                    if line:find(pat) then
                        matched = true
                        break
                    end
                end
                if matched then
                    waitrt()
                    if line:find("cannot be skinned") and guild == "Necromancer" then
                        harvest_ritual()
                    end
                    -- Re-equip
                    if shield and not worn_skinning_tool then
                        fput("remove " .. shield)
                    end
                    waitrt()
                    if not moonblade and not worn_skinning_tool then
                        fput("sheath " .. skinning_tool)
                    end
                    if weapon ~= "Empty" and not moonblade then
                        fput("wield " .. weapon)
                    end
                    break
                end
            end
        end
    end
end

do_skin()
fput("loot")
