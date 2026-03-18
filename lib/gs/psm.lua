-- Unified PSM module — registers CMan, Feat, Shield, Armor, Weapon, Ascension, Warcry as globals

local function normalize(name)
    return name:lower():gsub("[%s%-']", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function make_psm(prefix)
    local t = {}

    -- known_p: is skill known? (rank >= 1 in Infomon)
    function t.known_p(name)
        local val = Infomon.get(prefix .. "." .. normalize(name))
        return val == "learned" or val == "active"
    end

    -- known: alias for known_p (matches Lich5 Weapon.known?/CMan.known? etc.)
    function t.known(name)
        return t.known_p(name)
    end

    -- active_p: is skill currently active?
    function t.active_p(name)
        return Infomon.get(prefix .. "." .. normalize(name)) == "active"
    end

    -- available(name): not overexerted AND not on cooldown.
    -- Matches Lich5 PSMS.available?(name) — does NOT check known/stamina (those are separate).
    function t.available(name)
        -- Check for overexerted debuff
        if Effects and Effects.Debuffs and Effects.Debuffs.active("Overexerted") then
            return false
        end
        -- Check not on cooldown (Effects.Cooldowns stores by game text, e.g. "Clash", "Fury")
        if Effects and Effects.Cooldowns then
            -- Try both the raw name and normalized form
            if Effects.Cooldowns.active(name) then return false end
        end
        return true
    end

    -- list_known: return array of {name, status} for all known skills in this category
    function t.list_known()
        local result = {}
        for _, kv in ipairs(Infomon.keys()) do
            if kv:match("^" .. prefix .. "%.") then
                local skill_name = kv:sub(#prefix + 2)
                local val = Infomon.get(kv)
                if val == "learned" or val == "active" then
                    result[#result + 1] = { name = skill_name, status = val }
                end
            end
        end
        return result
    end

    -- Metatable for CMan["name"] style access (checks known_p)
    return setmetatable(t, {
        __index = function(_, key)
            if type(key) == "string" and rawget(t, key) == nil then
                return t.known_p(key)
            end
            return rawget(t, key)
        end
    })
end

CMan = make_psm("cman")
Feat = make_psm("feat")
Shield = make_psm("shield")
Armor = make_psm("armor")
Weapon = make_psm("weapon")
Ascension = make_psm("ascension")

-- Warcry is different: list of known warcries + execution
Warcry = {
    known = function()
        local result = {}
        for _, kv in ipairs(Infomon.keys()) do
            if kv:match("^warcry%.") then
                result[#result + 1] = kv:sub(8)
            end
        end
        return result
    end,
    -- use(name, target) — attempt to execute a warcry, optionally at a target.
    -- name: warcry name string (e.g. "Cry", "Bertrandts Bellow") — normalized to lowercase cmd form.
    -- target: optional target string (e.g. "all", "goblin") or nil.
    -- Waits for roundtime. Returns the matching result line or nil.
    use = function(name, target)
        waitrt()
        waitcastrt()
        local cmd = "warcry " .. name:lower():gsub("[%s%-']", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
        if target and target ~= "" then
            cmd = cmd .. " " .. target
        end
        local result = dothistimeout(cmd, 5,
            "Roundtime|is still in cooldown|You are unable|You feel your|You don't seem|what%?$|^You bellow")
        waitrt()
        waitcastrt()
        return result
    end,
}

-- CMan.use(name, target) — attempt to execute a combat maneuver, optionally at a target.
-- name: maneuver name (e.g. "eviscerate", "Stance Perfection") — normalized to underscore form.
-- target: optional target string or nil.
-- Returns the matching result line or nil.
function CMan.use(name, target)
    waitrt()
    waitcastrt()
    local normalized = name:lower():gsub("[%s%-']", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    local cmd = "cman " .. normalized
    if target and target ~= "" then
        cmd = cmd .. " " .. target
    end
    local result = dothistimeout(cmd, 5,
        "Roundtime|is still in cooldown|You are unable|You don't seem|what%?$|^You ")
    waitrt()
    waitcastrt()
    return result
end

-------------------------------------------------------------------------------
-- PSMS module — stamina cost checks and failure pattern detection.
-- Matches Lich5's PSMS.assess / PSMS.available? / PSMS::FAILURES_REGEXES.
-------------------------------------------------------------------------------

-- Weapon technique stamina costs (from Lich5 lib/gemstone/psms/weapon.rb)
local WEAPON_COSTS = {
    barrage       = 15,
    charge        = 14,
    clash         = 20,
    clobber       = 0,
    cripple       = 7,
    cyclone       = 20,
    dizzyingswing = 7,
    dizzying_swing = 7,
    flurry        = 15,
    fury          = 15,
    gthrusts      = 15,
    guardant_thrusts = 15,
    overpower     = 0,
    pindown       = 14,
    pin_down      = 14,
    pulverize     = 20,
    pummel        = 15,
    radialsweep   = 0,
    radial_sweep  = 0,
    reactiveshot  = 0,
    reactive_shot = 0,
    reversestrike = 0,
    reverse_strike = 0,
    riposte       = 0,
    spinkick      = 0,
    spin_kick     = 0,
    thrash        = 15,
    twinhammer    = 7,
    twin_hammerfists = 7,
    volley        = 20,
    wblade        = 20,
    whirling_blade = 20,
    whirlwind     = 20,
}

-- Common PSM failure message Lua patterns (mirrors Lich5's PSMS::FAILURES_REGEXES)
local PSM_FAILURE_PATTERNS = {
    "^And give yourself away!  Never!$",
    "^You are unable to do that right now%.$",
    "^You don't seem to be able to move to do that%.$",
    "^Provoking a GameMaster is not such a good idea%.$",
    "^You do not currently have a target%.$",
    "^Your mind clouds with confusion and you glance around uncertainly%.$",
    "^But your hands are full!$",
    "^You are still stunned%.$",
    "^You lack the momentum to attempt another skill%.$",
    "You can't reach .+!$",
    "attempting to .+ would be a rather awkward proposition%.$",
}

PSMS = {}

-- PSMS.is_failure(text): returns true if text matches a known PSM failure message
function PSMS.is_failure(text)
    if not text then return false end
    for _, pat in ipairs(PSM_FAILURE_PATTERNS) do
        if string.find(text, pat) then return true end
    end
    return false
end

-- PSMS.assess(name, type, costcheck):
--   costcheck=true  → check current stamina > skill stamina cost; returns bool
--   costcheck=false → return Infomon rank for the skill; returns rank value or nil
-- Matches Lich5 PSMS.assess(name, "Weapon", true/false)
function PSMS.assess(name, psm_type, costcheck)
    if costcheck == nil then costcheck = false end
    local key = normalize(name)
    if psm_type == "Weapon" or psm_type == "weapon" then
        if costcheck then
            local cost = WEAPON_COSTS[key]
            if cost == nil then
                -- Unknown weapon technique — fail safe
                return false
            end
            local cur_stamina = (GameState and GameState.stamina) or 0
            return cur_stamina > cost
        else
            -- Return rank check (truthy if known)
            return Weapon and Weapon.known_p(name)
        end
    end
    -- Other PSM types (CMan, Feat, Shield, Armor, Ascension): no stamina cost
    if costcheck then return true end
    local mod_map = {
        CMan = CMan, Feat = Feat, Shield = Shield,
        Armor = Armor, Ascension = Ascension,
    }
    local mod = mod_map[psm_type]
    if mod then return mod.known_p(name) end
    return false
end

-- PSMS.available(name): not overexerted + not on cooldown (delegate to Weapon.available)
-- Convenience wrapper matching Lich5 PSMS.available?(name)
function PSMS.available(name)
    if Effects and Effects.Debuffs and Effects.Debuffs.active("Overexerted") then
        return false
    end
    if Effects and Effects.Cooldowns and Effects.Cooldowns.active(name) then
        return false
    end
    return true
end

return true -- globals already registered
