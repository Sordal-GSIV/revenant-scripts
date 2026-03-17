--- @revenant-script
--- name: traffle
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Cait
--- game: gs
--- description: Raffle ticket tracking, listing, and management at festival events
--- tags: raffle,raffles,festival,event
---
--- Changelog (from Lich5):
---   v2.0.0 (2025-10-18): Complete OO refactor, YAML storage replaced with JSON
---   v1.x: Original Cait script
---
--- Usage:
---   ;traffle                - Scan current room for raffle tables
---   ;traffle list           - Show known raffles
---   ;traffle reverse        - Show raffles in reverse order
---   ;traffle find <term>    - Search known raffles
---   ;traffle clear          - Clear all tracked raffles
---   ;traffle delete <#>     - Delete a specific raffle by index
---   ;traffle help           - Show help

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DATA_FILE = "data/traffle.json"
local LOOK_ON_EXCLUSIONS = {
    disk = true, sign = true, list = true, kitten = true, cat = true,
    spirit = true, falcon = true, placard = true, rat = true, wolf = true,
    raven = true, figure = true, hamster = true,
}
local TIME_LIMIT = 15  -- minutes after completion before pruning

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function with_commas(num)
    local s = tostring(num)
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
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Data persistence
--------------------------------------------------------------------------------

local function load_raffles()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function save_raffles(raffles)
    File.write(DATA_FILE, Json.encode(raffles))
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
    return result
end

--------------------------------------------------------------------------------
-- Room scanning
--------------------------------------------------------------------------------

local function scan_room_objects()
    -- Use XML mode to find room objects with raffle tables
    local room_objs = {}
    local line = dothistimeout("look", 1, "exist=")
    if line then
        local id_re = Regex.new('exist="([^"]+)" noun="([^"]+)">([^<]+)<')
        local matches = id_re:match_all(line)
        if matches then
            for _, m in ipairs(matches) do
                if not LOOK_ON_EXCLUSIONS[m[2]] then
                    table.insert(room_objs, { id = m[1], noun = m[2], desc = m[3] })
                end
            end
        end
    end
    return room_objs
end

local function find_raffle_tickets(room_objs)
    local raffles = {}
    for _, obj in ipairs(room_objs) do
        local line = dothistimeout("look on #" .. obj.id, 1,
            'noun="tickets"|There is nothing on there|There is nothing on the')
        if line and string.find(line, 'noun="tickets"') then
            local re = Regex.new('exist="(%d+)" noun="tickets">([%w%s]+)<')
            local matches = re:match_all(line)
            if matches then
                for _, m in ipairs(matches) do
                    table.insert(raffles, { id = m[1], desc = m[2], table_desc = obj.desc })
                end
            end
        end
    end
    return raffles
end

