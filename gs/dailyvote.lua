--- @revenant-script
--- name: dailyvote
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Daily MudVerse voting for GemStone IV with CSRF handling
--- tags: utility,vote
---
--- Original ;autovote by Drafix.
--- Refactored into DailyVote for Revenant.
---
--- Usage:
---   ;dailyvote           start the daily voting loop
---   ;dailyvote test      print IP, timer state, current stats (no vote)
---   ;dailyvote now       force an immediate vote with before/after report
---   ;dailyvote clear     reset the vote timer

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local HOST       = "www.mudverse.com"
local VOTE_PATH  = "/vote/566"
local POST_PATH  = "/"
local STATS_PATH = "/game/566"
local LISTING_ID  = "566"
local LISTING_ID2 = "434"
local VOTE_INTERVAL = 86400  -- 24 hours

local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0"

--------------------------------------------------------------------------------
-- Persistence helpers
--------------------------------------------------------------------------------

local function get_vote_data()
    local raw = Settings.mv_vote_data
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_vote_data(data)
    Settings.mv_vote_data = Json.encode(data)
end

local function external_ip()
    local providers = {
        "https://api.ipify.org/",
        "https://icanhazip.com/",
        "https://checkip.amazonaws.com/",
    }
    for _, url in ipairs(providers) do
        local ok, result = pcall(Http.get, url)
        if ok and result and result.body then
            local ip = result.body:match("^%s*(%d+%.%d+%.%d+%.%d+)%s*$")
            if ip then return ip end
        end
    end
    echo("Warning: all IP providers failed. Using fallback key.")
    return "unknown"
end

local function last_vote_time()
    local data = get_vote_data()
    local ip = external_ip()
    return data[ip] or (os.time() - VOTE_INTERVAL)
end

local function record_vote_time()
    local data = get_vote_data()
    data[external_ip()] = os.time()
    save_vote_data(data)
end

local function seconds_until_next_vote()
    local remaining = last_vote_time() + VOTE_INTERVAL - os.time()
    return remaining > 0 and remaining or 0
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function format_duration(seconds)
    local total = math.floor(seconds)
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60
    return string.format("%02dh %02dm %02ds", hours, minutes, secs)
end

--------------------------------------------------------------------------------
-- HTTP helpers
--------------------------------------------------------------------------------

local function https_get(path)
    local url = "https://" .. HOST .. path
    local result = Http.get(url)
    return result.body or "", ""
end

local function extract_hidden_field(html, field_name)
    -- Try name-before-value
    local pattern1 = '<input[^>]+name="' .. field_name .. '"[^>]+value="([^"]*)"'
    local val = html:match(pattern1)
    if val then return val end
    -- Try value-before-name
    local pattern2 = '<input[^>]+value="([^"]*)"[^>]+name="' .. field_name .. '"'
    return html:match(pattern2)
end

local function fetch_stats()
    local ok, body = pcall(https_get, STATS_PATH)
    if not ok then
        echo("Warning: could not fetch stats")
        return nil, nil
    end

    -- Parse rank and votes from listing summary
    local rank = body:match('<strong>#(%d+)</strong>%s*with%s*<strong>%d')
    local votes = body:match('<strong>#%d+</strong>%s*with%s*<strong>(%d[%d,]*)</strong>%s*votes')
    if votes then votes = votes:gsub(",", "") end
    return rank, votes
end

local function format_stats(rank, votes, label)
    return label .. " - rank: " .. (rank or "(unknown)") .. ", votes: " .. (votes or "(unknown)")
end

--------------------------------------------------------------------------------
-- Vote
--------------------------------------------------------------------------------

local function cast_vote()
    echo("Fetching vote page for CSRF token...")
    local body = https_get(VOTE_PATH)

    local csrf = extract_hidden_field(body, "csrf_token")
    if not csrf then
        echo("Error: csrf_token not found - the site form may have changed.")
        return false
    end

    -- POST the vote
    local post_url = "https://" .. HOST .. POST_PATH
    local form_body = "listing_id=" .. LISTING_ID
        .. "&csrf_token=" .. csrf
        .. "&p=vote"
        .. "&listing_id2=" .. LISTING_ID2
        .. "&submit=Vote"

    local ok, result = pcall(Http.post, post_url, {
        body = form_body,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"] = "https://" .. HOST .. VOTE_PATH,
            ["User-Agent"] = USER_AGENT,
        },
    })

    if ok and result and result.status and result.status < 400 then
        local resp_body = (result.body or ""):lower()
        if resp_body:find("already voted") or resp_body:find("already cast") then
            echo("Vote response: already voted today.")
        end
        return true
    else
        echo("Error during vote POST")
        return false
    end
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

local function run_test()
    local ip = external_ip()
    echo("External IP     : " .. ip)
    echo("Since last vote : " .. format_duration(os.time() - last_vote_time()))
    echo("Until next vote : " .. format_duration(seconds_until_next_vote()))
    local rank, votes = fetch_stats()
    echo("Current rank    : " .. (rank or "(could not parse)"))
    echo("Current votes   : " .. (votes or "(could not parse)"))
end

local function run_clear()
    local data = get_vote_data()
    data[external_ip()] = os.time() - VOTE_INTERVAL
    save_vote_data(data)
    echo("Vote timer cleared - will vote on next loop.")
end

local function run_now()
    echo("Forcing immediate vote...")
    local rank, votes = fetch_stats()
    echo(format_stats(rank, votes, "Before"))

    if cast_vote() then
        record_vote_time()
        echo("Vote submitted!")
        pause(5)
        rank, votes = fetch_stats()
        echo(format_stats(rank, votes, "After"))
    else
        echo("Vote may have failed - check output above.")
    end
end

local function run_loop()
    while true do
        local wait_secs = seconds_until_next_vote()
        if wait_secs > 0 then
            echo("Next vote in " .. format_duration(wait_secs) .. ".")
            pause(wait_secs)
        end

        echo("--- MudVerse DailyVote ---")
        local rank, votes = fetch_stats()
        echo(format_stats(rank, votes, "Before"))

        if cast_vote() then
            record_vote_time()
            echo("Vote cast successfully!")
            pause(5)
            rank, votes = fetch_stats()
            echo(format_stats(rank, votes, "After"))
            echo("Next vote in " .. format_duration(VOTE_INTERVAL) .. ".")
        else
            echo("Vote attempt failed. Retrying in 1 hour.")
            pause(3600)
        end
    end
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 == "test" then
    run_test()
elseif arg1 == "clear" then
    run_clear()
elseif arg1 == "now" then
    run_now()
else
    run_loop()
end
