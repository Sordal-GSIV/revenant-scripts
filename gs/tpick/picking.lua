-- tpick/picking.lua — Lock picking system: measurement, pick loop, tricks, wedging, bashing, relocking
-- Ported from tpick.lic lines 1947-1956, 2049-2073, 2164-2218, 2409-2742, 2744-3130, 4896-4923, 5346-5365
-- Original authors: Dreaven et al.

local M = {}
local data = require("tpick/data")
local util -- set by wire()

-- Cross-module function references set by wire()
local lockpicks       -- lockpicks module (next_pick, lock_pick_information, etc.)
local traps           -- traps module (disarm_scale, manually_disarm_trap, etc.)
local spells          -- spells module (tpick_cast_spells, tpick_stop_spell, cast_407)
local modes           -- modes module (open_solo, open_others, open_current_plinite, etc.)

---------------------------------------------------------------------------
-- M.wire(funcs) — Inject cross-module dependencies.
-- Called once during init before any picking functions are used.
--
-- @param funcs  Table with keys: util, lockpicks, traps, spells, modes
---------------------------------------------------------------------------
function M.wire(funcs)
    util      = funcs.util      or require("tpick/util")
    lockpicks = funcs.lockpicks or require("tpick/lockpicks")
    traps     = funcs.traps
    spells    = funcs.spells
    modes     = funcs.modes
end

---------------------------------------------------------------------------
-- M.calibrate_calipers(vars, settings) — Calibrate lockpicking calipers.
-- Port of lines 2049-2073.
--
-- Rogue-only. Gets calipers from container, sends LMAS CALIBRATE,
-- retries on Roundtime, stows on success or "leave them alone".
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.calibrate_calipers(vars, settings)
    -- Respect external flag to skip calibration
    if vars["rogue_do_not_calibrate_calipers"] then
        return
    end

    util.tpick_silent(nil, "Calibrating calipers.", settings)

    -- Get calipers into hand (up to 3 attempts)
    for _ = 1, 3 do
        waitrt()
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local rh_name = rh and rh.name or ""
        local lh_name = lh and lh.name or ""
        if string.find(rh_name, "calipers") or string.find(lh_name, "calipers") then
            break
        end
        fput("get my calipers")
        pause(0.2)
    end

    -- Verify calipers are in hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_name = rh and rh.name or ""
    local lh_name = lh and lh.name or ""
    if not string.find(rh_name, "calipers") and not string.find(lh_name, "calipers") then
        util.tpick_silent(true,
            "Couldn't find your calipers.\n"
            .. "To fix the below issues enter ;tpick setup\n"
            .. "Make sure your calipers container is filled out properly and that you have calipers.\n"
            .. "If you don't want to use calipers then go to the 'Other' tab and uncheck the box for the setting 'Use Calipers.'",
            settings)
        error("tpick: Calipers not found")
    end

    local result = dothistimeout("lmas calibrate my calipers", 4,
        { "You're good, but you're not that good",
          "You should leave them alone",
          "Roundtime" })

    if result and (string.find(result, "You're good") or string.find(result, "You should leave them alone")) then
        util.tpick_put_stuff_away(vars, settings)
    elseif result and string.find(result, "Roundtime") then
        waitrt()
        if vars["Can Use Calipers"] then
            M.calibrate_calipers(vars, settings)
        end
    elseif not result then
        M.calibrate_calipers(vars, settings)
    end
end

---------------------------------------------------------------------------
-- M.wedge_lock(vars, settings) — Open lock with a wedge.
-- Port of lines 2164-2218.
--
-- Gets wedge (Rogue only), sends LMASTER WEDGE, handles success/retry/failure.
-- Falls back to 407 or gives up depending on settings and mode.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.wedge_lock(vars, settings)
    local load_data = settings.load_data
    waitrt()

    -- Get box if on ground and hands empty
    if vars["Picking Mode"] == "ground" and not checkright() then
        util.tpick_get_box(vars)
    end

    -- Rogues: get wedge into hand (up to 3 attempts)
    if Stats.prof == "Rogue" then
        for _ = 1, 3 do
            waitrt()
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local rh_name = rh and rh.name or ""
            local lh_name = lh and lh.name or ""
            if string.find(rh_name, "wedge") or string.find(lh_name, "wedge") then
                break
            end
            fput("get my wedge")
            pause(0.2)
        end
    end

    -- Check if wedge is in hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_name = rh and rh.name or ""
    local lh_name = lh and lh.name or ""

    if not string.find(rh_name, "wedge") and not string.find(lh_name, "wedge") then
        -- No wedge available
        if vars["Use A Wedge"] then
            util.tpick_silent(true,
                "Currently working on a ;rogues task for using a wedge but you appear to be out of wedges.\n"
                .. ";tpick will now exit and ;rogues will create more wedges then start ;tpick again.",
                settings)
            error("tpick: Out of wedges for rogues task")
        else
            if load_data["Unlock (407)"] == "Never" or not Spell[407].known then
                util.tpick_silent(true, "Couldn't open this box.", settings)
                if vars["Picking Mode"] == "other" then
                    util.tpick_say("Can't Open Box", settings)
                    if modes and modes.open_others then
                        modes.open_others(vars, settings)
                    end
                elseif vars["Picking Mode"] == "ground" then
                    vars["Box Opened"] = nil
                elseif vars["Picking Mode"] == "solo" then
                    util.where_to_stow_box(vars)
                    util.tpick_put_stuff_away(vars, settings)
                    pause(0.1)
                elseif vars["Picking Mode"] == "worker" then
                    vars["Give Up On Box"] = true
                end
            else
                if Stats.prof == "Rogue" then
                    util.tpick_silent(nil, "Couldn't find any wedges, going to try popping this box.", settings)
                else
                    util.tpick_silent(nil, "Going to try popping this box.", settings)
                end
                if spells and spells.cast_407 then
                    spells.cast_407(vars, settings)
                end
            end
        end
    else
        -- Have wedge, attempt to wedge the lock
        local box_id = vars["Current Box"].id
        local result = dothistimeout("lmaster wedge #" .. box_id, 3,
            { "What do you expect to wedge it with",
              "suddenly splits away from the casing",
              "Why bother",
              "Roundtime" })

        if result and string.find(result, "What do you expect to wedge it with") then
            util.tpick_put_stuff_away(vars, settings)
            M.wedge_lock(vars, settings)
        elseif result and (string.find(result, "suddenly splits away from the casing") or string.find(result, "Why bother")) then
            util.tpick_put_stuff_away(vars, settings)
            if vars["Picking Mode"] == "solo" and modes and modes.open_solo then
                modes.open_solo(vars, settings)
            elseif vars["Picking Mode"] == "other" and modes and modes.open_others then
                modes.open_others(vars, settings)
            elseif vars["Picking Mode"] == "ground" then
                util.tpick_drop_box(vars)
            elseif vars["Picking Mode"] == "worker" then
                -- Worker wedge success: done with this box
            end
        elseif (result and string.find(result, "Roundtime")) or not result then
            M.wedge_lock(vars, settings)
        end
    end
end

---------------------------------------------------------------------------
-- M.do_relock_boxes(vars, settings, lockpicks_mod) — Relock box after opening.
-- Port of lines 1947-1956.
--
-- Used for rogues guild relock tasks. Gets vaalin lockpick, closes box,
-- sends LMAS RELOCK, then drops/stows.
--
-- @param vars          Mutable picking state table.
-- @param settings      Settings table with load_data.
-- @param lockpicks_mod Lockpicks module reference (for no_vaalin_picks, all_pick_ids).
---------------------------------------------------------------------------
function M.do_relock_boxes(vars, settings, lockpicks_mod)
    local lp = lockpicks_mod or lockpicks
    local all_pick_ids = vars["all_pick_ids"] or {}

    -- Validate vaalin picks exist
    if lp and lp.no_vaalin_picks then
        lp.no_vaalin_picks(vars, settings, all_pick_ids)
    end

    waitrt()
    if vars["Picking Mode"] == "ground" then
        util.tpick_get_box(vars)
    end

    local vaalin_ids = all_pick_ids["Vaalin"] or {}
    if vaalin_ids[1] then
        fput("get #" .. vaalin_ids[1])
    end
    fput("close #" .. vars["Current Box"].id)
    fput("lm relock #" .. vars["Current Box"].id)

    if vars["Picking Mode"] == "ground" then
        util.tpick_drop_box(vars)
    end
    util.tpick_put_stuff_away(vars, settings)
