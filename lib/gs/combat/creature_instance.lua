--- Per-creature runtime tracker.
--- Manages creature instances with HP, injury, status, and UCS tracking.
--- Port of Lich5's Combat::Tracker creature state system.

local M = {}
local instances = {}  -- id => creature data table
local MAX_INSTANCES = 1000
local DEFAULT_FALLBACK_HP = 350

-- Body parts tracked (same as Lich5)
M.BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nsys",
}

-- Status effect durations (seconds, nil = no auto-expiry)
local STATUS_DURATIONS = {
    breeze = 6, bind = 10, web = 8, entangle = 10,
    hypnotism = 12, calm = 15, mass_calm = 15, sleep = 8,
}

--- Create a new creature instance (or return existing one).
---@param id string creature exist ID
---@param name string full display name
---@param noun string|nil noun (e.g. "troll")
---@return table creature data table
function M.register(id, name, noun)
    if instances[id] then return instances[id] end
    -- Cleanup if full
    if M.size() >= MAX_INSTANCES then
        M.cleanup_old(600)
    end
    local c = {
        id = id, name = name, noun = noun or "",
        damage_taken = 0,
        _max_hp = nil,  -- from template if available
        injuries = {},  -- body_part => rank (0-3)
        status = {},    -- array of status name strings
        status_timestamps = {},  -- status_name => expiry_time (os.time based)
        created_at = os.time(),
        fatal_crit = false,
        -- UCS
        ucs_position = nil,  -- 1/2/3
        ucs_tierup = nil,
        ucs_smote = nil,
        ucs_updated = nil,
    }
    -- Initialize injuries to 0
    for _, part in ipairs(M.BODY_PARTS) do
        c.injuries[part] = 0
    end
    instances[id] = c
    return c
end

--- Lookup creature by ID.
---@param id string
---@return table|nil
function M.get(id)
    return instances[id]
end

