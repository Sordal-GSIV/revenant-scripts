--- ELoot settings management
-- Ported from eloot.lic lines 1723-1893, 2106-2139
-- Handles profile load/save, defaults, setting coercion, validation.
--
-- Usage:
--   local Settings = require("gs.eloot.settings")
--   local data = Settings.load()

local M = {}

-- ---------------------------------------------------------------------------
-- Defaults — every setting with its default value
-- Organized by category matching the original Ruby source (lines 1760-1822)
-- ---------------------------------------------------------------------------

M.DEFAULTS = {
    -- Looting: what to pick up and how
    loot_types = {
        "alchemy", "armor", "box", "breakable", "clothing", "collectible",
        "food", "gem", "jewelry", "lockpick", "lm trap", "magic", "reagent",
        "scroll", "skin", "uncommon", "valuable", "wand",
    },
    loot_exclude           = { "black ora", "urglaes" },
    loot_phase             = false,
    loot_defensive         = false,
    use_disk               = true,
    use_disk_group         = false,
    auto_close             = {},
    track_full_sacks       = true,
    crumbly                = {},
    unskinnable            = {},
    unlootable             = {},
    favor_left             = false,
    log_unlootables        = false,

    -- Selling: what to sell and how
    sell_loot_types = {
        "alchemy", "armor", "breakable", "clothing", "food", "gem", "jewelry",
        "lockpick", "magic", "reagent", "scroll", "skin", "uncommon",
        "valuable", "wand", "box", "lm trap",
    },
    sell_container = {
        "default", "overflow", "box", "collectible", "forageable", "gem",
        "herb", "lockpick", "potion", "reagent", "scroll", "skin", "treasure",
        "trinket", "wand",
    },
    sell_exclude           = {},
    sell_keep_scrolls      = {},
    sell_appraise_types    = { "jewelry", "magic", "uncommon", "valuable" },
    sell_appraise_gemshop  = 14999,
    sell_appraise_pawnshop = 34999,
    sell_collectibles      = true,
    sell_gold_rings        = false,
    sell_locksmith         = false,
    sell_locksmith_pool    = true,
    always_check_pool      = false,
    sell_share_silvers     = false,
    sell_fwi               = false,
    sell_shroud            = false,
    sell_aspect            = false,
    sell_keep_silver       = 0,

    -- Locksmith pool
    locksmith_withdraw_amount       = 10000,
    display_box_contents            = true,
    use_standard_tipping            = true,
    sell_locksmith_pool_tip         = 15,
    sell_locksmith_pool_tip_percent = true,

    -- Skinning
    skin_enable       = false,
    skin_kneel        = false,
    skin_604          = false,
    skin_resolve      = false,
    skin_sheath       = "",
    skin_weapon       = "",
    skin_sheath_blunt = "",
    skin_weapon_blunt = "",

    -- Display / debug
    silence    = false,
    debug      = false,
    debug_file = "",

    -- Containers / coin hand
    coin_hand_name       = "",
    charm_name           = "",
    overflow_container   = "",
    secondary_overflow   = "",
    appraisal_container  = "",

    -- Hoarding
    gem_horde               = false,
    alchemy_horde           = false,
    gem_locker              = "",
    alchemy_locker          = "",
    hoard_exclusion         = {},
    gem_horde_containers    = {},
    alchemy_horde_containers = {},
    gem_horde_inv           = {},
    alchemy_horde_inv       = {},

    -- CHE / house locker
    use_house_locker  = false,
    che_locker_room   = "",
    che_entry         = "",
    che_exit          = "",

    -- Blood band
    use_bloodbands    = false,
    blood_band_name   = "",

    -- Keep closed
    keep_closed       = false,

    -- Misc
    between_scripts   = {},

    -- Sigil determination
    sigil_determination_on_fail = false,
}

-- ---------------------------------------------------------------------------
-- Type coercion — convert CLI input to proper Lua type (lines 1724-1748)
-- ---------------------------------------------------------------------------

--- Coerce a raw CLI input value to match the type of the default value.
-- @param name string setting name (for error messages)
-- @param default any the current/default value whose type drives coercion
-- @param input table list of string tokens from user input
-- @return any the coerced value
function M.coerce_setting_value(name, default, input)
    local dt = type(default)

    if dt == "boolean" then
        local fix = {
            on = true, ["true"] = true, yes = true,
            off = false, ["false"] = false, no = false,
        }
        local raw = input[1] and input[1]:lower() or ""
        if fix[raw] ~= nil then
            return fix[raw]
        end
        error(string.format(
            'Expected a boolean (true/false/yes/no) value for "%s" but got "%s"', name, raw))

    elseif dt == "table" then
        -- Array settings: return the input tokens as-is
        return input

    elseif dt == "number" then
        local raw = input[1] or ""
        local n = tonumber(raw)
        if n and math.floor(n) == n then
            return math.floor(n)
        end
        error(string.format(
            'Expected an integer value for %s but got "%s"', name, raw))

    elseif dt == "string" then
        return table.concat(input, " ")

    else
        error(string.format(
            "Recognized %s but don't know how to normalize a %s type setting", name, dt))
    end
