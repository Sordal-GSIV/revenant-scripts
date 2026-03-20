--- @revenant-script
--- name: tfish
--- version: 1.9.1
--- author: elanthia-online
--- contributors: Tysong
--- game: gs
--- description: Ebon Gate fishing automation with weight cycling and room selection
--- tags: EG,Ebon Gate,fish,fishing
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from Lich5):
---   v1.9.1 (2025-11-03): handle long description fishing poles
---   v1.9.0 (2024-10-10): add default option to trash fish
---   v1.8.7 (2024-10-07): bugfix for Ruby 3.x regex comparisons
---   v1.8.6 (2023-10-01): bugfix caught fish detection
---   v1.8.5 (2023-10-01): bugfix for long description weights
---   v1.8.4 (2023-10-01): Rubocop cleanup, update default weights
---   v1.8.3 (2022-10-13): Toggle silence_me with debug_my_script
---   v1.8.2 (2022-10-06): Update regex matching
---   v1.8.1 (2022-10-06): Add additional container messaging
---   v1.8   (2022-10-05): Initial 2022 EG updates
---   v1.7   (2020-10-18): Add additional get messaging
---   v1.6   (2020-10-13): Fix supplies readout regex
---   v1.5   (2020-10-13): Cleanup on weight cycling
---   v1.4   (2020-10-13): Cleanup when killing script to store supplies
---   v1.3   (2020-10-13): Fixes for lure descriptions (credit: Ziled)
---   v1.2   (2019-10-17): Prone handling, knife container variable
---   v1.1   (2018-10-07): UserVars weight descriptors, seashell cost regex
---   v1.0   (2017-10-08): Initial Release (based on Taleph's 3.3.3)
---
--- Usage:
---   ;tfish       - Start fishing
---   ;tfish help  - Show additional help
---
--- Requires lootsack to be set: ;vars set lootsack=cloak

--------------------------------------------------------------------------------
-- Settings (UserVars-based)
--------------------------------------------------------------------------------

local function init_settings()
    if not UserVars.tfish then UserVars.tfish = {} end
    local s = UserVars.tfish
    if s.pause_me == nil then s.pause_me = true end
    if s.familiar_debug == nil then s.familiar_debug = false end
    if s.debug_my_script == nil then s.debug_my_script = false end
    if s.cast_total == nil then s.cast_total = 0 end
    if s.fish_total == nil then s.fish_total = 0 end
    if s.snap_total == nil then s.snap_total = 0 end
    if s.fish_t5jackpot == nil then s.fish_t5jackpot = 0 end
    if s.client_kill == nil then s.client_kill = false end
    if s.trash_globes == nil then s.trash_globes = false end
    if s.squelch_script == nil then s.squelch_script = true end
    if s.supplies_container == nil then s.supplies_container = "cloak" end
    if s.supplies_bait == nil then s.supplies_bait = "squid" end
    if s.supplies_pole == nil then s.supplies_pole = "rod" end
    if s.supplies_line == nil then s.supplies_line = "wire" end
    if s.fillet_knife == nil then s.fillet_knife = "dagger" end
    if s.knife_container == nil then s.knife_container = "cloak" end
    if s.supplies_buy == nil then s.supplies_buy = true end
    if s.cycle_weights == nil then s.cycle_weights = true end
    if s.weight_noncycle == nil then s.weight_noncycle = "" end
    if s.weight_depths == nil then s.weight_depths = "blown glass weight" end
    if s.weight_bottom == nil then s.weight_bottom = "glaes weight" end
    if s.use_cman == nil then s.use_cman = false end
    if s.supplies_minimum == nil then s.supplies_minimum = 5 end
    if s.cast_timer == nil then s.cast_timer = 60 end
    if s.fav_room == nil then s.fav_room = 0 end
    if s.trash_cut == nil then s.trash_cut = true end
    return s
end

local S = init_settings()

if not S.debug_my_script then silence_me() end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local ROOMS_ENTRANCE = 31834
local ROOMS_FISHING = { [32116] = true, [32117] = true, [32118] = true }
local ROOMS_FISHING_LIST = { 32116, 32117, 32118 }
local FISHING_BOTS = Regex.new("Fishmon|Ilten")

local FISH_REGEX_GOOD = Regex.new(
    "^You manage to stop whatever's on your line"
    .. "|zigzags back and forth wildly"
    .. "|whips back and forth wildly"
    .. "|wavers frantically and makes sharp zigzag"
    .. "|weaves wildly and bends a bit"
    .. "|dips down a bit and proceeds to twitch"
)

local FISH_REGEX_OTHER = Regex.new(
    "dips visibly in a sharp curve"
    .. "|shakes and twitches as its tip bends"
    .. "|bends sharply several times"
    .. "|massive amount of resistance"
    .. "|bends alarmingly as it tugs"
)

local FISH_REGEX_SNAP = Regex.new(
    "Your line suddenly twists and then breaks"
    .. "|^But the " .. S.supplies_pole .. " is already reeled in"
)

local FISH_REGEX_CATCH = Regex.new(
    "one final tug and the .+ comes wriggling to the surface"
)

local FISH_REGEX_COMBINED = Regex.new(
    "brief tug on your line"
    .. "|zigzags back and forth wildly"
    .. "|whips back and forth wildly"
    .. "|wavers frantically"
    .. "|weaves wildly"
    .. "|dips down a bit"
    .. "|dips visibly in a sharp curve"
    .. "|shakes and twitches"
    .. "|bends sharply"
    .. "|massive amount of resistance"
    .. "|bends alarmingly"
)

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

local function count_by_noun(container_noun, item_noun)
    local container = GameObj[container_noun]
    if not container or not container.contents then return 0 end
    local count = 0
    for _, item in ipairs(container.contents) do
        if item.noun == item_noun then count = count + 1 end
    end
    return count
end

local function count_by_name_pattern(container_noun, pattern)
    local container = GameObj[container_noun]
    if not container or not container.contents then return 0 end
    local re = Regex.new(pattern)
    local count = 0
    for _, item in ipairs(container.contents) do
        if re:test(item.name) then count = count + 1 end
    end
    return count
end

local function find_by_name_pattern(container_noun, pattern)
    local container = GameObj[container_noun]
    if not container or not container.contents then return nil end
    local re = Regex.new(pattern)
    for _, item in ipairs(container.contents) do
        if re:test(item.name) then return item end
    end
    return nil
end

local function count_non_bot_pcs()
    local pcs = GameObj.pcs()
    if not pcs then return 0 end
    local count = 0
    for _, pc in ipairs(pcs) do
        if not FISHING_BOTS:test(pc.noun) then count = count + 1 end
    end
    return count
end

local function depth_name(counter)
    if counter == 2 then return "Top"
    elseif counter == 3 then return "Middle"
    else return "Bottom"
    end
end

local function timestamp()
    return os.date("%H:%M:%S")
end

local function fam_debug(msg)
    if S.familiar_debug then
        respond(timestamp() .. " - " .. msg)
    end
end

local function hands_contain(pattern)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rname = rh and rh.name or ""
    local lname = lh and lh.name or ""
    return string.find(rname, pattern, 1, true) or string.find(lname, pattern, 1, true)
end

local function got_item(line)
    if not line then return false end
    return string.find(line, "You remove", 1, true)
        or string.find(line, "You already", 1, true)
        or string.find(line, "You grab", 1, true)
        or string.find(line, "You reach", 1, true)
        or string.find(line, "You retrieve", 1, true)
end

local function cant_get(line)
    if not line then return false end
    return string.find(line, "Get what", 1, true)
        or string.find(line, "Hey, that doesn't", 1, true)
        or string.find(line, "almost certainly a bad idea", 1, true)
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("    SYNTAX - ;tfish")
    respond("")
    respond("      Does NOT automatically sell, as I'm not taking on that responsibility.")
    respond("      You will have to empty your containers via selling/lockering.")
    respond("")
    respond("      Requires your lootsack to be set for bundling seashells and storing loot")
    respond("      ;vars set lootsack=cloak")
    respond("")
    respond("      Defines whether to pause between caught fish. Default set to TRUE")
    respond("      ;e UserVars.tfish.pause_me = true")
    respond("")
    respond("      Send statistic information to familiar window. Default set to FALSE")
    respond("      ;e UserVars.tfish.familiar_debug = false")
    respond("")
    respond("      Enable/Disable use of ;tsquelch script. Default set to TRUE")
    respond("      ;e UserVars.tfish.squelch_script = true")
    respond("")
    respond("      Enable/Disable trashing of cut fish after catching. Default set to TRUE")
    respond("      ;e UserVars.tfish.trash_cut = true")
    respond("")
    respond("      Name of your supplies container. Default set to \"cloak\"")
    respond("      ;e UserVars.tfish.supplies_container = \"cloak\"")
    respond("")
    respond("      Minimum supplies to continue fishing. Default set to 5")
    respond("      ;e UserVars.tfish.supplies_minimum = 5")
    respond("")
    respond("      Type of bait you wish to use. Default set to \"squid\"")
    respond("      ;e UserVars.tfish.supplies_bait = \"squid\"")
    respond("")
    respond("      The noun of your fishing pole. Default set to \"rod\"")
    respond("      ;e UserVars.tfish.supplies_pole = \"rod\"")
    respond("")
    respond("      The noun of your fishing line. Default set to \"wire\"")
    respond("      ;e UserVars.tfish.supplies_line = \"wire\"")
    respond("")
    respond("      The noun of your gutting knife. Default set to \"dagger\"")
    respond("      ;e UserVars.tfish.fillet_knife = \"dagger\"")
    respond("")
    respond("      Name of your knife container. Default set to \"cloak\"")
    respond("      ;e UserVars.tfish.knife_container = \"cloak\"")
    respond("")
    respond("      Enable/Disable automatic cycling of weights. Default set to TRUE")
    respond("      MUST USE EG WEIGHTS IF SET TO TRUE. GLASS & GLAES WEIGHTS ONLY!")
    respond("      ;e UserVars.tfish.cycle_weights = true")
    respond("")
    respond("      To use a constant weight, set the following. Default set to \"\"")
    respond("      If you wish to use a constant weight, make sure cycle_weights is FALSE")
    respond("      ;e UserVars.tfish.weight_noncycle = \"glass\"")
    respond("      ;e UserVars.tfish.weight_noncycle = \"glaes\"")
    respond("")
    respond("      To use different weight descriptors, set the following:")
    respond("      ;e UserVars.tfish.weight_depths = \"blown glass weight\"")
    respond("      ;e UserVars.tfish.weight_bottom = \"glaes weight\"")
    respond("")
    respond("      Enable usage of CMAN SURGE OF STRENGTH. Default set to FALSE")
    respond("      ;e UserVars.tfish.use_cman = false")
    respond("")
    respond("      Cast timer between pulls waiting till bite/nibble. Default set to 60")
    respond("      ;e UserVars.tfish.cast_timer = 60")
    respond("")
    respond("      Script will default to auto-picking least crowded room.")
    respond("      ;e UserVars.tfish.fav_room = 0        -- To autopick")
    respond("      ;e UserVars.tfish.fav_room = 32117    -- Main Entrance")
    respond("      ;e UserVars.tfish.fav_room = 32118    -- Northwest Location")
    respond("      ;e UserVars.tfish.fav_room = 32116    -- Southeast Location")
    respond("")
end

--------------------------------------------------------------------------------
-- Fish fight loop (returns true = caught, false = snap)
--------------------------------------------------------------------------------

local function fish_fight()
    local cast_counter = 1
    local cast_pull = 0
    local tension_counter = 0

    while true do
        waitrt()

        -- Weight cycling
        if cast_counter == 1 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
        elseif cast_counter == 2 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
            local depths_item = find_by_name_pattern(S.supplies_container, S.weight_depths)
            if depths_item then
                fput("get #" .. depths_item.id .. " from my " .. S.supplies_container)
            else
                fput("get my " .. S.weight_depths .. " from my " .. S.supplies_container)
            end
            fput("put my weight on my " .. S.supplies_pole)
        elseif cast_counter == 3 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
            local bottom_item = find_by_name_pattern(S.supplies_container, S.weight_bottom)
            if bottom_item then
                fput("get #" .. bottom_item.id .. " from my " .. S.supplies_container)
            else
                fput("get my " .. S.weight_bottom .. " from my " .. S.supplies_container)
            end
            fput("put my weight on my " .. S.supplies_pole)
            cast_counter = 0
        end

        S.cast_total = S.cast_total + 1
        cast_counter = cast_counter + 1
        fput("raise my " .. S.supplies_pole)

        -- Wait for a bite
        cast_pull = 0
        local line
        while true do
            line = matchtimeout(S.cast_timer, FISH_REGEX_COMBINED)
            if line and FISH_REGEX_COMBINED:test(line) then break end
            line = dothistimeout("pull my " .. S.supplies_pole, 1,
                "Roundtime:", "You reel your", "already reeled in")
            if line and (string.find(line, "You reel", 1, true) or string.find(line, "already reeled in", 1, true)) then
                break
            end
            cast_pull = cast_pull + 1
        end

        -- If reeled in without a fish, try again
        if line and (string.find(line, "You reel", 1, true) or string.find(line, "already reeled in", 1, true)) then
            goto next_cast
        end

        waitrt()

        -- Weigh fish on the pole
        local weigh_line = dothistimeout("weigh my " .. S.supplies_pole, 1,
            "weight is about")
        local pole_fish_weight = nil
        if weigh_line then
            pole_fish_weight = string.match(weigh_line, "weight is about (.-) pounds")
            if pole_fish_weight then
                echo("Fish Weight: " .. pole_fish_weight)
                fam_debug(depth_name(cast_counter) .. " - Fish Weight: " .. pole_fish_weight .. " - Pulls Before Nibble " .. cast_pull)
            end
        end

        waitrt()

        -- CMAN Surge of Strength
        if S.use_cman and Spell[9605]:affordable() and not Spell[9606].active then
            fput("cman surge")
        end

        -- Fish fight
        local pole_tension = 0
        local pole_msg = 0

        while true do
            while true do
                if checkleft() then break end
                local fline = get()
                if fline then
                    if FISH_REGEX_GOOD:test(fline) then
                        pole_tension = pole_tension + 1
                        tension_counter = tension_counter + 1
                        pole_msg = pole_msg + 1
                        if S.debug_my_script then
                            echo("Pull +Tension: " .. pole_tension .. " | Overall Tension " .. tension_counter .. " | Messages " .. pole_msg)
                        end
                    elseif FISH_REGEX_OTHER:test(fline) then
                        pole_msg = pole_msg + 1
                        if S.debug_my_script then
                            echo("Pull Tension: " .. pole_tension .. " | Overall Tension " .. tension_counter .. " | Messages " .. pole_msg)
                        end
                    elseif FISH_REGEX_SNAP:test(fline) then
                        if S.debug_my_script then
                            echo("Snap Tension: " .. pole_tension .. " | Overall Tension " .. tension_counter .. " | Messages " .. pole_msg)
                        end
                        return false
                    elseif FISH_REGEX_CATCH:test(fline) then
                        if S.debug_my_script then
                            echo("Overall Tension " .. tension_counter .. " | Messages " .. pole_msg)
                        end
                        return true
                    end
                end
                if pole_tension > 0 then
                    if S.debug_my_script then
                        echo("Reset Tension: " .. pole_tension .. " | Overall Tension " .. tension_counter .. " | Messages " .. pole_msg)
                    end
                    pole_tension = 0
                    break
                end
            end

            if not ROOMS_FISHING[Room.id] or checkleft() then
                if S.debug_my_script then
                    echo("Overall Pulls " .. tension_counter .. " | Messages Seen " .. pole_msg)
                end
                fam_debug("Overall Pulls " .. tension_counter .. " | Messages Seen " .. pole_msg)
                return true
            end
            waitrt()
            fput("pull my " .. S.supplies_pole)
        end

        ::next_cast::
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args_str = Script.vars[1] or ""
if string.lower(args_str) == "help" then
    show_help()
    return
end

-- Squelch script management
local squelch_script_running = false
if S.squelch_script then
    if not Script.exists("tsquelch") then
        echo("    You need to have ;tsquelch downloaded to squelch.")
        echo("")
        echo("    Either disable squelching variable as shown below, or download tsquelch")
        echo("    ;e UserVars.tfish.squelch_script = false")
        return
    end
    if Script.running("tsquelch") then
        squelch_script_running = true
    else
        Script.run("tsquelch")
    end
end

-- Cleanup on exit
before_dying(function()
    if not squelch_script_running and Script.running("tsquelch") then
        Script.kill("tsquelch")
    end
    if hands_contain(S.supplies_pole) then
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
    end
    if hands_contain("weight") then
        fput("put my weight in my " .. S.supplies_container)
    end
    if hands_contain(S.supplies_bait) then
        fput("put my " .. S.supplies_bait .. " in my " .. S.supplies_container)
    end
    if hands_contain(S.supplies_line) then
        fput("put my " .. S.supplies_line .. " in my " .. S.supplies_container)
    end
    if hands_contain(S.fillet_knife) then
        fput("put my " .. S.fillet_knife .. " in my " .. S.knife_container)
    end
end)

if checkleft() or checkright() then
    echo("Please empty your hands before running this script.")
    return
end

fput("look in my " .. S.supplies_container)
pause(0.5)

-- Main loop
while true do
    -- Check for minimum supplies to continue
    local line_count = count_by_noun(S.supplies_container, S.supplies_line)
    local bait_count = count_by_noun(S.supplies_container, S.supplies_bait)
    local need_supplies = false

    if line_count < 1 then need_supplies = true end
    if bait_count < S.supplies_minimum then need_supplies = true end

    if S.cycle_weights then
        local depths_count = count_by_name_pattern(S.supplies_container, S.weight_depths)
        local bottom_count = count_by_name_pattern(S.supplies_container, S.weight_bottom)
        if depths_count < S.supplies_minimum then need_supplies = true end
        if bottom_count < S.supplies_minimum then need_supplies = true end
    elseif S.weight_noncycle ~= "" then
        local nc_count = count_by_name_pattern(S.supplies_container, S.weight_noncycle .. ".* weight")
        if nc_count < S.supplies_minimum then need_supplies = true end
    end

    if need_supplies then
        echo("YOU NEED MORE SUPPLIES!")
        echo("Fishing Line - " .. S.supplies_line .. " - " .. line_count .. "/1")
        echo("Bait - " .. S.supplies_bait .. " - " .. bait_count .. "/" .. S.supplies_minimum)
        if S.cycle_weights then
            echo(S.weight_depths .. " - " .. count_by_name_pattern(S.supplies_container, S.weight_depths) .. "/" .. S.supplies_minimum)
            echo(S.weight_bottom .. " - " .. count_by_name_pattern(S.supplies_container, S.weight_bottom) .. "/" .. S.supplies_minimum)
        elseif S.weight_noncycle ~= "" then
            echo("Constant Weight - " .. S.weight_noncycle .. " - " .. count_by_name_pattern(S.supplies_container, S.weight_noncycle .. ".* weight") .. "/" .. S.supplies_minimum)
        end
        return
    end

    -- Navigate to entrance if needed
    local all_fishing_and_entrance = { [32116] = true, [32117] = true, [32118] = true, [ROOMS_ENTRANCE] = true }
    if not all_fishing_and_entrance[Room.id] then
        Script.run("go2", tostring(ROOMS_ENTRANCE))
        wait_while(function() return Script.running("go2") end)
    end

    if not all_fishing_and_entrance[Room.id] then
        echo("You aren't at Ebon Gate, you should probably travel there first before running this")
        return
    end

    -- Get pole from container
    local line = dothistimeout("get my " .. S.supplies_pole .. " from my " .. S.supplies_container, 2,
        "You remove", "You already", "You grab", "You reach", "You retrieve",
        "Get what", "Hey, that doesn't", "almost certainly a bad idea")
    if cant_get(line) then
        echo("CAN'T FIND YOUR FISHING POLE, CHECK THAT YOU HAVE THE FOLLOWING:")
        echo("   Fishing Pole: " .. S.supplies_pole)
        echo("   Supplies Container: " .. S.supplies_container)
        echo("")
        echo("   If those aren't correct for your character, please set them using:")
        echo("       ;e UserVars.tfish.supplies_pole = \"pole\"")
        echo("       ;e UserVars.tfish.supplies_container = \"cloak\"")
        return
    elseif not got_item(line) then
        echo("Something bad happened. Error 1")
        return
    end

    -- Check pole state: look for lure
    line = dothistimeout("look on my " .. S.supplies_pole, 2,
        "You see nothing unusual", "currently strung with", "has snapped")
    if line and string.find(line, "You see nothing unusual", 1, true) then
        -- Pole has no lure — need to attach bait
        local bait_line = dothistimeout("get my " .. S.supplies_bait .. " from my " .. S.supplies_container, 2,
            "You remove", "You already", "You grab", "You reach", "You retrieve",
            "Get what", "Hey, that doesn't", "almost certainly a bad idea")
        if cant_get(bait_line) then
            echo("You ran out of bait or have the wrong bait type set to be used by your character")
            echo("")
            echo("Set your bait by doing the following command:")
            echo("  ;e UserVars.tfish.supplies_bait = \"ragworm\"")
            fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
            return
        elseif not got_item(bait_line) then
            echo("Something bad happened. Error 3")
            return
        end
        fput("put my " .. S.supplies_bait .. " on my " .. S.supplies_pole)

    elseif line and string.find(line, "has snapped", 1, true) then
        -- Line snapped — replace line, add bait, optionally add weight
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
        fput("get my " .. S.supplies_line .. " from my " .. S.supplies_container)
        fput("pull my " .. S.supplies_line)
        fput("put my second " .. S.supplies_line .. " in my " .. S.supplies_container)
        fput("get my " .. S.supplies_pole .. " from my " .. S.supplies_container)
        fput("put my " .. S.supplies_line .. " on my " .. S.supplies_pole)
        fput("get my " .. S.supplies_bait .. " from my " .. S.supplies_container)
        fput("put my " .. S.supplies_bait .. " on my " .. S.supplies_pole)
        if not S.cycle_weights and S.weight_noncycle ~= "" then
            fput("get my " .. S.weight_noncycle .. " weight from my " .. S.supplies_container)
            fput("put my weight on my " .. S.supplies_pole)
        end

    elseif line and string.find(line, "currently strung with", 1, true) then
        -- Pole has lure — check weight status
        local weight_line = dothistimeout("look on my " .. S.supplies_pole, 2, "as a weight")

        if (S.cycle_weights or S.weight_noncycle == "") and weight_line and string.find(weight_line, "as a weight", 1, true) then
            -- Remove weight (will be cycled during fishing, or no constant weight set)
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
        elseif (not S.cycle_weights and S.weight_noncycle ~= "") and weight_line and string.find(weight_line, "as a weight", 1, true) then
            -- Check if the current weight is the desired non-cycle weight
            if not string.find(weight_line, S.weight_noncycle, 1, true) then
                fput("get weight from my " .. S.supplies_pole)
                fput("put my weight in my " .. S.supplies_container)
                fput("get my " .. S.weight_noncycle .. " weight from my " .. S.supplies_container)
                fput("put my weight on my " .. S.supplies_pole)
            end
        end
    else
        echo("Something bad happened. Error 2")
        return
    end

    -- Navigate to fishing room if not already there
    if not ROOMS_FISHING[Room.id] then
        -- Stand up first
        while not standing() do
            fput("stand")
            if dead() then return end
        end

        line = dothistimeout("go dock", 2,
            "do not have enough soul shards to enter the dock",
            "It will cost 50 soul shards")

        if line and string.find(line, "do not have enough soul shards", 1, true) then
            echo("You need to redeem more soul shards!")
            fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
            return
        elseif line and string.find(line, "It will cost 50 soul shards", 1, true) then
            fput("go dock")

            if S.fav_room == 0 then
                -- Auto-pick least crowded room
                local room_crowded = {}
                for _, room_id in ipairs(ROOMS_FISHING_LIST) do
                    Script.run("go2", tostring(room_id))
                    wait_while(function() return Script.running("go2") end)
                    room_crowded[room_id] = count_non_bot_pcs()
                end

                -- Find least crowded
                local best_room = ROOMS_FISHING_LIST[1]
                local best_count = room_crowded[best_room]
                for _, room_id in ipairs(ROOMS_FISHING_LIST) do
                    if room_crowded[room_id] < best_count then
                        best_room = room_id
                        best_count = room_crowded[room_id]
                    end
                end

                Script.run("go2", tostring(best_room))
                wait_while(function() return Script.running("go2") end)
            else
                Script.run("go2", tostring(S.fav_room))
                wait_while(function() return Script.running("go2") end)
            end
        else
            echo("Something bad happened. Error 4")
            return
        end
    end

    -- Fish!
    if fish_fight() then
        pause(1)
        waitrt()
        local fish_obj = GameObj.left_hand()
        local fish_name = fish_obj and fish_obj.name or "unknown"
        S.fish_total = S.fish_total + 1
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)

        -- Weigh the caught fish
        local fish_weight = "?"
        local weigh_line = dothistimeout("weigh my " .. checkleft(), 2, "weight is about")
        if weigh_line then
            local w = string.match(weigh_line, "weight is about (.*) pounds")
            if w then
                echo(weigh_line)
                echo(w)
                fish_weight = w
            end
        end
        pause(1)
        waitrt()
        pause(0.25)

        -- Fillet the fish
        fput("get my " .. S.fillet_knife .. " from my " .. S.knife_container)
        line = dothistimeout("cut my " .. checkleft(), 2, "Roundtime", "probably deserves a close inspection")
        if line and string.find(line, "close inspection", 1, true) then
            echo("ALERT ALERT ALERT ALERT ALERT ALERT ALERT")
            echo("ALERT ALERT ALERT ALERT ALERT ALERT ALERT")
            echo("")
            echo("     POSSIBLE T5+ FOUND, LOOK AT ME!")
            echo("")
            echo("ALERT ALERT ALERT ALERT ALERT ALERT ALERT")
            echo("ALERT ALERT ALERT ALERT ALERT ALERT ALERT")
            pause_script()
        end
        pause(1)
        waitrt()
        pause(0.25)

        -- Trash cut fish remains if enabled
        if S.trash_cut then
            local loot = GameObj.loot()
            for _, item in ipairs(loot) do
                if item.noun == "fish" then
                    fput("trash #" .. item.id)
                    break
                end
            end
        end

        -- Get info about item found inside the fish
        local item_obj = GameObj.left_hand()
        local item_name = item_obj and item_obj.name or "unknown"
        fput("put my " .. S.fillet_knife .. " in my " .. S.knife_container)

        -- Analyze and inspect the found item, then store it
        if checkleft() then
            local left_noun = checkleft()
            multifput("analyze my " .. left_noun, "inspect my " .. left_noun,
                "look at my " .. left_noun, "look in my " .. left_noun)
            fput("put my " .. left_noun .. " in my " .. (Vars.lootsack or "cloak"))
        end

        fam_debug(S.fish_total .. "/" .. S.cast_total .. " - " .. fish_name .. "(" .. item_name .. ") - " .. fish_weight .. "#s")

        if S.pause_me then pause_script() end
    else
        S.snap_total = S.snap_total + 1
        fam_debug("*SNAP*")
        waitrt()
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
    end
end
