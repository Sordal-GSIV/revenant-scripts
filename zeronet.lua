--- @revenant-script
--- name: zeronet
--- version: 0.0.10
--- author: Ondreian
--- game: any
--- tags: core, chat
--- description: Extended LNet chat client with custom callbacks (0net port)
---
--- Original Lich5 author: Ondreian
--- Ported to Revenant Lua from 0net.lic v0.0.10
---
--- Extended LNet client: backwards-compatible with ;lnet, adds LNet.add_callback()
--- for custom request types.  Auto-loads lnet_callbacks if present.
---
--- @lic-certified: complete 2026-03-19

local VERSION = "0.0.10"
local LNET_CLIENT_VERSION = "1.6"

Script.unique()
Script.hidden()

-- CA certificate for lnet.lichproject.org (from 0net.lic v0.0.10)
local CA_CERT_PEM = [[
-----BEGIN CERTIFICATE-----
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
LZDXmY9kWt+7pGQ2SKOT79gNcnOSc3SGYWkX48J6C1hihhjD3AfD0hb1mgvlJuij
zNnZ7vczOF8AcvBeu8ww5eIrkN6TTshjICg71/deVo9HvjhiCGK0XvL+WL6EQwLe
6/nVVFrPfd0sRZZ5OTJR5nM1kA71oChUw9mHCyrAc3zYyW37k+p8ADRFfON8th8M
1Blel1SpgqlQ22WpYoHbUCSjGt6JKC/HrSHdKBezTuRahOSfqwncAE77Dz4FJaQ5
WD2mk3SZbB2ytAHUDEy3xr697EI=
-----END CERTIFICATE-----]]

local LNET_HOST = "lnet.lichproject.org"
local LNET_PORT = 7155
-- The server cert may have CN = 'lichproject.org' or 'LichNet'.
-- We try each; native_tls checks the cert CN against this value.
local TLS_HOSTNAMES = { "lnet.lichproject.org", "lichproject.org", "LichNet" }

--------------------------------------------------------------------------------
-- Callback registry
--------------------------------------------------------------------------------
local callbacks = {}  -- { [request_type] = { [name] = handler } }

local function add_callback(name, request_type, handler)
    if type(name) == "string" and name:lower():match("^lnet_")
       and Script.current_name() ~= "zeronet" then
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

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local sock          = nil          -- SocketHandle or nil
local last_send     = os.time()
local last_recv     = os.time()
local server_restart = false
local waiting       = {}           -- { {type, name, data} }

local options = CharSettings.get("zeronet_options") or {}
if options.timestamps  == nil then options.timestamps  = false end
if options.fam_window  == nil then options.fam_window  = false end
if options.greeting    == nil then options.greeting    = true  end
if not options.friends     then options.friends    = {}  end
if not options.enemies     then options.enemies    = {}  end
if not options.permission  then options.permission = {}  end
if not options.ignore      then options.ignore     = {}  end

local stored_secret = CharSettings.get("zeronet_secret") or {}
local secret = stored_secret

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function save_options() CharSettings.set("zeronet_options", options) end
local function save_secret()  CharSettings.set("zeronet_secret", secret)   end

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
    if perm == "all"     then return true
    elseif perm == "friends"  then return is_friend(name)
    elseif perm == "enemies"  then return not is_enemy(name)
    else return false
    end
end

local function server_connected()
    return sock ~= nil and not sock:closed()
