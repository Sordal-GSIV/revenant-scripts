--- @revenant-script
--- name: exptrack
--- version: 1.0
--- author: Nisugi
--- game: gs
--- description: Experience tracker — session, daily, hourly, and custom range reports with SQLite persistence
--- tags: experience, tracking, data, database
---
--- Commands:
---   ;exptrack help     - Show this help
---   ;exptrack session  - Show current session stats
---   ;exptrack last     - Show last 10 entries
---   ;exptrack instant  - Show last 10 instant/bounty entries
---   ;exptrack today    - Show today's totals
---   ;exptrack daily    - Show daily totals for last 10 days
---   ;exptrack hour     - Show last hour's gains
---   ;exptrack report <start> <end> - Show exp report for time range
---      Examples: ;exptrack report "2025-08-28 13:05:52" "2025-08-30 15:02:22"
---                ;exptrack report "08-28 13:05" "08-30 15:02"
---                ;exptrack report "13:05" "15:02"  (today)
---   ;exptrack addgain <gain> - Manually add exp gain (no exp value)
---   ;exptrack clean    - Remove entries with 0 exp gained
---   ;exptrack reset    - Clear all data (WARNING: permanent)
---
--- Changelog (from Lich5 exptrack.lic):
---   v1.0 - Nisugi original Lich5 version
---   Revenant port: Lua coroutines, Revenant SQLite/hook APIs, dual-hook bounty detection

local HOOK_ID = "exptrack_" .. tostring(os.time())

-- ─── Database Setup ─────────────────────────────────────────────────────────

local db, db_err = Sqlite.open("exptrack.db")
if not db then
    echo("exptrack: failed to open database: " .. tostring(db_err))
    Script.kill(Script.name)
end

db:exec_batch([[
    CREATE TABLE IF NOT EXISTS experience_log (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp        DATETIME NOT NULL,
        experience       INTEGER NOT NULL,
        experience_gained INTEGER,
        character_name   TEXT,
        source_type      TEXT DEFAULT 'normal'
    );
    CREATE INDEX IF NOT EXISTS idx_timestamp
        ON experience_log(timestamp);
    CREATE INDEX IF NOT EXISTS idx_character_timestamp
        ON experience_log(character_name, timestamp);
]])

-- ─── Shared State ───────────────────────────────────────────────────────────

local last_exp      = nil   -- last observed total experience value
local pending_bounty = false -- set when bounty completion text detected
local cmd_queue     = {}    -- upstream commands queued for main loop

-- ─── Downstream Hook ────────────────────────────────────────────────────────
-- A single hook handles both bounty-completion detection and exp capture so
-- that combined XML chunks (progressBar immediately followed by bounty dialog
-- in the same server line) are handled atomically.

DownstreamHook.add(HOOK_ID, function(s)
    -- Detect bounty completion text — covers the case where it arrives
    -- before or after the progressBar in a separate line
    if s:find('says, "All done with that assignment') then
        pending_bounty = true
    end

    -- Check for combined bounty+exp pattern in a single chunk
    local is_combined_bounty = s:find("<progressBar id='nextLvlPB'") and
                                s:find('says, "All done with that assignment')

    -- Extract experience from progressBar
    local exp_str = s:match("<progressBar id='nextLvlPB'[^>]*text='(%d+) experience'")
    if exp_str then
        local exp = tonumber(exp_str)
        local exp_gained = last_exp and (exp - last_exp) or 0
        last_exp = exp

        if exp_gained ~= 0 then
            local source_type
            if is_combined_bounty or pending_bounty then
                source_type   = "bounty"
                pending_bounty = false
            elseif exp_gained > 400 then
                source_type = "instant"
            else
                source_type = "normal"
            end

            local char_name = Char.name or "Unknown"
            local now = os.date("%Y-%m-%d %H:%M:%S")
            db:exec(
                "INSERT INTO experience_log (timestamp, experience, experience_gained, character_name, source_type) VALUES (?, ?, ?, ?, ?)",
                { now, exp, exp_gained, char_name, source_type }
            )
        end
    end

    return s
end)