end

---------------------------------------------------------------------------
-- M.measure_detection(vars, settings) — Measure lock difficulty via calipers
-- (Rogue) or loresinging (Bard).
-- Port of lines 4988-5071.
--
-- Sets vars["Lock Difficulty"] to a numeric value, "not locked",
-- "can't find trap", "can't measure", "need vaalin", or "Soul Golem".
-- Also sets vars["Measured Lock"] for calibration tracking.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.measure_detection(vars, settings)
    local load_data = settings.load_data
    vars["Lock Difficulty"] = nil
    vars["Measured Lock"] = nil

    if Stats.prof == "Rogue" then
        util.tpick_silent(nil, "Measuring lock.", settings)
        -- Get calipers (up to 3 attempts)
        for _ = 1, 3 do
            waitrt()
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local rh_name = rh and rh.name or ""
            local lh_name = lh and lh.name or ""
            if string.find(rh_name, "calipers") or string.find(lh_name, "calipers") then
                break
            end
            fput("get my calipers")
            pause(0.2)
        end
        -- Verify calipers in hand
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local rh_name = rh and rh.name or ""
        local lh_name = lh and lh.name or ""
        if not string.find(rh_name, "calipers") and not string.find(lh_name, "calipers") then
            util.tpick_silent(true,
                "To fix the below issues enter ;tpick setup\n"
                .. "Make sure your calipers container is filled out properly and that you have calipers.\n"
                .. "If you don't want to use calipers then go to the 'Other' tab and uncheck the box for the 'Use Calipers' setting.\n\n"
                .. "Couldn't find your calipers.",
                settings)
            error("tpick: Calipers not found")
        end
        fput("lmaster measure #" .. vars["Current Box"].id)

    elseif Stats.prof == "Bard" then
        util.tpick_silent(nil, "Loresinging to box to find out lock difficulty.", settings)
        if vars["Picking Mode"] == "ground" then
            util.tpick_get_box(vars)
            -- Wait until box is in hand
            while true do
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                if (rh and rh.id == vars["Current Box"].id) or (lh and lh.id == vars["Current Box"].id) then
                    break
                end
                pause(0.1)
            end
        end
        waitrt()
        fput("speak bard")

        local loresong_cmd
        if vars["Picking Mode"] == "worker" then
            local char_name = checkname() or ""
            local box_noun = vars["Current Box"].noun or "box"
            local pool_table = vars["Pool Table"] or "table"
            loresong_cmd = "loresing ::" .. char_name .. " " .. box_noun .. " on " .. pool_table
                .. ":: " .. box_noun .. " that looks like a clock;What's the purpose of your lock?"
        else
            local rh_name = checkright() or "box"
            loresong_cmd = "loresing " .. rh_name .. " that I hold;let your purpose now be told"
        end

        -- Send loresing command, retry until "You sing" received
        local finished = false
        while not finished do
            local result = dothistimeout(loresong_cmd, 2, { "^You sing" })
            if result and string.find(result, "You sing") then
                finished = true
            end
        end
    end

    -- Parse the response for lock difficulty
    while true do
        local line = get()
        if not line then break end

        -- Numeric difficulty from calipers: "-NNN in thief-lingo difficulty ranking"
        local numeric_diff = string.match(line, "%-(%d+) in thief%-lingo difficulty ranking")
        if numeric_diff then
            vars["Lock Difficulty"] = tonumber(numeric_diff)
            break
        end

        -- Check loresing text difficulty descriptions
        for desc, value in pairs(data.LOCK_DIFFICULTIES) do
            if string.find(line, desc, 1, true) then
                vars["Lock Difficulty"] = value
                break
            end
        end
        if vars["Lock Difficulty"] then break end

        -- Soul golem / trapped box detection
        if string.find(line, "You place the probe in the lock and grimace as something feels horribly wrong") then
            local critter_name = vars["Critter Name"] or ""
            if string.find(string.lower(critter_name), "soul golem") then
                vars["Lock Difficulty"] = "need vaalin"
            else
                if vars["Picking Mode"] == "worker" then
                    vars["Give Up On Box"] = true
                    vars["Lock Difficulty"] = "Soul Golem"
                else
                    vars["Lock Difficulty"] = "need vaalin"
                end
            end
            break
        end

        -- Already unlocked
        if string.find(string.lower(line), "has already been unlocked") then
            vars["Lock Difficulty"] = "not locked"
            break
        end

        -- Can't find trap (rogue calipers on undetected trap)
        if string.find(line, "As you start to place the probe in the lock") then
            vars["Lock Difficulty"] = "can't find trap"
            break
        end

        -- Bard loresing insufficient skill
        if string.find(line, "but your song simply wasn't powerful enough") then
            vars["Lock Difficulty"] = "can't measure"
            break
        end

        -- Invalid target
        if string.find(line, "^Try measuring something with a lock%.") then
            error("tpick: Invalid measure target")
        end
    end

    waitrt()

    -- Store measured value for calibration comparison
    if type(vars["Lock Difficulty"]) == "number" then
        vars["Measured Lock"] = vars["Lock Difficulty"]
    end

    -- Apply Lock Buffer
    local lock_buffer = tonumber(load_data["Lock Buffer"]) or 0
    if type(vars["Lock Difficulty"]) == "number" and lock_buffer > 0 then
        vars["Lock Difficulty"] = vars["Lock Difficulty"] + lock_buffer
        util.tpick_silent(nil,
            "You have lock buffer set to " .. lock_buffer
            .. ", going to assume this lock is +" .. lock_buffer
            .. " higher at -" .. vars["Lock Difficulty"],
            settings)
    end

    -- Retry measurement up to 3 times for "can't measure"
    vars["Number Of Times To Measure"] = (vars["Number Of Times To Measure"] or 0) + 1
    if vars["Lock Difficulty"] == "can't measure" and vars["Number Of Times To Measure"] < 3 then
        M.measure_detection(vars, settings)
    elseif vars["Lock Difficulty"] == "IMPOSSIBLE" then
        vars["Lock Difficulty"] = "can't measure"
    end

    -- Update info window
    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
end

---------------------------------------------------------------------------
-- M.roll_amount_check(vars, settings) — Parse d100 roll from pick result
-- and decide whether to retry same pick or advance to next tier.
-- Port of lines 4896-4923.
--
-- For non-Vaalin picks: compare roll to Lock Roll setting.
-- For Vaalin picks: compare roll to Vaalin Lock Roll setting, possibly flag 403.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.roll_amount_check(vars, settings)
    local load_data = settings.load_data
    waitrt()

    local needed_pick = vars["Needed Pick"]
    local vaalin_pick = load_data["Vaalin"]
    local roll = vars["Roll Amount"] or 0
    local lock_roll = tonumber(load_data["Lock Roll"]) or 0
    local vaalin_lock_roll = tonumber(load_data["Vaalin Lock Roll"]) or 0

    if needed_pick ~= vaalin_pick then
        -- Non-Vaalin pick
        if roll > lock_roll then
            util.tpick_silent(nil,
                "You rolled: " .. roll .. ", your Lock Roll setting: " .. lock_roll .. ". Trying next pick.",
                settings)
            util.tpick_put_stuff_away(vars, settings)
            vars["Next Task"] = "nextpick"
        else
            util.tpick_silent(nil,
                "You rolled: " .. roll .. ", your Lock Roll setting: " .. lock_roll .. ". Trying same pick again",
                settings)
            vars["Next Task"] = "pick3"
        end
    else
        -- Vaalin pick
        if roll > vaalin_lock_roll then
            local four03_setting = (load_data["403"] or ""):lower()
            if not vars["403 Needed"] and not string.find(four03_setting, "never") then
                util.tpick_silent(nil,
                    "You rolled: " .. roll .. ", your Vaalin Lock Roll setting: " .. vaalin_lock_roll
                    .. ". Going to use 403 now.",
                    settings)
                vars["Roll Amount"] = 99
            else
                util.tpick_silent(true,
                    "You rolled: " .. roll .. ", your Vaalin Lock Roll setting: " .. vaalin_lock_roll
                    .. ". You are already using 403 or your settings are set to never use 403. According to your Vaalin Lock Roll setting you should stop trying to use lockpicks.",
                    settings)
                vars["Roll Amount"] = 100
            end
            util.tpick_put_stuff_away(vars, settings)
            vars["Next Task"] = "nextpick"
        else
            util.tpick_silent(nil,
                "You rolled: " .. roll .. ", your Vaalin Lock Roll setting: " .. vaalin_lock_roll
                .. ". Trying same pick again",
                settings)
            vars["Next Task"] = "pick3"
        end
    end
