--- Gift experience tracking.
--- Tracks gift start time and pulse count with Infomon persistence.

local M = {}

local TOTAL_PULSES = 360
local PULSE_INTERVAL = 60    -- seconds
local RESET_CYCLE = 594000   -- seconds (165 hours)

local gift_start = nil
local pulse_count = 0

-- Load persisted state on module load
local function load_state()
    local start_raw = Infomon.get("gift.start")
    if start_raw and start_raw ~= "" then
        gift_start = tonumber(start_raw)
    end
    local count_raw = Infomon.get("gift.pulse_count")
    if count_raw and count_raw ~= "" then
        pulse_count = tonumber(count_raw) or 0
    end
end

--- Mark the gift as started (resets pulse count).
function M.started()
    gift_start = os.time()
    pulse_count = 0
    Infomon.set("gift.start", tostring(gift_start))
    Infomon.set("gift.pulse_count", tostring(pulse_count))
end

--- Increment the pulse count.
function M.pulse()
    pulse_count = pulse_count + 1
    Infomon.set("gift.pulse_count", tostring(pulse_count))
end

--- Return remaining time in seconds (pulse-based).
function M.remaining()
    return (TOTAL_PULSES - pulse_count) * PULSE_INTERVAL
end

--- Return the timestamp when the gift cycle restarts, or nil.
function M.restarts_on()
    if not gift_start then return nil end
    return gift_start + RESET_CYCLE
end

--- Mark the gift as ended.
function M.ended()
    pulse_count = TOTAL_PULSES
    Infomon.set("gift.pulse_count", tostring(pulse_count))
end

--- True if the gift is active.
function M.active()
    return gift_start ~= nil and pulse_count < TOTAL_PULSES
end

load_state()

return M