-- ─── Upstream Hook ──────────────────────────────────────────────────────────

UpstreamHook.add(HOOK_ID, function(s)
    local cmd = s:match("^<c>;exptrack%s*(.*)") or s:match("^;exptrack%s*(.*)")
    if cmd then
        table.insert(cmd_queue, cmd:match("^%s*(.-)%s*$"))
        return nil  -- squelch — don't forward to server
    end
    return s
end)

-- ─── Cleanup ────────────────────────────────────────────────────────────────

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
    UpstreamHook.remove(HOOK_ID)
    db:close()
end)

-- ─── Date Parsing ───────────────────────────────────────────────────────────

-- Parse flexible date/time strings to a Unix timestamp (local time).
-- Supported formats:
--   "HH:MM" or "HH:MM:SS"              → today at that time
--   "MM-DD HH:MM" or "MM-DD HH:MM:SS"  → current year
--   "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS"
local function parse_datetime(str)
    local now_t = os.date("*t")

    -- HH:MM:SS
    local h, m, s = str:match("^(%d%d?):(%d%d):(%d%d)$")
    if h then
        return os.time({ year=now_t.year, month=now_t.month, day=now_t.day,
                         hour=tonumber(h), min=tonumber(m), sec=tonumber(s) })
    end
    -- HH:MM
    h, m = str:match("^(%d%d?):(%d%d)$")
    if h then
        return os.time({ year=now_t.year, month=now_t.month, day=now_t.day,
                         hour=tonumber(h), min=tonumber(m), sec=0 })
    end
    -- MM-DD HH:MM:SS
    local mo, d, hh, mm, ss = str:match("^(%d%d?)-(%d%d?)%s+(%d%d?):(%d%d):(%d%d)$")
    if mo then
        return os.time({ year=now_t.year, month=tonumber(mo), day=tonumber(d),
                         hour=tonumber(hh), min=tonumber(mm), sec=tonumber(ss) })
    end
    -- MM-DD HH:MM
    mo, d, hh, mm = str:match("^(%d%d?)-(%d%d?)%s+(%d%d?):(%d%d)$")
    if mo then
        return os.time({ year=now_t.year, month=tonumber(mo), day=tonumber(d),
                         hour=tonumber(hh), min=tonumber(mm), sec=0 })
    end
    -- YYYY-MM-DD HH:MM:SS
    local yr, mo2, d2, hh2, mm2, ss2 = str:match("^(%d%d%d%d)-(%d%d?)-(%d%d?)%s+(%d%d?):(%d%d):(%d%d)$")
    if yr then
        return os.time({ year=tonumber(yr), month=tonumber(mo2), day=tonumber(d2),
                         hour=tonumber(hh2), min=tonumber(mm2), sec=tonumber(ss2) })
    end
    -- YYYY-MM-DD HH:MM
    yr, mo2, d2, hh2, mm2 = str:match("^(%d%d%d%d)-(%d%d?)-(%d%d?)%s+(%d%d?):(%d%d)$")
    if yr then
        return os.time({ year=tonumber(yr), month=tonumber(mo2), day=tonumber(d2),
                         hour=tonumber(hh2), min=tonumber(mm2), sec=0 })
    end

    return nil
end

-- Convert a YYYY-MM-DD HH:MM:SS string to a Unix timestamp
local function str_to_epoch(ts)
    local yr, mo, d, h, mi, s = ts:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
    if yr then
        return os.time({ year=tonumber(yr), month=tonumber(mo), day=tonumber(d),
                         hour=tonumber(h), min=tonumber(mi), sec=tonumber(s) })
    end
    return nil
end

-- ─── Command Handlers ───────────────────────────────────────────────────────

