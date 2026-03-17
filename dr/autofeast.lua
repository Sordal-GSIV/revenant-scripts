--- @revenant-script
--- name: autofeast
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Monitor health/mana and cast feast spells to restore.
--- tags: healing, mana, automated
---
--- Converted from autofeast.lic

local settings = get_settings()

echo("AutoFeast monitoring health and mana...")

while true do
    pause(1)
    if DRStats.spirit >= 80 then
        if DRStats.health < 55 and settings.feast_vit then
            echo("Health low, casting vitality feast...")
            DRCA.cast_spell(settings.feast_vit, settings)
        end
        if DRStats.mana < 20 and settings.feast_mana then
            echo("Mana low, casting mana feast...")
            DRCA.cast_spell(settings.feast_mana, settings)
        end
    end
end
