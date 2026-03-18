--- @revenant-script
--- name: lumnismon
--- version: 1.2.3
--- author: elanthia-online
--- contributors: Vailan, Demandred
--- game: gs
--- description: Lumnis experience boost tracking and monitoring across multiple characters
--- tags: character,experience,lumnis,tracking
--- @lic-certified: complete 2026-03-18

--------------------------------------------------------------------------------
-- LumnisMon - Multi-Character Lumnis Tracking
--
-- Tracks Lumnis boost cycles (2x/3x/4x/5x multiplier), profession resources,
-- bounty points, experience, deeds, and invoker spells across all characters.
-- Data is shared via Settings (cross-character) so every character sees every
-- other character's last-recorded state.
--
-- Usage:
--   ;lumnismon              - Query all data for this char + display report
--   ;lumnismon log          - Query + save, no report display
--   ;lumnismon report       - Display saved data without querying
--   ;lumnismon help         - Show help and current settings
--   ;lumnismon --setting=value  - Change a display/sort setting
--------------------------------------------------------------------------------

local TableRender = require("lib/table_render")

local VERSION = "1.2.3"

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Mind state string -> fraction of capacity (0..1)
local MIND_STATES = {
    ["clear as a bell"] = 0,
    ["fresh and clear"] = 0.25 / 2,
    ["clear"]           = 0.75 / 2,
    ["muddled"]         = 1.12 / 2,
    ["becoming numbed"] = 1.37 / 2,
    ["numbed"]          = 1.65 / 2,
    ["must rest"]       = 1.9 / 2,
    ["saturated"]       = 1,
}

-- Month abbreviation -> next schedule month number (6 months ahead)
local MONTH_TO_NEXT = {
    Ready = "Ready",
    Jan = "7",  Feb = "8",  Mar = "9",  Apr = "10",
    May = "11", Jun = "12", Jul = "1",  Aug = "2",
    Sep = "3",  Oct = "4",  Nov = "5",  Dec = "6",
}

-- Spells watched for invoker tracking (average remaining time)
local WATCHED_SPELLS = {101, 104, 105, 107, 112, 401, 406, 414, 503, 509, 601, 602, 618, 911, 1204, 1208}

-- Profession service access requirements
local PROF_SERVICE_REQS = {
    Bard     = {level = 20},
    Monk     = {level = 20},
    Warrior  = {level = 20},
    Rogue    = {level = 20},
    Wizard   = {level = 25, spell = 925},
    Sorcerer = {level = 35, spell = 735},
    Cleric   = {level = 30, spell = 330},
    Ranger   = {level = 20, spell = 620},
    Paladin  = {level = 20, spell = 1620},
    Empath   = {spell = 1135},
}

--------------------------------------------------------------------------------
-- Settings defaults (boolean toggles and numeric settings)
--------------------------------------------------------------------------------

local BOOLEAN_DEFAULTS = {
    show_account          = false,
    account_inline        = false,
    show_prof             = true,
    show_level            = true,
    show_deeds            = true,
    show_invoker          = true,
    show_check_time       = false,
    show_renew_time       = false,
    show_field_exp        = true,
    show_weekly_resource  = true,
    show_total_resource   = true,
    show_suffused_resource = true,
    show_xpn              = true,
    show_next_schedule    = false,
    show_bps              = true,
    sort_by_refresh       = false,
    sort_by_account       = true,
    sort_by_name          = false,
    use_terminal_table    = true,
}

local NUMERIC_DEFAULTS = {
    header_repeat_rows = 10,
}

local VALUE_MAP = {
    ["on"] = true, ["true"] = true, ["yes"] = true,
    ["off"] = false, ["false"] = false, ["no"] = false,
}

--------------------------------------------------------------------------------
-- UserVars-based per-character settings (display prefs)
--------------------------------------------------------------------------------

local function init_user_settings()
    local raw = UserVars.lumnismon
    local uv
    if raw and raw ~= "" then
        local ok, decoded = pcall(Json.decode, raw)
        if ok and type(decoded) == "table" then
            uv = decoded
        else
            uv = {}
        end
    else
        uv = {}
    end

    for k, v in pairs(BOOLEAN_DEFAULTS) do
        if uv[k] == nil then uv[k] = v end
    end
    for k, v in pairs(NUMERIC_DEFAULTS) do
        if uv[k] == nil then uv[k] = v end
    end
    if not uv.char_account then uv.char_account = "9999 Not Listed" end
    if not uv.custom_place then uv.custom_place = 0 end

    return uv
end

local function save_user_settings(uv)
    UserVars.lumnismon = Json.encode(uv)
end

--------------------------------------------------------------------------------
-- Shared data store (Settings = cross-character)
-- Key: "lumnismon_data" -> JSON of {charname -> char_info, ...}
--------------------------------------------------------------------------------

local DATA_KEY = "lumnismon_data"

local DEFAULT_CHAR = {
    charactername          = "",
    characteraccount       = "",
    profession             = "",
    level                  = "",
    lastcheckwhen          = "",
    refreshwhen            = 0,
    doubledexperience      = "",
    tripledexperience      = "",
    quadrupledexperience   = 0,
    quintupledexperience   = 0,
    supports_4x_5x        = false,
    refreshdays            = "",
    refreshhours           = "",
    refreshminutes         = "",
    refreshstring          = "",
    mindcapacity           = "",
    mindpercent            = "",
    currentmind            = "",
    currentdeed            = "",
    currentweeklyresource  = "",
    currenttotalresource   = "",
    currentsuffusedresource = "",
    currentexp             = "",
    expnext                = "",
    nextschedulestring     = "",
    bountypoints           = "",
    customplace            = "",
    invokerspellsremaining = "",
}

