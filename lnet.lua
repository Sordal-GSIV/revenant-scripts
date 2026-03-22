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
--- changelog:
---   1.14 (2025-09-19) — Add safeguards for non-valid XML; newer REXML support
---   1.13 (2025-06-01) — change class checks to is_a? checks
---   1.12 (2024-12-14) — REXML gem 3.3.2+ compatibility prevention
---   1.11 (2024-06-06) — custom preset highlights (none, lnet, thoughts)
---   1.10 (2024-06-05) — Update SSL cert
---   1.9  (2024-01-08) — Remove combat leadership skill
---   1.8  (2023-11-08) — rubocop cleanup; remove spell-ranks; remove forage tracking
---   1.7  (2022-11-23) — removed $SAFE references
---   1.6  (2016-01-10) — fixed room id lookup for locate; added alias feature
---   1.5  (2015-11-25) — added reply command
---   1.4  (2015-05-13) — channel owners and moderators to front of ;who list
--- @lic-certified: complete 2026-03-20

local VERSION     = "1.14.0"
local CLIENT_VER  = "1.6"     -- protocol version sent to server (matches Lich5 client attr)
local LNET_HOST   = "lnet.lichproject.org"
local LNET_PORT   = 7155

-- CA certificate for lnet.lichproject.org (updated 2024-06-05, valid until 2044-05-31)
local LNET_CA_CERT = [[-----BEGIN CERTIFICATE-----
MIIDoDCCAoigAwIBAgIUYwhIyTlqWaEd5mYGXoQQoC+ndKcwDQYJKoZIhvcNAQEL
BQAwYTELMAkGA1UEBhMCVVMxETAPBgNVBAgMCElsbGlub2lzMRIwEAYDVQQKDAlN
YXR0IExvd2UxDzANBgNVBAMMBlJvb3RDQTEaMBgGCSqGSIb3DQEJARYLbWF0dEBp
bzQudXMwHhcNMjQwNjA1MTM1NzUxWhcNNDQwNTMxMTM1NzUxWjBhMQswCQYDVQQG
EwJVUzERMA8GA1UECAwISWxsaW5vaXMxEjAQBgNVBAoMCU1hdHQgTG93ZTEPMA0G
A1UEAwwGUm9vdENBMRowGAYJKoZIhvcNAQkBFgttYXR0QGlvNC51czCCASIwDQYJ
KoZIhvcNAQEBBQADggEPADCCAQoCggEBAJwhGfQgwI1h4vlqAqaR152AlewjJMlL
yoqtjoS9Cyri23SY7c6v0rwhoOXuoV1D2d9InmmE2CgLL3Bn2sNa/kWFjkyedUca
vd8JrtGQzEkVH83CIPiKFCWLE5SXLvqCVx7Jz/pBBL1s173p69kOy0REYAV/OAdj
ioCXK6tHqYG70xvLIJGiTrExGeOttMw2S+86y4bSxj2i35IscaBTepPv7BWH8JtZ
yN4Xv9DBr/99sWSarlzUW6+FTcNqdJLP5W5a508VLJnevmlisswlazKiYNriCQvZ
snmPJrYFYMxe9JIKl1CA8MiUKUx8AUt39KzxkgZrq40VxIrpdxrnUKUCAwEAAaNQ
ME4wHQYDVR0OBBYEFJxuCVGIbPP3LO6GAHAViOCKZ4HIMB8GA1UdIwQYMBaAFJxu
CVGIbPP3LO6GAHAViOCKZ4HIMAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQELBQAD
ggEBAGKn0vYx9Ta5+/X1WRUuADuie6JuNMHUxzYtxwEba/m5lA4nE5f2yoO6Y/Y3
LZDx2Y9kWt+7pGQ2SKOT79gNcnOSc3SGYWkX48J6C1hihhjD3AfD0hb1mgvlJuij
zNnZ7vczOF8AcvBeu8ww5eIrkN6TTshjICg71/deVo9HvjhiCGK0XvL+WL6EQwLe
6/nVVFrPfd0sRZZ5OTJR5nM1kA71oChUw9mHCyrAc3zYyW37k+p8ADRFfON8th8M
1Blel1SpgqlQ22WpYoHbUCSjGt6JKC/HrSHdKBezTuRahOSfqwncAE77Dz4FJaQ5
WD2mk3SZbB2ytAHUDEy3xr697EI=
-----END CERTIFICATE-----]]

Script.unique()
Script.hidden()

--------------------------------------------------------------------------------
-- Settings persistence helpers (all settings stored as JSON strings)
--------------------------------------------------------------------------------

local function load_table(key, default)
    local raw = CharSettings[key]
    if raw then
        local ok, val = pcall(Json.decode, raw)
        if ok and type(val) == "table" then return val end
    end
    return default or {}
end

local function save_table(key, tbl)
    CharSettings[key] = Json.encode(tbl)
end

local function load_global_table(key, default)
    local raw = Settings[key]
    if raw then
        local ok, val = pcall(Json.decode, raw)
        if ok and type(val) == "table" then return val end
    end
    return default or {}
end

local function save_global_table(key, tbl)
    Settings[key] = Json.encode(tbl)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local socket         = nil
local server_closed  = true
local last_recv      = os.time()
local last_send      = os.time()
local last_priv      = nil
local server_restart = false

-- Per-connection data request waiters: {type, name, data} tables
local waiting = {}

local options = load_table("lnet_options")
if options.timestamps == nil    then options.timestamps = false end
if options.fam_window == nil    then options.fam_window = false end
if options.greeting == nil      then options.greeting = true end
if not options.friends          then options.friends = {} end
if not options.enemies          then options.enemies = {} end
if not options.permission       then options.permission = {} end
if not options.ignore           then options.ignore = {} end
-- options.preset: nil / "lnet" / "thought"

local aliases = load_global_table("lnet_aliases")

local secret = load_table("lnet_secret")   -- secret[1] = password string or nil

local function save_options()  save_table("lnet_options", options) end
local function save_aliases()  save_global_table("lnet_aliases", aliases) end
local function save_secret()   save_table("lnet_secret", secret) end

--------------------------------------------------------------------------------
-- Simple list helpers
--------------------------------------------------------------------------------

