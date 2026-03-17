local M = {}

local DEFAULTS = {
    herb_container = "herbsack",
    buy_missing = false,
    deposit_coins = false,
    use_mending = false,
    skip_scars = false,
    blood_only = false,
    use_yaba = false,
    use_potions = false,
    use_650 = false,
    use_1035 = false,
    stock_percent = 0,
    use_distiller = false,
}

function M.load()
    local state = {}
    local raw = CharSettings.eherbs_prefs
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
    CharSettings.eherbs_prefs = Json.encode(prefs)
end

return M
