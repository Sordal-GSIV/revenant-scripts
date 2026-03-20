--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: traffle
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Cait
--- game: gs
--- description: Raffle ticket tracking, listing, and management at festival events
--- tags: raffle,raffles,festival,event
---
--- Original Lich5 script by elanthia-online (v2.0.0, 2025-10-18)
---
--- Changelog (ported from Lich5):
---   v2.0.0 (2025-10-18): Complete OO refactor; YAML storage replaced with JSON for Revenant
---   v1.x: Original Cait script
---
--- Usage:
---   ;traffle                - Scan current room for raffle tables, then show list
---   ;traffle list           - Show known raffles
---   ;traffle reverse        - Show raffles in reverse order
---   ;traffle find <term>    - Search known raffles (checks date, room, description)
---   ;traffle clear          - Clear all tracked raffles
---   ;traffle delete <#>     - Delete a specific raffle by index (0-based)
---   ;traffle csv            - Export raffles to data/raffle.csv
---   ;traffle wiki           - Output raffles in MediaWiki markup format
---   ;traffle towncrier      - Post raffles to TownCrier
---   ;traffle buy            - Auto-purchase tickets for all tracked raffles
---   ;traffle help           - Show help
---
--- Debug mode:
---   ;e Vars["traffle"] = {debug_my_script = true}

local Vars = require("lib/vars")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DATA_FILE = "data/" .. (GameState.game or "gs") .. "/traffle.json"
local CSV_FILE  = "data/raffle.csv"

local LOOK_ON_EXCLUSIONS = {
    disk    = true, sign   = true, list    = true, kitten  = true,
    cat     = true, spirit = true, falcon  = true, placard = true,
    rat     = true, wolf   = true, raven   = true, figure  = true,
    hamster = true,
}

local TIME_LIMIT = 15  -- minutes after draw before pruning

--------------------------------------------------------------------------------
-- Debug helper
--------------------------------------------------------------------------------

local function is_debug()
    local t = Vars["traffle"]
    return type(t) == "table" and t.debug_my_script == true
end

local function dbg(msg)
    if is_debug() then echo(msg) end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function with_commas(num)
    local s = tostring(num or 0)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function format_time_remaining(seconds)
    if seconds <= 0 then return "COMPLETED" end
    local d = math.floor(seconds / 86400)
    seconds = seconds - d * 86400
    local h = math.floor(seconds / 3600)
    seconds = seconds - h * 3600
    local m = math.floor(seconds / 60)
    seconds = math.floor(seconds - m * 60)
    local parts = {}
    if d > 0 then table.insert(parts, string.format("%02dd", d)) end
    if h > 0 then table.insert(parts, string.format("%02dh", h)) end
    if m > 0 then table.insert(parts, string.format("%02dm", m)) end
    if seconds > 0 then table.insert(parts, string.format("%02ds", seconds)) end
    if #parts == 0 then return "0s" end
    return table.concat(parts, " ")
end

-- Parse a game time string into seconds-from-now.
-- Handles:
--   "09:00 PM EST"                               → today or tomorrow
--   "Sunday, October 19 at 09:00 PM EST"         → specific calendar date
--   "October 19 at 09:00 PM"                     → specific calendar date
local function parse_game_time_str(time_str)
    local MONTH_NUM = {
        January=1, February=2, March=3, April=4, May=5, June=6,
        July=7, August=8, September=9, October=10, November=11, December=12,
    }

    local h, m, ampm = string.match(time_str, "(%d+):(%d+)%s*([AaPp][Mm])")
    if not h then return 3600 end  -- fallback: 1 hour

    h = tonumber(h); m = tonumber(m)
    ampm = ampm:upper()
    if ampm == "PM" and h ~= 12 then h = h + 12 end
    if ampm == "AM" and h == 12 then h = 0 end

    local now = os.time()
    local t   = os.date("*t", now)
    t.hour = h; t.min = m; t.sec = 0

    -- Try to find a named month + day so multi-day raffles are anchored correctly
    local month_name, day_n = string.match(time_str, "(%a+)%s+(%d+)")
    local mon = month_name and MONTH_NUM[month_name]
    if mon then
        t.month = mon
        t.day   = tonumber(day_n)
        local draw = os.time(t)
        if draw <= now then
            t.year = t.year + 1   -- must be next year
            draw = os.time(t)
        end
        return draw - now
    end

    -- Time-of-day only: use today, wrapping to tomorrow if the time has passed
    local draw = os.time(t)
    if draw <= now then draw = draw + 86400 end
    return draw - now
end

