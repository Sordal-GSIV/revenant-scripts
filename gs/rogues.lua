--- @revenant-script
--- name: rogues
--- version: 1.0.0
--- author: Dreaven (Tgo01)
--- game: gs
--- description: GS Rogue Guild training automation - Lock Mastery, Stun Maneuvers, Sweep, Subdue, Cheapshots
--- tags: rogue, guild, training, lockpick, sweep, subdue, stun, cheapshot
--- @lic-certified: complete 2026-03-18
---
--- Ported from rogues.lic (Lich5 lib/) to Revenant Lua
--- Original author: Dreaven (Tgo01) — Version 50
---
--- Current achievable ranks:
---   Lock Mastery:       MASTER
---   Stun Maneuvers:     MASTER
---   Sweep:              MASTER
---   Subdue:             MASTER
---   Cheapshots:         MASTER
---   Gambits:            0 (not yet implemented)
---
--- Usage:
---   ;rogues                  - Show usage info
---   ;rogues sweep            - Train Sweep skill
---   ;rogues subdue           - Train Subdue skill
---   ;rogues stun             - Train Stun Maneuvers skill
---   ;rogues lock / lmas      - Train Lock Mastery skill
---   ;rogues cheapshots       - Train Cheapshots skill
---   ;rogues setup            - Open settings GUI
---   ;rogues help             - Show task numbers for trade-in
---   ;rogues checkin          - Pay guild dues (3 months)
---   ;rogues wedge <N>        - Create N wooden wedges
---   ;rogues partner [name]   - Help partner with their tasks

-- ============================================================================
-- Utility: split a comma-separated string into a trimmed table
-- ============================================================================
local function split_csv(str)
    local result = {}
    if not str or str == "" then return result end
    for piece in str:gmatch("[^,]+") do
        local trimmed = piece:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end
    return result
end

--- Checks if a table contains a value
local function tbl_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

--- Find an NPC by name pattern in the room
local function find_npc(name_pattern)
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if npc.name:lower():find(name_pattern:lower()) then
            return npc
        end
    end
    return nil
end

--- Wait for an NPC to appear
local function wait_for_npc(name_pattern)
    local npc = find_npc(name_pattern)
    while not npc do
        pause(0.2)
        npc = find_npc(name_pattern)
    end
    return npc
end

-- ============================================================================
-- Display message box (bordered output like the Ruby version)
-- ============================================================================
local text_to_display = {}