end

---------------------------------------------------------------------------
-- M.bash_the_box_open(vars, settings) — Warrior box bashing.
-- Port of lines 5346-5365.
--
-- Drops box if held, tries OPEN first (might be unlocked), then BASH
-- in a loop until the box is gone.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.bash_the_box_open(vars, settings)
    local load_data = settings.load_data
    local box_id = vars["Current Box"].id

    -- Drop box if holding it
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (rh and rh.id == box_id) or (lh and lh.id == box_id) then
        fput("drop #" .. box_id)
    end

    util.tpick_silent(nil, "Bashing open box.", settings)
    waitrt()

    local result = dothistimeout("open #" .. box_id, 3,
        { "That is already open",
          "You open",
          "It appears to be locked" })

    if result and (string.find(result, "That is already open") or string.find(result, "You open")) then
        vars["Box Math"] = nil
        vars["Box Was Not Locked"] = true
    elseif result and string.find(result, "It appears to be locked") then
        local bash_weapon = load_data["Bashing Weapon"] or ""
        fput("get my " .. bash_weapon)
        -- Bash loop until box is gone
        while vars["Current Box"].status ~= "gone" do
            waitrt()
            fput("bash #" .. box_id)
            waitrt()
            pause(0.2)
        end
    elseif not result then
        M.bash_the_box_open(vars, settings)
    end
end

---------------------------------------------------------------------------
-- Helper: handle "give up on box" routing for all modes.
-- Used in multiple places when a box cannot be opened.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
-- @param message   Optional message to display.
---------------------------------------------------------------------------
local function give_up_on_box(vars, settings, message)
    if message then
        util.tpick_silent(true, message, settings)
    end
    vars["Box Math"] = nil

    if vars["Picking Mode"] == "solo" then
        util.where_to_stow_box(vars)
    elseif vars["Picking Mode"] == "other" then
        util.tpick_say("Can't Open Box", settings)
        if modes and modes.open_others then
            modes.open_others(vars, settings)
        end
    elseif vars["Picking Mode"] == "ground" then
        vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
        vars["Box Opened"] = nil
    elseif vars["Picking Mode"] == "worker" then
        vars["Give Up On Box"] = true
    end
end

