local herbs_db = require("lib/herbs")
local settings = require("settings")
local actions = require("actions")

local M = {}

-- Default minimum stock doses per herb type (matches original eherbs.lic)
local DEFAULT_MIN_STOCK = {
    ["major head scar"]   = 6,
    ["minor head wound"]  = 4,
    ["major nerve wound"] = 4,
    ["minor organ scar"]  = 4,
    ["major organ scar"]  = 6,
    ["missing eye"]       = 7,
    ["blood"]             = 50,
    ["major head wound"]  = 25,
    ["minor head scar"]   = 25,
    ["major organ wound"] = 25,
    ["minor organ wound"] = 25,
    ["major limb wound"]  = 25,
    ["minor limb wound"]  = 25,
    ["major limb scar"]   = 25,
    ["minor limb scar"]   = 25,
    ["severed limb"]      = 25,
    ["minor nerve wound"] = 25,
    ["major nerve scar"]  = 25,
    ["minor nerve scar"]  = 25,
}

--- Herb type lists used for stock subcommands
local HERB_TYPE_LIST = {
    "blood", "major head wound", "minor head scar", "major organ wound", "minor organ wound",
    "major limb wound", "minor limb wound", "major limb scar", "minor limb scar", "severed limb",
    "minor nerve wound", "major nerve scar", "minor nerve scar",
}
local POTION_TYPE_LIST = {
    "major head scar", "minor head wound", "major nerve wound",
    "minor organ scar", "major organ scar", "missing eye",
}

--- Get min stock doses, adjusted by stock_percent if set
function M.get_min_stock_doses(state)
    local doses = {}
    for k, v in pairs(DEFAULT_MIN_STOCK) do
        doses[k] = v
    end

    local pct = tonumber(state.stock_percent) or 0
    if pct > 0 then
        pct = math.min(pct, 100)
        for k, v in pairs(doses) do
            doses[k] = math.floor(v * (pct / 100))
        end
    end

    return doses
end

--- Check current silver on hand
function M.check_silver()
    fput("wealth quiet")
    local line = waitfor("You have")
    local silver = 0
    if line then
        local num = line:match("(%d[%d,]*) silver")
        if num then silver = tonumber(num:gsub(",", "")) or 0 end
        if line:find("but one silver") then silver = 1 end
    end
    return silver
end

--- Read N lines of game response and return true if pattern found, false if fail_pattern found
local function read_response(success_pat, fail_pat, max_lines)
    for i = 1, max_lines or 10 do
        local line = get()
        if not line then break end
        if fail_pat and line:find(fail_pat) then return false, line end
        if success_pat and line:find(success_pat) then return true, line end
        if line:find("<prompt") then break end
    end
    return nil
end

--- Withdraw silver from bank
function M.withdraw(amount, state)
    local original_room = Map.current_room()
    actions.check_cutthroat(state)

    -- Unhide/un-invisible before navigating (go2 may not do this automatically)
    if GameState.hidden then fput("unhide") end

    Script.run("go2", "bank")

    if GameState.room_name and GameState.room_name:find("Pinefar, Depository") then
        -- Check if banker NPC is present
        local banker_found = false
        for _, npc in ipairs(GameObj.npcs()) do
            if npc.noun == "banker" then banker_found = true; break end
        end

        if banker_found then
            fput("ask banker for " .. math.max(amount or state.withdraw_amount, 20) .. " silvers")
            -- Pinefar banker says "suspicious" if no funds
            local ok = read_response("Alright|here ye go", "suspicious", 10)
            if ok == false then
                respond("[eherbs] No coins in Pinefar bank. Returning to start.")
                if original_room then Script.run("go2", tostring(original_room)) end
                return false
            end
        else
            -- Banker absent at Pinefar — find nearest Icemule bank and try there
            respond("[eherbs] Pinefar banker absent, trying Icemule bank...")
            local icemule_bank = Map.find_nearest_by_tag and Map.find_nearest_by_tag("bank")
            if icemule_bank then
                Script.run("go2", tostring(icemule_bank))
                fput("withdraw " .. (amount or state.withdraw_amount) .. " silvers")
                local ok, line = read_response("withdrawn|You withdraw", "suspicious|chuckles at you|debt collector", 10)
                if ok == false then
                    if line and line:find("debt collector") then
                        fput("withdraw " .. (amount or state.withdraw_amount) .. " silvers")
                    else
                        respond("[eherbs] No coins in bank. Returning to start.")
                        if original_room then Script.run("go2", tostring(original_room)) end
                        return false
                    end
                end
            else
                fput("ask banker for " .. math.max(amount or state.withdraw_amount, 20) .. " silvers")
            end
        end
    else
        -- Regular bank
        fput("withdraw " .. (amount or state.withdraw_amount) .. " silvers")
        local ok, line = read_response("withdrawn|You withdraw", "suspicious|chuckles at you|debt collector", 10)
        if ok == false then
            if line and line:find("debt collector") then
                -- Debt collector intercept — re-send the original command
                fput("withdraw " .. (amount or state.withdraw_amount) .. " silvers")
            else
                respond("[eherbs] No coins in bank. Returning to start.")
                if original_room then Script.run("go2", tostring(original_room)) end
                return false
            end
        end
    end

    if original_room then
        Script.run("go2", tostring(original_room))
    end
    return true
