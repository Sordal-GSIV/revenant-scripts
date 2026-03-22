--- @revenant-script
--- name: tablewatch
--- version: 2.0
--- author: Fulmen
--- game: gs
--- description: Enhanced table protection - blocks EXIT while deployed, tracks location/timer
--- tags: merchant, table, protection
--- @lic-certified: complete 2026-03-20
---
--- Ported from Fulmen's Enhanced Tablewatch v2.0 (tablewatch.lic)
---
--- Changelog (Revenant port):
---   - Exit blocking via UpstreamHook instead of ;alias add exit=
---   - CLI settings (timer/location/quiet/noisy) now persisted via CharSettings
---   - Table name detection from GameObj.loot()
---   - Table name capture from deployment text pattern
---   - Speech window notifications via stream_window()
---   - Audio alert via ASCII BEL (suppress with ;tablewatch quiet)
---   - Timer reset detection on hug/nudge
---   - Full help text matching original
---
--- Usage:
---   ;tablewatch                - Start monitoring
---   ;tablewatch help           - Show help
---   ;tablewatch timer <min>    - Set timer reminder interval (saved, default: 15)
---   ;tablewatch location <min> - Set location reminder interval (saved, default: 5)
---   ;tablewatch quiet          - Disable audio alerts (saved)
---   ;tablewatch noisy          - Enable audio alerts (saved)

local VERSION = "2.0"
local HOOK_DS = "tablewatch_detect"
local HOOK_US = "tablewatch_exit_block"

-- ── Settings (persisted via CharSettings) ─────────────────────────────────────

local function load_cfg()
    return {
        timer_interval    = tonumber(CharSettings["tablewatch_timer"])    or 15,
        location_interval = tonumber(CharSettings["tablewatch_location"]) or 5,
        quiet_mode        = CharSettings["tablewatch_quiet"] == "true",
    }
end

local function save_cfg(cfg)
    CharSettings["tablewatch_timer"]    = tostring(cfg.timer_interval)
    CharSettings["tablewatch_location"] = tostring(cfg.location_interval)
    CharSettings["tablewatch_quiet"]    = cfg.quiet_mode and "true" or "false"
end

-- ── CLI arg handling ───────────────────────────────────────────────────────────

local cmd = (Script.vars[1] or ""):lower()
local arg = Script.vars[2]

if cmd == "help" or cmd == "-h" or cmd == "--help" then
    respond(string.format([[

Tablewatch - Enhanced Table Protection Script v%s

USAGE:
  ;tablewatch                Start monitoring your table
  ;tablewatch help           Show this help message
  ;tablewatch timer <min>    Set timer reminder interval (default: 15)
  ;tablewatch location <min> Set location reminder interval (default: 5)
  ;tablewatch quiet          Disable audio alerts
  ;tablewatch noisy          Enable audio alerts

WHAT IT DOES:
  - Blocks the EXIT command while your table is deployed
  - Tracks which room you deployed your table in
  - Warns when you leave the table room behind
  - Reminds you regularly if you stay away
  - Automatically shuts down when you TINKER to pack the table
  - Restores normal exit functionality when done

HOW TO USE:
  1. Deploy your table in a room
  2. Start the script: ;tablewatch
  3. Script blocks exit and tracks your location
  4. When done, TINKER your table to pack it up
  5. Script automatically removes exit blocking

TIP:
  I recommend adding an alias like:
  ;alias add prod=;e  start_script("tablewatch"); fput "prod my basket"
  This will make sure to start the script whenever you turn your
  basket into a table.

ALERTS:
  - Visual warning when you leave the table room
  - Audio beep to get your attention (can be disabled)
  - Speech window notification for visibility
  - Repeated reminders while away (customizable intervals)
  - Timer warnings (customizable intervals)
  - Critical warning at 15 minutes remaining

Settings are saved and restored across sessions.
The script prevents accidental logouts while your valuable table
is deployed, ensuring you don't lose it by exiting carelessly.

]], VERSION))
    exit()
end

if cmd == "timer" then
    local cfg = load_cfg()
    local val = arg and tonumber(arg)
    if val and val > 0 then
        cfg.timer_interval = val
        save_cfg(cfg)
        echo(string.format("Timer reminder interval set to %d minutes", val))
    else
        echo("Usage: ;tablewatch timer <minutes>")
    end
    exit()
end

if cmd == "location" then
    local cfg = load_cfg()
    local val = arg and tonumber(arg)
    if val and val > 0 then
        cfg.location_interval = val
        save_cfg(cfg)
        echo(string.format("Location reminder interval set to %d minutes", val))
    else
        echo("Usage: ;tablewatch location <minutes>")
    end
    exit()
end

if cmd == "quiet" then
    local cfg = load_cfg()
    cfg.quiet_mode = true
    save_cfg(cfg)
    echo("Audio alerts disabled")
    exit()
end

if cmd == "noisy" then
    local cfg = load_cfg()
    cfg.quiet_mode = false
    save_cfg(cfg)
    echo("Audio alerts enabled")
    exit()
end

-- ── Runtime state ──────────────────────────────────────────────────────────────

local cfg             = load_cfg()
local table_room      = Room.id
local table_room_name = Room.title or "Unknown"
local away            = false
local start_time      = os.time()
local last_reminder   = os.time()
local last_timer_warn = os.time()
local critical_warned = false
local table_name      = "table"

