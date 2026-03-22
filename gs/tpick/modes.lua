-- tpick/modes.lua — Picking modes: ground, solo, other, plinite, pop, and support functions
-- Ported from tpick.lic lines 2075-2162, 2220-2250, 3810-3983, 3899-3918,
-- 4149-4235, 4375-4461, 4925-4949, 5186-5252
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

---------------------------------------------------------------------------
-- M.wire(funcs) — Inject cross-module dependencies.
-- Called once during init before any mode functions are used.
--
-- @param funcs  Table with keys: util, traps, picking, spells, loot, stats, lockpicks
---------------------------------------------------------------------------
function M.wire(funcs)
    util      = funcs.util      or require("tpick/util")
    traps     = funcs.traps
    picking   = funcs.picking
    spells    = funcs.spells
    loot      = funcs.loot
    stats     = funcs.stats
    lockpicks = funcs.lockpicks
end

---------------------------------------------------------------------------
-- M.stuff_to_do(vars, settings) — Mind-state rest/wait check.
-- Port of stuff_to_do from lines 4443-4452.
--
-- If Rest At Percent is not "Never" and Pick At Percent is not "Always",
-- check percentmind against rest threshold. If mind is too full, wait
-- until pick threshold is reached.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.stuff_to_do(vars, settings)
    local load_data = settings.load_data
    if load_data["Rest At Percent"] ~= "Never"
       and load_data["Pick At Percent"] ~= "Always"
       and vars["Picking Mode"] ~= "worker" then
        local rest_percent = tonumber(load_data["Rest At Percent"]:match("%d+")) or 0
        if rest_percent <= percentmind() then
            local pick_percent = tonumber(load_data["Pick At Percent"]:match("%d+")) or 0
            util.tpick_silent(true, "Resting until mind reaches " .. pick_percent .. "%.", settings)
            wait_until(function() return pick_percent >= percentmind() end)
        end
    end
end

---------------------------------------------------------------------------
-- M.check_for_boxes(vars, settings) — Enumerate boxes in inventory containers.
-- Port of check_for_boxes from lines 4454-4461.
--
-- NOTE: GameObj.containers is NOT available in Revenant.
-- Instead: iterate GameObj.inv(), for each container check obj.contents.
-- If contents nil, send "look in #id" to populate.
-- Collect all items with type "box" (or name matching "plinite" if Open Plinites mode).
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.check_for_boxes(vars, settings)
    vars["All Box IDs"] = {}
    local inv = GameObj.inv()
    if not inv then return end

    for _, container in ipairs(inv) do
        -- Populate contents if not yet loaded
        if container.contents == nil then
            dothistimeout("look in #" .. container.id, 3,
                { "In .* you see", "In the .*:", "There is nothing in" })
        end

        local contents = container.contents
        if contents then
            for _, item in ipairs(contents) do
                if vars["Open Plinites"] then
                    if item.name and string.find(item.name, "plinite") then
                        table.insert(vars["All Box IDs"], item.id)
                    end
                else
                    if item.type and string.find(item.type, "box") then
                        table.insert(vars["All Box IDs"], item.id)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.check_disk(vars) — Scan disk for boxes.
