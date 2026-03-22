-- OSACrew Cannoneer Module
-- Original: osacrew.lic lines 1004-1304
-- Implements the full cannon crew duty loop: set_mode, get_balls, load, fire,
-- and the four flag-driven dispatch handlers (boarded/stop/sunk/cycle).

local M = {}

-- ---------------------------------------------------------------------------
-- Internal flag helpers
-- ---------------------------------------------------------------------------

local function any_flag(osa)
    return osa["$osa_cannoneer_boarded"]
        or osa["$osa_cannoneer_thirty"]
        or osa["$osa_cannoneer_sunk"]
        or osa["$osa_cannoneer_stop"]
end

local function reset_flags(osa, save_fn)
    osa["$osa_cannoneer_boarded"] = false
    osa["$osa_cannoneer_thirty"]  = false
    osa["$osa_cannoneer_sunk"]    = false
    osa["$osa_cannoneer_stop"]    = false
    save_fn(osa)
end

-- ---------------------------------------------------------------------------
-- M.set_mode(osa, save_fn)
-- Interactive CLI: choose duty (load/fire/both) then cannon position.
-- Source: lines 1006-1068
-- ---------------------------------------------------------------------------

function M.set_mode(osa, save_fn)
    respond(
        "\n" ..
        "  =======================================\n" ..
        "  What duties are you assuming?\n" ..
        "      1. Load Only\n" ..
        "      2. Fire Only\n" ..
        "      3. Load And Fire\n" ..
        "  =======================================\n" ..
        "  Select your mode -\n" ..
        "        ;send <#> "
    )
    respond("")
    clear()

    local duty_line = nil
    repeat
        duty_line = get()
    until duty_line:match("^%s*%d+%s*$")

    local duty = duty_line:match("%d+")

    osa["$osa_loadonly"]    = (duty == "1")
    osa["$osa_fireonly"]    = (duty == "2")
    osa["$osa_loadandfire"] = (duty == "3")
    save_fn(osa)

    -- Cannon position selection.  Man o' war has 3 options; others have 2.
    respond(
        "\n\n" ..
        "  =======================================\n" ..
        "  Which cannons?"
    )
    respond("      1. Main Deck")
    if osa["$osa_ship_type"] == "man o' war" then
        respond("      2. Mid Deck")
        respond("      3. Forward Deck")
    else
        respond("      2. Forward Deck")
    end
    respond(
        "  =======================================\n" ..
        "  Select your cannons -\n" ..
        "        ;send <#> "
    )
    respond("")
    clear()

    local cannon_line = nil
    repeat
        cannon_line = get()
    until cannon_line:match("^%s*%d+%s*$")

    local cannons = cannon_line:match("%d+")

    if osa["$osa_ship_type"] == "man o' war" then
        osa["$osa_maincannons"]    = (cannons == "1")
        osa["$osa_midcannons"]     = (cannons == "2")
        osa["$osa_forwardcannons"] = (cannons == "3")
    else
        -- Non-man-o-war: option 2 maps to forward
        osa["$osa_maincannons"]    = (cannons == "1")
        osa["$osa_midcannons"]     = false
        osa["$osa_forwardcannons"] = (cannons == "2")
    end
    save_fn(osa)
end

-- ---------------------------------------------------------------------------
-- M.get_balls(osa)
-- Navigate to cargo hold and retrieve cannon balls.
-- Source: lines 1070-1098
-- ---------------------------------------------------------------------------

function M.get_balls(osa)
    if any_flag(osa) then return end

    waitrt()

    -- Navigate to cargo hold tag
    Map.go2("cargo_hold")

    local result = dothistimeout(
        "get balls",
        3,
        "You cannot fire your cannons while boarded",
        "You search through the cannon balls and find an iron cannon ball",
        "You search through the cannon balls only to find that you are out of cannon balls",
        "...wait",
        "You will need a free hand to search for supplies"
    )

    if not result then return end

    if result:find("You cannot fire your cannons while boarded") then
        osa["$osa_cannoneer_boarded"] = true
        return
    elseif result:find("You will need a free hand to search for supplies") then
        -- Both hands full; caller will handle
        return
    elseif result:find("You search through the cannon balls and find an iron cannon ball") then
        waitrt()
        local lh = GameObj.left_hand()
        local rh = GameObj.right_hand()
        if lh and rh then
            -- Both hands full — done
            return
        end
        M.get_balls(osa)
    elseif result:find("You search through the cannon balls only to find that you are out of cannon balls") then
        local lh = GameObj.left_hand()
        local rh = GameObj.right_hand()
        if lh or rh then
            -- At least one ball in hand; proceed
            return
        else
            M.out_of_balls(osa)
        end
    elseif result:find("%.%.%.wait") then
        waitrt()
        M.get_balls(osa)
    end
end

