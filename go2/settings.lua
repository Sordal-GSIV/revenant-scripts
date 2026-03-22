-- settings.lua — go2 persistent configuration
-- Per-character prefs stored in CharSettings.go2_prefs (JSON)
-- Per-game/cross-char vars stored in UserVars (mapdb_* keys, same names as go2.lic)
-- Cross-character targets stored in Settings.go2_targets (JSON)

local M = {}

-- Keys stored in CharSettings (per-character, per-game)
local CHAR_DEFAULTS = {
    typeahead            = 0,
    delay                = 0,
    hide_room_descriptions = false,
    hide_room_titles     = false,
    echo_input           = true,
    stop_for_dead        = false,
    disable_confirm      = false,
    vaalor_shortcut      = false,
    get_silvers          = false,
    get_return_silvers   = false,
    use_seeking          = false,
    use_gigas_hwtravel   = false,
    gigas_min_number     = 4,
    rogue_password       = "",
    element              = nil,   -- attuned element for Confluence
}

-- Keys stored in UserVars (per-game, cross-character) — same naming as go2.lic
local USERVARS_DEFAULTS = {
    mapdb_use_urchins       = false,
    mapdb_use_portmasters   = false,
    mapdb_use_portals       = false,   -- 'yes'/'no' string in lic; boolean here
    mapdb_use_old_portals   = false,
    mapdb_have_portal_pass  = false,
    mapdb_use_day_pass      = false,
    mapdb_buy_day_pass      = "",      -- "" | "on" | "wl,imt;..." etc.
    mapdb_day_pass_sack     = "",
    mapdb_fwi_trinket       = "",      -- "" means disabled
    mapdb_car_to_sos        = false,
    mapdb_car_from_sos      = false,
    mapdb_ice_mode          = "auto",  -- "auto" | "wait" | "run"
    mapdb_urchins_expire    = 0,
    mapdb_hinterwilds_location = nil,
}

-------------------------------------------------------------------------------
-- Internal helpers
-------------------------------------------------------------------------------

local function decode_or(raw, fallback)
    if not raw then return fallback end
    local ok, data = pcall(Json.decode, raw)
    if ok and type(data) == "table" then return data end
    return fallback
end

-------------------------------------------------------------------------------
-- CharSettings (per-character prefs)
-------------------------------------------------------------------------------

function M.load()
    local state = decode_or(CharSettings.go2_prefs, {})
    for k, v in pairs(CHAR_DEFAULTS) do
        if state[k] == nil then state[k] = v end
    end
    return state
end

function M.save(state)
    local prefs = {}
    for k in pairs(CHAR_DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.go2_prefs = Json.encode(prefs)
end

-------------------------------------------------------------------------------
-- UserVars (per-game settings)
-------------------------------------------------------------------------------

function M.load_uservars()
    local uv = {}
    for k, default in pairs(USERVARS_DEFAULTS) do
        local raw = UserVars[k]
        if raw == nil then
            uv[k] = default
        elseif type(default) == "boolean" then
            uv[k] = (raw == true or raw == "true" or raw == "yes" or raw == "on")
        elseif type(default) == "number" then
            uv[k] = tonumber(raw) or default
        else
            uv[k] = raw
        end
    end
    return uv
end

function M.save_uservars(uv)
    for k in pairs(USERVARS_DEFAULTS) do
        if uv[k] ~= nil then
            -- Portals stored as 'yes'/'no' in UserVars to match go2.lic convention
            if k == "mapdb_use_portals" or k == "mapdb_use_old_portals" or k == "mapdb_have_portal_pass" then
                UserVars[k] = uv[k] and "yes" or "no"
            else
                UserVars[k] = uv[k]
            end
        end
    end
end

function M.set_uvar(key, value)
    if USERVARS_DEFAULTS[key] == nil then return end
    UserVars[key] = value
end

function M.get_uvar(key)
    local default = USERVARS_DEFAULTS[key]
    local raw = UserVars[key]
    if raw == nil then return default end
    if type(default) == "boolean" then
        return (raw == true or raw == "true" or raw == "yes" or raw == "on")
    elseif type(default) == "number" then
        return tonumber(raw) or default
    end
    return raw
end

-------------------------------------------------------------------------------
-- Custom targets (cross-character, per-game)
-------------------------------------------------------------------------------

function M.load_targets()
    return decode_or(Settings.go2_targets, {})
end

function M.save_targets(targets)
    Settings.go2_targets = Json.encode(targets)
end

-------------------------------------------------------------------------------
-- Go-back start room (per-character)
-------------------------------------------------------------------------------

function M.save_start_room(room_id)
    CharSettings.go2_start_room = tostring(room_id)
end

function M.get_start_room()
    local raw = CharSettings.go2_start_room
    if raw then return tonumber(raw) end
    return nil
end

-------------------------------------------------------------------------------
-- Urchin expiry (per-game)
-------------------------------------------------------------------------------

function M.get_urchin_expire()
    return tonumber(UserVars.mapdb_urchins_expire) or 0
end

function M.set_urchin_expire(ts)
    UserVars.mapdb_urchins_expire = tostring(ts)
end

function M.urchins_active()
    local use = M.get_uvar("mapdb_use_urchins")
    if not use then return false end
    local expire = M.get_urchin_expire()
    if expire == 0 then return false end
    return os.time() < expire
end

-------------------------------------------------------------------------------
-- Defaults table (exported for GUI and other consumers)
-------------------------------------------------------------------------------

M.CHAR_DEFAULTS  = CHAR_DEFAULTS
M.USERVARS_DEFAULTS = USERVARS_DEFAULTS

return M
