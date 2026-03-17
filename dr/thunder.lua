--- @revenant-script
--- name: thunder
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Thunder multi-character server - TCP server for sharing stats between game instances
--- tags: multi-character, monitoring, networking, server
---
--- Ported from thunder.lic (Lich5 lib/) to Revenant Lua
---
--- Thunder is the server component of the Thunder/Struck system.
--- It runs a local TCP server to share character stats between game instances.
--- Client component is ;struck.
---
--- In Revenant, multi-character support is handled natively by the engine.
---
--- Usage:
---   ;thunder   - Start the Thunder server

echo("=== Thunder Multi-Character Server ===")
echo("Thunder shares character stats between game instances via TCP.")
echo("")
echo("Revenant handles multi-character communication natively.")
echo("This compatibility stub is provided for reference.")
echo("")
echo("To share data between characters in Revenant:")
echo("  - Use the engine's built-in IPC channels")
echo("  - Character state is accessible via GameState API")