local function cmd_help()
    echo("Experience Tracker Commands:")
    echo("  ;exptrack help     - Show this help")
    echo("  ;exptrack session  - Show current session stats")
    echo("  ;exptrack last     - Show last 10 entries")
    echo("  ;exptrack instant  - Show last 10 instant/bounty entries")
    echo("  ;exptrack today    - Show today's totals")
    echo("  ;exptrack daily    - Show daily totals for last 10 days")
    echo("  ;exptrack hour     - Show last hour's gains")
    echo('  ;exptrack report <start> <end> - Show exp report for time range')
    echo('     Examples: ;exptrack report "2025-08-28 13:05:52" "2025-08-30 15:02:22"')
    echo('               ;exptrack report "08-28 13:05" "08-30 15:02"')
    echo('               ;exptrack report "13:05" "15:02"  (today)')
    echo("  ;exptrack addgain <gain> - Manually add exp gain (no exp value)")
    echo("  ;exptrack clean    - Remove entries with 0 exp gained")
    echo("  ;exptrack reset    - Clear all data (WARNING: permanent)")
end

local function cmd_session()
    local char_name = Char.name or "Unknown"
    local day_ago   = os.date("%Y-%m-%d %H:%M:%S", os.time() - 24 * 3600)

    local session_start = db:scalar(
        "SELECT MIN(timestamp) FROM experience_log WHERE timestamp >= ?",
        { day_ago }
    )

    if not session_start then
        echo("No session data found (no entries in the last 24 hours).")
        return
    end

    local rows, err = db:query([[
        SELECT
            MIN(experience)  AS start_exp,
            MAX(experience)  AS current_exp,
            MAX(experience) - MIN(experience) AS gained,
            COUNT(*)         AS pulses,
            SUM(CASE WHEN source_type LIKE '%bounty%'  THEN experience_gained ELSE 0 END) AS bounty_exp,
            SUM(CASE WHEN source_type LIKE '%instant%' THEN experience_gained ELSE 0 END) AS instant_exp
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ?
    ]], { char_name, session_start })

    if err then echo("exptrack: query error: " .. err); return end

    local r = rows and rows[1]
    if r and r.gained then
        local gained  = r.gained    or 0
        local bounty  = r.bounty_exp  or 0
        local instant = r.instant_exp or 0
        echo("Session Report for " .. char_name .. ":")
        echo("  Started:     " .. tostring(session_start))
        echo("  Current exp: " .. tostring(r.current_exp))
        echo("  Gained:      " .. tostring(gained))
        echo("  Bounty exp:  " .. tostring(bounty))
        echo("  Instant exp: " .. tostring(instant))
        echo("  Normal exp:  " .. tostring(gained - bounty - instant))
    else
        echo("No session data found for " .. char_name)
    end
end

local function cmd_last()
    local char_name = Char.name or "Unknown"
    local rows, err = db:query([[
        SELECT timestamp, experience, experience_gained, source_type
        FROM experience_log
        WHERE character_name = ?
        ORDER BY timestamp DESC
        LIMIT 10
    ]], { char_name })

    if err then echo("exptrack: query error: " .. err); return end

    echo("Last 10 experience updates:")
    echo(string.format("%-20s %12s %10s %10s", "Time", "Total Exp", "Gained", "Type"))
    echo(string.rep("-", 55))
    for _, row in ipairs(rows or {}) do
        local t = (row.timestamp or ""):match("%d%d:%d%d:%d%d") or row.timestamp or ""
        echo(string.format("%-20s %12d %10d %10s",
            t, row.experience or 0, row.experience_gained or 0, row.source_type or ""))
    end
end

local function cmd_instant()
    local char_name = Char.name or "Unknown"
    local rows, err = db:query([[
        SELECT timestamp, experience, experience_gained, source_type
        FROM experience_log
        WHERE character_name = ?
          AND (source_type LIKE '%instant%' OR source_type LIKE '%bounty%')
        ORDER BY timestamp DESC
        LIMIT 10
    ]], { char_name })

    if err then echo("exptrack: query error: " .. err); return end

    echo("Last 10 instant/bounty experience updates:")
    echo(string.format("%-20s %12s %10s %10s", "Time", "Total Exp", "Gained", "Type"))
    echo(string.rep("-", 55))
    for _, row in ipairs(rows or {}) do
        local t = (row.timestamp or ""):match("%d%d:%d%d:%d%d") or row.timestamp or ""
        echo(string.format("%-20s %12d %10d %10s",
            t, row.experience or 0, row.experience_gained or 0, row.source_type or ""))
    end
    if not rows or #rows == 0 then
        echo("No instant or bounty entries found for " .. char_name)
    end
