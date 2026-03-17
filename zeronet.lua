--- @revenant-script
--- name: zeronet
--- version: 0.0.10
--- author: Ondreian
--- game: any
--- tags: core, chat
--- description: Extended LNet chat client with custom callbacks (0net)
---
--- Original Lich5 authors: Ondreian
--- Ported to Revenant Lua from 0net.lic v0.0.10
---
--- NOTE: This is the extended version of lnet that adds a callback system
--- for custom request types. The network layer (SSL to lnet.lichproject.org)
--- is stubbed with TODOs, same as lnet.lua. Local UI, commands, permissions,
--- friends/enemies, and the callback registration API are fully implemented.

local VERSION = "0.0.10"

Script.unique()
Script.hidden()

--------------------------------------------------------------------------------
-- Callback Registry
--------------------------------------------------------------------------------
local callbacks = {}

local function add_callback(name, request_type, handler)
    if name:lower():match("^lnet_") and Script.current_name() ~= "zeronet" then
        error("you may not use the reserved prefix 'lnet_'")
    end
    if not callbacks[request_type] then callbacks[request_type] = {} end
    callbacks[request_type][name] = handler
end

local function remove_callback(name, request_type)
    if callbacks[request_type] then callbacks[request_type][name] = nil end
end

local function clear_callbacks()
    callbacks = {}
end

-- Expose globally for other scripts
_G.LNet = _G.LNet or {}
_G.LNet.add_callback = add_callback
_G.LNet.remove_callback = remove_callback
_G.LNet.clear_callbacks = clear_callbacks
_G.LNet.callbacks = callbacks

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local server = nil          -- TODO: network socket placeholder
local server_closed = true
local last_recv = os.time()
local last_send = os.time()
local last_priv = nil
local secret = {}
local waiting = {}
local server_restart = false

local options = CharSettings.get("zeronet_options") or {}
if not options.timestamps    then options.timestamps = false end
if not options.fam_window    then options.fam_window = false end
if options.greeting == nil   then options.greeting = true end
if not options.friends       then options.friends = {} end
if not options.enemies       then options.enemies = {} end
if not options.permission    then options.permission = {} end
if not options.ignore        then options.ignore = {} end

local stored_secret = CharSettings.get("zeronet_secret") or {}
secret = stored_secret

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function save_options()
    CharSettings.set("zeronet_options", options)
end

local function save_secret()
    CharSettings.set("zeronet_secret", secret)
end

