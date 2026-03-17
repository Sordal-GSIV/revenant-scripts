--- @revenant-script
--- name: killtracker
--- version: 2.10
--- author: Alastir
--- contributors: Nisugi
--- game: gs
--- description: Tracks gemstones, dust, jewels, kills, and creature data
--- tags: hunting,combat,tracking,gemstones,jewels,dust,klocks,data
---
--- Changelog (from Lich5):
---   v2.10 - Fixed search tracking for dust when not eligible for jewel
---   v2.9  - Corrected corsair search name
---   v2.8  - Corrected validation, handles search # as timestamp
---   v2.7  - Sailor's Grief creatures added
---   v2.6  - Major performance optimizations, fixed eligibility system
---
--- Usage:
---   ;killtracker           -- start tracking
---   ;killtracker help      -- show help
---   ;killtracker report    -- show current report
---   ;killtracker reset     -- reset tracking data

--------------------------------------------------------------------------------
-- Settings & Data
--------------------------------------------------------------------------------

local SCRIPT_NAME = "killtracker"

local function load_data()
    local raw = CharSettings["killtracker_data"]
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    return {
        kills = {},
        searches = {},
        gems = {},
        dust = 0,
        jewels = {},
        total_kills = 0,
        total_searches = 0,
        session_start = os.time(),
        last_reset = os.time(),
    }
end

local function save_data(data)
    CharSettings["killtracker_data"] = Json.encode(data)
end

local data = load_data()

--------------------------------------------------------------------------------
-- Creature Database
--------------------------------------------------------------------------------

local SEARCH_VERBS = {
    "search", "loot", "skin",
}

--------------------------------------------------------------------------------
-- Tracking Patterns
--------------------------------------------------------------------------------

local KILL_PATTERNS = {
    "The (%S+.-) falls to the ground dead",
    "The (%S+.-) collapses and dies",
    "The (%S+.-) crumbles to the ground",
    "The (%S+.-) goes still",
    "The (%S+.-) slumps to the ground",
    "The (%S+.-) expires",
}

local GEM_PATTERN = "You notice (?:a|an|some) (.+) inside"
local DUST_PATTERN = "crumbles into a pile of dust"
local JEWEL_PATTERN = "(?:a|an) (.+jewel.+)"
local SEARCH_PATTERN = "You search the"
local NO_FIND_PATTERN = "You find nothing"

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

local function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

local function show_report()
    local elapsed = os.time() - data.session_start

    respond("")
    respond("=== Killtracker Report ===")
    respond(string.format("  Session Duration: %s", format_time(elapsed)))
    respond(string.format("  Total Kills:      %d", data.total_kills))
    respond(string.format("  Total Searches:   %d", data.total_searches))
    respond(string.format("  Dust Found:       %d", data.dust))
    respond("")

    if next(data.kills) then
        respond("  -- Kills by Creature --")
        local sorted = {}
        for name, cnt in pairs(data.kills) do
            table.insert(sorted, { name = name, count = cnt })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, entry in ipairs(sorted) do
            respond(string.format("    %-40s %d", entry.name, entry.count))
        end
        respond("")
    end

    if next(data.gems) then
        respond("  -- Gems Found --")
        local sorted = {}
        for name, cnt in pairs(data.gems) do
            table.insert(sorted, { name = name, count = cnt })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for _, entry in ipairs(sorted) do
            respond(string.format("    %-40s %d", entry.name, entry.count))
        end
        respond("")
    end

    if next(data.jewels) then
        respond("  -- Jewels Found --")
        for name, cnt in pairs(data.jewels) do
            respond(string.format("    %-40s %d", name, cnt))
        end
        respond("")
    end

    if elapsed > 0 then
        local kpm = data.total_kills / (elapsed / 60)
        respond(string.format("  Kills/min: %.1f", kpm))
    end
    respond("==========================")
    respond("")
end

local function show_help()
    respond("")
    respond("=== Killtracker Help ===")
    respond("  ;killtracker           -- start tracking (runs in background)")
    respond("  ;killtracker help      -- show this help")
    respond("  ;killtracker report    -- show current tracking report")
    respond("  ;killtracker reset     -- reset all tracking data")
    respond("  ;killtracker status    -- show brief status")
    respond("========================")
    respond("")
end

local function reset_data()
    data = {
        kills = {},
        searches = {},
        gems = {},
        dust = 0,
        jewels = {},
        total_kills = 0,
        total_searches = 0,
        session_start = os.time(),
        last_reset = os.time(),
    }
    save_data(data)
    respond("[killtracker] Data reset.")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args = Script.args or {}
local cmd = args[1]

if cmd == "help" then
    show_help()
    return
elseif cmd == "report" then
    show_report()
    return
elseif cmd == "reset" then
    reset_data()
    return
elseif cmd == "status" then
    local elapsed = os.time() - data.session_start
    respond(string.format("[killtracker] Kills: %d | Searches: %d | Gems: %d | Dust: %d | Time: %s",
        data.total_kills, data.total_searches,
        (function() local c = 0; for _, v in pairs(data.gems) do c = c + v end; return c end)(),
        data.dust, format_time(elapsed)))
    return
end

respond("[killtracker] Tracking started. Use ;killtracker help for commands.")

on_exit(function()
    save_data(data)
end)

-- Save periodically
local last_save = os.time()

while true do
    local line = get()

    -- Track kills
    for _, pattern in ipairs(KILL_PATTERNS) do
        local creature = string.match(line, pattern)
        if creature then
            creature = creature:match("^%s*(.-)%s*$")
            data.kills[creature] = (data.kills[creature] or 0) + 1
            data.total_kills = data.total_kills + 1
            break
        end
    end

    -- Track searches
    if Regex.test(line, SEARCH_PATTERN) then
        data.total_searches = data.total_searches + 1
    end

    -- Track gems
    local gem_match = Regex.match(line, GEM_PATTERN)
    if gem_match and gem_match[1] then
        local gem_name = gem_match[1]
        data.gems[gem_name] = (data.gems[gem_name] or 0) + 1
    end

    -- Track dust
    if Regex.test(line, DUST_PATTERN) then
        data.dust = data.dust + 1
    end

    -- Track jewels
    local jewel_match = Regex.match(line, JEWEL_PATTERN)
    if jewel_match and jewel_match[1] then
        local jewel_name = jewel_match[1]
        data.jewels[jewel_name] = (data.jewels[jewel_name] or 0) + 1
    end

    -- Periodic save every 60 seconds
    if os.time() - last_save > 60 then
        save_data(data)
        last_save = os.time()
    end
end
