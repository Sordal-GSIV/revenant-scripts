--- sloot/sacks.lua
-- Sack lookup, open/close management.
-- Mirrors the sacks Hash, open_sack proc, close_open_sacks proc from sloot.lic v3.5.2.

local settings_mod = require("sloot/settings")
local M = {}

-- Current sack map: type -> GameObj
M.sacks = {}

-- IDs of sacks we've opened (to close if enable_close_sacks)
local closed_sacks = {}

local SACK_TYPES = {
    "clothing", "ammo", "box", "gem", "herb", "jewelry", "lockpick",
    "magic", "reagent", "scroll", "skin", "uncommon", "wand",
    "skinweapon", "valuable", "collectible", "forage",
}

--- Find all sacks from UserVars, print warnings for missing ones.
-- @param settings  current settings table
-- @param cmd       script.vars[1] (skip exit on setup)
function M.find_sacks(settings, cmd)
    M.sacks = {}
    closed_sacks = {}
    for _, stype in ipairs(SACK_TYPES) do
        local ukey = (stype == "forage") and "foragesack" or (stype .. "sack")
        local sack_name = settings_mod.uvar_get(ukey)
        if sack_name ~= "" then
            local found = GameObj.find_inv(sack_name)
            if found then
                M.sacks[stype] = found
            elseif (cmd or "") ~= "setup" then
                -- Only warn/exit for enabled types
                if stype == "skinweapon" and not settings.enable_skinning then
                    -- skip
                elseif settings["enable_loot_" .. stype] then
                    echo("** failed to find " .. stype .. " sack")
                    -- Original exits here; preserve that behaviour
                    error("missing sack: " .. stype)
                end
            end
        end
    end
end

--- Open a sack and record it for later closing.
function M.open_sack(sack)
    if type(sack) ~= "table" then
        sack = GameObj.find(tostring(sack))
    end
    if not sack then
        echo("fixme: open_sack failed to find sack")
        return false
    end
    local res = dothistimeout("open #" .. sack.id, 5, Regex.new("^You open .*\\.$"))
    if not res then
        echo("fixme: unknown open_sack result")
        return false
    end
    closed_sacks[#closed_sacks + 1] = sack.id
    return true
end

--- Close all sacks we opened (if enable_close_sacks is on).
function M.close_open_sacks(settings)
    if not settings.enable_close_sacks then return end
    for _, sack_id in ipairs(closed_sacks) do
        dothistimeout("close #" .. sack_id, 5, Regex.new("^You close .*\\.$"))
    end
    closed_sacks = {}
end

return M