-- Port of check_disk from lines 3810-3848.
--
-- Find disk in GameObj.loot() by name match. If found, look in disk.
-- Enumerate box-type items, process each (pop or get+disarm+pick).
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.check_disk(vars, settings)
    vars["Stow In Disk"] = true
    local load_data = settings.load_data

    -- Find the disk
    local disk = nil
    local loot_items = GameObj.loot()
    if loot_items then
        for _, obj in ipairs(loot_items) do
            if obj.name and string.find(obj.name, GameState.name .. " disk")
               or (obj.name and string.find(obj.name, "coffin")) then
                disk = obj
                break
            end
        end
    end

    -- If not found, wait 4 seconds then retry
    if not disk and not vars["Checked For Disk"] then
        util.tpick_silent(true, "Waiting 4 seconds for disk", settings)
        for _ = 1, 40 do
            loot_items = GameObj.loot()
            if loot_items then
                for _, obj in ipairs(loot_items) do
                    if obj.name and (string.find(obj.name, GameState.name .. " disk")
                       or string.find(obj.name, "coffin")) then
                        disk = obj
                        break
                    end
                end
            end
            if disk then break end
            pause(0.1)
        end
    end

    if not disk then
        if not vars["Checked For Disk"] then
            util.tpick_silent(nil, "No disk found.", settings)
        end
        return
    end

    -- Populate disk contents
    if disk.contents == nil then
        dothistimeout("look in #" .. disk.id, 3,
            { "In the", "There is nothing in" })
    end

    local contents = disk.contents
    if not contents then return end

    for _, item in ipairs(contents) do
        if _G["$tpick_stop_immediately"] then break end
        if item.type and string.find(item.type, "box") then
            waitrt()
            if vars["Pop Boxes"] then
                vars["Current Box"] = item
                if settings.update_box_for_window then
                    settings.update_box_for_window()
                end
                M.pop_boxes_begin(vars, settings)
            else
                fput("get #" .. item.id)
                vars["Start Time"] = os.time()
                vars["Critter Name"] = nil
                stats.start_values_nilled(vars, load_data)
                vars["Manual Trap Checks Remaining"] = load_data["Trap Check Count"]
                if vars["Gnomish Bracers"] and load_data["Bracer Tier 2"] == "Yes" then
                    traps.gnomish_bracers_trap_check(vars, settings)
                else
                    traps.manually_disarm_trap(vars, settings)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.start_ground(vars, settings, stats_data) — Ground picking loop.
