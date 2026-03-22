--- @revenant-script
--- name: training-manager
--- version: 1.0
--- author: Nisugi, Etreu, and dr-scripts contributors
--- game: dr
--- description: Orchestrates town training and hunting cycles. Manages crossing-training,
---   hunting-buddy, safe-room, crossing-repair, mining-buddy, forestry-buddy,
---   sell-loot, and favor checking in a configurable loop.
--- tags: training, hunting, automation, orchestration, favors, repair
--- source: https://elanthipedia.play.net/Lich_script_repository#training-manager
--- @lic-certified: complete 2026-03-18
---
--- Converted from training-manager.lic
--- Original authors: Nisugi, Etreu, and dr-scripts contributors
---
--- Changelog vs Lich5:
---   v1.0 - Initial conversion
---   * parse_args replaced with Script.vars (check for "skip" in args[1])
---   * $CROSSING_TRAINER global replaced with Script.run/kill/running calls.
---     Idle state communicated via UserVars.crossing_trainer_idle = "true"
---     (crossing-training.lua must set this when it enters an idle/waiting state).
---   * DRSkill.getxp uses 0-19 scale (Lich5 used 0-34).
---     Adjust priority_skills_lower_limit in YAML proportionally (e.g. 34 → 19).
---   * DRC.bput uses plain-string matching; patterns simplified accordingly.
---   * GUI status window added (enhancement) — shows current phase and counters.

-- ============================================================================
-- Settings and initialization
-- ============================================================================

fput("awaken")

local args = Script.vars
local skip = args[1] and args[1]:lower() == "skip"

local settings = get_settings()
local town_data = get_data("town")

local hometown_data = (town_data and settings.hometown and town_data[settings.hometown]) or {}
local skip_repair   = settings.skip_repair
local sell_loot     = settings.sell_loot
local repair_every  = settings.repair_every
local use_favor_altars = settings.use_favor_altars

-- Persistent repair counter (survives across runs)
if not UserVars.repair_every_counter then
    UserVars.repair_every_counter = "0"
end

-- ============================================================================
-- GUI status window (enhancement — no Lich5 equivalent)
-- ============================================================================

local win, lbl_mode, lbl_phase, lbl_favor, lbl_repair

local function build_gui()
    win = Gui.window("Training Manager", { width = 260, height = 160, resizable = false })
    local root = Gui.vbox()

    lbl_mode  = Gui.label("Mode:  —")
    lbl_phase = Gui.label("Phase: —")
    lbl_favor = Gui.label("Favors: —")
    lbl_repair = Gui.label("Repair counter: —")

    root:add(Gui.section_header("Training Manager"))
    root:add(lbl_mode)
    root:add(lbl_phase)
    root:add(lbl_favor)
    root:add(lbl_repair)

    win:set_root(root)
    win:show()
end

local function gui_set_mode(mode)
    if lbl_mode then lbl_mode:set_text("Mode:  " .. mode) end
end

local function gui_set_phase(phase)
    if lbl_phase then lbl_phase:set_text("Phase: " .. phase) end
end

local function gui_set_favor(count, goal)
    if lbl_favor then
        if goal then
            lbl_favor:set_text(string.format("Favors: %d / %d", count, goal))
        else
            lbl_favor:set_text("Favors: (no goal set)")
        end
    end
end

local function gui_set_repair(counter, every)
    if lbl_repair then
        if every then
            lbl_repair:set_text(string.format("Repair counter: %d / %d", counter, every))
        else
            lbl_repair:set_text("Repair counter: (disabled)")
        end
    end
end

-- Only show GUI if the monitor feature is available
if Gui then
    local ok = pcall(build_gui)
    if not ok then
        win = nil  -- GUI not available; continue without it
    end
end

-- ============================================================================
-- Helpers
-- ============================================================================

--- Return true if the training timer has expired.
local function timer_expired(start_time)
    if not settings.training_manager_town_duration then return false end
    return (os.time() - start_time) >= (settings.training_manager_town_duration * 60)
end

--- Return true if any priority skill has XP at or below the lower limit.
-- NOTE: DRSkill.getxp uses 0-19 scale in Revenant (Lich5 used 0-34).
-- Adjust settings.priority_skills_lower_limit proportionally.
local function priority_skills_low()
    local skills = settings.training_manager_priority_skills
    local limit  = settings.priority_skills_lower_limit
    if not skills or not limit then return false end
    for _, skill in ipairs(skills) do
        local xp = DRSkill.getxp(skill)
        if xp and xp <= limit then return true end
    end
    return false
end

--- Check current favor count via game command. Returns integer.
local function get_favor_count()
    local result = DRC.bput("favor", "You currently have", "You are not currently")
    if result and result:find("currently have") then
        local n = result:match("(%d+)")
        if n then return tonumber(n) end
    end
    return 0
end

--- Rub the favor orb and return true if sacrifice is properly prepared.
local function rub_orb()
    local god = settings.favor_god or "chadatru"
    local result = DRC.bput("rub my " .. god .. " orb",
        "not yet fully prepared",
        "lacking in the type of sacrifice",
        "your sacrifice is properly prepared")
    return result and result:find("properly prepared") ~= nil
end

