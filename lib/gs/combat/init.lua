--- Combat tracking system for GemStone IV.
--- Port of Lich5's Combat::Tracker / Creature instance system.
--- Provides per-creature HP estimation, injury tracking, status effects, and UCS state.

local creature_instance = require("lib/gs/combat/creature_instance")
local tracker = require("lib/gs/combat/tracker")

-- Set up global CombatCreature table with __index for CombatCreature[id] syntax.
-- This provides Lich5-compatible access: CombatCreature[creature_id]
if not _G.CombatCreature then
    _G.CombatCreature = setmetatable({}, {
        __index = function(_, id)
            return creature_instance.essential_data(id)
        end,
    })
end

-- Expose tracker as CombatTracker global (replaces the minimal death-only tracker)
_G.CombatTracker = tracker

-- Expose creature instance module
_G.CreatureInstance = creature_instance

return {
    tracker = tracker,
    creature_instance = creature_instance,
}
