--- Combat tracker — main downstream hook that buffers lines and triggers processing.
--- Replaces and extends the minimal death-only tracker in lib/gs/combat_tracker.lua.

local processor = require("lib/gs/combat/processor")
local creature_instance = require("lib/gs/combat/creature_instance")
local M = {}

local enabled = false
local settings = {
    track_damage = true,
    track_statuses = true,
    track_ucs = true,
    fallback_max_hp = 350,
    cleanup_interval = 100,
    cleanup_max_age = 600,
    debug = false,
}

local chunks_processed = 0
local buffer = {}

-- Fast relevance filter — only process lines that could contain combat data.
local function combat_relevant(line)
    return string.find(line, "points of damage", 1, true)
        or string.find(line, "swing", 1, true)
        or string.find(line, "fire", 1, true)
        or string.find(line, "cast", 1, true)
        or string.find(line, "gesture", 1, true)
        or string.find(line, "pushBold", 1, true)
        or string.find(line, "AS:", 1, true)
        or string.find(line, "positioning against", 1, true)
        or string.find(line, "vulnerable to a followup", 1, true)
        or string.find(line, "crimson mist", 1, true)
        or string.find(line, "stunned", 1, true)
        or string.find(line, "knocked to the ground", 1, true)
        or string.find(line, "breaks free", 1, true)
        or string.find(line, "ensnared", 1, true)
        or string.find(line, "slumber", 1, true)
        or string.find(line, "blinded", 1, true)
end

-- Check if chunk contains creatures (bold-wrapped links with exist IDs).
local function has_creatures(chunk)
    for _, line in ipairs(chunk) do
        if string.find(line, "pushBold", 1, true) and string.find(line, "exist=", 1, true) then
            return true
        end
    end
    return false
end

local function hook_fn(line)
    -- Buffer lines between prompts
    buffer[#buffer + 1] = line

    -- Check for prompt (end of chunk)
    if string.find(line, "<prompt", 1, true) then
        -- Process buffered chunk
        if #buffer > 1 and has_creatures(buffer) then
            -- Filter to relevant lines
            local relevant = {}
            for _, l in ipairs(buffer) do
                if combat_relevant(l) then
                    relevant[#relevant + 1] = l
                end
            end
            if #relevant > 0 then
                local ok, err = pcall(processor.process, relevant)
                if not ok and settings.debug then
                    echo("[CombatTracker] Error: " .. tostring(err))
                end
                chunks_processed = chunks_processed + 1
                -- Periodic cleanup
                if chunks_processed % settings.cleanup_interval == 0 then
                    creature_instance.cleanup_old(settings.cleanup_max_age)
                end
            end
        end
        buffer = {}
    end

    -- Prevent buffer from growing unbounded
    if #buffer > 200 then
        buffer = {}
    end

    return line  -- pass through (don't modify)
end

--- Enable the combat tracker hook.
function M.enable()
    if enabled then return end
    DownstreamHook.add("__combat_tracker_v2", hook_fn, DownstreamHook.PRIORITY_FIRST)
    enabled = true
end

--- Disable the combat tracker hook.
function M.disable()
    if not enabled then return end
    DownstreamHook.remove("__combat_tracker_v2")
    enabled = false
end

--- Return whether the tracker is enabled.
---@return boolean
function M.enabled_p()
    return enabled
end

--- Update tracker settings.
---@param new_settings table partial settings table to merge
function M.configure(new_settings)
    for k, v in pairs(new_settings or {}) do
        settings[k] = v
    end
end

--- Return tracker stats.
---@return table { enabled, chunks_processed, creatures_tracked, settings }
function M.stats()
    return {
        enabled = enabled,
        chunks_processed = chunks_processed,
        creatures_tracked = creature_instance.size(),
        settings = settings,
    }
end

--- Check if debug mode is enabled.
---@return boolean
function M.debug_p()
    return settings.debug
end

--- Enable debug output.
function M.enable_debug()
    settings.debug = true
end

--- Disable debug output.
function M.disable_debug()
    settings.debug = false
end

--- Set fallback max HP for creatures without bestiary data.
---@param hp number
function M.set_fallback_hp(hp)
    settings.fallback_max_hp = hp
end

--- Get fallback max HP.
---@return number
function M.fallback_hp()
    return settings.fallback_max_hp
end

-- Auto-enable if previously enabled
if Infomon and Infomon.get("combat_tracker_v2.enabled") == "true" then
    M.enable()
end

return M
