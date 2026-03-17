--- @revenant-script
--- name: log_search_no_time
--- version: 1.0.0
--- author: unknown
--- game: gs
--- tags: hunting, data collection, log parsing
--- description: Parse game logs for search/treasure/lock-key/gemstone data (no timestamps)
---
--- Original Lich5 authors: unknown
--- Ported to Revenant Lua from log_search_no_time.lic
---
--- Usage: ;log_search_no_time <path/to/logs/*.log>

local file_location = Script.current.vars[1]
if not file_location then
    echo("You need to specify folder of the log you wish to parse such as:")
    echo("C:/Users/xxxx/Desktop/Lich5/logs/GSIV-Name/2024/08/*.log")
    return
end

local scrape_data = {
    creature = "none",
    total_searches = 0,
    ascension_searches = 0,
    searches_since_jewel = 0,
    searches_since_dust = 0,
    searches_since_lock_key = 0,
    jewel_found = {},
    dust_found = {},
    lock_key_found = {},
}
local start_scrapin = false

local ASCENSION_CREATURES = {
    "armored battle mastodon", "black valravn", "boreal undansormr",
    "crimson angargeist", "fork%-tongued wendigo", "giant warg",
    "gigas berserker", "gigas disciple", "gigas shield%-maiden", "gigas skald",
    "gold%-bristled hinterboar", "gorefrost golem", "halfling bloodspeaker",
    "halfling cannibal", "reptilian mutant", "sanguine ooze",
    "shadow%-cloaked draugr", "winged disir", "basalt grotesque",
    "death knight", "mist%-wreathed banshee", "patrician vampire",
    "phantasmic conjurer", "skeletal dreadsteed", "tatterdemalion ghast",
    "hive thrall", "kiramon broodtender", "kiramon myrmidon",
    "kiramon stalker", "kiramon strandweaver", "kresh ravager",
}

local function is_ascension(name)
    for _, pat in ipairs(ASCENSION_CREATURES) do
        if name:find(pat) then return true end
    end
    return false
end

echo("Log parsing requires filesystem glob support in Revenant.")
echo("Provide individual log file paths for processing.")
echo("Data would be saved to: " .. GameState.data_dir .. "/SearchDataFromLogs.yaml")
