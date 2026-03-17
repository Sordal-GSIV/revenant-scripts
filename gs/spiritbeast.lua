--- @revenant-script
--- name: spiritbeast
--- version: 0.91.0
--- author: Deathravin
--- game: gs
--- description: Spirit Beast tracker - capture, display info, manage collection, and battle spirit beasts
--- tags: spiritbeasts, spirit, beast, capture, collection
---
--- Usage:
---   ;spiritbeast               - Gather info on all owned beasts and display
---   ;spiritbeast info           - Gather info on all captured beasts
---   ;spiritbeast echo           - Display all owned beasts (sorted by level)
---   ;spiritbeast element        - Display owned beasts sorted by element
---   ;spiritbeast class          - Display owned beasts sorted by class
---   ;spiritbeast collection [rarity] - Display full collection status
---   ;spiritbeast capture [area] - Capture a beast (WL, SH, TE, RR, IM, etc.)
---   ;spiritbeast reset          - Clear all gathered beast information
---   ;spiritbeast help           - Show this help

-- Spirit beast database
local spirit_beasts = {}

local function reset_beasts()
    spirit_beasts = {}

    -- Purchasable
    local beasts_data = {
        -- name = { location, room, cap_level, swim, climb, area, rarity }
        -- Purchasable (AP)
        ["Battle Cardinal"]       = { "AP", " ", 101, 0, 0, "", "Legendary" },
        ["Rolton King"]           = { "AP", " ", 101, 0, 0, "", "Legendary" },
        ["Beleaguered Healer"]    = { "AP", " ", 101, 0, 0, "", "Uncommon" },
        ["Headless Pooka"]        = { "AP", " ", 101, 0, 0, "", "Uncommon" },
        ["fennec fox"]            = { "AP", " ", 101, 0, 0, "", "Common" },
        ["great panda"]           = { "AP", " ", 101, 0, 0, "", "Common" },
        ["raven"]                 = { "AP", " ", 101, 0, 0, "", "Common" },
        -- Hinterwilds (HW)
        ["Battleborn Berserker"]  = { "HW", "u7503498", 101, 0, 0, "Angargreft", "Legendary" },
        ["Chthonian Sybil"]       = { "HW", "u7503444", 101, 0, 0, "Pit of the Dead", "Legendary" },
        ["Brawny Disir"]          = { "HW", " ", 101, 0, 0, "Angargreft", "Uncommon" },
        ["halfling cannibal"]     = { "HW", "u7503101", 101, 0, 0, "", "Common" },
        ["hinterboar"]            = { "HW", "u7503101", 101, 0, 0, "", "Common" },
        ["warg"]                  = { "HW", "u7503101", 101, 0, 0, "", "Common" },
        -- Wehnimer's Landing (WL)
        ["Featherdancer"]         = { "WL", "u2123030", 35, 0, 0, "Elven Village", "Legendary" },
        ["Frost Lich"]            = { "WL", "u18209", 20, 0, 0, "Graveyard", "Legendary" },
        ["Frostwyrm"]             = { "WL", "u4044008", 30, 0, 0, "Glatoph", "Legendary" },
        ["Ghostfin"]              = { "WL", "u386022", 0, 0, 0, "Coastal Cliffs", "Legendary" },
        ["Golden Champion"]       = { "WL", "u386033", 0, 0, 0, "Shrines", "Legendary" },
        ["Kobold High Shaman"]    = { "WL", "u373016", 10, 0, 0, "Kobold Village", "Legendary" },
        ["Moon Serpent"]           = { "WL", "u52017", 101, 0, 50, "Melgorehn's Reach", "Legendary" },
        ["Nightchild"]            = { "WL", "u45134", 101, 0, 30, "Darkstone Keep", "Legendary" },
        ["Pyrelord"]              = { "WL", "u35025", 30, 0, 0, "Glatoph", "Legendary" },
        ["Rose Lord"]             = { "WL", "u4121003", 0, 0, 0, "Upper Dragonsclaw", "Legendary" },
        ["Stone Guardian"]        = { "WL", "u374017", 0, 0, 0, "Colossus", "Legendary" },
        ["Whiskey Spirit"]        = { "WL", "u338001", 0, 0, 0, "Wehnimer's Landing", "Legendary" },
        ["Elusive Warcat"]        = { "WL", "u92120", 35, 0, 0, "Blackened Cave", "Uncommon" },
        ["Greenwing Queen"]       = { "WL", "u4285042", 40, 0, 0, "Castle Anwyn", "Uncommon" },
        ["Hungering Ghoul"]       = { "WL", "u18003", 15, 0, 0, "Graveyard", "Uncommon" },
        ["Iron Kobold"]           = { "WL", "u401004", 20, 0, 0, "Kobold Mines", "Uncommon" },
        ["Primal Minotaur"]       = { "WL", "u2167023", 40, 0, 30, "Hidden Plateau", "Uncommon" },
        ["goblin"]                = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        ["kobold"]                = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        ["manticore"]             = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        ["rat"]                   = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        ["rolton"]                = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        ["thrak"]                 = { "WL", "u7122101", 15, 0, 0, "", "Common" },
        -- Solhaven (SH)
        ["Deathless Knight"]      = { "SH", "u4900308", 0, 0, 0, "Dark Cavern", "Legendary" },
        ["Demonic Echo"]          = { "SH", "u319140", 65, 0, 40, "Bonespear Tower", "Legendary" },
        ["Dwarven Zealot"]        = { "SH", "u2130205", 0, 0, 0, "Cairnfang", "Legendary" },
        ["Fledgling Kraken"]      = { "SH", "u4202110", 0, 0, 0, "Vornavian Coast", "Legendary" },
        ["Oceanic Oracle"]        = { "SH", "u4902101", 0, 0, 0, "Solhaven", "Legendary" },
        ["alleycat"]              = { "SH", "u7124101", 0, 0, 0, "", "Common" },
        ["daggerbeak"]            = { "SH", "u7124101", 0, 0, 0, "", "Common" },
        ["hound"]                 = { "SH", "u7124101", 0, 0, 0, "", "Common" },
        -- Teras (TE)
        ["Drowned Lover"]         = { "TE", "u3011007", 101, 20, 0, "Kharam Dzu", "Legendary" },
        ["Glaesine Horror"]       = { "TE", "u3051026", 80, 0, 50, "Glaes Caverns", "Legendary" },
        ["Mistwood Treant"]       = { "TE", "u3021001", 40, 0, 0, "Greymist Wood", "Legendary" },
        ["Phoenix Hatchling"]     = { "TE", "u3023107", 100, 0, 80, "The F'Eyrie", "Legendary" },
        ["Saltsinger"]            = { "TE", "u3031107", 100, 100, 0, "Nelemar", "Legendary" },
        ["cinder wasp"]           = { "TE", "u7123101", 0, 0, 0, "", "Common" },
        ["fire elemental"]        = { "TE", "u7123101", 0, 0, 0, "", "Common" },
        -- Icemule (IM)
        ["Ancient Jeweler"]       = { "IM", "u4130016", 30, 0, 0, "Icemule, Ruins", "Legendary" },
        ["Stunted Firemage"]      = { "IM", "u4045251", 20, 0, 0, "Subterranean Tunnels", "Legendary" },
        ["Titanic Shaman"]        = { "IM", "u4044138", 30, 0, 0, "Off the trail", "Legendary" },
        ["penguin"]               = { "IM", "u7133001", 0, 0, 0, "", "Common" },
        ["timber wolf"]           = { "IM", "u7133001", 0, 0, 0, "", "Common" },
        -- River's Rest (RR)
        ["Dread Stallion"]        = { "RR", "u2103003", 5, 0, 0, "Citadel Stables", "Legendary" },
        ["Master Arcanist"]       = { "RR", "u377327", 65, 0, 0, "Citadel", "Legendary" },
        ["aardvark"]              = { "RR", "u7125101", 0, 0, 0, "", "Common" },
        ["chimera"]               = { "RR", "u7125101", 0, 0, 0, "", "Common" },
        -- Ta'Illistim (TI)
        ["Great Machinist"]       = { "TI", "u13021038", 80, 0, 0, "Maaghara Tower", "Legendary" },
        ["Lady of Skulls"]        = { "TI", "u13300080", 80, 0, 0, "Temple Wyneb", "Legendary" },
        ["griffin"]               = { "TI", "u13017097", 0, 0, 0, "", "Common" },
        ["kiramon"]               = { "TI", "u13017097", 0, 0, 0, "", "Common" },
    }

    for name, data in pairs(beasts_data) do
        spirit_beasts[name] = {
            own = false,
            location = data[1], room = data[2], cap_level = data[3],
            swim = data[4], climb = data[5], area = data[6], rarity = data[7],
            level = 0, exp_to_next = 0, class = " ", element = " ",
            loyalty = " ", loyalty_n = 0, quality = " ", quality_n = 0,
            power = 0, defense = 0, insight = 0, accuracy = 0, speed = 0,
            rarity_n = ({ Common = 1, Uncommon = 2, Legendary = 3 })[data[7]] or 0,
        }
    end
