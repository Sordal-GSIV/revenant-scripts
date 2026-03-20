--- @revenant-script
--- name: blue_tracker
--- version: 1.1.0
--- author: Nisugi
--- game: gs
--- description: Fetch and display recent GM posts from the Gemstone Discord via blue-tracker API
--- tags: discord,gamemaster,announcements,information
--- @lic-certified: complete 2026-03-19
---
--- Changelog (from Lich5):
---   v1.1.0: Added watch command (SSE live feed), Discord list/quote cleaning, channel names in history header
---   v1.0.1: Fixed nil watcher code, improved channel matching, timestamp fixes
---   v1.0.0: Initial release
---
--- Usage:
---   ;blue_tracker latest [channel]          - Show most recent GM post
---   ;blue_tracker <post_id>                 - Show specific post by ID
---   ;blue_tracker history <channel> [count] - Show recent GM posts (max 50)
---   ;blue_tracker watch <channel> [...]     - Watch channels for new GM posts (or 'all')
---   ;blue_tracker channels                  - Show available channels
---   ;blue_tracker help                      - Show help

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local API_URL = "https://blue-tracker.fly.dev"
local WIDTH = 78
local MAX_WATCH_RETRIES = 5

local CHANNEL_GROUPS = {
    { name = "Announcements", channels = {
        { name = "general",     id = "796618391262986241" },
        { name = "development", id = "796619793934319643" },
        { name = "merchant",    id = "1331041053309931591" },
        { name = "event",       id = "832466682291027998" },
        { name = "endnotes",    id = "1121832778791665716" },
    }},
    { name = "Game Channels", channels = {
        { name = "game_chatter", id = "387270949499830273" },
        { name = "help",         id = "387271714012135425" },
        { name = "prime",        id = "387271313695309824" },
        { name = "premium",      id = "387271364572086272" },
        { name = "platinum",     id = "387271396218241024" },
        { name = "shattered",    id = "387271438081720331" },
        { name = "festivals",    id = "387271681539833858" },
        { name = "roleplaying",  id = "541653031691747329" },
        { name = "mechanics",    id = "532373273816858636" },
        { name = "gemstones",    id = "1271943281613340775" },
    }},
    { name = "Pay Events", channels = {
        { name = "events",        id = "594010837732294735" },
        { name = "duskruin",      id = "594009933763051549" },
        { name = "ebongate",      id = "594009960166457344" },
        { name = "ringsoflumnis", id = "701166110204231733" },
        { name = "rumorwoods",    id = "594009994953883648" },
    }},
}

-- Flattened channel lookup: name → id
local CHANNELS = {}
for _, group in ipairs(CHANNEL_GROUPS) do
    for _, ch in ipairs(group.channels) do
        CHANNELS[string.lower(ch.name)] = ch.id
    end
end

--------------------------------------------------------------------------------
-- HTTP helper
--------------------------------------------------------------------------------

local function api_get(path)
    if not Http then
        respond("BlueTracker error: Http module not available")
        return nil
    end
    local ok, result = pcall(Http.get, API_URL .. path, {
        ["User-Agent"] = "RevenantBlue/1.0",
        ["Accept"] = "application/json",
    })
    if not ok then
        respond("BlueTracker error: " .. tostring(result))
        return nil
    end
    if result.status ~= 200 then
        if result.status ~= 404 then
            respond("BlueTracker error: HTTP " .. tostring(result.status))
        end
        return nil
    end
    local dok, data = pcall(Json.decode, result.body)
    if not dok then
        respond("BlueTracker error: Invalid JSON response")
        return nil
    end
    return data
end

--------------------------------------------------------------------------------
-- Formatter
--------------------------------------------------------------------------------

