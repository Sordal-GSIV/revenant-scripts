-- osacombat/config.lua — Configuration module for OSACombat
-- Handles defaults, CharSettings persistence (JSON), and creature_type detection.
-- Original: osacombat.lic by OSA (GemStone IV automated combat)

local M = {}

---------------------------------------------------------------------------
-- DEFAULTS — every setting key from the original Lich5 osacombat script.
-- String defaults match the original Ruby semantics.
---------------------------------------------------------------------------
local DEFAULTS = {
    -- Combat settings
    percentleech            = "50",
    wound_level             = "0",
    percent_health          = "65",
    safe_room               = "",
    uachands                = false,
    uacfeet                 = false,
    flareglovesnoun         = "",
    energy_wings_noun       = "",
    infusespell             = "",
    exclusion               = "",
    stealth_disabler        = "Search (Default)",

    -- Boolean toggles
    osacombat               = false,
    use_mana_leech          = false,
    stomp                   = false,
    pound                   = false,
    tap                     = false,
    noattack                = false,
    stance_dance            = false,
    osaarcher               = false,
    use_kneel               = false,
    use_mstrike             = false,
    use_stealth             = false,
    use_waylay              = false,
    uacweapons              = false,
    nouacweapons            = false,
    usebriefcombat          = false,
    use_reactive            = false,
    check_for_group         = false,
    use_unstun              = false,
    osalooter               = false,
    usekilltracker          = false,
    skin_only               = false,
    givebless               = false,
    needbless               = false,

    -- Support/Buff toggles
    warcry_shout            = false,
    warcry_holler           = false,
    cman_surge_of_strength_cooldown    = false,
    cman_surge_of_strength_no_cooldown = false,
    spell_wall_of_force     = false,
    groupbravery            = false,
    spell_heroism           = false,
    sanctrighthand          = false,
    sanctlefthand           = false,
    cast_spell_mana_focus   = false,
    cast_spell_self_celerity  = false,
    cast_spell_group_celerity = false,
    spell_rapid_fire        = false,
    barkskin_spell          = false,
    barkskin_spell_group    = false,
    song_song_of_tonis      = false,
    mob                     = false,
    focus                   = false,
    spell_beacon_of_courage = false,
    spell_shield_faith      = false,
    di_armor                = false,
    cast_spell_di_zeal      = false,
    shield_steely           = false,
    symbol_of_mana          = false,
    sigil_of_mana           = false,
    symbol_of_restore       = false,
    symbol_of_transcendance = false,

    -- Society Signs
    sign_of_warding         = false,
    sign_of_defending       = false,
    sign_of_shields         = false,
    sign_of_striking        = false,
    sign_of_smiting         = false,
    sign_of_swords          = false,

    -- Society Sigils
    sigil_of_minor_bane     = false,
    sigil_of_offense        = false,
    sigil_of_major_bane     = false,
    sigil_of_minor_protection = false,
    sigil_of_defense        = false,
    sigil_of_major_protection = false,
    sigil_of_concentration  = false,
    sigil_of_power          = false,

    -- Society Symbols
    symbol_of_courage       = false,
    symbol_of_protection    = false,
    symbol_of_retribution   = false,
    symbol_of_supremacy     = false,
    symbol_of_disruption    = false,

    -- Living combat attacks
    attack_stance           = "Offensive",
    defending_stance        = "Defensive",
    setup_attack            = "None",
    setup_attack_stam_min   = "0",
    setup_attack_man_min    = "0",
    setup_attack_enemy_min  = "1",
    setup_attack_enemy_max  = "10",
    setup_attack2           = "None",
    setup_attack2_stam_min  = "0",
    setup_attack2_man_min   = "0",
    setup_attack2_enemy_min = "1",
    setup_attack2_enemy_max = "10",
    special_attack          = "None",
    special_attack_stam_min = "0",
    special_attack_man_min  = "0",
    special_attack_enemy_min = "1",
    special_attack_enemy_max = "10",
    special_attack2         = "None",
    special_attack2_stam_min = "0",
    special_attack2_man_min = "0",
    special_attack2_enemy_min = "1",
    special_attack2_enemy_max = "10",
    aoe_attack              = "None",
    aoe_attack_stam_min     = "0",
    aoe_attack_man_min      = "0",
    aoe_attack_enemy_min    = "1",
    aoe_attack_enemy_max    = "10",
    aoe_attack2             = "None",
    aoe_attack2_stam_min    = "0",
    aoe_attack2_man_min     = "0",
    aoe_attack2_enemy_min   = "1",
    aoe_attack2_enemy_max   = "10",
    assault                 = "None",
    assault_stam_min        = "0",
    assault_man_min         = "0",
    assault_enemy_min       = "1",
    assault_enemy_max       = "10",
    assault2                = "None",
    assault2_stam_min       = "0",
    assault2_man_min        = "0",
    assault2_enemy_min      = "1",
    assault2_enemy_max      = "10",

    -- Living spell openers
    spell_opener            = "",
    spell_opener_stam_min   = "0",
    spell_opener_man_min    = "0",
    spell_opener_enemy_min  = "1",
    spell_opener_enemy_max  = "10",
    spell_opener_warding    = false,
    spell_opener_channel    = false,
    spell_opener_evoke      = false,
    spell_opener_open_cast  = false,
    spell_opener2           = "",
    spell_opener2_stam_min  = "0",
    spell_opener2_man_min   = "0",
    spell_opener2_enemy_min = "1",
    spell_opener2_enemy_max = "10",
    spell_opener2_warding   = false,
    spell_opener2_channel   = false,
    spell_opener2_evoke     = false,
    spell_opener2_open_cast = false,

    -- Living attack spells 1-5
    attack_spell            = "",
    attack_spell_stam_min   = "0",
    attack_spell_man_min    = "0",
    attack_spell_enemy_min  = "1",
    attack_spell_enemy_max  = "10",
    attack_spell_warding    = false,
    attack_spell_channel    = false,
    attack_spell_evoke      = false,
    attack_spell_open_cast  = false,
    attack_spell2           = "",
    attack_spell2_stam_min  = "0",
    attack_spell2_man_min   = "0",
    attack_spell2_enemy_min = "1",
    attack_spell2_enemy_max = "10",
    attack_spell2_warding   = false,
    attack_spell2_channel   = false,
    attack_spell2_evoke     = false,
    attack_spell2_open_cast = false,
    attack_spell3           = "",
    attack_spell3_stam_min  = "0",
    attack_spell3_man_min   = "0",
    attack_spell3_enemy_min = "1",
    attack_spell3_enemy_max = "10",
    attack_spell3_warding   = false,
    attack_spell3_channel   = false,
    attack_spell3_evoke     = false,
    attack_spell3_open_cast = false,
    attack_spell4           = "",
    attack_spell4_stam_min  = "0",
    attack_spell4_man_min   = "0",
    attack_spell4_enemy_min = "1",
    attack_spell4_enemy_max = "10",
    attack_spell4_warding   = false,
    attack_spell4_channel   = false,
    attack_spell4_evoke     = false,
    attack_spell4_open_cast = false,
    attack_spell5           = "",
    attack_spell5_stam_min  = "0",
    attack_spell5_man_min   = "0",
    attack_spell5_enemy_min = "1",
    attack_spell5_enemy_max = "10",
    attack_spell5_warding   = false,
    attack_spell5_channel   = false,
    attack_spell5_evoke     = false,
    attack_spell5_open_cast = false,

    -- Undead combat attacks
    undead_attack_stance           = "Offensive",
    undead_defending_stance        = "Defensive",
    undead_setup_attack            = "None",
    undead_setup_attack_stam_min   = "0",
    undead_setup_attack_man_min    = "0",
    undead_setup_attack_enemy_min  = "1",
    undead_setup_attack_enemy_max  = "10",
    undead_setup_attack2           = "None",
    undead_setup_attack2_stam_min  = "0",
    undead_setup_attack2_man_min   = "0",
    undead_setup_attack2_enemy_min = "1",
    undead_setup_attack2_enemy_max = "10",
    undead_special_attack          = "None",
    undead_special_attack_stam_min = "0",
    undead_special_attack_man_min  = "0",
    undead_special_attack_enemy_min = "1",
    undead_special_attack_enemy_max = "10",
    undead_special_attack2         = "None",
    undead_special_attack2_stam_min = "0",
    undead_special_attack2_man_min = "0",
    undead_special_attack2_enemy_min = "1",
    undead_special_attack2_enemy_max = "10",
    undead_aoe_attack              = "None",
    undead_aoe_attack_stam_min     = "0",
    undead_aoe_attack_man_min      = "0",
    undead_aoe_attack_enemy_min    = "1",
    undead_aoe_attack_enemy_max    = "10",
    undead_aoe_attack2             = "None",
    undead_aoe_attack2_stam_min    = "0",
    undead_aoe_attack2_man_min     = "0",
    undead_aoe_attack2_enemy_min   = "1",
    undead_aoe_attack2_enemy_max   = "10",
    undead_assault                 = "None",
    undead_assault_stam_min        = "0",
    undead_assault_man_min         = "0",
    undead_assault_enemy_min       = "1",
    undead_assault_enemy_max       = "10",
    undead_assault2                = "None",
    undead_assault2_stam_min       = "0",
    undead_assault2_man_min        = "0",
    undead_assault2_enemy_min      = "1",
    undead_assault2_enemy_max      = "10",

    -- Undead spell openers
    undead_spell_opener            = "",
    undead_spell_opener_stam_min   = "0",
    undead_spell_opener_man_min    = "0",
    undead_spell_opener_enemy_min  = "1",
    undead_spell_opener_enemy_max  = "10",
    undead_spell_opener_warding    = false,
    undead_spell_opener_channel    = false,
    undead_spell_opener_evoke      = false,
    undead_spell_opener_open_cast  = false,
    undead_spell_opener2           = "",
    undead_spell_opener2_stam_min  = "0",
    undead_spell_opener2_man_min   = "0",
    undead_spell_opener2_enemy_min = "1",
    undead_spell_opener2_enemy_max = "10",
    undead_spell_opener2_warding   = false,
    undead_spell_opener2_channel   = false,
    undead_spell_opener2_evoke     = false,
    undead_spell_opener2_open_cast = false,

    -- Undead attack spells 1-5
    undead_attack_spell            = "",
    undead_attack_spell_stam_min   = "0",
    undead_attack_spell_man_min    = "0",
    undead_attack_spell_enemy_min  = "1",
    undead_attack_spell_enemy_max  = "10",
    undead_attack_spell_warding    = false,
    undead_attack_spell_channel    = false,
    undead_attack_spell_evoke      = false,
    undead_attack_spell_open_cast  = false,
    undead_attack_spell2           = "",
    undead_attack_spell2_stam_min  = "0",
    undead_attack_spell2_man_min   = "0",
    undead_attack_spell2_enemy_min = "1",
    undead_attack_spell2_enemy_max = "10",
    undead_attack_spell2_warding   = false,
    undead_attack_spell2_channel   = false,
    undead_attack_spell2_evoke     = false,
    undead_attack_spell2_open_cast = false,
    undead_attack_spell3           = "",
    undead_attack_spell3_stam_min  = "0",
    undead_attack_spell3_man_min   = "0",
    undead_attack_spell3_enemy_min = "1",
    undead_attack_spell3_enemy_max = "10",
    undead_attack_spell3_warding   = false,
    undead_attack_spell3_channel   = false,
    undead_attack_spell3_evoke     = false,
    undead_attack_spell3_open_cast = false,
    undead_attack_spell4           = "",
    undead_attack_spell4_stam_min  = "0",
    undead_attack_spell4_man_min   = "0",
    undead_attack_spell4_enemy_min = "1",
    undead_attack_spell4_enemy_max = "10",
    undead_attack_spell4_warding   = false,
    undead_attack_spell4_channel   = false,
    undead_attack_spell4_evoke     = false,
    undead_attack_spell4_open_cast = false,
    undead_attack_spell5           = "",
    undead_attack_spell5_stam_min  = "0",
    undead_attack_spell5_man_min   = "0",
    undead_attack_spell5_enemy_min = "1",
    undead_attack_spell5_enemy_max = "10",
    undead_attack_spell5_warding   = false,
    undead_attack_spell5_channel   = false,
    undead_attack_spell5_evoke     = false,
    undead_attack_spell5_open_cast = false,

    -- Gemstone abilities
    gemstone_arcane_aegis                      = false,
    activate_arcane_aegis_mana_if              = "40",
    gemstone_arcanists_ascendancy              = false,
    activate_arcanists_ascendancy_enemy_if     = "1",
    gemstone_arcanists_blade                   = false,
    activate_arcanists_blade_enemy_if          = "1",
    activate_arcanists_blade_mana_if           = "0",
    activate_arcanists_blade_stamina_if        = "0",
    gemstone_arcanists_will                    = false,
    activate_arcanists_will_enemy_if           = "1",
    activate_arcanists_will_mana_if            = "0",
    activate_arcanists_will_stamina_if         = "0",
    gemstone_blood_boil                        = false,
    activate_blood_boil_enemy_if               = "1",
    gemstone_blood_siphon                      = false,
    activate_blood_siphon_enemy_if             = "1",
    gemstone_blood_wellspring                  = false,
    activate_blood_wellspring_health_if        = "50",
    gemstone_evanescent_possession             = false,
    activate_evanescent_possession_enemy_if    = "1",
    gemstone_force_of_will                     = false,
    gemstone_geomancers_spite                  = false,
    activate_geomancers_spite_enemy_if         = "1",
    gemstone_mana_shield                       = false,
    activate_mana_shield_mana_if               = "40",
    gemstone_mana_wellspring                   = false,
    activate_mana_wellspring_mana_if           = "50",
    gemstone_reckless_precision                = false,
    activate_reckless_precision_enemy_if       = "6",
    gemstone_spellblades_fury                  = false,
    activate_spellblades_fury_enemy_if         = "3",
    activate_spellblades_fury_mana_if          = "120",
    gemstone_spirit_wellspring                 = false,
    activate_spirit_wellspring_spirit_if       = "8",
    gemstone_unearthly_chains                  = false,
    activate_unearthly_chains_enemy_if         = "2",
    gemstone_witchhunters_ascendancy           = false,
    activate_witchhunters_ascendancy_enemy_if  = "3",
}

