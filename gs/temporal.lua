--- @revenant-script
--- @lic-audit: validated 2026-03-18
--- name: temporal
--- version: 0.4.0
--- author: Nick S
--- game: gs
--- tags: temporal, flare, timing, enchant, combat, utility
--- description: Temporal flare timing helper - waits for specific Unix timestamp tail digits to fire weapon actions
---
--- Original Lich5 authors: Nick S
--- Ported to Revenant Lua from temporal.lic
---
--- Changelog (from Lich5):
---   v0.4.0: Full CLI arg handling, auto offset via SNTP or GameState.server_time,
---           next-flare computation, death flare support, manual offset mode
---
--- Usage:
---   ;temporal                                  - run with saved config
---   ;temporal auto                             - auto-detect offset and run with saved config
---   ;temporal auto fire 67 clench              - auto offset + CLI flare/enchant/action
---   ;temporal auto 66death                     - auto offset + death flare
---   ;temporal auto 100death                    - auto offset + 100-death flare
---   ;temporal auto next 67 clench              - auto offset + compute next flare type
---   ;temporal next 67 clench right             - next flare from saved offset
---   ;temporal set                              - interactive settings display
---   ;temporal offset 1.5 behind                - manual offset override
---   ;temporal 1.5 behind 100 clench right      - full manual mode
---   ;temporal help                             - show usage

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_DIGITS = 6
local CONFIG_NAME = "temporal"

-- Temporal flare digit mapping (3rd-to-last digit for normal flares)
local FLARE_DIGIT = {
    ["Fire"]           = "1",
    ["Ice"]            = "2",
    ["Lightning"]      = "3",
    ["Earth"]          = "4",
    ["Acid"]           = "5",
    ["Void"]           = "6",
    ["Disruption"]     = "7",
    ["Plasma"]         = "8",
    ["Steam"]          = "9",
    ["Disintegration"] = "0",
    ["+66 Death"]      = "666",
    ["+100 Death"]     = "666100",
}

-- Inverse map for normal flares only (single digit 0-9)
local DIGIT_TO_FLARE = {}
for name, digit in pairs(FLARE_DIGIT) do
    if #digit == 1 then
        DIGIT_TO_FLARE[digit] = name
    end
end

local FLARE_NAMES_LOWER = {}
for name, _ in pairs(FLARE_DIGIT) do
    FLARE_NAMES_LOWER[string.lower(name)] = name
end

--------------------------------------------------------------------------------
-- Settings helpers
--------------------------------------------------------------------------------

local function load_cfg()
    local cfg = {}
    cfg.flare_type       = CharSettings.temporal_flare_type or "Earth"
    cfg.enchant          = tonumber(CharSettings.temporal_enchant) or 100
    cfg.action           = CharSettings.temporal_action or "clench"
    cfg.hand             = CharSettings.temporal_hand or "right"
    cfg.offset_seconds   = tonumber(CharSettings.temporal_offset_seconds) or 0.0
    cfg.offset_direction = CharSettings.temporal_offset_direction or "behind"
    cfg.offset_source    = CharSettings.temporal_offset_source or ""
    cfg.offset_note      = CharSettings.temporal_offset_note or ""
    return cfg
end

local function save_cfg(cfg)
    CharSettings.temporal_flare_type       = cfg.flare_type
    CharSettings.temporal_enchant          = tostring(cfg.enchant)
    CharSettings.temporal_action           = cfg.action
    CharSettings.temporal_hand             = cfg.hand
    CharSettings.temporal_offset_seconds   = tostring(cfg.offset_seconds)
    CharSettings.temporal_offset_direction = cfg.offset_direction
    CharSettings.temporal_offset_source    = cfg.offset_source or ""
    CharSettings.temporal_offset_note      = cfg.offset_note or ""
end

--------------------------------------------------------------------------------
-- Offset / timing
--------------------------------------------------------------------------------

