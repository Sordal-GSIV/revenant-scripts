--- @revenant-script
--- name: playershopsearchomatic
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Search Crossing and Haven player shops for items.
--- tags: shopping, search, playershops
--- Usage: ;playershopsearchomatic <item>
--- Converted from playershopsearchomatic.lic
local item = Script.vars[1]
if not item then echo("Usage: ;playershopsearchomatic <item>") return end
echo("=== playershopsearchomatic ===")
echo("Searching player shops for: " .. item)
echo("Requires go2 navigation for multi-room search. Pending full integration.")
