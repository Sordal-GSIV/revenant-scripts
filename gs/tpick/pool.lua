--- tpick pool module — Locksmith pool interaction: worker NPC communication,
-- box assignment, tipping, drop-off/pickup modes.
-- Ported from tpick.lic lines 4463-4605, 4872-4896, 4978-4988,
-- 5633-5640, 5655-5758, 5807-5859.
-- Original authors: Dreaven et al.

local M = {}
local data = require("tpick/data")

-- Cross-module references set by wire()
local util       -- util module
local traps      -- traps module
local picking    -- picking module
local spells     -- spells module
local loot       -- loot module
local stats      -- stats module
local lockpicks  -- lockpicks module
local modes      -- modes module

---------------------------------------------------------------------------
-- M.wire(funcs) — Inject cross-module dependencies.
-- Called once during init before any pool functions are used.
--
-- @param funcs  Table with keys: util, traps, picking, spells, loot, stats, lockpicks, modes
---------------------------------------------------------------------------
function M.wire(funcs)
    util      = funcs.util      or require("tpick/util")
    traps     = funcs.traps
    picking   = funcs.picking
    spells    = funcs.spells
    loot      = funcs.loot
    stats     = funcs.stats
    lockpicks = funcs.lockpicks
    modes     = funcs.modes
end

---------------------------------------------------------------------------
-- M.get_pool_info(vars) — Find pool NPC and table from room tags.
-- Port of get_pool_info from lines 5633-5640.
--
-- Searches Room.current().tags for "meta:boxpool:npc:NAME" and
-- "meta:boxpool:table:NAME", then matches against GameObj.npcs() and
-- GameObj.loot()/GameObj.room_desc().
--
-- @param vars  Mutable picking state table. Sets vars["Pool NPC"] and
--              vars["Pool Table"].
---------------------------------------------------------------------------
function M.get_pool_info(vars)
    local room = Room.current()
    local tags = room and room.tags or {}

    -- Find pool NPC name from tags
    local npc_name = nil
    for _, tag in ipairs(tags) do
        local name = tag:match("^meta:boxpool:npc:(.+)$")
        if name then
            npc_name = name
            break
        end
    end

    -- Match NPC name to a GameObj NPC
    vars["Pool NPC"] = nil
    if npc_name then
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name == npc_name then
                vars["Pool NPC"] = npc
                break
            end
        end
    end

    -- Find pool table name from tags
    local table_name = nil
    for _, tag in ipairs(tags) do
        local name = tag:match("^meta:boxpool:table:(.+)$")
        if name then
            table_name = name
            break
        end
    end

    -- Match table name to a loot object or room desc object
    vars["Pool Table"] = nil
    if table_name then
        local loot_objs = GameObj.loot()
        for _, obj in ipairs(loot_objs) do
            if obj.name == table_name then
                vars["Pool Table"] = obj
                break
            end
        end
        if not vars["Pool Table"] then
            local desc_objs = GameObj.room_desc()
            for _, obj in ipairs(desc_objs) do
                if obj.name == table_name then
                    vars["Pool Table"] = obj
                    break
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.tpick_get_current_worker_box(vars, settings) — Get the assigned box
-- from the pool table.
-- Port of tpick_get_current_worker_box from lines 5807-5836.
--
-- Looks on the pool table for a box belonging to the current character.
-- First checks contents by name match, then falls back to tapping each item.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with update_box_for_window callback.
---------------------------------------------------------------------------
function M.tpick_get_current_worker_box(vars, settings)
    local char_name = GameState.name

    while not vars["Current Box"] do
        dothistimeout("look on #" .. vars["Pool Table"].id, 3, { "^On the" })

        -- First pass: check contents by character name
        local contents = vars["Pool Table"].contents
        if contents then
            for _, item in ipairs(contents) do
                if item.name and string.find(item.name, char_name) then
                    vars["Current Box"] = item
                    if settings.update_box_for_window then
                        settings.update_box_for_window()
                    end
                    break
                end
            end
        end

        -- Second pass: tap each item to identify ownership
        if not vars["Current Box"] and contents then
            for _, item in ipairs(contents) do
                fput("tap #" .. item.id)
                while true do
                    local line = get()
                    if not line then break end
                    if string.find(line, "^You probably shouldn't do that%.") then
                        break
                    elseif string.find(line, "^You tap") then
                        vars["Current Box"] = item
                        if settings.update_box_for_window then
                            settings.update_box_for_window()
                        end
                        break
                    end
                end
                if vars["Current Box"] then break end
            end
        end

        if not vars["Current Box"] then
            pause(1)
        end
    end

    util.tpick_silent(nil,
        "Found your box/plinite!\nName: " .. tostring(vars["Current Box"])
        .. ", ID: " .. tostring(vars["Current Box"].id)
        .. ", tip: " .. tostring(vars["Offered Tip Amount"])
        .. ", Critter name: " .. tostring(vars["Critter Name"])
        .. ", Critter level: " .. tostring(vars["Critter Level"]),
        settings)

    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
