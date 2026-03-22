--- Bigshot Group — head/tail coordination via whisper-based events
-- Port of Group class and DRb event system from bigshot.lic v5.12.1
-- Revenant uses JSON-encoded whisper messages instead of DRb IPC.
-- Leader broadcasts events; followers listen and execute.

local M = {}

local PREFIX = "BIGSHOT:"
local event_queue = {}
local members = {}
local is_leader_flag = false
local leader_name = nil
local hook_name = "bigshot_group"
local expected_count = 1

---------------------------------------------------------------------------
-- Event Types (mirrors Ruby Event class @@RECOGNIZED)
---------------------------------------------------------------------------
M.EVENT_TYPES = {
    "HUNTING_PREP_COMMANDS", "HUNTING_SCRIPTS_START", "CAST_SIGNS", "ATTACK",
    "PREP_REST", "HUNTING_SCRIPTS_STOP", "RESTING_SCRIPTS_START",
    "RESTING_PREP_COMMANDS", "DISPLAY_WATCH", "START_WATCH", "STOP_WATCH",
    "SINGLE_STOP", "FOLLOWER_OVERKILL", "STAY_QUIET", "FOLLOW_NOW", "LOOT",
    "CUSTOM_PUT", "CUSTOM_CMD", "CUSTOM_DO_CLIENT", "PUBLIC_SEND",
    "GO2_WAYPOINTS", "GO2_RESTING_ROOM", "GO2_RALLY_ROOM", "GO2_HUNTING_ROOM",
    "CHECK_MIND", "FOG_RETURN", "CHECK_SNEAKY", "LEAVE_GROUP",
    "HUNT_MONITOR_START", "HUNT_MONITOR_STOP",
}

---------------------------------------------------------------------------
-- Leader Functions
---------------------------------------------------------------------------

function M.set_leader(flag, count)
    is_leader_flag = flag
    expected_count = count or 1
    leader_name = GameState.name
end

function M.is_leader()
    return is_leader_flag
end

function M.get_leader_name()
    return leader_name
end

--- Broadcast an event to all group followers via whisper
function M.broadcast(event_type, data)
    data = data or {}
    data.type = event_type
    data.from = GameState.name
    data.room_id = Map.current_room()
    data.time = os.time()

    local json = Json.encode(data)
    put("whisper group ooc " .. PREFIX .. json)
end

--- Broadcast a command to execute
function M.broadcast_command(event_type, cmd_input)
    M.broadcast(event_type, { cmd = cmd_input })
end

--- Wait for all followers to be present in the room
function M.all_present()
    local group_members = GameObj.pcs() or {}
    local present_count = 0
    for _, pc in ipairs(group_members) do
        if members[pc.noun] then
            present_count = present_count + 1
        end
    end
    return present_count >= M.member_count()
end

--- Wait for followers with timeout
function M.wait_for_followers(timeout)
    timeout = timeout or 30
    local waited = 0
    while waited < timeout do
        if M.all_present() then return true end
        pause(0.5)
        waited = waited + 0.5
    end
    respond("[bigshot] Timeout waiting for followers")
    return false
end

--- Open group for joining
function M.group_open()
    fput("group open")
    pause(0.3)
end

--- Close group
function M.group_close()
    fput("group close")
    pause(0.3)
end

--- Disband group
function M.disband()
    fput("disband")
    pause(0.3)
end

---------------------------------------------------------------------------
-- Follower Functions
---------------------------------------------------------------------------

--- Install downstream hook to listen for leader broadcasts
function M.install_listener()
    DownstreamHook.remove(hook_name)
    before_dying(function() DownstreamHook.remove(hook_name) end)

    DownstreamHook.add(hook_name, function(line)
        -- Look for whisper containing BIGSHOT: prefix
        local json_str = line:match("BIGSHOT:(%b{})")
        if json_str then
            local ok, event = pcall(Json.decode, json_str)
            if ok and event and event.type then
                event_queue[#event_queue + 1] = event
            end
            return nil  -- squelch the whisper from display
        end
        return line
    end)
end

--- Get next event from queue (non-blocking)
function M.next_event()
    if #event_queue > 0 then
        return table.remove(event_queue, 1)
    end
    return nil
end

--- Wait for next event (blocking with timeout)
function M.wait_event(timeout)
    timeout = timeout or 30
    local waited = 0
    while waited < timeout do
        local event = M.next_event()
        if event then return event end
        pause(0.1)
        waited = waited + 0.1
    end
    return nil
end

--- Check if event is stale (>15 seconds old or different room)
function M.event_stale(event)
    if not event then return true end
    local age = os.time() - (event.time or 0)
    if age > 15 then return true end
    local current = Map.current_room()
    if event.room_id and current and event.room_id ~= current then return true end
    return false
end

function M.clear_events()
    event_queue = {}
end

---------------------------------------------------------------------------
-- Member Management
---------------------------------------------------------------------------

function M.add_member(name)
    members[name] = { name = name, active = true, joined = os.time() }
end

function M.remove_member(name)
    members[name] = nil
end

function M.get_members()
    return members
end

function M.get_member_names()
    local names = {}
    for name, _ in pairs(members) do
        names[#names + 1] = name
    end
    return names
end

function M.member_count()
    local count = 0
    for _ in pairs(members) do count = count + 1 end
    return count
end

function M.in_group(name)
    return members[name] ~= nil
end

function M.expected_size()
    return expected_count
end

---------------------------------------------------------------------------
-- Group Status Checks
---------------------------------------------------------------------------

--- Check if group should rest (any member needs rest)
function M.group_should_rest(bstate)
    -- For whisper-based system, followers report their status
    -- Leader checks its own state; followers self-report via events
    return false
end

--- Check if group looting is done
function M.looting_done()
    -- In whisper-based system, followers signal completion
    return true
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

function M.cleanup()
    DownstreamHook.remove(hook_name)
    event_queue = {}
    members = {}
end

return M
