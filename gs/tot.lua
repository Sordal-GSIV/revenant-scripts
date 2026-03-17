--- @revenant-script
--- name: tot
--- version: 1.0.0
--- author: Alastir
--- game: gs
--- description: Trick or Treat automation - candy bag purchasing and door-to-door hunting
--- tags: halloween, trick or treat, event
---
--- Usage: ;tot (start at room #31980)
--- Requires: Vars.lootsack set, bigshot configured
---
--- Uses ;bigshot quick for combat. Start with combat gear in hands.

respond("ToT (Trick or Treat) by Alastir")
respond("Vars.lootsack = " .. (Vars.lootsack or "not set"))
respond("Unpause when ready to start.")
pause_script()

local STARTING_LOCATIONS = {"32033","32038","32026","32029","32000","32009","31990"}

local function handle_combat()
    if GameObj.targets and #GameObj.targets > 0 then
        Script.start("bigshot", "quick")
        wait_while(function() return Script.running("bigshot") end)
        waitrt()
    end
end

local function knock_door()
    local result = dothistimeout("knock", 5, "door opens|no answer|already open")
    if result and result:match("door opens") then
        move("go door")
        handle_combat()
        -- Loot anything on the ground
        fput("loot room")
        waitrt()
        -- Return outside
        move("out")
    end
end

local function go_to_start()
    local loc = STARTING_LOCATIONS[math.random(#STARTING_LOCATIONS)]
    Script.run("go2", loc)
end

-- Main loop
while true do
    if GameObj.targets and #GameObj.targets > 0 then
        handle_combat()
    end

    -- Try to knock on doors in current room
    knock_door()
    pause(1)

    -- Move to next location
    if checkpaths() then
        walk()
    else
        go_to_start()
    end
end
