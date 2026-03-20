--- @revenant-script
--- name: star_squelch
--- version: 1.1.0
--- author: Starsworn
--- game: gs
--- tags: squelch, filter, chat, spam
--- description: Hide incoming lines beginning with saved phrases (global across characters)
---
--- Original Lich5 authors: Starsworn
--- Ported to Revenant Lua from star-squelch.lic
--- @lic-certified: complete 2026-03-20
---
--- Usage:
---   ;star_squelch                 - run the filter
---   ;star_squelch add <phrase>    - add a phrase to ignore
---   ;star_squelch list            - list saved phrases
---   ;star_squelch remove <index>  - remove phrase by 1-based index
---   ;star_squelch clear           - clear all phrases
---
--- Phrases are stored globally (shared across all characters), matching Lich5 Settings behaviour.

local HOOK_NAME = "star-squelch-hook"

-- Settings stores strings only; serialize the prefixes array as JSON.
-- Uses global Settings (not CharSettings) to match Lich5 behaviour:
-- "Phrases will be blocked by any of your characters running the script."
local function load_prefixes()
    local raw = Settings.star_squelch_prefixes
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_prefixes(prefixes)
    Settings.star_squelch_prefixes = Json.encode(prefixes)
end

local prefixes = load_prefixes()

-- Rebuild normalised cache (strip quotes for comparison, same as Lich5 rebuild_norm!)
local function build_norm(prefixes)
    local norm = {}
    for i, p in ipairs(prefixes) do
        norm[i] = p:gsub('"', "")
    end
    return norm
end

local prefixes_norm = build_norm(prefixes)

local function normalize_phrase(phrase)
    if not phrase or phrase == "" then return phrase end
    -- Find last ':' in the phrase (Lua: pattern anchored to end of string)
    local idx = phrase:find(":[^:]*$")
    if not idx then return phrase end
    local head = phrase:sub(1, idx)        -- includes the colon
    local tail = phrase:sub(idx + 1)
    tail = tail:gsub('^[%s"]+', "")       -- strip leading spaces/quotes after colon
    return head .. ' "' .. tail
end

local function strip_tags(s)
    return s and s:gsub("<[^>]*>", "") or ""
end

local function suppressed(text)
    if text == "" or #prefixes_norm == 0 then return false end
    local t = text:gsub('"', "")
    for _, p in ipairs(prefixes_norm) do
        if t:sub(1, #p) == p then return true end
    end
    return false
end

-- Parse command and args from Script.vars (Revenant equivalent of Script.current.vars)
local cmd = Script.vars[1] and Script.vars[1]:lower() or ""

if cmd == "add" then
    local args = {}
    for i = 2, #Script.vars do
        args[#args + 1] = Script.vars[i]
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
        save_prefixes(prefixes)
        prefixes_norm = build_norm(prefixes)
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
    local idx = tonumber(Script.vars[2] or "0")
    if not idx or idx <= 0 or idx > #prefixes then
        echo("invalid index. try ;star_squelch list")
        return
    end
    local removed = table.remove(prefixes, idx)
    save_prefixes(prefixes)
    prefixes_norm = build_norm(prefixes)
    echo("removed: " .. removed)
    return

elseif cmd == "clear" then
    prefixes = {}
    save_prefixes(prefixes)
    prefixes_norm = {}
    echo("cleared all phrases.")
    return
end

-- Run the filter
DownstreamHook.remove(HOOK_NAME)
DownstreamHook.add(HOOK_NAME, function(server_string)
    local ok, result = pcall(function()
        local txt = strip_tags(server_string)
        if suppressed(txt) then return nil end
        return server_string
    end)
    if not ok then
        echo("star-squelch error: " .. tostring(result))
        return server_string
    end
    return result
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    echo("star-squelch stopped.")
end)

echo("star-squelch active. " .. #prefixes .. " phrases blocked.")
while true do
    pause(0.5)
end
