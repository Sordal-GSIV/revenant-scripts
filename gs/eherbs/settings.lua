local M = {}

local DEFAULTS = {
    herb_container = "herbsack",
    buy_missing = false,
    deposit_coins = false,
    use_mending = false,
    skip_scars = false,
    blood_only = false,
    blood_toggle = false,
    use_yaba = false,
    use_potions = false,
    use_650 = false,
    use_1035 = false,
    stock_percent = 0,
    use_distiller = false,
    debug = false,
    heal_cutthroat = true,
    use_npchealer = true,
    withdraw_amount = 8000,
    no_get = false,
    spellcast_only = false,
    ranged_only = false,
}

-- Keys that map from CLI short names to settings keys
M.var_names = {
    buy         = "buy_missing",
    ["buy-missing"] = "buy_missing",
    deposit     = "deposit_coins",
    mending     = "use_mending",
    skipscars   = "skip_scars",
    ["650"]     = "use_650",
    ["1035"]    = "use_1035",
    yaba        = "use_yaba",
    potions     = "use_potions",
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
    -- Cached per-herbalist prices: { [room_id] = { [herb_type] = { cost, name, short_name } } }
    local raw_prices = CharSettings.eherbs_prices
    if raw_prices then
        local ok, data = pcall(Json.decode, raw_prices)
        if ok and data then
            state.prices = data
        end
    end
    if not state.prices then state.prices = {} end

    return state
end

function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.eherbs_prefs = Json.encode(prefs)
    if state.prices then
        CharSettings.eherbs_prices = Json.encode(state.prices)
    end
end

return M