end

local function beast_inventory()
    local beast_list = {}
    put("beast list all")
    local recording = false
    local count = 0
    while true do
        local line = get()
        if not line then break end
        if line:find("You have bound the following") then
            recording = true
        elseif line:find("You have bound a total of") then
            break
        elseif recording and #line > 1 then
            table.insert(beast_list, line:match("^%s*(.-)%s*$"))
        end
        count = count + 1
        if count > 200 then break end
    end
    return beast_list
end

local function beast_info(spirit_name)
    local result = quiet_command("beast info " .. spirit_name, "The Spirit Beast")
    if not result then return end

    local mob_name = nil
    for _, line in ipairs(result) do
        local rarity_match, name_match, level_match = line:match("The Spirit Beast is an? (%w+) (.+) of (%d+) training")
        if name_match then
            mob_name = name_match
            if not spirit_beasts[mob_name] then
                spirit_beasts[mob_name] = {
                    own = true, location = "", room = "",
                    cap_level = 0, swim = 0, climb = 0, area = "", rarity = "",
                    level = 0, exp_to_next = 0, class = " ", element = " ",
                    loyalty = " ", loyalty_n = 0, quality = " ", quality_n = 0,
                    power = 0, defense = 0, insight = 0, accuracy = 0, speed = 0, rarity_n = 0,
                }
            end
            spirit_beasts[mob_name].level = tonumber(level_match) or 0
            spirit_beasts[mob_name].own = true
        end
        if mob_name then
            local val
            val = line:match("Exp%. to Next:%s+(%d+)")
            if val then spirit_beasts[mob_name].exp_to_next = tonumber(val) end

            val = line:match("Class:%s+(%S+)")
            if val then spirit_beasts[mob_name].class = val end

            val = line:match("Element:%s+(%S+)")
            if val then spirit_beasts[mob_name].element = val end

            val = line:match("Rarity:%s+(%S+)")
            if val then
                spirit_beasts[mob_name].rarity = val
                spirit_beasts[mob_name].rarity_n = ({ Common = 1, Uncommon = 2, Legendary = 3 })[val] or 0
            end

            val = line:match("Loyalty:%s+(%S+)")
            if val then
                spirit_beasts[mob_name].loyalty = val
                spirit_beasts[mob_name].loyalty_n = ({ Disinterested = 1, Average = 2, High = 3, Exceptional = 4 })[val] or 0
            end

            val = line:match("Quality:%s+(%S+)")
            if val then
                spirit_beasts[mob_name].quality = val
                spirit_beasts[mob_name].quality_n = ({ Unimpressive = 1, Average = 2, Robust = 3, Perfect = 4, Extraordinary = 5 })[val] or 0
            end

            val = line:match("Power:%s+%S+%s+%S+%s+(%d+)")
            if val then spirit_beasts[mob_name].power = tonumber(val) end

            val = line:match("Defense:%s+%S+%s+%S+%s+(%d+)")
            if val then spirit_beasts[mob_name].defense = tonumber(val) end

            val = line:match("Insight:%s+%S+%s+%S+%s+(%d+)")
            if val then spirit_beasts[mob_name].insight = tonumber(val) end

            val = line:match("Accuracy:%s+%S+%s+%S+%s+(%d+)")
            if val then spirit_beasts[mob_name].accuracy = tonumber(val) end

            val = line:match("Speed:%s+%S+%s+%S+%s+(%d+)")
            if val then spirit_beasts[mob_name].speed = tonumber(val) end

            if line:find("^Appearance and Attacks$") then break end
        end
    end
