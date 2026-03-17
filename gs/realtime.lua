--- @revenant-script
--- name: realtime
--- version: 0.1.0
--- author: nishima
--- game: gs
--- description: Scan recent text for timestamps and convert to your local time zone in 12h format
--- tags: time,timestamp,utility
---
--- Changelog:
---   0.1b - fix regex for extra spacing
---   0.1  - initial release

-- Timestamp format: Sat Apr 26 18:28:27 ET 2025
local TIMESTAMP_RE = Regex.new(
    "\\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{1,2}\\s\\d{2}:\\d{2}:\\d{2}\\s[A-Z]{2,4}\\s\\d{4}\\b"
)

-- Server time is US Eastern: UTC-5 (EST) or UTC-4 (EDT)
local local_offset = os.date("*t").isdst and -4 * 3600 or -5 * 3600
local my_offset = os.difftime(os.time(), os.time(os.date("!*t")))
local adjustment = my_offset - local_offset

local tz_name = os.date("%Z")
respond("")
respond(" - Converting recent timestamps to 12h in " .. tz_name .. " - ")
respond("")

local text = regetall()
local count = 0

local months = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
}

for _, line in ipairs(text) do
    local match = TIMESTAMP_RE:match(line)
    if match then
        -- Parse the timestamp
        local mon_s, day, hour, min, sec, year =
            match:match("(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+%a+%s+(%d+)")
        if mon_s and months[mon_s] then
            local t = os.time({
                year = tonumber(year), month = months[mon_s], day = tonumber(day),
                hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec)
            })
            local local_t = t + adjustment
            local fmt = os.date("%a %b %d %I:%M:%S %p", local_t)
            respond("<output class=\"mono\"/>")
            respond("<pushBold/>" .. fmt .. "<popBold/> | " .. line)
            respond("<output class=\"\"/>")
            count = count + 1
        end
    end
end

if count == 0 then
    respond(" No timestamps found.  Run this after looking at something like a raffle ticket.")
end

respond("")