-- Port of start_ground from lines 2075-2162.
--
-- Iterate boxes on the ground, skip already-picked IDs. For each box:
-- reset state, disarm, pick, open if Ground Loot, loot contents, garbage_check.
-- Handle Pop Boxes mode, Bash mode, Gnomish Bracers mode.
--
-- @param vars        Mutable picking state table.
-- @param settings    Settings table with load_data.
-- @param stats_data  Stats tracking table.
---------------------------------------------------------------------------
function M.start_ground(vars, settings, stats_data)
    local load_data = settings.load_data

    stats.total_boxes_count(vars, stats_data)

    local loot_items = GameObj.loot()
    if loot_items then
        for _, box in ipairs(loot_items) do
            if _G["$tpick_exit_tpick_immediately"] then return end
            if _G["$tpick_stop_immediately"] then break end

            if box.type and string.find(box.type, "box") then
                -- Skip already-picked boxes
                local already_picked = false
                if vars["Box IDs Already Picked"] then
                    for _, pid in ipairs(vars["Box IDs Already Picked"]) do
                        if pid == box.id then
                            already_picked = true
                            break
                        end
                    end
                end

                if not already_picked then
                    -- Track this box ID
                    if not vars["Box IDs Already Picked"] then
                        vars["Box IDs Already Picked"] = {}
                    end
                    table.insert(vars["Box IDs Already Picked"], box.id)

                    stats.update(vars, stats_data)
                    vars["Box Opened"] = true
                    if settings.update_box_for_window then
                        settings.update_box_for_window()
                    end
                    spells.tpick_stop_403_404(vars, settings)
                    M.stuff_to_do(vars, settings)
                    waitrt()

                    vars["Box Was Not Locked"] = nil
                    vars["Start Time"] = os.time()
                    stats.start_values_nilled(vars, load_data)
                    vars["Current Box"] = box
                    vars["Manual Trap Checks Remaining"] = load_data["Trap Check Count"]

                    if vars["Pop Boxes"] then
                        M.pop_boxes_begin(vars, settings)
                    elseif vars["Bash Open Boxes"] then
                        if vars["Disarm Only"] then
                            if vars["Gnomish Bracers"] and load_data["Bracer Tier 2"] == "Yes" then
                                traps.gnomish_bracers_trap_check(vars, settings)
                            else
                                traps.manually_disarm_trap(vars, settings)
                            end
                        else
                            picking.bash_the_box_open(vars, settings)
                        end
                    else
                        if vars["Gnomish Bracers"] and load_data["Bracer Tier 2"] == "Yes" then
                            traps.gnomish_bracers_trap_check(vars, settings)
                        else
                            traps.manually_disarm_trap(vars, settings)
                        end
                    end

                    vars["Update Information"] = true
                    stats.total_boxes_picked_math(vars, stats_data)
                    util.tpick_drop_box(vars)

                    if vars["Ground Loot"] then
                        -- Auto deposit check
                        if load_data["Auto Deposit Silvers"]
                           and load_data["Auto Deposit Silvers"]:match("%S") then
                            loot.encumbrance_check(vars, settings)
                        end

                        if vars["Bash Open Boxes"] and vars["Box Was Not Locked"] == nil then
                            -- Bash mode: loot from ground
                            local ground_items = GameObj.loot()
                            if ground_items then
                                for _, item in ipairs(ground_items) do
                                    vars["Current Item"] = item
                                    loot.tpick_gather_the_loot(vars, settings)
                                end
                            end
                            stats.update(vars, stats_data)
                        elseif vars["Box Opened"] or vars["Box Was Not Locked"] then
                            waitrt()
                            if vars["Use 506"] then
                                spells.tpick_cast_spells(506, vars, settings)
                            end
                            if vars["Use 1035"] then
                                spells.tpick_cast_spells(1035, vars, settings)
                            end
                            if not vars["Pop Boxes"] then
                                fput("open #" .. vars["Current Box"].id)
                            end
                            -- Populate contents if needed
                            if box.contents == nil then
                                dothistimeout("look in #" .. box.id, 10,
                                    { "In .* you see", "In the .*:", "There is nothing in" })
                            end
                            local contents = box.contents
                            if contents then
                                for _, item in ipairs(contents) do
                                    vars["Current Item"] = item
                                    loot.tpick_gather_the_loot(vars, settings)
                                end
                            end
                            stats.update(vars, stats_data)
                            if vars["Relock Boxes"] then
                                picking.do_relock_boxes(vars, settings, lockpicks)
                            end
                            util.garbage_check(vars, settings)
                        end
                        stats_data["Boxes Looted"] = (stats_data["Boxes Looted"] or 0) + 1
                        stats.update(vars, stats_data)
                    else
                        if vars["Pop Boxes"] then
                            -- Do nothing
                        else
                            if vars["Box Opened"]
                               and not vars["Disarm Only"]
                               and load_data["Open Boxes"] == "Yes" then
                                fput("open #" .. vars["Current Box"].id)
                            end
                        end
                    end

                    util.tpick_put_stuff_away(vars, settings)
                end
            end
        end
    end

    -- After all boxes
    if not _G["$tpick_stop_immediately"] then
        if vars["Check Ground Again"] then
            vars["Check Ground Again"] = nil
            util.tpick_silent(true, "Checking for boxes I might have missed.", settings)
            vars["Box Math"] = nil
            M.start_ground(vars, settings, stats_data)
        else
            util.tpick_silent(true, "All done!", settings)
            local cant_open = vars["Can't Open Plated Box Count"] or 0
            if cant_open > 0 then
                util.tpick_silent(true, "Couldn't open " .. cant_open
                    .. " box(es), which are still on the ground.", settings)
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.open_solo(vars, settings, stats_data) — Open and loot a solo box after picking.
-- Port of open_solo from lines 2229-2250.
--
-- Open box, look in to populate contents, swap to other hand,
-- loot each item, relock if configured, garbage check.
--
-- @param vars        Mutable picking state table.
-- @param settings    Settings table with load_data.
-- @param stats_data  Stats tracking table.
---------------------------------------------------------------------------
function M.open_solo(vars, settings, stats_data)
    vars["Update Information"] = true
    stats.total_boxes_picked_math(vars, stats_data)
    waitrt()

    if vars["Use 506"] then
        spells.tpick_cast_spells(506, vars, settings)
    end
    if vars["Use 1035"] then
        spells.tpick_cast_spells(1035, vars, settings)
    end

    if not vars["Pop Boxes"] then
        fput("open #" .. vars["Current Box"].id)
    end

    local lootbox = GameObj.right_hand()
    if lootbox and lootbox.contents == nil then
        dothistimeout("look in my " .. (lootbox.noun or lootbox.name or "box"), 10,
            { "In .* you see", "In the .*:", "There is nothing in" })
    end
    waitrt()
    fput("swap")

    if lootbox and lootbox.contents then
        for _, item in ipairs(lootbox.contents) do
            vars["Current Item"] = item
            loot.tpick_gather_the_loot(vars, settings)
        end
    end

    stats_data["Boxes Looted"] = (stats_data["Boxes Looted"] or 0) + 1
    stats.update(vars, stats_data)

    if vars["Relock Boxes"] then
        picking.do_relock_boxes(vars, settings, lockpicks)
    end
    util.garbage_check(vars, settings)
    util.tpick_put_stuff_away(vars, settings)
    pause(0.1)
