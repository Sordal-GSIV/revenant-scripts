--- @revenant-script
--- name: prydaen_favors
--- version: 2.0
--- author: Damiza Nihshyde
--- game: dr
--- description: Prydaen favor quest at Triquetra boulder.
--- tags: prydaen, favors, quest
--- Converted from prydaen-favors.lic
if DRStats.race ~= "Prydaen" then echo("No meow.") return end
if DRSkill.getrank("Perception") <= 64 then echo("Not enough perception.") return end
echo("=== prydaen_favors ===")
echo("Requires go2 navigation for multi-room quest. Pending full integration.")
