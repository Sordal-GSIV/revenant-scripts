-- movement.lua — go2 step and walk execution

local M = {}

local ok_sp, stringproc = pcall(require, "lib/stringproc")
if not ok_sp then stringproc = nil end

local is_mounted = false   -- track mounted state across the walk

local function is_swim_or_climb(cmd)
    if not cmd then return false end
    local c = cmd:lower()
    return c:find("swim") or c:find("dive") or c:find("climb") or c:find("pedal")
end

local function is_drag_compatible(cmd)
    -- go2.lic drag logic: directional moves and "go/climb <target>"
    if cmd:match("^n$") or cmd:match("^s$") or cmd:match("^e$") or cmd:match("^w$") or
       cmd:match("^ne$") or cmd:match("^se$") or cmd:match("^sw$") or cmd:match("^nw$") or
       cmd:match("^u$") or cmd:match("^d$") or cmd:match("^out$") or
       cmd:match("^north$") or cmd:match("^south$") or cmd:match("^east$") or
       cmd:match("^west$") or cmd:match("^up$") or cmd:match("^down$") or
       cmd:match("^northeast$") or cmd:match("^northwest$") or
       cmd:match("^southeast$") or cmd:match("^southwest$") then
        return true, "direction"
    end
    if cmd:match("^go ") or cmd:match("^climb ") then
        return true, "go_climb"
    end
    return false, nil
end

local function build_drag_cmd(cmd, drag_target)
    if not drag_target then return cmd end
    local compat, mode = is_drag_compatible(cmd)
    if not compat then return nil end  -- signals: can't drag this command
    if mode == "direction" then
        return "drag " .. drag_target .. " " .. cmd
    elseif mode == "go_climb" then
        -- "go portal" → "drag Target portal"
        return cmd:gsub("^go ", "drag " .. drag_target .. " ")
                  :gsub("^climb ", "drag " .. drag_target .. " ")
    end
    return nil
end

-- Stand with retry and mounted detection
local STAND_PATTERNS = {
    "You cannot do that while mounted",
    "You stand",
    "your .+ back and stand up",
    "You struggle, but fail to stand",
    "You are already standing",
    "You don%-t seem to be able to move to do that",
    "There%-s not enough room to do that",
    "There is not enough room to stand up in here",
    "You%-d tip the boat over",
    "%.%.%.wait %d+ seconds?%.",
    "You are overburdened and cannot manage to stand",
    "You attempt to stand, but slip",
}

local function try_stand()
    waitrt()
    local result = nil
    -- fput with a stand pattern wait
    put("stand")
    -- wait briefly for response
    local deadline = os.time() + 3
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            for _, pat in ipairs(STAND_PATTERNS) do
                if line:find(pat) then
                    result = line
                    break
                end
            end
            if result then break end
        end
        pause(0.05)
    end
    if not result then return "unknown" end
    if result:find("You cannot do that while mounted") then return "mounted" end
    if result:find("slip") or result:find("slippery") then return "slipped" end
    return "ok"
end

-- Single step with all safety checks
function M.step(command, state)
    if dead() then return false, "dead" end

    -- Muckled check — wait it out
    local muckle_warned = false
    while muckled() do
        if not muckle_warned then
            if stunned() then respond("[go2] Waiting for stun to clear...") end
            if webbed()   then respond("[go2] Waiting for web to clear...") end
            if sleeping() then respond("[go2] Waiting to wake up...") end
            if bound()    then respond("[go2] Waiting for bind to clear...") end
            muckle_warned = true
        end
        pause(0.5)
        if dead() then return false, "dead" end
    end

    -- Stand if needed (skip for swim/climb and mounted movement)
    if not standing() and not is_swim_or_climb(command) and not is_mounted then
        local result = try_stand()
        if result == "mounted" then
            is_mounted = true
        elseif result == "slipped" then
            -- stood but slipped; ice-mode handling is in the caller
        end
        pause(0.2)
    end

    waitrt()

    -- Build final command (drag mode rewriting)
    local final_cmd = command
    if state and state.drag and state.drag ~= "" then
        local drag_cmd = build_drag_cmd(command, state.drag)
        if drag_cmd then
            final_cmd = drag_cmd
        else
            return false, "drag_incompatible: " .. command
        end
    end

    -- Execute movement
    local ok, err = pcall(move, final_cmd)

    -- Post-move delay
    if ok and state and state.delay and state.delay > 0 then
        pause(state.delay)
    end

    if ok then
        -- Check ice mode — if we slipped and are prone, handle it
        if prone() and state and state.ice_mode then
            if state.ice_mode == "wait" then
                respond("[go2] Slipped on ice — waiting to stand...")
                while prone() do pause(0.5) end
                waitrt()
            elseif state.ice_mode == "run" then
                -- run mode: just keep going, don't stop for slips
            else
                -- auto: wait up to 3 seconds, then continue
                local deadline = os.time() + 3
                while prone() and os.time() < deadline do pause(0.2) end
            end
        end
    end

    return ok, err