end

--- Withdraw a bank note for large purchases
function M.withdraw_note(amount, state)
    local original_room = Map.current_room()
    actions.check_cutthroat(state)
    Script.run("go2", "bank")

    -- Can't get a note from Pinefar
    if GameState.room_name and GameState.room_name:find("Pinefar, Depository") then
        local silver = M.check_silver()
        if silver < (state.withdraw_amount or 8000) then
            M.withdraw(state.withdraw_amount, state)
        end
        if original_room then Script.run("go2", tostring(original_room)) end
        return nil
    end

    -- Stow hands first
    local stowed = actions.stow_hands()

    fput("withdraw " .. math.floor(amount) .. " note")
    pause(2)  -- Wait for note to appear

    -- Find the note in hand
    local note = nil
    for i = 1, 20 do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        for _, hand in ipairs({rh, lh}) do
            if hand and hand.noun and hand.noun:find("^note$") or
               (hand and hand.noun and (hand.noun == "scrip" or hand.noun == "chit")) then
                note = hand
                break
            end
        end
        if note then break end
        pause(0.1)
    end

    actions.restore_hands(stowed)

    if original_room then
        Script.run("go2", tostring(original_room))
    end

    return note
end

--- Deposit all silver
function M.deposit(state)
    local silver = M.check_silver()
    if silver <= 0 then return end

    Script.run("go2", "bank")

    if GameState.room_name and GameState.room_name:find("Pinefar, Depository") then
        -- Wait for banker
        wait_until(function()
            for _, npc in ipairs(GameObj.npcs()) do
                if npc.noun == "banker" then return true end
            end
            return false
        end)
        fput("give banker " .. silver .. " silvers")
    else
        fput("deposit " .. silver)
    end
end

--- Deposit a bank note
function M.deposit_note(note, state)
    if not note then return end
    local original_room = Map.current_room()
    actions.check_cutthroat(state)
    Script.run("go2", "bank")

    if GameState.room_name and GameState.room_name:find("Pinefar, Depository") then
        M.deposit(state)
        return
    end

    fput("get #" .. note.id)
    fput("deposit " .. note.noun)

    if original_room then
        Script.run("go2", tostring(original_room))
    end
end

--- Read the herbalist order menu, returns { [herb_name] = { order_num = N, price = N } }
function M.read_menu()
    actions.check_cutthroat({})
    fput("order")
    local menu = {}

    for i = 1, 30 do
        local line = get()
        if not line then break end
        -- Parse dialog-style menu: <d cmd="order N">herb name</d>
        for order_num, name in line:gmatch('cmd=["\']order (%d+).->(.-)</d>') do
            -- Strip leading article
            name = name:gsub("^an? ", "")
            menu[name] = tonumber(order_num)
        end
        -- Also try plaintext format: "  1. some acantha leaf    10 doses    50 silvers"
        local num, name = line:match("^%s*(%d+)%.%s+(.-)%s+%d+ doses?")
        if num and name then
            menu[name:match("^%s*(.-)%s*$")] = tonumber(num)
        end
        if line:find("output class") or line:find("closeDialog") or line:find("Roundtime") then break end
    end

    return menu
