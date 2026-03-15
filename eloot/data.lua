local M = {}

M.categories = {
    gem      = {"gem", "valuable"},
    box      = {"box"},
    skin     = {"skin"},
    scroll   = {"scroll"},
    wand     = {"wand"},
    herb     = {"herb"},
    reagent  = {"reagent", "alchemy"},
    uncommon = {"uncommon"},
    magic    = {"magic"},
    food     = {"food"},
    clothing = {"clothing"},
    jewelry  = {"jewelry"},
    ammo     = {"ammo"},
    plinite  = {"plinite"},
    bounty   = {"bounty"},
    bloodscrip = {"bloodscrip"},
    seashell = {"seashell"},
    collectible = {"collectible"},
}

function M.item_category(item)
    for cat, types in pairs(M.categories) do
        for _, t in ipairs(types) do
            if item:type_p(t) then return cat end
        end
    end
    return nil
end

function M.should_loot(item, state)
    -- Check exclusion list
    local name_lower = item.name:lower()
    for _, excl in ipairs(state.loot_exclude or {}) do
        if name_lower:find(excl:lower(), 1, true) then return false end
    end
    -- Check keep list (overrides everything)
    for _, keep in ipairs(state.loot_keep or {}) do
        if name_lower:find(keep:lower(), 1, true) then return true end
    end
    -- Check if category is in loot_types
    local cat = M.item_category(item)
    if not cat then return false end
    for _, lt in ipairs(state.loot_types or {}) do
        if lt == cat then return true end
    end
    return false
end

return M
