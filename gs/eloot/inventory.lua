--- ELoot inventory management
-- Ported from eloot.lic lines 1894-2106 (set_inventory helpers) and
-- lines 3162-3641 (ELoot::Inventory submodule).
--
-- Usage:
--   local Inventory = require("gs.eloot.inventory")
--   Inventory.clear_hands(data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires to avoid circular dependencies
-- ---------------------------------------------------------------------------

local function Util()   return require("gs.eloot.util") end
local function Settings() return require("gs.eloot.settings") end

-- ---------------------------------------------------------------------------
-- Helper: check if any line in a table matches a Lua pattern
-- ---------------------------------------------------------------------------

local function any_match(lines, pattern)
    if not lines then return false end
    for _, l in ipairs(lines) do
        if l:find(pattern) then return true end
    end
    return false
end

--- Check if any line matches any of several patterns.
local function any_match_multi(lines, patterns)
    if not lines then return false end
    for _, l in ipairs(lines) do
        for _, pat in ipairs(patterns) do
            if l:find(pat) then return true end
        end
    end
    return false
end

--- Find the first line matching a pattern, return captures.
local function find_match(lines, pattern)
    if not lines then return nil end
    for _, l in ipairs(lines) do
        local m = l:match(pattern)
        if m then return m end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Helper: table contains value
-- ---------------------------------------------------------------------------

local function contains(tbl, val)
    if not tbl or not val then return false end
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function contains_id(tbl, id)
    if not tbl or not id then return false end
    for _, v in ipairs(tbl) do
        if v and v.id == id then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 1. container_contents (lines 3162-3184)
-- Wait for a container's contents to be populated by the game engine.
-- ---------------------------------------------------------------------------

--- Wait for container contents to become available.
-- @param container GameObj the container to inspect
-- @param time number seconds to wait (default 3)
-- @return boolean true if contents became available
function M.container_contents(container, time, data)
    time = time or 3
    Util().msg({ type = "debug", text = "container: " .. tostring(container) }, data)

    local wait_ticks = time * 10  -- check in 0.1s increments

    -- First attempt: just poll
    for _ = 1, wait_ticks do
        local keys = GameObj.containers()
        if keys[container.id] and type(container.contents) == "table" then
            return true
        end
        pause(0.1)
    end

    Util().msg({ type = "info", text = "container_contents: first attempt failed. Retrying. Container: " .. (container.name or "?") }, data)

    -- Second attempt: explicitly look in the container
    local lines = Util().get_command("look in #" .. container.id, data.look_regex, { silent = true, quiet = true }, data)

    for _ = 1, wait_ticks do
        local keys = GameObj.containers()
        if keys[container.id] and type(container.contents) == "table" then
            return true
        end
        if any_match_multi(lines, {
            "The wide leather belt",
            "You glance",
            "There is nothing",
            "stuffed with a variety of shredded up paper and cloth",
            "Looking at the .*, you notice:",
        }) then
            return true
        end
        pause(0.1)
    end

    Util().msg({ type = "info", text = "container_contents: second attempt failed. Container: " .. tostring(container) }, data)
    Util().msg({ type = "info", text = " Unable to determine the contents of " .. (container.name or "?") .. "." }, data)
    return false
end

-- ---------------------------------------------------------------------------
-- 2. check_auto_closer (lines 3186-3192)
-- Open any containers in the auto_close list.
-- ---------------------------------------------------------------------------

--- Re-open containers that auto-close after looting.
-- @param data table ELoot data state
function M.check_auto_closer(data)
    if not data.settings.auto_close or #data.settings.auto_close == 0 then
        return
    end

    for _, bag_name in ipairs(data.settings.auto_close) do
        M.open_single_container(bag_name, data)
    end
end

-- ---------------------------------------------------------------------------
-- 3. clear_hands (lines 3194-3206)
-- Remember what's in hands, then stow both.
-- ---------------------------------------------------------------------------

--- Save current hand contents and empty both hands.
-- @param data table ELoot data state
function M.clear_hands(data)
    data.right_hand = GameObj.right_hand()
    data.left_hand  = GameObj.left_hand()

    M.free_hands({ both = true }, data)

    if checkright() or checkleft() then
        Util().msg({ type = "error", text = "** Something is wrong. Can't empty hands! Report this to Elanthia-Online. A log is helpful. Exiting...", space = true }, data)
        error("eloot: unable to clear hands")
    end
end

-- ---------------------------------------------------------------------------
-- 4. close_container (lines 3208-3210)
-- Close a single container by id.
-- ---------------------------------------------------------------------------

--- Close a single container.
-- @param bag GameObj the container to close
-- @param data table ELoot data state
function M.close_container(bag, data)
    Util().get_res("close #" .. bag.id, data.close_regex, data)
end

-- ---------------------------------------------------------------------------
-- 5. close_sell_containers (lines 3212-3221)
-- Close all sell containers if keep_closed is enabled.
-- ---------------------------------------------------------------------------

--- Close all selling containers (skips ready-list containers).
-- @param data table ELoot data state
function M.close_sell_containers(data)
    if not data.settings.keep_closed then return end

    for _, sack in ipairs(data.sell_containers) do
        -- Don't close ready list containers — storage/retrieval breaks
        local skip = false
        for k, v in pairs(ReadyList.ready_list) do
            if data.original_readylist and contains(data.original_readylist, k) and v.id == sack.id then
                skip = true
                break
            end
        end

        if not skip then
            M.close_container(sack, data)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 6. drag (lines 3223-3267)
-- Drag an item from inventory to a hand.
-- ---------------------------------------------------------------------------

--- Drag an item from a container to a hand.
-- @param item GameObj the item to retrieve
-- @param to string "hand" (free either), "right", or "left"
-- @param data table ELoot data state
-- @return boolean true if item ended up in hand
function M.drag(item, to, data)
    to = to or "hand"
    Util().msg({ type = "debug", text = "drag item: " .. tostring(item) }, data)

    if not item or (item.name and item.name == "Empty") then return false end
    if item.id == nil then return false end

    -- Free the target hand
    if to == "hand" then
        M.free_hand(data)
        local rh = GameObj.right_hand()
        to = (rh.id == nil) and "right" or "left"
    elseif to == "right" then
        M.free_hands({ right = true }, data)
    elseif to == "left" then
        M.free_hands({ left = true }, data)
    end

    local line = Util().get_res("_drag #" .. item.id .. " " .. to, nil, data)

    for _ = 1, 20 do
        if Util().in_hand(item) then return true end
        if line and line:find("Get what") then break end
        if line and line:find("I could not find what you were referring to") then break end
        if line and line:find("You are unable to handle the additional load") then break end
        pause(0.1)
    end

    -- Can't carry it
    if line and line:find("You are unable to handle the additional load") then
        Util().msg({ type = "yellow", text = " Unable to pick up the " .. (item.name or "?") .. ". Exiting..." }, data)
        error("eloot: unable to handle additional load")
    end

    -- Can't find it — search all bags
    if line and (line:find("Get what") or line:find("I could not find what you were referring to")) then
        for _, bag_obj in pairs(StowList.stow_list) do
            M.open_single_container(bag_obj, data)
        end

        -- Look through all bag contents for the lost item
        local Sell = require("gs.eloot.sell")
        local all_items = Sell.check_inventory and Sell.check_inventory(data) or {}
        local lost_item = nil
        for _, obj in ipairs(all_items) do
            if obj.id == item.id then
                lost_item = obj
                break
            end
        end

        if lost_item then
            return M.drag(lost_item, to, data)
        else
            Util().msg({ type = "info", text = " Can't find " .. (item.name or "?") .. ". Looked in all the bags in case it got misplaced." }, data)
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 7. wear (lines 3269-3289)
-- Wear an item (drag to wear slot).
-- ---------------------------------------------------------------------------

--- Wear an item from hand.
-- @param item GameObj the item to wear
-- @param data table ELoot data state
-- @return boolean true on success
function M.wear(item, data)
    Util().msg({ type = "debug", text = "wear item: " .. tostring(item) }, data)

    if not item or (item.name and item.name == "Empty") then return false end
    if item.id == nil then return false end

    local line = Util().get_res("_drag #" .. item.id .. " wear", nil, data)

    for _ = 1, 20 do
        -- Success: not in hand AND in worn inventory
        if not Util().in_hand(item) then
            local inv = GameObj.inv()
            for _, obj in ipairs(inv) do
                if obj.id == item.id then
                    return true
                end
            end
        end
        if line and line:find("You can't wear that") then break end
        pause(0.1)
    end

    -- Still in hand — something went wrong
    if Util().in_hand(item) then
        Util().msg({ type = "warn", text = " Something is wrong. Unable to wear the " .. tostring(item) .. ". Exiting to avoid losing items." }, data)
        Util().msg({ type = "warn", text = " Please grab a short log and post it to the scripting discord for debugging" }, data)
        error("eloot: unable to wear item")
    end

    return true
end

-- ---------------------------------------------------------------------------
-- 8. free_hand (lines 3291-3312)
-- Free one hand by stowing, respecting injury and favor_left.
-- ---------------------------------------------------------------------------

--- Free one hand, preferring uninjured hands and honoring favor_left.
-- @param data table ELoot data state
function M.free_hand(data)
    local rw = math.max(Wounds.rightArm, Wounds.rightHand, Scars.rightArm, Scars.rightHand)
    local right_usable = rw < 3
    local rh = GameObj.right_hand()
    local right_free = (rh.id == nil) and right_usable

    local lw = math.max(Wounds.leftArm, Wounds.leftHand, Scars.leftArm, Scars.leftHand)
    local left_usable = lw < 3
    local lh = GameObj.left_hand()
    local left_free = (lh.id == nil) and left_usable

    if right_free or left_free then return end

    waitrt()

    local favor_left = data.settings.favor_left
    local right_damaged = rw == 3

    if (favor_left and left_usable) or right_damaged then
        M.free_hands({ left = true }, data)
    elseif right_usable then
        M.free_hands({ right = true }, data)
    else
        Util().msg({ type = "yellow", text = " Neither hand is usable. Looks like you need an Empath!", space = true }, data)
        error("eloot: no usable hand")
    end
end

-- ---------------------------------------------------------------------------
-- 9. free_hands (lines 3314-3333)
-- Free specific hands (right/left/both).
-- ---------------------------------------------------------------------------

--- Free the specified hand(s) by stowing or returning to ready list.
-- @param opts table { right = bool, left = bool, both = bool }
-- @param data table ELoot data state
function M.free_hands(opts, data)
    opts = opts or {}
    local do_right = opts.right or opts.both
    local do_left  = opts.left or opts.both

    if do_right and checkright() then
        local rh = GameObj.right_hand()
        if rh.id then
            -- Check if it's a ready-list item
            local ready_item = nil
            for k, v in pairs(ReadyList.ready_list) do
                if data.original_readylist and contains(data.original_readylist, k) and v.id == rh.id then
                    ready_item = k
                    break
                end
            end
            if ready_item then
                M.stow_ready_list(ready_item, rh, data)
            end
        end
        if checkright() then
            M.single_drag(GameObj.right_hand(), true, data)
        end
    end

    if do_left and checkleft() then
        local lh = GameObj.left_hand()
        if lh.id then
            local ready_item = nil
            for k, v in pairs(ReadyList.ready_list) do
                if data.original_readylist and contains(data.original_readylist, k) and v.id == lh.id then
                    ready_item = k
                    break
                end
            end
            if ready_item then
                M.stow_ready_list(ready_item, lh, data)
            end
        end
        if checkleft() then
            M.single_drag(GameObj.left_hand(), true, data)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 10. open_loot_containers (lines 3335-3361)
-- Open containers needed for looting a set of items.
-- ---------------------------------------------------------------------------

--- Open all containers that will receive loot from a set of items.
-- @param items table array of loot GameObjs
-- @param data table ELoot data state
function M.open_loot_containers(items, data)
    Util().msg({ type = "debug", text = "open_loot_containers: " .. tostring(#items) .. " items" }, data)

    -- Recheck auto-closers periodically (every 30s)
    if Util().time_between("autoclosers", 30, data) then
        M.check_auto_closer(data)
    end

    -- Early return if not keeping closed (they were all opened on startup)
    if not data.settings.keep_closed then return end

    M.open_single_container(StowList.stow_list.default, data)
    M.open_single_container(StowList.stow_list.overflow_container, data)
    M.open_single_container(StowList.stow_list.secondary_overflow, data)

    local opened = {}
    for _, loot in ipairs(items) do
        local loot_type = loot.type
        if loot_type then
            local container = StowList.stow_list[loot_type]
            if container and not opened[container.id] then
                M.open_single_container(container, data)
                opened[container.id] = true
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 11. open_single_container (lines 3363-3392)
-- Open one container with messaging handling.
-- ---------------------------------------------------------------------------

--- Open a single container, resolving name/GameObj/StowList key.
-- @param sack string|GameObj container identifier
-- @param data table ELoot data state
function M.open_single_container(sack, data)
    Util().msg({ type = "debug", text = "open_single_container: " .. tostring(sack) }, data)

    if not sack then return end
    if type(sack) == "string" and sack == "" then return end

    -- Resolve to a GameObj
    local container
    if type(sack) == "table" and sack.id then
        -- It's already a GameObj
        container = sack
    elseif type(sack) == "string" then
        container = StowList.stow_list[sack]
        if not container then
            container = GameObj[sack]
        end
        if not container then
            Util().msg({ type = "debug", text = "open_single_container: not able to determine GameObj for " .. tostring(sack) }, data)
            return
        end
    else
        return
    end

    -- Already open? Check if contents are populated
    local keys = GameObj.containers()
    if keys[container.id] and type(container.contents) == "table" then
        return
    end

    -- Assume closed — try to open
    Util().get_command("open #" .. container.id, data.silent_open, { silent = true, quiet = true }, data)

    -- Inspect contents
    local lines = Util().get_command("look in #" .. container.id, data.look_regex, { silent = true, quiet = true }, data)
    if any_match_multi(lines, {
        "You glance",
        "There is nothing",
        "stuffed with a variety of shredded up paper and cloth",
        "Looking at the .*, you notice:",
        "The .+ has .+ in its left%-hand scabbard and .+ in its right%-hand scabbard%.",
    }) then
        -- Contents loaded
    end

    -- Track as a sell container
    if not contains_id(data.sell_containers, container.id) then
        table.insert(data.sell_containers, container)
    end
end

-- ---------------------------------------------------------------------------
-- 12. return_hands (lines 3394-3415)
-- Restore original hand contents after an operation.
-- ---------------------------------------------------------------------------

--- Restore the items that were in hands before clear_hands was called.
-- @param data table ELoot data state
function M.return_hands(data)
    -- Nothing to do if hands haven't changed
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (data.right_hand and data.right_hand.id == rh.id) and
       (data.left_hand and data.left_hand.id == lh.id) then
        return
    end

    -- Restore right hand
    if data.right_hand and data.right_hand.id and data.right_hand.id ~= rh.id then
        local ready_item = nil
        for k, v in pairs(ReadyList.ready_list) do
            if data.original_readylist and contains(data.original_readylist, k) and v.id == data.right_hand.id then
                ready_item = k
                break
            end
        end
        if ready_item then
            M.return_ready_list(ready_item, data.right_hand, data)
        else
            M.drag(data.right_hand, "right", data)
        end
    end

    -- Restore left hand
    if data.left_hand and data.left_hand.id and data.left_hand.id ~= lh.id then
        local ready_item = nil
        for k, v in pairs(ReadyList.ready_list) do
            if data.original_readylist and contains(data.original_readylist, k) and v.id == data.left_hand.id then
                ready_item = k
                break
            end
        end
        if ready_item then
            M.return_ready_list(ready_item, data.left_hand, data)
        else
            M.drag(data.left_hand, "left", data)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 13. return_ready_list (lines 3417-3427)
-- Restore a ready-list item to hand.
-- ---------------------------------------------------------------------------

--- Restore a ready-list item to hand via the "ready" command.
-- @param ready_item string ready list key
-- @param item GameObj the item to restore
-- @param data table ELoot data state
-- @return boolean true on success
function M.return_ready_list(ready_item, item, data)
    if not ReadyList.ready_list[ready_item] then return true end

    for _ = 1, 10 do
        Util().get_res("ready " .. Util().fix_item_key(tostring(ready_item)), data.get_regex, data)
        pause(0.2)
        if Util().in_hand(item) then return true end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 14. single_drag (lines 3429-3488)
-- Drag a single item from hand into the best container.
-- ---------------------------------------------------------------------------

--- Drag a single held item into a container, trying sacks in priority order.
-- @param item GameObj the item to store
-- @param phase_thing boolean if true, phase boxes after storing
-- @param data table ELoot data state
function M.single_drag(item, phase_thing, data)
    if phase_thing == nil then phase_thing = true end
    Util().msg({ type = "debug", text = "single_drag item: " .. tostring(item) }, data)

    if not item or (item.name and item.name == "Empty") then return end

    -- Try box-to-disk first
    if M.single_drag_box(item, data) then return end

    local stored = false

    -- Try sacks in priority order: item-specific, default, overflow, secondary
    local containers = {
        item.type and StowList.stow_list[item.type] or nil,
        StowList.stow_list.default,
        StowList.stow_list.overflow_container,
        StowList.stow_list.secondary_overflow,
    }

    local function try_store()
        for index, bag in ipairs(containers) do
            if stunned() then
                Util().wait_rt()
                return false  -- signal retry
            end

            if contains(data.sacks_full, bag) then
                -- skip full sacks
            elseif not bag then
                if index == 2 then
                    Util().msg({ type = "yellow", text = " No default container identified. This shouldn't happen." }, data)
                    Util().msg({ type = "yellow", text = "   Check your STOW settings. Exiting" }, data)
                    error("eloot: no default container")
                elseif index == 3 then
                    Util().msg({ type = "info", text = " Skipping primary overflow. No container identified." }, data)
                elseif index == 4 then
                    Util().msg({ type = "info", text = " Skipping secondary overflow. No container identified." }, data)
                end
            else
                local result = M.store_item(bag, item, false, data)
                if result then
                    if phase_thing then
                        Util().box_phase(item, data)
                    end
                    stored = true
                    return true
                end
            end
        end
        return true  -- exhausted all containers, stop retrying
    end

    -- Retry loop (handles stun interruption)
    while not try_store() do end

    -- If not stored, pause script for manual handling
    if not stored then
        -- Special case: gold ingot at locksmith
        local room_tags = Room.current and Room.current.tags or {}
        local at_locksmith = false
        for _, tag in ipairs(room_tags) do
            if tag:find("[Ll]ocksmith") or tag:find("[Ll]ocksmith pool") then
                at_locksmith = true
                break
            end
        end

        if at_locksmith then
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local ingot = nil
            if rh.name and rh.name:find("gold ingot") then ingot = rh end
            if lh.name and lh.name:find("gold ingot") then ingot = lh end
            if ingot then
                local Sell = require("gs.eloot.sell")
                if Sell.handle_ingot then
                    Sell.handle_ingot(ingot, data)
                    return
                end
            end
        end

        Util().msg({ type = "info", text = " Failed to store the " .. (item.name or "?") .. "." }, data)
        Util().msg({ type = "info", text = " Pausing the script to handle it yourself" }, data)
        Util().msg({ type = "info", text = " ;unpause " .. (Script.current and Script.current.name or "eloot") .. " after addressing to continue!" }, data)
        Script.current:pause()
    end
end

-- ---------------------------------------------------------------------------
-- 15. single_drag_box (lines 3490-3519)
-- Drag a box into the character's disk.
-- ---------------------------------------------------------------------------

--- Try to store a box in a disk (character's disk first, then group disks).
-- @param item GameObj the box item
-- @param data table ELoot data state
-- @return boolean true if box was stored in a disk
function M.single_drag_box(item, data)
    Util().msg({ type = "debug", text = "single_drag_box item: " .. tostring(item) }, data)

    if not item or not item.type or item.type ~= "box" then return false end
    if not data.settings.use_disk and not data.settings.use_disk_group then return false end

    -- Check if any disk has room
    local has_room = false
    for _, full in pairs(data.disk_full) do
        if not full then has_room = true; break end
    end
    if not has_room then return false end

    -- If not using group disks, check own disk specifically
    if not data.settings.use_disk_group then
        if not data.disk or data.disk_full[GameState.name] then return false end
    end

    -- Wait for own disk if it exists
    if data.disk then
        Util().wait_for_disk(data, M)
    end

    -- Sort disks: own disk first
    local disks = Group and Group.disks and Group.disks() or {}
    table.sort(disks, function(a, b)
        if a.name == GameState.name then return true end
        if b.name == GameState.name then return false end
        return false
    end)

    for _, disk in ipairs(disks) do
        if not data.disk_full[disk.name] then
            -- Confirm disk is present
            if Disk.find_by_name and Disk.find_by_name(disk.name) then
                local result = M.store_item(GameObj[disk.id], item, false, data)
                if result then return true end

                -- Didn't fit
                if #disks > 1 then
                    Util().msg({ type = "info", text = " The " .. tostring(item) .. " won't fit in the " .. disk.name .. " disk. Trying a different disk." }, data)
                end
                data.disk_full[disk.name] = true
            end
        end
    end

    Util().msg({ type = "info", text = " The " .. tostring(item) .. " won't fit in any disk(s). Trying a different container." }, data)
    return false
end

-- ---------------------------------------------------------------------------
-- 16. single_loot (lines 3521-3563)
-- Loot a single item from the ground.
-- ---------------------------------------------------------------------------

--- Loot a single item from the room floor into a container.
-- @param item GameObj the item to loot
-- @param data table ELoot data state
-- @return boolean true on success
function M.single_loot(item, data)
    Util().msg({ type = "debug", text = "single_loot item: " .. tostring(item) }, data)
    if not item then return false end

    -- Find the best bag; fall back to default if specific bag is full
    local bag = item.type and StowList.stow_list[item.type] or nil
    if bag and contains(data.sacks_full, bag) then bag = nil end
    if not bag then bag = StowList.stow_list.default end
    if bag and contains(data.sacks_full, bag) then bag = nil end

    if not bag then
        M.single_drag(item, true, data)
        return true
    end

    local lines = Util().get_command("loot #" .. item.id, data.put_regex, nil, data)

    -- Check for auto-closer (container was closed)
    local bag_id = find_match(lines, 'You can\'t put your .- in the <a exist="(%d+)"')
    if bag_id then
        local inv = GameObj.inv()
        local closed_bag = nil
        for _, obj in ipairs(inv) do
            if obj.id == bag_id then closed_bag = obj; break end
        end

        if closed_bag then
            local keys = GameObj.containers()
            if keys[closed_bag.id] and type(closed_bag.contents) == "table" then
                if not contains(data.settings.auto_close, closed_bag.name) then
                    table.insert(data.settings.auto_close, closed_bag.name)
                end
                M.open_single_container(closed_bag, data)
                Util().msg({ type = "info", text = " " .. (closed_bag.name or "?") .. " must be an autocloser, adding to list." }, data)
                Settings().save_profile(data)
            end
        end
    end

    -- Wait for item to land in a container
    for _ = 1, 20 do
        if not Util().in_hand(item) then
            -- Check specific container
            local type_bag = item.type and StowList.stow_list[item.type] or nil
            if type_bag and type_bag.contents then
                for _, obj in ipairs(type_bag.contents) do
                    if obj.id == item.id then return true end
                end
            end
            -- Check default container
            local def = StowList.stow_list.default
            if def and def.contents then
                for _, obj in ipairs(def.contents) do
                    if obj.id == item.id then return true end
                end
            end
            -- Skins may not appear in contents
            if item.type and item.type:find("skin") then return true end
        end
        pause(0.1)
    end

    -- Edge case: treasure system mismatch — check all inventory
    local Sell = require("gs.eloot.sell")
    if Sell.check_inventory then
        local all_items = Sell.check_inventory(data)
        for _, obj in ipairs(all_items) do
            if obj.id == item.id then return true end
        end
    end

    -- Still here — loot manually
    M.single_drag(item, true, data)
    return true
end

-- ---------------------------------------------------------------------------
-- 17. store_item (lines 3565-3623)
-- Store an item in a specific container.
-- ---------------------------------------------------------------------------

--- Store an item into a container, handling closed/full/crumbly edge cases.
-- @param bag GameObj the target container
-- @param item GameObj the item to store
-- @param is_skinner boolean true if bag is a weapon displayer (no contents)
-- @param data table ELoot data state
-- @return boolean true if item was stored
function M.store_item(bag, item, is_skinner, data)
    is_skinner = is_skinner or false
    Util().msg({ type = "debug", text = "store_item bag: " .. tostring(bag) .. " | item: " .. tostring(item) }, data)

    if not item or (item.name and item.name == "Empty") then return false end

    for _ = 1, 5 do
        local lines = Util().get_command("_drag #" .. item.id .. " #" .. bag.id, data.put_regex, nil, data)

        -- Container closed? Open and retry
        if any_match(lines, "You can't.*It's closed!") then
            local keys = GameObj.containers()
            if keys[bag.id] and type(bag.contents) == "table" then
                -- Auto-closer detection
                if not contains(data.settings.auto_close, bag.name) then
                    table.insert(data.settings.auto_close, bag.name)
                end
                Util().msg({ type = "info", text = " " .. (bag.name or "?") .. " must be an autocloser, adding to list." }, data)
                Settings().save_profile(data)
            end
            Util().get_res("open #" .. bag.id, data.silent_open, data)
            lines = Util().get_command("_drag #" .. item.id .. " #" .. bag.id, data.put_regex, nil, data)
        end

        -- Item gone / not ours — treat as success (not our problem)
        if any_match_multi(lines, {
            "You are unable to handle",
            "That is not yours",
            "Hey, that belongs to",
            "Get what",
            "I could not find what you were referring",
        }) then
            return true
        end

        -- Can't hold it (cursed, etc.)
        if any_match(lines, "put something that you can't hold") then
            Util().unlootable(item, data)
            return true
        end

        -- Container full
        if any_match(lines, "won't fit") then
            if not item.name or not item.name:find("gold ingot") then
                Util().msg({ type = "debug", text = "sacks_full(" .. (bag.name or "?") .. ") - item: " .. tostring(item) }, data)
                table.insert(data.sacks_full, bag)
            end
            return false
        end

        -- Crumbly item
        if any_match_multi(lines, { "crumbles? and decays? away", "crumbles? into a pile of dust" }) then
            Util().msg({ type = "info", text = " This item was crumbly, adding to list" }, data)
            table.insert(data.settings.crumbly, item.name)
            Settings().save_profile(data)
            return true
        end

        -- Make sure container is open if contents aren't loaded
        if not is_skinner and type(bag.contents) ~= "table" then
            M.open_single_container(bag, data)
        end

        -- Wait for item to appear in container
        for _ = 1, 20 do
            if not Util().in_hand(item) then
                if bag.contents then
                    for _, obj in ipairs(bag.contents) do
                        if obj.id == item.id then return true end
                    end
                end
                -- Weapon displayers don't track contents
                if is_skinner then return true end
            end
            pause(0.1)
        end

        waitrt()
    end

    -- Exhausted retries
    return false
end

-- ---------------------------------------------------------------------------
-- 18. stow_ready_list (lines 3625-3640)
-- Stow an item via the ready-list store command.
-- ---------------------------------------------------------------------------

--- Stow an item back into its ready-list location.
-- @param ready_item string ready list key
-- @param item GameObj the item to stow
-- @param data table ELoot data state
-- @return boolean true on success
function M.stow_ready_list(ready_item, item, data)
    if not ReadyList.ready_list[ready_item] then return true end

    -- Open the target sheath if needed
    local store_cmd = ReadyList.store_list and ReadyList.store_list[ready_item] or ""
    if store_cmd:find("put in sheath") then
        M.open_single_container(ReadyList.ready_list.sheath, data)
    elseif store_cmd:find("put in secondary") then
        M.open_single_container(ReadyList.ready_list.secondary_sheath, data)
    end

    for _ = 1, 10 do
        Util().get_res("store " .. Util().fix_item_key(tostring(ready_item)), data.put_regex, data)
        pause(0.2)
        if not Util().in_hand(item) then return true end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 19. ensure_items (lines 1894-1920)
-- Ensure a configured item exists in inventory and is tracked.
-- ---------------------------------------------------------------------------

--- Find a configured item in inventory and record it in a tracking list.
-- @param opts table { key = string, list = table, inventory = table|nil, check_hidden = bool }
-- @param data table ELoot data state
function M.ensure_items(opts, data)
    Util().msg({ type = "debug" }, data)

    local key = opts.key
    local list = opts.list
    local inventory = opts.inventory or GameObj.inv()
    local check_hidden = opts.check_hidden or false

    local item_name = data.settings[key]
    if not item_name or tostring(item_name) == "" then return end
    item_name = tostring(item_name)

    -- Check if already recorded AND name still matches
    local recorded = list[key]
    if recorded and recorded.name and recorded.name:find(item_name, 1, true) then
        return
    end

    -- Search inventory for the item
    local found = nil
    for _, obj in ipairs(inventory) do
        if obj.name and obj.name:lower():find("%f[%w]" .. item_name:lower() .. "%f[%W]") then
            found = obj
            break
        end
    end

    if found then
        list[key] = found
    elseif check_hidden then
        M.find_sheath_hidden(item_name, key, data)
    else
        list[key] = nil
    end

    if not list[key] then
        -- Only warn if not called from set_inventory (caller can handle it)
        Util().msg({ text = " Can't find " .. key .. ": " .. item_name .. ". Please check ;eloot setup.", space = true }, data)
    end
end

-- ---------------------------------------------------------------------------
-- 20. get_weapon_inv (lines 1922-1939)
-- Get weapon inventory for skinning.
-- ---------------------------------------------------------------------------

--- Populate the weapon inventory list for skinning weapon lookup.
-- @param data table ELoot data state
function M.get_weapon_inv(data)
    local exist_pattern = '<a exist="(.-)" noun="(.-)">(.-)</a>'

    local lines = Util().get_command(
        "inventory full weapons",
        { "You are currently wearing:", "You are carrying no weapons at this time%." },
        { silent = true, quiet = true },
        data
    )

    for _, line in ipairs(lines) do
        for id, noun, name in line:gmatch(exist_pattern) do
            local already = false
            for _, w in ipairs(data.weapon_inv) do
                if w.id == id then already = true; break end
            end
            if not already then
                table.insert(data.weapon_inv, GameObj.new(id, noun, name))
            end
        end
    end

    -- Include what's currently in hands
    local rh = GameObj.right_hand()
    if rh and rh.id and checkright() then
        table.insert(data.weapon_inv, rh)
    end
    local lh = GameObj.left_hand()
    if lh and lh.id and checkleft() then
        table.insert(data.weapon_inv, lh)
    end
end

-- ---------------------------------------------------------------------------
-- 21. find_bloodtooth (lines 1941-1962)
-- Find blood band/bracer combo.
-- ---------------------------------------------------------------------------

--- Detect bloodtooth band + bracer combo in inventory.
-- @param data table ELoot data state
function M.find_bloodtooth(data)
    if not data.settings.use_bloodbands then return end

    local bracer_found = false

    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item.name and (item.name:find("bands") or item.name:find("bracer")) then
            local lines = Util().get_command(
                "analyze #" .. item.id,
                { "You analyze" },
                { silent = true, quiet = true },
                data
            )

            if any_match(lines, "magically drains some of your blood") then
                if item.name:find("bracer") then
                    bracer_found = true
                end
                if item.name:find("bands") then
                    data.blood_band = item
                end
            end

            if bracer_found and data.blood_band then break end
        end
    end

    data.settings.use_bloodbands = (bracer_found and data.blood_band ~= nil)
end

-- ---------------------------------------------------------------------------
-- 22. find_coin_containers (lines 1964-1996)
-- Find weightless coin containers.
-- ---------------------------------------------------------------------------

--- Locate coin hand / coin bag / gambling kit in inventory.
-- @param data table ELoot data state
function M.find_coin_containers(data)
    local coin_name = data.settings.coin_hand_name
    if not coin_name or tostring(coin_name) == "" then return end
    coin_name = tostring(coin_name)

    -- Check worn inventory first
    local inv = GameObj.inv()
    for _, obj in ipairs(inv) do
        if obj.name and obj.name:lower():find("%f[%w]" .. coin_name:lower() .. "%f[%W]") then
            data.coin_hand = obj
            break
        end
    end

    -- If not found as worn, check inside containers
    if not data.coin_hand then
        for _, item in ipairs(inv) do
            local keys = GameObj.containers()
            if keys[item.id] then
                M.open_single_container(item, data)

                if item.contents then
                    for _, thing in ipairs(item.contents) do
                        if thing.name and thing.name:lower():find("%f[%w]" .. coin_name:lower() .. "%f[%W]") then
                            data.coin_hand = thing
                            data.coin_container = item
                            break
                        end
                    end
                end
                if data.coin_hand then break end
            end
        end
    end

    -- Bail if not found or if it matches "coin hand" pattern (the item itself)
    if not data.coin_hand then return end
    if not data.coin_hand.name:find("%f[%w]coin%f[%W].*%f[%w]hand%f[%W]")
       and not data.coin_hand.name:find("%f[%w]hand%f[%W].*%f[%w]coin%f[%W]") then
        -- Not a "coin hand" — analyze to determine type
        local lines = Util().get_command(
            "analyze #" .. data.coin_hand.id,
            { "You analyze" },
            { silent = true, quiet = true },
            data
        )

        if any_match(lines, 'noun must remain "pouch," "bag," or "purse," immediately preceded by the word "coin."') then
            data.coin_bag = data.coin_hand
        elseif any_match(lines, "Gambling Kit") then
            data.gambling_kit = data.coin_hand
        end
    end
end

-- ---------------------------------------------------------------------------
-- 23. find_sheath_hidden (lines 1998-2013)
-- Find hidden sheath items.
-- ---------------------------------------------------------------------------

--- Find a hidden sheath by pulling it out momentarily, then pushing it back.
-- @param sheath_name string the name to search for
-- @param item_type string the setting key (e.g. "skin_sheath")
-- @param data table ELoot data state
function M.find_sheath_hidden(sheath_name, item_type, data)
    Util().msg({ type = "debug", text = item_type .. " not found but is in setup" }, data)

    local lines = Util().get_command(
        "pull my sheath",
        { "You reach down", "I'm afraid that" },
        { silent = true, quiet = true },
        data
    )
    Util().msg({ type = "debug", text = "Is sheath hidden? : " .. table.concat(lines, " | ") }, data)

    if any_match(lines, "You reach down") then
        -- Sheath was hidden, now exposed — find it
        local inv = GameObj.inv()
        for _, obj in ipairs(inv) do
            if obj.name and obj.name:lower():find("%f[%w]" .. sheath_name:lower() .. "%f[%W]") then
                ReadyList.ready_list[item_type] = obj
                break
            end
        end

        -- Push it back
        Util().get_command(
            "push my " .. sheath_name,
            { "You reach down", "I'm afraid that you can't pull that" },
            { silent = true, quiet = true },
            data
        )
    end
end

-- ---------------------------------------------------------------------------
-- 24. set_inventory (lines 2015-2075)
-- Main inventory initialization.
-- ---------------------------------------------------------------------------

--- Full startup inventory initialization: flags, ready/stow lists,
-- containers, weapons, coin hand, charms, blood band, disk, validation.
-- @param data table ELoot data state
function M.set_inventory(data)
    -- Check account type
    data.account_type = Account and Account.subscription and Account.subscription() or "unknown"

    -- Disable flag righthand / lefthand
    Util().get_command("flag righthand off", { "You will not attempt to pick%s?up treasure using your right hand" }, { silent = true, quiet = true }, data)
    Util().get_command("flag lefthand off", { "You will not attempt to pick%s?up treasure using your left hand" }, { silent = true, quiet = true }, data)

    -- Populate ReadyList and StowList if not already done
    if not ReadyList.checked() then
        ReadyList.check({ silent = true, quiet = true })
    end
    if not StowList.checked() then
        StowList.check({ silent = true, quiet = true })
    end

    -- Remove eloot-specific keys so we can re-find them cleanly
    ReadyList.ready_list.skin_weapon       = nil
    ReadyList.ready_list.skin_weapon_blunt = nil
    ReadyList.ready_list.skin_sheath       = nil
    ReadyList.ready_list.skin_sheath_blunt = nil

    StowList.stow_list.overflow_container  = nil
    StowList.stow_list.secondary_overflow  = nil
    StowList.stow_list.appraisal_container = nil

    -- Find stow containers: overflow, secondary overflow, appraisal
    M.ensure_items({ key = "overflow_container",  list = StowList.stow_list }, data)
    M.ensure_items({ key = "secondary_overflow",  list = StowList.stow_list }, data)
    M.ensure_items({ key = "appraisal_container", list = StowList.stow_list }, data)

    -- Find skin sheaths
    if data.settings.skin_enable then
        M.ensure_items({ key = "skin_sheath",       list = ReadyList.ready_list, check_hidden = true }, data)
        M.ensure_items({ key = "skin_sheath_blunt", list = ReadyList.ready_list, check_hidden = true }, data)
    end

    -- Open all stow containers so their contents are available
    local opened = {}
    for _, item in pairs(StowList.stow_list) do
        if item and item.id and not opened[item.id] then
            M.open_single_container(item, data)
            opened[item.id] = true
        end
    end

    -- Get weapon inventory for skinning
    M.get_weapon_inv(data)

    -- Find skinning weapons
    M.ensure_items({ key = "skin_weapon",       list = ReadyList.ready_list, inventory = data.weapon_inv }, data)
    M.ensure_items({ key = "skin_weapon_blunt", list = ReadyList.ready_list, inventory = data.weapon_inv }, data)

    -- Weightless coin containers
    M.find_coin_containers(data)

    -- Fossil charm
    local charm_name = data.settings.charm_name
    if charm_name and tostring(charm_name) ~= "" then
        charm_name = tostring(charm_name)
        local inv = GameObj.inv()
        for _, obj in ipairs(inv) do
            if obj.name and obj.name:lower():find("%f[%w]" .. charm_name:lower() .. "%f[%W]") then
                data.charm = obj
                break
            end
        end
    end

    -- Blood band
    M.find_bloodtooth(data)

    -- Eonake gauntlet
    local inv = GameObj.inv()
    for _, obj in ipairs(inv) do
        if obj.name and obj.name:lower():find("%f[%w]eonake gauntlet%f[%W]") then
            data.gauntlet = obj
            break
        end
    end

    -- Disk usage
    Util().disk_usage(data)

    -- Close containers if keep_closed
    M.close_sell_containers(data)

    -- Validate setup
    Settings().validate_setup(data)
end

-- ---------------------------------------------------------------------------
-- 25. set_selling_containers (lines 2077-2104)
-- Configure selling containers for a given item type.
-- ---------------------------------------------------------------------------

--- Build the list of containers to search when selling a given item type.
-- @param item_type string|nil loot category (e.g. "gem", "scroll")
-- @param data table ELoot data state
-- @return table array of GameObj containers (deduplicated)
function M.set_selling_containers(item_type, data)
    Util().msg({ type = "debug" }, data)

    local container_array = {}
    local seen = {}

    local function add(obj)
        if obj and not seen[obj.id] then
            seen[obj.id] = true
            table.insert(container_array, obj)
        end
    end

    -- Add the specific type container if listed in sell_container
    if item_type and contains(data.settings.sell_container, item_type) then
        local c = StowList.stow_list[item_type]
        if c then add(c) end
    end

    -- Add default container
    if contains(data.settings.sell_container, "default") then
        if StowList.default then
            add(StowList.default)
        end
    end

    -- Handle overflow containers
    if contains(data.settings.sell_container, "overflow") then
        M.ensure_items({ key = "overflow_container", list = StowList.stow_list }, data)
        local c1 = StowList.stow_list.overflow_container
        if c1 then add(c1) end

        M.ensure_items({ key = "secondary_overflow", list = StowList.stow_list }, data)
        local c2 = StowList.stow_list.secondary_overflow
        if c2 then add(c2) end
    end

    return container_array
end

return M
