--- @revenant-script
--- name: help-me
--- version: 1.0.0
--- author: tspivey (original), elanthia-online (port)
--- game: dr
--- description: Gather system/character info and post to pastebin for support purposes
--- tags: utility, support, debug
--- @lic-certified: complete 2026-03-19
---
--- Original: help-me.lic by tspivey
--- Changelog:
---   1.0.0 - Revenant port: Ruby Net::HTTP → Http.post, File API, Version API
---
--- Usage:
---   ;help-me           - Post info to pastebin and echo the URL
---   ;help-me <user>    - Post info and send URL to <user> via lnet private message

local PASTEBIN_TOKEN = 'dca351a27a8af501a8d3123e29af7981'
local PASTEBIN_URL   = 'https://pastebin.com/api/api_post.php'

local user = Script.vars[1]

-- URL-encode a string for form POST bodies
local function url_encode(s)
    return s:gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+")
end

local function submit_pastebin(message_body)
    local post_body = "api_dev_key="           .. url_encode(PASTEBIN_TOKEN)
                   .. "&api_paste_code="       .. url_encode(message_body)
                   .. "&api_paste_private=1"
                   .. "&api_paste_expire_date=1W"
                   .. "&api_option=paste"

    local ok, resp = pcall(Http.post, PASTEBIN_URL, post_body, {
        ["Content-Type"] = "application/x-www-form-urlencoded",
    })

    if not ok then
        return "Failed to upload pastebin: " .. tostring(resp)
    end
    if type(resp) ~= "table" or not resp.status then
        return "Failed to upload pastebin."
    end
    if resp.status < 200 or resp.status >= 300 then
        return "Failed to upload pastebin (HTTP " .. tostring(resp.status) .. ")."
    end

    local result = (resp.body or ""):gsub("[\r\n]+$", "")
    if #result >= 200 then
        return "Failed to upload pastebin."
    end
    return result
end

local function build_message_body()
    local parts = {}

    -- Engine / runtime version info
    table.insert(parts, "Revenant Version: " .. Version.current())
    table.insert(parts, "Lua Version: "      .. _VERSION)
    table.insert(parts, "SQLite Version: "   .. Version.sqlite())
    table.insert(parts, "Game: "             .. (GameState.game or "unknown"))
    table.insert(parts, "Character: "        .. (GameState.name or "unknown"))

    -- Profile YAML files belonging to this character
    local char_name = GameState.name or ""
    if File.is_dir("profiles") then
        for _, fname in ipairs(File.list("profiles") or {}) do
            if fname:match("%.yaml$") and fname:find(char_name, 1, true) then
                local path  = "profiles/" .. fname
                local mtime = File.mtime(path) or 0
                table.insert(parts, "\n****\n****\n****")
                table.insert(parts, path .. "  -  Modified: " .. tostring(mtime))
                table.insert(parts, File.read(path) or "")
            end
        end
    end

    -- Directory listings
    table.insert(parts, "\n****\n****\n****")

    local profile_entries = {}
    if File.is_dir("profiles") then
        for _, f in ipairs(File.list("profiles") or {}) do
            table.insert(profile_entries, "profiles/" .. f)
        end
    end
    table.insert(parts, table.concat(profile_entries, ","))

    local data_entries = {}
    if File.is_dir("data") then
        for _, f in ipairs(File.list("data") or {}) do
            table.insert(data_entries, "data/" .. f)
        end
    end
    table.insert(parts, table.concat(data_entries, ","))

    local body = table.concat(parts, "\n")
    body = body:gsub("bastard", "dastard (modified)")
    return body
end

local function help_me(target_user)
    local result = submit_pastebin(build_message_body())

    if result:find("Bad API request") or not target_user then
        echo(result .. " ")
    else
        if running("lnet") or running("lnet2") then
            put(";chat to " .. target_user .. " " .. result)
            echo("Attempted to PM pastebin link on lnet to " .. target_user .. ".  Check lnet window for success or failure.")
        else
            echo(result .. " ")
        end
    end
end

help_me(user)