end

local function cmd_today()
    local char_name  = Char.name or "Unknown"
    local today_start = os.date("%Y-%m-%d") .. " 00:00:00"

    local rows, err = db:query([[
        SELECT
            SUM(experience_gained) AS gained,
            SUM(CASE WHEN source_type LIKE '%bounty%'  THEN experience_gained ELSE 0 END) AS bounty_exp,
            SUM(CASE WHEN source_type LIKE '%instant%' THEN experience_gained ELSE 0 END) AS instant_exp,
            COUNT(*)               AS pulses,
            MIN(experience)        AS min_exp,
            MAX(experience)        AS max_exp
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ?
    ]], { char_name, today_start })

    if err then echo("exptrack: query error: " .. err); return end

    local r = rows and rows[1]
    if r then
        local total   = r.gained     or 0
        local bounty  = r.bounty_exp  or 0
        local instant = r.instant_exp or 0
        echo("Today's totals for " .. char_name .. " (since midnight):")
        echo("  Total gained: " .. tostring(total))
        echo("  Bounty exp:   " .. tostring(bounty))
        echo("  Instant exp:  " .. tostring(instant))
        echo("  Normal exp:   " .. tostring(total - bounty - instant))
        echo("  Updates:      " .. tostring(r.pulses or 0))
        if r.max_exp then
            echo("  Current exp:  " .. tostring(r.max_exp))
        end
    else
        echo("No experience data found for today.")
    end
end

local function cmd_daily()
    local char_name   = Char.name or "Unknown"
    local ten_ago_str = os.date("%Y-%m-%d %H:%M:%S", os.time() - 10 * 24 * 3600)

    local rows, err = db:query([[
        SELECT timestamp, experience_gained, source_type
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ?
        ORDER BY timestamp DESC
    ]], { char_name, ten_ago_str })

    if err then echo("exptrack: query error: " .. err); return end
    if not rows or #rows == 0 then
        echo("No experience data found for the last 10 days.")
        return
    end

    -- Group by calendar date in Lua (avoids SQLite date-localisation issues)
    local daily_data = {}
    local seen_order = {}
    for _, row in ipairs(rows) do
        local date_key = (row.timestamp or ""):match("^(%d%d%d%d%-%d%d%-%d%d)")
        if date_key then
            if not daily_data[date_key] then
                daily_data[date_key] = { total=0, normal=0, bounty=0, instant=0, pulses=0 }
                table.insert(seen_order, date_key)
            end
            local gained = row.experience_gained or 0
            local d      = daily_data[date_key]
            d.total  = d.total  + gained
            d.pulses = d.pulses + 1
            local src = row.source_type or "normal"
            if src:find("bounty") then
                d.bounty  = d.bounty  + gained
            elseif src:find("instant") then
                d.instant = d.instant + gained
            else
                d.normal  = d.normal  + gained
            end
        end
    end

    -- Deduplicate and sort descending, keep first 10
    table.sort(seen_order, function(a, b) return a > b end)
    local deduped = {}
    local seen    = {}
    for _, dk in ipairs(seen_order) do
        if not seen[dk] then
            seen[dk] = true
            table.insert(deduped, dk)
            if #deduped >= 10 then break end
        end
    end

    local today       = os.date("%Y-%m-%d")
    local grand_total = 0

    echo(string.rep("=", 70))
    echo(string.format("%-12s %10s %10s %10s %10s %6s",
        "Date", "Total", "Normal", "Bounty", "Instant", "Pulses"))
    echo(string.rep("-", 70))

    for _, dk in ipairs(deduped) do
        local d  = daily_data[dk]
        grand_total = grand_total + d.total
        local yr, mo, dy = dk:match("(%d%d%d%d)-(%d%d)-(%d%d)")
        local date_str   = string.format("%s/%s/%s", mo, dy, yr)
        if dk == today then date_str = date_str .. "*" end
        echo(string.format("%-12s %10d %10d %10d %10d %6d",
            date_str, d.total, d.normal, d.bounty, d.instant, d.pulses))
    end

    echo(string.rep("-", 70))
    echo(string.format("%-12s %10d", "Total:", grand_total))
    echo(string.rep("=", 70))
    if seen[today] then echo("* = Today") end
