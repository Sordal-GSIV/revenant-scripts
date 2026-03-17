--- DR definitions and constants.
-- Ported from Lich5 drvariables.rb / drdefs.rb
-- @module lib.dr.defs
local M = {}

--- Learning rate names indexed 0-19 (used as mindstate thresholds).
-- In DR, experience is displayed as a "learning rate" that indicates
-- how quickly you are absorbing knowledge in a skill.
M.LEARNING_RATES = {
  [0]  = "clear",
  [1]  = "dabbling",
  [2]  = "perusing",
  [3]  = "learning",
  [4]  = "thoughtful",
  [5]  = "thinking",
  [6]  = "considering",
  [7]  = "pondering",
  [8]  = "ruminating",
  [9]  = "concentrating",
  [10] = "attentive",
  [11] = "deliberating",
  [12] = "investigating",
  [13] = "rapt",
  [14] = "engaged",
  [15] = "cogitating",
  [16] = "absorbed",
  [17] = "riveted",
  [18] = "contemplating",
  [19] = "mind lock",
}

--- Guild native mana types.
-- Barbarians and Thieves have no mana type (nil).
M.GUILD_MANA_TYPES = {
  ["Necromancer"]  = "arcane",
  ["Moon Mage"]    = "lunar",
  ["Trader"]       = "lunar",
  ["Warrior Mage"] = "elemental",
  ["Bard"]         = "elemental",
  ["Cleric"]       = "holy",
  ["Paladin"]      = "holy",
  ["Empath"]       = "life",
  ["Ranger"]       = "life",
  -- Barbarian and Thief intentionally omitted (nil)
}

--- Skill categories with all skill names per category.
M.SKILL_CATEGORIES = {
  armor = {
    "Shield Usage",
    "Light Armor",
    "Chain Armor",
    "Brigandine",
    "Plate Armor",
    "Defending",
    "Conviction",
  },
  weapon = {
    "Parry Ability",
    "Small Edged",
    "Large Edged",
    "Twohanded Edged",
    "Small Blunt",
    "Large Blunt",
    "Twohanded Blunt",
    "Slings",
    "Bow",
    "Crossbow",
    "Staves",
    "Polearms",
    "Light Thrown",
    "Heavy Thrown",
    "Brawling",
    "Offhand Weapon",
    "Melee Mastery",
    "Missile Mastery",
    "Expertise",
  },
  magic = {
    "Primary Magic",
    "Arcana",
    "Attunement",
    "Augmentation",
    "Debilitation",
    "Targeted Magic",
    "Utility",
    "Warding",
    "Sorcery",
    "Astrology",
    "Summoning",
    "Theurgy",
    "Inner Magic",
    "Inner Fire",
    "Lunar Magic",
    "Elemental Magic",
    "Holy Magic",
    "Life Magic",
    "Arcane Magic",
  },
  survival = {
    "Evasion",
    "Athletics",
    "Perception",
    "Stealth",
    "Locksmithing",
    "Thievery",
    "First Aid",
    "Outdoorsmanship",
    "Skinning",
    "Instinct",
    "Backstab",
    "Thanatology",
  },
  lore = {
    "Alchemy",
    "Appraisal",
    "Enchanting",
    "Engineering",
    "Forging",
    "Outfitting",
    "Performance",
    "Scholarship",
    "Tactics",
    "Empathy",
    "Bardic Lore",
    "Trading",
    "Mechanical Lore",
  },
}

--- Guild-specific skill aliases (e.g. "Primary Magic" -> "Inner Fire" for Barbarians).
M.GUILD_SKILL_ALIASES = {
  ["Cleric"]       = { ["Primary Magic"] = "Holy Magic" },
  ["Necromancer"]  = { ["Primary Magic"] = "Arcane Magic" },
  ["Warrior Mage"] = { ["Primary Magic"] = "Elemental Magic" },
  ["Thief"]        = { ["Primary Magic"] = "Inner Magic" },
  ["Barbarian"]    = { ["Primary Magic"] = "Inner Fire" },
  ["Ranger"]       = { ["Primary Magic"] = "Life Magic" },
  ["Bard"]         = { ["Primary Magic"] = "Elemental Magic" },
  ["Paladin"]      = { ["Primary Magic"] = "Holy Magic" },
  ["Empath"]       = { ["Primary Magic"] = "Life Magic" },
  ["Trader"]       = { ["Primary Magic"] = "Lunar Magic" },
  ["Moon Mage"]    = { ["Primary Magic"] = "Lunar Magic" },
}

--- Encumbrance text values indexed 0-11.
M.ENCUMBRANCE = {
  [0]  = "None",
  [1]  = "Light Burden",
  [2]  = "Somewhat Burdened",
  [3]  = "Burdened",
  [4]  = "Heavy Burden",
  [5]  = "Very Heavy Burden",
  [6]  = "Overburdened",
  [7]  = "Very Overburdened",
  [8]  = "Extremely Overburdened",
  [9]  = "Tottering Under Burden",
  [10] = "Are you even able to move?",
  [11] = "It's amazing you aren't squashed!",
}

--- Balance scale (12 levels, 0=completely off to 11=incredibly balanced).
M.BALANCE = {
  [0]  = "completely",
  [1]  = "hopelessly",
  [2]  = "extremely",
  [3]  = "very badly",
  [4]  = "badly",
  [5]  = "somewhat off",
  [6]  = "off",
  [7]  = "slightly off",
  [8]  = "solidly",
  [9]  = "nimbly",
  [10] = "adeptly",
  [11] = "incredibly",
}

--- Unknown spell duration sentinel value.
M.UNKNOWN_DURATION = 1000

return M
