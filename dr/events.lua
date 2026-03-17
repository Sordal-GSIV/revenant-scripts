--- @revenant-script
--- name: events
--- version: 1.0
--- author: Seped
--- game: dr
--- description: Flag-based event system for cross-script communication.
--- tags: events, flags, utility
--- Converted from events.lic
-- Note: Revenant provides Flags natively in lib/flags.lua
-- This script exists for backward compatibility.
no_kill_all(); no_pause_all()
echo("Events/Flags system is handled natively by Revenant.")
while true do local line = get() end