end

local function rarity_stars(n)
    return string.rep("@", n)
end

local function display_beasts(sort_type, filter_rarity)
    local items = {}
    for name, v in pairs(spirit_beasts) do
        if sort_type == "collection" then
            if not filter_rarity or filter_rarity == "All" or v.rarity == filter_rarity then
                table.insert(items, { name = name, data = v })
            end
        elseif v.own then
            table.insert(items, { name = name, data = v })
        end
    end

    if sort_type == "echo" then
        table.sort(items, function(a, b)
            if a.data.level ~= b.data.level then return a.data.level < b.data.level end
            if a.data.quality_n ~= b.data.quality_n then return a.data.quality_n < b.data.quality_n end
            return a.name < b.name
        end)
    elseif sort_type == "element" then
        table.sort(items, function(a, b)
            if a.data.element ~= b.data.element then return a.data.element < b.data.element end
            if a.data.level ~= b.data.level then return a.data.level < b.data.level end
            return a.name < b.name
        end)
    elseif sort_type == "class" then
        table.sort(items, function(a, b)
            if a.data.class ~= b.data.class then return a.data.class < b.data.class end
            if a.data.level ~= b.data.level then return a.data.level < b.data.level end
            return a.name < b.name
        end)
    elseif sort_type == "collection" then
        table.sort(items, function(a, b)
            if a.data.location ~= b.data.location then return a.data.location < b.data.location end
            if a.data.rarity_n ~= b.data.rarity_n then return a.data.rarity_n > b.data.rarity_n end
            return a.name < b.name
        end)
    end

    -- Header
    local hdr = string.format("| %22s | %2s %-9s | %2s %4s | %10s | %9s |%3s|%5s|%4s| %3s | %3s | %3s | %3s | %3s |",
        "Name", "", "Room", "Lv", "TNL", "Class", "Element", "Rar", "Qulty", "Loyl", "Pow", "Def", "Ins", "Acc", "Spd")
    local sep = "|" .. string.rep("=", #hdr - 2) .. "|"

    respond(sep)
    respond(hdr)
    respond(sep)

    local count = 0
    local last_group = nil
    for _, item in ipairs(items) do
        local v = item.data
        local group_key
        if sort_type == "element" then group_key = v.element
        elseif sort_type == "class" then group_key = v.class
        elseif sort_type == "collection" then group_key = v.location
        else group_key = nil
        end

        if group_key and group_key ~= last_group then
            if count > 0 then respond(sep) end
            respond(hdr)
            respond(sep)
            last_group = group_key
            count = 0
        end

        local own_marker = v.own and "" or " "
        respond(string.format("| %22s | %2s %-9s | %2s %4s | %10s | %9s |%3s|%5s|%4s| %3s | %3s | %3s | %3s | %3s |",
            item.name, v.location, v.room, v.level, v.exp_to_next,
            v.class, v.element, rarity_stars(v.rarity_n), rarity_stars(v.quality_n),
            rarity_stars(v.loyalty_n), v.power, v.defense, v.insight, v.accuracy, v.speed))

        count = count + 1
        if count >= 20 then
            respond(sep)
            respond(hdr)
            respond(sep)
            count = 0
        end
    end
    respond(sep)
    respond("")
    respond(" Owned: " .. #items .. " beasts")
    respond("")
end

local function beast_sense()
    fput("beast sense")
    local found = {}
    local recording = false
    local count = 0
    while true do
        local line = get()
        if not line then break end
        if line:find("too civilized") or line:find("will need to wait") then
            echo("Cannot sense here or cooldown active.")
            return found
        end
        if line:find("You focus your thoughts") then recording = true end
        if line:find("Roundtime") then break end

        if recording then
            local rarity, mob = line:match("presence of an? (%w+) (.+) spirit")
            if mob then
                table.insert(found, mob)
            end
            local legendary = line:match("legendary spirit: the (.+)!")
            if legendary then
                table.insert(found, legendary)
            end
        end
        count = count + 1
        if count > 50 then break end
    end
    return found
end

-- Element weakness table
local element_weakness = {
    Air    = { weakest = "Spirit", weak = "Fire", strong = "Water", strongest = "Earth" },
    Earth  = { weakest = "Air", weak = "Water", strong = "Fire", strongest = "Spirit" },
    Fire   = { weakest = "Water", weak = "Earth", strong = "Air", strongest = "Spirit" },
    Spirit = { weakest = "Fire", weak = "Earth", strong = "Water", strongest = "Air" },
    Water  = { weakest = "Spirit", weak = "Air", strong = "Earth", strongest = "Fire" },
}

-- Main
local arg1 = (Script.vars[1] or ""):lower()
local arg2 = Script.vars[2]

if arg1 == "help" or arg1 == "setup" then
    echo("")
    echo("Spirit Beasts by Deathravin")
    echo("")
    echo("Usage:")
    echo("  ;spiritbeast              - Gather info and display all owned beasts")
    echo("  ;spiritbeast info         - Re-gather info on all captured beasts")
    echo("  ;spiritbeast echo         - Display owned beasts (sorted by level)")
    echo("  ;spiritbeast element      - Display owned beasts sorted by element")
    echo("  ;spiritbeast class        - Display owned beasts sorted by class")
    echo("  ;spiritbeast collection   - Display full collection status")
    echo("  ;spiritbeast capture      - Capture beast in current room")
    echo("  ;spiritbeast capture <area> - Go capture in area (WL, SH, TE, etc.)")
    echo("  ;spiritbeast reset        - Clear all beast data")
    echo("  ;spiritbeast help         - Show this help")
    return
end

if arg1 == "reset" then
    reset_beasts()
    echo("Spirit beast data cleared.")
    return
end

-- Default: gather info on all beasts
if arg1 == "" or arg1 == "info" then
    reset_beasts()
    local owned = beast_inventory()
    echo("Found " .. #owned .. " owned beasts. Gathering info...")
    for _, spirit_name in ipairs(owned) do
        beast_info(spirit_name)
        pause(0.25)
    end
    display_beasts("echo")

elseif arg1 == "echo" then
    display_beasts("echo")

elseif arg1 == "element" or arg1 == "type" or arg1 == "types" then
    display_beasts("element")

elseif arg1 == "class" then
    display_beasts("class")

elseif arg1:match("^col") then
    display_beasts("collection", arg2 or "All")

elseif arg1:match("^cap") then
    local sensed = beast_sense()
    if #sensed > 0 then
        echo("Sensed beasts:")
        for _, name in ipairs(sensed) do
            echo("  " .. name)
        end
        echo("")
        echo("Use BEAST CAPTURE <name> to capture one.")
    else
        echo("No beasts sensed in this area.")
    end
end
