--- @revenant-script
--- name: lnet
--- version: 1.14.0
--- author: Tillmen (tillmen@lichproject.org)
--- game: any
--- tags: core, chat
--- description: Lich network chat system (LNet) — cross-game chat client
---
--- Original Lich5 authors: Tillmen
--- Ported to Revenant Lua from lnet.lic v1.14
---
--- NOTE: The LNet server protocol (SSL connection to lnet.lichproject.org:7155,
--- XML-based messaging, Marshal-encoded data) is Lich-specific infrastructure.
--- The network layer is stubbed with TODOs. All local UI, command parsing,
--- permissions, friends/enemies, aliases, and display formatting are fully
--- implemented and will work once the network transport is connected.

local VERSION = "1.14.0"

Script.unique()
Script.hidden()

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
local aliases = {}

local options = CharSettings.get("lnet_options") or {}
if not options.timestamps    then options.timestamps = false end
if not options.fam_window    then options.fam_window = false end
if options.greeting == nil   then options.greeting = true end
if not options.friends       then options.friends = {} end
if not options.enemies       then options.enemies = {} end
if not options.permission    then options.permission = {} end
if not options.ignore        then options.ignore = {} end
if not options.preset        then options.preset = nil end

local stored_aliases = Settings.get("lnet_aliases") or {}
for k, v in pairs(stored_aliases) do aliases[k] = v end

local stored_secret = CharSettings.get("lnet_secret") or {}
secret = stored_secret

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function save_options()
    CharSettings.set("lnet_options", options)
end

local function save_aliases()
    Settings.set("lnet_aliases", aliases)
end

local function save_secret()
    CharSettings.set("lnet_secret", secret)
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

local function escape_xml(s)
    return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function short_name(name)
    -- Extract the character name portion (after Game:)
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

local function allow(action, name)
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
    local aliased_from = aliases[from] or from
    local ch = ""
    if from ~= "[server]" then ch = "[" .. channel .. "]-" end

    local timestamp = ""
    if options.timestamps then
        timestamp = "  (" .. os.date("%X") .. ")"
    end

    local text = ch .. aliased_from .. ': "' .. message .. '"' .. timestamp
    if not is_ignored(from) then
        respond(text)
    end
end

--------------------------------------------------------------------------------
-- Network Layer (STUBBED)
-- TODO: Implement SSL connection to lnet.lichproject.org:7155
-- The LNet protocol uses XML messages over SSL:
--   <login name="X" game="Y" client="1.6" lich="5.x" [password="Z"]/>
--   <message type="channel|private|privateto" [channel="X"] [to="X"] [from="X"]>text</message>
--   <query type="connected|channels|server stats" [name="X"] [num="15"]/>
--   <request type="spells|skills|info|locate|health|bounty" to="X"/>
--   <data type="X" to="X">base64-marshal-data</data>
--   <tune channel="X"/>  <untune channel="X"/>
--   <ping/>  <pong/>
--   <moderate action="ban|gag|mod|unban|ungag|unmod" name="X" channel="Y" [length="Z"]/>
--   <admin action="create channel|delete channel" name="X" .../>
--------------------------------------------------------------------------------

local function server_connected()
    -- TODO: return true if SSL socket is open
    return not server_closed
end

local function send_xml(xml_str)
    -- TODO: write xml_str to SSL socket
    -- server:write(xml_str .. "\n")
    last_send = os.time()
    if server_closed then
        echo("lnet: not connected to server (network layer not yet implemented)")
        return false
    end
    return true
end

local function lnet_connect()
    -- TODO: Establish SSL connection to lnet.lichproject.org:7155
    -- 1. Create TCP socket, wrap in SSL with the embedded CA cert
    -- 2. Verify server CN is "lichproject.org" or "LichNet"
    -- 3. Send login XML with GameState.name, GameState.game, version, secret
    -- 4. Start read loop parsing incoming XML
    echo("lnet: network connection not yet implemented (Revenant TODO)")
    echo("lnet: local commands (help, friends, enemies, aliases, permissions) work offline")
