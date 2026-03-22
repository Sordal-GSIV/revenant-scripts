-- Unified PSM module — registers CMan, Feat, Shield, Armor, Weapon, Ascension, Warcry as globals

-- normalize: underscore form used for building game commands (e.g. "cman spine_grind")
local function normalize(name)
    return name:lower():gsub("[%s%-']", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

-- find_psm_key: resolve a display name to the infomon key suffix.
-- Infomon stores PSM commands as the game's short command name (captured by [a-z]+ in the
-- PSM_LINE regex), e.g. "Absorb Magic" → "absorbmagic", "Shield Mind" → "mind".
-- Strategy:
--   1. Simple concat (lowercase, strip spaces/punctuation) — covers most feats/cmans
--   2. Individual word scan — covers abbreviated commands like "mind" for "Shield Mind"
--   3. Fallback to simple form (key may not exist in infomon yet)
local function find_psm_key(prefix, name)
    -- Attempt 1: lowercase, no spaces or punctuation
    local s1 = name:lower():gsub("[%s%-']", "")
    if Infomon.get(prefix .. "." .. s1) then return s1 end

    -- Attempt 2: each word individually (handles "Shield Mind" → key "mind")
    for word in name:lower():gmatch("%a+") do
        if #word >= 3 and Infomon.get(prefix .. "." .. word) then
            return word
        end
    end

    return s1  -- fallback: return simple form even if not yet in infomon
end

local function make_psm(prefix)
    local t = {}

    -- known_p: is skill known? (rank >= 1 in Infomon)
    -- Infomon stores integer rank strings (e.g. "1", "2"), not "learned"/"active".
    function t.known_p(name)
        local key = find_psm_key(prefix, name)
        local val = Infomon.get(prefix .. "." .. key)
        if not val then return false end
        local n = tonumber(val)
        return n ~= nil and n >= 1
    end

    -- known: alias for known_p (matches Lich5 Weapon.known?/CMan.known? etc.)
    function t.known(name)
        return t.known_p(name)
    end

    -- active_p: is skill currently active as a buff?
    -- NOTE: Infomon currently stores ranks (integers), not active/inactive state.
    -- This returns false always until active-state tracking is added to the infomon parser.
    function t.active_p(name)
        local key = find_psm_key(prefix, name)
        return Infomon.get(prefix .. "." .. key) == "active"
    end

    -- available(name): known AND not overexerted AND not on cooldown.
    -- Matches Lich5 Feat.available?/Shield.available? which check known + affordable + cooldown.
    function t.available(name)
        -- Must know the ability first
        if not t.known_p(name) then return false end
        -- Check for overexerted debuff
        if Effects and Effects.Debuffs and Effects.Debuffs.active("Overexerted") then
            return false
        end
        -- Check not on cooldown (Effects.Cooldowns stores by game text, e.g. "Absorb Magic")
        if Effects and Effects.Cooldowns then
            if Effects.Cooldowns.active(name) then return false end
        end
        return true
    end

    -- list_known: return array of {name, rank} for all known skills in this category
    function t.list_known()
        local result = {}
        for _, kv in ipairs(Infomon.keys()) do
            if kv:match("^" .. prefix .. "%.") then
                local skill_name = kv:sub(#prefix + 2)
                local val = Infomon.get(kv)
                local n = tonumber(val)
                if n and n >= 1 then
                    result[#result + 1] = { name = skill_name, rank = n }
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