end

---------------------------------------------------------------------------
-- M.ask_worker(vars, settings) — Submit completed box to worker.
-- Port of ask_worker from lines 4872-4894.
--
-- Asks the pool NPC to check the completed box. Handles payment,
-- give-up confirmation, too-tough response, and retries on nil result.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with stats_data.
---------------------------------------------------------------------------
function M.ask_worker(vars, settings)
    local stats_data = settings.stats_data

    waitrt()
    local result = dothistimeout(
        "ask #" .. vars["Pool NPC"].id .. " to check", 3,
        {
            'If you want to give up, ASK me to CHECK it again within 30 seconds%."',
            '"That\'s some quality work%.  Here\'s your payment of .* silvers?%."',
            "You aren't working on a job%.",
            "Too tough for ya, eh%?",
        }
    )

    if result and string.find(result, "That's some quality work") then
        -- Successful pick — extract payment
        local amount_str = result:match("payment of ([%d,]+) silvers?")
        local amount = 0
        if amount_str then
            amount = tonumber(amount_str:gsub(",", "")) or 0
        end
        stats_data["Pool Tips Silvers"] = (stats_data["Pool Tips Silvers"] or 0) + amount
        stats_data["Loot Session"]["Silver"] = (stats_data["Loot Session"]["Silver"] or 0) + amount
        stats_data["Pool Boxes Picked"] = (stats_data["Pool Boxes Picked"] or 0) + 1
        stats_data["Session Boxes Picked"] = (stats_data["Session Boxes Picked"] or 0) + 1
        stats.update(vars, stats_data)
        stats.start_values_nilled(vars, settings.load_data)

    elseif result and vars["Give Up On Box"]
        and (string.find(result, "If you want to give up")
             or string.find(result, "You aren't working on a job")) then
        -- Confirm give-up
        fput("ask #" .. vars["Pool NPC"].id .. " to check")
        stats.update(vars, stats_data)
        stats.start_values_nilled(vars, settings.load_data)

    elseif result and string.find(result, "Too tough for ya") then
        stats.update(vars, stats_data)
        stats.start_values_nilled(vars, settings.load_data)

    elseif not result then
        util.tpick_silent(nil, "Didn't recognize game line I was looking for, trying again.", settings)
        M.ask_worker(vars, settings)
    end

    vars["Give Up On Box"] = nil
end