--- Expose DEFAULTS for external inspection (e.g. GUI settings)
M.defaults = DEFAULTS

--- Current settings table (populated by M.load)
M.data = {}

---------------------------------------------------------------------------
-- Deep-copy a value (handles nested tables)
---------------------------------------------------------------------------
local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, item in pairs(v) do
        copy[k] = deep_copy(item)
    end
    return copy
end

---------------------------------------------------------------------------
-- M.load() — Load settings from CharSettings.osacombat (JSON).
-- Missing keys filled from DEFAULTS so callers always see every key.
---------------------------------------------------------------------------
function M.load()
    local state = {}

    local raw = CharSettings.osacombat
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                state[k] = v
            end
        end
    end

    -- Merge defaults for any missing keys
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then
            state[k] = deep_copy(v)
        end
    end

    M.data = state
    return state
end

---------------------------------------------------------------------------
-- M.save() — Persist current settings to CharSettings as JSON.
-- Only writes keys that exist in DEFAULTS (avoids runtime transients).
---------------------------------------------------------------------------
function M.save()
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        if M.data[k] ~= nil then
            prefs[k] = M.data[k]
        end
    end
    CharSettings.osacombat = Json.encode(prefs)
end

---------------------------------------------------------------------------
-- M.get(key) — Get a setting value with default fallback.
---------------------------------------------------------------------------
function M.get(key)
    local val = M.data[key]
    if val ~= nil then return val end
    local def = DEFAULTS[key]
    if def ~= nil then return deep_copy(def) end
    return nil
