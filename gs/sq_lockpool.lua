--- @revenant-script
--- name: sq_lockpool
--- version: 1.0.1
--- author: Wolenthor
--- game: gs
--- tags: squelch, locksmith, pool, filter
--- description: Squelch common locksmith pool spam messages
---
--- Original Lich5 authors: Wolenthor
--- Ported to Revenant Lua from sq_lockpool.lic v1.0.0
--- @lic-certified: complete 2026-03-20
---
--- Usage:
---   ;sq_lockpool          - hide matching messages
---   ;sq_lockpool showme   - show what is being squelched

local HOOK_NAME = "squelch_pool_hook"

-- Patterns with no (?i) prefix are literal strings from server output (known exact case).
-- Patterns prefixed with (?i) correspond to Ruby /regex/i (case-insensitive) originals.
-- Compiled into a single union regex at startup (mirrors Ruby's Regexp.union).
local SQUELCH_PATTERNS = {
    -- Literal string patterns (Ruby: Regexp.escape'd strings, case-sensitive)
    "speaks briefly with the worker",
    "speaks briefly with",
    "professional calipers a bit",
    "carefully bends the tip of his",
    "removes a pair of",
    "removes a pair of metal grips",
    "Please rephrase that command",
    -- Case-insensitive PCRE patterns (Ruby originals used /i flag)
    "(?i)tries to empty the contents of",
    "(?i)takes.*some.*coins",
    "(?i)removes.*calipers",
    "(?i)moths takes.*calipers",
    "(?i)dropping.*calipers.*in.*hand",
    "(?i)refines (?:his|her) professional calipers a bit",
    "(?i)attaches an?\\b.*keyring",
    "(?i)(?:removes|grabs?|puts?)\\s+an?\\b.*\\b(?:box|strongbox|chest|trunk|coffer)s?",
    "(?i)(?:removes|grabs?|puts?)\\s+an?\\b.*\\b(?:caliper|calipers)s?",
    "(?i)just opened\\s+an?\\b.*\\b(?:caliper|calipers|box|strongbox|chest|trunk|coffer)s?",
    "(?i)to carefully measure the lock...",
    "(?i)glass vial",
    "(?i)detaches a.*keyring",
    "(?i)no longer appears focused",
    "(?i)searches through a",
    "(?i)appears extremely focused",
    "(?i)briefly outlined by the woven yarn as",
    "(?i)and removes one item of note",
    "(?i)and carefully works it back and forth until it is firmly seated",
    "(?i), which takes off in search of silvers inside",
}

-- Build a single compiled union regex (mirrors Ruby's Regexp.union) so each
-- downstream line only requires one regex test instead of 27.
local MASTER_RE = Regex.new(table.concat(SQUELCH_PATTERNS, "|"))

local show_mode = Script.vars[1] and Script.vars[1]:lower() == "showme"

DownstreamHook.remove(HOOK_NAME)

DownstreamHook.add(HOOK_NAME, function(server_string)
    if MASTER_RE:test(server_string) then
        if show_mode then
            respond("<pushBold/>Squelched: " .. server_string:match("^%s*(.-)%s*$") .. "<popBold/>")
        end
        return nil
    end
    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

while true do
    local line = get()
    -- keep script alive
end