-- Try to detect table name from room loot
local function find_table_name()
    local loot = GameObj.loot()
    local found = {}
    for _, obj in ipairs(loot) do
        if obj.noun == "table" then
            found[#found + 1] = obj.name
        end
    end
    if #found == 1 then
        return found[1]
    elseif #found > 1 then
        return "table (multiple found)"
    end
    return nil
end

-- Retry detection up to 3 times with 0.5s gaps (handles GameObj lag at deploy)
for _ = 1, 3 do
    local n = find_table_name()
    if n then table_name = n; break end
    pause(0.5)
end

-- ── Alert helper ───────────────────────────────────────────────────────────────

local function alert(msg)
    echo(msg)
    stream_window(msg, "speech")
    if not cfg.quiet_mode then
        respond("\007")  -- ASCII BEL — audio alert for the client
    end
end

-- ── Exit blocking (UpstreamHook) ──────────────────────────────────────────────

UpstreamHook.add(HOOK_US, function(line)
    -- Strip <c> XML prefix and trailing whitespace/newline
    local stripped = (line:match("^<c>(.+)$") or line):match("^%s*(.-)%s*\r?\n?$")
    if stripped and stripped:lower() == "exit" then
        echo(string.format(
            "Exit blocked - Your '%s' is still deployed at %s! TINKER table to pack it up first.",
            table_name, table_room_name))
        return ""  -- squelch the exit command
    end
    return line
end)

-- ── Detection hook (DownstreamHook) ───────────────────────────────────────────

DownstreamHook.add(HOOK_DS, function(line)
    local low = line:lower()

    -- Capture table name from deployment text
    local captured = low:match("transforms into a (.+ table)")
    if not captured then
        captured = low:match("becomes .+ into a (.+ table)")
    end
    if captured then
        table_name = captured:match("^%s*(.-)%s*$")
        echo(string.format("Captured table name from deployment: '%s'", table_name))
    end

    -- Table packed: "you trigger the transformation" / "pick ... basket ... up" / "folds into basket"
    if low:match("you trigger the transformation")
    or low:match("you pick.+basket.+up")
    or low:match("table.+folds.+into.+basket") then
        echo(string.format("Your '%s' at %s packed! Shutting down.", table_name, table_room_name))
        UpstreamHook.remove(HOOK_US)
        DownstreamHook.remove(HOOK_DS)
        exit()
    end

    -- Timer reset via hug/nudge: resets the 120-minute countdown
    if (low:match("you nudge.+table") or low:match("you hug.+table"))
    and (low:match("refresh") or low:match("reset"))
    and low:match("120") then
        start_time      = os.time()
        last_timer_warn = os.time()
        critical_warned = false
        echo(string.format(
            "Your '%s' timer reset to 120 minutes by HUG - timer refreshed!", table_name))
    end

    return line
end)

-- ── Cleanup on script exit ─────────────────────────────────────────────────────

before_dying(function()
    UpstreamHook.remove(HOOK_US)
    DownstreamHook.remove(HOOK_DS)
    echo("Exit blocking removed. You can now exit normally.")
end)

-- ── Startup messages ───────────────────────────────────────────────────────────

echo(string.format("Enhanced Tablewatch v%s ready", VERSION))
echo(string.format("Started. Table deployed in %s", table_room_name))
echo(string.format("Table name: '%s'", table_name))
echo("Exit command blocked until table is packed")
echo("Table timer: 120 minutes remaining")
echo(string.format(
    "Reminders: timer every %d min | location every %d min | audio %s",
    cfg.timer_interval, cfg.location_interval,
    cfg.quiet_mode and "off" or "on"))

-- ── Main monitoring loop ───────────────────────────────────────────────────────

while true do
    local current = Room.id

    -- Location tracking
    if current and table_room then
        if current ~= table_room and not away then
            -- First time leaving the table room
            away          = true
            last_reminder = os.time()
            alert(string.format(
                "WARNING: You just left your '%s' behind at %s!",
                table_name, table_room_name))

        elseif current ~= table_room and away then
            -- Still away — periodic reminders
            if (os.time() - last_reminder) >= cfg.location_interval * 60 then
                echo(string.format(
                    "REMINDER: Your '%s' is still deployed at %s!",
                    table_name, table_room_name))
                last_reminder = os.time()
            end

        elseif current == table_room and away then
            -- Returned to table
            away = false
            echo(string.format(
                "You are back at your '%s' at %s", table_name, table_room_name))
        end
    end

    -- Timer tracking
    local rem_secs = math.max(0, 7200 - (os.time() - start_time))
    local rem_min  = math.floor(rem_secs / 60)

    -- Critical warning at ≤15 minutes (fires once per table session)
    if rem_min <= 15 and not critical_warned then
        alert(string.format(
            "WARNING: Only %d minutes left on your '%s' at %s! HUG your table now or it will disappear!",
            rem_min, table_name, table_room_name))
        critical_warned = true
        last_timer_warn = os.time()
    end

    -- Regular interval timer reminders
    if (os.time() - last_timer_warn) >= cfg.timer_interval * 60 then
        if rem_min > 0 then
            echo(string.format(
                "Table timer: %d minutes remaining on your '%s' at %s",
                rem_min, table_name, table_room_name))
        else
            echo(string.format(
                "Table timer: EXPIRED! Your '%s' at %s may collapse soon!",
                table_name, table_room_name))
        end
        last_timer_warn = os.time()
    end

    -- Lazy-refresh table name if still generic and we're at the table room
    if table_name == "table" and current == table_room then
        local refreshed = find_table_name()
        if refreshed and refreshed ~= "table" then
            table_name = refreshed
            echo(string.format("Table name updated: '%s'", table_name))
        end
    end

    pause(1)
end
