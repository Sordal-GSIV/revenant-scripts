--- @revenant-script
--- name: rofl_puzzles
--- version: 1.5
--- author: elanthia-online
--- contributors: Kragdruk
--- game: gs
--- description: Rings of Lumnis Puzzle Solver
--- tags: festival,RoL,Rings,puzzles
---
--- Changelog (from Lich5 rofl-puzzles.lic v1.5):
---   v1.5 - Converted to Revenant Lua; full implementation of all 27 puzzles:
---     statue, mosaic, crystal, stars, scramble, ghost, symbol, makecandle,
---     lightcandle, levers, irondoor, trapdoor, boxsphere, colorsphere,
---     bookcase1, bookcase2, lavariver, wizard, wicker, aldoran, gnomes,
---     elves, shops, cutouts, sheet, flowers, professions
---
--- Usage:
---   ;rofl_puzzles                  -- auto-solve puzzles when they appear
---   ;rofl_puzzles <puzzle name>    -- solve a specific puzzle
---
--- Thanks:
---   * Fyffil for solutions to the Planar puzzles
---   * Alastir for creating ;RoL (trivia) and solutions to many anagrams,
---     the ghost, box, and stars puzzles
---   * Cigger for gem anagram answers and testing
---   * Naamit for creature anagrams, arkati symbol tiles, and testing/feedback
---   * Maetriks for creature anagrams
---   * Claudaro for help testing and feedback
---   * Roblar for hints to puzzle solutions
---   * Hebrew2You for bribing to fix the mosaic puzzle
---   * Jahadeem for reporting the candle/NOMARKEDDROP issue
---   * Athias for Order and Elemental ring puzzle solutions
---   * Azanoth for Chaos ring puzzle solutions
---
--- @lic-certified: complete 2026-03-19

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function table_includes(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--- empty_hands: stow both hands
local function empty_hands()
    if righthand_p() then fput("stow right") end
    if lefthand_p() then fput("stow left") end
end

--- fill_hands: Lich5 tracked stowed items via global state; Revenant cannot.
local function fill_hands()
    -- no-op: cannot reconstruct what was stowed without global state
end

--- loot_has: check if any room loot matches noun or name
local function loot_has(requirement)
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.noun == requirement or obj.name == requirement then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- STATUE DATA (BFS pathfinding)
--------------------------------------------------------------------------------

local STATUE_KNOWN_POSITIONS = {
    "left-rear corner", "left-rear", "centered behind", "right-rear", "right-rear corner",
    "left",                            "middle",                         "right",
    "left-front corner", "left-front", "centered in front", "right-front", "right-front corner",
}

local STATUE_POSITION_MAP = {
    ["centered behind"]   = { middle = "pull", ["left-rear"] = "nudge", ["right-rear"] = "prod" },
    ["centered in front"] = { middle = "push", ["left-front"] = "nudge", ["right-front"] = "prod" },
    ["left"]              = { ["left-rear corner"] = "push", ["left-front corner"] = "pull", middle = "prod" },
    ["left-front"]        = { ["left-front corner"] = "nudge", ["centered in front"] = "prod" },
    ["left-front corner"] = { left = "push", ["left-front"] = "prod" },
    ["left-rear"]         = { ["left-rear corner"] = "nudge", ["centered behind"] = "prod" },
    ["left-rear corner"]  = { left = "pull", ["left-rear"] = "prod" },
    ["middle"]            = { left = "nudge", right = "prod", ["centered behind"] = "push", ["centered in front"] = "pull" },
    ["right"]             = { middle = "nudge", ["right-rear corner"] = "push", ["right-front corner"] = "pull" },
    ["right-front"]       = { ["centered in front"] = "nudge", ["right-front corner"] = "prod" },
    ["right-front corner"]= { ["right-front"] = "nudge", right = "push" },
    ["right-rear"]        = { ["centered behind"] = "nudge", ["right-rear corner"] = "prod" },
    ["right-rear corner"] = { ["right-rear"] = "nudge", right = "pull" },
}

local STATUE_DESCRIPTION_OF = {
    jackal  = { altar = "snarling and menacing jackal statue",          bowl = "jackal statue" },
    cobra   = { altar = "coiled and ready-to-strike cobra casting",     bowl = "cobra statue" },
    nymph   = { altar = "lithe shark-fanged nymph sculpture",           bowl = "nymph statue" },
    goddess = { altar = "flame-wreathed and sneering goddess effigy",   bowl = "goddess statue" },
}

local function statue_find_path(starting_pos, ending_pos)
    if not table_includes(STATUE_KNOWN_POSITIONS, starting_pos) then return nil end
    if not table_includes(STATUE_KNOWN_POSITIONS, ending_pos)   then return nil end

    local queue   = { starting_pos }
    local visited = {}
    local edge_to = {}

    while #queue > 0 do
        local cur = table.remove(queue, 1)
        if cur == ending_pos then
            -- Walk back to reconstruct path
            local path = {}
            while cur ~= starting_pos do
                local prev = edge_to[cur]
                local dir  = STATUE_POSITION_MAP[prev][cur]
                table.insert(path, 1, dir)
                cur = prev
            end
            return path
        end
        visited[cur] = true
        local neighbors = STATUE_POSITION_MAP[cur]
        if neighbors then
            for neighbor, _ in pairs(neighbors) do
                if not visited[neighbor] then
                    table.insert(queue, neighbor)
                    visited[neighbor] = true
                    edge_to[neighbor] = cur
                end
            end
        end
    end
    return nil
end

local function statue_parse_altar_position(statue, text)
    if text:find("are situated in the middle of the") then
        return "middle"
    end
    local altar_desc = STATUE_DESCRIPTION_OF[statue].altar
    local pattern    = "a " .. altar_desc
                       .. "(?: to the| in the)? (.+?) (?:of )?the (?:altar|worshipping space)"
    local caps = Regex.new(pattern):captures(text)
    if caps and caps[1] then return caps[1] end
    echo("ERROR: couldn't parse " .. statue .. " position on the altar")
    return nil
end

local function statue_parse_bowl_position(statue, text)
    local bowl_desc = STATUE_DESCRIPTION_OF[statue].bowl
    local pattern   = "a " .. bowl_desc
                      .. "(?: to the| in the)? (.+?) (?:of )?the altar"
    local caps = Regex.new(pattern):captures(text)
    if caps and caps[1] then return caps[1] end
    echo("ERROR: couldn't parse " .. statue .. " position in the bowl")
    return nil
end

--------------------------------------------------------------------------------
-- MOSAIC DATA
--------------------------------------------------------------------------------

local MOSAIC_GEM_INFO = {
    Aeia         = { gem = "emerald",           shape = "lily" },
    Amasalen     = { gem = "heliodor",          shape = "two-headed serpent" },
    Andelas      = { gem = "cat's eye quartz",  shape = "feline" },
    Arachne      = { gem = "garnet",            shape = "arachnid" },
    Charl        = { gem = "thunder egg geode", shape = "trident" },
    Cholen       = { gem = "amethyst",          shape = "lute" },
    Eorgina      = { gem = "black diamond",     shape = "flame" },
    ["Fash'lo'nae"] = { gem = "citrine quartz", shape = "slit-pupiled eye" },
    Gosaena      = { gem = "moss agate",        shape = "sickle" },
    Imaera       = { gem = "emerald",           shape = "doe" },
    Ivas         = { gem = "green jade",        shape = "stylized wisp of smoke" },
    Jastev       = { gem = "alexandrite",       shape = "crystal ball" },
    Jaston       = { gem = "blue quartz",       shape = "feather" },
    Kai          = { gem = "tigerfang crystal", shape = "clenched fist" },
    Koar         = { gem = "topaz",             shape = "crown" },
    Kuon         = { gem = "green zircon",      shape = "leaf" },
    Laethe       = { gem = "rhodochrosite",     shape = "lone rose" },
    Leya         = { gem = "chalcedony",        shape = "dagger" },
    Lorminstra   = { gem = "black dreamstone",  shape = "key" },
    Lumnis       = { gem = "turquoise",         shape = "five-ringed golden scroll" },
    Luukos       = { gem = "emerald",           shape = "serpent" },
    Marlu        = { gem = "star diopside",     shape = "six-tentacled star" },
    Mularos      = { gem = "bloodstone",        shape = "dagger-pierced heart" },
    Niima        = { gem = "white opal",        shape = "dolphin" },
    Oleani       = { gem = "morganite",         shape = "budding flower atop a heart" },
    Onar         = { gem = "obsidian",          shape = "broken skull" },
    Phoen        = { gem = "yellow sapphire",   shape = "sunburst" },
    Sheru        = { gem = "amber",             shape = "jackal" },
    Ronan        = { gem = "jet",               shape = "sword" },
    ["The Huntress"] = { gem = "starstone",     shape = "eight-pointed star" },
    Tilamaire    = { gem = "labradorite",       shape = "musical note" },
    Tonis        = { gem = "jasper",            shape = "pegasus" },
    Voaris       = { gem = "geode",             shape = "young rose" },
    Voln         = { gem = "onyx",             shape = "shield" },
    ["V'tull"]   = { gem = "bloodjewel",        shape = "scimitar" },
    Zelia        = { gem = "moonstone",         shape = "crescent moon" },
}

--------------------------------------------------------------------------------
-- CONSTELLATION DATA
--------------------------------------------------------------------------------

local CONSTELLATIONS = {
    Charlatos  = "The Spire",
    Eoantos    = "The Lady of the Green",
    Eorgaen    = "The Paladin",
    Fashanos   = "Arachne",
    Imaerasta  = "The Queen of Enlightenment",
    Ivastaen   = "The Mistress of Adoration",
    Jastatos   = "The Jackal",
    Koaratos   = "Jastev's Crystal",
    Lormesta   = "Grandfather's Eye",
    Lumnea     = "The Dragonfly",
    Olaesta    = "The Hammer",
    Phoenatos  = "The Sun God",
    Spring     = "The Mistress of Adoration",
    Summer     = "The Guardian",
    Fall       = "The Gryphon",
    Winter     = "The Ur-Daemon",
}

--------------------------------------------------------------------------------
-- SCRAMBLE DATA
--------------------------------------------------------------------------------

local SCRAMBLE_SOLUTIONS = {
    -- Spiritual (Arkati)
    ["I   E   A   A"]                     = "aeia",
    ["A   C   H   R   E   N   A"]         = "arachne",
    ["L   A   R   C   H"]                 = "charl",
    ["L   O   E   N   C   H"]             = "cholen",
    ["K   A   N   E   O"]                 = "eonak",
    ["A   I   O   G   E   R   N"]         = "eorgina",
    ["R   E   Z   G   S   H   E   H"]     = "ghezresh",
    ["R   A   I   M   E   A"]             = "imaera",
    ["V   A   S   E   J   T"]             = "jastev",
    ["S   A   T   N   O   J"]             = "jaston",
    ["N   A   S   T   J   O"]             = "jaston",
    ["A   I   K"]                         = "kai",
    ["R   O   K   A"]                     = "koar",
    ["N   O   K   U"]                     = "kuon",
    ["K   O   N   U"]                     = "kuon",
    ["A   T   E   L   E   H"]             = "laethe",
    ["M   U   I   N   L   S"]             = "lumnis",
    ["S   O   U   L   K   U"]             = "luukos",
    ["A   M   L   U   R"]                 = "marlu",
    ["S   O   M   L   A   R   U"]         = "mularos",
    ["E   A   N   I   L   O"]             = "oleani",
    ["E   P   H   N   O"]                 = "phoen",
    ["N   A   R   O   N"]                 = "ronan",
    ["A   R   O   N"]                     = "onar",
    ["U   S   E   R   H"]                 = "sheru",
    ["O   S   T   I   N"]                 = "tonis",
    ["L   O   V   N"]                     = "voln",
    ["A   Z   I   L   E"]                 = "zelia",
    -- Gems
    ["E   A   G   T   A"]                 = "agate",
    ["S   T   Y   H   E   A   T   M"]     = "amethyst",
    ["R   L   C   O   A"]                 = "coral",
    ["M   A   I   D   O   N   D"]         = "diamond",
    ["D   I   P   S   O   E   D   I"]     = "diopside",
    ["L   A   M   E   R   E   D"]         = "emerald",
    ["N   O   S   T   E   Y   F   E"]     = "feystone",
    ["T   R   A   N   E   G"]             = "garnet",
    ["S   P   A   J   E   R"]             = "jasper",
    ["D   O   E   R   P   T   I"]         = "peridot",
    ["R   A   L   E   P"]                 = "pearl",
    ["N   E   T   I   L   I   P"]         = "plinite",
    ["E   R   I   A   P   S   H   P"]     = "sapphire",
    ["U   T   S   S   O   L   E   N   O"] = "soulstone",
    ["I   R   E   S   P   H   E   N"]     = "spherine",
    ["L   I   S   N   E   P"]             = "spinel",
    -- Monsters
    ["M   O   G   L   E"]                 = "golem",
    ["R   A   I   M   T   O   N   U"]     = "minotaur",
    ["T   E   K   S   L   E   O   N"]     = "skeleton",
    ["A   I   L   N   V   E   L   N"]     = "velnalin",
    ["T   O   N   S   C   U   C   R   T"] = "construct",
    ["R   A   C   E   T   U   N"]         = "centaur",
    ["S   O   U   L   M   I"]             = "moulis",
    ["K   L   A   N   I   M   Y"]         = "myklian",
    ["M   O   N   K   A   I   R"]         = "Kiramon",
    ["M   O   O   N   O   N   N   I"]     = "nonomino",
    ["L   I   M   E   R   N   G"]         = "gremlin",
    ["T   A   E   I   S   R   I   C"]     = "csetairi",
    ["H   A   I   T   R   W"]             = "wraith",
    ["M   A   H   T   N   O   P"]         = "phantom",
    ["S   P   Y   O   C   C   L"]         = "cyclops",
    ["B   O   R   C   A"]                 = "cobra",
}

--------------------------------------------------------------------------------
-- SYMBOL PAINTING DATA
--------------------------------------------------------------------------------

local SYMBOL_COLORS = {
    ["trident"]                = { symbol = "green",   tile = "blue" },
    ["lute"]                   = { symbol = "crimson", tile = "gold" },
    ["anvil"]                  = { symbol = "gold",    tile = "brown" },
    ["sheaf of grain"]         = { symbol = "gold",    tile = "green" },
    ["doe"]                    = { symbol = "brown",   tile = "green" },
    ["artist's brush"]         = { symbol = "black",   tile = "grey" },
    ["crystal ball"]           = { symbol = "silver",  tile = "grey" },
    ["arm with fist clenched"] = { symbol = "silver",  tile = "crimson" },
    ["crown"]                  = { symbol = "gold",    tile = "white" },
    ["key"]                    = { symbol = "gold",    tile = "black" },
    ["sunburst"]               = { symbol = "gold",    tile = "blue" },
    ["pegasus"]                = { symbol = "gold",    tile = "blue" },
    ["sickle"]                 = { symbol = "silver",  tile = "green" },
    ["crescent moon"]          = { symbol = "silver",  tile = "black" },
    ["cat's head"]             = { symbol = "black",   tile = "red" },
    ["slit-pupiled eye"]       = { symbol = "yellow",  tile = "grey" },
    ["serpent"]                = { symbol = "green",   tile = "brown" },
    ["jackal's head"]          = { symbol = "black",   tile = "gold" },
    ["scimitar"]               = { symbol = "black",   tile = "red" },
    ["lily"]                   = { symbol = "white",   tile = "green" },
    ["widow"]                  = { symbol = "black",   tile = "red" },
    ["eight-pointed star"]     = { symbol = "silver",  tile = "black" },
    ["leaf"]                   = { symbol = "gold",    tile = "brown" },
    ["dagger"]                 = { symbol = "ivory",   tile = "blue" },
    ["broken skull"]           = { symbol = "white",   tile = "black" },
    ["note"]                   = { symbol = "yellow",  tile = "blue" },
    ["rose"]                   = { symbol = "yellow",  tile = "red" },
    ["shield"]                 = { symbol = "white",   tile = "black" },
    ["wisp"]                   = { symbol = "green",   tile = "red" },
    ["flame"]                  = { symbol = "red",     tile = "grey" },
}

local PIGMENT_COMPONENTS = {
    blue    = { "blue" },
    brown   = { "brown" },
    crimson = { "crimson" },
    gold    = { "gold" },
    ivory   = { "ivory" },
    red     = { "red" },
    silver  = { "silver" },
    white   = { "white" },
    yellow  = { "yellow" },
    black   = { "black" },
    grey    = { "black", "white" },
    green   = { "yellow", "blue" },
    orange  = { "red", "yellow" },
    purple  = { "blue", "red" },
}

--------------------------------------------------------------------------------
-- CUTOUTS DATA
--------------------------------------------------------------------------------

local CUTOUT_MAP = {
    ["warrior shade"]    = "ta'vaalor",
    ["ash hag"]          = "teras",
    ["dybbuk"]           = "solhaven",
    ["bat"]              = "zul",
    ["black urgh"]       = "ta'vaalor",
    ["krolvin pirate"]   = "river",
    ["krolvin corsair"]  = "river",
    ["great stag"]       = "ta'illistim",
    ["skayl"]            = "teras",
    ["wolfshade"]        = "ta'vaalor",
    ["forest trali"]     = "ta'illistim",
    ["lava golem"]       = "teras",
    ["brown spinner"]    = "river",
    ["mezic"]            = "solhaven",
    ["monkey"]           = "icemule",
    ["spectre"]          = "river",
    ["red tsark"]        = "teras",
    ["ridge orc"]        = "zul",
    ["striped relnak"]   = "ta'vaalor",
    ["luminous spectre"] = "river",
    ["maw spore"]        = "ta'illistim",
    ["fire ogre"]        = "teras",
    ["mongrel hobgoblin"]= "landing",
    ["niirsha"]          = "ta'vaalor",
    ["carceris"]         = "landing",
    ["farlook"]          = "ta'illistim",
    ["three-toed tegu"]  = "ta'illistim",
    ["dobrem"]           = "solhaven",
    ["krynch"]           = "zul",
    ["wood wight"]       = "solhaven",
    ["albino scorpion"]  = "zul",
    ["seraceris"]        = "icemule",
    ["pyrothag"]         = "teras",
    ["spectral miner"]   = "landing",
    ["caribou"]          = "icemule",
    ["cave bear"]        = "river",
    ["grizzly bear"]     = "icemule",
    ["blood eagle"]      = "river",
    ["stone gargoyle"]   = "landing",
    ["grutik savage"]    = "zul",
    ["white vysan"]      = "icemule",
    ["giant veaba"]      = "zul",
    ["waern"]            = "solhaven",
    ["hobgoblin"]        = "landing",
    ["ilvarie pixie"]    = "ta'vaalor",
    ["greater kappa"]    = "landing",
    ["monastic lich"]    = "landing",
    ["pale crab"]        = "solhaven",
    ["grifflet"]         = "ta'illistim",
    ["seeker"]           = "icemule",
}

--------------------------------------------------------------------------------
-- SHEET (HIDES) DATA
--------------------------------------------------------------------------------

local SHEET_HIDE_MAP = {
    ["lesser orc"]       = "hide",
    ["agresh bear"]      = "claw",
    ["troll chieftain"]  = "fang",
    ["werebear"]         = "paw",
    ["bear"]             = "claw",
    ["cyclops"]          = "eye",
    ["thrak"]            = "hide",
    ["coyote"]           = "tail",
    ["warthog"]          = "snout",
    ["vesperti"]         = "claw",
    ["forest trali"]     = "hide",
    ["martial eagle"]    = "talon",
    ["red bear"]         = "paw",
    ["puma"]             = "hide",
    ["cougar"]           = "tail",
    ["mountain snowcat"] = "pelt",
    ["manticore"]        = "tail",
    ["spotted leaper"]   = "pelt",
    ["thunder troll"]    = "scalp",
    ["shadow steed"]     = "tail",
    ["plains lion"]      = "skin",
    ["black leopard"]    = "paw",
    ["spectre"]          = "skin",
    ["lava troll"]       = "eye",
    ["treekin druid"]    = "beard",
    ["grey orc"]         = "beard",
    ["mist wraith"]      = "eye",
    ["centaur ranger"]   = "hide",
}

--------------------------------------------------------------------------------
-- FLOWERS DATA
--------------------------------------------------------------------------------

local FLOWER_SEEDS = {
    Admiration    = "sunflower seed",
    Bashfulness   = "peony tuber",
    Beauty        = "orchid seedpod",
    Betrayal      = "wolfsbane bulb",
    Cheerfulness  = "crocus seed",
    Danger        = "foxglove bulb",
    Elegance      = "begonia seed",
    Expectation   = "anemone bulb",
    Fickleness    = "larkspur seed",
    Forgetfulness = "moonflower seedpod",
    Laughter      = "monkeyflower seed",
    Love          = "rose hip",
    Presumption   = "snapdragon seed",
    Prophecy      = "sirenflower seed",
    Remembrance   = "rosemary seed",
    Spirituality  = "dandelion seed-puff",
    Strength      = "fennel seed",
    Untameable    = "heather seed",
}

--------------------------------------------------------------------------------
-- GNOME DATA
--------------------------------------------------------------------------------

local GNOME_TRANSLATION = {
    Rosengift   = "multi-feathered",
    Angstholm   = "owl-feathered",
    Basingstoke = "peacock",
    Wendwillow  = "feather",
    Felcour     = "vulture",
}

--------------------------------------------------------------------------------
-- SHOP DATA
--------------------------------------------------------------------------------

local SHOP_TRANSLATION = {
    Darbo     = "alchemist",
    Elantaran = "alchemist",
    Lomara    = "alchemist",
    Sorena    = "alchemist",
    Morvaeyn  = "armor",
    Itarille  = "armor",
    Haldrick  = "armor",
    Vonder    = "fletcher",
    Relegan   = "fletcher",
    Marijon   = "herb",
    Trill     = "instrument",
    Ambra     = "instrument",
    Hervina   = "jewelry",
    Murdos    = "jewelry",
    Galena    = "locksmith",
    Hihaeim   = "locksmith",
    Kniknak   = "locksmith",
    Kreldor   = "locksmith",
}

--------------------------------------------------------------------------------
-- PROFESSION GOBLETS DATA
--------------------------------------------------------------------------------

local PROFESSION_GOBLETS = {
    rangers   = "green goblet",
    rogues    = "dark goblet",
    bards     = "blue goblet",
    paladins  = "blue goblet",
    wizards   = "clear goblet",
    clerics   = "silver goblet",
    warriors  = "purple goblet",
    empaths   = "silver goblet",
    sorcerers = "black goblet",
}

--------------------------------------------------------------------------------
-- PUZZLE SOLVERS
--------------------------------------------------------------------------------

local function solve_statue()
    local altar_text = dothistimeout(
        "look at altar", 3,
        "A collection of statuary are situated near the altar",
        "Four different statues",
        "I could not find what you were referring to%."
    )
    local bowl_text = altar_text and dothistimeout(
        "look in bowl", 3,
        "An altar sits",
        "I could not find what you were referring to%."
    )

    if not altar_text or not bowl_text
       or altar_text:find("I could not find what you were referring to%.")
       or bowl_text:find("I could not find what you were referring to%.") then
        respond("")
        respond("ERROR: doesn't look like an altar statue puzzle")
        respond("")
        return false
    end

    local all_commands = {}
    for statue, desc in pairs(STATUE_DESCRIPTION_OF) do
        local bowl_pos  = statue_parse_bowl_position(statue, bowl_text)
        local altar_pos = statue_parse_altar_position(statue, altar_text)
        if not bowl_pos or not altar_pos then
            respond("ERROR: couldn't determine position for " .. statue)
            return false
        end
        local path = statue_find_path(altar_pos, bowl_pos)
        if path then
            local altar_noun = desc.altar:match("(%S+)$")  -- last word
            for _, dir in ipairs(path) do
                table.insert(all_commands, dir .. " " .. altar_noun)
            end
        end
    end

    if #all_commands == 0 then
        respond("")
        respond("ERROR: couldn't determine a solution")
        respond("")
        return false
    end

    for _, cmd in ipairs(all_commands) do
        fput(cmd)
    end
    fput("bow altar")
    return true
end

local function solve_mosaic()
    for round = 1, 5 do
        local result = dothistimeout(
            "look at colorful mosaic", 5,
            "The depiction of",
            "I could not find what you were referring to%."
        )

        if not result then
            respond("")
            respond("  ERROR: timed out looking at mosaic")
            respond("")
            return false
        elseif result:find("I could not find what you were referring to%.") then
            respond("")
            respond("  ERROR: This doesn't look like a mosaic puzzle")
            respond("")
            return false
        end

        local god = result:match("The depiction of (.-) is lit up from behind,")
        if not god then
            respond("")
            respond("  ERROR: couldn't determine which Arkati is selected in the mosaic")
            respond("")
            return false
        end

        local info = MOSAIC_GEM_INFO[god]
        if not info then
            respond("")
            respond("  ERROR: don't have data for Arkati: " .. god)
            respond("")
            return false
        end

        local gem   = info.gem
        local shape = info.shape
        local gem_noun = gem:match("(%S+)$")  -- last word of gem name

        -- Turn contraption until gem type matches (plain find — gem names are literal)
        for _ = 1, 100 do
            local r = dothistimeout("turn contraption", 5, "^As you")
            if r and string.find(r, gem, 1, true) then
                break
            end
        end

        -- Push contraption until shape matches (plain find — shape names may contain hyphens)
        for _ = 1, 100 do
            local r = dothistimeout("push contraption", 5, "^As you")
            if r and string.find(r, shape, 1, true) then
                break
            end
        end

        dothistimeout("tap contraption", 3, "You tap the bejweled button")

        local placed = dothistimeout(
            "put my " .. gem_noun .. " in colorful mosaic", 3,
            "You carefully place your"
        )
        if not placed then
            respond("")
            respond("  ERROR: failed to place gem in mosaic.")
            respond("  Try to pry everything and unpause script to continue.")
            respond("")
            pause_script(Script.name)
            return false
        end

        if round < 5 then
            fput("rub colorful mosaic")
        end
    end
    return true
end

local function solve_crystal()
    for round = 1, 3 do
        for _ = 1, 100 do
            local result = dothistimeout(
                "rub glowing crystal", 5,
                "^Within moments, however,",
                "Rather than destroying it",
                "What were you referring to%?"
            )

            if not result or result:find("What were you referring to%?") then
                respond("")
                respond("  ERROR: Doesn't look like a crystal puzzle to me")
                respond("")
                return false
            elseif result:find("Rather than destroying it") then
                break
            end
            -- "Within moments, however," = wrong type, tap and try again
            fput("tap crystal")
        end

        if round < 3 then
            fput("turn crystal")
        end
    end
    return true
end

local function solve_stars()
    for round = 1, 4 do
        if not checkright("star") and not checkleft("star") then
            fput("get star")
            if not checkright("star") and not checkleft("star") then
                echo("ERROR: couldn't get a star to place")
                return false
            end
        end

        local result = dothistimeout(
            "look sky", 3,
            'The "',
            "You can't see the sky from here.",
            "You gaze up into the sky"
        )

        if not result or result:find("You can't see the sky from here.") or result:find("You gaze up into the sky") then
            respond("")
            respond("  ERROR: This doesn't seem like a Constellation puzzle")
            respond("")
            return false
        end

        local active_area = result:match('The "(.-)\" area is brightly lit with a random smattering of stars%.')
        if not active_area then
            respond("")
            respond("  ERROR: couldn't parse active area from: " .. tostring(result))
            respond("")
            return false
        end

        local constellation = CONSTELLATIONS[active_area]
        if not constellation then
            respond("")
            respond("  ERROR: don't know the constellation for: " .. active_area)
            respond("")
            return false
        end

        -- Rub star until it settles into the correct constellation
        for _ = 1, 100 do
            local r = dothistimeout("rub my star", 5, "until they settle on a formation akin")
            if r and r:find("formation akin to " .. constellation .. "%.") then
                break
            end
        end

        fput("put star in sky")
        if round < 4 then
            fput("turn sky")
        end
    end
    return true
end

local function solve_scramble()
    local result = dothistimeout(
        "look wall", 5,
        "the letters are:",
        "I could not find what you were referring to%."
    )

    if not result then
        respond("")
        respond("  ERROR: timed out looking at the wall")
        respond("")
        return false
    elseif result:find("I could not find what you were referring to%.") then
        respond("")
        respond("  ERROR: doesn't look like a word scramble puzzle")
        respond("")
        return false
    end

    local letters = result:match("the letters are:%s+(.-)%s*$")
    if not letters then
        respond("")
        respond("  ERROR: couldn't parse letters from wall")
        respond("")
        return false
    end

    local answer = SCRAMBLE_SOLUTIONS[letters]
    if not answer then
        respond("")
        respond("  ERROR: don't know the answer for: " .. letters)
        respond("")
        return false
    end

    fput("get chalk")
    fput("write wall; " .. answer)
    return true
end

local function solve_ghost()
    -- Credit: Alastir
    fput("dig dirt")
    fput("get wand")
    fput("turn my wand")
    fput("turn my wand")
    fput("turn my wand")
    dothistimeout("wave wand at ghost", 5, "^You wave")
    waitcastrt()
    waitrt()
    fput("drop wand")
    fput("search corpse")
    fput("unlock coffin with my key")
    fput("open coffin")
    fput("push corpse")
    fput("close coffin")
    fput("push coffin")
    fput("bury coffin")
    return true
end

local function symbol_change_pigment_to(color)
    for _ = 1, 25 do
        local result = dothistimeout(
            "rub pigment", 3,
            "the pigment inside gradually transforms from",
            "What were you referring to%?"
        )
        if not result or result:find("What were you referring to%?") then
            respond("")
            respond("  ERROR: couldn't find any pigment for our paintbrush")
            respond("")
            return false
        end
        local cur_color = result:match("the pigment inside gradually transforms from .* to (.-)%.$")
        if cur_color == color then
            return true
        end
    end
    return false
end

local function symbol_set_pigment(color)
    fput("clean paintbrush")
    local components = PIGMENT_COMPONENTS[color]
    if not components then
        respond("  ERROR: don't know pigment components for: " .. color)
        return false
    end
    for _, base in ipairs(components) do
        if not symbol_change_pigment_to(base) then return false end
        fput("dip pigment")
    end
    return true
end

local function solve_symbol()
    -- Find the symbol in room loot
    local loot = GameObj.loot()
    local symbol_obj = nil
    for _, obj in ipairs(loot) do
        if obj.noun == "symbol" then
            symbol_obj = obj
            break
        end
    end

    if not symbol_obj then
        respond("")
        respond("  ERROR: couldn't find a symbol in the room")
        respond("")
        return false
    end

    -- description = name minus last word ("symbol")
    local symbol_description = symbol_obj.name:match("^(.+)%s+%S+$")
    if not symbol_description then
        symbol_description = symbol_obj.name
    end

    -- Look up color info; try exact match first, then suffix match
    local color_info = SYMBOL_COLORS[symbol_description]
    if not color_info then
        for desc, info in pairs(SYMBOL_COLORS) do
            if symbol_description:sub(-#desc) == desc then
                color_info = info
                break
            end
        end
    end

    if not color_info then
        respond("")
        respond("  ERROR: don't know which color to paint '" .. symbol_description .. "'")
        respond("  Sorry, but you will need to solve this on your own.")
        respond("")
        pause_script(Script.name)
        return false
    end

    -- Get paintbrush
    if not checkright("paintbrush") and not checkleft("paintbrush") then
        fput("get paintbrush")
    end

    -- Paint symbol and tile
    for target, color in pairs(color_info) do
        fput("clean " .. target)
        if not symbol_set_pigment(color) then return false end
        fput("paint " .. target)
    end

    fput("drop paintbrush")
    fput("get symbol")
    fput("put symbol on tile")
    return true
end

local function solve_makecandle()
    -- Credit: Alastir
    fput("look in box")
    fput("get beeswax")
    fput("put beeswax in pot")
    fput("get wick")
    fput("put wick in mold")
    fput("get pot")
    fput("put pot on hearth")
    fput("light hearth")
    fput("turn pot")
    fput("snuff hearth")
    fput("get pot")
    fput("get mold")
    fput("pour pot into mold")
    fput("put pot on hearth")
    fput("put mold in case")
    fput("get mold from case")
    fput("turn mold")
    fput("put mold in case")

    local r = dothistimeout(
        "drop candle", 5,
        "^You drop",
        "^You notice that the beeswax pillar candle is marked as unsellable and stop yourself."
    )
    if r and r:find("^You notice that the beeswax pillar candle is marked as unsellable and stop yourself%.") then
        echo("You have NOMARKEDDROP enabled but this puzzle requires you to drop marked items.")
        echo("You can disable this setting with: SET NOMARKEDDROP OFF")
        fput("set nomarkeddrop off")
        fput("drop candle")
        fput("set nomarkeddrop on")
    end

    fput("light candle")
    return true
end

local function solve_lightcandle()
    fput("look bench")
    fput("get twig")
    fput("put twig in brazier")

    for _, ord in ipairs({ "first", "second", "third", "fourth" }) do
        local result = dothistimeout(
            "light " .. ord .. " candle", 3,
            "The wick flickers gently but burns brightly",
            "The wick refuses to stay lit",
            "What were you referring to%?"
        )
        if not result or result:find("What were you referring to%?") then
            respond("")
            respond("  ERROR: this doesn't seem to be a candle puzzle")
            respond("")
            return false
        elseif result:find("The wick flickers gently but burns brightly") then
            return true
        end
        -- FAIL_REGEX: wrong candle, try next ordinal
    end
    return true
end

local function solve_levers()
    multifput("push white lev", "pull black lev", "push green lev", "pull blue lev", "push red lev")
    return true
end

local function solve_irondoor()
    multifput("kick boulder", "get key", "unlock door")
    return true
end

local function solve_boxsphere()
    multifput("push box", "roll sphere")
    return true
end

local function solve_trapdoor()
    dothistimeout(
        "push boulder", 3,
        "With a heave%-ho, you manage to push the boulder onto the trapdoor%."
    )
    while true do
        local result = dothistimeout(
            "jump trapdoor", 0.5,
            "As the wooden trapdoor breaks apart and the boulder drops into darkness",
            "That was fun%."
        )
        if result and (result:find("As the wooden trapdoor breaks apart") or result:find("That was fun%.")) then
            break
        end
    end
    return true
end

local function solve_bookcase1()
    multifput("l in book", "lean journal", "pull rug", "pull trap")
    return true
end

local function solve_bookcase2()
    multifput("jump", "push button", "l behind book", "pull lever")
    return true
end

local function solve_lavariver()
    fput("get hatchet")
    while true do
        local result = dothistimeout(
            "cut tree", 3,
            "You raise a steel hatchet high over your head",
            "There is already a sufficient notch in the tree%."
        )
        pause(0.2)
        if result and result:find("There is already a sufficient notch in the tree%.") then
            break
        end
    end
    multifput("push tree", "go tree")
    return true
end

local function solve_wizard()
    multifput("get robe", "put robe on man", "get hat", "put hat on man")
    return true
end

local function solve_wicker()
    multifput(
        "open box", "l in box", "get tube", "drop tube", "get sheet",
        "shake sheet", "put sheet on box", "get tube", "play tube"
    )
    return true
end

local function solve_aldoran()
    local result = dothistimeout("look", 3, "sickly looking woman%.", "sickly looking man%.")
    local heal_target
    if result and result:find("sickly looking woman%.") then
        heal_target = "woman"
    elseif result and result:find("sickly looking man%.") then
        heal_target = "man"
    else
        respond("  ERROR: couldn't determine the sick person")
        return false
    end

    fput("look in basket")
    result = dothistimeout(
        "inspect " .. heal_target, 10,
        "head%.", "neck%.", "face%.", "broken hand%.", "broken arm%.", "broken leg%.",
        "back%.", "chest%.", "abdomen%.", "major convulsions%.", "severe blood loss%.",
        "over%-indulgence of alcohol%.", "debilitating disease%.", "exposure to poison%."
    )

    if not result then
        respond("  ERROR: couldn't determine injury type")
        return false
    end

    local stone
    if result:find("head%.") or result:find("neck%.") or result:find("face%.") then
        stone = "spinel"
    elseif result:find("broken hand%.") or result:find("broken arm%.") or result:find("broken leg%.") then
        stone = "sard"
    elseif result:find("back%.") or result:find("chest%.") or result:find("abdomen%.") then
        stone = "sunstone"
    elseif result:find("major convulsions%.") then
        stone = "tourmaline"
    elseif result:find("severe blood loss%.") then
        stone = "quartz"
    elseif result:find("over%-indulgence of alcohol%.") then
        stone = "amethyst"
    elseif result:find("debilitating disease%.") then
        stone = "alabaster"
    elseif result:find("exposure to poison%.") then
        stone = "turquoise"
    else
        echo("Could not find appropriate injury")
        return false
    end

    multifput("get " .. stone .. " from basket", "wave " .. stone .. " at " .. heal_target)
    return true
end

local function solve_gnomes()
    fput("look mannequin")
    while true do
        local line = get()
        local clan = line:match("(%a+) forest gnome mannequin")
        if clan then
            local apotl_type = GNOME_TRANSLATION[clan]
            if apotl_type then
                multifput("get " .. apotl_type .. " apotl", "put apotl on mannequin")
            else
                respond("  ERROR: don't know apotl for clan: " .. clan)
                return false
            end
            break
        end
    end
    return true
end

local function solve_elves()
    fput("look in basket")
    for _, shield_num in ipairs({ "first", "second", "third", "fourth" }) do
        pause(0.2)
        local result = dothistimeout(
            "look " .. shield_num .. " shield", 5,
            "Encircled by silver, an onyx rose is set upon a field of jade",
            "Encircled by silver, a silver harp is set upon a field of dark amethyst",
            "Encircled by silver, a golden wyvern leaf is set upon a field of crimson",
            "Encircled by silver, an aquamarine wavecrest is set upon a field of white",
            "Encircled by gold, a peacock is set upon a field of deep sapphire blue",
            "Encircled by gold, a broad green oak leaf is set upon a field of umber",
            "Encircled by gold, a scarlet pentacle is set upon a field of grey"
        )

        if not result then goto continue_shields end

        local cabochon
        if result:find("onyx rose") then
            cabochon = "black cabochon"
        elseif result:find("silver harp") then
            cabochon = "purple cabochon"
        elseif result:find("golden wyvern leaf") then
            cabochon = "red cabochon"
        elseif result:find("aquamarine wavecrest") then
            cabochon = "green cabochon"
        elseif result:find("peacock") then
            cabochon = "white cabochon"
        elseif result:find("broad green oak leaf") then
            cabochon = "yellow cabochon"
        elseif result:find("scarlet pentacle") then
            cabochon = "orange cabochon"
        end

        if cabochon then
            multifput("get " .. cabochon, "put my cabochon in " .. shield_num .. " shield")
        end

        ::continue_shields::
    end
    return true
end

local function solve_colorsphere()
    local translation = {
        crimson  = "red",
        ivory    = "white",
        sapphire = "blue",
        ebony    = "black",
        viridian = "green",
    }

    local ordered_spheres = {}
    fput("push button")
    while #ordered_spheres < 4 do
        local line = get()
        local color = line:match("An? (%a+) glow fills the area")
        if color then
            local mapped = translation[color]
            if mapped then
                table.insert(ordered_spheres, mapped)
            end
        end
    end

    for _, color in ipairs(ordered_spheres) do
        fput("touch " .. color .. " sphere")
    end
    return true
end

local function solve_shops()
    pause(0.5)
    put("peer window")
    while true do
        local line = get()
        local caps = Regex.new("the faint image of (\\w+) (?:in|materializes)"):captures(line)
        if caps and caps[1] then
            local npc = caps[1]
            local shop = SHOP_TRANSLATION[npc]
            if shop then
                fput("point " .. shop .. " shop")
            else
                respond("  ERROR: don't know which shop for NPC: " .. npc)
                return false
            end
            break
        end
    end
    return true
end

local function solve_cutouts()
    fput("look in paper bag")
    local cutouts_left = true
    while cutouts_left do
        fput("get cutout from paper bag")
        local result = dothistimeout(
            "look in paper bag", 3,
            "cutout",
            "There is nothing in the bag%."
        )
        if result and result:find("There is nothing in the bag%.") then
            cutouts_left = false
        end

        dothistimeout("dip my cutout in glue", 3, "until it is sufficiently covered%.")

        local rh = GameObj.right_hand()
        if rh then
            local creature = rh.name:lower():gsub(" cutout$", "")
            local map_dest = CUTOUT_MAP[creature]
            if map_dest then
                dothistimeout(
                    "put cutout on " .. map_dest .. " map", 3,
                    "You pat it firmly a few times until the glue dries sufficiently%."
                )
            else
                respond("  ERROR: don't know map for creature: " .. creature)
            end
        end
    end
    return true
end

local function solve_sheet()
    fput("pull sheet")
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.name:find("statue$") then
            local creature = obj.name:lower():gsub(" statue$", "")
            local hide = SHEET_HIDE_MAP[creature]
            if hide then
                echo(creature .. " -> " .. hide)
                put("look")
                pause(1)
                fput("get " .. hide)
                fput("put " .. hide .. " on #" .. obj.id)
            else
                respond("  ERROR: don't know hide for creature: " .. creature)
            end
        end
    end
    return true
end

local function solve_flowers()
    pause(0.2)
    fput("look in seed box")
    pause(0.2)
    put("read tapestry")
    while true do
        local line = get()
        local word = line:match("~~ (%a+) ~~")
        if word then
            local seed = FLOWER_SEEDS[word]
            if seed then
                multifput(
                    "get " .. seed,
                    "put " .. seed .. " in pot",
                    "get watering can",
                    "pour can on pot"
                )
            else
                respond("  ERROR: don't know seed for: " .. word)
                return false
            end
            break
        end
    end
    return true
end

local function solve_professions()
    pause(0.2)
    fput("look on mahogany bar")
    pause(0.2)
    put("read bar")

    local profession = nil
    while true do
        local line = get()
        local prof = line:match("~%*~ I am the goblet of (%a+)%. ~%*~")
        if prof then
            profession = prof:lower()
            break
        end
    end

    if not profession then
        respond("  ERROR: couldn't determine profession from bar")
        return false
    end

    local goblet = PROFESSION_GOBLETS[profession]
    if not goblet then
        respond("  ERROR: don't know goblet for profession: " .. profession)
        return false
    end

    if profession == "paladins" or profession == "bards" then
        local result = dothistimeout(
            "get " .. goblet .. " from mahogany bar", 3,
            "elegant blue cut%-glass goblet",
            "elegant blue crystal goblet"
        )
        local correct = (result and result:find("elegant blue cut%-glass goblet") and profession == "paladins")
                     or (result and result:find("elegant blue crystal goblet") and profession == "bards")
        if correct then
            fput("drink my goblet")
        else
            multifput(
                "put my goblet on bar",
                "get second " .. goblet .. " from mahogany bar",
                "drink my goblet"
            )
        end
    else
        multifput("get " .. goblet .. " from mahogany bar", "drink my goblet")
    end
    return true
end

--------------------------------------------------------------------------------
-- PUZZLE REGISTRY
--------------------------------------------------------------------------------

local PUZZLES = {
    { name = "statue",      solve = solve_statue,      requirements = { "grey felsite altar" } },
    { name = "mosaic",      solve = solve_mosaic,       requirements = { "gem-bedecked contraption", "colorful floor mosaic" } },
    { name = "crystal",     solve = solve_crystal,      requirements = { "depiction" } },
    { name = "stars",       solve = solve_stars,        requirements = { "dark night sky" } },
    { name = "ghost",       solve = solve_ghost,        requirements = { "dead ghost", "ebonwood coffin", "patch of loose dirt", "pale grey wand" } },
    { name = "scramble",    solve = solve_scramble,     requirements = { "wall", "piece of chalk" } },
    { name = "symbol",      solve = solve_symbol,       requirements = { "symbol", "pigment", "tile" } },
    { name = "makecandle",  solve = solve_makecandle,   requirements = { "white paper box" } },
    { name = "lightcandle", solve = solve_lightcandle,  requirements = { "iron brazier", "elaborate prayer bench" } },
    { name = "levers",      solve = solve_levers,       requirements = { "white lever", "black lever", "green lever", "blue lever", "red lever" } },
    { name = "irondoor",    solve = solve_irondoor,     requirements = { "iron door", "slate grey boulder" } },
    { name = "trapdoor",    solve = solve_trapdoor,     requirements = { "wooden trapdoor", "large boulder" } },
    { name = "boxsphere",   solve = solve_boxsphere,    requirements = { "slightly elevated platform", "glowing sphere", "large metal box", "wrought iron gate" } },
    { name = "colorsphere", solve = solve_colorsphere,  requirements = { "metal button", "white sphere", "black sphere", "green sphere", "blue sphere", "red sphere" } },
    { name = "bookcase1",   solve = solve_bookcase1,    requirements = { "woven rug", "wooden bookcase" } },
    { name = "bookcase2",   solve = solve_bookcase2,    requirements = { "tall bookcase" } },
    { name = "lavariver",   solve = solve_lavariver,    requirements = { "wide lava river", "ironwood tree", "steel hatchet" } },
    { name = "wizard",      solve = solve_wizard,       requirements = { "robe", "hat", "wizard mannequin" } },
    { name = "wicker",      solve = solve_wicker,       requirements = { "wicker box" } },
    { name = "aldoran",     solve = solve_aldoran,      requirements = { "woven basket" } },
    { name = "gnomes",      solve = solve_gnomes,       requirements = { "black vulture feather apotla", "tawny owl-feathered apotl", "multi-feathered apotla", "albatross feather apotl", "peacock feather apotl" } },
    { name = "elves",       solve = solve_elves,        requirements = { "wicker basket", "shield" } },
    { name = "shops",       solve = solve_shops,        requirements = { "small window" } },
    { name = "cutouts",     solve = solve_cutouts,      requirements = { "paper bag", "bowl of glue" } },
    { name = "sheet",       solve = solve_sheet,        requirements = { "white silk sheet covering a large display" } },
    { name = "flowers",     solve = solve_flowers,      requirements = { "watering can", "clay pot", "seed box", "woven tapestry" } },
    { name = "professions", solve = solve_professions,  requirements = { "antique mahogany bar" } },
}

--------------------------------------------------------------------------------
-- AUTO DETECTION
--------------------------------------------------------------------------------

local PUZZLE_TRIGGERS = { "white tile", "tile", "dark ceiling", "dim crystal" }

local function activate_puzzle_triggers()
    local loot = GameObj.loot()
    for _, trigger in ipairs(PUZZLE_TRIGGERS) do
        for _, obj in ipairs(loot) do
            if obj.name == trigger then
                fput("look " .. trigger)
                break
            end
        end
    end
end

local function determine_puzzle()
    for _, puzzle in ipairs(PUZZLES) do
        local all_found = true
        for _, req in ipairs(puzzle.requirements) do
            if not loot_has(req) then
                all_found = false
                break
            end
        end
        if all_found then return puzzle end
    end
    return nil
end

local function puzzle_here()
    activate_puzzle_triggers()
    return determine_puzzle()
end

--------------------------------------------------------------------------------
-- HELP
--------------------------------------------------------------------------------

local function print_usage()
    respond("")
    respond("  Rings of Lumnis Puzzle Solver")
    respond("")
    respond("  Usage:")
    respond("")
    respond("    ;rofl_puzzles <puzzle name>")
    respond("")
    respond("  where <puzzle name> is one of the following:")
    respond("")
    respond(string.format("    %-12s %s", "auto", "automatically solve puzzles when they appear (default behavior)"))
    respond("")

    -- Sort puzzles by name for display
    local sorted = {}
    for _, p in ipairs(PUZZLES) do
        table.insert(sorted, p)
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for _, puzzle in ipairs(sorted) do
        respond(string.format("    %s", puzzle.name))
    end
    respond("")
end

--------------------------------------------------------------------------------
-- AUTO SOLVE LOOP
--------------------------------------------------------------------------------

local function auto_solve()
    while true do
        local puzzle = wait_until(
            "[rofl_puzzles] waiting for next puzzle...",
            function() return puzzle_here() end
        )

        respond("")
        respond("  Looks like a " .. puzzle.name .. " puzzle, attempting to solve it.")

        empty_hands()
        puzzle.solve()
        clear()

        -- Wait for reward: "I believe this is yours, and places"
        for _ = 1, 5 do
            local result = matchtimeout(10, '"I believe this is yours," and places')
            if result and result:find('"I believe this is yours," and places') then
                break
            else
                local qname = "rofl_questions"
                if Script.running(qname) and not Script.is_paused(qname) then
                    respond("")
                    respond("ERROR: Something went wrong with trying to solve the puzzle.")
                    respond("  Please report this error to the Elanthia-Online group for help")
                    respond("")
                    return
                elseif Script.is_paused(qname) then
                    respond("")
                    respond("ERROR: You have rofl_questions paused, attempting to unpause now and repeat!")
                    Script.unpause(qname)
                    put("repeat")
                else
                    respond("")
                    respond("ERROR: You don't have rofl_questions running, this is required or answer the question manually!")
                    respond("  Attempting to start rofl_questions now since question was not answered manually.")
                    if Script.exists(qname) and not Script.running(qname) then
                        Script.run(qname)
                    end
                    pause(1)
                    if Script.running(qname) then
                        put("repeat")
                    else
                        respond("  Couldn't start rofl_questions, and you didn't answer question manually, something is wrong!")
                        respond("  Report this to Elanthia-Online group for help")
                        return
                    end
                end
            end
        end

        fill_hands()
        fput("look")
    end
end

--------------------------------------------------------------------------------
-- DISPATCH
--------------------------------------------------------------------------------

local vars = Script.vars
local cmd  = (vars and vars[1] or "auto"):lower()

if cmd:match("^help") then
    print_usage()
elseif cmd == "auto" or cmd == "" or not cmd then
    auto_solve()
elseif cmd:match("^stat") then
    solve_statue()
elseif cmd:match("^mosaic") or cmd:match("^mosiac") or cmd:match("^gem") then
    solve_mosaic()
elseif cmd:match("^cry") then
    solve_crystal()
elseif cmd:match("^star") then
    solve_stars()
elseif cmd:match("^scram") then
    solve_scramble()
elseif cmd:match("^ghost") or cmd:match("^coffin") then
    solve_ghost()
elseif cmd:match("^paint") or cmd:match("^symbol") or cmd:match("^tile") then
    solve_symbol()
elseif cmd:match("^makec") then
    solve_makecandle()
elseif cmd:match("^light") then
    solve_lightcandle()
elseif cmd:match("^lever") then
    solve_levers()
elseif cmd:match("^iron") then
    solve_irondoor()
elseif cmd:match("^trap") then
    solve_trapdoor()
elseif cmd:match("^box") then
    solve_boxsphere()
elseif cmd:match("^color") then
    solve_colorsphere()
elseif cmd:match("case1") then
    solve_bookcase1()
elseif cmd:match("case2") then
    solve_bookcase2()
elseif cmd:match("^lava") then
    solve_lavariver()
elseif cmd:match("^wizard") then
    solve_wizard()
elseif cmd:match("^wicker") then
    solve_wicker()
elseif cmd:match("^aldoran") then
    solve_aldoran()
elseif cmd:match("^gnomes") then
    solve_gnomes()
elseif cmd:match("^elves") then
    solve_elves()
elseif cmd:match("^shops") then
    solve_shops()
elseif cmd:match("^cutouts") then
    solve_cutouts()
elseif cmd:match("^sheet") then
    solve_sheet()
elseif cmd:match("^flowers") then
    solve_flowers()
elseif cmd:match("^professions") then
    solve_professions()
else
    respond("")
    respond("  [rofl_puzzles] didn't recognize '" .. cmd .. "' as a valid puzzle")
    print_usage()
end
