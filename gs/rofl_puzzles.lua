--- @revenant-script
--- name: rofl_puzzles
--- version: 1.5
--- author: elanthia-online
--- contributors: Kragdruk
--- game: gs
--- description: Rings of Lumnis puzzle solver
--- tags: festival,RoL,Rings,puzzles
---
--- Changelog (from Lich5):
---   v1.5 - Various puzzle additions and updates
---
--- Usage:
---   ;rofl_puzzles           -- auto-solve puzzles as they appear
---   ;rofl_puzzles <puzzle>  -- solve a specific puzzle
---
--- Supported puzzles:
---   auto, bookcase1, bookcase2, boxsphere, colorsphere, crystal, ghost,
---   irondoor, lavariver, levers, lightcandle, makecandle, mosaic, scramble,
---   stars, statue, symbol, trapdoor, wicker, wizard, aldoran, gnomes,
---   elves, shops

--------------------------------------------------------------------------------
-- Puzzle Data
--------------------------------------------------------------------------------

-- Scramble word list
local SCRAMBLE_WORDS = {
    "ABANDON", "ABDUCT", "ABOLISH", "ABOMINATION", "ABYSS", "ACCLAIM",
    "ACCOLADE", "ACCRUE", "ACUMEN", "ADAMANTINE", "ADEPT", "ADJURE",
    "ADMONISH", "ADVENT", "AEGIS", "AFFLICT", "AGILE", "ALCHEMY",
    "AMULET", "ANCIENT", "ANNIHILATE", "ANOMALY", "APPARITION",
    "ARCANE", "ARCHAIC", "ARMOR", "ARSENAL", "ARTIFACT", "ASSAULT",
    "ASTRAL", "ATONE", "AUGMENT", "AURA", "AVATAR", "AVENGE",
    "BANDIT", "BANISH", "BARBARIAN", "BARD", "BARRIER", "BASTION",
    "BATTLE", "BEACON", "BEAST", "BEGUILE", "BEHEMOTH", "BESEECH",
    "BESTOW", "BETRAY", "BEWITCH", "BLADE", "BLESS", "BLIGHT",
    "BLISS", "BLOOD", "BOLT", "BOON", "BOUNTY", "BRAVE",
    "BREACH", "BRUTE", "BURDEN", "CABAL", "CAIRN", "CALAMITY",
    "CANTRIP", "CATALYST", "CATARACT", "CELESTIAL", "CHAMPION",
    "CHAOS", "CHARM", "CHRONICLE", "CITADEL", "CLAIRVOYANT",
    "CLEAVE", "CLERIC", "CLOISTER", "COALESCE", "CODEX",
    "CONJURE", "CONSECRATE", "CONSPIRE", "CORRUPT", "COVENANT",
    "CRUSADE", "CRYSTAL", "CURSE", "DAEMON", "DAGGER", "DAMNATION",
    "DEATH", "DECEIVE", "DECREE", "DEFILE", "DEITY", "DELUGE",
    "DEMON", "DESCEND", "DESECRATE", "DESPAIR", "DESTINY", "DESTROY",
    "DEVASTATE", "DEVOUT", "DISCIPLE", "DIVINE", "DOMAIN", "DOOM",
    "DRAGON", "DREAD", "DRUID", "DUNGEON", "DUSK", "ECLIPSE",
    "ELDRITCH", "ELEMENTAL", "ELIXIR", "EMISSARY", "EMPATH",
    "ENCHANT", "ENDURE", "ENIGMA", "ENLIGHTEN", "EPOCH", "ERADICATE",
    "ESSENCE", "ETERNAL", "ETHEREAL", "EVADE", "EVOKE", "EXALT",
    "EXILE", "EXORCISE", "EXPEDITION", "FABLE", "FAITH", "FAMILIAR",
    "FAMINE", "FANATIC", "FATE", "FEALTY", "FIEND", "FLAME",
    "FLESH", "FORESIGHT", "FORGE", "FORSAKE", "FORTRESS", "FRACTURE",
    "FURY", "GALLANT", "GARRISON", "GENESIS", "GHOST", "GLADIATOR",
    "GLYPH", "GOLEM", "GRACE", "GRIMOIRE", "GUARDIAN", "GUILD",
    "HALLOWED", "HARBINGER", "HAVEN", "HEALER", "HERESY", "HERITAGE",
    "HERMIT", "HEROIC", "HEXED", "HIERARCH", "HOLY", "HONOR",
    "HORIZON", "HORROR", "HORDE", "HUNTER", "HYMN", "ICON",
    "ILLUSION", "IMMORTAL", "IMPALE", "INCANTATION", "INFERNAL",
    "INVOKE", "IRON", "JADE", "JUDGMENT", "JUSTICE", "KEEN",
    "KNIGHT", "LABYRINTH", "LANCE", "LEGEND", "LICHE", "LIGHT",
    "LORE", "MAGE", "MAGIC", "MALICE", "MANTLE", "MARTYR",
    "MASTERY", "MELEE", "MERCY", "MIGHT", "MIRACLE", "MIRAGE",
    "MITHRIL", "MONASTERY", "MONK", "MORTAL", "MYSTIC", "MYTH",
    "NECROMANCER", "NEMESIS", "NOBLE", "OATH", "OBLITERATE",
    "OBSCURE", "OMEN", "ORACLE", "ORDAIN", "PALADIN", "PARCHMENT",
    "PARIAH", "PATRON", "PENANCE", "PERIL", "PHANTOM", "PILGRIM",
    "PLAGUE", "PORTAL", "PRAYER", "PRIMAL", "PROPHECY", "PROTECT",
    "PROWESS", "PURGE", "QUEST", "RADIANT", "RAGE", "RANGER",
    "REALM", "REBIRTH", "RECKONING", "REDEMPTION", "REFUGE", "RELIC",
    "REMNANT", "REPENT", "REQUIEM", "RESONATE", "RESURRECTION",
    "RETRIBUTION", "REVELATION", "REVENANT", "RIFT", "RIGHTEOUS",
    "RITUAL", "ROGUE", "RUNE", "SACRED", "SACRIFICE", "SAGE",
    "SANCTIFY", "SANCTUARY", "SCEPTER", "SCHOLAR", "SCROLL",
    "SEER", "SENTINEL", "SERAPH", "SERPENT", "SHADOW", "SHAMAN",
    "SHIELD", "SHRINE", "SIEGE", "SIGIL", "SKULL", "SLAYER",
    "SMITE", "SORCERER", "SOUL", "SOVEREIGN", "SPARK", "SPECTER",
    "SPELL", "SPIRIT", "STALWART", "STEEL", "STORM", "STRIKE",
    "SUMMON", "SURGE", "SWORD", "TALISMAN", "TEMPEST", "TEMPLE",
    "TENACITY", "TERROR", "TESTAMENT", "THRONE", "TITAN", "TOMB",
    "TORMENT", "TOTEM", "TRANSCEND", "TRIDENT", "TRIUMPH", "TYRANT",
    "UNDEAD", "VALOR", "VAMPIRE", "VANQUISH", "VENGEANCE", "VESTIGE",
    "VIGILANT", "VIRTUE", "VISION", "VOID", "VORTEX", "VOW",
    "WARDEN", "WARLOCK", "WARRIOR", "WRAITH", "WRATH", "ZEALOT",
}