---------------------------------------------------------------------------
-- M.start_worker(vars, settings, stats_data) — Main pool picking loop.
-- Port of start_worker from lines 4463-4605.
--
-- Core pool function: put away items, check mind state, find pool NPC,
-- ask worker for a job, parse response messages, handle wait timers,
-- minimum tip negotiation, rest-when-fried, critter level check,
-- then dispatch to trap check / pick / ask_worker and recurse.
--
-- @param vars        Mutable picking state table.
-- @param settings    Settings table with load_data, stats_data, etc.
-- @param stats_data  Stats tracking table.
---------------------------------------------------------------------------
function M.start_worker(vars, settings, stats_data)
    local load_data = settings.load_data

    vars["Do Not Ask To Check"] = nil
    util.tpick_put_stuff_away(vars, settings)
    modes.stuff_to_do(vars, settings)
    vars["Current Box"] = nil
    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
    waitrt()

    if not vars["Pool NPC"] then
        util.tpick_silent(true, "Get yourself to a worker who assigns you jobs.", settings)
        return
    end

    -- Check encumbrance if auto-deposit is configured
    if load_data["Auto Deposit Silvers"]
        and type(load_data["Auto Deposit Silvers"]) == "string"
        and #load_data["Auto Deposit Silvers"]:gsub("^ +", "") > 0 then
        loot.encumbrance_check(vars, settings)
    end

    vars["Offered Tip Amount"] = nil

    -- Check exit conditions
    if vars["rogue_the_current_task_is_finished"] or vars["exit_tpick_immediately"] then
        return
    end

    if vars["stop_immediately"] then
        -- Skip asking, fall through
    else
        -- Ask worker for a job
        if (vars["Current Minimum Tip"] or 0) > 0 then
            fput("ask #" .. vars["Pool NPC"].id .. " for job minimum " .. vars["Current Minimum Tip"])
        else
            fput("ask #" .. vars["Pool NPC"].id .. " for job")
        end

        -- Parse worker response
        local next_task = nil
        while true do
            local line = get()
            if not line then break end

            if string.find(line, 'You should finish the job you\'re working on first') then
                next_task = nil
                break

            elseif string.find(line, "offering a tip of") then
                -- Check if creature info is present
                local tip_str, critter, level = line:match(
                    "offering a tip of ([%d,]+) silvers? and mentioned it being from %a+ (.*) %(level (%d+)%)")
                if tip_str then
                    vars["Offered Tip Amount"] = tonumber(tip_str:gsub(",", "")) or 0
                    vars["Critter Name"] = critter
                    vars["Critter Level"] = tonumber(level) or 0
                    next_task = nil
                    break
                end

                -- Unknown creature source
                local tip_unknown = line:match("offering a tip of ([%d,]+) silvers? and they aren't sure")
                if tip_unknown then
                    vars["Offered Tip Amount"] = tonumber(tip_unknown:gsub(",", "")) or 0
                    vars["Critter Name"] = "Unknown"
                    vars["Critter Level"] = Stats.level or 0
                    next_task = nil
                    break
                end

            elseif string.find(line, "done enough boxes.*10 minutes") then
                next_task = "Wait 300 Seconds"
                break

            elseif string.find(line, "done enough boxes.*few minutes") then
                next_task = "Wait 120 Seconds"
                break

            elseif string.find(line, "done enough boxes.*about a minute") then
                next_task = "Wait 60 Seconds"
                break

            elseif string.find(line, "What, you think we have a job already") then
                next_task = "Wait 10 Seconds"
                break

            elseif string.find(line, "rest your mind") then
                next_task = "Rest Wait"
                break

            elseif string.find(line, "We don't have any jobs for you")
                or string.find(line, "You haven't quite reflected")
                or string.find(line, "You've done enough") then
                next_task = "Tip Wait"
                break

            elseif string.find(line, "Come back when you learn") then
                util.tpick_silent(true,
                    "You need to train in more ranks in lockpicking before you can pick boxes at the locksmith pool.",
                    settings)
                return
            end
        end

        -- Handle wait/tip scenarios
        if next_task and string.find(next_task, "Wait") then
            if vars["Exit When Waiting"] then
                return
            end

            local wait_time = nil
            local text = nil

            if next_task == "Tip Wait" then
                -- Minimum tip negotiation
                if load_data["Minimum Tip Interval"] and load_data["Minimum Tip Floor"] then
                    if (vars["Current Minimum Tip"] or 0) > load_data["Minimum Tip Floor"] then
                        text = "No boxes at your current minimum rate. Lowering minimum tip wanted."
                        vars["Current Minimum Tip"] = (vars["Current Minimum Tip"] or 0) - load_data["Minimum Tip Interval"]
                        vars["Current Minimum Tip"] = math.max(vars["Current Minimum Tip"], load_data["Minimum Tip Floor"])
                        if load_data["Standard Wait"] == "No" then
                            wait_time = load_data["Time To Wait"] or 10
                        else
                            wait_time = 10
                        end
                    else
                        -- Reset to start tip
                        vars["Current Minimum Tip"] = load_data["Minimum Tip Start"]
                        text = "No boxes at your lowest minimum rate."
                        if load_data["Standard Wait"] == "No" then
                            wait_time = load_data["Time To Wait"] or 30
                        else
                            wait_time = 30
                        end
                    end
                else
                    text = "No boxes available at the moment."
                    if load_data["Standard Wait"] == "No" then
                        wait_time = load_data["Time To Wait"] or 30
                    else
                        wait_time = 30
                    end
                end

            elseif next_task == "Rest Wait" then
                -- Rest when fried — navigate to rest room if configured
                if vars["Pool Fried Commands"] and load_data["Pick At Percent"] ~= "Always" then
                    local pool_fried_start = os.time()
                    local pick_percent = tonumber(tostring(load_data["Pick At Percent"]):match("%d+")) or 0
                    util.tpick_silent(true,
                        "Worker isn't assigning you boxes because your mind is too full. "
                        .. "Running your resting routine then coming back to pick more boxes when your mind reaches "
                        .. pick_percent .. "%.",
                        settings)

                    local starting_room = Room.id
                    Script.run("go2", { vars["Pool Fried Commands"][1] })
                    wait_while(function() return running("go2") end)

                    if vars["Pool Fried Commands"][2] then
                        fput(vars["Pool Fried Commands"][2])
                    end

                    util.tpick_silent(true, "Resting until mind reaches " .. pick_percent .. "%.", settings)
                    wait_until(function() return pick_percent >= percentmind() end)

                    util.tpick_silent(true, "Mind cleared out! Heading back to pick more boxes!", settings)
                    Script.run("go2", { tostring(starting_room) })
                    wait_while(function() return running("go2") end)

                    stats_data["Pool Time Spent Waiting"] = (stats_data["Pool Time Spent Waiting"] or 0)
                        + os.difftime(os.time(), pool_fried_start)
                    -- wait_time stays nil so we skip the generic wait below
                else
                    text = "Worker isn't assigning boxes because your mind is too full."
                    if load_data["Standard Wait"] == "No" then
                        wait_time = load_data["Time To Wait"] or 120
                    else
                        wait_time = 120
                    end
                end

            else
                -- Generic "Wait N Seconds" from next_task string
                text = "No boxes available at the moment."
                local parsed_seconds = tonumber(next_task:match("(%d+)"))
                if load_data["Standard Wait"] == "No" then
                    wait_time = load_data["Time To Wait"] or parsed_seconds or 30
                else
                    wait_time = parsed_seconds or 30
                end
            end

            -- Perform the wait
            if wait_time then
                wait_time = tonumber(wait_time) or 30
                util.tpick_silent(true,
                    text .. " Waiting " .. wait_time .. " seconds and trying again.",
                    settings)

                local real_time_waited = 0
                for _ = 1, wait_time do
                    if vars["stop_immediately"] then break end
                    pause(1)
                    real_time_waited = real_time_waited + 1
                end

                if real_time_waited > 0 then
                    stats_data["Pool Time Spent Waiting"] = (stats_data["Pool Time Spent Waiting"] or 0)
                        + real_time_waited
                else
                    stats_data["Pool Time Spent Waiting"] = (stats_data["Pool Time Spent Waiting"] or 0)
                        + wait_time
                end
            end

            stats.update(vars, stats_data)
            -- Recurse to try again
            return M.start_worker(vars, settings, stats_data)

        else
            -- Got a job offer — check critter level
            if vars["Critter Level"] and load_data["Max Level"]
                and vars["Critter Level"] > load_data["Max Level"] then
                util.tpick_silent(true,
                    "Critter level too high, turning in box. Critter level: " .. vars["Critter Level"] .. ".",
                    settings)
                vars["Give Up On Box"] = true
                M.ask_worker(vars, settings)
                return M.start_worker(vars, settings, stats_data)
            end

            -- Rogue guild task tracking
            if vars["rogue_current_task"] == "Gather trap components"
                and vars["rogue_task_for_footpad_or_administrator"] == "Footpad" then
                local remaining = (vars["rogue_reps_remaining"] or 0)
                    - #(vars["rogue_trap_components_needed_array"] or {})
                util.tpick_silent(true, "Need " .. remaining .. " more trap components.", settings)
            end

            -- Get box from table, prepare trap check state
            M.tpick_get_current_worker_box(vars, settings)
            spells.tpick_stop_403_404(vars, settings)
            vars["Manual Trap Checks Remaining"] = load_data["Trap Check Count"]

            -- Dispatch to trap check / pick
            if vars["Gnomish Bracers"]
                and load_data["Bracer Tier 2"] == "Yes"
                and vars["Current Box"]
                and vars["Current Box"].name
                and not string.find(vars["Current Box"].name:lower(), "plinite") then
                traps.gnomish_bracers_trap_check(vars, settings)
            elseif vars["Pop Boxes"] then
                modes.pop_boxes_begin(vars, settings)
            else
                traps.manually_disarm_trap(vars, settings)
            end

            -- Submit completed box
            if not vars["Do Not Ask To Check"] then
                M.ask_worker(vars, settings)
            end

            -- Loop for next box
            return M.start_worker(vars, settings, stats_data)
        end
    end
