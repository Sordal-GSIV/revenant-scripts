--- @revenant-script
--- name: circlecheck
--- version: 1.0.0
--- author: rpherbig
--- game: dr
--- description: Display progress toward next circle with skill requirements by guild
--- tags: circle, training, skills, progress
---
--- Ported from circlecheck.lic (Lich5) to Revenant Lua
---
--- Requires: drinfomon
---
--- Usage:
---   ;circlecheck        - Show full circle requirements
---   ;circlecheck short  - Show only skills needed for next circle
---   ;circlecheck next   - Same as short

local brief = false
local args = Script.vars or {}
if args[1] and (args[1]:lower() == "short" or args[1]:lower() == "brief" or args[1]:lower() == "next") then
    brief = true
end

local skills = {
    -- Survival
    { name = "Scouting",       type = "Survival" },
    { name = "Evasion",        type = "Survival" },
    { name = "Athletics",      type = "Survival" },
    { name = "Stealth",        type = "Survival" },
    { name = "Perception",     type = "Survival" },
    { name = "Locksmithing",   type = "Survival" },
    { name = "First Aid",      type = "Survival" },
    { name = "Skinning",       type = "Survival" },
    { name = "Outdoorsmanship",type = "Survival" },
    { name = "Thievery",       type = "Survival" },
    { name = "Backstab",       type = "Survival" },
    { name = "Thanatology",    type = "Survival" },
    -- Lore
    { name = "Forging",        type = "Lore" },
    { name = "Outfitting",     type = "Lore" },
    { name = "Engineering",    type = "Lore" },
    { name = "Alchemy",        type = "Lore" },
    { name = "Scholarship",    type = "Lore" },
    { name = "Appraisal",      type = "Lore" },
    { name = "Tactics",        type = "Lore" },
    { name = "Mechanical Lore",type = "Lore" },
    { name = "Performance",    type = "Lore" },
    { name = "Empathy",        type = "Lore" },
    { name = "Enchanting",     type = "Lore" },
    { name = "Trading",        type = "Lore" },
    -- Magic
    { name = "Attunement",     type = "Magic" },
    { name = "Arcana",         type = "Magic" },
    { name = "Targeted Magic", type = "Magic" },
    { name = "Debilitation",   type = "Magic" },
    { name = "Warding",        type = "Magic" },
    { name = "Augmentation",   type = "Magic" },
    { name = "Utility",        type = "Magic" },
    { name = "Sorcery",        type = "Magic" },
    { name = "Summoning",      type = "Magic" },
    { name = "Astrology",      type = "Magic" },
    { name = "Theurgy",        type = "Magic" },
    -- Weapons
    { name = "Parry Ability",  type = "Weapon" },
    { name = "Small Edged",    type = "Weapon" },
    { name = "Large Edged",    type = "Weapon" },
    { name = "Twohanded Edged",type = "Weapon" },
    { name = "Small Blunt",    type = "Weapon" },
    { name = "Large Blunt",    type = "Weapon" },
    { name = "Twohanded Blunt",type = "Weapon" },
    { name = "Slings",         type = "Weapon" },
    { name = "Bows",           type = "Weapon" },
    { name = "Crossbows",      type = "Weapon" },
    { name = "Staves",         type = "Weapon" },
    { name = "Polearms",       type = "Weapon" },
    { name = "Light Thrown",   type = "Weapon" },
    { name = "Heavy Thrown",   type = "Weapon" },
    { name = "Brawling",       type = "Weapon" },
    -- Armor
    { name = "Shield Usage",   type = "Armor" },
    { name = "Light Armor",    type = "Armor" },
    { name = "Chain Armor",    type = "Armor" },
    { name = "Brigandine",     type = "Armor" },
    { name = "Plate Armor",    type = "Armor" },
    { name = "Defending",      type = "Armor" },
}

local guild = DRStats.guild or "unknown"
local circle = DRStats.circle or 0

echo("=== Circle Check ===")
echo("Guild: " .. guild .. " | Current Circle: " .. circle)
echo("Next Circle: " .. (circle + 1))
echo("")

-- Display skill ranks
local categories = {"Survival", "Lore", "Magic", "Weapon", "Armor"}
for _, cat in ipairs(categories) do
    local header_shown = false
    for _, skill in ipairs(skills) do
        if skill.type == cat then
            local rank = DRSkill.getrank(skill.name) or 0
            local xp = DRSkill.getxp(skill.name) or 0
            if not brief or rank > 0 then
                if not header_shown then
                    echo("--- " .. cat .. " ---")
                    header_shown = true
                end
                local name_pad = skill.name
                while #name_pad < 20 do name_pad = name_pad .. " " end
                echo("  " .. name_pad .. " Rank: " .. rank .. "  XP: " .. xp .. "/34")
            end
        end
    end
end

echo("")
echo("Note: Full circle requirement calculations require guild-specific data.")
echo("Use ;circlemonitor for continuous monitoring.")
