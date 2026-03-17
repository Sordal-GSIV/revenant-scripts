--- Elemental Confluence zone navigation handler.
--- Ported from the GS mapdb room 23282 self-referencing wayto algorithm.
--- Navigates the hot/cold room grid, tracking exits, pits, and tranquility points.

local M = {}

-- Hot rooms (fire/lava side of the Confluence)
M.hot_rooms = {
    23282, 23283, 23284, 23285, 23286, 23287, 23288, 23289,
    23290, 23291, 23292, 23293, 23294, 23295, 23296, 23297,
    23298, 23299, 23300, 23301, 23302, 23303, 23329, 23330,
    23331, 23332, 23333, 23334,
}

-- Cold rooms (ice side of the Confluence)
M.cold_rooms = {
    23304, 23305, 23306, 23307, 23308, 23309, 23310, 23311,
    23312, 23313, 23314, 23315, 23316, 23317, 23318, 23319,
    23320, 23321, 23322, 23323, 23324, 23325, 23326, 23327,
    23328,
}

-- Persistent state (survives across calls like Lich5 globals)
M.wayto = {}          -- [room_id] = { [dir] = dest_room_id|nil }
M.wander = {}         -- ordered list of recently visited room IDs
M.hot_pit = nil       -- room ID containing the pit on the hot side
M.cold_pit = nil      -- room ID containing the pit on the cold side
M.hot_tranquility = nil   -- room ID containing tranquility on hot side
M.cold_tranquility = nil  -- room ID containing tranquility on cold side

-- Helpers -----------------------------------------------------------------

local function contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function is_hot(room_id)
    return contains(M.hot_rooms, room_id)
end

local function is_cold(room_id)
    return contains(M.cold_rooms, room_id)
end

local function has_loot_named(name)
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.name == name then return true end
    end
    return false
end

