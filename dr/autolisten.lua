--- @revenant-script
--- name: autolisten
--- version: 1.0
--- author: Xinphinity
--- game: dr
--- description: Auto-listen to an approved teacher when they request it
--- tags: teach, education, listen
---
--- Usage: Runs in background; when an approved person whispers "startlisteningtome",
--- the script will listen to them. Edit the approved name below.

local approved_name = "Xinphinity"

while true do
    local line = waitfor("startlisteningtome")
    local requestor = line:match("^(%S+)")

    if requestor ~= approved_name then
        fput("shake head")
        pause(10)
    else
        fput("nod " .. requestor)
        fput("stop listening")
        pause(3)
        fput("listen " .. requestor)
        pause(2)
    end
end
