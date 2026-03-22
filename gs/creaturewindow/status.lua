--- Creature status normalization and custom status detection.

local M = {}

local state -- lazy-loaded to avoid circular require

local function get_state()
    if not state then state = require("state") end
    return state
end

-- Custom status cache keyed by creature ID
local custom_status_cache = {}

--- Clear cached custom status for a creature.
function M.clear_cache(id)
    custom_status_cache[id] = nil
end

--- Normalize a creature's status string into human-readable indicators.
--- Also detects special custom statuses (e.g. cold wyrm airborne/grounded).
--- @param status string|nil  Raw status string from GameObj
--- @param name string|nil    Creature full name
--- @param id string|nil      Creature ID
--- @return string|nil  Comma-separated status indicators, or nil if none
function M.creature_status_fix(status, name, id)
    local s = get_state()
    local custom_statuses = {}

    -- Cold wyrm special states
    if name and name:lower():find("cold wyrm") then
        for _, line in ipairs(s.recent_lines) do
            if line:lower():find("cold wyrm plummets toward the ground") and
               line:lower():find("radiating wall of devastation") then
                custom_statuses[#custom_statuses + 1] = "grounded"
            elseif line:lower():find("cold wyrm's muscles bunch and she launches herself into the air") then
                custom_statuses[#custom_statuses + 1] = "airborne"
            elseif line:lower():find("corruscations of color play along") and
                   line:lower():find("disrupting the attack") then
                custom_statuses[#custom_statuses + 1] = "shielded"
            end
        end

        if #custom_statuses > 0 and id then
            custom_status_cache[id] = custom_statuses
        elseif id and custom_status_cache[id] then
            custom_statuses = custom_status_cache[id]
        end
    end

    -- Standard status mapping
    local standard = nil
    if status then
        local sl = status:lower()
        if sl:find("calm") then standard = "calmed"
        elseif sl:find("frozen") or sl:find("immobilized") or sl:find("terrified") then standard = "frozen"
        elseif sl:find("held") then standard = "held"
        elseif sl:find("rooted") then standard = "rooted"
        elseif sl:find("unconscious") or sl:find("slumber") or sl:find("sleeping") then standard = "unconscious"
        elseif sl:find("webbed") or sl:find("webbing") then standard = "webbed"
        elseif sl:find("stunned") then standard = "stunned"
        elseif sl:find("prone") or sl:find("lying down") or sl:find("knocked to the ground") then standard = "prone"
        elseif sl:find("flying") then standard = "flying"
        end
    end

    local all = {}
    if standard then all[#all + 1] = standard end
    for _, cs in ipairs(custom_statuses) do
        all[#all + 1] = cs
    end

    if #all == 0 then return nil end
    return table.concat(all, ", ")
end

return M