--- Estimate clock offset using GameState.server_time vs os.time().
--- Returns offset_seconds (positive = local ahead of server), or nil on failure.
local function auto_detect_offset()
    local server_time = GameState.server_time
    if not server_time or server_time == 0 then
        return nil, "GameState.server_time not available"
    end
    local local_time = os.time()
    local drift = local_time - server_time
    -- offset_sec such that: server = local + offset_sec
    local offset_sec = -drift
    local seconds = math.abs(drift)
    local dir = drift >= 0 and "behind" or "ahead"
    -- "behind" means local clock is behind server (server = local + seconds)
    -- "ahead" means local clock is ahead of server (server = local - seconds)
    -- Actually: drift = local - server.
    --   If drift > 0: local is ahead of server, so to get server from local: server = local - drift => offset = -drift (negative)
    --   If drift < 0: local is behind server: server = local + |drift| => offset = |drift| (positive)
    -- Convention from original: "behind X" => server = local + X, "ahead X" => server = local - X
    if drift >= 0 then
        -- local is ahead of server
        dir = "ahead"
        seconds = drift
        offset_sec = -drift
    else
        -- local is behind server
        dir = "behind"
        seconds = math.abs(drift)
        offset_sec = math.abs(drift)
    end

    return {
        seconds = seconds,
        dir = dir,
        offset_sec = offset_sec,
        drift = drift,
    }
end

--- Convert seconds + direction string to a signed offset.
local function offset_from(seconds, dir)
    local sec = math.abs(tonumber(seconds) or 0)
    dir = string.lower(tostring(dir)):match("^%s*(.-)%s*$")
    if dir == "behind" then
        return sec
    elseif dir == "ahead" then
        return -sec
    else
        echo("temporal: direction must be 'behind' or 'ahead', got '" .. tostring(dir) .. "'")
        return 0
    end
end

--------------------------------------------------------------------------------
-- Hand / action helpers
--------------------------------------------------------------------------------

local function normalize_hand(raw)
    local h = string.lower(tostring(raw or "right")):match("^%s*(.-)%s*$")
    if h:sub(1, 1) == "l" then return "left" end
    return "right"
end

local function hand_obj(hand)
    if hand == "left" then
        return GameObj.left_hand()
    else
        return GameObj.right_hand()
    end
end

local function perform_action(action, hand)
    local obj = hand_obj(hand)
    if not obj or not obj.noun or obj.noun == "" then
        echo("temporal: nothing detected in your " .. hand .. " hand.")
        return
    end
    fput(action .. " my " .. obj.noun)
end

--------------------------------------------------------------------------------
-- Flare parsing / tail building
--------------------------------------------------------------------------------

local function parse_flare_token(token)
    local t = tostring(token or ""):match("^%s*(.-)%s*$")
    if t == "" then return nil end
    local down = string.lower(t)

    if down == "66death" then return "+66 Death" end
    if down == "100death" then return "+100 Death" end

    return FLARE_NAMES_LOWER[down]
end

local function build_tail(flare_type, enchant)
    local flare = tostring(flare_type)
    local digit = FLARE_DIGIT[flare]
    if not digit then
        echo("temporal: unknown flare type '" .. flare .. "'")
        return nil
    end

    local ench = tonumber(enchant) or 0
    if ench < 0 then ench = 0 end
    if ench > 100 then ench = 100 end

    if flare == "+100 Death" then return "666100" end
    if flare == "+66 Death" then return "666" end

    local ench2 = string.format("%02d", ench % 100)
    return digit .. ench2
end

--------------------------------------------------------------------------------
-- Next flare computation
--------------------------------------------------------------------------------

local function next_flare_info(offset_sec)
    local server_sec = math.floor(os.time() + offset_sec)

    local current_digit = tostring(math.floor(server_sec / 100) % 10)
    local next_digit    = tostring((math.floor(server_sec / 100) + 1) % 10)

    local next_boundary = (math.floor(server_sec / 100) + 1) * 100
    local eta = next_boundary - server_sec

    local current_flare = DIGIT_TO_FLARE[current_digit] or "Unknown"
    local next_flare    = DIGIT_TO_FLARE[next_digit] or "Unknown"

    return current_flare, current_digit, next_flare, next_digit, eta
end

local function resolve_flare_type(flare_type, offset_sec)
    if string.lower(tostring(flare_type)) ~= "next" then
        return flare_type, nil
    end

    local current_flare, current_digit, nxt_flare, nxt_digit, eta = next_flare_info(offset_sec)
    local note = "[temporal] Next flare computed from server time: now=" .. current_flare ..
        "(" .. current_digit .. "), next=" .. nxt_flare ..
        "(" .. nxt_digit .. ") in ~" .. tostring(eta) .. "s"
    return nxt_flare, note
