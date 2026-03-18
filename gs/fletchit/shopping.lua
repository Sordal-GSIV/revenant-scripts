--------------------------------------------------------------------------------
-- FletchIt - Shopping Module
--
-- Automated supply purchasing: check needed items, find order numbers at shop,
-- check silver, bank withdraw, navigate to shop, buy items, return, deposit.
--
-- Original author: elanthia-online (Dissonance)
-- Lua conversion preserves all original functionality.
--------------------------------------------------------------------------------

local M = {}

--- Check current silver on hand.
-- Uses Currency.silver (GS infomon cache) — avoids sending a game command.
-- @return number silver amount
function M.check_silver()
    return Currency.silver or 0
end

--- Get the contents of a container by name.
-- Opens the container if necessary.
-- @param container_name string
-- @param debug_log function
-- @return table array of GameObj items, or empty table
function M.get_container_contents(container_name, debug_log)
    debug_log("get_container_contents called with container_name: " .. tostring(container_name))
    if not container_name or container_name == "" then
        echo("ERROR: Blank container name")
        error("blank_container")
    end

    local container = nil
    local inv = GameObj.inv() or {}
    for _, obj in ipairs(inv) do
        if string.find(string.lower(obj.name or ""), string.lower(container_name), 1, true) then
            container = obj
            break
        end
    end

    -- Fallback: try matching with flexible spacing
    if not container then
        for _, obj in ipairs(inv) do
            local pattern = string.gsub(container_name, " ", ".*")
            if string.find(string.lower(obj.name or ""), string.lower(pattern)) then
                container = obj
                break
            end
        end
    end

    if not container then
        echo("ERROR: Failed to find container: " .. container_name)
        error("no_container")
    end

    if not container.contents then
        dothistimeout("open #" .. container.id, 10, "You open|already open")

        if not container.contents then
            dothistimeout("look in #" .. container.id, 10, "In the .* you see")

            if not container.contents then
                echo("WARNING: Failed to find contents of container: " .. container_name)
                pause(1)
            end
        end
    end

    return container.contents or {}
end

--- Check which supplies are needed based on container contents.
-- In learning mode, only wood is needed (no glue, fletchings, paint, paintsticks).
-- @param settings table
-- @param fletch_sack_contents table array of GameObj
-- @param paints table paint color mapping
-- @param debug_log function
-- @return table array of item name strings that need purchasing
function M.check_needed_items(settings, fletch_sack_contents, paints, debug_log)
    local count = fletch_sack_contents and #fletch_sack_contents or 0
    debug_log("check_needed_items called with " .. count .. " items in container")
    if not fletch_sack_contents then return {} end

    local needs = {
        wood = true,
        paint = true,
        glue = true,
        fletchings = true,
        paintstick1 = true,
        paintstick2 = true,
    }

    -- In learning mode, we only need wood
    if settings.learning then
        needs.glue = false
        needs.fletchings = false
        needs.paint = false
        needs.paintstick1 = false
        needs.paintstick2 = false
    end

    -- Check what we have
    for _, item in ipairs(fletch_sack_contents) do
        local name = item.name or ""
        if string.find(name, "shaft", 1, true) or string.find(name, settings.wood, 1, true) then
            needs.wood = false
        end
        if paints[settings.paint] and string.find(name, paints[settings.paint], 1, true) then
            needs.paint = false
        end
        if string.find(name, settings.fletchings, 1, true) then
            needs.fletchings = false
        end
        if string.find(name, "bottle of fletching glue", 1, true) then
            needs.glue = false
        end
        if settings.paintstick1 and #settings.paintstick1 > 0 and string.find(name, settings.paintstick1, 1, true) then
            needs.paintstick1 = false
        end
        if settings.paintstick2 and #settings.paintstick2 > 0 and string.find(name, settings.paintstick2, 1, true) then
            needs.paintstick2 = false
        end
    end

    local needed_items = {}
    if needs.wood then table.insert(needed_items, settings.wood) end
    if needs.glue then table.insert(needed_items, "bottle of fletching glue") end
    if needs.fletchings then table.insert(needed_items, settings.fletchings) end
    if needs.paint and settings.paint ~= 0 then table.insert(needed_items, "vial of paint") end
    if needs.paintstick1 and settings.paintstick1 and #settings.paintstick1 > 0 then
        table.insert(needed_items, settings.paintstick1)
    end
    if needs.paintstick2 and settings.paintstick2 and #settings.paintstick2 > 0 then
        table.insert(needed_items, settings.paintstick2)
    end

    return needed_items
