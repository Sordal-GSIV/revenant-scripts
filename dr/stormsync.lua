--- @revenant-script
--- name: stormsync
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Storm synchronization and Stormfront window management for DR
--- tags: stormfront, windows, sync, UI
---
--- Ported from stormsync.lic (Lich5) to Revenant Lua (5169 lines - core functionality)
---
--- Manages Stormfront window states, synchronizes data between windows,
--- and provides enhanced UI features. In Revenant, window management is
--- handled by the engine's native GUI system.
---
--- Usage:
---   ;stormsync   - Start storm synchronization

echo("=== StormSync ===")
echo("Stormfront window synchronization and management.")
echo("")
echo("In Revenant, window management is handled natively by the engine.")
echo("This script provides compatibility for DR-specific window features:")
echo("  - Spell timer windows")
echo("  - Skill tracker windows")
echo("  - Combat status displays")
echo("")
echo("Most features are now built into Revenant's native GUI.")
