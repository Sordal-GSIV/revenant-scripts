--- tpick loot and container management module
-- Gathering items from boxes, routing to containers, locksmith supplies,
-- encumbrance handling.
-- Ported from tpick.lic lines 3918-3958, 4341-4375, 4787-4825,
-- 5073-5101, 5101-5186, 5252-5312, 5871-5907.
local M = {}

local util  -- set by wire()

function M.wire(funcs)
    util = funcs.util
end

---------------------------------------------------------------------------
-- Helper: update_box_for_window wrapper
---------------------------------------------------------------------------
local function update_box_for_window(settings)
    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
end

---------------------------------------------------------------------------
-- coins_from_boxes_comma_nonsense (lines 5090-5099)
-- After picking up silver coins, wait an appropriate amount based on amount.
---------------------------------------------------------------------------
function M.coins_from_boxes_comma_nonsense(vars)
    if (vars["Silvers From Box"] or 0) < 625 then
        pause(0.01)
    else
        waitrt()
        pause(1)
        waitrt()
    end
    waitrt()
end

---------------------------------------------------------------------------
-- gather_stuff (lines 5101-5167)
-- Get an item from the current box and route to the correct container.
-- Handles coins (with fossil charm), cursed items, and loot stats.
---------------------------------------------------------------------------
function M.gather_stuff(vars, settings)
    local load_data = settings.load_data
    local stats_data = settings.stats_data
    waitrt()

    local item = vars["Current Item"]
    if not item then return end

    -- ---- Silver coins ----
    if item.name and string.find(item.name, "coins") then
        vars["Silvers From Box"] = 0

        if load_data["Fossil Charm"] and #load_data["Fossil Charm"] > 1 then
            -- Use fossil charm to gather coins
            fput("point my " .. load_data["Fossil Charm"] .. " at #" .. vars["Current Box"].id)
            while true do
                local line = get()
                if line and string.find(line, "You summon .* They locate a pile of .* coin") then
                    local amount_str = line:match("a pile of ([%d,]+) coin")
                    if amount_str then
                        vars["Silvers From Box"] = tonumber(amount_str:gsub(",", "")) or 0
                    end
                    break
                end
            end
        else
            -- Manual coin pickup loop
            vars["Got All Coins"] = false
            while not vars["Got All Coins"] do
                fput("get #" .. item.id)
                while true do
                    local line = get()
                    if not line then break end

                    local remaining = line:match("You gather the remaining ([%d,]+) coins?")
                    if remaining then
                        vars["Silvers From Box"] = tonumber(remaining:gsub(",", "")) or 0
                        M.coins_from_boxes_comma_nonsense(vars)
                        vars["Got All Coins"] = true
                        break
                    end

                    local load_limited = line:match("^You can only collect ([%d,]+) of the coins due to your load%.")
                    if load_limited then
                        vars["Silvers From Box"] = tonumber(load_limited:gsub(",", "")) or 0
                        util.tpick_silent(true, "You can't carry anymore silvers!", settings)
                        M.coins_from_boxes_comma_nonsense(vars)
                        vars["Got All Coins"] = true
                        break
                    end

                    if string.find(line, "^You cannot hold any more silvers%.") then
                        util.tpick_silent(true, "You can't carry anymore silvers!", settings)
                        vars["Got All Coins"] = true
                        break
                    end

                    local partial = line:match("^You gather ([%d,]+) of the coins?")
                    if partial then
                        vars["Silvers From Box"] = tonumber(partial:gsub(",", "")) or 0
                        M.coins_from_boxes_comma_nonsense(vars)
                        break
                    end
                end
            end
        end

        -- Update silver stats
        if stats_data then
            stats_data["Loot Session"]["Silver"] = (stats_data["Loot Session"]["Silver"] or 0)
                + (vars["Silvers From Box"] or 0)
            if load_data["Track Loot"] == "Yes" then
                stats_data["Loot Total"]["Silver"] = (stats_data["Loot Total"]["Silver"] or 0)
                    + (vars["Silvers From Box"] or 0)
            end
        end

    -- ---- Non-coin items ----
    else
        if not vars["cannot_pick_up_items"] then
            vars["cannot_pick_up_items"] = {}
        end
        local add_stats = true

        -- Skip items we already know we can't pick up
        local dominated = false
        for _, skip_id in ipairs(vars["cannot_pick_up_items"]) do
            if skip_id == item.id then
                dominated = true
                break
            end
        end

        if not dominated then
            if vars["Picking Up"] then
                fput("get #" .. item.id)
                wait_until(function() return checkleft() end)
                util.tpick_put_stuff_away(vars, settings)
            else
                local result = dothistimeout(
                    "get #" .. item.id, 2,
                    { "You pick up", "You can't", "You remove" }
                )
                if result and (string.find(result, "You pick up") or string.find(result, "You remove")) then
                    -- success
                elseif result and string.find(result, "You can't") then
                    add_stats = false
                    table.insert(vars["cannot_pick_up_items"], item.id)
                end
            end

            if add_stats and stats_data then
                local item_name = item.name or "unknown"
                stats_data["Loot Session"][item_name] = (stats_data["Loot Session"][item_name] or 0) + 1
                local item_type = item.type or ""
                local skip_types = { clothing = true, junk = true, food = true, herb = true,
                                     cursed = true, toy = true, ammo = true }
                if not skip_types[item_type] and load_data["Track Loot"] == "Yes" then
                    stats_data["Loot Total"][item_name] = (stats_data["Loot Total"][item_name] or 0) + 1
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- tpick_gather_the_loot (lines 5169-5184)
-- Wrapper: skip cursed items and boxes, gather item, bundle vials, stow.
---------------------------------------------------------------------------
function M.tpick_gather_the_loot(vars, settings)
    local load_data = settings.load_data
    local item = vars["Current Item"]
    if not item then return end

    waitrt()

    local item_type = item.type or ""
    -- Skip cursed items and boxes
    if string.find(item_type, "cursed") or item_type == "box" then
        return
    end

    M.gather_stuff(vars, settings)
    waitrt()

    local item_name = item.name or ""
    if not string.find(item_name, "coins") and not string.find(item_type, "cursed") and item_type ~= "box" then
        -- Wait up to 1 second for item to appear in hand
        for _ = 1, 10 do
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.id == item.id) or (lh and lh.id == item.id) then
                break
            end
            pause(0.1)
        end

        -- Auto-bundle vials if enabled
        if load_data["Auto Bundle Vials"] == "Yes" and string.find(item_name, "vial") then
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and string.find(rh.name or "", "vial")) or (lh and string.find(lh.name or "", "vial")) then
                M.tpick_bundle_vials(vars, settings)
            end
        end

        util.tpick_put_stuff_away(vars, settings)
    end

    waitrt()
