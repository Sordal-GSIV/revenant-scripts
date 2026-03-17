--- @revenant-script
--- name: task
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Sleeping Dragon maze task runner - navigates maze paths for non-combat tasks
--- tags: maze, sleeping dragon, tasks, navigation
---
--- Ported from task.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;task   - Run non-combat tasks in the Sleeping Dragon maze
---
--- Start from the room 3 east of the maze entrance.
--- Requires: common, drinfomon, textsubs, common-travel, events, common-items

local maze_path = {
    "south","south","south","south","west","west","west",
    "south","south","south","south","south","go tunnel",
    "east","south","south","southeast","southeast","go tunnel",
    "southwest","southwest","south","south","go tunnel",
    "north","north","go tunnel","north","east","north","west",
    "north","north","north","north","north","north","north",
    "north","north","east","east","east","north","north","north","north",
}

local mice_path = {
    "east","east","south","west","east","south","west","west",
    "south","west","north","north","west","west","south","south",
    "east","north","east","south","east","south","west","west","west",
    "south","south","south","south","south","go tunnel",
    "east","south","south","southeast","southeast","go tunnel",
    "southwest","southwest","south","south","go tunnel",
    "north","north","go tunnel","north","east","north","west",
    "north","north","north","north","north","north","north",
    "north","north","east","east","east","north","north","north","north",
}

local scream_path = {
    "scream","south","south","south","south","west","west","west",
    "south","south","south","south","south","go tunnel","scream",
    "east","south","south","southeast","southeast","northeast",
    "northeast","go tunnel","scream","go tunnel","southwest",
    "southwest","go tunnel","scream","southwest","southwest",
    "south","south","go tunnel","scream","north","north","go tunnel",
    "north","east","north","west","north","north","north","north",
    "north","north","north","north","north","east","east","east",
    "north","north","north","north",
}

local function walk_path(path)
    for _, dir in ipairs(path) do
        if dir == "loot" then
            fput("loot")
            pause(0.5)
        elseif dir == "scream" then
            fput("scream")
            pause(1)
        else
            move(dir)
        end
    end
end

echo("=== Sleeping Dragon Maze Task Runner ===")
echo("Start from 3 rooms east of entrance.")
echo("Running maze path...")

walk_path(maze_path)
echo("Maze path complete!")