end

--- Find the order number for a supply item in the shop menu.
-- Unhides character, parses ORDER menu, searches for the supply.
-- @param supply string item name (without leading articles)
-- @param debug_log function
-- @return string order number
function M.find_order_number(supply, debug_log)
    debug_log("find_order_number called with supply: " .. supply)

    waitrt()
    if GameState.hidden or GameState.invisible then
        fput("unhide")
    end
    clear()
    fput("order")

    -- Parse the order menu
    local menu = {}
    local endtime = os.time() + 10
    while true do
        local line = get()
        if not line then break end

        -- Match order entries: <d cmd="order N">item name</d>
        local order_num, item_name = string.match(line, "order (%d+).->(.-)<")
        if order_num and item_name then
            -- Strip leading article
            item_name = string.gsub(item_name, "^a ", "")
            item_name = string.gsub(item_name, "^an ", "")
            item_name = string.gsub(item_name, "^some ", "")
            menu[item_name] = order_num
        end

        -- Stop when we see ORDER or BUY prompt
        if string.find(line, "ORDER") or string.find(line, "BUY") then break end
        if os.time() > endtime then break end
    end

    clear()

    -- Search for the supply in the menu
    local found_name = nil
    local found_num = nil
    for name, num in pairs(menu) do
        if string.find(string.lower(name), string.lower(supply)) then
            found_name = name
            found_num = num
            break
        end
    end

    if not found_num then
        echo("ERROR: Failed to find item '" .. supply .. "' in shop menu")
        echo("Remember to leave off a/an/some at the start")
        error("item_not_found")
    end

    return found_num
end

--- Purchase needed supplies from the shop.
-- Complete workflow: check silver, bank withdraw, navigate to fletcher,
-- empty hands, order+buy each item, stow, return, deposit.
-- @param settings table
-- @param needed_items table array of item names to buy
-- @param add_stat function
-- @param debug_log function
-- @return number silver spent
function M.buy_items(settings, needed_items, add_stat, debug_log)
    debug_log("buy_items called with " .. #needed_items .. " items to purchase")

    local was_invisible = GameState.invisible
    local start_room = GameState.room_id

    -- Ensure we have enough silver
    local silver = M.check_silver()
    if silver < 5000 then
        local withdraw_amount = 5000 - silver
        Script.run("go2", "bank")
        waitrt()
        if GameState.hidden or GameState.invisible then
            fput("unhide")
        end
        fput("withdraw " .. withdraw_amount)

        if M.check_silver() < 5000 then
            echo("ERROR: Failed to withdraw silver from bank")
            error("withdraw_failed")
        end
    end

    -- Go to fletcher shop
    Script.run("go2", "fletcher")
    -- Special case for Ta'Vaalor
    local room = Room.current()
    if room and room.location and string.find(room.location, "Ta'Vaalor") then
        move("south")
    end

    -- Empty hands
    local rh = GameObj.right_hand()
    if rh then fput("stow right") end
    local lh = GameObj.left_hand()
    if lh then fput("stow left") end

    -- Buy each item
    for _, item in ipairs(needed_items) do
        local order_number
        if string.find(item, "vial of paint") then
            order_number = M.find_order_number(item, debug_log)
            multifput("order " .. order_number .. " color " .. settings.paint, "buy")
        else
            order_number = M.find_order_number(item, debug_log)
            multifput("order " .. order_number, "buy")
        end

        -- Wait for item to appear in hand
        local endtime = os.time() + 3
        while true do
            rh = GameObj.right_hand()
            if rh then break end
            if os.time() > endtime then
                echo("ERROR: Failed to buy item (timeout)")
                error("buy_failed")
            end
            pause(0.5)
        end

        -- Stow the item
        rh = GameObj.right_hand()
        local stow_check = dothistimeout("put my " .. rh.noun .. " in my " .. settings.sack, 3, "won't fit|You put")

        if stow_check and string.find(stow_check, "won't fit") then
            echo("ERROR: Container full")
            error("container_full")
        elseif not stow_check then
            echo("ERROR: Failed to stow item")
            error("stow_failed")
        end
    end

    local spent = 5000 - M.check_silver()

    -- Return to starting location
    Script.run("go2", tostring(start_room))
    if GameState.hidden or GameState.invisible then
        fput("unhide")
    end
    fput("depo all")

    -- Re-hide if we were invisible before
    if was_invisible and Spell[916] and Spell[916].affordable then
        fput("incant 916")
    end

    return spent
end

return M