end

-- ---------------------------------------------------------------------------
-- Setting name normalization (line 1842-1844)
-- ---------------------------------------------------------------------------

--- Normalize a setting key: lowercase, dashes to underscores.
-- @param input string raw setting name
-- @return string normalized key
function M.normalize_setting_name(input)
    return input:lower():gsub("%-", "_")
end

-- ---------------------------------------------------------------------------
-- Deep-copy helper
-- ---------------------------------------------------------------------------

local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deep_copy(v)
    end
    return copy
end

-- ---------------------------------------------------------------------------
-- load_defaults — return a fresh copy of DEFAULTS and persist to disk
-- (lines 1760-1820)
-- ---------------------------------------------------------------------------

--- Return a fresh copy of all default settings, writing them to the
-- character's profile file so future loads pick them up.
-- @return table fresh settings table
function M.load_defaults()
    local defaults = deep_copy(M.DEFAULTS)

    -- Ensure per-game/per-character directory exists
    local dir = string.format("data/eloot/%s/%s", GameState.game or "GS", GameState.name or "Unknown")
    File.mkdir(dir)

    -- Persist defaults
    File.write(dir .. "/eloot.json", Json.encode(defaults))

    return defaults
end

-- ---------------------------------------------------------------------------
-- load — load from CharSettings JSON, merge with defaults (lines 1756-1758)
-- ---------------------------------------------------------------------------

--- Load settings from CharSettings, filling in any missing keys from defaults.
-- @return table merged settings
function M.load()
    local raw = CharSettings.eloot
    if not raw or type(raw) ~= "table" then
        return M.load_defaults()
    end

    -- Decode if stored as JSON string
    if type(raw) == "string" then
        raw = Json.decode(raw) or {}
    end

    -- Merge: use saved value if present, else default
    local defaults = deep_copy(M.DEFAULTS)
    for k, v in pairs(raw) do
        defaults[k] = v
    end

    return defaults
end

-- ---------------------------------------------------------------------------
-- save — persist settings to CharSettings JSON (lines 1867-1871)
-- ---------------------------------------------------------------------------

--- Save the current settings table to CharSettings.
-- @param data table the ELoot data state (data.settings is written)
-- @param silent boolean if true, suppress confirmation message
function M.save(data, silent)
    CharSettings.eloot = data.settings
    if not silent then
        local Util = require("gs.eloot.util")
        Util.msg({ type = "info", text = " Settings saved." }, data)
    end
end

-- ---------------------------------------------------------------------------
-- load_profile — load named profile from file (lines 1822-1840)
-- ---------------------------------------------------------------------------

--- Load a named character profile from the data directory.
-- @param name string character name (defaults to current character)
-- @return table settings hash
function M.load_profile(name)
    name = name or GameState.name

    if not name then
        local Util = require("gs.eloot.util")
        Util.msg({ type = "error", text = " load_profile: name not defined" })
        return nil
    end

    local filename = string.format("data/eloot/%s/%s/eloot.json", GameState.game or "GS", name)

    if File.exists(filename) and name == GameState.name then
        local raw = File.read(filename)
        local settings = Json.decode(raw)
        return settings
    elseif not File.exists(filename) and name ~= GameState.name then
        local Util = require("gs.eloot.util")
        Util.msg({ type = "error", text = " load_profile: Attempt to load a profile that does not exist." })
        return nil
    elseif not File.exists(filename) and name == GameState.name then
        local Util = require("gs.eloot.util")
        Util.msg({ type = "info", text = " No current settings found. Loading defaults..." })
        return M.load_defaults()
    else
        local Util = require("gs.eloot.util")
        Util.msg({ type = "error", text = " load_profile: There was an unknown error with loading a profile" })
        return nil
    end
end

-- ---------------------------------------------------------------------------
-- save_profile — save profile to file (lines 1867-1871)
-- ---------------------------------------------------------------------------

--- Save settings to the character's profile file on disk.
-- @param data table the ELoot data state
-- @param silent boolean if true, suppress confirmation message
function M.save_profile(data, silent)
    local dir = string.format("data/eloot/%s/%s", GameState.game or "GS", GameState.name or "Unknown")
    File.mkdir(dir)

    local filename = dir .. "/eloot.json"
    File.write(filename, Json.encode(data.settings))

    if not silent then
        local Util = require("gs.eloot.util")
        Util.msg({ type = "info", text = " Settings saved to file: " .. filename .. "." }, data)
    end
end

