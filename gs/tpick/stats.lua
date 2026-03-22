local M = {}
local data = require("tpick/data")
local util = require("tpick/util")

--- Initialize the full stats_data table with all tracked fields.
-- Persisted fields default to 0; session fields are ephemeral.
-- Per-trap and per-lockpick fields are generated dynamically from data tables.
-- @return stats_data  The initialized stats table.
function M.init()
    local stats_data = {}

    -- Per-trap encounter counts (from data.TRAP_NAMES)
    for _, trap in ipairs(data.TRAP_NAMES) do
        stats_data[trap] = 0
    end

    -- Per-lockpick open/break tracking (hash tables keyed by pick material)
    stats_data["Opened/Broke For Each Pick"] = {}
    stats_data["Locks Opened Since Last Pick Broke"] = 0

    -- Pool (locksmith worker) stats
    stats_data["Pool Boxes Picked"] = 0
    stats_data["Pool Tips Silvers"] = 0
    stats_data["Pool Scarabs Received"] = 0
    stats_data["Pool Time Spent Picking"] = 0
    stats_data["Pool Time Spent Waiting"] = 0

    -- Non-pool (solo/ground/other) stats
    stats_data["Non-Pool Boxes Picked"] = 0
    stats_data["Non-Pool Time Spent Picking"] = 0

    -- Loot tracking
    stats_data["Boxes Looted"] = 0
    stats_data["Loot Total"] = {}
    stats_data["Loot Session"] = {}

    -- Session-only stats (not persisted)
    stats_data["Session Start Time"] = os.time()
    stats_data["Session Boxes Picked"] = 0

    return stats_data
end

--- Merge loaded stats into an initialized stats_data table.
-- Numeric fields are coerced to int; hash fields are preserved as tables.
-- Session fields are always reset fresh.
-- @param stats_data     The freshly init'd stats table.
-- @param loaded         The table loaded from disk (may be nil or partial).
-- @param track_loot     Whether loot tracking is enabled ("Yes"/"No").
-- @return stats_data    The merged table.
function M.merge_loaded(stats_data, loaded, track_loot)
    if not loaded then return stats_data end

    -- Hash-valued keys that should stay as tables
    local hash_keys = {
        ["Opened/Broke For Each Pick"] = true,
        ["Loot Total"] = true,
        ["Loot Session"] = true,
    }

    -- Session keys that are never loaded from disk
    local session_keys = {
        ["Session Start Time"] = true,
        ["Session Boxes Picked"] = true,
    }

    for key, default in pairs(stats_data) do
        if session_keys[key] then
            -- Keep the fresh init value
        elseif key == "Loot Total" then
            if track_loot == "No" then
                stats_data[key] = {}
            elseif loaded[key] and type(loaded[key]) == "table" then
                -- Coerce all values to int
                local tbl = {}
                for k, v in pairs(loaded[key]) do
                    tbl[k] = math.floor(tonumber(v) or 0)
                end
                stats_data[key] = tbl
            end
        elseif key == "Loot Session" then
            -- Always start fresh
            stats_data[key] = {}
        elseif hash_keys[key] then
            if loaded[key] and type(loaded[key]) == "table" then
                local tbl = {}
                for k, v in pairs(loaded[key]) do
                    tbl[k] = math.floor(tonumber(v) or 0)
                end
                stats_data[key] = tbl
            end
        else
            if loaded[key] ~= nil then
                stats_data[key] = math.floor(tonumber(loaded[key]) or 0)
            end
        end
    end

    return stats_data
end

--- Update all stats after each box cycle (port of update_all_stats, lines 5500-5508).
-- Accumulates pool picking time if in worker mode, then signals UI refresh.
-- @param vars        The tpick_vars working state.
-- @param stats_data  The stats table to update.
function M.update(vars, stats_data)
    if vars["Worker Start Time"] then
        stats_data["Pool Time Spent Picking"] = stats_data["Pool Time Spent Picking"]
            + os.difftime(os.time(), vars["Worker Start Time"])
        vars["Worker Start Time"] = os.time()
    end