end

local function cmd_hour()
    local char_name  = Char.name or "Unknown"
    local hour_ago   = os.date("%Y-%m-%d %H:%M:%S", os.time() - 3600)

    local rows, err = db:query([[
        SELECT
            SUM(experience_gained)  AS gained,
            SUM(CASE WHEN source_type LIKE '%bounty%'  THEN experience_gained ELSE 0 END) AS bounty_exp,
            SUM(CASE WHEN source_type LIKE '%instant%' THEN experience_gained ELSE 0 END) AS instant_exp,
            COUNT(*) AS pulses
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ?
    ]], { char_name, hour_ago })

    if err then echo("exptrack: query error: " .. err); return end

    local r = rows and rows[1]
    if r then
        local gained  = r.gained     or 0
        local bounty  = r.bounty_exp  or 0
        local instant = r.instant_exp or 0
        echo("Last hour for " .. char_name .. ":")
        echo("  Total gained: " .. tostring(gained))
        echo("  Bounty exp:   " .. tostring(bounty))
        echo("  Instant exp:  " .. tostring(instant))
        echo("  Normal exp:   " .. tostring(gained - bounty - instant))
        echo("  Rate:         " .. tostring(gained) .. " exp/hour")
    end
end

-- Multiplier bracket definitions (GS4 pulse values)
local MULT_RANGES = {
    { label="1x",   range="0-74",    min=0,   max=74   },
    { label="1.5x", range="75-106",  min=75,  max=106  },
    { label="2x",   range="107-137", min=107, max=137  },
    { label="2.5x", range="138-168", min=138, max=168  },
    { label="3x",   range="169-199", min=169, max=199  },
    { label="3.5x", range="200-228", min=200, max=228  },
    { label="4x",   range="229-259", min=229, max=259  },
    { label="4.5x", range="260-289", min=260, max=289  },
    { label="5x",   range="290-320", min=290, max=320  },
    { label="5.5x", range="321-350", min=321, max=350  },
    { label="6x",   range="351-381", min=351, max=381  },
    { label="6x+",  range=">381",    min=382, max=math.maxinteger },
}

