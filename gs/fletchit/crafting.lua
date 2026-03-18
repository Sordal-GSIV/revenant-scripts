--------------------------------------------------------------------------------
-- FletchIt - Crafting Module
--
-- All crafting operations: stow, get tools, cut shafts, paint, paintstick,
-- cut nock, glue, attach fletchings, string bow, finalize.
--
-- Original author: elanthia-online (Dissonance)
-- Lua conversion preserves all original functionality.
--------------------------------------------------------------------------------

local M = {}

-- Room-level trash can cache: { [room_id] = true/false }
local trash_can_cache = {}
-- Set to true after user confirms they are OK dropping shafts on the ground
local drop_confirmed = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Stow an item from the given hand into a container.
-- Uses dothistimeout to match success/failure. Exits on full container.
-- @param hand string "left" or "right"
-- @param container string container noun
-- @param debug_log function debug logger
function M.stow(hand, container, debug_log)
    debug_log("stow called with hand: " .. hand .. ", container: " .. container)

    local item
    if hand == "right" then
        local rh = GameObj.right_hand()
        if not rh then return end
        item = rh.noun
    elseif hand == "left" then
        local lh = GameObj.left_hand()
        if not lh then return end
        item = lh.noun
    else
        return
    end

    local check = dothistimeout("put my " .. item .. " in my " .. container, 3, "You put|won't fit")

    if check and string.find(check, "won't fit") then
        echo("ERROR: Container full")
        error("container_full")
    elseif not check then
        echo("ERROR: Failed to stow item (timeout)")
        error("stow_failed")
    end
end

--- Empty both hands by stowing items into the supplies container.
-- @param sack string supplies container name
-- @param debug_log function debug logger
function M.empty_hands(sack, debug_log)
    debug_log("empty_hands called")
    local rh = GameObj.right_hand()
    if rh then
        M.stow("right", sack, debug_log)
    end
    local lh = GameObj.left_hand()
    if lh then
        M.stow("left", sack, debug_log)
    end
end

--- Get wood or log from supplies container.
-- @param settings table
-- @param debug_log function
function M.get_wood(settings, debug_log)
    debug_log("get_wood called with wood: " .. settings.wood)
    local wood_type = string.find(settings.wood, "log") and "log" or "wood"
    local check = dothistimeout("get my " .. wood_type .. " in my " .. settings.sack, 1, "You remove|Get what")

    if check and string.find(check, "Get what") then
        echo("ERROR: Run out of wood/logs, this shouldn't be happening.")
        error("no_wood")
    elseif not check then
        -- Backup wait for scripted containers
        local endtime = os.time() + 5
        while true do
            local rh = GameObj.right_hand()
            if rh and string.find(rh.noun or "", wood_type, 1, true) then break end
            if os.time() > endtime then
                echo("ERROR: Could not get " .. wood_type .. ", stopping")
                error("no_wood")
            end
            pause(0.5)
        end
    end
end

--- Get axe from inventory.
-- @param settings table
-- @param debug_log function
function M.get_axe(settings, debug_log)
    debug_log("get_axe called with axe: " .. settings.axe)
    local check = dothistimeout("get my " .. settings.axe, 3, "You remove|get what")

    if check and string.find(check, "get what") then
        echo("ERROR: Could not get your axe to cut the shafts")
        error("no_axe")
    elseif not check then
        local endtime = os.time() + 5
        while true do
            local lh = GameObj.left_hand()
            if lh and string.find(lh.noun or "", settings.axe, 1, true) then break end
            if os.time() > endtime then
                echo("ERROR: Could not get your axe to cut the shafts")
                error("no_axe")
            end
            pause(0.5)
        end
    end
end

--- Get knife/dagger from inventory.
-- @param settings table
-- @param debug_log function
function M.get_knife(settings, debug_log)
    debug_log("get_knife called with knife: " .. settings.knife)
    local check = dothistimeout("get my " .. settings.knife, 3, "You remove|get what")

    if check and string.find(check, "get what") then
        echo("ERROR: Failed to get knife")
        error("no_knife")
    elseif not check then
        local endtime = os.time() + 5
        while true do
            local lh = GameObj.left_hand()
            if lh and string.find(lh.noun or "", settings.knife, 1, true) then break end
            if os.time() > endtime then
                echo("ERROR: Failed to get knife (timeout)")
                error("no_knife")
            end
            pause(0.5)
        end
    end
