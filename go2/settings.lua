local M = {}

local DEFAULTS = {
    typeahead = 0,
    delay = 0,
    hide_room_descriptions = false,
    hide_room_titles = false,
    echo_input = true,
    stop_for_dead = false,
    disable_confirm = false,
}

function M.load()
    local state = {}
    local raw = CharSettings.go2_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then state[k] = v end
    end
    return state
end

function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.go2_prefs = Json.encode(prefs)
end

function M.load_targets()
    local raw = Settings.go2_targets
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then return data end
    end
    return {}
end

function M.save_targets(targets)
    Settings.go2_targets = Json.encode(targets)
end

function M.save_start_room(room_id)
    CharSettings.go2_start_room = tostring(room_id)
end

function M.get_start_room()
    local raw = CharSettings.go2_start_room
    if raw then return tonumber(raw) end
    return nil
end

return M
