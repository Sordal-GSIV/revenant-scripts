--- Ascension gemstone system constants
-- Critter list, property lists, rarity data

local M = {}

-- Ascension critters that count toward gemstone pity counter
M.ascension_critters = {
    "armored battle mastodon",
    "black valravn",
    "boreal undansormr",
    "crimson angargeist",
    "fork-tongued wendigo",
    "giant warg",
    "gigas berserker",
    "gigas disciple",
    "gigas shield-maiden",
    "gigas skald",
    "gold-bristled hinterboar",
    "gorefrost golem",
    "halfling bloodspeaker",
    "halfling cannibal",
    "reptilian mutant",
    "sanguine ooze",
    "shadow-cloaked draugr",
    "winged disir",
    "basalt grotesque",
    "death knight",
    "mist-wreathed banshee",
    "patrician vampire",
    "phantasmic conjurer",
    "skeletal dreadsteed",
    "tatterdemalion ghast",
    "hive thrall",
    "kiramon broodtender",
    "kiramon myrmidon",
    "kiramon stalker",
    "kiramon strandweaver",
    "kresh ravager",
}

-- Build a lookup set for fast matching
M.ascension_set = {}
for _, name in ipairs(M.ascension_critters) do
    M.ascension_set[name] = true
end

-- Regex pattern for matching any ascension critter in text
M.ascension_pattern = table.concat(M.ascension_critters, "|")

-- Full display names (with descriptors) for the critter dropdown
M.critter_display_names = {
    "horned basalt grotesque",
    "infernal death knight",
    "smouldering skeletal dreadsteed",
    "gaudy phantasmic conjurer",
    "flickering mist-wreathed banshee",
    "ashen patrician vampire",
    "cadaverous tatterdemalion ghast",
    "bloody halfling cannibal",
    "immense gold-bristled hinterboar",
    "stunted halfling bloodspeaker",
    "behemothic gorefrost golem",
    "savage fork-tongued wendigo",
    "heavily armored battle mastodon",
    "tattooed gigas berserker",
    "niveous giant warg",
    "grim gigas skald",
    "brawny gigas shield-maiden",
    "quivering sanguine ooze",
    "flayed gigas disciple",
    "colossal boreal undansormr",
    "withered shadow-cloaked draugr",
    "shining winged disir",
    "squamous reptilian mutant",
    "eyeless black valravn",
    "roiling crimson angargeist",
    "chitinous kiramon myrmidon",
    "disfigured hive thrall",
    "corpulent kresh ravager",
    "sleek black kiramon stalker",
    "translucent kiramon strandweaver",
    "bloated kiramon broodtender",
}

-- Gemstone properties by rarity tier
M.common_properties = {
    "Arcane Intensity", "Binding Shot", "Blood Artist", "Blood Prism",
    "Boatswain's Savvy", "Bold Brawler", "Burning Blood", "Cannoneer's Savvy",
    "Channeler's Edge", "Consummate Professional", "Cutting Corners",
    "Dispulsion Ward", "Elemental Resonance", "Elementalist's Gift",
    "Ephemera's Extension", "Ether Flux", "Flare Resonance", "Force of Will",
    "Geomancer's Spite", "Grand Theft Kobold", "Green Thumb", "High Tolerance",
    "Immobility Veil", "Journeyman Defender", "Journeyman Tactician",
    "Limit Break: Blunt Weapons", "Limit Break: Brawling",
    "Limit Break: Edged Weapons", "Limit Break: Pole Arm Weapons",
    "Limit Break: Ranged Weapons", "Limit Break: Spell Aiming",
    "Limit Break: Thrown Weapons", "Limit Break: Two-Handed Weapons",
    "Limit Break: Agility", "Limit Break: Aura", "Limit Break: Constitution",
    "Limit Break: Dexterity", "Limit Break: Discipline", "Limit Break: Influence",
    "Limit Break: Intuition", "Limit Break: Logic", "Limit Break: Strength",
    "Limit Break: Wisdom", "Mana Prism", "Metamorphic Shield", "Mephitic Brume",
    "Mystic Magnification", "Navigator's Savvy", "Opportunistic Sadism",
    "Root Veil", "Slayer's Fortitude", "Spirit Prism", "Stamina Prism",
    "Storm of Rage", "Subtle Ward", "Tactical Canny", "Taste of Brutality",
    "Twist the Knife", "Web Veil",
}

M.regional_properties = {
    "Grimswarm: Shroud Soother",
    "Hinterwilds: Indigestible",
    "Hinterwilds: Light of the Disir",
    "Hinterwilds: Warden of the Damned",
    "Moonsedge: Gift of Enlightement",
    "Moonsedge: Organ Enthusiast",
    "Temple Nelemar: Breath of the Nymph",
    "Temple Nelemar: Perfect Conduction",
    "Temple Nelemar: Trident of the Sunderer",
    "The Hinterwilds: Gift of Enlightement",
    "The Hive: Arrhythmic Gait",
    "The Hive: Astral Spark",
    "The Hive: Gift of Enlightement",
    "The Rift: Gift of the God-King",
}

M.rare_properties = {
    "Adaptive Resistance", "Advanced Spell Shielding", "Anointed Defender",
    "Arcane Opus", "Bandit Bait", "Blood Boil", "Blood Siphon",
    "Blood Wellspring", "Chameleon Shroud", "Channeler's Epiphany",
    "Defensive Duelist", "Evanescent Possession", "Grace of the Battlecaster",
    "Greater Arcane Intensity", "Hunter's Afterimage", "Infusion of Acid",
    "Infusion of Cold", "Infusion of Disintegration", "Infusion of Disruption",
    "Infusion of Heat", "Infusion of Lightning", "Infusion of Plasma",
    "Infusion of Steam", "Infusion of Vacuum", "Innate Focus", "Lost Arcanum",
    "Mana Wellspring", "Martial Impulse", "Master Tactician", "Relentless",
    "Relentless Warder", "Ripe Melon", "Rock Hound", "Serendipitous Hex",
    "Spirit Wellspring", "Stamina Wellspring", "Strong Back", "Sureshot",
    "Terror's Tribute", "Tethered Strike", "Thirst for Brutality",
}

M.legendary_properties = {
    "Arcane Aegis", "Arcanist's Ascendancy", "Arcanist's Blade",
    "Arcanist's Will", "Charged Presence", "Chronomage Collusion",
    "Forbidden Arcanum", "Imaera's Balm", "Mana Shield", "Mirror Image",
    "Mystic Impulse", "One Shot, One Kill", "Pixie's Mischief",
    "Reckless Precision", "Spellblade's Fury", "Stolen Power",
    "Thorns of Acid", "Thorns of Cold", "Thorns of Disintegration",
    "Thorns of Disruption", "Thorns of Heat", "Thorns of Lightning",
    "Thorns of Plasma", "Thorns of Steam", "Thorns of Vacuum",
    "Trueshot", "Unearthly Chains", "Witchhunter's Ascendancy",
}

M.rarity_names = { "Common", "Regional", "Rare", "Legendary" }

-- Base find rate (pity denominator for first gem)
M.FIND_RATE = 1500
-- Upper rate for 2nd/3rd gemstone (cumulative 90% by this many loots)
M.UPPER_RATE_SECOND_THIRD = 3500

return M