end

--- Cast Haste (535) if known, not active, and affordable.
-- @param add_stat function stats tracker
-- @param debug_log function
function M.haste(add_stat, debug_log)
    debug_log("haste! called")
    waitcastrt()
    waitrt()
    if Spell[535].known and not Spell[535].active and Spell[535].affordable then
        fput("incant 535")
        add_stat("haste_casts", 1)
    end
end

--- Cut a shaft from wood per ammo type.
-- "cut arrow shaft my wood" vs "cut light bolt my wood" vs "cut heavy bolt my wood"
-- @param settings table
-- @param add_stat function
-- @param debug_log function
function M.cut_shaft_from_wood(settings, add_stat, debug_log)
    debug_log("cut_shaft_from_wood called with ammo type: " .. tostring(settings.ammo) .. ", wood: " .. settings.wood)
    local wood_type = string.find(settings.wood, "log") and "log" or "wood"

    local command
    if settings.ammo == 1 then
        command = "cut arrow shaft my " .. wood_type
    elseif settings.ammo == 2 then
        command = "cut light bolt my " .. wood_type
    elseif settings.ammo == 3 then
        command = "cut heavy bolt my " .. wood_type
    else
        echo("ERROR: Invalid ammo type")
        error("invalid_ammo")
    end

    waitrt()
    M.haste(add_stat, debug_log)
    fput(command)

    local endtime = os.time() + 10
    while true do
        local rh = GameObj.right_hand()
        if rh and string.find(rh.noun or "", "shaft", 1, true) then break end
        if os.time() > endtime then
            add_stat("shafts_cut_failed", 1)
            echo("ERROR: Failed to cut shafts.")
            error("shaft_cut_failed")
        end
        pause(0.5)
    end

    add_stat("shafts_cut_success", 1)
    local wood_type_used = string.find(settings.wood, "log") and "logs_used" or "wood_pieces_used"
    add_stat(wood_type_used, 1)
end

--- Full shaft-making workflow: empty hands, get wood, get axe, cut, stow.
-- @param settings table
-- @param add_stat function
-- @param debug_log function
function M.make_shafts(settings, add_stat, debug_log)
    debug_log("make_shafts called")
    M.empty_hands(settings.sack, debug_log)
    M.get_wood(settings, debug_log)
    M.get_axe(settings, debug_log)
    M.cut_shaft_from_wood(settings, add_stat, debug_log)

    waitrt()
    M.stow("right", settings.sack, debug_log)
    M.stow("left", settings.sack, debug_log)
end

--- Apply paint to a shaft.
-- Gets paint from container, applies to shaft, waits for drying.
-- @param settings table
-- @param paints table paint color mapping
-- @param add_stat function
-- @param debug_log function
-- @return string "success", "no_paint", or "failed"
function M.apply_paint(settings, paints, add_stat, debug_log)
    debug_log("apply_paint called with paint: " .. tostring(settings.paint))
    if settings.paint == 0 then return "success" end

    M.stow("left", settings.sack, debug_log)

    local paint_name = paints[settings.paint]
    if not paint_name then return "success" end

    -- Get the first word of the paint name for the get command
    local paint_words = {}
    for word in string.gmatch(paint_name, "%S+") do
        table.insert(paint_words, word)
    end
    local paint_first = paint_words[1] or "paint"

    waitrt()
    fput("get my " .. paint_first .. " paint")

    local endtime = os.time() + 6
    local got_paint = false
    while true do
        local lh = GameObj.left_hand()
        if lh and string.find(lh.noun or "", "paint", 1, true) then
            got_paint = true
            break
        end
        if os.time() > endtime then
            break
        elseif os.time() > (endtime - 3) then
            waitrt()
            fput("get my " .. paint_first .. " paint")
        end
        pause(0.5)
    end

    if not got_paint then
        echo("ERROR: Run out of paint, probably means you have another colour paint on you messing with my check.")
        echo("Get it out of your fletchsack")
        add_stat("supply_shortage_events", 1)
        return "no_paint"
    end

    waitrt()
    M.haste(add_stat, debug_log)
    local check = dothistimeout("paint my shaft", 3, "You carefully smear a bit of paint")

    if not check then
        -- Double check by looking at the shaft
        local look_check = dothistimeout("look my shaft", 3, "has been pared down and smoothed|paint covers the shaft")
        if not look_check or not string.find(look_check, "paint covers the shaft") then
            echo("ERROR: Could not determine if painting was successful, stopping")
            add_stat("paint_applications_failed", 1)
            return "failed"
        end
    end

    add_stat("paint_applications_success", 1)

    -- Wait for paint to dry (up to 120 seconds)
    local dry_check = matchtimeout(120, "The paint on your")
    if not dry_check then
        echo("WARNING: Did not see paint dry, but carrying on...")
    end

    waitrt()
    M.stow("left", settings.sack, debug_log)
    return "success"
