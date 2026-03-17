--- @revenant-script
--- name: magic_training
--- version: 1.0
--- author: Chuno
--- game: dr
--- description: Train magic skills with YAML-configured spells.
--- tags: magic, training, spells
--- Converted from magic-training.lic
local settings = get_settings()
local spells = settings.magic_training or {}
echo("=== magic_training ===")
for skill, spell_data in pairs(spells) do
    if DRSkill.getxp(skill) < 32 then
        echo("Training " .. skill .. " with " .. (spell_data.abbrev or "unknown"))
        DRCA.cast_spell(spell_data, settings)
        pause(1)
    end
end
echo("Magic training complete.")