-- ---------------------------------------------------------------------------
-- save_hoard_profile — save hoard data separately (lines 1846-1865)
-- ---------------------------------------------------------------------------

--- Mark hoard inventory for save-on-exit and register the before_dying hook.
-- @param data table the ELoot data state
function M.save_hoard_profile(data)
    data.inv_save = true

    if data.hoard_type == "gem" then
        data.gem_inventory = data.inventory
    elseif data.hoard_type == "alchemy" then
        data.alchemy_inventory = data.inventory
    end

    before_dying(function()
        if data.inv_save then
            local Util = require("gs.eloot.util")
            Util.msg({ type = "default", text = " Saving profile to sync gem/reagent inventories." }, data)
            data.settings.gem_horde_inv = data.gem_inventory
            data.settings.alchemy_horde_inv = data.alchemy_inventory
            M.save_profile(data, false)
            data.inv_save = false
        end
    end)
end

-- ---------------------------------------------------------------------------
-- update_setting — CLI setting update handler (lines 1873-1890)
-- ---------------------------------------------------------------------------

--- Update a single setting from CLI input tokens.
-- @param input table list of string tokens; first is setting name, rest is value
-- @param data table the ELoot data state
function M.update_setting(input, data)
    local Util = require("gs.eloot.util")

    local setting_name = M.normalize_setting_name(input[1])
    Util.msg({ type = "debug", text = "Normalized " .. input[1] .. " as " .. setting_name }, data)

    if data.settings[setting_name] ~= nil then
        local default_value = data.settings[setting_name]
        Util.msg({ type = "debug", text = "recognized " .. setting_name .. " as valid " .. type(default_value) .. " setting" }, data)

        -- Build value tokens (everything after the setting name)
        local value_tokens = {}
        for i = 2, #input do
            table.insert(value_tokens, input[i])
        end

        local ok, new_value = pcall(M.coerce_setting_value, setting_name, default_value, value_tokens)
        if not ok then
            Util.msg({ type = "error", text = new_value }, data)
            return
        end

        Util.msg({ type = "debug", text = "Normalized value as " .. tostring(new_value) }, data)

        data.settings[setting_name] = new_value
        Util.msg({ type = "info", text = " Updated " .. setting_name .. " to " .. tostring(new_value) }, data)
        M.save_profile(data)
    else
        Util.msg({ type = "error", text = " " .. setting_name .. " is not a recognized setting. Recognized setting names:" }, data)

        local keys = {}
        for k in pairs(data.settings) do
            table.insert(keys, k)
        end
        table.sort(keys)
        Util.msg({ type = "error", text = table.concat(keys, "\n") }, data)
    end
end

-- ---------------------------------------------------------------------------
-- validate_setup — validate required settings exist (lines 2106-2137)
-- ---------------------------------------------------------------------------

--- Validate that all configured items were found in inventory.
-- Exits the script if critical items are missing.
-- @param data table the ELoot data state
function M.validate_setup(data)
    local Util = require("gs.eloot.util")
    local need_exit = false

    local checks = {
        { key = "overflow_container",  found = StowList.stow_list.overflow_container,   label = "primary overflow container" },
        { key = "secondary_overflow",  found = StowList.stow_list.secondary_overflow,   label = "secondary overflow container" },
        { key = "appraisal_container", found = StowList.stow_list.appraisal_container,  label = "appraisal container" },
        { key = "skin_sheath",         found = ReadyList.ready_list.skin_sheath,         label = "bladed skinning sheath",  cond = "skin_enable" },
        { key = "skin_sheath_blunt",   found = ReadyList.ready_list.skin_sheath_blunt,   label = "blunt skinning sheath",   cond = "skin_enable" },
        { key = "skin_weapon",         found = ReadyList.ready_list.skin_weapon,         label = "bladed skinning weapon",  cond = "skin_enable" },
        { key = "skin_weapon_blunt",   found = ReadyList.ready_list.skin_weapon_blunt,   label = "blunt skinning weapon",   cond = "skin_enable" },
        { key = "coin_hand_name",      found = data.coin_hand,                           label = "coin storage" },
        { key = "charm_name",          found = data.charm,                               label = "fossil charm" },
    }

    for _, check in ipairs(checks) do
        local setting_val = data.settings[check.key]
        -- Skip if setting is empty/nil
        if not setting_val or tostring(setting_val) == "" then
            goto continue
        end
        -- Skip if conditional key exists and is false
        if check.cond and not data.settings[check.cond] then
            goto continue
        end

        if not check.found then
            Util.msg({ text = " Not able to find the " .. check.label .. ": " .. tostring(setting_val) }, data)
            need_exit = true
        end

        ::continue::
    end

    if need_exit then
        Util.msg({ text = " Something went wrong initializing eloot. Please check ;eloot setup. Exiting...", space = true }, data)
        error("eloot: setup validation failed")
    end
end

return M
