--- @revenant-script
--- name: generate_gemstone
--- version: 10
--- author: Dreaven
--- game: dr
--- description: Random gemstone property generator - simulates gemstone drops with rarity tiers
--- tags: gemstone, random, fun, simulator
---
--- Note: This script uses GTK3 GUI which requires Revenant GUI support.
--- This is a text-mode fallback version.

local COMMON = {"Arcane Intensity","Binding Shot","Blood Artist","Blood Prism","Bold Brawler","Burning Blood","Channeler's Edge","Consummate Professional","Cutting Corners","Dispulsion Ward","Elemental Resonance","Flare Resonance","Force of Will","Green Thumb","High Tolerance","Immobility Veil","Mana Prism","Metamorphic Shield","Mystic Magnification","Opportunistic Sadism","Slayer's Fortitude","Spirit Prism","Stamina Prism","Storm of Rage","Subtle Ward","Tactical Canny","Taste of Brutality","Twist the Knife","Web Veil"}

local RARE = {"Adaptive Resistance","Advanced Spell Shielding","Arcane Opus","Blood Boil","Blood Siphon","Blood Wellspring","Chameleon Shroud","Channeler's Epiphany","Defensive Duelist","Grace of the Battlecaster","Greater Arcane Intensity","Hunter's Afterimage","Innate Focus","Lost Arcanum","Mana Wellspring","Martial Impulse","Master Tactician","Relentless","Ripe Melon","Rock Hound","Spirit Wellspring","Stamina Wellspring","Strong Back","Sureshot","Terror's Tribute","Thirst for Brutality"}

local LEGENDARY = {"Arcane Aegis","Arcanist's Ascendancy","Arcanist's Blade","Arcanist's Will","Charged Presence","Chronomage Collusion","Forbidden Arcanum","Imaera's Balm","Mana Shield","Mirror Image","Mystic Impulse","One Shot One Kill","Pixie's Mischief","Reckless Precision","Spellblade's Fury","Stolen Power","Trueshot","Unearthly Chains","Witchhunter's Ascendancy"}

local total = 0

local function generate()
    total = total + 1
    local roll = math.random(100)
    local rarity, props

    if roll <= 2 then
        rarity = "LEGENDARY"
        props = {COMMON[math.random(#COMMON)], RARE[math.random(#RARE)], LEGENDARY[math.random(#LEGENDARY)]}
    elseif roll <= 7 then
        rarity = "RARE"
        props = {COMMON[math.random(#COMMON)], RARE[math.random(#RARE)]}
    elseif roll <= 12 then
        rarity = "DOUBLE COMMON"
        local p1 = COMMON[math.random(#COMMON)]
        local p2 = COMMON[math.random(#COMMON)]
        while p2 == p1 do p2 = COMMON[math.random(#COMMON)] end
        props = {p1, p2}
    else
        rarity = "COMMON"
        props = {COMMON[math.random(#COMMON)]}
    end

    respond("")
    respond("=== " .. rarity .. " GEMSTONE (#" .. total .. ") ===")
    for _, p in ipairs(props) do respond("  " .. p) end
    respond("")
end

if script.vars[1] == "help" then
    respond("generate_gemstone - Random gemstone property simulator")
    respond("Run it to generate a random gemstone with properties.")
    exit()
end

generate()
echo("Generated " .. total .. " gemstone(s). Run again for more!")
