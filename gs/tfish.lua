--- @revenant-script
--- name: tfish
--- version: 1.9.1
--- author: elanthia-online
--- contributors: Tysong
--- game: gs
--- description: Ebon Gate fishing automation with weight cycling and room selection
--- tags: EG,Ebon Gate,fish,fishing
---
--- Changelog (from Lich5):
---   v1.9.1 (2025-11-03): handle long description fishing poles
---   v1.9.0 (2024-10-10): add default option to trash fish
---   v1.8.7 (2024-10-07): bugfix for Ruby 3.x regex comparisons
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
local ROOMS_FISHING2 = { [27578] = true, [27579] = true, [27580] = true }

local FISH_REGEX_GOOD = Regex.new(
    "^You manage to stop whatever's on your line" ..
    "|zigzags back and forth wildly" ..
    "|whips back and forth wildly" ..
    "|wavers frantically and makes sharp zigzag" ..
    "|weaves wildly and bends a bit" ..
    "|dips down a bit and proceeds to twitch"
)

local FISH_REGEX_OTHER = Regex.new(
    "dips visibly in a sharp curve" ..
    "|shakes and twitches as its tip bends" ..
    "|bends sharply several times" ..
    "|massive amount of resistance" ..
    "|bends alarmingly as it tugs"
)

local FISH_REGEX_SNAP = Regex.new(
    "Your line suddenly twists and then breaks" ..
    "|^But the " .. S.supplies_pole .. " is already reeled in"
)

local FISH_REGEX_CATCH = Regex.new(
    "one final tug and the .+ comes wriggling to the surface"
)

local FISH_REGEX_COMBINED = Regex.new(
    "brief tug on your line" ..
    "|zigzags back and forth wildly" ..
    "|whips back and forth wildly" ..
    "|wavers frantically" ..
    "|weaves wildly" ..
    "|dips down a bit" ..
    "|dips visibly in a sharp curve" ..
    "|shakes and twitches" ..
    "|bends sharply" ..
    "|massive amount of resistance" ..
    "|bends alarmingly"
)

local FISH_REEL_DONE = Regex.new(
    "You reel your .+ in completely" ..
    "|^But the " .. S.supplies_pole .. " is already reeled in"
)

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("  TFISH - Ebon Gate Fishing Script")
    respond("")
    respond("  Settings (use ;e UserVars.tfish.KEY = VALUE):")
    respond("    pause_me           = " .. tostring(S.pause_me) .. " (pause between caught fish)")
    respond("    supplies_container = " .. S.supplies_container)
    respond("    supplies_bait      = " .. S.supplies_bait)
    respond("    supplies_pole      = " .. S.supplies_pole)
    respond("    supplies_line      = " .. S.supplies_line)
    respond("    fillet_knife       = " .. S.fillet_knife)
    respond("    knife_container    = " .. S.knife_container)
    respond("    cycle_weights      = " .. tostring(S.cycle_weights))
    respond("    weight_depths      = " .. S.weight_depths)
    respond("    weight_bottom      = " .. S.weight_bottom)
    respond("    use_cman           = " .. tostring(S.use_cman))
    respond("    supplies_minimum   = " .. tostring(S.supplies_minimum))
    respond("    cast_timer         = " .. tostring(S.cast_timer))
    respond("    fav_room           = " .. tostring(S.fav_room))
    respond("    trash_cut          = " .. tostring(S.trash_cut))
    respond("")
end

--------------------------------------------------------------------------------
-- Fish fight loop (returns true = caught, false = snap)
--------------------------------------------------------------------------------

local function fish_fight()
    local cast_counter = 1
    local cast_pull = 0

    while true do
        waitrt()

        -- Weight cycling
        if cast_counter == 1 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
        elseif cast_counter == 2 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
            -- Get depths weight
            fput("get my " .. S.weight_depths .. " from my " .. S.supplies_container)
            fput("put my weight on my " .. S.supplies_pole)
        elseif cast_counter == 3 and S.cycle_weights then
            fput("get weight from my " .. S.supplies_pole)
            fput("put my weight in my " .. S.supplies_container)
            fput("get my " .. S.weight_bottom .. " from my " .. S.supplies_container)
            fput("put my weight on my " .. S.supplies_pole)
            cast_counter = 0
        end

        S.cast_total = S.cast_total + 1
        cast_counter = cast_counter + 1
        fput("raise my " .. S.supplies_pole)

        -- Wait for a bite
        local line
        while true do
            line = matchtimeout(S.cast_timer, FISH_REGEX_COMBINED)
            if line and FISH_REGEX_COMBINED:test(line) then break end
            line = dothistimeout("pull my " .. S.supplies_pole, 1,
                "Roundtime:|" .. FISH_REEL_DONE.pattern)
            if line and FISH_REEL_DONE:test(line) then break end
            cast_pull = cast_pull + 1
        end

        -- If reeled in without a fish, try again
        if line and FISH_REEL_DONE:test(line) then goto next_cast end

        waitrt()
        -- Weigh the fish on the pole
        dothistimeout("weigh my " .. S.supplies_pole, 1,
            "You carefully examine the .* and determine that the weight is about")

        waitrt()

        -- Fish fight
        local pole_tension = 0
        while true do
            -- Read messages until we need to pull
            while true do
                if checkleft() then break end
                local fline = get()
                if fline then
                    if FISH_REGEX_GOOD:test(fline) then
                        pole_tension = pole_tension + 1
                    elseif FISH_REGEX_SNAP:test(fline) then
                        return false
                    elseif FISH_REGEX_CATCH:test(fline) then
                        return true
                    end
                end
                if pole_tension > 0 then
                    pole_tension = 0
                    break
                end
            end
            if not ROOMS_FISHING[Room.id] or checkleft() then
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

