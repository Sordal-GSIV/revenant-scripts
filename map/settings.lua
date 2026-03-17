local M = {}

local GLOBAL_DEFAULTS = {
    follow_mode = true,
    keep_centered = true,
    keep_above = true,
    theme = nil,  -- nil = default maps/, "dark" = maps-dark/, etc.
    global_scale = 1.0,
    global_scale_enabled = false,
    map_scales = {},
    expanded_canvas = true,
    dynamic_indicator_size = false,
}

local CHAR_DEFAULTS = {
    window_width = 400,
    window_height = 300,
    window_x = 0,
    window_y = 0,
}

function M.load()
    local state = {}

    local raw = Settings.map_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(GLOBAL_DEFAULTS) do
        if state[k] == nil then state[k] = v end
    end

    local char_raw = CharSettings.map_geometry
    if char_raw then
        local ok, data = pcall(Json.decode, char_raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(CHAR_DEFAULTS) do
        if state[k] == nil then state[k] = v end
    end

    return state
end

function M.save(state)
    local globals = {}
    for k, _ in pairs(GLOBAL_DEFAULTS) do
        globals[k] = state[k]
    end
    Settings.map_prefs = Json.encode(globals)

    local char = {}
    for k, _ in pairs(CHAR_DEFAULTS) do
        char[k] = state[k]
    end
    CharSettings.map_geometry = Json.encode(char)
end

function M.get_scale(state, map_key)
    if state.global_scale_enabled then
        return state.global_scale
    end
    if map_key and state.map_scales and state.map_scales[map_key] then
        return state.map_scales[map_key]
    end
    return state.global_scale
end

function M.set_scale(state, map_key, value)
    if state.global_scale_enabled then
        state.global_scale = value
    else
        if not state.map_scales then state.map_scales = {} end
        state.map_scales[map_key] = value
    end
end

return M
