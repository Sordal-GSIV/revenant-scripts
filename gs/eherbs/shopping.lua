local herbs_db = require("lib/herbs")
local settings = require("settings")

local M = {}

-- Cached herbalist menu prices: { [room_id] = { [herb_short] = { order_num, price } } }
local price_cache = {}

function M.check_silver()
    fput("wealth")
    local line = waitfor("You have")
    local silver = 0
    if line then
        local num = line:match("(%d[%d,]*) silver")
        if num then silver = tonumber(num:gsub(",", "")) or 0 end
    end
    return silver
end

function M.withdraw(amount)
    Script.run("go2", "bank")
    fput("withdraw " .. amount .. " silvers")
end

function M.deposit()
    Script.run("go2", "bank")
    fput("deposit all")
end

function M.read_menu(room_id)
    if price_cache[room_id] then return price_cache[room_id] end
    local menu = {}
    fput("order")
    -- Parse order menu output
    -- Format: "  1. an acantha leaf          10 doses    50 silvers"
    while true do
        local line = get()
        if not line then break end
        local num, name, price = line:match("^%s*(%d+)%.%s+(.-)%s+%d+ doses?%s+(%d+) silvers?")
        if num then
            menu[#menu + 1] = {
                order_num = tonumber(num),
                name = name:match("^%s*(.-)%s*$"),
                price = tonumber(price),
            }
        end
        if line:find("You can also") or line:find("Roundtime") or line == "" then break end
    end
    price_cache[room_id] = menu
    return menu
end

function M.buy_herb(herb_type, amount, state)
    -- Navigate to herbalist
    Script.run("go2", "herbalist")
    pause(0.5)

    local room_id = Map.current_room()
    local menu = M.read_menu(room_id)

    -- Find matching herb in menu
    local herb = herbs_db.find_by_type(herb_type, {
        prefer_drinkable = state.use_potions,
        prefer_edible = not state.use_potions,
    })
    if not herb then
        respond("[eherbs] No herb known for type: " .. herb_type)
        return false
    end

    local menu_item = nil
    for _, item in ipairs(menu) do
        if item.name:lower():find(herb.short:lower(), 1, true) then
            menu_item = item
            break
        end
    end

    if not menu_item then
        respond("[eherbs] Herb '" .. herb.short .. "' not found at this herbalist")
        return false
    end

    -- Buy in batches of 10
    local bought = 0
    while bought < amount do
        local batch = math.min(10, amount - bought)
        local cost = menu_item.price * batch
        local silver = M.check_silver()
        if silver < cost then
            M.withdraw(cost - silver + 100)
        end
        fput("order " .. batch .. " " .. menu_item.order_num)
        fput("buy")
        bought = bought + batch
        respond("[eherbs] Bought " .. bought .. "/" .. amount .. " " .. herb.short)
    end

    -- Put herbs in container
    fput("put my " .. herb.short .. " in my " .. (state.herb_container or "herbsack"))

    return true
end

function M.fill_missing(state)
    respond("[eherbs] Checking for missing herb types...")
    local missing = {}
    -- Check which herb types we don't have
    for _, herb_type in ipairs(herbs_db.list_types()) do
        -- Simple check: try to find the herb in inventory
        -- A full implementation would scan container contents
        missing[#missing + 1] = herb_type
    end

    if #missing == 0 then
        respond("[eherbs] All herb types present")
        return
    end

    local start_room = Map.current_room()
    for _, herb_type in ipairs(missing) do
        M.buy_herb(herb_type, 1, state)
    end

    -- Return to start
    if start_room then
        Script.run("go2", tostring(start_room))
    end

    if state.deposit_coins then M.deposit() end
    respond("[eherbs] Fill complete")
end

function M.stock(state, filter)
    local min_doses = {
        blood = 50, poison = 10, disease = 10,
        ["major head wound"] = 10, ["minor head wound"] = 10,
        ["major head scar"] = 10, ["minor head scar"] = 10,
        ["major nerve wound"] = 10, ["minor nerve wound"] = 10,
        ["major nerve scar"] = 10, ["minor nerve scar"] = 10,
        ["major organ wound"] = 10, ["minor organ wound"] = 10,
        ["major organ scar"] = 10, ["minor organ scar"] = 10,
        ["major limb wound"] = 10, ["minor limb wound"] = 10,
        ["major limb scar"] = 10, ["minor limb scar"] = 10,
        ["severed limb"] = 4, ["missing eye"] = 4,
    }

    respond("[eherbs] Stocking herbs...")
    local start_room = Map.current_room()

    for herb_type, target in pairs(min_doses) do
        local should_buy = true
        if filter == "herbs" then
            local herb = herbs_db.find_by_type(herb_type)
            if herb and herb.drinkable then should_buy = false end
        elseif filter == "potions" then
            local herb = herbs_db.find_by_type(herb_type)
            if herb and not herb.drinkable then should_buy = false end
        end

        if should_buy then
            M.buy_herb(herb_type, target, state)
        end
    end

    if start_room then Script.run("go2", tostring(start_room)) end
    if state.deposit_coins then M.deposit() end
    respond("[eherbs] Stocking complete")
end

return M
