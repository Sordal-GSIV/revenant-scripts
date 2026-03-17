local data = require("data")
local inventory = require("inventory")

local M = {}

function M.skin(state)
    if not state.skin_enable then return end

    local dead = GameObj.dead()
    if not dead or #dead == 0 then return end

    -- Filter by exclusions
    local to_skin = {}
    for _, creature in ipairs(dead) do
        local dominated = false
        local name_lower = (creature.name or ""):lower()
        for _, excl in ipairs(state.skin_exclude or {}) do
            if name_lower:find(excl:lower(), 1, true) then dominated = true; break end
        end
        for _, excl in ipairs(state.critter_exclude or {}) do
            if name_lower:find(excl:lower(), 1, true) then dominated = true; break end
        end
        if not dominated then
            to_skin[#to_skin + 1] = creature
        end
    end

    if #to_skin == 0 then return end

    -- Get weapon
    local stowed = inventory.stow_hands()
    if state.skin_weapon and state.skin_weapon ~= "" then
        fput("get my " .. state.skin_weapon .. " from my " .. (state.skin_sheath or ""))
    end

    -- Kneel if needed
    if state.skin_kneel then fput("kneel") end

    -- Skin each
    for _, creature in ipairs(to_skin) do
        waitrt()
        fput("skin #" .. creature.id)
    end

    -- Stow weapon
    if state.skin_weapon and state.skin_weapon ~= "" then
        if state.skin_sheath and state.skin_sheath ~= "" then
            fput("put my " .. state.skin_weapon .. " in my " .. state.skin_sheath)
        else
            fput("stow my " .. state.skin_weapon)
        end
    end

    -- Stand if kneeling
    if state.skin_kneel then fput("stand") end

    inventory.restore_hands(stowed)
end

function M.search(state)
    local dead = GameObj.dead()
    if not dead or #dead == 0 then return end

    for _, creature in ipairs(dead) do
        -- Skip excluded critters
        local skip = false
        local name_lower = (creature.name or ""):lower()
        for _, excl in ipairs(state.critter_exclude or {}) do
            if name_lower:find(excl:lower(), 1, true) then skip = true; break end
        end
        if not skip then
            waitrt()
            fput("loot #" .. creature.id)
        end
    end
end

function M.room(state)
    local loot = GameObj.loot()
    if not loot or #loot == 0 then return 0 end

    local looted = 0
    for _, item in ipairs(loot) do
        if data.should_loot(item, state) then
            waitrt()
            fput("get #" .. item.id)
            local container = inventory.route_container(item, state)
            inventory.stow_item(item, container)
            looted = looted + 1
        end
    end
    return looted
end

function M.loot_cycle(state)
    M.skin(state)
    M.search(state)
    local count = M.room(state)
    return count
end

return M
