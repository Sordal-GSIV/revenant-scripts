-- Settings persistence for playerwindow via CharSettings + JSON

local M = {}

local KEY = "playerwindow_settings"

local DEFAULTS = {
    single_column       = false,
    filter_animals      = false,
    filter_flares       = false,
    filter_combat_math  = false,
    filter_spam         = true,
    show_filter_buttons = true,
    show_movement       = true,
}

function M.load()
    local raw = CharSettings[KEY]
    if not raw then return M.defaults() end
    local ok, data = pcall(Json.decode, raw)
    if not ok or type(data) ~= "table" then return M.defaults() end
    local s = M.defaults()
    for k in pairs(DEFAULTS) do
        if data[k] ~= nil then s[k] = data[k] end
    end
    return s
end

function M.save(s)
    local data = {}
    for k in pairs(DEFAULTS) do data[k] = s[k] end
    CharSettings[KEY] = Json.encode(data)
end

function M.defaults()
    local t = {}
    for k, v in pairs(DEFAULTS) do t[k] = v end
    return t
end

return M
