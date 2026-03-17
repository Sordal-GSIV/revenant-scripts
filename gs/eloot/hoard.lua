local M = {}

function M.hoard_items(item_type, state)
    -- item_type is "gem" or "alchemy"
    local prefix = item_type == "gem" and "gem" or "alchemy"
    local enabled = state[prefix .. "_horde"]
    if not enabled then
        respond("[eloot] " .. item_type .. " hoarding disabled")
        return
    end

    local locker_tag = state[prefix .. "_horde_locker"] or "locker"
    local containers = state[prefix .. "_horde_containers"] or {"default"}

    respond("[eloot] Hoarding " .. item_type .. " items to locker...")

    -- Navigate to locker
    Script.run("go2", locker_tag)
    pause(0.5)

    -- Open locker
    fput("open locker")
    pause(0.3)

    -- Get items from source containers and put in locker
    local hoarded = 0
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        local should_hoard = false
        if item_type == "gem" and (item:type_p("gem") or item:type_p("valuable")) then
            should_hoard = true
        elseif item_type == "alchemy" and (item:type_p("reagent") or item:type_p("alchemy")) then
            should_hoard = true
        end

        if should_hoard then
            waitrt()
            fput("put #" .. item.id .. " in locker")
            hoarded = hoarded + 1
        end
    end

    fput("close locker")
    respond("[eloot] Hoarded " .. hoarded .. " " .. item_type .. " items")
end

function M.show_inventory(item_type, state)
    local prefix = item_type == "gem" and "gem" or "alchemy"
    respond("[eloot] " .. item_type .. " hoard inventory:")

    -- Navigate to locker and look
    local locker_tag = state[prefix .. "_horde_locker"] or "locker"
    Script.run("go2", locker_tag)
    pause(0.5)
    fput("open locker")
    fput("look in locker")
    -- Output goes to game window
    fput("close locker")
end

function M.raid(item_type, item_name, count, state)
    local prefix = item_type == "gem" and "gem" or "alchemy"
    local locker_tag = state[prefix .. "_horde_locker"] or "locker"

    Script.run("go2", locker_tag)
    pause(0.5)
    fput("open locker")

    local taken = 0
    for i = 1, (count or 1) do
        fput("get " .. item_name .. " from locker")
        taken = taken + 1
    end

    fput("close locker")
    respond("[eloot] Took " .. taken .. " " .. item_name .. " from hoard")
end

return M
