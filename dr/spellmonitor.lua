--- @revenant-script
--- name: spellmonitor
--- version: 1.0
--- author: Seped
--- game: dr
--- description: Track active spells and currently preparing spell via DRSpells.
--- tags: spells, monitoring, utility
--- Converted from spellmonitor.lic

no_kill_all()
no_pause_all()

-- Note: In Revenant, spell monitoring is handled natively by the
-- DRSpells module in lib/dr/spells.lua. This script provides
-- backward compatibility for scripts that expect spellmonitor to be running.

echo("Spell monitoring is handled natively by Revenant's DRSpells module.")
echo("This script runs as a no-op for compatibility.")

while true do
    local line = get()
    -- Spell tracking is done by the engine-level hooks
end
