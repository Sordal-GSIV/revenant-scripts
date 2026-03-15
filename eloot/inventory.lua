local data = require("data")

local M = {}

function M.route_container(item, state)
    local cat = data.item_category(item)
    -- Check type-specific container first
    if cat and state[cat .. "_container"] and state[cat .. "_container"] ~= "" then
        return state[cat .. "_container"]
    end
    -- Default container
    if state.sell_container and state.sell_container ~= "" then
        return state.sell_container
    end
    -- Overflow
    if state.overflow_container and state.overflow_container ~= "" then
        return state.overflow_container
    end
    return nil
end

function M.stow_item(item, container)
    if container then
        fput("put #" .. item.id .. " in my " .. container)
    else
        fput("stow #" .. item.id)
    end
end

function M.stow_hands()
    local stowed = { right = nil, left = nil }
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh then
        stowed.right = rh
        fput("stow right")
    end
    if lh then
        stowed.left = lh
        fput("stow left")
    end
    return stowed
end

function M.restore_hands(stowed)
    if stowed.left then fput("get #" .. stowed.left.id) end
    if stowed.right then fput("get #" .. stowed.right.id) end
end

function M.get_item(item_id)
    waitrt()
    fput("get #" .. item_id)
end

return M