--- BFS/backtrack through the learned wayto graph to find a direction from
--- the current room toward any of the target room IDs.
--- Returns a direction string or nil.
local function dir_to(start_id, targets)
    local dir = nil
    local tried = {}

    for _ = 1, 30 do
        -- Direct exit from current room to a target?
        if M.wayto[start_id] then
            for d, dest in pairs(M.wayto[start_id]) do
                if contains(targets, dest) then
                    return d
                end
            end
        end

        -- Expand: find rooms whose exits lead to current targets
        for _, t in ipairs(targets) do
            if not contains(tried, t) then
                tried[#tried + 1] = t
            end
        end

        local new_targets = {}
        for k, edges in pairs(M.wayto) do
            for _, dest in pairs(edges) do
                if contains(targets, dest) and not contains(tried, k) then
                    new_targets[#new_targets + 1] = k
                end
            end
        end

        if #new_targets == 0 then break end
        targets = new_targets
    end

    return dir  -- nil
end

--- Navigate to a target within the Elemental Confluence.
--- target: a room ID (number), or the string "tranquility".
--- Returns true on success, false if the zone was exited unexpectedly.
function M.navigate(target)
    while true do
        local start_id = GameState.room_id
        if start_id == target then return true end

        -- Determine hot/cold
        local hot
        if is_hot(start_id) then
            hot = true
        elseif is_cold(start_id) then
            hot = false
        else
            -- Outside the Confluence zone entirely
            return false
        end

        -- Track tranquility points
        if has_loot_named("point of elemental tranquility") then
            if hot then
                M.hot_tranquility = start_id
            else
                M.cold_tranquility = start_id
            end
        elseif M.hot_tranquility == start_id then
            M.hot_tranquility = nil
        elseif M.cold_tranquility == start_id then
            M.cold_tranquility = nil
        end

        -- Track bottomless pits
        if has_loot_named("gaping bottomless pit") then
            if hot then
                M.hot_pit = start_id
            else
                M.cold_pit = start_id
            end
        elseif M.hot_pit == start_id then
            M.hot_pit = nil
        elseif M.cold_pit == start_id then
            M.cold_pit = nil
        end

        -- Learn exits for this room if not yet known
        if not M.wayto[start_id] then
            local exits = GameState.room_exits()
            local wayto_entry = {}
            for _, d in ipairs(exits) do
                wayto_entry[d] = nil
            end
            -- Re-check room hasn't changed
            if GameState.room_id ~= start_id then goto continue end
            M.wayto[start_id] = wayto_entry
        end

        -- Verify exits still match (zone can shuffle)
        local exits = GameState.room_exits()
        local keys = {}
        for d, _ in pairs(M.wayto[start_id]) do
            keys[#keys + 1] = d
        end
        table.sort(keys)
        table.sort(exits)
        local match = (#keys == #exits)
        if match then
            for i, k in ipairs(keys) do
                if k ~= exits[i] then match = false; break end
            end
        end
        if not match then
            if GameState.room_id ~= start_id then goto continue end
            -- Exits changed; reset learned graph
            M.wayto = {}
            goto continue
        end

        -- Check for bounty child escort
        local child = nil
        if bounty and bounty():match("^You have made contact with the child") then
            local npcs = GameObj.npcs()
            for _, npc in ipairs(npcs) do
                if npc.noun == "child" then
                    child = npc
                    break
                end
            end
        end

        -- Determine direction to move
        local dir = nil

        if target == "tranquility" then
            -- Already here with tranquility? Enter it.
            if has_loot_named("point of elemental tranquility") then
                move("go tranquility")
                return true
            end
            -- Navigate toward known tranquility room
            if hot and M.hot_tranquility then
                dir = dir_to(start_id, { M.hot_tranquility })
            elseif not hot and M.cold_tranquility then
                dir = dir_to(start_id, { M.cold_tranquility })
            end
        else
            -- Target is a room ID; might need to cross via pit
            if hot and is_cold(target) then
                if has_loot_named("gaping bottomless pit") then
                    move("go pit")
                    goto continue
                end
                if M.hot_pit then
                    dir = dir_to(start_id, { M.hot_pit })
                end
            elseif not hot and is_hot(target) then
                if has_loot_named("gaping bottomless pit") then
                    move("go pit")
                    goto continue
                end
                if M.cold_pit then
                    dir = dir_to(start_id, { M.cold_pit })
                end
            else
                dir = dir_to(start_id, { target })
            end
        end

        -- Fallback: try unexplored exits (dest == nil in our graph)
        if not dir then
            dir = dir_to(start_id, { nil })
        end

        -- Fallback: pick an exit we haven't wandered to recently
        if not dir and M.wayto[start_id] then
            for d, dest in pairs(M.wayto[start_id]) do
                if not contains(M.wander, dest) then
                    dir = d
                    break
                end
            end
        end

        -- Fallback: backtrack through wander history
        if not dir and M.wayto[start_id] then
            for _, wander_id in ipairs(M.wander) do
                for d, dest in pairs(M.wayto[start_id]) do
                    if dest == wander_id then
                        dir = d
                        break
                    end
                end
                if dir then break end
            end
        end

        -- Move
        local result = move(dir)

        -- Wait for child to catch up if escorting
        if child then
            for _ = 1, 50 do
                local found = false
                for _, npc in ipairs(GameObj.npcs()) do
                    if npc.id == child.id then found = true; break end
                end
                if found then break end
                sleep(0.1)
            end
        end

        if result == false then
            -- Movement failed; try random exit from compass
            local look_result = dothistimeout("look", 5, "<compass>")
            if look_result then
                local options = {}
                for d in look_result:gmatch('<dir value="(.-)"') do
                    options[#options + 1] = d
                end
                if #options > 0 then
                    move(options[math.random(#options)])
                end
            end
        else
            local end_id = GameState.room_id
            if end_id ~= start_id then
                -- Record learned connection
                if M.wayto[start_id] then
                    M.wayto[start_id][dir] = end_id
                end
                -- Update wander list (remove then push)
                for i = #M.wander, 1, -1 do
                    if M.wander[i] == end_id then
                        table.remove(M.wander, i)
                    end
                end
                M.wander[#M.wander + 1] = end_id
            end
        end

        ::continue::
    end
end

--- Reset all learned state.
function M.reset()
    M.wayto = {}
    M.wander = {}
    M.hot_pit = nil
    M.cold_pit = nil
    M.hot_tranquility = nil
    M.cold_tranquility = nil
end

return M