end

---------------------------------------------------------------------------
-- tpick_bundle_vials (lines 3918-3956)
-- Bundle acid vials into locksmith container after disarming.
---------------------------------------------------------------------------
function M.tpick_bundle_vials(vars, settings)
    if vars["Start Sorter"] then
        Script.run("sorter")
    end

    -- Identify which hand holds the vial
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and string.find(rh.name or "", "vial") then
        vars["Current Vial"] = rh.id
    elseif lh and string.find(lh.name or "", "vial") then
        vars["Current Vial"] = lh.id
    end

    -- Stow box if in solo/other mode
    if vars["Picking Mode"] == "solo" or vars["Picking Mode"] == "other" then
        util.tpick_stow_box(vars)
    end
    util.tpick_put_stuff_away(vars, settings)

    -- Wait for both hands to be empty
    wait_until(function()
        return not checkright() and not checkleft()
    end)

    -- Remove locksmith container
    local ls_container = vars["Locksmith's Container"]
    if not ls_container then
        util.tpick_silent(true, "I could not find your locksmith's container to bundle a vial inside of it.", settings)
        return
    end

    fput("remove #" .. ls_container.id)
    for _ = 1, 20 do
        if checkright() then break end
        pause(0.1)
    end

    if not checkright() then
        fput("get #" .. ls_container.id)
        for _ = 1, 15 do
            if checkright() then break end
            pause(0.1)
        end
    end

    if not checkright() then
        util.tpick_silent(true, "I could not find your locksmith's container to bundle a vial inside of it.", settings)
    else
        fput("get #" .. vars["Current Vial"])
        wait_until(function() return checkleft() end)
        fput("bundle")
        fput("wear #" .. ls_container.id)
        vars["Vials Remaining"] = (vars["Vials Remaining"] or 0) + 1
        if vars["Vials Remaining"] > 100 then
            vars["Vials Remaining"] = 100
        end
        update_box_for_window(settings)
        wait_until(function() return not checkright() end)
    end

    -- Re-get box if in solo/other mode
    if vars["Picking Mode"] == "solo" or vars["Picking Mode"] == "other" then
        util.tpick_get_box(vars)
        wait_until(function() return checkright() end)
    end
