-- huntpro/config.lua — Settings system with all major config keys
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara (19157 lines)
-- Ported defaults from Ruby Settings[Char.name]['huntpro_setting_*'] block (lines 22-137)

local Config = {}

---------------------------------------------------------------------------
-- Default values for every huntpro setting
-- "0" means disabled/unset (matches Ruby original which stores strings)
---------------------------------------------------------------------------
Config.DEFAULTS = {
    -- Profile / detection
    profile_detection       = "0",
    character_society       = "0",    -- Voln / Col / Gos / None

    -- Skip / ignore lists
    force_skip_list         = "0",
    force_skip_list2        = "0",
    force_skip_list3        = "0",
    compound_ignore         = "0",

    -- Empath
    empath_self_heal        = "0",

    -- Fog return spells
    voln_fog                = "0",
    fog_130                 = "0",    -- Spirit Guide
    fog_1020                = "0",    -- Sign of Seeking

    -- Hunting behaviour
    hunt_while_fried        = "0",
    disable_encumbrance     = "0",
    disable_stamina         = "0",
    disable_mana            = "0",
    disable_140             = "0",
    disable_240             = "0",
    disable_919             = "0",
    disable_306             = "0",
    value_encumbrance       = 50,
    value_stamina           = 10,

    -- Spell upkeep toggles
    upkeep140               = "0",
    upkeep240               = "0",
    upkeep515               = "0",
    upkeep506               = "0",
    upkeep919               = "0",
    upkeep1035              = "0",
    upkeep650               = "0",

    -- Voln deed mana / wrack
    deedmana                = "0",
    wrack                   = "0",

    -- Zone scripts
    zonescripts             = "0",
    run_script              = "0",
    run_script2             = "0",
    run_script3             = "0",

    -- Stance
    stay_offensive          = "0",
    defensive_stance        = "0",
    offensive_stance        = "0",

    -- Loot
    loot_script             = "0",
    cleanloot_script        = "0",

    -- Spell defaults
    spell_default           = "0",
    evoke_default           = "0",

    -- Rest room
    rest_room               = "0",

    -- Equipment detection
    use_shield              = "0",
    use_empty               = "0",
    right_hand_detect       = "0",
    left_hand_detect        = "0",

    -- Group settings
    leader                  = "0",
    group_one               = "0",
    group_two               = "0",
    group_three             = "0",
    group_four              = "0",
    group_five              = "0",
    group_six               = "0",
    group_seven             = "0",
    group_eight             = "0",
    group_nine              = "0",
    group_quiet             = "0",
    group_peace             = "0",
    group_sharemana         = "0",

    -- Combat cleanup
    combat_cleanup          = "0",

    -- Crowd control
    turbo_crowd_control     = "0",
    crowd_control           = "0",
    no_crowd_control        = "0",

    -- CMAN control
    cman_control            = "0",
    no_cman_control         = "0",

    -- Control toggles
    no_shield_control       = "0",
    no_weapon_control       = "0",
    no_2weapon_control      = "0",
    no_mstrike_control      = "0",

    -- Society
    no_society              = "0",
    no_stun                 = "0",
    society_spellactive     = "0",

    -- Bounty toggles
    bounty_noherb           = "0",
    bounty_noskin           = "0",
    bounty_nobandit         = "0",
    bounty_nogroup          = "0",
    bounty_lite             = "0",

    -- Force target
    force_target            = "0",

    -- Ranged
    no_cock                 = "0",

    -- Herbs
    use_herbs               = "0",
    no_herbs                = "0",
    nocleanupherbs          = "0",

    -- Spell waggle
    no_waggle               = "0",

    -- Cleric sanctify
    sanctify_330            = "0",

    -- Style 9 arcane
    style9_arcaneblast      = "0",
    style9_arcanecs         = "0",

    -- Warrior berserk
    berserk                 = "0",
    no_berserk              = "0",

    -- Flee counter
    flee                    = "0",

    -- Weapon attune
    weapon_attune           = "0",

    -- Meditate
    meditate                = "0",

    -- Boost
    boost_long              = "0",
    boost_loot              = "0",

    -- QC / debug
    qc_testing              = "0",
    qc_debug                = "0",

    -- Time limit
    timelimit               = "0",

    -- Misc toggles
    immolate                = "0",
    taxi                    = "0",
    noquartz                = "0",
    disable_pod             = "0",
    disable_cloud           = "0",
    disable_void            = "0",
    disable_vine            = "0",
    disable_sandstorm       = "0",
    disable_web             = "0",
    disable_arms            = "0",
    disable_tempest         = "0",
    solo_mode               = "0",
    use_wands               = "0",
    dead_wands              = "0",
    get_invoked             = "0",
    rescuebox               = "0",
    stomp                   = "0",
    spell_705cs             = "0",
    camo                    = "0",
}

