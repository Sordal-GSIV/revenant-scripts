-- lib/gs/readylist.lua
-- Parse READY LIST command output to track equipped items.
-- NOTE: check() must be called from a running script context (needs fput/get).

local M = {}

local READY_SLOTS = {
    "shield", "weapon", "secondary_weapon", "ranged_weapon",
    "ammo_bundle", "ammo2_bundle", "sheath", "secondary_sheath", "wand",
}
local STORE_SLOTS = {
    "store_shield", "store_weapon", "store_secondary_weapon",
    "store_ranged_weapon", "store_ammo_bundle", "store_wand",
}

-- Normalize slot names from game output to our keys
local SLOT_MAP = {
    ["shield"]             = "shield",
    ["weapon"]             = "weapon",
    ["secondary weapon"]   = "secondary_weapon",
    ["ranged weapon"]      = "ranged_weapon",
    ["ammo bundle"]        = "ammo_bundle",
    ["ammo2 bundle"]       = "ammo2_bundle",
    ["sheath"]             = "sheath",
    ["secondary sheath"]   = "secondary_sheath",
    ["wand"]               = "wand",
    ["store shield"]       = "store_shield",
    ["store weapon"]       = "store_weapon",
    ["store secondary weapon"] = "store_secondary_weapon",
    ["store ranged weapon"]    = "store_ranged_weapon",
    ["store ammo bundle"]      = "store_ammo_bundle",
    ["store wand"]             = "store_wand",
}

local state = {}
local checked = false

--- Parse READY LIST output. Must be called from a running script.
function M.check(opts)
    opts = opts or {}
    for _, slot in ipairs(READY_SLOTS) do state[slot] = nil end
    for _, slot in ipairs(STORE_SLOTS) do state[slot] = nil end
    checked = false

    waitrt()
    fput("ready list")

    -- Wait for header
    local header = waitfor("Your current settings are:", 5)
    if not header then
        if not opts.quiet then respond("[readylist] Failed to parse ready list") end
        return false
    end

    -- Parse lines until prompt
    while true do
        local line = get()
        if not line or line:match("^>") then break end

        local raw_slot, item = line:match("^%s+(.-):%s+(.+)$")
        if raw_slot and item then
            local slot_key = SLOT_MAP[raw_slot:lower():match("^(.-)%s*$")]
            item = item:match("^%s*(.-)%s*$")
            if slot_key and item ~= "none" and item ~= "" then
                state[slot_key] = item
            end
        end
    end

    checked = true
    return true
end

--- Verify items still exist in inventory.
function M.valid()
    if not checked then return false end
    -- Basic check: slots with values are assumed valid
    -- Full validation would cross-reference GameObj.inv
    return true
end

--- Clear all slots.
function M.reset()
    for _, slot in ipairs(READY_SLOTS) do state[slot] = nil end
    for _, slot in ipairs(STORE_SLOTS) do state[slot] = nil end
    checked = false
end

--- Get the full ready list table.
function M.ready_list()
    local result = {}
    for _, slot in ipairs(READY_SLOTS) do
        result[slot] = state[slot]
    end
    return result
end

--- Get the full store list table.
function M.store_list()
    local result = {}
    for _, slot in ipairs(STORE_SLOTS) do
        result[slot] = state[slot]
    end
    return result
end

setmetatable(M, {
    __index = function(_, key)
        if state[key] ~= nil then return state[key] end
        if key == "checked" then return checked end
        return rawget(M, key)
    end,
})

return M