end

---------------------------------------------------------------------------
-- M.set(key, value) — Set a setting value.
---------------------------------------------------------------------------
function M.set(key, value)
    M.data[key] = value
end

---------------------------------------------------------------------------
-- M.get_num(key) — Get setting as a number (tonumber with 0 fallback).
---------------------------------------------------------------------------
function M.get_num(key)
    local val = M.get(key)
    if val == nil or val == "" then return 0 end
    return tonumber(val) or 0
end

---------------------------------------------------------------------------
-- M.get_bool(key) — Get setting as a boolean.
-- Truthy: true, "true", "1", "yes", non-zero numbers.
---------------------------------------------------------------------------
function M.get_bool(key)
    local val = M.get(key)
    if val == nil then return false end
    if type(val) == "boolean" then return val end
    if type(val) == "number" then return val ~= 0 end
    if type(val) == "string" then
        local lower = val:lower()
        return lower == "true" or lower == "1" or lower == "yes"
    end
    return false
end

---------------------------------------------------------------------------
-- Compute cast_type string from evoke/channel flags.
-- Returns "evoke channel", "evoke", "channel", or "" based on flags.
---------------------------------------------------------------------------
local function compute_cast_type(evoke, channel)
    if evoke and channel then
        return "evoke channel"
    elseif evoke then
        return "evoke"
    elseif channel then
        return "channel"
    else
        return ""
    end