end

--- Apply a paintstick crest to a shaft.
-- Gets paintstick from container, applies it, waits for drying.
-- @param settings table
-- @param paintstick_key string "paintstick1" or "paintstick2"
-- @param add_stat function
-- @param debug_log function
-- @return string "success", "no_paintstick", or "failed"
function M.apply_paintstick(settings, paintstick_key, add_stat, debug_log)
    local ps_value = settings[paintstick_key] or ""
    debug_log("apply_paintstick called with " .. paintstick_key .. ": " .. ps_value)
    if ps_value == "" then return "success" end

    M.stow("left", settings.sack, debug_log)
    waitrt()
    fput("get my " .. ps_value)

    local endtime = os.time() + 6
    local got_ps = false
    while true do
        local lh = GameObj.left_hand()
        if lh and string.find(lh.noun or "", "paintstick", 1, true) then
            got_ps = true
            break
        end
        if os.time() > endtime then
            break
        elseif os.time() > (endtime - 3) then
            waitrt()
            fput("get my " .. ps_value)
        end
        pause(0.5)
    end

    if not got_ps then
        echo("ERROR: Could not get your paintstick")
        add_stat("paintstick_applications_failed", 1)
        return "no_paintstick"
    end

    waitrt()
    M.haste(add_stat, debug_log)
    local check = dothistimeout("paint my shaft", 3, "You carefully apply a band of")

    if not check then
        -- Double check by looking at the shaft
        local look_check = dothistimeout("look my shaft", 3, "It looks like someone has painted a single|It looks like someone has painted a pair of")
        if not look_check or (not string.find(look_check, "single") and not string.find(look_check, "pair of")) then
            echo("ERROR: Could not determine if paintsticking was successful, stopping")
            add_stat("paintstick_applications_failed", 1)
            return "failed"
        end
    end

    add_stat("paintstick_applications_success", 1)

    -- Wait for paint to dry (up to 120 seconds)
    local dry_check = matchtimeout(120, "The paint on your")
    if not dry_check then
        echo("WARNING: Did not see paint dry, but carrying on...")
    end

    waitrt()
    M.stow("left", settings.sack, debug_log)
    return "success"
end

--- Cut a nock in the shaft (arrows only).
-- If painted, retrieves knife (stowed during painting) and cuts once.
-- If not painted, cuts twice for proper depth.
-- @param settings table
-- @param painted boolean whether paint/paintsticks were applied
-- @param add_stat function
-- @param debug_log function
-- @return string "success", "failed", or "not_arrow"
function M.cut_nock(settings, painted, add_stat, debug_log)
    debug_log("cut_nock called with ammo type: " .. tostring(settings.ammo) .. ", painted: " .. tostring(painted))
    if settings.ammo ~= 1 then return "not_arrow" end

    waitrt()

    -- Get knife if we just did painting (it will be stowed)
    if painted then
        M.get_knife(settings, debug_log)
        waitrt()
    end

    waitrt()
    M.haste(add_stat, debug_log)
    waitrt()
    fput("cut nock in my shaft with my " .. settings.knife)
    pause(0.25)
    waitrt()

    -- If shaft was not painted/crested, cut twice for proper nock depth
    if not painted then
        M.haste(add_stat, debug_log)
        waitrt()
        fput("cut nock in my shaft with my " .. settings.knife)
        pause(0.25)
        waitrt()
    end

    -- Check if shaft is still there
    local rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        waitrt()
        M.stow("left", settings.sack, debug_log)
        add_stat("nocks_cut_failed", 1)
        return "failed"
    end

    add_stat("nocks_cut_success", 1)
    M.stow("left", settings.sack, debug_log)
    return "success"
