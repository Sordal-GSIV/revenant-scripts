--- @revenant-script
--- name: dr_autovote
--- version: 1.0
--- author: Drafix/Crannach
--- game: dr
--- description: Auto-vote for DR at topmudsites.com every 13 hours.
--- tags: voting, automated
--- Converted from dr-autovote.lic
---
--- Usage:
---   ;dr_autovote         - Start voting loop (votes every 13 hours)
---   ;dr_autovote clear   - Reset vote timer and vote immediately
---   ;dr_autovote test    - Test vote form retrieval (dry run)
---
--- NOTE: This script requires HTTP support. The original Ruby version used
--- net/http to POST vote forms to topmudsites.com. In Revenant, this uses
--- the http module if available.

-- Check for HTTP support
local http_available, http = pcall(require, "http")
if not http_available then
    echo("ERROR: HTTP support is not available in the current Revenant build.")
    echo("This script requires net/http equivalent to vote on topmudsites.com.")
    echo("The script cannot function without HTTP. Exiting.")
    return
end

hide_me()
Script.want_downstream = false

local vote_interval = 46800  -- 13 hours in seconds
local last_vote_time = CharSettings["last_vote_time"] or (os.time() - vote_interval)
local form_data = {}

local vote_page_path = "/vote-DragonRealms.html"
local vote_host = "www.topmudsites.com"
local vote_post_path = "/vote.php"

local headers_list = {
    {
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Accept-Encoding"] = "gzip, deflate",
        ["Accept-Language"] = "en-US,en;q=0.5",
        ["Connection"] = "keep-alive",
        ["Referer"] = "http://www.topmudsites.com/vote-DragonRealms.html",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 6.3; WOW64; rv:31.0) Gecko/20100101 Firefox/31.0",
    },
    {
        ["Connection"] = "keep-alive",
        ["Cache-Control"] = "max-age=0",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        ["Origin"] = "http://www.topmudsites.com",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.143 Safari/537.36",
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Referer"] = "http://www.topmudsites.com/vote-DragonRealms.html",
        ["Accept-Encoding"] = "gzip,deflate,sdch",
        ["Accept-Language"] = "en-US,en;q=0.8",
    },
    {
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        ["Accept-Encoding"] = "gzip,deflate",
        ["Accept-Language"] = "en-US,en;q=0.8",
        ["Cache-Control"] = "max-age=0",
        ["Connection"] = "keep-alive",
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Origin"] = "http://www.topmudsites.com",
        ["Referer"] = "http://www.topmudsites.com/vote-DragonRealms.html",
        ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.94 Safari/537.36",
    },
}

--- Parse hidden form fields from the vote page HTML
local function parse_form_fields(html_text)
    form_data = {}
    for line in html_text:gmatch("[^\n]+") do
        if line:find("<input") and line:find('type="hidden"') then
            local name = line:match('name="([^"]+)"')
            local value = line:match('value="([^"]+)"')
            if name and value then
                form_data[name] = value
            end
        end
    end
    return form_data
end

--- Fetch form data from the vote page
local function fetch_vote_page()
    local ok, text = pcall(http.get, "http://" .. vote_host .. vote_page_path)
    if not ok or not text then
        echo("ERROR: Could not fetch vote page.")
        return false
    end
    parse_form_fields(text)
    return true
end

--- Test vote (dry run) - fetch and display form fields
local function testvote()
    if not fetch_vote_page() then return end
    echo("Form data found:")
    for k, v in pairs(form_data) do
        echo("  " .. k .. " = " .. v)
    end
end

--- Submit the vote
local function do_vote()
    if not fetch_vote_page() then return end
    echo("Form data:")
    for k, v in pairs(form_data) do
        echo("  " .. k .. " = " .. v)
    end

    local chosen_headers = headers_list[math.random(#headers_list)]
    local ok, res = pcall(http.post, "http://" .. vote_host .. vote_post_path, form_data, chosen_headers)
    if ok and res then
        echo("Voted Successfully!")
    else
        echo("Error: Vote submission failed.")
    end
end

--- Format seconds as HH:MM:SS
local function format_time(seconds)
    if seconds < 0 then seconds = 0 end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Handle command-line arguments
if Script.vars[1] == "clear" then
    last_vote_time = os.time() - vote_interval
    CharSettings["last_vote_time"] = last_vote_time
    echo("Vote timer cleared - will vote on next cycle.")
elseif Script.vars[1] == "test" then
    testvote()
    return
end

-- Main voting loop
while true do
    local wait_time = last_vote_time + vote_interval - os.time()
    if wait_time > 0 then
        echo("Waiting " .. format_time(wait_time) .. " to vote again")
    end
    local sleep_time = math.max(wait_time, 1)
    pause(sleep_time)

    last_vote_time = os.time()
    CharSettings["last_vote_time"] = last_vote_time
    echo("Voting...")
    do_vote()
    echo("Finished, waiting 13 hours before voting again.")
end
