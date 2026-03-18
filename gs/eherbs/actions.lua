local herbs = require("lib/herbs")
local diagnosis = require("diagnosis")

local M = {}

-- Global dose tracking table (keyed by item ID string)
-- Shared across the script session via the downstream hook
M.dose_tracker = {}
M._last_purchase_doses = nil

--- Install the downstream hook that tracks herb doses from game output
function M.install_dose_monitor()
    local tracker = M.dose_tracker
    local using = nil

    DownstreamHook.remove("eherbs_monitor")
    DownstreamHook.add("eherbs_monitor", function(line)
        -- Reset 'using' on prompt
        if line:find("<prompt") then
            using = nil
        elseif using then
            -- After eating/drinking, parse remaining dose info
            local quaffs = line:match("^You have only about (%d+) quaffs left%.")
            if quaffs then
                tracker[using] = tonumber(quaffs)
            end

            -- "You have about N doses left" or "You have N bites left"
            local count1 = line:match("^You have about (%d+) doses left%.")
                        or line:match("^You have (%d+) doses left%.")
                        or line:match("^You have about (%d+) bites left%.")
                        or line:match("^You have (%d+) bites left%.")
            if count1 then
                tracker[using] = tonumber(count1)
            end

            if line:find("^You have one bite left%.") or line:find("^You only have one bite left%.") then
                tracker[using] = 1
            end
            if line:find("^You have only about one quaff left%.") or line:find("^You only have one dose left%.")
               or line:find("^You only have one quaff left%.") then
                tracker[using] = 1
            end
            if line:find("^That was the last drop%.") or line:find("^That was the last of it%.") then
                tracker[using] = 0
            end
        end

        -- Detect eating/drinking with item ID
        -- "You take a drink from your <item exist="12345"..."
        -- "You take a bite of your <item exist="12345"..."
        local eat_id = line:match('^You take a drink from your .-exist="(%d+)"')
                    or line:match('^You take a bite of your .-exist="(%d+)"')
                    or line:match('^You manage to take a drink from your .-exist="(%d+)"')
                    or line:match('^You manage to take a bite of your .-exist="(%d+)"')
        if eat_id then
            using = eat_id
        end

        -- Detect pouring with source and target IDs
        local pour_src, pour_dst = line:match('^You carefully pour a little bit from your .-exist="(%d+)".-into .-exist="(%d+)"')
        if pour_src then
            using = pour_src
            if pour_dst and tracker[pour_dst] then
                tracker[pour_dst] = tracker[pour_dst] + 1
            end
        end

        -- "The <item> has several doses left." (5-10 range, estimate 7)
        local sev_id = line:match('^The .-exist="(%d+)".-has several doses left%.')
        if sev_id then
            if not tracker[sev_id] or tracker[sev_id] < 5 or tracker[sev_id] > 10 then
                tracker[sev_id] = 7
            end
        end

        -- "The <item> has a few doses left." (3-4 range, estimate 4)
        local few_id = line:match('^The .-exist="(%d+)".-has a few doses left%.')
        if few_id then
            if not tracker[few_id] or tracker[few_id] < 3 or tracker[few_id] > 4 then
                tracker[few_id] = 4
            end
        end

        -- Exact numeric doses: "The <item> has N doses left."
        local exact_id, exact_ct = line:match('^The .-exist="(%d+)".-has (%d+) doses left%.')
        if exact_id and exact_ct then
            tracker[exact_id] = tonumber(exact_ct)
        end

        -- 1 dose left
        local one_dose_id = line:match('^The .-exist="(%d+)".-has 1 dose left%.')
        if one_dose_id then
            tracker[one_dose_id] = 1
        end

        -- "seems to have plenty of bites left" (11-50 range, estimate 50)
        local plenty_id = line:match('exist="(.-)".-seems to have plenty of bites left%.')
        if plenty_id then
            if not tracker[plenty_id] or tracker[plenty_id] < 11 or tracker[plenty_id] > 50 then
                tracker[plenty_id] = 50
            end
        end

        -- "looks like it has several bites left" (5-10 range)
        local sev_bite_id = line:match('^The .-exist="(.-)".-looks like it has several bites left%.')
        if sev_bite_id then
            if not tracker[sev_bite_id] or tracker[sev_bite_id] < 5 or tracker[sev_bite_id] > 10 then
                tracker[sev_bite_id] = 10
            end
        end

        -- "looks like it has a few bites left"
        local few_bite_id = line:match('^The .-exist="(.-)".-looks like it has a few bites left%.')
        if few_bite_id then
            if not tracker[few_bite_id] or tracker[few_bite_id] < 3 or tracker[few_bite_id] > 4 then
                tracker[few_bite_id] = 4
            end
        end

        -- Exact bites: "has N bites left."
        local bite_id, bite_ct = line:match('^The .-exist="(.-)".-has (%d+) bites left%.')
        if bite_id and bite_ct then
            tracker[bite_id] = tonumber(bite_ct)
        end

        -- 1 bite left: "has one bite left" or "has 1 bite left"
        local one_bite_id = line:match('^The .-exist="(.-)".-has one bite left%.')
                         or line:match('^The .-exist="(.-)".-has 1 bite left%.')
        if one_bite_id then
            tracker[one_bite_id] = 1
        end

        -- Purchase: "hands you <item> and says, Here's your purchase"
        local purchase_name = line:match('hands you <a exist="%d+".->(.-)</a> and says, "Here\'s your purchase')
        if purchase_name then
            for _, h in ipairs(herbs.database) do
                if h.name == purchase_name then
                    M._last_purchase_doses = h.doses
                    break
                end
            end
        end

        -- Bundle combine: "Carefully, you combine all your ... into one bundle."
        if line:find("^Carefully, you combine all your") then
            local rh = GameObj.right_hand()
            if rh and M._last_purchase_doses then
                local bid = rh.id
                if tracker[bid] then
                    tracker[bid] = tracker[bid] + (M._last_purchase_doses or 0)
                end
                M._last_purchase_doses = nil
            end
        end

        -- Separate dose from bundle: "You carefully remove one dose from your <item>"
        local sep_id = line:match('^You carefully remove one dose from your <a exist="(%d+)"')
        if sep_id then
            if tracker[sep_id] then
                tracker[sep_id] = tracker[sep_id] - 1
            end
        end

        return line  -- pass through, never squelch
    end)

    before_dying(function()
        DownstreamHook.remove("eherbs_monitor")
    end)
