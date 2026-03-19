--- @revenant-script
--- name: hunting-buddy
--- version: 1.0
--- game: dr
--- description: Orchestrates hunting sessions using combat-trainer with configurable stop conditions.
--- tags: hunting, combat, automation, training, orchestration
--- original-authors: Ondreian, Nisugi, and dr-scripts contributors
--- source: https://elanthipedia.play.net/Lich_script_repository#hunting-buddy
--- @lic-certified: complete 2026-03-18
---
--- Conversion notes vs Lich5:
---   * DRSkill.getxp uses 0-19 scale (Lich5 used 0-34).
---     Adjust yaml thresholds proportionally (e.g. 34 → 19, 25 → ~14).
---   * $COMBAT_TRAINER global replaced with Script.running("combat-trainer") checks.
---   * GUI monitor window added (enhancement) — shows hunt status and manual controls.
---   * DRC.wait_for_script_to_complete now fully implemented (was stub).
---   * over_box_limit? uses direct box count vs settings.box_hunt_maximum.

-- ============================================================================
-- Settings and data loading
-- ============================================================================

local args = Script.vars

local settings = get_settings(args[1] and { args[1] } or {})
local town_data = get_data("town")
local hunting_data = get_data("hunting")

local hometown_data = town_data and settings.hometown and town_data[settings.hometown] or {}
local escort_zones  = hunting_data and hunting_data.escort_zones  or {}
local hunting_zones = hunting_data and hunting_data.hunting_zones or {}

-- Config fields
local stop_on_familiar_drag  = settings.stop_on_familiar_drag
local stop_to_burgle         = settings.stop_to_burgle
local stop_on_low_threshold  = settings.stop_on_low_threshold
local stop_on_high_threshold = settings.stop_on_high_threshold
local hunting_buddies_max    = settings.hunting_buddies_max or 0
local prehunt_buffing_room   = settings.prehunt_buffing_room or settings.prehunt_buffs
local prehunt_buff_waggle    = settings.prehunt_buff_waggle or "prehunt_buffs"

-- Per-skillset thresholds (0-19 scale in Revenant)
local skillset_exp_thresholds = {
    Armor    = settings.armor_exp_training_max_threshold,
    Weapon   = settings.weapon_exp_training_max_threshold,
    Magic    = settings.magic_exp_training_max_threshold,
    Survival = settings.survival_exp_training_max_threshold,
    Lore     = settings.lore_exp_training_max_threshold,
}

-- Build the ordered list of hunting info entries
local hunting_info = {}