-- ---------------------------------------------------------------------------
-- M.out_of_balls(osa, save_fn)
-- Drop any held balls, echo message, set thirty flag.
-- Source: lines 1100-1113
-- ---------------------------------------------------------------------------

function M.out_of_balls(osa, save_fn)
    local rh = GameObj.right_hand()
    if rh and rh.noun == "ball" then
        fput("drop right")
    end
    local lh = GameObj.left_hand()
    if lh and lh.noun == "ball" then
        fput("drop left")
    end
    respond(
        "\n\n" ..
        "         ------------====== The Ship Is Out Of Cannon Balls ======-------------\n\n"
    )
    osa["$osa_cannoneer_thirty"] = true
    if save_fn then save_fn(osa) end
end

-- ---------------------------------------------------------------------------
-- M.load_cannon(osa, cannon_tag, save_fn)
-- Navigate to cannon_tag and load the cannon.
-- Source: lines 1115-1148
-- ---------------------------------------------------------------------------

function M.load_cannon(osa, cannon_tag, save_fn)
    if any_flag(osa) then return end

    waitrt()

    -- Navigate to cannon position if not already there
    local cur = Room.current()
    local in_tag = false
    if cur and cur.tags then
        for _, t in ipairs(cur.tags) do
            if t == cannon_tag then in_tag = true; break end
        end
    end
    if not in_tag then
        Map.go2(cannon_tag)
    end

    local result = dothistimeout(
        "load cannon",
        3,
        "You carefully lift your cannon ball and drop it into the tubular opening of a",
        "You need to be holding a cannon ball in order to load the",
        "You cannot fire your cannons while boarded",
        "The .* cannon already appears to be loaded to capacity"
    )

    if not result then return end

    if result:find("You carefully lift your cannon ball and drop it into the tubular opening of a") then
        waitrt()
        -- Pick up any ball on the ground from loot
        local loot = GameObj.loot()
        for _, item in ipairs(loot) do
            if item.noun == "ball" then
                fput("get ball")
                break
            end
        end
        local lh = GameObj.left_hand()
        local rh = GameObj.right_hand()
        if not lh and not rh then
            M.get_balls(osa)
        end
        M.load_cannon(osa, cannon_tag, save_fn)
    elseif result:find("You need to be holding a cannon ball in order to load the") then
        M.get_balls(osa)
        M.load_cannon(osa, cannon_tag, save_fn)
    elseif result:find("You cannot fire your cannons while boarded") then
        osa["$osa_cannoneer_boarded"] = true
        if save_fn then save_fn(osa) end
        return
    elseif result:find("already appears to be loaded to capacity") then
        -- Cannon full; drop any held balls
        local rh = GameObj.right_hand()
        if rh and rh.noun == "ball" then fput("drop right") end
        local lh = GameObj.left_hand()
        if lh and lh.noun == "ball" then fput("drop left") end
    end
end

-- ---------------------------------------------------------------------------
-- M.fire_cannon(osa, cannon_tag, save_fn)
-- Navigate to cannon_tag and fire.
-- Source: lines 1150-1172
-- ---------------------------------------------------------------------------

function M.fire_cannon(osa, cannon_tag, save_fn)
    if any_flag(osa) then return end

    waitrt()

    -- Navigate to cannon position if not already there
    local cur = Room.current()
    local in_tag = false
    if cur and cur.tags then
        for _, t in ipairs(cur.tags) do
            if t == cannon_tag then in_tag = true; break end
        end
    end
    if not in_tag then
        Map.go2(cannon_tag)
    end

    local result = dothistimeout(
        "fire cannon",
        3,
        "You cannot fire your cannons while boarded",
        "You'll need to load one of the cannons first",
        "...wait",
        "You fire a"
    )

    if not result then return end

    if result:find("You cannot fire your cannons while boarded") then
        osa["$osa_cannoneer_boarded"] = true
        if save_fn then save_fn(osa) end
        return
    elseif result:find("You'll need to load one of the cannons first") then
        return
    elseif result:find("%.%.%.wait") then
        waitrt()
        M.fire_cannon(osa, cannon_tag, save_fn)
    elseif result:find("You fire a") then
        waitrt()
        M.fire_cannon(osa, cannon_tag, save_fn)
    end
end

-- ---------------------------------------------------------------------------
-- M.gunner_boarded(osa, save_fn, go_to_tag_fn)
-- Handle boarding: drop balls, go to main deck, join commander.
-- If osacombat enabled start it; else gird and go to captain's quarters.
-- Source: lines 1174-1204
-- ---------------------------------------------------------------------------

