local M = {}

--- Classify creatures into kill, flee, and safe targets.
-- @param hunting_area     HuntingArea table with spawn_rids, hunting_rids
-- @param target_creature  The target creature table {names={...}, level=N, spawn_ids={...}}
-- @param room_index       {[rid]=RoomData} with creature_names
-- @param creature_index   {[name]=creature} lookup
-- @param hunting_rids     array of hunting room ids
-- @param is_bounty        boolean
-- @param is_dangerous_creature_bounty  boolean
-- @param has_dangerous_creature_spawned boolean
-- @param char_level       number
-- @param find_creatures_in_vicinity_fn  function(hunting_rids_set, radius, room_index) → {[name]=true}
-- @return kill_targets (array), flee_targets (array), safe_targets (array)
function M.classify_targets(hunting_area, target_creature, room_index, creature_index,
                            hunting_rids, is_bounty, is_dangerous_creature_bounty,
                            has_dangerous_creature_spawned, char_level,
                            find_creatures_in_vicinity_fn)
    local kill_targets = {}
    local flee_targets = {}
    local safe_targets = {}

    -- Collect creature names that spawn in the hunting area's spawn_rids
    local hunting_area_creature_names = {}
    for rid in pairs(hunting_area.spawn_rids) do
        if room_index[rid] then
            for name in pairs(room_index[rid].creature_names) do
                hunting_area_creature_names[name] = true
            end
        end
    end

    -- For dangerous creature bounties, add ancient/grizzled variants
    if is_dangerous_creature_bounty then
        for _, name in ipairs(target_creature.names) do
            local trimmed = name:gsub("^ancient ", ""):gsub("^grizzled ", "")
            kill_targets[#kill_targets + 1] = "ancient " .. trimmed
            kill_targets[#kill_targets + 1] = "grizzled " .. trimmed
        end
    end

    -- If dangerous creature hasn't spawned yet, add normal names
    if not has_dangerous_creature_spawned then
        for _, name in ipairs(target_creature.names) do
            kill_targets[#kill_targets + 1] = name
        end
    end

    -- Build set of kill target names for fast lookup
    local kill_set = {}
    for _, name in ipairs(kill_targets) do kill_set[name] = true end

    -- Find creatures in vicinity (wander radius 10)
    local hunting_rids_set = {}
    for _, rid in ipairs(hunting_rids) do hunting_rids_set[rid] = true end
    local creatures_in_proximity = find_creatures_in_vicinity_fn(hunting_rids_set, 10, room_index)

    local target_level = target_creature.level or char_level
    local max_ref = math.max(target_level, char_level)

    local processed = {}
    for creature_name in pairs(creatures_in_proximity) do
        if not processed[creature_name] then
            processed[creature_name] = true

            local is_kill = kill_set[creature_name]
            local creature = creature_index[creature_name]

            -- If creature level unknown, consider it a flee target
            if not creature or not creature.level then
                if not is_kill then
                    flee_targets[#flee_targets + 1] = creature_name
                end
            else
                local level = creature.level
                local is_safe = (level + 10 <= max_ref)
                local is_weak = (level + 5 <= max_ref)
                local is_good = (level <= math.max(target_level, char_level - 1))

                if is_kill or is_safe or is_good then
                    -- Add as kill target if appropriate conditions are met
                    if not is_kill and
                       (not is_bounty and not is_safe and not is_weak or #hunting_rids <= 15) and
                       not has_dangerous_creature_spawned and
                       hunting_area_creature_names[creature_name] then
                        kill_targets[#kill_targets + 1] = creature_name
                        kill_set[creature_name] = true
                    end

                    if is_safe then
                        safe_targets[#safe_targets + 1] = creature_name
                    end
                else
                    flee_targets[#flee_targets + 1] = creature_name
                end
            end
        end
    end

    return kill_targets, flee_targets, safe_targets
end

--- Format kill targets for bigshot profile (prepend regex for boss/glam variants).
-- @param kill_targets     array of creature names
-- @return array of formatted target strings
function M.format_kill_targets_for_bigshot(kill_targets)
    local formatted = {}
    for _, name in ipairs(kill_targets) do
        if name:match("^ancient ") or name:match("^grizzled ") then
            formatted[#formatted + 1] = name
        else
            formatted[#formatted + 1] = "(?:.*)" .. name
        end
    end
    return formatted
end

return M
