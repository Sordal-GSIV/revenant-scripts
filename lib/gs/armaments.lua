--- Weapon/armor/shield lookup scaffold.
--- Data tables to be populated later; provides the API surface now.

local M = {}

-- Armor group definitions
M.ARMOR_GROUPS = {
    [1] = "Cloth",
    [2] = "Leather",
    [3] = "Scale",
    [4] = "Chain",
    [5] = "Plate",
}

-- Armor subgroup definitions
M.ARMOR_SUBGROUPS = {
    [1]  = "Robes",
    [2]  = "Light Leather",
    [3]  = "Full Leather",
    [4]  = "Reinforced Leather",
    [5]  = "Double Leather",
    [6]  = "Leather Breastplate",
    [7]  = "Cuirbouilli Leather",
    [8]  = "Studded Leather",
    [9]  = "Brigandine Armor",
    [10] = "Chain Mail",
    [11] = "Double Chain",
    [12] = "Augmented Chain",
    [13] = "Chain Hauberk",
    [14] = "Metal Breastplate",
    [15] = "Augmented Plate",
    [16] = "Half Plate",
    [17] = "Full Plate",
    [18] = "Razern Armor",
    [19] = "Mithglin Armor",
    [20] = "Ora Armor",
}

-- Data stores (empty, populated later)
M.weapons = {}
M.armors = {}
M.shields = {}

--- Case-insensitive find across weapons, armors, and shields.
function M.find(name)
    if not name then return nil end
    local lower = name:lower()
    for _, store in ipairs({ M.weapons, M.armors, M.shields }) do
        for key, item in pairs(store) do
            if key:lower() == lower then
                return item
            end
        end
    end
    return nil
end

--- Return the type string for a named item.
function M.type_for(name)
    if not name then return nil end
    local lower = name:lower()
    for key, _ in pairs(M.weapons) do
        if key:lower() == lower then return "weapon" end
    end
    for key, _ in pairs(M.armors) do
        if key:lower() == lower then return "armor" end
    end
    for key, _ in pairs(M.shields) do
        if key:lower() == lower then return "shield" end
    end
    return nil
end

--- Return the category for a named item, or nil.
function M.category_for(name)
    local item = M.find(name)
    if item and item.data then
        return item.data.category
    end
    return nil
end

--- List names, optionally filtered by type ("weapon", "armor", "shield").
function M.names(filter_type)
    local result = {}
    local stores = {
        weapon = M.weapons,
        armor  = M.armors,
        shield = M.shields,
    }
    if filter_type then
        local store = stores[filter_type]
        if store then
            for key, _ in pairs(store) do
                result[#result + 1] = key
            end
        end
    else
        for _, store in pairs(stores) do
            for key, _ in pairs(store) do
                result[#result + 1] = key
            end
        end
    end
    table.sort(result)
    return result
end

return M
