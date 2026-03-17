--- @revenant-script
--- name: circlemonitor
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Continuous circle progress monitor - tracks skill gains toward next circle
--- tags: circle, monitoring, training, progress
---
--- Ported from circlemonitor.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;circlemonitor   - Run in background to track circle progress

echo("=== Circle Monitor ===")
echo("Monitoring skill progress toward next circle...")
echo("Guild: " .. (DRStats.guild or "unknown"))
echo("Circle: " .. (DRStats.circle or 0))

local last_circle = DRStats.circle or 0

while true do
    pause(30)
    local current = DRStats.circle or 0
    if current > last_circle then
        echo("*** CIRCLE UP! Now circle " .. current .. "! ***")
        last_circle = current
    end
end