end

---------------------------------------------------------------------------
-- M.drop_off_boxes(vars, settings) — Drop-off mode: leave boxes at pool
-- for someone else to pick.
-- Port of drop_off_boxes from lines 5655-5710.
--
-- Counts boxes, goes to bank to get tip money, returns to pool,
-- hands each box to the NPC with the specified tip.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.drop_off_boxes(vars, settings)
    local load_data = settings.load_data

    vars["Current Room"] = Room.id

    if not vars["Pool NPC"] then
        util.tpick_silent(true, "The 'drop' command only works at locksmith pools.", settings)
        return
    end

    if not vars["Tip Being Offered"] then
        util.tpick_silent(true,
            "You need to specify how much you are tipping and if you want it to be a percent.\n"
            .. "For example do ';tpick drop 100' to tip 100 silvers per box\n"
            .. "Do \";tpick drop 10 percent\" or ';tpick drop 10%' if you want to tip 10% per box",
            settings)
        return
    end

    if vars["Tip Is A Percent"] and vars["Tip Being Offered"] > 100 then
        util.tpick_silent(true, "Wise guy, huh? You can't tip more than 100%!", settings)
        return
    end

    util.tpick_put_stuff_away(vars, settings)
    modes.check_for_boxes(vars, settings)

    vars["Total Number Of Boxes"] = #(vars["All Box IDs"] or {})

    -- Count boxes in disk unless hunt looter
    if vars["hunt_looter"] ~= GameState.name then
        stats.count_boxes_in_disk(vars)
    end

    util.tpick_silent(true,
        "Total number of boxes: " .. vars["Total Number Of Boxes"],
        settings)

    if vars["Total Number Of Boxes"] == 0 then
        util.tpick_silent(true, "You don't have any boxes.", settings)
        return
    end

    local npc_name = vars["Pool NPC"].name or tostring(vars["Pool NPC"])
    local box_ids = vars["All Box IDs"] or {}

    if vars["Tip Is A Percent"] then
        util.tpick_silent(true,
            "You are tipping " .. vars["Tip Being Offered"] .. "% for each box.",
            settings)
        pause(1)

        -- Go to bank, deposit all, withdraw enough for tips
        Script.run("go2", { "bank", "--disable-confirm" })
        wait_while(function() return running("go2") end)
        fput("depo all")
        fput("withdraw " .. (3500 * vars["Total Number Of Boxes"]) .. " silvers")

        -- Return to pool room
        Script.run("go2", { tostring(vars["Current Room"]) })
        wait_while(function() return running("go2") end)

        -- Wait for disk to arrive (unless hunt looter)
        if vars["hunt_looter"] ~= GameState.name then
            for _ = 1, 40 do
                local found = false
                for _, obj in ipairs(GameObj.loot()) do
                    if obj.name and string.find(obj.name, GameState.name)
                        and (string.find(obj.name, "disk") or string.find(obj.name, "coffin")) then
                        found = true
                        break
                    end
                end
                if found then break end
                pause(0.1)
            end
        end

        -- Hand each box to NPC with percent tip
        for _, box_id in ipairs(box_ids) do
            util.tpick_put_stuff_away(vars, settings)
            fput("get #" .. box_id)
            fput("give " .. npc_name .. " " .. vars["Tip Being Offered"] .. " percent")
            fput("give " .. npc_name .. " " .. vars["Tip Being Offered"] .. " percent")
        end
    else
        local total_tip = vars["Tip Being Offered"] * vars["Total Number Of Boxes"]
        util.tpick_silent(true,
            "You are tipping " .. vars["Tip Being Offered"]
            .. " silvers for each box for a total tip needed of " .. total_tip,
            settings)
        pause(1)

        -- Go to bank, deposit all, withdraw exact tip amount
        Script.run("go2", { "bank", "--disable-confirm" })
        wait_while(function() return running("go2") end)
        fput("depo all")
        fput("withdraw " .. total_tip .. " silvers")

        -- Return to pool room
        Script.run("go2", { tostring(vars["Current Room"]) })
        wait_while(function() return running("go2") end)

        -- Wait for disk to arrive (unless hunt looter)
        if vars["hunt_looter"] ~= GameState.name then
            for _ = 1, 40 do
                local found = false
                for _, obj in ipairs(GameObj.loot()) do
                    if obj.name and string.find(obj.name, GameState.name)
                        and (string.find(obj.name, "disk") or string.find(obj.name, "coffin")) then
                        found = true
                        break
                    end
                end
                if found then break end
                pause(0.1)
            end
        end

        -- Hand each box to NPC with flat tip
        for _, box_id in ipairs(box_ids) do
            util.tpick_put_stuff_away(vars, settings)
            fput("get #" .. box_id)
            fput("give " .. npc_name .. " " .. vars["Tip Being Offered"])
            fput("give " .. npc_name .. " " .. vars["Tip Being Offered"])
        end
    end
