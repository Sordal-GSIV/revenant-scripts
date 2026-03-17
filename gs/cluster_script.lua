--- @revenant-script
--- name: cluster_script
--- version: 1.0.0
--- author: Ondreian
--- game: gs
--- description: Distributed RPC/communications for multi-character coordination via pub/sub
--- tags: cluster,multi-box,coordination,rpc,contracts
---
--- Changelog (from Lich5):
---   v1.0.0 (2025-10-27): Semantic versioning, connection_pool support
---   v0.1.0 (2019-06-22): Contract system
---   v0.0.0 (2019-01-14): Initial release
---
--- NOTE: This is the standalone cluster coordination script. The cluster
--- library lives at lib/gs/cluster.lua. This script manages the event loop,
--- pub/sub connections, contract bidding, and keepalive pings.
---
--- In Revenant, Redis pub/sub is replaced by the built-in MessageBus system.
--- Characters on the same Revenant instance share a process-local bus.
---
--- Usage:
---   ;cluster_script                - Start cluster node
---   ;cluster_script --debug        - Start with debug logging
---   ;cluster_script --headless     - Run without respond() output

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

local Log = {}

function Log.out(msg, label)
    label = label or "debug"
    if type(label) == "table" then label = table.concat(label, ".") end
    local prefix = "[cluster." .. tostring(label) .. "]"
    if type(msg) == "table" then
        msg = Json.encode(msg)
    end
    respond(prefix .. " " .. tostring(msg))
end

