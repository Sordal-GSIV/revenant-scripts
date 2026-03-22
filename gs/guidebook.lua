--- @revenant-script
--- name: guidebook
--- version: 1.0.8
--- author: elanthia-online
--- contributors: Tysong
--- game: gs
--- description: EG Guidebook Companion — friendly formatted merchant/raffle display with clickable go2/whisper links
--- tags: eg,ebon gate,guidebook,merchant,raffle
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;guidebook                        show merchants and raffles
---   ;guidebook m[erchant]             show only merchants
---   ;guidebook r[affle]               show only raffles
---   ;guidebook w[hisper]              show all, use guidebook whisper command instead of go2
---   ;guidebook m[erchant] w[hisper]   show only merchants, use whisper navigation
---   ;guidebook r[affle] w[hisper]     show only raffles, use whisper navigation
---   ;guidebook help                   show this help
---
--- Requires guidebook on character, readable, flipped to Chapter 14 (Epilogue).
---
--- changelog:
---   1.0.8 (2025-10-17) Added whisper navigation and RealID matching from source XML links
---   1.0.7 (2025-10-17) RealID# matching from original source XML links
---   1.0.6 (2025-10-17) Regex updates, merchant name in raffle output
---   1.0.5 (2022-10-18) Regex updates
---   1.0.4 (2022-10-18) Error handling, go2 display improvements
---   1.0.3 (2022-10-18) Guidebook not on epilogue handling
---   1.0.2 (2022-10-18) Go2 links, totals, raffle line breaks
---   1.0.1 (2022-10-17) Regex updates
---   1.0.0 (2022-10-17) Initial release

local TableRender = require("lib/table_render")
local Messaging   = require("lib/messaging")

-- ---------------------------------------------------------------------------
-- quiet_command_xml: send a command, suppress its output from the frontend,
-- and return the raw XML lines between the <output class="mono"/> start marker
-- and the next <prompt. Equivalent to Lich5's Lich::Util.quiet_command_xml.
-- ---------------------------------------------------------------------------
local function quiet_command_xml(command, timeout_secs)
    timeout_secs = timeout_secs or 5
    local hook_name = "guidebook_qcx_" .. Script.name .. "_" .. tostring(math.random(1000000))
    local hook_capturing = false

    -- Hook: suppress captured output from reaching the frontend
    DownstreamHook.add(hook_name, function(line)
        if hook_capturing then
            if line:find("<prompt") then
                hook_capturing = false
                DownstreamHook.remove(hook_name)
            end
            return nil  -- squelch
        end
        if line:find('<output class="mono"') or line:find("You can't do that") then
            hook_capturing = true
            return nil  -- squelch start marker
        end
        return line
    end)

    clear()  -- drain stale lines from script buffer
    put(command)

    -- Collect lines via get_noblock loop
    local captured = {}
    local elapsed  = 0
    local started  = false

    while elapsed < timeout_secs do
        local line = get_noblock()
        if line then
            if not started then
                -- Wait for the start marker
                if line:find('<output class="mono"') or line:find("You can't do that") then
                    started = true
                    table.insert(captured, line)  -- include for "can't do that" detection
                end
                -- Ignore pre-command output
            else
                if line:find("<prompt") then
                    break  -- done
                end
                table.insert(captured, line)
            end
        else
            pause(0.05)
            elapsed = elapsed + 0.05
        end
    end

    DownstreamHook.remove(hook_name)
    return captured
end

-- ---------------------------------------------------------------------------
-- Hardcoded room overrides (matches Lich5 source)
-- ---------------------------------------------------------------------------
local ROOM_OVERRIDES = {
    ["Flightless Dragonfly"] = 8084542,
}

