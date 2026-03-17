local M = {}

local DEFAULTS = {
    -- Resting
    rest_room = "",
    rest_till_exp = 80,
    rest_till_mana = 80,
    rest_till_spirit = 100,
    rest_till_percentstamina = 80,
    resting_commands = {},
    resting_scripts = {},
    resting_prep_commands = {},

    -- Hunting
    hunting_room_id = 0,
    hunting_boundaries = {},
    hunting_stance = "offensive",
    defensive_stance = "defensive",
    wander_wait = 0,
    hunting_prep_commands = {},
    hunting_scripts = {},

    -- Commands (A-J)
    hunting_commands = {},
    hunting_commands_b = {},
    hunting_commands_c = {},
    hunting_commands_d = {},
    hunting_commands_e = {},
    hunting_commands_f = {},
    hunting_commands_g = {},
    hunting_commands_h = {},
    hunting_commands_i = {},
    hunting_commands_j = {},
    targets = {},
    quick_commands = {},
    disable_commands = {},

    -- Attacking
    flee_count = 0,
    always_flee_from = {},
    signs = {},

    -- Misc
    use_wracking = false,
    loot_script = "eloot",
    designated_looter = "",
    fog_return = "",
    fog_return_commands = {},
    skin_enable = false,
    use_disk = false,
    coin_hand = "",

    -- Bounty
    bounty_mode = false,

    -- Navigation
    rally_room = "",
    waypoints = {},
    independent_travel = false,
    independent_return = false,

    -- Monitoring
    dead_man_switch = false,
    interaction_monitor = false,

    -- Multi-account
    ma_mode = "",  -- "", "head", "tail"
    ma_count = 1,
    quiet_followers = false,

    -- Debug
    debug_combat = false,
    debug_commands = false,
    debug_status = false,
    debug_system = false,
}

function M.load()
    local state = {}
    local raw = CharSettings.bigshot_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do state[k] = v end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then
            if type(v) == "table" then
                state[k] = {}
                for i, item in ipairs(v) do state[k][i] = item end
            else
                state[k] = v
            end
        end
    end
    return state
end

function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = state[k]
    end
    CharSettings.bigshot_prefs = Json.encode(prefs)
end

-- Profile management
function M.save_profile(state, name)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do prefs[k] = state[k] end
    local dir = "_bigshot_profiles"
    if not File.exists(dir) then File.mkdir(dir) end
    File.write(dir .. "/" .. name .. ".json", Json.encode(prefs))
    respond("[bigshot] Profile saved: " .. name)
end

function M.load_profile(name)
    local path = "_bigshot_profiles/" .. name .. ".json"
    if not File.exists(path) then
        respond("[bigshot] Profile not found: " .. name)
        return nil
    end
    local raw, err = File.read(path)
    if not raw then return nil end
    local ok, data = pcall(Json.decode, raw)
    if ok and data then return data end
    return nil
end

function M.list_profiles()
    local dir = "_bigshot_profiles"
    if not File.exists(dir) then return {} end
    local files = File.list(dir) or {}
    local profiles = {}
    for _, f in ipairs(files) do
        local name = f:match("^(.+)%.json$")
        if name then profiles[#profiles + 1] = name end
    end
    return profiles
end

return M