end

---------------------------------------------------------------------------
-- fill_up_locksmith_container (lines 4341-4373)
-- Navigate to bank, deposit, withdraw, go to locksmith shop, buy toolkits,
-- bundle into locksmith container.
---------------------------------------------------------------------------
function M.fill_up_locksmith_container(vars, settings)
    local load_data = settings.load_data

    -- Move out if there's an 'out' exit
    if checkpaths and checkpaths("out") then
        fput("go out")
    end

    -- Go to bank, deposit all, withdraw funds
    Script.run("go2", { "bank", "--disable-confirm" })
    wait_while(function() return running("go2") end)
    if hidden and hidden() then fput("unhide") end
    fput("depo all")
    fput("withdraw 1000")

    -- Navigate to nearest locksmith shop
    local nearest = Room.current and Room.current.find_nearest_by_tag and
        Room.current.find_nearest_by_tag("locksmith shop")
    if nearest then
        Script.run("go2", { tostring(nearest), "--disable-confirm" })
        wait_while(function() return running("go2") end)
    end

    waitrt()

    -- Read the order list to find toolkit order number
    fput("order")
    while true do
        local line = get()
        if not line then break end
        -- Match toolkit/leather case in order listing
        local order_num = line:match("(%d+).*locksmith's")
            or line:match("(%d+).*tool kit")
            or line:match("(%d+).*toolkit")
            or line:match("(%d+).*leather case")
        if order_num then
            vars["Toolkit Order Number"] = order_num
        end
        if string.find(line, "You can APPRAISE") then
            break
        end
    end

    -- Stow everything
    util.tpick_put_stuff_away(vars, settings)
    wait_until(function()
        return not checkright() and not checkleft()
    end)

    -- Remove locksmith container into right hand
    local ls_container = vars["Locksmith's Container"]
    if ls_container then
        while not checkright() do
            waitrt()
            fput("remove #" .. ls_container.id)
            pause(0.2)
        end
    end

    -- Buy and bundle a toolkit
    M.buy_locksmith_pouch(vars, settings)

    -- If still low, buy another
    if (vars["Putty Remaining"] or 0) < 50 or (vars["Cotton Remaining"] or 0) < 50 then
        M.buy_locksmith_pouch(vars, settings)
    end

    -- Wear the locksmith container again
    if ls_container then
        fput("wear #" .. ls_container.id)
    end

    -- Re-check container contents
    if settings.check_lock_smiths_container then
        settings.check_lock_smiths_container()
    end
end

---------------------------------------------------------------------------
-- buy_locksmith_pouch (lines 4978-4986)
-- Order a toolkit, open it, bundle contents into locksmith container, drop empty.
---------------------------------------------------------------------------
function M.buy_locksmith_pouch(vars, settings)
    fput("order " .. (vars["Toolkit Order Number"] or "1"))
    fput("buy")
    wait_until(function() return checkleft() end)
    local lh = GameObj.left_hand()
    if lh then
        fput("open #" .. lh.id)
    end
    fput("bundle")
    -- The empty pouch is now in left hand; drop it
    lh = GameObj.left_hand()
    if lh then
        vars["Current Box"] = lh
        util.tpick_drop_box(vars)
    end
end

