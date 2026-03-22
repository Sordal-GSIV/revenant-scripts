local M = {}

--- Conditional messaging (port of tpick_silent from lines 1774-1793).
-- @param flag   If true, always show. If nil, only show if Run Silently is "No".
-- @param message  The message text to display.
-- @param settings  Table with load_data settings and vars.
function M.tpick_silent(flag, message, settings)
    local load_data = settings.load_data
    local vars = settings.vars

    -- If flag is nil, only show when Run Silently is off
    if load_data["Run Silently"] == "No" then
        flag = true
    end

    if flag then
        -- Update the window message (skip putty remaining updates)
        if not string.find(message, "Putty remaining") then
            vars["Window Message"] = message
            if settings.update_box_for_window then
                settings.update_box_for_window()
            end
        end

        -- Display bordered message unless suppressed
        if load_data["Don't Show Messages"] == "No" then
            respond("")
            if load_data["Use Monster Bold"] == "Yes" then
                respond("<pushBold/>########################################\n"
                    .. message
                    .. "\n########################################<popBold/>")
            else
                respond("########################################\n"
                    .. message
                    .. "\n########################################")
            end
            respond("")
        end
    end
end

--- Critical bordered message display (port of self.message from lines 415-417).
-- Always shows with borders and monster bold.
-- @param message  The message text to display.
function M.tpick_message(message)
    respond("<pushBold/>\n\n\n########################################\n"
        .. "########################################\n"
        .. "########################################\n"
        .. message .. "\n"
        .. "########################################\n"
        .. "########################################\n"
        .. "########################################\n\n\n<popBold/>")
end

--- Get box into hand by ID (port of tpick_get_box from lines 5601-5607).
-- Loops until the box is in either hand.
-- @param vars  Table containing vars["Current Box"] with .id field.
function M.tpick_get_box(vars)
    local box_id = vars["Current Box"].id
    while true do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.id == box_id) or (lh and lh.id == box_id) then
            break
        end
        waitrt()
        fput("get #" .. box_id)
        pause(0.2)
    end
end

--- Drop current box (port of tpick_drop_box from lines 5593-5599).
-- Loops until the box is no longer in either hand.
-- @param vars  Table containing vars["Current Box"] with .id field.
function M.tpick_drop_box(vars)
    local box_id = vars["Current Box"].id
    while true do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (not rh or rh.id ~= box_id) and (not lh or lh.id ~= box_id) then
            break
        end
        waitrt()
        fput("drop #" .. box_id)
        pause(0.2)
    end
end

--- Stow current box (port of tpick_stow_box from lines 5621-5627).
-- Loops until the box is no longer in either hand.
-- @param vars  Table containing vars["Current Box"] with .id field.
function M.tpick_stow_box(vars)
    local box_id = vars["Current Box"].id
    while true do
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (not rh or rh.id ~= box_id) and (not lh or lh.id ~= box_id) then
            break
        end
        waitrt()
        fput("stow #" .. box_id)
        pause(0.2)
    end
end

--- Say configured phrase (port of tpick_say from lines 5629-5631).
-- Only speaks if the setting contains non-space characters.
-- @param words     The settings key name for the phrase to say.
-- @param settings  Table with load_data settings.
function M.tpick_say(words, settings)
    local phrase = settings.load_data[words]
    if phrase and phrase:match("%S") then
        fput("say " .. phrase)
    end
end

--- Determine stow destination (port of where_to_stow_box from lines 4433-4441).
-- If solo mode and stow-in-disk is set, put in disk. Otherwise stow normally.
-- @param vars  Table containing picking mode, stow-in-disk flag, and current box.
function M.where_to_stow_box(vars)
    if vars["Picking Mode"] == "solo" then
        if vars["Stow In Disk"] then
            fput("put #" .. vars["Current Box"].id .. " in " .. GameState.name .. " disk")
        else
            M.tpick_stow_box(vars)
        end
    end
end