--- Delegate to the favor script (with or without god argument).
local function run_favors()
    local god = settings.favor_god or "chadatru"
    if use_favor_altars then
        DRC.wait_for_script_to_complete("favor", { god })
    else
        DRC.wait_for_script_to_complete("favor")
    end
end

--- Check favor status and run favor quests if needed.
local function check_favors()
    if not settings.favor_goal then return end

    local favor_count = get_favor_count()
    gui_set_favor(favor_count, settings.favor_goal)

    if favor_count >= settings.favor_goal then return end

    local god = settings.favor_god or "chadatru"
    local tap_result = DRC.bput("tap my " .. god .. " orb",
        "The orb is delicate",
        "I could not find")

    if tap_result and tap_result:find("could not") then
        -- Orb not found — earn more favors, then stow
        gui_set_phase("running favors")
        run_favors()
        fput("stow my orb")
    elseif rub_orb() then
        -- Orb is ready for sacrifice — walk to altar and place it
        gui_set_phase("placing orb on altar")
        local altar = hometown_data.favor_altar
        if altar and altar.id then
            DRCT.walk_to(altar.id)
        end
        fput("get my " .. god .. " orb")
        fput("put my orb on altar")
        if favor_count + 1 < settings.favor_goal then
            -- Still more favors needed after this one
            run_favors()
            fput("stow my orb")
        end
    end
    -- Re-read favor count for GUI
    gui_set_favor(get_favor_count(), settings.favor_goal)
end

--- Conditionally run crossing-repair. Manages the repair_every counter.
local function check_repair()
    if skip_repair then return end

    local repair_args = {}

    if repair_every then
        local counter = tonumber(UserVars.repair_every_counter) or 0
        counter = counter + 1
        if counter >= repair_every then
            counter = 0
            repair_args = { "force" }
        end
        UserVars.repair_every_counter = tostring(counter)
        gui_set_repair(counter, repair_every)
    end

    gui_set_phase("repairing")
    DRC.wait_for_script_to_complete("crossing-repair", repair_args)
end

--- Run the post-hunt sequence: hunt → safe room → optional repair.
local function hunting_combo()
    gui_set_phase("hunting")
    DRC.wait_for_script_to_complete("hunting-buddy")

    gui_set_phase("safe room")
    DRC.wait_for_script_to_complete("safe-room")

    check_repair()
end

--- Start crossing-training and clear the idle flag.
local function start_crossing_training()
    UserVars.crossing_trainer_idle = nil
    Script.run("crossing-training")
    pause(5)  -- let it initialize
end

--- Stop crossing-training and wait for it to finish.
local function stop_crossing_training()
    Script.kill("crossing-training")
    local deadline = os.time() + 15
    while Script.running("crossing-training") and os.time() < deadline do
        pause(1)
    end
end

-- ============================================================================
-- Main loops
-- ============================================================================

--- Hunting-priority mode: train until priority skills are low, then hunt.
local function combat_loop()
    gui_set_mode("combat (hunting priority)")

    check_favors()
    if priority_skills_low() then
        gui_set_phase("initial hunt (priority skills low)")
        hunting_combo()
    end

    while true do
        settings = get_settings()
        clear()

        check_favors()

        if sell_loot then
            gui_set_phase("selling loot")
            DRC.wait_for_script_to_complete("sell-loot")
        end

        if settings.mine_while_training and not skip then
            gui_set_phase("mining")
            DRC.wait_for_script_to_complete("mining-buddy")
        end

        if settings.lumber_while_training and not skip then
            gui_set_phase("forestry")
            DRC.wait_for_script_to_complete("forestry-buddy")
        end
        skip = false

        gui_set_phase("crossing-training")
        start_crossing_training()
        local start_time = os.time()

        -- Keep training until a priority skill needs work or the timer expires
        while true do
            if priority_skills_low() or timer_expired(start_time) then break end
            pause(1)
        end

        stop_crossing_training()
        hunting_combo()
    end
end

--- Town-training-priority mode: train until crossing-training idles, then hunt.
-- Requires crossing-training.lua to set UserVars.crossing_trainer_idle = "true"
-- when it enters its idle/waiting state.
local function town_loop()
    gui_set_mode("town (training priority)")

    while true do
        settings = get_settings()
        clear()

        check_favors()

        if sell_loot then
            gui_set_phase("selling loot")
            DRC.wait_for_script_to_complete("sell-loot")
        end

        if settings.mine_while_training then
            gui_set_phase("mining")
            DRC.wait_for_script_to_complete("mining-buddy")
        end

        gui_set_phase("crossing-training")
        start_crossing_training()
        local start_time = os.time()

        -- Wait until crossing-training signals idle (or timer expires)
        while true do
            local idle_flag = UserVars.crossing_trainer_idle
            if (idle_flag and idle_flag ~= "") or timer_expired(start_time) then break end
            pause(1)
        end

        stop_crossing_training()
        hunting_combo()
    end
end

-- ============================================================================
-- Cleanup hook
-- ============================================================================

before_dying(function()
    if Script.running("hunting-buddy") then
        Script.kill("hunting-buddy")
    end
    if Script.running("crossing-training") then
        Script.kill("crossing-training")
    end
    if win then
        pcall(function() win:close() end)
    end
end)

-- ============================================================================
-- Entry point
-- ============================================================================

if settings.training_manager_hunting_priority then
    combat_loop()
else
    town_loop()
end