---------------------------------------------------------------------------
-- encumbrance_check (lines 5073-5088)
-- If over 99% encumbered, deposit silvers and return.
-- Supports "Yes" (bank trip) or a custom script name.
---------------------------------------------------------------------------
function M.encumbrance_check(vars, settings)
    local load_data = settings.load_data
    if not percentencumbrance or percentencumbrance() <= 99 then
        return
    end

    util.tpick_silent(nil,
        "Your settings indicate you want to deposit silvers when encumbered, "
        .. "and you are encumbered, so we are depositing silvers.", settings)

    vars["Starting Room Number"] = Room.id

    -- If the setting is not simply "yes", run it as a custom script first
    local auto_deposit = load_data["Auto Deposit Silvers"] or ""
    if not string.find(string.lower(auto_deposit), "yes") then
        local script_commands = {}
        for word in auto_deposit:gmatch("%S+") do
            table.insert(script_commands, word)
        end
        if #script_commands > 0 then
            local script_name = table.remove(script_commands, 1)
            Script.run(script_name, script_commands)
            wait_while(function() return running(script_name) end)
        end
    end

    -- Go to bank and deposit
    Script.run("go2", { "bank", "--disable-confirm" })
    wait_while(function() return running("go2") end)
    fput("depo all")

    -- Return to starting room
    Script.run("go2", { tostring(vars["Starting Room Number"]) })
    wait_while(function() return running("go2") end)
end

---------------------------------------------------------------------------
-- get_vials_and_stuff (lines 4787-4823)
-- Get a vial from locksmith container for plate trap disarming.
-- If no vials found, handle fallback (wedge, 407, or error).
---------------------------------------------------------------------------
function M.get_vials_and_stuff(vars, settings)
    local load_data = settings.load_data
    wait_until(function() return checkrt() == 0 end)

    -- Try up to 3 times to get a vial
    for _ = 1, 3 do
        waitrt()
        wait_until(function() return checkrt() == 0 end)
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_vial = (rh and string.find(rh.name or "", "vial"))
            or (lh and string.find(lh.name or "", "vial"))
        if not has_vial then
            local ls_container = vars["Locksmith's Container"]
            if ls_container then
                fput("get vial from #" .. ls_container.id)
                pause(0.2)
            end
        end
    end

    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local has_vial = (rh and string.find(rh.name or "", "vial"))
        or (lh and string.find(lh.name or "", "vial"))

    if not has_vial then
        util.tpick_silent(true,
            "No vials found bundled in your locksmith's container and no loose vials "
            .. "found in your locksmith's container", settings)

        if Stats.prof == "Rogue" then
            util.tpick_silent(nil, "Going to try wedging this box open.", settings)
            -- wedge_lock is in the traps/picking module
            if settings.wedge_lock then
                settings.wedge_lock(vars, settings)
            end
        elseif Stats.prof ~= "Rogue" then
            local knows_407 = Spell and Spell[407] and Spell[407].known
                and Spell[407]:known()
            local uses_407_plate = load_data["Unlock (407)"]
                and string.find(load_data["Unlock (407)"], "Plate")
            local uses_407_all = load_data["Unlock (407)"]
                and string.find(load_data["Unlock (407)"], "All")
            local can_407 = knows_407 and (uses_407_plate or uses_407_all)

            if not can_407 then
                util.tpick_silent(true, "Can't open this plated box.", settings)
                if vars["Picking Mode"] == "solo" then
                    error("tpick: cannot open plated box, exiting")
                elseif vars["Picking Mode"] == "other" then
                    util.tpick_say("Can't Open Box", settings)
                    if settings.open_others then
                        settings.open_others(vars, settings)
                    end
                elseif vars["Picking Mode"] == "ground" then
                    vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
                    vars["Box Opened"] = nil
                elseif vars["Picking Mode"] == "worker" then
                    -- do nothing
                end
            else
                if vars["Picking Mode"] == "ground" then
                    util.tpick_get_box(vars)
                end
                util.tpick_silent(nil, "Going to try popping this box.", settings)
                if settings.cast_407 then
                    settings.cast_407(vars, settings)
                end
            end
        end
    else
        util.tpick_silent(nil, "Found a loose vial! Let's do this!", settings)
        if settings.plate_trap_disarm then
            settings.plate_trap_disarm(vars, settings)
        end
    end
end

