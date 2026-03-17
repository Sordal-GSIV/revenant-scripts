--- @revenant-script
--- name: talisman_sleep
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Auto-cast Symbol of Sleep and point Twisted Talisman at random targets when off cooldown.

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
