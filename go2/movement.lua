local M = {}

local function is_swim_or_climb(cmd)
    local c = cmd:lower()
    return c:find("swim") or c:find("dive") or c:find("climb") or c:find("pedal")
end

function M.step(command, state)
    -- Dead check
    if dead() then return false, "dead" end

    -- Muckled check — wait it out
    while muckled() do
        if stunned() then respond("[go2] Waiting for stun to clear...") end
        if webbed() then respond("[go2] Waiting for web to clear...") end
        if sleeping() then respond("[go2] Waiting to wake up...") end
        pause(0.5)
    end

    -- Stand if needed (skip for swim/climb)
    if not standing() and not is_swim_or_climb(command) then
        waitrt()
        fput("stand")
        pause(0.2)
    end

    -- Wait for roundtime
    waitrt()

    -- Execute movement — move() raises on failure, so wrap in pcall
    local ok, err = pcall(move, command)

    -- Post-move delay
    if ok and state and state.delay and state.delay > 0 then
        pause(state.delay)
    end

    return ok, err
end

function M.walk(path, state, on_step)
    local error_count = 0

    for i, command in ipairs(path) do
        if on_step then
            on_step(i, #path, command)
        end

        local ok, err = M.step(command, state)
        if not ok then
            error_count = error_count + 1
            if error_count > 2 then
                return false, "movement failed 3 consecutive times: " .. tostring(err)
            end
            return false, "retry"
        else
            error_count = 0
        end
    end

    return true, nil
end

function M.walk_typeahead(path, state, on_step)
    local typeahead = state.typeahead or 0
    if typeahead <= 0 then
        return M.walk(path, state, on_step)
    end

    local moves_sent = 0
    local room_count_start = GameState.room_count

    for i, command in ipairs(path) do
        if on_step then on_step(i, #path, command) end

        if dead() then return false, "dead" end

        -- Wait for room confirmation window
        local deadline = os.time() + 5
        while (GameState.room_count - room_count_start) < (moves_sent - typeahead) do
            if os.time() > deadline then
                return false, "typeahead timeout — server not responding"
            end
            pause(0.1)
        end

        -- First move is always blocking
        if i == 1 then
            local ok, err = M.step(command, state)
            if not ok then return false, "retry" end
            room_count_start = GameState.room_count
            moves_sent = 0
        else
            -- Typeahead: non-blocking send
            waitrt()
            put(command)
            moves_sent = moves_sent + 1
        end
    end

    -- Wait for all pending moves to confirm
    local deadline = os.time() + 10
    while (GameState.room_count - room_count_start) < moves_sent do
        if os.time() > deadline then
            return false, "timeout waiting for final room confirmations"
        end
        pause(0.2)
    end

    return true, nil
end

return M
