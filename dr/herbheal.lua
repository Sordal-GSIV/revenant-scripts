--- @revenant-script
--- name: herbheal
--- version: 1.0
--- author: Alastir
--- game: dr
--- description: Auto herb using/buying script - redirects to EHerbs replacement
--- tags: healing, herbs, buying, eherbs
---
--- Converted from herbheal.lic (Lich5) to Revenant Lua
---
--- The original herbheal.lic was deprecated and replaced by EHerbs.
--- It handled auto-healing from benches, herbsacks, and purchasing from
--- herbalists across many towns (Illistim, Teras, Ta'Vaalor, Zul Logoth,
--- Landing, Mist Harbor, Pinefar, Cysageir, Solhaven, Icemule, Rivers Rest).
---
--- The script would:
--- 1. Check free herbs on benches first (find_herb_cache)
--- 2. Use herbs from your herbsack (herbmaster)
--- 3. Go to bank, withdraw silver, go to nearest herbalist
--- 4. Buy specific herbs for each wound type (limbs/head/neck/torso/nerves/blood)
--- 5. Apply herbs via herbmaster
--- 6. Return to starting room
---
--- Usage: ;herbheal [nobench|help]

local args = Script.vars[0] or ""

if args:lower():find("help") then
    echo("Simply run herbheal without any arguments to use the bench.")
    echo("")
    echo("Type ;herbheal nobench to skip the bench routine")
    echo("")
    echo("Exiting...")
    return
end

echo("This script has been replaced by the script EHerbs.")
echo("EHerbs provides the same auto herb using/buying functionality")
echo("with support for more towns and better herb management.")
echo("")

if Script.exists and Script.exists("eherbs") then
    echo("Starting EHerbs setup...")
    start_script("eherbs", {"setup"})
else
    echo("EHerbs not found. To install:")
    echo("  ;repository download eherbs")
    echo("Then run: ;eherbs setup")
end
