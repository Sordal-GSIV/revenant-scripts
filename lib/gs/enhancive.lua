-- lib/gs/enhancive.lua
-- Track enhancive item bonuses from INVENTORY ENHANCIVE output.
-- NOTE: refresh() must be called from a running script context (needs fput/get).

local M = {}

local STAT_CAP = 40
local SKILL_CAP = 50

local state = {
    active = false,
    stats = {},
    skills = {},
    resources = {},
    spells = {},
    item_count = 0,
    property_count = 0,
    total_amount = 0,
    last_updated = nil,
}

--- Parse INVENTO ENH output. Must be called from a running script.
function M.refresh(opts)
    opts = opts or {}

    state.stats = {}
    state.skills = {}
    state.resources = {}
    state.spells = {}
    state.item_count = 0
    state.property_count = 0
    state.total_amount = 0

    waitrt()
    fput("invento enh")

    -- Wait for either the header or "no bonuses" message
    local header = waitfor("Enhancive item bonuses:", "No enhancive item bonuses found", 5)
    if not header then
        if not opts.quiet then respond("[enhancive] Failed to read enhancive data") end
        return false
    end

    if header:find("No enhancive item bonuses found") then
        state.active = false
        state.last_updated = os.time()
        return true
    end

    local section = nil
    while true do
        local line = get()
        if not line or line:match("^>") then break end

        if line:find("^%s*Stats:") then
            section = "stats"
        elseif line:find("^%s*Skills:") then
            section = "skills"
        elseif line:find("^%s*Resources:") then
            section = "resources"
        elseif section then
            local name, val = line:match("^%s+(.-):%s+%+?(%d+)")
            if name and val then
                name = name:match("^(.-)%s*$"):lower():gsub("%s+", "_")
                local v = tonumber(val)
                if section == "stats" then
                    state.stats[name] = { value = v, cap = STAT_CAP }
                elseif section == "skills" then
                    state.skills[name] = { value = v, cap = SKILL_CAP }
                elseif section == "resources" then
                    state.resources[name] = { value = v, cap = 600 }
                end
                state.property_count = state.property_count + 1
                state.total_amount = state.total_amount + v
            end
        end
    end

    state.active = true
    state.last_updated = os.time()
    return true
end

--- Refresh just the active/paused status.
function M.refresh_status(opts)
    opts = opts or {}
    waitrt()
    fput("invento enh status")
    local line = waitfor("You are currently", "You are not currently", 5)
    if line then
        state.active = line:find("You are currently") ~= nil
    end
end

function M.active() return state.active end
function M.item_count_val() return state.item_count end
function M.property_count_val() return state.property_count end
function M.total_amount_val() return state.total_amount end
function M.last_updated_val() return state.last_updated end

function M.stat_over_cap(stat_name)
    local s = state.stats[stat_name]
    return s and s.value > STAT_CAP
end

function M.skill_over_cap(skill_name)
    local s = state.skills[skill_name]
    return s and s.value > SKILL_CAP
end

function M.over_cap_stats()
    local result = {}
    for name, s in pairs(state.stats) do
        if s.value > STAT_CAP then result[#result + 1] = name end
    end
    return result
end

function M.over_cap_skills()
    local result = {}
    for name, s in pairs(state.skills) do
        if s.value > SKILL_CAP then result[#result + 1] = name end
    end
    return result
end

function M.reset_all()
    state.stats = {}
    state.skills = {}
    state.resources = {}
    state.spells = {}
    state.active = false
    state.item_count = 0
    state.property_count = 0
    state.total_amount = 0
end

setmetatable(M, {
    __index = function(_, key)
        if state.stats[key] then return state.stats[key] end
        if state.skills[key] then return state.skills[key] end
        if state.resources[key] then return state.resources[key] end
        return rawget(M, key)
    end,
})

return M
