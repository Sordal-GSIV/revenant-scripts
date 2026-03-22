--- @revenant-script
--- name: cluster_script
--- version: 1.1.0
--- author: Ondreian
--- lic-author: Ondreian
--- game: gs
--- description: Distributed RPC/communications for multi-character coordination via pub/sub
--- tags: cluster,multi-box,coordination,rpc,contracts
--- @lic-certified: complete 2026-03-19
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
    Log._write(prefix .. " " .. tostring(msg))
end

function Log._write(line)
    if HEADLESS then
        -- In headless mode, write to stdout equivalent
        respond(line)
    elseif string.find(line, "<") and string.find(line, ">") then
        respond(line)
    else
        respond(Log.Preset.as("debug", line))
    end
end

function Log.pp(msg, label)
    label = label or "debug"
    if type(label) == "table" then label = table.concat(label, ".") end
    local prefix = "[cluster." .. tostring(label) .. "]"
    if type(msg) == "table" then
        msg = Json.encode(msg)
    end
    respond(prefix .. " " .. tostring(msg))
end

function Log.dump(...)
    Log.pp(...)
end

Log.Preset = {}
function Log.Preset.as(kind, body)
    return "<preset id=\"" .. tostring(kind) .. "\">" .. tostring(body) .. "</preset>"
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
                local name = string.sub(name_val, 1, eq - 1)
                local val = string.sub(name_val, eq + 1)
                -- Support comma-separated values
                if string.find(val, ",") then
                    local parts = {}
                    for part in string.gmatch(val, "[^,]+") do
                        table.insert(parts, part)
                    end
                    result[name] = parts
                else
                    result[name] = val
                end
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
HEADLESS = opts.headless or false