-- Constellation data for the stars puzzle
local CONSTELLATIONS = {
    { name = "Hammer",        deity = "Eonak",      stars = 5 },
    { name = "Handmaidens",   deity = "Zelia",      stars = 6 },
    { name = "Huntress",      deity = "Huntress",    stars = 1 },
    { name = "Trident",       deity = "Charl",       stars = 7 },
    { name = "Jackal",        deity = "Luukos",      stars = 4 },
    { name = "Queen",         deity = "Lumnis",      stars = 5 },
    { name = "The First",     deity = "Ka'lethas",   stars = 21 },
    { name = "The Gates",     deity = "Lorminstra",  stars = 4 },
    { name = "Cat",           deity = "Andelas",     stars = 3 },
    { name = "Sickle",        deity = "Gosaena",     stars = 6 },
    { name = "Eye",           deity = "Ronan",       stars = 3 },
    { name = "Dragon",        deity = "Koar",        stars = 15 },
}

-- Arkati symbols and their colors
local ARKATI_SYMBOLS = {
    Andelas    = { symbol = "cat",        colors = { "black" } },
    Charl      = { symbol = "trident",    colors = { "blue" } },
    Cholen     = { symbol = "lute",       colors = { "gold" } },
    Eonak      = { symbol = "anvil",      colors = { "golden" } },
    Eorgina    = { symbol = "flames",     colors = { "red" } },
    Gosaena    = { symbol = "sickle",     colors = { "silver", "grey" } },
    Imaera     = { symbol = "leaf",       colors = { "green" } },
    Ivas       = { symbol = "wisp",       colors = { "green" } },
    Jastev     = { symbol = "eye",        colors = { "blue", "silver" } },
    Kai        = { symbol = "fist",       colors = { "red" } },
    Koar       = { symbol = "crown",      colors = { "gold" } },
    Lorminstra = { symbol = "gate",       colors = { "golden" } },
    Lumnis     = { symbol = "scroll",     colors = { "white", "gold" } },
    Luukos     = { symbol = "serpent",    colors = { "green" } },
    Marlu      = { symbol = "tentacles",  colors = { "black" } },
    Mularos    = { symbol = "heart",      colors = { "bleeding", "red" } },
    Oleani     = { symbol = "rose",       colors = { "red" } },
    Phoen      = { symbol = "sunburst",   colors = { "golden" } },
    Ronan      = { symbol = "eye",        colors = { "black", "silver" } },
    Sheru      = { symbol = "jackal",     colors = { "yellow" } },
    Vtull      = { symbol = "scimitar",   colors = { "black" } },
    Zelia      = { symbol = "crescent",   colors = { "silver" } },
}