---------------------------------------------------------------------------
-- M.measure_lock(vars, settings, lockpicks_mod) — Main lock measurement and
-- pick selection system.
-- Port of lines 2409-2742. ~335 lines of Ruby with three main paths:
--   Path A: Caliper measurement (Rogue)
--   Path B: Loresinging (Bard)
--   Path C: Always Vaalin / Start With Copper / Picks On Level
--
-- After determining the pick, calls pick_2 to begin picking.
--
-- @param vars          Mutable picking state table.
-- @param settings      Settings table with load_data.
-- @param lockpicks_mod Lockpicks module reference.
---------------------------------------------------------------------------
function M.measure_lock(vars, settings, lockpicks_mod)
    local load_data = settings.load_data
    local lp = lockpicks_mod or lockpicks
    local all_pick_ids = vars["all_pick_ids"] or {}
    local settings_pick_names = vars["settings_pick_names"] or {}

    -- Reset Always Use Vaalin if rogue needs measurement
    if vars["rogue_need_to_measure_boxes"] then
        vars["Always Use Vaalin"] = nil
    end

    -- stuff_to_do for solo mode (swap container, etc.)
    if vars["Picking Mode"] == "solo" and modes and modes.stuff_to_do then
        modes.stuff_to_do(vars, settings)
    end

    waitrt()

    -- Cast buff spells if configured
    if vars["Use 506"] and spells and spells.tpick_cast_spells then
        spells.tpick_cast_spells(506, vars, settings)
    end
    if vars["Use 1035"] and spells and spells.tpick_cast_spells then
        spells.tpick_cast_spells(1035, vars, settings)
    end

    vars["Recommended Pick"] = nil

    -- Check 403 On Level setting
    local use_403_on_level = tonumber(load_data["Use 403 On Level"]) or 200
    if use_403_on_level ~= 200 then
        if vars["Critter Level"] == nil then
            util.tpick_silent(nil, "Critter level unknown, using 403 based on your settings.", settings)
            vars["403 Needed"] = "yes"
        else
            if use_403_on_level <= vars["Critter Level"] then
                util.tpick_silent(nil,
                    "Critter level is " .. vars["Critter Level"] .. ", using 403 based on your settings.",
                    settings)
                vars["403 Needed"] = "yes"
            end
        end
    end

    vars["Use A Wedge"] = nil

    -- Rogues guild wedge task logic
    local rogue_current_task = vars["rogue_current_task"] or ""
    local rogue_automate = vars["rogue_automate_current_task_with_tpick"]
    if rogue_current_task == "Wedge open boxes" and rogue_automate and vars["Picking Mode"] == "worker" then
        local required_plated_boxes = 0
        fput("gld")
        while true do
            local line = get()
            if not line then break end
            if string.find(line, "The Training Administrator told you to wedge open some boxes%.") then
                while true do
                    line = get()
                    if not line then break end
                    local plated_count = string.match(line, "At least (%d+) more should have a plated lock or fused tumblers")
                    if plated_count then
                        required_plated_boxes = tonumber(plated_count)
                    end
                    local reps_text = string.match(line, "You have (.-) repetitions? remaining")
                    if reps_text then
                        local total_reps_remaining
                        if reps_text == "no" then
                            total_reps_remaining = 0
                        else
                            total_reps_remaining = tonumber(reps_text) or 0
                        end
                        -- Determine if wedge should be used
                        if vars["Current Trap Type"] ~= "Scales" then
                            if required_plated_boxes == total_reps_remaining then
                                util.tpick_silent(true,
                                    "Either no more plated boxes or only plated boxes are required for your task.\n"
                                    .. "Therefore I am not using a wedge on this box.",
                                    settings)
                                vars["Use A Wedge"] = nil
                            elseif required_plated_boxes ~= total_reps_remaining or required_plated_boxes == 0 then
                                util.tpick_silent(true,
                                    "Non-plated boxes are required to get a rep for your current task.\n"
                                    .. "Therefore I am using a wedge on this box.",
                                    settings)
                                vars["Use A Wedge"] = true
                            end
                        end
                        break
                    end
                end
                break
            end
        end
    end

    -------------------------------------------------------------------
    -- DISPATCH: Route to appropriate picking path
    -------------------------------------------------------------------

    if vars["Use A Wedge"] then
        -- Wedge task: go directly to wedge
        M.wedge_lock(vars, settings)
        return
    end

    -- Rogues task: Repair broken lockpicks
    if rogue_automate and vars["Picking Mode"] == "worker" and rogue_current_task == "Repair broken lockpicks" then
        util.tpick_silent(true, "Trying to break a lockpick.", settings)
        vars["Always Use Vaalin"] = nil
        local picks_to_break = vars["Lockpicks To Break For Rogue"] or {}
        if #picks_to_break == 0 then
            vars["finished_with_current_rogue_task"] = true
            error("tpick: Finished breaking lockpicks for rogues task")
        else
            while not checkright() do
                if #picks_to_break == 0 then break end
                waitrt()
                fput("get #" .. picks_to_break[1])
                pause(0.2)
            end
        end
        M.pick_3(vars, settings, lockpicks_mod)
        return
    end

    -- Rogues task: Use lockpick from rogues setting (non-measured)
    if rogue_automate and vars["Picking Mode"] == "worker"
        and vars["True Lock Difficulty"] == nil
        and load_data[";rogues Lockpick"] and load_data[";rogues Lockpick"]:find("%S")
        and not string.find(rogue_current_task, "Measure then pick tough boxes")
        and not string.find(rogue_current_task, "Calibrate calipers in the field")
        and not string.find(rogue_current_task, "Gather trap components")
        and not string.find(rogue_current_task, "Melt open plated boxes") then

        if vars["rogue_change_needed_lockpick"] then
            local all_lp = { "copper", "steel", "gold", "silver", "mithril", "ora",
                "glaes", "laje", "vultite", "rolaren", "veniom", "invar", "alum",
                "golvern", "kelyn", "vaalin" }
            local number = 0
            local current_rogue_lp = (load_data[";rogues Lockpick"] or ""):lower()
            for _, name in ipairs(all_lp) do
                if name == current_rogue_lp then break end
                number = number + 1
            end
            vars["rogue_change_needed_lockpick"] = nil
            number = number + 1
            if number < #all_lp then
                load_data[";rogues Lockpick"] = all_lp[number + 1]
            else
                load_data[";rogues Lockpick"] = "vaalin"
            end
        end

        util.tpick_silent(true,
            ";tpick is automating your current ;rogues task.\n"
            .. ";tpick will use the lockpick in the 'Lockpick' setting under the ';rogues integration' tab.\n"
            .. ";rogues will automatically adjust this setting as necessary.",
            settings)
        vars["Always Use Vaalin"] = nil
        local rogue_pick = load_data[";rogues Lockpick"] or "Vaalin"
        -- Capitalize first letter
        vars["Recommended Pick"] = rogue_pick:sub(1, 1):upper() .. rogue_pick:sub(2):lower()
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    -- Always use 407
    if load_data["Unlock (407)"] == "All" then
        util.tpick_silent(nil, "Always use 407 setting enabled, using 407.", settings)
        if vars["Scale Trap Found"] then
            util.tpick_silent(true, "Can't open a scales trap with 407.", settings)
            if vars["Picking Mode"] == "solo" then
                util.where_to_stow_box(vars)
            elseif vars["Picking Mode"] == "other" then
                util.tpick_say("Can't Open Box", settings)
                if modes and modes.open_others then
                    modes.open_others(vars, settings)
                end
            elseif vars["Picking Mode"] == "ground" then
                vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
                vars["Box Opened"] = nil
            elseif vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            end
        else
            if vars["Picking Mode"] == "ground" then
                util.tpick_get_box(vars)
            end
            if spells and spells.cast_407 then
                spells.cast_407(vars, settings)
            end
        end
        return
    end

    -- Picks On Level (worker mode, no measurement)
    if vars["Picks For Critter Level"] and vars["Picking Mode"] == "worker" and vars["True Lock Difficulty"] == nil then
        vars["Needed Pick"] = nil
        if vars["Critter Level"] == nil then
            vars["Recommended Pick"] = "Vaalin"
        else
            for _, entry in ipairs(vars["Picks For Critter Level"]) do
                local parts = {}
                for word in entry:gmatch("%S+") do
                    table.insert(parts, word)
                end
                if #parts >= 2 then
                    local level = tonumber(parts[1]) or 0
                    local pick_name = parts[2]:sub(1, 1):upper() .. parts[2]:sub(2):lower()
                    if level >= vars["Critter Level"] then
                        vars["Recommended Pick"] = pick_name
                        break
                    end
                end
            end
        end
        -- Default to Vaalin if no match found
        if vars["Recommended Pick"] == nil then
            vars["Recommended Pick"] = "Vaalin"
        end
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        if vars["Critter Level"] then
            util.tpick_silent(nil,
                "Critter level is " .. vars["Critter Level"]
                .. ", using a " .. vars["Recommended Pick"] .. " lockpick based on your settings.",
                settings)
        else
            util.tpick_silent(nil,
                "Critter level is unknown, using a " .. vars["Recommended Pick"] .. " lockpick.",
                settings)
        end
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    -- Always Use Vaalin
    if vars["Always Use Vaalin"] then
        util.tpick_silent(nil, "Always use Vaalin setting enabled, using a Vaalin lockpick.", settings)
        vars["Recommended Pick"] = "Vaalin"
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        local four03_setting = (load_data["403"] or ""):lower()
        if not string.find(four03_setting, "never") then
            vars["403 Needed"] = "yes"
        end
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    -- Use Vaalin When Fried
    if load_data["Use Vaalin When Fried"] == "Yes" and (percentmind() >= 100) then
        util.tpick_silent(nil, "Always use Vaalin when fried enabled, using a Vaalin lockpick.", settings)
        vars["Box Math"] = nil
        vars["Recommended Pick"] = "Vaalin"
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        local four03_setting = (load_data["403"] or ""):lower()
        if not string.find(four03_setting, "never") then
            vars["403 Needed"] = "yes"
        end
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    -- Start With Copper (no measurement)
    if vars["Start With Copper"] and vars["True Lock Difficulty"] == nil then
        util.tpick_silent(nil, "Start with copper option enabled, starting with lockpick in your copper lockpick setting.", settings)
        vars["Recommended Pick"] = "Copper"
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    -------------------------------------------------------------------
    -- MEASUREMENT PATH: Measure lock then select pick
    -------------------------------------------------------------------

    waitrt()
    if vars["True Lock Difficulty"] == nil then
        vars["Number Of Times To Measure"] = 0
        M.measure_detection(vars, settings)
        if Stats.prof == "Bard" then fput("speak common") end
        if Stats.prof == "Rogue" then
            util.tpick_put_stuff_away(vars, settings)
        elseif Stats.prof == "Bard" and vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
        end
    end

    vars["Needed Pick"] = nil
    vars["Needed Pick ID"] = nil

    -- Route based on measurement result
    if vars["Lock Difficulty"] == "not locked" then
        vars["Box Math"] = nil
        if vars["Picking Mode"] == "solo" and modes and modes.open_solo then
            modes.open_solo(vars, settings)
        elseif vars["Picking Mode"] == "other" and modes and modes.open_others then
            modes.open_others(vars, settings)
        end
        -- ground/worker: do nothing, return naturally
        return
    end

    if vars["Lock Difficulty"] == "can't find trap" then
        give_up_on_box(vars, settings, "Doesn't look like you have the skill to detect the trap on this box.")
        return
    end

    if vars["Lock Difficulty"] == "can't measure" then
        util.tpick_silent(true, "You can't determine the lock difficulty.", settings)
        if vars["Scale Trap Found"] then
            give_up_on_box(vars, settings,
                "This box has a scales trap therefore it can't be popped or wedged. Skipping box.")
        else
            util.tpick_silent(true, "Going to try wedging this box open since the lock difficulty can't be determined.", settings)
            M.wedge_lock(vars, settings)
        end
        return
    end

    if vars["Lock Difficulty"] == "need vaalin" then
        vars["Recommended Pick"] = "Vaalin"
        if lp and lp.lock_pick_information then
            lp.lock_pick_information(vars, settings, all_pick_ids)
        end
        local pick_skill = vars["Pick Skill"] or 0
        local modifier = vars["Recommended Pick Modifier"] or 2.50
        local quick_maths = math.floor(pick_skill * modifier)
        util.tpick_silent(nil,
            "Recommended lock pick: " .. vars["Recommended Pick"]
            .. " with a modifier of " .. modifier
            .. "\nRecommend 403: No"
            .. "\nYour calculated lockpicking skill: " .. pick_skill
            .. "\nYour total picking skill for this attempt is: " .. quick_maths
            .. "\nLock difficulty: " .. tostring(vars["Lock Difficulty"]),
            settings)
        M.pick_2(vars, settings, lockpicks_mod)
        return
    end

    if vars["Lock Difficulty"] == "Soul Golem" and vars["Give Up On Box"] then
        util.tpick_silent(true,
            "Message indicates this box is trapped. Normally this means this is a Soul Golem box but "
            .. "the worker didn't say this was from a Soul Golem. To be on the safe side I am turning "
            .. "this box in and moving on.",
            settings)
        return
    end

    -------------------------------------------------------------------
    -- NUMERIC DIFFICULTY: Calculate pick selection
    -------------------------------------------------------------------

    local lock_difficulty = vars["Lock Difficulty"]
    if type(lock_difficulty) ~= "number" then
        -- Non-numeric, non-handled difficulty string — should not reach here
        util.tpick_silent(true, "Unexpected lock difficulty: " .. tostring(lock_difficulty), settings)
        return
    end

    local pick_skill = vars["Pick Skill"] or 0
    local pick_lore = vars["Pick Lore"] or 0
    vars["Total Pick Skill"] = (pick_skill + pick_lore) * 2.50
    local max_lock_attempt = tonumber(load_data["Max Lock"]) or 9999
    local vaalin_lock_roll = tonumber(load_data["Vaalin Lock Roll"]) or 0

    -- Check: Max Lock compared to skill
    if vars["Max Lock Compared To Skill"] and lock_difficulty > (vars["Total Pick Skill"] - max_lock_attempt) then
        if vars["Scale Trap Found"] then
            give_up_on_box(vars, settings,
                "Lock difficulty: " .. lock_difficulty
                .. ", your max picking skill with a Vaalin lockpick: " .. vars["Total Pick Skill"]
                .. ", you won't pick anything higher than " .. max_lock_attempt
                .. " points below your max skill according to the Max Lock setting in the ;setup menu."
                .. " This box also has a scales trap so can't be popped or wedged open. Skipping box.")
        else
            util.tpick_silent(true,
                "Lock difficulty: " .. lock_difficulty
                .. ", your max picking skill with a Vaalin lockpick: " .. vars["Total Pick Skill"]
                .. ", you won't pick anything higher than " .. max_lock_attempt
                .. " points below your max skill according to the Max Lock setting in the ;setup menu so a lockpick won't be used.",
                settings)
            M.wedge_lock(vars, settings)
        end
        return
    end

    -- Check: Max Lock as absolute value (not compared to skill)
    if lock_difficulty > max_lock_attempt and not vars["Max Lock Compared To Skill"] then
        if vars["Scale Trap Found"] then
            give_up_on_box(vars, settings,
                "This lock is higher than the Max Lock setting you entered in the ;setup menu so a lockpick won't be used."
                .. " This box also has a scales trap so can't be popped or wedged open. Skipping box.")
        else
            util.tpick_silent(true,
                "This lock is higher than the Max Lock setting you entered in the ;setup menu so a lockpick won't be used.",
                settings)
            M.wedge_lock(vars, settings)
        end
        return
    end

    -- Check: Can we pick this at all with Vaalin + roll?
    if lock_difficulty > (vars["Total Pick Skill"] + vaalin_lock_roll) then
        if vars["Scale Trap Found"] then
            give_up_on_box(vars, settings,
                "Can't pick this box based on my calculations (and it has a scales trap.) "
                .. "If you think this is in error increase the Vaalin Lock Roll setting in the setup menu. Skipping box.")
        else
            util.tpick_silent(true,
                "Can't pick this box based on my calculations. "
                .. "If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                settings)
            M.wedge_lock(vars, settings)
        end
        return
    end

    -------------------------------------------------------------------
    -- Calculate the best lockpick for this lock
    -------------------------------------------------------------------

    if lp and lp.calculate_needed_lockpick then
        lp.calculate_needed_lockpick(vars, settings, all_pick_ids)
    end

    -- Build info text
    local text = "Recommended lock pick: " .. (vars["Recommended Pick"] or "?")
        .. " with a modifier of " .. (vars["Recommended Pick Modifier"] or "?") .. "\n"

    local temp_math_number
    if vars["403 Needed"] == "yes" then
        if vars["Use 403 For Lock Difficulty"] and lock_difficulty > vars["Use 403 For Lock Difficulty"] then
            text = text .. "Lock difficulty is higher than your 403 setting in setup menu, using 403.\n"
        else
            text = text .. "Recommend 403: Yes\n"
        end
        text = text .. "Your calculated lockpicking skill: " .. pick_skill .. "\n"
        text = text .. "Your calculated lockpicking lore: " .. pick_lore .. "\n"
        temp_math_number = pick_skill + pick_lore
    else
        text = text .. "Recommend 403: No\n"
        text = text .. "Your calculated lockpicking skill: " .. pick_skill .. "\n"
        temp_math_number = pick_skill
    end
    local modifier = vars["Recommended Pick Modifier"] or 1.0
    local quick_maths = math.floor(temp_math_number * modifier)
    text = text .. "Your total picking skill for this attempt is: " .. quick_maths .. "\n"
    text = text .. "Lock difficulty: " .. lock_difficulty
    util.tpick_silent(nil, text, settings)

    -- Check if we actually have the recommended pick
    if vars["Needed Pick ID"] == nil then
        if vars["Recommended Pick"] == "Vaalin" then
            util.tpick_silent(true,
                "ALL OF YOUR VAALIN LOCKPICKS ARE BROKEN. YOU REALLY SHOULD HAVE AT LEAST 1 WORKING VAALIN LOCKPICK WHEN RUNNING THIS SCRIPT.",
                settings)
            error("tpick: No working Vaalin lockpicks")
        else
            util.tpick_silent(true,
                "All of your " .. (vars["Recommended Pick"] or "unknown")
                .. " lockpicks seem to be broken, trying a higher tier lockpick.",
                settings)
            if lp and lp.next_pick then
                lp.next_pick(vars, settings, all_pick_ids, settings_pick_names)
            end
        end
    else
        M.pick_2(vars, settings, lockpicks_mod)
    end
end

---------------------------------------------------------------------------
-- M.pick_2(vars, settings, lockpicks_mod) — Get lockpick into hand and
-- initiate pick attempt.
-- Port of lines 2744-2765.
--
-- Handles gnomish bracers or normal lockpick retrieval, then calls pick_3.
--
-- @param vars          Mutable picking state table.
-- @param settings      Settings table with load_data.
-- @param lockpicks_mod Lockpicks module reference.
---------------------------------------------------------------------------
function M.pick_2(vars, settings, lockpicks_mod)
    local load_data = settings.load_data
    local lp = lockpicks_mod or lockpicks

    waitrt()

    if vars["Gnomish Bracers"] and load_data["Bracer Override"] == "No" then
        -- Gnomish bracer lockpick selection
        if lp and lp.find_gnomish_lockpick then
            lp.find_gnomish_lockpick(vars, settings)
        end
    else
        -- Get the needed lockpick into hand (up to 3 attempts)
        local needed_id = vars["Needed Pick ID"]
        for _ = 1, 3 do
            waitrt()
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.id == needed_id) or (lh and lh.id == needed_id) then
                break
            end
            fput("get #" .. (needed_id or ""))
            pause(0.2)
        end

        -- Check if we got the lockpick
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (not rh or rh.id ~= needed_id) and (not lh or lh.id ~= needed_id) then
            util.tpick_silent(true, "Couldn't find " .. (vars["Needed Pick"] or "lockpick") .. ".", settings)
            waitrt()
            vars["Roll Amount"] = 100
            if lp and lp.next_pick then
                local all_pick_ids = vars["all_pick_ids"] or {}
                local settings_pick_names = vars["settings_pick_names"] or {}
                lp.next_pick(vars, settings, all_pick_ids, settings_pick_names)
            end
        else
            M.pick_3(vars, settings, lockpicks_mod)
        end
    end
