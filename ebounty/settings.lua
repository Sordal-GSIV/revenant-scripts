local M = {}

local DEFAULTS = {
    bounty_types = {"boss_culling", "culling", "gem_collecting", "heirloom_loot", "skinning"},
    escort_types = {},
    boost_type = "",
    forage_options = {},
    heirloom_options = {},
    creature_exclude = {},
    herb_exclude = {},
    gem_exclude = {},
    location_exclude = {},
    culling_max = 30, gem_max = 30, herb_max = 30, skin_max = 30, extra_skin = 0,
    exp_pause = false, only_required_creatures = false,
    use_boosts = false, use_vouchers = false,
    skip_healing = false, remove_heirloom = false,
    once_and_done = false, new_bounty_on_exit = false,
    keep_hunting = false, basic = false,
    ranger_track = false, return_to_group = false,
    debug = false,
    selling_script = "eloot", healing_script = "eherbs",
    death_script = "", hording_script = "",
    escort_script = "escortgo2", rescue_script = "echild",
    gem_history = "",
    table_rest = false, bigshot_rest = false,
    custom_rest = false, resting_room = "",
    rest_random = false, use_script = false, use_script_name = "",
    join_player = false, join_list = "",
    use_buff_script = false, buff_script = "",
    forage_prep_commands = "", forage_prep_scripts = "",
    forage_post_commands = "", forage_post_scripts = "",
    heirloom_prep_commands = "", heirloom_prep_scripts = "",
    heirloom_post_commands = "", heirloom_post_scripts = "",
    escort_prep_commands = "", escort_prep_scripts = "",
    escort_post_commands = "", escort_post_scripts = "",
    wander_wait = 0.5,
    default_profile = "", bandits_profile = "", kill_bandits = false,
}

-- Initialize location/bad_room/profile slots
for i = 1, 12 do
    DEFAULTS["location" .. i] = ""
    DEFAULTS["bad_room" .. i] = ""
end
DEFAULTS.location1 = "Whistler's Pass"
DEFAULTS.location2 = "Widowmaker's Road"
DEFAULTS.location3 = "Old Logging Road"
DEFAULTS.bad_room1 = "37,38,39,40,41"
DEFAULTS.bad_room2 = "30609,30610,30611,30613,30614,30615,30616,30617,30618,30619,30811,30817,28918,28919,28920,28921,28922,28923,28929,28930,28931,28932,28978,29078,29079,29081,29089"
DEFAULTS.bad_room3 = "12532,12533,14729,3548,3762,3763"

for _, letter in ipairs({"a","b","c","d","e","f","g","h","i","j"}) do
    DEFAULTS["names_" .. letter] = ""
    DEFAULTS["profile_" .. letter] = ""
    DEFAULTS["kill_" .. letter] = false
end

function M.load()
    local st = {}
    local raw = CharSettings.ebounty_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and data then
            for k, v in pairs(data) do st[k] = v end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if st[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for i, item in ipairs(v) do copy[i] = item end
                st[k] = copy
            else
                st[k] = v
            end
        end
    end
    return st
end

function M.save(st)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        prefs[k] = st[k]
    end
    CharSettings.ebounty_prefs = Json.encode(prefs)
end

function M.list_contains(list, val)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do if v == val then return true end end
    return false
end

function M.list_add(list, val)
    if not M.list_contains(list, val) then
        list[#list + 1] = val
        table.sort(list)
    end
end

function M.list_remove(list, val)
    for i = #list, 1, -1 do
        if list[i] == val then table.remove(list, i) end
    end
end

function M.build_reject_list(st)
    local all = {
        "boss_culling", "culling", "heirloom_loot", "skinning",
        "heirloom_search", "foraging", "rescue", "escort",
        "kill_bandits", "gem_collecting",
    }
    local reject = {}
    for _, t in ipairs(all) do
        if not M.list_contains(st.bounty_types or {}, t) then
            reject[#reject + 1] = t
        end
    end
    return reject
end

function M.build_bad_rooms(st)
    local bad = {}
    for i = 1, 12 do
        local val = st["bad_room" .. i] or ""
        if val ~= "" then
            for room in val:gmatch("[^,%s]+") do
                local id = tonumber(room)
                if id then bad[#bad + 1] = id end
            end
        end
    end
    return bad
end

return M