end

--------------------------------------------------------------------------------
-- Wait for server tail
--------------------------------------------------------------------------------

local function wait_for_server_tail(tail, offset_sec, fire_at)
    fire_at = fire_at or 0.5
    local tail_s = tostring(tail):match("^%s*(.-)%s*$")

    if not tail_s:match("^%d+$") or #tail_s < 1 or #tail_s > MAX_DIGITS then
        echo("temporal: tail must be 1.." .. MAX_DIGITS .. " digits, got '" .. tail_s .. "'")
        return
    end

    local mod    = 10 ^ #tail_s
    local tail_i = tonumber(tail_s)

    -- ETA estimate (printed once)
    local server_now = os.time() + offset_sec
    local sec  = math.floor(server_now)
    local frac = server_now - sec

    local rem = (tail_i - (sec % mod)) % mod

    local eta
    if rem == 0 then
        eta = math.max(fire_at - frac, 0.0)
    else
        eta = (rem - frac) + fire_at
    end

    if eta <= 0.5 then
        echo("[temporal] Trigger imminent...")
    else
        echo(string.format("[temporal] Estimated time until fire: ~%.2fs", eta))
    end

    -- Poll loop: wait for server seconds to match tail and fractional >= fire_at
    local poll_sleep = 0.01

    while true do
        server_now = os.time() + offset_sec
        sec  = math.floor(server_now)
        frac = server_now - sec

        if (sec % mod) == tail_i then
            if frac >= fire_at then
                return
            end
            -- In the correct second but before fire_at
            local sleep_time = fire_at - frac
            if sleep_time > 0 then
                pause(sleep_time)
            end
            return
        end

        pause(poll_sleep)
    end
end

--------------------------------------------------------------------------------
-- Run from config
--------------------------------------------------------------------------------

local function run_from_config(cfg, offset_override)
    local action = string.lower(tostring(cfg.action or "clench")):match("^%s*(.-)%s*$")
    local hand   = normalize_hand(cfg.hand)

    local offset_sec
    if offset_override then
        offset_sec = offset_override
    else
        offset_sec = offset_from(cfg.offset_seconds, cfg.offset_direction)
    end

    local flare = cfg.flare_type
    local ench  = cfg.enchant

    local resolved_flare, next_note = resolve_flare_type(flare, offset_sec)
    if next_note then
        echo(next_note)
    end

    local tail = build_tail(resolved_flare, ench)
    if not tail then return end

    if not offset_override then
        respond("************************************************************")
        respond("*** temporal using SAVED offset: " .. tostring(cfg.offset_seconds) ..
            " " .. tostring(cfg.offset_direction) .. " (offset=" .. tostring(offset_sec) .. ")")
        respond("*** target tail=" .. tail .. " (flare=" .. tostring(resolved_flare) ..
            ", enchant=" .. tostring(ench) .. "), action=" .. action .. ", hand=" .. hand)
        respond("************************************************************")
    end

    wait_for_server_tail(tail, offset_sec, 0.5)
    perform_action(action, hand)
end

--------------------------------------------------------------------------------
-- Usage
--------------------------------------------------------------------------------

local function usage()
    echo("temporal.lua (v0.4.0) -- Nick S")
    echo("")
    echo("Setup / run with saved config:")
    echo("  ;temporal                 - run with saved config")
    echo("  ;temporal set             - display current settings")
    echo("")
    echo("Auto-detect offset and run:")
    echo("  ;temporal auto            - auto-detect offset, run saved config")
    echo("  ;temporal auto <flare> <enchant> [clench|break] [right|left]")
    echo("    Example: ;temporal auto fire 67 clench")
    echo("")
    echo("Death flares:")
    echo("  ;temporal auto 66death")
    echo("  ;temporal auto 100death")
    echo("")
    echo("Next flare type:")
    echo("  ;temporal next <enchant> [clench|break] [right|left]")
    echo("  ;temporal auto next <enchant> [clench|break] [right|left]")
    echo("")
    echo("Manual offset:")
    echo("  ;temporal offset <seconds> <behind|ahead>")
    echo("  ;temporal <seconds> <behind|ahead> <tail> [clench|break] [right|left]")
    echo("")
    echo("Valid flare types: fire, ice, lightning, earth, acid, void,")
    echo("  disruption, plasma, steam, disintegration, 66death, 100death, next")