end

---------------------------------------------------------------------------
-- M.creature_type() — Detect living vs undead targets and load the
-- appropriate attack configuration. Returns a config table with all
-- combat fields resolved for the current encounter.
---------------------------------------------------------------------------
function M.creature_type()
    local targets = GameObj.targets and GameObj.targets() or {}

    -- Check if any target is undead
    local has_undead = false
    for _, npc in ipairs(targets) do
        local npc_type = (npc.type or ""):lower()
        if npc_type:find("undead") then
            has_undead = true
            break
        end
    end

    -- Select prefix: undead settings or living (no prefix)
    local prefix = has_undead and "undead_" or ""

    local cfg = {}

    -- Stances
    cfg.attack_stance    = M.get(prefix .. "attack_stance") or "Offensive"
    cfg.defending_stance = M.get(prefix .. "defending_stance") or "Defensive"

    -- Physical attacks: setup, special, aoe, assault (each with x2 variant)
    local attack_types = {
        "setup_attack", "setup_attack2",
        "special_attack", "special_attack2",
        "aoe_attack", "aoe_attack2",
        "assault", "assault2",
    }
    for _, atk in ipairs(attack_types) do
        cfg[atk]               = M.get(prefix .. atk) or "None"
        cfg[atk .. "_stam_min"]  = M.get_num(prefix .. atk .. "_stam_min")
        cfg[atk .. "_man_min"]   = M.get_num(prefix .. atk .. "_man_min")
        cfg[atk .. "_enemy_min"] = M.get_num(prefix .. atk .. "_enemy_min")
        cfg[atk .. "_enemy_max"] = M.get_num(prefix .. atk .. "_enemy_max")
    end

    -- Spell openers
    local opener_keys = { "spell_opener", "spell_opener2" }
    for _, opener in ipairs(opener_keys) do
        cfg[opener]                = M.get(prefix .. opener) or ""
        cfg[opener .. "_stam_min"]   = M.get_num(prefix .. opener .. "_stam_min")
        cfg[opener .. "_man_min"]    = M.get_num(prefix .. opener .. "_man_min")
        cfg[opener .. "_enemy_min"]  = M.get_num(prefix .. opener .. "_enemy_min")
        cfg[opener .. "_enemy_max"]  = M.get_num(prefix .. opener .. "_enemy_max")
        cfg[opener .. "_warding"]    = M.get_bool(prefix .. opener .. "_warding")
        cfg[opener .. "_channel"]    = M.get_bool(prefix .. opener .. "_channel")
        cfg[opener .. "_evoke"]      = M.get_bool(prefix .. opener .. "_evoke")
        cfg[opener .. "_open_cast"]  = M.get_bool(prefix .. opener .. "_open_cast")
    end

    -- Attack spells 1-5
    local suffixes = { "", "2", "3", "4", "5" }
    for i, sfx in ipairs(suffixes) do
        local key = "attack_spell" .. sfx
        cfg[key]                = M.get(prefix .. key) or ""
        cfg[key .. "_stam_min"]   = M.get_num(prefix .. key .. "_stam_min")
        cfg[key .. "_man_min"]    = M.get_num(prefix .. key .. "_man_min")
        cfg[key .. "_enemy_min"]  = M.get_num(prefix .. key .. "_enemy_min")
        cfg[key .. "_enemy_max"]  = M.get_num(prefix .. key .. "_enemy_max")
        cfg[key .. "_warding"]    = M.get_bool(prefix .. key .. "_warding")
        cfg[key .. "_channel"]    = M.get_bool(prefix .. key .. "_channel")
        cfg[key .. "_evoke"]      = M.get_bool(prefix .. key .. "_evoke")
        cfg[key .. "_open_cast"]  = M.get_bool(prefix .. key .. "_open_cast")

        -- Compute cast_type for each attack spell
        cfg["cast_type" .. tostring(i)] = compute_cast_type(
            cfg[key .. "_evoke"],
            cfg[key .. "_channel"]
        )
    end

    cfg.is_undead = has_undead

    return cfg
end

return M
