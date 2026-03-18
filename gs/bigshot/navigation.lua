--- Bigshot Navigation — room movement within hunting boundaries
-- Handles wandering to new rooms, returning to anchor, fog return, escape rooms.
-- Port of bs_wander, bs_move, fog_return, escape_rooms from bigshot.lic v5.12.1

local area_rooms = require("area_rooms")

local M = {}

---------------------------------------------------------------------------
-- Room movement: pick a valid neighbor and move
---------------------------------------------------------------------------

--- Move to a random valid neighbor within hunting boundaries.
-- @param bstate  Bigshot state table
-- @return target NPC or nil, boolean moved
function M.wander(bstate)
    local current = Map.current_room()
    if not current then return nil, false end

    -- Out of bounds check
    if not area_rooms.valid(current) then
        respond("[bigshot] Out of bounds — returning to anchor")
        M.goto_room(area_rooms.get_anchor())
        return nil, true
    end

    local neighbors = area_rooms.get_valid_neighbors(current)
    if #neighbors == 0 then
        -- Dead end — return to anchor and try again
        respond("[bigshot] No valid exits — returning to anchor")
        M.goto_room(area_rooms.get_anchor())
        return nil, true
    end

    -- Wait before wandering if configured
    local wander_wait = tonumber(bstate.wander_wait) or 0.3
    if wander_wait > 0 then
        pause(wander_wait)
    end

    -- Sneaky movement
    if bstate._sneaky_mode then
        if not (hidden and hidden()) then
            fput("hide")
            pause(0.3)
        end
    end

    -- Pick random neighbor
    math.randomseed(os.time() + (os.clock() * 1000))
    local choice = neighbors[math.random(#neighbors)]

    -- Move using the command from wayto
    waitrt()
    local ok = M.bs_move(choice.command, bstate)
    return nil, ok
end

--- Execute a single room movement command with retry logic.
-- Handles StringProc-style commands, regular go commands, and stun/web waits.
function M.bs_move(command, bstate)
    if not command then return false end

    -- If command is a function (StringProc equivalent), call it
    if type(command) == "function" then
        local ok, err = pcall(command)
        return ok
    end

    -- Standard movement
    waitrt()
    local result = fput(command)

    -- Brief wait to let room change register
    pause(0.3)
    return true
end

---------------------------------------------------------------------------
-- Go2: navigate to a specific room
---------------------------------------------------------------------------

function M.goto_room(room_id)
    if not room_id or room_id == 0 or room_id == "" then return false end
    room_id = tonumber(room_id) or room_id

    local current = Map.current_room()
    if current == room_id then return true end

    -- Unhide before long travel
    if hidden and hidden() then
        fput("unhide")
        pause(0.3)
    end

    Map.go2(tostring(room_id))
    pause(0.5)

    -- Verify arrival
    return Map.current_room() == room_id
end

--- Navigate to room with retry (loops go2 until arrival)
function M.goto_room_loop(room_id, max_attempts)
    max_attempts = max_attempts or 5
    for attempt = 1, max_attempts do
        if M.goto_room(room_id) then return true end
        pause(1)
    end
    respond("[bigshot] Failed to reach room " .. tostring(room_id) .. " after " .. max_attempts .. " attempts")
    return false
end

---------------------------------------------------------------------------
-- Travel waypoints: move through a series of rooms in order
---------------------------------------------------------------------------

function M.travel_waypoints(waypoint_ids)
    if not waypoint_ids or type(waypoint_ids) ~= "table" or #waypoint_ids == 0 then return end
    for _, wp in ipairs(waypoint_ids) do
        local id = tonumber(wp)
        if id then
            M.goto_room_loop(id, 3)
        end
    end
end

---------------------------------------------------------------------------
-- Fog Return: fast-travel home after hunting
---------------------------------------------------------------------------

function M.fog_return(bstate)
    local fog_type = tonumber(bstate.fog_return) or 0
    if fog_type == 0 then return false end

    -- Optional fog: only use if wounded or encumbered
    if bstate.fog_optional then
        local dominated = false
        if Char.percent_encumbrance and Char.percent_encumbrance >= 60 then dominated = true end
        if Wounds then
            local parts = {"head","neck","chest","abdomen","back","leftArm","rightArm","rightLeg","leftLeg","nsys"}
            for _, p in ipairs(parts) do
                if Wounds[p] and Wounds[p] > 0 then dominated = true; break end
            end
        end
        if not dominated then return false end
    end

    if fog_type == 1 then
        return M._fog_spirit_guide(bstate)
    elseif fog_type == 2 then
        return M._fog_voln_return(bstate)
    elseif fog_type == 3 then
        -- Traveler's Song (1020)
        waitrt()
        waitcastrt()
        fput("incant 1020")
        pause(2)
        return true
    elseif fog_type == 4 then
        -- GoS Sigil of Escape (9720)
        waitrt()
        waitcastrt()
        fput("sigil of escape")
        pause(2)
        return true
    elseif fog_type == 5 then
        -- Familiar Gate (930)
        waitrt()
        waitcastrt()
        fput("incant 930")
        pause(2)
        fput("go portal")
        pause(2)
        return true
    elseif fog_type == 6 then
        -- Custom fog commands
        return M._fog_custom(bstate)
    end

    return false
end

function M._fog_spirit_guide(bstate, from_voln)
    waitrt()
    waitcastrt()
    fput("incant 130")
    pause(2)

    -- If fog_rift and still in rift area, cast again
    if bstate.fog_rift then
        local rest_id = tonumber(bstate.resting_room_id)
        if rest_id and Map.current_room() ~= rest_id then
            waitrt()
            waitcastrt()
            fput("incant 130")
            pause(2)
        end
    end

    -- Fallback to voln if still not home
    local rest_id = tonumber(bstate.resting_room_id)
    if rest_id and Map.current_room() ~= rest_id and not from_voln then
        return M._fog_voln_return(bstate, true)
    end

    return true
end

function M._fog_voln_return(bstate, from_130)
    waitrt()
    fput("symbol of return")
    pause(2)

    -- If fog_rift and still in rift area, cast again
    if bstate.fog_rift then
        local rest_id = tonumber(bstate.resting_room_id)
        if rest_id and Map.current_room() ~= rest_id then
            waitrt()
            fput("symbol of return")
            pause(2)
        end
    end

    -- Fallback to 130 if still not home
    local rest_id = tonumber(bstate.resting_room_id)
    if rest_id and Map.current_room() ~= rest_id and not from_130 then
        return M._fog_spirit_guide(bstate, true)
    end

    return true
end

function M._fog_custom(bstate)
    local cmds = bstate.custom_fog or ""
    if type(cmds) == "string" then
        for cmd in cmds:gmatch("[^,]+") do
            cmd = cmd:match("^%s*(.-)%s*$")
            if cmd ~= "" then
                -- Check if it's a script command
                local script_name = cmd:match("^script%s+(.+)")
                if script_name then
                    local parts = {}
                    for word in script_name:gmatch("%S+") do parts[#parts + 1] = word end
                    local name = table.remove(parts, 1)
                    local args = table.concat(parts, " ")
                    Script.run(name, args)
                    -- Wait for script to finish
                    local timeout = 30
                    local waited = 0
                    while Script.running(name) and waited < timeout do
                        pause(0.5)
                        waited = waited + 0.5
                    end
                else
                    fput(cmd)
                    pause(0.5)
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Escape Rooms: handle swallowed/trapped scenarios
---------------------------------------------------------------------------

function M.escape_rooms(bstate)
    local room_name = GameState.room_name or ""
    local room_desc = GameState.room_description or ""

    -- Worm belly / Crawler innards
    if room_name:find("[Bb]elly") or room_name:find("[Ii]nnards") then
        M._creature_escape(bstate)
        return true
    end

    -- Ooze innards
    if room_name:find("[Oo]oze") and room_name:find("[Ii]nnards") then
        M._creature_escape(bstate)
        return true
    end

    -- Temporal Rift
    if room_name:find("[Tt]emporal") and room_name:find("[Rr]ift") then
        M._temporal_escape(bstate)
        return true
    end

    return false
end

function M._creature_escape(bstate)
    -- Find a dagger or blunt weapon to attack with
    local weapon = M._find_escape_weapon(bstate)
    if not weapon then
        respond("[bigshot] No escape weapon found! Need a dagger or blunt weapon.")
        return false
    end

    -- Attack from inside
    for i = 1, 20 do
        waitrt()
        fput("attack " .. weapon)
        pause(1)
        -- Check if we escaped
        local room_name = GameState.room_name or ""
        if not room_name:find("[Bb]elly") and not room_name:find("[Ii]nnards") then
            return true
        end
    end
    return false
end

function M._temporal_escape(bstate)
    -- Random movement to escape temporal rift
    local dirs = {"n", "s", "e", "w", "ne", "nw", "se", "sw", "u", "d", "out"}
    for i = 1, 20 do
        local dir = dirs[math.random(#dirs)]
        local ok = pcall(move, dir)
        pause(0.5)
        local room_name = GameState.room_name or ""
        if not room_name:find("[Tt]emporal") then
            return true
        end
    end
    return false
end

function M._find_escape_weapon(bstate)
    -- Check hands first
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and rh.noun then
        if rh.noun:find("dagger") or rh.noun:find("knife") or rh.noun:find("dirk") then
            return rh.noun
        end
    end
    if lh and lh.noun then
        if lh.noun:find("dagger") or lh.noun:find("knife") or lh.noun:find("dirk") then
            return lh.noun
        end
    end
    -- Try getting from containers
    fput("get dagger")
    pause(0.3)
    rh = GameObj.right_hand()
    if rh and rh.noun and rh.noun:find("dagger") then
        return rh.noun
    end
    return nil
end

return M