local hunting_files = {}
if args[1] then
    -- Args passed on command line become the file list
    for i = 1, #args do
        hunting_files[#hunting_files + 1] = args[i]
    end
end
if settings.hunting_file_list and #settings.hunting_file_list > 0 then
    for _, f in ipairs(settings.hunting_file_list) do
        hunting_files[#hunting_files + 1] = f
    end
end
if #hunting_files == 0 then
    hunting_files[#hunting_files + 1] = "setup"
end

for _, suffix in ipairs(hunting_files) do
    local file_settings = get_settings({ suffix })
    local infos = file_settings and file_settings.hunting_info or {}
    for _, info in ipairs(infos) do
        info.args = info.args or {}
        if suffix ~= "setup" then
            -- Inject config suffix so combat-trainer knows which config to use
            local already = false
            for _, a in ipairs(info.args) do
                if a == suffix then already = true; break end
            end
            if not already then
                info.args[#info.args + 1] = suffix
            end
        end
        hunting_info[#hunting_info + 1] = info
    end
end

-- ============================================================================
-- State
-- ============================================================================

local stop_hunting       = false   -- manual stop requested
local next_hunt          = false   -- skip to next entry
local stopped_for_bleed  = false   -- bleeding forced stop
local escort_exit        = nil     -- { area, "exit" } for bescort cleanup
local current_zone       = nil     -- name of the zone we're in

-- ============================================================================
-- GUI monitor
-- ============================================================================

local gui_win        = nil
local gui_status_lbl = nil
local gui_hunt_lbl   = nil
local gui_timer_lbl  = nil
local gui_cond_lbl   = nil

local function build_gui()
    gui_win = Gui.window("Hunting Buddy", { width = 380, height = 320, resizable = true })

    local root = Gui.vbox()

    -- Header card
    local header_card = Gui.card({ title = "Hunt Status" })
    local header_box = Gui.vbox()
    gui_status_lbl = Gui.label("Initializing…")
    gui_hunt_lbl   = Gui.label("No hunt active")
    gui_timer_lbl  = Gui.label("Timer: —")
    header_box:add(gui_status_lbl)
    header_box:add(gui_hunt_lbl)
    header_box:add(gui_timer_lbl)
    header_card:add(header_box)
    root:add(header_card)

    -- Conditions card
    local cond_card = Gui.card({ title = "Stop Conditions" })
    gui_cond_lbl = Gui.label("—")
    cond_card:add(gui_cond_lbl)
    root:add(cond_card)

    -- Controls
    local btn_row = Gui.hbox()

    local stop_btn = Gui.button("Stop Hunt")
    stop_btn:on_click(function()
        stop_hunting = true
        gui_status_lbl:set_text("Stopping (manual)…")
    end)
    btn_row:add(stop_btn)

    local next_btn = Gui.button("Next Hunt")
    next_btn:on_click(function()
        next_hunt = true
        gui_status_lbl:set_text("Skipping to next hunt…")
    end)
    btn_row:add(next_btn)

    local quit_btn = Gui.button("Quit Script")
    quit_btn:on_click(function()
        stop_hunting = true
        Script.kill(Script.name)
    end)
    btn_row:add(quit_btn)

    root:add(btn_row)
    gui_win:set_root(root)
    gui_win:show()
end

local function gui_set_status(txt)
    if gui_status_lbl then gui_status_lbl:set_text(txt) end
end

local function gui_set_hunt(txt)
    if gui_hunt_lbl then gui_hunt_lbl:set_text(txt) end
end

local function gui_set_timer(txt)
    if gui_timer_lbl then gui_timer_lbl:set_text(txt) end
end

local function gui_set_cond(txt)
    if gui_cond_lbl then gui_cond_lbl:set_text(txt) end
end

-- ============================================================================
-- Helpers
-- ============================================================================

--- Resolve zone list from an info entry (string or table).
local function get_zones(info)
    local z = info.zone or info[":zone"]
    if not z then return {} end
    if type(z) == "string" then return { z } end
    return z  -- already a table
end

--- Execute a list of scripts, waiting for each to complete.
local function execute_actions(actions)
    if not actions then return end
    for _, action in ipairs(actions) do
        DRC.message("***STATUS*** EXECUTE " .. action)
        local parts = {}
        for part in action:gmatch("%S+") do parts[#parts + 1] = part end
        local name = table.remove(parts, 1)
        DRC.wait_for_script_to_complete(name, parts)
    end
end

--- Start scripts in the background (non-blocking).
local function execute_nonblocking_actions(actions)
    if not actions then return end
    for _, action in ipairs(actions) do
        DRC.message("***STATUS*** EXECUTE " .. action)
        local parts = {}
        for part in action:gmatch("%S+") do parts[#parts + 1] = part end
        local name = table.remove(parts, 1)
        local args_str = table.concat(parts, " ")
        Script.run(name, args_str)
    end
end

--- Kill a list of running scripts.
local function stop_actions(actions)
    if not actions then return end
    for _, action in ipairs(actions) do
        local name = action:match("^%S+")
        if name and Script.running(name) then
            DRC.message("***STATUS*** STOP " .. name)
            Script.kill(name)
        end
    end
end

--- Check if bleeding.
local function is_bleeding()
    return GameState and GameState.bleeding and GameState.bleeding() or false
end

--- Check encumbrance against a 0-6 threshold (matches DRC.check_encumbrance scale).
local function encumbered(threshold)
    if not threshold then return false end
    threshold = math.max(0, math.min(6, math.floor(tonumber(threshold) or 0)))
    local enc = DRC.check_encumbrance(false)  -- use cached value
    return enc >= threshold
end

--- Return the current hunting zone name (nil if not in a known zone).
local function get_current_hunting_zone(room_id)
    room_id = room_id or (Map and Map.current_room())
    if not room_id then return nil end
    for zone_name, rooms in pairs(hunting_zones) do
        if type(rooms) == "table" then
            for _, rid in ipairs(rooms) do
                if rid == room_id then return zone_name end
            end
        end
    end
    return nil
end

--- Get the skillset high-stop threshold for a skill.
local function get_skillset_high_threshold(skillset)
    return stop_on_high_threshold or skillset_exp_thresholds[skillset]
end

--- Get the skillset low-stop threshold for a skill.
local function get_skillset_low_threshold(_skillset)
    return stop_on_low_threshold
end

--- True if ALL skills in the list are at/above their high threshold.
local function should_stop_for_high_skills(skill_list)
    if not skill_list or #skill_list == 0 then return false end
    for _, skill in ipairs(skill_list) do
        local xp        = DRSkill.getxp(skill)
        local skillset  = DRSkill.getskillset(skill)
        local threshold = get_skillset_high_threshold(skillset)
        if not threshold or xp < threshold then
            return false
        end
    end
    return true
end

--- True if ANY skill in the list is at/below its low threshold.
local function should_stop_for_low_skills(skill_list)
    if not skill_list or #skill_list == 0 then return false end
    for _, skill in ipairs(skill_list) do
        local xp        = DRSkill.getxp(skill)
        local skillset  = DRSkill.getskillset(skill)
        local threshold = get_skillset_low_threshold(skillset)
        if threshold and xp <= threshold then
            return true
        end
    end
    return false
end

--- Return skills from list that have NOT yet met their high threshold.
local function get_skills_below_high(skill_list)
    if not skill_list then return {} end
    local result = {}
    for _, skill in ipairs(skill_list) do
        local xp        = DRSkill.getxp(skill)
        local skillset  = DRSkill.getskillset(skill)
        local threshold = get_skillset_high_threshold(skillset)
        if not threshold or xp < threshold then
            result[#result + 1] = skill
        end
    end
    return result
end

-- Cache box count to avoid rummaging containers every second.
local box_count_cache       = 0
local box_count_last_update = 0
local BOX_CACHE_TTL         = 60  -- seconds

local function cached_box_count()
    local now = os.time()
    if (now - box_count_last_update) >= BOX_CACHE_TTL then
        box_count_cache       = DRCI.count_all_boxes(settings)
        box_count_last_update = now
    end
    return box_count_cache
end

--- Have we collected more boxes than the configured maximum?
local function over_box_limit()
    if not settings.box_hunt_maximum then return false end
    return cached_box_count() >= settings.box_hunt_maximum
end

--- Have we collected fewer boxes than the configured minimum?
local function need_boxes()
    if not settings.box_hunt_minimum then return false end
    return cached_box_count() <= settings.box_hunt_minimum
end

--- Check the yiamura cooldown (last-raised cooldown, 10 min window).
local function yiamura_all_done()
    local yiamura = UserVars.yiamura
    if not yiamura then return true end
    local room_id = Map and Map.current_room()
    if yiamura.last_raised_room_id ~= room_id then return true end
    local last = tonumber(yiamura.last_raised) or 0
    return (os.time() - last) > 600
end

-- ============================================================================
-- Pre-hunt helpers
-- ============================================================================

local function check_bundling_rope()
    if not settings.skinning or not settings.skinning.skin then return end
    if DRCI.wearing("bundle") then return end
    if DRCI.exists("bundling rope") then return end
    -- Go buy one from the tannery
    local tannery = hometown_data.tannery
    if tannery then
        DRCT.ask_for_item(tannery.id, tannery.name, "bundling rope")
        DRCI.stow_hand("right")
    end
end

local function check_prehunt_buffs()
    if not settings.waggle_sets then return end
    if not settings.waggle_sets[prehunt_buff_waggle] then return end
    if prehunt_buffing_room then
        DRCT.walk_to(prehunt_buffing_room)
    end
    DRC.wait_for_script_to_complete("buff", { prehunt_buff_waggle })
end

-- ============================================================================
-- Hunting room finder
-- ============================================================================

--- Find a suitable hunting room from the given zones.
-- Returns true if we found and are standing in a room, false otherwise.
local function find_hunting_room(zones_to_search, waiting_room, prefer_buddies, avoid_buddies)
    UserVars.friends          = settings.hunting_buddies  or {}
    UserVars.hunting_nemesis  = settings.hunting_nemesis  or {}

    for _, zone in ipairs(zones_to_search) do
        local escort_info = escort_zones[zone]
        if escort_info then
            -- Escort zone: walk to base, run bescort, store exit info
            DRCT.walk_to(escort_info.base)
            DRC.wait_for_script_to_complete("bescort", { escort_info.area, escort_info.enter })
            escort_exit = { escort_info.area, "exit" }
            return true
        end
    end

    -- Standard zone search
    escort_exit = nil
    local rooms_to_search = {}
    local added = {}

    for _, zone in ipairs(zones_to_search) do
        local custom = settings.custom_hunting_zones and settings.custom_hunting_zones[zone]
        if custom then
            if hunting_zones[zone] then
                echo("[hunting-buddy] Overriding base-hunting.yaml zone: " .. zone)
            end
            for _, rid in ipairs(custom) do
                if not added[rid] then
                    rooms_to_search[#rooms_to_search + 1] = rid
                    added[rid] = true
                end
            end
        elseif hunting_zones[zone] then
            for _, rid in ipairs(hunting_zones[zone]) do
                if not added[rid] then
                    rooms_to_search[#rooms_to_search + 1] = rid
                    added[rid] = true
                end
            end
        else
            echo("[hunting-buddy] Unknown hunting zone: " .. zone)
        end
    end

    if #rooms_to_search == 0 then
        DRC.message("Unable to look up any hunting rooms. Check yaml :zone: entries.")
        return false
    end

    local max_searches = settings.hunting_room_max_searches or 999
    local min_mana     = settings.hunting_room_min_mana
    local strict_mana  = settings.hunting_room_strict_mana

    -- Build the room evaluation predicate
    local function room_predicate(_search_attempt)
        -- Clear previous capture so we don't carry stale state into this evaluation
        Flags.reset("hunting-buddy-room-check")

        local pcs       = DRRoom.pcs or {}
        local group_mb  = DRRoom.group_members or {}
        local friends   = UserVars.friends or {}
        local nemesis   = UserVars.hunting_nemesis or {}

        -- Skip if room has a nemesis
        for _, pc in ipairs(pcs) do
            for _, nem in ipairs(nemesis) do
                if pc == nem then return false end
            end
        end

        -- Skip if more people than allowed (excluding group members)
        local non_group_pcs = {}
        for _, pc in ipairs(pcs) do
            local in_group = false
            for _, gm in ipairs(group_mb) do
                if pc == gm then in_group = true; break end
            end
            if not in_group then
                non_group_pcs[#non_group_pcs + 1] = pc
            end
        end
        if #non_group_pcs > hunting_buddies_max then return false end

        -- Skip if avoid_buddies and a friend is in the room
        if avoid_buddies then
            for _, pc in ipairs(non_group_pcs) do
                for _, friend in ipairs(friends) do
                    if pc == friend then return false end
                end
            end
        end

        -- If prefer_buddies and a friend is here: accept immediately
        if prefer_buddies then
            for _, pc in ipairs(non_group_pcs) do
                for _, friend in ipairs(friends) do
                    if pc == friend then return true end
                end
            end
        end

        -- No unexpected PCs must be present (beyond group members)
        if #non_group_pcs > 0 then
            -- Check if any are friends before rejecting
            for _, pc in ipairs(non_group_pcs) do
                local is_friend = false
                for _, friend in ipairs(friends) do
                    if pc == friend then is_friend = true; break end
                end
                if not is_friend then return false end
            end
        end

        -- Mana check if configured (skip for Moon Mage / Trader who use lunar mana pools)
        if min_mana then
            local mana_pct = GameState and GameState.mana and GameState.mana() or 100
            local max_mana = GameState and GameState.max_mana and GameState.max_mana() or 100
            if max_mana > 0 then
                local pct = (mana_pct / max_mana) * 100
                if pct < min_mana then
                    if strict_mana then return false end
                    -- Non-strict: accept but warn
                    echo("[hunting-buddy] Mana low (" .. math.floor(pct) .. "%) but not strict — accepting room")
                end
            end
        end

        -- Search the room for hidden people
        Flags.add("hunting-buddy-room-check",
            "says?, ",
            "You hear",
            "Someone snipes a",
            "leaps from hiding and ambushes",
            "[A-Z][a-z]+ begins to advance",
            "[A-Z][a-z]+ (jabs|slices|draws|chops|sweeps|lunges|thrusts|claws|gouges|elbows|kicks|punches|knees|shoves|lobs|throws|hurls|fires|shoots|feints) (a|an|some|his|her|their)")

        for _, friend in ipairs(friends) do
            Flags.add("hunting-buddy-friend-" .. friend, friend)
        end

        local search_result = DRC.bput("search",
            "roundtime",
            "You're not in any condition to be searching around")

        if search_result:find("not in any condition") then
            DRC.message("***STATUS*** Too injured to hunt!")
            stop_hunting = true
            stopped_for_bleed = is_bleeding()
            -- Return true so the search loop stops quickly
            return true
        end

        waitrt()

        -- Check if any friends spoke up
        for _, friend in ipairs(friends) do
            if Flags["hunting-buddy-friend-" .. friend] then
                return true  -- friend is here, accept room
            end
        end

        -- Check search results for hidden people
        local recent = reget(40)
        if type(recent) == "table" then
            for _, line in ipairs(recent) do
                if line:find("vague silhouette") or line:find("You notice .*, who is") or line:find("see signs that") then
                    -- Hidden person found — wait briefly to see if it's a friend
                    pause(1)
                    for _, friend in ipairs(friends) do
                        if Flags["hunting-buddy-friend-" .. friend] then
                            return true
                        end
                    end
                    return false
                end
            end
        end

        -- Room appears empty — say greeting if configured
        if settings.empty_hunting_room_messages and #settings.empty_hunting_room_messages > 0 then
            local idx = math.random(1, #settings.empty_hunting_room_messages)
            fput("say " .. settings.empty_hunting_room_messages[idx])
        end

        -- Wait a moment watching for activity
        local room_is_empty = true
        for _ = 1, 20 do
            pause(0.5)
            for _, friend in ipairs(friends) do
                if Flags["hunting-buddy-friend-" .. friend] then return true end
            end
            if Flags["hunting-buddy-room-check"] then return false end
            local cur_pcs    = DRRoom.pcs or {}
            local cur_group  = DRRoom.group_members or {}
            local cur_friends = UserVars.friends or {}
            local non_friends = {}
            for _, pc in ipairs(cur_pcs) do
                local in_group_or_friend = false
                for _, gm in ipairs(cur_group) do
                    if pc == gm then in_group_or_friend = true; break end
                end
                if not in_group_or_friend then
                    for _, f in ipairs(cur_friends) do
                        if pc == f then in_group_or_friend = true; break end
                    end
                end
                if not in_group_or_friend then
                    non_friends[#non_friends + 1] = pc
                end
            end
            room_is_empty = (#non_friends == 0)
        end
        return room_is_empty
    end

    return DRCT.find_empty_room(rooms_to_search, waiting_room, room_predicate, max_searches)
end

-- ============================================================================
-- Hunt monitor loop
-- ============================================================================

local function hunt(info_args, duration, stop_on_high_skills, stop_on_low_skills,
                    stop_on_boxes, stop_on_no_moons, stop_on_encumbrance, stop_on_burgle_cooldown)

    local hunting_room = Map and Map.current_room()

    Flags.add("hunting-buddy-familiar-drag",
        "^Your .+ grabs ahold of you and drags you .+, out of combat.+$")
    Flags.add("hunting-buddy-stop-to-burgle",
        "^A tingling on the back of your neck draws attention to itself by disappearing, making you believe the heat is off from your last break in")

    local args_str = type(info_args) == "table" and table.concat(info_args, " ") or (info_args or "")
    DRC.message("***STATUS*** Beginning hunt '" .. args_str .. "' for '" .. tostring(duration) .. "' minutes")
    gui_set_status("Hunting")

    -- Verify combat-trainer exists
    if not Script.exists("combat-trainer") then
        DRC.message("***STATUS*** combat-trainer script not found!")
        return
    end

    -- Launch combat-trainer (non-blocking)
    Script.run("combat-trainer", args_str)

    -- Wait up to 30s for combat-trainer to start
    local start_wait = os.time()
    while not Script.running("combat-trainer") and (os.time() - start_wait) < 30 do
        pause(1)
    end

    local counter    = 0  -- seconds elapsed
    local hunt_start = os.time()

    while true do
        clear()

        -- Health emergency
        if DRStats.health and DRStats.health < (settings.health_threshold or 30) then
            DRC.message("***STATUS*** Exiting because low health: " .. tostring(DRStats.health))
            fput("avoid all")
            fput("exit")
        end

        -- Bleeding stop
        if settings.stop_hunting_if_bleeding and is_bleeding() then
            DRC.message("***STATUS*** Stopping because bleeding")
            stopped_for_bleed = true
            break
        end

        -- Box limit stop
        if stop_on_boxes and over_box_limit() then
            DRC.message("***STATUS*** Stopping hunt because have enough boxes")
            break
        end

        -- Moon stop
        if stop_on_no_moons and not DRCMM.moons_visible() then
            DRC.message("***STATUS*** Stopping because no moons")
            break
        end

        -- High skill stop (with yiamura check)
        if should_stop_for_high_skills(stop_on_high_skills) and yiamura_all_done() then
            DRC.message("***STATUS*** Stopping because skills reached threshold: " ..
                table.concat(stop_on_high_skills or {}, ", "))
            break
        end

        -- Low skill stop (with yiamura check)
        if should_stop_for_low_skills(stop_on_low_skills) and yiamura_all_done() then
            DRC.message("***STATUS*** Stopping because skills dropped below threshold: " ..
                table.concat(stop_on_low_skills or {}, ", "))
            break
        end

        -- Manual stop or next-hunt request
        if stop_hunting or next_hunt then
            DRC.message("***STATUS*** Stopping because manual intervention")
            next_hunt = false
            break
        end

        -- Duration expired (with yiamura check)
        if duration and (counter / 60) >= duration and yiamura_all_done() then
            DRC.message("***STATUS*** Stopping because time")
            break
        end

        -- Burgle cooldown expired
        if Flags["hunting-buddy-stop-to-burgle"] and (stop_to_burgle or stop_on_burgle_cooldown) and yiamura_all_done() then
            DRC.message("***STATUS*** Stopping because it's burgle time!")
            Flags.reset("hunting-buddy-stop-to-burgle")
            break
        end

        -- Familiar drag handling
        if Flags["hunting-buddy-familiar-drag"] then
            if stop_on_familiar_drag then
                DRC.message("***STATUS*** Stopping because familiar dragged while stunned")
                Flags.reset("hunting-buddy-familiar-drag")
                break
            else
                DRC.message("***STATUS*** Heading back to room because familiar dragged while stunned")
                Script.pause("combat-trainer")
                if hunting_room then DRCT.walk_to(hunting_room) end
                Script.unpause("combat-trainer")
                Flags.reset("hunting-buddy-familiar-drag")
            end
        end

        -- Periodic (once per minute) checks and status update
        if counter % 60 == 0 then
            -- Encumbrance check (only periodically to avoid spam)
            if encumbered(stop_on_encumbrance) then
                DRC.message("***STATUS*** Stopping because encumbrance, threshold: " ..
                    tostring(stop_on_encumbrance))
                break
            end

            -- Status message and GUI update
            local elapsed_min = math.floor(counter / 60)
            local status_parts = {}

            if duration then
                local remaining = duration - elapsed_min
                status_parts[#status_parts + 1] = remaining .. " min remaining"
            else
                status_parts[#status_parts + 1] = elapsed_min .. " min elapsed"
            end

            if stop_on_high_skills and #stop_on_high_skills > 0 then
                local waiting = get_skills_below_high(stop_on_high_skills)
                if #waiting > 0 then
                    status_parts[#status_parts + 1] = "waiting on " .. table.concat(waiting, ", ")
                end
                gui_set_cond("Skills: " .. table.concat(waiting, ", "))
            end

            DRC.message("***STATUS*** " .. table.concat(status_parts, " | "))
            gui_set_timer(table.concat(status_parts, " | "))
        end

        counter = counter + 1
        pause(1)
    end

    -- Stop combat-trainer and wait for it to exit
    if Script.running("combat-trainer") then
        Script.kill("combat-trainer")
        local kill_start = os.time()
        while Script.running("combat-trainer") and (os.time() - kill_start) < 10 do
            pause(0.5)
        end
    end

    DRC.retreat()

    gui_set_status("Hunt ended")
end

-- ============================================================================
-- Main
-- ============================================================================

local function main()
    build_gui()
    gui_set_status("Starting up…")

    check_bundling_rope()

    if not settings.sell_loot_skip_bank then
        DRC.wait_for_script_to_complete("restock")
    end

    for idx, info in ipairs(hunting_info) do
        local info_args          = info.args or {}
        local before_actions     = info.before or {}
        local after_actions      = info.after or {}
        local during_actions     = info.during or {}
        local duration           = info.duration
        local stop_on_high       = info.stop_on
        local stop_on_low        = info.stop_on_low
        local stop_on_boxes_flag = info.boxes or info.stop_on_boxes
        local stop_on_no_moons   = info.moons or info.stop_on_moons
        local stop_on_encumb     = info.stop_on_encumbrance
        local stop_on_burgle     = info.stop_on_burgle_cooldown
        local zones              = get_zones(info)
        local waiting_room       = info.full_waiting_room or settings.safe_room
        local prefer_buddies     = info.prefer_buddies
        local avoid_buddies      = info.avoid_buddies

        -- Normalize stop_on lists (may be string or table in yaml)
        if type(stop_on_high) == "string" then stop_on_high = { stop_on_high } end
        if type(stop_on_low) == "string"  then stop_on_low  = { stop_on_low }  end

        gui_set_hunt("Hunt " .. idx .. "/" .. #hunting_info ..
            " | Zone: " .. table.concat(zones, ","))

        -- Manual stop check
        if stop_hunting then
            DRC.message("***STATUS*** Stopping all hunting — manual intervention")
            stop_actions(during_actions)
            execute_actions(after_actions)
            break
        end

        -- Bleeding stop check
        if stopped_for_bleed then
            DRC.message("***STATUS*** Stopping all hunting — bleeding")
            DRC.retreat()
            if Script.running("tendme") then Script.kill("tendme") end
            stop_actions(during_actions)
            execute_actions(after_actions)
            break
        end

        -- Box check (skip hunt if already have enough)
        if stop_on_boxes_flag and not need_boxes() then
            DRC.message("***STATUS*** Skipping hunt — have enough boxes")
            goto continue
        end

        execute_actions(before_actions)

        -- Moon check (after before_actions since they may buff/prep)
        if stop_on_no_moons and not DRCMM.moons_visible() then
            DRC.message("***STATUS*** Skipping hunt — no moons")
            stop_actions(during_actions)
            execute_actions(after_actions)
            goto continue
        end

        -- Encumbrance check
        if encumbered(stop_on_encumb) then
            DRC.message("***STATUS*** Skipping hunt — encumbered (threshold: " ..
                tostring(stop_on_encumb) .. ")")
            stop_actions(during_actions)
            execute_actions(after_actions)
            goto continue
        end

        -- Skill threshold checks (pre-hunt)
        if should_stop_for_high_skills(stop_on_high) then
            DRC.message("***STATUS*** Skipping hunt — skills at threshold: " ..
                table.concat(stop_on_high or {}, ", "))
            stop_actions(during_actions)
            execute_actions(after_actions)
            goto continue
        end
        if should_stop_for_low_skills(stop_on_low) then
            DRC.message("***STATUS*** Skipping hunt — skills below low threshold")
            stop_actions(during_actions)
            execute_actions(after_actions)
            goto continue
        end

        check_prehunt_buffs()

        -- Find hunting room
        do
            local need_new_room = (idx == 1) or not zones or
                not (function()
                    for _, z in ipairs(zones) do
                        if z == current_zone then return true end
                    end
                    return false
                end)()

            if need_new_room then
                gui_set_status("Searching for room…")
                local found = find_hunting_room(zones, waiting_room, prefer_buddies, avoid_buddies)
                if not found then
                    goto continue
                end
                current_zone = get_current_hunting_zone()
            end
        end

        -- Bleeding check after navigation
        if stopped_for_bleed then
            DRC.message("***STATUS*** Stopping all hunting — bleeding after travel")
            DRC.retreat()
            if Script.running("tendme") then Script.kill("tendme") end
            stop_actions(during_actions)
            execute_actions(after_actions)
            break
        end

        execute_nonblocking_actions(during_actions)

        hunt(info_args, duration, stop_on_high, stop_on_low,
            stop_on_boxes_flag, stop_on_no_moons, stop_on_encumb, stop_on_burgle)

        stop_actions(during_actions)

        -- Stow anything in hand/at feet
        if DRC.right_hand() and DRC.left_hand() then
            DRCI.stow_hand("left")
        end
        while DRC.bput("stow feet", "You pick up", "Stow what"):find("You pick up") do
            -- stow each item
        end

        -- Release escort if needed
        if escort_exit then
            DRC.wait_for_script_to_complete("bescort", escort_exit)
            escort_exit = nil
        end

        -- Release cyclic spells
        DRCA.release_cyclics(settings.cyclic_no_release)

        execute_actions(after_actions)

        ::continue::
    end

    -- Return to safe room and change back to standard gear
    DRC.message("***STATUS*** Returning to safe room: " .. tostring(settings.safe_room))
    if settings.safe_room then
        DRCT.walk_to(settings.safe_room)
    end

    local gear_set = settings.combat_trainer_gear_set or "standard"
    DREMgr.EquipmentManager(settings):wear_equipment_set(gear_set)

    gui_set_status("Done — safe room reached")
    DRC.message("***STATUS*** Hunting buddy complete")

    if gui_win then
        Gui.wait(gui_win, "close")
    end
end

-- ============================================================================
-- Cleanup on exit
-- ============================================================================

before_dying(function()
    if Script.running("combat-trainer") then
        Script.kill("combat-trainer")
    end
    DRCA.release_cyclics(settings.cyclic_no_release)

    -- Remove all hunting-buddy flags we may have registered
    Flags.remove("hunting-buddy-familiar-drag")
    Flags.remove("hunting-buddy-stop-to-burgle")
    Flags.remove("hunting-buddy-room-check")
    -- Remove per-friend flags
    local friends = (settings and settings.hunting_buddies) or {}
    for _, friend in ipairs(friends) do
        Flags.remove("hunting-buddy-friend-" .. friend)
    end

    if gui_win then
        pcall(function() gui_win:close() end)
    end
end)

main()
