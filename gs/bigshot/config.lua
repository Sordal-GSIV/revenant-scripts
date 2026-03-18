--- Bigshot Configuration — full parity with Lich5 bigshot v5.12.x
-- All 100+ settings from UserVars.op, stored via CharSettings as JSON.
-- Profiles saved/loaded as JSON files under _bigshot_profiles/.

local M = {}

---------------------------------------------------------------------------
-- DEFAULTS — mirrors every key from Lich5 Setup.@@categories[:general]
-- and the runtime load_settings hash. String defaults match the original
-- Ruby "" / nil semantics; booleans match the original true/false.
---------------------------------------------------------------------------
local DEFAULTS = {
    -- Profile / General
    profile_current         = "",
    save_profile_name       = "",
    notes                   = "",

    -- Resting — Where to Rest
    return_waypoint_ids     = "",      -- comma-separated room IDs (supports UIDs like u7000)
    resting_room_id         = "",      -- room ID or UID
    resting_commands        = "",      -- newline-separated commands to run before rest
    resting_scripts         = "",      -- newline-separated scripts to run while resting
    fog_return              = "0",     -- 0=none,1=130/Spirit Guide,2=Voln Symbol,3=1020/Traveler,4=GoS Sigil,5=Familiar Gate,6=Custom
    fog_optional            = false,   -- only fog if wounded/encumbered
    custom_fog              = "",      -- custom fog commands, comma-separated
    fog_rift                = false,   -- double-cast from rift

    -- Resting — Should Rest?
    fried                   = 100,     -- percentmind threshold to stop hunting (101 = never)
    overkill                = "",      -- extra kills after fried (blank = 0)
    lte_boost               = "",      -- long-term exp boosts to use
    oom                     = "",      -- mana % below which to rest
    encumbered              = 101,     -- encumbrance % threshold
    wounded_eval            = "",      -- Lua expression for wound check
    bounty_eval             = "",      -- bounty completion expression
    crushing_dread          = "",      -- dread level threshold
    creeping_dread          = "",      -- dread level threshold
    wot_poison              = false,   -- rest on Wall of Thorns poison
    confusion               = false,   -- rest on confusion debuff
    box_in_hand             = false,   -- rest if box stuck in hand after looting

    -- Hunting — Map
    hunting_room_id         = "",      -- starting hunt room ID or UID
    rallypoint_room_ids     = "",      -- comma-separated rally point room IDs
    hunting_boundaries      = "",      -- comma-separated boundary room IDs

    -- Hunting — Should Hunt? (rest-until thresholds)
    rest_till_exp           = "",      -- mind % to rest until
    rest_till_mana          = "",      -- mana % to rest until
    rest_till_spirit        = "",      -- spirit amount to rest until
    rest_till_percentstamina = "",     -- stamina % to rest until

    -- Hunting — Stances & Prep
    hunting_stance          = "",      -- stance during combat
    wander_stance           = "",      -- stance while wandering
    stand_stance            = "",      -- stance when standing up
    hunting_prep_commands   = "",      -- newline-separated pre-hunt commands
    hunting_scripts         = "",      -- newline-separated scripts to run during hunt
    signs                   = "",      -- comma-separated society signs/sigils/symbols
    loot_script             = "",      -- loot script name (default eloot at runtime)
    wracking_spirit         = "",      -- spirit threshold for wracking

    -- Hunting — Toggles
    priority                = false,   -- attack highest priority target first
    delay_loot              = false,   -- delay looting until combat done
    troubadours_rally       = false,   -- use 1040 for incapacitated group
    sneaky_sneaky           = false,   -- sneak while hunting
    use_wracking            = false,   -- use sign of wracking / sigil of power / symbol of mana
    loot_stance             = false,   -- switch to defensive before looting
    pull                    = true,    -- pull group members to feet
    deader                  = true,    -- stop for dead group members
    check_favor             = false,   -- check voln favor before using symbol

    -- Attacking
    ambush                  = "",      -- body part for ambush aiming (comma-separated cycle)
    archery_aim             = "",      -- body part for archery aiming (comma-separated cycle)
    flee_count              = 100,     -- number of enemies before fleeing
    invalid_targets         = "",      -- comma-separated creatures to ignore in count
    always_flee_from        = "",      -- comma-separated creatures to always flee
    flee_message            = "",      -- pipe-separated flee trigger messages
    wander_wait             = 0.3,     -- seconds to wait before wandering

    -- Attacking — Toggles
    boon_flee_from          = false,   -- legacy toggle: flee from boon/boss creatures
    flee_clouds             = false,
    flee_vines              = false,
    flee_webs               = false,
    flee_voids              = false,
    lone_targets_only       = false,   -- only approach rooms with 1 target
    weapon_reaction         = true,    -- use weapon reactive strikes
    bless                   = false,   -- stop hunt when blessing runs out

    -- Commands (A-J) — comma-separated, supports (xN) and "and" connectors
    hunting_commands        = "",      -- routine A
    hunting_commands_b      = "",
    hunting_commands_c      = "",
    hunting_commands_d      = "",
    hunting_commands_e      = "",
    hunting_commands_f      = "",
    hunting_commands_g      = "",
    hunting_commands_h      = "",
    hunting_commands_i      = "",
    hunting_commands_j      = "",
    disable_commands        = "",      -- commands when fried in group
    quick_commands          = "",      -- commands for quick mode
    targets                 = "",      -- creature->letter mapping like "troll(a),goblin(b)"
    quickhunt_targets       = "",      -- similar mapping for quick mode

    -- Boon Creatures — arrays of mode strings
    boons_all               = {},      -- modes: common / ignore / flee
    boons_ignore            = {},
    boons_flee              = {},
    -- Per-group boon arrays (immunity, misc, offensive, defensive)
    immunity                = {},
    misc                    = {},
    offensive               = {},
    defensive               = {},

    -- Misc — UAC (Unarmed Combat)
    tier3                   = "",      -- tier 3 unarmed attack (punch/grapple/kick)
    aim                     = "",      -- comma-separated aim locations for UAC cycle
    uac_smite               = false,   -- use voln smite in UAC
    uac_mstrike             = false,   -- prevent mstrike during unarmed

    -- Misc — Mstrike
    mstrike_stamina_cooldown    = "",  -- max stamina before mstrike (default: Char.max_stamina at runtime)
    mstrike_stamina_quickstrike = "",  -- stamina for quickstrike
    mstrike_mob                 = "",  -- min mob count for unfocused mstrike
    mstrike_cooldown            = false, -- mstrike during cooldown
    mstrike_quickstrike         = false, -- use quickstrike for mstrike

    -- Misc — Ammo & Wands
    ammo_container          = "",      -- container for ammo
    ammo                    = "",      -- ammo noun
    fresh_wand_container    = "",      -- container for fresh wands
    dead_wand_container     = "",      -- container for spent wands
    wand                    = "",      -- wand noun
    hide_for_ammo           = false,   -- hide before picking up ammo
    wand_if_oom             = false,   -- use wands when out of mana

    -- Misc — Multi-Account Grouping
    independent_travel      = false,   -- travel independently in group
    independent_return      = false,   -- return independently
    ma_looter               = "",      -- designated looter name
    never_loot              = "",      -- comma-separated names that never loot
    random_loot             = false,   -- random looter by encumbrance
    quiet_followers         = true,    -- followers wait for leader
    final_loot              = false,   -- leader does final room loot
    group_deader            = false,   -- stop for dead group members

    -- Monitoring
    dead_man_switch         = false,   -- auto-pause on death
    depart_switch           = false,   -- auto-depart and rerun
    monitor_interaction     = false,   -- monitor for GM interactions
    ignore_disks            = false,   -- ignore other players' disks
    monitor_strings         = "",      -- pipe-separated alert patterns
    monitor_safe_strings    = "",      -- pipe-separated safe patterns to suppress alerts

    -- Debug (stored in CharSettings directly in original, we keep in same blob)
    debug_combat            = false,
    debug_commands          = false,
    debug_status            = false,
    debug_system            = false,
    debug_file              = false,
}

