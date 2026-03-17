--- @revenant-script
--- name: old_service_cost
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Legacy service cost calculator for enchanting and other player services
--- tags: service, cost, calculator, enchanting
---
--- Ported from old-service-cost.lic (Lich5 lib/) to Revenant Lua
---
--- See also: ;service_cost for the updated version.
---
--- Usage:
---   ;old_service_cost   - Show legacy service cost calculator

echo("=== Old Service Cost Calculator ===")
echo("This is the legacy version. Use ;service_cost for the updated calculator.")
echo("")
echo("Legacy cost reference:")
echo("  Enchant: 312.5 * (level-1) per cast up to +24")
echo("  Ensorcell: 50k/75k/100k/125k/150k for levels 1-5")
echo("  Sanctify: 50k/75k/100k/125k/150k/200k for levels 1-6")
echo("  Grit: 25k per level")