local function load_all_chars()
    local raw = Settings[DATA_KEY]
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            -- Migrate: ensure 4x/5x fields exist
            for _, ci in pairs(data) do
                if ci.quadrupledexperience == nil or ci.quadrupledexperience == "" then
                    ci.quadrupledexperience = 0
                end
                if ci.quintupledexperience == nil or ci.quintupledexperience == "" then
                    ci.quintupledexperience = 0
                end
                if ci.supports_4x_5x == nil then ci.supports_4x_5x = false end
            end
            return data
        end
    end
    return {}
end

local function save_all_chars(all)
    Settings[DATA_KEY] = Json.encode(all)
end

local function ensure_char_entry(all, name)
    if not all[name] then
        local entry = {}
        for k, v in pairs(DEFAULT_CHAR) do entry[k] = v end
        all[name] = entry
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function bold_wrap(text)
    return "<pushBold/>" .. text .. "<popBold/>"
end

local function preset(id, text)
    return '<preset id="' .. id .. '">' .. text .. '</preset>'
end

local function with_commas(n)
    local s = tostring(n)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function pad_right(s, w)
    s = tostring(s or "")
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function strip_xml(s)
    return (string.gsub(s, "<.->", ""))
end

local function parse_minutes_to_string(val)
    if val == nil or val == "" then return "0h0m" end
    local m = tonumber(val)
    if not m then return "0h0m" end
    local h = math.floor(m / 60)
    local rem = m % 60
    return h .. "h" .. rem .. "m"
end

local function format_bounty_points(bps)
    if not bps or bps == 0 then return "0" end
    if bps > 1000000000 then
        return string.format("%.2fB", bps / 1000000000)
    elseif bps > 1000000 then
        return string.format("%.2fM", bps / 1000000)
    elseif bps > 1000 then
        return string.format("%.0fK", bps / 1000)
    end
    return tostring(bps)
end

local function format_time_until(refresh_epoch)
    local diff = refresh_epoch - os.time()
    if diff <= 0 then return "Ready" end
    local total_min = math.floor(diff / 60)
    local mm = total_min % 60
    local total_hr = math.floor(total_min / 60)
    local hh = total_hr % 24
    local dd = math.floor(total_hr / 24)
    return string.format("%dd%02dh%02dm", dd, hh, mm)
end

local function format_check_time(epoch)
    if not epoch or epoch == "" or epoch == 0 then return "" end
    if epoch == "F2P" then return "F2P" end
    return os.date("%H%M %-d/%-m", epoch)
end

local function msg(text)
    respond(bold_wrap("[lumnismon]: " .. text))
end

--------------------------------------------------------------------------------
-- Profession service check
--------------------------------------------------------------------------------

local function has_profession_service()
    local prof = Stats.prof
    local level = Stats.level
    local req = PROF_SERVICE_REQS[prof]
    if not req then return false end
    if req.level and level < req.level then return false end
    if req.spell and not Spell[req.spell].known then return false end
    return true
end

--------------------------------------------------------------------------------
-- Mind capacity / percent
--------------------------------------------------------------------------------

local function mind_capacity()
    local log_stat = Stats.enhanced_log
    local dis_stat = Stats.enhanced_dis
    local log_val = (log_stat and log_stat[1]) or 0
    local dis_val = (dis_stat and dis_stat[1]) or 0
    return 800 + log_val + dis_val
end

local function mind_percent()
    local mind_str = GameState.mind
    if not mind_str then return 0 end
    return MIND_STATES[string.lower(mind_str)] or 0
end

--------------------------------------------------------------------------------
-- Exp until next level
--------------------------------------------------------------------------------

local function exp_until_next()
    if Char.level == 100 then return "Cap" end
    local nlt = GameState.next_level_text
    if not nlt then return 0 end
    if not string.find(nlt, "experience") and not string.find(nlt, "until next level") then
        return 0
    end
    local cleaned = string.gsub(nlt, " experience", "")
    cleaned = string.gsub(cleaned, " until next level", "")
    cleaned = string.gsub(cleaned, ",", "")
    return tonumber(cleaned) or 0
end

--------------------------------------------------------------------------------
-- Invoker info: average remaining minutes across watched spells
--------------------------------------------------------------------------------

