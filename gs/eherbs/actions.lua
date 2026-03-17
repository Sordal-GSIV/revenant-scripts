local herbs = require("lib/gs/herbs")

local M = {}

function M.find_herb_in_container(wound_type, container_noun, state)
    -- Try to find a matching herb by getting items from the container
    -- In practice, this searches GameObj container contents
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item.noun then
            -- Check if this item matches any herb for the wound type
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

function M.use_herb(item, herb, container_noun, state)
    -- Get herb from container
    waitrt()
    fput("get #" .. item.id .. " from my " .. container_noun)

    -- Eat or drink
    if herbs.is_drinkable(item.noun) then
        fput("drink my " .. item.noun)
    else
        fput("eat my " .. item.noun)
    end

    -- If herb is still in hand (didn't get consumed), put it back
    local rh = GameObj.right_hand()
    if rh and rh.id == item.id then
        fput("put my " .. item.noun .. " in my " .. container_noun)
    end
end

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

function M.restore_hands(stowed)
    if stowed.left then
        fput("get #" .. stowed.left.id)
    end
    if stowed.right then
        fput("get #" .. stowed.right.id)
    end
end

function M.heal_escort(state)
    -- Heal an NPC escort's wounds
    local npcs = GameObj.npcs()
    local escort = nil
    for _, npc in ipairs(npcs) do
        if npc.noun == "child" or npc.noun == "traveller" or npc.noun == "merchant" then
            escort = npc
            break
        end
    end
    if not escort then
        respond("[eherbs] No escort NPC found in room")
        return
    end
    respond("[eherbs] Healing escort: " .. escort.name)
    -- Use herbs on the escort instead of self
    -- This requires different commands: tend #id, apply herb to #id, etc.
    -- Simplified: use basic tend approach
    fput("tend #" .. escort.id)
end

function M.heal_dead_player(player_name, full_heal, container_noun, state)
    -- Heal a dead player's bleeding wounds
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
    respond("[eherbs] Healing " .. target.name .. (full_heal and " (full)" or " (blood only)"))

    -- For dead players, primarily need blood herbs (acantha)
    local herbs_db = require("lib/gs/herbs")
    local herb = herbs_db.find_by_type("blood")
    if herb then
        waitrt()
        fput("get my " .. herb.short .. " from my " .. container_noun)
        fput("give my " .. herb.short .. " to #" .. target.id)
    else
        respond("[eherbs] No blood herb available")
    end
end

return M