local function list_contains(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

local function list_remove(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then table.remove(tbl, i); return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- XML helpers
--------------------------------------------------------------------------------

local function escape_xml(s)
    return tostring(s):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;")
end

local function unescape_xml(s)
    return (s or ""):gsub("&amp;","&"):gsub("&lt;","<"):gsub("&gt;",">"):gsub("&quot;",'"'):gsub("&apos;","'")
end

--- Build a simple XML tag string: <tag k="v"...>text</tag> or <tag k="v".../>
local function build_tag(tag, attrs, text)
    local parts = { "<", tag }
    if attrs then
        -- Sort for deterministic output
        local keys = {}
        for k in pairs(attrs) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            parts[#parts+1] = ' ' .. k .. '="' .. escape_xml(attrs[k]) .. '"'
        end
    end
    if text ~= nil then
        parts[#parts+1] = ">"
        parts[#parts+1] = tostring(text)
        parts[#parts+1] = "</" .. tag .. ">"
    else
        parts[#parts+1] = "/>"
    end
    return table.concat(parts)
end

--- Parse a single XML element: returns tag, attrs, text (all may be nil on failure).
--- attrs keys are lowercased.  text has XML entities decoded.
local function parse_xml_elem(xml)
    local tag = xml:match("^%s*<([%w%-]+)")
    if not tag then return nil end
    local attrs = {}
    for k, v in xml:gmatch('%s+([%w%-]+)%s*=%s*"([^"]*)"') do
        attrs[k] = unescape_xml(v)
    end
    -- text content between <tag>...</tag>
    local text = xml:match(">[%s]*(.-)[%s]*</" .. tag .. ">%s*$")
    if text then text = unescape_xml(text) end
    return tag, attrs, text
end

--- Extract the next complete XML element from a string buffer.
--- Returns: element_string, remainder  (or nil, original if not yet complete)
local function extract_xml_elem(buf)
    -- skip leading whitespace / empty lines
    local s = buf:find("[^ \t\r\n]")
    if not s then return nil, buf end
    buf = buf:sub(s)

    -- self-closing: <tag .../>
    local sc = buf:match("^<[^>]*/>")
    if sc then return sc, buf:sub(#sc+1) end

    -- get tag name
    local tag = buf:match("^<([%w%-]+)")
    if not tag then
        -- garbage at front; skip to next '<'
        local nx = buf:find("<", 2)
        if nx then return nil, buf:sub(nx) else return nil, "" end
    end

    local close = "</" .. tag .. ">"
    local cp = buf:find(close, 1, true)
    if not cp then return nil, buf end

    local elem = buf:sub(1, cp + #close - 1)
    return elem, buf:sub(cp + #close)
end

--------------------------------------------------------------------------------
-- Network send helpers
--------------------------------------------------------------------------------

local function server_connected()
    return not server_closed and socket ~= nil and not socket:closed()
end

local function send_raw(xml)
    if not server_connected() then return false end
    socket:writeln(xml)
    last_send = os.time()
    return true
end

local function send_ping()
    if not server_connected() then return false end
    -- Empty XML document used as keepalive (matches Lich5 behavior)
    send_raw('<?xml version="1.0"?>')
    return true
end

local function send_message(attrs, message)
    if not server_connected() then return false end
    return send_raw(build_tag("message", attrs, escape_xml(message)))
end

local function send_query(attrs)
    if not server_connected() then return false end
    return send_raw(build_tag("query", attrs, nil))
end

local function send_request(attrs)
    if not server_connected() then return false end
    return send_raw(build_tag("request", attrs, nil))
end

--- Encode data value as base64-Marshal and send <data> element.
local function send_data(attrs, data)
    if not server_connected() then return false end
    local raw, err = Marshal.dump(data)
    if not raw then
        echo("lnet: marshal error: " .. tostring(err))
        return false
    end
    local encoded = Crypto.base64_encode(raw)
    return send_raw(build_tag("data", attrs, encoded))
end

local function tune_channel(channel)
    if not server_connected() then return false end
    return send_raw(build_tag("tune", { channel = channel }, nil))
end

local function untune_channel(channel)
    if not server_connected() then return false end
    return send_raw(build_tag("untune", { channel = channel }, nil))
end

local function moderate(attrs)
    if not server_connected() then return false end
    return send_raw(build_tag("moderate", attrs, nil))
end

local function admin(attrs)
    if not server_connected() then return false end
    return send_raw(build_tag("admin", attrs, nil))
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function is_ignored(name)
    return list_contains(options.ignore, name)
        or list_contains(options.ignore, name:match("[A-Z][a-z]+$") or "")
end

local function is_friend(name)
    return list_contains(options.friends, name)
        or list_contains(options.friends, name:match("[A-Z][a-z]+$") or "")
end

local function is_enemy(name)
    return list_contains(options.enemies, name)
        or list_contains(options.enemies, name:match("[A-Z][a-z]+$") or "")
end

local function echo_thought(from, message, channel)
    if is_ignored(from) then return end
    local aliased_from = aliases[from] or from
    local ch = (from ~= "[server]") and ("[" .. channel .. "]-") or ""
    local timestamp = options.timestamps and ("  (" .. os.date("%X") .. ")") or ""
    local preset_open  = options.preset and ("<preset id='" .. options.preset .. "'>") or ""
    local preset_close = options.preset and "</preset>" or ""
    local safe_msg = escape_xml(message)

    local xml_line
    if options.fam_window then
        xml_line = '<pushStream id="familiar" ifClosedStyle="watching"/>'
            .. ch .. aliased_from .. ': "' .. safe_msg .. '"' .. timestamp
            .. '\n<popStream/>'
    else
        xml_line = '<pushStream id="thoughts"/>'
            .. preset_open .. ch .. aliased_from .. ':' .. preset_close
            .. ' "' .. safe_msg .. '"' .. timestamp
            .. '\n<popStream/>'
    end
    respond(xml_line)
end

--------------------------------------------------------------------------------
-- Format helpers
--------------------------------------------------------------------------------

local function format_time(secs)
    secs = math.floor(tonumber(secs) or 0)
    local s = secs % 60
    local diff = math.floor((secs - s) / 60)
    local m = diff % 60
    diff = math.floor((diff - m) / 60)
    local h = diff % 24
    local d = math.floor((diff - h) / 24)
    local parts = {}
    if d > 0 then parts[#parts+1] = d .. " day"    .. (d ~= 1 and "s" or "") end
    if h > 0 then parts[#parts+1] = h .. " hour"   .. (h ~= 1 and "s" or "") end
    if m > 0 then parts[#parts+1] = m .. " minute" .. (m ~= 1 and "s" or "") end
    if s > 0 and d < 1 and h < 1 then
        parts[#parts+1] = s .. " second" .. (s ~= 1 and "s" or "")
    end
    local result = table.concat(parts, ", ")
    if result == "1 day" then result = "24 hours" end
    return result ~= "" and result or "0 seconds"
end

--- Format fractional minutes as MM:SS or H:MM:SS
local function minutes_to_time(mins)
    local total_secs = math.floor((tonumber(mins) or 0) * 60)
    local s = total_secs % 60
    local total_mins = math.floor(total_secs / 60)
    local m = total_mins % 60
    local h = math.floor(total_mins / 60)
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%d:%02d", m, s)
    end
end

local time_multiplier = {
    s=1, second=1, seconds=1,
    m=60, minute=60, minutes=60,
    h=3600, hour=3600, hours=3600,
    d=86400, day=86400, days=86400,
    y=31536000, year=31536000, years=31536000,
}

local fix_game = { gsf="GSF", gsiv="GSIV", gsplat="GSPlat" }

local function resolve_name(game_part, name_part)
    local name = name_part:sub(1,1):upper() .. name_part:sub(2):lower()
    if game_part and game_part ~= "" then
        local g = game_part:gsub(":$","")
        g = fix_game[g:lower()] or g
        name = g .. ":" .. name
    end
    return name
end

local fix_action_desc = {
    locate="locate you", spells="view your active spells",
    skills="view your skills", info="view your stats",
    health="view your health", bounty="view your bounties",
}

local fix_perm_desc = {
    all="everyone", friends="only your friends",
    enemies="everyone except your enemies", none="no one",
}

--------------------------------------------------------------------------------
-- Permission check
--------------------------------------------------------------------------------

local function allow(action, name)
    local perm = options.permission[action]
    if perm == "all"     then return true
    elseif perm == "friends"  then return is_friend(name)
    elseif perm == "enemies"  then return not is_enemy(name)
    else return false
    end
end

--------------------------------------------------------------------------------
-- Server data request handler (someone is requesting our data)
--------------------------------------------------------------------------------

local skill_name_map = {
    ["Two Weapon Combat"]            = "two_weapon_combat",
    ["Armor Use"]                    = "armor_use",
    ["Shield Use"]                   = "shield_use",
    ["Combat Maneuvers"]             = "combat_maneuvers",
    ["Edged Weapons"]                = "edged_weapons",
    ["Blunt Weapons"]                = "blunt_weapons",
    ["Two-Handed Weapons"]           = "two_handed_weapons",
    ["Ranged Weapons"]               = "ranged_weapons",
    ["Thrown Weapons"]               = "thrown_weapons",
    ["Polearm Weapons"]              = "polearm_weapons",
    ["Brawling"]                     = "brawling",
    ["Ambush"]                       = "ambush",
    ["Multi Opponent Combat"]        = "multi_opponent_combat",
    ["Physical Fitness"]             = "physical_fitness",
    ["Dodging"]                      = "dodging",
    ["Arcane Symbols"]               = "arcane_symbols",
    ["Magic Item Use"]               = "magic_item_use",
    ["Spell Aiming"]                 = "spell_aiming",
    ["Harness Power"]                = "harness_power",
    ["Elemental Mana Control"]       = "elemental_mana_control",
    ["Mental Mana Control"]          = "mental_mana_control",
    ["Spirit Mana Control"]          = "spirit_mana_control",
    ["Elemental Lore - Air"]         = "elemental_lore_air",
    ["Elemental Lore - Earth"]       = "elemental_lore_earth",
    ["Elemental Lore - Fire"]        = "elemental_lore_fire",
    ["Elemental Lore - Water"]       = "elemental_lore_water",
    ["Spiritual Lore - Blessings"]   = "spiritual_lore_blessings",
    ["Spiritual Lore - Religion"]    = "spiritual_lore_religion",
    ["Spiritual Lore - Summoning"]   = "spiritual_lore_summoning",
    ["Sorcerous Lore - Demonology"]  = "sorcerous_lore_demonology",
    ["Sorcerous Lore - Necromancy"]  = "sorcerous_lore_necromancy",
    ["Mental Lore - Divination"]     = "mental_lore_divination",
    ["Mental Lore - Manipulation"]   = "mental_lore_manipulation",
    ["Mental Lore - Telepathy"]      = "mental_lore_telepathy",
    ["Mental Lore - Transference"]   = "mental_lore_transference",
    ["Mental Lore - Transformation"] = "mental_lore_transformation",
    ["Survival"]                     = "survival",
    ["Disarming Traps"]              = "disarming_traps",
    ["Picking Locks"]                = "picking_locks",
    ["Stalking and Hiding"]          = "stalking_and_hiding",
    ["Perception"]                   = "perception",
    ["Climbing"]                     = "climbing",
    ["Swimming"]                     = "swimming",
    ["First Aid"]                    = "first_aid",
    ["Trading"]                      = "trading",
    ["Pickpocketing"]                = "pickpocketing",
}

local spell_circle_display = {
    minor_elemental="Minor Elemental", major_elemental="Major Elemental",
    minor_spiritual="Minor Spiritual", major_spiritual="Major Spiritual",
    minor_mental="Minor Mental",
    wizard="Wizard", sorcerer="Sorcerer", ranger="Ranger",
    paladin="Paladin", empath="Empath", cleric="Cleric", bard="Bard",
}

local function handle_data_request(req_type, from)
    if is_ignored(from) then
        send_data({ type=req_type, to=from }, nil)
        return
    end

    if req_type == "spells" then
        if allow("spells", from) then
            echo("lnet: sending spell info to " .. from .. "...")
            local active_spells = {}
            local sp = Spell.active()
            for _, spell in ipairs(sp) do
                active_spells[tostring(spell.num)] = spell.timeleft
            end
            send_data({ type=req_type, to=from }, active_spells)
        else
            echo("lnet: rejecting request from " .. from .. " for spell info...")
            send_data({ type=req_type, to=from }, nil)
        end

    elseif req_type == "skills" then
        if allow("skills", from) then
            echo("lnet: sending skills to " .. from .. "...")
            local skills = {}
            for display_name, lua_name in pairs(skill_name_map) do
                local ranks = Skills[lua_name]
                if type(ranks) == "number" and ranks > 0 then
                    skills[display_name] = ranks
                end
            end
            -- Spell circles
            for lua_name, display_name in pairs(spell_circle_display) do
                local ranks = Spells[lua_name]
                if type(ranks) == "number" and ranks > 0 then
                    skills[display_name] = ranks
                end
            end
            send_data({ type=req_type, to=from }, skills)
        else
            echo("lnet: rejecting request from " .. from .. " for skills...")
            send_data({ type=req_type, to=from }, nil)
        end

    elseif req_type == "info" then
        if allow("info", from) then
            echo("lnet: sending stats to " .. from .. "...")
            local str = Stats.str; local con = Stats.con
            local dex = Stats.dex; local agi = Stats.agi
            local dis = Stats.dis; local aur = Stats.aur
            local log = Stats.log; local int = Stats.int
            local wis = Stats.wis; local inf = Stats.inf
            local info = {
                Race         = Stats.race,
                Profession   = Stats.prof,
                Gender       = Stats.gender,
                Age          = tostring(Stats.age),
                Expr         = tostring(Stats.experience),
                Level        = GameState.level,
                Strength     = { str[1], str[2] },
                Constitution = { con[1], con[2] },
                Dexterity    = { dex[1], dex[2] },
                Agility      = { agi[1], agi[2] },
                Discipline   = { dis[1], dis[2] },
                Aura         = { aur[1], aur[2] },
                Logic        = { log[1], log[2] },
                Intuition    = { int[1], int[2] },
                Wisdom       = { wis[1], wis[2] },
                Influence    = { inf[1], inf[2] },
                Mana         = GameState.mana,
            }
            send_data({ type=req_type, to=from }, info)
        else
            echo("lnet: rejecting request from " .. from .. " for stats...")
            send_data({ type=req_type, to=from }, nil)
        end

    elseif req_type == "locate" then
        if allow("locate", from) then
            echo("lnet: sending location to " .. from .. "...")
            local loot_names = {}
            for _, obj in ipairs(GameObj.loot()) do loot_names[#loot_names+1] = obj.name end
            local pcs_list = {}
            for _, pc in ipairs(GameObj.pcs()) do
                pcs_list[#pcs_list+1] = { name=pc.name, status=pc.status }
            end
            if not hidden() and not invisible() then
                local status_parts = {}
                if dead()    then status_parts[#status_parts+1] = "dead" end
                if webbed()  then status_parts[#status_parts+1] = "webbed" end
                if stunned() then status_parts[#status_parts+1] = "stunned" end
                if kneeling()     then status_parts[#status_parts+1] = "kneeling"
                elseif sitting()  then status_parts[#status_parts+1] = "sitting"
                elseif not standing() then status_parts[#status_parts+1] = "lying down"
                end
                local st = #status_parts > 0 and table.concat(status_parts, " ") or nil
                pcs_list[#pcs_list+1] = { name=Char.name, status=st }
            end
            local npcs_list = {}
            for _, npc in ipairs(GameObj.npcs()) do
                npcs_list[#npcs_list+1] = { name=npc.name, status=npc.status }
            end
            local exits = {}
            for _, ex in ipairs(GameState.room_exits or {}) do exits[#exits+1] = ex end
            local room = {
                title       = GameState.room_name,
                description = GameState.room_description,
                exits       = table.concat(exits, ", "),
                loot        = loot_names,
                pcs         = pcs_list,
                npcs        = npcs_list,
            }
            send_data({ type=req_type, to=from }, room)
        else
            echo("lnet: rejecting request from " .. from .. " for location...")
            send_data({ type=req_type, to=from }, nil)
        end

    elseif req_type == "health" then
        if allow("health", from) then
            echo("lnet: sending health to " .. from .. "...")
            -- Build injuries table: {body_part -> {wound=N, scar=N}}
            local injuries = {}
            local parts = {
                "head","neck","chest","abdomen","back",
                "rightArm","leftArm","rightHand","leftHand",
                "rightLeg","leftLeg","rightFoot","leftFoot",
                "rightEye","leftEye","nsys",
            }
            for _, part in ipairs(parts) do
                local w = Wounds[part] or 0
                local s = Scars[part] or 0
                if w > 0 or s > 0 then
                    injuries[part] = { wound=w, scar=s }
                end
            end
            local health = {
                injuries    = injuries,
                health      = GameState.health,
                max_health  = GameState.max_health,
                spirit      = GameState.spirit,
                max_spirit  = GameState.max_spirit,
                stamina     = GameState.stamina,
                max_stamina = GameState.max_stamina,
            }
            send_data({ type=req_type, to=from }, health)
        else
            echo("lnet: rejecting request from " .. from .. " for health info...")
            send_data({ type=req_type, to=from }, nil)
        end

    elseif req_type == "bounty" then
        if allow("bounty", from) then
            send_data({ type=req_type, to=from }, Bounty.task)
        else
            echo("lnet: rejecting request from " .. from .. " for bounty info...")
            send_data({ type=req_type, to=from }, nil)
        end

    else
        echo("lnet: rejecting unknown request (" .. req_type .. ") from " .. from .. "...")
        send_data({ type=req_type, to=from }, nil)
    end
end

--------------------------------------------------------------------------------
-- Server data display (we received data in response to our request)
--------------------------------------------------------------------------------

local skill_display_order = {
    "Two Weapon Combat","Armor Use","Shield Use","Combat Maneuvers","Edged Weapons",
    "Blunt Weapons","Two-Handed Weapons","Ranged Weapons","Thrown Weapons","Polearm Weapons",
    "Brawling","Ambush","Multi Opponent Combat","Physical Fitness","Dodging","Arcane Symbols",
    "Magic Item Use","Spell Aiming","Harness Power","Elemental Mana Control","Mental Mana Control",
    "Spirit Mana Control","Elemental Lore - Air","Elemental Lore - Earth","Elemental Lore - Fire",
    "Elemental Lore - Water","Spiritual Lore - Blessings","Spiritual Lore - Religion",
    "Spiritual Lore - Summoning","Sorcerous Lore - Demonology","Sorcerous Lore - Necromancy",
    "Mental Lore - Divination","Mental Lore - Manipulation","Mental Lore - Telepathy",
    "Mental Lore - Transference","Mental Lore - Transformation","Survival","Disarming Traps",
    "Picking Locks","Stalking and Hiding","Perception","Climbing","Swimming","First Aid",
    "Trading","Pickpocketing",
    -- Spell circles (flagged as special below)
    "Major Elemental","Minor Elemental","Minor Mental","Major Spirit","Minor Spirit",
    "Wizard","Sorcerer","Ranger","Paladin","Empath","Cleric","Bard",
}

local spell_circles_set = {
    ["Major Elemental"]=true, ["Minor Elemental"]=true, ["Minor Mental"]=true,
    ["Major Spirit"]=true,    ["Minor Spirit"]=true,    ["Wizard"]=true,
    ["Sorcerer"]=true,        ["Ranger"]=true,           ["Paladin"]=true,
    ["Empath"]=true,          ["Cleric"]=true,           ["Bard"]=true,
}

local wound_message = {
    head     ={ "", "minor bruises about the head", "minor lacerations about the head and a possible mild concussion", "severe head trauma and bleeding from the ears" },
    neck     ={ "", "minor bruises on your neck", "moderate bleeding from your neck", "snapped bones and serious bleeding from the neck" },
    chest    ={ "", "minor cuts and bruises on your chest", "deep lacerations across your chest", "deep gashes and serious bleeding from your chest" },
    abdomen  ={ "", "minor cuts and bruises on your abdominal area", "deep lacerations across your abdominal area", "deep gashes and serious bleeding from your abdominal area" },
    back     ={ "", "minor cuts and bruises on your back", "deep lacerations across your back", "deep gashes and serious bleeding from your back" },
    rightEye ={ "", "a bruised right eye", "a swollen right eye", "a blinded right eye" },
    leftEye  ={ "", "a bruised left eye", "a swollen left eye", "a blinded left eye" },
    rightLeg ={ "", "some minor cuts and bruises on your right leg", "a fractured and bleeding right leg", "a completely severed right leg" },
    leftLeg  ={ "", "some minor cuts and bruises on your left leg", "a fractured and bleeding left leg", "a completely severed left leg" },
    rightArm ={ "", "some minor cuts and bruises on your right arm", "a fractured and bleeding right arm", "a completely severed right arm" },
    leftArm  ={ "", "some minor cuts and bruises on your left arm", "a fractured and bleeding left arm", "a completely severed left arm" },
    rightHand={ "", "some minor cuts and bruises on your right hand", "a fractured and bleeding right hand", "a completely severed right hand" },
    leftHand ={ "", "some minor cuts and bruises on your left hand", "a fractured and bleeding left hand", "a completely severed left hand" },
    nsys     ={ "", "a strange case of muscle twitching", "a case of sporadic convulsions", "a case of uncontrollable convulsions" },
    rightFoot={ "", "minor injury to your right foot", "serious injury to your right foot", "a completely severed right foot" },
    leftFoot ={ "", "minor injury to your left foot", "serious injury to your left foot", "a completely severed left foot" },
}

local scar_message = {
    head     ={ "", "a scar across your face", "several facial scars", "old mutilation wounds about your head" },
    neck     ={ "", "a scar across your neck", "some old neck wounds", "terrible scars from some serious neck injury" },
    chest    ={ "", "an old battle scar across your chest", "several painful-looking scars across your chest", "terrible, permanent mutilation of your chest muscles" },
    abdomen  ={ "", "an old battle scar across your abdominal area", "several painful-looking scars across your abdominal area", "terrible, permanent mutilation of your abdominal muscles" },
    back     ={ "", "an old battle scar across your back", "several painful-looking scars across your back", "terrible, permanent mutilation of your back muscles" },
    rightEye ={ "", "a black-and-blue right eye", "severe bruises and swelling around your right eye", "a missing right eye" },
    leftEye  ={ "", "a black-and-blue left eye", "severe bruises and swelling around your left eye", "a missing left eye" },
    rightLeg ={ "", "old battle scars on your right leg", "a mangled right leg", "a missing right leg" },
    leftLeg  ={ "", "old battle scars on your left leg", "a mangled left leg", "a missing left leg" },
    rightArm ={ "", "old battle scars on your right arm", "a mangled right arm", "a missing right arm" },
    leftArm  ={ "", "old battle scars on your left arm", "a mangled left arm", "a missing left arm" },
    rightHand={ "", "old battle scars on your right hand", "a mangled right hand", "a missing right hand" },
    leftHand ={ "", "old battle scars on your left hand", "a mangled left hand", "a missing left hand" },
    nsys     ={ "", "developed slurred speech", "constant muscle spasms", "a very difficult time with muscle control" },
    rightFoot={ "", "old scars on your right foot", "a mangled right foot", "a missing right foot" },
    leftFoot ={ "", "old scars on your left foot", "a mangled left foot", "a missing left foot" },
}

local function handle_server_data(data_type, from, data, attrs)
    -- Check if this data is for a waiting get_data() request
    if from and data_type then
        for _, waiter in ipairs(waiting) do
            if waiter.data == "waiting"
                and waiter.type == data_type
                and from:lower():find("^" .. waiter.name:lower()) then
                waiter.data = data
                return
            end
        end
    end

    if data_type == "connected" and from == "server" then
        -- Who list
        local by_game = {}
        local game_order = {}
        if type(data) == "table" then
            for _, name in ipairs(data) do
                local g, n = name:match("^(.+):(.+)$")
                if g and n then
                    if not by_game[g] then by_game[g]={}; game_order[#game_order+1]=g end
                    by_game[g][#by_game[g]+1] = n
                else
                    if not by_game["unknown"] then by_game["unknown"]={};game_order[#game_order+1]="unknown" end
                    by_game["unknown"][#by_game["unknown"]+1] = name
                end
            end
        end
        table.sort(game_order)
        local output = "\n"
        local who_columns = 5
        for _, game in ipairs(game_order) do
            local name_list = by_game[game]
            -- Sort: owners (^) first, then mods (*), then rest
            table.sort(name_list, function(a, b)
                local ra = a:match("%^$") and 2 or (a:match("%*$") and 1 or 0)
                local rb = b:match("%^$") and 2 or (b:match("%*$") and 1 or 0)
                if ra ~= rb then return ra > rb end
                return a < b
            end)
            output = output .. "\n" .. game .. " (" .. #name_list .. "):\n\n"
            -- Fill columns by popping from the end (matches Lich5 column-fill logic)
            local cols = {}; local widths = {}
            for i = 1, who_columns do cols[i]={}; widths[i]=0 end
            local remaining = {}
            for _, n in ipairs(name_list) do remaining[#remaining+1] = n end
            while #remaining > 0 do
                for i = 1, who_columns do
                    local n = table.remove(remaining)
                    if n then
                        cols[i][#cols[i]+1] = n
                        widths[i] = math.max(widths[i], #n)
                    end
                end
            end
            local row = 1
            while cols[1][row] do
                local row_parts = {}
                for c = 1, who_columns do
                    if cols[c][row] then
                        row_parts[#row_parts+1] = cols[c][row]
                            .. string.rep(" ", widths[c] - #cols[c][row] + 3)
                    end
                end
                output = output .. (table.concat(row_parts):match("^(.-)%s*$") or "") .. "\n"
                row = row + 1
            end
        end
        local channel = attrs and attrs.channel
        if channel then
            output = output .. "\nTotal tuned to " .. channel .. ": " .. (type(data)=="table" and #data or 0) .. "\n\n"
        else
            output = output .. "\nTotal connected: " .. (type(data)=="table" and #data or 0) .. "\n\n"
        end
        respond("\n" .. output)

    elseif data_type == "channels" and from == "server" then
        local total = attrs and tonumber(attrs.total) or 0
        local name_width = 0; local tuned_width = 0
        if type(data) == "table" then
            for _, ch in ipairs(data) do
                name_width  = math.max(name_width,  #tostring(ch.name  or ""))
                tuned_width = math.max(tuned_width, #tostring(ch.tuned or ""))
            end
        end
        local output = "\nAvailable channels:\n\n"
        if type(data) == "table" then
            for _, ch in ipairs(data) do
                local prefix = " "
                if ch.status == "default" then prefix = "+"
                elseif ch.status == "tuned" then prefix = "-"
                end
                local name_pad  = string.rep(" ", name_width  - #tostring(ch.name  or ""))
                local tuned_pad = string.rep(" ", tuned_width - #tostring(ch.tuned or ""))
                output = output .. prefix .. " " .. name_pad .. tostring(ch.name or "")
                    .. "   " .. tuned_pad .. tostring(ch.tuned or "0")
                    .. "   " .. tostring(ch.description or "") .. "\n"
            end
        end
        if type(data) == "table" and #data < total then
            output = output .. '\nuse ";channels full" to see ' .. (total - #data) .. ' more\n'
        end
        output = output .. "\n"
        respond(output)

    elseif data_type == "server stats" and from == "server" then
        if type(data) ~= "table" then return end
        local output = "\n"
        if data.uptime and tonumber(data.uptime) and tonumber(data.uptime) > 0 then
            output = output .. "No major accidents in the last " .. format_time(data.uptime) .. "\n"
        end
        if type(data["character connections"]) == "table" then
            for _, entry in ipairs(data["character connections"]) do
                local length, num = entry[1], entry[2]
                if length and num then
                    output = output .. num .. " characters have connected in the last " .. format_time(length) .. "\n"
                end
            end
        end
        if type(data["ip connections"]) == "table" then
            for _, entry in ipairs(data["ip connections"]) do
                local length, num = entry[1], entry[2]
                if length and num then
                    output = output .. "About " .. num .. " players have connected in the last " .. format_time(length) .. "\n"
                end
            end
        end
        output = output .. "\n"
        local function print_channel_section(channels, role)
            if type(channels) ~= "table" then return end
            for chan_name, chan_data in pairs(channels) do
                output = output .. chan_name .. " (" .. role .. ")\n"
                if type(chan_data.moderators) == "table" then
                    output = output .. "   moderators: "
                        .. (#chan_data.moderators > 0 and table.concat(chan_data.moderators, ", ") or "none") .. "\n"
                end
                if type(chan_data.invited) == "table" then
                    output = output .. "   invited: "
                        .. (#chan_data.invited > 0 and table.concat(chan_data.invited, ", ") or "none") .. "\n"
                end
                if type(chan_data.banned) == "table" then
                    if #chan_data.banned == 0 then
                        output = output .. "   banned: none\n"
                    else
                        output = output .. "   banned:\n"
                        for _, entry in ipairs(chan_data.banned) do
                            local ban_name = entry[1] or entry.name or "?"
                            local ban_time = entry[2] or entry.time
                            local ban_str  = ban_time and format_time(ban_time) or "indefinite"
                            output = output .. "      " .. tostring(ban_name):sub(1,16)
                                .. string.rep(" ", math.max(0, 16-#tostring(ban_name)))
                                .. " (" .. ban_str .. ")\n"
                        end
                    end
                end
                if type(chan_data.gagged) == "table" then
                    if #chan_data.gagged == 0 then
                        output = output .. "   gagged: none\n"
                    else
                        output = output .. "   gagged:\n"
                        for _, entry in ipairs(chan_data.gagged) do
                            local gag_name = entry[1] or entry.name or "?"
                            local gag_time = entry[2] or entry.time
                            local gag_str  = gag_time and format_time(gag_time) or "indefinite"
                            output = output .. "      " .. tostring(gag_name):sub(1,16)
                                .. string.rep(" ", math.max(0, 16-#tostring(gag_name)))
                                .. " (" .. gag_str .. ")\n"
                        end
                    end
                end
            end
        end
        print_channel_section(data.own_channels, "owner")
        print_channel_section(data.mod_channels, "moderator")
        respond(output)

    elseif data_type == "spells" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for spell information.")
        elseif data == false then
            echo("no such user")
        elseif type(data) == "table" then
            -- Sort spells by spell number, group by circle
            local spell_list = {}
            for num_str, timeleft in pairs(data) do
                spell_list[#spell_list+1] = { num=tonumber(num_str) or 0, timeleft=timeleft }
            end
            if #spell_list == 0 then
                echo(from .. " has no spells.")
                return
            end
            table.sort(spell_list, function(a,b) return a.num < b.num end)
            local output = "\n" .. from .. ":\n"
            local last_circle = nil
            for _, entry in ipairs(spell_list) do
                local sp = Spell[entry.num]
                local spell_name   = sp and sp.name   or ("Spell " .. entry.num)
                local circle_name  = sp and sp.circle or "Unknown"
                if last_circle ~= circle_name then
                    last_circle = circle_name
                    output = output .. "\n- " .. circle_name .. ":\n"
                end
                local time_str = minutes_to_time(entry.timeleft)
                output = output .. tostring(entry.num):rep(1):sub(1,4)
                    .. string.rep(" ", math.max(0, 4-#tostring(entry.num)))
                    .. ":  " .. spell_name
                    .. string.rep(" ", math.max(0, 22-#spell_name))
                    .. "- " .. time_str .. "\n"
            end
            output = output .. "\n"
            respond(output)
        end

    elseif data_type == "skills" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for skill information.")
        elseif data == false then
            echo("no such user")
        elseif type(data) == "table" then
            local output = "\n" .. from .. ":\n\n"
            output = output .. "  Skill Name                         | Current Current\n"
            output = output .. "                                     |   Bonus   Ranks\n"
            local shown = {}
            for _, skill_name in ipairs(skill_display_order) do
                local ranks = data[skill_name]
                if ranks then
                    shown[skill_name] = true
                    local pad = string.rep(".", math.max(0, 35-#skill_name))
                    if spell_circles_set[skill_name] then
                        output = output .. "\nSpell Lists\n"
                        output = output .. "  " .. skill_name .. pad
                            .. "|" .. string.rep(" ", math.max(0,16-#tostring(ranks)))
                            .. tostring(ranks) .. "\n"
                    else
                        local bonus = Skills.to_bonus and Skills.to_bonus(ranks) or 0
                        output = output .. "  " .. skill_name .. pad
                            .. "|" .. string.rep(" ", math.max(0,8-#tostring(bonus))) .. tostring(bonus)
                            .. string.rep(" ", math.max(0,8-#tostring(ranks))) .. tostring(ranks) .. "\n"
                    end
                end
            end
            -- Any extra skills not in the display order
            for skill_name, ranks in pairs(data) do
                if not shown[skill_name] then
                    local pad = string.rep(".", math.max(0, 35-#skill_name))
                    if spell_circles_set[skill_name] then
                        output = output .. "\nSpell Lists\n"
                        output = output .. "  " .. skill_name .. pad
                            .. "|" .. string.rep(" ", math.max(0,16-#tostring(ranks)))
                            .. tostring(ranks) .. "\n"
                    else
                        local bonus = Skills.to_bonus and Skills.to_bonus(ranks) or 0
                        output = output .. "  " .. skill_name .. pad
                            .. "|" .. string.rep(" ", math.max(0,8-#tostring(bonus))) .. tostring(bonus)
                            .. string.rep(" ", math.max(0,8-#tostring(ranks))) .. tostring(ranks) .. "\n"
                    end
                end
            end
            output = output .. "\n"
            respond(output)
        end

    elseif data_type == "info" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for stat information.")
        elseif data == false then
            echo("no such user")
        elseif type(data) == "table" then
            local function stat_str(t)
                if type(t) == "table" then
                    return string.format("%3s (%2s)", tostring(t[1] or "?"), tostring(t[2] or "?"))
                end
                return tostring(t)
            end
            local output = "\n"
            output = output .. "Name: " .. from
                .. " Race: "       .. tostring(data.Race or "?")
                .. "  Profession: " .. tostring(data.Profession or "?") .. "\n"
            output = output .. "Gender: " .. tostring(data.Gender or "?")
                .. "    Age: "   .. tostring(data.Age or "?")
                .. "    Expr: "  .. tostring(data.Expr or "?")
                .. "    Level:  " .. tostring(data.Level or "?") .. "\n"
            output = output .. "                  Normal (Bonus)  ...  Enhanced (Bonus)\n"
            local stats_order = {
                {"Strength","STR"}, {"Constitution","CON"}, {"Dexterity","DEX"},
                {"Agility","AGI"}, {"Discipline","DIS"}, {"Aura","AUR"},
                {"Logic","LOG"}, {"Intuition","INT"}, {"Wisdom","WIS"}, {"Influence","INF"},
            }
            for _, pair in ipairs(stats_order) do
                local full, abbr = pair[1], pair[2]
                local v = data[full]
                if type(v) == "table" then
                    local val = tostring(v[1] or "?")
                    local bon = tostring(v[2] or "?")
                    local label = string.format("%16s (%s):", full .. " (" .. abbr .. ")", abbr)
                    output = output .. string.format("  %s   %3s (%2s)    ...  %3s (%2s)\n",
                        full:sub(-16), val, bon, val, bon)
                end
            end
            output = output .. "Mana:  " .. tostring(data.Mana or "?") .. "\n\n"
            respond(output)
        end

    elseif data_type == "health" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for health information.")
        elseif data == false then
            echo("no such user")
        elseif type(data) == "table" then
            local output = "\n" .. from .. ":\n\n"
            local injuries = data.injuries
            local wound_parts = {}; local scar_parts = {}
            if type(injuries) == "table" then
                for part, inj in pairs(injuries) do
                    local w = tonumber(inj and inj.wound) or 0
                    local s = tonumber(inj and inj.scar)  or 0
                    local wm = wound_message[part]
                    local sm = scar_message[part]
                    if wm and w > 0 and wm[w+1] and wm[w+1] ~= "" then
                        wound_parts[#wound_parts+1] = wm[w+1]
                    end
                    if sm and s > 0 and sm[s+1] and sm[s+1] ~= "" then
                        scar_parts[#scar_parts+1] = sm[s+1]
                    end
                end
            end
            if #wound_parts == 0 and #scar_parts == 0 then
                output = output .. "You seem to be in one piece.\n"
            else
                if #wound_parts == 1 then
                    output = output .. "You have " .. wound_parts[1] .. ".\n"
                elseif #wound_parts > 1 then
                    output = output .. "You have "
                        .. table.concat(wound_parts, ", ", 1, #wound_parts-1)
                        .. ", and " .. wound_parts[#wound_parts] .. ".\n"
                end
                if #scar_parts == 1 then
                    output = output .. "You have " .. scar_parts[1] .. ".\n"
                elseif #scar_parts > 1 then
                    output = output .. "You have "
                        .. table.concat(scar_parts, ", ", 1, #scar_parts-1)
                        .. ", and " .. scar_parts[#scar_parts] .. ".\n"
                end
            end
            output = output .. "\n"
            output = output .. "    Maximum Health Points: "    .. tostring(data.max_health  or "?") .. "\n"
            output = output .. "  Remaining Health Points: "    .. tostring(data.health      or "?") .. "\n\n"
            output = output .. "    Maximum Spirit Points: "    .. tostring(data.max_spirit  or "?") .. "\n"
            output = output .. "  Remaining Spirit Points: "    .. tostring(data.spirit      or "?") .. "\n\n"
            output = output .. "    Maximum Stamina Points: "   .. tostring(data.max_stamina or "?") .. "\n"
            output = output .. "  Remaining Stamina Points: "   .. tostring(data.stamina     or "?") .. "\n\n"
            respond(output)
        end

    elseif data_type == "locate" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for location information.")
        elseif data == false then
            echo("no such user")
        elseif type(data) == "table" then
            local output = "\n" .. from .. ":\n\n"
            -- Try to find room in map
            local room_id_str = ""
            local room = Map.find_room and Map.find_room(tostring(data.title or ""))
            if room and room.id then room_id_str = " (" .. room.id .. ")" end
            local also_see = {}
            if type(data.npcs) == "table" then
                for _, npc in ipairs(data.npcs) do
                    local entry = tostring(npc.name or "?")
                    if npc.status and npc.status ~= "" then entry = entry .. " (" .. npc.status .. ")" end
                    also_see[#also_see+1] = entry
                end
            end
            if type(data.loot) == "table" then
                for _, item in ipairs(data.loot) do also_see[#also_see+1] = tostring(item) end
            end
            local also_here = {}
            if type(data.pcs) == "table" then
                for _, pc in ipairs(data.pcs) do
                    local entry = tostring(pc.name or "?")
                    if pc.status and pc.status ~= "" then entry = entry .. " (" .. pc.status .. ")" end
                    also_here[#also_here+1] = entry
                end
            end
            output = output .. tostring(data.title or "") .. room_id_str .. "\n"
            local desc = tostring(data.description or "")
            if #also_see > 0 then
                output = output .. desc .. "  You also see " .. table.concat(also_see, ", ") .. ".\n"
            else
                output = output .. desc .. "\n"
            end
            if #also_here > 0 then
                output = output .. "Also here: " .. table.concat(also_here, ", ") .. "\n"
            end
            output = output .. tostring(data.exits or "") .. "\n"
            respond(output)
        end

    elseif data_type == "bounty" and from then
        if is_ignored(from) then return end
        if data == nil then
            echo(from .. " declined your request for bounty information.")
        elseif data == false then
            echo("no such user")
        else
            respond("\n" .. from .. ":\n" .. tostring(data) .. "\n\n")
        end
    end
end

--------------------------------------------------------------------------------
-- get_data: synchronously wait for data response (used by lichnet_get_spells etc.)
--------------------------------------------------------------------------------

local function get_data(name, req_type)
    if type(name) ~= "string" or name == "" then return false end
    if type(req_type) ~= "string" or req_type == "" then return false end
    if not server_connected() then return false end
    name = name:sub(1,1):upper() .. name:sub(2):lower()
    local waiter = { type=req_type, name=name, data="waiting" }
    waiting[#waiting+1] = waiter
    send_request({ type=req_type, to=name })
    -- Wait up to 8 seconds
    for _ = 1, 80 do
        pause(0.1)
        if waiter.data ~= "waiting" then break end
    end
    for i, w in ipairs(waiting) do
        if w == waiter then table.remove(waiting, i); break end
    end
    return waiter.data ~= "waiting" and waiter.data or false
end

-- Public API for other scripts
function lichnet_get_spells(name)
    return get_data(name, "spells")
end

--------------------------------------------------------------------------------
-- Server XML event handler
--------------------------------------------------------------------------------

local function handle_server_xml(xml)
    last_recv = os.time()
    local tag, attrs, text = parse_xml_elem(xml)
    if not tag then return end

    if tag == "ping" then
        -- Respond with pong
        send_raw("<pong/>")

    elseif tag == "message" then
        local msg_type = attrs["type"]
        if msg_type == "greeting" then
            if options.greeting then respond(text or "") end
        elseif msg_type == "server" then
            local t = text or ""
            if t:match("incorrect password") or t:match("password required") then
                local out = "\n"
                out = out .. "If you have forgotten your password, visit https://lnet.lichproject.org to reset it.\n"
                out = out .. "To attempt to log in with a different password, type: ;lnet password=<password>\n\n"
                respond(out)
                Script.kill("lnet")
                return
            end
            echo_thought("[server]", t, "")
        elseif msg_type == "private" then
            local from = attrs["from"]
            if from ~= nil then
                last_priv = from
                echo_thought(from, text or "", "Private")
            end
        elseif msg_type == "privateto" then
            local to = attrs["to"]
            if to ~= nil and text ~= nil and #text < 512 then
                echo_thought(to, text, "PrivateTo")
            end
        elseif msg_type == "channel" then
            local from    = attrs["from"]
            local channel = attrs["channel"]
            if from ~= nil and channel ~= nil then
                echo_thought(from, text or "", channel)
            end
        end

    elseif tag == "request" then
        local req_type = attrs["type"]
        local from     = attrs["from"]
        if req_type ~= nil and from ~= nil then
            pcall(handle_data_request, req_type, from)
        end

    elseif tag == "notify" then
        local notify_type = attrs["type"]
        if notify_type == "server-restart" then
            server_restart = true
            if socket then pcall(function() socket:close() end) end
        end

    elseif tag == "data" then
        local data_type = attrs["type"]
        local from      = attrs["from"]
        if text ~= nil and data_type ~= nil then
            -- Decode: base64 → Marshal binary → Lua value
            local raw, berr = Crypto.base64_decode(text)
            if raw then
                local data, merr = Marshal.load(raw)
                if data ~= nil or merr == nil then
                    pcall(handle_server_data, data_type, from, data, attrs)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Connection
--------------------------------------------------------------------------------

local function lnet_connect()
    echo("lnet: connecting to " .. LNET_HOST .. ":" .. LNET_PORT .. "...")
    local sock, err = Socket.connect_tls(LNET_HOST, LNET_PORT, LNET_CA_CERT)
    if not sock then
        echo("lnet: connection failed: " .. tostring(err or "unknown error"))
        return false
    end
    socket = sock
    server_closed = false

    -- Send login
    local login_attrs = {
        name   = GameState.name,
        game   = GameState.game,
        client = CLIENT_VER,
        lich   = VERSION,
    }
    if secret[1] then login_attrs.password = secret[1] end
    send_raw(build_tag("login", login_attrs, nil))
    last_send = os.time()
    echo("lnet: connected")
    return true
end

--------------------------------------------------------------------------------
-- Background: connection + XML read loop (reconnects on disconnect)
--------------------------------------------------------------------------------

local conn_thread = Thread.new(function()
    while true do
        local last_connect_attempt = os.time()

        local ok = pcall(lnet_connect)
        if ok and server_connected() then
            -- Read loop: accumulate chunks, extract and handle XML elements
            local xml_buf = ""
            while not socket:closed() do
                local chunk, err = socket:read(4096)
                if not chunk then break end
                xml_buf = xml_buf .. chunk
                -- Process all complete elements from the buffer
                while true do
                    local elem, rest = extract_xml_elem(xml_buf)
                    if not elem then break end
                    xml_buf = rest
                    pcall(handle_server_xml, elem)
                end
            end
        end

        -- Clean up
        if socket then
            pcall(function() socket:close() end)
            socket = nil
        end
        server_closed = true

        if server_restart then
            server_restart = false
            echo("lnet: server is restarting; waiting 30 seconds to reconnect...")
            pause(30)
        else
            echo("lnet: connection lost")
            local elapsed   = os.time() - last_connect_attempt
            local wait_time = math.max(300 - elapsed, 1)
            if wait_time > 1 then
                echo("lnet: waiting " .. math.floor(wait_time) .. " seconds before reconnecting...")
            end
            pause(wait_time)
        end
    end
end)

--------------------------------------------------------------------------------
-- Command processing
--------------------------------------------------------------------------------

local function process_command(msg)
    msg = msg:match("^%s*(.-)%s*$")  -- trim

    -- Private message shortcuts:  ;Name:message  (handled by upstream hook, but also here)
    local to, text = msg:match("^chat%s+::(%S+)%s+(.*)")
    if not to then to, text = msg:match("^chat%s+to%s+(%S+)%s+(.*)") end
    if to then
        send_message({ type="private", to=to }, text)
        return
    end

    -- Chat to channel
    local chan
    chan, text = msg:match("^chat%s+:([^:%s]+)%s+(.*)")
    if not chan then chan, text = msg:match("^chat%s+on%s+(%S+)%s+(.*)") end
    if chan then
        send_message({ type="channel", channel=chan }, text)
        return
    end

    -- Chat to default channel
    text = msg:match("^chat%s+(.*)")
    if text then
        -- Strip leading ".to " or ".on " artifacts (Lich compat)
        text = text:gsub("^%.to%s+", ""):gsub("^%.on%s+", "")
        send_message({ type="channel" }, text)
        return
    end

    -- Reply
    text = msg:match("^reply%s+(.*)")
    if text then
        if last_priv then
            send_message({ type="private", to=last_priv }, text)
        else
            echo("No private message to reply to.")
        end
        return
    end

    -- Who
    if msg:match("^who$") then
        send_query({ type="connected" })
        return
    end
    local who_target = msg:match("^who%s+([A-Za-z:]+)$")
    if who_target then
        send_query({ type="connected", name=who_target })
        return
    end

    -- Stats
    if msg:match("^stats$") then
        send_query({ type="server stats" })
        return
    end

    -- Channels
    if msg:match("^channels?%s+full") or msg:match("^channels?%s+all") then
        send_query({ type="channels" })
        return
    end
    if msg:match("^channels?") then
        send_query({ type="channels", num="15" })
        return
    end

    -- Tune / Untune
    local tune_ch = msg:match("^tune%s+([A-Za-z]+)$")
    if tune_ch then tune_channel(tune_ch); return end
    local untune_ch = msg:match("^untune%s+([A-Za-z]+)$")
    if untune_ch then untune_channel(untune_ch); return end

    -- Data queries
    local qtype, qname = msg:match("^(spells|skills|info|locate|health|bounty)%s+([A-Za-z:]+)$")
    if qtype then
        if is_ignored(qname) then
            echo("There's no point in sending a request to someone you're ignoring.")
        else
            send_request({ type=qtype:lower(), to=qname })
        end
        return
    end

    -- Add alias
    local real, aliased = msg:match("^add%s?alias%s+(%S+)%s+(.+)$")
    if real then
        aliases[real] = aliased
        save_aliases()
        echo("chats from " .. real .. " will now appear as " .. aliased)
        if not real:match("^[A-Z][A-Za-z]+:[A-Z][a-z]+$") then
            echo("The name should be entered exactly as it appears in the thought window, e.g.:   ;lnet add alias GSIV:Jeril StrangerDanger")
            echo("If " .. real .. " is incorrect, remove it with:   ;lnet remove alias " .. aliased)
        end
        return
    end

    -- Remove alias
    local del_alias = msg:match("^[dr]e[lm]e?t?e?%s?alias%s+(.+)$")
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
            local max_k, max_v = 0, 0
            for k, v in pairs(aliases) do
                max_k = math.max(max_k, #k); max_v = math.max(max_v, #v)
            end
            local out = "\n"
            for k, v in pairs(aliases) do
                out = out .. "   " .. k .. string.rep(" ", max_k-#k)
                    .. " => " .. v .. string.rep(" ", max_v-#v) .. "\n"
            end
            out = out .. "\n"
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
            options.friends[#options.friends+1] = name
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
            options.enemies[#options.enemies+1] = name
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

    -- Allow (list)
    if msg:match("^allow$") then
        for _, action in ipairs({"locate","spells","skills","info","health","bounty"}) do
            local perm = options.permission[action] or "none"
            respond("You are allowing " .. (fix_perm_desc[perm] or "no one")
                .. " to " .. (fix_action_desc[action] or action) .. ".")
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
                and {"locate","spells","skills","info","health","bounty"}
                or {allow_action}
            for _, a in ipairs(actions) do
                options.permission[a] = group_key
                echo("You are now allowing " .. fix_perm_desc[group_key]
                    .. " to " .. (fix_action_desc[a] or a) .. ".")
            end
            save_options()
        else
            echo("Unknown group. Use: all, friends, enemies, none")
        end
        return
    end

    -- Ignore (list)
    if msg:match("^ignore$") then
        if #options.ignore == 0 then
            echo("You are not ignoring anyone.")
        else
            echo("You are ignoring the following people: " .. table.concat(options.ignore, ", "))
        end
        return
    end

    -- Ignore (add)
    game_part, name_part = msg:match("^ignore%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.ignore, name) then
            echo("You were already ignoring " .. name .. ".")
        else
            options.ignore[#options.ignore+1] = name
            save_options()
            echo("You are now ignoring " .. name .. ".")
        end
        return
    end

    -- Unignore
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

    -- Password (local + server notification if connected)
    local pw = msg:match("^password=(%S+)$")
    if pw then
        if pw == "nil" then
            -- Also notify server to clear password
            if server_connected() then
                send_data({ type="newpassword" }, nil)
            end
            secret[1] = nil
            echo("Password cleared.")
        else
            -- Notify server of new password
            if server_connected() then
                send_data({ type="newpassword" }, pw)
            end
            secret[1] = pw
            echo("Password saved locally.")
        end
        save_secret()
        return
    end

    -- Email (sends data to server, no local storage)
    local em = msg:match("^email=(%S+)$")
    if em then
        if server_connected() then
            send_data({ type="newemail" }, em)
            echo("Email address sent to server.")
        else
            echo("lnet: not connected.")
        end
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

    -- Eval (admin only — sends arbitrary data to server for server-side eval)
    local eval_expr = msg:match("^eval%s+(.+)$")
    if eval_expr then
        if server_connected() then
            send_data({ type="eval" }, eval_expr)
        else
            echo("lnet: not connected.")
        end
        return
    end

    -- Ban/gag/mod/banip on channel
    local action_type, target_name, target_channel =
        msg:match("^(ban|gag|mod|banip)%s+([%w:]+)%s+on%s+(%w+)$")
    if action_type then
        moderate({ action=action_type:lower(), name=target_name, channel=target_channel })
        return
    end

    -- Ban/gag/banip with time limit
    local a, n, c, dur, unit =
        msg:match("^(ban|gag|banip)%s+([%w:]+)%s+on%s+(%w+)%s+for%s+(%d+)%s*(%a+)$")
    if a then
        local mult = time_multiplier[unit:lower()] or 1
        moderate({ action=a:lower(), name=n, channel=c, length=tostring(tonumber(dur)*mult) })
        return
    end

    -- Unban/ungag/unmod
    action_type, target_name, target_channel =
        msg:match("^(unban|ungag|unmod)%s+([%w:]+)%s+on%s+(%w+)$")
    if action_type then
        moderate({ action=action_type:lower(), name=target_name, channel=target_channel })
        return
    end

    -- Create channel
    local hidden, private, ch_name, ch_desc =
        msg:match("^create%s+(hidden)?%s*(private)?%s*channel%s+(%w+)%s+(.+)$")
    if ch_name then
        admin({
            action      = "create channel",
            name        = ch_name,
            description = ch_desc:match("^%s*(.-)%s*$"),
            hidden      = hidden  and "yes" or "no",
            private     = private and "yes" or "no",
        })
        return
    end

    -- Create poll
    local poll_question = msg:match("%-%-question%s+(.-)%s*(?:%-%-|$)")
    if not poll_question then poll_question = msg:match("%-%-question%s+(.-)%s*%-%-") end
    if not poll_question then poll_question = msg:match("%-%-question%s+(.+)$") end
    if msg:match("^create%s+poll%s+") and poll_question then
        poll_question = poll_question:sub(1, 512):match("^%s*(.-)%s*$")
        local vote_time_secs = nil
        local vt_n, vt_unit = msg:match("%-%-vote%-time%s+(%d+)%s*(%a+)")
        if vt_n and vt_unit then
            local mult = time_multiplier[vt_unit:lower()] or 1
            vote_time_secs = tonumber(vt_n) * mult
        end
        local poll_attrs = { action="create poll", question=poll_question }
        local opt_idx = 1
        while true do
            local opt = msg:match("%-%-option%-" .. opt_idx .. "%s+(.-)%s*%-%-")
            if not opt then opt = msg:match("%-%-option%-" .. opt_idx .. "%s+(.+)$") end
            if not opt then break end
            poll_attrs["option " .. opt_idx] = opt:sub(1,64):match("^%s*(.-)%s*$")
            opt_idx = opt_idx + 1
        end
        if opt_idx > 2 then  -- need at least 2 options
            if vote_time_secs then poll_attrs.length = tostring(vote_time_secs) end
            if server_connected() then
                admin(poll_attrs)
            else
                echo("lnet: not connected.")
            end
        else
            echo("You're doing it wrong. Type ;lnet help")
        end
        return
    end

    -- Delete channel
    local del_ch = msg:match("^delete%s+channel%s+(%w+)$")
    if del_ch then
        admin({ action="delete channel", name=del_ch })
        return
    end

    -- Help
    if msg:match("^help$") or msg == "" then
        local sn = "lnet"
        local lc = ";"
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
        out = out .. lc .. "reply <message>                    reply to last private message\n"
        out = out .. "\n"
        out = out .. lc .. "locate <name>                      show someone's current room\n"
        out = out .. lc .. "spells <name>                      show someone's active spells and time remaining\n"
        out = out .. lc .. "skills <name>                      show someone's skills\n"
        out = out .. lc .. "info <name>                        show someone's stats\n"
        out = out .. lc .. "health <name>                      show someone's health, spirit, stamina and injuries\n"
        out = out .. lc .. "bounty <name>                      show someone's current adventurer's guild task\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " stats                         server statistics\n"
        out = out .. ";" .. sn .. " timestamps=<on/off>           turn on/off chat timestamps\n"
        out = out .. ";" .. sn .. " famwindow=<on/off>            turn on/off sending chats to familiar window\n"
        out = out .. ";" .. sn .. " greeting=<on/off>             turn on/off server greeting at logon\n"
        out = out .. ";" .. sn .. " preset=<lnet/thought/nil>     set highlight preset for your front end\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " friends                       list friends\n"
        out = out .. ";" .. sn .. " add friend <name>             add a name to your friend list\n"
        out = out .. ";" .. sn .. " del friend <name>             delete a name from your friend list\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " enemies                       list enemies\n"
        out = out .. ";" .. sn .. " add enemy <name>              add a name to your enemy list\n"
        out = out .. ";" .. sn .. " del enemy <name>              delete a name from your enemy list\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " allow                         list your current permissions\n"
        out = out .. ";" .. sn .. " allow <action> <group>        set permissions\n"
        out = out .. "      <action>: locate, spells, skills, info, health, bounty, all\n"
        out = out .. "      <group>: all, friends, enemies (non-enemies), none\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " aliases                       list aliases\n"
        out = out .. ";" .. sn .. " add alias <name> <new_name>   create alias\n"
        out = out .. ";" .. sn .. " del alias <new_name>          delete alias\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " ignore                        list ignored users\n"
        out = out .. ";" .. sn .. " ignore <name>                 ignore a person\n"
        out = out .. ";" .. sn .. " unignore <name>               stop ignoring a person\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " password=<password>           set your lnet password\n"
        out = out .. ";" .. sn .. " password=nil                  remove your lnet password\n"
        out = out .. ";" .. sn .. " email=<email>                 update your account email\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " create [hidden] [private] channel <name> <description>\n"
        out = out .. ";" .. sn .. " delete channel <name>\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " ban <char> on <channel> [for <n> <unit>]\n"
        out = out .. ";" .. sn .. " unban <char> on <channel>\n"
        out = out .. ";" .. sn .. " gag <char> on <channel> [for <n> <unit>]\n"
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
-- Upstream hook — intercept client commands
--------------------------------------------------------------------------------

local function on_upstream(line)
    -- ;, or ;chat ... or ;reply ... etc.
    local cmd, rest = line:match("^;(,)(.*)")
    if not cmd then
        -- ;lnet <subcommand>
        local lnet_sub = line:match("^;lnet%s*(.*)")
        if lnet_sub then
            process_command(lnet_sub)
            return nil
        end
        -- ;Name:message  private message shorthand
        local pm_name, pm_msg = line:match("^;([A-Za-z]+):(.*)")
        if pm_name then
            process_command("chat ::" .. pm_name .. " " .. pm_msg)
            return nil
        end
        -- ;chat, ;reply, ;who, ;channels, ;tune, ;untune, ;locate, ;spells, ;info, ;skills, ;health, ;bounty, ;stats
        for _, pat in ipairs({
            "^;(chat%s.*)", "^;(reply%s.*)", "^;(who.*)", "^;(channels?.*)",
            "^;(tune%s.*)", "^;(untune%s.*)", "^;(locate%s.*)", "^;(spells%s.*)",
            "^;(info%s.*)", "^;(skills%s.*)", "^;(health%s.*)", "^;(bounty%s.*)",
            "^;(stats)$",
        }) do
            local m = line:match(pat)
            if m then
                process_command(m)
                return nil
            end
        end
        return line
    end

    -- ;,<message>  → chat <message>
    process_command("chat " .. (rest or ""))
    return nil
end

UpstreamHook.add("lnet", on_upstream)
Script.at_exit(function()
    UpstreamHook.remove("lnet")
    if conn_thread then pcall(function() conn_thread:kill() end) end
    if socket then pcall(function() socket:close() end) end
end)

--------------------------------------------------------------------------------
-- Handle initial arguments
--------------------------------------------------------------------------------

local args = Script.vars[1] or ""
if args:match("^password=(%S+)$") then
    process_command("password=" .. args:match("^password=(%S+)$"))
elseif args:lower() == "help" then
    process_command("help")
end

--------------------------------------------------------------------------------
-- Main loop — keepalive (connection is managed by conn_thread)
--------------------------------------------------------------------------------

echo("LNet v" .. VERSION .. " loaded")

while true do
    pause(10)
    if server_connected() and (os.time() - last_send) > 49 then
        send_ping()
    end
end