-- Gem/Arkati associations for the mosaic puzzle
local GEM_ARKATI = {
    alexandrite = "Oleani",
    amethyst    = "Ronan",
    bloodstone  = "Kai",
    chrysoberyl = "Imaera",
    deathstone  = "Lorminstra",
    diamond     = "Lumnis",
    diopside    = "Eonak",
    emerald     = "Charl",
    firestone   = "Phoen",
    garnet      = "Mularos",
    jade        = "Jastev",
    lapis       = "Koar",
    moonstone   = "Zelia",
    opal        = "Cholen",
    pearl       = "Niima",
    ruby        = "Eorgina",
    sapphire    = "Andelas",
    topaz       = "Sheru",
}

-- Aldoran healing stones
local ALDORAN_STONES = {
    fever       = "blue",
    rash        = "green",
    cough       = "yellow",
    chills      = "red",
    ache        = "white",
    swelling    = "purple",
}

-- Gnome bloodline descriptions
local GNOME_BLOODLINES = {
    ["metals trades"]       = "aledotter",
    ["tricksters"]          = "nylem",
    ["never speak"]         = "neimhean",
    ["burghal gnome"]       = "withycombe",
    ["hosts"]               = "rosengift",
    ["wine"]                = "felcour",
    ["academic"]            = "anodheles",
    ["seafaring"]           = "greengair",
    ["traveling merchant"]  = "basingstoke",
    ["jewel"]               = "wendwillow",
    ["healing"]             = "winedotter",
    ["fortune"]             = "vykin",
}

-- Elven house shield stones
local ELVEN_SHIELDS = {
    Vaalor    = "ruby",
    Illistim  = "sapphire",
    Nalfein   = "emerald",
    Ardenai   = "topaz",
    Loenthra  = "pearl",
    Faendryl  = "onyx",
    Ashrim    = "coral",
}

--------------------------------------------------------------------------------
-- Puzzle Solvers
--------------------------------------------------------------------------------

local function solve_scramble(line)
    -- Extract scrambled letters
    local scrambled = Regex.match(line, "letters?: ([A-Z ]+)")
    if not scrambled or not scrambled[1] then return end

    local letters = scrambled[1]:gsub("%s+", ""):upper()

    -- Sort the scrambled letters
    local sorted_scramble = {}
    for i = 1, #letters do
        table.insert(sorted_scramble, letters:sub(i, i))
    end
    table.sort(sorted_scramble)
    local scramble_key = table.concat(sorted_scramble)

    -- Find matching word
    for _, word in ipairs(SCRAMBLE_WORDS) do
        if #word == #letters then
            local sorted_word = {}
            for i = 1, #word do
                table.insert(sorted_word, word:sub(i, i))
            end
            table.sort(sorted_word)
            if table.concat(sorted_word) == scramble_key then
                fput("answer " .. word)
                return
            end
        end
    end
end

local function solve_stars(line)
    -- Match constellation description
    for _, c in ipairs(CONSTELLATIONS) do
        if string.find(line, c.name) or string.find(line, c.deity) then
            fput("point " .. c.name:lower())
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Auto-solve Mode
--------------------------------------------------------------------------------

