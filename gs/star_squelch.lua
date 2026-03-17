--- @revenant-script
--- name: star_squelch
--- version: 1.0.0
--- author: Starsworn
--- game: gs
--- tags: squelch, filter, chat, spam
--- description: Hide incoming lines beginning with saved phrases
---
--- Original Lich5 authors: Starsworn
--- Ported to Revenant Lua from star-squelch.lic
---
--- Usage:
---   ;star_squelch                 - run the filter
---   ;star_squelch add <phrase>    - add a phrase to ignore
---   ;star_squelch list            - list saved phrases
---   ;star_squelch remove <index>  - remove phrase by 1-based index
---   ;star_squelch clear           - clear all phrases

local HOOK_NAME = "star-squelch-hook"
local settings = CharSettings.load("star_squelch") or {}
settings.prefixes = settings.prefixes or {}

local prefixes = settings.prefixes

local function save_prefixes()
    settings.prefixes = prefixes
    CharSettings.save("star_squelch", settings)
end

local function normalize_phrase(phrase)
    if not phrase or phrase == "" then return phrase end
    local idx = phrase:find(":[^:]*$")
    if not idx then return phrase end
    local head = phrase:sub(1, idx)
    local tail = phrase:sub(idx + 1)
    tail = tail:gsub('^[%s"]+', "")
    return head .. ' "' .. tail
end

local function strip_tags(s)
    return s and s:gsub("<[^>]*>", "") or ""
end

local function suppressed(text)
    if text == "" or #prefixes == 0 then return false end
    local t = text:gsub('"', "")
    for _, p in ipairs(prefixes) do
        local norm = p:gsub('"', "")
        if t:sub(1, #norm) == norm then return true end
    end
    return false
end

local cmd = Script.current.vars[1] and Script.current.vars[1]:lower() or ""

if cmd == "add" then
    local args = {}
    for i = 2, #Script.current.vars do
        args[#args + 1] = Script.current.vars[i]
    end
    local phrase = table.concat(args, " "):match("^%s*(.-)%s*$")
    if phrase == "" then
        echo("usage: ;star_squelch add <phrase>")
        return
    end
    phrase = normalize_phrase(phrase)
    local found = false
    for _, p in ipairs(prefixes) do
        if p == phrase then found = true; break end
    end
    if not found then
        prefixes[#prefixes + 1] = phrase
        save_prefixes()
    end
    echo("added (" .. #prefixes .. " total): " .. phrase)
    return

elseif cmd == "list" then
    if #prefixes == 0 then
        echo("no prefixes saved.")
    else
        echo("saved prefixes:")
        for i, p in ipairs(prefixes) do
            respond(i .. ". " .. p)
        end
    end
    return

elseif cmd == "remove" then
    local idx = tonumber(Script.current.vars[2] or "0")
    if idx <= 0 or idx > #prefixes then
        echo("invalid index. try ;star_squelch list")
        return
    end
    local removed = table.remove(prefixes, idx)
    save_prefixes()
    echo("removed: " .. removed)
    return

elseif cmd == "clear" then
    prefixes = {}
    save_prefixes()
    echo("cleared all phrases.")
    return
end

-- Run the filter
DownstreamHook.remove(HOOK_NAME)
DownstreamHook.add(HOOK_NAME, function(server_string)
    local txt = strip_tags(server_string)
    if suppressed(txt) then return nil end
    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    echo("star_squelch stopped.")
end)

echo("star_squelch active. " .. #prefixes .. " phrases blocked.")
while true do
    wait(0.5)
end
