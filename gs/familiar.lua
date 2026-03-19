--- @revenant-script
--- name: familiar
--- version: 1.46.0
--- author: elanthia-online
--- contributors: Tysong, Dissonance, Annelie, sele
--- game: gs
--- description: Keep your wizard familiar alive by auto-refreshing spell 920
--- tags: familiar,920,wizard
--- @lic-certified: complete 2026-03-19
---
--- Ported from familiar.lic v1.46.0 (elanthia-online/scripts)
--- Original authors: Annelie, sele, Tysong, Dissonance
---
--- changelog:
---   1.46.0 (2025-12-28)
---     Added check that 920 is known before attempting to cast to prevent infinite error loop.
---     Fixed header format and version formatting.
---     Updated to more current scripting standards.
---     removed hide_me, no reason to hide script
---   1.45 (2024-05-06)
---     Add support for ewaggle
---     Change checkmana to Char.mana call
---   1.44 (2023-06-05)
---     Fix for Lich 5.7.0 infomon update
---     rubocop cleanup
---   1.43 (2022-03-09)
---     change to use Effects
---   1.42 (2018-10-07)
---     fixed bug in checkmana being 5 instead of 20
---   1.41 (2018-10-05)
---     fixed bug in logic of --allowmove being backwards
---   1.4 (2018-08-20)
---     Added additional interference detection
---     Added option to not move away from room on fizzle/interference, pauses script
---     Added option to set refresh timer (defaults to 15)
---
--- Usage:
---   ;familiar_script                     start monitoring
---   ;familiar_script help                show help
---   ;familiar_script --allowmove=no      disable moving to node on fizzle
---   ;familiar_script --refreshtimer=15   set refresh timer in minutes

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
    Messaging.msg("info", "This script will automatically refresh your familiar once you are under the defined refresh time remaining (" .. tostring(settings.refresh_timer) .. " minutes).")
    Messaging.msg("info", "Start script using ;" .. Script.name)
    Messaging.msg("info", "")
    Messaging.msg("info", "Optional arguments:")
    Messaging.msg("info", "   ;" .. Script.name .. " --allowmove=no")
    Messaging.msg("info", "    disables moving to node on fizzle/interference")
    Messaging.msg("info", "    defaults to YES, currently set to " .. (settings.allow_move and "YES" or "NO"))
    Messaging.msg("info", "")
    Messaging.msg("info", "   ;" .. Script.name .. " --refreshtimer=#")
    Messaging.msg("info", "    sets time to refresh 920 to in minutes")
    Messaging.msg("info", "    defaults to 15 mins, currently set to " .. tostring(settings.refresh_timer) .. " mins")
    Messaging.msg("info", "")
    if not Spell[920].known then
        Messaging.msg("warn", "This script requires that you know spell 920 - Call Familiar, which you do not.")
    end
    return
end

if not Spell[920].known then
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
    wait_while(function()
        return Effects.Spells.time_left("Call Familiar") >= settings.refresh_timer
    end)

    -- Pause waggle scripts if running
    if Script.running("waggle") then Script.pause("waggle") end
    if Script.running("ewaggle") then Script.pause("ewaggle") end

    -- Wait for mana
    wait_until(function() return Char.mana >= 20 end)
    waitcastrt()
    waitrt()

    local result = Spell[920]:cast()
    if result and result:match("fizzle") or (result and result:match("interfere")) then
        if not settings.allow_move then
            Messaging.msg("info", "ALERT ALERT ALERT")
            Messaging.msg("info", "ALERT ALERT ALERT")
            Messaging.msg("info", "")
            Messaging.msg("info", "You failed to cast 920 here")
            Messaging.msg("info", "Pausing ;" .. Script.name)
            Messaging.msg("info", "")
            Messaging.msg("info", "Unpause to move away to closest node to refresh 920")
            Messaging.msg("info", "")
            Messaging.msg("info", "ALERT ALERT ALERT")
            Messaging.msg("info", "ALERT ALERT ALERT")
            Script.pause(Script.name)
        end
        local current_room = Map.current_room()
        Messaging.msg("info", "Moving to a node to re-fresh familiar in 10 seconds")
        Messaging.msg("info", "Please ;k " .. Script.name .. " before 10 seconds if you wish to stay")
        pause(10)
        Map.go2("node")
        waitrt()
        waitcastrt()
        Spell[920]:cast()
        pause(2)
        if current_room then
            Map.go2(tostring(current_room))
        end
    else
        pause(4)
        -- In Lich5, infomon was restarted here if the spell timer was still low after
        -- a successful cast (workaround for infomon staleness). In Revenant, Effects are
        -- tracked natively from the XML stream and do not require a manual refresh.
    end

    -- Unpause waggle scripts
    if Script.running("waggle") then Script.unpause("waggle") end
    if Script.running("ewaggle") then Script.unpause("ewaggle") end
end
