-- lib/gs/disk.lua
-- Tracks GemStone spell 919 (Floating Disk) status.
-- Lich5 parity: disk detection and noun lookup.

local M = {}
local disk_active = false
local disk_noun = nil  -- e.g., "Sordal disk"

-- Detect disk from active spells
function M.active()
    -- Check if spell 919 (Floating Disk) is active
    if Spell and Spell.active_p then
        return Spell.active_p(919)
    end
    return disk_active
end

function M.noun()
    if not disk_noun then
        disk_noun = (GameState.name or "your") .. " disk"
    end
    return disk_noun
end

function M.set_active(val)
    disk_active = val
end

return M