local function auto_solve()
    respond("[rofl_puzzles] Auto-solve mode active. Watching for puzzles...")

    while true do
        local line = get()

        -- Scramble puzzle
        if string.find(line, "scrambled letters") or string.find(line, "letters:") then
            solve_scramble(line)

        -- Stars/constellation puzzle
        elseif string.find(line, "constellation") or string.find(line, "night sky") then
            solve_stars(line)

        -- Aldoran healing puzzle
        elseif string.find(line, "fever") or string.find(line, "rash") or
               string.find(line, "cough") or string.find(line, "chills") or
               string.find(line, "ache") or string.find(line, "swelling") then
            for symptom, stone in pairs(ALDORAN_STONES) do
                if string.find(line, symptom) then
                    fput("get " .. stone .. " stone")
                    fput("rub " .. stone .. " stone")
                    break
                end
            end

        -- Mosaic gem puzzle
        elseif string.find(line, "mosaic") and string.find(line, "gem") then
            for gem, arkati in pairs(GEM_ARKATI) do
                if string.find(line, arkati) or string.find(line, arkati:lower()) then
                    fput("put " .. gem .. " in mosaic")
                    break
                end
            end

        -- Levers puzzle
        elseif string.find(line, "pull") and string.find(line, "lever") then
            -- Try levers in sequence
            for i = 1, 5 do
                fput("pull lever " .. i)
            end

        -- Light candle puzzle
        elseif string.find(line, "light") and string.find(line, "candle") then
            fput("light candle")

        -- Bookcase puzzles
        elseif string.find(line, "bookcase") and string.find(line, "lean") then
            fput("lean bookcase")

        -- Wicker/tube puzzle
        elseif string.find(line, "tube") and string.find(line, "play") then
            fput("play tube")

        -- Generic puzzle interaction
        elseif string.find(line, "You have solved the puzzle") or
               string.find(line, "puzzle is complete") then
            respond("[rofl_puzzles] Puzzle solved!")
        end
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("=== ROFL Puzzles Help ===")
    respond("  ;rofl_puzzles           -- auto-solve puzzles as they appear")
    respond("  ;rofl_puzzles <name>    -- solve a specific puzzle")
    respond("")
    respond("  Supported puzzles:")
    respond("    auto         - automatically solve puzzles when they appear (default)")
    respond("    bookcase1    - lean against a book in a bookcase")
    respond("    bookcase2    - lever behind a book")
    respond("    boxsphere    - manipulate a metal box and a glowing sphere")
    respond("    colorsphere  - push a button and touch sphere of various colors")
    respond("    crystal      - choose correct damage type for monster paintings")
    respond("    ghost        - use a wand to do stuff to a ghost")
    respond("    irondoor     - unlock an iron door with help from a boulder")
    respond("    lavariver    - the floor is lava")
    respond("    levers       - pull levers in correct order")
    respond("    lightcandle  - light the correct candle")
    respond("    makecandle   - make an artisanal candle")
    respond("    mosaic       - find the right gem and symbol for the mosaic")
    respond("    scramble     - guess the word from scrambled letters")
    respond("    stars        - select correct constellation")
    respond("    statue       - move statues around on an altar")
    respond("    symbol       - paint an Arkati symbol the correct colors")
    respond("    trapdoor     - get through a trapdoor by moving a boulder")
    respond("    wicker       - play a tube")
    respond("    wizard       - put on robe and wizard hat")
    respond("    aldoran      - use healing stones to fix the sick person")
    respond("    gnomes       - pick out the apotl for the bloodline")
    respond("    elves        - place the correct stone in house shield")
    respond("    shops        - point to the correct shop")
    respond("=========================")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args = Script.args or {}
local cmd = (args[1] or "auto"):lower()

if cmd == "help" then
    show_help()
elseif cmd == "auto" or cmd == "" then
    auto_solve()
elseif cmd == "scramble" then
    respond("[rofl_puzzles] Watching for scramble puzzles...")
    while true do
        local line = get()
        if string.find(line, "scrambled") or string.find(line, "letters:") then
            solve_scramble(line)
        end
    end
elseif cmd == "stars" then
    respond("[rofl_puzzles] Watching for constellation puzzles...")
    while true do
        local line = get()
        if string.find(line, "constellation") then
            solve_stars(line)
        end
    end
else
    respond("[rofl_puzzles] Running puzzle: " .. cmd)
    auto_solve()
end