local function cmd_report(args)
    -- Parse quoted or space-separated date arguments
    local parts = {}
    for quoted in args:gmatch('"([^"]+)"') do
        table.insert(parts, quoted)
    end
    if #parts < 2 then
        parts = {}
        for token in args:gmatch("%S+") do
            table.insert(parts, token)
        end
    end

    if #parts < 2 then
        echo("Usage: ;exptrack report <start_time> <end_time>")
        echo('Examples:')
        echo('  ;exptrack report "2025-08-28 13:05:52" "2025-08-30 15:02:22"')
        echo('  ;exptrack report "08-28 13:05" "08-30 15:02"')
        echo('  ;exptrack report 13:05 15:02  (assumes today)')
        return
    end

    local start_ts = parse_datetime(parts[1])
    local end_ts   = parse_datetime(parts[2])

    if not start_ts or not end_ts then
        echo("Error parsing dates. Supported formats:")
        echo('  "YYYY-MM-DD HH:MM[:SS]"')
        echo('  "MM-DD HH:MM[:SS]"')
        echo('  "HH:MM[:SS]"  (today)')
        return
    end

    local start_str = os.date("%Y-%m-%d %H:%M:%S", start_ts)
    local end_str   = os.date("%Y-%m-%d %H:%M:%S", end_ts)
    local char_name = Char.name or "Unknown"

    -- Starting experience (first entry in range)
    local start_exp = db:scalar([[
        SELECT experience FROM experience_log
        WHERE character_name = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC LIMIT 1
    ]], { char_name, start_str, end_str })

    -- Aggregate summary
    local rows, err = db:query([[
        SELECT
            MIN(timestamp)   AS first_time,
            MAX(timestamp)   AS last_time,
            MAX(experience)  AS end_exp,
            SUM(experience_gained) AS total_gained,
            SUM(CASE WHEN LOWER(source_type) IN ('normal', 'manual') THEN experience_gained ELSE 0 END) AS normal_exp,
            SUM(CASE WHEN source_type LIKE '%bounty%'  THEN experience_gained ELSE 0 END) AS bounty_exp,
            SUM(CASE WHEN source_type LIKE '%instant%' THEN experience_gained ELSE 0 END) AS instant_exp,
            COUNT(*) AS total_pulses,
            COUNT(DISTINCT DATE(timestamp)) AS days_active
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ? AND timestamp <= ?
    ]], { char_name, start_str, end_str })

    if err then echo("exptrack: query error: " .. err); return end

    local r = rows and rows[1]
    if not r or not r.total_gained then
        echo("No experience data found for the specified time period.")
        echo("Period: " .. start_str .. " to " .. end_str)
        return
    end

    local total_gained = r.total_gained or 0
    local normal_exp   = r.normal_exp   or 0
    local bounty_exp   = r.bounty_exp   or 0
    local instant_exp  = r.instant_exp  or 0

    -- Pulse multiplier breakdown (normal pulses only)
    local pulse_rows = db:query([[
        SELECT experience_gained
        FROM experience_log
        WHERE character_name = ? AND timestamp >= ? AND timestamp <= ?
          AND source_type NOT LIKE '%instant%'
          AND source_type NOT LIKE '%bounty%'
          AND experience_gained > 0
        ORDER BY timestamp ASC
    ]], { char_name, start_str, end_str })

    local mult_counts         = {}
    local total_normal_pulses = 0
    for _, pr in ipairs(pulse_rows or {}) do
        local pa    = pr.experience_gained or 0
        local label = "6x+"
        for _, m in ipairs(MULT_RANGES) do
            if pa >= m.min and pa <= m.max then label = m.label; break end
        end
        mult_counts[label]    = (mult_counts[label] or 0) + 1
        total_normal_pulses   = total_normal_pulses + 1
    end

    -- Duration and rate
    local duration_str = "N/A"
    local exp_per_hour = 0
    if r.first_time and r.last_time then
        local t1 = str_to_epoch(r.first_time)
        local t2 = str_to_epoch(r.last_time)
        if t1 and t2 then
            local dur   = t2 - t1
            local hours = math.floor(dur / 3600)
            local mins  = math.floor((dur % 3600) / 60)
            duration_str = string.format("%dh %dm", hours, mins)
            if dur > 0 then
                exp_per_hour = math.floor(total_gained * 3600 / dur)
            end
        end
    end

    -- Assemble report
    local lines = {}
    local function add(s) table.insert(lines, s) end

    local function pct(v)
        if total_gained > 0 then
            return string.format("%.2f", v * 100.0 / total_gained)
        end
        return "0.00"
    end

    add(string.rep("=", 60))
    add("Experience Report for " .. char_name)
    add("Period: " .. start_str .. " to " .. end_str)
    add(string.rep("-", 60))
    add("Starting Experience: " .. tostring(start_exp or "N/A"))
    add("Ending Experience:   " .. tostring(r.end_exp or "N/A"))
    add("Total Gained:        " .. tostring(total_gained))
    add("")
    add("Breakdown by Type:")
    add(string.format("  Normal:   %d (%s%%)",  normal_exp,  pct(normal_exp)))
    add(string.format("  Bounty:   %d (%s%%)",  bounty_exp,  pct(bounty_exp)))
    add(string.format("  Instant:  %d (%s%%)",  instant_exp, pct(instant_exp)))
    add("")

    if total_normal_pulses > 0 then
        add("Pulse Multiplier Breakdown (excluding instant/bounty):")
        for _, m in ipairs(MULT_RANGES) do
            local count = mult_counts[m.label] or 0
            if count > 0 then
                local mp = count * 100.0 / total_normal_pulses
                add(string.format("  %-5s: %6d pulses (%6.2f%%) [%s]",
                    m.label, count, mp, m.range))
            end
        end
        add(string.format("  Total: %5d normal pulses", total_normal_pulses))
        add("")
    end

    add("Statistics:")
    add("  Duration:     " .. duration_str)
    add("  Rate:         " .. tostring(exp_per_hour) .. " exp/hour")
    add("  Total Pulses: " .. tostring(r.total_pulses or 0))
    add("  Days Active:  " .. tostring(r.days_active  or 0))
    add(string.rep("=", 60))

    if exp_per_hour > 5000 and normal_exp > instant_exp + bounty_exp then
        add("")
        add("Note: High sustained experience rate detected.")
        add("This may indicate RPA orb or other exp bonus was active.")
    end

    respond(table.concat(lines, "\n"))
