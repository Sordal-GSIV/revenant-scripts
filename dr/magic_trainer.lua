--- @revenant-script
--- name: magic_trainer
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Train magic by cycling training spells from settings.
--- tags: magic, training, spells
--- Converted from magic-trainer.lic

local settings = get_settings()
local spells = settings.training_spells or {}
local counter = 0
local max_loops = 30

for skill, spell in pairs(spells) do
    if counter > max_loops then break end
    if DRSkill.getxp(skill) <= 33 then
        local data = DRCA.check_discern(spell, settings)
        DRCA.cast_spell(data, settings)
        pause(1)
        counter = counter + 1
    end
end