---------------------------------------------------------------------------
-- check_for_lockpicks_etc (lines 5252-5310)
-- Verify all required picks, scale weapon, and locksmith supplies.
---------------------------------------------------------------------------
function M.check_for_lockpicks_etc(vars, settings)
    local load_data = settings.load_data
    local all_pick_ids = vars["all_pick_ids"] or {}
    local settings_pick_names = vars["settings_pick_names"] or {}
    local all_repair_ids = vars["all_repair_ids"] or {}
    local all_repair_names = vars["all_repair_names"] or {}

    -- ---- Scale weapon ----
    local sw_container = vars["Scale Weapon Container"]
    if sw_container then
        if not sw_container.contents then
            fput("look in #" .. sw_container.id)
            pause(1)
        end

        -- Find scale weapon by name in container contents
        local weapon_pattern = load_data["Scale Trap Weapon"] or ""
        if sw_container.contents and #weapon_pattern > 0 then
            for _, obj in ipairs(sw_container.contents) do
                if obj.name and string.find(string.lower(obj.name), string.lower(weapon_pattern)) then
                    vars["Scale Weapon ID"] = obj.id
                    break
                end
            end
        end

        -- Fallback: search all containers
        if not vars["Scale Weapon ID"] and #weapon_pattern > 0 then
            if GameObj.containers then
                local containers = GameObj.containers()
                if containers then
                    for _, contents in pairs(containers) do
                        for _, obj in ipairs(contents) do
                            if obj.name and string.find(string.lower(obj.name), string.lower(weapon_pattern)) then
                                vars["Scale Weapon ID"] = obj.id
                                break
                            end
                        end
                        if vars["Scale Weapon ID"] then break end
                    end
                end
            end
        end
    end

    -- ---- Lockpick container contents ----
    local lp_container = vars["Lockpick Container"]
    if lp_container then
        if not lp_container.contents then
            fput("look in #" .. lp_container.id)
            pause(1)
        end

        if lp_container.contents then
            for _, obj in ipairs(lp_container.contents) do
                -- Map picks into all_pick_ids by material
                for name, _ in pairs(all_pick_ids) do
                    local names_for_mat = settings_pick_names[name] or {}
                    for _, pname in ipairs(names_for_mat) do
                        if pname == obj.name then
                            table.insert(all_pick_ids[name], obj.id)
                        end
                    end
                end
                -- Map picks into all_repair_ids
                for name, _ in pairs(all_repair_ids) do
                    local names_for_mat = all_repair_names[name] or {}
                    for _, rname in ipairs(names_for_mat) do
                        if rname == obj.name then
                            table.insert(all_repair_ids[name], obj.id)
                        end
                    end
                end
            end
        end

        -- If no vaalin picks found, try text-based lookup
        if not all_pick_ids["Vaalin"] or #all_pick_ids["Vaalin"] == 0 then
            local command_to_use
            if load_data["Lockpick Container"] and
                string.find(string.lower(load_data["Lockpick Container"]), "vambrace") then
                command_to_use = "look in #" .. lp_container.id
            else
                command_to_use = "look on #" .. lp_container.id
            end

            status_tags()
            fput(command_to_use)
            local lockpick_container_contents = nil
            while true do
                local line = get()
                if not line then break end
                if string.find(line, "you see") then
                    lockpick_container_contents = line
                    break
                elseif string.find(line, "There is nothing on") then
                    break
                end
            end
            status_tags()

            if lockpick_container_contents then
                -- Parse exist="ID" noun="NOUN">NAME</a> patterns
                for id, item_name in string.gmatch(lockpick_container_contents,
                    'exist="(%w+)" noun="%w+">([^<]+)</a>') do
                    for name, _ in pairs(all_pick_ids) do
                        local names_for_mat = settings_pick_names[name] or {}
                        for _, pname in ipairs(names_for_mat) do
                            if pname == item_name then
                                table.insert(all_pick_ids[name], id)
                            end
                        end
                    end
                    for name, _ in pairs(all_repair_ids) do
                        local names_for_mat = all_repair_names[name] or {}
                        for _, rname in ipairs(names_for_mat) do
                            if rname == item_name then
                                table.insert(all_repair_ids[name], id)
                            end
                        end
                    end
                end
            end
        end
    end

    -- ---- Check locksmith container supplies ----
    local ls_container = vars["Locksmith's Container"]
    if ls_container then
        if settings.check_lock_smiths_container then
            settings.check_lock_smiths_container()
        end
        if (vars["Putty Remaining"] or 0) == 0 and (vars["Cotton Remaining"] or 0) == 0 then
            vars["Error Message"] = "The container you have selected as your Locksmith's Container "
                .. "doesn't appear to be a Locksmith's Container. Run ;tpick setup and be sure to "
                .. "select your Locksmith's Container. Your Locksmith's Container is where your putty "
                .. "and cotton balls are stored."
            error("tpick: " .. vars["Error Message"])
        end
        util.tpick_silent(true,
            "Putty remaining: " .. (vars["Putty Remaining"] or 0)
            .. "\nCotton balls remaining: " .. (vars["Cotton Remaining"] or 0)
            .. "\nVials of acid remaining: " .. (vars["Vials Remaining"] or 0), settings)
        if vars["Start Sorter"] then
            Script.run("sorter")
        end
    end