--- Expose DEFAULTS for external inspection (e.g. gui_settings building loops)
M.DEFAULTS = DEFAULTS

---------------------------------------------------------------------------
-- Deep-copy a value (handles nested tables/arrays)
---------------------------------------------------------------------------
local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, item in pairs(v) do
        copy[k] = deep_copy(item)
    end
    return copy
end

---------------------------------------------------------------------------
-- M.load() — Load settings from CharSettings.bigshot_prefs (JSON).
-- Missing keys are filled from DEFAULTS so callers always see every key.
---------------------------------------------------------------------------
function M.load()
    local state = {}

    local raw = CharSettings.bigshot_prefs
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                state[k] = v
            end
        end
    end

    -- Merge defaults for any missing keys
    for k, v in pairs(DEFAULTS) do
        if state[k] == nil then
            state[k] = deep_copy(v)
        end
    end

    return state
end

---------------------------------------------------------------------------
-- M.save(state) — Persist to CharSettings as JSON.
-- Only writes keys that exist in DEFAULTS (avoids runtime-only transients).
---------------------------------------------------------------------------
function M.save(state)
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        if state[k] ~= nil then
            prefs[k] = state[k]
        end
    end
    CharSettings.bigshot_prefs = Json.encode(prefs)
end

---------------------------------------------------------------------------
-- Profile management — JSON files under _bigshot_profiles/
---------------------------------------------------------------------------