local function list_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function list_remove(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then table.remove(tbl, i); return true end
    end
    return false
end

local function short_name(name)
    return name:match("[A-Z][a-z]+$") or name
end

local function is_ignored(name)
    return list_contains(options.ignore, name)
        or list_contains(options.ignore, short_name(name))
end

local function is_friend(name)
    return list_contains(options.friends, name)
        or list_contains(options.friends, short_name(name))
end

local function is_enemy(name)
    return list_contains(options.enemies, name)
        or list_contains(options.enemies, short_name(name))
end

local function allow_action(action, name)
    local perm = options.permission[action]
    if perm == "all" then return true
    elseif perm == "friends" then return is_friend(name)
    elseif perm == "enemies" then return not is_enemy(name)
    else return false
    end
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function echo_thought(from, message, channel)
    local ch = ""
    if from ~= "[server]" then ch = "[" .. channel .. "]-" end

    local timestamp = ""
    if options.timestamps then
        timestamp = "  (" .. os.date("%X") .. ")"
    end

    local text = ch .. from .. ': "' .. message .. '"' .. timestamp
    if not is_ignored(from) then
        respond(text)
    end
end

--------------------------------------------------------------------------------
-- Network Layer (STUBBED)
-- TODO: Same SSL protocol as lnet.lua — connect to lnet.lichproject.org:7155
--------------------------------------------------------------------------------

local function server_connected()
    return not server_closed
end

local function send_xml(xml_str)
    last_send = os.time()
    if server_closed then
        echo("zeronet: not connected to server (network layer not yet implemented)")
        return false
    end
    return true
end

local function lnet_connect()
    echo("zeronet: network connection not yet implemented (Revenant TODO)")
    echo("zeronet: local commands and callback registration work offline")
end

local function send_message(attrs, message)
    if not server_connected() then return false end
    echo("zeronet: send_message stub — " .. (attrs.type or "?") .. ": " .. message)
    return true
end

local function safe_send(attrs, message)
    if (os.time() - last_send) > 3 then
        return send_message(attrs, message)
    end
    return false
end

_G.LNet.safe_send = safe_send

local function send_query(attrs)
    if not server_connected() then return false end
    echo("zeronet: send_query stub — " .. (attrs.type or "?"))
    return true
end

local function send_request(attrs)
    if not server_connected() then return false end
    echo("zeronet: send_request stub — " .. (attrs.type or "?"))
    return true
end

local function send_data(attrs, data)
    if not server_connected() then return false end
    echo("zeronet: send_data stub — " .. (attrs.type or "?"))
    return true
end

local function tune_channel(channel)
    if not server_connected() then return false end
    echo("zeronet: tune stub — " .. channel)
    return true
end

local function untune_channel(channel)
    if not server_connected() then return false end
    echo("zeronet: untune stub — " .. channel)
    return true
end

local function moderate(attrs)
    if not server_connected() then return false end
    echo("zeronet: moderate stub — " .. (attrs.action or "?"))
    return true
end

local function admin(attrs)
    if not server_connected() then return false end
    echo("zeronet: admin stub — " .. (attrs.action or "?"))
    return true
end

--------------------------------------------------------------------------------
-- Callback dispatch (called when receiving a <request> from the server)
--------------------------------------------------------------------------------

local function dispatch_callback(request_type, attrs)
    local from = attrs.from
    local type_base = request_type:match("^([^:]+)") or request_type

    if not callbacks[type_base] then
        echo("rejecting unknown request (" .. type_base .. ") from " .. from .. "...")
        send_data({ type = type_base, to = from }, nil)
        return
    end

    local perm = options.permission[type_base]
    if perm and not allow_action(type_base, from) then
        echo("rejecting request from " .. from .. " for " .. type_base .. " info...")
        send_data({ type = type_base, to = from }, nil)
        return
    end

    if perm then
        echo("sending " .. type_base .. " info to " .. from .. "...")
    end

    -- Execute first registered callback
    local handler = nil
    for _, h in pairs(callbacks[type_base]) do handler = h; break end
    if handler then
        local ok, result = pcall(handler, attrs)
        if ok then
            send_data({ type = type_base, to = from }, result)
        else
            echo("error in callback for " .. type_base .. ": " .. tostring(result))
            send_data({ type = type_base, to = from }, nil)
        end
    else
        send_data({ type = type_base, to = from }, nil)
    end
end

--------------------------------------------------------------------------------
-- Register default LNet callbacks
--------------------------------------------------------------------------------

-- Spells callback
add_callback("lnet_spells", "spells", function(attrs)
    local active = Spell.active and Spell.active() or {}
    local result = {}
    for _, spell in ipairs(active) do
        result[tostring(spell.num)] = spell.timeleft or 0
    end
    return result
end)

-- Info callback
add_callback("lnet_info", "info", function(attrs)
    return {
        Race       = Stats.race or "",
        Profession = Stats.prof or "",
        Gender     = Stats.gender or "",
        Level      = GameState.level or 0,
    }
end)

-- Bounty callback
add_callback("lnet_bounty", "bounty", function(attrs)
    return Bounty and Bounty.task or ""
end)

-- Health callback
add_callback("lnet_health", "health", function(attrs)
    return {
        health     = GameState.health or 0,
        max_health = GameState.max_health or 0,
        spirit     = GameState.spirit or 0,
        max_spirit = GameState.max_spirit or 0,
    }
end)

-- Locate callback
add_callback("lnet_locate", "locate", function(attrs)
    return {
        title = GameState.room_title or "",
        description = GameState.room_description or "",
    }
end)

--------------------------------------------------------------------------------
-- Load user callbacks if available
--------------------------------------------------------------------------------
-- In Lich5: ;lnet-callbacks script is auto-loaded
-- In Revenant: if a lnet_callbacks.lua exists, require it
local ok, _ = pcall(function()
    if Script.exists and Script.exists("lnet_callbacks") then
        echo("detected callback library...")
        Script.run("lnet_callbacks")
    end
end)

--------------------------------------------------------------------------------
-- Game name helper
--------------------------------------------------------------------------------
local fix_game = { gsf = "GSF", gsiv = "GSIV", gsplat = "GSPlat" }

local function resolve_name(game_part, name_part)
    local name = name_part:sub(1,1):upper() .. name_part:sub(2):lower()
    if game_part and game_part ~= "" then
        local g = game_part:gsub(":$", "")
        g = fix_game[g:lower()] or g
        name = g .. ":" .. name
    end
    return name
end

--------------------------------------------------------------------------------
-- Permission descriptions
--------------------------------------------------------------------------------
local fix_action_desc = {
    locate = "locate you", spells = "view your active spells",
    skills = "view your skills", info = "view your stats",
    health = "view your health", bounty = "view your bounties",
}
local fix_perm_desc = {
    all = "everyone", friends = "only your friends",
    enemies = "everyone except your enemies", none = "no one",
}

--------------------------------------------------------------------------------
-- Command handling (same as lnet with callback additions)
--------------------------------------------------------------------------------

local function process_command(msg)
    -- Chat commands — same as lnet
    local to, text = msg:match("^chat%s+::(%S+)%s+(.*)")
    if not to then to, text = msg:match("^chat%s+to%s+(%S+)%s+(.*)") end
    if to then send_message({ type = "private", to = to }, text); return end

    local chan
    chan, text = msg:match("^chat%s+:([^:%s]+)%s+(.*)")
    if not chan then chan, text = msg:match("^chat%s+on%s+(%S+)%s+(.*)") end
    if chan then send_message({ type = "channel", channel = chan }, text); return end

    text = msg:match("^chat%s+(.*)")
    if text then send_message({ type = "channel" }, text); return end

    text = msg:match("^reply%s+(.*)")
    if text then
        if last_priv then send_message({ type = "private", to = last_priv }, text)
        else echo("No private message to reply to.") end
        return
    end

    if msg:match("^who$") then send_query({ type = "connected" }); return end
    local who_target = msg:match("^who%s+([A-Za-z:]+)$")
    if who_target then send_query({ type = "connected", name = who_target }); return end
    if msg:match("^stats$") then send_query({ type = "server stats" }); return end

    if msg:match("^channels?") then
        if msg:match("full") or msg:match("all") then send_query({ type = "channels" })
        else send_query({ type = "channels", num = "15" }) end
        return
    end

    local tune_ch = msg:match("^tune%s+([A-Za-z]+)$")
    if tune_ch then tune_channel(tune_ch); return end
    local untune_ch = msg:match("^untune%s+([A-Za-z]+)$")
    if untune_ch then untune_channel(untune_ch); return end

    local qtype, qname = msg:match("^(spells|skills|info|locate|health|bounty)%s+([A-Za-z:]+)$")
    if qtype then
        if is_ignored(qname) then echo("There's no point in sending a request to someone you're ignoring.")
        else send_request({ type = qtype:lower(), to = qname }) end
        return
    end

    -- Friends
    local game_part, name_part = msg:match("^add%s?friends?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.friends, name) then echo(name .. " is already on your friend list.")
        else options.friends[#options.friends+1] = name; save_options(); echo(name .. " was added to your friend list.") end
        return
    end

    if msg:match("^friends?$") then
        if #options.friends == 0 then echo("You have no friends.")
        else echo("friends: " .. table.concat(options.friends, ", ")) end
        return
    end

    -- Enemies
    game_part, name_part = msg:match("^add%s?enem[iy]e?s?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.enemies, name) then echo(name .. " is already on your enemy list.")
        else options.enemies[#options.enemies+1] = name; save_options(); echo(name .. " was added to your enemy list.") end
        return
    end

    if msg:match("^enem[iy]e?s?$") then
        if #options.enemies == 0 then echo("You have no enemies.")
        else echo("enemies: " .. table.concat(options.enemies, ", ")) end
        return
    end

    -- Allow
    if msg:match("^allow$") then
        for _, action in ipairs({"locate", "spells", "skills", "info", "health", "bounty"}) do
            local perm = options.permission[action] or "none"
            respond("You are allowing " .. (fix_perm_desc[perm] or "no one") .. " to " .. fix_action_desc[action] .. ".")
        end
        return
    end

    local allow_act, allow_grp = msg:match("^allow%s+(locate|spells|skills|info|health|bounty|all)%s+(%S+)$")
    if allow_act then
        local group_key
        if allow_grp:match("^all$") then group_key = "all"
        elseif allow_grp:match("^friends?$") then group_key = "friends"
        elseif allow_grp:match("enem") then group_key = "enemies"
        elseif allow_grp:match("^none$") then group_key = "none" end
        if group_key then
            local actions = allow_act == "all" and {"locate","spells","skills","info","health","bounty"} or {allow_act}
            for _, a in ipairs(actions) do
                options.permission[a] = group_key
                echo("You are now allowing " .. fix_perm_desc[group_key] .. " to " .. fix_action_desc[a] .. ".")
            end
            save_options()
        end
        return
    end

    -- Ignore
    if msg:match("^ignore$") then
        if #options.ignore == 0 then echo("You are not ignoring anyone.")
        else echo("Ignoring: " .. table.concat(options.ignore, ", ")) end
        return
    end

    -- Timestamps / famwindow / greeting / password / preset — same as lnet
    local ts = msg:match("^timestamps?=(on|off)$")
    if ts then options.timestamps = (ts == "on"); save_options(); echo("timestamps " .. (options.timestamps and "on" or "off")); return end

    local fw = msg:match("^famwindow=(on|off)$")
    if fw then options.fam_window = (fw == "on"); save_options(); echo("familiar window " .. (options.fam_window and "on" or "off")); return end

    local gr = msg:match("^greeting=(on|off)$")
    if gr then options.greeting = (gr == "on"); save_options(); echo("greeting " .. (options.greeting and "on" or "off")); return end

    local pw = msg:match("^password=(%S+)$")
    if pw then
        if pw == "nil" then secret[1] = nil; echo("Password cleared.")
        else secret[1] = pw; echo("Password saved locally.") end
        save_secret(); return
    end

    -- Callbacks list
    if msg:match("^callbacks$") then
        if not next(callbacks) then echo("No callbacks registered.")
        else
            for rtype, handlers in pairs(callbacks) do
                for name, _ in pairs(handlers) do
                    echo("  " .. rtype .. " -> " .. name)
                end
            end
        end
        return
    end

    -- Help
    if msg:match("^help$") then
        local out = "\n"
        out = out .. "0net (zeronet) — extended LNet chat client with custom callbacks\n\n"
        out = out .. "All standard lnet commands work (;chat, ;who, ;tune, etc.)\n"
        out = out .. "Additional commands:\n"
        out = out .. "  ;zeronet callbacks    — list registered callbacks\n\n"
        out = out .. "Callback API (from other scripts):\n"
        out = out .. "  LNet.add_callback(name, type, handler)\n"
        out = out .. "  LNet.remove_callback(name, type)\n"
        out = out .. "  LNet.clear_callbacks()\n"
        out = out .. "  LNet.safe_send(attrs, message)  — rate-limited send\n\n"
        out = out .. "Example:\n"
        out = out .. '  LNet.add_callback("my_rt", "roundtime", function(attrs)\n'
        out = out .. '    return { hard = checkrt(), soft = checkcastrt() }\n'
        out = out .. "  end)\n"
        out = out .. "\n"
        respond(out)
        return
    end

    echo("Unknown command. Type ;zeronet help")
end

--------------------------------------------------------------------------------
-- Input hook
--------------------------------------------------------------------------------

local function on_upstream(line)
    local cmd, rest = line:match("^;(,)(.*)")
    if not cmd then cmd = line:match("^;(chat%s.*)") end
    if not cmd then cmd = line:match("^;(reply%s.*)") end
    if not cmd then cmd = line:match("^;(who.*)") end
    if not cmd then cmd = line:match("^;(locate%s.*)") end
    if not cmd then cmd = line:match("^;(spells%s.*)") end
    if not cmd then cmd = line:match("^;(info%s.*)") end
    if not cmd then cmd = line:match("^;(skills%s.*)") end
    if not cmd then cmd = line:match("^;(health%s.*)") end
    if not cmd then cmd = line:match("^;(bounty%s.*)") end
    if not cmd then cmd = line:match("^;(tune%s.*)") end
    if not cmd then cmd = line:match("^;(untune%s.*)") end
    if not cmd then cmd = line:match("^;(channels?.*)") end

    if cmd then
        if cmd == "," then process_command("chat " .. (rest or ""))
        else process_command(cmd) end
        return nil
    end

    local pm_name, pm_msg = line:match("^;([A-Za-z]+):(.*)")
    if pm_name then
        process_command("chat ::" .. pm_name .. " " .. pm_msg)
        return nil
    end

    local zn_cmd = line:match("^;zeronet%s*(.*)")
    if not zn_cmd then zn_cmd = line:match("^;0net%s*(.*)") end
    if zn_cmd then
        process_command(zn_cmd:match("^%s*(.-)%s*$"))
        return nil
    end

    return line
end

UpstreamHook.add("zeronet", on_upstream)
Script.at_exit(function() UpstreamHook.remove("zeronet") end)

--------------------------------------------------------------------------------
-- Handle initial arguments
--------------------------------------------------------------------------------
local args = Script.vars[1] or ""
if args:match("^password=") then
    local pw = args:match("^password=(%S+)$")
    if pw == "nil" then secret[1] = nil; echo("Password cleared.")
    else secret[1] = pw; echo("Password saved locally.") end
    save_secret()
elseif args:lower() == "help" then
    process_command("help")
end

--------------------------------------------------------------------------------
-- Connect
--------------------------------------------------------------------------------
lnet_connect()

echo("0net (zeronet) v" .. VERSION .. " loaded (local commands + callbacks active, network TODO)")

while true do
    pause(10)
    if server_connected() and (os.time() - last_send) > 49 then
        -- TODO: send_ping
    end
end