end

---------------------------------------------------------------------------
-- M.pick_up_boxes(vars, settings, stats_data) — Pickup mode: collect
-- picked boxes from pool.
-- Port of pick_up_boxes from lines 5711-5758.
--
-- Asks NPC "about return" in a loop, collects each returned box,
-- opens, loots contents. Handles "lighten your load" by banking.
--
-- @param vars        Mutable picking state table.
-- @param settings    Settings table with load_data.
-- @param stats_data  Stats tracking table.
---------------------------------------------------------------------------
function M.pick_up_boxes(vars, settings, stats_data)
    if not vars["Pool NPC"] then
        util.tpick_silent(true, "This command only works at locksmith pools.", settings)
        return
    end

    util.tpick_put_stuff_away(vars, settings)

    local npc_name = vars["Pool NPC"].name or tostring(vars["Pool NPC"])
    local no_boxes = false

    while not no_boxes do
        fput("ask " .. npc_name .. " about return")

        while true do
            local line = get()
            if not line then break end

            if string.find(line, "We don't have any boxes ready for you") then
                no_boxes = true
                break

            elseif string.find(line, "here's your .* back") then
                wait_until(function() return checkright() end)
                vars["Picking Up"] = true
                pause(0.2)

                local lootbox = GameObj.right_hand()
                vars["Current Box"] = lootbox
                if settings.update_box_for_window then
                    settings.update_box_for_window()
                end

                fput("open #" .. lootbox.id)

                -- Wait for contents to populate
                for _ = 1, 25 do
                    if lootbox.contents then break end
                    fput("look in #" .. lootbox.id)
                    pause(0.2)
                end

                -- Loot all non-cursed items
                if lootbox.contents then
                    for _, item in ipairs(lootbox.contents) do
                        vars["Current Item"] = item
                        waitrt()
                        if not item.type or not string.find(item.type, "cursed") then
                            loot.gather_stuff(vars, settings)
                        end
                    end
                end

                stats_data["Boxes Looted"] = (stats_data["Boxes Looted"] or 0) + 1
                stats.update(vars, stats_data)
                util.garbage_check(vars, settings)
                util.tpick_put_stuff_away(vars, settings)
                break

            elseif string.find(line, "You need to lighten your load first") then
                vars["Starting Room Number"] = Room.id
                Script.run("go2", { "bank", "--disable-confirm" })
                wait_while(function() return running("go2") end)
                fput("depo all")
                Script.run("go2", { tostring(vars["Starting Room Number"]) })
                wait_while(function() return running("go2") end)
                break
            end
        end
    end

    vars["Picking Up"] = nil
