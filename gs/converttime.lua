--- @revenant-script
--- name: converttime
--- version: 1.1.0
--- author: Mara
--- game: gs
--- description: Converts elven time (Eastern / ET) to local time live
--- tags: time, convert, elven, eastern, local
---
--- Usage:
---   ;converttime

-- Eastern Time is UTC-5 (EST) or UTC-4 (EDT)
-- We approximate with -5 hours offset; DST detection is best-effort
local EST_OFFSET = -5 * 3600

local function echo_line(msg)
    _respond("<pushBold/>##################################################<popBold/>")
    _respond("<pushBold/>#  " .. msg .. "<popBold/>")
    _respond("<pushBold/>##################################################<popBold/>")
end

local function convert_eastern_to_local(hour, min, sec)
    -- Build a UTC timestamp from the Eastern time
    local now = os.time()
    local today = os.date("*t", now)

    -- Construct Eastern time as UTC
    local eastern_utc = os.time({
        year = today.year, month = today.month, day = today.day,
        hour = hour, min = min, sec = sec or 0
    }) - EST_OFFSET

    local local_time = os.date("*t", eastern_utc)
    local f24 = string.format("%02d:%02d", local_time.hour, local_time.min)

    local h12 = local_time.hour % 12
    if h12 == 0 then h12 = 12 end
    local ampm = local_time.hour >= 12 and "pm" or "am"
    local f12 = string.format("%d:%02d %s", h12, local_time.min, ampm)

    return f24, f12
end

local MONTHS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
}

while true do
    local line = get()
    if line then
        -- Pattern A: "It is HH:MM by the elven time standard"
        local h, m, s, ampm = line:match("It is (%d+):(%d+):?(%d*)%s*([ap]m)?%s*by the elven time standard")
        if h then
            local hour = tonumber(h)
            local min = tonumber(m)
            local sec = tonumber(s) or 0
            if ampm then
                ampm = ampm:lower()
                if ampm == "am" and hour == 12 then hour = 0
                elseif ampm == "pm" and hour < 12 then hour = hour + 12 end
            end
            local f24, f12 = convert_eastern_to_local(hour, min, sec)
            echo_line("Elven time converted to local: " .. f24 .. " (" .. f12 .. ")")
        end

        -- Pattern B: timestamp like "until: Mon Mar 17 14:30:00 ET 2026"
        local mon, day, hh, mm, ss, year = line:match("until:?%s+%a+%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+E[SD]?T?%s+(%d+)")
        if mon then
            local month_num = MONTHS[mon:lower():sub(1, 3)]
            if month_num then
                local f24, f12 = convert_eastern_to_local(tonumber(hh), tonumber(mm), tonumber(ss))
                echo_line("Elven timestamp converted to local: " .. f24 .. " (" .. f12 .. ")")
            end
        end

        -- Pattern C: "guild training points awards will be doubled...until midnight"
        if line:match("guild training points awards will be doubled.-until midnight") then
            -- Midnight Eastern = 00:00 next day ET
            local f24, f12 = convert_eastern_to_local(24, 0, 0)
            echo_line("Guild 2x until midnight ET -> local: " .. f24 .. " (" .. f12 .. ")")
        end
    end
end
