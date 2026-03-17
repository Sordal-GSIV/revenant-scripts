--- @revenant-script
--- name: redcantrip
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Keep red cantrip and ashcloak buffs active on timers
--- tags: magic, cantrip, buff

local time_30 = os.time() - 30000
local time_5 = os.time() - 30000

while true do
    if os.time() - time_30 > 30 * 60 then
        time_30 = os.time()
        DRC.bput("prep can p h", "You are now prepared")
        DRC.bput("gest iridesc flame red", "The air around you becomes", "The iridescent flame")
    end
    if os.time() - time_5 > 5 * 60 then
        time_5 = os.time()
        DRC.bput("prep can b t", "You are now prepared")
        DRC.bput("gest ashcloak", "You touch a glowing finger")
    end
    pause(0.25)
end