end

--- Finalize arrow: glue, fletchings, bow test, stow. Learning mode trash handling.
-- Learning mode trash priority:
--   1. Trash receptacle (tested and cached per room)
--   2. Drop and clean table (if room title ends with "Table]")
--   3. Drop on ground (pauses script once for user confirmation)
-- @param settings table
-- @param add_stat function
-- @param debug_log function
-- @return string "completed" or "no_supplies"
function M.finalize_arrow(settings, add_stat, debug_log)
    debug_log("finalize_arrow called with learning: " .. tostring(settings.learning))

    -- Learning mode — dispose of shaft
    if settings.learning then
        waitrt()
        local room_id = GameState.room_id

        local cached = trash_can_cache[room_id]

        if cached == nil then
            -- Unknown room — test for trash can
            local result = dothistimeout("trash my shaft", 3, "you feel pleased with yourself|You need to find a trash receptacle")
            if result and string.find(result, "you feel pleased with yourself") then
                trash_can_cache[room_id] = true
            else
                trash_can_cache[room_id] = false
                cached = false
            end
            cached = trash_can_cache[room_id]
        elseif cached then
            fput("trash my shaft")
        end

        if not cached then
            -- Check if we're at a table
            local title = GameState.room_name or ""
            if string.find(title, "Table%]$") then
                fput("drop right")
                fput("clean table")
            else
                if not drop_confirmed then
                    echo("WARNING: No trash can or table found in this room.")
                    echo("WARNING: Unpause the script to drop shafts on the ground.")
                    Script.pause(Script.name)
                    -- When unpaused, user has confirmed
                    drop_confirmed = true
                end
                fput("drop right")
            end
        end

        return "completed"
    end

    -- Normal mode — full finalization
    waitrt()

    -- Make sure there's a shaft in hand
    local rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        M.stow("right", settings.sack, debug_log)
    end

    -- Get glue
    fput("get my glue")
    local endtime = os.time() + 6
    local got_glue = false
    while true do
        local lh = GameObj.left_hand()
        if lh and (string.find(lh.noun or "", "glue", 1, true) or string.find(lh.noun or "", "bottle", 1, true)) then
            got_glue = true
            break
        end
        if os.time() > endtime then
            break
        elseif os.time() > (endtime - 3) then
            waitrt()
            fput("get my glue")
        end
        pause(0.5)
    end

    if not got_glue then
        echo("ERROR: Run out of glue, stopping")
        add_stat("supply_shortage_events", 1)
        return "no_supplies"
    end

    waitrt()
    M.haste(add_stat, debug_log)
    dothistimeout("pour my bottle on my shaft", 3, "You carefully pour")
    add_stat("glue_applications_success", 1)
    M.stow("left", settings.sack, debug_log)

    -- Get fletchings
    waitrt()
    fput("get my " .. settings.fletchings)
    endtime = os.time() + 6
    local got_fletchings = false
    while true do
        local lh = GameObj.left_hand()
        if lh and string.find(lh.noun or "", "fletching", 1, true) then
            got_fletchings = true
            break
        end
        if os.time() > endtime then
            break
        elseif os.time() > (endtime - 3) then
            waitrt()
            fput("get my " .. settings.fletchings)
        end
        pause(0.5)
    end

    if not got_fletchings then
        echo("ERROR: Run out of fletchings, stopping")
        add_stat("supply_shortage_events", 1)
        return "no_supplies"
    end

    waitrt()
    M.haste(add_stat, debug_log)
    local attach_result = dothistimeout("attach my fletching to my shaft", 3, "You carefully attach")
    if attach_result then
        add_stat("fletching_attached_success", 1)
    else
        add_stat("fletching_attached_failure", 1)
    end

    -- Wait for glue to dry (up to 120 seconds)
    local dry_check = matchtimeout(120, "The glue on your")
    if not dry_check then
        echo("WARNING: Did not see glue dry, but carrying on...")
    end

    waitrt()
    M.stow("left", settings.sack, debug_log)

    -- Test with bow
    if settings.bow and settings.bow ~= "" then
        waitrt()
        M.haste(add_stat, debug_log)
        dothistimeout("string my " .. settings.bow .. " with my shaft", 3, "You carefully string")
    end

    waitrt()
    M.stow("right", settings.quiver, debug_log)

    -- Track completion by ammo type
    if settings.ammo == 1 then
        add_stat("arrows_completed", 1)
    elseif settings.ammo == 2 then
        add_stat("light_bolts_completed", 1)
    elseif settings.ammo == 3 then
        add_stat("heavy_bolts_completed", 1)
    end

    return "completed"