end

--- Check prices at the current herbalist (cached per herbalist room)
function M.check_prices(state)
    state.prices = state.prices or {}
    local room_id = tostring(Map.current_room() or "unknown")

    -- Check if we already have valid cached prices for this room
    if state.prices[room_id] then
        local first_val = nil
        for _, v in pairs(state.prices[room_id]) do
            first_val = v
            break
        end
        if first_val and type(first_val) == "table" and first_val.cost then
            return state.prices[room_id]
        end
    end

    -- Need to check prices
    Script.run("go2", "herbalist")
    room_id = tostring(Map.current_room() or "unknown")
    respond("[eherbs] Checking prices at this location (one-time)")

    local menu = M.read_menu()
    state.prices[room_id] = {}

    local current_location = M.get_current_location()

    for menu_name, order_num in pairs(menu) do
        -- Match menu item to known herb
        for _, herb in ipairs(herbs_db.database) do
            if (herb.name:find(menu_name, 1, true) or herb.short:find(menu_name, 1, true) or
                menu_name:find(herb.short, 1, true))
               and not M._is_do_not_buy(herb) then

                -- Order the item to get its price
                fput("order " .. order_num)
                local price = nil
                for i = 1, 10 do
                    local line = get()
                    if not line then break end
                    local silver_str = line:match("(%d[%d,]*) silvers?")
                    if silver_str then
                        price = tonumber(silver_str:gsub(",", ""))
                        break
                    end
                    if line:find("Roundtime") or line:find("^$") then break end
                end

                if price and herb.type then
                    state.prices[room_id][herb.type] = {
                        cost = price,
                        name = herb.name,
                        short_name = herb.short,
                    }
                end
                break
            end
        end
    end

    settings.save(state)
    return state.prices[room_id]
end

--- Check if an herb entry is marked Do Not Buy
function M._is_do_not_buy(herb)
    if herb.location then
        for _, loc in ipairs(herb.location) do
            if loc == "Do Not Buy" then return true end
        end
    end
    return false
end

--- Get current map location name
function M.get_current_location()
    local room = Room.current and Room.current()
    if room and room.location then return room.location end
    -- Fallback: try to find town tag
    local nearest = Room.find_nearest_by_tag and Room.find_nearest_by_tag("town")
    if nearest then
        local town_room = Map.find_room(nearest.id)
        if town_room and town_room.location then return town_room.location end
    end
    return nil
end

--- Buy a specific herb type at the herbalist
function M.buy_herb(herb_type, amount, state)
    local menu = M.read_menu()
    local current_location = M.get_current_location()

    -- Find the herb to buy, preferring location-appropriate ones
    local herb = herbs_db.find_by_type(herb_type, {
        location = current_location,
        prefer_drinkable = state.use_potions,
        prefer_edible = not state.use_potions,
    })
    if not herb then
        respond("[eherbs] No herb known for type: " .. herb_type)
        return nil
    end

    -- Find in menu
    local order_num = nil
    for menu_name, num in pairs(menu) do
        if menu_name:lower():find(herb.short:lower(), 1, true)
           or herb.short:lower():find(menu_name:lower(), 1, true) then
            order_num = num
            break
        end
    end

    if not order_num then
        respond("[eherbs] Herb '" .. herb.short .. "' not found at this herbalist")
        return nil
    end

    -- Check silver
    local silver = M.check_silver()
    if silver < 4000 then
        M.withdraw(state.withdraw_amount or 8000, state)
        Script.run("go2", "herbalist")
    end

    -- Order the herb
    fput("order " .. amount .. " " .. order_num)
    local buy_result = fput("buy")

    -- Track the purchased doses
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local purchased_item = nil
    for _, hand in ipairs({rh, lh}) do
        if hand and hand.noun then
            for _, h in ipairs(herbs_db.database) do
                if hand.name:lower():find(h.short:lower(), 1, true) then
                    purchased_item = hand
                    if actions.dose_tracker then
                        actions.dose_tracker[hand.id] = h.doses
                    end
                    break
                end
            end
        end
        if purchased_item then break end
    end

    return purchased_item
end

