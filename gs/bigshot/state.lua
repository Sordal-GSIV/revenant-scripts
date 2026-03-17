--- Bigshot State — predicates and target selection
-- All decision logic: should_rest, should_hunt, should_flee, valid_target, etc.

local M = {}

-- Target selection: sort NPCs by priority from TARGETS map
function M.sort_npcs(targets_map)
    local npcs = GameObj.npcs()
    if not npcs or #npcs == 0 then return {} end

    local sorted = {}
    for _, npc in ipairs(npcs) do
        if npc.status ~= "dead" and npc.status ~= "gone" then
            -- Find priority from targets map
            local priority = 99
            for creature_name, letter in pairs(targets_map or {}) do
                if npc.name:lower():find(creature_name:lower(), 1, true) then
                    -- a=1, b=2, ... j=10
                    priority = string.byte(letter) - string.byte("a") + 1
                    break
                end
            end
            sorted[#sorted + 1] = { npc = npc, priority = priority }
        end
    end

    table.sort(sorted, function(a, b) return a.priority < b.priority end)

    local result = {}
    for _, entry in ipairs(sorted) do
        result[#result + 1] = entry.npc
    end
    return result
end

-- Find best target from sorted NPC list
function M.find_target(targets_map, state)
    local sorted = M.sort_npcs(targets_map)
    for _, npc in ipairs(sorted) do
        if M.valid_target(npc, state) then
            return npc
        end
    end
    return nil
end

-- Check if a target is valid (not dead, not excluded, not untargetable)
function M.valid_target(npc, state)
    if not npc then return false end
    if npc.status == "dead" or npc.status == "gone" then return false end

    -- Check critter exclusion list
    local name_lower = (npc.name or ""):lower()
    for _, excl in ipairs(state.critter_exclude or {}) do
        if name_lower:find(excl:lower(), 1, true) then return false end
    end

    return true
end

-- Should the character flee?
function M.should_flee(state)
    -- Flee count: too many enemies
    if state.flee_count and state.flee_count > 0 then
        local npcs = GameObj.npcs()
        local count = 0
        for _, npc in ipairs(npcs or {}) do
            if npc.status ~= "dead" and npc.status ~= "gone" then
                count = count + 1
            end
        end
        if count >= state.flee_count then return true, "too many enemies" end
    end

    -- Always flee from specific creatures
    if state.always_flee_from then
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs or {}) do
            local name_lower = (npc.name or ""):lower()
            for _, flee_name in ipairs(state.always_flee_from) do
                if name_lower:find(flee_name:lower(), 1, true) then
                    return true, "flee from " .. npc.name
                end
            end
        end
    end

    return false, nil
end

-- Should the character rest?
function M.should_rest(state)
    -- Wounded
    if M.is_wounded() then return true, "wounded" end

    -- Fried (mind full)
    if state.rest_till_exp and GameState.mind_value then
        if GameState.mind_value >= (state.rest_till_exp or 80) then
            return true, "fried"
        end
    end

    -- Out of mana
    if state.rest_till_mana and Char.percent_mana then
        if Char.percent_mana <= (100 - (state.rest_till_mana or 80)) then
            return true, "low mana"
        end
    end

    -- Encumbered
    if Char.percent_encumbrance and Char.percent_encumbrance >= 80 then
        return true, "encumbered"
    end

    return false, nil
end

-- Is the character ready to hunt again?
function M.ready_to_hunt(state)
    if M.is_wounded() then return false end

    if state.rest_till_exp and GameState.mind_value then
        if GameState.mind_value > (state.rest_till_exp or 80) then return false end
    end

    if state.rest_till_mana and Char.percent_mana then
        if Char.percent_mana < (state.rest_till_mana or 80) then return false end
    end

    if state.rest_till_spirit and Char.spirit then
        if Char.spirit < (state.rest_till_spirit or 100) then return false end
    end

    if state.rest_till_percentstamina and Char.percent_stamina then
        if Char.percent_stamina < (state.rest_till_percentstamina or 80) then return false end
    end

    return true
end

-- Check if character has wounds
function M.is_wounded()
    if not Wounds then return false end
    local parts = {"head", "neck", "torso", "rightArm", "leftArm",
                   "rightHand", "leftHand", "rightLeg", "leftLeg", "nsys"}
    for _, part in ipairs(parts) do
        if Wounds[part] and Wounds[part] > 0 then return true end
    end
    return false
end

return M