end

local function cmd_addgain(args)
    local gain_str = args:match("^(%d+)$")
    if not gain_str then
        echo("Usage: ;exptrack addgain <number>")
        return
    end
    local gain      = tonumber(gain_str)
    local char_name = Char.name or "Unknown"
    local now       = os.date("%Y-%m-%d %H:%M:%S")
    db:exec(
        "INSERT INTO experience_log (timestamp, experience, experience_gained, character_name, source_type) VALUES (?, ?, ?, ?, ?)",
        { now, 0, gain, char_name, "manual" }
    )
    echo("Manually added experience gain: " .. tostring(gain))
end

local function cmd_clean()
    db:exec("DELETE FROM experience_log WHERE experience_gained = 0")
    local deleted = db:changes()
    echo("Removed " .. tostring(deleted) .. " entries with 0 experience gained")
end

local function cmd_reset()
    echo("WARNING: This will permanently delete ALL experience tracking data!")
    echo("To confirm reset, type: ;exptrack confirm_reset")
end

local function cmd_confirm_reset()
    db:exec("DELETE FROM experience_log")
    local deleted = db:changes()
    echo("Database reset complete. Removed " .. tostring(deleted) .. " entries.")
    last_exp = nil
end

-- ─── Command Dispatch ───────────────────────────────────────────────────────

local function process_command(cmd)
    if cmd == "help" or cmd == "" then
        cmd_help()
    elseif cmd == "session" then
        cmd_session()
    elseif cmd == "last" then
        cmd_last()
    elseif cmd == "instant" then
        cmd_instant()
    elseif cmd == "today" then
        cmd_today()
    elseif cmd == "daily" then
        cmd_daily()
    elseif cmd == "hour" then
        cmd_hour()
    elseif cmd:sub(1, 6) == "report" then
        cmd_report(cmd:sub(7):match("^%s*(.-)%s*$") or "")
    elseif cmd:sub(1, 7) == "addgain" then
        cmd_addgain(cmd:sub(8):match("^%s*(.-)%s*$") or "")
    elseif cmd == "clean" then
        cmd_clean()
    elseif cmd == "reset" then
        cmd_reset()
    elseif cmd == "confirm_reset" then
        cmd_confirm_reset()
    else
        echo("Unknown command '" .. cmd .. "'. Type ;exptrack help for commands.")
    end
end

-- ─── Main Loop ──────────────────────────────────────────────────────────────

echo("Experience tracking started. Type ';exptrack help' for commands.")

while true do
    if #cmd_queue > 0 then
        process_command(table.remove(cmd_queue, 1))
    end
    pause(0.1)
end