end

local function show_settings()
    local cfg = load_cfg()
    echo("=== temporal settings ===")
    echo("  flare_type:       " .. tostring(cfg.flare_type))
    echo("  enchant:          " .. tostring(cfg.enchant))
    echo("  action:           " .. tostring(cfg.action))
    echo("  hand:             " .. tostring(cfg.hand))
    echo("  offset_seconds:   " .. tostring(cfg.offset_seconds))
    echo("  offset_direction: " .. tostring(cfg.offset_direction))
    echo("  offset_source:    " .. tostring(cfg.offset_source))
    echo("  offset_note:      " .. tostring(cfg.offset_note))
    echo("=========================")
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local args = {}
for i = 1, 20 do
    local v = Script.vars[i]
    if not v or v == "" then break end
    table.insert(args, v)
end

-- No args: run from saved config
if #args == 0 then
    local ok, err = pcall(function()
        local cfg = load_cfg()
        run_from_config(cfg)
    end)
    if not ok then
        echo("temporal: ERROR: " .. tostring(err))
        echo("temporal: run ';temporal set' to check settings.")
    end
    return
end

-- Check for auto mode
local auto_mode = false
if string.lower(args[1]) == "auto" then
    auto_mode = true
    table.remove(args, 1)
end

local cmd = string.lower(args[1] or "")

-- Help
if cmd == "help" or cmd == "-h" or cmd == "--help" then
    usage()
    return
end

-- Set / show settings
if cmd == "set" or cmd == "settings" or cmd == "config" then
    show_settings()
    return
end

-- Offset command: ;temporal offset <seconds> <direction>
if cmd == "offset" then
    table.remove(args, 1)
    local sec_str = args[1] or ""
    local dir_str = args[2] or ""

    if not sec_str:match("^%-?%d+%.?%d*$") or
       (dir_str ~= "behind" and dir_str ~= "ahead") then
        echo("temporal: usage: ;temporal offset <seconds> <behind|ahead>")
        return
    end

    local cfg = load_cfg()
    cfg.offset_seconds   = math.abs(tonumber(sec_str))
    cfg.offset_direction = dir_str
    cfg.offset_source    = "manual"
    cfg.offset_note      = "Manual override via CLI."
    save_cfg(cfg)
    echo("temporal: offset saved: " .. tostring(cfg.offset_seconds) .. " " .. cfg.offset_direction)
    return
end

-- Load config for remaining commands
local cfg = load_cfg()

-- Auto-detect offset if in auto mode
local auto_offset_sec = nil
if auto_mode then
    local result, err_msg = auto_detect_offset()
    if result then
        cfg.offset_seconds   = result.seconds
        cfg.offset_direction = result.dir
        cfg.offset_source    = "auto"
        cfg.offset_note      = "Auto-detected via GameState.server_time: drift=" ..
            tostring(result.drift) .. "s => offset=" .. tostring(result.offset_sec) .. "s"
        save_cfg(cfg)
        auto_offset_sec = result.offset_sec
        respond("*** temporal auto-detected offset: " .. tostring(result.seconds) ..
            " " .. result.dir .. " (offset=" .. tostring(result.offset_sec) .. ")")
    else
        cfg.offset_note = "Auto-detect failed: " .. tostring(err_msg)
        save_cfg(cfg)
        echo("temporal: " .. cfg.offset_note)
    end
end

-- ;temporal auto (no further args)
if auto_mode and #args == 0 then
    local ok, err = pcall(function()
        if auto_offset_sec then
            run_from_config(cfg, auto_offset_sec)
        else
            run_from_config(cfg)
        end
    end)
    if not ok then
        echo("temporal: ERROR: " .. tostring(err))
        echo("temporal: run ';temporal set' to check settings.")
    end
    return
end

-- Consume command token
table.remove(args, 1)