local function parse_raffle_info(raffle_id)
    local info = { item = nil, cost = nil, timeleft = 0, winners = nil }

    fput("look at #" .. raffle_id)

    local deadline = os.time() + 5
    while os.time() < deadline do
        local line = get()
        if not line then
            pause(0.05)
            goto continue
        end

        -- Winner count
        local w = string.match(line, "The drawing will be in .* for (.+) winners?%.")
        if w then info.winners = w end

        -- Full date format
        local tickets, date_str = string.match(line,
            "The drawing for (%d+) winners? will be in .* %(at (.-)%)%.")
        if tickets then
            info.winners = tickets
            -- Parse approximate time from date
            info.timeleft = 3600  -- default 1 hour if can't parse
            break
        end

        -- Simple time formats
        local mins = string.match(line, "The drawing will be in (%d+) minutes?")
        if mins then
            info.timeleft = info.timeleft + tonumber(mins) * 60
            break
        end
        local hrs, mins2 = string.match(line, "The drawing will be in (%d+) hours? and (%d+) minutes?")
        if hrs then
            info.timeleft = info.timeleft + tonumber(hrs) * 3600 + tonumber(mins2) * 60
            break
        end

        -- Item description
        local item = string.match(line, "^The raffle is for (.+)")
            or string.match(line, "^Raffle for (.+)")
            or string.match(line, "^This raffle is (.+)")
            or string.match(line, "raffle will receive (.+)")
            or string.match(line, "winner will receive (.+)")
        if item then info.item = item end

        -- Cost
        local cost = string.match(line, "The tickets? sell for (.+) silvers each%.")
            or string.match(line, "The tickets? sell for (.+) %w+ each%.")
        if cost then info.cost = string.gsub(cost, ",", "") end

        -- Drawing has ended
        if string.find(line, "I could not find what you were referring to")
            or string.find(line, "The drawing has been held") then
            info.timeleft = 0
            break
        end

        ::continue::
    end
    return info
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function display_list(raffles, reverse)
    if #raffles == 0 then
        respond("No raffles being tracked. Run this script while at a raffle table!")
        respond("Completed raffles are removed after " .. TIME_LIMIT .. " minutes.")
        return
    end

    local ordered = {}
    for i, r in ipairs(raffles) do ordered[i] = r end
    if reverse then
        local rev = {}
        for i = #ordered, 1, -1 do table.insert(rev, ordered[i]) end
        ordered = rev
    end

    respond("================")
    for _, raffle in ipairs(ordered) do
        local remaining = (raffle.draw_time or 0) - os.time()
        local time_str = remaining > 0 and format_time_remaining(remaining) or "COMPLETED"

        respond("")
        respond(os.date("%A, %B %d, %Y at %I:%M %p", raffle.draw_time or 0) .. " (" .. time_str .. " remaining)")
        respond(raffle.room_name or "Unknown Room")
        respond("Ticket cost: " .. with_commas(raffle.cost or 0) .. " silvers | Winners: " .. tostring(raffle.winners or "?"))
        respond("Located On: " .. tostring(raffle.table_description or ""))
        respond(tostring(raffle.description or ""))
    end
    respond("================")
    respond(" " .. #raffles .. " Total Raffles")
    respond("================")
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function cmd_scan(raffles)
    local room_name = checkroom()
    local room_id = Room.id

    local room_objs = scan_room_objects()
    local found = find_raffle_tickets(room_objs)
    pause(0.5)

    for _, rf in ipairs(found) do
        local info = parse_raffle_info(rf.id)
        if info.item and info.timeleft > 0 then
            local draw_time = os.time() + info.timeleft

            -- Remove duplicates
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
                draw_time = draw_time,
                description = info.item,
                room_name = room_name,
                room_id = room_id,
                cost = info.cost,
                winners = info.winners,
                table_description = rf.table_desc,
            })
        end
    end

    -- Sort by time
    table.sort(raffles, function(a, b) return (a.draw_time or 0) < (b.draw_time or 0) end)
    save_raffles(raffles)
    return raffles
end

local function cmd_find(raffles, term)
    if not term or term == "" then
        respond("Usage: ;traffle find <term>")
        return
    end
    local found = {}
    for _, r in ipairs(raffles) do
        if string.find(string.lower(r.description or ""), string.lower(term), 1, true)
            or string.find(string.lower(r.room_name or ""), string.lower(term), 1, true) then
            table.insert(found, r)
        end
    end
    display_list(found, false)
end

local function show_help()
    respond("Type ;traffle at a raffle table to keep track of the raffle")
    respond("")
    respond("   ;traffle                - Scan room for raffle tables")
    respond("   ;traffle list           - Show known raffles")
    respond("   ;traffle reverse        - Show raffles in reverse order")
    respond("   ;traffle find <term>    - Search known raffles")
    respond("   ;traffle clear          - Clear all tracked raffles")
    respond("   ;traffle delete <#>     - Delete specific raffle by index (0-based)")
    respond("   ;traffle help           - This help")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local raffles = prune_old(load_raffles())

before_dying(function()
    save_raffles(raffles)
end)

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

local cmd = args[1] and string.lower(args[1]) or ""

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
        respond("Invalid index.")
    end
elseif cmd == "help" then
    show_help()
elseif cmd == "find" then
    cmd_find(raffles, args[2])
elseif cmd == "list" or cmd == "view" then
    display_list(raffles, false)
elseif cmd == "reverse" then
    display_list(raffles, true)
else
    -- Default: scan room
    raffles = cmd_scan(raffles)
    save_raffles(raffles)
    display_list(raffles, false)
end