--- Trash or stow empty box (port of garbage_check from lines 1958-1995).
-- If Trash Boxes setting is on: try "trash", handle rooms without garbage cans.
-- If in a table/booth room, drops and cleans table.
-- Otherwise: stow the box via tpick_put_stuff_away.
-- @param vars      Table with picking state (Current Box, Picking Mode, etc.)
-- @param settings  Table with load_data settings.
function M.garbage_check(vars, settings)
    local load_data = settings.load_data
    waitrt()

    if load_data["Trash Boxes"] == "Yes" then
        local room_name = GameState.room_name or ""
        if string.find(string.lower(room_name), "table") or string.find(string.lower(room_name), "booth") then
            -- In a table/booth room: drop and clean
            if vars["Picking Mode"] == "solo" then
                M.tpick_drop_box(vars)
            end
            fput("clean table")
        else
            waitrt()
            local throw_away = true

            -- Check if we already know this room has no garbage
            if vars["No Garbage In Room"] then
                if vars["No Garbage In Room"] == Room.id then
                    throw_away = false
                else
                    vars["No Garbage In Room"] = nil
                end
            end

            if throw_away then
                if vars["Picking Mode"] == "ground" then
                    M.tpick_get_box(vars)
                end
                local result = dothistimeout("trash #" .. vars["Current Box"].id, 2, "You need to find|As you toss")
                if result and string.find(result, "You need to find") then
                    vars["No Garbage In Room"] = Room.id
                    M.tpick_drop_box(vars)
                elseif result and string.find(result, "As you toss") then
                    vars["No Garbage In Room"] = nil
                elseif not result then
                    M.tpick_drop_box(vars)
                end
            else
                if vars["Picking Mode"] == "solo" then
                    M.tpick_drop_box(vars)
                end
            end
        end
    else
        vars["stow_current_box"] = true
        if vars["Picking Mode"] == "ground" then
            M.tpick_get_box(vars)
        end
        M.tpick_put_stuff_away(vars, settings)
    end

    waitrt()
end

