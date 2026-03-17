--- @revenant-script
--- name: task_loot
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Sleeping Dragon maze task runner with looting enabled
--- tags: maze, sleeping dragon, tasks, loot
---
--- Ported from task-loot.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;task_loot   - Run maze tasks with looting at checkpoints

echo("=== Sleeping Dragon Maze Task (Loot) ===")
echo("This is a variant of ;task with looting enabled at each checkpoint.")
echo("Start from 3 rooms east of the maze entrance.")

-- Same as task.lua but with $looting = true
-- Uses the full_path which includes 'loot' commands at each stop

local full_path = {
    "west","west","west","east","east","east","loot",
    "south","east","west","north","east","east","east","east",
    "southwest","north","west","south","loot",
    "south","loot",
    "southwest","north","west","south","west","north","loot",
    "north","west","west","south","loot",
    "south","east","north","east","south","east","south","west","loot",
    "west","west","south","east","east","loot",
    "west","south","north","west","south","south","south","loot",
    "south","south","south","south","loot",
}

local function walk_path(path)
    for _, dir in ipairs(path) do
        if dir == "loot" then
            fput("loot")
            pause(1)
            -- Pick up any items
            while true do
                local r = DRC.bput("get coin", {"You pick up", "What were you"})
                if r:find("What") then break end
            end
        else
            move(dir)
        end
    end
end

walk_path(full_path)
echo("Maze task with looting complete!")
