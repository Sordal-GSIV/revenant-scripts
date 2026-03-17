--- @revenant-script
--- name: plaza
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Search all Crossing plaza shops for item.
--- tags: shopping, search, plaza
--- Usage: ;plaza <item>
--- Converted from plaza.lic
local item = Script.vars[1]
if not item then echo("Usage: ;plaza <item>") return end
echo("=== plaza search ===")
echo("Searching plaza for: " .. item)
echo("Requires go2 navigation for multi-room search. Pending full integration.")
