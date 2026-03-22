--- @module blackarts.settings
-- Settings load/save with defaults.
-- Ported from BlackArts::Data and BlackArts.load_profile / save_profile (BlackArts.lic v3.12.x)

local M = {}

local SETTINGS_KEY = "blackarts_settings"

M.DEFAULT = {
    -- Guild skills to train (array of "alchemy", "potions", "trinkets", "illusions")
    skill_types            = {},

    -- Illusions
    shadow_drop_item       = "",

    -- Foraging
    forage_options         = {},         -- flags: "run", "use_213", "use_709", "use_919", "use_140"
    no_forage_rooms        = "",         -- comma-separated room IDs

    -- Behaviour flags
    only_required_creatures = false,
    use_vouchers            = false,
    use_boost               = false,
    once_and_done           = false,
    no_alchemy              = false,
    rr_travel               = false,     -- include River's Rest in guild travel
    guild_travel            = false,
    guild_pause             = 60,        -- seconds to pause between guilds

    -- Guild home selection ("Closest" or specific town name)
    home_guild              = "Closest",
    home_guild_name         = "",

    -- Banking
    buy_reagents            = false,
    sell_consignment        = false,
    no_bank                 = false,
    note_withdrawal         = "50000",
    note_refresh            = "5000",

    -- Mana / spirit supplements
    use_wracking            = false,
    use_symbol_mana         = false,
    use_symbol_renewal      = false,
    use_sigil_power         = false,
    use_sigil_concentration = false,

    -- Pre/post hunt hooks
    forage_prep_commands    = "",
    forage_prep_scripts     = "",
    forage_post_commands    = "",
    forage_post_scripts     = "",

    -- Lists (arrays of strings)
    consignment_include     = {},
    item_include            = {},
    recipe_exclude          = {},
    trash                   = {},
    no_magic                = {},

    -- Output
    silence                 = true,
    debug                   = false,

    -- Hunting profiles a–j
    names_a = "", profile_a = "", kill_a = false,
    names_b = "", profile_b = "", kill_b = false,
    names_c = "", profile_c = "", kill_c = false,
    names_d = "", profile_d = "", kill_d = false,
    names_e = "", profile_e = "", kill_e = false,
    names_f = "", profile_f = "", kill_f = false,
    names_g = "", profile_g = "", kill_g = false,
    names_h = "", profile_h = "", kill_h = false,
    names_i = "", profile_i = "", kill_i = false,
    names_j = "", profile_j = "", kill_j = false,

    profile_name_a = "", profile_name_b = "", profile_name_c = "",
    profile_name_d = "", profile_name_e = "", profile_name_f = "",
    profile_name_g = "", profile_name_h = "", profile_name_i = "",
    profile_name_j = "",
}

--- Load settings from CharSettings, merging in any missing keys from DEFAULT.
function M.load()
    local raw = CharSettings[SETTINGS_KEY]
    local ok, t
    if raw and raw ~= "" then
        ok, t = pcall(Json.decode, raw)
    end
    local cfg = (ok and type(t) == "table") and t or {}
    for k, v in pairs(M.DEFAULT) do
        if cfg[k] == nil then cfg[k] = v end
    end
    -- Normalise guild_pause to integer
    cfg.guild_pause = (tonumber(cfg.guild_pause) or 0) > 0 and tonumber(cfg.guild_pause) or 60
    return cfg
end

--- Persist current settings to CharSettings.
function M.save(cfg)
    CharSettings[SETTINGS_KEY] = Json.encode(cfg)
end

--- Parse note_withdrawal / note_refresh strings into integers.
function M.parse_silver(str, default)
    if not str then return default end
    local n = tonumber(tostring(str):gsub("[,%s]", ""):gsub("silver", ""))
    return (n and n > 0) and n or default
end

return M
