--- @revenant-script
--- name: familiar_script
--- version: 1.46.0
--- author: elanthia-online
--- contributors: Tysong, Dissonance, Annelie, sele
--- game: gs
--- description: Keep your wizard familiar alive by auto-refreshing spell 920
--- tags: familiar,920,wizard
---
--- Usage:
---   ;familiar_script                     start monitoring
---   ;familiar_script help                show help
---   ;familiar_script --allowmove=no      disable moving to node on fizzle
---   ;familiar_script --refreshtimer=15   set refresh timer in minutes
---
--- NOTE: This is the standalone script. The Familiar engine global is separate.

local args = require("lib/args")
local Messaging = require("lib/messaging")

no_pause_all()
no_kill_all()

-- Settings via CharSettings
local settings = {}
settings.allow_move = CharSettings["familiar.allow_move"]
if settings.allow_move == nil then settings.allow_move = true end
settings.refresh_timer = tonumber(CharSettings["familiar.refresh_timer"]) or 15

-- Parse arguments
local opts = args.parse(Script.vars[0])

if opts.args[1] and opts.args[1]:lower() == "help" then
    Messaging.msg("info", "This script auto-refreshes your familiar once under the defined refresh time.")
    Messaging.msg("info", "Start with ;familiar_script")
    Messaging.msg("info", "")
    Messaging.msg("info", "Optional arguments:")
    Messaging.msg("info", "  --allowmove=no       disable moving to node on fizzle/interference")
    Messaging.msg("info", "  --allowmove=yes      enable moving (default)")
    Messaging.msg("info", "  Current: " .. (settings.allow_move and "YES" or "NO"))
    Messaging.msg("info", "")
    Messaging.msg("info", "  --refreshtimer=#     minutes before refresh (default 15)")
    Messaging.msg("info", "  Current: " .. tostring(settings.refresh_timer) .. " mins")
    if not Spell[920].known() then
        Messaging.msg("warn", "You do not know spell 920 - Call Familiar.")
    end
    return
end

if not Spell[920].known() then
    Messaging.msg("error", "You do not know spell 920 - Call Familiar.")
    Messaging.msg("error", "Please learn the spell before running this script.")
    return
end

if opts.allowmove then
    settings.allow_move = (opts.allowmove:lower() == "yes")
    CharSettings["familiar.allow_move"] = settings.allow_move
end

if opts.refreshtimer then
    settings.refresh_timer = tonumber(opts.refreshtimer) or settings.refresh_timer
    CharSettings["familiar.refresh_timer"] = settings.refresh_timer
end

echo("Familiar upkeep active. Refresh at " .. settings.refresh_timer .. " min remaining.")

while true do
    -- Wait until spell is below refresh threshold
    wait_until(function()
        return Effects.spell_time(920) < settings.refresh_timer
    end)

    -- Pause waggle scripts if running
    if Script.running("waggle") then Script.pause("waggle") end
    if Script.running("ewaggle") then Script.pause("ewaggle") end

    -- Wait for mana
    wait_until(function() return Char.mana() >= 20 end)
    waitcastrt()
    waitrt()

    local result = Spell[920].cast()
    if result and result:match("fizzle") or (result and result:match("interfere")) then
        if not settings.allow_move then
            Messaging.msg("info", "ALERT: Failed to cast 920 here")
            Messaging.msg("info", "Pausing ;familiar_script")
            Messaging.msg("info", "Unpause to move to closest node")
            pause_script()
        end
        local current_room = Map.current_room()
        Messaging.msg("info", "Moving to a node to refresh familiar in 10 seconds")
        Messaging.msg("info", "Kill ;familiar_script within 10s to stay")
        sleep(10)
        Script.run("go2", "node")
        waitrt()
        waitcastrt()
        Spell[920].cast()
        sleep(2)
        if current_room then
            Script.run("go2", tostring(current_room))
        end
    else
        sleep(4)
    end

    -- Unpause waggle scripts
    if Script.running("waggle") then Script.unpause("waggle") end
    if Script.running("ewaggle") then Script.unpause("ewaggle") end
end
