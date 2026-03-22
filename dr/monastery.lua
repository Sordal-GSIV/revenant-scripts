--- @revenant-script
--- name: monastery
--- version: 1.0
--- author: Kaldonis
--- game: gs
--- description: Solves the Monastery puzzle using a familiar (Voln, spell 920).
--- tags: go2, travel, voln, familiar, puzzle
--- Converted from monastery.lic
---
--- Usage:
---   ;monastery
---
--- Workflow:
---   1) Waits for you to get a familiar (Spell 920 active)
---   2) Has the familiar follow you
---   3) Runs to room 6486 (outside the monastery door)
---   4) Tells the familiar to navigate the monastery and retrieve 4 rocks
---   5) Familiar returns when done

echo("Waiting until you get a familiar")
waitfor("You sense that a familiar")

fput("tell familiar follow")

-- Navigate to room 6486 (right outside the door)
start_script("go2", {"6486"})
wait_while(function() return running("go2") end)

-- Path into the monastery and to the rock chamber
local function send_familiar_to_rocks()
    fput("TELL FAMILIAR GO DOOR")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO SOUTH")
    fput("TELL FAMILIAR GO ARCH")
    fput("TELL FAMILIAR GO NORTHEAST")
    fput("TELL FAMILIAR GO EAST")
    fput("TELL FAMILIAR GO PRIVY")
    fput("TELL FAMILIAR GO HOLE")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO SOUTHWEST")
    fput("TELL FAMILIAR GO IRON DOOR")
    fput("TELL FAMILIAR GO STEEL DOOR")
    fput("TELL FAMILIAR GO BRONZE DOOR")
    fput("TELL FAMILIAR GO COPPER DOOR")
end

-- Return path from rock chamber to drop point
local function send_familiar_to_dropoff()
    fput("TELL FAMILIAR GO COPPER DOOR")
    fput("TELL FAMILIAR GO BRONZE DOOR")
    fput("TELL FAMILIAR GO STEEL DOOR")
    fput("TELL FAMILIAR GO IRON DOOR")
    fput("TELL FAMILIAR GO NORTHEAST")
    fput("TELL FAMILIAR GO EAST")
    fput("TELL FAMILIAR GO EAST")
    fput("TELL FAMILIAR GO SOUTH")
    fput("TELL FAMILIAR GO EAST")
    fput("TELL FAMILIAR GO EAST")
    fput("TELL FAMILIAR GO SOUTHEAST")
end

-- Return path from drop point back to rock chamber
local function send_familiar_back_to_rocks()
    fput("TELL FAMILIAR GO NORTHWEST")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO NORTH")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO WEST")
    fput("TELL FAMILIAR GO SOUTHWEST")
    fput("TELL FAMILIAR GO IRON DOOR")
    fput("TELL FAMILIAR GO STEEL DOOR")
    fput("TELL FAMILIAR GO BRONZE DOOR")
    fput("TELL FAMILIAR GO COPPER DOOR")
end

-- First rock: go all the way in from the door
send_familiar_to_rocks()
fput("TELL FAMILIAR GET ROCK")
send_familiar_to_dropoff()
fput("TELL FAMILIAR DROP ROCK")

-- Rocks 2-4: go back from drop point to rock chamber
for _ = 2, 4 do
    send_familiar_back_to_rocks()
    fput("TELL FAMILIAR GET ROCK")
    send_familiar_to_dropoff()
    fput("TELL FAMILIAR DROP ROCK")
end

fput("TELL FAMILIAR RETURN")
