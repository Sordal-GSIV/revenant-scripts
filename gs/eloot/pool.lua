--- ELoot locksmith pool module
-- Ported from eloot.lic ELoot::Sell locksmith pool methods
-- (lines 6218-6412, 6512-6554).
-- Handles depositing boxes into the locksmith pool, tipping,
-- returning opened boxes, and pool management.
--
-- Usage:
--   local Pool = require("gs.eloot.pool")
--   Pool.pool({ deposit = true, check = true }, data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires to avoid circular dependencies
-- ---------------------------------------------------------------------------

local function Util()      return require("gs.eloot.util") end
local function Inventory() return require("gs.eloot.inventory") end
local function Loot()      return require("gs.eloot.loot") end
local function Sell()      return require("gs.eloot.sell") end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function contains(tbl, val)
    if not tbl or not val then return false end
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function any_match(lines, pattern)
    if not lines then return false end
    for _, l in ipairs(lines) do
        if l:find(pattern) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 1. locksmith_tip (lines 6406-6410)
-- Tip formula for incremental tipping.
-- ---------------------------------------------------------------------------

--- Calculate the tip for a single box based on its position in the pool.
-- @param box_no number position of the box in the pool (1-100)
-- @param base_tip number minimum tip amount
-- @param max_tip number maximum tip amount
-- @param alpha number scaling exponent
-- @return number tip amount (rounded integer)
function M.locksmith_tip(box_no, base_tip, max_tip, alpha)
    local factor = box_no / 100.0
    local adjusted_tip = (tonumber(base_tip) or 0) +
        (factor ^ (tonumber(alpha) or 1.0)) *
        ((tonumber(max_tip) or 0) - (tonumber(base_tip) or 0))
    return math.floor(adjusted_tip + 0.5)  -- round
end

-- ---------------------------------------------------------------------------
-- 2. locksmith_determine_tip (lines 6394-6404)
-- Calculate scaled tip for a batch of boxes.
-- ---------------------------------------------------------------------------

--- Calculate the total tip for a batch of boxes using incremental tipping.
-- @param pool_count number current number of boxes in the pool
-- @param boxes_len number number of boxes being deposited
-- @param data table ELoot data state
-- @return number total tip amount (ceiling)
function M.locksmith_determine_tip(pool_count, boxes_len, data)
    local tip_amount = 0
    local upper_limit = math.min(pool_count + boxes_len, 100)
    pool_count = pool_count + 1

    for items = pool_count, upper_limit do
        tip_amount = tip_amount + M.locksmith_tip(
            items,
            data.settings.base_tip,
            data.settings.max_tip,
            data.settings.alpha_rate
        )
    end

    return math.ceil(tip_amount)
end

-- ---------------------------------------------------------------------------
-- 3. locksmith_pool_count (lines 6376-6392)
-- Count boxes in pool.
-- ---------------------------------------------------------------------------

--- Ask the pool worker how many boxes are in the pool.
-- @param worker table GameObj NPC worker
-- @param data table ELoot data state
-- @return number count of boxes in pool (minus ready-for-return ones)
function M.locksmith_pool_count(worker, data)
    local current_box_amount = 0
    local list_match = {
        "here's the list of boxes we have for you%.",
        "You haven't given us any boxes to be worked on%.",
        "^%d+%.",
    }

    local results = Util().get_command("ask #" .. worker.id .. " about list",
        list_match, { silent = true, quiet = true }, data)

    -- Find the highest numbered box entry
    for i = #results, 1, -1 do
        local amount = results[i]:match("^%s*(%d+)%.%s+An?")
        if amount then
            current_box_amount = tonumber(amount) or 0
            break
        end
    end

    -- Subtract boxes ready for return
    local previous_buffer = reget and reget(300) or {}
    local start_index = nil
    for i = #previous_buffer, 1, -1 do
        if string.find(previous_buffer[i], "here's the list of boxes we have for you%.") or
           string.find(previous_buffer[i], "You haven't given us any boxes to be worked on%.") then
            start_index = i
            break
        end
    end

    if start_index then
        local ready_count = 0
        for i = start_index, #previous_buffer do
            if string.find(previous_buffer[i], "It is ready to be RETURNED%.") then
                ready_count = ready_count + 1
            end
        end
        current_box_amount = current_box_amount - ready_count
    end

    return current_box_amount
end

-- ---------------------------------------------------------------------------
-- 4. handle_full_pool (lines 6316-6323)
-- Handle when pool is full.
-- ---------------------------------------------------------------------------

--- Handle when the pool is full. Log warning, attempt return, recount.
-- @param worker table GameObj NPC worker
-- @param data table ELoot data state
-- @return number updated pool count
function M.handle_full_pool(worker, data)
    Util().msg({ type = "yellow", text = " That was the last spot open in the pool" }, data)

    Util().msg({ type = "yellow", text = " Checking to see if any boxes available for return" }, data)
    M.pool_return(worker, data)
    return M.locksmith_pool_count(worker, data)
end

-- ---------------------------------------------------------------------------
-- 5. pool_return (lines 6325-6374)
-- Return/loot boxes from pool.
-- ---------------------------------------------------------------------------

--- Retrieve and loot boxes from the locksmith pool.
-- @param worker table|nil GameObj NPC worker (navigates to pool if nil)
-- @param data table ELoot data state
function M.pool_return(worker, data)
    if not worker then
        Util().go2("locksmith pool", data)
        worker = Util().find_worker(data)
    end

    local lighten_load = false

    while true do
        local match = {
            "We don't have any boxes ready for you",
            "We don't seem to have that box",
            "Alright, here's your",
            "You need to lighten your load first",
        }
        local res = dothistimeout("ask #" .. worker.id .. " for return", 3, match)

        -- Break if no boxes returned or not a returnable response
        if not res then break end
        if not (string.find(res, "Alright, here's your") or
                string.find(res, "You need to lighten your load first")) then
            break
        end

        if string.find(res, "You need to lighten your load first") then
            if lighten_load then
                Util().msg({ type = "info", text = " Too much weight! Breaking from locksmith pool return." }, data)
                break
            end
            lighten_load = true
            Util().msg({ type = "info", text = " Too much weight! Depositing coins and trying again" }, data)
            local room = Room.current().id
            Util().silver_deposit(nil, data)
            Util().go2(room, data)
        else
            -- Wait for box to appear in hand
            for _ = 1, 20 do
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                local rh_type = rh and rh.type or ""
                local lh_type = lh and lh.type or ""
                if string.find(rh_type .. "," .. lh_type, "box") or
                   string.find(rh_type .. "," .. lh_type, "plinite") then
                    break
                end
                pause(0.1)
            end

            lighten_load = false
            local box = nil
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh.type and (string.find(rh.type, "box") or string.find(rh.type, "plinite")) then
                box = rh
            elseif lh.type and (string.find(lh.type, "box") or string.find(lh.type, "plinite")) then
                box = lh
            else
                Util().msg({ type = "error", text = " Failed to find the box you were supposed to get; report this to Elanthia-Online" }, data)
                Util().msg({ type = "error", text = " GameObj.left_hand: " .. tostring(lh) }, data)
                Util().msg({ type = "error", text = " GameObj.right_hand: " .. tostring(rh) }, data)
            end

            if box then
                data.silver_breakdown["Pool Return"] = (data.silver_breakdown["Pool Return"] or 0) + 1
                Loot().box_loot(box, "Locksmith Pool", data)
            end
        end

        Util().wait_rt()
    end

    data.silver_breakdown["Pool Depth"] = M.locksmith_pool_count(worker, data)
end

-- ---------------------------------------------------------------------------
-- 6. locksmith_pool (lines 6218-6314)
-- Main pool handler: navigate to pool, handle tips, deposit boxes.
-- ---------------------------------------------------------------------------

--- Deposit boxes into the locksmith pool.
-- @param boxes table list of box GameObj items
-- @param deposit boolean|nil if true, this is a deposit-only operation
-- @param data table ELoot data state
-- @return boolean|nil true if deposit-only mode exits early from full pool
function M.locksmith_pool(boxes, deposit, data)
    if Util().f2p and Util().f2p(data) then return end

    -- Are we starting with a box in hand?
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local box_in_hand = (rh.type and string.find(rh.type, "box")) or
                        (lh.type and string.find(lh.type, "box"))

    -- Make sure some type of tipping was selected
    if not data.settings.use_standard_tipping and not data.settings.use_incremental_tipping then
        Util().msg({ type = "yellow", text = " No tipping options selected in UI" }, data)
        error("eloot: no tipping options selected")
    end

    local match_patterns = {
        "You want a locksmith",
        "You don't have",
        "takes your",
        "already holding as many boxes",
        "already unlocked",
        "already open",
    }
    local percent = data.settings.sell_locksmith_pool_tip_percent and " PERCENT" or ""
    local pool_count = 0

    -- If we're here, assume we will empty out the disk
    Util().reset_disk_full(data)

    if #boxes > 0 and data.settings.use_standard_tipping then
        local amount = data.settings.locksmith_withdraw_amount
        Util().silver_withdraw(amount, data)
    end

    Util().go2("locksmith pool", data)
    local original_pool = Room.current().id
    local worker = Util().find_worker(data)

    -- If using incremental tipping, need to find out how many boxes are in the pool
    if #boxes > 0 and data.settings.use_incremental_tipping then
        pool_count = M.locksmith_pool_count(worker, data)
        if pool_count > 99 then
            local new_count = M.handle_full_pool(worker, data)
            if deposit then return true end
            if new_count > 99 then return end
            pool_count = new_count
        else
            local total_tips = M.locksmith_determine_tip(pool_count + 1, #boxes, data) + 15000
            Util().silver_withdraw(total_tips, data)
            Util().go2(original_pool, data)
            worker = Util().find_worker(data)
        end
    end

    -- Free hands unless we already have a box
    rh = GameObj.right_hand()
    lh = GameObj.left_hand()
    if not ((rh.type and string.find(rh.type, "box")) or (lh.type and string.find(lh.type, "box"))) then
        Inventory().free_hands({ both = true }, data)
    end
    Util().wait_for_disk(data)

    for _, box in ipairs(boxes) do
        local redo_needed = false
        repeat
            redo_needed = false

            -- Get box into hand if not already there
            rh = GameObj.right_hand()
            lh = GameObj.left_hand()
            if not ((rh.type and string.find(rh.type, "box")) or (lh.type and string.find(lh.type, "box"))) then
                Inventory().drag(box, nil, data)
            end

            -- Make sure box is in right hand
            rh = GameObj.right_hand()
            if rh.id ~= box.id then
                fput("swap")
                Util().wait_rt()
            end

            box = Util().box_unphase(box, data)

            -- Determine tip amount
            local tip_amount
            if data.settings.use_standard_tipping then
                tip_amount = tostring(data.settings.sell_locksmith_pool_tip or 0) .. percent
            else
                tip_amount = tostring(M.locksmith_determine_tip(pool_count, 1, data))
            end

            for i = 1, 2 do
                local confirm = (i == 1) and "" or " confirm"
                local result = dothistimeout("give #" .. worker.id .. " " .. tip_amount .. confirm,
                    3, match_patterns)

                if result and string.find(result, "totaling ([%d,]+) silvers?") then
                    local silver_str = result:match("totaling ([%d,]+) silvers?")
                    local silver = tonumber(silver_str and silver_str:gsub(",", "") or "0") or 0
                    data.silver_breakdown["Locksmith Pool"] = (data.silver_breakdown["Locksmith Pool"] or 0) - silver
                    pool_count = pool_count + 1
                    data.silver_breakdown["Pool Dropoff"] = (data.silver_breakdown["Pool Dropoff"] or 0) + 1

                    if pool_count > 99 then
                        local new_count = M.handle_full_pool(worker, data)
                        if deposit then return true end
                        pool_count = new_count
                    end
                elseif result and string.find(result, "You don't have that much") then
                    Util().silver_withdraw(data.settings.locksmith_withdraw_amount, data)
                    Util().go2(original_pool, data)
                    redo_needed = true
                    break
                elseif result and string.find(result, "already holding as many boxes") then
                    if not box_in_hand then
                        Inventory().single_drag(box, nil, data)
                    end
                    local new_count = M.handle_full_pool(worker, data)
                    if deposit then return true end
                    pool_count = new_count
                    redo_needed = true
                    break
                elseif result and (string.find(result, "already unlocked") or string.find(result, "already open")) then
                    Loot().box_loot(box, "Locksmith Pool", data)
                end
            end
        until not redo_needed

        if pool_count > 99 then break end
    end

    Inventory().free_hands({ both = true }, data)
end

-- ---------------------------------------------------------------------------
-- 7. pool (lines 6512-6552)
-- Pool entry point: deposit and/or return.
-- ---------------------------------------------------------------------------

--- Main pool entry point. Handles deposit-only, return-only, or both.
-- @param opts table {deposit=boolean, check=boolean}
-- @param data table ELoot data state
function M.pool(opts, data)
    opts = opts or {}
    local room = Room.current().id
    data.right_hand = GameObj.right_hand()
    data.left_hand = GameObj.left_hand()

    if opts.deposit then
        -- Make sure we can see all the containers
        for item_key, container in pairs(StowList.stow_list) do
            if container then
                local match = false
                for _, sell in ipairs(data.settings.sell_container or {}) do
                    if string.find(tostring(item_key), sell, 1, true) then
                        match = true
                        break
                    end
                end
                if match then
                    Inventory().open_single_container(container, data)
                end
            end
        end

        -- Remember current silver amount
        local current_keep_silver = tonumber(data.settings.sell_keep_silver) or 0
        data.settings.sell_keep_silver = Util().silver_check(data)

        Sell().box_in_hand(opts.deposit, data)
        local deposit_boxes = Util().find_boxes(data)

        Inventory().free_hands({ both = true }, data)
        if #deposit_boxes > 0 then
            M.locksmith_pool(deposit_boxes, opts.deposit, data)
        end

        -- Deposit any additional silver taken out for box processing
        Util().silver_deposit(nil, data)
        data.settings.sell_keep_silver = current_keep_silver
    end

    if opts.check then
        Inventory().free_hands({ both = true }, data)
        M.pool_return(nil, data)
    end

    Util().go2(room, data)
    Inventory().return_hands(data)
end

return M