--------------------------------------------------------------------------------
-- UUID generation (replaces Ruby's SecureRandom.hex)
--------------------------------------------------------------------------------

local function generate_uuid()
    -- Generate a 20-character hex string (equivalent to SecureRandom.hex(10))
    local chars = "0123456789abcdef"
    local result = {}
    math.randomseed(os.time() + math.random(1, 999999))
    for i = 1, 20 do
        local idx = math.random(1, 16)
        result[i] = string.sub(chars, idx, idx)
    end
    return table.concat(result)
end

--------------------------------------------------------------------------------
-- Cluster core
--------------------------------------------------------------------------------

local Cluster = {}
Cluster.cb_map = {}
Cluster.pending_requests = {}
Cluster.connected = {}
Cluster.last_publish = 0
Cluster.TTL = 5
Cluster.NOOP = function() end
Cluster.UNSUPPORTED_METHOD = function(channel, _)
    return { error = channel .. " is not implemented on " .. GameState.name }
end

local CHAR_NAME = GameState.name

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
    -- channel can be a table (e.g., {uuid, "response"}) — join with "."
    if type(channel) == "table" then
        channel = table.concat(channel, ".")
    end
    local ch = Cluster.make_channel_name(person, channel)
    payload.from = CHAR_NAME
    Cluster.publish(ch, payload)
end

function Cluster.request(person, payload)
    payload = payload or {}
    local req_id = generate_uuid()
    local channel = payload.channel
    payload.channel = nil
    local ttl = payload.timeout or Cluster.TTL
    payload.timeout = nil

    Cluster.cast(person, {
        channel = { channel, "request" },
        uuid = req_id,
        from = CHAR_NAME,
    })

    -- Store a marker for the pending request
    Cluster.pending_requests[req_id] = true

    -- Poll for response within TTL
    local deadline = os.time() + ttl
    while os.time() < deadline do
        local resp = Cluster.pending_requests[req_id]
        if type(resp) == "table" then
            -- Got a response
            Cluster.pending_requests[req_id] = nil
            if resp.error then
                return nil, resp.error
            end
            return resp
        end
        pause(0.1)
    end

    -- Timed out
    Cluster.pending_requests[req_id] = nil
    return nil, "request to " .. tostring(person) .. " failed in " .. tostring(ttl) .. "s"
end

function Cluster.map(people, payload)
    -- Sequential requests to multiple people (Lua is single-threaded)
    local results = {}
    for _, name in ipairs(people) do
        local resp, err = Cluster.request(name, payload)
        if resp then
            table.insert(results, resp)
        else
            table.insert(results, { error = err })
        end
    end
    return results
end

function Cluster.on_broadcast(channel, callback)
    local key = "gs.pub." .. string.lower(tostring(channel))
    Cluster.cb_map[key] = callback
end

function Cluster.on_cast(channel, callback)
    local key = "gs." .. string.lower(CHAR_NAME) .. "." .. string.lower(tostring(channel))
    Cluster.cb_map[key] = callback
end

function Cluster.on_request(channel, callback)
    local key = "gs." .. string.lower(CHAR_NAME) .. "." .. string.lower(tostring(channel)) .. ".request"
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

function Cluster._touch(_, incoming)
    local from = incoming.from
    if from then
        Cluster.connected[from] = os.time()
    end
end

function Cluster._handle_leave(_, incoming)
    local from = incoming.from
    if from then
        Cluster.connected[from] = nil
    end
end

function Cluster._handle_cast(channel, incoming)
    local ok2, err = pcall(function()
        local callback = Cluster.cb_map[channel] or Cluster.NOOP
        callback(channel, incoming)
    end)
    if not ok2 then
        Log.out(tostring(err), { "dispatch", "error", channel })
    end
end

function Cluster._handle_request(channel, incoming)
    local ok2, result = pcall(function()
        local callback = Cluster.cb_map[channel] or Cluster.UNSUPPORTED_METHOD
        return callback(channel, incoming)
    end)

    local response
    if ok2 and type(result) == "table" then
        response = result
    elseif not ok2 then
        response = { error = tostring(result) }
    else
        response = {}
    end

    -- Dispatch response back to requester
    Cluster._dispatch_response_object(incoming, response)
end

function Cluster._dispatch_response_object(incoming, response)
    local from = incoming.from
    if not from then
        Log.out("Request `from` was missing", "error")
        return
    end
    response.channel = { incoming.uuid, "response" }
    response.uuid = incoming.uuid
    response.from = CHAR_NAME
    Cluster.cast(from, response)
end

function Cluster._handle_response(_, incoming)
    local resp_id = incoming.uuid
    if not resp_id then return end
    local pending = Cluster.pending_requests[resp_id]
    if pending then
        Cluster.pending_requests[resp_id] = incoming
    end
end

function Cluster.route_incoming(channel, raw_message)
    local ok, incoming = pcall(Json.decode, raw_message)
    if not ok or type(incoming) ~= "table" then return end
    if incoming.from == CHAR_NAME then return end

    if DEBUG then
        Log.out(incoming, { "incoming", channel })
    end

    -- Keep alive tracking
    Cluster._touch(channel, incoming)

    -- Determine channel type from last segment
    local parts = {}
    for part in string.gmatch(channel, "[^%.]+") do
        table.insert(parts, part)
    end
    local kind = parts[#parts]

    if incoming.uuid and kind == "response" then
        Cluster._handle_response(channel, incoming)
        return
    end

    if incoming.uuid and kind == "request" then
        Cluster._handle_request(channel, incoming)
        return
    end

    if kind == "leave" and incoming.from then
        Cluster._handle_leave(channel, incoming)
    end

    Cluster._handle_cast(channel, incoming)
end

--------------------------------------------------------------------------------
-- Contracts system
--------------------------------------------------------------------------------

local Contracts = {}
Contracts.OPEN_CONTRACTS = {}
Contracts.OPEN_BIDS = {}
Contracts.CALLBACKS = {}
Contracts.TTL = 1
Contracts.VALID_BID_MIN = 0
Contracts.VALID_BID_MAX = 1

Contracts.Events = {
    CONTRACT_OPEN  = "contract_open",
    CONTRACT_CLOSE = "contract_close",
    CONTRACT_BID   = "contract_bid",
    CONTRACT_WIN   = "contract_win",
}

function Contracts.next_expiry()
    return os.time() + Contracts.TTL
end

function Contracts.expired(contract)
    return os.time() > (contract.expiry or 0)
end

function Contracts.closed(contract)
    if Contracts.expired(contract) then return true end
    local bids = contract.bids or {}
    local bidders = contract.valid_bidders or {}
    return #bids >= #bidders
end

function Contracts.valid_bid(value)
    return type(value) == "number" and value >= Contracts.VALID_BID_MIN and value <= Contracts.VALID_BID_MAX
end

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

function Contracts.fetch_open_contract(contract_id, callback)
    Contracts.prune()
    local contract = Contracts.OPEN_CONTRACTS[contract_id]
    if contract then
        callback(contract)
    end
end

function Contracts.make_contract(args)
    args.contract_id = generate_uuid()
    args.kind = string.lower(tostring(args.kind))
    args.from = CHAR_NAME
    args.expiry = Contracts.next_expiry()
    args.bids = {}
    return args
end

function Contracts.bid(contract, value)
    Log.out("bidding " .. tostring(value) .. " on Contract(" .. tostring(contract.contract_id) .. ") from " .. tostring(contract.from), "bid")

    Cluster.cast(contract.from, {
        channel = Contracts.Events.CONTRACT_BID,
        contract_id = contract.contract_id,
        bid = value,
    })
end

function Contracts.maybe_bid(contract)
    if not contract.valid_bidders then return end
    local valid = false
    for _, name in ipairs(contract.valid_bidders) do
        if name == CHAR_NAME then valid = true; break end
    end
    if not valid then return end

    local kind_key = contract.kind
    local cb = Contracts.CALLBACKS[kind_key]
    if not cb or not cb[Contracts.Events.CONTRACT_OPEN] then return end

    local bid_value = cb[Contracts.Events.CONTRACT_OPEN](contract)
    if not bid_value or not (bid_value > (contract.min_bid or 0)) then
        bid_value = -1
    end

    if Contracts.valid_bid(bid_value) then
        Contracts.OPEN_BIDS[contract.contract_id] = contract
    end

    Contracts.bid(contract, bid_value)
end

function Contracts.tell_remote_winner(winner, contract)
    local payload = {}
    for k, v in pairs(contract) do
        payload[k] = v
    end
    payload.channel = Contracts.Events.CONTRACT_WIN
    Cluster.cast(winner, payload)
end

function Contracts.collect_bids(kind, args, on_empty_callback)
    -- args: { valid_bidders = {...}, min_bid = 0, ... }
    args = args or {}
    Contracts.prune()

    local contract_args = {}
    for k, v in pairs(args) do
        contract_args[k] = v
    end
    contract_args.kind = kind

    local contract = Contracts.make_contract(contract_args)
    Contracts.OPEN_CONTRACTS[contract.contract_id] = contract
    Log.out(contract, Contracts.Events.CONTRACT_OPEN)
    Cluster.broadcast(Contracts.Events.CONTRACT_OPEN, contract)

    -- Wait until contract is closed (all bids in or expired)
    while not Contracts.closed(contract) do
        pause(0.1)
    end

    -- Filter valid bids
    local valid_bids = {}
    for _, resp in ipairs(contract.bids) do
        if Contracts.valid_bid(resp.bid) then
            table.insert(valid_bids, resp)
        end
    end

    -- No valid bids — call the empty callback
    if #valid_bids == 0 then
        if on_empty_callback then
            on_empty_callback(contract)
        end
        return nil
    end

    -- Highest bid wins
    table.sort(valid_bids, function(a, b) return a.bid < b.bid end)
    local winning_bid = valid_bids[#valid_bids]
    Log.out(winning_bid, "winning_bid")
    Contracts.tell_remote_winner(winning_bid.from, contract)
    return winning_bid
end

function Contracts.on_contract(kind, callbacks)
    -- Assert we have valid callbacks for this contract
    if not callbacks[Contracts.Events.CONTRACT_OPEN] then
        error("on_contract: missing " .. Contracts.Events.CONTRACT_OPEN .. " callback")
    end
    if not callbacks[Contracts.Events.CONTRACT_WIN] then
        error("on_contract: missing " .. Contracts.Events.CONTRACT_WIN .. " callback")
    end
    Contracts.CALLBACKS[kind] = callbacks
end

-- Register contract event handlers
Cluster.on_broadcast(Contracts.Events.CONTRACT_OPEN, function(_, req)
    Contracts.prune()
    Contracts.maybe_bid(req)
end)

Cluster.on_cast(Contracts.Events.CONTRACT_BID, function(_, req)
    if DEBUG then Log.out(req, Contracts.Events.CONTRACT_BID) end
    Contracts.fetch_open_contract(req.contract_id, function(contract)
        if not contract.bids then contract.bids = {} end
        table.insert(contract.bids, req)
    end)
end)

Cluster.on_cast(Contracts.Events.CONTRACT_WIN, function(_, req)
    Contracts.OPEN_BIDS[req.contract_id] = nil
    local cb = Contracts.CALLBACKS[req.kind]
    if cb and cb[Contracts.Events.CONTRACT_WIN] then
        cb[Contracts.Events.CONTRACT_WIN](req)
    end
end)

--------------------------------------------------------------------------------
-- Registry (key-value store, replaces Redis get/set)
-- Uses CharSettings for persistence since Redis is not available in Revenant.
--------------------------------------------------------------------------------

local Registry = {}
Registry.__index = Registry

function Registry.new(namespace)
    local self = setmetatable({}, Registry)
    self.namespace = namespace or CHAR_NAME
    return self
end

function Registry:_key(str)
    return string.lower(tostring(self.namespace)) .. "." .. string.lower(tostring(str))
end

function Registry:put(key, val)
    local storage_key = "cluster_registry_" .. self:_key(key)
    CharSettings[storage_key] = Json.encode(val)
end

function Registry:get(key)
    local storage_key = "cluster_registry_" .. self:_key(key)
    local raw = CharSettings[storage_key]
    if raw then
        local ok, result = pcall(Json.decode, raw)
        if ok then return result end
    end
    return nil
end

function Registry:delete(key)
    local storage_key = "cluster_registry_" .. self:_key(key)
    CharSettings[storage_key] = nil
end

function Registry:exists(key)
    local storage_key = "cluster_registry_" .. self:_key(key)
    return CharSettings[storage_key] ~= nil
end

Cluster.Registry = Registry

function Cluster.registry(namespace)
    return Registry.new(namespace)
end

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
-- Singleton pattern (mirrors Ruby's Cluster.init / Cluster.of / method_missing)
--------------------------------------------------------------------------------

local _cluster_initialized = false

function Cluster.up()
    return _cluster_initialized
end

function Cluster.init()
    if _cluster_initialized then return Cluster end

    -- Setup subscriptions
    if MessageBus then
        local personal_pattern = "gs." .. string.lower(CHAR_NAME) .. ".*"
        local public_pattern = "gs.pub.*"

        MessageBus.subscribe(personal_pattern, function(channel, message)
            Cluster.route_incoming(channel, message)
        end)

        MessageBus.subscribe(public_pattern, function(channel, message)
            Cluster.route_incoming(channel, message)
        end)
    else
        echo("Warning: MessageBus not available. Cluster will run in local-only mode.")
    end

    -- Load user callbacks if available
    if File.exists("scripts/cluster_callbacks.lua") then
        local ok2, err = pcall(dofile, "scripts/cluster_callbacks.lua")
        if not ok2 then
            echo("Warning: Failed to load cluster_callbacks.lua: " .. tostring(err))
        end
    end

    -- Announce presence
    Cluster.broadcast("announce")

    _cluster_initialized = true
    return Cluster
end

function Cluster.destroy()
    Log.out("cleaning up", "destroy")
    Cluster.broadcast("leave")
    _cluster_initialized = false
end

--------------------------------------------------------------------------------
-- Export for other scripts
--------------------------------------------------------------------------------

_G.Cluster = Cluster
_G.Contracts = Contracts
_G.Log = Log

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

Cluster.init()

echo("Cluster node started for " .. CHAR_NAME)
if DEBUG then echo("Debug mode enabled") end
local peers = Cluster.get_connected()
if #peers > 0 then
    echo("Connected peers: " .. table.concat(peers, ", "))
else
    echo("No peers connected yet")
end

-- Cleanup
before_dying(function()
    Cluster.destroy()
end)

-- Keepalive loop (35s interval matches Ruby original)
while true do
    Cluster.broadcast("ping")
    pause(35)
end
