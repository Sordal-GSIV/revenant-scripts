--- @revenant-script
--- name: dothethingwatch
--- version: 1.0.1
--- author: Phocosoen
--- game: gs
--- tags: script check, filter, spam, familiar, sqlite
--- description: Throttle repeated game messages in familiar window using shared counts
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from dothethingwatch.lic v1.0.1
---
--- Changelog:
---   1.0.1 (2025-07-02) Start with ;dothethingwatch NUMBER or ;dothethingwatch threshold NUMBER
---                       to change the number of times a line must be seen before ignored.
---   1.0.1 (2025-07-02) Minor bug fixes and matching updates.
---   1.0.0 (2025-07-02) Initial release: shared DB, in-memory batching, verb filtering,
---                       normalize anchors & pronouns, threshold notices.
---
--- Usage:
---   ;dothethingwatch          - run with default threshold (5)
---   ;dothethingwatch <N>      - set threshold to N
---   ;dothethingwatch threshold <N> - set threshold to N
---
--- @lic-certified: complete 2026-03-19

no_kill_all()
hide_me()

-- -------------------------------------------------------------------
-- 1) Settings key helpers — uses Settings (global, shared across all
--    characters on the same game) with MD5-hashed keys for persistence
-- -------------------------------------------------------------------
local SETTINGS_PREFIX = "dttw:"
local SETTINGS_META_LINES = "dttw_meta:total_lines"
local SETTINGS_META_COUNT = "dttw_meta:total_count"

local function settings_key(mod_line)
    return SETTINGS_PREFIX .. Crypto.md5(mod_line)
end

local function get_stored_count(mod_line)
    local val = Settings[settings_key(mod_line)]
    return val and tonumber(val) or 0
end

-- -------------------------------------------------------------------
-- 2) Display startup stats from persisted data
-- -------------------------------------------------------------------
local total_lines = tonumber(Settings[SETTINGS_META_LINES]) or 0
local total_count = tonumber(Settings[SETTINGS_META_COUNT]) or 0

echo("There are " .. total_lines .. " unique lines being blocked in the familiar window {?!}")

-- -------------------------------------------------------------------
-- 3) Batching parameters — in-memory cache, flush to Settings every 30s
-- -------------------------------------------------------------------
local cache = {}          -- {[mod_line] = delta_count}
local FLUSH_INTERVAL = 30 -- seconds between flushes
local last_flush = os.time()

local function flush_cache()
    local new_unique = 0
    local new_total = 0
    for mod_line, delta in pairs(cache) do
        local key = settings_key(mod_line)
        local existing = tonumber(Settings[key]) or 0
        local new_count = existing + delta
        Settings[key] = tostring(new_count)
        if existing == 0 then
            new_unique = new_unique + 1
        end
        new_total = new_total + delta
    end
    -- update meta counters
    local cur_lines = tonumber(Settings[SETTINGS_META_LINES]) or 0
    local cur_count = tonumber(Settings[SETTINGS_META_COUNT]) or 0
    Settings[SETTINGS_META_LINES] = tostring(cur_lines + new_unique)
    Settings[SETTINGS_META_COUNT] = tostring(cur_count + new_total)
    cache = {}
    last_flush = os.time()
end

-- -------------------------------------------------------------------
-- 4) Threshold configuration
-- -------------------------------------------------------------------
local threshold = 5

local args_str = Script.vars[0] or ""
local num_match = args_str:match("^(%d+)$")
local thresh_match = args_str:match("^[Tt][Hh][Rr][Ee][Ss][Hh][Oo][Ll][Dd]%s+(%d+)$")
if num_match then
    threshold = tonumber(num_match)
    echo("Threshold updated to " .. threshold .. ". {?!}")
elseif thresh_match then
    threshold = tonumber(thresh_match)
    echo("Threshold updated to " .. threshold .. ". {?!}")
end

-- -------------------------------------------------------------------
-- 5) XML noise and skip patterns
-- -------------------------------------------------------------------
local SKIP_PLAIN = {
    "<compass>", "<nav rm=", 'style id="roomDesc"', 'style id="roomName"',
    "component id='room objs'", "component id='room players'",
    "<roundTime value='", "<dialogData id=", "<d cmd=", "<indicator id='",
    "<a href=", 'noun="disk">', "<preset id='speech'>",
    'pushStream id="thoughts', 'Also here: <a exist="',
    "Stream id='inv'", "(registered)", "(marked)",
    '<pushStream id="death"', "Also here:",
}

