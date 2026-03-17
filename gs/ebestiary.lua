--- @revenant-script
--- name: ebestiary
--- version: 2.0.0
--- author: Ramparts (ported to Revenant)
--- description: GemStone IV creature lookup by level, type, or name
--- tags: hunting,creatures,reference
--- depends: lib/args,lib/table_render

local args_lib = require("lib/args")
local TableRender = require("lib/table_render")

local BASE_URL = "https://gswiki.play.net"
local DATA_FILE = "data/gs/creatures.json"

local NAME_OVERRIDES = {
    ["Nasty little gremlin"]       = "nasty little red gremlin",
    ["Myklian"]                    = "red myklian",
    ["Decaying citadel guardsman"] = "decaying Citadel guardsman",
    ["Rotting citadel arbalester"] = "rotting Citadel arbalester",
    ["Putrefied citadel herald"]   = "putrefied Citadel herald",
    ["Supple ivasian inciter"]     = "supple Ivasian inciter",
    ["Magna vereri"]               = "voluptuous magna vereri",
    ["Bony tenthsworn occultist"]  = "bony Tenthsworn occultist",
    ["Crackling lightning fiend"]  = "lightning fiend",
    ["Stooped titan stormcaller"]  = "titan stormcaller",
    ["Titan tempest tyrant"]       = "tempest tyrant",
    ["Haggard veiki herald"]       = "Veiki herald",
    ["Silver-scaled cold wyrm"]    = "azure-scaled cold wyrm",
}

local function get_noun(name)
    return name:match("(%S+)$") or name
end

local function classify_creature(creature_name)
    local name = NAME_OVERRIDES[creature_name] or creature_name
    local noun = get_noun(name)

    local permutations = {
        {noun, name},
        {noun:lower(), name:lower()},
        {noun:sub(1,1):upper() .. noun:sub(2), name:sub(1,1):upper() .. name:sub(2)},
        {noun:lower(), name},
    }

    for _, perm in ipairs(permutations) do
        local t = GameObj.classify(perm[1], perm[2])
        if t and t ~= "" then
            local types = {}
            for part in t:gmatch("[^,]+") do
                local trimmed = part:match("^%s*(.-)%s*$")
                if trimmed ~= "aggressive npc" then
                    types[#types + 1] = trimmed
                end
            end
            if #types > 0 then
                return table.concat(types, ", ")
            end
        end
    end

    return "UNKNOWN"
end

local function get_creatures_at_level(creatures, level)
    local result = {}
    for cname, info in pairs(creatures) do
        if info.level == level then
            result[#result + 1] = {
                name = cname,
                level = info.level,
                link = BASE_URL .. info.link,
            }
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function run()
    local parsed = args_lib.parse(Script.vars[0] or "")
    local raw_args = Script.vars[0] or ""

    for _, a in ipairs(parsed.args) do
        if a:lower() == "help" then
            respond("Usage:")
            respond("    ;ebestiary              -- creatures at your level +/-5")
            respond("    ;ebestiary 20           -- creatures at level 20")
            respond("    ;ebestiary 5 10         -- creatures at levels 5-10")
            respond("    ;ebestiary 20 undead    -- level 20 undead creatures")
            respond("    ;ebestiary 5 10 orc     -- orcs between levels 5-10")
            return
        end
    end

    local raw = File.read(DATA_FILE)
    if not raw then
        echo("Creature database not found: " .. DATA_FILE)
        echo("Place creatures.json in data/")
        return
    end
    local ok, creatures = pcall(Json.decode, raw)
    if not ok or type(creatures) ~= "table" then
        echo("Error parsing creature database")
        return
    end

    local levels = {}
    for num in raw_args:gmatch("(%d+)") do
        levels[#levels + 1] = tonumber(num)
    end

    local filter_words = {}
    for word in raw_args:gmatch("([a-zA-Z'-]+)") do
        if not word:match("^%d+$") then
            filter_words[#filter_words + 1] = word:lower()
        end
    end

    local min_level, max_level
    if #levels == 0 then
        local current = Stats.level or 1
        min_level = math.max(1, current - 5)
        max_level = current + 5
    elseif #levels == 1 then
        min_level = levels[1]
        max_level = levels[1]
    else
        min_level = math.min(levels[1], levels[2])
        max_level = math.max(levels[1], levels[2])
    end

    if max_level - min_level > 20 then
        echo("Too many levels requested (max range: 20). Try a smaller range.")
        return
    end

    local tbl = TableRender.new({"Level", "Creature", "Types", "Wiki Link"})
    local count = 0
    local prev_level = nil

    for level = min_level, max_level do
        local mobs = get_creatures_at_level(creatures, level)
        for _, mob in ipairs(mobs) do
            local types = classify_creature(mob.name)

            local show = true
            if #filter_words > 0 then
                show = false
                if types == "UNKNOWN" then
                    show = true
                else
                    for _, word in ipairs(filter_words) do
                        if types:lower():find(word, 1, true) or mob.name:lower():find(word, 1, true) then
                            show = true
                            break
                        end
                    end
                end
            end

            if show then
                if prev_level and level ~= prev_level then
                    tbl:add_separator()
                end
                tbl:add_row({tostring(level), mob.name, types, mob.link})
                prev_level = level
                count = count + 1
            end
        end
    end

    if count == 0 then
        respond("No creatures found for the given criteria.")
    else
        for line in tbl:render():gmatch("[^\n]+") do
            respond(line)
        end
    end
end

run()
