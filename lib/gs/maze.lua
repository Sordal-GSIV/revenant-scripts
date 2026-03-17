--- Minotaur Maze solver.
--- Ported from the GS mapdb $minotaur_maze_dirs algorithm.
--- Learns room connections by exploration and uses them to navigate
--- toward the target room.  Falls back to random directions when stuck.

local M = {}

-- Persistent learned directions: [room_id] = { [dir] = dest_room_id }
-- Survives across calls so repeated traversals improve.
M.dirs = {}

-- Helpers -----------------------------------------------------------------

local function contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function find_child()
    if bounty and bounty():match("^You have made contact with the child") then
        for _, npc in ipairs(GameObj.npcs()) do
            if npc.noun == "child" then return npc end
        end
    end
    return nil
end

local function wait_for_child(child)
    if not child then return end
    for _ = 1, 50 do
        for _, npc in ipairs(GameObj.npcs()) do
            if npc.id == child.id then return end
        end
        sleep(0.1)
    end
end

--- Solve a maze by exploring until reaching target_id.
--- target_id:  destination room ID (number)
--- maze_rooms: array of room IDs that form the maze
--- Returns true on success.
function M.solve(target_id, maze_rooms)
    while true do
        local child = find_child()
        local start_id = GameState.room_id

        -- Ensure we have an entry for this room
        if not M.dirs[start_id] then
            M.dirs[start_id] = {}
        end

        local room_dirs = M.dirs[start_id]
        local exits = GameState.room_exits()

        -- Pick direction using priority chain:
        -- 1. Known direct exit to target
        -- 2. Unexplored exit (no learned destination yet)
        -- 3. One-hop lookahead (exit leads to room that connects to target)
        -- 4. Random exit
        local dir = nil

        -- 1) Known direct path
        for d, dest in pairs(room_dirs) do
            if dest == target_id then
                dir = d
                break
            end
        end

        -- 2) Unexplored exit
        if not dir then
            for _, d in ipairs(exits) do
                if room_dirs[d] == nil then
                    dir = d
                    break
                end
            end
        end

        -- 3) One-hop lookahead: an exit leads to a room whose exits include target
        if not dir then
            for d, dest in pairs(room_dirs) do
                if M.dirs[dest] then
                    for _, next_dest in pairs(M.dirs[dest]) do
                        if next_dest == target_id then
                            dir = d
                            break
                        end
                    end
                    if dir then break end
                end
            end
        end

        -- 4) Random
        if not dir then
            dir = exits[math.random(#exits)]
        end

        -- Move
        move(dir)
        wait_for_child(child)

        local end_id = GameState.room_id

        -- Learn the connection
        room_dirs[dir] = end_id

        -- Reached target?
        if end_id == target_id then
            return true
        end

        -- Ended up outside the maze? Backtrack.
        if not contains(maze_rooms, end_id) then
            local back = Map.room(end_id)
            if back and back.wayto and back.wayto[tostring(start_id)] then
                local back_dir = back.wayto[tostring(start_id)]
                if type(back_dir) == "string" then
                    move(back_dir)
                    wait_for_child(child)
                elseif type(back_dir) == "function" then
                    back_dir()
                    wait_for_child(child)
                end
            end
        end
    end
end

--- Reset all learned maze state.
function M.reset()
    M.dirs = {}
end

return M