end

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
    if s > 0 and d < 1 and h < 1 then
        parts[#parts+1] = s .. " second" .. (s ~= 1 and "s" or "")
    end
    local result = table.concat(parts, ", ")
    if result == "1 day" then result = "24 hours" end
    return result
end

local time_multiplier = {
    s=1, second=1, seconds=1,
    m=60, minute=60, minutes=60,
    h=3600, hour=3600, hours=3600,
    d=86400, day=86400, days=86400,
    y=31536000, year=31536000, years=31536000,
}

--------------------------------------------------------------------------------
-- XML builder
--------------------------------------------------------------------------------

local function escape_xml(s)
    s = tostring(s)
    return s:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;")
end

local function build_tag(name, attrs, text)
    local parts = {"<", name}
    for k, v in pairs(attrs) do
        if v ~= nil then
            parts[#parts+1] = ' ' .. k .. '="' .. escape_xml(v) .. '"'
        end
    end
    if text ~= nil then
        parts[#parts+1] = ">" .. escape_xml(tostring(text)) .. "</" .. name .. ">"
    else
        parts[#parts+1] = "/>"
    end
    return table.concat(parts)
end

--------------------------------------------------------------------------------
-- XML line parser (handles single-line LNet XML elements)
--------------------------------------------------------------------------------

local function parse_xml_line(line)
    line = line:match("^%s*(.-)%s*$")
    if line == "" or line:sub(1,1) ~= "<" then return nil end

    -- Tag name
    local tagname = line:match("^</?([%w%-:]+)")
    if not tagname then return nil end

    -- Attributes
    local attrs = {}
    for k, v in line:gmatch(' ([%w%-:]+)="([^"]*)"') do
        attrs[k] = v
    end

    -- Self-closing?
    local self_closing = line:match("/>%s*$") ~= nil

    -- Text content
    local text = nil
    if not self_closing then
        text = line:match(">(.-)%s*</" .. tagname .. ">")
    end

    return { tag = tagname, attrs = attrs, text = text, self_closing = self_closing }
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function echo_thought(from, message, channel)
    local ch = ""
    if from ~= "[server]" then ch = "[" .. channel .. "]-" end
    local timestamp = ""
    if options.timestamps then timestamp = "  (" .. os.date("%X") .. ")" end
    local line = ch .. from .. ': "' .. message .. '"' .. timestamp
    if not is_ignored(from) then
        respond(line)
    end
end

-- Format 'who' response (connected users grouped by game)
local function format_who(data, channel)
    if type(data) ~= "table" then return "" end
    local by_game = {}
    for _, entry in ipairs(data) do
        local game, char = entry:match("^(.+):(.+)$")
        if not game then game = "unknown"; char = entry end
        if not by_game[game] then by_game[game] = {} end
        table.insert(by_game[game], char)
    end
    local out = "\n"
    for game, names in pairs(by_game) do
        table.sort(names)
        out = out .. game .. " (" .. #names .. "):\n\n"
        local who_cols = 5
        local rows = math.ceil(#names / who_cols)
        local longest = {}
        for c = 1, who_cols do longest[c] = 0 end
        for i, n in ipairs(names) do
            local col = ((i-1) % who_cols) + 1
            if #n > longest[col] then longest[col] = #n end
        end
        for r = 1, rows do
            local row_str = ""
            for c = 1, who_cols do
                local idx = (r-1)*who_cols + c
                local n = names[idx]
                if n then
                    row_str = row_str .. n .. string.rep(" ", longest[c] - #n + 3)
                end
            end
            out = out .. row_str:match("^%s*(.-)%s*$") .. "\n"
        end
        out = out .. "\n"
    end
    if channel then
        out = out .. "Total tuned to " .. channel .. ": " .. #data .. "\n\n"
    else
        out = out .. "Total connected: " .. #data .. "\n\n"
    end
    return out
end

-- Format channels list
local function format_channels(data, total)
    if type(data) ~= "table" then return "" end
    local name_w, tuned_w = 0, 0
    for _, ch in ipairs(data) do
        if #(ch.name or "") > name_w then name_w = #ch.name end
        if #tostring(ch.tuned or 0) > tuned_w then tuned_w = #tostring(ch.tuned) end
    end
    local out = "\nAvailable channels:\n\n"
    for _, ch in ipairs(data) do
        local prefix = " "
        if ch.status == "default" then prefix = "+"
        elseif ch.status == "tuned" then prefix = "-" end
        local name_pad = string.rep(" ", name_w - #(ch.name or ""))
        local tuned_pad = string.rep(" ", tuned_w - #tostring(ch.tuned or 0))
        out = out .. prefix .. " " .. name_pad .. (ch.name or "")
               .. "   " .. tuned_pad .. tostring(ch.tuned or 0)
               .. "   " .. (ch.description or "") .. "\n"
    end
    if total and total > #data then
        out = out .. "\nuse \";channels full\" to see " .. (total - #data) .. " more\n"
    end
    out = out .. "\n"
    return out
end

-- Format server stats
local function format_stats(data)
    if type(data) ~= "table" then return "" end
    local out = "\n"
    if data.uptime and tonumber(data.uptime) and tonumber(data.uptime) > 0 then
        out = out .. "No major accidents in the last " .. format_time(tonumber(data.uptime)) .. "\n"
    end
    if data["character connections"] then
        for length, num in pairs(data["character connections"]) do
            out = out .. num .. " characters have connected in the last " .. format_time(tonumber(length)) .. "\n"
        end
    end
    if data["ip connections"] then
        for length, num in pairs(data["ip connections"]) do
            out = out .. "About " .. num .. " players have connected in the last " .. format_time(tonumber(length)) .. "\n"
        end
    end
    out = out .. "\n"
    if data.own_channels then
        for ch_name, ch_data in pairs(data.own_channels) do
            out = out .. ch_name .. " (owner)\n"
            local mods = ch_data.moderators or {}
            if #mods == 0 then out = out .. "   moderators: none\n"
            else out = out .. "   moderators: " .. table.concat(mods, ", ") .. "\n" end
            local inv = ch_data.invited
            if inv and #inv > 0 then out = out .. "   invited: " .. table.concat(inv, ", ") .. "\n"
            elseif inv then out = out .. "   invited: none\n" end
            local banned = ch_data.banned
            if banned and next(banned) then
                out = out .. "   banned:\n"
                for bname, btime in pairs(banned) do
                    local bt = btime and format_time(tonumber(btime)) or "indefinite"
                    out = out .. "      " .. string.format("%-16s", bname) .. " (" .. bt .. ")\n"
                end
            else out = out .. "   banned: none\n" end
            local gagged = ch_data.gagged
            if gagged and next(gagged) then
                out = out .. "   gagged:\n"
                for gname, gtime in pairs(gagged) do
                    local gt = gtime and format_time(tonumber(gtime)) or "indefinite"
                    out = out .. "      " .. string.format("%-16s", gname) .. " (" .. gt .. ")\n"
                end
            else out = out .. "   gagged: none\n" end
        end
    end
    if data.mod_channels then
        for ch_name, ch_data in pairs(data.mod_channels) do
            out = out .. ch_name .. " (moderator)\n"
            local inv = ch_data.invited
            if inv and #inv > 0 then out = out .. "   invited: " .. table.concat(inv, ", ") .. "\n"
            elseif inv then out = out .. "   invited: none\n" end
            local banned = ch_data.banned
            if banned and next(banned) then
                out = out .. "   banned:\n"
                for bname, btime in pairs(banned) do
                    local bt = btime and format_time(tonumber(btime)) or "indefinite"
                    out = out .. "      " .. string.format("%-16s", bname) .. " (" .. bt .. ")\n"
                end
            else out = out .. "   banned: none\n" end
            local gagged = ch_data.gagged
            if gagged and next(gagged) then
                out = out .. "   gagged:\n"
                for gname, gtime in pairs(gagged) do
                    local gt = gtime and format_time(tonumber(gtime)) or "indefinite"
                    out = out .. "      " .. string.format("%-16s", gname) .. " (" .. gt .. ")\n"
                end
            else out = out .. "   gagged: none\n" end
        end
    end
    return out
end

-- Format spell list response
local function format_spells(name, data)
    if type(data) ~= "table" then return "" end
    local out = "\n" .. name .. ":\n"
    -- Sort by spell number
    local entries = {}
    for num_str, timeleft in pairs(data) do
        table.insert(entries, {num = tonumber(num_str) or 0, tl = timeleft})
    end
    table.sort(entries, function(a,b) return a.num < b.num end)
    for _, e in ipairs(entries) do
        local mins = math.floor(e.tl / 60)
        local secs = e.tl % 60
        out = out .. string.format("%4d:  %-22s- %d:%02d\n", e.num, "Spell " .. e.num, mins, secs)
    end
    out = out .. "\n"
    return out
end

-- Format skills response (GS4 format)
local SKILL_ORDER = {
    "Two Weapon Combat","Armor Use","Shield Use","Combat Maneuvers",
    "Edged Weapons","Blunt Weapons","Two-Handed Weapons","Ranged Weapons",
    "Thrown Weapons","Polearm Weapons","Brawling","Ambush",
    "Multi Opponent Combat","Physical Fitness","Dodging","Arcane Symbols",
    "Magic Item Use","Spell Aiming","Harness Power","Elemental Mana Control",
    "Mental Mana Control","Spirit Mana Control","Elemental Lore - Air",
    "Elemental Lore - Earth","Elemental Lore - Fire","Elemental Lore - Water",
    "Spiritual Lore - Blessings","Spiritual Lore - Religion",
    "Spiritual Lore - Summoning","Sorcerous Lore - Demonology",
    "Sorcerous Lore - Necromancy","Mental Lore - Divination",
    "Mental Lore - Manipulation","Mental Lore - Telepathy",
    "Mental Lore - Transference","Mental Lore - Transformation",
    "Survival","Disarming Traps","Picking Locks","Stalking and Hiding",
    "Perception","Climbing","Swimming","First Aid","Trading","Pickpocketing",
    "Major Elemental","Minor Elemental","Minor Mental","Major Spirit",
    "Minor Spirit","Wizard","Sorcerer","Ranger","Paladin","Empath","Cleric","Bard",
}
local SPELL_SKILLS = {
    ["Major Elemental"]=true,["Minor Elemental"]=true,["Minor Mental"]=true,
    ["Major Spirit"]=true,["Minor Spirit"]=true,["Wizard"]=true,
    ["Sorcerer"]=true,["Ranger"]=true,["Paladin"]=true,
    ["Empath"]=true,["Cleric"]=true,["Bard"]=true,
}

local function skill_bonus(ranks)
    local bonus = 0
    while ranks > 0 do
        if ranks > 40 then bonus = bonus + (ranks - 40); ranks = 40
        elseif ranks > 30 then bonus = bonus + (ranks - 30)*2; ranks = 30
        elseif ranks > 20 then bonus = bonus + (ranks - 20)*3; ranks = 20
        elseif ranks > 10 then bonus = bonus + (ranks - 10)*4; ranks = 10
        else bonus = bonus + ranks*5; ranks = 0 end
    end
    return bonus
end

local function format_skills(name, data)
    if type(data) ~= "table" then return "" end
    local out = "\n" .. name .. ":\n\n"
    out = out .. "  Skill Name                         | Current Current\n"
    out = out .. "                                     |   Bonus   Ranks\n"
    local seen = {}
    for _, skill in ipairs(SKILL_ORDER) do
        local ranks = data[skill]
        if ranks then
            seen[skill] = true
            if SPELL_SKILLS[skill] then
                out = out .. "\nSpell Lists\n"
                out = out .. string.format("  %-35s|%16d\n", skill:sub(1,35) .. string.rep(".", 35-#skill:sub(1,35)), ranks)
            else
                out = out .. string.format("  %-35s|%8d%8d\n",
                    (skill .. string.rep(".", 35)):sub(1,35),
                    skill_bonus(ranks), ranks)
            end
        end
    end
    -- Any remaining skills not in SKILL_ORDER
    for sname, ranks in pairs(data) do
        if not seen[sname] then
            if SPELL_SKILLS[sname] then
                out = out .. "\nSpell Lists\n"
                out = out .. string.format("  %-35s|%16d\n",
                    (sname .. string.rep(".", 35)):sub(1,35), ranks)
            else
                out = out .. string.format("  %-35s|%8d%8d\n",
                    (sname .. string.rep(".", 35)):sub(1,35),
                    skill_bonus(ranks), ranks)
            end
        end
    end
    out = out .. "\n"
    return out
end

-- Format info (stats) response
local function format_info(name, data)
    if type(data) ~= "table" then return "" end
    local function stat(d, key)
        local v = d[key]
        if type(v) == "table" then return v[1] or 0, v[2] or 0
        else return v or 0, 0 end
    end
    local out = "\n"
    out = out .. string.format("Name: %-20s Race: %s  Profession: %s\n",
        name, data.Race or "", data.Profession or "")
    out = out .. string.format("Gender: %-8s Age: %-6s Expr: %-12s Level: %s\n",
        data.Gender or "", tostring(data.Age or ""), tostring(data.Expr or ""),
        tostring(data.Level or ""))
    out = out .. "                  Normal (Bonus)  ...  Enhanced (Bonus)\n"
    local stats = {
        {"Strength","STR"},{"Constitution","CON"},{"Dexterity","DEX"},
        {"Agility","AGI"},{"Discipline","DIS"},{"Aura","AUR"},
        {"Logic","LOG"},{"Intuition","INT"},{"Wisdom","WIS"},{"Influence","INF"},
    }
    for _, pair in ipairs(stats) do
        local full, abbr = pair[1], pair[2]
        local v1, v2 = stat(data, full)
        out = out .. string.format("%17s (%s): %4d (%3d)    ...  %4d (%3d)\n",
            full, abbr, v1, v2, v1, v2)
    end
    out = out .. string.format("Mana:  %s\n\n", tostring(data.Mana or ""))
    return out
end

-- Format health response
local WOUND_MSG = {
    head      = {"","minor bruises about the head","minor lacerations about the head and a possible mild concussion","severe head trauma and bleeding from the ears"},
    neck      = {"","minor bruises on your neck","moderate bleeding from your neck","snapped bones and serious bleeding from the neck"},
    chest     = {"","minor cuts and bruises on your chest","deep lacerations across your chest","deep gashes and serious bleeding from your chest"},
    abdomen   = {"","minor cuts and bruises on your abdominal area","deep lacerations across your abdominal area","deep gashes and serious bleeding from your abdominal area"},
    back      = {"","minor cuts and bruises on your back","deep lacerations across your back","deep gashes and serious bleeding from your back"},
    rightEye  = {"","a bruised right eye","a swollen right eye","a blinded right eye"},
    leftEye   = {"","a bruised left eye","a swollen left eye","a blinded left eye"},
    rightLeg  = {"","some minor cuts and bruises on your right leg","a fractured and bleeding right leg","a completely severed right leg"},
    leftLeg   = {"","some minor cuts and bruises on your left leg","a fractured and bleeding left leg","a completely severed left leg"},
    rightArm  = {"","some minor cuts and bruises on your right arm","a fractured and bleeding right arm","a completely severed right arm"},
    leftArm   = {"","some minor cuts and bruises on your left arm","a fractured and bleeding left arm","a completely severed left arm"},
    rightHand = {"","some minor cuts and bruises on your right hand","a fractured and bleeding right hand","a completely severed right hand"},
    leftHand  = {"","some minor cuts and bruises on your left hand","a fractured and bleeding left hand","a completely severed left hand"},
    nsys      = {"","a strange case of muscle twitching","a case of sporadic convulsions","a case of uncontrollable convulsions"},
    rightFoot = {"","","",""},
    leftFoot  = {"","","",""},
}
local SCAR_MSG = {
    head      = {"","a scar across your face","several facial scars","old mutilation wounds about your head"},
    neck      = {"","a scar across your neck","some old neck wounds","terrible scars from some serious neck injury"},
    chest     = {"","an old battle scar across your chest","several painful-looking scars across your chest","terrible, permanent mutilation of your chest muscles"},
    abdomen   = {"","an old battle scar across your abdominal area","several painful-looking scars across your abdominal area","terrible, permanent mutilation of your abdominal muscles"},
    back      = {"","an old battle scar across your back","several painful-looking scars across your back","terrible, permanent mutilation of your back muscles"},
    rightEye  = {"","a black-and-blue right eye","severe bruises and swelling around your right eye","a missing right eye"},
    leftEye   = {"","a black-and-blue left eye","severe bruises and swelling around your left eye","a missing left eye"},
    rightLeg  = {"","old battle scars on your right leg","a mangled right leg","a missing right leg"},
    leftLeg   = {"","old battle scars on your left leg","a mangled left leg","a missing left leg"},
    rightArm  = {"","old battle scars on your right arm","a mangled right arm","a missing right arm"},
    leftArm   = {"","old battle scars on your left arm","a mangled left arm","a missing left arm"},
    rightHand = {"","old battle scars on your right hand","a mangled right hand","a missing right hand"},
    leftHand  = {"","old battle scars on your left hand","a mangled left hand","a missing left hand"},
    nsys      = {"","developed slurred speech","constant muscle spasms","a very difficult time with muscle control"},
    rightFoot = {"","","",""},
    leftFoot  = {"","","",""},
}

local function format_health(name, data)
    if type(data) ~= "table" then return "" end
    local out = "\n" .. name .. ":\n\n"
    local inj = data.injuries or {}
    local wound_parts = {}
    local scar_parts  = {}
    for part, state in pairs(inj) do
        local ws = type(state) == "table" and (tonumber(state.wound) or 0) or 0
        local sc = type(state) == "table" and (tonumber(state.scar)  or 0) or 0
        if ws > 0 and WOUND_MSG[part] and WOUND_MSG[part][ws+1] ~= "" then
            wound_parts[#wound_parts+1] = WOUND_MSG[part][ws+1]
        end
        if sc > 0 and SCAR_MSG[part] and SCAR_MSG[part][sc+1] ~= "" then
            scar_parts[#scar_parts+1] = SCAR_MSG[part][sc+1]
        end
    end
    if #wound_parts == 0 and #scar_parts == 0 then
        out = out .. "You seem to be in one piece.\n"
    else
        if #wound_parts == 1 then
            out = out .. "You have " .. wound_parts[1] .. ".\n"
        elseif #wound_parts > 1 then
            out = out .. "You have " .. table.concat(wound_parts, ", ", 1, #wound_parts-1)
                      .. ", and " .. wound_parts[#wound_parts] .. ".\n"
        end
        if #scar_parts == 1 then
            out = out .. "You have " .. scar_parts[1] .. ".\n"
        elseif #scar_parts > 1 then
            out = out .. "You have " .. table.concat(scar_parts, ", ", 1, #scar_parts-1)
                      .. ", and " .. scar_parts[#scar_parts] .. ".\n"
        end
    end
    out = out .. "\n"
    out = out .. string.format("    Maximum Health Points: %s\n",  tostring(data.max_health or 0))
    out = out .. string.format("  Remaining Health Points: %s\n",  tostring(data.health or 0))
    out = out .. "\n"
    out = out .. string.format("    Maximum Spirit Points: %s\n",  tostring(data.max_spirit or 0))
    out = out .. string.format("  Remaining Spirit Points: %s\n",  tostring(data.spirit or 0))
    out = out .. "\n"
    out = out .. string.format("   Maximum Stamina Points: %s\n",  tostring(data.max_stamina or 0))
    out = out .. string.format(" Remaining Stamina Points: %s\n",  tostring(data.stamina or 0))
    out = out .. "\n"
    return out
end

-- Format locate response
local function format_locate(name, data)
    if type(data) ~= "table" then return "" end
    local out = "\n" .. name .. ":\n\n"
    local also_see = {}
    if data.npcs then
        for _, npc in ipairs(data.npcs) do
            also_see[#also_see+1] = npc.status and (npc.name .. " (" .. npc.status .. ")") or npc.name
        end
    end
    if data.loot then
        for _, loot in ipairs(data.loot) do also_see[#also_see+1] = loot end
    end
    local also_here = {}
    if data.pcs then
        for _, pc in ipairs(data.pcs) do
            also_here[#also_here+1] = pc.status and (pc.name .. " (" .. pc.status .. ")") or pc.name
        end
    end
    local room_id_str = data.id and (" (" .. tostring(data.id) .. ")") or ""
    out = out .. (data.title or "") .. room_id_str .. "\n"
    if #also_see > 0 then
        out = out .. (data.description or "") .. "  You also see " .. table.concat(also_see, ", ") .. ".\n"
    else
        out = out .. (data.description or "") .. "\n"
    end
    if #also_here > 0 then
        out = out .. "Also here: " .. table.concat(also_here, ", ") .. "\n"
    end
    out = out .. (data.exits or "") .. "\n"
    return out
end

-- Format bounty response
local function format_bounty(name, data)
    if type(data) ~= "string" then return "" end
    return "\n" .. name .. ":\n" .. data .. "\n\n"
end

--------------------------------------------------------------------------------
-- Network send helpers (synchronous write queue)
--------------------------------------------------------------------------------

local function send_xml(xml_str)
    if not server_connected() then return false end
    sock:writeln(xml_str)
    last_send = os.time()
    return true
end

local function send_ping()
    if not server_connected() then return false end
    -- Ruby sends empty REXML::Document which serializes to empty string + newline
    sock:writeln("")
    last_send = os.time()
    return true
end

local function send_message(attrs, message)
    return send_xml(build_tag("message", attrs, message))
end

local function safe_send(attrs, message)
    if (os.time() - last_send) > 3 then
        return send_message(attrs, message)
    end
    return false
end

local function send_query(attrs)
    return send_xml(build_tag("query", attrs))
end

local function send_request(attrs)
    return send_xml(build_tag("request", attrs))
end

local function send_data_raw(attrs, data)
    if not server_connected() then return false end
    if data == nil then
        return send_xml(build_tag("data", attrs))
    end
    -- Encode with Marshal.dump -> base64
    local bytes, err = Marshal.dump(data)
    if not bytes then
        echo("zeronet: marshal error: " .. tostring(err))
        return send_xml(build_tag("data", attrs))
    end
    local b64 = Crypto.base64_encode(bytes)
    -- Include base64 as text content
    local parts = {"<data"}
    for k, v in pairs(attrs) do
        parts[#parts+1] = ' ' .. k .. '="' .. escape_xml(v) .. '"'
    end
    parts[#parts+1] = ">"
    parts[#parts+1] = b64
    parts[#parts+1] = "</data>"
    return send_xml(table.concat(parts))
end

local function tune_channel(channel)
    return send_xml(build_tag("tune", {channel = channel}))
end

local function untune_channel(channel)
    return send_xml(build_tag("untune", {channel = channel}))
end

local function moderate(attrs)
    return send_xml(build_tag("moderate", attrs))
end

local function admin(attrs)
    return send_xml(build_tag("admin", attrs))
end

-- Decode base64+marshal data element text
local function decode_data_text(text)
    if not text or text == "" then return nil end
    local bytes, err = Crypto.base64_decode(text)
    if not bytes then
        echo("zeronet: base64 decode error: " .. tostring(err))
        return nil
    end
    local val, merr = Marshal.load(bytes)
    if merr then
        echo("zeronet: marshal decode error: " .. tostring(merr))
        return nil
    end
    return val
end

--------------------------------------------------------------------------------
-- Callback dispatch
--------------------------------------------------------------------------------

local function dispatch_callback(request_type, attrs)
    local from = attrs.from
    local type_base = request_type:match("^([^:]+)") or request_type

    if not callbacks[type_base] then
        echo("rejecting unknown request (" .. type_base .. ") from " .. from .. "...")
        send_data_raw({ type = type_base, to = from }, nil)
        return
    end

    if is_ignored(from) then
        send_data_raw({ type = type_base, to = from }, nil)
        return
    end

    local perm = options.permission[type_base]
    if perm and not allow_action(type_base, from) then
        echo("rejecting request from " .. from .. " for " .. type_base .. " info...")
        send_data_raw({ type = type_base, to = from }, nil)
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
            send_data_raw({ type = type_base, to = from }, result)
        else
            echo("error in callback for " .. type_base .. ": " .. tostring(result))
            send_data_raw({ type = type_base, to = from }, nil)
        end
    else
        send_data_raw({ type = type_base, to = from }, nil)
    end
end

--------------------------------------------------------------------------------
-- Process incoming XML line from server
--------------------------------------------------------------------------------

local function process_incoming_line(line)
    local parsed = parse_xml_line(line)
    if not parsed then return end
    local tag, attrs, text = parsed.tag, parsed.attrs, parsed.text

    last_recv = os.time()

    if tag == "ping" then
        -- Respond with pong
        send_xml("<pong/>")

    elseif tag == "message" then
        local mtype = attrs.type
        if mtype == "greeting" then
            if options.greeting and text then respond(text) end
        elseif mtype == "server" then
            if text and text:match("incorrect password") or
               text and text:match("password required") then
                respond("\n--- Lich: If you have forgotten your password, visit https://lnet.lichproject.org to reset it.")
                respond("--- Lich: To use a different password: ;zeronet password=<password>\n")
                Script.kill("zeronet")
                return
            end
            if text then echo_thought("[server]", text, "") end
        elseif mtype == "private" and attrs.from then
            if text then echo_thought(attrs.from, text, "Private") end
        elseif mtype == "privateto" and attrs.to then
            if text then echo_thought(attrs.to, text, "PrivateTo") end
        elseif mtype == "channel" and attrs.from and attrs.channel then
            if text then echo_thought(attrs.from, text, attrs.channel) end
        end

    elseif tag == "request" and attrs.type and attrs.from then
        if is_ignored(attrs.from) then
            send_data_raw({ type = attrs.type:match("^([^:]+)") or attrs.type, to = attrs.from }, nil)
        else
            dispatch_callback(attrs.type, attrs)
        end

    elseif tag == "notify" then
        if attrs.type == "new-spell-ranks" then
            -- Request spell ranks from server (Revenant doesn't use SpellRanks, skip)
        elseif attrs.type == "server-restart" then
            server_restart = true
            if sock then sock:close() end
        end

    elseif tag == "data" then
        local data = decode_data_text(text)
        local from = attrs.from
        local dtype = attrs.type

        -- Check if this is a response to a waiting get_data request
        if from and dtype then
            for _, w in ipairs(waiting) do
                if w.data == "waiting"
                   and w.type == dtype
                   and from:lower():find("^" .. w.name:lower(), 1, true) then
                    w.data = data
                    break
                end
            end
        end

        -- Handle server responses
        if from == "server" then
            if dtype == "connected" then
                respond(format_who(data, attrs.channel))
            elseif dtype == "channels" then
                respond(format_channels(data, tonumber(attrs.total)))
            elseif dtype == "server stats" then
                respond(format_stats(data))
            end
        elseif from and not is_ignored(from) then
            if dtype == "spells" then
                if data == nil then
                    echo(from .. " declined your request for spell information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_spells(from, data))
                end
            elseif dtype == "skills" then
                if data == nil then
                    echo(from .. " declined your request for skill information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_skills(from, data))
                end
            elseif dtype == "info" then
                if data == nil then
                    echo(from .. " declined your request for stat information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_info(from, data))
                end
            elseif dtype == "health" then
                if data == nil then
                    echo(from .. " declined your request for health information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_health(from, data))
                end
            elseif dtype == "locate" then
                if data == nil then
                    echo(from .. " declined your request for location information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_locate(from, data))
                end
            elseif dtype == "bounty" then
                if data == nil then
                    echo(from .. " declined your request for bounty information.")
                elseif data == false then
                    echo("no such user")
                else
                    respond(format_bounty(from, data))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Connect and run (called from connection thread)
--------------------------------------------------------------------------------

local function try_connect()
    local last_err = nil
    for _, tls_host in ipairs(TLS_HOSTNAMES) do
        local handle, err = Socket.connect_tls(LNET_HOST, LNET_PORT, CA_CERT_PEM, tls_host)
        if handle then
            return handle
        end
        last_err = err
    end
    -- Fall back to the first TLS hostname but without custom CA (system roots)
    local handle, err = Socket.connect_tls(LNET_HOST, LNET_PORT, nil, LNET_HOST)
    if handle then return handle end
    return nil, last_err or err
end

local function do_connect()
    local handle, err = try_connect()
    if not handle then
        echo("zeronet: connection failed: " .. tostring(err))
        return false
    end

    sock = handle

    -- Send login XML
    local char_name = (GameState and GameState.name) or "Unknown"
    local game_name = (GameState and GameState.game) or "GS3"
    local login_attrs = {
        name   = char_name,
        game   = game_name,
        client = LNET_CLIENT_VERSION,
        lich   = "revenant-" .. VERSION,
    }
    if secret[1] then login_attrs.password = secret[1] end
    send_xml(build_tag("login", login_attrs))

    echo("0net (zeronet) v" .. VERSION .. " connected to LNet")

    -- Read loop
    while server_connected() do
        local line, read_err = sock:readline()
        if not line then
            if read_err then
                echo("zeronet: read error: " .. tostring(read_err))
            end
            break
        end
        line = line:match("^(.-)%s*$")  -- rtrim
        if #line > 0 then
            local ok, perr = pcall(process_incoming_line, line)
            if not ok then
                echo("zeronet: parse error: " .. tostring(perr))
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Default callbacks
--------------------------------------------------------------------------------

-- Skills: full GS4 skill list
add_callback("lnet_skills", "skills", function(_attrs)
    local skills = {}
    local function add(name, val)
        if val and val > 0 then skills[name] = val end
    end
    add("Two Weapon Combat",       Skills.two_weapon_combat)
    add("Armor Use",               Skills.armor_use)
    add("Shield Use",              Skills.shield_use)
    add("Combat Maneuvers",        Skills.combat_maneuvers)
    add("Edged Weapons",           Skills.edged_weapons)
    add("Blunt Weapons",           Skills.blunt_weapons)
    add("Two-Handed Weapons",      Skills.two_handed_weapons)
    add("Ranged Weapons",          Skills.ranged_weapons)
    add("Thrown Weapons",          Skills.thrown_weapons)
    add("Polearm Weapons",         Skills.polearm_weapons)
    add("Brawling",                Skills.brawling)
    add("Ambush",                  Skills.ambush)
    add("Multi Opponent Combat",   Skills.multi_opponent_combat)
    add("Physical Fitness",        Skills.physical_fitness)
    add("Dodging",                 Skills.dodging)
    add("Arcane Symbols",          Skills.arcane_symbols)
    add("Magic Item Use",          Skills.magic_item_use)
    add("Spell Aiming",            Skills.spell_aiming)
    add("Harness Power",           Skills.harness_power)
    add("Elemental Mana Control",  Skills.elemental_mana_control)
    add("Mental Mana Control",     Skills.mental_mana_control)
    add("Spirit Mana Control",     Skills.spirit_mana_control)
    add("Elemental Lore - Air",    Skills.elemental_lore_air)
    add("Elemental Lore - Earth",  Skills.elemental_lore_earth)
    add("Elemental Lore - Fire",   Skills.elemental_lore_fire)
    add("Elemental Lore - Water",  Skills.elemental_lore_water)
    add("Spiritual Lore - Blessings",   Skills.spiritual_lore_blessings)
    add("Spiritual Lore - Religion",    Skills.spiritual_lore_religion)
    add("Spiritual Lore - Summoning",   Skills.spiritual_lore_summoning)
    add("Sorcerous Lore - Demonology",  Skills.sorcerous_lore_demonology)
    add("Sorcerous Lore - Necromancy",  Skills.sorcerous_lore_necromancy)
    add("Mental Lore - Divination",     Skills.mental_lore_divination)
    add("Mental Lore - Manipulation",   Skills.mental_lore_manipulation)
    add("Mental Lore - Telepathy",      Skills.mental_lore_telepathy)
    add("Mental Lore - Transference",   Skills.mental_lore_transference)
    add("Mental Lore - Transformation", Skills.mental_lore_transformation)
    add("Survival",         Skills.survival)
    add("Disarming Traps",  Skills.disarming_traps)
    add("Picking Locks",    Skills.picking_locks)
    add("Stalking and Hiding", Skills.stalking_and_hiding)
    add("Perception",       Skills.perception)
    add("Climbing",         Skills.climbing)
    add("Swimming",         Skills.swimming)
    add("First Aid",        Skills.first_aid)
    add("Trading",          Skills.trading)
    add("Pickpocketing",    Skills.pickpocketing)
    -- Spell lists via Spells module
    local sp = Spells
    if sp then
        add("Major Elemental", sp.major_elemental)
        add("Minor Elemental", sp.minor_elemental)
        add("Minor Mental",    sp.minor_mental)
        add("Major Spirit",    sp.major_spiritual)
        add("Minor Spirit",    sp.minor_spiritual)
        add("Wizard",          sp.wizard)
        add("Sorcerer",        sp.sorcerer)
        add("Ranger",          sp.ranger)
        add("Paladin",         sp.paladin)
        add("Empath",          sp.empath)
        add("Cleric",          sp.cleric)
        add("Bard",            sp.bard)
    end
    return skills
end)

-- Info (stats)
add_callback("lnet_info", "info", function(_attrs)
    local gs = GameState
    return {
        Race        = Stats.race or "",
        Profession  = Stats.prof or "",
        Gender      = Stats.gender or "",
        Age         = Stats.age or 0,
        Expr        = Stats.exp or 0,
        Level       = gs and gs.level or 0,
        Strength    = {Stats.strength or 0, 0},
        Constitution= {Stats.constitution or 0, 0},
        Dexterity   = {Stats.dexterity or 0, 0},
        Agility     = {Stats.agility or 0, 0},
        Discipline  = {Stats.discipline or 0, 0},
        Aura        = {Stats.aura or 0, 0},
        Logic       = {Stats.logic or 0, 0},
        Intuition   = {Stats.intuition or 0, 0},
        Wisdom      = {Stats.wisdom or 0, 0},
        Influence   = {Stats.influence or 0, 0},
        Mana        = gs and gs.mana or 0,
    }
end)

-- Active spells
add_callback("lnet_spells", "spells", function(_attrs)
    local gs = GameState
    if not gs then return {} end
    local active = gs.active_spells or {}
    local result = {}
    for _, spell in ipairs(active) do
        if spell.name and spell.duration then
            result[tostring(spell.name)] = spell.duration
        end
    end
    return result
end)

-- Locate
add_callback("lnet_locate", "locate", function(_attrs)
    local gs = GameState
    if not gs then return {} end
    local room = {
        title       = gs.room_name or "",
        description = gs.room_description or "",
        exits       = gs.room_exits_string or "",
        id          = gs.room_id,
        loot        = {},
        pcs         = {},
        npcs        = {},
    }
    -- Include GameObj if available
    if GameObj then
        if GameObj.loot then
            for _, obj in ipairs(GameObj.loot()) do
                room.loot[#room.loot+1] = obj.name or ""
            end
        end
        if GameObj.pcs then
            for _, pc in ipairs(GameObj.pcs()) do
                room.pcs[#room.pcs+1] = {name = pc.name or "", status = pc.status}
            end
        end
        if GameObj.npcs then
            for _, npc in ipairs(GameObj.npcs()) do
                room.npcs[#room.npcs+1] = {name = npc.name or "", status = npc.status}
            end
        end
    end
    -- Include self
    if not gs.hidden and not gs.invisible then
        local status_parts = {}
        if gs.dead    then status_parts[#status_parts+1] = "dead" end
        if gs.webbed  then status_parts[#status_parts+1] = "webbed" end
        if gs.stunned then status_parts[#status_parts+1] = "stunned" end
        if gs.kneeling     then status_parts[#status_parts+1] = "kneeling"
        elseif gs.sitting  then status_parts[#status_parts+1] = "sitting"
        elseif gs.prone    then status_parts[#status_parts+1] = "prone"
        elseif not gs.standing then status_parts[#status_parts+1] = "lying down" end
        local char_name = (Char and Char.name) or "Unknown"
        room.pcs[#room.pcs+1] = {
            name = char_name,
            status = #status_parts > 0 and table.concat(status_parts, " ") or nil
        }
    end
    return room
end)

-- Health
add_callback("lnet_health", "health", function(_attrs)
    local gs = GameState
    if not gs then return {} end
    -- Build injuries table compatible with original format
    local body_parts = {
        "head","neck","back","chest","abdomen",
        "leftEye","rightEye","leftArm","rightArm",
        "leftHand","rightHand","leftLeg","rightLeg",
        "leftFoot","rightFoot","nsys"
    }
    local injuries = {}
    for _, part in ipairs(body_parts) do
        local w = Wounds and Wounds[part] or 0
        local s = Scars  and Scars[part]  or 0
        if w > 0 or s > 0 then
            injuries[part] = {wound = w, scar = s}
        end
    end
    return {
        injuries    = injuries,
        health      = gs.health      or 0,
        max_health  = gs.max_health  or 0,
        spirit      = gs.spirit      or 0,
        max_spirit  = gs.max_spirit  or 0,
        stamina     = gs.stamina     or 0,
        max_stamina = gs.max_stamina or 0,
    }
end)

-- Bounty
add_callback("lnet_bounty", "bounty", function(_attrs)
    return Bounty and Bounty.task() or ""
end)

-- Upload spell ranks to LNet server (called on initial connect)
local function upload_spell_ranks()
    if not server_connected() then return false end
    local sp = Spells
    if not sp then return false end
    local data = {
        minorspiritual = sp.minor_spiritual or 0,
        majorspiritual = sp.major_spiritual or 0,
        cleric         = sp.cleric          or 0,
        minorelemental = sp.minor_elemental or 0,
        majorelemental = sp.major_elemental or 0,
        ranger         = sp.ranger          or 0,
        sorcerer       = sp.sorcerer        or 0,
        wizard         = sp.wizard          or 0,
        bard           = sp.bard            or 0,
        empath         = sp.empath          or 0,
        paladin        = sp.paladin         or 0,
        arcanesymbols  = Skills.arcane_symbols  or 0,
        magicitemuse   = Skills.magic_item_use  or 0,
    }
    if sp.minor_mental then data.minormental = sp.minor_mental end
    return send_data_raw({ type = "spell-ranks" }, data)
end

--------------------------------------------------------------------------------
-- get_data(name, type) -> data or false
-- Request data from another LNet user (blocking in a Thread).
-- Must be called from a Thread or async context.
--------------------------------------------------------------------------------
local function get_data(name, request_type)
    if not server_connected() then return false end
    if not name or name == "" or not request_type or request_type == "" then return false end
    name = name:sub(1,1):upper() .. name:sub(2):lower()
    local waiter = {type = request_type, name = name, data = "waiting"}
    table.insert(waiting, waiter)
    send_request({type = request_type, to = name})
    -- Wait up to 8 seconds
    local t = Thread.new(function()
        local deadline = os.time() + 8
        while waiter.data == "waiting" and os.time() < deadline do
            pause(0.1)
        end
    end)
    t:value()
    -- Remove waiter
    for i, w in ipairs(waiting) do
        if w == waiter then table.remove(waiting, i); break end
    end
    if waiter.data == "waiting" then return false end
    return waiter.data
end

--------------------------------------------------------------------------------
-- Auto-load user callbacks
--------------------------------------------------------------------------------
local ok_cb = pcall(function()
    if Script.exists and Script.exists("lnet_callbacks") then
        echo("zeronet: detected callback library...")
        Script.run("lnet_callbacks")
    end
end)

--------------------------------------------------------------------------------
-- Expose global LNet API (for other scripts)
--------------------------------------------------------------------------------
_G.LNet = _G.LNet or {}
_G.LNet.add_callback     = add_callback
_G.LNet.remove_callback  = remove_callback
_G.LNet.clear_callbacks  = clear_callbacks
_G.LNet.callbacks        = callbacks
_G.LNet.get_data         = get_data
_G.LNet.safe_send        = safe_send
_G.LNet.send_message     = send_message
_G.LNet.send_request     = send_request
_G.LNet.send_data        = send_data_raw
_G.LNet.upload_spell_ranks = upload_spell_ranks

-- Lich5-compat globals used by other scripts
_G.UNTRUSTED_LNET_GET_DATA = function(name, rtype) return get_data(name, rtype) end
_G.UNTRUSTED_LNET_UPLOAD_SPELL_RANKS = function() return upload_spell_ranks() end
_G.lichnet_get_spells = function(name) return get_data(name, "spells") end

--------------------------------------------------------------------------------
-- Permission / option strings
--------------------------------------------------------------------------------
local fix_action_desc = {
    locate = "locate you", spells = "view your active spells",
    skills = "view your skills", info   = "view your stats",
    health = "view your health", bounty = "view your bounties",
}
local fix_perm_desc = {
    all = "everyone", friends = "only your friends",
    enemies = "everyone except your enemies", none = "no one",
}

--------------------------------------------------------------------------------
-- Command processing
--------------------------------------------------------------------------------
local function process_command(msg)
    -- Chat: ::Name or to Name
    local to, text = msg:match("^chat%s+::(%S+)%s+(.*)")
    if not to then to, text = msg:match("^chat%s+to%s+(%S+)%s+(.*)") end
    if to then send_message({type="private", to=to}, text); return end

    -- Chat: :channel or on channel
    local chan
    chan, text = msg:match("^chat%s+:([^:%s]+)%s+(.*)")
    if not chan then chan, text = msg:match("^chat%s+on%s+(%S+)%s+(.*)") end
    if chan then send_message({type="channel", channel=chan}, text); return end

    -- Chat default channel
    text = msg:match("^chat%s+(.*)")
    if text then send_message({type="channel"}, text); return end

    if msg:match("^who$") then send_query({type="connected"}); return end
    local who_target = msg:match("^who%s+([A-Za-z:]+)$")
    if who_target then send_query({type="connected", name=who_target}); return end

    if msg:match("^stats$") then send_query({type="server stats"}); return end

    if msg:match("^channels?") then
        if msg:match("full") or msg:match("all") then
            send_query({type="channels"})
        else
            send_query({type="channels", num="15"})
        end
        return
    end

    local tune_ch = msg:match("^tune%s+([A-Za-z]+)$")
    if tune_ch then tune_channel(tune_ch); return end
    local untune_ch = msg:match("^untune%s+([A-Za-z]+)$")
    if untune_ch then untune_channel(untune_ch); return end

    local qtype, qname = msg:match("^(spells|skills|info|locate|health|bounty)%s+([A-Za-z:]+)$")
    if qtype then
        if is_ignored(qname) then
            echo("There's no point in sending a request to someone you're ignoring.")
        else
            send_request({type=qtype:lower(), to=qname})
        end
        return
    end

    -- Friends
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
    game_part, name_part = msg:match("^[dr]e[lm]e?t?e?%s?friends?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.friends, name) then save_options()
            echo(name .. " was removed from your friend list.")
        else echo(name .. " was not found on your friend list.") end
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
        if list_contains(options.enemies, name) then
            echo(name .. " is already on your enemy list.")
        else
            options.enemies[#options.enemies+1] = name
            save_options()
            echo(name .. " was added to your enemy list.")
        end
        return
    end
    game_part, name_part = msg:match("^[dr]e[lm]e?t?e?%s?enem[iy]e?s?%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.enemies, name) then save_options()
            echo(name .. " was removed from your enemy list.")
        else echo(name .. " was not found on your enemy list.") end
        return
    end
    if msg:match("^enem[iy]e?s?$") then
        if #options.enemies == 0 then echo("You have no enemies.")
        else echo("enemies: " .. table.concat(options.enemies, ", ")) end
        return
    end

    -- Allow (show)
    if msg:match("^allow$") then
        for _, action in ipairs({"locate","spells","skills","info","health","bounty"}) do
            local perm = options.permission[action] or "none"
            respond("You are allowing " .. (fix_perm_desc[perm] or "no one")
                    .. " to " .. (fix_action_desc[action] or action) .. ".")
        end
        return
    end

    -- Allow (set)
    local allow_act, allow_grp = msg:match("^allow%s+(locate|spells|skills|info|health|bounty|all)%s+(%S+)$")
    if allow_act then
        local group_key
        if allow_grp:match("^all$")     then group_key = "all"
        elseif allow_grp:match("^friends?$") then group_key = "friends"
        elseif allow_grp:match("enem")  then group_key = "enemies"
        elseif allow_grp:match("^none$") then group_key = "none" end
        if group_key then
            local actions = allow_act == "all"
                and {"locate","spells","skills","info","health","bounty"}
                or {allow_act}
            for _, a in ipairs(actions) do
                options.permission[a] = group_key
                echo("You are now allowing " .. fix_perm_desc[group_key]
                     .. " to " .. (fix_action_desc[a] or a) .. ".")
            end
            save_options()
        end
        return
    end

    -- Ignore
    if msg:match("^ignore$") then
        if #options.ignore == 0 then echo("You are not ignoring anyone.")
        else echo("You are ignoring the following people: " .. table.concat(options.ignore, ", ")) end
        return
    end
    game_part, name_part = msg:match("^ignore%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_contains(options.ignore, name) then echo("You were already ignoring " .. name .. ".")
        else
            options.ignore[#options.ignore+1] = name
            save_options()
            echo("You are now ignoring " .. name .. ".")
        end
        return
    end
    game_part, name_part = msg:match("^unignore%s+([A-Za-z]*:?)([A-Za-z]+)$")
    if name_part then
        local name = resolve_name(game_part, name_part)
        if list_remove(options.ignore, name) then save_options()
            echo("You are no longer ignoring " .. name .. ".")
        else echo(name .. " wasn't being ignored.") end
        return
    end

    -- Options
    local ts = msg:match("^timestamps?=(on|off)$")
    if ts then options.timestamps = (ts=="on"); save_options()
        echo("timestamps " .. (options.timestamps and "on" or "off")); return end

    local fw = msg:match("^famwindow=(on|off)$")
    if fw then options.fam_window = (fw=="on"); save_options()
        echo("familiar window " .. (options.fam_window and "on" or "off")); return end

    local gr = msg:match("^greeting=(on|off)$")
    if gr then options.greeting = (gr=="on"); save_options()
        echo("greeting " .. (options.greeting and "on" or "off")); return end

    -- Password (local only)
    local pw = msg:match("^password=(%S+)$")
    if pw then
        if pw == "nil" then secret[1] = nil; echo("Password cleared.")
        else secret[1] = pw; echo("Password saved locally.") end
        save_secret(); return
    end

    -- Password change on server
    local newpw = msg:match("^changepw=(%S+)$")
    if newpw then
        send_data_raw({type="newpassword"}, newpw)
        if newpw == "nil" then secret[1] = nil; echo("Password cleared.")
        else secret[1] = newpw; echo("Password saved locally.") end
        save_secret(); return
    end

    -- Email
    local email = msg:match("^email=(%S+)$")
    if email then send_data_raw({type="newemail"}, email); return end

    -- Moderate
    local ma, mn, mc = msg:match("^(ban|gag|mod|banip)%s+([%w:]+)%s+on%s+(%w+)$")
    if ma then moderate({action=ma:lower(), name=mn, channel=mc}); return end

    local a, n, c, dur, unit = msg:match("^(ban|gag|banip)%s+([%w:]+)%s+on%s+(%w+)%s+for%s+(%d+)%s*(%a+)$")
    if a then
        local mult = time_multiplier[unit:lower()] or 1
        moderate({action=a:lower(), name=n, channel=c, length=tostring(tonumber(dur)*mult)})
        return
    end

    local ua, un, uc = msg:match("^(unban|ungag|unmod)%s+([%w:]+)%s+on%s+(%w+)$")
    if ua then moderate({action=ua:lower(), name=un, channel=uc}); return end

    -- Channel admin
    local hidden, private, ch_name, ch_desc = msg:match("^create%s+(hidden)?%s*(private)?%s*channel%s+(%w+)%s+(.+)$")
    if ch_name then
        admin({
            action="create channel", name=ch_name,
            description=ch_desc:match("^%s*(.-)%s*$"),
            hidden=hidden and "yes" or "no",
            private=private and "yes" or "no",
        })
        return
    end

    -- Create poll
    if msg:match("^create%s+poll") then
        local question = msg:match("%-%-question%s+(.-)%s*(?:%-%-|$)")
        if not question then question = msg:match("%-%-question%s+(.+)$") end
        local vt_num, vt_unit = msg:match("%-%-vote%-time%s+(%d+)%s*(%a+)")
        local vote_time = nil
        if vt_num then
            local mult = time_multiplier[vt_unit:lower()] or 1
            vote_time = tonumber(vt_num) * mult
        end
        local options_list = {}
        local i = 1
        while true do
            local opt = msg:match("%-%-option%-" .. i .. "%s+(.-)%s*(?:%-%-|$)")
            if not opt then opt = msg:match("%-%-option%-" .. i .. "%s+(.+)$") end
            if not opt then break end
            options_list[#options_list+1] = opt:sub(1,64)
            i = i + 1
        end
        if question and #options_list >= 2 then
            local attrs = {action="create poll", question=question}
            for j, opt in ipairs(options_list) do
                attrs["option " .. j] = opt
            end
            if vote_time then attrs.length = vote_time end
            admin(attrs)
        else
            echo("You're doing it wrong. Type ;zeronet help")
        end
        return
    end

    local del_ch = msg:match("^delete%s+channel%s+(%w+)$")
    if del_ch then admin({action="delete channel", name=del_ch}); return end

    -- Callbacks list
    if msg:match("^callbacks$") then
        if not next(callbacks) then echo("No callbacks registered.")
        else
            for rtype, handlers in pairs(callbacks) do
                for cname, _ in pairs(handlers) do
                    echo("  " .. rtype .. " -> " .. cname)
                end
            end
        end
        return
    end

    -- Upload spell ranks
    if msg:match("^upload%-spell%-ranks?$") then
        if upload_spell_ranks() then echo("Spell ranks uploaded.")
        else echo("Not connected or no spell rank data.") end
        return
    end

    -- Help
    if msg:match("^help$") then
        local lc = ";"
        local sn = "zeronet"
        local out = "\n0net (zeronet) v" .. VERSION .. " — extended LNet chat client\n\n"
        out = out .. lc .. "chat <message>                     send a message to your default channel\n"
        out = out .. lc .. ",<message>                         ''\n"
        out = out .. lc .. "chat on <channel name> <message>   send a message to the given channel\n"
        out = out .. lc .. "chat :<channel name> <message>     ''\n"
        out = out .. lc .. "chat to <name> <message>           send a private message\n"
        out = out .. lc .. "chat ::<name> <message>            ''\n"
        out = out .. lc .. "<name>:<message>                   private message shorthand\n"
        out = out .. lc .. "who                                list who's connected\n"
        out = out .. lc .. "who <channel>                      list who's tuned to a channel\n"
        out = out .. lc .. "channels                           list 15 most populated channels\n"
        out = out .. lc .. "channels full                      list all channels\n"
        out = out .. lc .. "tune <channel>                     listen to a channel\n"
        out = out .. lc .. "untune <channel>                   stop listening to a channel\n"
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
        out = out .. ";" .. sn .. " ignore                        list ignored\n"
        out = out .. ";" .. sn .. " ignore <name>                 ignore a person\n"
        out = out .. ";" .. sn .. " unignore <name>               unignore a person\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " password=<password>           protect character name with password\n"
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
        out = out .. "      <time>: number + s/m/h/d/y\n"
        out = out .. "\n"
        out = out .. "Callback API (from other scripts):\n"
        out = out .. "  LNet.add_callback(name, type, handler)\n"
        out = out .. "  LNet.remove_callback(name, type)\n"
        out = out .. "  LNet.get_data(name, type)  -- blocking, call from Thread\n"
        out = out .. "  LNet.safe_send(attrs, message)\n"
        out = out .. "\n"
        out = out .. ";" .. sn .. " callbacks                     list registered callbacks\n"
        respond(out)
        return
    end

    echo("Unknown command. Type ;zeronet help")
end

--------------------------------------------------------------------------------
-- Input hook
--------------------------------------------------------------------------------
local function on_upstream(line)
    -- Intercept ;, shorthand
    local cmd, rest = line:match("^;(,)(.*)")
    if cmd then
        process_command("chat " .. (rest or ""))
        return nil
    end

    -- Standard lnet commands (chat, who, locate, spells, info, skills, health, bounty, tune, untune, channels, reply)
    for _, pat in ipairs({
        "^;(chat%s.*)",
        "^;(who.*)",
        "^;(locate%s.*)",
        "^;(spells%s.*)",
        "^;(info%s.*)",
        "^;(skills%s.*)",
        "^;(health%s.*)",
        "^;(bounty%s.*)",
        "^;(tune%s.*)",
        "^;(untune%s.*)",
        "^;(channels?.*)",
    }) do
        local m = line:match(pat)
        if m then process_command(m); return nil end
    end

    -- ;Name:message → private message
    local pm_name, pm_msg = line:match("^;([A-Za-z]+):(.*)")
    if pm_name then
        process_command("chat ::" .. pm_name .. " " .. pm_msg)
        return nil
    end

    -- ;zeronet or ;0net subcommand
    local zn_cmd = line:match("^;zeronet%s*(.*)")
    if not zn_cmd then zn_cmd = line:match("^;0net%s*(.*)") end
    if zn_cmd then
        process_command(zn_cmd:match("^%s*(.-)%s*$"))
        return nil
    end

    return line
end

UpstreamHook.add("zeronet", on_upstream)
Script.at_exit(function()
    UpstreamHook.remove("zeronet")
    if sock then sock:close() end
    _G.LNet.add_callback    = nil
    _G.LNet.get_data        = nil
end)

--------------------------------------------------------------------------------
-- Handle initial args
--------------------------------------------------------------------------------
local init_args = Script.vars[1] or ""
if init_args:match("^password=") then
    local pw = init_args:match("^password=(%S+)$")
    if pw == "nil" then secret[1] = nil; echo("Password cleared.")
    else secret[1] = pw; echo("Password saved locally.") end
    save_secret()
elseif init_args:lower() == "help" then
    process_command("help")
end

--------------------------------------------------------------------------------
-- Connection thread — reconnects automatically
--------------------------------------------------------------------------------
local conn_thread = Thread.new(function()
    while true do
        server_restart = false
        local connected = do_connect()
        -- Cleanup socket
        if sock then sock:close() end
        sock = nil

        if server_restart then
            echo("zeronet: server is restarting; waiting 30 seconds to reconnect...")
            pause(30)
        else
            if connected then
                echo("zeronet: connection lost")
            end
            pause(30)  -- wait before reconnect
        end
    end
end)

--------------------------------------------------------------------------------
-- Keepalive thread — pings every 49 seconds of silence
--------------------------------------------------------------------------------
local keepalive_thread = Thread.new(function()
    while true do
        pause(10)
        if server_connected() and (os.time() - last_send) > 49 then
            send_ping()
        end
    end
end)

--------------------------------------------------------------------------------
-- Main loop — keeps script alive; threads do the real work
--------------------------------------------------------------------------------
while true do
    pause(60)
end
