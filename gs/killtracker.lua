--- @revenant-script
--- name: killtracker
--- version: 2.10
--- author: Alastir
--- contributors: Nisugi
--- game: gs
--- description: Tracks ascension creature searches, gemstone jewels, and dust finds with weekly/monthly eligibility and cross-character reporting
--- tags: hunting,combat,tracking,gemstones,jewels,dust,klocks,data
--- @lic-certified: complete 2026-03-20
---
--- Changelog (from Lich5):
---   v2.10 (2025-09-21) - Fixed search tracking for dust when not eligible for jewel;
---                        fixed cross character jewel eligibility reporting
---   v2.9  (2025-09-16) - Corrected corsair search name
---   v2.8  (2025-09-15) - Corrected validation; handles search # as timestamp
---   v2.7  (2025-09-14) - Sailor's Grief creatures added
---   v2.6  (2025-08-23) - Major performance optimizations; adaptive sleep; fixed eligibility;
---                        simplified timezone (ET); improved cross-char eligibility;
---                        enhanced reports; optimized backups; robust reset validation;
---                        added debug mode; code cleanup; removed deprecated fields;
---                        added backup/restore; comprehensive error handling;
---                        standardized timestamps as integers; data validation before saves;
---                        atomic weekly resets
---
--- Usage:
---   ;killtracker help              -- show help
---   ;killtracker summary           -- summary for the week
---   ;killtracker jewel report      -- find report of all jewels
---   ;killtracker dust report       -- find report of all dust
---   ;killtracker gemstones report [N] -- find report by week (optional last N weeks)
---   ;killtracker eligible [prof]   -- cross-character eligibility
---   ;killtracker announce          -- toggle kill-by-kill announcements
---   ;killtracker announce msg      -- toggle announcement style
---   ;killtracker submit finds      -- toggle Google Sheets submission
---   ;killtracker save              -- force save to file
---   ;killtracker backup            -- create a manual backup
---   ;killtracker restore backup    -- restore from latest backup
---   ;killtracker validate          -- check data integrity
---   ;killtracker fix find count    -- recalculate monthly/weekly counts
---   Also aliased as: ;kt ...

no_kill_all()
no_pause_all()

local T = require("lib/table_render")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SCRIPT_NAME = Script.name or "killtracker"
local CHAR_NAME   = Char.name or "unknown"

-- Sandboxed data paths (relative to scripts dir)
local DATA_DIR   = "data/gs/" .. CHAR_NAME
local DATA_FILE  = DATA_DIR .. "/killtracker.json"
local BACKUP_DIR = DATA_DIR .. "/killtracker_backups"
local ELIG_FILE  = "data/gs/jewel_eligibility.json"

local DS_HOOK_ID = SCRIPT_NAME .. "::downstream"
local US_HOOK_ID = SCRIPT_NAME .. "::upstream"

local SHEETS_URL = "https://script.google.com/macros/s/" ..
    "AKfycbyltG_Eax1-CY4n1isy9U_ZRlKxD93Ai5XQqbF78Wq-4tIqtFirLjbVcgrd13T59e6z/exec"

-- Ascension creatures (PCRE alternation)
local ASCENSION_RE = Regex.new(
    "armored battle mastodon|black valravn|boreal undansormr|" ..
    "crimson angargeist|fork-tongued wendigo|giant warg|" ..
    "gigas berserker|gigas disciple|gigas shield-maiden|gigas skald|" ..
    "gold-bristled hinterboar|gorefrost golem|halfling bloodspeaker|halfling cannibal|" ..
    "reptilian mutant|sanguine ooze|shadow-cloaked draugr|winged disir|" ..
    "basalt grotesque|death knight|mist-wreathed banshee|patrician vampire|" ..
    "phantasmic conjurer|skeletal dreadsteed|tatterdemalion ghast|" ..
    "hive thrall|kiramon broodtender|kiramon myrmidon|kiramon stalker|" ..
    "kiramon strandweaver|kresh ravager|lightning whelk|needle-toothed trenchling|" ..
    "coral golem|stormborn primordial|corsair|steelwing harpy|bilge mass|" ..
    "drowned mariner|revenant buccaneer|wraith shark|humpbacked merrow|" ..
    "fog-cloaked kelpie|kraken tentacle|merrow oracle")

-- Downstream XML patterns
local FOUND_GEMSTONE_RE = Regex.new(
    [=[<pushBold/> \*\* A glint of light catches your eye, and you notice an? ]=] ..
    [=[<a exist="\d+" noun="\w+">(?<n>[^<]+)</a> at your feet! \*\*]=])

local FOUND_DUST_RE = Regex.new(
    [=[<pushBold/>You notice a scintillating mote of gemstone dust on the ground and gather it quickly\.]=])