local function display_message()
    respond("")
    local longest = 0
    for _, line in ipairs(text_to_display) do
        if #line + 12 > longest then longest = #line + 12 end
    end
    local border = string.rep("#", longest)
    respond(border)
    for _, line in ipairs(text_to_display) do
        local padding = longest - (#line + 7)
        respond("#     " .. line .. string.rep(" ", padding) .. "#")
    end
    respond(border)
    respond("")
    text_to_display = {}
end

-- ============================================================================
-- Parse command-line arguments
-- ============================================================================
local args = Script.vars or {}
local raw_skill = args[1] and args[1]:lower() or nil
local current_skill = nil

if raw_skill then
    if raw_skill:find("^check") then
        current_skill = "Checkin"
    elseif raw_skill:find("^swe") then
        current_skill = "Sweep"
    elseif raw_skill:find("^sub") then
        current_skill = "Subdue"
    elseif raw_skill:find("^stu") then
        current_skill = "Stun Maneuvers"
    elseif raw_skill:find("^loc") or raw_skill:find("^lmas") then
        current_skill = "Lock Mastery"
    elseif raw_skill:find("^che") then
        current_skill = "Cheapshots"
    elseif raw_skill:find("^gam") then
        current_skill = "Gambits"
    elseif raw_skill:find("^hel") then
        current_skill = "Help"
    elseif raw_skill:find("^set") then
        current_skill = "Setup"
    elseif raw_skill:find("^wed") then
        current_skill = "Wedge"
    elseif raw_skill:find("^part") then
        current_skill = "Help Partner"
    end
end

-- ============================================================================
-- Load settings from UserVars (persisted per-character)
-- ============================================================================
local function uv(key)
    local val = UserVars.rogues and UserVars.rogues[key] or nil
    if val == nil then return "" end
    return tostring(val)
end

-- Initialize UserVars.rogues if absent
if not UserVars.rogues then
    UserVars.rogues = {}
end

-- Partner setup
local partner_name = nil
local partner_room_number = nil
local only_work_with_partner = nil

if args[2] and #args[2] > 0 and current_skill ~= "Wedge" then
    partner_name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
    only_work_with_partner = partner_name
elseif #uv("partner_name") > 0 then
    local pn = uv("partner_name")
    partner_name = pn:sub(1,1):upper() .. pn:sub(2):lower()
end

if args[3] and args[3]:find("%d+") then
    partner_room_number = tonumber(args[3])
elseif uv("partner_room"):find("%d+") then
    partner_room_number = tonumber(uv("partner_room"))
else
    partner_room_number = GameState.room_id
end

local get_promotion_from_partner = uv("get_promotions_from_partner"):lower():find("yes") ~= nil

local automate_partner_reps = nil
do
    local val = uv("automate_partner_reps"):lower()
    if val:find("full") then automate_partner_reps = "full"
    elseif val:find("confirm") then automate_partner_reps = "confirm"
    elseif val:find("none") then automate_partner_reps = "none"
    end
end

-- Voucher limits
local limit_voucher_usage = 10
local voucher_limit_exit_or_continue = "Exit"
do
    local lv = uv("limit_vouchers")
    if #lv > 0 then
        local parts = split_csv(lv)
        if parts[1] then limit_voucher_usage = tonumber(parts[1]) or 10 end
        if parts[2] then
            if parts[2]:lower():find("continue") then
                voucher_limit_exit_or_continue = "Continue"
            else
                voucher_limit_exit_or_continue = "Exit"
            end
        end
    end
end

-- Task trade-in lists
local sweep_tasks_to_trade = split_csv(uv("sweep_tasks_to_trade"))
local subdue_tasks_to_trade = split_csv(uv("subdue_tasks_to_trade"))
local stun_maneuvers_tasks_to_trade = split_csv(uv("stun_maneuvers_tasks_to_trade"))
local lock_mastery_tasks_to_trade = split_csv(uv("lock_mastery_tasks_to_trade"))
local cheapshots_tasks_to_trade = split_csv(uv("cheapshots_tasks_to_trade"))
local gambits_tasks_to_trade = split_csv(uv("gambits_tasks_to_trade"))
local universal_tasks_to_trade = split_csv(uv("universal_tasks_to_trade"))
local tasks_to_use_tpick_for = split_csv(uv("tasks_to_use_tpick_for"))

-- Stun command setup
local stun_command = "Guildmaster's special"
if #uv("stun_command") > 0 then
    stun_command = uv("stun_command")
end

local needed_stun_item = nil
if #uv("stun_item") > 0 then
    needed_stun_item = uv("stun_item")
end

-- Hunting setup
local wait_before_moving = 1
if uv("hunting_wait_time"):find("%d+") then
    wait_before_moving = tonumber(uv("hunting_wait_time")) or 1
    if wait_before_moving < 1 then wait_before_moving = 1 end
end

local all_hunting_rooms = split_csv(uv("hunting_area_rooms"))
local all_critters_to_hunt = split_csv(uv("hunting_acceptable_critters"))

-- Wedge quality data
local wedge_quality_data = {
    "thin wooden wedge",
    "warped wooden wedge",
    "solid wooden wedge",
    "strong wooden wedge",
    "superior wooden wedge",
}

local function wedge_quality_index(name)
    for i, v in ipairs(wedge_quality_data) do
        if v == name then return i end
    end
    return nil
end

-- Flower names for watering task
local flower_names_pattern = "wildflower|iceflower|dandelion|begonia|iris|rose|wisteria|anemones|terracotta pot|terracotta planter"

-- ============================================================================
-- State variables
-- ============================================================================
local current_task = nil
local reps_remaining = 0
local number_of_vouchers_remaining = 0
local total_current_ranks = 0
local total_maximum_ranks = 0
local number_of_vouchers_used = 0
local do_not_skip_this_task = nil
local dark_corner_number = 0
local current_skill_rank = 0
local guild_night_active = nil
local current_cheapshot = nil
local stunman_current_command = nil
local trap_components_needed_list = nil
local trap_components_needed_names = nil
local trap_components_needed_nouns = nil
local trap_components_needed_array = {}
local trap_components_first_turnin = nil
local sense_task_5_current_task = nil
local task_for_footpad_or_administrator = nil
local required_wedge_quality = nil
local created_wedges = {}
local starting_room = nil
local need_to_stance_down = nil
local npc = nil  -- current NPC we're interacting with

-- ============================================================================
-- Navigation helpers
-- ============================================================================
local function go2_room(room_number)
    room_number = tonumber(room_number)
    while GameState.room_id ~= room_number do
        if Script.running("go2") then
            Script.kill("go2")
            wait_until(function() return not Script.running("go2") end)
        end
        Script.run("go2", tostring(room_number))
        wait_while(function() return Script.running("go2") end)
        pause(0.1)
        if GameState.dead then break end
    end
end

local function move_out_of_room()
    local exits = GameState.room_exits or {}
    for _, ex in ipairs(exits) do
        if ex == "out" then
            move("out")
            break
        end
    end
    if GameState.room_name and GameState.room_name:lower():find("dark corner") then
        local exits2 = GameState.room_exits or {}
        if #exits2 > 0 then
            move(exits2[1])
        end
    end
end

local function find_nearest_target_room(tag)
    if not GameState.room_id then
        while not GameState.room_id do
            table.insert(text_to_display, "This room has no room ID so go2 won't work.")
            table.insert(text_to_display, "Moving to a random room to see if the issue is fixed.")
            display_message()
            local exits = GameState.room_exits or {}
            if #exits > 0 then
                move(exits[math.random(#exits)])
            end
        end
    end
    dark_corner_number = dark_corner_number + 1
    move_out_of_room()

    -- Find rooms with the given tag (and alternate tags for special cases)
    local target_room = nil
    if tag == "rogue guild toolbenchs" then
        target_room = Room.find_nearest_by_tag("rogue guild toolbenchs")
        if not target_room then
            target_room = Room.find_nearest_by_tag("rogue guild workshop")
        end
    elseif tag == "rogue guild trainer" then
        target_room = Room.find_nearest_by_tag("rogue guild trainer")
        if not target_room then
            target_room = Room.find_nearest_by_tag("rogue guild footpads")
        end
    elseif tag == "rogue guild master" then
        target_room = Room.find_nearest_by_tag("rogue guild master")
        if not target_room then
            target_room = Room.find_nearest_by_tag("rogue guild masters")
        end
    else
        target_room = Room.find_nearest_by_tag(tag)
    end

    if target_room and target_room.id then
        go2_room(target_room.id)
    else
        table.insert(text_to_display, "The required room doesn't appear to be tagged properly.")
        table.insert(text_to_display, "Room tag needed: " .. tag)
        display_message()
        error("Required room tag not found: " .. tag)
    end
end

-- ============================================================================
-- Hand management
-- ============================================================================
local function check_hands()
    local rh = GameObj.right_hand()
    while rh do
        waitrt()
        fput("stow " .. rh.noun)
        pause(0.1)
        rh = GameObj.right_hand()
    end
    local lh = GameObj.left_hand()
    while lh do
        waitrt()
        fput("stow " .. lh.noun)
        pause(0.1)
        lh = GameObj.left_hand()
    end
end

local function stand_up()
    while not GameState.standing do
        waitrt()
        fput("stand")
        pause(0.2)
    end
end

local function unhide()
    while GameState.hidden do
        waitrt()
        fput("unhide")
        pause(0.1)
    end
end

-- ============================================================================
-- Tool management (guild tools: rag, broom, bag, watering can)
-- ============================================================================
local function put_tools_away()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local tool_names = { "soft rag", "wooden broom", "burlap bag", "watering can" }
    local has_tool = false
    for _, tool in ipairs(tool_names) do
        if (rh and rh.name == tool) or (lh and lh.name == tool) then
            has_tool = true
            break
        end
    end
    if has_tool then
        table.insert(text_to_display, "You have guild tools in your hands.")
        table.insert(text_to_display, "Putting the tools away in the guild tool rack before continuing on.")
        display_message()
        find_nearest_target_room("rogue guild tools")
        rh = GameObj.right_hand()
        lh = GameObj.left_hand()
        if (rh and rh.name == "soft rag") or (lh and lh.name == "soft rag") then fput("put rag on rack") end
        if (rh and rh.name == "wooden broom") or (lh and lh.name == "wooden broom") then fput("put broom on rack") end
        if (rh and rh.name == "burlap bag") or (lh and lh.name == "burlap bag") then fput("put bag on rack") end
        if (rh and rh.name == "watering can") or (lh and lh.name == "watering can") then fput("put can on rack") end
    end
end

-- Register cleanup on script exit
before_dying(function()
    put_tools_away()
end)

-- ============================================================================
-- Wait for stamina
-- ============================================================================
local function wait_for_stamina(amount)
    if GameState.stamina < amount then
        table.insert(text_to_display, "Waiting for stamina.")
        display_message()
        wait_until(function() return GameState.stamina >= amount end)
    end
end

-- ============================================================================
-- Wound check — head back to town if badly hurt
-- ============================================================================
local function wound_check()
    local dominated = false
    -- Check wounds > 1 on any body part
    local parts = {"head", "neck", "chest", "abdomen", "back", "leftArm", "rightArm",
                   "leftHand", "rightHand", "leftLeg", "rightLeg", "leftEye", "rightEye", "nsys"}
    for _, part in ipairs(parts) do
        if Wounds[part] and Wounds[part] > 1 then dominated = true; break end
        if Scars[part] and Scars[part] > 1 then dominated = true; break end
    end
    if Char.percent_health < 60 then dominated = true end
    if dominated then
        table.insert(text_to_display, "You are wounded. Heading back to town then exiting.")
        display_message()
        waitrt()
        unhide()
        fput("stance defensive")
        if starting_room then
            go2_room(starting_room)
        end
        Script.run("go2", "town")
        wait_while(function() return Script.running("go2") end)
        table.insert(text_to_display, "You are wounded. Once healed, run the script again.")
        display_message()
        error("Script exiting due to wounds")
    end
end

-- ============================================================================
-- Bank operations
-- ============================================================================
local function withdraw_silvers(amount)
    find_nearest_target_room("bank")
    fput("depo all")
    fput("withdraw " .. amount .. " silvers")
    local enough = false
    fput("wealth quiet")
    while true do
        local line = get()
        if line:find("You have no silver with you") or line:find("You have but one silver with you") then
            break
        end
        local silver_str = line:match("You have (.-) silver with you")
        if silver_str then
            local silver_num = tonumber(silver_str:gsub(",", "")) or 0
            if silver_num >= amount then enough = true end
            break
        end
    end
    if not enough then
        if current_task == "Join the guild" then
            table.insert(text_to_display, "It costs 15,000 silvers to join the Rogue Guild and you don't seem to have enough.")
        else
            table.insert(text_to_display, "You don't have enough silvers to finish this task.")
        end
        table.insert(text_to_display, "Deposit enough silvers in the local bank, then run the script again.")
        display_message()
        error("Not enough silvers")
    end
end

-- ============================================================================
-- Get a new task from the Training Administrator
-- ============================================================================
local function get_a_new_task()
    table.insert(text_to_display, "Heading to nearest Guild Administrator to get a task for " .. current_skill .. ".")
    display_message()
    find_nearest_target_room("rogue guild administrator")
    npc = wait_for_npc("Training Administrator")
    fput("ask #" .. npc.id .. " about training " .. current_skill)
    while true do
        local line = get()
        if line:find("Repeat this .* time") or line:find("You need to finish the task I gave you") then
            current_task = "Check next task"
            break
        elseif line:find("you need to go concentrate on your other studies") then
            table.insert(text_to_display, "You can't get a task because you can't earn anymore ranks right now.")
            table.insert(text_to_display, "Earn more experience to unlock more guild ranks then run ;rogues again.")
            display_message()
            error("No more ranks available")
        elseif line:find("Come back in about (.-) minute") then
            local mins = line:match("Come back in about (.-) minute")
            local time_to_wait = 1
            if mins ~= "a" then time_to_wait = tonumber(mins) or 1 end
            table.insert(text_to_display, "Must wait " .. time_to_wait .. " minutes before getting a new task.")
            table.insert(text_to_display, "Waiting " .. time_to_wait .. " minutes then asking again.")
            display_message()
            pause(time_to_wait * 60)
            current_task = "Get a new task"
            break
        end
    end
end

-- ============================================================================
-- Check current task status via GLD command
-- ============================================================================
local function check_next_task()
    dark_corner_number = dark_corner_number + 1
    current_task = nil
    guild_night_active = nil
    fput("gld")
    while true do
        local line = get()
        if line:find("You have no guild affiliation") then
            current_task = "Join the guild"
            break
        end
        local voucher_count = line:match("You currently have (%d+) task trading vouchers?%.")
        if voucher_count then
            number_of_vouchers_remaining = tonumber(voucher_count) or 0
        end
        if line:find("You currently have one rank out of a possible (%d+)") then
            total_current_ranks = 1
            total_maximum_ranks = tonumber(line:match("possible (%d+)")) or 0
        end
        local cur_ranks, max_ranks = line:match("You currently have (%d+) ranks? out of a possible (%d+)")
        if cur_ranks then
            total_current_ranks = tonumber(cur_ranks) or 0
            total_maximum_ranks = tonumber(max_ranks) or 0
        end
        if line:find("You are a Master of " .. current_skill) or
           (current_skill == "Cheapshots" and line:find("You are a Master of Cheap Shot")) then
            table.insert(text_to_display, "You have already mastered " .. current_skill .. "! Time to work on something else!")
            display_message()
            error("Already mastered " .. current_skill)
        end

        -- Check skill rank
        local rank_str = line:match("You have (.-) ranks? in the " .. current_skill .. " skill%.")
        if not rank_str and current_skill == "Cheapshots" then
            rank_str = line:match("You have (.-) ranks? in the Cheap Shot skill%.")
        end
        if rank_str then
            if rank_str == "no" then
                current_skill_rank = 0
            else
                current_skill_rank = tonumber(rank_str) or 0
            end
            current_task = "This task isn't yet coded."
            -- Now parse the actual task description
            while true do
                line = get()
                -- Footpad lessons
                if line:find("told you to visit a master footpad") or
                   line:find("told you to visit the footpads for some lessons") or
                   line:find("told you to get some lessons from the footpads") or
                   line:find("told you to get lessons in .* from a master footpad") then
                    current_task = "Talk to master footpad"
                -- Lock Mastery tasks
                elseif line:find("told you to pick some .* boxes under a variety of conditions") then
                    current_task = "Pick boxes under a variety of conditions"
                elseif line:find("told you to use some .* boxes to practice your latest trick") then
                    current_task = "Pick boxes using your latest trick in front of an audience"
                elseif line:find("told you to pick some tough boxes from creatures") then
                    current_task = "Pick some tough boxes from creatures"
                elseif line:find("told you to measure some tough boxes") then
                    current_task = "Measure then pick tough boxes"
                elseif line:find("told you to calibrate your calipers out in the field") then
                    current_task = "Calibrate calipers in the field"
                elseif line:find("told you to pit your skills against a footpad") then
                    current_task = "Pit your skills against a footpad"
                elseif line:find("told you to wedge open some boxes") then
                    current_task = "Wedge open boxes"
                elseif line:find("told you to relock some tough boxes") then
                    current_task = "Relock tough boxes"
                elseif line:find("told you to put clasps on some containers") then
                    current_task = "Clasp some containers"
                elseif line:find("told you to make some good locks") then
                    current_task = "Create lock assemblies"
                elseif line:find("told you to cut keys for some locks") then
                    current_task = "Cut keys"
                elseif line:find("told you to melt open some plated boxes") then
                    current_task = "Melt open plated boxes"
                elseif line:find("told you to extract some poison needles or jaw traps") then
                    trap_components_needed_list = "pair of small steel jaws, slender steel needle"
                    task_for_footpad_or_administrator = "Administrator"
                    current_task = "Gather trap components"
                elseif line:find("told you to extract some acid vials") then
                    trap_components_needed_list = "clear glass vial of light yellow acid"
                    task_for_footpad_or_administrator = "Administrator"
                    current_task = "Gather trap components"
                elseif line:find("told you to extract some magic crystal trap components") then
                    trap_components_needed_list = "(small) dark crystal, (various colors of) sphere"
                    task_for_footpad_or_administrator = "Administrator"
                    current_task = "Gather trap components"
                elseif line:find("told you to extract some vials from stun clouds or fire traps") then
                    trap_components_needed_list = "thick glass vial filled with murky red liquid, green-tinted vial filled with thick acrid smoke"
                    task_for_footpad_or_administrator = "Administrator"
                    current_task = "Gather trap components"
                elseif line:find("told you to customize some lockpicks and keys") then
                    task_for_footpad_or_administrator = "Administrator"
                    current_task = "Customize lockpicks"
                -- Universal tasks
                elseif line:find("told you to clean the windows") or line:find("told you to clean the guild windows") then
                    current_task = "Clean windows"
                elseif line:find("told you to sweep the guild courtyard") then
                    current_task = "Sweep floors"
                elseif line:find("told you to water the guild plants") then
                    current_task = "Water plants"
                -- Stun Maneuvers
                elseif line:find("told you to let a footpad shoot arrows at you") then
                    current_task = "Let a footpad shoot arrows at you"
                elseif line:find("told you to practice readying your shield while stunned") then
                    current_task = "Readying your shield while stunned"
                elseif line:find("told you to practice getting your weapon while stunned") then
                    current_task = "Getting your weapon while stunned"
                elseif line:find("told you to practice picking stuff up while stunned") then
                    current_task = "Picking stuff up while stunned"
                elseif line:find("told you to practice standing up while stunned") then
                    current_task = "Standing up while stunned"
                elseif line:find("told you to practice defending yourself a little more while stunned") then
                    current_task = "Defending yourself a little more while stunned"
                elseif line:find("told you to practice defending yourself a lot more while stunned") then
                    current_task = "Defending yourself a lot more while stunned"
                elseif line:find("told you to practice attacking while stunned") then
                    current_task = "Attacking while stunned"
                elseif line:find("told you to play a few rounds of slap hands with a footpad") then
                    current_task = "Play slap hands with a footpad"
                -- Subdue
                elseif line:find("told you to crush up some garlic") then
                    current_task = "Crush up some garlic"
                elseif line:find("told you to try and subdue some creatures") then
                    current_task = "Subdue some creatures"
                elseif line:find("told you to ding up a few melons") then
                    current_task = "Ding up a few melons"
                elseif line:find("told you to see one of the footpads to learn a secret") then
                    current_task = "Talk to master footpad"
                -- Sweep
                elseif line:find("told you to practice sweeping a partner") then
                    current_task = "Practice sweeping a partner"
                elseif line:find("told you to defend against a partner") then
                    current_task = "Defend against sweep from a partner"
                elseif line:find("told you to practice sweeping creatures") then
                    current_task = "Practice sweeping creatures"
                elseif line:find("told you to work out on the sweep dummies") then
                    current_task = "Sweep dummies"
                -- Cheapshots
                elseif line:find("told you to stomp some creatures' feet") then
                    current_cheapshot = "footstomp"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to tweak some creatures' noses") then
                    current_cheapshot = "nosetweak"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to practice templeshot on some creatures") then
                    current_cheapshot = "templeshot"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to kneecap some creatures") then
                    current_cheapshot = "kneebash"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to poke some creatures in the eyes") then
                    current_cheapshot = "eyepoke"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to practice throatchop on creatures") then
                    current_cheapshot = "throatchop"
                    current_task = "Practice cheapshots on creatures"
                elseif line:find("told you to practice defending against footstomps") then
                    current_task = "Defend against cheapshots from a partner"
                    current_cheapshot = "footstomp"
                elseif line:find("told you to practice footstomping a partner") then
                    current_task = "Practice cheapshots on partner"
                    current_cheapshot = "footstomp"
                -- Promotion / no task
                elseif line:find("You have earned enough training points for your next rank") then
                    current_task = "Get promotion"
                    break
                elseif line:find("You are not currently training in this skill") or
                       line:find("You have not been assigned a current task") or
                       line:find("You have not yet been assigned a task") then
                    current_task = "Get a new task"
                    break
                elseif line:find("You have (.-) repetitions? remaining") then
                    local rep_str = line:match("You have (.-) repetitions? remaining")
                    if rep_str == "no" then
                        reps_remaining = 0
                    else
                        reps_remaining = tonumber(rep_str) or 0
                    end
                    if reps_remaining == 0 then
                        current_task = "Current task finished"
                    end
                    break
                end
            end
        end
        if line:find("It is currently a Guild Night") or line:find("Most guild training points awards will be doubled") then
            guild_night_active = true
        end
        if line:find("Click GLD MENU for additional commands") then
            if not current_task then
                current_task = "Get a new task"
            end
            break
        end
    end
end

-- ============================================================================
-- Turn in a completed task
-- ============================================================================
local function turnin_current_task()
    number_of_vouchers_used = 0
    do_not_skip_this_task = nil
    table.insert(text_to_display, "Your current task for " .. current_skill .. " is finished.")
    table.insert(text_to_display, "Let's turn it in and get a new one.")
    display_message()
    find_nearest_target_room("rogue guild administrator")
    npc = wait_for_npc("Training Administrator")
    if uv("use_guild_profession_boost"):lower():find("yes") and not guild_night_active then
        fput("boost guild profession")
    end
    fput("ask #" .. npc.id .. " about training " .. current_skill)
    fput("ask #" .. npc.id .. " about training " .. current_skill)
    current_task = "Check next task"
end

-- ============================================================================
-- Get a promotion
-- ============================================================================
local function get_promotion()
    local need_npc_master = true
    if get_promotion_from_partner and partner_name then
        need_npc_master = false
        table.insert(text_to_display, "Getting a promotion in " .. current_skill .. " from your partner.")
        display_message()
        go2_room(partner_room_number)
        pause(1)
        -- Check if partner is here (simplified check via game output)
        fput("look")
        pause(1)
        -- Try to get promotion from partner
        local got_promoted = false
        for i = 1, 3 do
            local result = matchtimeout(10,
                "whisper ooc " .. partner_name .. " Can you please promote me in " .. current_skill .. "?",
                "offers to promote you to your next rank")
            if result and result:find("offers to promote you") then
                fput("gld accept")
                got_promoted = true
                break
            end
        end
        if not got_promoted then
            need_npc_master = true
        end
    end

    if need_npc_master then
        table.insert(text_to_display, "Getting a promotion in " .. current_skill .. " from a Guild Master.")
        display_message()
        find_nearest_target_room("rogue guild master")
        npc = wait_for_npc("Guild Master")
        fput("ask #" .. npc.id .. " about next in " .. current_skill)
        while true do
            local line = get()
            if line:find("You need to learn .* rank%(s%) of other skills") then
                local needed = line:match("learn (.-) rank")
                table.insert(text_to_display, "You need more ranks in other skills before ranking up in " .. current_skill .. ".")
                display_message()
                error("Need more ranks in other skills")
            elseif line:find("Congratulations.*for achieving") then
                break
            elseif line:find("Congratulations.*for mastering this skill") then
                table.insert(text_to_display, "Congratulations! You have mastered " .. current_skill .. "!")
                display_message()
                error("Mastered " .. current_skill)
            elseif line:find("You need to be checked in, first") then
                -- Pay guild dues then retry
                checkin_for_guild_dues()
                break
            end
        end
    end
    current_task = "Check next task"
end

-- ============================================================================
-- Checkin for guild dues
-- ============================================================================
function checkin_for_guild_dues()
    table.insert(text_to_display, "Finding nearest Rogue Guild Master to checkin for 3 months.")
    display_message()
    withdraw_silvers(15000)
    find_nearest_target_room("rogue guild master")
    npc = wait_for_npc("Guild Master")
    for i = 1, 3 do
        fput("ask #" .. npc.id .. " about checkin")
    end
    find_nearest_target_room("bank")
    fput("depo all")
end

-- ============================================================================
-- Join the guild
-- ============================================================================
local function join_the_guild()
    table.insert(text_to_display, "You haven't yet joined the Rogue Guild! Let's fix that.")
    display_message()
    withdraw_silvers(15000)
    table.insert(text_to_display, "Got the silvers needed to join the Rogue Guild!")
    display_message()
    find_nearest_target_room("rogue guild master")
    npc = wait_for_npc("Guild Master")
    fput("ask #" .. npc.id .. " about membership")
    waitfor("Enter GLD ACCEPT to join this guild.")
    fput("gld accept")
    table.insert(text_to_display, "Excellent! You are now a member of the Rogue Guild!")
    table.insert(text_to_display, "Now let's get to training!")
    display_message()
    current_task = "Get a new task"
end

-- ============================================================================
-- Trade in current task for a new one (uses a voucher)
-- ============================================================================
local function trade_in_current_task()
    find_nearest_target_room("rogue guild administrator")
    npc = wait_for_npc("Training Administrator")
    fput("ask #" .. npc.id .. " about trade in " .. current_skill)
    current_task = "Get a new task"
end

-- ============================================================================
-- Check if we should trade in the current task
-- ============================================================================
local function check_to_trade_in_task()
    move_out_of_room()
    if number_of_vouchers_used >= limit_voucher_usage then
        if voucher_limit_exit_or_continue == "Continue" then
            table.insert(text_to_display, "Voucher limit reached. Continuing with current task per your settings.")
            display_message()
            do_not_skip_this_task = true
            current_task = "Check next task"
        else
            table.insert(text_to_display, "Voucher limit reached. Exiting per your settings.")
            display_message()
            error("Voucher limit reached")
        end
    else
        table.insert(text_to_display, "You have opted to trade in these tasks.")
        table.insert(text_to_display, "Trading in this task and getting a new one.")
        display_message()
        number_of_vouchers_used = number_of_vouchers_used + 1
        current_task = "Trade in current task"
    end
end

-- ============================================================================
-- Ask a footpad to train
-- ============================================================================
local function ask_footpad_to_train()
    npc = find_npc("Master Footpad")
    if not npc then
        table.insert(text_to_display, "Waiting for a master footpad to show up.")
        display_message()
        npc = wait_for_npc("Master Footpad")
    end
    fput("ask #" .. npc.id .. " about train " .. current_skill)
end

-- ============================================================================
-- Check for a needed item (weapon, shield, etc.)
-- ============================================================================
local function check_for_needed_item(item_name, item_type)
    if not item_name or item_name == "" then
        table.insert(text_to_display, "You must set a " .. item_type .. " in the setup menu (;rogues setup).")
        table.insert(text_to_display, "Go to the " .. current_skill .. " tab and fill out the " .. item_type .. " setting.")
        display_message()
        move_out_of_room()
        error("Missing " .. item_type .. " setting")
    end
    check_hands()
    fput("get my " .. item_name)
    fput("remove my " .. item_name)
    pause(1)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_noun = rh and rh.noun or ""
    local lh_noun = lh and lh.noun or ""
    if rh_noun ~= item_name and lh_noun ~= item_name then
        table.insert(text_to_display, "Could not find your " .. item_type .. " for " .. current_skill .. ".")
        table.insert(text_to_display, "Be sure it is in an open container.")
        display_message()
        move_out_of_room()
        error("Missing " .. item_type)
    end
    if current_skill ~= "Subdue" and current_skill ~= "Cheapshots" then
        check_hands()
    end
end

-- ============================================================================
-- Ready hands for critter reps (weapons)
-- ============================================================================
local function ready_hands_for_critter_reps()
    local weapon = uv("weapon_for_subdue_and_cheapshots")
    local main_hand = uv("hunting_main_hand")
    local off_hand = uv("hunting_off_hand")

    if current_skill == "Subdue" or current_skill == "Cheapshots" then
        local rh = GameObj.right_hand()
        if not rh or rh.noun ~= weapon then
            waitrt()
            fput("get my " .. weapon)
        end
        if #off_hand > 0 then
            local lh = GameObj.left_hand()
            if not lh or lh.noun ~= off_hand then
                while GameObj.left_hand() do
                    waitrt()
                    fput("stow left")
                    pause(0.2)
                end
                fput("get my " .. off_hand)
                fput("remove my " .. off_hand)
            end
        end
    else
        if main_hand:lower() == "gird" then
            while GameObj.right_hand() do waitrt(); fput("stow right"); pause(0.2) end
            while GameObj.left_hand() do waitrt(); fput("stow left"); pause(0.2) end
            fput("gird")
        else
            if #main_hand > 0 then
                local rh = GameObj.right_hand()
                if not rh or rh.noun ~= main_hand then
                    while GameObj.right_hand() do waitrt(); fput("stow right"); pause(0.2) end
                    fput("get my " .. main_hand)
                    fput("remove my " .. main_hand)
                end
            end
            if #off_hand > 0 then
                local lh = GameObj.left_hand()
                if not lh or lh.noun ~= off_hand then
                    while GameObj.left_hand() do waitrt(); fput("stow left"); pause(0.2) end
                    fput("get my " .. off_hand)
                    fput("remove my " .. off_hand)
                end
            end
        end
    end
end

-- ============================================================================
-- Stance management
-- ============================================================================
local function stance_down()
    local s = GameState.stance or ""
    if s == "offensive" then fput("stance advance")
    elseif s == "advance" then fput("stance forward")
    elseif s == "forward" then fput("stance neutral")
    elseif s == "neutral" then fput("stance guarded")
    elseif s == "guarded" then fput("stance defensive")
    end
    need_to_stance_down = nil
end

-- ============================================================================
-- UNIVERSAL TASKS
-- ============================================================================

--- Clean windows
local function clean_windows()
    find_nearest_target_room("rogue guild tools")
    check_hands()
    fput("get rag from rack")
    local target_rooms = Map.tags("rogue guild window") or {}
    while true do
        for _, room_id in ipairs(target_rooms) do
            go2_room(room_id)
            waitrt()
            fput("rub window")
            while true do
                local line = get()
                if line:find("repetition") then
                    local r = line:match("(%d+) repetition")
                    if r then reps_remaining = tonumber(r) or 0 end
                    break
                elseif line:find("You have completed") then
                    reps_remaining = 0
                    break
                elseif line:find("let someone else") or line:find("What were you referring to") then
                    break
                end
            end
            if reps_remaining == 0 then break end
        end
        if reps_remaining == 0 then break end
        find_nearest_target_room("rogue guild tools")
        fput("put rag on rack")
        fput("get rag from rack")
        table.insert(text_to_display, "No more dirty windows. Retrying in 60 seconds.")
        display_message()
        pause(60)
    end
    find_nearest_target_room("rogue guild tools")
    fput("put rag on rack")
end

--- Sweep floors
local function sweep_floors()
    find_nearest_target_room("rogue guild tools")
    check_hands()
    fput("get broom from rack")
    fput("get bag from rack")
    local target_rooms = Map.tags("rogue guild dirt") or {}
    while true do
        for _, room_id in ipairs(target_rooms) do
            go2_room(room_id)
            while true do
                waitrt()
                fput("push broom")
                local line = get()
                if line:find("There is no dirt here") then break end
            end
            fput("get pile")
            fput("look in my bag")
            while true do
                local line = get()
                if line:find("It has room for more") or line:find("bag is empty") then
                    break
                elseif line:find("bag is full of dirt") then
                    find_nearest_target_room("rogue guild tools")
                    fput("put bag in bin")
                    while true do
                        local line2 = get()
                        if line2:find("repetition") then
                            local r = line2:match("(%d+) repetition")
                            if r then reps_remaining = tonumber(r) or 0 end
                            break
                        elseif line2:find("You have completed") then
                            reps_remaining = 0
                            break
                        end
                    end
                    break
                end
            end
            if reps_remaining == 0 then break end
        end
        if reps_remaining == 0 then break end
        find_nearest_target_room("rogue guild tools")
        fput("put bag in bin")
    end
    find_nearest_target_room("rogue guild tools")
    fput("put broom on rack")
    fput("put bag on rack")
end

--- Water plants
local function water_plants()
    find_nearest_target_room("rogue guild tools")
    check_hands()
    fput("get can from rack")
    local target_rooms = Map.tags("rogue guild plant") or {}
    while true do
        for _, room_id in ipairs(target_rooms) do
            go2_room(room_id)
            waitrt()
            -- Look for a plant in the room
            local loot = GameObj.loot()
            local target_plant = nil
            for _, obj in ipairs(loot) do
                for piece in flower_names_pattern:gmatch("[^|]+") do
                    if obj.name:lower():find(piece:lower()) then
                        target_plant = obj
                        break
                    end
                end
                if target_plant then break end
            end
            if not target_plant then
                local room_desc = GameObj.room_desc()
                for _, obj in ipairs(room_desc) do
                    for piece in flower_names_pattern:gmatch("[^|]+") do
                        if obj.name:lower():find(piece:lower()) then
                            target_plant = obj
                            break
                        end
                    end
                    if target_plant then break end
                end
            end
            if target_plant then
                while not GameState.kneeling do
                    waitrt()
                    fput("kneel")
                    pause(0.2)
                end
                local plant_name = nil
                if target_plant.name:lower():find("terracotta pot") then
                    plant_name = "anemones"
                elseif target_plant.name:lower():find("terracotta planter") then
                    plant_name = "flowers"
                end
                if plant_name then
                    fput("water " .. plant_name)
                else
                    fput("water #" .. target_plant.id)
                end
                while true do
                    local line = get()
                    if line:find("repetition") then
                        local r = line:match("(%d+) repetition")
                        if r then reps_remaining = tonumber(r) or 0 end
                        break
                    elseif line:find("You have completed") then
                        reps_remaining = 0
                        break
                    elseif line:find("let someone else") or line:find("What were you referring to") then
                        break
                    end
                end
                stand_up()
            end
            if reps_remaining == 0 then break end
        end
        if reps_remaining == 0 then break end
        find_nearest_target_room("rogue guild tools")
        fput("put can on rack")
        fput("get can from rack")
        table.insert(text_to_display, "No more plants to water. Retrying in 60 seconds.")
        display_message()
        pause(60)
    end
    find_nearest_target_room("rogue guild tools")
    fput("put can on rack")
end

-- ============================================================================
-- STUN MANEUVER TASKS
-- ============================================================================

--- Footpad shoots arrows at you
local function footpad_shoot_arrows()
    local actions = {"lean left", "lean right", "duck", "jump"}
    find_nearest_target_room("rogue guild trainer")
    ask_footpad_to_train()
    waitfor("Ya ready")
    while true do
        stand_up()
        waitrt()
        local action = actions[math.random(#actions)]
        fput(action)
        local line = matchtimeout(15, "You have to dodge", "repetition", "You have completed")
        if line then
            if line:find("repetition") or line:find("You have completed") then
                move_out_of_room()
                break
            end
        end
    end
    current_task = "Check next task"
end

--- Self-stun tasks (done alone at the bar)
local function practice_stun_tasks_alone()
    if stun_command == "Guildmaster's special" then
        table.insert(text_to_display, "Using Guildmaster's specials to stun yourself.")
        display_message()
    end
    if stunman_current_command == "stunman shield" then
        check_for_needed_item(uv("shield_for_stunman_shield"), "shield")
    elseif stunman_current_command == "stunman weapon" then
        check_for_needed_item(uv("weapon_for_stunman_weapon"), "weapon")
    end
    local order_number = nil
    local successful = false
    while not successful do
        -- Stow stuff if needed
        wait_until(function() return not GameState.stunned end)
        check_hands()
        wait_for_stamina(15)

        if not GameState.stunned then
            if stun_command == "Guildmaster's special" then
                withdraw_silvers(2000)
            elseif needed_stun_item then
                fput("get my " .. needed_stun_item)
            end
            find_nearest_target_room("rogue guild bar")
            waitrt()

            -- Pre-position for specific tasks
            if stunman_current_command == "stunman stand" then
                while GameState.standing do
                    waitrt()
                    wait_until(function() return not GameState.stunned end)
                    fput("lay")
                    pause(0.3)
                end
            elseif stunman_current_command == "stunman stance1" or stunman_current_command == "stunman stance2" then
                while (GameState.stance or "") ~= "offensive" do
                    waitrt()
                    fput("stance offensive")
                    pause(0.3)
                end
            end

            if stun_command == "Guildmaster's special" then
                if not order_number then
                    fput("order")
                    while true do
                        local line = get()
                        local num = line:match("(%d+)%. Guildmaster's Special")
                        if num then
                            order_number = tonumber(num)
                            break
                        end
                    end
                end
                fput("order " .. order_number)
                fput("drink my special")
            else
                fput(stun_command)
            end
        end
        waitrt()
        fput(stunman_current_command)
        local line = matchtimeout(5, "repetition", "Roundtime", "You have completed")
        if line and line:find("You have completed") then
            successful = true
        end
        pause(0.1)
    end
    wait_until(function() return not GameState.stunned end)
    waitrt()
    if stun_command == "Guildmaster's special" then
        fput("drop my special")
    else
        check_hands()
    end
end

--- Stun maneuver footpad tasks (with a footpad stunning you)
local function stun_man_footpad_tasks()
    waitfor("Enter NOD to begin")
    if stunman_current_command == "stunman shield" then
        check_for_needed_item(uv("shield_for_stunman_shield"), "shield")
    elseif stunman_current_command == "stunman weapon" then
        check_for_needed_item(uv("weapon_for_stunman_weapon"), "weapon")
    elseif stunman_current_command == "stunman get" then
        stunman_current_command = "stunman get my " .. uv("weapon_for_stunman_weapon")
        check_for_needed_item(uv("weapon_for_stunman_weapon"), "weapon")
    end
    fput("nod")
    while true do
        waitrt()
        wait_for_stamina(15)
        check_hands()
        if stunman_current_command == "stunman stand" then
            while GameState.standing do
                waitrt()
                wait_until(function() return not GameState.stunned end)
                fput("lay")
                pause(0.3)
            end
        elseif stunman_current_command == "stunman stance1" or stunman_current_command == "stunman stance2" then
            if (GameState.stance or "") == "defensive" then
                wait_until(function() return not GameState.stunned end)
            end
            if not GameState.stunned then
                while (GameState.stance or "") ~= "offensive" do
                    waitrt()
                    fput("stance offensive")
                    pause(0.3)
                end
            end
        end
        if GameState.stunned then
            fput(stunman_current_command)
            local line = matchtimeout(5, "You're not stunned", "Roundtime", "You have completed")
            if line then
                if line:find("You're not stunned") then
                    pause(2)
                elseif line:find("Roundtime") then
                    waitrt()
                elseif line:find("You have completed") then
                    break
                end
            end
        end
        pause(0.2)
    end
    wait_until(function() return not GameState.stunned end)
    waitrt()
end

--- Play slap hands with a footpad
local function play_slap_hands()
    local actions = {"slap", "duck", "stop"}
    find_nearest_target_room("rogue guild trainer")
    ask_footpad_to_train()
    waitfor("just put your hands on mine")
    while true do
        stand_up()
        waitrt()
        local action = actions[math.random(#actions)]
        fput(action)
        local line = matchtimeout(15, "Current score", "repetition", "Roundtime", "What were you referring to", "You duck your head", "Usage:")
        if line then
            if line:find("What were you referring to") or line:find("You duck your head") or line:find("Usage:") then
                move_out_of_room()
                break
            end
        end
    end
end

-- ============================================================================
-- SUBDUE TASKS
-- ============================================================================

--- Crush garlic in the kitchen
local function crush_garlic()
    find_nearest_target_room("rogue guild kitchen")
    fput("go kitchen")
    local weapon = uv("weapon_for_subdue_and_cheapshots")
    while true do
        waitrt()
        wait_for_stamina(15)
        local rh = GameObj.right_hand()
        if not rh or rh.noun ~= weapon then
            check_for_needed_item(weapon, "weapon")
        end
        fput("subdue block")
        local line = matchtimeout(5, "You need to have a weapon", "Roundtime", "wait",
            "CLEAN the block", "clove of garlic on the block", "Put it in the pot", "You have completed", "done with this task")
        if line then
            if line:find("Roundtime") or line:find("wait") or line:find("You need to have a weapon") then
                waitrt()
            elseif line:find("CLEAN the block") then
                fput("clean block")
            elseif line:find("clove of garlic") then
                fput("clean block")
                fput("put clove on block")
            elseif line:find("Put it in the pot") then
                fput("put block in pot")
            elseif line:find("You have completed") or line:find("done with this task") then
                break
            end
        end
    end
end

--- Ding up melons on mannequin
local function ding_up_melons()
    find_nearest_target_room("rogue guild mannequin")
    fput("go mannequin")
    local weapon = uv("weapon_for_subdue_and_cheapshots")
    while true do
        waitrt()
        wait_for_stamina(15)
        local rh = GameObj.right_hand()
        if not rh or rh.noun ~= weapon then
            check_for_needed_item(weapon, "weapon")
        end
        stand_up()
        fput("subdue mannequin")
        local line = matchtimeout(5, "mannequin needs a head", "CLEAN the battered melon",
            "Roundtime", "wait", "You have completed", "done with this task")
        if line then
            if line:find("Roundtime") or line:find("wait") then
                waitrt()
            elseif line:find("mannequin needs a head") then
                fput("clean mannequin")
                fput("put melon on mannequin")
            elseif line:find("CLEAN the battered melon") then
                fput("clean mannequin")
            elseif line:find("You have completed") or line:find("done with this task") then
                break
            end
        end
    end
end

--- Subdue footpad mannequin tasks
local function subdue_footpad_tasks()
    local weapon = uv("weapon_for_subdue_and_cheapshots")
    check_hands()
    while true do
        fput("stance offensive")
        local rh = GameObj.right_hand()
        if not rh or rh.noun ~= weapon then
            check_for_needed_item(weapon, "weapon")
        end
        while not GameState.hidden do
            waitrt()
            pause(0.2)
            fput("hide")
        end
        waitrt()
        fput("subdue mannequin")
        local line = matchtimeout(5, "Try hiding first", "haven't learned how to subdue", "Roundtime", "wait", "You have completed")
        if line then
            if line:find("Try hiding") or line:find("haven't learned") or line:find("Roundtime") or line:find("wait") then
                waitrt()
            elseif line:find("You have completed") then
                break
            end
        end
    end
end

-- ============================================================================
-- SWEEP TASKS
-- ============================================================================

--- Sweep dummies
local function sweep_the_dummies()
    find_nearest_target_room("rogue guild dummies")
    fput("go dummies")
    while true do
        waitrt()
        stand_up()
        wait_for_stamina(15)
        fput("sweep dummy")
        local line = matchtimeout(5, "Roundtime", "need to FIX it", "beneficial to your training",
            "done with this task", "You have completed")
        if line then
            if line:find("Roundtime") then
                -- continue
            elseif line:find("need to FIX it") then
                fput("fix dummy")
            elseif line:find("beneficial to your training") then
                fput("touch dummy")
            elseif line:find("done with this task") or line:find("You have completed") then
                break
            end
        end
    end
end

--- Sweep footpads
local function sweep_footpads()
    fput("stance defensive")
    fput("gld stance offensive")
    local attacking_or_defending = nil
    while true do
        stand_up()
        if attacking_or_defending == "defending" then
            waitrt()
            fput("stance defensive")
            waitfor("SMR result")
            attacking_or_defending = nil
        end
        waitrt()
        stand_up()
        wait_for_stamina(15)
        fput("stance offensive")
        fput("sweep #" .. npc.id)
        local line = matchtimeout(5, "hasn't instructed you", "is lying down", "Roundtime", "wait", "You have completed")
        if line then
            if line:find("Roundtime") or line:find("wait") then
                waitrt()
            elseif line:find("hasn't instructed") then
                attacking_or_defending = "defending"
            elseif line:find("is lying down") then
                waitfor("stands back up")
            elseif line:find("You have completed") then
                break
            end
        end
    end
end

--- Cheapshot footpads
local function cheapshot_footpads()
    fput("stance offensive")
    fput("gld stance offensive")
    local weapon = uv("weapon_for_subdue_and_cheapshots")
    while true do
        stand_up()
        wait_for_stamina(15)
        fput("cheapshot " .. current_cheapshot .. " #" .. npc.id)
        local line = matchtimeout(5, "do not know how to .* barehanded",
            "Roundtime", "wait", "You have completed")
        if line then
            if line:find("barehanded") then
                local rh = GameObj.right_hand()
                if not rh or rh.noun ~= weapon then
                    check_for_needed_item(weapon, "weapon")
                end
            elseif line:find("Roundtime") or line:find("wait") then
                waitrt()
            elseif line:find("You have completed") then
                break
            end
        end
    end
end

-- ============================================================================
-- CRITTER TASKS (for Sweep/Subdue/Cheapshots on creatures)
-- ============================================================================
local function practice_on_critters()
    if uv("rogues_exit_critter_reps"):lower():find("yes") then
        table.insert(text_to_display, "You have opted to exit for critter tasks.")
        table.insert(text_to_display, "Start the script again once finished.")
        display_message()
        error("Exiting for manual critter task")
    end
    if #all_hunting_rooms == 0 then
        table.insert(text_to_display, "You must set hunting rooms in setup (;rogues setup, Critter Info tab).")
        display_message()
        error("No hunting rooms configured")
    end
    if #all_critters_to_hunt == 0 then
        table.insert(text_to_display, "You must set critters in setup (;rogues setup, Critter Info tab).")
        display_message()
        error("No critters configured")
    end

    table.insert(text_to_display, "BE SURE TO CHECK IF YOU CAN GET A REP FROM YOUR TARGET CRITTERS.")
    display_message()
    pause(2)

    if current_skill == "Subdue" or current_skill == "Cheapshots" then
        local weapon = uv("weapon_for_subdue_and_cheapshots")
        local rh = GameObj.right_hand()
        if not rh or rh.noun ~= weapon then
            check_for_needed_item(weapon, "weapon")
        end
    end
    ready_hands_for_critter_reps()

    local all_finished = false
    while not all_finished do
        fput("stance defensive")

        -- Navigate to a hunting room if not in one
        if not tbl_contains(all_hunting_rooms, tostring(GameState.room_id)) then
            go2_room(all_hunting_rooms[1])
        else
            -- Move to a random adjacent hunting room
            local room = Room.current()
            if room and room.wayto then
                local adjacent = {}
                for dest_id, cmd in pairs(room.wayto) do
                    if tbl_contains(all_hunting_rooms, tostring(dest_id)) then
                        table.insert(adjacent, {id = dest_id, cmd = cmd})
                    end
                end
                if #adjacent > 0 then
                    local choice = adjacent[math.random(#adjacent)]
                    move(choice.cmd)
                else
                    go2_room(all_hunting_rooms[math.random(#all_hunting_rooms)])
                end
            end
        end

        pause(1)

        -- Skip rooms with other players
        local pcs = GameObj.pcs()
        if #pcs > 0 then
            table.insert(text_to_display, "Moving to a new room because someone is here.")
            display_message()
        else
            -- Attack critters in this room
            while true do
                wound_check()

                local targets = GameObj.npcs()
                local critter = nil
                for _, t in ipairs(targets) do
                    if tbl_contains(all_critters_to_hunt, t.noun) then
                        if current_skill == "Sweep" or (current_cheapshot and current_cheapshot:lower() == "kneebash") then
                            if not (t.status and t.status:find("prone")) and not (t.status and t.status:find("lying")) then
                                critter = t
                                break
                            end
                        else
                            critter = t
                            break
                        end
                    end
                end

                if critter then
                    if GameState.stamina < 15 then
                        table.insert(text_to_display, "Low on stamina. Heading to town.")
                        display_message()
                        unhide()
                        fput("stance defensive")
                        if starting_room then go2_room(starting_room) end
                        Script.run("go2", "town")
                        wait_while(function() return Script.running("go2") end)
                        table.insert(text_to_display, "Waiting for stamina.")
                        display_message()
                        wait_until(function() return GameState.stamina > (GameState.max_stamina * 0.9) end)
                    else
                        waitrt()
                        fput("stance offensive")
                        ready_hands_for_critter_reps()
                        if current_skill == "Subdue" then
                            while not GameState.hidden do
                                waitrt()
                                fput("hide")
                                pause(0.1)
                            end
                        end

                        local action
                        if current_skill == "Subdue" then
                            action = "subdue"
                        elseif current_skill == "Sweep" then
                            action = "sweep"
                        elseif current_skill == "Cheapshots" then
                            action = "cheapshot " .. current_cheapshot
                        end

                        fput(action .. " #" .. critter.id)
                        local line = matchtimeout(5, "Roundtime", "You have completed", "is out of reach")
                        if line then
                            if line:find("You have completed") then
                                all_finished = true
                                break
                            elseif line:find("is out of reach") then
                                local disabler = uv("hunting_disabler")
                                if #disabler > 0 then
                                    waitrt()
                                    fput(disabler .. " #" .. critter.id)
                                end
                            end
                        end
                    end
                else
                    break -- no critters, move on
                end
            end
        end
        wound_check()
        if all_finished then break end
        pause(wait_before_moving)
    end
    fput("stance defensive")
    unhide()
    if starting_room then go2_room(starting_room) end
end

-- ============================================================================
-- LOCK MASTERY TASKS
-- ============================================================================

--- LMAS sense tasks (1 through 5) - simplified versions
local function lmas_sense_task1()
    fput("lmaster sense")
    while true do
        local line = get()
        local condition = line:match("the area around you .- (.-)%.")
        if condition and (line:find("has") or line:find("is")) then
            fput("say " .. condition)
        end
        if line:find("repetition") then
            fput("lmaster sense")
        elseif line:find("You have completed") then
            break
        end
    end
end

--- Sense task 2: report room conditions + active spells
local function lmas_sense_task2()
    local stuff_to_say = nil
    fput("lmaster sense")
    while true do
        local line = get()
        local condition = line:match("As far as you can tell, the area around you (?:has|is) (.-)%.")
        if not condition then
            condition = line:match("the area around you (?:has|is) (.-)%.")
        end
        if condition then
            stuff_to_say = condition .. ", "
            -- Collect active spell names for ~2 seconds
            local start_time = os.time()
            fput("spell active")
            while true do
                local spell_line = get()
                if spell_line:find("Presence") then
                    stuff_to_say = stuff_to_say .. "Presence, "
                elseif spell_line:find("Sounds") then
                    stuff_to_say = stuff_to_say .. "Sounds, "
                elseif spell_line:find("Weapon Deflection") then
                    stuff_to_say = stuff_to_say .. "Weapon Deflection, "
                elseif spell_line:find("Interference") then
                    stuff_to_say = stuff_to_say .. "Interference, "
                elseif spell_line:find("Song of Luck") then
                    stuff_to_say = stuff_to_say .. "Song of Luck, "
                elseif spell_line:find("Self Control") then
                    stuff_to_say = stuff_to_say .. "Self Control, "
                elseif spell_line:find("Lock Pick Enhancement") then
                    stuff_to_say = stuff_to_say .. "Lock Pick Enhancement, "
                elseif spell_line:find("Disarm Enhancement") then
                    stuff_to_say = stuff_to_say .. "Disarm Enhancement, "
                elseif os.time() > start_time + 2 then
                    break
                end
            end
            -- Trim trailing ", " and say result
            local trimmed = stuff_to_say:gsub(", $", "")
            fput("say " .. trimmed)
        elseif line:find("repetition") then
            stuff_to_say = nil
            if sense_task_5_current_task then
                sense_task_5_current_task = nil
                break
            else
                fput("lmaster sense")
            end
        elseif line:find("Try sensing again") or line:find("sense again") then
            stuff_to_say = nil
            fput("lmaster sense")
        elseif line:find("You have completed") then
            sense_task_5_current_task = "finished"
            break
        end
    end
end

local function lmas_sense_task3()
    fput("lmaster sense")
    while true do
        local line = get()
        local trap_type = line:match("you think you could probably handle (.-) trap")
        if trap_type then
            fput("say " .. trap_type .. " trap")
        end
        if line:find("repetition") then
            if sense_task_5_current_task then
                sense_task_5_current_task = nil
                break
            else
                fput("lmaster sense")
            end
        elseif line:find("Try sensing again") or line:find("sense again") then
            fput("lmaster sense")
        elseif line:find("You have completed") then
            sense_task_5_current_task = "finished"
            break
        end
    end
end

local function lmas_sense_task4()
    fput("lmaster sense")
    while true do
        local line = get()
        local lock_type = line:match("probably handle .* trap and an? (.-) with")
        if lock_type then
            fput("say " .. lock_type)
        end
        if line:find("repetition") then
            if sense_task_5_current_task then
                sense_task_5_current_task = nil
                break
            else
                fput("lmaster sense")
            end
        elseif line:find("Try sensing again") or line:find("sense again") then
            fput("lmaster sense")
        elseif line:find("You have completed") then
            sense_task_5_current_task = "finished"
            break
        end
    end
end

--- Sense task 5: multiplex dispatcher — read footpad hint and dispatch to task 2/3/4
local function lmas_sense_task5()
    while true do
        if sense_task_5_current_task == "finished" then
            break
        elseif sense_task_5_current_task == nil then
            while true do
                local line = get()
                if line:find("room conditions") then
                    sense_task_5_current_task = "room conditions"
                    break
                elseif line:find("going for the best trap you can get") then
                    sense_task_5_current_task = "best trap"
                    break
                elseif line:find("going for the best lock you can get") then
                    sense_task_5_current_task = "best lock"
                    break
                end
            end
        end
        if sense_task_5_current_task == "room conditions" then
            lmas_sense_task2()
        elseif sense_task_5_current_task == "best trap" then
            lmas_sense_task3()
        elseif sense_task_5_current_task == "best lock" then
            lmas_sense_task4()
        end
    end
    sense_task_5_current_task = nil
end

--- Measure box task
local function lmas_measure_box()
    local all_finished = false
    while not all_finished do
        waitrt()
        local rh = GameObj.right_hand()
        if not rh or not rh.noun:find("calipers") then
            fput("get calipers from table")
        end
        fput("lmas measure box")
        local line = matchtimeout(20, "Measuring carefully", "repetition", "You have completed", "Give it another shot", "try again")
        if line then
            local diff = line:match("it looks to be an? (.-) %(")
            if diff then
                fput("say " .. diff)
                while true do
                    local line2 = get()
                    if line2:find("repetition") or line2:find("try again") or line2:find("Give it another shot") then
                        break
                    elseif line2:find("You have completed") then
                        all_finished = true
                        break
                    end
                end
            elseif line:find("You have completed") then
                all_finished = true
            end
        end
        pause(0.1)
    end
end

--- Measure box with calipers, then pick it open, then calibrate and give calipers back
local function lmas_measure_and_pick_box()
    local all_finished = false
    fput("get calipers from table")
    fput("lmaster calibrate my calipers")
    waitrt()
    while not all_finished do
        fput("lmas measure box")
        local result = matchtimeout(20, "Measuring carefully")
        local wait_for_line = result and result:find("Measuring carefully")
        if wait_for_line then
            -- Stow calipers
            while GameObj.right_hand() or GameObj.left_hand() do
                waitrt()
                fput("put calipers on table")
                pause(0.2)
            end
            -- Get lockpick
            while not GameObj.right_hand() do
                waitrt()
                fput("get lockpick from table")
                pause(0.2)
            end
            -- Pick box until it opens
            while true do
                waitrt()
                local pick_result = matchtimeout(5, "It opens", "Roundtime")
                if pick_result and pick_result:find("It opens") then
                    break
                end
            end
            waitrt()
            -- Stow lockpick
            while GameObj.right_hand() or GameObj.left_hand() do
                waitrt()
                fput("put lockpick on table")
                pause(0.2)
            end
            -- Get calipers back
            while not GameObj.right_hand() do
                waitrt()
                fput("get calipers from table")
                pause(0.2)
            end
            -- Calibrate calipers
            while true do
                waitrt()
                local cal_result = matchtimeout(15, "but you're not that good", "Roundtime")
                if cal_result and cal_result:find("but you're not that good") then
                    break
                elseif cal_result and cal_result:find("Roundtime") then
                    -- keep looping
                end
            end
            -- Give calipers to footpad
            while true do
                waitrt()
                local give_result = matchtimeout(15, "repetition", "This still needs some work", "You have completed")
                if give_result and (give_result:find("repetition") or give_result:find("This still needs some work")) then
                    break
                elseif give_result and give_result:find("You have completed") then
                    all_finished = true
                    break
                end
            end
        end
        waitrt()
        if not all_finished then
            while not GameObj.right_hand() do
                waitrt()
                fput("get calipers from table")
                pause(0.2)
            end
        end
        pause(0.1)
    end
end

--- Relock boxes with footpad
local function relock_boxes()
    fput("get my lockpick")
    wait_until(function() return GameObj.right_hand() end)
    while true do
        waitrt()
        fput("lmas relock box on table")
        local line = matchtimeout(5, "It locks")
        if line and line:find("It locks") then
            while not GameObj.left_hand() do
                waitrt()
                fput("get box from table")
                pause(0.2)
            end
            fput("give my box to #" .. npc.id)
            local result = matchtimeout(5, "repetition", "You have completed")
            if result and result:find("You have completed") then
                break
            end
        end
    end
    check_hands()
end

--- Appraise lockpicks with footpad — get pick, appraise, give to NPC, repeat
local function appraise_lockpicks_with_footpad()
    local all_finished = false
    while not all_finished do
        -- Get a lockpick from the table
        while not (GameObj.right_hand() or GameObj.left_hand()) do
            waitrt()
            fput("get lockpick from table")
            pause(0.1)
        end
        -- Appraise the lockpick
        while true do
            waitrt()
            fput("lmas appraise my lockpick")
            local result = matchtimeout(3, "Roundtime")
            if result and result:find("Roundtime") then
                break
            end
        end
        -- Give the lockpick to the footpad
        while true do
            waitrt()
            fput("give my lockpick to #" .. npc.id)
            local result = matchtimeout(3, "repetition", "Try one more", "Lemme rearrange", "You have completed")
            if result then
                if result:find("repetition") or result:find("Try one more") or result:find("Lemme rearrange") then
                    break
                elseif result:find("You have completed") then
                    all_finished = true
                    break
                end
            end
            if not GameObj.right_hand() and not GameObj.left_hand() then
                break
            end
        end
    end
end

--- Pit skills against footpad (picking contest)
local function pit_skills_against_footpad()
    find_nearest_target_room("rogue guild trainer")
    ask_footpad_to_train()
    waitfor("just nod to me")
    local box_numbers = {"first", "second", "third", "fourth", "fifth"}
    fput("nod #" .. npc.id)
    fput("lmas focus")
    -- Disarm all boxes
    for _, box_num in ipairs(box_numbers) do
        while true do
            waitrt()
            fput("disarm " .. box_num .. " box")
            local line = matchtimeout(5, "You discover no traps", "preventing its exit",
                "BOOM", "flag pops out", "flag rolled around")
            if line then
                if line:find("You discover no traps") or line:find("preventing its exit") or
                   line:find("BOOM") or line:find("flag pops out") then
                    break
                elseif line:find("flag rolled around") then
                    -- Need to disarm the flag
                    while true do
                        waitrt()
                        fput("disarm " .. box_num .. " box")
                        local line2 = matchtimeout(5, "nudge the end", "preventing its exit", "Roundtime")
                        if line2 then
                            if line2:find("nudge") or line2:find("preventing") then break end
                        end
                    end
                    break
                end
            end
        end
    end
    -- Pick all boxes
    waitrt()
    while not (GameObj.right_hand() and GameObj.right_hand().noun == "lockpick") do
        waitrt()
        fput("get lockpick from table")
        pause(0.1)
    end
    if uv("use_lmas_focus_picking_contests"):lower():find("yes") then
        fput("lmas focus")
    else
        fput("stop lmaster focus")
    end
    for _, box_num in ipairs(box_numbers) do
        while true do
            waitrt()
            fput("pick " .. box_num .. " box")
            local line = matchtimeout(5, "It opens", "not appear to be locked", "Roundtime")
            if line then
                if line:find("It opens") or line:find("not appear to be locked") then break end
            end
        end
    end
    waitfor("Final scores", "escorts you back")
    move_out_of_room()
end

--- Make wooden wedges
local function make_wooden_wedges(number)
    if current_task == "Make wooden wedges" then
        table.insert(text_to_display, "Creating " .. number .. " wedges of at least \"" .. (required_wedge_quality or "warped") .. "\" quality.")
    else
        table.insert(text_to_display, "Creating " .. number .. " wedges.")
    end
    display_message()
    local cost_per_wedge = (current_task == "Make wooden wedges") and 600 or 300
    withdraw_silvers(number * cost_per_wedge)
    find_nearest_target_room("rogue guild toolbenchs")
    fput("go toolbench")
    created_wedges = {}
    local order_number = nil
    local acceptable_count = 0

    while acceptable_count < number do
        check_hands()
        if not order_number then
            fput("read sign")
            while true do
                local line = get()
                local num = line:match("(%d+)%.%) an uncarved wooden block")
                if num then
                    order_number = tonumber(num)
                    break
                end
            end
        end
        fput("order " .. order_number)
        fput("buy")
        waitfor("accepts your silvers")

        local tasks = {"carve my block", "carve my wedge", "rub my wedge"}
        for _, task in ipairs(tasks) do
            while true do
                waitrt()
                fput(task)
                local line = matchtimeout(5, "Maybe if you were holding it",
                    "can't carve that", "should RUB the wedge",
                    "RUB the wedge in a guild workshop", "wedge is ready for use",
                    "rub .* wedge in your hand", "Roundtime")
                if line then
                    if not line:find("Roundtime") then break end
                end
            end
        end

        -- Check wedge quality
        local quality = nil
        while not quality do
            waitrt()
            fput("rub my wedge")
            local line = matchtimeout(3, "You rub")
            if line then
                quality = line:match("You rub an? (.-) in your hand")
            end
        end

        local qi = wedge_quality_index(quality)
        if current_task == "Make wooden wedges" then
            local rqi = wedge_quality_index(required_wedge_quality)
            if qi and rqi and qi >= rqi then
                acceptable_count = acceptable_count + 1
                local rh = GameObj.right_hand()
                if rh then table.insert(created_wedges, rh.id) end
            else
                fput("drop my wedge")
            end
        else
            acceptable_count = acceptable_count + 1
        end
    end
    check_hands()
    move_out_of_room()
    if current_skill == "Wedge" then
        error("Wedge creation complete")
    end
end

--- Clasp some containers
local function clasp_some_containers()
    table.insert(text_to_display, "Buying containers to add clasps to.")
    display_message()
    withdraw_silvers(reps_remaining * 1300)
    find_nearest_target_room("rogue guild shop")
    local order_number = nil
    local created_items = {}
    for i = 1, reps_remaining do
        check_hands()
        if not order_number then
            fput("order")
            while true do
                local line = get()
                local num = line:match("(%d+)%. an?%s+%D*sack")
                if num then
                    order_number = tonumber(num)
                    break
                end
            end
        end
        fput("order " .. order_number)
        fput("buy")
        wait_until(function() return GameObj.right_hand() end)
        local rh = GameObj.right_hand()
        if rh then table.insert(created_items, rh.id) end
        fput("stow right")
    end

    find_nearest_target_room("rogue guild toolbenchs")
    fput("go toolbench")
    local clasp_order = nil
    for idx, sack_id in ipairs(created_items) do
        table.insert(text_to_display, (#created_items - idx + 1) .. " more sacks to clasp.")
        display_message()
        check_hands()
        while not GameObj.right_hand() do
            waitrt()
            fput("get #" .. sack_id)
            pause(0.3)
        end
        if not clasp_order then
            fput("read sign")
            while true do
                local line = get()
                local num = line:match("(%d+)%.%) a slate grey steel clasp")
                if num then
                    clasp_order = tonumber(num)
                    break
                end
            end
        end
        fput("order " .. clasp_order)
        fput("buy")
        wait_until(function() return GameObj.right_hand() and GameObj.left_hand() end)
        -- Remove any existing clasp
        fput("lmas clasp remove my sack")
        pause(1)
        -- Add the new clasp
        while GameObj.left_hand() do
            waitrt()
            fput("lmas clasp my sack")
            pause(0.2)
        end
        local action = (task_for_footpad_or_administrator == "Footpad") and "stow" or "drop"
        while GameObj.right_hand() do
            waitrt()
            fput(action .. " #" .. sack_id)
            pause(0.3)
        end
    end
    find_nearest_target_room("bank")
    fput("depo all")

    if task_for_footpad_or_administrator == "Footpad" then
        find_nearest_target_room("rogue guild trainer")
        ask_footpad_to_train()
        waitfor("it's useful to keep your containers closed")
        for _, sack_id in ipairs(created_items) do
            check_hands()
            while not GameObj.right_hand() do
                waitrt()
                fput("get #" .. sack_id)
                pause(0.3)
            end
            fput("give #" .. sack_id .. " to #" .. npc.id)
            pause(0.3)
            fput("drop #" .. sack_id)
        end
    end
end

--- Create lock assemblies
local function create_lock_assemblies()
    table.insert(text_to_display, "Creating some lock assemblies.")
    display_message()
    local lock_to_create
    if task_for_footpad_or_administrator == "Footpad" then
        lock_to_create = math.floor(Skills.to_bonus(Skills.picking_locks) / 5) * 5
        withdraw_silvers(reps_remaining * 9000)
    else
        lock_to_create = math.floor((Skills.to_bonus(Skills.picking_locks) * 2.0) / 4) * 5
        withdraw_silvers(60000)
    end
    find_nearest_target_room("rogue guild toolbenchs")
    local created_items = {}
    fput("go toolbench")
    for i = 1, reps_remaining do
        table.insert(text_to_display, (reps_remaining - i + 1) .. " more lock assemblies to make.")
        display_message()
        while true do
            waitrt()
            fput("lmas lock create " .. lock_to_create)
            local line = matchtimeout(5, "If this price is acceptable", "Roundtime", "don't have enough")
            if line then
                if line:find("Roundtime") or line:find("don't have enough") then break end
            end
        end
        wait_until(function() return GameObj.right_hand() end)
        local rh = GameObj.right_hand()
        if rh then table.insert(created_items, rh.id) end
        check_hands()
        if task_for_footpad_or_administrator == "Administrator" then
            move_out_of_room()
            while not GameObj.right_hand() do
                waitrt()
                fput("get my assembly")
                pause(0.3)
            end
            fput("give my assembly to attendant")
            fput("give my assembly to attendant")
            fput("go toolbench")
        end
    end
    move_out_of_room()
    if task_for_footpad_or_administrator == "Footpad" then
        find_nearest_target_room("rogue guild trainer")
        ask_footpad_to_train()
        waitfor("lockmakers around")
        for _, item_id in ipairs(created_items) do
            while not GameObj.right_hand() do
                waitrt()
                fput("get #" .. item_id)
                pause(0.3)
            end
            fput("give #" .. item_id .. " to #" .. npc.id)
            check_hands()
        end
        -- Sell assemblies back
        move_out_of_room()
        find_nearest_target_room("rogue guild toolbenchs")
        for _, item_id in ipairs(created_items) do
            while not GameObj.right_hand() do
                waitrt()
                fput("get #" .. item_id)
                pause(0.3)
            end
            fput("give #" .. item_id .. " to attendant")
            fput("give #" .. item_id .. " to attendant")
            check_hands()
        end
    end
    find_nearest_target_room("bank")
    fput("depo all")
end

--- Create lockpicks for task
local function create_lockpicks_for_task()
    table.insert(text_to_display, "Creating lockpicks.")
    display_message()
    withdraw_silvers(reps_remaining * 300)
    local created_items = {}
    find_nearest_target_room("rogue guild toolbenchs")
    fput("go toolbench")
    local order_number = nil
    for i = 1, reps_remaining do
        table.insert(text_to_display, (reps_remaining - #created_items) .. " more lockpicks to create.")
        display_message()
        check_hands()
        if not order_number then
            fput("read sign")
            while true do
                local line = get()
                local num = line:match("(%d+)%.%) a thin bar of copper")
                if num then
                    order_number = tonumber(num)
                    break
                end
            end
        end
        fput("order " .. order_number)
        fput("buy")
        wait_until(function() return GameObj.right_hand() end)
        while GameObj.right_hand() do
            fput("lmas create")
            pause(0.2)
            waitrt()
        end
        if current_task == "Customize lockpicks" then
            if GameObj.left_hand() then
                fput("swap")
                fput("lmas customize edge brass")
                fput("lmas customize edge brass")
                local rh = GameObj.right_hand()
                if rh then table.insert(created_items, rh.id) end
                local action = (task_for_footpad_or_administrator == "Footpad") and "stow" or "drop"
                while GameObj.right_hand() do
                    waitrt()
                    fput(action .. " right")
                    pause(0.2)
                end
            end
        else
            if GameObj.left_hand() then
                local lh = GameObj.left_hand()
                if lh then table.insert(created_items, lh.id) end
                while GameObj.left_hand() do
                    waitrt()
                    fput("stow left")
                    pause(0.2)
                end
            end
        end
    end
    find_nearest_target_room("bank")
    fput("depo all")
    if task_for_footpad_or_administrator == "Footpad" then
        find_nearest_target_room("rogue guild trainer")
        ask_footpad_to_train()
        waitfor("lockpick", "creative side")
        for _, pick_id in ipairs(created_items) do
            check_hands()
            while not GameObj.right_hand() do
                waitrt()
                fput("get #" .. pick_id)
                pause(0.3)
            end
            fput("give #" .. pick_id .. " to #" .. npc.id)
            pause(0.3)
            fput("drop #" .. pick_id)
        end
    end
end

--- Cut keys
local function cut_keys()
    table.insert(text_to_display, "Cutting some keys.")
    display_message()
    withdraw_silvers(5000)
    find_nearest_target_room("rogue guild toolbenchs")
    fput("go toolbench")
    -- Create an assembly first
    while true do
        waitrt()
        fput("lmas lock create 10")
        local line = matchtimeout(5, "If this price is acceptable", "Roundtime")
        if line and line:find("Roundtime") then break end
    end
    check_hands()
    while not GameObj.right_hand() do
        waitrt()
        fput("get my assembly")
        pause(0.3)
    end
    local order_number = nil
    for i = 1, reps_remaining do
        if not order_number then
            fput("read sign")
            while true do
                local line = get()
                local num = line:match("(%d+)%.%) a steel key blank")
                if num then
                    order_number = tonumber(num)
                    break
                end
            end
        end
        table.insert(text_to_display, (reps_remaining - i + 1) .. " more keys to make.")
        display_message()
        fput("order " .. order_number)
        fput("buy")
        wait_until(function() return GameObj.left_hand() end)
        while true do
            waitrt()
            fput("lmas cut")
            local line = matchtimeout(5, "Roundtime")
            if line and line:find("Roundtime") then break end
        end
        while GameObj.left_hand() do
            waitrt()
            fput("drop my key")
            pause(0.3)
        end
    end
    move_out_of_room()
    fput("give my assembly to attendant")
    fput("give my assembly to attendant")
    find_nearest_target_room("bank")
    fput("depo all")
end

-- ============================================================================
-- Talk to master footpad (dispatches to the correct sub-task)
-- ============================================================================
local function talk_to_master_footpad()
    table.insert(text_to_display, "Visiting a master footpad for " .. current_skill .. ".")
    display_message()
    find_nearest_target_room("rogue guild trainer")
    check_hands()
    ask_footpad_to_train()
    waitfor("pulls you aside for some instruction")
    while true do
        local line = get()
        -- Lock Mastery footpad sub-tasks
        if line:find("Pick as many boxes on the table") then
            current_task = "First Lock Mastery task"
            break
        elseif line:find("then describe the room conditions in one sentence") then
            current_task = "Lock Mastery sense task 1"
            break
        elseif line:find("describe the room conditions and name any spells") or
               line:find("room conditions and any spells affecting you") then
            current_task = "Lock Mastery sense task 2"
            break
        elseif line:find("then describe the best trap you can get") then
            current_task = "Lock Mastery sense task 3"
            break
        elseif line:find("then describe the best lock you can get") then
            current_task = "Lock Mastery sense task 4"
            break
        elseif line:find("any number of different things you learned recently") then
            current_task = "Lock Mastery sense task 5"
            break
        elseif line:find("LMASTER MEASURE box") and line:find("speak the box") then
            current_task = "Lock Mastery measure box"
            break
        elseif line:find("LMASTER CALIBRATE them once to attune") then
            current_task = "Lock Mastery measure and pick box"
            break
        elseif line:find("If you gots a wedge for me") or line:find("I'll accept a warped") or
               line:find("have to be at least of solid construction") then
            if line:find("I'll accept a warped") then
                required_wedge_quality = "warped wooden wedge"
            elseif line:find("solid construction") then
                required_wedge_quality = "solid wooden wedge"
            else
                required_wedge_quality = "warped wooden wedge"
            end
            current_task = "Make wooden wedges"
            break
        elseif line:find("LMASTER APPRAISE") then
            current_task = "Lock Mastery appraise lockpicks with footpad"
            break
        elseif line:find("Nothin' wrong with takin' a busted pick") then
            current_task = "Repair broken lockpicks"
            break
        elseif line:find("LMASTER RELOCK the box on the table") then
            current_task = "Relock boxes with footpad"
            break
        elseif line:find("useful to keep your containers closed") then
            current_task = "Clasp some containers"
            break
        elseif line:find("lockmakers around") then
            current_task = "Make lock assemblies"
            break
        elseif line:find("yank out poison needles") then
            trap_components_first_turnin = true
            trap_components_needed_names = {"small jaws", "steel needle"}
            trap_components_needed_nouns = {"jaws", "needle"}
            trap_components_needed_list = "pair of small steel jaws, slender steel needle"
            task_for_footpad_or_administrator = "Footpad"
            current_task = "Gather trap components"
            break
        elseif line:find("extract the vials of acid") then
            trap_components_first_turnin = true
            trap_components_needed_names = {"clear vial"}
            trap_components_needed_nouns = {"vial"}
            trap_components_needed_list = "clear glass vial of light yellow acid"
            task_for_footpad_or_administrator = "Footpad"
            current_task = "Gather trap components"
            break
        elseif line:find("eagerly awaiting to learn how to extract are those pretty crystals") then
            trap_components_first_turnin = true
            trap_components_needed_names = {"dark crystal", "sphere"}
            trap_components_needed_nouns = {"crystal", "sphere"}
            trap_components_needed_list = "(small) dark crystal, (various colors of) sphere"
            task_for_footpad_or_administrator = "Footpad"
            current_task = "Gather trap components"
            break
        elseif line:find("throw burning goo on you and the shocking cloud") then
            trap_components_first_turnin = true
            trap_components_needed_names = {"thick vial", "green vial"}
            trap_components_needed_nouns = {"vial"}
            trap_components_needed_list = "thick glass vial filled with murky red liquid, green-tinted vial filled with thick acrid smoke"
            task_for_footpad_or_administrator = "Footpad"
            current_task = "Gather trap components"
            break
        elseif line:find("while going to your local professional and picking up a lockpick") then
            current_task = "Create lockpicks"
            break
        elseif line:find("time to exercise your creative side") then
            dark_corner_number = dark_corner_number + 1
            task_for_footpad_or_administrator = "Footpad"
            current_task = "Customize lockpicks"
            break
        -- Stun Maneuvers footpad sub-tasks
        elseif line:find("tosses the shield back into the corner") then
            stunman_current_command = "stunman shield"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("plucks up a sword from the corner") then
            stunman_current_command = "stunman weapon"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("tosses the brick back into the corner") then
            stunman_current_command = "stunman get"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("Don't be afraid to hit me") then
            stunman_current_command = "stunman attack"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("manages to pull .* to .* knees") then
            stunman_current_command = "stunman stand"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("STUNMAN STANCE2") or line:find("how STANCE2 is done right") then
            stunman_current_command = "stunman stance2"
            current_task = "Stun Maneuvers footpad tasks"
            break
        elseif line:find("slowly force .* to bring up .* arms in protection") then
            stunman_current_command = "stunman stance1"
            current_task = "Stun Maneuvers footpad tasks"
            break
        -- Subdue footpad
        elseif line:find("Type SUBDUE mannequin to begin") then
            current_task = "Subdue mannequin"
            break
        elseif line:find("Youze gots enough skill now") then
            current_task = "Secret revealed"
            break
        -- Sweep footpad
        elseif line:find("sweep should just be used for combat") or
               line:find("show ya da way this sweep thing works") or
               line:find("You try to sweep me while I try to sweep you") or
               line:find("I'll sweep you, you sweep me") or
               line:find("see how you do under combat") then
            current_task = "Sweep footpads"
            break
        -- Cheapshot footpad
        elseif line:find("Type CHEAPSHOT (.-) .* to begin") then
            current_task = "Cheapshot footpads"
            current_cheapshot = line:match("Type CHEAPSHOT (%S+)")
            if current_cheapshot then current_cheapshot = current_cheapshot:lower() end
            break
        end
    end

    -- Dispatch to the specific sub-task handler
    if current_task == "First Lock Mastery task" then
        -- Pick boxes on the table
        local table_obj = nil
        for _, obj in ipairs(GameObj.loot()) do
            if obj.name:find("table") then table_obj = obj; break end
        end
        if not table_obj then
            for _, obj in ipairs(GameObj.room_desc()) do
                if obj.name:find("table") then table_obj = obj; break end
            end
        end
        if table_obj then
            fput("look on #" .. table_obj.id)
            pause(0.5)
            fput("get lockpick from table")
            wait_until(function() return GameObj.right_hand() end)
            -- Pick all boxes on table
            if table_obj.contents then
                for _, box in ipairs(table_obj.contents) do
                    waitrt()
                    fput("pick #" .. box.id)
                end
            end
            while GameObj.right_hand() do
                waitrt()
                fput("give lockpick to #" .. npc.id)
                pause(0.1)
            end
            waitfor("escorts you back")
        end
    elseif current_task == "Lock Mastery sense task 1" then
        lmas_sense_task1()
    elseif current_task == "Lock Mastery sense task 2" then
        lmas_sense_task2()
    elseif current_task == "Lock Mastery sense task 3" then
        lmas_sense_task3()
    elseif current_task == "Lock Mastery sense task 4" then
        lmas_sense_task4()
    elseif current_task == "Lock Mastery sense task 5" then
        lmas_sense_task5()
    elseif current_task == "Lock Mastery measure box" then
        lmas_measure_box()
    elseif current_task == "Lock Mastery measure and pick box" then
        lmas_measure_and_pick_box()
    elseif current_task == "Lock Mastery appraise lockpicks with footpad" then
        appraise_lockpicks_with_footpad()
    elseif current_task == "Make wooden wedges" then
        make_wooden_wedges(reps_remaining)
        find_nearest_target_room("rogue guild trainer")
        ask_footpad_to_train()
        waitfor("wedge for me", "I'll accept a warped", "solid construction")
        for _, wedge_id in ipairs(created_wedges) do
            fput("get #" .. wedge_id)
            wait_until(function() return GameObj.right_hand() or GameObj.left_hand() end)
            fput("give my wedge to #" .. npc.id)
            fput("drop my wedge")
        end
    elseif current_task == "Relock boxes with footpad" then
        relock_boxes()
    elseif current_task == "Clasp some containers" then
        task_for_footpad_or_administrator = "Footpad"
        clasp_some_containers()
    elseif current_task == "Make lock assemblies" then
        task_for_footpad_or_administrator = "Footpad"
        create_lock_assemblies()
    elseif current_task == "Create lockpicks" or current_task == "Customize lockpicks" then
        task_for_footpad_or_administrator = "Footpad"
        create_lockpicks_for_task()
    elseif current_task == "Stun Maneuvers footpad tasks" then
        stun_man_footpad_tasks()
    elseif current_task == "Subdue mannequin" then
        subdue_footpad_tasks()
    elseif current_task == "Secret revealed" then
        pause(0.1)
    elseif current_task == "Sweep footpads" then
        sweep_footpads()
    elseif current_task == "Cheapshot footpads" then
        cheapshot_footpads()
    elseif current_task == "Repair broken lockpicks" or
           current_task == "Gather trap components" or
           current_task == "Melt open plated boxes" then
        -- These tasks give instructions but need manual or tpick handling
        table.insert(text_to_display, "This task requires ;tpick or manual completion.")
        table.insert(text_to_display, "Task: " .. current_task)
        if trap_components_needed_list then
            table.insert(text_to_display, "Components needed: " .. trap_components_needed_list)
        end
        display_message()
        error("Task requires manual completion: " .. current_task)
    end
    move_out_of_room()
    current_task = "Check next task"
end

-- ============================================================================
-- Partner tasks
-- ============================================================================
local function practice_with_a_partner()
    if not partner_name then
        table.insert(text_to_display, "You must specify a partner name.")
        table.insert(text_to_display, "Use ;rogues setup (Partner Info tab) or ;rogues sweep <name>.")
        display_message()
        error("No partner specified")
    end

    go2_room(partner_room_number)
    pause(1)
    fput("stance offensive")

    local what_to_ask
    local attack_to_perform
    if current_task == "Practice sweeping a partner" then
        fput("gld stance offensive")
        attack_to_perform = "sweep"
        what_to_ask = "whisper ooc " .. partner_name .. " I need help with a Rogue guild task. Can I sweep you?"
    elseif current_task == "Practice cheapshots on partner" then
        fput("gld stance offensive")
        attack_to_perform = "cheapshot " .. current_cheapshot
        what_to_ask = "whisper ooc " .. partner_name .. " I need help with a Rogue guild task. Can I cheapshot you?"
    elseif current_task == "Defend against sweep from a partner" then
        fput("gld stance defensive")
        what_to_ask = "whisper ooc " .. partner_name .. " I need help with a Rogue guild task. Can you sweep me?"
    elseif current_task == "Defend against cheapshots from a partner" then
        fput("gld stance defensive")
        what_to_ask = "whisper ooc " .. partner_name .. " I need help with a Rogue guild task. Can you " .. current_cheapshot .. " me?"
    end

    -- Wait for partner to respond
    while true do
        fput(what_to_ask)
        local line = matchtimeout(10, "Sure! Let's do this!")
        if line and line:find("Sure!") then break end
    end

    if current_task == "Practice sweeping a partner" or current_task == "Practice cheapshots on partner" then
        local all_finished = false
        while not all_finished do
            stand_up()
            if all_finished then break end
            waitrt()
            if need_to_stance_down then stance_down() end
            wait_for_stamina(15)
            fput(attack_to_perform .. " " .. partner_name)
            while true do
                local line = get()
                if line:find("SMR result") then
                    break
                elseif line:find("Roundtime") then
                    break
                elseif line:find("You have completed") then
                    put("whisper ooc " .. partner_name .. " All finished with my task. Thank you!")
                    all_finished = true
                    break
                end
            end
        end
    elseif current_task == "Defend against sweep from a partner" or
           current_task == "Defend against cheapshots from a partner" then
        while true do
            local line = get()
            if line:find("repetition") then
                put("whisper ooc " .. partner_name .. " Again please.")
            elseif line:find("You have completed") then
                put("whisper ooc " .. partner_name .. " All finished with my task. Thank you!")
                break
            end
            -- Auto stand
            if not GameState.standing then
                waitrt()
                fput("stand")
            end
        end
    end
end

-- ============================================================================
-- do_the_task: dispatch a numbered task, optionally trading it in
-- ============================================================================
local function do_the_task(number, skill_name)
    table.insert(text_to_display, "Your current task is: " .. current_task .. ".")
    if current_task == "Gather trap components" and trap_components_needed_list then
        table.insert(text_to_display, "Components needed: " .. trap_components_needed_list)
    end
    table.insert(text_to_display, "This is task #" .. number .. " for \"" .. skill_name .. " tasks to trade\" in setup.")

    -- Check if user wants to trade this task
    local tasks_to_trade = {}
    if skill_name == "Universal" then tasks_to_trade = universal_tasks_to_trade
    elseif skill_name == "Stun Maneuvers" then tasks_to_trade = stun_maneuvers_tasks_to_trade
    elseif skill_name == "Subdue" then tasks_to_trade = subdue_tasks_to_trade
    elseif skill_name == "Sweep" then tasks_to_trade = sweep_tasks_to_trade
    elseif skill_name == "Cheapshots" then tasks_to_trade = cheapshots_tasks_to_trade
    elseif skill_name == "Lock Mastery" then tasks_to_trade = lock_mastery_tasks_to_trade
    end

    if tbl_contains(tasks_to_trade, number) and not do_not_skip_this_task then
        check_to_trade_in_task()
        return
    end

    display_message()

    -- Execute the task
    if skill_name == "Universal" then
        if number == "1" then clean_windows()
        elseif number == "2" then sweep_floors()
        elseif number == "3" then water_plants()
        end
        current_task = "Check next task"
    elseif skill_name == "Stun Maneuvers" then
        if number == "1" then
            footpad_shoot_arrows()
        elseif number == "2" then
            -- Determine stunman command based on current_task
            if current_task == "Readying your shield while stunned" then
                stunman_current_command = "stunman shield"
            elseif current_task == "Getting your weapon while stunned" then
                stunman_current_command = "stunman weapon"
            elseif current_task == "Picking stuff up while stunned" then
                stunman_current_command = "stunman get my " .. uv("weapon_for_stunman_weapon")
            elseif current_task == "Standing up while stunned" then
                stunman_current_command = "stunman stand"
            elseif current_task == "Defending yourself a little more while stunned" then
                stunman_current_command = "stunman stance1"
            elseif current_task == "Defending yourself a lot more while stunned" then
                stunman_current_command = "stunman stance2"
            elseif current_task == "Attacking while stunned" then
                stunman_current_command = "stunman attack"
            end
            practice_stun_tasks_alone()
        elseif number == "3" then
            play_slap_hands()
        end
        current_task = "Check next task"
    elseif skill_name == "Subdue" then
        if number == "1" then crush_garlic()
        elseif number == "2" then practice_on_critters()
        elseif number == "3" then ding_up_melons()
        end
        current_task = "Check next task"
    elseif skill_name == "Sweep" then
        if number == "1" then practice_with_a_partner()
        elseif number == "2" then practice_with_a_partner()
        elseif number == "3" then practice_on_critters()
        elseif number == "4" then sweep_the_dummies()
        end
        current_task = "Check next task"
    elseif skill_name == "Cheapshots" then
        if number == "1" then practice_with_a_partner()
        elseif number == "2" then practice_with_a_partner()
        elseif number == "3" then practice_on_critters()
        end
        current_task = "Check next task"
    elseif skill_name == "Lock Mastery" then
        -- Check if tpick should be used
        local tpick_tasks = {"2", "3", "4", "5", "7", "8", "9", "13", "14"}
        if tbl_contains(tasks_to_use_tpick_for, number) and tbl_contains(tpick_tasks, number) then
            table.insert(text_to_display, "This task is set to be automated via ;tpick.")
            table.insert(text_to_display, "Please use ;tpick to complete this task, then restart ;rogues.")
            display_message()
            error("Task delegated to tpick")
        elseif number == "6" then
            pit_skills_against_footpad()
        elseif number == "10" then
            task_for_footpad_or_administrator = "Administrator"
            clasp_some_containers()
        elseif number == "11" then
            task_for_footpad_or_administrator = "Administrator"
            create_lock_assemblies()
        elseif number == "12" then
            cut_keys()
        elseif number == "15" then
            create_lockpicks_for_task()
        else
            -- Tasks that need manual/tpick help or aren't fully automatable
            table.insert(text_to_display, "Task #" .. number .. " for Lock Mastery.")
            if number == "1" then
                table.insert(text_to_display, "This task requires specific room conditions. Use LMASTER SENSE to find suitable rooms.")
            elseif number == "2" then
                table.insert(text_to_display, "Requires an audience (4+ people, Rogues count as 2). Use ;tpick at a locksmith pool.")
            elseif number == "3" then
                table.insert(text_to_display, "Pick tough boxes from creatures. Use ;tpick at a locksmith pool.")
            elseif number == "4" then
                table.insert(text_to_display, "Measure then pick. Requires calipers. Use ;tpick at a locksmith pool.")
            elseif number == "5" then
                table.insert(text_to_display, "Calibrate calipers. Requires calipers. Use ;tpick at a locksmith pool.")
            elseif number == "7" then
                table.insert(text_to_display, "Wedge open boxes. Use LMAS WEDGE. Can use ;tpick.")
            elseif number == "8" then
                table.insert(text_to_display, "Repair broken lockpicks. Buy cheap picks, break them, repair with LMAS REPAIR.")
            elseif number == "9" then
                table.insert(text_to_display, "Relock tough boxes with LMAS RELOCK. Can use ;tpick.")
            elseif number == "13" then
                table.insert(text_to_display, "Gather trap components. Use LMASTER DISARM ON then disarm boxes.")
                if trap_components_needed_list then
                    table.insert(text_to_display, "Needed: " .. trap_components_needed_list)
                end
            elseif number == "14" then
                table.insert(text_to_display, "Melt open plated boxes. DISARM plated boxes with acid vials.")
            end
            display_message()
            error("Task requires manual completion or ;tpick")
        end
        current_task = "Check next task"
    end
end

-- ============================================================================
-- Main task dispatcher
-- ============================================================================
local function do_next_task()
    check_hands()
    if current_task == "Join the guild" then
        join_the_guild()
    elseif current_task == "Get a new task" then
        get_a_new_task()
    elseif current_task == "Check next task" then
        check_next_task()
    elseif current_task == "Current task finished" then
        turnin_current_task()
    elseif current_task == "Get promotion" then
        get_promotion()
    elseif current_task == "This task isn't yet coded." then
        table.insert(text_to_display, "This task isn't yet coded. Look for future updates.")
        display_message()
        error("Task not yet coded")
    elseif current_task == "Trade in current task" then
        trade_in_current_task()
    elseif current_task == "Talk to master footpad" then
        talk_to_master_footpad()
    -- Universal
    elseif current_task == "Clean windows" then
        do_the_task("1", "Universal")
    elseif current_task == "Sweep floors" then
        do_the_task("2", "Universal")
    elseif current_task == "Water plants" then
        do_the_task("3", "Universal")
    -- Stun Maneuvers
    elseif current_task == "Let a footpad shoot arrows at you" then
        do_the_task("1", "Stun Maneuvers")
    elseif current_task == "Readying your shield while stunned" or
           current_task == "Getting your weapon while stunned" or
           current_task == "Picking stuff up while stunned" or
           current_task == "Standing up while stunned" or
           current_task == "Defending yourself a little more while stunned" or
           current_task == "Defending yourself a lot more while stunned" or
           current_task == "Attacking while stunned" then
        do_the_task("2", "Stun Maneuvers")
    elseif current_task == "Play slap hands with a footpad" then
        do_the_task("3", "Stun Maneuvers")
    -- Subdue
    elseif current_task == "Crush up some garlic" then
        do_the_task("1", "Subdue")
    elseif current_task == "Subdue some creatures" then
        do_the_task("2", "Subdue")
    elseif current_task == "Ding up a few melons" then
        do_the_task("3", "Subdue")
    -- Sweep
    elseif current_task == "Practice sweeping a partner" then
        do_the_task("1", "Sweep")
    elseif current_task == "Defend against sweep from a partner" then
        do_the_task("2", "Sweep")
    elseif current_task == "Practice sweeping creatures" then
        do_the_task("3", "Sweep")
    elseif current_task == "Sweep dummies" then
        do_the_task("4", "Sweep")
    -- Cheapshots
    elseif current_task == "Practice cheapshots on partner" then
        do_the_task("1", "Cheapshots")
    elseif current_task == "Defend against cheapshots from a partner" then
        do_the_task("2", "Cheapshots")
    elseif current_task == "Practice cheapshots on creatures" then
        do_the_task("3", "Cheapshots")
    -- Lock Mastery
    elseif current_task == "Pick boxes under a variety of conditions" then
        do_the_task("1", "Lock Mastery")
    elseif current_task == "Pick boxes using your latest trick in front of an audience" then
        do_the_task("2", "Lock Mastery")
    elseif current_task == "Pick some tough boxes from creatures" then
        do_the_task("3", "Lock Mastery")
    elseif current_task == "Measure then pick tough boxes" then
        do_the_task("4", "Lock Mastery")
    elseif current_task == "Calibrate calipers in the field" then
        do_the_task("5", "Lock Mastery")
    elseif current_task == "Pit your skills against a footpad" then
        do_the_task("6", "Lock Mastery")
    elseif current_task == "Wedge open boxes" then
        do_the_task("7", "Lock Mastery")
    elseif current_task == "Relock tough boxes" then
        do_the_task("9", "Lock Mastery")
    elseif current_task == "Clasp some containers" then
        do_the_task("10", "Lock Mastery")
    elseif current_task == "Create lock assemblies" then
        do_the_task("11", "Lock Mastery")
    elseif current_task == "Cut keys" then
        do_the_task("12", "Lock Mastery")
    elseif current_task == "Gather trap components" then
        do_the_task("13", "Lock Mastery")
    elseif current_task == "Melt open plated boxes" then
        do_the_task("14", "Lock Mastery")
    elseif current_task == "Customize lockpicks" then
        do_the_task("15", "Lock Mastery")
    end
end

-- ============================================================================
-- Help display
-- ============================================================================
local function display_help()
    table.insert(text_to_display, "Lock Mastery tasks to trade:")
    table.insert(text_to_display, "1: Pick boxes under a variety of conditions")
    table.insert(text_to_display, "2: Pick boxes using your latest trick in front of an audience")
    table.insert(text_to_display, "3: Pick some tough boxes from creatures")
    table.insert(text_to_display, "4: Measure then pick tough boxes")
    table.insert(text_to_display, "5: Calibrate calipers in the field")
    table.insert(text_to_display, "6: Pit your skills against a footpad")
    table.insert(text_to_display, "7: Wedge open boxes")
    table.insert(text_to_display, "8: Repair broken lockpicks")
    table.insert(text_to_display, "9: Relock tough boxes")
    table.insert(text_to_display, "10: Clasp some containers")
    table.insert(text_to_display, "11: Create lock assemblies")
    table.insert(text_to_display, "12: Cut keys")
    table.insert(text_to_display, "13: Gather trap components")
    table.insert(text_to_display, "14: Melt open plated boxes")
    table.insert(text_to_display, "15: Customize lockpicks")
    table.insert(text_to_display, "---------------------------------------")
    table.insert(text_to_display, "Stun Maneuvers tasks to trade:")
    table.insert(text_to_display, "1: Let a footpad shoot arrows at you")
    table.insert(text_to_display, "2: Self stun tasks")
    table.insert(text_to_display, "3: Play slap hands with a footpad")
    table.insert(text_to_display, "---------------------------------------")
    table.insert(text_to_display, "Subdue tasks to trade:")
    table.insert(text_to_display, "1: Crush up some garlic")
    table.insert(text_to_display, "2: Subdue some creatures")
    table.insert(text_to_display, "3: Ding up a few melons")
    table.insert(text_to_display, "---------------------------------------")
    table.insert(text_to_display, "Sweep tasks to trade:")
    table.insert(text_to_display, "1: Practice sweeping a partner")
    table.insert(text_to_display, "2: Defend against sweep from a partner")
    table.insert(text_to_display, "3: Practice sweeping creatures")
    table.insert(text_to_display, "4: Sweep dummies")
    table.insert(text_to_display, "---------------------------------------")
    table.insert(text_to_display, "Cheapshots tasks to trade:")
    table.insert(text_to_display, "1: Practice cheapshots on partner")
    table.insert(text_to_display, "2: Defend against cheapshots from a partner")
    table.insert(text_to_display, "3: Practice cheapshots on creatures")
    table.insert(text_to_display, "---------------------------------------")
    table.insert(text_to_display, "Universal tasks to trade:")
    table.insert(text_to_display, "1: Clean windows")
    table.insert(text_to_display, "2: Sweep floors")
    table.insert(text_to_display, "3: Water plants")
    display_message()
end

-- ============================================================================
-- Setup GUI
-- ============================================================================
local function run_setup()
    local win = Gui.window("Rogues Setup", { width = 600, height = 700, resizable = true })
    local root = Gui.vbox()

    local tabs = Gui.tab_bar({
        "Tasks Info", "Critter Info", "Partner Info",
        "Lock Mastery", "Stun Maneuvers", "Subdue/Cheapshots"
    })
    root:add(tabs)

    -- Helper to make a labeled input
    local entries = {}
    local function make_entry(parent, label_text, var_key)
        local hbox = Gui.hbox()
        hbox:add(Gui.label(label_text))
        local input = Gui.input({ text = uv(var_key), placeholder = var_key })
        hbox:add(input)
        parent:add(hbox)
        entries[var_key] = input
    end

    -- Tab 1: Tasks Info
    local tab1 = Gui.vbox()
    make_entry(tab1, "Use Guild Profession Boost (yes/no):", "use_guild_profession_boost")
    make_entry(tab1, "Limit vouchers (e.g. 5, exit):", "limit_vouchers")
    make_entry(tab1, "Sweep tasks to trade:", "sweep_tasks_to_trade")
    make_entry(tab1, "Subdue tasks to trade:", "subdue_tasks_to_trade")
    make_entry(tab1, "Stun Maneuvers tasks to trade:", "stun_maneuvers_tasks_to_trade")
    make_entry(tab1, "Lock Mastery tasks to trade:", "lock_mastery_tasks_to_trade")
    make_entry(tab1, "Cheapshots tasks to trade:", "cheapshots_tasks_to_trade")
    make_entry(tab1, "Gambits tasks to trade:", "gambits_tasks_to_trade")
    make_entry(tab1, "Universal tasks to trade:", "universal_tasks_to_trade")
    tabs:set_tab_content(1, Gui.scroll(tab1))

    -- Tab 2: Critter Info
    local tab2 = Gui.vbox()
    make_entry(tab2, "Rooms (comma-separated IDs):", "hunting_area_rooms")
    make_entry(tab2, "Main Hand (noun or GIRD):", "hunting_main_hand")
    make_entry(tab2, "Off Hand (noun):", "hunting_off_hand")
    make_entry(tab2, "Wait time (seconds):", "hunting_wait_time")
    make_entry(tab2, "Critters (comma-separated nouns):", "hunting_acceptable_critters")
    make_entry(tab2, "Disabler (e.g. sweep):", "hunting_disabler")
    make_entry(tab2, "Exit on critter tasks (yes/no):", "rogues_exit_critter_reps")
    tabs:set_tab_content(2, Gui.scroll(tab2))

    -- Tab 3: Partner Info
    local tab3 = Gui.vbox()
    make_entry(tab3, "Partner Name:", "partner_name")
    make_entry(tab3, "Partner Room:", "partner_room")
    make_entry(tab3, "Get promotions from partner (yes/no):", "get_promotions_from_partner")
    make_entry(tab3, "Automate partner reps (full/confirm/none):", "automate_partner_reps")
    tabs:set_tab_content(3, Gui.scroll(tab3))

    -- Tab 4: Lock Mastery
    local tab4 = Gui.vbox()
    make_entry(tab4, "Tasks to use ;tpick for:", "tasks_to_use_tpick_for")
    make_entry(tab4, "Use lmas focus during picking contests (yes/no):", "use_lmas_focus_picking_contests")
    tabs:set_tab_content(4, Gui.scroll(tab4))

    -- Tab 5: Stun Maneuvers
    local tab5 = Gui.vbox()
    make_entry(tab5, "Shield (noun):", "shield_for_stunman_shield")
    make_entry(tab5, "Weapon (noun):", "weapon_for_stunman_weapon")
    make_entry(tab5, "Stun command:", "stun_command")
    make_entry(tab5, "Stun item (noun, if held):", "stun_item")
    tabs:set_tab_content(5, Gui.scroll(tab5))

    -- Tab 6: Subdue and Cheapshots
    local tab6 = Gui.vbox()
    make_entry(tab6, "Weapon (noun):", "weapon_for_subdue_and_cheapshots")
    tabs:set_tab_content(6, Gui.scroll(tab6))

    -- Save button
    local save_btn = Gui.button("Save Settings")
    save_btn:on_click(function()
        for key, input in pairs(entries) do
            UserVars.rogues[key] = input:get_text():match("^%s*(.-)%s*$"):lower()
        end
        UserVars.save()
        respond("Settings saved!")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================
if Stats.prof ~= "Rogue" then
    table.insert(text_to_display, "This script is for rogues only!")
    table.insert(text_to_display, "If you ARE a Rogue, enter INFO into the game and try again.")
    display_message()
elseif Stats.level < 15 then
    table.insert(text_to_display, "You must be level 15 to join a guild. Try again when you reach level 15.")
    display_message()
elseif not current_skill then
    table.insert(text_to_display, "You must specify a skill to work on when starting the script.")
    table.insert(text_to_display, "Available: sweep, subdue, stun maneuvers, lock mastery, cheapshots, gambits")
    table.insert(text_to_display, "You only need the first 3 letters. Examples:")
    table.insert(text_to_display, "  ;rogues stun    - Stun Maneuvers")
    table.insert(text_to_display, "  ;rogues swe     - Sweep")
    table.insert(text_to_display, "  ;rogues lmas    - Lock Mastery")
    table.insert(text_to_display, "  ;rogues sub     - Subdue")
    table.insert(text_to_display, "  ;rogues che     - Cheapshots")
    table.insert(text_to_display, "")
    table.insert(text_to_display, "Other commands:")
    table.insert(text_to_display, "  ;rogues setup   - Open settings GUI")
    table.insert(text_to_display, "  ;rogues help    - Show task numbers")
    table.insert(text_to_display, "  ;rogues checkin - Pay guild dues (3 months)")
    table.insert(text_to_display, "  ;rogues wedge N - Create N wooden wedges")
    table.insert(text_to_display, "  ;rogues partner [name] - Help partner with tasks")
    display_message()
elseif current_skill == "Help" then
    display_help()
elseif current_skill == "Setup" then
    run_setup()
elseif current_skill == "Wedge" then
    if args[2] then
        make_wooden_wedges(tonumber(args[2]) or 1)
    else
        table.insert(text_to_display, "Specify how many wedges: ;rogues wedge 2")
        display_message()
    end
elseif current_skill == "Checkin" then
    checkin_for_guild_dues()
elseif current_skill == "Gambits" then
    table.insert(text_to_display, "Gambits are not yet implemented in this script.")
    table.insert(text_to_display, "Available: Lock Mastery, Stun Maneuvers, Sweep, Subdue, Cheapshots")
    display_message()
elseif current_skill == "Help Partner" then
    if not automate_partner_reps then
        table.insert(text_to_display, "Fill out the \"Automate partner reps\" setting in ;rogues setup.")
        display_message()
    else
        if only_work_with_partner then
            table.insert(text_to_display, "Helping " .. only_work_with_partner .. " ONLY with their guild tasks.")
        else
            table.insert(text_to_display, "Helping ANYONE with their guild tasks.")
        end
        if automate_partner_reps == "full" then
            table.insert(text_to_display, "Fully automated mode. DO NOT GO AFK unless in Shattered.")
        elseif automate_partner_reps == "confirm" then
            table.insert(text_to_display, "Confirm mode. Enter \"shake\" to proceed with each request.")
        elseif automate_partner_reps == "none" then
            table.insert(text_to_display, "Manual mode. Script will prompt you to restart.")
        end
        display_message()
        -- Wait for partner whisper
        while true do
            table.insert(text_to_display, "Waiting for someone to ask for help.")
            display_message()
            while true do
                local line = get()
                if line:find("I need help with a Rogue guild task") or
                   line:find("Can you please promote me in") then
                    local who = line:match("%(OOC%) (.-)'s player whispers")
                    if who and (not only_work_with_partner or only_work_with_partner == who) then
                        if automate_partner_reps == "confirm" then
                            table.insert(text_to_display, who .. " is asking for help. Enter \"shake\" to proceed.")
                            display_message()
                            waitfor("Shake what?")
                        elseif automate_partner_reps == "none" then
                            table.insert(text_to_display, who .. " is asking for help. Restart the script to proceed.")
                            display_message()
                            error("Restart needed for partner help")
                        end
                        -- Help the partner
                        fput("stance offensive")
                        if line:find("Can I") then
                            -- Partner wants to attack us
                            fput("gld stance defensive")
                            put("whisper ooc " .. who .. " Sure! Let's do this!")
                            while true do
                                local line2 = get()
                                if line2:find("All finished with my task") then break end
                                if not GameState.standing then
                                    waitrt()
                                    fput("stand")
                                end
                            end
                        elseif line:find("Can you .* me") then
                            -- Partner wants us to attack them
                            fput("gld stance offensive")
                            put("whisper ooc " .. who .. " Sure! Let's do this!")
                            local attack = "sweep"
                            local atk_match = line:match("Can you (%S+) me")
                            if atk_match then
                                if atk_match == "sweep" then
                                    attack = "sweep"
                                else
                                    attack = "cheapshot " .. atk_match
                                end
                            end
                            while true do
                                waitrt()
                                wait_for_stamina(15)
                                fput(attack .. " " .. who)
                                local line2 = matchtimeout(10, "Again please", "All finished")
                                if line2 and line2:find("All finished") then break end
                            end
                        elseif line:find("promote me in") then
                            local skill_to_promote = line:match("promote me in (.-)%?")
                            fput("gld promote " .. who .. " in " .. (skill_to_promote or ""))
                        end
                        break
                    end
                end
            end
        end
    end
else
    -- Main training loop
    current_task = "Check next task"
    fput("gld stance offensive")
    put_tools_away()
    check_hands()
    move_out_of_room()
    starting_room = GameState.room_id
    if not partner_room_number then
        partner_room_number = GameState.room_id
    end
    if partner_name then
        table.insert(text_to_display, "Your partner: " .. partner_name)
        table.insert(text_to_display, "Partner room: " .. tostring(partner_room_number))
        display_message()
    end
    while true do
        do_next_task()
        pause(0.1)
    end
end