-- Cleanup on exit
before_dying(function()
    local rh = checkright() or ""
    local lh = checkleft() or ""
    if string.find(rh .. lh, S.supplies_pole) then
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
    end
    if string.find(rh .. lh, "weight") then
        fput("put my weight in my " .. S.supplies_container)
    end
end)

if checkleft() or checkright() then
    echo("Please empty your hands before running this script.")
    return
end

-- Main loop
while true do
    -- Check supplies
    fput("look in my " .. S.supplies_container)
    pause(0.5)

    -- Navigate to entrance if needed
    if not ROOMS_FISHING[Room.id] and Room.id ~= ROOMS_ENTRANCE then
        Script.run("go2", tostring(ROOMS_ENTRANCE))
        wait_while(function() return Script.running("go2") end)
    end

    -- Get pole
    local line = dothistimeout("get my " .. S.supplies_pole .. " from my " .. S.supplies_container, 2,
        "You remove|You already|You grab|You reach|You retrieve|Get what|Hey, that doesn't")
    if line and Regex.test(line, "Get what|Hey, that doesn't") then
        echo("CAN'T FIND YOUR FISHING POLE")
        echo("  Pole: " .. S.supplies_pole)
        echo("  Container: " .. S.supplies_container)
        return
    end

    -- Check/setup pole
    line = dothistimeout("look on my " .. S.supplies_pole, 2,
        "You see nothing unusual|currently strung with|line .* has snapped")
    if line and string.find(line, "You see nothing unusual") then
        -- Need bait
        dothistimeout("get my " .. S.supplies_bait .. " from my " .. S.supplies_container, 2,
            "You remove|Get what")
        fput("put my " .. S.supplies_bait .. " on my " .. S.supplies_pole)
    elseif line and string.find(line, "has snapped") then
        -- Need new line
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
        fput("get my " .. S.supplies_line .. " from my " .. S.supplies_container)
        fput("pull my " .. S.supplies_line)
        fput("put my second " .. S.supplies_line .. " in my " .. S.supplies_container)
        fput("get my " .. S.supplies_pole .. " from my " .. S.supplies_container)
        fput("put my " .. S.supplies_line .. " on my " .. S.supplies_pole)
        fput("get my " .. S.supplies_bait .. " from my " .. S.supplies_container)
        fput("put my " .. S.supplies_bait .. " on my " .. S.supplies_pole)
    end

    -- Navigate to fishing room
    if not ROOMS_FISHING[Room.id] then
        dothistimeout("go dock", 2,
            "do not have enough soul shards|It will cost 50 soul shards")
        fput("go dock")
        if S.fav_room ~= 0 then
            Script.run("go2", tostring(S.fav_room))
            wait_while(function() return Script.running("go2") end)
        else
            Script.run("go2", "32117")
            wait_while(function() return Script.running("go2") end)
        end
    end

    -- Fish!
    if fish_fight() then
        pause(1)
        waitrt()
        S.fish_total = S.fish_total + 1
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)

        dothistimeout("weigh my " .. checkleft(), 2,
            "You carefully examine")
        pause(1)
        waitrt()

        -- Fillet
        fput("get my " .. S.fillet_knife .. " from my " .. S.knife_container)
        line = dothistimeout("cut my " .. checkleft(), 2, "Roundtime|probably deserves a close inspection")
        if line and string.find(line, "close inspection") then
            echo("ALERT! POSSIBLE T5+ FOUND!")
            pause_script()
        end
        pause(1)
        waitrt()

        fput("put my " .. S.fillet_knife .. " in my " .. S.knife_container)
        if checkleft() then
            fput("put my " .. checkleft() .. " in my " .. (Vars.lootsack or "cloak"))
        end

        if S.pause_me then pause_script() end
    else
        S.snap_total = S.snap_total + 1
        waitrt()
        fput("put my " .. S.supplies_pole .. " in my " .. S.supplies_container)
    end
end