end

---------------------------------------------------------------------------
-- M.refill_locksmiths_container(vars, settings) — Refill locksmith
-- container with supplies (putty and cotton balls).
-- Port of refill_locksmiths_container from lines 5838-5857.
--
-- Checks container contents, validates it is a real locksmith container,
-- then delegates to loot.fill_up_locksmith_container.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with check_lock_smiths_container callback.
---------------------------------------------------------------------------
function M.refill_locksmiths_container(vars, settings)
    if settings.check_lock_smiths_container then
        settings.check_lock_smiths_container()
    end

    if (vars["Putty Remaining"] or 0) == 0 and (vars["Cotton Remaining"] or 0) == 0 then
        vars["Error Message"] = "The container you have selected as your Locksmith's Container "
            .. "doesn't appear to be a Locksmith's Container. Run ;tpick setup and be sure to "
            .. "select your Locksmith's Container."
        return
    end

    -- Start sorter script if configured
    if vars["Start Sorter"] then
        Script.run("sorter")
    end

    if (vars["Putty Remaining"] or 0) >= 100 and (vars["Cotton Remaining"] or 0) >= 100 then
        util.tpick_silent(true, "You already have 100 each of putty and cotton balls.", settings)
        return
    end

    -- Check for missing/wounded hands or arms
    if Wounds.lhand() >= 3 or Wounds.rhand() >= 3
        or Wounds.larm() >= 3 or Wounds.rarm() >= 3
        or Scars.lhand() >= 3 or Scars.rhand() >= 3
        or Scars.larm() >= 3 or Scars.rarm() >= 3 then
        util.tpick_silent(true,
            "Your wounds are too great to do this task. You can't do this with a missing hand or arm.",
            settings)
        return
    end

    util.tpick_put_stuff_away(vars, settings)
    loot.fill_up_locksmith_container(vars, settings)
end

---------------------------------------------------------------------------
-- M.buy_locksmith_pouch(vars, settings) — Buy a locksmith pouch from shop.
-- Port of buy_locksmith_pouch from lines 4978-4986.
--
-- Orders the toolkit, opens it, bundles contents, drops box.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table.
---------------------------------------------------------------------------
function M.buy_locksmith_pouch(vars, settings)
    fput("order " .. (vars["Toolkit Order Number"] or "1"))
    fput("buy")
    wait_until(function() return checkleft() end)

    local left = GameObj.left_hand()
    if left then
        fput("open #" .. left.id)
        fput("bundle")
        vars["Current Box"] = GameObj.left_hand()
        util.tpick_drop_box(vars)
    end
end

return M
