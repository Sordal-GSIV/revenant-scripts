--- @revenant-script
--- name: tentwatch
--- version: 2.0
--- author: Fulmen
--- game: gs
--- description: Enhanced tent protection - blocks EXIT while deployed, tracks location and collapse timer
--- tags: camping, tent, protection
--- @lic-certified: complete 2026-03-20
---
--- Ported from Fulmen's Enhanced Tentwatch v2.0 (tentwatch.lic)
---
--- Changelog (Revenant port):
---   - Exit blocking via UpstreamHook instead of ;alias add exit=
---   - CLI settings (timer/location/collapse/quiet/noisy) persisted via CharSettings
---   - Tent name detection from GameObj.loot()
---   - Tent name capture from deployment text pattern
---   - Inside-tent detection (negative room IDs titled "Tent" are treated as safe)
---   - Collapse timer: warns every 3 min while away, urgent at collapse_threshold-2 min
---   - TENT COLLAPSED message once threshold is reached (then rate-limited)
---   - Startup detection of already-deployed tent in current room
---   - Speech window notifications via stream_window()
---   - Audio alert via ASCII BEL (suppress with ;tentwatch quiet)
---   - Full help text matching original
---
--- Usage:
---   ;tentwatch                 - Start monitoring
---   ;tentwatch help            - Show help
---   ;tentwatch timer <min>     - Set timer reminder interval (saved, default: 15)
---   ;tentwatch location <min>  - Set location reminder interval (saved, default: 1)
---   ;tentwatch collapse <min>  - Set collapse warning threshold (saved, default: 20)
---   ;tentwatch quiet           - Disable audio alerts (saved)
---   ;tentwatch noisy           - Enable audio alerts (saved)

local VERSION  = "2.0"
local HOOK_DS  = "tentwatch_detect"
local HOOK_US  = "tentwatch_exit_block"

-- ── Settings (persisted via CharSettings) ──────────────────────────────────

local function load_cfg()
    return {
        timer_interval     = tonumber(CharSettings["tentwatch_timer"])     or 15,
        location_interval  = tonumber(CharSettings["tentwatch_location"])  or 1,
        collapse_threshold = tonumber(CharSettings["tentwatch_collapse"])  or 20,
        quiet_mode         = CharSettings["tentwatch_quiet"] == "true",
    }
end

local function save_cfg(cfg)
    CharSettings["tentwatch_timer"]     = tostring(cfg.timer_interval)
    CharSettings["tentwatch_location"]  = tostring(cfg.location_interval)
    CharSettings["tentwatch_collapse"]  = tostring(cfg.collapse_threshold)
    CharSettings["tentwatch_quiet"]     = cfg.quiet_mode and "true" or "false"
end

-- ── CLI arg handling ────────────────────────────────────────────────────────

local cmd = (Script.vars[1] or ""):lower()
local arg = Script.vars[2]

