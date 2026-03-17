--- @revenant-script
--- name: manatimer
--- version: 0.12.0
--- author: Drafix
--- game: gs
--- tags: mana, timer, pulse, tracker, window
--- description: Mana pulse timer displayed in a stream window
---
--- Original Lich5 authors: Drafix, Doug, Deysh
--- Ported to Revenant Lua from manatimer-gtk3.lic v0.12
---
--- Usage: ;manatimer
--- Note: GTK window replaced with stream window output

hide_me()
silence_me()
no_kill_all()

local ticks = 0
local WINDOW_ID = "manatimer"

-- Open stream window
put("<closeDialog id='" .. WINDOW_ID .. "'/><streamWindow id='" .. WINDOW_ID .. "' title='" .. GameState.character_name .. " Mana Timer' location='left' resident='true'></streamWindow>")

local function update_window()
    local mins = math.floor(math.abs(ticks) / 60)
    local secs = math.abs(ticks) % 60
    local sign = ticks < 0 and "-" or ""
    local text = sign .. string.format("%02d:%02d", mins, secs)
    put('<clearStream id="' .. WINDOW_ID .. '"/><pushStream id="' .. WINDOW_ID .. '"/>' .. text .. '<popStream/>')
end

before_dying(function()
    put('<clearStream id="' .. WINDOW_ID .. '"/><pushStream id="' .. WINDOW_ID .. '"/>manatimer stopped<popStream/>')
end)

-- Mana pulse detection via downstream hook
local HOOK_ID = "manatimer_hook"
local oldexp = Stats.exp or 0
local beforemana = checkmana()

DownstreamHook.add(HOOK_ID, function(line)
    -- Detect mana pulse from dialogData
    local exp_val = line:match("text='(%d+) (?:experience|until next level)'")
    local mana_val = line:match("text='mana (%d+)/")

    if exp_val and mana_val then
        local currentexp = tonumber(exp_val)
        local currentmana = tonumber(mana_val)
        local gained = currentexp - oldexp
        oldexp = currentexp
        if gained ~= 0 then
            local diff = currentmana - beforemana
            ticks = 120
            echo(os.date() .. " | You absorb " .. gained .. " experience points. You gain " .. diff .. " mana.")
        end
    elseif mana_val then
        local currentmana = tonumber(mana_val)
        local diff = currentmana - beforemana
        if diff > 10 then
            ticks = 120
            echo("PULSE - (" .. diff .. " mana) - " .. os.date())
        end
    end

    if mana_val then
        beforemana = tonumber(mana_val)
    end

    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
end)

-- Countdown loop
while true do
    ticks = ticks - 1
    update_window()
    wait(1)
end
