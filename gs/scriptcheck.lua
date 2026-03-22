--- @revenant-script
--- name: scriptcheck
--- version: 1.1.0
--- author: Alastir (Tillmen)
--- game: gs
--- tags: script check, filter, familiar, window
--- description: Echo unique lines to familiar window, suppressing lines seen more than 5 times
---
--- Original Lich5 authors: Alastir (Tillmen)
--- Ported to Revenant Lua from scriptcheck.lic
--- @lic-certified: complete 2026-03-20
---
--- Usage: ;scriptcheck

hide_me()

-- All patterns are PCRE (passed to Regex.test).
-- Alternation (|), non-capturing groups (?:...), and inline flags (?i) are supported.
local IGNORE_PATTERNS = {
    "^You offer to sell",
    "^.* takes your",
    "^You ask ",
    "^The .* takes",
    "^You analyze",
    "^Try as you might",
    "^You can tell that",
    "^You might be able to",
    "^You get no sense",
    "^You summon",
    "^As you place",
    "^You search through",
    "^You (?:open|close)",
    "^You want a locksmith to open",
    "^This .* has the Liquid Extractor unlock",
    "An iron portcullis is raised",
    "^\\[.*?\\]-[A-Za-z]+:|^\\[server\\]: \"",
    "\\[LNet\\]|\\[Merchant\\]|\\[Realm\\]|\\[General\\]|\\[Help\\]|\\[OOC\\]",
    "(?i)^You notice",
    "^You (?:put|remove|retrieve|carefully|slip)",
    "^In the",
    "^Today is",
    "^Also here",
    "just (?:arrived|went)",
    "bandit|brigand|highwayman|marauder|mugger|outlaw|robber|rogue|thief|thug",
    "^Obvious (?:exits|paths): ",
    "^(?:Magic Items|Special|Armor|Weapons|Containers|Wands|Gems|Herbs|Food/Drink|Clothing|Misc) \\[\\d+\\]: ",
    "^\\[[^\\]]+\\](?: \\(\\d+\\))?$",
}

local THRESHOLD = 5

-- Load persisted count from CharSettings (JSON-encoded table).
local raw = CharSettings.scriptcheck_count
local count = raw and Json.decode(raw) or nil
if not count then
    echo("No previous count found, starting fresh.")
    count = {}
end

local function save_count()
    CharSettings.scriptcheck_count = Json.encode(count)
end

local function compact()
    local before_n = 0
    for _ in pairs(count) do before_n = before_n + 1 end
    local compacted = {}
    for k, v in pairs(count) do
        if v >= THRESHOLD then compacted[k] = v end
    end
    count = compacted
    local after_n = 0
    for _ in pairs(count) do after_n = after_n + 1 end
    echo("Before compact: " .. before_n)
    echo("After compact: " .. after_n)
    save_count()
end

local function should_ignore(line)
    for _, pat in ipairs(IGNORE_PATTERNS) do
        if Regex.test(pat, line) then return true end
    end
    if CritRanks.parse(line) ~= nil then return true end
    return false
end

local function normalize_line(line)
    return line:gsub("[0-9%s]+", "")
end

local function process_line(line)
    if should_ignore(line) then return end
    local mod_line = normalize_line(line)
    local c = count[mod_line] or 0
    if c < THRESHOLD then
        count[mod_line] = c + 1
        Messaging.stream_window(line, "familiar")
    end
end

before_dying(function()
    compact()
end)

compact()

local last_save = os.time()

while true do
    local line = get()
    if line then
        process_line(line)
        if os.time() - last_save > 300 then
            save_count()
            last_save = os.time()
        end
    end
end
