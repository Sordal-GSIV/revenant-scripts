--- @revenant-script
--- name: squelch_pool
--- version: 1.0.2
--- author: Wolenthor
--- game: gs
--- tags: squelch, locksmith, pool, filter
--- description: Squelch common locksmith pool spam messages (extended patterns)
---
--- Original Lich5 authors: Wolenthor
--- Ported to Revenant Lua from squelch_pool.lic v1.0.2
--- @lic-certified: complete 2026-03-20
---
--- Usage:
---   ;squelch_pool          - hide matching messages
---   ;squelch_pool showme   - show what is being squelched

local HOOK_NAME = "squelch_pool_hook"

-- Patterns 1-7 are plain string literals (case-sensitive in original Ruby source).
-- Patterns 8-40 had /i flag in Ruby; prefixed with (?i) for case-insensitive PCRE.
-- Patterns with \s, \b use PCRE escapes (not Lua pattern escapes).
local SQUELCH_PATTERNS = {
    "speaks briefly with the worker",
    "speaks briefly with",
    "professional calipers a bit",
    "carefully bends the tip of his",
    "removes a pair of",
    "removes a pair of metal grips",
    "Please rephrase that command",
    "(?i)tries to empty the contents of",
    "(?i)takes.*?some.*?coins",
    "(?i)removes.*?calipers",
    "(?i)moths takes.*?calipers",
    "(?i)dropping.*?calipers.*?in.*?hand",
    "(?i)refines (?:his|her) professional calipers a bit",
    "(?i)attaches an?\\b.*?keyring",
    "(?i)(?:removes|grabs?|puts?|produces)\\s+(?:some|an?)\\b.*?\\b(?:box|strongbox|chest|trunk|coffer)s?",
    "(?i)(?:removes|grabs?|puts?)\\s+(?:some|an?)\\b.*?\\b(?:caliper|calipers)s?",
    "(?i)(?:box|strongbox|chest|trunk|coffer) vanishes into the depths",
    "(?i)just opened\\s+an?\\b.*?\\b(?:caliper|calipers|box|strongbox|chest|trunk|coffer)s?",
    "(?i)to carefully measure the lock...",
    "(?i)glass vial",
    "(?i)green-tinted vial filled with thick acrid smoke",
    "(?i)(?:attaches|removes) an?.*?toolkit",
    "(?i)put a pair of small steel jaws in (?:his|her)",
    "(?i)detaches a.*?keyring",
    "(?i)no longer appears focused",
    "(?i)searches through a",
    "(?i)appears extremely focused",
    "(?i)briefly outlined by the woven yarn as",
    "(?i)and removes one item of note",
    "(?i)and carefully works it back and forth until it is firmly seated",
    "(?i), which takes off in search of silvers inside",
    "(?i)unties (?:his|her) pouch,.*?then reties it quickly",
    "(?i)Suddenly it seems to spring to life as a tiny mechanical arm extends",
    "(?i), causing its bronze gears to whirl.",
    "(?i)begins to glow with a white light for a few moments as a tiny",
    "(?i)moment later the gears spring to life as the",
    "(?i)moments before retreating back into the",
    "(?i)begins to glow with a white light for a few moments",
    "(?i)removes(?:some|an?)\\b.*?\\b(?:caliper|calipers)s?",
    "(?i)removes .*?from in a large wastebasket",
}

local show_mode = Script.vars[1] and Script.vars[1]:lower() == "showme"

DownstreamHook.remove(HOOK_NAME)

DownstreamHook.add(HOOK_NAME, function(server_string)
    for _, pat in ipairs(SQUELCH_PATTERNS) do
        if Regex.test(pat, server_string) then
            if show_mode then
                respond("<pushBold/>Squelched: " .. server_string:match("^%s*(.-)%s*$") .. "<popBold/>")
            end
            return nil
        end
    end
    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

while true do
    get()
end