end

--- Compute derived totals and display end-of-box summary (port of total_boxes_picked_math, lines 4745-4785).
-- Records picking time and box count for non-pool modes, prints summary.
-- @param vars        The tpick_vars working state.
-- @param stats_data  The stats table.
function M.total_boxes_picked_math(vars, stats_data)
    if vars["Update Information"] then
        if not vars["Box Math"] then
            util.tpick_silent(nil, "This box was not added to your total boxes picked nor was the time spent opening it recorded.", {
                load_data = vars["_load_data"] or {},
                vars = vars,
            })
        else
            local total_picking_time = os.difftime(os.time(), vars["Start Time"])
            stats_data["Non-Pool Time Spent Picking"] = stats_data["Non-Pool Time Spent Picking"] + total_picking_time
            stats_data["Non-Pool Boxes Picked"] = stats_data["Non-Pool Boxes Picked"] + 1
            stats_data["Session Boxes Picked"] = stats_data["Session Boxes Picked"] + 1
        end
        if vars["Picking Mode"] == "solo" or vars["Picking Mode"] == "ground" then
            vars["Total Boxes Number"] = vars["Total Boxes Number"] - 1
            if vars["Total Boxes Number"] < 0 then
                vars["Total Boxes Number"] = 0
            end
        end
    end

    -- Round non-pool picking time
    if stats_data["Non-Pool Time Spent Picking"] ~= 0 then
        stats_data["Non-Pool Time Spent Picking"] = math.floor(stats_data["Non-Pool Time Spent Picking"] * 100 + 0.5) / 100
    end

    local average_picking_time = 0
    if stats_data["Non-Pool Boxes Picked"] > 0 then
        average_picking_time = math.floor((stats_data["Non-Pool Time Spent Picking"] / stats_data["Non-Pool Boxes Picked"]) * 100 + 0.5) / 100

        respond("")
        respond("####################")
        respond("####################")
        respond("Total boxes picked: " .. util.add_commas(stats_data["Non-Pool Boxes Picked"]))
        respond("Total time picking: " .. util.add_commas(stats_data["Non-Pool Time Spent Picking"]) .. " seconds")
        respond("Average time per box: " .. tostring(average_picking_time) .. " seconds")
        respond("####################")
        respond("####################")
        respond("")
    end

    if (vars["Picking Mode"] == "solo" or vars["Picking Mode"] == "ground")
        and vars["Total Boxes Number"] and vars["Total Boxes Number"] > 0 then
        respond("")
        respond("####################")
        respond("####################")
        respond("Boxes remaining: " .. tostring(vars["Total Boxes Number"]))
        if stats_data["Non-Pool Boxes Picked"] > 0 then
            local time_left = math.floor((vars["Total Boxes Number"] * average_picking_time) * 100 + 0.5) / 100
            respond("Estimated time remaining: " .. tostring(time_left) .. " seconds")
        end
        respond("####################")
        respond("####################")
        respond("")
    end

    vars["Box Math"] = true
end

--- Count remaining boxes to process for ground/solo modes (port of total_boxes_count, lines 4825-4833).
-- Resets Total Boxes Number then counts based on mode.
-- @param vars        The tpick_vars working state.
-- @param stats_data  The stats table (passed through to total_boxes_picked_math).
function M.total_boxes_count(vars, stats_data)
    vars["Total Boxes Number"] = 0
    if vars["Picking Mode"] == "ground" then
        local loot = GameObj.loot()
        for _, item in ipairs(loot) do
            if item.type == "box" then
                -- Skip boxes already picked
                local already_picked = false
                if vars["Box IDs Already Picked"] then
                    for _, id in ipairs(vars["Box IDs Already Picked"]) do
                        if id == item.id then
                            already_picked = true
                            break
                        end
                    end
                end
                if not already_picked then
                    vars["Total Boxes Number"] = vars["Total Boxes Number"] + 1
                end
            end
        end
    elseif vars["Picking Mode"] == "solo" then
        if vars["All Box IDs"] then
            vars["Total Boxes Number"] = #vars["All Box IDs"]
        end
    end
    M.total_boxes_picked_math(vars, stats_data)