end

local function send_message(attrs, message)
    if not server_connected() then return false end
    -- TODO: build <message> XML with attrs and text=message
    -- send_xml(xml)
    echo("lnet: send_message stub — " .. (attrs.type or "?") .. ": " .. message)
    return true
end

local function send_query(attrs)
    if not server_connected() then return false end
    -- TODO: build <query> XML
    echo("lnet: send_query stub — " .. (attrs.type or "?"))
    return true
end

local function send_request(attrs)
    if not server_connected() then return false end
    -- TODO: build <request> XML
    echo("lnet: send_request stub — " .. (attrs.type or "?"))
    return true
end

local function send_ping()
    if not server_connected() then return false end
    -- TODO: send empty XML doc as keepalive
    last_send = os.time()
    return true
end

local function tune_channel(channel)
    if not server_connected() then return false end
    -- TODO: build <tune channel="X"/> XML
    echo("lnet: tune stub — " .. channel)
    return true
end

local function untune_channel(channel)
    if not server_connected() then return false end
    -- TODO: build <untune channel="X"/> XML
    echo("lnet: untune stub — " .. channel)
    return true
end

local function moderate(attrs)
    if not server_connected() then return false end
    -- TODO: build <moderate> XML
    echo("lnet: moderate stub — " .. (attrs.action or "?"))
    return true
end

local function admin(attrs)
    if not server_connected() then return false end
    -- TODO: build <admin> XML
    echo("lnet: admin stub — " .. (attrs.action or "?"))
    return true
end