end

---------------------------------------------------------------------------
-- check_for_containers (lines 5871-5906)
-- Validate container settings match actually worn items.
-- Maps each container setting name to a GameObj.inv() item.
---------------------------------------------------------------------------
function M.check_for_containers(vars, settings)
    local load_data = settings.load_data
    local worn_containers = vars["worn_containers"] or {}
    local container_names = {
        "Lockpick Container", "Broken Lockpick Container",
        "Wedge Container", "Calipers Container",
        "Scale Weapon Container", "Locksmith's Container",
    }

    for _, name in ipairs(container_names) do
        if load_data[name] then
            local container_name = load_data[name]
            local id = worn_containers[container_name]
            if id and id ~= "Not Found" then
                local inv = GameObj.inv()
                for _, obj in ipairs(inv) do
                    if obj.id == id then
                        vars[name] = obj
                        break
                    end
                end
            end
        end
    end

    -- Fallback for locksmith container: search all worn containers
    if not vars["Locksmith's Container"] and load_data["Locksmith's Container"] then
        fput("inv containers")
        local all_worn_containers_line = nil
        while true do
            local line = get()
            if not line then break end
            if string.find(line, "You are wearing") then
                all_worn_containers_line = line
                break
            end
        end

        if all_worn_containers_line then
            -- Split on commas and periods, look in each
            for part in all_worn_containers_line:gmatch("[^,%.]+") do
                local last_word = part:match("(%S+)%s*$")
                if last_word then
                    fput("look in " .. last_word)
                end
            end
            -- Now search all container contents for the named item
            if GameObj.containers then
                local containers = GameObj.containers()
                if containers then
                    for _, contents in pairs(containers) do
                        for _, obj in ipairs(contents) do
                            if obj.name == load_data["Locksmith's Container"] then
                                vars["Locksmith's Container"] = obj
                                break
                            end
                        end
                        if vars["Locksmith's Container"] then break end
                    end
                end
            end
        end
    end

    -- Validate required containers are found
    local missing = {}
    if not vars["Lockpick Container"] then
        table.insert(missing, "Could not find your lockpick container.")
    end
    if not vars["Broken Lockpick Container"] then
        table.insert(missing, "Could not find your broken lockpick container.")
    end
    if not vars["Wedge Container"] and Stats.prof == "Rogue" then
        table.insert(missing, "Could not find your wedge container.")
    end
    if not vars["Calipers Container"] and Stats.prof == "Rogue"
        and load_data["Use Calipers"] == "Yes" then
        table.insert(missing, "Could not find your calipers container.")
    end
    if not vars["Scale Weapon Container"] then
        table.insert(missing, "Could not find your scale weapon container.")
    end
    if not vars["Locksmith's Container"] then
        table.insert(missing, "Could not find your locksmith's container.")
    end

    if #missing > 0 then
        local text = "To fix the below issues enter ;tpick setup\n"
            .. "Be sure to properly fill out the name of each of your containers.\n"
            .. "It is also possible you aren't wearing the missing container.\n\n"
            .. table.concat(missing, "\n")
        vars["Error Message"] = text
        error("tpick: " .. text)
    end

    -- Proceed to check picks and locksmith supplies
    M.check_for_lockpicks_etc(vars, settings)
end

return M