end

--- Debug message helper
function M.debug(state, msg)
    if state.debug then
        echo("[eherbs debug] " .. msg)
    end
end

--- Find herb in container matching a wound type
function M.find_herb_in_container(wound_type, container_noun, state)
    local inv = GameObj.inv()
    local use_yaba = state.use_yaba and wound_type == "blood"
    local use_potions = state.use_potions

    -- Pass 1: yabathilium check
    if use_yaba then
        for _, item in ipairs(inv) do
            if item.name and item.name:lower():find("yabathilium") then
                for _, herb in ipairs(herbs.database) do
                    if herb.type == "blood" and herb.short:lower():find("yabathilium") then
                        return item, herb
                    end
                end
            end
        end
    end

    -- Pass 2: prefer edible (if not use_potions) or drinkable (if use_potions)
    for _, item in ipairs(inv) do
        if item.noun then
            for _, herb in ipairs(herbs.database) do
                if herb.type == wound_type then
                    if item.name:lower():find(herb.short:lower(), 1, true) then
                        local is_drink = herbs.is_drinkable(item.noun)
                        if use_potions and is_drink then return item, herb end
                        if not use_potions and not is_drink then return item, herb end
                    end
                end
            end
        end
    end

    -- Pass 3: fallback to any matching herb
    for _, item in ipairs(inv) do
        if item.noun then
            for _, herb in ipairs(herbs.database) do
                if herb.type == wound_type then
                    if item.name:lower():find(herb.short:lower(), 1, true) then
                        return item, herb
                    end
                end
            end
        end
    end

    return nil, nil
end