--- Return all tracked creatures as an array.
---@return table[]
function M.all()
    local result = {}
    for _, c in pairs(instances) do
        result[#result + 1] = c
    end
    return result
end

--- Return count of tracked creatures.
---@return integer
function M.size()
    local count = 0
    for _ in pairs(instances) do count = count + 1 end
    return count
end

--- Clear all tracked creatures.
function M.clear()
    instances = {}
end

--- Remove creatures older than max_age seconds.
---@param max_age number|nil seconds (default 600)
---@return integer removed count
function M.cleanup_old(max_age)
    max_age = max_age or 600
    local now = os.time()
    local removed = 0
    for id, c in pairs(instances) do
        if (now - c.created_at) > max_age then
            instances[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

---------------------------------------------------------------------------
-- HP tracking
---------------------------------------------------------------------------

--- Add damage to a creature.
---@param id string
---@param amount number
function M.add_damage(id, amount)
    local c = instances[id]
    if not c then return end
    c.damage_taken = c.damage_taken + amount
end

--- Get max HP for a creature (from bestiary or fallback).
---@param id string
---@return number
function M.max_hp(id)
    local c = instances[id]
    if not c then return DEFAULT_FALLBACK_HP end
    if c._max_hp and c._max_hp > 0 then return c._max_hp end
    -- Try bestiary lookup
    if Creature and Creature.find then
        local data = Creature.find(c.noun) or Creature.find(c.name)
        if data and data.max_hp then
            c._max_hp = data.max_hp
            return c._max_hp
        end
    end
    return DEFAULT_FALLBACK_HP
end

--- Get estimated current HP.
---@param id string
---@return number|nil
function M.current_hp(id)
    local c = instances[id]
    if not c then return nil end
    local max = M.max_hp(id)
    return math.max(max - c.damage_taken, 0)
end

--- Get HP as percentage (0-100).
---@param id string
---@return number|nil
function M.hp_percent(id)
    local c = instances[id]
    if not c then return nil end
    local max = M.max_hp(id)
    if max <= 0 then return 100 end
    local current = math.max(max - c.damage_taken, 0)
    return math.floor((current / max) * 100 + 0.5)
end

---------------------------------------------------------------------------
-- Injury tracking
---------------------------------------------------------------------------

--- Add injury to a body part (capped at rank 3).
---@param id string
---@param body_part string
---@param rank number|nil rank increment (default 1)
function M.add_injury(id, body_part, rank)
    local c = instances[id]
    if not c then return end
    rank = rank or 1
    local current = c.injuries[body_part] or 0
    c.injuries[body_part] = math.min(current + rank, 3)
end

---------------------------------------------------------------------------
-- Status tracking
---------------------------------------------------------------------------

--- Add a status effect to a creature.
---@param id string
---@param status_name string
function M.add_status(id, status_name)
    local c = instances[id]
    if not c then return end
    -- Check if already has this status
    for _, s in ipairs(c.status) do
        if s == status_name then return end
    end
    c.status[#c.status + 1] = status_name
    -- Set expiry if defined
    local dur = STATUS_DURATIONS[status_name]
    if dur then
        c.status_timestamps[status_name] = os.time() + dur
    end
end

--- Remove a status effect from a creature.
---@param id string
---@param status_name string
function M.remove_status(id, status_name)
    local c = instances[id]
    if not c then return end
    for i, s in ipairs(c.status) do
        if s == status_name then
            table.remove(c.status, i)
            break
        end
    end
    c.status_timestamps[status_name] = nil
end

--- Remove expired status effects from a creature.
---@param id string
function M.cleanup_expired_statuses(id)
    local c = instances[id]
    if not c then return end
    local now = os.time()
    local to_remove = {}
    for status_name, expiry in pairs(c.status_timestamps) do
        if expiry <= now then
            to_remove[#to_remove + 1] = status_name
        end
    end
    for _, s in ipairs(to_remove) do
        M.remove_status(id, s)
    end
end

--- Get active statuses for a creature (auto-cleans expired).
---@param id string
---@return string[]
function M.statuses(id)
    M.cleanup_expired_statuses(id)
    local c = instances[id]
    if not c then return {} end
    return c.status
end

---------------------------------------------------------------------------
-- Fatal crit
---------------------------------------------------------------------------

--- Mark a creature as having received a fatal critical hit.
---@param id string
function M.mark_fatal_crit(id)
    local c = instances[id]
    if c then c.fatal_crit = true end
end

---------------------------------------------------------------------------
-- UCS (Unarmed Combat System)
---------------------------------------------------------------------------

local UCS_TTL = 120
local UCS_SMITE_TTL = 15

--- Set UCS positioning tier for a creature.
---@param id string
---@param position string "decent"|"good"|"excellent"
function M.set_ucs_position(id, position)
    local c = instances[id]
    if not c then return end
    local tier = ({ decent = 1, good = 2, excellent = 3 })[position]
    if tier then
        if c.ucs_position ~= tier then c.ucs_tierup = nil end
        c.ucs_position = tier
        c.ucs_updated = os.time()
    end
end

--- Set UCS tier-up attack type.
---@param id string
---@param attack_type string "jab"|"grapple"|"punch"|"kick"
function M.set_ucs_tierup(id, attack_type)
    local c = instances[id]
    if c then c.ucs_tierup = attack_type end
end

--- Mark creature as smote (crimson mist active).
---@param id string
function M.smite(id)
    local c = instances[id]
    if c then c.ucs_smote = os.time() end
end

--- Check if creature is currently smote.
---@param id string
---@return boolean
function M.smote(id)
    local c = instances[id]
    if not c or not c.ucs_smote then return false end
    if (os.time() - c.ucs_smote) > UCS_SMITE_TTL then
        c.ucs_smote = nil
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Data export
---------------------------------------------------------------------------

--- Export essential data for a creature (for creaturebar, etc.).
---@param id string
---@return table|nil
function M.essential_data(id)
    local c = instances[id]
    if not c then return nil end
    M.cleanup_expired_statuses(id)
    return {
        id = c.id,
        noun = c.noun,
        name = c.name,
        status = c.status,
        injuries = c.injuries,
        damage_taken = c.damage_taken,
        max_hp = M.max_hp(id),
        current_hp = M.current_hp(id),
        hp_percent = M.hp_percent(id),
        created_at = c.created_at,
        fatal_crit = c.fatal_crit,
    }
end

return M
