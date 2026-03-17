--- @revenant-script
--- name: sewers_shat
--- version: 1.8.0
--- author: Tysong
--- game: gs
--- tags: sewer, duskruin, bloodscrip, automation
--- description: Duskruin sewers automation - navigate, search, collect loot
---
--- Original Lich5 authors: Tysong, Omrii
--- Ported to Revenant Lua from sewers_shat.lic v1.8
---
--- Usage:
---   ;sewers_shat <loot_container>
---   ;sewers_shat <loot_container> speed
---   ;sewers_shat help

local REVERSE = { n="s", s="n", e="w", w="e", ne="sw", nw="se", se="nw", sw="ne" }

local function show_help()
    respond("-- This script runs the sewers event in Duskruin Arena.")
    respond("-- Syntax: ;sewers_shat <storage_container> [speed]")
    respond("-- Example: ;sewers_shat rucksack")
    respond("-- speed option ignores mind state")
end

local arg1 = Script.current.vars[1]
local arg2 = Script.current.vars[2]

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
    echo("can't find " .. container_noun .. " in your inventory containers, exiting!")
    show_help()
    return
end

local last_dir = nil

local function standing_up()
    while not standing() do
        fput("stand")
    end
end

local function movement()
    local dirs = checkpaths() or {}
    if #dirs > 1 and last_dir then
        local filtered = {}
        for _, d in ipairs(dirs) do
            if d ~= last_dir then filtered[#filtered + 1] = d end
        end
        if #filtered > 0 then dirs = filtered end
    end
    local chosen = dirs[math.random(#dirs)]
    last_dir = REVERSE[chosen]
    move(chosen)
end

local function storage()
    if GameObj.left_hand() and GameObj.left_hand().id then
        fput("_drag #" .. GameObj.left_hand().id .. " #" .. storage_container.id)
        for _ = 1, 20 do
            if not GameObj.left_hand().id then break end
            wait(0.1)
        end
    end
    if GameObj.right_hand() and GameObj.right_hand().id then
        fput("_drag #" .. GameObj.right_hand().id .. " #" .. storage_container.id)
        for _ = 1, 20 do
            if not GameObj.right_hand().id then break end
            wait(0.1)
        end
    end
end

while true do
    -- Wait for mind state if not speed mode
    if not arg2 and Regex.test(checkmind() or "", "saturated|must rest") then
        echo("Waiting to absorb experience.")
        wait_until(function() return percentmind() < 75 end)
        echo("Starting the next sewers run!")
    end

    -- Navigate to sewer entrance if needed
    if not Room.current.tags_include("sewer") then
        Script.run("go2", "u8214001 --disable-confirm")
        wait(1)
    end

    local entered = move("go grate")
    if not entered then
        echo("Out of entry tokens!")
        break
    end

    while true do
        standing_up()
        movement()
        local result = waitfor("You can't go there|Bloodriven Village")
        wait(0.5)
        if not Regex.test(result, "can't go") then
            -- Made it through
        end

        local search_result = dothistimeout("search", 2,
            "Roundtime|You get washed away|You've recently|You don't find anything|You search around and find")
        if search_result and Regex.test(search_result, "get washed|You don't find anything") then
            break
        end
        waitrt()
        wait(0.5)
        storage()
        wait(0.1)
    end

    storage()
    standing_up()
    wait(0.5)
    waitrt()
    move("climb rope")
    move("out")
end

echo("Script has ended.")