--------------------------------------------------------------------------------
-- Data persistence
--------------------------------------------------------------------------------

local function load_raffles()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
    if ok and type(data) == "table" then
        dbg("Loaded " .. #data .. " raffles from " .. DATA_FILE)
        return data
    end
    return {}
end

local function save_raffles(raffles)
    File.write(DATA_FILE, Json.encode(raffles))
    dbg("Saved " .. #raffles .. " raffles to " .. DATA_FILE)
end

--------------------------------------------------------------------------------
-- Pruning
--------------------------------------------------------------------------------

local function prune_old(raffles)
    local now = os.time()
    local result = {}
    for _, r in ipairs(raffles) do
        local remaining = (r.draw_time or 0) - now
        if remaining > -(TIME_LIMIT * 60) then
            table.insert(result, r)
        end
    end
    local pruned = #raffles - #result
    if pruned > 0 then dbg("Pruned " .. pruned .. " old raffles") end
    return result
end

--------------------------------------------------------------------------------
-- Room scanning — relies on raw XML lines delivered to scripts by Revenant
-- (scripts see raw game XML, same as Lich5's want_downstream_xml mode)
--------------------------------------------------------------------------------

-- Regex patterns compiled once
local OBJ_RE     = Regex.new('exist="([^"]+)" noun="([^"]+)">([^<]+)<')
local TICKET_RE  = Regex.new('exist="(\\d+)" noun="tickets">([^<]+)<')

local function scan_room_objects()
    local room_objs = {}
    local line = dothistimeout("look", 3, "exist=", "<compass>")
    if not line then return room_objs end
    if not string.find(line, "exist=", 1, true) then return room_objs end

    local matches = OBJ_RE:find_all(line)
    for _, m in ipairs(matches) do
        local id, noun, desc = m[1], m[2], m[3]
        if not LOOK_ON_EXCLUSIONS[noun] then
            table.insert(room_objs, { id = id, noun = noun, desc = desc })
            dbg("Room obj found: " .. noun .. " (" .. id .. ") — " .. desc)
        end
    end
    return room_objs
end

local function find_raffle_tickets(room_objs)
    local raffles = {}
    for _, obj in ipairs(room_objs) do
        local line = dothistimeout("look on #" .. obj.id, 3,
            'noun="tickets"', "There is nothing on", "<prompt")
        if line and string.find(line, 'noun="tickets"', 1, true) then
            local matches = TICKET_RE:find_all(line)
            for _, m in ipairs(matches) do
                local id, desc = m[1], m[2]
                table.insert(raffles, { id = id, desc = desc, table_desc = obj.desc })
                dbg("Raffle found: " .. desc .. " (id=" .. id .. ") on " .. obj.desc)
            end
        end
    end
    return raffles
end

--------------------------------------------------------------------------------
-- Raffle info parser — reads `look at #<id>` output
--------------------------------------------------------------------------------

local function parse_raffle_info(raffle_id)
    local info = { item = nil, cost = nil, timeleft = 0, winners = nil }

    fput("look at #" .. raffle_id)

    local deadline = os.time() + 8
    while os.time() < deadline do
        local line = get_noblock()
        if not line then
            pause(0.05)
            goto continue
        end

        -- "The drawing will be in ... for N winner(s)." — winner count
        local w = string.match(line, "The drawing will be in .* for (.+) winners?%.")
        if w then info.winners = w end

        -- Full-date format: "The drawing for N winner(s) will be in ... (at HH:MM AM/PM [TZ])."
        local tickets, date_str = string.match(line,
            "The drawing for (%d+) winners? will be in [^(]+ %(at (.-)%)")
        if tickets then
            info.winners = tickets
            info.timeleft = parse_game_time_str(date_str)
            dbg("Full-date parse: " .. tostring(date_str) .. " → " .. info.timeleft .. "s")
            break
        end

        -- Elven standard time: "the drawing will be held on <day> elven standard time (<time>)."
        local est_day, est_time = string.match(line,
            "the drawing will be held on (.+)elven standard time %((.+)%)")
        if est_day then
            info.timeleft = parse_game_time_str(est_time)
            dbg("EST parse: " .. est_time .. " → " .. info.timeleft .. "s")
            break
        end

        -- "The drawing will be in X minutes."
        local mins = string.match(line, "The drawing will be in (%d+) minutes?")
        if mins then
            info.timeleft = info.timeleft + tonumber(mins) * 60
            break
        end

        -- "The drawing will be in X hours and Y minutes."
        local hrs, mins2 = string.match(line,
            "The drawing will be in (%d+) hours? and (%d+) minutes?")
        if hrs then
            info.timeleft = info.timeleft + tonumber(hrs) * 3600 + tonumber(mins2) * 60
            break
        end

        -- "The drawing will be in X hours." (no minutes)
        local hrs_only = string.match(line, "The drawing will be in (%d+) hours?[^%s]")
        if hrs_only then
            info.timeleft = info.timeleft + tonumber(hrs_only) * 3600
            break
        end

        -- Item description — all patterns from original
        local item = string.match(line, "^The raffle is for (.+)")
            or string.match(line, "^Raffle for (.+)")
            or string.match(line, "^This raffle is (.+)")
            or string.match(line, "^The raffle for (.+)")
            or string.match(line, 'This raffle is for "(.+)"%.')
            or string.match(line, "raffle will receive (.+)")
            or string.match(line, "winner will receive (.+)")
        if item then
            info.item = item
            dbg("Item: " .. item)
        end

        -- Ticket cost: "The ticket(s) sell for X silvers each."
        local cost = string.match(line, "The tickets? sell for (.+) silvers each%.")
            or string.match(line, "The tickets? sell for (.+) %w+ each%.")
        if cost then
            info.cost = string.gsub(cost, ",", "")
            dbg("Cost: " .. info.cost)
        end

        -- Draw ended / not found
        if string.find(line, "I could not find what you were referring to", 1, true)
            or string.find(line, "The drawing has been held", 1, true) then
            info.timeleft = 0
            break
        end

        ::continue::
    end
    return info
end

--------------------------------------------------------------------------------
-- Display — uses _respond() for raw XML output (bold, clickable room links)
--------------------------------------------------------------------------------

local NO_RAFFLES_MSG =
    "No raffles being tracked. Run this script while at a raffle table!\n" ..
    "Completed raffles are removed after " .. TIME_LIMIT .. " minutes."

local function format_list(raffles, reverse)
    if #raffles == 0 then return nil end  -- caller handles empty case

    local ordered = {}
    for i, r in ipairs(raffles) do ordered[i] = r end
    if reverse then
        local rev = {}
        for i = #ordered, 1, -1 do table.insert(rev, ordered[i]) end
        ordered = rev
    end

    local out = "================\n"
    for idx, raffle in ipairs(ordered) do
        local remaining = (raffle.draw_time or 0) - os.time()
        local time_str = remaining > 0 and format_time_remaining(remaining) or "COMPLETED"

        out = out .. "<pushBold/>"
        if is_debug() then out = out .. (idx - 1) .. " - " end
        out = out .. (raffle.pretty_date or os.date("%A, %B %e, %Y at %I:%M %p", raffle.draw_time or 0))

        if remaining <= 0 then
            out = out .. " (COMPLETED)"
        else
            out = out .. " (" .. time_str .. " remaining)"
        end

        out = out .. "<popBold/>\n"
        out = out .. (raffle.room_name or "Unknown Room")

        if raffle.room_id then
            out = out .. ' Room#:<d cmd=";go2 ' .. tostring(raffle.room_id) .. '">'
                      .. tostring(raffle.room_id) .. "</d>"
        end

        out = out .. "\n"
        out = out .. "Ticket cost: " .. with_commas(raffle.cost or 0)
                  .. " silvers | Winners: " .. tostring(raffle.winners or "?") .. "\n"
        out = out .. "Located On: " .. tostring(raffle.table_description or "") .. "\n"
        out = out .. tostring(raffle.description or "") .. "\n"
    end

    out = out .. "================\n"
    out = out .. " " .. #raffles .. " Total Raffles\n"
    out = out .. "================\n"
    return out
end

local function display_list(raffles, reverse)
    local out = format_list(raffles, reverse)
    if out then
        _respond(out)
    else
        respond(NO_RAFFLES_MSG)
    end
end

local function display_find_list(raffles)
    if #raffles == 0 then
        -- Mirror Ruby: explicit "0 Total Raffles" block when find returns empty
        local out = "================\n\n================\n 0 Total Raffles\n================\n"
        _respond(out)
        return
    end
    _respond(format_list(raffles, false))
end

--------------------------------------------------------------------------------
-- CSV formatter
--------------------------------------------------------------------------------

local function format_csv(raffles)
    if #raffles == 0 then return NO_RAFFLES_MSG end

    local lines = { "Subject,Start date,Start time,End date,End time,All day event,Description,Location,Private" }
    for _, raffle in ipairs(raffles) do
        local draw = raffle.draw_time or 0
        local date_part = os.date("%m/%d/%Y", draw)
        local time_part = os.date("%I:%M %p", draw)
        local desc = tostring(raffle.description or ""):gsub('"', "&quot;")
        local line = '"",'  -- Subject: empty (matches original Ruby convention)
                  .. date_part .. ","
                  .. time_part .. ",,,False,"
                  .. '"Ticket cost: ' .. with_commas(raffle.cost or 0) .. " silvers | Winners: "
                  .. tostring(raffle.winners or "?") .. "<br \\>"
                  .. "Located On: " .. tostring(raffle.table_description or "") .. "<br \\>"
                  .. desc .. '",'
                  .. '"' .. tostring(raffle.room_name or "") .. " | " .. tostring(raffle.room_id or "") .. '",'
                  .. "False"
        table.insert(lines, line)
    end

    File.write(CSV_FILE, table.concat(lines, "\n") .. "\n")
    return CSV_FILE .. " created!"
end

--------------------------------------------------------------------------------
-- Wiki formatter
--------------------------------------------------------------------------------

local function format_wiki(raffles)
    if #raffles == 0 then return NO_RAFFLES_MSG end

    local out = ""
    for _, raffle in ipairs(raffles) do
        local draw = raffle.draw_time or 0
        local date_hdr = (raffle.pretty_date or os.date("%A, %B %e, %Y", draw))
                      .. " | " .. os.date("%H:%M", draw)
        out = out .. "\n===" .. date_hdr .. "===\n<pre>"
        out = out .. tostring(raffle.room_name or "") .. "\n"
        if raffle.room_id then
            out = out .. "Lich Room#:" .. tostring(raffle.room_id) .. "\n"
        end
        out = out .. "Ticket cost: " .. with_commas(raffle.cost or 0) .. " silvers\n"
        out = out .. "Winners: " .. tostring(raffle.winners or "?") .. "\n"
        out = out .. "Located On: " .. tostring(raffle.table_description or "") .. "\n"
        out = out .. tostring(raffle.description or "") .. "\n</pre>"
    end
    return out
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function cmd_scan(raffles)
    local room_name = checkroom()
    local room_id   = Room.id

    local room_objs = scan_room_objects()
    local found     = find_raffle_tickets(room_objs)

    dbg("Room objs: " .. #room_objs .. ", raffles found: " .. #found)
    pause(0.5)

    for _, rf in ipairs(found) do
        local info = parse_raffle_info(rf.id)
        if info.item and info.timeleft > 0 then
            local draw_time   = os.time() + info.timeleft
            local pretty_date = os.date("%A, %B %e, %Y at %I:%M %p", draw_time)

            -- Remove duplicate entries (same description, room, draw time within 60s)
            local new_raffles = {}
            for _, existing in ipairs(raffles) do
                if not (existing.description == info.item
                    and existing.room_name == room_name
                    and math.abs((existing.draw_time or 0) - draw_time) < 60) then
                    table.insert(new_raffles, existing)
                end
            end
            raffles = new_raffles

            table.insert(raffles, {
                draw_time         = draw_time,
                pretty_date       = pretty_date,
                description       = info.item,
                room_name         = room_name,
                room_id           = room_id,
                cost              = info.cost,
                winners           = info.winners,
                table_description = rf.table_desc,
            })
        end
    end

    -- Sort by draw time (ascending)
    table.sort(raffles, function(a, b)
        return (a.draw_time or 0) < (b.draw_time or 0)
    end)

    save_raffles(raffles)
    return raffles
end

local function cmd_find(raffles, term)
    if not term or term == "" then
        respond("Usage: ;traffle find <term>")
        return
    end
    local lower = string.lower(term)
    local found = {}
    for _, r in ipairs(raffles) do
        if string.find(string.lower(r.description   or ""), lower, 1, true)
        or string.find(string.lower(r.room_name     or ""), lower, 1, true)
        or string.find(string.lower(r.pretty_date   or ""), lower, 1, true) then
            table.insert(found, r)
        end
    end
    display_find_list(found)
end

local function cmd_buy(raffles)
    if #raffles == 0 then
        respond("No raffles to buy tickets for.")
        return
    end

    local total_cost = 0
    for _, r in ipairs(raffles) do
        total_cost = total_cost + (tonumber(r.cost) or 0)
    end

    local starting_room = Room.id
    dbg("buy_all: total_cost=" .. total_cost .. " starting_room=" .. tostring(starting_room))

    -- Navigate to bank, deposit all, withdraw needed silver
    Script.run("go2", "bank")
    fput("deposit all")
    fput("withdraw " .. total_cost .. " silver")

    -- Visit each raffle room and buy a ticket
    for _, raffle in ipairs(raffles) do
        if raffle.room_id then
            Script.run("go2", tostring(raffle.room_id))
            if Room.id == raffle.room_id then
                local table_noun = (raffle.table_description or ""):match("%S+$") or "table"
                fput("buy ticket on " .. table_noun)
            end
        end
    end

    -- Return to bank to deposit remainder, then go home
    Script.run("go2", "bank")
    fput("deposit all")
    Script.run("go2", tostring(starting_room))
end

local function cmd_towncrier(raffles)
    if #raffles == 0 then
        respond("No raffles to post to TownCrier.")
        return
    end

    -- Load the towncrier_api script if not already running
    if not Script.running("towncrier_api") then
        Script.run("towncrier_api")
        pause(1)
    end

    -- Call TownCrier_API global registered by the towncrier_api script.
    -- Note: towncrier_api.lua must be ported separately.
    local ok, err = pcall(function()
        for _, raffle in ipairs(raffles) do
            local desc = tostring(raffle.description or ""):gsub('"', "&quot;")
            TownCrier_API.post_raffle(
                raffle.draw_time,
                desc .. ", Number of Winners: " .. tostring(raffle.winners or "?"),
                with_commas(raffle.cost or 0) .. " silvers",
                "Located On: " .. tostring(raffle.table_description or "")
                    .. ", Room Name: " .. tostring(raffle.room_name or ""),
                tostring(raffle.room_id or ""),
                GameState.name
            )
        end
    end)
    if not ok then
        respond("TownCrier error: " .. tostring(err))
        respond("Make sure towncrier_api.lua is installed and running.")
    end
end

local function show_help()
    respond("Type ;traffle at a raffle table to keep track of the raffle")
    respond("Thank you for downloading and using ;TRAFFLE.")
    respond("The various commands available are below:")
    respond("")
    respond("   ;TRAFFLE                - Scan room objects for raffle tables")
    respond("   ;TRAFFLE LIST           - Show a list of known raffles")
    respond("   ;TRAFFLE REVERSE        - Show above list in reverse order")
    respond("   ;TRAFFLE FIND <TERM>    - Search known raffles for a term")
    respond("   ;TRAFFLE CLEAR          - Clear your entire raffles list")
    respond("   ;TRAFFLE DELETE <#>     - Delete specific raffle by index (list starts at 0)")
    respond("   ;TRAFFLE CSV            - Export raffles to data/raffle.csv")
    respond("   ;TRAFFLE WIKI           - Output raffles in MediaWiki format")
    respond("   ;TRAFFLE TOWNCRIER      - Post raffles to TownCrier")
    respond("   ;TRAFFLE BUY            - Auto-purchase tickets for all tracked raffles")
    respond("   ;TRAFFLE HELP           - Show this help")
    respond("")
    respond("   To enable debug output:")
    respond("     ;e Vars[\"traffle\"] = {debug_my_script = true}")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local raffles = prune_old(load_raffles())
dbg("Initial raffle count after pruning: " .. #raffles)

before_dying(function()
    save_raffles(raffles)
end)

-- Silence output unless debug mode is on (matches Lich5 CLI behaviour)
if not is_debug() then silence_me() end

-- Parse args (Lich5 style: Script.vars[0] = full string, [1] = first token, ...)
local args    = Script.vars
local cmd     = string.lower(args[1] or "")

if cmd == "clear" then
    raffles = {}
    save_raffles(raffles)
    respond("Raffle entries have been cleared.")

elseif cmd == "delete" then
    local idx = tonumber(args[2])
    if idx and idx >= 0 and idx < #raffles then
        table.remove(raffles, idx + 1)
        save_raffles(raffles)
        respond("Deleted raffle #" .. tostring(idx))
    else
        respond("Invalid index. Use ;traffle list to see indices (enable debug for numbered list).")
    end

elseif cmd == "help" then
    show_help()

elseif cmd == "find" then
    cmd_find(raffles, args[2])

elseif cmd == "csv" then
    respond(format_csv(raffles))

elseif cmd == "wiki" then
    respond(format_wiki(raffles))

elseif cmd == "towncrier" then
    cmd_towncrier(raffles)

elseif cmd == "buy" then
    cmd_buy(raffles)

elseif cmd == "list" or cmd == "view" then
    display_list(raffles, false)

elseif cmd == "reverse" then
    display_list(raffles, true)

else
    -- Default (empty or unrecognised): scan current room, then display
    raffles = cmd_scan(raffles)
    save_raffles(raffles)
    display_list(raffles, false)
end