--- Store a purchased herb (or package) into the container.
--- Returns true on success, false if container is full (caller should stop).
function M.store_herb(item, state)
    if not item then return true end
    local container = state.herb_container or "herbsack"

    -- Handle packages: open, empty contents into container, throw away
    if item.name and item.name:lower():find("package") then
        fput("open #" .. item.id)
        for i = 1, 5 do
            local line = get()
            if not line then break end
            if line:find("You open") or line:find("already open") then break end
            if line:find("<prompt") then break end
        end
        fput("empty #" .. item.id .. " in my " .. container)
        waitrt()
        fput("throw #" .. item.id)
        for i = 1, 5 do
            local line = get()
            if not line then break end
            if line:find("You throw away") or line:find("<prompt") then break end
        end
        return true
    end

    fput("put #" .. item.id .. " in my " .. container)

    -- Check for container-full response
    for i = 1, 10 do
        local line = get()
        if not line then break end
        if line:match("^Your .+ won't fit in .+%.$") then
            respond("[eherbs] Container full. Stowing and stopping.")
            local rh = GameObj.right_hand()
            if rh and rh.id then fput("stow right") end
            local lh = GameObj.left_hand()
            if lh and lh.id then fput("stow left") end
            if state.use_distiller then
                local sk = require("survival_kit")
                if sk.detected and sk.has_distiller then
                    sk.distill()
                end
            end
            return false
        end
        if line:find("You put") or line:find("You add") or
           line:find("You find a suitable") or line:find("already fully stocked") then
            break
        end
        if line:find("<prompt") then break end
    end

    return true
end

