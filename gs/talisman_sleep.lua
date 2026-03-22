--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: talisman_sleep
--- version: 1.0
--- author: unknown
--- game: gs
--- tags: combat, talisman, sleep, automation
--- description: Auto-cast Symbol of Sleep and point Twisted Talisman at random targets when off cooldown.
---
--- Original Lich5 author: unknown (from lich_repo_mirror/lib/talisman_sleep.lic)
---
--- Usage:
---   ;talisman_sleep

while true do
    waitrt()
    waitcastrt()
    if not Effects.Cooldowns.active("Twisted Talisman") then
        local targets = GameObj.targets()
        if #targets > 0 then
            local target = targets[math.random(#targets)]
            put("symbol of sleep #" .. target.id)
            fput("point my twisted talisman at #" .. target.id)
        end
    end
    pause(0.1)
end
