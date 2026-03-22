--- Kill metrics tracking: TTK (time-to-kill) and KPM (kills-per-minute).

local M = {}

-- TTK tracking
local time_to_kill_list = {}
local creature_timestamps = {}    -- id -> first-seen time
local creature_targeted = {}      -- id -> true when targeted
local counted_dead_ids = {}       -- id -> time counted
local last_kill_time = nil
local last_kill_name = nil
local last_kill_activity_at = nil

-- KPM tracking
local owned_room_kill_count = 0
local owned_room_kill_started_at = nil

-- Import claim module (lazy)
local claim_loaded = false
local claim_mine = function() return false end

local function try_load_claim()
    if claim_loaded then return end
    claim_loaded = true
    local ok, mod = pcall(require, "lib/gs/claim")
    if ok and mod and mod.mine then
        claim_mine = mod.mine
    end
end

--- Record that a creature is now being tracked (first seen alive).
function M.note_creature_alive(id)
    if not creature_timestamps[id] then
        creature_timestamps[id] = os.time()
    end
end

--- Record that a creature has been targeted.
function M.note_creature_targeted(id)
    creature_targeted[id] = true
    M.note_creature_alive(id)
end

--- Track a creature kill for TTK metrics.
function M.track_creature_kill(id, name)
    if not creature_timestamps[id] then return end
    if not creature_targeted[id] then return end

    local time_alive = os.time() - creature_timestamps[id]
    time_to_kill_list[#time_to_kill_list + 1] = time_alive
    last_kill_time = time_alive
    last_kill_name = name
    last_kill_activity_at = os.time()

    creature_timestamps[id] = nil
    creature_targeted[id] = nil
end

--- Register generic kill activity (for KPM timeout tracking).
local function register_kill_activity()
    last_kill_activity_at = os.time()
end

--- Reset metrics after inactivity.
function M.reset_if_inactive(dead_creatures, inactivity_seconds)
    inactivity_seconds = inactivity_seconds or 300
    if not last_kill_activity_at then return end
    if (os.time() - last_kill_activity_at) < inactivity_seconds then return end

    time_to_kill_list = {}
    last_kill_time = nil
    last_kill_name = nil
    owned_room_kill_count = 0
    owned_room_kill_started_at = nil
    -- Re-seed counted_dead_ids with current dead
    counted_dead_ids = {}
    for _, c in ipairs(dead_creatures) do
        counted_dead_ids[c.id] = os.time()
    end
    last_kill_activity_at = nil
end

--- Track kills in owned (claimed) rooms for KPM.
function M.track_owned_room_kills(dead_creatures)
    try_load_claim()
    if not claim_mine() then return end

    if not owned_room_kill_started_at then
        owned_room_kill_started_at = os.time()
    end

    local current_dead_ids = {}
    for _, c in ipairs(dead_creatures) do
        current_dead_ids[c.id] = true

        if not counted_dead_ids[c.id] then
            counted_dead_ids[c.id] = os.time()
            owned_room_kill_count = owned_room_kill_count + 1
            register_kill_activity()
        end
    end

    -- Remove IDs no longer present
    for id, _ in pairs(counted_dead_ids) do
        if not current_dead_ids[id] then
            counted_dead_ids[id] = nil
        end
    end
end

--- Track disappearing creatures (killed/removed) from the live target list.
function M.track_missing_creatures(current_targets)
    local current_ids = {}
    for _, t in ipairs(current_targets) do
        current_ids[t.id] = true
    end

    for id, _ in pairs(creature_timestamps) do
        if not current_ids[id] then
            -- Creature vanished — look up name from npcs
            local name = "Unknown"
            for _, npc in ipairs(GameObj.npcs()) do
                if npc.id == id then
                    name = npc.name
                    break
                end
            end
            M.track_creature_kill(id, name)
        end
    end
end

--- Calculate average TTK string.
function M.avg_ttk()
    if #time_to_kill_list == 0 then return "N/A" end
    local sum = 0
    for _, t in ipairs(time_to_kill_list) do sum = sum + t end
    return string.format("%.2f sec", sum / #time_to_kill_list)
end

--- Last TTK display string.
function M.last_ttk()
    if not last_kill_time then return "N/A" end
    return string.format("%.2f sec", last_kill_time)
end

--- Last killed creature name, or nil.
function M.last_kill()
    return last_kill_name
end

--- Calculate KPM string.
function M.kpm()
    if not owned_room_kill_started_at or owned_room_kill_count == 0 then
        return "N/A"
    end
    local elapsed = (os.time() - owned_room_kill_started_at) / 60.0
    if elapsed <= 0 then return "N/A" end
    return string.format("%.2f (%d)", owned_room_kill_count / elapsed, owned_room_kill_count)
end

--- Clear the custom status cache for a creature (called from status module).
function M.clear_status_cache(id)
    -- Delegate to status module if needed
end

return M
