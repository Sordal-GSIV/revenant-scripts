--- @revenant-script
--- name: task_noloot
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Sleeping Dragon maze task runner without looting
--- tags: maze, sleeping dragon, tasks
---
--- Ported from task-noloot.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;task_noloot   - Run maze tasks without stopping to loot

echo("=== Sleeping Dragon Maze Task (No Loot) ===")
echo("Variant of ;task that skips all looting.")

local maze_path = {
    "south","south","south","south","west","west","west",
    "south","south","south","south","south","go tunnel",
    "east","south","south","southeast","southeast","go tunnel",
    "southwest","southwest","south","south","go tunnel",
    "north","north","go tunnel","north","east","north","west",
    "north","north","north","north","north","north","north",
    "north","north","east","east","east","north","north","north","north",
}

for _, dir in ipairs(maze_path) do
    move(dir)
end

echo("Maze navigation complete (no loot).")
