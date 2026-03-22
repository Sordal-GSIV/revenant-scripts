--- sloot/locksmith.lua
-- Locksmith routine: open boxes, pay, loot contents, trash empty boxes.
-- Mirrors locksmith proc from sloot.lic v3.5.2.

local items_mod = require("sloot/items")
local coins_mod = require("sloot/coins")
local sacks_mod = require("sloot/sacks")

local M = {}

--- Run the locksmith routine on a list of boxes.
-- @param boxes           array of GameObj boxes
-- @param silver_breakdown  table to accumulate silver changes by location
-- @param settings        settings table
function M.locksmith(boxes, silver_breakdown, settings)
    if #boxes == 0 then return end

    empty_hands()
    coins_mod.withdraw_coins(10000)
    go2("locksmith")

    -- Unhide if needed
    if invisible() or hiding() then
        dothistimeout("unhide", 5, Regex.new("hiding|visible"))
    end

    -- Find trash container
    local trash = nil
    for _, obj in ipairs(GameObj.loot()) do
        if Regex.test(obj.name or "", "crate|barrel|wastebarrel|casket") then
            trash = obj; break
        end
    end
    for _, obj in ipairs(GameObj.room_desc() or {}) do
        if not trash and Regex.test(obj.name or "", "crate|barrel|wastebarrel|casket") then
            trash = obj; break
        end
    end

    -- Find activator (bell / chime / keys)
    local activator_cmd = nil
    local act_obj = nil
    -- Check for loose chime in room first
    for _, obj in ipairs(GameObj.loot()) do
        if Regex.test(obj.noun or "", "chime") then act_obj = obj; break end
    end
    if not act_obj then
        -- Check on table/counter
        local surface = nil
        for _, obj in ipairs(GameObj.loot()) do
            if Regex.test(obj.name or "", "table|counter") then surface = obj; break end
        end
        for _, obj in ipairs(GameObj.room_desc() or {}) do
            if not surface and Regex.test(obj.name or "", "table|counter") then surface = obj; break end
        end
        if surface then
            dothistimeout("look on #" .. surface.id, 5, Regex.new("On the"))
            for _, obj in ipairs(surface.contents or {}) do
                if Regex.test(obj.noun or "", "bell|keys|chime") then
                    act_obj = obj; break
                end
            end
        end
    end

    if act_obj then
        if Regex.test(act_obj.noun or "", "bell|chime") then
            activator_cmd = "ring #" .. act_obj.id
        elseif Regex.test(act_obj.noun or "", "keys") then
            activator_cmd = "pull keys"
        end
    end

    if not activator_cmd then
        echo("[SLoot] locksmith: unable to find activator")
        return
    end

    silver_breakdown["locksmith"] = silver_breakdown["locksmith"] or 0

    local done = {}
    for _, box in ipairs(boxes) do
        if done[box.id] then goto next_box end
        done[box.id] = true

        -- Get the box
        if not items_mod.get_item(box, nil) then
            goto next_box
        end

        -- Handle phased (shifting) boxes
        if Regex.test(box.name or "", "shifting") then
            local in_right = GameObj.right_hand() and GameObj.right_hand().id == box.id
            local res2 = dothistimeout("drop #" .. box.id, 5, Regex.new("flickers in and out of existence"))
            if res2 and Regex.test(res2, "flickers in and out") then
                if in_right then
                    wait_until(function() local rh = GameObj.right_hand(); return rh and rh.noun end)
                    box = GameObj.right_hand()
                else
                    wait_until(function() local lh = GameObj.left_hand(); return lh and lh.noun end)
                    box = GameObj.left_hand()
                end
            end
        end

        -- Ring activator
        local res = dothistimeout(activator_cmd, 5, Regex.new("but it'll cost ya\\.  Gimme (\\d+) silvers"))
        local box_cost = 0
        if res then
            local cost = res:match("Gimme (%d+) silvers")
            box_cost = tonumber(cost) or 0
        else
            echo("[SLoot] locksmith: unknown activator response")
        end

        -- Pay
        local pay_res = dothistimeout("pay", 5, Regex.new("accepts|have enough"))
        if pay_res and Regex.test(pay_res, "have enough") then
            -- Not enough coin — stow box and withdraw more
            items_mod.put_item(box, sacks_mod.sacks["box"] or GameObj.find_inv(UserVars["boxsack"] or ""))
            coins_mod.withdraw_coins(10000)
            -- Retry this box
            done[box.id] = nil
            goto next_box
        end

        silver_breakdown["locksmith"] = silver_breakdown["locksmith"] - box_cost
        local cur_silvers = checksilvers()

        -- Open box and loot it
        dothistimeout("open #" .. box.id, 5, Regex.new("open"))
        if not box.contents then
            dothistimeout("look in #" .. box.id, 5, Regex.new("^In the"))
        end

        if box.contents then
            items_mod.loot_it(box.contents, {}, settings)
        else
            echo("[SLoot] locksmith: failed to see box contents — looting from hand")
            items_mod.loot_it({ box }, {}, settings)
        end

        silver_breakdown["locksmith"] = silver_breakdown["locksmith"] + (checksilvers() - cur_silvers)

        -- Trash the empty box
        if trash then
            if not items_mod.put_item(box, trash.id) then
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                if (rh and rh.noun == box.noun) or (lh and lh.noun == box.noun) then
                    fput("drop #" .. box.id)
                end
            end
        else
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.noun == box.noun) or (lh and lh.noun == box.noun) then
                fput("drop #" .. box.id)
            end
        end

        ::next_box::
    end
end

return M