end

---------------------------------------------------------------------------
-- M.pick_3(vars, settings, lockpicks_mod) — Pick result handler.
-- Port of lines 2767-3130. ~365 lines of Ruby.
--
-- Sends the pick command, parses game response for:
-- - Success (box opened)
-- - Failure with roll info
-- - Pick damage (bent/broken)
-- - Keep Trying logic
-- - 403 needed logic
-- Then dispatches to appropriate next step.
--
-- @param vars          Mutable picking state table.
-- @param settings      Settings table with load_data.
-- @param lockpicks_mod Lockpicks module reference.
---------------------------------------------------------------------------
function M.pick_3(vars, settings, lockpicks_mod)
    local load_data = settings.load_data
    local lp = lockpicks_mod or lockpicks
    local all_pick_ids = vars["all_pick_ids"] or {}
    local settings_pick_names = vars["settings_pick_names"] or {}

    vars["Next Task"] = nil
    vars["Roll Amount"] = nil

    local is_plinite = vars["Open Plinites"]
        or (vars["Current Box"] and vars["Current Box"].name and string.find(vars["Current Box"].name, "plinite"))

    if is_plinite then
        util.tpick_silent(nil, "Attempting to extract plinite.", settings)
    else
        util.tpick_silent(nil, "Attempting to pick lock.", settings)
    end

    waitrt()

    -- Cast buff spells
    if vars["Use 506"] and spells and spells.tpick_cast_spells then
        spells.tpick_cast_spells(506, vars, settings)
    end
    if vars["Use 1035"] and spells and spells.tpick_cast_spells then
        spells.tpick_cast_spells(1035, vars, settings)
    end

    -- Handle 403 spell
    local four03_setting = (load_data["403"] or ""):lower()
    if not string.find(four03_setting, "never") then
        if vars["403 Needed"] == "yes" or vars["Use 403"] then
            -- Check active spells then cast 403
            if spells and spells.tpick_cast_spells then
                spells.tpick_cast_spells(403, vars, settings)
            end
        end
    end

    -- Auto-stop 403 if not needed
    if string.find(four03_setting, "auto") and not vars["403 Needed"] and not vars["Need 403"] and not vars["Use 403"] then
        if spells and spells.tpick_stop_spell then
            spells.tpick_stop_spell(403, vars, settings)
        end
    end

    local finished_task = false

    -------------------------------------------------------------------
    -- MAIN PICK LOOP
    -------------------------------------------------------------------
    while not finished_task do
        local box_id = vars["Current Box"].id

        if is_plinite then
            -- Plinite extraction
            fput("extract #" .. box_id)
        elseif vars["Gnomish Bracers"] and load_data["Bracer Override"] == "No" then
            -- Gnomish bracer push
            if vars["Picking Mode"] == "ground" then
                util.tpick_get_box(vars)
            end
            fput("push my " .. vars["Gnomish Bracers"])
        else
            -- Normal pick command
            if vars["rogue_trick_to_use"] then
                vars["Do Trick"] = "lmas ptrick " .. vars["rogue_trick_to_use"]
            elseif load_data["Trick"] == "random" then
                local tricks = { "spin", "twist", "turn", "twirl", "toss", "bend", "flip" }
                vars["Do Trick"] = "lmas ptrick " .. tricks[math.random(#tricks)]
            end

            -- Wait for RT to clear
            while checkrt() > 0 do pause(0.1) end

            fput((vars["Do Trick"] or "pick") .. " #" .. box_id)
        end

        -------------------------------------------------------------------
        -- PLINITE RESPONSE PARSING
        -------------------------------------------------------------------
        if is_plinite then
            while true do
                local line = get()
                if not line then break end

                -- Roll result
                local plinite_roll = string.match(line, "^You make .* attempt %(d100%(open%)%=(%d+)%)%.")
                    or string.match(line, "^You make .* attempt %(d100%=(%d+)%)%.")
                if plinite_roll then
                    vars["Roll Amount"] = tonumber(plinite_roll)
                    if vars["Roll Amount"] == 1 then
                        waitrt()
                        vars["Next Task"] = "pick3"
                        finished_task = true
                        break
                    end
                end

                -- Ruptured core
                if string.find(line, "As you do you so, you push just a little too hard and rupture the core!") then
                    waitrt()
                    vars["Next Task"] = "next plinite"
                    finished_task = true
                    break
                end

                -- Within abilities (retry)
                if string.find(line, "you withdraw your .* with the feeling that retrieving the core is within your abilities") then
                    waitrt()
                    vars["Next Task"] = "pick3"
                    finished_task = true
                    break
                end

                -- Not sufficient / broken pick
                if string.find(line, "with the feeling that your abilities are probably not sufficient to retrieve the core")
                    or string.find(line, "You fumble about for a bit before you realize you are using a broken")
                    or string.find(line, "you realize that the .* is broken") then

                    local rh = GameObj.right_hand()
                    if (not rh or rh.id ~= box_id) and (vars["Picking Mode"] == "ground" or vars["Picking Mode"] == "worker") then
                        if string.find(line, "You fumble about for a bit before you realize you are using a broken")
                            or string.find(line, "you realize that the .* is broken") then
                            vars["lockpick_is_broken"] = true
                            util.tpick_put_stuff_away(vars, settings)
                            local rec_pick = vars["Recommended Pick"] or "Vaalin"
                            if all_pick_ids[rec_pick] and #all_pick_ids[rec_pick] > 0 then
                                table.remove(all_pick_ids[rec_pick], 1)
                            end
                            local vaalin_ids = all_pick_ids["Vaalin"] or {}
                            if #vaalin_ids < 1 then
                                vars["Roll Amount"] = 100
                            end
                            if lp and lp.no_vaalin_picks then
                                lp.no_vaalin_picks(vars, settings, all_pick_ids)
                            end
                        else
                            util.tpick_put_stuff_away(vars, settings)
                        end
                    end
                    util.tpick_put_stuff_away(vars, settings)

                    if vars["Needed Pick"] == load_data["Vaalin"] then
                        if vars["Picking Mode"] == "worker" then
                            util.tpick_silent(true,
                                "Can't extract this plinite based on my calculations. If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                                settings)
                            vars["Next Task"] = "next plinite"
                        else
                            util.tpick_silent(true,
                                "Can't extract this plinite, OPENing it instead. If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                                settings)
                            waitrt()
                            fput("open #" .. box_id)
                            vars["Next Task"] = "next plinite"
                        end
                    else
                        vars["Next Task"] = "nextpick"
                    end
                    finished_task = true
                    break
                end

                -- Plinite ready to pluck
                if string.find(line, "where it can be easily PLUCKed") then
                    vars["Next Task"] = "open plinite"
                    finished_task = true
                    break
                end

                -- Roundtime
                if string.find(line, "^Roundtime:") then
                    finished_task = true
                    break
                end

                -- Wait message (retry loop)
                if string.find(line, "%.%.%.wait") then
                    break -- breaks inner while, outer while retries
                end
            end

        -------------------------------------------------------------------
        -- NORMAL LOCK PICKING RESPONSE PARSING
        -------------------------------------------------------------------
        else
            local flip_trick_is_being_used = false

            while true do
                local line = get()
                if not line then break end

                -- Flip trick detection
                if string.find(line, "you instead attempt to quietly turn the tumblers to within a hair's breadth of clicking") then
                    flip_trick_is_being_used = true
                end

                -- Get roll amount
                local roll_str = string.match(line, "^You make .* attempt %(d100%(open%)%=(%d+)%)%.")
                    or string.match(line, "^You make .* attempt %(d100%=(%d+)%)%.")
                if roll_str then
                    vars["Roll Amount"] = tonumber(roll_str)
                    if vars["Roll Amount"] == 1 then
                        vars["Next Task"] = "pick3"
                    end
                end

                -------------------------------------------------------
                -- BOX OPENED or ALREADY OPEN
                -------------------------------------------------------
                local box_opened = false
                local actual_lock_difficulty = nil

                if string.find(line, "As you do, you get a sense that the .* has .* %(%-(%d+) thief%-lingo difficulty ranking%)%.  Then%.%.%.CLICK!  It opens!")
                    or string.find(line, "gives off an audible %*click%* as the tumblers snap open")
                    or string.find(line, "It does not appear to be locked") then
                    box_opened = true

                    -- Extract actual difficulty if present
                    actual_lock_difficulty = tonumber(string.match(line, "%(%-(%d+) thief%-lingo difficulty ranking%)"))
                end

                if box_opened then
                    vars["Calibrate-Count"] = (vars["Calibrate-Count"] or 0) + 1
                    waitrt()
                    util.tpick_put_stuff_away(vars, settings)

                    if string.find(line, "It does not appear to be locked") then
                        vars["Box Math"] = nil
                    else
                        -- Track stats for non-repair tasks
                        local rogue_repair_task = rogue_automate_check(vars)
                        if not rogue_repair_task then
                            local stats = vars["stats_data"] or {}
                            stats["Locks Opened Since Last Pick Broke"] = (stats["Locks Opened Since Last Pick Broke"] or 0) + 1
                            local per_pick = stats["Opened/Broke For Each Pick"] or {}
                            local rec_pick = vars["Recommended Pick"] or "Unknown"
                            per_pick[rec_pick] = (per_pick[rec_pick] or 0) + 1
                            stats["Opened/Broke For Each Pick"] = per_pick
                            vars["stats_data"] = stats

                            -- Display stats
                            local stat_text = "Number of locks successfully opened since last broken lockpick: "
                            for key, value in pairs(per_pick) do
                                stat_text = stat_text .. key .. ": " .. value .. ", "
                            end
                            stat_text = stat_text:sub(1, -3)  -- Remove trailing ", "
                            stat_text = stat_text .. ". Number of total locks picked since any lockpick broke: "
                                .. (stats["Locks Opened Since Last Pick Broke"] or 0)
                            util.tpick_silent(true, stat_text, settings)

                            -- Calibration logic (Rogue only)
                            if Stats.prof == "Rogue" then
                                if vars["rogue_calibrate_every_box"] then
                                    M.calibrate_calipers(vars, settings)
                                elseif vars["Calibrate Auto Amount"]
                                    and type(vars["Measured Lock"]) == "number"
                                    and type(actual_lock_difficulty) == "number" then
                                    local calibrate_diff = math.abs(vars["Measured Lock"] - actual_lock_difficulty)
                                    if calibrate_diff >= vars["Calibrate Auto Amount"] then
                                        if not vars["Pop Boxes"] then
                                            util.tpick_silent(nil,
                                                "The difference between calipers reading and actual lock difficulty was "
                                                .. calibrate_diff .. ". According to your settings you want your calipers calibrated.",
                                                settings)
                                            M.calibrate_calipers(vars, settings)
                                        end
                                    end
                                elseif (vars["Calibrate-Count"] or 0) >= (tonumber(load_data["Calibrate Count"]) or 999)
                                    and not vars["Calibrate Auto Amount"] then
                                    if vars["Can Use Calipers"] and not vars["Always Use Vaalin"] and not vars["Start With Copper"] then
                                        if not vars["Pop Boxes"] then
                                            M.calibrate_calipers(vars, settings)
                                        end
                                    end
                                    vars["Calibrate-Count"] = 0
                                end
                            end
                        end
                    end

                    -- Route to next step based on mode
                    if vars["Scale Trap Found"] then
                        vars["Next Task"] = "scale_disarm_call"
                    elseif vars["Picking Mode"] == "solo" then
                        vars["Next Task"] = "Open Solo"
                    elseif vars["Picking Mode"] == "other" then
                        vars["Next Task"] = "open_other"
                    elseif vars["Picking Mode"] == "ground" then
                        if vars["Gnomish Bracers"] and load_data["Bracer Override"] == "No" then
                            util.tpick_drop_box(vars)
                        end
                        vars["Next Task"] = "open_ground"
                    elseif vars["Picking Mode"] == "worker" then
                        vars["Next Task"] = "worker finished"
                    end

                    finished_task = true
                    break
                end

                -------------------------------------------------------
                -- NO READ FROM BOX (failed, no info)
                -------------------------------------------------------
                if string.find(line, "^You are not able to pick the lock, and learn little about it%.") then
                    if vars["Roll Amount"] == 1 then
                        util.tpick_silent(nil, "This attempt was a fumble, going to try again.", settings)
                        vars["Next Task"] = "pick3"
                    else
                        M.roll_amount_check(vars, settings)
                    end
                    finished_task = true
                    break
                end

                -------------------------------------------------------
                -- BOX CAN BE OPENED WITH CURRENT PICK (got a read)
                -------------------------------------------------------
                local got_read = false
                local read_difficulty = nil

                if string.find(line, "^You are not able to pick the .*, but you get a sense that it has .* lock%.")
                    or string.find(line, "^You are not able to pick the lock, but you get a feeling that it is within your abilities%.")
                    or (string.find(line, "^You get a sense that the .* %(%-(%d+) thief%-lingo difficulty ranking%)%.")
                        and not flip_trick_is_being_used) then
                    got_read = true
                    read_difficulty = tonumber(string.match(line, "About a %-(%d+) difficulty lock"))
                        or tonumber(string.match(line, "%(%-(%d+) thief%-lingo difficulty ranking%)"))
                end

                if got_read then
                    -- First read: update lock difficulty
                    if (read_difficulty or string.find(line, "About a %-(%d+) difficulty lock"))
                        and vars["True Lock Difficulty"] == nil then
                        if read_difficulty then
                            vars["Lock Difficulty"] = read_difficulty
                        end
                        if settings.update_box_for_window then
                            settings.update_box_for_window()
                        end
                        vars["True Lock Difficulty"] = true

                        -- Vaalin pick handling
                        if vars["Needed Pick"] == load_data["Vaalin"] then
                            local vaalin_roll = tonumber(load_data["Vaalin Lock Roll"]) or 0
                            if (vars["Roll Amount"] or 0) > vaalin_roll then
                                if not vars["Need 403"] and not string.find(four03_setting, "never") then
                                    util.tpick_silent(nil,
                                        "You rolled: " .. (vars["Roll Amount"] or 0)
                                        .. ", your Vaalin Lock Roll setting: " .. vaalin_roll
                                        .. ". Going to use 403/Lmas Focus now.",
                                        settings)
                                    vars["Roll Amount"] = 99
                                elseif string.find(four03_setting, "never") then
                                    util.tpick_silent(nil,
                                        "You rolled: " .. (vars["Roll Amount"] or 0)
                                        .. ", your Vaalin Lock Roll setting: " .. vaalin_roll
                                        .. ". Your settings indicate you don't want to use 403/Lmas Focus. According to your Vaalin Lock Roll setting you should stop trying to use lockpicks.",
                                        settings)
                                    vars["Roll Amount"] = 100
                                else
                                    util.tpick_silent(nil,
                                        "You rolled: " .. (vars["Roll Amount"] or 0)
                                        .. ", your Vaalin Lock Roll setting: " .. vaalin_roll
                                        .. ". You are already using 403. According to your Vaalin Lock Roll setting you should stop trying to use lockpicks.",
                                        settings)
                                    vars["Roll Amount"] = 100
                                end
                                util.tpick_put_stuff_away(vars, settings)
                                vars["Next Task"] = "nextpick"
                            else
                                util.tpick_silent(nil,
                                    "You rolled: " .. (vars["Roll Amount"] or 0)
                                    .. ", your Vaalin Lock Roll setting: " .. vaalin_roll
                                    .. ". Trying same pick again",
                                    settings)
                                vars["Next Task"] = "pick3"
                            end
                        else
                            -- Non-Vaalin: got a read, re-measure with correct difficulty
                            vars["Next Task"] = "measure again"
                        end
                    else
                        -- Already had a read — handle based on roll
                        if vars["Roll Amount"] == 1 then
                            util.tpick_silent(nil, "This attempt was a fumble, going to try again.", settings)
                            vars["Next Task"] = "pick3"
                        else
                            if load_data["Keep Trying"] == "Yes" then
                                util.tpick_silent(nil,
                                    "Messaging indicates you can open this box with current lockpick, according to your settings you want to try same lockpick again.",
                                    settings)
                                vars["Next Task"] = "pick3"
                            else
                                util.tpick_silent(nil,
                                    "Messaging indicates you can open this box with current lockpick, but according to your settings you don't want to try same lockpick again.",
                                    settings)
                                M.roll_amount_check(vars, settings)
                            end
                        end
                    end
                    finished_task = true

                    -- Special case: flip trick sense line doesn't break the loop
                    if not string.find(line, "^You get a sense that the .* %(%-(%d+) thief%-lingo difficulty ranking%)%.") then
                        break
                    end
                end

                -------------------------------------------------------
                -- LOCKPICK DAMAGED (bent/stressed)
                -------------------------------------------------------
                if string.find(line, "gets stuck in the lock!  You carefully try to work it free but end up bending the tip!")
                    or string.find(line, "gets stuck in the lock!  You carefully try to work it free, but it may have been weakened")
                    or string.find(line, "shoot out of your .* to steady your .* before you do any damage!") then

                    waitrt()
                    while checkrt() > 0 do pause(0.1) end

                    -- Auto-repair bent lockpick (Rogue only)
                    if string.find(line, "stuck in the lock!  You carefully try to work it free but end up bending the tip!")
                        and load_data["Auto Repair Bent Lockpicks"] == "Yes"
                        and Stats.prof == "Rogue" then
                        waitrt()
                        while checkrt() > 0 do pause(0.1) end
                        util.tpick_silent(nil, "Lockpick tip was bent, going to try repairing it.", settings)
                        if vars["Picking Mode"] ~= "ground" and vars["Picking Mode"] ~= "worker" then
                            util.tpick_stow_box(vars)
                        end
                        fput("lmas repair #" .. (vars["Needed Pick ID"] or ""))
                        waitrt()
                        pause(1)
                        while checkrt() > 0 do pause(0.1) end
                        if vars["Picking Mode"] ~= "ground" and vars["Picking Mode"] ~= "worker" then
                            util.tpick_get_box(vars)
                        end
                    end

                    if vars["Roll Amount"] == 1 then
                        util.tpick_silent(nil, "This attempt was a fumble, going to try again.", settings)
                        vars["Next Task"] = "pick3"
                    elseif (vars["Roll Amount"] or 0) < (tonumber(load_data["Max Lock Roll"]) or 0) then
                        util.tpick_silent(nil,
                            "You rolled " .. (vars["Roll Amount"] or 0)
                            .. ", your settings are to try again because you rolled less than "
                            .. (load_data["Max Lock Roll"] or 0) .. ".",
                            settings)
                        vars["Next Task"] = "pick3"
                    else
                        if vars["Needed Pick"] ~= load_data["Vaalin"] then
                            util.tpick_silent(nil, "This pick doesn't seem to be cutting it, going to try a different one.", settings)
                        else
                            if not vars["Need 403"] and not string.find(four03_setting, "never") then
                                util.tpick_silent(nil, "A Vaalin pick doesn't seem to be cutting it alone, going to try 403/Lmas Focus.", settings)
                                vars["Roll Amount"] = 99
                            elseif string.find(four03_setting, "never") then
                                util.tpick_silent(nil, "A Vaalin pick doesn't seem to be cutting it alone and your settings indicate you never want to use 403/Lmas Focus, going to try wedges or 407.", settings)
                                vars["Roll Amount"] = 100
                            else
                                util.tpick_silent(nil, "A Vaalin pick with 403/Lmas Focus doesn't seem to be cutting it, going to try wedges or 407.", settings)
                                vars["Roll Amount"] = 100
                            end
                        end
                        util.tpick_put_stuff_away(vars, settings)
                        vars["Next Task"] = "nextpick"
                    end
                    finished_task = true
                    break
                end

                -------------------------------------------------------
                -- LOCKPICK BROKEN
                -------------------------------------------------------
                if string.find(line, "SNAP")
                    or string.find(line, "fumble about for a bit before you realize you are using a broken")
                    or string.find(line, "gets stuck in the lock!  You carefully try to work it free but end up snapping off the tip!") then

                    -- Check for rogue repair task
                    local rogue_repair_task = rogue_automate_check(vars)
                    if rogue_repair_task and not string.find(line, "shoot out of your .* to steady") then
                        -- Rogue repair task: record broken pick
                        local picks_to_break = vars["Lockpicks To Break For Rogue"] or {}
                        local rh = GameObj.right_hand()
                        if rh then
                            -- Remove from list
                            for i, pid in ipairs(picks_to_break) do
                                if pid == rh.id then
                                    table.remove(picks_to_break, i)
                                    break
                                end
                            end
                            -- Stow the broken pick
                            while checkright() do
                                waitrt()
                                fput("stow #" .. (GameObj.right_hand() and GameObj.right_hand().id or ""))
                                pause(0.2)
                            end
                        end
                        if #picks_to_break == 0 then
                            util.tpick_silent(true, "That's the last lockpick to break! Let's repair them all now.", settings)
                            vars["finished_with_current_rogue_task"] = true
                            error("tpick: Finished breaking lockpicks")
                        else
                            util.tpick_silent(true, "Broke this lockpick! " .. #picks_to_break .. " more to go!", settings)
                        end
                    else
                        -- Normal broken pick handling
                        if string.find(line, "SNAP") or string.find(line, "snapping off the tip") then
                            local stats = vars["stats_data"] or {}
                            local per_pick = stats["Opened/Broke For Each Pick"] or {}
                            local rec_pick = vars["Recommended Pick"] or "Unknown"
                            util.tpick_silent(true,
                                "Your " .. rec_pick .. " lockpick successfully picked "
                                .. (per_pick[rec_pick] or 0) .. " locks before it broke. You successfully picked "
                                .. (stats["Locks Opened Since Last Pick Broke"] or 0)
                                .. " locks since you last broke any lockpick.",
                                settings)
                            stats["Locks Opened Since Last Pick Broke"] = 0
                            per_pick[rec_pick] = 0
                            stats["Opened/Broke For Each Pick"] = per_pick
                            vars["stats_data"] = stats
                        end
                        util.tpick_silent(true, (vars["Needed Pick"] or "Lockpick") .. " is broken.", settings)
                        waitrt()
                        vars["Next Task"] = "broken lockpick stow"
                    end
                    finished_task = true
                    break
                end

                -------------------------------------------------------
                -- NOT HOLDING A LOCKPICK
                -------------------------------------------------------
                if string.find(line, "You must be holding a lockpick to perform that trick")
                    or string.find(line, "You didn't mention what you want to pick the lock with") then
                    util.tpick_silent(true, "Couldn't find " .. (vars["Needed Pick"] or "lockpick") .. ".", settings)
                    waitrt()
                    vars["Next Task"] = "nextpick"
                    finished_task = true
                    break
                end

                -------------------------------------------------------
                -- ROUNDTIME (end of response)
                -------------------------------------------------------
                if string.find(line, "^Roundtime:") then
                    finished_task = true
                    break
                end

                -- Wait message (retry the pick command)
                if string.find(line, "%.%.%.wait") then
                    break -- breaks inner while, outer while retries
                end

                -- Invalid target
                if string.find(line, "You want to pick a lock on what") then
                    error("tpick: Invalid pick target")
                end
            end
        end
    end -- end main pick loop

    -------------------------------------------------------------------
    -- DISPATCH based on Next Task
    -------------------------------------------------------------------

    local rogue_repair_task = rogue_automate_check(vars)
    if rogue_repair_task then
        -- Rogues repair lockpick task dispatching
        if vars["Next Task"] == "scale_disarm_call" then
            if traps and traps.disarm_scale then
                traps.disarm_scale(vars, settings)
            end
        elseif vars["Next Task"] == "worker finished" then
            -- Done
        elseif vars["Next Task"] == "open plinite" then
            if vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            end
        elseif vars["Next Task"] == "next plinite" then
            util.tpick_put_stuff_away(vars, settings)
            if vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            end
        else
            M.measure_lock(vars, settings, lockpicks_mod)
        end
    else
        -- Normal dispatching
        if vars["Next Task"] == "Open Solo" then
            if modes and modes.open_solo then
                modes.open_solo(vars, settings)
            end
        elseif vars["Next Task"] == "open_other" then
            if modes and modes.open_others then
                modes.open_others(vars, settings)
            end
        elseif vars["Next Task"] == "worker finished" then
            -- Relock boxes for rogues relock task
            local rc_task = vars["rogue_current_task"] or ""
            if vars["rogue_automate_current_task_with_tpick"]
                and vars["Picking Mode"] == "worker"
                and rc_task == "Relock tough boxes" then
                M.do_relock_boxes(vars, settings, lockpicks_mod)
            end
        elseif vars["Next Task"] == "open_ground" then
            -- Ground mode: done, return naturally
        elseif vars["Next Task"] == "pick3" then
            M.pick_3(vars, settings, lockpicks_mod)
        elseif vars["Next Task"] == "nextpick" then
            if lp and lp.next_pick then
                lp.next_pick(vars, settings, all_pick_ids, settings_pick_names)
            end
        elseif vars["Next Task"] == "measure again" then
            util.tpick_silent(nil, "Got a read on this box, going to change to best suited lockpick.", settings)
            waitrt()
            util.tpick_put_stuff_away(vars, settings)
            M.measure_lock(vars, settings, lockpicks_mod)
        elseif vars["Next Task"] == "broken lockpick stow" then
            if vars["Gnomish Bracers"] and load_data["Bracer Override"] == "No" then
                if lp and lp.next_pick then
                    lp.next_pick(vars, settings, all_pick_ids, settings_pick_names)
                end
            else
                vars["lockpick_is_broken"] = true
                util.tpick_put_stuff_away(vars, settings)
                local rec_pick = vars["Recommended Pick"] or "Vaalin"
                if all_pick_ids[rec_pick] and #all_pick_ids[rec_pick] > 0 then
                    table.remove(all_pick_ids[rec_pick], 1)
                end
                local vaalin_ids = all_pick_ids["Vaalin"] or {}
                if #vaalin_ids < 1 then
                    vars["Roll Amount"] = 100
                end
                if lp and lp.no_vaalin_picks then
                    lp.no_vaalin_picks(vars, settings, all_pick_ids)
                end
                if lp and lp.next_pick then
                    lp.next_pick(vars, settings, all_pick_ids, settings_pick_names)
                end
            end
        elseif vars["Next Task"] == "open plinite" then
            if vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            else
                if modes and modes.open_current_plinite then
                    modes.open_current_plinite(vars, settings)
                end
            end
        elseif vars["Next Task"] == "next plinite" then
            util.tpick_put_stuff_away(vars, settings)
            if vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            end
        elseif vars["Next Task"] == "scale_disarm_call" then
            if traps and traps.disarm_scale then
                traps.disarm_scale(vars, settings)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Internal helper: Check if we're in rogue repair lockpick automation mode.
--
-- @param vars  Picking state table.
-- @return true if in rogue repair task mode, false otherwise.
---------------------------------------------------------------------------
function rogue_automate_check(vars)
    return vars["rogue_automate_current_task_with_tpick"]
        and vars["Picking Mode"] == "worker"
        and (vars["rogue_current_task"] or "") == "Repair broken lockpicks"
end

return M
