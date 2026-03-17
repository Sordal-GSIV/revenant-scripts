local M = {}

local PREFIX = "BIGSHOT:"
local event_queue = {}
local members = {}
local is_leader = false

function M.broadcast(event_type, data)
    data = data or {}
    data.type = event_type
    data.from = GameState.name
    local json = Json.encode(data)
    put("whisper group ooc " .. PREFIX .. json)
end

function M.install_listener()
    DownstreamHook.add("bigshot_group", function(line)
        local json_str = line:match("BIGSHOT:(%b{})")
        if json_str then
            local ok, event = pcall(Json.decode, json_str)
            if ok and event then
                event_queue[#event_queue + 1] = event
            end
            return nil
        end
        return line
    end)
end

function M.next_event()
    if #event_queue > 0 then
        return table.remove(event_queue, 1)
    end
    return nil
end

function M.clear_events()
    event_queue = {}
end

function M.add_member(name)
    members[name] = { name = name, active = true }
end

function M.remove_member(name)
    members[name] = nil
end

function M.get_members()
    return members
end

function M.member_count()
    local count = 0
    for _ in pairs(members) do count = count + 1 end
    return count
end

function M.set_leader(v)
    is_leader = v
end

function M.is_leader()
    return is_leader
end

function M.cleanup()
    DownstreamHook.remove("bigshot_group")
    event_queue = {}
    members = {}
end

return M