function M.gunner_boarded(osa, save_fn, go_to_tag_fn)
    waitrt()

    local rh = GameObj.right_hand()
    if rh and rh.noun == "ball" then fput("drop right") end
    local lh = GameObj.left_hand()
    if lh and lh.noun == "ball" then fput("drop left") end

    -- Go to main deck
    Map.go2("main_deck")

    -- Wait until commander is in the room
    local commander = osa["$osa_commander"] or ""
    wait_until(function()
        local pcs = GameObj.pcs()
        for _, pc in ipairs(pcs) do
            if pc.name and pc.name:find(commander) then return true end
        end
        return false
    end)

    fput("join " .. commander)

    if osa["$osa_osacombat"] then
        if not Script.running("osacombat") then
            Script.run("osacombat")
        end
    else
        echo("You Are Not Currently In A Combatant Role, Ready Thyself For Combat!")
        fput("gird")
        local medic = osa["$osa_medicalofficer"] or ""
        if medic ~= "" and medic:find(GameState.name) then
            Map.go2("captains_quarters")
        end
    end

    reset_flags(osa, save_fn)
end

-- ---------------------------------------------------------------------------
-- M.gunner_stop(osa, save_fn, go_to_tag_fn)
-- Stop duty: drop balls, main deck, join commander, reset flags.
-- Does NOT start osacombat.
-- Source: lines 1206-1221
-- ---------------------------------------------------------------------------

function M.gunner_stop(osa, save_fn, go_to_tag_fn)
    waitrt()

    local rh = GameObj.right_hand()
    if rh and rh.noun == "ball" then fput("drop right") end
    local lh = GameObj.left_hand()
    if lh and lh.noun == "ball" then fput("drop left") end

    Map.go2("main_deck")

    local commander = osa["$osa_commander"] or ""
    wait_until(function()
        local pcs = GameObj.pcs()
        for _, pc in ipairs(pcs) do
            if pc.name and pc.name:find(commander) then return true end
        end
        return false
    end)

    fput("join " .. commander)

    reset_flags(osa, save_fn)
end

-- ---------------------------------------------------------------------------
-- M.gunner_sunk(osa, save_fn, damage_control_fn)
-- Sunk handler: drop balls, run damage_control, reset flags.
-- Source: lines 1223-1236
-- ---------------------------------------------------------------------------

function M.gunner_sunk(osa, save_fn, damage_control_fn)
    waitrt()

    local rh = GameObj.right_hand()
    if rh and rh.noun == "ball" then fput("drop right") end
    local lh = GameObj.left_hand()
    if lh and lh.noun == "ball" then fput("drop left") end

    damage_control_fn(osa)

    reset_flags(osa, save_fn)
end

-- ---------------------------------------------------------------------------
-- M.gunner_cycle(osa, save_fn, go_to_tag_fn, damage_control_fn)
-- Main cannoneer loop.  Determines cannon position and duty, then runs
-- get_balls → load and/or fire.  Dispatches on flags after each step.
-- Source: lines 1238-1304
-- ---------------------------------------------------------------------------

function M.gunner_cycle(osa, save_fn, go_to_tag_fn, damage_control_fn)
    -- Resolve cannon position tag
    local cannon_tag
    if osa["$osa_maincannons"] then
        cannon_tag = "main_cannon"
    elseif osa["$osa_midcannons"] then
        cannon_tag = "mid_cannon"
    elseif osa["$osa_forwardcannons"] then
        cannon_tag = "forward_cannon"
    end

    -- Resolve duty
    local duty
    if osa["$osa_loadonly"] then
        duty = "load"
    elseif osa["$osa_fireonly"] then
        duty = "fire"
    elseif osa["$osa_loadandfire"] then
        duty = "both"
    end

    -- Helper: dispatch flag handlers and return true if a flag was set
    local function dispatch_flags()
        if osa["$osa_cannoneer_boarded"] or osa["$osa_cannoneer_thirty"] then
            M.gunner_boarded(osa, save_fn, go_to_tag_fn)
            return true
        end
        if osa["$osa_cannoneer_sunk"] then
            M.gunner_sunk(osa, save_fn, damage_control_fn)
            return true
        end
        if osa["$osa_cannoneer_stop"] then
            M.gunner_stop(osa, save_fn, go_to_tag_fn)
            return true
        end
        return false
    end

    M.get_balls(osa)
    if dispatch_flags() then return end

    -- Load phase
    if duty == "load" or duty == "both" then
        if not any_flag(osa) then
            M.load_cannon(osa, cannon_tag, save_fn)
        end
        if dispatch_flags() then return end
    end

    -- Fire phase
    if duty == "fire" or duty == "both" then
        if not any_flag(osa) then
            M.fire_cannon(osa, cannon_tag, save_fn)
        end
        if dispatch_flags() then return end
    end

    -- Recurse for next cycle if no flags
    if not any_flag(osa) then
        M.gunner_cycle(osa, save_fn, go_to_tag_fn, damage_control_fn)
    else
        dispatch_flags()
    end
end

return M
