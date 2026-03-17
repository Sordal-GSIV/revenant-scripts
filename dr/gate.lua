--- @revenant-script
--- name: gate
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Moon Mage moongate/teleport for a target.
--- tags: moonmage, gate, teleport
--- Usage: ;gate <person> [release] [teleport]
--- Converted from gate.lic
local person = Script.vars[1]
if not person then echo("Usage: ;gate <person> [release] [teleport]") return end
echo("=== gate ===")
echo("Moongate casting requires moon detection, waggle sets, and lnet.")
echo("Pending full integration.")