end

---------------------------------------------------------------------------
-- M.open_others(vars, settings) — Give box back to customer after picking.
-- Port of open_others from lines 2220-2227.
--
-- Update stats, give box to customer, wait for accept, restart start_others.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.open_others(vars, settings)
    local stats_data = settings.stats_data
    vars["Update Information"] = true
    stats.total_boxes_picked_math(vars, stats_data)
    waitrt()
    fput("give #" .. vars["Current Box"].id .. " to " .. vars["Customer"])
    if checkright() then
        waitfor("has accepted your offer")
    end
    if not _G["$tpick_stop_immediately"] then
        M.start_others(vars, settings)
    end
end

---------------------------------------------------------------------------
-- M.start_solo(vars, settings, stats_data) — Solo picking mode.
-- Port of start_solo from lines 3850-3870.
--
-- Call check_for_boxes to enumerate box IDs, then loop through them.
-- For each: get box, disarm, pick. After all: check disk.
--
-- @param vars        Mutable picking state table.
-- @param settings    Settings table with load_data.
-- @param stats_data  Stats tracking table.
---------------------------------------------------------------------------
function M.start_solo(vars, settings, stats_data)
    local load_data = settings.load_data

    stats.total_boxes_count(vars, stats_data)

    if vars["Pop Boxes"] then
        M.pop_start(vars, settings)
        return
    end

    if vars["Open Plinites"] then
        M.start_plinites(vars, settings)
        return
    end

    local all_box_ids = vars["All Box IDs"] or {}
    for _, box_id in ipairs(all_box_ids) do
        if _G["$tpick_exit_tpick_immediately"] then return end
        if _G["$tpick_stop_immediately"] then break end

        stats.update(vars, stats_data)
        spells.tpick_stop_403_404(vars, settings)
        fput("get #" .. box_id)
        vars["Start Time"] = os.time()
        vars["Critter Name"] = nil
        stats.start_values_nilled(vars, load_data)
        M.stuff_to_do(vars, settings)
        vars["Manual Trap Checks Remaining"] = load_data["Trap Check Count"]

        if vars["Gnomish Bracers"] and load_data["Bracer Tier 2"] == "Yes" then
            traps.gnomish_bracers_trap_check(vars, settings)
        else
            traps.manually_disarm_trap(vars, settings)
        end
    end

    if not _G["$tpick_stop_immediately"] then
        M.check_disk(vars, settings)
    end
end