---------------------------------------------------------------------------
-- Load settings from CharSettings, filling in defaults
---------------------------------------------------------------------------
function Config.load()
    local s = {}
    for key, default in pairs(Config.DEFAULTS) do
        local stored = CharSettings["huntpro_" .. key]
        if stored ~= nil and stored ~= "" then
            s[key] = stored
        else
            s[key] = default
        end
    end
    return s
end

---------------------------------------------------------------------------
-- Save a single setting
---------------------------------------------------------------------------
function Config.save(key, value)
    CharSettings["huntpro_" .. key] = tostring(value)
end

---------------------------------------------------------------------------
-- Save all settings from a table
---------------------------------------------------------------------------
function Config.save_all(settings)
    for key, value in pairs(settings) do
        if Config.DEFAULTS[key] ~= nil then
            CharSettings["huntpro_" .. key] = tostring(value)
        end
    end
end

---------------------------------------------------------------------------
-- Reset all settings to defaults
---------------------------------------------------------------------------
function Config.reset()
    for key, default in pairs(Config.DEFAULTS) do
        CharSettings["huntpro_" .. key] = tostring(default)
    end
end

---------------------------------------------------------------------------
-- Display current settings
---------------------------------------------------------------------------
function Config.display(settings)
    respond("")
    respond("|----------- Huntpro Settings -----------|")
    respond("")
    respond("  Society:          " .. (settings.character_society or "0"))
    respond("  Loot Script:      " .. (settings.loot_script or "eloot"))
    respond("  Rest Room:        " .. (settings.rest_room or "0"))
    respond("  Stay Offensive:   " .. (settings.stay_offensive or "0"))
    respond("  Force Target:     " .. (settings.force_target or "0"))
    respond("  Use Herbs:        " .. (settings.use_herbs or "0"))
    respond("  No Waggle:        " .. (settings.no_waggle or "0"))
    respond("  Combat Cleanup:   " .. (settings.combat_cleanup or "0"))
    respond("  Weapon Attune:    " .. (settings.weapon_attune or "0"))
    respond("  Leader:           " .. (settings.leader or "0"))
    respond("  Group Members:    " .. (settings.group_one or "0") .. " / "
                                    .. (settings.group_two or "0") .. " / "
                                    .. (settings.group_three or "0"))
    respond("  No Crowd Control: " .. (settings.no_crowd_control or "0"))
    respond("  No CMan Control:  " .. (settings.no_cman_control or "0"))
    respond("  Boost Long:       " .. (settings.boost_long or "0"))
    respond("  Boost Loot:       " .. (settings.boost_loot or "0"))
    respond("  Flee Counter:     " .. (settings.flee or "0"))
    respond("")
    respond("|----------------------------------------|")
    respond("")
end

---------------------------------------------------------------------------
-- Handle ;huntpro setup change <key> <value>
---------------------------------------------------------------------------
function Config.change(settings, key, value)
    if Config.DEFAULTS[key] == nil then
        respond("Unknown setting: " .. key)
        respond("Use ;huntpro setup to see available settings.")
        return settings
    end
    settings[key] = value
    Config.save(key, value)
    respond(Char.name .. ", setting '" .. key .. "' updated to: " .. tostring(value))
    return settings
end

---------------------------------------------------------------------------
-- Town room ID tables for bounty detection
---------------------------------------------------------------------------
Config.TOWNS = {
    Landing      = {228, 3785, 420, 405, 3824, 4142},
    Icemule      = {2300, 3233, 3778, 3424, 2466, 2406, 2635, 2777},
    Solhaven     = {12805, 1507, 13054, 5723, 5576, 1438},
    ["River's Rest"] = {10992, 10915, 10934, 10861},
    Teras        = {12511, 1957, 1886, 1851, 1932},
    Illistim     = {13048, 37, 4019, 13241, 188},
    Vaalor       = {10332, 5907, 10329, 10397, 3519},
    ["Zul Logoth"]   = {9445, 9411, 9471, 9506, 1005},
    ["Kraken's Fall"] = {28927, 28978, 28942, 28813},
}

---------------------------------------------------------------------------
-- Detect current town from room ID
---------------------------------------------------------------------------
function Config.detect_town()
    local room_id = GameState.room_id
    if not room_id then return "0" end
    for town, ids in pairs(Config.TOWNS) do
        for _, id in ipairs(ids) do
            if id == room_id then return town end
        end
    end
    return "0"
end

return Config
