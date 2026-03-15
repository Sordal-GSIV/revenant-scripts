local M = {}

local DEFAULTS = {
    -- Loot
    loot_types = {"gem", "box", "skin", "wand", "scroll", "bounty"},
    loot_exclude = {},
    loot_keep = {},
    critter_exclude = {},
    overflow_container = "",
    secondary_overflow = "",
    coin_hand_name = "",
    use_disk = false,
    loot_defensive = false,
    favor_left = false,
    -- Skin
    skin_enable = true,
    skin_weapon = "",
    skin_sheath = "",
    skin_weapon_blunt = "",
    skin_sheath_blunt = "",
    skin_kneel = false,
    skin_604 = false,
    skin_resolve = false,
    skin_exclude = {},
    -- Sell
    sell_loot_types = {"gem", "skin", "wand", "scroll"},
    sell_container = "",
    sell_exclude = {},
    sell_keep_scrolls = {},
    sell_appraise_gemshop = 0,
    sell_appraise_pawnshop = 0,
    appraisal_container = "",
    sell_deposit_coinhand = true,
    -- Boxes
    sell_locksmith_pool = false,
    sell_locksmith = false,
    locksmith_pool_tip = 0,
    locksmith_pool_tip_percent = true,
    -- Hoard
    gem_horde = false,
    alchemy_horde = false,
}

function M.load()
    local state = {}
    local raw = CharSettings.eloot_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then
            if type(v) == "table" then
                state[k] = {}
                for i, item in ipairs(v) do state[k][i] = item end
            else
                state[k] = v
            end
        end
    end
    return state
end

function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.eloot_prefs = Json.encode(prefs)
end

return M
