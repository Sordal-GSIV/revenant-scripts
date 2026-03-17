--- @revenant-script
--- name: news
--- version: 1.4.0
--- author: unknown
--- game: gs
--- description: Fetches daily GemStone IV events from the TownCrier RSS feed
--- tags: towncrier, events, news, rss

local TOWNCRIER_FEED = "https://gstowncrier.com/category/news/feed/"
local INFO_LINK      = "https://gstowncrier.com/author/newsby/"

local function fetch_rss_feed()
    local ok, result = pcall(Http.get, TOWNCRIER_FEED)
    if ok and result and result.body then
        return result.body
    end
    respond("Error fetching RSS feed.")
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

    -- Extract date from title
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

    -- Extract event lines (times followed by descriptions)
    local events = {}
    for event in description:gmatch("((?:Today|Remember|All Day|24/7|Noon|til Sundown|Midnight|%d%d?:?%d*[ap]?m?)[^\n]*[^\n]+)") do
        table.insert(events, event)
    end

    -- Fallback: try simpler line-by-line extraction
    if #events == 0 then
        for line in description:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 then
                if trimmed:match("^%d") or trimmed:match("^Today") or trimmed:match("^Remember")
                    or trimmed:match("^All Day") or trimmed:match("^Noon") or trimmed:match("^Midnight")
                    or trimmed:match("^til Sundown") or trimmed:match("^24/7") then
                    table.insert(events, trimmed)
                end
            end
        end
    end

    if #events == 0 then
        return {"No events found."}, display_date
    end

    return events, display_date
end

-- Main
respond("Fetching TownCrier events...")
local xml_data = fetch_rss_feed()
local events, display_date = extract_today_events(xml_data)

respond("------------------------------------")
respond("Events for: " .. display_date)
respond("------------------------------------")
for _, event in ipairs(events) do
    respond(event:match("^%s*(.-)%s*$"))
end
respond("------------------------------------")
respond("All times are Eastern.")
respond("For more information, visit: " .. INFO_LINK)
