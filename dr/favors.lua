--- @revenant-script
--- name: favors
--- version: 1.0
--- author: Tarjan
--- game: dr
--- description: Get deity favors by solving temple puzzles.
--- tags: favors, theurgy, quest
--- Usage: ;favors [god_name]
--- Converted from favors.lic
local god = Script.vars[1] or "chadatru"
echo("=== favors ===")
echo("Favor quest for " .. god .. ". Requires go2 navigation for temple puzzles.")
echo("Pending full integration.")