local function invoker_info()
    local total = 0
    for _, num in ipairs(WATCHED_SPELLS) do
        local sp = Spell[num]
        if sp and sp.active then
            total = total + (sp.timeleft or 0)
        end
    end
    return math.floor(total / #WATCHED_SPELLS)
end

--------------------------------------------------------------------------------
-- LUMNIS INFO parsing via DownstreamHook
--------------------------------------------------------------------------------

local function get_lumnis_info()
    local current_time = os.time()
    local lumnis_result = nil
    local lumnis_done = false
    local f2p = false
    local supports_4x_5x = false
    local schedule_info = {month = nil, day = nil, year = nil}
    local filter = false

    local hook_name = "lumnismon_lumnis_info_" .. tostring(os.time())
    DownstreamHook.add(hook_name, function(line)
        local s = strip_xml(line)

        -- Start of lumnis output
        if string.find(s, "It is scheduled to refresh")
            or string.find(s, "restart as soon as you absorb experience")
            or string.find(s, "Because your account is free,")
            or string.find(s, "Your Gift of Lumnis has expired for this week") then
            filter = true
            lumnis_result = s
            if string.find(s, "Because your account is free,") then
                f2p = true
            end
            return nil
        end

        if filter then
            -- Empty line
            if string.match(s, "^%s*$") then
                return nil
            end

            -- Fash'lo'nae line
            if string.find(s, "You are not presently receiving") then
                return nil
            end

            -- Temple donations
            if string.find(s, "recent donations to the Temple of Lumnis") then
                if string.find(s, "You have not made") then
                    supports_4x_5x = false
                else
                    supports_4x_5x = true
                end
                return nil
            end

            -- Schedule info
            if string.find(s, "You last used a Lumnis scheduling option")
                or string.find(s, "You have not selected a Gift of Lumnis schedule") then
                local mon, d, yr = string.match(s,
                    "on %a+ (%a+)%s+(%d+) %S+ .. (%d+)%.")
                if mon then
                    schedule_info.month = mon
                    schedule_info.day = d
                    schedule_info.year = yr
                    if not string.find(s, "You must wait six months") then
                        schedule_info.month = "Ready"
                        schedule_info.day = "Ready"
                        schedule_info.year = "Ready"
                    end
                elseif string.find(s, "You have not selected") then
                    schedule_info.month = "Ready"
                    schedule_info.day = "Ready"
                    schedule_info.year = "Ready"
                end
                return nil
            end

            -- Scheduled gift / available uses lines
            if string.find(s, "Your Gift of Lumnis is scheduled")
                or string.find(s, "available uses? of")
                or string.find(s, "You have no available uses of")
                or string.find(s, "You have %d+ available use") then
                return nil
            end

            -- Prompt -> end of output
            if string.find(line, "<prompt time=") then
                DownstreamHook.remove(hook_name)
                lumnis_done = true
                return nil
            end

            -- Additional cycle / experience lines that are part of the lumnis block
            if string.find(s, "points of") or string.find(s, "additional cycle")
                or string.find(s, "experience remaining") then
                -- Append to result for parsing
                lumnis_result = (lumnis_result or "") .. " " .. s
                return nil
            end
        end

        -- Prompt outside filter still ends if we somehow missed it
        if string.find(line, "<prompt time=") and filter then
            DownstreamHook.remove(hook_name)
            lumnis_done = true
            return nil
        end

        return line
    end)

    put("lumnis info")
    wait_until(function() return lumnis_done end)

    return {
        result = lumnis_result,
        time = current_time,
        f2p = f2p,
        supports_4x_5x = supports_4x_5x,
        schedule = schedule_info,
    }
end

--------------------------------------------------------------------------------
-- Parse lumnis result string for experience multipliers and time
--------------------------------------------------------------------------------

local function parse_lumnis_result(result_str)
    local exp = {doubled = 0, tripled = 0, quadrupled = 0, quintupled = 0}
    local time_c = {days = 0, hours = 0, minutes = 0}
    local highest_tier = 0

    if not result_str then return exp, time_c end

    -- Split on periods to separate experience part from time part
    local parts = {}
    for part in string.gmatch(result_str, "[^%.]+") do
        table.insert(parts, part)
    end

    -- Parse experience multipliers from the first part
    if parts[1] then
        local words = {}
        for w in string.gmatch(parts[1], "%S+") do
            table.insert(words, w)
        end
        for i, w in ipairs(words) do
            local wl = string.lower(w)
            if string.find(wl, "doubled") and i >= 4 then
                local val = string.gsub(words[i - 3], ",", "")
                exp.doubled = tonumber(val) or 0
                if 2 > highest_tier then highest_tier = 2 end
            elseif string.find(wl, "tripled") and i >= 4 then
                local val = string.gsub(words[i - 3], ",", "")
                exp.tripled = tonumber(val) or 0
                if 3 > highest_tier then highest_tier = 3 end
            elseif string.find(wl, "quadrupled") and i >= 4 then
                local val = string.gsub(words[i - 3], ",", "")
                exp.quadrupled = tonumber(val) or 0
                if 4 > highest_tier then highest_tier = 4 end
            elseif string.find(wl, "quintupled") and i >= 4 then
                local val = string.gsub(words[i - 3], ",", "")
                exp.quintupled = tonumber(val) or 0
                if 5 > highest_tier then highest_tier = 5 end
            end
        end
    end

    -- Infer queued lower tiers from "additional cycles"
    if string.find(result_str, "additional cycle") then
        if highest_tier == 5 then
            if exp.quadrupled == 0 then exp.quadrupled = 7300 end
            if exp.tripled == 0 then exp.tripled = 7300 end
            if exp.doubled == 0 then exp.doubled = 7300 end
        elseif highest_tier == 4 then
            if exp.tripled == 0 then exp.tripled = 7300 end
            if exp.doubled == 0 then exp.doubled = 7300 end
        elseif highest_tier == 3 then
            if exp.doubled == 0 then exp.doubled = 7300 end
        end
    end

    -- Parse time remaining from second part
    if parts[2] then
        local words = {}
        for w in string.gmatch(parts[2], "%S+") do
            table.insert(words, w)
        end
        for i, w in ipairs(words) do
            local wl = string.lower(w)
            if string.find(wl, "minute") and i >= 2 then
                time_c.minutes = tonumber(words[i - 1]) or 0
            elseif string.find(wl, "hour") and i >= 2 then
                time_c.hours = tonumber(words[i - 1]) or 0
            elseif string.find(wl, "day") and i >= 2 then
                time_c.days = tonumber(words[i - 1]) or 0
            end
        end
    end

    return exp, time_c
end

--------------------------------------------------------------------------------
-- EXPERIENCE parsing via DownstreamHook
--------------------------------------------------------------------------------

local function get_exp_info()
    local cur_mind = 0
    local cur_deed = 0
    local cur_expnext = nil  -- nil until captured; fallback to GameState.next_level_text
    local exp_done = false
    local filter = false

    local hook_name = "lumnismon_exp_" .. tostring(os.time())
    DownstreamHook.add(hook_name, function(line)
        local s = strip_xml(line)

        if string.match(s, "^%s+Level:%s+%d+%s+Fame:") then
            filter = true
            return nil
        end

        if filter then
            if string.match(s, "^%s*$") then return nil end

            -- Squelch / capture misc experience output lines
            if string.find(s, "Ascension Exp:")
                or string.find(s, "Total Exp:")
                or string.find(s, "Exp to next TP:")
                or string.find(s, "PTPs/MTPs:")
                or string.find(s, "Your mind")
                or string.find(s, "strange sense of serenity")
                or string.find(s, "recent adventures echo") then
                return nil
            end

            -- Capture exp until next level (squelch from display)
            local xpn = string.match(s, "Exp until lvl:%s*([%d,]+)")
            if xpn then
                cur_expnext = tonumber(string.gsub(xpn, ",", "")) or 0
                return nil
            end

            local deed = string.match(s, "Deeds:%s+(%d+)")
            if deed then
                cur_deed = tonumber(deed)
                return nil
            end

            local field = string.match(s, "Field Exp:%s+([%d,]+)/")
            if field then
                cur_mind = tonumber(string.gsub(field, ",", "")) or 0
                return nil
            end

            if string.find(line, "<prompt time=") then
                DownstreamHook.remove(hook_name)
                exp_done = true
                return nil
            end
        end

        -- Prompt outside filter
        if string.find(line, "<prompt time=") and filter then
            DownstreamHook.remove(hook_name)
            exp_done = true
            return nil
        end

        return line
    end)

    put("experience")
    wait_until(function() return exp_done end)

    return {mind = cur_mind, deed = cur_deed, expnext = cur_expnext}
end

--------------------------------------------------------------------------------
-- RESOURCE parsing via DownstreamHook
--------------------------------------------------------------------------------

local function get_resource_info(is_f2p)
    if is_f2p then
        return {weekly = "F2P", total = "F2P", suffused = "F2P"}
    end

    if not has_profession_service() then
        return {weekly = "RSN", total = "RSN", suffused = "RSN"}
    end

    local weekly = nil
    local total = nil
    local suffused = nil
    local res_done = false
    local filter = false

    local hook_name = "lumnismon_resource_" .. tostring(os.time())
    DownstreamHook.add(hook_name, function(line)
        local s = strip_xml(line)

        -- Resource header line (contains Mana: with digits)
        if string.find(s, "Mana:") and string.find(s, "/") then
            filter = true
            return nil
        end

        if filter then
            if string.match(s, "^%s*$") then return nil end

            if string.find(s, "Voln Favor:") then return nil end

            -- Weekly/Total resource line
            -- Pattern: ResourceName: 1,234/50,000 (Weekly)  5,678/200,000 (Total)
            local w, t = string.match(s,
                ":%s+([%d,]+)/50,000 %(Weekly%)%s+([%d,]+)/200,000%s+%(Total%)")
            if w then
                weekly = string.gsub(w, ",", "")
                total = string.gsub(t, ",", "")
                return nil
            end

            -- Suffused resource line
            local suf = string.match(s, "Suffused%s+%a[%a%s']-:%s+([%d,]+)")
            if suf then
                suffused = string.gsub(suf, ",", "")
                return nil
            end

            if string.find(line, "<prompt time=") then
                DownstreamHook.remove(hook_name)
                res_done = true
                return nil
            end
        end

        if string.find(line, "<prompt time=") and filter then
            DownstreamHook.remove(hook_name)
            res_done = true
            return nil
        end

        return line
    end)

    put("resource")
    wait_until(function() return res_done end)

    return {
        weekly = weekly or "ATN",
        total = total or "ATN",
        suffused = suffused or "ATN",
    }
end

--------------------------------------------------------------------------------
-- BOUNTY parsing via DownstreamHook
--------------------------------------------------------------------------------

local function get_bounty_points()
    local bps = 0
    local bps_done = false
    local filter = false
    local char_name = GameState.name

    local hook_name = "lumnismon_bounty_" .. tostring(os.time())
    DownstreamHook.add(hook_name, function(line)
        local s = strip_xml(line)

        -- Bounty header: "CharName, your Adventurer's Guild information is as follows:"
        if string.find(s, "your Adventurer's Guild information is as follows") then
            filter = true
            return nil
        end

        if filter then
            if string.match(s, "^%s*$") then return nil end

            -- Squelch informational lines
            if string.find(s, "You have succeeded")
                or string.find(s, "You have accumulated")
                or string.find(s, "expedited")
                or string.find(s, "You are not currently")
                or string.find(s, "You have been tasked")
                or string.find(s, "The taskmaster told you") then
                return nil
            end

            local pts = string.match(s, "You currently have ([%d,]+) unspent bounty points")
            if pts then
                bps = tonumber(string.gsub(pts, ",", "")) or 0
                return nil
            end

            if string.find(line, "<prompt time=") then
                DownstreamHook.remove(hook_name)
                bps_done = true
                return nil
            end
        end

        if string.find(line, "<prompt time=") and filter then
            DownstreamHook.remove(hook_name)
            bps_done = true
            return nil
        end

        return line
    end)

    put("bounty")
    wait_until(function() return bps_done end)

    return bps
end

--------------------------------------------------------------------------------
-- Next schedule calculation
--------------------------------------------------------------------------------

local function calculate_next_schedule(schedule, is_f2p)
    if is_f2p then return "F2P" end
    if schedule.month == "Ready" or schedule.month == nil then return "Ready" end

    local next_month = MONTH_TO_NEXT[schedule.month]
    if not next_month then return "Ready" end

    return next_month .. "/" .. (schedule.day or "?")
end

--------------------------------------------------------------------------------
-- Update character info with all gathered data
--------------------------------------------------------------------------------

local function update_char_info(all, uv, lumnis, exp_data, res_data, bps_raw, avg_invoker)
    local name = GameState.name
    ensure_char_entry(all, name)
    local ci = all[name]

    ci.charactername = name
    ci.characteraccount = uv.char_account or "9999 Not Listed"
    ci.profession = Stats.prof
    ci.level = Char.level
    ci.mindcapacity = mind_capacity()
    ci.mindpercent = mind_percent()
    ci.currentmind = exp_data.mind
    ci.currentdeed = exp_data.deed
    ci.currentweeklyresource = res_data.weekly
    ci.currenttotalresource = res_data.total
    ci.currentsuffusedresource = res_data.suffused
    ci.currentexp = Stats.exp or 0
    ci.bountypoints = format_bounty_points(bps_raw)
    ci.customplace = uv.custom_place or 0
    ci.invokerspellsremaining = avg_invoker
    ci.supports_4x_5x = lumnis.supports_4x_5x
    ci.nextschedulestring = calculate_next_schedule(lumnis.schedule, lumnis.f2p)

    -- Prefer hook-captured expnext; fall back to GameState.next_level_text if available
    if Char.level == 100 then
        ci.expnext = "Cap"
    elseif exp_data.expnext ~= nil then
        ci.expnext = exp_data.expnext
    else
        ci.expnext = exp_until_next()
    end

    -- Update lumnis status
    if lumnis.f2p then
        ci.lastcheckwhen = "F2P"
        ci.refreshwhen = os.time() + 2592000 -- far future for sorting
        ci.refreshdays = "F2P"
        ci.refreshhours = "F2P"
        ci.refreshminutes = "F2P"
        ci.doubledexperience = "F2P"
        ci.tripledexperience = "F2P"
        ci.quadrupledexperience = "F2P"
        ci.quintupledexperience = "F2P"
    elseif lumnis.result and string.find(lumnis.result, "restart as soon as you absorb experience") then
        ci.lastcheckwhen = lumnis.time
        ci.refreshwhen = lumnis.time
        ci.refreshdays = 0
        ci.refreshhours = 0
        ci.refreshminutes = 0
        ci.doubledexperience = 7300
        ci.tripledexperience = 7300
        if lumnis.supports_4x_5x then
            ci.quadrupledexperience = 7300
            ci.quintupledexperience = 7300
        else
            ci.quadrupledexperience = 0
            ci.quintupledexperience = 0
        end
    elseif lumnis.result and (string.find(lumnis.result, "points of")
            or string.find(lumnis.result, "expired for this week")) then
        local exp_mult, time_c = parse_lumnis_result(lumnis.result)
        local total_secs = (time_c.days * 86400) + (time_c.hours * 3600) + (time_c.minutes * 60)
        ci.lastcheckwhen = lumnis.time
        ci.refreshwhen = lumnis.time + total_secs
        ci.refreshdays = time_c.days
        ci.refreshhours = time_c.hours
        ci.refreshminutes = time_c.minutes
        ci.doubledexperience = exp_mult.doubled
        ci.tripledexperience = exp_mult.tripled
        ci.quadrupledexperience = exp_mult.quadrupled
        ci.quintupledexperience = exp_mult.quintupled
    else
        echo("Lumnis Info was not found and therefore unable to be parsed")
    end
end

--------------------------------------------------------------------------------
-- Sorting
--------------------------------------------------------------------------------

local function sort_characters(all, uv)
    -- Build array of {name, info} pairs
    local arr = {}
    for name, info in pairs(all) do
        if info.charactername and info.charactername ~= "" then
            table.insert(arr, {name = name, info = info})
        end
    end

    if uv.sort_by_refresh and uv.sort_by_account then
        table.sort(arr, function(a, b)
            local aa = tostring(a.info.characteraccount or "")
            local ba = tostring(b.info.characteraccount or "")
            if aa ~= ba then return aa < ba end
            local ar = tonumber(a.info.refreshwhen) or 0
            local br = tonumber(b.info.refreshwhen) or 0
            return ar < br
        end)
    elseif uv.sort_by_account then
        table.sort(arr, function(a, b)
            local aa = tostring(a.info.characteraccount or "")
            local ba = tostring(b.info.characteraccount or "")
            if aa ~= ba then return aa < ba end
            return a.name < b.name
        end)
    elseif uv.sort_by_refresh then
        table.sort(arr, function(a, b)
            local ar = tonumber(a.info.refreshwhen) or 0
            local br = tonumber(b.info.refreshwhen) or 0
            if ar ~= br then return ar < br end
            return a.name < b.name
        end)
    else
        table.sort(arr, function(a, b)
            return a.name < b.name
        end)
    end

    return arr
end

--------------------------------------------------------------------------------
-- Prepare refresh strings
--------------------------------------------------------------------------------

local function prepare_char_data(all)
    local now = os.time()
    for _, ci in pairs(all) do
        ci.invokerspellsremaining = ci.invokerspellsremaining or 0
        ci.customplace = ci.customplace or 0

        local rw = tonumber(ci.refreshwhen)
        if ci.refreshwhen == "F2P" or not rw then
            ci.refreshwhen_epoch = now + 2592000
            ci.refreshstring = "F2P"
        elseif now >= rw then
            ci.refreshwhen_epoch = rw
            ci.refreshstring = "Ready"
        else
            ci.refreshwhen_epoch = rw
            ci.refreshstring = format_time_until(rw)
        end
    end
end

--------------------------------------------------------------------------------
-- Table headers and rows
--------------------------------------------------------------------------------

local function build_headers(uv)
    local h = {"Char"}
    if uv.show_account and uv.account_inline then table.insert(h, "Account") end
    if uv.show_prof then table.insert(h, "Prof") end
    if uv.show_level then table.insert(h, "Lvl") end
    if uv.show_deeds then table.insert(h, "Deed") end
    if uv.show_invoker then table.insert(h, "Invoker") end
    if uv.show_check_time then table.insert(h, "ChckTime") end
    if uv.show_renew_time then table.insert(h, "RenTim") end
    table.insert(h, "2x")
    table.insert(h, "3x")
    table.insert(h, "4x")
    table.insert(h, "5x")
    table.insert(h, "Stat")
    if uv.show_field_exp then table.insert(h, "Fld") end
    if uv.show_xpn then table.insert(h, "XPN") end
    if uv.show_weekly_resource then table.insert(h, "WRe") end
    if uv.show_total_resource then table.insert(h, "TRe") end
    if uv.show_suffused_resource then table.insert(h, "SRe") end
    if uv.show_next_schedule then table.insert(h, "NxSch") end
    if uv.show_bps then table.insert(h, "BPs") end
    return h
end

local function format_experience_status(ci)
    local now = os.time()
    local rw = tonumber(ci.refreshwhen) or 0

    -- F2P check: refreshwhen far in the future means F2P
    if ci.doubledexperience == "F2P" then
        return {"F2P", "F2P", "F2P", "F2P", "F2P"}
    end

    -- Ready: lumnis has refreshed
    if rw < now then
        local x4 = (ci.supports_4x_5x == true) and "7300" or "0"
        local x5 = (ci.supports_4x_5x == true) and "7300" or "0"
        return {
            tostring(ci.doubledexperience or 7300),
            tostring(ci.tripledexperience or 7300),
            x4, x5, "Rdy"
        }
    end

    -- Active: show actual values
    local x2 = tostring(ci.doubledexperience or 0)
    local x3 = tostring(ci.tripledexperience or 0)
    local x4 = tostring(ci.quadrupledexperience or 0)
    local x5 = tostring(ci.quintupledexperience or 0)

    local total = (tonumber(ci.doubledexperience) or 0)
        + (tonumber(ci.tripledexperience) or 0)
        + (tonumber(ci.quadrupledexperience) or 0)
        + (tonumber(ci.quintupledexperience) or 0)

    local stat = total > 0 and "Act" or "Exp"

    return {x2, x3, x4, x5, stat}
end

local function format_resource(val, total_val, rtype)
    local vs = tostring(val or "")
    if vs == "F2P" or vs == "RSN" or vs == "ATN" then return vs end
    local v = tonumber(vs) or 0
    if rtype == "weekly" then
        return v == 50000 and (vs .. "*") or vs
    elseif rtype == "total" then
        local tv = tonumber(total_val) or 0
        return tv == 200000 and (vs .. "!") or vs
    end
    return vs
end

local function build_row(ci, uv)
    local row = {tostring(ci.charactername or "")}

    if uv.show_account and uv.account_inline then
        table.insert(row, string.upper(tostring(ci.characteraccount or "")))
    end
    if uv.show_prof then
        local prof = tostring(ci.profession or "")
        table.insert(row, string.sub(prof, 1, 3))
    end
    if uv.show_level then table.insert(row, tostring(ci.level or "")) end
    if uv.show_deeds then table.insert(row, tostring(ci.currentdeed or "")) end
    if uv.show_invoker then
        table.insert(row, parse_minutes_to_string(ci.invokerspellsremaining))
    end
    if uv.show_check_time then
        table.insert(row, format_check_time(ci.lastcheckwhen))
    end
    if uv.show_renew_time then
        table.insert(row, tostring(ci.refreshstring or ""))
    end

    -- Experience multiplier columns + status
    local exp_cols = format_experience_status(ci)
    for _, v in ipairs(exp_cols) do
        table.insert(row, v)
    end

    if uv.show_field_exp then table.insert(row, tostring(ci.currentmind or "")) end
    if uv.show_xpn then table.insert(row, tostring(ci.expnext or "")) end
    if uv.show_weekly_resource then
        table.insert(row, format_resource(ci.currentweeklyresource, ci.currenttotalresource, "weekly"))
    end
    if uv.show_total_resource then
        table.insert(row, format_resource(ci.currenttotalresource, ci.currenttotalresource, "total"))
    end
    if uv.show_suffused_resource then
        table.insert(row, format_resource(ci.currentsuffusedresource, ci.currenttotalresource, "suffused"))
    end
    if uv.show_next_schedule then
        table.insert(row, tostring(ci.nextschedulestring or ""))
    end
    if uv.show_bps then
        table.insert(row, tostring(ci.bountypoints or ""))
    end

    return row
end

--------------------------------------------------------------------------------
-- Colorize cell based on header context
--------------------------------------------------------------------------------

local function colorize_cell_value(header, value)
    if value == "F2P" then
        return preset("speech", value)
    end

    if header == "2x" or header == "3x" or header == "4x" or header == "5x" then
        if value == "0" then return preset("watching", value) end
    elseif header == "Stat" then
        if value == "Exp" then return preset("watching", value) end
    elseif header == "XPN" then
        if value == "Cap" then return preset("watching", value) end
    elseif header == "WRe" then
        if value == "RSN" or value == "ATN" then return preset("thought", value) end
        if string.find(value, "%*$") then
            -- 50000* means weekly capped
            if string.find(value, "^50000") then
                return preset("watching", value)
            end
            return preset("speech", value)
        end
    elseif header == "TRe" then
        if value == "RSN" or value == "ATN" then return preset("thought", value) end
        if string.find(value, "!$") then return preset("speech", value) end
        local num = tonumber(string.gsub(value, "[^%d]", ""))
        if num and num > 150000 and num < 200000 then
            return bold_wrap(value)
        end
    elseif header == "SRe" then
        if value == "RSN" or value == "ATN" then return preset("thought", value) end
    end

    return value
end

--------------------------------------------------------------------------------
-- Report display (forward declarations for mutually-dependent locals)
--------------------------------------------------------------------------------

local display_single_table
local display_by_account
local display_legacy

local function display_report(all, uv)
    prepare_char_data(all)
    local sorted = sort_characters(all, uv)

    if #sorted == 0 then
        echo("No character data found. Run ;lumnismon on each character to gather data.")
        return
    end

    echo("All values are based off of the last time that character ran LumnisMon")
    echo("Includes 2x, 3x, 4x, and 5x experience tracking")

    local headers = build_headers(uv)

    if uv.use_terminal_table then
        -- Use TableRender for nice bordered output
        if uv.show_account and not uv.account_inline then
            -- Group by account
            display_by_account(sorted, headers, uv)
        else
            display_single_table(sorted, headers, uv)
        end
    else
        -- Legacy plain-text format
        display_legacy(sorted, headers, uv)
    end
end

local function render_colorized_table(tbl, headers)
    local raw = tbl:render()
    local lines = {}
    local header_found = false
    for line in string.gmatch(raw .. "\n", "(.-)\n") do
        if string.sub(line, 1, 1) == "+" then
            table.insert(lines, line)
        elseif not header_found and string.find(line, "Char") then
            header_found = true
            table.insert(lines, line)
        else
            -- Colorize data cells
            if string.find(line, "|") then
                local cells = {}
                local idx = 0
                for cell in string.gmatch(line, "|([^|]+)") do
                    idx = idx + 1
                    local val = string.match(cell, "^%s*(.-)%s*$") or ""
                    local pad_l = string.match(cell, "^(%s*)") or ""
                    local pad_r = string.match(cell, "(%s*)$") or ""
                    local h = headers[idx]
                    if h and val ~= "" then
                        local colored = colorize_cell_value(h, val)
                        -- Recalculate padding if we added XML tags
                        if colored ~= val then
                            table.insert(cells, pad_l .. colored .. pad_r)
                        else
                            table.insert(cells, cell)
                        end
                    else
                        table.insert(cells, cell)
                    end
                end
                if #cells > 0 then
                    table.insert(lines, "|" .. table.concat(cells, "|") .. "|")
                else
                    table.insert(lines, line)
                end
            else
                table.insert(lines, line)
            end
        end
    end
    return table.concat(lines, "\n")
end

display_single_table = function(sorted, headers, uv)
    local repeat_interval = uv.header_repeat_rows or 10

    if repeat_interval == 0 or #sorted <= repeat_interval then
        local tbl = TableRender.new(headers)
        for _, entry in ipairs(sorted) do
            tbl:add_row(build_row(entry.info, uv))
        end
        respond('<output class="mono"/>')
        respond(render_colorized_table(tbl, headers))
        respond('<output class=""/>')
    else
        -- Chunk output with repeated headers
        local i = 1
        while i <= #sorted do
            local tbl = TableRender.new(headers)
            local j = math.min(i + repeat_interval - 1, #sorted)
            for k = i, j do
                tbl:add_row(build_row(sorted[k].info, uv))
            end
            respond('<output class="mono"/>')
            respond(render_colorized_table(tbl, headers))
            respond('<output class=""/>')
            if j < #sorted then respond("") end
            i = j + 1
        end
    end
end

display_by_account = function(sorted, headers, uv)
    local tbl = TableRender.new(headers)
    local current_account = nil

    for _, entry in ipairs(sorted) do
        local acct = tostring(entry.info.characteraccount or "")
        if acct ~= current_account then
            if current_account ~= nil then
                tbl:add_separator()
            end
            -- Account header row spanning all columns
            local display_acct = uv.show_account and string.upper(acct) or "ACCOUNT"
            local header_cells = {display_acct}
            for i = 2, #headers do header_cells[i] = "" end
            tbl:add_row(header_cells)
            tbl:add_separator()
            current_account = acct
        end
        tbl:add_row(build_row(entry.info, uv))
    end

    respond('<output class="mono"/>')
    respond(render_colorized_table(tbl, headers))
    respond('<output class=""/>')
end

display_legacy = function(sorted, headers, uv)
    -- Calculate column widths
    local just = {}
    for i, h in ipairs(headers) do
        just[i] = #h + 1
    end
    for _, entry in ipairs(sorted) do
        local row = build_row(entry.info, uv)
        for i, val in ipairs(row) do
            local len = #tostring(val) + 1
            if len > (just[i] or 0) then just[i] = len end
        end
    end

    -- Header line
    local hline = ""
    for i, h in ipairs(headers) do
        hline = hline .. pad_right(h, just[i])
    end
    respond('<output class="mono"/>' .. bold_wrap(hline) .. '\n<output class=""/>')

    -- Data lines
    local current_account = nil
    for _, entry in ipairs(sorted) do
        -- Account header if grouping
        if uv.show_account and not uv.account_inline and uv.sort_by_account then
            local acct = tostring(entry.info.characteraccount or "")
            if acct ~= current_account then
                local total_w = 0
                for _, w in ipairs(just) do total_w = total_w + w end
                local disp = uv.show_account and string.upper(acct) or "ACCOUNT"
                local pad = math.floor((total_w - #disp) / 2)
                if pad < 0 then pad = 0 end
                respond('<output class="mono"/>' .. bold_wrap(string.rep(" ", pad) .. disp) .. '\n<output class=""/>')
                current_account = acct
            end
        end

        local row = build_row(entry.info, uv)
        local line = ""
        for i, val in ipairs(row) do
            local h = headers[i]
            local colored = colorize_cell_value(h, tostring(val))
            -- If colored differs, we need to pad the raw value width
            if colored ~= tostring(val) then
                line = line .. colored .. string.rep(" ", math.max(0, (just[i] or 0) - #tostring(val)))
            else
                line = line .. pad_right(val, just[i])
            end
        end
        respond('<output class="mono"/>' .. line .. '\n<output class=""/>')
    end
end

--------------------------------------------------------------------------------
-- Help display
--------------------------------------------------------------------------------

local function show_help(uv)
    msg("Welcome to LumnisMon/MyInfo. Multi-character Lumnis tracking across all your characters.")
    msg("From lumnis info to resources to bounty points to deeds...there's a lot here now.")
    respond("")
    msg(";lumnismon        - Query this character and report all characters")
    msg(";lumnismon log    - Query and save but do not display the report")
    msg(";lumnismon report - Display saved data without querying")
    msg(";lumnismon help   - Show this help")
    respond("")
    msg("Settings (use --setting=value, e.g. ;lumnismon --show-bps=on):")
    respond("")

    local settings_info = {
        {"--show-account",           "Show account names",             uv.show_account},
        {"--char-account",           "Your account name",              uv.char_account},
        {"--account-inline",         "Show account inline or header",  uv.account_inline},
        {"--show-prof",              "Show profession",                uv.show_prof},
        {"--show-level",             "Show level",                     uv.show_level},
        {"--show-deeds",             "Show current deeds",             uv.show_deeds},
        {"--show-invoker",           "Show invoker spell times",       uv.show_invoker},
        {"--show-check-time",        "Show last check time",           uv.show_check_time},
        {"--show-renew-time",        "Show renewal time",              uv.show_renew_time},
        {"--show-field-exp",         "Show field experience",          uv.show_field_exp},
        {"--show-weekly-resource",   "Show weekly resource",           uv.show_weekly_resource},
        {"--show-total-resource",    "Show total resource",            uv.show_total_resource},
        {"--show-suffused-resource", "Show suffused resource",         uv.show_suffused_resource},
        {"--show-xpn",              "Show exp to next level",          uv.show_xpn},
        {"--show-next-schedule",     "Show next schedule date",        uv.show_next_schedule},
        {"--show-bps",              "Show bounty points",              uv.show_bps},
        {"--sort-by-refresh",        "Sort by renewal time",           uv.sort_by_refresh},
        {"--sort-by-account",        "Sort by account",                uv.sort_by_account},
        {"--use-terminal-table",     "Use bordered table output",      uv.use_terminal_table},
        {"--header-repeat-rows",     "Repeat headers every N rows",    uv.header_repeat_rows},
    }

    for _, s in ipairs(settings_info) do
        local flag, desc, val = s[1], s[2], s[3]
        if flag == "--char-account" then
            msg("  " .. flag .. "=ACCOUNT_NAME")
        elseif flag == "--header-repeat-rows" then
            msg("  " .. flag .. "=NUMBER (e.g. 10, 15, 0)")
        else
            msg("  " .. flag .. "=on|off")
        end
        msg("    " .. desc .. " -- Currently: " .. tostring(val))
    end
end

--------------------------------------------------------------------------------
-- CLI argument processing
--------------------------------------------------------------------------------

local function process_settings(args, uv)
    local changed = false

    for i = 1, #args do
        local arg = args[i]

        -- Boolean setting: --foo-bar=true
        local key, val = string.match(arg, "^%-?%-?([%w_%-]+)=(.+)$")
        if key then
            local setting_name = string.gsub(key, "%-", "_")

            -- Check boolean
            local bval = VALUE_MAP[string.lower(val)]
            if bval ~= nil and BOOLEAN_DEFAULTS[setting_name] ~= nil then
                uv[setting_name] = bval
                changed = true
            -- Check numeric
            elseif NUMERIC_DEFAULTS[setting_name] ~= nil then
                local nval = tonumber(val)
                if nval then
                    uv[setting_name] = nval
                    changed = true
                end
            -- char_account special
            elseif setting_name == "char_account" then
                uv.char_account = val
                changed = true
            elseif setting_name == "custom_place" then
                uv.custom_place = tonumber(val) or 0
                changed = true
            end
        end
    end

    return changed
end

local function parse_mode(args)
    if not args or not args[1] then return "normal" end
    local first = string.lower(args[1])
    if first == "log" then return "log" end
    if first == "help" or first == "?" then return "help" end
    if first == "report" then return "report" end
    return "settings"
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local uv = init_user_settings()

-- Build args array from Script.vars
local args = {}
if Script.vars[0] and Script.vars[0] ~= "" then
    for w in string.gmatch(Script.vars[0], "%S+") do
        table.insert(args, w)
    end
end

local mode = parse_mode(args)

-- Handle settings changes first
if mode == "settings" then
    local changed = process_settings(args, uv)
    if changed then
        save_user_settings(uv)
        msg("Settings saved. Rerun ;lumnismon to see updated report.")
    else
        msg("No recognized settings changed. Run ;lumnismon help for options.")
    end
    return
end

if mode == "help" then
    show_help(uv)
    return
end

local report_only = (mode == "report")
local log_only = (mode == "log")

-- Load shared character data
local all = load_all_chars()

if not report_only then
    ensure_char_entry(all, GameState.name)

    -- Query LUMNIS INFO
    local lumnis = get_lumnis_info()

    -- Query EXPERIENCE
    local exp_data = get_exp_info()

    -- Query RESOURCE
    local res_data = get_resource_info(lumnis.f2p)

    -- Query BOUNTY
    local bps_raw = get_bounty_points()

    -- Get invoker info
    local avg_invoker = invoker_info()

    -- Update this character's record
    update_char_info(all, uv, lumnis, exp_data, res_data, bps_raw, avg_invoker)

    -- Save
    save_all_chars(all)
    msg("Data saved for " .. GameState.name .. ".")
end

if not log_only then
    display_report(all, uv)
end