--- Stow all hand items per container routing (port of tpick_put_stuff_away from lines 5408-5498).
-- Routes items to correct containers based on type/name. Handles lockpicks going to
-- lockpick or broken lockpick containers, wedges, calipers, scale weapons, and
-- user-configured Other Containers routing. Falls back to generic stow.
-- @param vars      Table with picking state (all pick IDs, container refs, etc.)
-- @param settings  Table with load_data and other_container_options.
function M.tpick_put_stuff_away(vars, settings)
    local rogue_trap_nouns = vars["rogue_trap_components_needed_nouns"] or {}
    local rogue_trap_names = vars["rogue_trap_components_needed_names"] or {}
    local rogue_trap_array = vars["rogue_trap_components_needed_array"] or {}
    local all_pick_ids = vars["all_pick_ids"] or {}
    local all_other_container_options = settings.other_container_options or {}

    local both_hands = { GameObj.right_hand(), GameObj.left_hand() }

    for _, item in ipairs(both_hands) do
        if item then
            -- Check if this item is a rogue trap component
            local is_rogue_component = false
            for _, noun in ipairs(rogue_trap_nouns) do
                if item.noun == noun then
                    is_rogue_component = true
                    break
                end
            end
            if is_rogue_component then
                -- Check vial matching
                local dominated_by_vial = false
                for _, rn in ipairs(rogue_trap_nouns) do
                    if string.find(rn, "vial") then
                        dominated_by_vial = true
                        break
                    end
                end
                if dominated_by_vial then
                    local name_lower = item.name or ""
                    local dominated_clear = string.find(name_lower, "clear glass vial")
                    local dominated_thick = string.find(name_lower, "thick glass vial") or string.find(name_lower, "green%-tinted vial")
                    local want_clear = false
                    local want_thick = false
                    for _, rn in ipairs(rogue_trap_names) do
                        if rn == "clear vial" then want_clear = true end
                        if rn == "thick vial" then want_thick = true end
                    end
                    if (dominated_clear and want_clear) or (dominated_thick and want_thick) then
                        table.insert(rogue_trap_array, item.id)
                    end
                else
                    table.insert(rogue_trap_array, item.id)
                end
            end

            -- Determine if we should stow this item
            local current_box_id = vars["Current Box"] and vars["Current Box"].id
            if item.name ~= "Empty" and (item.id ~= current_box_id or vars["stow_current_box"]) then
                local container_id = nil
                local short_name_container = nil

                -- Check if item is a lockpick
                local is_pick = false
                for _, ids in pairs(all_pick_ids) do
                    for _, pid in ipairs(ids) do
                        if pid == item.id then
                            is_pick = true
                            break
                        end
                    end
                    if is_pick then break end
                end

                if is_pick then
                    if vars["lockpick_is_broken"] then
                        container_id = vars["Broken Lockpick Container"] and vars["Broken Lockpick Container"].id
                    else
                        container_id = vars["Lockpick Container"] and vars["Lockpick Container"].id
                    end
                elseif item.name and string.find(item.name, "wedge") then
                    container_id = vars["Wedge Container"] and vars["Wedge Container"].id
                elseif item.name and string.find(item.name, "caliper") then
                    container_id = vars["Calipers Container"] and vars["Calipers Container"].id
                elseif item.id == vars["Scale Weapon ID"] then
                    container_id = vars["Scale Weapon Container"] and vars["Scale Weapon Container"].id
                end

                -- Check Other Containers setting if no match yet
                if not container_id and #all_other_container_options > 0 then
                    local name_match = false
                    local type_match = false
                    local name_match_container_id = nil
                    local name_match_short = nil
                    local type_match_container_id = nil
                    local type_match_short = nil

                    for _, option in ipairs(all_other_container_options) do
                        local stripped = option:match("^%s*(.-)%s*$") or option
                        local pattern_part, container_part = stripped:match("^(.-):%s*(.-)%s*$")
                        if pattern_part and container_part then
                            -- Check name match
                            if not name_match and item.name and string.find(item.name, pattern_part) then
                                local inv = GameObj.inv()
                                for _, inv_item in ipairs(inv) do
                                    if inv_item.name == container_part then
                                        name_match_container_id = inv_item.id
                                        break
                                    end
                                end
                                name_match_short = container_part
                                name_match = true
                            end
                            -- Check type match
                            if not type_match and item.type and string.find(item.type, pattern_part) then
                                local inv = GameObj.inv()
                                for _, inv_item in ipairs(inv) do
                                    if inv_item.name == container_part then
                                        type_match_container_id = inv_item.id
                                        break
                                    end
                                end
                                type_match_short = container_part
                                type_match = true
                            end
                            if name_match and type_match then break end
                        end
                    end

                    if name_match then
                        if name_match_container_id then
                            container_id = name_match_container_id
                        else
                            short_name_container = name_match_short
                        end
                    elseif type_match then
                        if type_match_container_id then
                            container_id = type_match_container_id
                        else
                            short_name_container = type_match_short
                        end
                    end
                end

                -- Try to put item in designated container (up to 3 attempts)
                if container_id or short_name_container then
                    for _ = 1, 3 do
                        local rh = GameObj.right_hand()
                        local lh = GameObj.left_hand()
                        local still_holding = (rh and rh.id == item.id) or (lh and lh.id == item.id)
                        if not still_holding then break end
                        waitrt()
                        if container_id then
                            fput("put #" .. item.id .. " in #" .. container_id)
                        else
                            fput("put #" .. item.id .. " in my " .. short_name_container)
                        end
                        pause(0.2)
                    end
                    -- Check if it's still in hand after 3 tries
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if (rh and rh.id == item.id) or (lh and lh.id == item.id) then
                        M.tpick_silent(nil, "Couldn't put " .. item.name .. " in its proper container, STOWing it instead.", settings)
                    end
                end

                -- Final fallback: stow until out of hand
                while true do
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if (not rh or rh.id ~= item.id) and (not lh or lh.id ~= item.id) then
                        break
                    end
                    waitrt()
                    fput("stow #" .. item.id)
                    pause(0.2)
                end
            end
        end
    end

    vars["stow_current_box"] = nil
    vars["lockpick_is_broken"] = nil
end

--- Format number with comma separators (port of add_commas from line 898).
-- @param number  The number to format.
-- @return String with commas inserted every 3 digits.
function M.add_commas(number)
    local s = tostring(math.floor(number))
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    -- Remove leading comma if present
    if result:sub(1, 1) == "," then
        result = result:sub(2)
    end
    return result
end

return M
