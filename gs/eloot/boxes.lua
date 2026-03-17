local inventory = require("inventory")

local M = {}

function M.loot_box(box, state)
    -- Open the box
    fput("open #" .. box.id)
    pause(0.3)

    -- Get coins
    fput("get coins from #" .. box.id)

    -- Get remaining contents
    local contents = box.contents
    if contents then
        for _, item in ipairs(contents) do
            waitrt()
            fput("get #" .. item.id .. " from #" .. box.id)
            local container = inventory.route_container(item, state)
            inventory.stow_item(item, container)
        end
    end

    -- Discard empty box
    fput("drop #" .. box.id)
end

function M.locksmith_pool_deposit(state)
    if not state.sell_locksmith_pool then
        respond("[eloot] Locksmith pool disabled")
        return
    end

    Script.run("go2", "locksmith pool")
    pause(0.5)

    -- Find the pool worker NPC
    local npcs = GameObj.npcs()
    local worker = nil
    for _, npc in ipairs(npcs) do
        if npc.noun == "worker" or npc.noun == "locksmith" then
            worker = npc
            break
        end
    end

    if not worker then
        respond("[eloot] No locksmith worker found")
        return
    end

    -- Deposit boxes from inventory
    local deposited = 0
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item:type_p("box") then
            local tip = state.locksmith_pool_tip or 0
            local tip_str = tostring(tip)
            if state.locksmith_pool_tip_percent then
                tip_str = tip_str .. " percent"
            end

            waitrt()
            fput("give #" .. item.id .. " to #" .. worker.id .. " " .. tip_str)
            deposited = deposited + 1
        end
    end

    respond("[eloot] Deposited " .. deposited .. " boxes to locksmith pool")
end

function M.locksmith_pool_return(state)
    Script.run("go2", "locksmith pool")
    pause(0.5)

    local npcs = GameObj.npcs()
    local worker = nil
    for _, npc in ipairs(npcs) do
        if npc.noun == "worker" or npc.noun == "locksmith" then
            worker = npc
            break
        end
    end

    if not worker then
        respond("[eloot] No locksmith worker found")
        return
    end

    -- Ask for returns
    local returned = 0
    for attempt = 1, 50 do
        fput("ask #" .. worker.id .. " for return")
        pause(0.5)
        local rh = GameObj.right_hand()
        if not rh then break end -- no more boxes
        if rh:type_p("box") then
            M.loot_box(rh, state)
            returned = returned + 1
        else
            fput("stow right")
        end
    end

    respond("[eloot] Retrieved and looted " .. returned .. " boxes from pool")
end

function M.locksmith_pool(state)
    M.locksmith_pool_deposit(state)
    M.locksmith_pool_return(state)
end

return M
