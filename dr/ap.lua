--- @revenant-script
--- name: ap
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Astral travel to named destination stones.
--- tags: moonmage, astral, travel
--- Usage: ;ap <destination_stone>
--- Converted from ap.lic

local stones = {
    Auilusi = "Aesry", ["Dor'na'torna"] = "Arid Steppes/Hib",
    Rolagi = "Crossing", Vellano = "Fang Cove",
    ["Asharshpar'i"] = "Leth Deriel", Besoge = "Mer'Kresh",
    Tabelrem = "Muspar'i", Tamigen = "Raven's Point",
    Taniendar = "Riverhaven", Marendin = "Shard",
    Erekinzil = "Taisgath", Dinegavren = "Therenborough",
    Mintais = "Throne City",
}

local dest = Script.vars[1]
if not dest then
    echo("=== Astral Plane Stones ===")
    for stone, loc in pairs(stones) do
        echo("  " .. stone .. " - " .. loc)
    end
    return
end
echo("Traveling to " .. dest .. "...")
echo("Requires apwatch companion script and full AP integration.")
