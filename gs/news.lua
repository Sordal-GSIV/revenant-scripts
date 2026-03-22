--- @revenant-script
--- name: news
--- version: 1.5.0
--- author: unknown
--- game: gs
--- description: Fetches daily GemStone IV events from the TownCrier RSS feed
--- tags: towncrier, events, news, rss
--- @lic-source: news.lic
--- @lic-certified: complete 2026-03-20

local TOWNCRIER_FEED = "https://gstowncrier.com/category/news/feed/"
local INFO_LINK      = "https://gstowncrier.com/author/newsby/"

-- Full PCRE equivalent of the Ruby scan regex from news.lic (line 50).
-- Matches time-prefixed event lines: keywords or H:MM(am/pm) ranges, followed by text.
local EVENT_RE = Regex.new(
    "((?:Today|Remember|All Day|24/7|Noon|til Sundown|Midnight" ..
    "|\\d{1,2}(?::\\d{2})?(?:am|pm)?(?:-(?:\\d{1,2}(?::\\d{2})?(?:am|pm)?" ..
    "|CANCELED|Today|Remember|Midnight|Noon))?): .*)"
)

local function fetch_rss_feed()
    local resp, err = Http.get(TOWNCRIER_FEED)
    if resp and resp.body then
        return resp.body
    end
    respond("Error fetching RSS feed: " .. (err or "unknown error"))
    return nil
end

local function extract_today_events(xml_data)
    if not xml_data then
        return {"No events found."}, "Unknown Date"
    end

    -- Extract first <item> title
    local title = xml_data:match("<item>.-<title>(.-)</title>")
    if not title then
        return {"No events found."}, "Unknown Date"
    end

    -- Decode CDATA wrapper
    title = title:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")

    -- Extract date from title ("Happening Today: <date> in GemStone IV")
    local display_date = title:match("Happening Today: (.+) in GemStone IV") or "Unknown Date"

    -- Extract description from first <item>
    local description = xml_data:match("<item>.-<description>(.-)</description>")
    if not description then
        return {"No events found."}, display_date
    end

    -- Decode CDATA / HTML entities
    description = description:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
    description = description:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")

    -- Strip HTML tags
    description = description:gsub("</?[^>]+>", "")

    -- Extract event lines using PCRE (matches the full time-prefixed event pattern)
    local events = {}
    for _, m in ipairs(EVENT_RE:find_all(description)) do
        local line = m[1]:match("^%s*(.-)%s*$")
        if line and #line > 0 then
            events[#events + 1] = line
        end
    end

    -- Fallback: keyword-anchored line-by-line scan
    if #events == 0 then
        for line in description:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 then
                if trimmed:match("^%d") or trimmed:match("^Today") or trimmed:match("^Remember")
                    or trimmed:match("^All Day") or trimmed:match("^Noon") or trimmed:match("^Midnight")
                    or trimmed:match("^til Sundown") or trimmed:match("^24/7") then
                    events[#events + 1] = trimmed
                end
            end
        end
    end

    if #events == 0 then
        return {"No events found."}, display_date
    end

    return events, display_date
end

local function show_gui(events, display_date)
    local win = Gui.window("TownCrier Events", { width = 500, height = 420, resizable = true })
    win:on_close(function() win = nil end)

    local root = Gui.vbox()
    root:add(Gui.section_header("Events for: " .. display_date))
    root:add(Gui.separator())

    for _, event in ipairs(events) do
        root:add(Gui.label(event))
    end

    root:add(Gui.separator())
    root:add(Gui.label("All times are Eastern."))
    root:add(Gui.label("For more information: " .. INFO_LINK))

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

-- Main
respond("Fetching TownCrier events...")
local xml_data = fetch_rss_feed()
local events, display_date = extract_today_events(xml_data)

respond("------------------------------------")
respond("Events for: " .. display_date)
respond("------------------------------------")
for _, event in ipairs(events) do
    respond(event)
end
respond("------------------------------------")
respond("All times are Eastern.")
respond("For more information, visit: " .. INFO_LINK)

show_gui(events, display_date)
