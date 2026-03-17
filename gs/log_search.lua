--- @revenant-script
--- name: log_search
--- version: 1.4
--- author: Nisugi
--- game: gs
--- description: Parse game logs for search statistics (gemstones and dust)
--- tags: hunting,combat,tracking,gemstones,dust,data
---
--- Changelog (from Lich5):
---   v1.4 - Added monthly/weekly gemstone and dust tracking
---   v1.3 (2025-04-08) - Reset dust search count on weekly reset
---   v1.2 (2025-03-27) - Auto-disable timestamps if none detected
---   v1.1 (2025-03-24) - Added mug for searches
---   v1.0 (2025-03-23) - Initial release
---
--- Usage: ;log_search "<directory>" [--reset] [--no-timestamps] [--debug] [--txt]
---
--- Note: This script parses local log files. Requires log files to be stored
--- in a directory accessible from your system. Uses Revenant File API.

--------------------------------------------------------------------------------
-- Settings and data
--------------------------------------------------------------------------------

local DATA_FILE = "data/log_search.json"

local function load_data()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
    return (ok and type(data) == "table") and data or {}
end

local function save_data(data)
    File.write(DATA_FILE, Json.encode(data))
end

local arg0 = Script.vars[0] or ""

if not Script.vars[1] or Script.vars[1] == "" then
    respond("Usage: ;log_search <directory> [--reset] [--no-timestamps] [--debug] [--txt]")
    respond("Example: ;log_search /path/to/logs/2024/08/")
    return
end

local data = load_data()
local do_reset = arg0:find("%-%-reset") ~= nil
local no_timestamps = arg0:find("%-%-no%-timestamps?") ~= nil
local debug_mode = arg0:find("%-%-debug") ~= nil

if do_reset then data = {} end

data.creature = data.creature or "none"
data.ascension_searches = data.ascension_searches or 0
data.weekly_ascension_searches = data.weekly_ascension_searches or 0
data.searches_since_jewel = data.searches_since_jewel or 0
data.searches_since_dust = data.searches_since_dust or 0
data.jewel_found = data.jewel_found or {}
data.dust_found = data.dust_found or {}
data.monthly_gemstones = data.monthly_gemstones or 0
data.weekly_gemstone = data.weekly_gemstone or 0
data.weekly_dust = data.weekly_dust or 0
data.quest_complete = data.quest_complete or false

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local SEARCH_CREATURE_RX = Regex.new("You search the .+?\\.$")
local SEARCH_MUG_RX = Regex.new("Taking advantage of the scuffle")
local FOUND_DUST_RX = Regex.new("You notice a scintillating mote of gemstone dust")
local FOUND_GEMSTONE_RX = Regex.new("A glint of light catches your eye, and you notice an? (.+?) at your feet!")
local QUEST_COMPLETE_RX = Regex.new("The fallen sybil's power lingers")

local ASCENSION_CREATURES = Regex.new(table.concat({
    "armored battle mastodon", "black valravn", "boreal undansormr",
    "crimson angargeist", "fork-tongued wendigo", "giant warg",
    "gigas berserker", "gigas disciple", "gigas shield-maiden",
    "gigas skald", "gold-bristled hinterboar", "gorefrost golem",
    "halfling bloodspeaker", "halfling cannibal", "reptilian mutant",
    "sanguine ooze", "shadow-cloaked draugr", "winged disir",
    "basalt grotesque", "death knight", "mist-wreathed banshee",
    "patrician vampire", "phantasmic conjurer", "skeletal dreadsteed",
    "tatterdemalion ghast", "hive thrall", "kiramon broodtender",
    "kiramon myrmidon", "kiramon stalker", "kiramon strandweaver",
    "kresh ravager",
}, "|"))

--------------------------------------------------------------------------------
-- File parsing
--------------------------------------------------------------------------------

local dir = Script.vars[1]:gsub("\\", "/")
local pattern = dir .. "/*.log"
if arg0:find("%-%-txt") then pattern = dir .. "/*.txt" end

respond("Parsing files from: " .. pattern)

-- Note: In Revenant, file glob support may be limited.
-- This is a simplified version that reads the directory.
local files = File.glob(pattern) or {}

if #files == 0 then
    respond("No files found matching: " .. pattern)
    save_data(data)
    return
end

respond("Found " .. #files .. " file(s) to parse.")

local total_searches = 0

for _, filepath in ipairs(files) do
    if debug_mode then respond("Parsing: " .. filepath) end

    local content = File.read(filepath)
    if content then
        for line in content:gmatch("[^\n]+") do
            local stripped = line:gsub("<.->", "")

            if QUEST_COMPLETE_RX:test(stripped) then
                data.quest_complete = true
            end

            if FOUND_GEMSTONE_RX:test(stripped) then
                local m = FOUND_GEMSTONE_RX:match(stripped)
                if m then
                    data.monthly_gemstones = data.monthly_gemstones + 1
                    data.weekly_gemstone = data.weekly_gemstone + 1
                    local key = tostring(data.ascension_searches)
                    data.jewel_found[key] = {
                        searches_since = data.searches_since_jewel,
                        name = m[1],
                        creature = data.creature,
                    }
                    respond("Jewel found: " .. m[1] .. " (searches since last: " .. data.searches_since_jewel .. ")")
                    data.searches_since_jewel = 0
                end
            elseif FOUND_DUST_RX:test(stripped) then
                data.weekly_dust = data.weekly_dust + 1
                local key = tostring(data.ascension_searches)
                data.dust_found[key] = {
                    searches_since = data.searches_since_dust,
                    creature = data.creature,
                }
                respond("Dust found (searches since last: " .. data.searches_since_dust .. ")")
                data.searches_since_dust = 0
            elseif SEARCH_CREATURE_RX:test(stripped) or SEARCH_MUG_RX:test(stripped) then
                -- Extract creature name (simplified)
                local creature = stripped:match("You search the (.+)%.$")
                if creature then
                    data.creature = creature:gsub("<.->", "")
                end
                if ASCENSION_CREATURES:test(data.creature) and data.quest_complete then
                    data.ascension_searches = data.ascension_searches + 1
                    data.weekly_ascension_searches = data.weekly_ascension_searches + 1
                    data.searches_since_jewel = data.searches_since_jewel + 1
                    data.searches_since_dust = data.searches_since_dust + 1
                    total_searches = total_searches + 1
                end
            end
        end
    end
end

save_data(data)

respond("")
respond("Parsing complete.")
respond("Total ascension searches found: " .. data.ascension_searches)
respond("Gemstones found: " .. (function()
    local n = 0; for _ in pairs(data.jewel_found) do n = n + 1 end; return n
end)())
respond("Dust found: " .. (function()
    local n = 0; for _ in pairs(data.dust_found) do n = n + 1 end; return n
end)())
respond("Data saved to: " .. DATA_FILE)