function Log.pp(msg, label)
    respond("[cluster." .. tostring(label or "debug") .. "] " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Options parser
--------------------------------------------------------------------------------

local Opts = {}
function Opts.parse()
    local result = {}
    local vars = Script.vars
    for i = 1, #vars do
        local v = vars[i]
        if not v then break end
        if string.sub(v, 1, 2) == "--" then
            local name_val = string.sub(v, 3)
            local eq = string.find(name_val, "=")
            if eq then
                result[string.sub(name_val, 1, eq - 1)] = string.sub(name_val, eq + 1)
            else
                result[name_val] = true
            end
        else
            result[v] = true
        end
    end
    return result
end

local opts = Opts.parse()
local DEBUG = opts.debug or false

--------------------------------------------------------------------------------
-- Cluster core
--------------------------------------------------------------------------------

local Cluster = {}
Cluster.cb_map = {}
Cluster.pending_requests = {}
Cluster.connected = {}
Cluster.last_publish = 0
Cluster.TTL = 5

local CHAR_NAME = GameState.name
local NOOP = function() end

function Cluster.make_channel_name(...)
    local parts = { "gs" }
    for _, v in ipairs({...}) do
        if v then table.insert(parts, string.lower(tostring(v))) end
    end
    return table.concat(parts, ".")
end

function Cluster.publish(channel, payload)
    Cluster.last_publish = os.time()
    if MessageBus then
        MessageBus.publish(channel, Json.encode(payload))
    end
end

function Cluster.emit(channel, payload)
    channel = Cluster.make_channel_name(CHAR_NAME, channel)
    payload.from = CHAR_NAME
    Cluster.publish(channel, payload)
end

function Cluster.broadcast(channel, payload)
    payload = payload or {}
    channel = Cluster.make_channel_name("pub", channel)
    payload.from = CHAR_NAME
    Cluster.publish(channel, payload)
end

function Cluster.cast(person, payload)
    local channel = payload.channel
    payload.channel = nil
    local ch = Cluster.make_channel_name(person, channel)
    payload.from = CHAR_NAME
    Cluster.publish(ch, payload)
end

function Cluster.on_broadcast(channel, callback)
    local key = "gs.pub." .. string.lower(channel)
    Cluster.cb_map[key] = callback
end

function Cluster.on_cast(channel, callback)
    local key = "gs." .. string.lower(CHAR_NAME) .. "." .. string.lower(channel)
    Cluster.cb_map[key] = callback
end

function Cluster.on_request(channel, callback)
    local key = "gs." .. string.lower(CHAR_NAME) .. "." .. string.lower(channel) .. ".request"
    Cluster.cb_map[key] = callback
end

function Cluster.alive(name)
    local last_seen = Cluster.connected[name]
    if not last_seen then return false end
    return math.abs(os.time() - last_seen) < 60
end

function Cluster.get_connected()
    local result = {}
    for name, _ in pairs(Cluster.connected) do
        if Cluster.alive(name) then
            table.insert(result, name)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Message routing
--------------------------------------------------------------------------------

function Cluster.route_incoming(channel, raw_message)
    local ok, incoming = pcall(Json.decode, raw_message)
    if not ok or type(incoming) ~= "table" then return end
    if incoming.from == CHAR_NAME then return end

    if DEBUG then
        Log.out(incoming, { "incoming", channel })
    end

    -- Keep alive tracking
    if incoming.from then
        Cluster.connected[incoming.from] = os.time()
    end

    -- Determine channel type
    local parts = {}
    for part in string.gmatch(channel, "[^%.]+") do
        table.insert(parts, part)
    end
    local kind = parts[#parts]

    if incoming.uuid and kind == "response" then
        -- Handle response
        local pending = Cluster.pending_requests[incoming.uuid]
        if pending then
            Cluster.pending_requests[incoming.uuid] = incoming
        end
        return
    end

    if incoming.uuid and kind == "request" then
        -- Handle request
        local callback = Cluster.cb_map[channel]
        if callback then
            local ok2, response = pcall(callback, channel, incoming)
            if ok2 and type(response) == "table" then
                Cluster.cast(incoming.from, {
                    channel = incoming.uuid .. ".response",
                    uuid = incoming.uuid,
                    from = CHAR_NAME,
                })
            end
        end
        return
    end

    -- Handle leave
    if kind == "leave" and incoming.from then
        Cluster.connected[incoming.from] = nil
        return
    end

    -- Handle cast/broadcast
    local callback = Cluster.cb_map[channel]
    if callback then
        pcall(callback, channel, incoming)
    end
end

--------------------------------------------------------------------------------
-- Contracts system
--------------------------------------------------------------------------------

local Contracts = {}
Contracts.OPEN_CONTRACTS = {}
Contracts.OPEN_BIDS = {}
Contracts.CALLBACKS = {}

Contracts.Events = {
    CONTRACT_OPEN  = "contract_open",
    CONTRACT_CLOSE = "contract_close",
    CONTRACT_BID   = "contract_bid",
    CONTRACT_WIN   = "contract_win",
}

function Contracts.prune()
    local now = os.time()
    for id, contract in pairs(Contracts.OPEN_CONTRACTS) do
        if contract.expiry and now > contract.expiry then
            Contracts.OPEN_CONTRACTS[id] = nil
        end
    end
    for id, contract in pairs(Contracts.OPEN_BIDS) do
        if contract.expiry and now > contract.expiry then
            Contracts.OPEN_BIDS[id] = nil
        end
    end
end

function Contracts.maybe_bid(contract)
    if not contract.valid_bidders then return end
    local valid = false
    for _, name in ipairs(contract.valid_bidders) do
        if name == CHAR_NAME then valid = true; break end
    end
    if not valid then return end

    local cb = Contracts.CALLBACKS[contract.kind]
    if not cb or not cb[Contracts.Events.CONTRACT_OPEN] then return end

    local bid = cb[Contracts.Events.CONTRACT_OPEN](contract)
    if not bid or bid <= (contract.min_bid or 0) then bid = -1 end

    if bid >= 0 and bid <= 1 then
        Contracts.OPEN_BIDS[contract.contract_id] = contract
    end

    Cluster.cast(contract.from, {
        channel = Contracts.Events.CONTRACT_BID,
        contract_id = contract.contract_id,
        bid = bid,
    })
end

function Contracts.on_contract(kind, callbacks)
    Contracts.CALLBACKS[kind] = callbacks
end

-- Register contract event handlers
Cluster.on_broadcast(Contracts.Events.CONTRACT_OPEN, function(_, req)
    Contracts.prune()
    Contracts.maybe_bid(req)
end)

Cluster.on_cast(Contracts.Events.CONTRACT_BID, function(_, req)
    if DEBUG then Log.out(req, Contracts.Events.CONTRACT_BID) end
    local contract = Contracts.OPEN_CONTRACTS[req.contract_id]
    if contract then
        if not contract.bids then contract.bids = {} end
        table.insert(contract.bids, req)
    end
end)

Cluster.on_cast(Contracts.Events.CONTRACT_WIN, function(_, req)
    Contracts.OPEN_BIDS[req.contract_id] = nil
    local cb = Contracts.CALLBACKS[req.kind]
    if cb and cb[Contracts.Events.CONTRACT_WIN] then
        cb[Contracts.Events.CONTRACT_WIN](req)
    end
end)

--------------------------------------------------------------------------------
-- Setup default handlers
--------------------------------------------------------------------------------

Cluster.on_request("api", function(_, _)
    local methods = {}
    for k, _ in pairs(Cluster.cb_map) do
        table.insert(methods, k)
    end
    return { methods = methods }
end)

Cluster.on_broadcast("announce", function(_, req)
    Cluster.cast(req.from, { channel = "ack" })
end)

--------------------------------------------------------------------------------
-- MessageBus subscription
--------------------------------------------------------------------------------

local function setup_subscriptions()
    if not MessageBus then
        echo("Warning: MessageBus not available. Cluster will run in local-only mode.")
        return
    end

    local personal_pattern = "gs." .. string.lower(CHAR_NAME) .. ".*"
    local public_pattern = "gs.pub.*"

    MessageBus.subscribe(personal_pattern, function(channel, message)
        Cluster.route_incoming(channel, message)
    end)

    MessageBus.subscribe(public_pattern, function(channel, message)
        Cluster.route_incoming(channel, message)
    end)
end

--------------------------------------------------------------------------------
-- Load user callbacks if available
--------------------------------------------------------------------------------

local function load_callbacks()
    if File.exists("scripts/cluster_callbacks.lua") then
        local ok, err = pcall(dofile, "scripts/cluster_callbacks.lua")
        if not ok then
            echo("Warning: Failed to load cluster_callbacks.lua: " .. tostring(err))
        end
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Export for other scripts
_G.Cluster = Cluster
_G.Contracts = Contracts

setup_subscriptions()
load_callbacks()

-- Announce presence
Cluster.broadcast("announce")

echo("Cluster node started for " .. CHAR_NAME)
if DEBUG then echo("Debug mode enabled") end
echo("Connected peers: " .. table.concat(Cluster.get_connected(), ", "))

-- Cleanup
before_dying(function()
    Cluster.broadcast("leave")
end)

-- Keepalive loop
while true do
    Cluster.broadcast("ping")
    pause(35)
end
