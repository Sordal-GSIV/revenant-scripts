--- @revenant-script
--- name: wmfight
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: War Mage multi-weapon training via summoning - cycles through weapon types
--- tags: combat, war mage, summoning, training, weapons
---
--- Ported from wmfight.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;wmfight   - Start weapon cycling combat (requires summoned weapon in hand)
---
--- Requires drinfomon. Uses summoning weapon ability to train multiple weapon skills.
--- Needs Elementalism and Expansive Infusions spells, arm-worn shield, parry stick,
--- belt knife, premade bundle, cambrinth armband.

local hiding = "off"

local function detect_weapon()
    local result = DRC.bput("glance", {
        "electric bola", "stone bola", "icy bola",
        "stone javelin", "icy javelin", "electric javelin",
        "mallet", "hara", "maul",
        "scimitar", "broadsword", "blade",
        "quarterstaff",
        "stone lance", "icy lance", "electric lance",
        "empty hands",
    })

    if result:find("bola") then return "bola", "Light Thrown", "ranged"
    elseif result:find("javelin") then return "javelin", "Heavy Thrown", "ranged"
    elseif result:find("mallet") then return "mallet", "Small Blunt", "melee"
    elseif result:find("hara") then return "hara", "Large Blunt", "melee"
    elseif result:find("maul") then return "maul", "Twohanded Blunt", "melee"
    elseif result:find("scimitar") then return "scimitar", "Small Edged", "melee"
    elseif result:find("broadsword") then return "broadsword", "Large Edged", "melee"
    elseif result:find("blade") then return "blade", "Twohanded Edged", "melee"
    elseif result:find("quarterstaff") then return "quarterstaff", "Staves", "melee"
    elseif result:find("lance") then return "lance", "Polearms", "melee"
    elseif result:find("empty hands") then return "brawl", "Brawling", "brawl"
    end
    return nil, nil, nil
end

-- Weapon progression for shape/summon cycling
local weapon_cycle = {
    "mallet", "hara", "maul",       -- blunts
    "scimitar", "broadsword", "blade", -- edges
    "quarterstaff", "lance",          -- staves/poles
}

local shape_map = {
    mallet = "small blunt",
    hara = "large blunt",
    maul = "2hb",
    scimitar = "small edge",
    broadsword = "large edge",
    blade = "2he",
    quarterstaff = "stave",
    lance = "pole",
}

local function check_exp(skill_name)
    local xp = DRSkill.getxp(skill_name) or 0
    local rank = DRSkill.getrank(skill_name) or 0
    return xp > 30 or rank > 110
end

local function do_attack(weapon, attack_type)
    waitrt()
    if attack_type == "melee" then
        fput("attack")
        local r = DRC.bput("", {
            "entangled in a web", "wait",
            "aren't close enough", "What do you want to advance",
            "fatigued", "tired",
            "nothing else to face", "You turn to",
            "Roundtime",
        })
        return r
    elseif attack_type == "ranged" then
        fput("get " .. weapon)
        fput("lob left")
        return ""
    elseif attack_type == "brawl" then
        if hiding == "on" then
            fput("hide")
            waitrt()
            pause(0.5)
            fput("stalk")
            waitrt()
            pause(0.5)
        end
        fput("attack")
        return ""
    end
end

local weapon, skill, attack_type = detect_weapon()
if not weapon then
    echo("Could not detect weapon. Make sure you have a summoned weapon or are empty-handed.")
    return
end

echo("Starting wmfight with: " .. weapon .. " (" .. skill .. ")")

while true do
    if check_exp(skill) then
        echo("Skill " .. skill .. " is trained enough, switching weapon...")
        -- Find next weapon in cycle
        waitrt()
        -- Simple: just cycle through shapes
        local switched = false
        for _, w in ipairs(weapon_cycle) do
            if not check_exp(shape_map[w] and skill or "") then
                local shape_to = shape_map[w]
                if shape_to then
                    fput("shape " .. weapon .. " to " .. shape_to)
                    waitrt()
                    pause(0.5)
                    weapon, skill, attack_type = detect_weapon()
                    switched = true
                    break
                end
            end
        end
        if not switched then
            echo("All weapon skills trained! Done.")
            break
        end
    end

    do_attack(weapon, attack_type)
    waitrt()
    pause(0.5)

    -- Loot if target dead
    fput("loot")
end
