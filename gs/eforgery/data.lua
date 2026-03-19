--- eforgery data tables
-- Material/oil/town mappings ported from eforgery.lic
local M = {}

-- Rental cost for a workshop
M.RENT = 300

-- Town wastebin locations: nearest trash receptacle for each forging town
M.TARGETS = {
    ["Ta'Illistim"]        = { town = 188,   wastebin = "bin" },
    ["Wehnimer's Landing"] = { town = 228,   wastebin = "bin" },
    ["Solhaven"]           = { town = 1438,  wastebin = "bin" },
    ["Icemule Trace"]      = { town = 2300,  wastebin = "bin" },
    ["Teras Isle"]         = { town = 1932,  wastebin = "barrel" },
    ["River's Rest"]       = { town = 10861, wastebin = "bin" },
    ["Zul Logoth"]         = { town = 1005,  wastebin = "barrel" },
    ["Ta'Vaalor"]          = { town = 3516,  wastebin = "barrel" },
}

-- What the oil/water looks like in the trough
M.OIL_TROUGH = {
    ["water"]               = "some water",
    ["tempering oil"]       = "some oil",
    ["enchanted oil"]       = "some iridescent oil",
    ["twice-enchanted oil"] = "some opalescent oil",
    ["ensorcelled oil"]     = "some dimly glowing oil",
}

-- Which material needs which oil
M.MATERIAL_OIL = {
    ["bronze"]    = "water",
    ["iron"]      = "water",
    ["steel"]     = "tempering oil",
    ["invar"]     = "tempering oil",
    ["faenor"]    = "enchanted oil",
    ["mithril"]   = "enchanted oil",
    ["ora"]       = "enchanted oil",
    ["drakar"]    = "enchanted oil",
    ["gornar"]    = "enchanted oil",
    ["rhimar"]    = "enchanted oil",
    ["zorchar"]   = "enchanted oil",
    ["kelyn"]     = "enchanted oil",
    ["imflass"]   = "twice-enchanted oil",
    ["razern"]    = "twice-enchanted oil",
    ["eahnor"]    = "ensorcelled oil",
    ["mithglin"]  = "ensorcelled oil",
    ["vaalorn"]   = "twice-enchanted oil",
    ["vultite"]   = "ensorcelled oil",
    ["rolaren"]   = "ensorcelled oil",
    ["veil iron"] = "ensorcelled oil",
    ["eonake"]    = "ensorcelled oil",
    ["golvern"]   = "ensorcelled oil",
}

-- Order numbers for purchasing oils
M.OIL_ORDER = {
    ["tempering oil"]       = 5,
    ["enchanted oil"]       = 6,
    ["twice-enchanted oil"] = 7,
    ["ensorcelled oil"]     = 8,
}

-- Known promissory note names
M.NOTE_NAMES = {
    "Northwatch bond note",
    "Icemule promissory note",
    "Borthuum Mining Company scrip",
    "Wehnimer's promissory note",
    "Torren promissory note",
    "mining chit",
    "City-States promissory note",
    "Vornavis promissory note",
    "Mist Harbor promissory note",
}

return M