---------------------------------------------------------------------------
-- M.start_others(vars, settings) — Other (customer) mode.
-- Port of start_others from lines 3872-3897.
--
-- Wait for someone to GIVE you a box, parse customer name,
-- accept the box, set Current Box, disarm and pick.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.start_others(vars, settings)
    local load_data = settings.load_data
    waitrt()
    _G["$tpick_currently_working_on_box"] = nil

    if _G["$tpick_exit_tpick_immediately"] then return end

    fput("accept")

    while true do
        local line = get()
        if line then
            -- Match: "You accept PersonName's offer and are now holding..."
            local accepted_name = line:match("^You accept ([a-zA-Z]+)'s offer and are now holding.*%.$")

            -- Match: "PersonName offers you a/an/some TYPE BOX... Click ACCEPT..."
            local offer_name, offer_desc
            if not accepted_name then
                local box_pattern = vars["All Box Types"] or data.BOX_TYPES
                offer_name = line:match("^([a-zA-Z]+) offers you .* " .. box_pattern)
            end

            local customer = accepted_name or offer_name
            if customer then
                vars["Customer"] = customer
                _G["$tpick_currently_working_on_box"] = true
                pause(1)

                -- If it was an offer (not already accepted), accept now
                if offer_name and not checkright() then
                    fput("accept")
                end

                vars["Start Time"] = os.time()
                spells.tpick_stop_403_404(vars, settings)
                vars["Critter Name"] = nil
                stats.start_values_nilled(vars, load_data)
                vars["Manual Trap Checks Remaining"] = load_data["Trap Check Count"]

                if vars["Gnomish Bracers"] and load_data["Bracer Tier 2"] == "Yes" then
                    traps.gnomish_bracers_trap_check(vars, settings)
                else
                    traps.manually_disarm_trap(vars, settings)
                end

                stats.update(vars, settings.stats_data)
                break
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.start_plinites(vars, settings) — Plinite opening mode.
-- Port of start_plinites from lines 3966-3981.
--
-- Loop through All Box IDs, get each plinite, detect difficulty, pick.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.start_plinites(vars, settings)
    local all_box_ids = vars["All Box IDs"] or {}
    for _, plinite_id in ipairs(all_box_ids) do
        util.tpick_put_stuff_away(vars, settings)
        vars["Plinite Already Open"] = nil
        vars["Can't Determine Plinite Difficulty"] = nil

        -- Get plinite into hand
        while true do
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.id == plinite_id) or (lh and lh.id == plinite_id) then
                break
            end
            waitrt()
            fput("get #" .. plinite_id)
            pause(0.2)
        end

        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if rh and rh.name and string.find(rh.name, "plinite") then
            vars["Current Box"] = rh
        elseif lh and lh.name and string.find(lh.name, "plinite") then
            vars["Current Box"] = lh
        end

        if settings.update_box_for_window then
            settings.update_box_for_window()
        end
        M.detect_plinite(vars, settings)
    end
end

---------------------------------------------------------------------------
-- M.open_current_plinite(vars) — Open a single plinite after picking.
-- Port of open_current_plinite from lines 3958-3964.
--
-- Pluck the plinite and stow the result.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.open_current_plinite(vars, settings)
    util.tpick_put_stuff_away(vars, settings)
    waitrt()
    fput("pluck #" .. vars["Current Box"].id)
    vars["stow_current_box"] = true
    util.tpick_put_stuff_away(vars, settings)
end

---------------------------------------------------------------------------
-- M.detect_plinite_result(vars, settings) — Send detect command, parse plinite difficulty.
-- Port of detect_plinite_result from lines 4925-4947.
--
-- dothistimeout "detect #ID", parse difficulty text, map to numeric difficulty.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.detect_plinite_result(vars, settings)
    waitrt()
    vars["Plinite Already Open"] = nil

    if vars["Use 404"] or vars["Need 404"] then
        spells.tpick_cast_spells(404, vars, settings)
    end
    if vars["Use 506"] then
        spells.tpick_cast_spells(506, vars, settings)
    end

    local result = dothistimeout("detect #" .. vars["Current Box"].id, 3, {
        "It looks like it would be.*%(%-(%d+)%)%.",
        "You struggle to determine the difficulty of the extraction %(somewhere between .* and %-(%d+)%)%.",
        "You promptly discover that the core has already been removed%.",
        "You are unable to determine the difficulty of the extraction%.",
        "You promptly discover that the core has already been extracted and merely needs to be PLUCKed",
    })

    if result then
        -- Check for difficulty number
        local difficulty = result:match("%(%-(%d+)%)%.")
        if difficulty then
            vars["Lock Difficulty"] = tonumber(difficulty)
        elseif string.find(result, "core has already been removed") then
            util.tpick_silent(nil, "This plinite has already been extracted.", settings)
            util.tpick_put_stuff_away(vars, settings)
            vars["Plinite Already Open"] = true
        elseif string.find(result, "unable to determine the difficulty") then
            vars["Can't Determine Plinite Difficulty"] = true
            vars["Lock Difficulty"] = 1000000
        elseif string.find(result, "merely needs to be PLUCKed") then
            if vars["Picking Mode"] ~= "worker" then
                M.open_current_plinite(vars, settings)
            end
            vars["Plinite Already Open"] = true
        end
    else
        -- Nil result: retry
        M.detect_plinite_result(vars, settings)
        return
    end

    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
