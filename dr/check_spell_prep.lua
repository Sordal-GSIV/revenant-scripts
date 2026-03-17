--- @revenant-script
--- name: check_spell_prep
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Finds the minimum prep needed for a spell to move a skill.
--- tags: magic, training, spell
---
--- Usage: ;check_spell_prep <spell> <min_prep> <skill>

local spell = Script.vars[1]
local min_prep = tonumber(Script.vars[2])
local skill = Script.vars[3]

if not spell or not min_prep or not skill then
    echo("Usage: ;check_spell_prep <spell> <min_prep> <skill>")
    return
end

local function get_skill_prep(spell_name, floor_prep, skill_name)
    local current = DRSkill.getxp(skill_name)
    echo("Checking " .. skill_name .. " movement using spell: " .. spell_name
         .. " starting at skill: " .. current .. ", and using " .. floor_prep .. " base prep...")
    local target = current + 1

    while checkmana() < 99 do
        echo("Waiting for full mana...")
        pause(5)
    end

    while DRSkill.getxp(skill_name) < target do
        echo("Check prep at " .. floor_prep)
        fput("prep " .. spell_name .. " " .. floor_prep)
        waitfor("fully prepared to cast")
        fput("cast")
        waitrt()
        if DRSkill.getxp(skill_name) >= target then
            echo("Skill movement prep identified at: " .. floor_prep)
            return floor_prep
        end
        echo("Skill does not move with a prep of " .. floor_prep .. "...")
        floor_prep = floor_prep + 1
    end
    return floor_prep
end

local result = get_skill_prep(spell, min_prep, skill)
echo("Prepare " .. spell .. " at " .. tostring(result) .. " mana to move " .. skill .. ".")
