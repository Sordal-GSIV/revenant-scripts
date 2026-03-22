--- sloot/settings.lua
-- Settings management and UserVars sack bindings.
-- Mirrors CharSettings and UserVars usage from sloot.lic v3.5.2.

local M = {}

-- All keys from the original Lich5 CharSettings hash.
local DEFAULTS = {
    -- Loot types
    enable_loot_gem        = true,
    enable_loot_skin       = true,
    enable_loot_box        = true,
    enable_loot_magic      = true,
    enable_loot_scroll     = true,
    enable_loot_wand       = true,
    enable_loot_jewelry    = true,
    enable_loot_herb       = true,
    enable_loot_reagent    = true,
    enable_loot_lockpick   = true,
    enable_loot_uncommon   = true,
    enable_loot_valuable   = true,
    enable_loot_collectible = true,
    enable_loot_clothing   = false,
    enable_loot_ammo       = false,
    -- Skinning
    enable_skinning        = false,
    enable_skin_alternate  = false,
    enable_skin_kneel      = false,
    enable_skin_offensive  = false,
    enable_skin_604        = false,
    enable_skin_sigil      = false,
    enable_skin_safe_mode  = true,
    enable_skin_stance_first = false,
    skin_stand_verb        = "",
    skin_exclude           = {},
    -- Looting advanced
    enable_search_all      = true,
    enable_stow_left       = false,
    enable_safe_hiding     = false,
    enable_self_drops      = false,
    enable_disking         = false,
    enable_phasing         = false,
    enable_gather          = false,
    enable_close_sacks     = false,
    enable_stance_on_start = false,
    safe_ignore            = "",
    loot_exclude           = "drake|feras|black ora",
    critter_exclude        = "",
    overflowsack           = "",
    ammo_name              = "",
    -- Sell types
    enable_sell_type_gem   = true,
    enable_sell_type_skin  = true,
    enable_sell_type_magic = false,
    enable_sell_type_scroll = false,
    enable_sell_type_wand  = false,
    enable_sell_type_jewelry = false,
    enable_sell_type_lockpick = false,
    enable_sell_type_reagent = false,
    enable_sell_type_valuable = false,
    enable_sell_type_clothing = false,
    enable_sell_type_empty_box = false,
    enable_sell_type_scarab = false,
    -- Sell advanced
    enable_sell_locksmith  = false,
    enable_locker_boxes    = false,
    enable_sell_chronomage = false,
    enable_sell_stockpile  = false,
    enable_sell_share_silvers = false,
    sell_exclude           = "gold ring|(?:gold|aquamarine) wand|(?:white|black) crystal",
    sell_withdraw          = "",
    -- Locker
    locker                 = "",
    locker_in              = "",
    locker_out             = "",
}

-- UserVars keys that hold sack names (shared per character, like Lich5 UserVars)
M.UVAR_SACK_KEYS = {
    "ammosack", "boxsack", "gemsack", "herbsack", "jewelrysack",
    "lockpicksack", "magicsack", "reagentsack", "scrollsack",
    "skinsack", "uncommonsack", "valuablesack", "clothingsack",
    "wandsack", "collectiblesack", "foragesack",
    "skinweapon", "skinweaponblunt", "skinweaponsack",
}

local function load()
    local raw = CharSettings["sloot_settings"]
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save(s)
    CharSettings["sloot_settings"] = Json.encode(s)
end

function M.load()
    local s = load()
    -- Merge defaults for any missing keys
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    return s
end

function M.save(s)
    save(s)
end

--- Get a UserVar sack name (empty string if unset)
function M.uvar_get(key)
    local v = UserVars[key]
    if v == nil then return "" end
    return tostring(v)
end

--- Set a UserVar sack name
function M.uvar_set(key, value)
    UserVars[key] = value or ""
end

return M
