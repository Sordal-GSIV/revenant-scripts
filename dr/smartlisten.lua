--- @revenant-script
--- name: smartlisten
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-listen when someone teaches an approved skill.
--- tags: teaching, listening, training
--- Converted from smartlisten.lic

local defaults = {
    "Large Edged", "Twohanded Edged", "Small Blunt", "Light Thrown", "Brawling",
    "Offhand Weapon", "Melee Mastery", "Missile Mastery", "Life Magic", "Attunement",
    "Arcana", "Augmentation", "Utility", "Warding", "Athletics", "Perception",
    "First Aid", "Outdoorsmanship", "Scholarship", "Mechanical Lore", "Appraisal",
    "Performance", "Tactics", "Stealth", "Bow", "Evasion", "Parry Ability",
    "Small Edged", "Defending", "Light Armor", "Chain Armor", "Shield Usage",
    "Targeted Magic", "Debilitation", "Brigandine", "Plate Armor", "Large Blunt",
    "Twohanded Blunt", "Slings", "Crossbow", "Staves", "Polearms", "Heavy Thrown",
    "Locksmithing", "Skinning", "Forging", "Engineering", "Outfitting", "Alchemy",
}
local skills_set = {}
for _, s in ipairs(defaults) do skills_set[s] = true end

while true do
    local line = get()
    if line then
        local teacher, skill = line:match("(.-) begins to lecture you on the proper usage of the (.-) skill")
        if teacher and skill and skills_set[skill] then
            DRC.bput("listen to " .. teacher, "You begin to listen")
        end
    end
end
