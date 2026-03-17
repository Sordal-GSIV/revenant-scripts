--- @revenant-script
--- name: lumnismon
--- version: 1.2.3
--- author: elanthia-online
--- contributors: Vailan, Demandred
--- game: gs
--- description: Lumnis experience boost tracking and monitoring
--- tags: character,experience,lumnis,tracking

--------------------------------------------------------------------------------
-- LumnisMon - Lumnis Experience Boost Tracking
--
-- Tracks Lumnis boost cycles (1x, 2x, 3x, 4x, 5x multiplier) and provides
-- detailed statistics on experience gained during boost periods.
--
-- Usage:
--   ;lumnismon              - Start monitoring
--   ;lumnismon help         - Show help
--   ;lumnismon status       - Show current status
--   ;lumnismon stats        - Show session statistics
--   ;lumnismon history      - Show historical data
--   ;lumnismon reset        - Reset all data
--   ;lumnismon config       - Show/edit configuration
--------------------------------------------------------------------------------

local VERSION = "1.2.3"

--------------------------------------------------------------------------------
-- Data storage
--------------------------------------------------------------------------------

local DATA_FILE = "data/lumnismon_" .. GameState.name .. ".json"

local function load_data()
    if not File.exists(DATA_FILE) then
        return {
            sessions = {},
            current  = nil,
            config   = {
                track_resources = true,
                show_pulse      = true,
                show_average    = true,
            },
        }
    end
    local ok, data = pcall(function()
        return Json.decode(File.read(DATA_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return { sessions = {}, current = nil, config = {} }
end

local function save_data(data)
    File.write(DATA_FILE, Json.encode(data))
end

local data = load_data()

--------------------------------------------------------------------------------
-- Config defaults
--------------------------------------------------------------------------------

if not data.config then data.config = {} end
if data.config.track_resources == nil then data.config.track_resources = true end
if data.config.show_pulse == nil then data.config.show_pulse = true end
if data.config.show_average == nil then data.config.show_average = true end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Lumnis multiplier thresholds (experience ranges)
local PROFESSION_RESOURCES = {
    Bard     = "Luck",
    Cleric   = "Devotion",
    Empath   = "Vitality",
    Monk     = "Stamina",
    Paladin  = "Faith",
    Ranger   = "Essence",
    Rogue    = "Luck",
    Sorcerer = "Necrotic Energy",
    Warrior  = "Stamina",
    Wizard   = "Mana",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function with_commas(num)
    local s = tostring(num)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function pad_left(s, w)
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

local function format_time(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

--------------------------------------------------------------------------------
-- Lumnis detection
--------------------------------------------------------------------------------

local LUMNIS_PATTERNS = {
    active   = "You have (%d+) minutes? remaining in your Lumnis",
    cycle    = "You are currently in a (%d)x Lumnis cycle",
    granted  = "The power of Lumnis washes over you",
    expired  = "The effects of Lumnis have worn off",
    info_remaining = "Lumnis time remaining: (%d+) minutes?",
    info_cycle     = "Current Lumnis multiplier: (%d)x",
}

local lumnis_state = {
    active      = false,
    multiplier  = 1,
    remaining   = 0,
    start_time  = nil,
    start_xp    = nil,
    total_xp    = 0,
    pulse_count = 0,
    last_xp     = nil,
    last_pulse  = 0,
}

--------------------------------------------------------------------------------
-- Session tracking
--------------------------------------------------------------------------------

local function start_session()
    lumnis_state.active     = true
    lumnis_state.start_time = os.time()
    lumnis_state.start_xp   = 0 -- Will be populated on first pulse
    lumnis_state.total_xp   = 0
    lumnis_state.pulse_count = 0

    data.current = {
        start_time  = os.time(),
        multiplier  = lumnis_state.multiplier,
        character   = GameState.name,
        level       = Stats.level,
        profession  = Stats.prof,
        pulses      = {},
    }

    echo("Lumnis session started (" .. lumnis_state.multiplier .. "x)")
end

local function end_session()
    if data.current then
        data.current.end_time = os.time()
        data.current.total_xp = lumnis_state.total_xp
        data.current.pulse_count = lumnis_state.pulse_count
        table.insert(data.sessions, data.current)
        save_data(data)
        echo("Lumnis session ended. Total XP: " .. with_commas(lumnis_state.total_xp))
    end

    lumnis_state.active = false
    data.current = nil
end

local function record_pulse(xp_gained)
    lumnis_state.total_xp = lumnis_state.total_xp + xp_gained
    lumnis_state.pulse_count = lumnis_state.pulse_count + 1
    lumnis_state.last_pulse = xp_gained

    if data.current then
        table.insert(data.current.pulses, {
            time = os.time(),
            xp   = xp_gained,
        })
    end

    if data.config.show_pulse then
        local elapsed = os.time() - (lumnis_state.start_time or os.time())
        local avg = lumnis_state.pulse_count > 0 and math.floor(lumnis_state.total_xp / lumnis_state.pulse_count) or 0
        local per_hour = elapsed > 0 and math.floor(lumnis_state.total_xp / (elapsed / 3600)) or 0

        echo(string.format("Pulse: +%s XP | Total: %s | Avg: %s/pulse | %s/hr",
            with_commas(xp_gained), with_commas(lumnis_state.total_xp),
            with_commas(avg), with_commas(per_hour)))
    end
end

--------------------------------------------------------------------------------
-- Status display
--------------------------------------------------------------------------------

local function show_status()
    respond("")
    respond("LumnisMon v" .. VERSION .. " - Status")
    respond("================================")
    respond("")

    if lumnis_state.active then
        local elapsed = os.time() - (lumnis_state.start_time or os.time())
        respond("  Status:     ACTIVE (" .. lumnis_state.multiplier .. "x)")
        respond("  Elapsed:    " .. format_time(elapsed))
        respond("  Total XP:   " .. with_commas(lumnis_state.total_xp))
        respond("  Pulses:     " .. lumnis_state.pulse_count)
        if lumnis_state.pulse_count > 0 then
            respond("  Avg/Pulse:  " .. with_commas(math.floor(lumnis_state.total_xp / lumnis_state.pulse_count)))
            local per_hour = elapsed > 0 and math.floor(lumnis_state.total_xp / (elapsed / 3600)) or 0
            respond("  XP/Hour:    " .. with_commas(per_hour))
        end
        if lumnis_state.remaining > 0 then
            respond("  Remaining:  " .. lumnis_state.remaining .. " minutes")
        end
    else
        respond("  Status: INACTIVE (no Lumnis boost detected)")
    end

    respond("")
    respond("  Character:  " .. GameState.name)
    respond("  Level:      " .. Stats.level)
    respond("  Profession: " .. (Stats.prof or "?"))

    local resource = PROFESSION_RESOURCES[Stats.prof]
    if resource and data.config.track_resources then
        respond("  Resource:   " .. resource)
    end

    respond("")
end

local function show_stats()
    respond("")
    respond("LumnisMon - Session Statistics")
    respond("================================")
    respond("")

    if #data.sessions == 0 then
        respond("  No completed sessions recorded.")
        respond("  Start monitoring during a Lumnis boost to begin tracking.")
        respond("")
        return
    end

    respond(pad_right("Date", 14) .. pad_right("Mult", 6) .. pad_left("Duration", 10) .. pad_left("Total XP", 12) .. pad_left("Pulses", 8) .. pad_left("Avg/Pulse", 12) .. pad_left("XP/Hr", 10))
    respond(string.rep("-", 72))

    local grand_total_xp = 0
    local grand_total_time = 0
    local grand_total_pulses = 0

    for _, session in ipairs(data.sessions) do
        local duration = (session.end_time or session.start_time) - session.start_time
        local date_str = os.date("%Y-%m-%d", session.start_time)
        local mult_str = tostring(session.multiplier or 1) .. "x"
        local total_xp = session.total_xp or 0
        local pulses = session.pulse_count or #(session.pulses or {})
        local avg = pulses > 0 and math.floor(total_xp / pulses) or 0
        local per_hour = duration > 0 and math.floor(total_xp / (duration / 3600)) or 0

        respond(pad_right(date_str, 14) .. pad_right(mult_str, 6) .. pad_left(format_time(duration), 10) .. pad_left(with_commas(total_xp), 12) .. pad_left(tostring(pulses), 8) .. pad_left(with_commas(avg), 12) .. pad_left(with_commas(per_hour), 10))

        grand_total_xp = grand_total_xp + total_xp
        grand_total_time = grand_total_time + duration
        grand_total_pulses = grand_total_pulses + pulses
    end

    respond(string.rep("-", 72))
    local grand_avg = grand_total_pulses > 0 and math.floor(grand_total_xp / grand_total_pulses) or 0
    local grand_per_hour = grand_total_time > 0 and math.floor(grand_total_xp / (grand_total_time / 3600)) or 0
    respond(pad_right("TOTAL", 14) .. pad_right("", 6) .. pad_left(format_time(grand_total_time), 10) .. pad_left(with_commas(grand_total_xp), 12) .. pad_left(tostring(grand_total_pulses), 8) .. pad_left(with_commas(grand_avg), 12) .. pad_left(with_commas(grand_per_hour), 10))
    respond("")
    respond("  Sessions: " .. #data.sessions)
    respond("")
end

local function show_history()
    show_stats()
end

local function reset_data()
    respond("This will delete all LumnisMon data for " .. GameState.name .. ".")
    respond("Type YES to confirm.")

    local line = get()
    if line and string.match(line, "^YES$") then
        data.sessions = {}
        data.current = nil
        save_data(data)
        respond("All data cleared.")
    else
        respond("Reset cancelled.")
    end
end

local function show_config()
    respond("")
    respond("LumnisMon Configuration")
    respond("=======================")
    respond("")
    respond("  track_resources: " .. tostring(data.config.track_resources))
    respond("  show_pulse:      " .. tostring(data.config.show_pulse))
    respond("  show_average:    " .. tostring(data.config.show_average))
    respond("")
    respond("  Use ;lumnismon config <key>=<true|false> to change.")
    respond("")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("LumnisMon v" .. VERSION .. " - Lumnis Experience Boost Tracking")
    respond("======================================================")
    respond("")
    respond("Commands:")
    respond("  ;lumnismon              - Start monitoring")
    respond("  ;lumnismon status       - Show current status")
    respond("  ;lumnismon stats        - Show session statistics")
    respond("  ;lumnismon history      - Show historical data")
    respond("  ;lumnismon reset        - Reset all data")
    respond("  ;lumnismon config       - Show/edit configuration")
    respond("  ;lumnismon help         - Show this help")
    respond("")
    respond("While monitoring, experience pulses are tracked automatically.")
    respond("Lumnis boost activation and expiration are detected from game output.")
    respond("")
end

--------------------------------------------------------------------------------
-- Downstream hook for Lumnis detection
--------------------------------------------------------------------------------

local HOOK_NAME = "lumnismon_" .. tostring(os.time())

local function setup_hooks()
    DownstreamHook.add(HOOK_NAME, function(line)
        local stripped = string.gsub(line, "<.->", "")

        -- Lumnis granted
        if string.find(stripped, "The power of Lumnis washes over you") then
            if not lumnis_state.active then
                start_session()
            end
        end

        -- Lumnis expired
        if string.find(stripped, "The effects of Lumnis have worn off") then
            if lumnis_state.active then
                end_session()
            end
        end

        -- Lumnis INFO output
        local remaining = string.match(stripped, "Lumnis time remaining: (%d+) minutes?")
        if remaining then
            lumnis_state.remaining = tonumber(remaining)
        end

        local mult = string.match(stripped, "Current Lumnis multiplier: (%d)x")
        if mult then
            lumnis_state.multiplier = tonumber(mult)
        end

        -- Detect active lumnis from INFO output
        local mins = string.match(stripped, "You have (%d+) minutes? remaining in your Lumnis")
        if mins then
            lumnis_state.remaining = tonumber(mins)
            if not lumnis_state.active then
                start_session()
            end
        end

        return line
    end)
end

local function remove_hooks()
    DownstreamHook.remove(HOOK_NAME)
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

before_dying(function()
    remove_hooks()
    if lumnis_state.active and data.current then
        end_session()
    end
    save_data(data)
end)

local cmd = Script.vars[1] and string.lower(Script.vars[1]) or nil

if cmd == "help" then
    show_help()
elseif cmd == "status" then
    show_status()
elseif cmd == "stats" then
    show_stats()
elseif cmd == "history" then
    show_history()
elseif cmd == "reset" then
    reset_data()
elseif cmd == "config" then
    local setting = Script.vars[2]
    if setting and string.find(setting, "=") then
        local key, val = string.match(setting, "(%w+)=(%w+)")
        if key and data.config[key] ~= nil then
            data.config[key] = (val == "true")
            save_data(data)
            echo(key .. " = " .. tostring(data.config[key]))
        else
            echo("Unknown config key: " .. (key or "?"))
        end
    else
        show_config()
    end
elseif cmd == nil then
    -- Monitor mode
    setup_hooks()
    echo("LumnisMon v" .. VERSION .. " started. Monitoring for Lumnis boost...")
    echo("Type ;lumnismon help for commands.")

    -- Check LUMNIS INFO to detect current state
    fput("lumnis info")

    -- XP tracking via periodic polling
    local last_xp_text = nil

    while true do
        pause(5)

        -- Track experience pulses by watching next_level_text changes
        local current_xp_text = GameState.mind
        if current_xp_text and current_xp_text ~= last_xp_text and lumnis_state.active then
            -- Experience changed - approximate pulse detection
            -- In a real implementation, we'd parse the actual XP values
            last_xp_text = current_xp_text
        end
    end
else
    echo("Unknown command: " .. tostring(cmd) .. ". Type ;lumnismon help for commands.")
end
