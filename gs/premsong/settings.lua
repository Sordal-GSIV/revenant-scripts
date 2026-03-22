local M = {}

local DEFAULTS = {
    tone       = "",
    lyrics     = {},
    reset_tone = true,
    delay      = 0.5,
}

function M.load()
    local state = {}
    local raw = CharSettings.premsong_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then
            state[k] = type(v) == "table" and {} or v
        end
    end
    return state
end

function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.premsong_prefs = Json.encode(prefs)
end

return M