-- ---------------------------------------------------------------------------
-- find_room_by_title_and_uid: given a uid (real_id) and room title string,
-- find the best room UID to use in go2 links.  Mirrors Lich5 logic exactly:
--   1. Hardcoded override table
--   2. Check rooms from Map.ids_from_uid(uid) for title match
--   3. Check wayto neighbors of those rooms
--   4. Full map scan
--   5. Fall back to original uid
-- ---------------------------------------------------------------------------
local function find_room_by_title_and_uid(uid, title)
    if ROOM_OVERRIDES[title] then
        return ROOM_OVERRIDES[title]
    end

    local room_ids = Map.ids_from_uid(uid)
    if room_ids and #room_ids > 0 then
        local first = Map.find_room(room_ids[1])
        if first then
            -- Check the room itself
            if first.title and first.title:lower():find(title:lower(), 1, true) then
                return uid
            end
            -- Check wayto neighbors
            if first.wayto then
                for neighbor_id_str, _ in pairs(first.wayto) do
                    local neighbor = Map.find_room(tonumber(neighbor_id_str))
                    if neighbor and neighbor.title and
                       neighbor.title:lower():find(title:lower(), 1, true) then
                        if neighbor.uid then
                            local nu = type(neighbor.uid) == "table"
                                and neighbor.uid[1] or neighbor.uid
                            return nu
                        end
                        return neighbor.id
                    end
                end
            end
        end
    end

    -- Full map scan
    local all_ids = Map.list()
    if all_ids then
        for _, room_id in ipairs(all_ids) do
            local room = Map.find_room(room_id)
            if room and room.title and
               room.title:lower():find(title:lower(), 1, true) then
                if room.uid then
                    local ru = type(room.uid) == "table" and room.uid[1] or room.uid
                    return ru
                end
                return room.id
            end
        end
    end

    return uid
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Wrap text at width, returning segments joined by \n (like Ruby's scan(/.{1,N}/).join("\n"))
local function wrap_text(text, width)
    if not text or text == "" then return "" end
    width = width or 90
    local parts = {}
    local i = 1
    while i <= #text do
        table.insert(parts, text:sub(i, i + width - 1))
        i = i + width
    end
    return table.concat(parts, "\n")
end

-- Parse "MM/DD/YYYY HH:MM:SS" → unix timestamp (for sorting)
local function parse_datetime(dt_str)
    if not dt_str then return 0 end
    local mo, dy, yr, hh, mm, ss =
        dt_str:match("(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+)")
    if not mo then return 0 end
    return os.time({
        year  = tonumber(yr),
        month = tonumber(mo),
        day   = tonumber(dy),
        hour  = tonumber(hh),
        min   = tonumber(mm),
        sec   = tonumber(ss),
    })
end

-- Format unix timestamp as "MM/DD/YYYY HH:MM AM/PM"
local function format_datetime(ts)
    return os.date("%m/%d/%Y %I:%M %p", ts)
end

-- Safe literal string replacement (avoids gsub pattern magic)
local function str_replace_once(s, plain, repl)
    local pos = s:find(plain, 1, true)
    if not pos then return s end
    return s:sub(1, pos - 1) .. repl .. s:sub(pos + #plain)
end

-- Return an XML bold-wrapped string (for embedding in table content)
local function bold_str(text)
    return "<pushBold/>" .. text .. "<popBold/>"
end

-- Build a clickable go2/whisper link string for use in table cells.
-- display_text is plain ASCII (no XML), so we also build the post-render map.
local function make_link(display_text, cmd)
    return '<d cmd="' .. Messaging.xml_encode(cmd) .. '">'
        .. bold_str(display_text)
        .. '</d>'
end

-- ---------------------------------------------------------------------------
-- parse_guidebook: read guidebook and extract merchant/raffle data.
-- Returns merchants table, raffles table (raffles sorted by datetime).
-- ---------------------------------------------------------------------------
local function parse_guidebook()
    local output = quiet_command_xml("read guidebook", 5)

    if not output or #output == 0 then
        respond("Could not read guidebook — no output received.")
        return nil, nil
    end

    local full_text = table.concat(output, "\n")

    if full_text:find("You can't do that") then
        respond("You need to have an EG guidebook on your character in a readable container.")
        respond("Also please have the guidebook flipped to Chapter 14, the epilogue.")
        return nil, nil
    end

    if not full_text:find("Epilogue") then
        respond("Guidebook not on the epilogue page. Flip to Chapter 14.")
        return nil, nil
    end

    -- Merchant line format (raw XML from game):
    -- #N  Name   Room   <d cmd='whisper my guidebook service N N REAL_ID'>[Shop Entrance] </d>DETAILS
    local re_merchant = Regex.new(
        [=[#\d+\s+([\w\s,'.]+?)\s{2,}([\w\s,'.-]+?)\s{2,}<d cmd='whisper my guidebook service \d+ \d+ (\d+)'>\[Shop Entrance\] <\/d>(.*)]=]
    )

    -- Raffle line format (raw XML from game):
    -- #N  Name  Room  MM/DD/YYYY HH:MM:SS ZONE  COST UNIT  <d cmd='whisper my guidebook raffle N N REAL_ID'>
    local re_raffle = Regex.new(
        [=[#\d+\s+(\w+)\s+([\w\s,'.-]+?)\s+(\d+/\d+/\d+ \d+:\d+:\d+) \w+\s+([\d,]+) \w+ \s+<d cmd='whisper my guidebook raffle \d+ \d+ (\d+)'>]=]
    )

    local merchants = {}
    local raffles   = {}

    for i, line in ipairs(output) do
        local m = re_merchant:captures(line)
        if m then
            table.insert(merchants, {
                name    = m[1]:match("^%s*(.-)%s*$"),
                room    = m[2]:match("^%s*(.-)%s*$"),
                real_id = tonumber(m[3]),
                details = m[4] or "",
            })
        else
            local r = re_raffle:captures(line)
            if r then
                local ts = parse_datetime(r[3])
                table.insert(raffles, {
                    name        = r[1],
                    room        = r[2]:match("^%s*(.-)%s*$"),
                    datetime    = ts,
                    cost        = r[4],
                    real_id     = tonumber(r[5]),
                    description = output[i + 1] or "",
                })
            end
        end
    end

    -- Sort raffles chronologically (matches Lich5's sort_by datetime)
    table.sort(raffles, function(a, b) return a.datetime < b.datetime end)

    return merchants, raffles
end

-- ---------------------------------------------------------------------------
-- bold_header: given a rendered table string, bold the header row content.
-- The header is always line 2 (border / header / border / ...).
-- ---------------------------------------------------------------------------
local function bold_header(rendered)
    local lines = {}
    for line in (rendered .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    if lines[2] then
        local inner = lines[2]:match("^|(.+)|$")
        if inner then
            lines[2] = "|" .. bold_str(inner) .. "|"
        end
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- show_merchants
-- ---------------------------------------------------------------------------
local function show_merchants(merchants, use_whisper)
    if not merchants or #merchants == 0 then
        respond("No merchants working currently!")
        return
    end

    local tbl          = TableRender.new({"Merchant", "Room", "Go2"})
    local go2_map      = {}  -- plain_display → xml_link (for post-render substitution)

    for _, m in ipairs(merchants) do
        local uid     = find_room_by_title_and_uid(m.real_id, m.room)
        local display = "u" .. tostring(uid)
        local cmd
        if use_whisper then
            cmd = "whisper my guidebook service 1 999 " .. tostring(m.real_id)
        else
            cmd = ";go2 " .. display
        end
        go2_map[display] = make_link(display, cmd)

        tbl:add_row({m.name, m.room, display})

        local details = m.details and m.details:match("^%s*(.-)%s*$") or ""
        if details ~= "" then
            tbl:add_full_row(wrap_text(details, 90))
        end
        tbl:add_separator()
    end
    tbl:add_full_row("Total of " .. #merchants .. " Merchant(s)")

    local rendered = bold_header(tbl:render())
    for plain, linked in pairs(go2_map) do
        rendered = str_replace_once(rendered, plain, linked)
    end

    _respond('<output class="mono"/>\n' .. rendered .. '\n<output class=""/>')
end

-- ---------------------------------------------------------------------------
-- show_raffles
-- ---------------------------------------------------------------------------
local function show_raffles(raffles, use_whisper)
    if not raffles or #raffles == 0 then
        respond("No raffles currently!")
        return
    end

    local tbl     = TableRender.new({"Merchant", "Room", "Go2", "DateTime", "Cost"})
    local go2_map = {}

    for _, r in ipairs(raffles) do
        local uid     = find_room_by_title_and_uid(r.real_id, r.room)
        local display = "u" .. tostring(uid)
        local cmd
        if use_whisper then
            cmd = "whisper my guidebook raffle 1 999 " .. tostring(r.real_id)
        else
            cmd = ";go2 " .. display
        end
        go2_map[display] = make_link(display, cmd)

        tbl:add_row({r.name, r.room, display, format_datetime(r.datetime), r.cost})

        local desc = r.description and r.description:match("^%s*(.-)%s*$") or ""
        if desc ~= "" then
            tbl:add_full_row(wrap_text(desc, 90))
        end
        tbl:add_separator()
    end
    tbl:add_full_row("Total of " .. #raffles .. " Raffle(s)")

    local rendered = bold_header(tbl:render())
    for plain, linked in pairs(go2_map) do
        rendered = str_replace_once(rendered, plain, linked)
    end

    _respond('<output class="mono"/>\n' .. rendered .. '\n<output class=""/>')
end

-- ---------------------------------------------------------------------------
-- show_help
-- ---------------------------------------------------------------------------
local function show_help()
    respond("EG Guidebook Companion")
    respond("")
    respond("  ;guidebook                        show merchants and raffles")
    respond("  ;guidebook m[erchant]             show only merchants")
    respond("  ;guidebook r[affle]               show only raffles")
    respond("  ;guidebook w[hisper]              show all, use whisper navigation")
    respond("  ;guidebook m[erchant] w[hisper]   show only merchants, use whisper navigation")
    respond("  ;guidebook r[affle] w[hisper]     show only raffles, use whisper navigation")
    respond("  ;guidebook help                   show this help")
    respond("")
    respond("Requires guidebook on character in a readable container, flipped to Chapter 14 (Epilogue).")
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------
local arg1 = Script.vars[1] and Script.vars[1]:lower() or ""
local arg2 = Script.vars[2] and Script.vars[2]:lower() or ""

if arg1 == "help" then
    show_help()
    return
end

-- Whisper flag: either arg triggers it
local use_whisper = arg1:match("^w") ~= nil or arg2:match("^w") ~= nil

-- Show flags: whisper alone → show both; m → only merchants; r → only raffles
local show_m = not arg1:match("^r")
local show_r = not arg1:match("^m")
if arg1:match("^w") then
    show_m = true
    show_r = true
end

local merchants, raffles = parse_guidebook()
if not merchants and not raffles then return end

if show_m then show_merchants(merchants, use_whisper) end
if show_r then show_raffles(raffles, use_whisper) end