end

--- Reset per-box working variables before processing each new box (port of start_values_nilled, lines 4835-4853).
-- Clears trap, lock, difficulty, and other transient state.
-- @param vars        The tpick_vars working state.
-- @param load_data   The settings table (for 403 check).
function M.start_values_nilled(vars, load_data)
    vars["Number Of Vial Disarm Tries"] = 0
    vars["Scale Trap Found"] = nil
    vars["Current Trap Type"] = nil
    vars["Time To Disarm Trap"] = nil
    vars["True Lock Difficulty"] = nil
    vars["Box Has Glyph Trap"] = nil
    vars["Use 404/Trap Higher Than Setting"] = nil
    vars["Current Box"] = nil
    vars["Lock Difficulty"] = nil
    vars["Trap Difficulty"] = nil
    vars["Offered Tip Amount"] = nil
    vars["Critter Name"] = nil
    vars["Critter Level"] = nil
    vars["Window Message"] = nil
    vars["Need 403"] = nil
    if load_data and load_data["403"] and string.find(load_data["403"], "yes") then
        vars["Need 403"] = true
    end
end

--- Count boxes in the character's disk for solo mode (port of count_boxes_in_disk, lines 4855-4870).
-- Finds the character's disk/coffin in the room, looks inside if needed,
-- then counts items with type "box".
-- @param vars  The tpick_vars working state. Increments vars["Total Number Of Boxes"]
--              and appends to vars["All Box IDs"].
function M.count_boxes_in_disk(vars)
    -- Find character's disk in loot
    local char_name = GameState.name
    local disk = nil
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if (obj.noun == "disk" or obj.noun == "coffin")
            and obj.name and string.find(obj.name, char_name) then
            disk = obj
            break
        end
    end

    -- Wait up to 4 seconds for disk to appear
    if not disk then
        util.tpick_silent(true, "Waiting 4 seconds for disk", {
            load_data = vars["_load_data"] or {},
            vars = vars,
        })
        for _ = 1, 40 do
            loot = GameObj.loot()
            for _, obj in ipairs(loot) do
                if (obj.noun == "disk" or obj.noun == "coffin")
                    and obj.name and string.find(obj.name, char_name) then
                    disk = obj
                    break
                end
            end
            if disk then break end
            pause(0.1)
        end
    end

    if not disk then return end

    -- If disk contents not loaded, look inside to trigger population
    if not disk.contents then
        dothistimeout("look in #" .. disk.id, 3, "In the|There is nothing in")
    end

    -- Count boxes in disk
    if disk.contents then
        for _, item in ipairs(disk.contents) do
            if item.type and string.find(string.lower(item.type), "box") then
                vars["Total Number Of Boxes"] = (vars["Total Number Of Boxes"] or 0) + 1
                if not vars["All Box IDs"] then
                    vars["All Box IDs"] = {}
                end
                table.insert(vars["All Box IDs"], item.id)
            end
        end
    end
end

--- Reset ALL stats to zero/empty (port of reset_stats, lines 974-981 + line 1621).
-- Wipes all fields back to initial state; session fields get fresh timestamps.
-- @param stats_data  The stats table to reset in-place.
function M.reset(stats_data)
    -- Zero out all numeric fields
    for key, value in pairs(stats_data) do
        if type(value) == "number" then
            stats_data[key] = 0
        elseif type(value) == "table" then
            stats_data[key] = {}
        end
    end
    -- Re-set session start time
    stats_data["Session Start Time"] = os.time()