end

--- Create a complete arrow/bolt from start to finish.
-- Orchestrates: get shaft, cut, paint, paintstick, nock, finalize.
-- @param settings table
-- @param paints table paint color mapping
-- @param add_stat function
-- @param debug_log function
-- @return string "completed", "failed", "no_shafts", or "no_supplies"
function M.make_arrow(settings, paints, add_stat, debug_log)
    debug_log("make_arrow called with ammo type: " .. tostring(settings.ammo))

    -- Get shaft
    waitrt()
    local check = dothistimeout("get 1 my shaft", 3, "You remove|get what")

    if check and string.find(check, "get what") then
        add_stat("supply_shortage_events", 1)
        return "no_shafts"
    elseif not check then
        -- Backup wait for scripted containers
        local endtime = os.time() + 5
        local found = false
        while true do
            local rh = GameObj.right_hand()
            if rh and string.find(rh.noun or "", "shaft", 1, true) then
                found = true
                break
            end
            if os.time() > endtime then break end
            pause(0.5)
        end
        if not found then
            add_stat("supply_shortage_events", 1)
            return "no_shafts"
        end
    end

    waitrt()
    M.get_knife(settings, debug_log)

    -- Cut shaft
    waitrt()
    M.haste(add_stat, debug_log)
    fput("cut my shaft with my " .. settings.knife)
    pause(0.25)
    waitrt()

    -- If shaft is gone, it failed
    local rh = GameObj.right_hand()
    if not rh or not string.find(rh.noun or "", "shaft", 1, true) then
        M.stow("left", settings.sack, debug_log)
        add_stat("shaft_cut_failures", 1)
        return "failed"
    else
        add_stat("shaft_cut_successes", 1)
    end

    -- Apply paint and decorations (skip in learning mode)
    local painted = false
    if not settings.learning then
        waitrt()
        local paint_result = M.apply_paint(settings, paints, add_stat, debug_log)
        if paint_result == "failed" then return "failed" end
        if paint_result == "no_paint" then return "no_supplies" end

        waitrt()
        local ps1_result = M.apply_paintstick(settings, "paintstick1", add_stat, debug_log)
        if ps1_result == "failed" then return "failed" end
        if ps1_result == "no_paintstick" then return "no_supplies" end

        waitrt()
        local ps2_result = M.apply_paintstick(settings, "paintstick2", add_stat, debug_log)
        if ps2_result == "failed" then return "failed" end
        if ps2_result == "no_paintstick" then return "no_supplies" end

        painted = settings.paint ~= 0
            or (settings.paintstick1 and settings.paintstick1 ~= "")
            or (settings.paintstick2 and settings.paintstick2 ~= "")
    end

    -- Cut nock (for arrows only)
    waitrt()
    local nock_result = M.cut_nock(settings, painted, add_stat, debug_log)
    if nock_result == "failed" then return "failed" end

    -- Finalize arrow
    waitrt()
    local result = M.finalize_arrow(settings, add_stat, debug_log)
    if result == "no_supplies" then return "no_supplies" end

    return "completed"
end

return M