if cmd == "help" or cmd == "-h" or cmd == "--help" then
    respond(string.format([[

Tentwatch - Enhanced Tent Protection Script v%s

USAGE:
  ;tentwatch                Start monitoring your tent
  ;tentwatch help           Show this help message
  ;tentwatch timer <min>    Set timer reminder interval (default: 15)
  ;tentwatch location <min> Set location reminder interval (default: 1)
  ;tentwatch quiet          Disable audio alerts
  ;tentwatch noisy          Enable audio alerts
  ;tentwatch collapse <min> Set collapse warning threshold (default: 20)

WHAT IT DOES:
  - Blocks the EXIT command while your tent is deployed
  - Tracks which room you deployed your tent in
  - Warns when you leave the tent room behind
  - Reminds you regularly if you stay away
  - Automatically shuts down when you FOLD your tent
  - Restores normal exit functionality when done
  - Monitors tent timer (deployment elapsed time)
  - Warns about potential tent collapse after extended absence

HOW TO USE:
  1. Deploy your tent in a room with STAND TENT
  2. Start the script: ;tentwatch
  3. Script blocks exit and tracks your location
  4. When done, FOLD your tent to pack it up
  5. Script automatically removes exit blocking

TIP:
  I recommend adding an alias like:
  ;alias add tent=;e start_script("tentwatch"); fput "stand tent"
  This will make sure to start the script whenever you deploy
  your tent.

ALERTS:
  - Visual warning when you leave the tent room
  - Audio beep to get your attention (can be disabled)
  - Speech window notification for visibility
  - Repeated reminders while away (customizable intervals)
  - Timer warnings (customizable intervals)
  - Collapse warnings when away too long

Settings are saved and restored across sessions.
The script prevents accidental logouts while your tent is
deployed, ensuring you don't lose it by exiting carelessly.

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
        echo("Usage: ;tentwatch timer <minutes>")
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
        echo("Usage: ;tentwatch location <minutes>")
    end
    exit()
end

if cmd == "collapse" then
    local cfg = load_cfg()
    local val = arg and tonumber(arg)
    if val and val > 0 then
        cfg.collapse_threshold = val
        save_cfg(cfg)
        echo(string.format("Collapse warning threshold set to %d minutes", val))
    else
        echo("Usage: ;tentwatch collapse <minutes>")
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

-- ── Runtime state ───────────────────────────────────────────────────────────

local cfg             = load_cfg()
local tent_deployed   = false
local tent_room       = nil
local tent_room_name  = "Unknown"
local tent_name       = "tent"

local away            = false
local away_started    = nil
local last_reminder   = os.time()
local last_timer_warn = os.time()
local last_collapse_w = 0      -- epoch 0 so first check fires after 3-min gap
local collapse_alerted = false -- set once TENT COLLAPSED fires; reset on return

local start_time      = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- Returns true when the current room is the inside of a deployed tent.
-- GemStone tent interiors use negative room IDs with "Tent" in the title.
local function inside_tent()
    local id = Room.id
    if id and id < 0 then
        local title = Room.title or ""
        return title:find("Tent") ~= nil
    end
    return false
end

-- Search room loot for an object whose noun is "tent".
local function find_tent_name()
    local loot = GameObj.loot()
    local found = {}
    for _, obj in ipairs(loot) do
        if obj.noun == "tent" then
            found[#found + 1] = obj.name
        end
    end
    if #found == 1 then
        return found[1]
    elseif #found > 1 then
        return "tent (multiple found)"
    end
    return nil
end

-- Echo + speech window + optional BEL.
local function alert(msg)
    echo(msg)
    stream_window(msg, "speech")
    if not cfg.quiet_mode then
        respond("\007")  -- ASCII BEL
    end
end

-- ── Startup: check for tent already deployed in current room ────────────────

local function check_existing_tent()
    for _ = 1, 3 do
        local n = find_tent_name()
        if n then
            tent_name       = n
            tent_room       = Room.id
            tent_room_name  = Room.title or "Unknown"
            tent_deployed   = true
            start_time      = os.time()
            last_timer_warn = os.time()
            return true
        end
        pause(0.5)
    end
    return false
end

-- ── Exit blocking (UpstreamHook) ─────────────────────────────────────────────

UpstreamHook.add(HOOK_US, function(line)
    if not tent_deployed then return line end
    local stripped = (line:match("^<c>(.+)$") or line):match("^%s*(.-)%s*\r?\n?$")
    if stripped and stripped:lower() == "exit" then
        echo(string.format(
            "Exit blocked - Your '%s' is still deployed at %s! FOLD TENT to pack it up first.",
            tent_name, tent_room_name))
        return ""  -- squelch
    end
    return line
end)

-- ── Detection hook (DownstreamHook) ──────────────────────────────────────────

DownstreamHook.add(HOOK_DS, function(line)
    local low = line:lower()

    -- Capture tent name from deployment text.
    -- "You quickly unfold the <a ...>some canvas tent</a>, ..."
    local captured = line:match("[Yy]ou quickly unfold the (.+tent[^,%.!<]*)")
    if captured then
        captured = captured:gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
        if captured and captured ~= "" then
            tent_name = captured
        end
    end

    -- Tent deployed.
    if low:match("you quickly unfold.*tent.*upright and ready to go") then
        tent_room       = Room.id
        tent_room_name  = Room.title or "Unknown"
        tent_deployed   = true
        away            = false
        away_started    = nil
        start_time      = os.time()
        last_timer_warn = os.time()
        last_collapse_w = 0
        collapse_alerted = false

        -- Brief pause then grab clean name from loot.
        pause(0.5)
        local n = find_tent_name()
        if n then tent_name = n end

        echo(string.format("Tent deployed in %s!", tent_room_name))
        echo("Exit command blocked until tent is packed")
        echo("Tent is safe while you remain here or inside tent (GO TENT)")
        echo(string.format(
            "WARNING: Tent will collapse after %d minutes if you leave the area!",
            cfg.collapse_threshold))
        alert("Tent deployed - Exit blocked!")

    -- Tent folded.
    elseif low:match("you methodically unhook.*tent.*fold it back up into a neat bundle") then
        echo(string.format(
            "Your '%s' at %s folded! Shutting down...", tent_name, tent_room_name))
        UpstreamHook.remove(HOOK_US)
        DownstreamHook.remove(HOOK_DS)
        exit()
    end

    return line
end)

-- ── Cleanup on script exit ───────────────────────────────────────────────────

before_dying(function()
    UpstreamHook.remove(HOOK_US)
    DownstreamHook.remove(HOOK_DS)
    if tent_deployed then
        echo("Exit blocking removed. You can now exit normally.")
    end
end)

-- ── Startup messages ─────────────────────────────────────────────────────────

echo(string.format("Enhanced Tentwatch v%s ready", VERSION))
echo(string.format(
    "Settings: timer every %d min | location every %d min | collapse at %d min | audio %s",
    cfg.timer_interval, cfg.location_interval, cfg.collapse_threshold,
    cfg.quiet_mode and "off" or "on"))

if check_existing_tent() then
    echo(string.format("Found existing tent '%s' in %s", tent_name, tent_room_name))
    echo("Exit command blocked until tent is packed")
    echo("Tent is safe while you remain in this room or inside tent")
    echo(string.format(
        "WARNING: Tent will collapse after %d minutes if you leave the area!",
        cfg.collapse_threshold))
    alert("Existing tent found - Exit blocked!")
else
    echo("Waiting for tent deployment... Use STAND TENT to begin monitoring")
end

-- ── Main monitoring loop ─────────────────────────────────────────────────────

while true do
    if tent_deployed then
        local current  = Room.id
        local in_tent  = inside_tent()
        local safe     = (current == tent_room) or in_tent
        local now      = os.time()

        -- ── Location / collapse tracking ─────────────────────────────────────

        if not safe and not away then
            -- First time leaving the tent area.
            away            = true
            away_started    = now
            last_reminder   = now
            last_collapse_w = now
            collapse_alerted = false

            alert(string.format(
                "WARNING: You just left your '%s' behind at %s! Collapse timer started - you have %d minutes.",
                tent_name, tent_room_name, cfg.collapse_threshold))

        elseif not safe and away then
            local elapsed        = now - away_started
            local collapse_secs  = cfg.collapse_threshold * 60
            local urgent_secs    = (cfg.collapse_threshold - 2) * 60

            -- Periodic location reminder.
            if (now - last_reminder) >= cfg.location_interval * 60 then
                echo(string.format(
                    "REMINDER: Your '%s' collapse timer is running! Return to %s or go inside tent.",
                    tent_name, tent_room_name))
                last_reminder = now
            end

            -- Collapse warnings.
            if elapsed >= collapse_secs then
                -- Tent has collapsed.
                if not collapse_alerted or (now - last_collapse_w) >= 180 then
                    alert(string.format(
                        "TENT COLLAPSED: Your tent at %s has collapsed after %d minutes away!",
                        tent_room_name, cfg.collapse_threshold))
                    last_collapse_w  = now
                    collapse_alerted = true
                end

            elseif elapsed >= urgent_secs then
                -- Urgent: last 2 minutes (rate-limited to every 30 seconds).
                if (now - last_collapse_w) >= 30 then
                    local rem_mins = math.ceil((collapse_secs - elapsed) / 60)
                    alert(string.format(
                        "URGENT: Your tent will collapse in %d minute(s)! Return to %s or GO TENT immediately!",
                        rem_mins, tent_room_name))
                    last_collapse_w = now
                end

            elseif (now - last_collapse_w) >= 180 then
                -- Regular warning every 3 minutes while away.
                local rem_mins    = math.floor((collapse_secs - elapsed) / 60)
                local elapsed_min = math.floor(elapsed / 60)
                if rem_mins > 0 then
                    alert(string.format(
                        "COLLAPSE WARNING: %d minute(s) remaining until tent collapse! (Away for %d minutes)",
                        rem_mins, elapsed_min))
                else
                    alert("COLLAPSE WARNING: Less than 1 minute until tent collapse! Return immediately!")
                end
                last_collapse_w = now
            end

        elseif safe and away then
            -- Returned to tent area.
            away             = false
            away_started     = nil
            last_collapse_w  = 0
            collapse_alerted = false

            if in_tent then
                echo("You are inside your tent - collapse timer stopped")
            else
                echo(string.format(
                    "You are back at your '%s' at %s - collapse timer stopped",
                    tent_name, tent_room_name))
            end
        end

        -- ── Deployment timer reminder ─────────────────────────────────────────

        if start_time and (now - last_timer_warn) >= cfg.timer_interval * 60 then
            local elapsed_min = math.floor((now - start_time) / 60)
            echo(string.format(
                "Tent status: %d minutes since deployment in %s",
                elapsed_min, tent_room_name))
            last_timer_warn = now
        end

        -- ── Lazy-refresh tent name if still generic ───────────────────────────

        if tent_name == "tent" and current == tent_room then
            local n = find_tent_name()
            if n then
                tent_name = n
                echo(string.format("Tent name updated: '%s'", tent_name))
            end
        end
    end

    pause(1)
end