end

-- Walk a full path (list of command strings)
function M.walk(path, state, on_step)
    local error_count = 0
    is_mounted = false

    for i, command in ipairs(path) do
        if on_step then on_step(i, #path, command) end

        -- Script dispatch: ;bescort (DR transport)
        if command:match("^;bescort%s") then
            local args = command:match("^;bescort%s+(.+)$")
            if args then
                Script.run("bescort", args)
                while running("bescort") do pause(0.5) end
                error_count = 0
                goto continue
            end
        end

        -- Script dispatch: ;go / ;go2 (recursive navigation)
        if command:match("^;go%s") then
            local dest = command:match("^;go%s+(.+)$")
            if dest then
                Script.run("go2", dest)
                while running("go2") do pause(0.5) end
                error_count = 0
                goto continue
            end
        end

        -- Script dispatch: generic ;script (wayto launcher)
        if command:match("^;%a") and not command:match("^;e ") then
            local script_name = command:match("^;(%S+)")
            local script_args = command:match("^;%S+%s+(.+)$") or ""
            if script_name then
                Script.run(script_name, script_args)
                while running(script_name) do pause(0.5) end
                error_count = 0
                goto continue
            end
        end

        -- StringProc (;e prefix)
        if stringproc and stringproc.is_stringproc(command) then
            local fn, tr_err = stringproc.translate(command)
            if fn then
                local sp_ok, sp_err = stringproc.execute(fn)
                if sp_ok then
                    error_count = 0
                    goto continue
                else
                    error_count = error_count + 1
                    if error_count > 2 then
                        return false, "stringproc failed: " .. tostring(sp_err)
                    end
                    return false, "retry"
                end
            else
                -- Translation failed — caller handles manual navigation
                local from_id = Map.current_room()
                return false, "manual:" .. tostring(from_id or 0) .. ":0"
            end
        end

        -- Normal movement
        local ok, err = M.step(command, state)
        if not ok then
            if err == "dead" then return false, "dead" end
            if err and err:find("drag_incompatible:") then
                respond("[go2] Cannot drag through: " .. command)
                return false, "drag_incompatible"
            end
            error_count = error_count + 1
            if error_count > 2 then
                return false, "movement failed 3 consecutive times: " .. tostring(err)
            end
            return false, "retry"
        else
            -- mounted state update: if urchins disabled due to mount, restart
            if is_mounted and state and state.mapdb_use_urchins then
                respond("[go2] Mounted — disabling urchin usage for this trip")
                state._saved_urchins = state.mapdb_use_urchins
                state.mapdb_use_urchins = false
                UserVars.mapdb_use_urchins = false
            end
            error_count = 0
        end

        ::continue::
    end

    return true, nil
end

-- Typeahead walk (send commands without waiting for each room change)
function M.walk_typeahead(path, state, on_step)
    local typeahead = (state and state.typeahead) or 0
    if typeahead <= 0 then
        return M.walk(path, state, on_step)
    end

    is_mounted = false
    local moves_sent    = 0
    local room_at_start = GameState.room_count or 0
    local first_move    = true

    for i, command in ipairs(path) do
        if on_step then on_step(i, #path, command) end

        if dead() then return false, "dead" end

        -- StringProcs and script launches always block
        local is_blocking = false
        if (stringproc and stringproc.is_stringproc(command)) or
           command:match("^;") then
            is_blocking = true
        end

        if first_move or is_blocking then
            -- Wait for all outstanding typeahead to land before doing proc/first move
            local deadline = os.time() + 5
            while (GameState.room_count - room_at_start) < moves_sent do
                if os.time() > deadline then
                    return false, "typeahead timeout"
                end
                pause(0.05)
            end

            local ok, err = M.step(command, state)
            if not ok then
                if err == "dead" then return false, "dead" end
                return false, "retry"
            end
            if first_move then
                room_at_start = GameState.room_count
                moves_sent = 0
            end
            first_move = false
        else
            -- Typeahead window: wait until we have room to send another command
            local deadline = os.time() + 5
            while (GameState.room_count - room_at_start) < (moves_sent - typeahead) do
                if os.time() > deadline then
                    return false, "typeahead timeout"
                end
                pause(0.02)
            end
            waitrt()
            put(command)
            moves_sent = moves_sent + 1
        end
    end

    -- Flush remaining typeahead
    local deadline = os.time() + 10
    while (GameState.room_count - room_at_start) < moves_sent do
        if os.time() > deadline then
            return false, "timeout waiting for final room confirmations"
        end
        pause(0.2)
    end

    return true, nil
end

function M.reset_mounted()
    is_mounted = false
end

return M