--- Fill: buy one of each missing herb type
function M.fill_missing(state)
    respond("[eherbs] Checking for missing herb types...")
    local container = state.herb_container or "herbsack"

    -- Open container and check contents
    actions.open_container(container)

    local inv = GameObj.inv()
    local herb_types_present = {}
    for _, item in ipairs(inv) do
        if item.noun then
            for _, herb in ipairs(herbs_db.database) do
                if item.name:lower():find(herb.short:lower(), 1, true) then
                    herb_types_present[herb.type] = true
                end
            end
        end
    end

    local types_to_buy = {
        "blood", "major head wound", "minor head wound", "major head scar", "minor head scar",
        "major organ wound", "minor organ wound", "major organ scar", "minor organ scar",
        "missing eye", "major limb wound", "minor limb wound", "major limb scar", "minor limb scar",
        "severed limb", "major nerve wound", "minor nerve wound", "major nerve scar", "minor nerve scar",
    }

    local missing = {}
    for _, t in ipairs(types_to_buy) do
        if not herb_types_present[t] then
            missing[#missing + 1] = t
        end
    end

    if #missing == 0 then
        respond("[eherbs] All herb types present")
        return
    end

    respond("[eherbs] Missing " .. #missing .. " herb types, buying...")

    local start_room = Map.current_room()

    -- Get silver and go to herbalist
    local silver = M.check_silver()
    if silver < 4000 then
        M.withdraw(state.withdraw_amount or 8000, state)
    end
    Script.run("go2", "herbalist")

    local stowed = actions.stow_hands()

    for _, herb_type in ipairs(missing) do
        local item = M.buy_herb(herb_type, 1, state)
        M.store_herb(item, state)
    end

    actions.restore_hands(stowed)

    -- Return and deposit
    if start_room then Script.run("go2", tostring(start_room)) end
    if state.deposit_coins then M.deposit(state) end

    respond("[eherbs] Fill complete")
end

--- Stock: buy herbs up to min stock levels
function M.stock(state, filter)
    local container = state.herb_container or "herbsack"
    local min_doses = M.get_min_stock_doses(state)

    -- Determine which types to stock based on filter
    local seek_types
    if filter == "herbs" then
        seek_types = HERB_TYPE_LIST
    elseif filter == "potions" then
        seek_types = POTION_TYPE_LIST
    elseif filter == "combined" then
        -- Combine both lists
        seek_types = {}
        for _, t in ipairs(POTION_TYPE_LIST) do seek_types[#seek_types + 1] = t end
        for _, t in ipairs(HERB_TYPE_LIST) do
            local found = false
            for _, existing in ipairs(seek_types) do
                if existing == t then found = true; break end
            end
            if not found then seek_types[#seek_types + 1] = t end
        end
    elseif filter then
        -- Specific type like "major head wound"
        seek_types = { filter }
    else
        -- Default: stock both herbs and potions
        seek_types = {}
        for _, t in ipairs(POTION_TYPE_LIST) do seek_types[#seek_types + 1] = t end
        for _, t in ipairs(HERB_TYPE_LIST) do
            local found = false
            for _, existing in ipairs(seek_types) do
                if existing == t then found = true; break end
            end
            if not found then seek_types[#seek_types + 1] = t end
        end
    end

    respond("[eherbs] Stocking herbs...")
    local start_room = Map.current_room()

    -- Measure current stock
    actions.open_container(container)

    -- Build shopping list
    local shopping_list = {}
    local current_location = M.get_current_location()

    for _, herb_type in ipairs(seek_types) do
        local target = min_doses[herb_type] or 10
        local current = 0

        -- Count doses from dose tracker for herbs of this type
        local inv = GameObj.inv()
        for _, item in ipairs(inv) do
            if item.noun then
                for _, herb in ipairs(herbs_db.database) do
                    if herb.type == herb_type and item.name:lower():find(herb.short:lower(), 1, true) then
                        local id_str = tostring(item.id)
                        if actions.dose_tracker[id_str] then
                            current = current + actions.dose_tracker[id_str]
                        else
                            -- If no tracked count, measure the herb
                            fput("get #" .. item.id .. " from my " .. container)
                            fput("measure #" .. item.id)
                            pause(0.5)
                            fput("put #" .. item.id .. " in my " .. container)
                            if actions.dose_tracker[id_str] then
                                current = current + actions.dose_tracker[id_str]
                            end
                        end
                    end
                end
            end
        end

        if current < target then
            -- Check if herb is available at current location
            local herb_info = herbs_db.find_by_type(herb_type, { location = current_location })
            if herb_info and not M._is_do_not_buy(herb_info) then
                local needed = math.ceil((target - current) / (herb_info.doses or 1))
                if needed >= 1 then
                    shopping_list[#shopping_list + 1] = {
                        category = herb_type,
                        herb_name = herb_info.short,
                        needed = needed,
                        doses_per = herb_info.doses or 1,
                    }
                end
            end
        end
    end

    if #shopping_list == 0 then
        respond("[eherbs] Already fully stocked!")
        return
    end

    -- Print shopping list
    respond("[eherbs] Shopping list:")
    for _, item in ipairs(shopping_list) do
        respond(string.format("  %-25s  %s  x%d", item.category, item.herb_name, item.needed))
    end
    pause(1)

    -- Calculate total cost and get a note
    local total_cost = 0
    local prices = M.check_prices(state)
    if prices then
        for _, item in ipairs(shopping_list) do
            local price_info = prices[item.category]
            if price_info and price_info.cost then
                total_cost = total_cost + (price_info.cost * item.needed)
            end
        end
    end
    total_cost = math.floor(total_cost * 1.1)  -- 10% buffer

    -- Withdraw note or silver
    local note = nil
    if total_cost > 5000 then
        note = M.withdraw_note(total_cost, state)
    else
        local silver = M.check_silver()
        if silver < total_cost then
            M.withdraw(state.withdraw_amount or 8000, state)
        end
    end

    -- Go to herbalist and buy
    Script.run("go2", "herbalist")
    local stowed = actions.stow_hands()

    local container_full = false
    for _, item in ipairs(shopping_list) do
        if container_full then break end
        -- Buy in batches
        local remaining = item.needed
        while remaining > 0 do
            local batch = math.min(10, remaining)
            local purchased = M.buy_herb(item.category, batch, state)
            local ok = M.store_herb(purchased, state)
            if not ok then
                container_full = true
                break
            end
            remaining = remaining - batch
        end
    end

    -- Cleanup
    actions.restore_hands(stowed)

    -- Deposit note if used
    if note then
        M.deposit_note(note, state)
    elseif state.deposit_coins then
        M.deposit(state)
    end

    -- Return to start
    if start_room then Script.run("go2", tostring(start_room)) end

    respond("[eherbs] Stocking complete")
end

return M