-- Next flare type: ;temporal [auto] next <enchant> [action] [hand]
if cmd == "next" then
    local ench_arg = (args[1] or ""):match("^%s*(.-)%s*$")
    if not ench_arg:match("^%d+$") then
        echo("temporal: 'next' requires an enchant integer (0-100).")
        usage()
        return
    end

    local action = string.lower(args[2] or cfg.action or "clench"):match("^%s*(.-)%s*$")
    local hand   = normalize_hand(args[3] or cfg.hand)

    cfg.flare_type = "Next"
    cfg.enchant    = tonumber(ench_arg)
    cfg.action     = action
    cfg.hand       = hand
    save_cfg(cfg)

    local ok, err = pcall(function()
        if auto_offset_sec then
            run_from_config(cfg, auto_offset_sec)
        else
            run_from_config(cfg)
        end
    end)
    if not ok then
        echo("temporal: ERROR: " .. tostring(err))
    end
    return
end

-- Flare token: ;temporal [auto] <flare> <enchant> [action] [hand]
local flare_token = parse_flare_token(cmd)

if flare_token then
    cfg.flare_type = flare_token

    if flare_token == "+66 Death" or flare_token == "+100 Death" then
        local action = string.lower(args[1] or cfg.action or "clench"):match("^%s*(.-)%s*$")
        local hand   = normalize_hand(args[2] or cfg.hand)
        cfg.action = action
        cfg.hand   = hand
        save_cfg(cfg)

        local ok, err = pcall(function()
            if auto_offset_sec then
                run_from_config(cfg, auto_offset_sec)
            else
                run_from_config(cfg)
            end
        end)
        if not ok then
            echo("temporal: ERROR: " .. tostring(err))
        end
        return
    end

    local ench_arg = (args[1] or ""):match("^%s*(.-)%s*$")
    if not ench_arg:match("^%d+$") then
        echo("temporal: expected enchant after flare (example: ;temporal" ..
            (auto_mode and " auto" or "") .. " fire 67 clench).")
        usage()
        return
    end

    local action = string.lower(args[2] or cfg.action or "clench"):match("^%s*(.-)%s*$")
    local hand   = normalize_hand(args[3] or cfg.hand)

    cfg.enchant = tonumber(ench_arg)
    cfg.action  = action
    cfg.hand    = hand
    save_cfg(cfg)

    local ok, err = pcall(function()
        if auto_offset_sec then
            run_from_config(cfg, auto_offset_sec)
        else
            run_from_config(cfg)
        end
    end)
    if not ok then
        echo("temporal: ERROR: " .. tostring(err))
    end
    return
end

-- Manual offset modes: ;temporal <seconds> <behind|ahead> [tail] [action] [hand]
local seconds_str = cmd
local dir         = string.lower(args[1] or ""):match("^%s*(.-)%s*$")
local tail_arg    = (args[2] or ""):match("^%s*(.-)%s*$")

if not seconds_str:match("^%-?%d+%.?%d*$") or (dir ~= "behind" and dir ~= "ahead") then
    usage()
    return
end

local seconds = math.abs(tonumber(seconds_str))
local offset_sec = offset_from(seconds, dir)

if tail_arg == "" then
    -- Save offset and run from config
    cfg.offset_seconds   = seconds
    cfg.offset_direction = dir
    cfg.offset_source    = "manual"
    cfg.offset_note      = "Manual override provided on CLI."
    save_cfg(cfg)

    respond("*** temporal using PROVIDED offset (saved): " .. tostring(seconds) ..
        " " .. dir .. " (offset=" .. tostring(offset_sec) .. ")")

    local ok, err = pcall(function()
        run_from_config(cfg, offset_sec)
    end)
    if not ok then
        echo("temporal: ERROR: " .. tostring(err))
    end
    return
end

-- Full manual mode with explicit tail
local action = string.lower(args[3] or "clench"):match("^%s*(.-)%s*$")
local hand   = normalize_hand(args[4])

echo("temporal: offset=" .. tostring(offset_sec) .. " (server = local + offset)")
echo("temporal: waiting for server tail " .. tail_arg .. " @ ~.5s, action=" .. action .. ", hand=" .. hand .. "...")
local ok, err = pcall(function()
    wait_for_server_tail(tail_arg, offset_sec, 0.5)
    perform_action(action, hand)
end)
if not ok then
    echo("temporal: ERROR: " .. tostring(err))
end