-- Regex patterns for combat creature lines (compiled once)
local re_combat1 = Regex.new("^The\\s.*(?:<pushBold/>\\s*)?<a exist=.*?</a>(?:\\s*<popBold/>)?.*!$")
local re_combat2 = Regex.new("^A\\s.*(?:<pushBold/>\\s*)?<a exist=.*?</a>(?:\\s*<popBold/>)?.*\\.$")
-- Lines starting with a/an/some + anchor tag
local re_item_line = Regex.new("^(?:a|an|some)\\s+<a exist=")
-- Lines containing "You ... <a exist="
local re_you_exist = Regex.new("You.*<a exist=")
-- Character name boundary match
local char_name = GameState.name or ""

local function should_skip(text)
    -- skip lines ending with special characters
    local last = text:sub(-1)
    if last == ":" or last == ")" or last == "]" then
        return true
    end

    -- skip XML noise (plain substring matching)
    for _, pat in ipairs(SKIP_PLAIN) do
        if text:find(pat, 1, true) then return true end
    end

    -- skip combat creature lines
    if re_combat1:test(text) then return true end
    if re_combat2:test(text) then return true end
    if re_item_line:test(text) then return true end
    if re_you_exist:test(text) then return true end

    -- skip lines with character name
    if char_name ~= "" and text:find(char_name, 1, true) then
        return true
    end

    -- skip lines starting with <prompt or <
    if text:sub(1, 7) == "<prompt" then return true end

    return false
end

-- -------------------------------------------------------------------
-- 6) Normalize line — strip anchor tags, pronouns, numbers, whitespace
--    (mirrors the original Ruby normalization exactly)
-- -------------------------------------------------------------------
local re_anchor = Regex.new('<a exist="[^"]+" noun="[^"]+">.*?</a>')
local re_pronoun = Regex.new("(?i)\\b(?:he|she|him|her|his|hers)\\b")

local function normalize(text)
    local mod = re_anchor:replace_all(text, "")
    mod = re_pronoun:replace_all(mod, "")
    mod = mod:gsub("[0-9%s]+", "")
    return mod
end

-- -------------------------------------------------------------------
-- 7) Hook — capture all downstream lines, process inline
--    Note: The original Lich5 version used EngTagger (Ruby NLP) to
--    require at least one verb in each line. No equivalent NLP library
--    exists in Lua, so that filter is omitted. The XML/combat/name
--    filters remove the bulk of noise regardless.
-- -------------------------------------------------------------------
local HOOK_ID = "dothethingwatch_action_spamfilter"

DownstreamHook.add(HOOK_ID, function(server_string)
    local text = server_string:match("^%s*(.-)%s*$") or ""
    if text == "" then return server_string end

    if should_skip(text) then return server_string end

    local mod_line = normalize(text)
    if mod_line == "" then return server_string end

    -- update in-memory cache
    cache[mod_line] = (cache[mod_line] or 0) + 1

    -- compute total: on-disk + all cache deltas
    local on_disk = get_stored_count(mod_line)
    local total_so_far = on_disk + cache[mod_line]

    if total_so_far <= threshold then
        -- still under (or at) the limit: stream to familiar window
        respond_to_window("familiar", text)
    elseif total_so_far == threshold + 1 then
        -- one-time threshold-crossed notice
        local msg = total_so_far .. " occurrences of '" .. mod_line .. "' (Threshold = " .. threshold .. ")"
        echo(msg .. " {?!}")
        respond_to_window("familiar", "          " .. msg)
    end

    return server_string
end)

-- -------------------------------------------------------------------
-- 8) Cleanup on script shutdown — flush remaining cache
-- -------------------------------------------------------------------
before_dying(function()
    DownstreamHook.remove(HOOK_ID)
    flush_cache()
end)

echo("Hook installed, batching thread started. {?!}")

-- -------------------------------------------------------------------
-- 9) Main loop — periodic cache flush
-- -------------------------------------------------------------------
while true do
    pause(1)
    if os.time() - last_flush >= FLUSH_INTERVAL then
        flush_cache()
    end
end