function M.save_profile(state, name)
    if not name or name == "" then
        respond("[bigshot] Error: profile name required")
        return
    end
    local prefs = {}
    for k, _ in pairs(DEFAULTS) do
        if state[k] ~= nil then
            prefs[k] = state[k]
        end
    end
    local dir = "_bigshot_profiles"
    if not File.exists(dir) then File.mkdir(dir) end
    File.write(dir .. "/" .. name .. ".json", Json.encode(prefs))
    respond("[bigshot] Profile saved: " .. name)
end

function M.load_profile(name)
    if not name or name == "" then
        respond("[bigshot] Error: profile name required")
        return nil
    end
    local path = "_bigshot_profiles/" .. name .. ".json"
    if not File.exists(path) then
        respond("[bigshot] Profile not found: " .. name)
        return nil
    end
    local raw, err = File.read(path)
    if not raw then
        respond("[bigshot] Error reading profile: " .. tostring(err))
        return nil
    end
    local ok, data = pcall(Json.decode, raw)
    if not ok or type(data) ~= "table" then
        respond("[bigshot] Error decoding profile: " .. name)
        return nil
    end

    -- Merge defaults so the returned table is complete
    for k, v in pairs(DEFAULTS) do
        if data[k] == nil then
            data[k] = deep_copy(v)
        end
    end
    return data
end