local function clean_text(text)
    text = text or "(no content)"
    text = string.gsub(text, "\r\n", "\n")
    text = string.gsub(text, "\r", "\n")
    -- Remove Discord reply quotes: "> **Author**: " at start of message
    text = string.gsub(text, "^>%s*%*%*[^*]+%*%*:%s*", "@")
    -- Convert Discord list markers (*, -, •) to bullet
    text = string.gsub(text, "\n[%*%-\xe2\x80\xa2]%s+", "\n\xe2\x80\xa2 ")
    text = string.gsub(text, "^[%*%-]%s+", "\xe2\x80\xa2 ")
    -- Remove bold/italic markdown
    text = string.gsub(text, "%*%*(.-)%*%*", "%1")
    text = string.gsub(text, "%*(.-)%*", "%1")
    -- Remove code blocks
    text = string.gsub(text, "```[^\n]*\n(.-)```", "%1")
    text = string.gsub(text, "`([^`]+)`", "%1")
    -- Remove non-ASCII (keep newlines)
    text = string.gsub(text, "[^\032-\126\n]", "")
    return text
end

local function wrap(text, max)
    local lines = {}
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        if #paragraph == 0 then
            table.insert(lines, "")
        elseif #paragraph <= max then
            table.insert(lines, paragraph)
        else
            local line = ""
            for word in string.gmatch(paragraph, "%S+") do
                if #line + #word + 1 > max then
                    table.insert(lines, line)
                    line = ""
                end
                if #line > 0 then line = line .. " " end
                line = line .. word
            end
            if #line > 0 then table.insert(lines, line) end
        end
    end
    return lines
end

local function truncate(s, max)
    if #s > max then return string.sub(s, 1, max) end
    return s
end

local function horiz(ch)
    ch = ch or "-"
    return "+" .. string.rep(ch, WIDTH - 2) .. "+"
end