local SEARCH_CREATURE_RE = Regex.new(
    [=[You search the <pushBold/><a exist="\d+" noun="[^"]+">(?<creature>[^<]+)</a><popBold/>\.]=])

local SEARCH_MUG_RE = Regex.new(
    [=[Taking advantage of the scuffle, you roughly pat (?:<.+?>)?the (?:<.+?>)?(?<creature>[-A-Za-z ]+)(?:<.+?>)? down for hidden valuables!]=])

local EVIL_EYE_RE = Regex.new(
    [=[The <pushBold/><a exist="\d+" noun="[^"]+">(?<creature>[^<]+)</a><popBold/> turns and runs screaming into the distance, never to be seen again\.]=])

local CMD_RX = Regex.new([=[(?i)^(?:<c>)?;(?:killtracker|kt)(?:\s+(.*))?$]=])

--------------------------------------------------------------------------------
-- Simple table-based FIFO queues
--------------------------------------------------------------------------------

local cmd_queue    = {}
local report_queue = {}

local function qpush(q, v)  q[#q + 1] = v end
local function qpop(q)      return #q > 0 and table.remove(q, 1) or nil end
local function qempty(q)    return #q == 0 end

--------------------------------------------------------------------------------
-- Timezone: US Eastern (EST = UTC-5, EDT = UTC-4)
--------------------------------------------------------------------------------

-- Leap years strictly before y
local function leap_before(y)
    y = y - 1
    return math.floor(y/4) - math.floor(y/100) + math.floor(y/400)
end

-- Pure UTC timestamp (no local timezone dependency)
local function mkutc(y, m, d, h, mi, s)
    h = h or 0; mi = mi or 0; s = s or 0
    local leap = (y%4==0 and (y%100~=0 or y%400==0))
    local mdays = {31, leap and 29 or 28, 31,30,31,30,31,31,30,31,30,31}
    local days  = (y - 1970) * 365 + (leap_before(y) - leap_before(1970))
    for i = 1, m-1 do days = days + mdays[i] end
    days = days + d - 1
    return days * 86400 + h * 3600 + mi * 60 + s
end

-- nth Sunday (n=1,2,...) of a UTC month, returned as day-of-month
local function nth_sunday(year, month, n)
    local d = os.date("!*t", mkutc(year, month, 1, 12))
    -- wday: 1=Sun in Lua; (8 - wday) % 7 gives days until first Sunday
    local first_sun = 1 + (8 - d.wday) % 7
    return first_sun + (n - 1) * 7
end

-- ET offset in seconds for a given UTC timestamp
local function et_offset(ts)
    local d = os.date("!*t", ts)
    local y, m = d.year, d.month
    if m > 3 and m < 11 then return -4 * 3600 end  -- definitely EDT
    if m < 3  or  m > 11 then return -5 * 3600 end  -- definitely EST
    if m == 3 then
        -- Spring forward: 2nd Sunday March 2am EST = 7am UTC
        local spring = mkutc(y, 3, nth_sunday(y, 3, 2), 7)
        return ts >= spring and -4 * 3600 or -5 * 3600
    end
    -- November: Fall back: 1st Sunday Nov 2am EDT = 6am UTC
    local fall = mkutc(y, 11, nth_sunday(y, 11, 1), 6)
    return ts < fall and -4 * 3600 or -5 * 3600
end

-- Format UTC timestamp as Eastern Time display string
local function fmt_et(ts)
    return os.date("!%m/%d %H:%M ET", ts + et_offset(ts))
end

-- Current broken-down time in ET (fields: year, month, day, hour, min, sec, wday)
local function et_now()
    local ts = os.time()
    return os.date("!*t", ts + et_offset(ts))
end

-- Week-of-year (Sunday-based, %U) for a UTC timestamp in Eastern Time
local function et_week(ts)
    return tonumber(os.date("!%U", ts + et_offset(ts)))
end

-- Next Sunday midnight ET expressed as UTC timestamp
local function next_sunday_midnight_utc()
    local now = os.time()
    local off = et_offset(now)
    local d   = os.date("!*t", now + off)
    local days_since_sun = d.wday - 1  -- wday 1=Sun
    local last_sun_et = (now + off)
                      - days_since_sun * 86400
                      - d.hour  * 3600
                      - d.min   * 60
                      - d.sec
    return last_sun_et + 7 * 86400 - off
end

-- Number with thousands commas
local function comma(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then return "-" .. comma(-n) end
    local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return s:gsub("^,", "")
end

--------------------------------------------------------------------------------
-- Data: normalize + load + save
--------------------------------------------------------------------------------

-- After JSON round-trip, event table keys become strings; convert back to ints
local function normalize_events(events)
    if type(events) ~= "table" then return {} end
    local out = {}
    for k, v in pairs(events) do
        local ki = tonumber(k)
        if ki and type(v) == "table" then
            v.searches_since = tonumber(v.searches_since) or 0
            v.searches_week  = tonumber(v.searches_week)  or 0
            v.room           = tostring(v.room or "")
            out[ki] = v
        end
    end
    return out
end

local function load_data()
    local raw, _ = File.read(DATA_FILE)
    if not raw then return nil end
    local ok, t = pcall(Json.decode, raw)
    if not ok or type(t) ~= "table" then return nil end
    t.jewel_found = normalize_events(t.jewel_found)
    t.dust_found  = normalize_events(t.dust_found)
    return t
end

-- Forward declarations (filled before first use)
local validate_data, create_backup

local data = {}

local function init_defaults()
    data.creature                   = data.creature or "none"
    data.weekly_ascension_searches  = tonumber(data.weekly_ascension_searches)  or 0
    data.monthly_ascension_searches = tonumber(data.monthly_ascension_searches) or 0
    data.searches_since_jewel       = tonumber(data.searches_since_jewel)       or 0
    data.searches_since_dust        = tonumber(data.searches_since_dust)        or 0
    data.jewel_found                = data.jewel_found or {}
    data.dust_found                 = data.dust_found  or {}
    if data.silent              == nil then data.silent              = true  end
    if data.announce_msg        == nil then data.announce_msg        = false end
    if data.submit_finds        == nil then data.submit_finds        = false end
    if data.jewel_found_this_week == nil then data.jewel_found_this_week = false end
    if data.debug_eligibility   == nil then data.debug_eligibility   = false end
    data.monthly_gemstones          = tonumber(data.monthly_gemstones) or 0
    data.weekly_gemstone            = tonumber(data.weekly_gemstone)   or 0
    data.weekly_dust                = tonumber(data.weekly_dust)       or 0
    data.last_month_reset           = tonumber(data.last_month_reset)  or et_now().month
    data.last_week_reset            = tonumber(data.last_week_reset)   or 0
    data.cached_reset_time          = tonumber(data.cached_reset_time) or 0
    data.weekly_counts              = data.weekly_counts or {}
end

-- Serialize data to JSON (converts integer keys to strings for JSON compatibility)
local function serializable_data()
    local out = {}
    for k, v in pairs(data) do out[k] = v end
    local jf = {}; for k, v in pairs(data.jewel_found) do jf[tostring(k)] = v end
    local df = {}; for k, v in pairs(data.dust_found)  do df[tostring(k)] = v end
    out.jewel_found = jf
    out.dust_found  = df
    return out
end

local _last_hash    = nil
local _next_save_at = 0

local function save_data(force)
    local now = os.time()
    local ok_enc, s = pcall(Json.encode, serializable_data())
    local h = ok_enc and #s or 0
    if not force then
        if h == _last_hash then return end
        if now <= _next_save_at then return end
    end
    -- Validate before save
    local errors = validate_data()
    if #errors > 0 then
        echo("WARNING: Data validation errors:")
        for _, e in ipairs(errors) do echo("  - " .. e) end
        create_backup("validation_errors")
    end
    local ok2, js = pcall(Json.encode, serializable_data())
    if not ok2 then echo("Error encoding data: " .. tostring(js)); return end
    local ok3, err = File.write(DATA_FILE, js)
    if ok3 then
        _next_save_at = now + 300
        _last_hash    = h
    else
        echo("Error saving data: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

validate_data = function()
    local errors = {}
    local int_keys = {
        "weekly_ascension_searches", "monthly_ascension_searches",
        "searches_since_jewel", "searches_since_dust",
        "monthly_gemstones", "weekly_gemstone", "weekly_dust",
    }
    for _, k in ipairs(int_keys) do
        local v = data[k]
        if type(v) == "number" and v < 0 then
            errors[#errors+1] = k .. " is negative: " .. v
        end
    end
    local now = os.time()
    for ts in pairs(data.jewel_found) do
        if type(ts) ~= "number" then
            errors[#errors+1] = "jewel_found non-integer key: " .. tostring(ts)
        elseif ts >= 100000 and (ts < 1000000000 or ts > now + 86400) then
            errors[#errors+1] = "jewel_found timestamp out of range: " .. ts
        end
    end
    for ts in pairs(data.dust_found) do
        if type(ts) ~= "number" then
            errors[#errors+1] = "dust_found non-integer key: " .. tostring(ts)
        elseif ts >= 100000 and (ts < 1000000000 or ts > now + 86400) then
            errors[#errors+1] = "dust_found timestamp out of range: " .. ts
        end
    end
    if data.monthly_gemstones > 3 then
        errors[#errors+1] = "monthly_gemstones exceeds max: " .. data.monthly_gemstones
    end
    if data.weekly_gemstone > 1 then
        errors[#errors+1] = "weekly_gemstone exceeds max: " .. data.weekly_gemstone
    end
    return errors
end

--------------------------------------------------------------------------------
-- Backup / Restore
--------------------------------------------------------------------------------

create_backup = function(reason)
    reason = reason or "manual"
    local ts   = os.date("!%Y%m%d_%H%M%S")
    local path = BACKUP_DIR .. "/killtracker_" .. ts .. "_" .. reason .. ".json"
    local ok, js = pcall(Json.encode, serializable_data())
    if not ok then echo("Warning: Could not encode backup: " .. tostring(js)); return nil end
    local ok2, err = File.write(path, js)
    if not ok2 then echo("Warning: Failed to create backup: " .. tostring(err)); return nil end
    -- Prune: keep only last 10 backups
    local files = File.list(BACKUP_DIR)
    if files then
        local kts = {}
        for _, f in ipairs(files) do
            if f:match("^killtracker_") then kts[#kts+1] = f end
        end
        table.sort(kts)
        while #kts > 10 do
            File.remove(BACKUP_DIR .. "/" .. kts[1])
            table.remove(kts, 1)
        end
    end
    return path
end

local function restore_latest_backup()
    local files = File.list(BACKUP_DIR)
    local kts   = {}
    if files then
        for _, f in ipairs(files) do
            if f:match("^killtracker_") then kts[#kts+1] = f end
        end
    end
    if #kts == 0 then echo("No backups found to restore from."); return false end
    table.sort(kts)
    local latest = BACKUP_DIR .. "/" .. kts[#kts]
    local raw, rerr = File.read(latest)
    if not raw then echo("Failed to read backup: " .. tostring(rerr)); return false end
    local ok, t = pcall(Json.decode, raw)
    if not ok or type(t) ~= "table" then echo("Failed to parse backup file."); return false end
    t.jewel_found = normalize_events(t.jewel_found)
    t.dust_found  = normalize_events(t.dust_found)
    data = t
    init_defaults()
    echo("Restored from backup: " .. kts[#kts])
    save_data(true)
    return true
end

--------------------------------------------------------------------------------
-- Eligibility
--------------------------------------------------------------------------------

local function currently_eligible()
    local weekly  = not data.jewel_found_this_week
    local monthly = data.monthly_gemstones < 3
    local elig    = weekly and monthly
    if data.debug_eligibility then
        echo("Eligibility: weekly=" .. tostring(weekly) ..
             " (found_this_week=" .. tostring(data.jewel_found_this_week) .. ")" ..
             " monthly=" .. tostring(monthly) ..
             " (gems=" .. data.monthly_gemstones .. ")" ..
             " => " .. tostring(elig))
    end
    return elig
end

local function update_eligibility()
    -- Read existing cross-character file
    local elig_data = {}
    local raw = File.read(ELIG_FILE)
    if raw then
        local ok, t = pcall(Json.decode, raw)
        if ok and type(t) == "table" then elig_data = t end
    end
    -- Prune stale entries (>7 days) from other characters
    local now = os.time()
    for char, stats in pairs(elig_data) do
        local lu = tonumber(stats.last_updated) or 0
        if (now - lu) > 7 * 86400 and char ~= CHAR_NAME then
            elig_data[char] = nil
        end
    end
    -- Write this character's current state
    elig_data[CHAR_NAME] = {
        profession         = Stats.prof,
        weekly_gemstone    = data.weekly_gemstone,
        monthly_gemstones  = data.monthly_gemstones,
        currently_eligible = currently_eligible(),
        last_updated       = now,
    }
    local ok, js = pcall(Json.encode, elig_data)
    if ok then File.write(ELIG_FILE, js) end
end

--------------------------------------------------------------------------------
-- Weekly / Monthly resets
--------------------------------------------------------------------------------

local function refresh_reset_time()
    data.cached_reset_time = next_sunday_midnight_utc()
end

local function maybe_reset_weekly()
    if data.cached_reset_time == 0 then refresh_reset_time() end
    local now      = os.time()
    local reset_ts = data.cached_reset_time
    -- Sanity check
    if reset_ts > 0 and math.abs(reset_ts - now) > 14 * 86400 then
        echo("Warning: Reset time seems invalid, recalculating...")
        refresh_reset_time()
        reset_ts = data.cached_reset_time
    end
    -- Process all missed resets
    while now >= reset_ts and (data.last_week_reset == 0 or data.last_week_reset < reset_ts) do
        create_backup("weekly_reset")
        local ok, err = pcall(function()
            local finished_week = et_week(reset_ts - 7 * 86400)
            local wk_searches   = data.weekly_ascension_searches
            local wk_dust       = data.weekly_dust
            local wk_gem        = data.weekly_gemstone
            data.weekly_counts["week_" .. finished_week .. "_ascension_searches"] = wk_searches
            data.weekly_counts["week_" .. finished_week .. "_dust"]               = wk_dust
            data.weekly_counts["week_" .. finished_week .. "_gemstone"]           = wk_gem
            data.monthly_ascension_searches = data.monthly_ascension_searches + wk_searches
            data.weekly_ascension_searches  = 0
            data.weekly_gemstone            = 0
            data.weekly_dust                = 0
            data.jewel_found_this_week      = false
            data.last_week_reset            = reset_ts
            refresh_reset_time()
            echo("Weekly reset completed for week " .. finished_week)
            save_data(true)
        end)
        if not ok then
            echo("Error during weekly reset: " .. tostring(err))
            restore_latest_backup()
            break
        end
        reset_ts = data.cached_reset_time
    end
end

local function maybe_reset_monthly()
    local en            = et_now()
    local current_month = en.month
    local current_year  = en.year
    if current_month ~= data.last_month_reset then
        create_backup("monthly_reset")
        data.monthly_gemstones          = 0
        data.monthly_ascension_searches = 0
        data.last_month_reset           = current_month
        echo("Monthly reset completed for month " .. current_month)
        save_data(true)
    end
    -- Recount gems this month for accuracy
    local gems = 0
    for ts in pairs(data.jewel_found) do
        if type(ts) == "number" then
            local d = os.date("!*t", ts + et_offset(ts))
            if d.month == current_month and d.year == current_year then
                gems = gems + 1
            end
        end
    end
    if gems ~= data.monthly_gemstones then
        echo("Correcting monthly count: " .. data.monthly_gemstones .. " → " .. gems)
        data.monthly_gemstones = gems
    end
end

--------------------------------------------------------------------------------
-- Helper calculations
--------------------------------------------------------------------------------

local function calculate_total_searches()
    local total = data.weekly_ascension_searches
    for k, v in pairs(data.weekly_counts) do
        if type(v) == "number" and k:find("ascension_searches") then
            total = total + v
        end
    end
    return total
end

local function calculate_monthly_eligible_searches()
    local total = data.monthly_ascension_searches + data.weekly_ascension_searches
    if total < 0 then
        echo("Warning: Monthly total is negative, using current week only")
        total = data.weekly_ascension_searches
    end
    return total
end

local function determine_jewel_number(jewel_ts)
    local jd    = os.date("!*t", jewel_ts + et_offset(jewel_ts))
    local count = 0
    for ts in pairs(data.jewel_found) do
        if type(ts) == "number" and ts < jewel_ts then
            local d = os.date("!*t", ts + et_offset(ts))
            if d.month == jd.month and d.year == jd.year then
                count = count + 1
            end
        end
    end
    return count + 1
end

local function get_eligible_since_time()
    if data.jewel_found_this_week then
        return fmt_et(next_sunday_midnight_utc())
    end
    local last_ts = nil
    for ts in pairs(data.jewel_found) do
        if type(ts) == "number" and (last_ts == nil or ts > last_ts) then last_ts = ts end
    end
    if last_ts then
        local now = os.time()
        if et_week(last_ts) < et_week(now) then
            -- Eligible since start of this week (last Sunday midnight ET)
            local off = et_offset(now)
            local d   = os.date("!*t", now + off)
            local sun_et = (now + off)
                         - (d.wday - 1) * 86400
                         - d.hour * 3600 - d.min * 60 - d.sec
            return fmt_et(sun_et - off)
        else
            return fmt_et(last_ts)
        end
    end
    return "Start of tracking"
end

--------------------------------------------------------------------------------
-- Reports
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond(";kt announce           - Watch kills increment in the speech window")
    respond(";kt announce msg       - Alternate between two announce message styles")
    respond(";kt summary            - Summary for the week")
    respond(";kt eligible           - Show cross character eligibility")
    respond(";kt gemstones report   - Find report broken down by week")
    respond(";kt jewel report       - Find report of all jewels")
    respond(";kt dust report        - Find report of all dust")
    respond(";kt fix find count     - Recalculate monthly/weekly gemstone counts")
    respond(";kt save               - Force search data to be saved to file")
    respond(";kt backup             - Create a manual backup")
    respond(";kt restore backup     - Restore from latest backup")
    respond(";kt validate           - Check data integrity")
    respond("")
    respond(";kt submit finds       - Toggle submitting finds to Google Sheets")
    respond("   https://docs.google.com/spreadsheets/d/1IOLs8AGRR45Kr6Y9nz6CXlMVBKYR7cHLaz0jjAbjMv0")
end

local function summary_report()
    local ok, err = pcall(function()
        local gems_total, dust_total = 0, 0
        for _ in pairs(data.jewel_found) do gems_total = gems_total + 1 end
        for _ in pairs(data.dust_found)  do dust_total = dust_total + 1 end

        local weekly_searches  = data.weekly_ascension_searches
        local monthly_searches = calculate_monthly_eligible_searches()
        local gems_this_week   = data.weekly_gemstone
        local dust_this_week   = data.weekly_dust
        local gems_this_month  = data.monthly_gemstones
        local since_last_gem   = data.searches_since_jewel
        local since_last_dust  = data.searches_since_dust

        local sfg, sfd = 0, 0
        for _, ev in pairs(data.jewel_found) do sfg = sfg + (tonumber(ev.searches_week) or 0) end
        for _, ev in pairs(data.dust_found)  do sfd = sfd + (tonumber(ev.searches_week) or 0) end

        local avg_gem  = gems_total > 0 and math.floor(sfg / gems_total + 0.5) or 0
        local avg_dust = dust_total > 0 and math.floor(sfd / dust_total + 0.5) or 0
        local remaining = math.max(0, 3 - gems_this_month)

        local weekly_status, eligible_since
        if currently_eligible() then
            local gem_num = gems_this_month + 1
            local ord     = (gem_num == 1 and "1st") or (gem_num == 2 and "2nd") or "3rd"
            weekly_status  = "Eligible (" .. ord .. ")"
            eligible_since = get_eligible_since_time()
        else
            weekly_status  = "Ineligible"
            eligible_since = "Ineligible"
        end

        local tbl = T.new({"Metric", "Count"})
        tbl:add_full_row("Killtracker Summary")
        tbl:add_separator()
        tbl:add_row({"Searches This Week",    comma(weekly_searches)})
        tbl:add_row({"Eligible This Month",   comma(monthly_searches)})
        tbl:add_separator()
        tbl:add_row({"Weekly Status",         weekly_status})
        tbl:add_row({"Eligible Since",        eligible_since})
        tbl:add_separator()
        tbl:add_row({"Gemstones Found (all)", comma(gems_total)})
        tbl:add_row({" This Week",            tostring(gems_this_week)})
        tbl:add_row({" This Month",           tostring(gems_this_month)})
        tbl:add_row({" Remaining This Month", tostring(remaining)})
        tbl:add_row({" Avg Searches/Gem",     comma(avg_gem)})
        tbl:add_separator()
        tbl:add_row({"Dust Found (all)",      comma(dust_total)})
        tbl:add_row({" This Week",            tostring(dust_this_week)})
        tbl:add_row({" Avg Searches/Dust",    comma(avg_dust)})
        tbl:add_separator()
        tbl:add_row({"Since Last Gem",        comma(since_last_gem)})
        tbl:add_row({"Since Last Dust",       comma(since_last_dust)})
        respond(tbl:render())
    end)
    if not ok then
        respond("Error generating summary report: " .. tostring(err))
        respond("Run ;kt validate to check data integrity")
    end
end

local function jewel_report()
    local ok, err = pcall(function()
        local events = {}
        for ts, ev in pairs(data.jewel_found) do
            if type(ts) == "number" then events[#events+1] = {ts=ts, ev=ev} end
        end
        table.sort(events, function(a, b) return a.ts < b.ts end)
        local total_searches = 0
        for _, e in ipairs(events) do
            total_searches = total_searches + (tonumber(e.ev.searches_week) or 0)
        end
        local title = string.format(
            "Detailed Jewel Report: %d Jewels over %s Eligible Searches",
            #events, comma(total_searches))
        local tbl = T.new({"Time", "Jewel#", "Since Last Jewel", "Creature", "Room", "Name"})
        tbl:add_full_row(title)
        tbl:add_separator()
        for _, e in ipairs(events) do
            local ev = e.ev
            tbl:add_row({
                fmt_et(e.ts),
                tostring(determine_jewel_number(e.ts)),
                comma(tonumber(ev.searches_since) or 0),
                ev.creature or "",
                ev.room     or "",
                ev.name     or "",
            })
        end
        respond(tbl:render())
    end)
    if not ok then respond("Error generating jewel report: " .. tostring(err)) end
end

local function dust_report()
    local ok, err = pcall(function()
        local events = {}
        for ts, ev in pairs(data.dust_found) do
            if type(ts) == "number" then events[#events+1] = {ts=ts, ev=ev} end
        end
        table.sort(events, function(a, b) return a.ts < b.ts end)
        local title = string.format(
            "Detailed Dust Report: %d Dust over %s Searches",
            #events, comma(calculate_total_searches()))
        local tbl = T.new({"Time", "Searches", "Creature", "Room", "Name"})
        tbl:add_full_row(title)
        tbl:add_separator()
        for _, e in ipairs(events) do
            local ev = e.ev
            tbl:add_row({
                fmt_et(e.ts),
                comma(tonumber(ev.searches_week) or 0),
                ev.creature or "",
                ev.room     or "",
                ev.name     or "",
            })
        end
        respond(tbl:render())
    end)
    if not ok then respond("Error generating dust report: " .. tostring(err)) end
end

local function gemstones_report(weeks_back)
    local ok, err = pcall(function()
        local now_ts       = os.time()
        local current_week = et_week(now_ts)

        -- Build combined event list
        local combined = {}
        for ts, ev in pairs(data.jewel_found) do
            if type(ts) == "number" and type(ev) == "table" then
                combined[#combined+1] = {
                    ts           = ts,
                    type         = "Gemstone",
                    searches_week = tonumber(ev.searches_week)  or 0,
                    since        = tonumber(ev.searches_since)  or 0,
                    creature     = ev.creature or "",
                    name         = ev.name     or "",
                    jewel_num    = determine_jewel_number(ts),
                }
            end
        end
        for ts, ev in pairs(data.dust_found) do
            if type(ts) == "number" and type(ev) == "table" then
                combined[#combined+1] = {
                    ts           = ts,
                    type         = "Dust",
                    searches_week = tonumber(ev.searches_week) or 0,
                    since        = tonumber(ev.searches_since) or 0,
                    creature     = ev.creature or "",
                    name         = ev.name     or "",
                }
            end
        end

        -- Group by ET week number
        local by_week = {}
        for _, ev in ipairs(combined) do
            local wk = et_week(ev.ts)
            if not by_week[wk] then by_week[wk] = {} end
            by_week[wk][#by_week[wk]+1] = ev
        end

        -- Collect and filter week keys
        local week_keys = {}
        for wk in pairs(by_week) do week_keys[#week_keys+1] = wk end
        table.sort(week_keys)

        for _, wk in ipairs(week_keys) do
            -- Filter by weeks_back if specified
            if weeks_back and (wk < current_week - weeks_back + 1 or wk > current_week) then
                goto continue
            end
            local weekly_count
            if wk == current_week then
                weekly_count = data.weekly_ascension_searches
            else
                weekly_count = tonumber(data.weekly_counts["week_" .. wk .. "_ascension_searches"]) or 0
            end
            if weekly_count == 0 then goto continue end

            local title = string.format("Week %d Gemstone Search Report: %s Searches",
                wk, comma(weekly_count))
            local tbl = T.new({"Time", "Type", "Week Searches", "Since Last", "Creature", "Name"})
            tbl:add_full_row(title)
            tbl:add_separator()

            local evs = by_week[wk]
            table.sort(evs, function(a, b) return a.ts < b.ts end)
            for _, ev in ipairs(evs) do
                local type_str = ev.type == "Gemstone" and ("Gem#" .. ev.jewel_num) or "Dust"
                tbl:add_row({
                    fmt_et(ev.ts),
                    type_str,
                    comma(ev.searches_week),
                    comma(ev.since),
                    ev.creature,
                    ev.name,
                })
            end
            respond(tbl:render())
            ::continue::
        end
    end)
    if not ok then respond("Error generating gemstones report: " .. tostring(err)) end
end

local function eligibility_report(sort_key)
    local ok, err = pcall(function()
        update_eligibility()

        local elig_data = {}
        local raw = File.read(ELIG_FILE)
        if raw then
            local jok, t = pcall(Json.decode, raw)
            if jok and type(t) == "table" then elig_data = t end
        end

        local now       = os.time()
        local prof_mode = sort_key and sort_key:lower():match("^prof") ~= nil

        if prof_mode then
            local groups = {}
            for _, stats in pairs(elig_data) do
                local p = stats.profession or "Unknown"
                if not groups[p] then groups[p] = {wk=0, mo=0} end
                groups[p].wk = groups[p].wk + (tonumber(stats.weekly_gemstone)   or 0)
                groups[p].mo = groups[p].mo + (tonumber(stats.monthly_gemstones) or 0)
            end
            local rows = {}
            for prof, g in pairs(groups) do
                local elig = (g.mo < 3 and g.wk == 0) and "Yes" or "No"
                rows[#rows+1] = {prof, elig, tostring(g.wk), tostring(g.mo)}
            end
            table.sort(rows, function(a, b) return a[1]:lower() < b[1]:lower() end)
            local tbl = T.new({"Prof", "Eligible", "Week", "Month"})
            tbl:add_full_row("Jewel Eligibility Across Characters (by profession)")
            tbl:add_separator()
            for _, r in ipairs(rows) do tbl:add_row(r) end
            respond(tbl:render())
        else
            local rows = {}
            for char, stats in pairs(elig_data) do
                local wk      = tonumber(stats.weekly_gemstone)   or 0
                local mo      = tonumber(stats.monthly_gemstones) or 0
                local elig    = (mo < 3 and wk == 0) and "Yes" or "No"
                local lu      = tonumber(stats.last_updated) or 0
                local stale_h = (now - lu) / 3600
                local char_d  = char
                if stale_h > 24 then
                    char_d = char .. " (" .. math.floor(stale_h) .. "h old)"
                    if elig == "Yes" then elig = "Yes?" end
                end
                rows[#rows+1] = {char_d, stats.profession or "", elig, tostring(wk), tostring(mo)}
            end
            table.sort(rows, function(a, b) return a[1]:lower() < b[1]:lower() end)
            local tbl = T.new({"Name", "Prof", "Eligible", "Week", "Month"})
            tbl:add_full_row("Jewel Eligibility Across Characters")
            tbl:add_separator()
            for _, r in ipairs(rows) do tbl:add_row(r) end
            respond(tbl:render())
        end
    end)
    if not ok then respond("Error generating eligibility report: " .. tostring(err)) end
end

local function backfill_counters()
    local ok, err = pcall(function()
        create_backup("pre_backfill")
        local now = os.time()
        local en  = et_now()
        local cw, cm, cy = et_week(now), en.month, en.year

        data.weekly_gemstone            = 0
        data.monthly_gemstones          = 0
        data.weekly_dust                = 0
        data.monthly_ascension_searches = 0
        data.jewel_found_this_week      = false

        for ts in pairs(data.jewel_found) do
            if type(ts) == "number" then
                local d  = os.date("!*t", ts + et_offset(ts))
                local wk = et_week(ts)
                if wk == cw and d.year == en.year then
                    data.weekly_gemstone       = data.weekly_gemstone + 1
                    data.jewel_found_this_week = true
                end
                if d.year == cy and d.month == cm then
                    data.monthly_gemstones = data.monthly_gemstones + 1
                end
            end
        end

        for ts in pairs(data.dust_found) do
            if type(ts) == "number" then
                local d  = os.date("!*t", ts + et_offset(ts))
                local wk = et_week(ts)
                if wk == cw and d.year == en.year then
                    data.weekly_dust = data.weekly_dust + 1
                end
            end
        end

        for k, v in pairs(data.weekly_counts) do
            if type(v) == "number" and k:find("ascension_searches") then
                local wk_num = tonumber(k:match("week_(%d+)_"))
                if wk_num then
                    -- Approximate: use start-of-week timestamp (wk_num weeks into the year)
                    local approx_ts = mkutc(en.year, 1, 1) + wk_num * 7 * 86400
                    local d = os.date("!*t", approx_ts + et_offset(approx_ts))
                    if d.year == cy and d.month == cm then
                        data.monthly_ascension_searches = data.monthly_ascension_searches + v
                    end
                end
            end
        end

        update_eligibility()
        respond("Counters successfully recalculated.")
        respond("  Weekly gems: " .. data.weekly_gemstone ..
                "  Monthly gems: " .. data.monthly_gemstones)
        respond("  Jewel found this week: " .. tostring(data.jewel_found_this_week))
    end)
    if not ok then
        respond("Error during backfill: " .. tostring(err))
        restore_latest_backup()
    end
end

--------------------------------------------------------------------------------
-- Google Sheets submission
--------------------------------------------------------------------------------

local function send_to_sheet(ev_type, ts)
    local ev = ev_type == "dust" and data.dust_found[ts] or data.jewel_found[ts]
    if not ev then return nil end
    local user_id = Crypto.sha256(CHAR_NAME .. "|" .. (Stats.race or "") .. "|" .. (Stats.prof or ""))
    local resp, err = Http.post_json(SHEETS_URL, {
        timestamp      = ts,
        type           = ev_type,
        searches_week  = ev.searches_week,
        searches_since = ev.searches_since,
        creature       = ev.creature,
        room           = ev.room,
        name           = ev.name,
        user           = user_id,
    })
    if resp then return resp.status end
    echo("!! send_to_sheet error: " .. tostring(err))
    return nil
end

local function send_all_finds()
    respond("Sending found jewels...")
    local sent = 0
    for ts in pairs(data.jewel_found) do
        if type(ts) == "number" and send_to_sheet("jewel", ts) then sent = sent + 1 end
    end
    respond("  Sent " .. sent .. " jewel records")

    respond("Sending found dust...")
    sent = 0
    for ts in pairs(data.dust_found) do
        if type(ts) == "number" and send_to_sheet("dust", ts) then sent = sent + 1 end
    end
    respond("  Sent " .. sent .. " dust records")

    respond("Sending complete.")
    respond("View the data at: https://docs.google.com/spreadsheets/d/1IOLs8AGRR45Kr6Y9nz6CXlMVBKYR7cHLaz0jjAbjMv0")
    respond("")
    respond("Note: this command should only be run once.")
    respond("To continue submitting finds going forward: ;kt submit finds")
end

--------------------------------------------------------------------------------
-- Downstream hook: parse game output
--------------------------------------------------------------------------------

local function on_downstream(line)
    -- Gemstone jewel find
    local caps = FOUND_GEMSTONE_RE:captures(line)
    if caps then
        local ts   = os.time()
        local name = caps["n"] or ""
        local room = tostring(Map.current_room() or "")
        create_backup("pre_jewel_find")
        data.monthly_gemstones     = data.monthly_gemstones + 1
        data.weekly_gemstone       = data.weekly_gemstone + 1
        data.jewel_found_this_week = true
        data.jewel_found[ts] = {
            searches_since = data.searches_since_jewel,
            searches_week  = data.weekly_ascension_searches,
            name           = name,
            room           = room,
            creature       = data.creature,
            on_the_month   = data.monthly_gemstones,
        }
        local report = {"found gemstone", data.creature,
                        data.weekly_ascension_searches, data.searches_since_jewel}
        data.searches_since_jewel = 0
        qpush(report_queue, report)
        if data.submit_finds then qpush(report_queue, {"send jewel report", ts}) end
        return line
    end

    -- Gemstone dust find
    if FOUND_DUST_RE:test(line) then
        local ts   = os.time()
        local room = tostring(Map.current_room() or "")
        data.weekly_dust = data.weekly_dust + 1
        data.dust_found[ts] = {
            searches_since = data.searches_since_dust,
            searches_week  = data.weekly_ascension_searches,
            name           = "gemstone dust",
            room           = room,
            creature       = data.creature,
        }
        local report = {"found dust", data.creature,
                        data.weekly_ascension_searches, data.searches_since_dust}
        data.searches_since_dust = 0
        qpush(report_queue, report)
        if data.submit_finds then qpush(report_queue, {"send dust report", ts}) end
        return line
    end

    -- Search / creature kill detection
    local creature = nil
    local c1 = SEARCH_CREATURE_RE:captures(line)
    if c1 then
        creature = c1["creature"]
    else
        local c2 = SEARCH_MUG_RE:captures(line)
        if c2 then
            creature = c2["creature"]
        else
            local c3 = EVIL_EYE_RE:captures(line)
            if c3 then creature = c3["creature"] end
        end
    end

    if creature then
        maybe_reset_weekly()
        maybe_reset_monthly()
        data.creature = creature
        if ASCENSION_RE:test(creature) then
            -- Always count dust searches (no monthly limit)
            data.searches_since_dust = data.searches_since_dust + 1
            -- Only count gem searches when eligible for gems
            if currently_eligible() then
                data.weekly_ascension_searches = data.weekly_ascension_searches + 1
                data.searches_since_jewel      = data.searches_since_jewel + 1
                if not data.silent then
                    qpush(report_queue, {
                        "search report", creature,
                        data.weekly_ascension_searches,
                        data.searches_since_dust,
                        data.searches_since_jewel,
                    })
                end
            elseif data.debug_eligibility then
                echo("Search not counted for gems — ineligible (" .. creature .. ")")
            end
        end
    end

    return line
end

--------------------------------------------------------------------------------
-- Upstream hook: intercept ;kt / ;killtracker commands
--------------------------------------------------------------------------------

local function on_upstream(command)
    local caps = CMD_RX:captures(command)
    if caps then
        local args = caps[1] or ""
        qpush(cmd_queue, args)
        return nil  -- squelch: don't send to game
    end
    return command
end

--------------------------------------------------------------------------------
-- Command dispatch
--------------------------------------------------------------------------------

local function handle_command(command)
    command = command:match("^%s*(.-)%s*$")  -- trim whitespace

    if command:match("^help") then
        show_help()
    elseif command:match("^save$") then
        save_data(true)
        respond("Killtracker data saved to file.")
    elseif command:match("^backup$") then
        local path = create_backup("manual")
        if path then respond("Backup created: " .. (path:match("[^/]+$") or path)) end
    elseif command:match("^restore backup$") then
        if restore_latest_backup() then
            respond("Data restored from latest backup.")
        else
            respond("Failed to restore from backup.")
        end
    elseif command:match("^validate$") then
        local errors = validate_data()
        if #errors == 0 then
            respond("Data validation passed — no errors found.")
        else
            respond("Data validation found " .. #errors .. " error(s):")
            for _, e in ipairs(errors) do respond("  - " .. e) end
        end
    elseif command:match("^jewel report$") then
        jewel_report()
    elseif command:match("^dust report$") then
        dust_report()
    elseif command:match("^gemstones? report") then
        local weeks_back = tonumber(command:match("report%s+(%d+)$"))
        gemstones_report(weeks_back)
    elseif command:match("^summary$") or command == "" then
        summary_report()
    elseif command:match("^send all finds$") then
        send_all_finds()
    elseif command:match("^fix find count$") then
        backfill_counters()
        respond("Monthly and weekly find counts have been recalculated.")
    elseif command:match("^elig") then
        local sort_key = command:match("^%S+%s+(%S+)")
        eligibility_report(sort_key)
    elseif command:match("^announce msg$") then
        data.announce_msg = not data.announce_msg
        respond(data.announce_msg
            and "Announce shows total search count."
            or  "Announce shows searches since last find.")
    elseif command:match("^announce$") then
        data.silent = not data.silent
        respond(data.silent
            and "Reporting only upon a find."
            or  "Reporting after each kill.")
    elseif command:match("^submit finds$") then
        data.submit_finds = not data.submit_finds
        respond(data.submit_finds
            and "Sending finds to external spreadsheet."
            or  "NOT sending finds to external spreadsheet.")
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Ensure directories exist (File.write creates parents automatically,
-- but explicit mkdir avoids confusion for File.list calls)
File.mkdir("data/gs")
File.mkdir(DATA_DIR)
File.mkdir(BACKUP_DIR)

-- Load or initialize data
local loaded = load_data()
if loaded then
    data = loaded
    -- One-time initial-load backup
    local init_path = BACKUP_DIR .. "/initial_load.json"
    if not File.exists(init_path) then
        local ok, js = pcall(Json.encode, serializable_data())
        if ok then File.write(init_path, js) end
    end
else
    data = {}
end

init_defaults()
save_data(true)
maybe_reset_weekly()
maybe_reset_monthly()
update_eligibility()

-- Register hooks
DownstreamHook.add(DS_HOOK_ID, on_downstream)
UpstreamHook.add(US_HOOK_ID, on_upstream)

-- Cleanup on script exit
before_dying(function()
    save_data(true)
    DownstreamHook.remove(DS_HOOK_ID)
    UpstreamHook.remove(US_HOOK_ID)
end)

-- Handle startup args (e.g. ;killtracker summary)
local startup = Script.vars and Script.vars[0]
if startup and startup ~= "" then qpush(cmd_queue, startup) end

respond("[killtracker] Tracking started. Use ;kt help for commands.")

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

while true do
    -- Process report queue
    while not qempty(report_queue) do
        local report = qpop(report_queue)
        if not report then break end
        local rtype = report[1]
        if rtype == "search report" then
            local creature, week, dust, jewel = report[2], report[3], report[4], report[5]
            if data.announce_msg then
                respond("Searches: (" .. week .. ") - (" .. creature .. ")")
            else
                respond("Searches: (" .. week .. ") - (" .. creature ..
                        ") - Since last Dust: (" .. dust ..
                        ")  Since last Jewel: (" .. jewel .. ")")
            end
            save_data()
        elseif rtype == "found dust" then
            local creature, week, dust = report[2], report[3], report[4]
            respond("Found dust after " .. dust .. " searches. (" ..
                    creature .. ") - Week Total: (" .. week .. ")")
            save_data()
        elseif rtype == "found gemstone" then
            local creature, week, jewel = report[2], report[3], report[4]
            respond("Found a gemstone in " .. week .. " searches. (" ..
                    creature .. ") - Since last Jewel: (" .. jewel .. ")")
            save_data()
            update_eligibility()
        elseif rtype == "send dust report" then
            send_to_sheet("dust", report[2])
        elseif rtype == "send jewel report" then
            send_to_sheet("jewel", report[2])
        end
    end

    -- Process command queue
    while not qempty(cmd_queue) do
        local command = qpop(cmd_queue)
        if command then handle_command(command) end
    end

    -- Adaptive sleep: tight when active, relaxed when idle
    pause(qempty(cmd_queue) and qempty(report_queue) and 1.0 or 0.1)
end