end

---------------------------------------------------------------------------
-- M.detect_plinite(vars, settings) — Plinite extraction orchestrator.
-- Port of detect_plinite from lines 5186-5250.
--
-- Cast 404 if needed, detect difficulty, calculate lock difficulty,
-- determine recommended pick, dispatch to pick_2.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.detect_plinite(vars, settings)
    local load_data = settings.load_data
    local all_pick_ids = vars["all_pick_ids"] or {}

    -- Need 404 for detection
    if not (load_data["404"] or ""):lower():find("never") then
        vars["Need 404"] = "yes"
    end
    waitrt()

    -- Stow non-vaalin picks
    lockpicks.no_vaalin_picks(vars, settings, all_pick_ids)

    -- Get vaalin lockpick
    local vaalin_ids = all_pick_ids["Vaalin"] or {}
    local vaalin_id = vaalin_ids[1]
    if vaalin_id then
        for _ = 1, 3 do
            waitrt()
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.id == vaalin_id) or (lh and lh.id == vaalin_id) then
                break
            end
            fput("get #" .. vaalin_id)
            pause(0.2)
        end

        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (not rh or rh.id ~= vaalin_id) and (not lh or lh.id ~= vaalin_id) then
            util.tpick_silent(true, "Couldn't find your " .. (load_data["Vaalin"] or "vaalin lockpick"), settings)
            return
        end
    else
        util.tpick_silent(true, "No vaalin lockpick configured.", settings)
        return
    end

    M.detect_plinite_result(vars, settings)
    util.tpick_put_stuff_away(vars, settings)

    if not vars["Plinite Already Open"] then
        local total_pick_skill = (vars["Pick Skill"] + (vars["Pick Lore"] or 0)) * 2.50
        vars["Total Pick Skill"] = total_pick_skill
        local vaalin_lock_roll = tonumber(load_data["Vaalin Lock Roll"]) or 0

        if vars["Lock Difficulty"] > (total_pick_skill + vaalin_lock_roll) then
            if vars["Picking Mode"] == "worker" then
                util.tpick_silent(true,
                    "Can't extract this plinite based on my calculations.\n"
                    .. "If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                    settings)
                vars["Can't Determine Plinite Difficulty"] = nil
                vars["Give Up On Box"] = true
            else
                util.tpick_silent(true,
                    "Can't extract this plinite, OPENing it instead.\n"
                    .. "If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                    settings)
                vars["Can't Determine Plinite Difficulty"] = nil
                waitrt()
                fput("open #" .. vars["Current Box"].id)
            end
        else
            lockpicks.calculate_needed_lockpick(vars, settings, all_pick_ids)

            local text = "Recommended lock pick: " .. (vars["Recommended Pick"] or "unknown")
                .. " with a modifier of " .. (vars["Recommended Pick Modifier"] or "?") .. "\n"

            local temp_math_number
            if vars["403 Needed"] == "yes" then
                if vars["Use 403 For Lock Difficulty"]
                   and vars["Lock Difficulty"] > vars["Use 403 For Lock Difficulty"] then
                    text = text .. "Lock difficulty is higher than your 403 setting in setup menu, using 403.\n"
                else
                    text = text .. "Recommend 403: Yes\n"
                end
                text = text .. "Your calculated lockpicking skill: " .. (vars["Pick Skill"] or 0) .. "\n"
                text = text .. "Your calculated lockpicking lore: " .. (vars["Pick Lore"] or 0) .. "\n"
                temp_math_number = (vars["Pick Skill"] or 0) + (vars["Pick Lore"] or 0)
            else
                text = text .. "Recommend 403: No\n"
                text = text .. "Your calculated lockpicking skill: " .. (vars["Pick Skill"] or 0) .. "\n"
                temp_math_number = vars["Pick Skill"] or 0
            end

            local _quick_maths = math.floor(temp_math_number * (vars["Recommended Pick Modifier"] or 1))
            util.tpick_silent(nil, text, settings)

            if not vars["Needed Pick ID"] then
                if vars["Recommended Pick"] == "Vaalin" then
                    util.tpick_silent(true,
                        "ALL OF YOUR VAALIN LOCKPICKS ARE BROKEN. YOU REALLY SHOULD HAVE AT LEAST 1 WORKING VAALIN LOCKPICK WHEN RUNNING THIS SCRIPT.",
                        settings)
                    return
                else
                    util.tpick_silent(true,
                        "All of your " .. (vars["Recommended Pick"] or "unknown")
                        .. " lockpicks seem to be broken, trying a higher tier lockpick.",
                        settings)
                    lockpicks.next_pick(vars, settings, all_pick_ids, vars["settings_pick_names"])
                end
            else
                picking.pick_2(vars, settings, lockpicks)
            end
        end
    elseif vars["Plinite Already Open"] then
        if vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        end
    end
end

---------------------------------------------------------------------------
-- M.pop_boxes_begin(vars, settings) — Begin pop sequence.
-- Port of pop_boxes_begin from lines 4149-4203.
--
-- Get box, cast 416 (Piercing Gaze) to detect trap, route based on
-- trap type to pop_open_box or give up.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.pop_boxes_begin(vars, settings)
    local load_data = settings.load_data

    util.tpick_put_stuff_away(vars, settings)

    if vars["Picking Mode"] == "worker" then
        -- Worker mode: box is already in hand via worker logic
        -- (tpick_get_current_worker_box handled externally)
    else
        -- Get box into hand
        while not checkright() do
            fput("get #" .. (type(vars["Current Box"]) == "table" and vars["Current Box"].id or vars["Current Box"]))
            pause(0.2)
        end
        -- Wait for GameObj to update
        for _ = 1, 20 do
            local rh = GameObj.right_hand()
            if rh and rh.name and rh.name ~= "Empty" then break end
            pause(0.1)
        end
        vars["Current Box"] = GameObj.right_hand()
        if settings.update_box_for_window then
            settings.update_box_for_window()
        end
    end

    vars["Start Time"] = os.time()
    vars["Remaining 416 Casts"] = load_data["Number Of 416 Casts"]
    M.stuff_to_do(vars, settings)
    vars["Hand Status"] = nil

    if vars["Picking Mode"] == "worker" then
        if vars["Current Box"] and vars["Current Box"].name
           and string.find(vars["Current Box"].name, "mithril")
           or (vars["Current Box"] and vars["Current Box"].name and string.find(vars["Current Box"].name, "enruned"))
           or (vars["Current Box"] and vars["Current Box"].name and string.find(vars["Current Box"].name, "rune%-incised")) then
            vars["Hand Status"] = "mithril or enruned"
        else
            vars["Hand Status"] = "good"
        end
    else
        vars["Check For Command"] = "glance"
        if _G["$tpick_check_mithril_or_enruned"] then
            _G["$tpick_check_mithril_or_enruned"]()
        end
    end

    -- Wait for hand status to be set
    wait_until(function() return vars["Hand Status"] end)

    if vars["Current Box"] and vars["Current Box"].name
       and string.find(vars["Current Box"].name, "plinite")
       and vars["Picking Mode"] == "worker" then
        util.tpick_silent(true, "Can't open plinites when popping.", settings)
        vars["Give Up On Box"] = true
    elseif vars["Hand Status"] == "mithril or enruned" and load_data["Pick Enruned"] == "No" then
        util.tpick_silent(true, "Can't open this box because it is mithril or enruned.", settings)
        waitrt()
        if vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
        elseif vars["Picking Mode"] == "solo" then
            util.where_to_stow_box(vars)
        elseif vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        end
        vars["Box Opened"] = nil
    elseif vars["Hand Status"] == "empty" then
        util.tpick_silent(true, "No box was found in your hands.", settings)
        return
    else
        if load_data["Phase (704)"] == "Yes" then
            traps.cast_704_at_box(vars, settings)
        else
            util.tpick_silent(nil, "Checking for traps.", settings)
            if vars["Picking Mode"] == "ground" then
                util.tpick_drop_box(vars)
            end
            traps.check_for_trap(vars, settings)
        end
    end
end

---------------------------------------------------------------------------
-- M.pop_open_box(vars, settings) — Pop open box with 407/408.
-- Port of pop_open_box from lines 4205-4233.
--
-- Use 408 to disarm if safe, use 407 to unlock, open box, loot.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.pop_open_box(vars, settings)
    local load_data = settings.load_data

    if vars["Hand Status"] == "mithril or enruned" and load_data["Pick Enruned"] == "Yes" then
        picking.measure_lock(vars, settings, lockpicks)
        return
    end

    local box_is_open = false
    util.tpick_silent(nil, "Popping box.", settings)

    while not box_is_open do
        if not (load_data["403"] or ""):lower():find("never") then
            -- Check active spells before casting 403
            dothistimeout("spell active", 3,
                { "You currently have the following active effects" })
            spells.tpick_cast_spells(403, vars, settings)
        end
        if vars["Use 515"] then
            spells.tpick_cast_spells(515, vars, settings)
        end

        spells.tpick_prep_spell(407, "Unlock", vars, settings)
        fput("cast at #" .. vars["Current Box"].id)
        waitrt()

        while true do
            local line = get()
            if not line then break end

            -- Box resists / trap fires / roundtime
            if string.find(line, "vibrates slightly but nothing else happens")
               or string.find(line, "face breaks away and a pair of gleaming jaws snap shut")
               or string.find(line, "Roundtime") then
                break
            -- Box opened
            elseif string.find(line, "soft click from the.*and it suddenly flies open")
                   or string.find(line, "But the.*is already open") then
                vars["Do Not Ask To Check"] = true
                box_is_open = true
                break
            end
        end
    end

    if vars["Picking Mode"] ~= "ground" and vars["Picking Mode"] ~= "worker" then
        M.open_solo(vars, settings, settings.stats_data)
    end
end

---------------------------------------------------------------------------
-- M.pop_start(vars, settings) — Pop mode entry.
-- Port of pop_start from lines 4375-4382.
--
-- Loop through All Box IDs, get each box, call pop_boxes_begin.
-- Then check disk.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.pop_start(vars, settings)
    stats.total_boxes_count(vars, settings.stats_data)

    local all_box_ids = vars["All Box IDs"] or {}
    for _, box_id in ipairs(all_box_ids) do
        vars["Current Box"] = box_id
        M.pop_boxes_begin(vars, settings)
    end

    M.check_disk(vars, settings)
end

---------------------------------------------------------------------------
-- M.relock_boxes_for_rogues(vars, settings) — Rogues guild relock task.
-- Port of relock_boxes_for_rogues from lines 3899-3916.
--
-- Get the needed lockpick, relock the box via LMAS RELOCK, then pick it
-- open again for guild credit.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.relock_boxes_for_rogues(vars, settings)
    -- Get lockpick into hand
    while not checkright() do
        waitrt()
        fput("get #" .. vars["Needed Pick ID"])
        pause(0.3)
    end

    -- Relock loop
    while true do
        waitrt()
        local result = dothistimeout("lmas relock #" .. vars["Current Box"].id, 5,
            { "Then%.%.%.CLICK!  It locks!" })
        if result and string.find(result, "CLICK!  It locks!") then
            break
        end
    end

    -- Pick open loop
    while true do
        waitrt()
        local result = dothistimeout("pick #" .. vars["Current Box"].id, 5,
            { "Then%.%.%.CLICK!  It opens!" })
        if result and string.find(result, "CLICK!  It opens!") then
            break
        end
    end

    util.tpick_put_stuff_away(vars, settings)
end

return M
