--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: talisman
--- version: 1.0
--- author: unknown
--- game: gs
--- tags: combat, talisman, automation
--- description: Auto-target, cast Spell 311, and point Twisted Talisman at random targets when off cooldown.
---
--- Original Lich5 author: unknown (from lich_repo_mirror/lib/talisman.lic)
---
--- Usage:
---   ;talisman

while true do
    waitrt()
    waitcastrt()
    if not Effects.Cooldowns.active("Twisted Talisman") then
        local targets = GameObj.targets()
        if #targets > 0 then
            local target = targets[math.random(#targets)]
            put("target #" .. target.id)
            if checkmana() > 11 then
                Spell[311]:force_incant()
            end
            waitrt()
            waitcastrt()
            fput("point my twisted talisman at #" .. target.id)
        end
    end
    pause(0.1)
end
