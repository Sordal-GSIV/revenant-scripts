--- @revenant-script
--- name: expreset
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Reset experience window to show all skills.
--- tags: experience, UI, display
--- Converted from expreset.lic

local skills = {
    "Shield Usage", "Light Armor", "Chain Armor", "Brigandine", "Plate Armor",
    "Defending", "Parry Ability", "Small Edged", "Large Edged", "Twohanded Edged",
    "Small Blunt", "Large Blunt", "Twohanded Blunt", "Slings", "Bow", "Crossbow",
    "Staves", "Polearms", "Light Thrown", "Heavy Thrown", "Brawling", "Offhand Weapon",
    "Melee Mastery", "Missile Mastery", "Expertise", "Holy Magic", "Lunar Magic",
    "Life Magic", "Elemental Magic", "Arcane Magic", "Summoning", "Astrology",
    "Inner Magic", "Inner Fire", "Attunement", "Arcana", "Targeted Magic",
    "Augmentation", "Debilitation", "Utility", "Warding", "Sorcery", "Evasion",
    "Athletics", "Perception", "Stealth", "Locksmithing", "Thievery", "First Aid",
    "Outdoorsmanship", "Skinning", "Scouting", "Backstab", "Thanatology", "Forging",
    "Engineering", "Outfitting", "Alchemy", "Enchanting", "Scholarship",
    "Mechanical Lore", "Appraisal", "Performance", "Theurgy", "Tactics",
    "Empathy", "Trading",
}

_respond("<streamWindow id='experience' title='Field Experience' location='center' target='drop' ifClosed='' resident='true'/>")
_respond("<clearStream id='experience'/>")
_respond("<pushStream id='experience'/><output class='mono'/>")
for _, skill in ipairs(skills) do
    _respond("<compDef id='exp " .. skill .. "'></compDef>")
end
_respond("<compDef id='exp mindstate'></compDef>")
_respond("<output class=''/><popStream id='experience'/>")
echo("Experience window reset.")
