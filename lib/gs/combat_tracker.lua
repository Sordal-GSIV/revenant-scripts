--- Combat event processing.
--- Observes game output for NPC death events via DownstreamHook.

local M = {}
local enabled = false
local callbacks = { death = {} }
local stats = { events = 0 }

-- NPC death message patterns (27 from Lich5)
local DEATH_PATTERNS = {
    "falls to the ground dead",
    "collapses dead",
    "dies with a final",
    "crumples to the ground",
    "topples over dead",
    "is knocked to the ground dead",
    "is blown to bits",
    "goes still",
    "rolls over dead",
    "expires",
    "succumbs to the",
    "crumbles into a",
    "shatters into fragments",
    "dissolves into a",
    "fades away",
    "falls apart",
    "drops dead",
    "is slain",
    "breathes its last",
    "lies still",
    "collapses into a heap",
    "is destroyed",
    "turns to dust",
    "melts away",
    "is struck down",
    "falls lifeless",
    "is no more",
}

local function hook_fn(line)
    for _, pattern in ipairs(DEATH_PATTERNS) do
        if string.find(line, pattern, 1, true) then
            stats.events = stats.events + 1
            for _, cb in ipairs(callbacks.death) do
                pcall(cb, line)
            end
            break
        end
    end
    return line
end

--- Register the downstream hook and persist enabled state.
function M.enable()
    if enabled then return end
    DownstreamHook.add("__combat_tracker", hook_fn)
    enabled = true
    Infomon.set("combat_tracker.enabled", "true")
end

--- Remove the downstream hook and persist disabled state.
function M.disable()
    if not enabled then return end
    DownstreamHook.remove("__combat_tracker")
    enabled = false
    Infomon.set("combat_tracker.enabled", "false")
end

--- Return whether the tracker is enabled.
function M.enabled_p()
    return enabled
end

--- Register a callback invoked with the line on NPC death.
function M.on_death(callback)
    callbacks.death[#callbacks.death + 1] = callback
end

--- Return the stats table.
function M.stats()
    return stats
end

-- Auto-restore: re-enable if previously persisted as enabled
if Infomon.get("combat_tracker.enabled") == "true" then
    M.enable()
end

return M