--------------------------------------------------------------------------------
-- Fix game name helper
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
-- Format time helper
--------------------------------------------------------------------------------
local function format_time(secs)
    local s = math.floor(secs) % 60
    local diff = math.floor((secs - s) / 60)
    local m = diff % 60
    diff = math.floor((diff - m) / 60)
    local h = diff % 24
    local d = math.floor((diff - h) / 24)

    local parts = {}
    if d > 0 then parts[#parts+1] = d .. " day" .. (d ~= 1 and "s" or "") end
    if h > 0 then parts[#parts+1] = h .. " hour" .. (h ~= 1 and "s" or "") end
    if m > 0 then parts[#parts+1] = m .. " minute" .. (m ~= 1 and "s" or "") end
    if s > 0 and d < 1 and h < 1 then parts[#parts+1] = s .. " second" .. (s ~= 1 and "s" or "") end

    local result = table.concat(parts, ", ")
    if result == "1 day" then result = "24 hours" end
    return result
end

--------------------------------------------------------------------------------
-- Multiplier for ban/gag durations
--------------------------------------------------------------------------------
local time_multiplier = {
    s = 1, second = 1, seconds = 1,
    m = 60, minute = 60, minutes = 60,
    h = 3600, hour = 3600, hours = 3600,
    d = 86400, day = 86400, days = 86400,
    y = 31536000, year = 31536000, years = 31536000,
}

--------------------------------------------------------------------------------
-- Permission display
--------------------------------------------------------------------------------
local fix_action_desc = {
    locate = "locate you",
    spells = "view your active spells",
    skills = "view your skills",
    info   = "view your stats",
    health = "view your health",
    bounty = "view your bounties",
}

local fix_perm_desc = {
    all     = "everyone",
    friends = "only your friends",
    enemies = "everyone except your enemies",
    none    = "no one",
}

--------------------------------------------------------------------------------
-- Command handling
--------------------------------------------------------------------------------

local function process_command(msg)
    -- Chat to private user: chat ::Name message  or  chat to Name message
    local to, text = msg:match("^chat%s+::(%S+)%s+(.*)")
    if not to then to, text = msg:match("^chat%s+to%s+(%S+)%s+(.*)") end
    if to then
        send_message({ type = "private", to = to }, text)
        return
    end

    -- Chat to channel: chat :channel message  or  chat on channel message
    local chan
    chan, text = msg:match("^chat%s+:([^:%s]+)%s+(.*)")
    if not chan then chan, text = msg:match("^chat%s+on%s+(%S+)%s+(.*)") end
    if chan then
        send_message({ type = "channel", channel = chan }, text)
        return
    end

    -- Chat to default channel: chat message  or  ,message
    text = msg:match("^chat%s+(.*)")
    if text then
        send_message({ type = "channel" }, text)
        return
    end

    -- Reply to last private message
    text = msg:match("^reply%s+(.*)")
    if text then
        if last_priv then
            send_message({ type = "private", to = last_priv }, text)
        else
            echo("No private message to reply to.")
        end
        return
    end

    -- Who
    if msg:match("^who$") then
        send_query({ type = "connected" })
        return
    end
    local who_target = msg:match("^who%s+([A-Za-z:]+)$")
    if who_target then
        send_query({ type = "connected", name = who_target })
        return
    end

    -- Stats
    if msg:match("^stats$") then
        send_query({ type = "server stats" })
        return
    end

    -- Channels
    local ch_full = msg:match("^channels?%s*(full|all)?")
    if msg:match("^channels?") then
        if msg:match("full") or msg:match("all") then
            send_query({ type = "channels" })
        else
            send_query({ type = "channels", num = "15" })
        end
        return
    end

    -- Tune / Untune
    local tune_ch = msg:match("^tune%s+([A-Za-z]+)$")
    if tune_ch then tune_channel(tune_ch); return end
    local untune_ch = msg:match("^untune%s+([A-Za-z]+)$")
    if untune_ch then untune_channel(untune_ch); return end

    -- Data queries: spells, skills, info, locate, health, bounty
    local qtype, qname = msg:match("^(spells|skills|info|locate|health|bounty)%s+([A-Za-z:]+)$")
    if qtype then
        if is_ignored(qname) then
            echo("There's no point in sending a request to someone you're ignoring.")
        else
            send_request({ type = qtype:lower(), to = qname })
        end
        return
    end

    -- Add alias
    local real, aliased = msg:match("^add%s?alias%s+(%S+)%s+(.+)$")
    if real then
        aliases[real] = aliased
        save_aliases()
        echo("chats from " .. real .. " will now appear as " .. aliased)
        return
    end

    -- Remove alias
    local del_alias = msg:match("^(?:del|rem|delete|remove)%s?alias%s+(.+)$")
    if not del_alias then del_alias = msg:match("^[dr]e[lm]e?t?e?%s?alias%s+(.+)$") end
    if del_alias then
        local found = false
        for k, v in pairs(aliases) do
            if v == del_alias then aliases[k] = nil; found = true end
        end
        save_aliases()
        echo(found and "alias deleted" or "couldn't find an alias by that name")
        return
    end

    -- List aliases
    if msg:match("^aliases$") then
        if not next(aliases) then
            echo("You have no aliases.")
        else
            local out = "\n"
            for k, v in pairs(aliases) do
                out = out .. "   " .. k .. " => " .. v .. "\n"
            end
            respond(out)
        end
        return
    end

    -- Add friend
    local game_part, name_part = msg:match("^add%s?friends?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.friends, name) then
            echo(name .. " is already on your friend list.")
        else
            options.friends[#options.friends + 1] = name
            save_options()
            echo(name .. " was added to your friend list.")
        end
        return
    end

    -- Remove friend
    game_part, name_part = msg:match("^[dr]e[lm]e?t?e?%s?friends?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.friends, name) then
            save_options()
            echo(name .. " was removed from your friend list.")
        else
            echo(name .. " was not found on your friend list.")
        end
        return
    end

    -- List friends
    if msg:match("^friends?$") then
        if #options.friends == 0 then
            echo("You have no friends.")
        else
            echo("friends: " .. table.concat(options.friends, ", "))
        end
        return
    end

    -- Add enemy
    game_part, name_part = msg:match("^add%s?enem[iy]e?s?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.enemies, name) then
            echo(name .. " is already on your enemy list.")
        else
            options.enemies[#options.enemies + 1] = name
            save_options()
            echo(name .. " was added to your enemy list.")
        end
        return
    end

    -- Remove enemy
    game_part, name_part = msg:match("^[dr]e[lm]e?t?e?%s?enem[iy]e?s?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.enemies, name) then
            save_options()
            echo(name .. " was removed from your enemy list.")
        else
            echo(name .. " was not found on your enemy list.")
        end
        return
    end

    -- List enemies
    if msg:match("^enem[iy]e?s?$") then
        if #options.enemies == 0 then
            echo("You have no enemies.")
        else
            echo("enemies: " .. table.concat(options.enemies, ", "))
        end
        return
    end

    -- Allow (show)
    if msg:match("^allow$") then
        for _, action in ipairs({"locate", "spells", "skills", "info", "health", "bounty"}) do
            local perm = options.permission[action] or "none"
            respond("You are allowing " .. (fix_perm_desc[perm] or "no one") .. " to " .. fix_action_desc[action] .. ".")
        end
        return
    end

    -- Allow (set)
    local allow_action, allow_group = msg:match("^allow%s+(locate|spells|skills|info|health|bounty|all)%s+(%S+)$")
    if allow_action then
        local group_key
        if allow_group:match("^all$") then group_key = "all"
        elseif allow_group:match("^friends?$") then group_key = "friends"
        elseif allow_group:match("enem") then group_key = "enemies"
        elseif allow_group:match("^none$") then group_key = "none"
        end
        if group_key then
            local actions = allow_action == "all"
                and {"locate", "spells", "skills", "info", "health", "bounty"}
                or {allow_action}
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
        if #options.ignore == 0 then
            echo("You are not ignoring anyone.")
        else
            echo("You are ignoring the following people: " .. table.concat(options.ignore, ", "))
        end
        return
    end

    game_part, name_part = msg:match("^ignore%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.ignore, name) then
            echo("You were already ignoring " .. name .. ".")
        else
            options.ignore[#options.ignore + 1] = name
            save_options()
            echo("You are now ignoring " .. name .. ".")
        end
        return
    end

    game_part, name_part = msg:match("^unignore%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.ignore, name) then
            save_options()
            echo("You are no longer ignoring " .. name .. ".")
        else
            echo(name .. " wasn't being ignored.")
        end
        return
    end

    -- Timestamps
    local ts_val = msg:match("^timestamps?=(on|off)$")
    if ts_val then
        options.timestamps = (ts_val == "on")
        save_options()
        echo("timestamps will " .. (options.timestamps and "" or "not ") .. "be shown")
        return
    end

    -- Familiar window
    local fw_val = msg:match("^famwindow=(on|off)$")
    if fw_val then
        options.fam_window = (fw_val == "on")
        save_options()
        echo("chats will be sent to the " .. (options.fam_window and "familiar" or "thought") .. " window")
        return
    end

    -- Greeting
    local gr_val = msg:match("^greeting=(on|off)$")
    if gr_val then
        options.greeting = (gr_val == "on")
        save_options()
        echo("greeting will " .. (options.greeting and "" or "not ") .. "be shown at login")
        return
    end

    -- Password
    local pw = msg:match("^password=(%S+)$")
    if pw then
        if pw == "nil" then
            secret[1] = nil
            echo("Password cleared.")
        else
            secret[1] = pw
            echo("Password saved locally.")
        end
        save_secret()
        return
    end

    -- Preset
    local preset_val = msg:match("^preset=(%S+)$")
    if preset_val then
        if preset_val:match("^nil$") then
            options.preset = nil
            echo("Removed highlight preset for lnet messages.")
        elseif preset_val:match("^lnet$") then
            options.preset = "lnet"
            echo("Set highlight preset for lnet messages to 'lnet'.")
        elseif preset_val:match("^thoughts?$") then
            options.preset = "thought"
            echo("Set highlight preset for lnet messages to 'thought'.")
        else
            echo("Unknown option for preset — only 'lnet', 'thought' and 'nil' are supported.")
        end
        save_options()
        return
    end

    -- Ban/gag/mod on channel
    local action_type, target_name, target_channel = msg:match("^(ban|gag|mod|banip)%s+([%w:]+)%s+on%s+(%w+)$")
    if action_type then
        moderate({ action = action_type:lower(), name = target_name, channel = target_channel })
        return
    end

    -- Ban/gag with time
    local a, n, c, dur, unit = msg:match("^(ban|gag|banip)%s+([%w:]+)%s+on%s+(%w+)%s+for%s+(%d+)%s*(%a+)$")
    if a then
        local mult = time_multiplier[unit:lower()] or 1
        moderate({ action = a:lower(), name = n, channel = c, length = tostring(tonumber(dur) * mult) })
        return
    end

    -- Unban/ungag/unmod
    action_type, target_name, target_channel = msg:match("^(unban|ungag|unmod)%s+([%w:]+)%s+on%s+(%w+)$")
    if action_type then
        moderate({ action = action_type:lower(), name = target_name, channel = target_channel })
        return
    end

    -- Create channel
    local hidden, private, ch_name, ch_desc = msg:match("^create%s+(hidden)?%s*(private)?%s*channel%s+(%w+)%s+(.+)$")
    if ch_name then
        admin({
            action = "create channel", name = ch_name, description = ch_desc:match("^%s*(.-)%s*$"),
            hidden = hidden and "yes" or "no",
            private = private and "yes" or "no",
        })
        return
    end

    -- Delete channel
    local del_ch = msg:match("^delete%s+channel%s+(%w+)$")
    if del_ch then
        admin({ action = "delete channel", name = del_ch })
        return
    end

    -- Help
    if msg:match("^help$") then
        local lc = ";"  -- lich char equivalent
        local sn = "lnet"
        local out = "\n"
        out = out .. lc .. "chat <message>                     send a message to your default channel\n"
        out = out .. lc .. ",<message>                         ''\n"
        out = out .. lc .. "chat on <channel name> <message>   send a message to the given channel\n"
        out = out .. lc .. "chat :<channel name> <message>     ''\n"
        out = out .. lc .. "chat to <name> <message>           send a private message\n"
        out = out .. lc .. "chat ::<name> <message>            ''\n"
        out = out .. lc .. "<name>:<message>                   ''\n"
        out = out .. lc .. "who                                list who's connected\n"
        out = out .. lc .. "who <channel>                      list who's tuned into the given channel\n"
        out = out .. lc .. "who <name>                         tells if a user is connected\n"
        out = out .. lc .. "channels                           list the 15 most populated channels\n"
        out = out .. lc .. "channels full                      list all available channels\n"
        out = out .. lc .. "tune <channel name>                listen to the given channel\n"
        out = out .. lc .. "untune <channel name>              stop listening to the given channel\n"
        out = out .. "\n"
        out = out .. lc .. "locate <name>                      show someone's current room\n"
        out = out .. lc .. "spells <name>                      show someone's active spells\n"
        out = out .. lc .. "skills <name>                      show someone's skills\n"
        out = out .. lc .. "info <name>                        show someone's stats\n"
        out = out .. lc .. "health <name>                      show someone's health/spirit/stamina\n"
        out = out .. lc .. "bounty <name>                      show someone's current task\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " stats                         server statistics\n"
        out = out .. ";" .. sn .. " timestamps=<on/off>           toggle timestamps\n"
        out = out .. ";" .. sn .. " famwindow=<on/off>            toggle familiar window\n"
        out = out .. ";" .. sn .. " greeting=<on/off>             toggle server greeting\n"
        out = out .. ";" .. sn .. " preset=<lnet/thought/nil>     set highlight preset\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " friends                       list friends\n"
        out = out .. ";" .. sn .. " add friend <name>             add friend\n"
        out = out .. ";" .. sn .. " del friend <name>             delete friend\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " enemies                       list enemies\n"
        out = out .. ";" .. sn .. " add enemy <name>              add enemy\n"
        out = out .. ";" .. sn .. " del enemy <name>              delete enemy\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " allow                         list permissions\n"
        out = out .. ";" .. sn .. " allow <action> <group>        set permissions\n"
        out = out .. "      <action>: locate, spells, skills, info, health, bounty, all\n"
        out = out .. "      <group>: all, friends, non-enemies, none\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " aliases                       list aliases\n"
        out = out .. ";" .. sn .. " add alias <name> <new_name>   create alias\n"
        out = out .. ";" .. sn .. " del alias <new_name>          delete alias\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " ignore                        list ignored\n"
        out = out .. ";" .. sn .. " ignore <name>                 ignore a person\n"
        out = out .. ";" .. sn .. " unignore <name>               unignore a person\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " password=<password>           set password\n"
        out = out .. ";" .. sn .. " password=nil                  remove password\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " create [hidden] [private] channel <name> <description>\n"
        out = out .. ";" .. sn .. " delete channel <name>\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " ban <char> on <channel> [for <time>]\n"
        out = out .. ";" .. sn .. " unban <char> on <channel>\n"
        out = out .. ";" .. sn .. " gag <char> on <channel> [for <time>]\n"
        out = out .. ";" .. sn .. " ungag <char> on <channel>\n"
        out = out .. ";" .. sn .. " mod <char> on <channel>\n"
        out = out .. ";" .. sn .. " unmod <char> on <channel>\n"
        out = out .. "\n"
        respond(out)
        return
    end

    echo("Unknown command. Type ;lnet help")
end

--------------------------------------------------------------------------------
-- Input hook for ; commands
--------------------------------------------------------------------------------

local function on_upstream(line)
    -- Match ;chat, ;,, ;who, ;locate, ;spells, ;info, ;skills, ;health, ;bounty, ;tune, ;untune, ;channels, ;reply
    local cmd, rest = line:match("^;(,)(.*)")
    if not cmd then cmd, rest = line:match("^;(chat%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(reply%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(who.*)()") end
    if not cmd then cmd, rest = line:match("^;(locate%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(spells%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(info%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(skills%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(health%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(bounty%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(tune%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(untune%s.*)()") end
    if not cmd then cmd, rest = line:match("^;(channels?.*)()") end

    if cmd then
        if cmd == "," then
            process_command("chat " .. (rest or ""))
        else
            process_command(cmd)
        end
        return nil -- consume the input
    end

    -- ;Name:message shorthand for private message
    local pm_name, pm_msg = line:match("^;([A-Za-z]+):(.*)")
    if pm_name then
        process_command("chat ::" .. pm_name .. " " .. pm_msg)
        return nil
    end

    -- ;lnet <subcommand>
    local lnet_cmd = line:match("^;lnet%s*(.*)")
    if lnet_cmd then
        process_command(lnet_cmd:match("^%s*(.-)%s*$"))
        return nil
    end

    return line
end

UpstreamHook.add("lnet", on_upstream)
Script.at_exit(function() UpstreamHook.remove("lnet") end)

--------------------------------------------------------------------------------
-- Handle initial arguments
--------------------------------------------------------------------------------
local args = Script.vars[1] or ""
if args:match("^password=(%S+)$") then
    local pw = args:match("^password=(%S+)$")
    if pw == "nil" then
        secret[1] = nil
        echo("Password cleared.")
    else
        secret[1] = pw
        echo("Password saved locally.")
    end
    save_secret()
elseif args:lower() == "help" then
    process_command("help")
end

--------------------------------------------------------------------------------
-- Connect to server
--------------------------------------------------------------------------------
lnet_connect()

--------------------------------------------------------------------------------
-- Main loop — process unique_get messages
-- In Lich5, the script reads from unique_buffer in a while loop.
-- In Revenant, we use the upstream hook above to intercept commands.
-- The main loop just keeps the script alive and handles keepalive pings.
--------------------------------------------------------------------------------

echo("LNet v" .. VERSION .. " loaded (local commands active, network layer TODO)")

while true do
    pause(10)

    -- Keepalive: send ping if no send in 49 seconds
    if server_connected() and (os.time() - last_send) > 49 then
        send_ping()
    end
end
