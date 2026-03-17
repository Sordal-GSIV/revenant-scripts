--- Bigshot Recovery — rest, spell-ups, loot delegation

local navigation = require("navigation")
local state_mod = require("state")

local M = {}

-- Run resting commands (user-configured)
function M.run_resting_commands(state)
    for _, cmd in ipairs(state.resting_commands or {}) do
        fput(cmd)
        pause(0.5)
    end
end

-- Run resting scripts (user-configured)
function M.run_resting_scripts(state)
    for _, script_entry in ipairs(state.resting_scripts or {}) do
        local name = script_entry:match("^(%S+)")
        local args = script_entry:match("^%S+%s+(.+)$") or ""
        if name then
            Script.run(name, args)
            pause(1)
        end
    end
end

-- Wait for recovery thresholds
function M.wait_for_recovery(state)
    respond("[bigshot] Waiting for recovery...")
    local max_wait = 600 -- 10 minutes max
    local waited = 0

    while waited < max_wait do
        if state_mod.ready_to_hunt(state) then
            respond("[bigshot] Recovery complete")
            return true
        end
        pause(5)
        waited = waited + 5
    end

    respond("[bigshot] Recovery timeout — forcing hunt")
    return false
end

-- Full rest cycle
function M.rest(state)
    respond("[bigshot] Resting...")

    -- Fog return or navigate to rest room
    if state.fog_return and state.fog_return ~= "" then
        navigation.fog_return(state)
        pause(1)
    end

    -- Travel to rest room
    if state.rest_room and state.rest_room ~= "" then
        navigation.goto_room(tonumber(state.rest_room))
    end

    -- Run resting prep commands
    M.run_resting_commands(state)

    -- Run resting scripts
    M.run_resting_scripts(state)

    -- Wait for recovery
    M.wait_for_recovery(state)
end

-- Loot via external script
function M.loot(state)
    local loot_script = state.loot_script or "eloot"
    if loot_script == "" then return end

    Script.run(loot_script)
    -- Wait for loot script to finish
    local timeout = 30
    local waited = 0
    while Script.running(loot_script) and waited < timeout do
        pause(0.5)
        waited = waited + 0.5
    end
end

return M
