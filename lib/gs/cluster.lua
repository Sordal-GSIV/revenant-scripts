-- lib/gs/cluster.lua
-- Multi-group coordination tracker.
-- Extension of Claim for hunting clusters (multiple groups in the same area).

local M = {}
local cluster_members = {}  -- array of character names

function M.add(name)
    for _, n in ipairs(cluster_members) do
        if n == name then return end
    end
    cluster_members[#cluster_members + 1] = name
end

function M.remove(name)
    for i, n in ipairs(cluster_members) do
        if n == name then
            table.remove(cluster_members, i)
            return
        end
    end
end

function M.members()
    return cluster_members
end

function M.clear()
    cluster_members = {}
end

function M.is_member(name)
    for _, n in ipairs(cluster_members) do
        if n == name then return true end
    end
    return false
end

return M
