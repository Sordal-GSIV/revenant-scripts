--- @revenant-script
--- name: sewers_shat
--- version: 1.8.1
--- author: Tysong
--- contributors: Omrii
--- game: gs
--- tags: sewer, duskruin, bloodscrip, automation
--- description: Duskruin sewers automation - navigate, search, collect loot
---
--- Original Lich5 authors: Tysong, Omrii
--- Ported to Revenant Lua from sewers_shat.lic v1.8
--- @lic-certified: complete 2026-03-20
---
--- Usage:
---   ;sewers_shat <loot_container>
---   ;sewers_shat <loot_container> speed
---   ;sewers_shat help
---
--- Changelog (Revenant port):
---   1.8.1: Full audit — fixed Script.vars, checkpaths, sleep, waitfor, movement
---          loop logic, movement_fix recovery, mind-state rest room, GSF cache load

local REVERSE = {
    north="south", south="north", east="west", west="east",
    northeast="southwest", northwest="southeast",
    southeast="northwest", southwest="northeast",
}

local ALL_DIRS = {
    "north", "south", "east", "west",
    "northeast", "northwest", "southeast", "southwest",
}

local function show_help()
    respond("--")
    respond("-- This script runs the sewers event in Duskruin Arena.")
    respond("-- Start standing at the sewer entrance (grate).")
    respond("-- Runs continuously, storing loot and waiting for mind state.")
    respond("--")
    respond("-- Syntax:  ;sewers_shat <storage_container> [speed]")
    respond("-- Example: ;sewers_shat rucksack")
    respond("--")
    respond("-- Options:")
    respond("--   speed  - ignore mind state, run without resting")
    respond("--")
end

local arg1 = Script.vars[1]
local arg2 = Script.vars[2]

if not arg1 or arg1:lower() == "help" then
    show_help()
    return
end

local container_noun = arg1:lower()

-- Find the container in inventory
local storage_container = nil
for _, item in ipairs(GameObj.inv()) do
    if item.noun == container_noun then
        storage_container = item
        break
    end
end

if not storage_container then
    respond("** Can't find '" .. container_noun .. "' in your inventory, exiting!")
    respond("** Run ;sewers_shat help for usage.")
    return
end

local last_dir = nil

local function standing_up()
    while not standing() do
        fput("stand")
        pause(0.5)
    end
end

-- Stow both hands into storage_container; exit if overloaded
local function storage()
    local lh = GameObj.left_hand()
    if lh and lh.id then
        fput("_drag #" .. lh.id .. " #" .. storage_container.id)
        for _ = 1, 20 do
            if not GameObj.left_hand() then break end
            pause(0.1)
        end
        if GameObj.left_hand() then
            respond("** You are overloaded — can't stow left hand. Please address.")
            exit()
        end
    end
    local rh = GameObj.right_hand()
    if rh and rh.id then
        fput("_drag #" .. rh.id .. " #" .. storage_container.id)
        for _ = 1, 20 do
            if not GameObj.right_hand() then break end
            pause(0.1)
        end
        if GameObj.right_hand() then
            respond("** You are overloaded — can't stow right hand. Please address.")
            exit()
        end
    end
end

-- Returns true if the current map room has the given tag
local function room_has_tag(tag)
    local room_id = Room.id
    if not room_id then return false end
    local r = Map.find_room(room_id)
    if not r then return false end
    local tag_lower = tag:lower()
    for _, t in ipairs(r.tags) do
        if t:lower() == tag_lower then return true end
    end
    return false
end

-- Move in a smart random direction (avoid backtracking).
-- Returns "moved", "exited" (reached Bloodriven Village), or "stuck".
local function movement()
    local dirs = GameState.room_exits
    if type(dirs) ~= "table" or #dirs == 0 then return "stuck" end
    -- Filter out the direction we came from unless it's the only option
    if #dirs > 1 and last_dir then
        local filtered = {}
        for _, d in ipairs(dirs) do
            if d ~= last_dir then filtered[#filtered + 1] = d end
        end
        if #filtered > 0 then dirs = filtered end
    end
    local chosen = dirs[math.random(#dirs)]
    last_dir = REVERSE[chosen]  -- nil for non-cardinal dirs (up/down/out), fine
    local ok = pcall(move, chosen)
    if not ok then return "stuck" end
    if (GameState.room_name or ""):find("Bloodriven") then return "exited" end
    return "moved"
end

-- Recovery: try all 8 cardinal directions when movement() returns "stuck".
-- Returns "moved", "exited", or "stuck".
local function movement_fix()
    for _, d in ipairs(ALL_DIRS) do
        local ok = pcall(move, d)
        if ok then
            if (GameState.room_name or ""):find("Bloodriven") then return "exited" end
            return "moved"
        end
    end
    return "stuck"
end

-- Main loop: run sewers until out of entry tokens
while true do
    -- Wait for mind state to drop below 75% (unless speed mode)
    if not arg2 then
        local mind = GameState.mind or ""
        if mind:lower():find("saturated") or mind:lower():find("must rest") then
            -- Navigate to Bloodriven waiting area to absorb
            if Room.id ~= 8214601 then
                Script.run("go2", "u8214601 --disable-confirm")
                pause(1)
            end
            echo("Waiting to absorb experience.")
            wait_until(function() return (GameState.mind_value or 0) < 75 end)
            echo("3...")
            pause(1)
            echo("2...")
            pause(1)
            echo("1...")
            pause(1)
            echo("Starting the next sewers run, pay attention!!!")
        end
    end

    -- Navigate to sewer entrance if not already in a sewer room
    if not room_has_tag("sewer") then
        Script.run("go2", "u8214001 --disable-confirm")
        pause(1)
    end

    -- Enter the sewers through the grate
    local entered = pcall(move, "go grate")
    if not entered then
        respond("** Out of entry tokens — script ending.")
        break
    end

    -- Per-room navigation and search loop
    local run_complete = false
    while not run_complete do
        standing_up()

        -- Move to a new room
        local move_result = movement()
        if move_result == "stuck" then
            move_result = movement_fix()
        end

        if move_result == "exited" then
            run_complete = true
            break
        end

        if move_result == "stuck" then
            respond("**")
            respond("** The script has failed to move within the sewers due to an unknown situation.")
            respond("** You will need to manually complete this sewer run.")
            respond("** Contact the script author if this error occurs consistently.")
            respond("**")
            exit()
        end

        -- Search the room for loot
        local search_result = dothistimeout("search", 2,
            "Roundtime",
            "You get washed away",
            "You've recently",
            "You don't find anything of interest here",
            "You search around and find an odd gem!")

        if not search_result
           or search_result:find("washed away")
           or search_result:find("don't find anything of interest") then
            run_complete = true
            break
        end

        waitrt()
        pause(0.5)
        storage()
        pause(0.1)
    end

    -- Clean up and exit sewers
    storage()
    standing_up()
    pause(0.5)
    waitrt()
    pcall(move, "climb rope")
    pcall(move, "out")

    -- GS Free-to-Play: navigate to cache segment to receive announcement
    local game = GameState.game or ""
    if game:match("GSF") then
        Script.run("go2", "u8212637 --disable-confirm")
        pause(2)
    end
end

echo("Script has ended.")
