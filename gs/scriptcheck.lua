--- @revenant-script
--- name: scriptcheck
--- version: 1.0.0
--- author: Alastir (Tillmen)
--- game: gs
--- tags: script check, filter, familiar, window
--- description: Echo unique lines to familiar window, suppressing lines seen more than 5 times
---
--- Original Lich5 authors: Alastir (Tillmen)
--- Ported to Revenant Lua from scriptcheck.lic
---
--- Usage: ;scriptcheck

hide_me()

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
    "^%[.*%]%-[A-Za-z]+:|^%[server%]: \"",
    "%[LNet%]|%[Merchant%]|%[Realm%]|%[General%]|%[Help%]|%[OOC%]",
    "^You notice",
    "^You (?:put|remove|retrieve|carefully|slip)",
    "^In the",
    "^Today is",
    "^Also here",
    "just (?:arrived|went)",
    "bandit|brigand|highwayman|marauder|mugger|outlaw|robber|rogue|thief|thug",
    "^Obvious (?:exits|paths): ",
}

local count = CharSettings.load("scriptcheck_count") or {}
local THRESHOLD = 5

local function should_ignore(line)
    for _, pat in ipairs(IGNORE_PATTERNS) do
        if Regex.test(line, pat) then return true end
    end
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
        Gui.stream_window(line, "familiar")
    end
end

before_dying(function()
    -- Compact: remove entries seen fewer than 5 times
    local compacted = {}
    for k, v in pairs(count) do
        if v >= THRESHOLD then compacted[k] = v end
    end
    CharSettings.save("scriptcheck_count", compacted)
end)

-- Compact on startup
local compacted = {}
for k, v in pairs(count) do
    if v >= THRESHOLD then compacted[k] = v end
end
count = compacted

local last_save = os.time()

while true do
    local line = get()
    if line then
        process_line(line)
        if os.time() - last_save > 300 then
            CharSettings.save("scriptcheck_count", count)
            last_save = os.time()
        end
    end
end
