--- @revenant-script
--- name: rafflewindow
--- version: 1.0.1
--- author: Phocosoen
--- game: gs
--- tags: wrayth, raffle, window, tracker
--- description: Track raffles in a Wrayth window with time zone adjusted draw times
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from rafflewindow.lic v1.0.1
---
--- Usage: ;rafflewindow (then type RAFFLE LIST in game)

hide_me()
no_kill_all()
set_priority(-1)

local raffles = {}
local raffle_lines = {}
local current_raffle = nil

local function raffle_window(message)
    put('<clearStream id="rafflewindow"/><pushStream id="rafflewindow"/>' .. message .. '<popStream/>')
end

put("<closeDialog id='rafflewindow'/><streamWindow id='rafflewindow' title='Raffles' location='left' resident='true' dynamic='true'></streamWindow>")

before_dying(function()
    raffle_window("Raffle script is not running :(")
end)

local function parse_raffle_lines()
    raffles = {}
    current_raffle = nil
    for _, line in ipairs(raffle_lines) do
        local id, item, cost = line:match('^Raffle #(.+) for "(.+)", Cost: ([%d,]+) silver')
        if id then
            if current_raffle and current_raffle.id and not current_raffle.discard then
                raffles[#raffles + 1] = current_raffle
            end
            current_raffle = {
                id = id, item = item, cost = cost:gsub(",", ""),
                online = false, logout_ok = true, purchased = false,
                discard = false, draw_time = nil,
            }
        elseif current_raffle then
            if line:find("Drew at:") then
                current_raffle.discard = true
            end
            if line:find("Draws at:") then
                current_raffle.draw_time_str = line:match("Draws at: (.+) %(in")
            end
            if line:find("must be online") then
                current_raffle.online = true
            elseif line:find("must be present") then
                current_raffle.online = false
                current_raffle.logout_ok = false
            end
            if line:find("You have purchased a ticket") then
                current_raffle.purchased = true
            end
        end
    end
    if current_raffle and current_raffle.id and not current_raffle.discard then
        raffles[#raffles + 1] = current_raffle
    end
end

local function format_raffle_info()
    local output = "Info - RAFFLE SHOW #\nTravel - RAFFLE GUIDE #\n* = ticket purchased\n\n"
    for _, r in ipairs(raffles) do
        local entry = ""
        entry = entry .. "Raffle #" .. r.id .. ' for "' .. r.item .. '"\n'
        entry = entry .. r.cost .. " silver\n"
        if r.draw_time_str then
            entry = entry .. r.draw_time_str .. "\n"
        end
        if r.online then
            entry = entry .. "Must be logged in.\n"
        elseif r.logout_ok then
            entry = entry .. "Can be logged out.\n"
        else
            entry = entry .. "Must be present.\n"
        end
        entry = entry .. "\n"
        if r.purchased then
            entry = entry:gsub("([^\n]+)", "*%1")
        end
        output = output .. entry
    end
    return output
end

fput("raffle list")

while true do
    local line = get()
    if line and Regex.test(line, "raffles are currently active") then
        raffle_lines = {}
        raffle_window("Capturing raffle list...")

        -- Capture subsequent lines
        for _ = 1, 200 do
            local next_line = get()
            if not next_line then break end
            if Regex.test(next_line, "^Raffle #|^%s*Location|^%s*Draws|^%s*Drew|^%s*Players|^%s*Characters|^%s*You have purchased") then
                raffle_lines[#raffle_lines + 1] = next_line
            else
                break
            end
        end

        parse_raffle_lines()
        raffle_window(format_raffle_info())
    end
end
