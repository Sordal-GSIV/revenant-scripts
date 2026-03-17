--- @revenant-script
--- name: dothethingwatch
--- version: 1.0.1
--- author: Phocosoen
--- game: gs
--- tags: script check, filter, spam, familiar
--- description: Throttle repeated game messages in familiar window using local counts
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from dothethingwatch.lic v1.0.1
---
--- Usage:
---   ;dothethingwatch          - run with default threshold (5)
---   ;dothethingwatch <N>      - set threshold to N

no_kill_all()
hide_me()

local threshold = 5
local HOOK_ID = "dothethingwatch_filter"

local arg1 = Script.current.vars[1]
if arg1 then
    local n = tonumber(arg1)
    if n then
        threshold = n
        echo("Threshold set to " .. threshold)
    end
end

-- In-memory count (no SQLite dependency needed for Revenant port)
local counts = CharSettings.load("dothethingwatch_counts") or {}

local SKIP_PATTERNS = {
    "^<compass>", "^<nav rm=", 'style id="roomDesc"', 'style id="roomName"',
    "component id='room objs'", "component id='room players'",
    "^<roundTime", "^<dialogData", "<d cmd=", "^<indicator",
    "<a href=", 'noun="disk">', "pushStream id=\"thoughts",
    "Also here:", "^<prompt",
}

local function should_skip(text)
    if text:sub(-1) == ":" or text:sub(-1) == ")" or text:sub(-1) == "]" then
        return true
    end
    for _, pat in ipairs(SKIP_PATTERNS) do
        if text:find(pat, 1, true) then return true end
    end
    if Regex.test(text, "^The%s.*<a exist=.*!</") then return true end
    if text:find(GameState.character_name, 1, true) then return true end
    return false
end

local function normalize(text)
    local mod = text:gsub("<a exist=\"[^\"]+\" noun=\"[^\"]+\">.-</a>", "")
    mod = mod:gsub("%f[%a][Hh][eEiIsSrR][eEsSmMrR]?[sS]?%f[%A]", "")
    mod = mod:gsub("[0-9%s]+", "")
    return mod
end

DownstreamHook.add(HOOK_ID, function(server_string)
    local text = server_string:match("^%s*(.-)%s*$")
    if should_skip(text) then return server_string end

    local mod_line = normalize(text)
    counts[mod_line] = (counts[mod_line] or 0) + 1

    if counts[mod_line] <= threshold then
        Gui.stream_window(text, "familiar")
    elseif counts[mod_line] == threshold + 1 then
        echo(counts[mod_line] .. " occurrences of normalized line (threshold = " .. threshold .. ")")
    end

    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
    CharSettings.save("dothethingwatch_counts", counts)
end)

echo("dothethingwatch active. Threshold: " .. threshold)

while true do
    wait(1)
end