end

--- Build the stats_info table used for display (port of set_stat_info, lines 823-831).
-- Computes derived totals: Total Boxes Picked, Total Time Spent Picking, Total Traps.
-- @param stats_data  The raw stats table.
-- @return stats_info  A copy with derived fields added.
function M.set_stat_info(stats_data)
    local info = {}
    for k, v in pairs(stats_data) do
        info[k] = v
    end

    -- Subtract wait time from pool picking time for display
    info["Pool Time Spent Picking"] = (info["Pool Time Spent Picking"] or 0)
        - (info["Pool Time Spent Waiting"] or 0)

    -- Derived totals
    info["Total Boxes Picked"] = (info["Pool Boxes Picked"] or 0)
        + (info["Non-Pool Boxes Picked"] or 0)
    info["Total Time Spent Picking"] = (info["Pool Time Spent Picking"] or 0)
        + (info["Non-Pool Time Spent Picking"] or 0)

    -- Sum all trap encounters
    info["Total Traps"] = 0
    for _, trap in ipairs(data.TRAP_NAMES) do
        if info[trap] then
            info["Total Traps"] = info["Total Traps"] + info[trap]
        end
    end

    -- Compute pool silvers
    local scarab_value = info["Scarab Value"] or 0
    local scarab_silvers = (info["Pool Scarabs Received"] or 0) * scarab_value
    info["Pool Scarab Silvers"] = scarab_silvers
    info["Pool Total Silvers"] = scarab_silvers + (info["Pool Tips Silvers"] or 0)
    local total_pool_time = (info["Pool Time Spent Picking"] or 0) + (info["Pool Time Spent Waiting"] or 0)
    if total_pool_time > 0 then
        info["Pool Silvers/Hour"] = math.floor((info["Pool Total Silvers"] / total_pool_time) * 3600)
    else
        info["Pool Silvers/Hour"] = 0
    end

    return info
end

--- Format a time value in seconds as HH:MM:SS (port of time formatting, line 872).
-- @param seconds  Number of seconds.
-- @return string  Formatted as "HH:MM:SS".
function M.format_time(seconds)
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds / 60) % 60
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

--- Record a trap encounter in stats (used by trap detection code).
-- @param stats_data  The stats table.
-- @param trap_type   The trap name string (must match a data.TRAP_NAMES entry).
function M.record_trap(stats_data, trap_type)
    if trap_type and stats_data[trap_type] ~= nil then
        stats_data[trap_type] = stats_data[trap_type] + 1
    end
end

--- Record a successful lock pick in the per-lockpick tracker (port of lines 2885-2890).
-- @param stats_data  The stats table.
-- @param pick_name   The lockpick material name.
function M.record_pick_success(stats_data, pick_name)
    stats_data["Locks Opened Since Last Pick Broke"] = (stats_data["Locks Opened Since Last Pick Broke"] or 0) + 1
    local per_pick = stats_data["Opened/Broke For Each Pick"]
    if per_pick then
        per_pick[pick_name] = (per_pick[pick_name] or 0) + 1
    end
end

--- Record a lockpick breaking (port of lines 3042-3044).
-- Resets the per-pick counter for this material and the global since-last-break counter.
-- @param stats_data  The stats table.
-- @param pick_name   The lockpick material name that broke.
-- @return picks_before  How many picks this lockpick had before breaking.
-- @return total_since   How many total picks since last break of any lockpick.
function M.record_pick_broke(stats_data, pick_name)
    local per_pick = stats_data["Opened/Broke For Each Pick"] or {}
    local picks_before = per_pick[pick_name] or 0
    local total_since = stats_data["Locks Opened Since Last Pick Broke"] or 0

    -- Reset counters
    stats_data["Locks Opened Since Last Pick Broke"] = 0
    per_pick[pick_name] = 0

    return picks_before, total_since
end