local function pad_right(s, w)
    if #s >= w then return string.sub(s, 1, w) end
    return s .. string.rep(" ", w - #s)
end

local function format_card(post, replied_post)
    local timestamp = post.ts or post.timestamp or 0
    local ts = os.date("%Y-%m-%d %H:%M", math.floor(timestamp / 1000))
    local body = clean_text(post.content)
    body = string.match(body, "^%s*(.-)%s*$") or body
    local author = post.author_name or "Unknown"
    local channel = post.channel_name or post.chan_id or ""

    local lines = {}
    table.insert(lines, horiz())
    table.insert(lines, "| Author: " .. pad_right(truncate(author, 22), 22) ..
        "  Date: " .. pad_right(ts, 37) .. " |")
    table.insert(lines, "| PostID: " .. pad_right(tostring(post.id or ""), 22) ..
        "  Channel: " .. pad_right(truncate(channel, 34), 34) .. " |")

    if replied_post then
        table.insert(lines, horiz("="))
        local ra = truncate(replied_post.author_name or "Unknown", 30)
        local rid = tostring(replied_post.id or replied_post.reply_to_id or "")
        table.insert(lines, "| Replying to: " .. pad_right(ra, 30) ..
            " (ID: " .. pad_right(rid, 19) .. ")      |")
        table.insert(lines, horiz("-"))
        local rb = clean_text(replied_post.content or "(no content)")
        rb = string.match(rb, "^%s*(.-)%s*$") or rb
        local rlines = wrap(rb, WIDTH - 4)
        for i = 1, math.min(3, #rlines) do
            table.insert(lines, "| " .. pad_right(rlines[i], WIDTH - 4) .. " |")
        end
        if #rb > 200 then
            table.insert(lines, "| " .. pad_right("[...]", WIDTH - 4) .. " |")
        end
    end

    table.insert(lines, horiz("="))
    for _, ln in ipairs(wrap(body, WIDTH - 4)) do
        table.insert(lines, "| " .. pad_right(ln, WIDTH - 4) .. " |")
    end
    table.insert(lines, horiz())
    return table.concat(lines, "\n")
end

local function format_brief(post)
    local timestamp = post.timestamp or post.ts or 0
    local ts = os.date("%m-%d %H:%M", math.floor(timestamp / 1000))
    local author = post.author_name or "Unknown"
    local body = clean_text(post.content or "")
    body = string.match(body, "^%s*(.-)%s*$") or body
    local max_body = WIDTH - #ts - #truncate(author, 15) - 10
    return string.format("[%s] %s: %s", ts, truncate(author, 15), truncate(body, max_body))
end

--------------------------------------------------------------------------------
-- Channel resolution
--------------------------------------------------------------------------------

local function resolve_channel(arg)
    if not arg then return nil end
    local lower = string.lower(arg)
    if CHANNELS[lower] then return CHANNELS[lower] end
    if string.match(arg, "^%d+$") then return arg end
    return nil
end

local function get_channel_display_name(arg)
    local lower = string.lower(arg)
    for _, group in ipairs(CHANNEL_GROUPS) do
        for _, ch in ipairs(group.channels) do
            if string.lower(ch.name) == lower then
                return arg .. " (" .. group.name .. ")"
            end
        end
    end
    return arg
end

local function show_channels()
    respond("Available channels by category:")
    respond("")
    for _, group in ipairs(CHANNEL_GROUPS) do
        respond(group.name .. ":")
        for _, ch in ipairs(group.channels) do
            respond("  " .. ch.name)
        end
        respond("")
    end
end

local function show_available_channels()
    respond("")
    respond("Available channels:")
    for _, group in ipairs(CHANNEL_GROUPS) do
        local names = {}
        for _, ch in ipairs(group.channels) do
            table.insert(names, ch.name)
        end
        respond("  " .. group.name .. ": " .. table.concat(names, ", "))
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function handle_latest(channel_arg)
    local channel_id = channel_arg and resolve_channel(channel_arg) or nil

    if channel_arg and not channel_id then
        respond("Unknown channel: " .. channel_arg)
        show_available_channels()
        return
    end

    if channel_id then
        local response = api_get("/api/search?channels=" .. channel_id .. "&per_page=1")
        if response and response.results and #response.results > 0 then
            local post_data = response.results[1]
            local post = {
                id          = post_data.id,
                chan_id     = post_data.channel_id,
                ts          = post_data.timestamp,
                content     = post_data.content,
                author_name = post_data.author_name,
                channel_name = post_data.channel,
            }
            respond(format_card(post, post_data.replied_to))
        else
            respond("No GM posts found in channel")
        end
    else
        local posts = api_get("/api/v1/posts?limit=1&order=desc")
        if posts and type(posts) == "table" and #posts > 0 then
            local post = posts[1]
            local replied = nil
            if post.reply_to_id then
                replied = api_get("/api/posts/" .. post.reply_to_id)
            end
            respond(format_card(post, replied))
        else
            respond("No posts found.")
        end
    end
end

local function handle_history(channel_arg, count_str)
    local count = tonumber(count_str) or 1
    if count > 50 then count = 50 end
    if count < 1 then count = 1 end

    local channel_id = resolve_channel(channel_arg)
    if not channel_id then
        respond("Usage: ;blue_tracker history <channel> [count]")
        show_available_channels()
        return
    end

    local response = api_get("/api/search?channels=" .. channel_id .. "&per_page=" .. count)
    if response and response.results and #response.results > 0 then
        local channel_display = get_channel_display_name(channel_arg)
        respond("=== Showing " .. #response.results .. " GM post(s) from " .. channel_display .. " ===")
        for i = #response.results, 1, -1 do
            local post_data = response.results[i]
            local post = {
                id          = post_data.id,
                chan_id     = post_data.channel_id,
                ts          = post_data.timestamp,
                content     = post_data.content,
                author_name = post_data.author_name,
                channel_name = post_data.channel,
            }
            respond(format_card(post, post_data.replied_to))
            if i > 1 then respond("") end
        end
    else
        respond("No GM posts found")
    end
end

local function handle_post_id(post_id)
    local post = api_get("/api/posts/" .. post_id)
    if post then
        local replied = nil
        if post.reply_to_id then
            replied = api_get("/api/posts/" .. post.reply_to_id)
        end
        respond(format_card(post, replied))
    else
        respond("Post not found.")
    end
end

local function handle_watch(args)
    if #args == 0 then
        respond("Usage: ;blue_tracker watch <channel1> [channel2] ... or 'all'")
        show_available_channels()
        return
    end

    if not Http or not Http.stream then
        respond("BlueTracker error: Http.stream not available (requires Revenant engine update)")
        return
    end

    -- Resolve channels
    local watch_all = (#args == 1 and string.lower(args[1]) == "all")
    local channel_ids = nil
    local channel_labels = {}

    if not watch_all then
        channel_ids = {}
        for _, ch in ipairs(args) do
            local id = resolve_channel(ch)
            if id then
                channel_ids[id] = true
                table.insert(channel_labels, get_channel_display_name(ch))
            else
                respond("Unknown channel: " .. ch)
                show_available_channels()
                return
            end
        end
    end

    if watch_all then
        respond("[BlueTracker] Watching ALL channels for GM posts.")
    else
        respond("[BlueTracker] Watching: " .. table.concat(channel_labels, ", "))
    end
    respond("[BlueTracker] Watcher running. Kill this script to stop watching.")

    local retry = 0
    while retry < MAX_WATCH_RETRIES do
        local ok, err = Http.stream(API_URL .. "/stream", function(data_str)
            local dok, event = pcall(Json.decode, data_str)
            if not dok or type(event) ~= "table" then return false end
            if event.type == "keepalive" then return false end

            local show = watch_all or
                (channel_ids and channel_ids[tostring(event.channel_id)])
            if show then
                respond("")
                respond(" New GM post in #" .. tostring(event.channel_name or "unknown") .. "!")
                respond(truncate(tostring(event.author_name or "Unknown"), 20) ..
                    ": " .. truncate(clean_text(tostring(event.content or "")), 60))
                respond("Use ;blue_tracker " .. tostring(event.id) .. " to see full post")
                respond("")
            end
            return false -- keep streaming
        end, {
            ["Accept"]        = "text/event-stream",
            ["Cache-Control"] = "no-cache",
            ["Connection"]    = "keep-alive",
        })

        retry = retry + 1
        if retry < MAX_WATCH_RETRIES then
            local wait = math.min(2 ^ retry, 60)
            respond("[BlueTracker] Connection lost: " .. tostring(err or "disconnected"))
            respond("[BlueTracker] Retrying in " .. wait .. "s (" .. retry .. "/" .. MAX_WATCH_RETRIES .. ")")
            sleep(wait)
        end
    end

    respond("[BlueTracker] Max retries exceeded. Use ;blue_tracker watch to reconnect.")
end

local function show_help()
    respond("BlueTracker Commands:")
    respond("  ;blue_tracker latest [channel]          - Show the most recent GM post")
    respond("  ;blue_tracker <post_id>                 - Show specific post by ID")
    respond("  ;blue_tracker history <channel> [count] - Show recent posts (max 50)")
    respond("  ;blue_tracker watch <channel1> [...]    - Watch channels for new GM posts")
    respond("  ;blue_tracker watch all                 - Watch all channels")
    respond("  ;blue_tracker channels                  - Show all available channels")
    respond("  ;blue_tracker help                      - Show this help")
    respond("")
    respond("Examples:")
    respond("  ;blue_tracker latest")
    respond("  ;blue_tracker latest general")
    respond("  ;blue_tracker 1234567890")
    respond("  ;blue_tracker history development 5")
    respond("  ;blue_tracker watch all")
    respond("  ;blue_tracker watch general development event")
    respond("")
    show_available_channels()
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

local cmd = args[1] and string.lower(args[1]) or "help"
table.remove(args, 1)

if cmd == "latest" then
    handle_latest(args[1])
elseif cmd == "history" then
    handle_history(args[1], args[2])
elseif cmd == "watch" then
    handle_watch(args)
elseif cmd == "channels" then
    show_channels()
elseif cmd == "help" then
    show_help()
elseif string.match(cmd, "^%d+$") then
    handle_post_id(cmd)
else
    show_help()
end
