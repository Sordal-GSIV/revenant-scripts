local M = {}

-- Default settings
M.defaults = {
    default_profile = "default",
    bounty_profile  = "bounty",
    ebounty_slot    = "a",
}

-- Town → resting room_id mapping
M.resting_rooms = {
    ["Icemule Trace"]      = 2300,
    ["Kharam-Dzu"]         = 1932,
    ["Kraken's Fall"]      = 28813,
    ["Mist Harbor"]        = 3668,
    ["River's Rest"]       = 10861,
    ["Solhaven"]           = 1438,
    ["Ta'Illistim"]        = 188,
    ["Ta'Vaalor"]          = 3519,
    ["Wehnimer's Landing"] = 228,
    ["Zul Logoth"]         = 1005,
    ["Cold River"]         = 29870,
    -- Aliases
    ["Wehnimer's Landing and Icemule Trace"] = 228,
    ["Wehnimer's Landing and Solhaven"]      = 228,
    ["the Broken Lands"]   = 228,
    ["Vornavis"]           = 1438,
}

--- Load huntplan settings from CharSettings.
-- @return settings table with defaults applied
function M.load_settings()
    local settings = {}
    for k, v in pairs(M.defaults) do
        local saved = CharSettings.get("huntplan_" .. k)
        settings[k] = saved or v
    end
    return settings
end

--- Save huntplan settings to CharSettings.
function M.save_settings(settings)
    for k in pairs(M.defaults) do
        if settings[k] then
            CharSettings.set("huntplan_" .. k, settings[k])
        end
    end
end

--- Find resting room for a bounty town, or nearest from starting_rid.
-- @param bounty_town  string or nil
-- @param starting_rid number
-- @return resting room id
function M.find_resting_room(bounty_town, starting_rid)
    if bounty_town and M.resting_rooms[bounty_town] then
        return M.resting_rooms[bounty_town]
    end
    -- Find nearest resting room from starting_rid
    local all_rids = {}
    local seen = {}
    for _, rid in pairs(M.resting_rooms) do
        if not seen[rid] then
            seen[rid] = true
            all_rids[#all_rids + 1] = rid
        end
    end
    local target_set = {}
    for _, rid in ipairs(all_rids) do target_set[rid] = true end
    local pathfinding = require("pathfinding")
    local nearest, _ = pathfinding.find_nearest_with_time(starting_rid, target_set, nil)
    return nearest
end

--- Write hunting plan results to bigshot profile settings via CharSettings.
-- @param results  table with keys: resting_room_id, hunting_room_id, hunting_boundaries,
--                 targets, always_flee_from, invalid_targets
-- @param profile_name  string — the bigshot profile to write to
function M.write_bigshot_profile(results, profile_name)
    local prefix = "bigshot_" .. profile_name .. "_"
    for key, value in pairs(results) do
        CharSettings.set(prefix .. key, value)
    end
end

--- Write ebounty slot settings.
-- @param slot           string (a-j)
-- @param creature_name  string
-- @param profile_name   string
function M.write_ebounty_slot(slot, creature_name, profile_name)
    CharSettings.set("ebounty_names_" .. slot, creature_name)
    CharSettings.set("ebounty_profile_name_" .. slot, profile_name)
    CharSettings.set("ebounty_profile_" .. slot, profile_name)
    CharSettings.set("ebounty_kill_" .. slot, false)
end

--- Validate ebounty slot.
-- @param slot  string
-- @return boolean
function M.valid_ebounty_slot(slot)
    return slot and slot:match("^[a-j]$") ~= nil
end

return M