--- Record pool box completion with tip (port of lines 4876-4879).
-- @param stats_data  The stats table.
-- @param tip_amount  Silvers received as tip.
function M.record_pool_box(stats_data, tip_amount)
    stats_data["Pool Tips Silvers"] = (stats_data["Pool Tips Silvers"] or 0) + tip_amount
    if not stats_data["Loot Session"] then stats_data["Loot Session"] = {} end
    stats_data["Loot Session"]["Silver"] = (stats_data["Loot Session"]["Silver"] or 0) + tip_amount
    stats_data["Pool Boxes Picked"] = (stats_data["Pool Boxes Picked"] or 0) + 1
    stats_data["Session Boxes Picked"] = (stats_data["Session Boxes Picked"] or 0) + 1
end

--- Record pool wait time (port of lines 4554, 4573, 4575).
-- @param stats_data   The stats table.
-- @param wait_seconds Number of seconds waited.
function M.record_pool_wait(stats_data, wait_seconds)
    stats_data["Pool Time Spent Waiting"] = (stats_data["Pool Time Spent Waiting"] or 0) + wait_seconds
end

--- Record a scarab found in pool mode (port of lines 3687-3689).
-- @param stats_data  The stats table.
-- @param track_loot  Whether to also track in Loot Total ("Yes"/"No").
function M.record_scarab(stats_data, track_loot)
    stats_data["Pool Scarabs Received"] = (stats_data["Pool Scarabs Received"] or 0) + 1
    if not stats_data["Loot Session"] then stats_data["Loot Session"] = {} end
    stats_data["Loot Session"]["Scarabs"] = (stats_data["Loot Session"]["Scarabs"] or 0) + 1
    if track_loot == "Yes" then
        if not stats_data["Loot Total"] then stats_data["Loot Total"] = {} end
        stats_data["Loot Total"]["Scarabs"] = (stats_data["Loot Total"]["Scarabs"] or 0) + 1
    end
end

--- Record box looted (port of lines 2139, 2244, 5743).
-- @param stats_data  The stats table.
function M.record_box_looted(stats_data)
    stats_data["Boxes Looted"] = (stats_data["Boxes Looted"] or 0) + 1
end

--- Record silvers looted from a box (port of lines 5141-5142).
-- @param stats_data    The stats table.
-- @param silvers       Amount of silvers found.
-- @param track_loot    Whether to persist in Loot Total ("Yes"/"No").
function M.record_silvers(stats_data, silvers, track_loot)
    if not stats_data["Loot Session"] then stats_data["Loot Session"] = {} end
    stats_data["Loot Session"]["Silver"] = (stats_data["Loot Session"]["Silver"] or 0) + silvers
    if track_loot == "Yes" then
        if not stats_data["Loot Total"] then stats_data["Loot Total"] = {} end
        stats_data["Loot Total"]["Silver"] = (stats_data["Loot Total"]["Silver"] or 0) + silvers
    end
end

--- Record a loot item found in a box (port of lines 5162-5163).
-- @param stats_data    The stats table.
-- @param item_name     Name of the item.
-- @param item_type     Type of the item (for filtering junk from totals).
-- @param track_loot    Whether to persist in Loot Total ("Yes"/"No").
function M.record_loot_item(stats_data, item_name, item_type, track_loot)
    if not stats_data["Loot Session"] then stats_data["Loot Session"] = {} end
    stats_data["Loot Session"][item_name] = (stats_data["Loot Session"][item_name] or 0) + 1

    -- Only track non-junk items in Loot Total
    local junk_types = { clothing = true, junk = true, food = true, herb = true, cursed = true, toy = true, ammo = true }
    if track_loot == "Yes" and not junk_types[item_type] then
        if not stats_data["Loot Total"] then stats_data["Loot Total"] = {} end
        stats_data["Loot Total"][item_name] = (stats_data["Loot Total"][item_name] or 0) + 1
    end
end

return M