function M.list_profiles()
    local dir = "_bigshot_profiles"
    if not File.exists(dir) then return {} end
    local files = File.list(dir) or {}
    local profiles = {}
    for _, f in ipairs(files) do
        local name = f:match("^(.+)%.json$")
        if name then
            profiles[#profiles + 1] = name
        end
    end
    table.sort(profiles)
    return profiles
end

---------------------------------------------------------------------------
-- Parsing helpers — match Lich5 clean_value semantics
---------------------------------------------------------------------------

--- Parse comma-separated command string with (xN) repetition and "and" connectors.
-- Input:  "attack(x3),incant 302 and incant 303,hide(x2)"
-- Output: { "attack", "attack", "attack", {"incant 302", "incant 303"}, "hide", "hide" }
--
-- (xx) is a shorthand for (x5), matching Lich5 split_xx behavior.
-- An "and"-joined command becomes a sub-table (array) for parallel execution.
function M.parse_commands(str)
    if type(str) ~= "string" or str == "" then return {} end

    local result = {}
    -- Split on comma
    for token in str:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$") -- trim

        -- Check for (xN) or (xx) repetition suffix
        local cmd_part, rep
        local xn = token:match("^(.-)%s*%(x(%d+)%)%s*$")
        if xn then
            cmd_part = xn
            rep = tonumber(select(2, token:match("^(.-)%s*%(x(%d+)%)%s*$")))
        else
            local xx = token:match("^(.-)%s*%(xx%)%s*$")
            if xx then
                cmd_part = xx
                rep = 5
            else
                cmd_part = token
                rep = 1
            end
        end

        -- Split on " and " for parallel commands
        local and_parts = {}
        for part in cmd_part:gmatch("[^a][^n][^d]?") do end -- dummy; use proper split:
        and_parts = {}
        local pos = 1
        while true do
            -- Find " and " (case-sensitive, matching Ruby /\sand\s/)
            local s, e = cmd_part:find("%s+and%s+", pos)
            if s then
                local piece = cmd_part:sub(pos, s - 1):match("^%s*(.-)%s*$")
                if piece ~= "" then and_parts[#and_parts + 1] = piece end
                pos = e + 1
            else
                local piece = cmd_part:sub(pos):match("^%s*(.-)%s*$")
                if piece ~= "" then and_parts[#and_parts + 1] = piece end
                break
            end
        end

        -- Build the entry: single string or sub-array for "and" groups
        local entry
        if #and_parts == 1 then
            entry = and_parts[1]
        elseif #and_parts > 1 then
            entry = and_parts
        else
            entry = cmd_part:match("^%s*(.-)%s*$")
        end

        for _ = 1, rep do
            result[#result + 1] = entry
        end
    end

    return result
end

--- Parse "creature=letter" or "creature(letter)" target mapping.
-- Input:  "troll(a),goblin(b),spider"
-- Output: { troll = "a", goblin = "b", spider = "a" }
--
-- Supports both "creature(X)" and "creature=X" syntax.
-- Untagged creatures default to "a" (or "quick" for quickhunt_targets — caller decides).
function M.parse_targets(str, default_letter)
    default_letter = default_letter or "a"
    if type(str) ~= "string" or str == "" then return {} end

    local targets = {}
    for token in str:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$") -- trim

        -- Try "creature(X)" format (Lich5 native)
        local name, letter = token:match("^(.-)%s*%(([a-jA-J])%)%s*$")
        if not name then
            -- Try "creature=X" format (alternative)
            name, letter = token:match("^(.-)%s*=%s*([a-jA-J])%s*$")
        end

        if name and letter then
            targets[name:lower():match("^%s*(.-)%s*$")] = letter:lower()
        elseif token ~= "" then
            targets[token:lower()] = default_letter
        end
    end

    return targets
end

--- Split a string by comma, trim whitespace from each element.
-- Returns an array of trimmed strings. Empty input returns {}.
function M.parse_csv(str)
    if type(str) ~= "string" or str == "" then return {} end
    local result = {}
    for token in str:gmatch("[^,]+") do
        local trimmed = token:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            result[#result + 1] = trimmed
        end
    end
    return result
end

--- Safe integer parse with default fallback.
function M.parse_int(val, default)
    if val == nil or val == "" then return default or 0 end
    local n = tonumber(val)
    if n then return math.floor(n) end
    return default or 0
end

--- Safe float parse with default fallback.
function M.parse_float(val, default)
    if val == nil or val == "" then return default or 0.0 end
    local n = tonumber(val)
    if n then return n end
    return default or 0.0
end

--- Parse pipe-separated string into an array.
-- Used for flee_message, monitor_strings, monitor_safe_strings.
function M.parse_pipe(str)
    if type(str) ~= "string" or str == "" then return {} end
    local result = {}
    for token in str:gmatch("[^|]+") do
        local trimmed = token:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            result[#result + 1] = trimmed
        end
    end
    return result
end

--- Parse newline-separated string into an array.
-- Used for resting_commands, resting_scripts, hunting_prep_commands, hunting_scripts.
function M.parse_lines(str)
    if type(str) ~= "string" or str == "" then return {} end
    local result = {}
    for line in str:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            result[#result + 1] = trimmed
        end
    end
    return result
end

return M