--- Use an herb (eat or drink)
function M.use_herb(item, herb, container_noun, state)
    waitrt()
    fput("get #" .. item.id .. " from my " .. container_noun)

    local is_drink = herbs.is_drinkable(item.noun) or herb.drinkable
    local use_cmd
    if state.no_get then
        use_cmd = "eat " .. item.noun
    elseif is_drink then
        use_cmd = "drink my " .. item.noun
    else
        use_cmd = "eat my " .. item.noun
    end

    fput(use_cmd)
    waitrt()

    -- If herb is still in hand (didn't get consumed), put it back
    local rh = GameObj.right_hand()
    if rh and rh.id == item.id then
        fput("put my " .. item.noun .. " in my " .. container_noun)
    end
end

--- Stow both hands, return info about what was stowed
function M.stow_hands()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local stowed = { right = nil, left = nil }

    if rh then
        stowed.right = rh
        fput("stow right")
    end
    if lh then
        stowed.left = lh
        fput("stow left")
    end

    return stowed
end

--- Restore previously stowed hand items
function M.restore_hands(stowed)
    if stowed.left then
        fput("get #" .. stowed.left.id)
    end
    if stowed.right then
        fput("get #" .. stowed.right.id)
    end
end

--- Open a container, handling various response patterns
function M.open_container(container_noun)
    fput("open my " .. container_noun)
end

--- Cast spells before healing (Sigil of Mending, Song of Tonis, Aspect of Yierka)
function M.cast_spells(state)
    -- Sigil of Mending (9713) — Guardians of Sunfist rank 13+ only
    if state.use_mending then
        local gos_qualified = (not Society) or
                              (Society.status == "Guardians of Sunfist" and (Society.rank or 0) >= 13)
        if gos_qualified then
            local mending = Spell[9713]
            if mending and mending.known and mending.affordable then
                if not Spell.active_p(9713) then
                    waitcastrt()
                    fput("incant 9713")
                    waitrt()
                end
            end
        end
    end

    -- Song of Tonis (1035)
    if state.use_1035 then
        local tonis = Spell[1035]
        if tonis and tonis.known and tonis.affordable and not Spell.active_p(1035) then
            if diagnosis.able_to_cast() then
                waitcastrt()
                fput("incant 1035")
                waitrt()
            end
        end
    end

    -- Aspect of Yierka (650)
    if state.use_650 and diagnosis.able_to_cast() then
        local aspect = Spell[650]
        if aspect and aspect.known and aspect.affordable and not Spell.active_p(650) then
            waitcastrt()
            multifput("prep 650", "assume yierka")
            waitrt()
        elseif aspect and Spell.active_p(650) then
            -- Already prepped, just assume
            if GameState.mana and GameState.mana > 25 then
                waitcastrt()
                fput("assume yierka")
                waitrt()
            end
        end
    end
end

--- Check for cutthroat status and handle it
function M.check_cutthroat(state)
    if not cutthroat or not cutthroat() then return false end

    respond("[eherbs] You have cutthroat and cannot speak without spewing blood everywhere.")

    if state.heal_cutthroat and state.use_npchealer then
        Script.run("go2", "npchealer")
        fput("lie")
        respond("[eherbs] Waiting at NPC healer. This may take a minute!")
        wait_until(function() return not cutthroat() end)
        return true
    elseif state.heal_cutthroat then
        Script.run("go2", "town")
        pause(1)
        fput("act gasps while trying to hold the blood back from the throat gash")
        pause(1)
        fput("say Help me?")
        respond("[eherbs] Waiting on a healer. Exiting...")
        return true
    else
        respond("[eherbs] Your cut throat requires attention! Exiting...")
        return true
    end
end

--- Heal an NPC escort's wounds by looking at them and giving herbs
function M.heal_escort(state)
    local escort = nil
    local escort_arg = Script.vars and Script.vars[2]

    -- Find the escort NPC
    local npcs = GameObj.npcs()
    if escort_arg then
        for _, npc in ipairs(npcs) do
            if npc.id == escort_arg or npc.noun == escort_arg then
                escort = npc
                break
            end
        end
        if not escort then
            respond("[eherbs] Failed to find NPC with id or noun: " .. escort_arg)
            return
        end
    else
        for _, npc in ipairs(npcs) do
            if npc.type and npc.type:find("escort") then
                escort = npc
                break
            end
        end
        if not escort then
            respond("[eherbs] Failed to find an escort NPC in room")
            return
        end
    end

    respond("[eherbs] Healing escort: " .. escort.name)
    local container = state.herb_container or "herbsack"

    -- Open container
    M.open_container(container)

    -- Look at the escort to determine injuries
    fput("look #" .. escort.id)
    local look_lines = {}
    for i = 1, 15 do
        local line = get()
        if not line then break end
        look_lines[#look_lines + 1] = line
        if line:find("appears to be in good shape") then
            respond("[eherbs] Escort appears healthy, nothing to do")
            return
        end
        if line:find("^I could not find") then
            respond("[eherbs] Cannot see escort")
            return
        end
        if line:find("Obvious") or line == "" then break end
    end

    local look_text = table.concat(look_lines, " ")

    -- Injury pattern matching (from original eherbs.lic)
    local injury_patterns = {
        { pattern = "severe head trauma and bleeding from the ears", herbs = {"major head wound", "major head wound", "minor head wound"} },
        { pattern = "minor lacerations about the head and a possible mild concussion", herbs = {"major head wound", "minor head wound"} },
        { pattern = "snapped bones and serious bleeding from the neck", herbs = {"major head wound", "major head wound", "minor head wound"} },
        { pattern = "moderate bleeding from h", herbs = {"major head wound", "minor head wound"} },
        { pattern = "deep gashes and serious bleeding from h", herbs = {"major organ wound", "major organ wound", "minor organ wound"} },
        { pattern = "deep lacerations across h", herbs = {"major organ wound", "minor organ wound"} },
        { pattern = "a blinded", herbs = {"major organ wound", "major organ wound", "minor organ wound"} },
        { pattern = "a swollen", herbs = {"major organ wound", "minor organ wound"} },
        { pattern = "a completely severed", herbs = {"major limb wound", "major limb wound", "minor limb wound"} },
        { pattern = "a fractured and bleeding", herbs = {"major limb wound", "minor limb wound"} },
        { pattern = "a case of uncontrollable convulsions", herbs = {"major nerve wound", "minor nerve wound"} },
        { pattern = "a case of sporadic convulsions", herbs = {"major nerve wound", "minor nerve wound"} },
        { pattern = "minor bruises about the head", herbs = {"minor head wound"} },
        { pattern = "minor bruises on h", herbs = {"minor head wound"} },
        { pattern = "minor cuts and bruises on h", herbs = {"minor organ wound"} },
        { pattern = "a bruised", herbs = {"minor organ wound"} },
        { pattern = "some minor cuts and bruises on h", herbs = {"minor limb wound"} },
        { pattern = "a strange case of muscle twitching", herbs = {"minor nerve wound"} },
    }

    local escort_injuries = {}
    for _, ip in ipairs(injury_patterns) do
        if look_text:find(ip.pattern, 1, true) then
            for _, herb_type in ipairs(ip.herbs) do
                escort_injuries[#escort_injuries + 1] = herb_type
            end
        end
    end

    if #escort_injuries == 0 then
        respond("[eherbs] No detectable injuries on escort")
        return
    end

    M.debug(state, "Escort injuries: " .. table.concat(escort_injuries, ", "))

    -- Stow current hand items
    local stowed = M.stow_hands()

    -- For each injury, find and give herb
    for _, herb_type in ipairs(escort_injuries) do
        -- Check if we already have the right herb in hand
        local in_hand = false
        local rh = GameObj.right_hand()
        if rh and rh.noun then
            for _, h in ipairs(herbs.database) do
                if h.type == herb_type and rh.name:lower():find(h.short:lower(), 1, true) then
                    in_hand = true
                    break
                end
            end
        end

        if not in_hand then
            -- Stow current herb if any
            rh = GameObj.right_hand()
            if rh and rh.id then
                fput("put #" .. rh.id .. " in my " .. container)
            end

            -- Find and get herb from container
            local item, herb = M.find_herb_in_container(herb_type, container, state)
            if item then
                waitrt()
                fput("get #" .. item.id .. " from my " .. container)
            else
                respond("[eherbs] No herb available for: " .. herb_type)
                goto continue_escort
            end
        end

        -- Give herb to escort (not tend!)
        fput("give #" .. escort.id)
        waitrt()

        ::continue_escort::
    end

    -- Stow remaining herb and restore hands
    local rh = GameObj.right_hand()
    if rh and rh.id then
        fput("put #" .. rh.id .. " in my " .. container)
    end
    M.restore_hands(stowed)
end

--- Heal a dead player using APPRAISE-based wound detection
function M.heal_dead_player(player_name, full_heal, container_noun, state)
    local pcs = GameObj.pcs()
    local target = nil
    for _, pc in ipairs(pcs) do
        if pc.name:lower():find(player_name:lower(), 1, true) then
            target = pc
            break
        end
    end
    if not target then
        respond("[eherbs] Player not found: " .. player_name)
        return
    end
    if not (target.status and target.status:lower():find("dead")) then
        respond("[eherbs] " .. target.name .. " does not appear to be dead")
        return
    end

    respond("[eherbs] Healing " .. target.name .. (full_heal and " (full)" or " (blood only)"))
    local container = container_noun or state.herb_container or "herbsack"

    -- Open container
    M.open_container(container)

    -- Stow hands
    local stowed = M.stow_hands()

    local no_herb = false
    while true do
        -- Appraise the dead character
        fput("appraise " .. target.name)
        local appraisal_lines = {}
        for i = 1, 20 do
            local line = get()
            if not line then break end
            appraisal_lines[#appraisal_lines + 1] = line
            if line:find("Appraise what") or line:find("Usage") then
                respond("[eherbs] " .. player_name .. " not found for appraisal")
                M.restore_hands(stowed)
                return
            end
            if line:find("Roundtime") or line == "" then break end
        end

        M.debug(state, "Appraisal lines: " .. table.concat(appraisal_lines, " | "))

        local deader_injuries = diagnosis.appraise_character(appraisal_lines, full_heal)

        if #deader_injuries == 0 then
            respond("[eherbs] " .. target.name .. ": Healdown finished")
            break
        end

        for _, herb_type in ipairs(deader_injuries) do
            M.debug(state, "Dead player needs: " .. herb_type)

            -- Check if we already have a drinkable herb of this type in hand
            local herb_in_hand = nil
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            for _, hand_item in ipairs({rh, lh}) do
                if hand_item and hand_item.noun then
                    for _, h in ipairs(herbs.database) do
                        if h.type == herb_type and h.drinkable
                           and (hand_item.name:lower():find(h.short:lower(), 1, true)) then
                            herb_in_hand = hand_item
                            break
                        end
                    end
                end
                if herb_in_hand then break end
            end

            if not herb_in_hand then
                -- Stow current herb
                rh = GameObj.right_hand()
                if rh and rh.id then
                    fput("put #" .. rh.id .. " in my " .. container)
                end

                -- Find a DRINKABLE herb for dead players (must pour, not give)
                local found_item = nil
                local inv = GameObj.inv()
                for _, obj in ipairs(inv) do
                    if obj.noun then
                        for _, h in ipairs(herbs.database) do
                            if h.type == herb_type and h.drinkable
                               and obj.name:lower():find(h.short:lower(), 1, true) then
                                found_item = obj
                                break
                            end
                        end
                    end
                    if found_item then break end
                end

                if found_item then
                    waitrt()
                    fput("get #" .. found_item.id .. " from my " .. container)
                    herb_in_hand = found_item
                end
            end

            if herb_in_hand then
                -- Pour into dead character's mouth (must use "in", not "on")
                fput("pour #" .. herb_in_hand.id .. " in " .. target.name)
                waitrt()
            else
                respond("[eherbs] Missing potion for: " .. herb_type)
                no_herb = true
            end
        end

        if no_herb then
            respond("[eherbs] Missing a needed potion to finish healing. Exiting...")
            break
        end
    end

    -- Stow herbs and restore hands
    local rh = GameObj.right_hand()
    if rh and rh.id then
        fput("put #" .. rh.id .. " in my " .. container)
    end
    M.restore_hands(stowed)
end

return M
