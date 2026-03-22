return {
    name        = "go2",
    version     = "2.2.13",
    author      = "Tillmen (tillmen@lichproject.org)",
    contributors = {
        "Shaelun (original author)",
        "Deysh", "Doug", "Gildaren", "Sarvatt", "Tysong",
        "Xanlin", "Dissonance", "Rinualdo", "Mahtra",
    },
    port        = "Sordal (Revenant Lua conversion)",
    description = "Shortest-path navigation between any two rooms using the map database. "
               .. "Supports urchin guides, portmasters, Chronomage day passes, FWI trinket, "
               .. "caravan to/from SoS, Hinterwilds gigas travel, Elemental Confluence, "
               .. "CHE locker, custom targets, drag mode, ice mode, typeahead, and silver "
               .. "cost estimation with automatic bank navigation.",
    game        = "any",
    tags        = { "core", "movement" },
    depends     = { "lib/stringproc" },
}
