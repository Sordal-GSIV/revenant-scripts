--- @revenant-script
--- name: timer
--- version: 1.1
--- author: Revenant contributors
--- game: any
--- description: Simple elapsed-time counter. Displays elapsed time every second until stopped.
---
--- @lic-certified: complete 2026-03-18

local count = 0

while true do
    count = count + 1
    pause(1)
    local minutes = math.floor(count / 60)
    local seconds = count % 60
    echo(string.format("%ds (%dm%02ds)", count, minutes, seconds))
end
