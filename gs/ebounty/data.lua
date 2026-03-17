local M = {}

M.bounty_towns_uid = {
    ["Icemule Trace"]      = "u4042150",
    ["Kharam-Dzu"]         = "u3001025",
    ["Kraken's Fall"]      = "u7118221",
    ["Mist Harbor"]        = "u3201029",
    ["River's Rest"]       = "u2101008",
    ["Solhaven"]           = "u4209030",
    ["Vornavis"]           = "u4209030",
    ["Ta'Illistim"]        = "u13100042",
    ["Ta'Vaalor"]          = "u14100047",
    ["Wehnimer's Landing"] = "u7120",
    ["Zul Logoth"]         = "u13006016",
    ["Cold River"]         = "u7503205",
    ["Contempt"]           = "u7150608",
}

M.herbalist_room_uids = {
    "u4043601", "u1015", "u3003056", "u14103400", "u13104200",
    "u4740011", "u2101052", "u13010004", "u7118358", "u7503253",
    "u3201291", "u7150621",
}

M.furrier_patterns = {
    "Bramblefist", "Delosa", "dwarven clerk", "furrier",
    "patchwork flesh merchant",
}

M.jeweler_patterns = {
    "areacne", "Brindlestoat", "dwarven clerk", "gem dealer",
    "jeweler", "plump purple%-robed trader", "Zirconia",
}

M.herbalist_patterns = {
    "Akrash", "alchemist", "brother Barnstel", "famed baker Leaftoe",
    "healer", "herbalist", "Libram Greenleaf", "Maraene",
    "merchant Kelph", "old Mistress Lomara", "scarred Agarnil kris",
    "Sparkfinger", "spectral quartermaster",
}

M.guard_patterns = {
    "guard", "sergeant", "guardsman", "sentry",
    "tavernkeeper", "alchemist", "Malovor",
}

M.crosswalk = {
    bandits   = "kill_bandits",
    creature  = "culling",
    dangerous = "boss_culling",
    cull      = "culling",
    escort    = "escort",
    gem       = "gem_collecting",
    heirloom  = "heirloom_both",
    herb      = "foraging",
    rescue    = "rescue",
    skin      = "skinning",
}

M.escort_pickup = {
    ["the area just inside the Sapphire Gate"]                   = "illy",
    ["the area just inside the North Gate"]                      = "landing",
    ["the south end of North Market"]                            = "solhaven",
    ["the area just north of the South Gate, past the barbican"] = "icemule",
    ["the Kresh'ar Deep monument"]                               = "zul",
    ["the area just inside the Amaranth Gate"]                   = "vaalor",
}

M.escort_dropoff = {
    ["Wehnimer's Landing"] = "landing",
    ["Icemule Trace"]      = "icemule",
    ["Zul Logoth"]         = "zul",
    ["Solhaven"]           = "solhaven",
    ["Ta'Vaalor"]          = "vaalor",
    ["Ta'Illistim"]        = "illy",
}

M.sailors_grief_rooms = {
    7150601, 7150602, 7150603, 7150604, 7150605,
    7150606, 7150607, 7150608, 7150609, 7150610,
    7150611, 7150612, 7150613, 7150614, 7150615,
    7150616, 7150617, 7150621, 7150622,
}

M.forage_results = {
    "You forage", "You make so much noise", "You stumble about",
    "you are unable to find anything useful", "you can find no hint",
    "you see no evidence", "something that stabs you",
    "you suddenly feel a sharp pain", "a burning sensation",
    "You fumble about so badly",
}

M.forage_injuries = {
    "something that stabs you in the finger",
    "you suddenly feel a sharp pain",
    "a burning sensation in your hand",
}

M.stance_names = {
    [0]   = "offensive", [20]  = "advanced", [40]  = "forward",
    [60]  = "neutral",   [80]  = "guarded",  [100] = "defensive",
}

function M.matches_any(name, patterns)
    for _, pat in ipairs(patterns) do
        if name:find(pat) then return true end
    end
    return false
end

return M
