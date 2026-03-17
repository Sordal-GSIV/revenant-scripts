--- @revenant-script
--- name: invoker_window
--- version: 0.4.2
--- author: nishima
--- game: gs
--- tags: invoker, timer, wrayth, window
--- description: Invoker arrival timer displayed in a Wrayth window
---
--- Original Lich5 authors: nishima
--- Ported to Revenant Lua from invoker-window.lic v0.4.2
---
--- Usage: ;invoker_window

no_kill_all()
hide_me()
set_priority(-1)

local invoker_duration = 15
local pre_alert = 5
local invoker_soon_msg = "=== INVOKER SOON ==="
local invoker_here_msg = "=== INVOKER TIME ==="
local check_interval = 6

-- Server time offset (ET) and invoker schedule (every 2 hours ET)
local elanthian_offset = -5 * 3600 -- UTC-05:00 EST
local local_offset = os.difftime(os.time(), os.time(os.date("!*t")))
local offset_diff = elanthian_offset - local_offset

local invoker_times = { 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22 }

local function invoker_window(message)
    put('<clearStream id="invoker"/><pushStream id="invoker"/>' .. message .. '<popStream/>')
end

-- Open Wrayth window
put("<closeDialog id='invoker'/><openDialog id='invoker'/><streamWindow id='invoker' title='Invoker' location='left' resident='true'></streamWindow>")

before_dying(function()
    invoker_window(Script.current.name .. " is not running :(")
end)

local main_msg_soon = true
local main_msg_here = true

while true do
    local now = os.time() + offset_diff
    local t = os.date("*t", now)
    local current_hour = t.hour
    local current_minute = t.min

    -- Find closest invoker hour
    local cur_invoker = nil
    for _, h in ipairs(invoker_times) do
        if h >= current_hour then
            cur_invoker = h
            break
        end
    end
    if not cur_invoker then cur_invoker = invoker_times[1] + 24 end

    local next_invoker = nil
    for _, h in ipairs(invoker_times) do
        if h > cur_invoker then
            next_invoker = h
            break
        end
    end
    if not next_invoker then next_invoker = invoker_times[1] + 24 end

    local diff_hours = cur_invoker - current_hour
    local next_hours = next_invoker - current_hour
    local diff_minutes = 60 - current_minute
    local message = ""

    if diff_hours == 0 and current_minute < invoker_duration then
        local remaining = invoker_duration - current_minute
        message = "The invoker is here for " .. remaining .. " more minute"
        if remaining > 1 then message = message .. "s" end
        message = message .. "!\n\n" .. invoker_here_msg
        if main_msg_here then
            respond("\n" .. invoker_here_msg .. "\n")
            main_msg_here = false
            main_msg_soon = true
        end
    else
        message = "The invoker should arrive in "
        local eff_hours = diff_hours
        if eff_hours == 0 then eff_hours = next_hours end
        if eff_hours > 1 then
            message = message .. (eff_hours - 1) .. " hour"
            if eff_hours > 2 then message = message .. "s" end
            message = message .. " and "
        end
        message = message .. diff_minutes .. " minute"
        if diff_minutes > 1 then message = message .. "s" end
        if diff_hours == 1 and diff_minutes <= pre_alert then
            message = message .. "\n\n" .. invoker_soon_msg
            if main_msg_soon then
                respond("\n" .. invoker_soon_msg .. "\n")
                main_msg_here = true
                main_msg_soon = false
            end
        end
    end

    invoker_window(message)
    wait(check_interval)
end
