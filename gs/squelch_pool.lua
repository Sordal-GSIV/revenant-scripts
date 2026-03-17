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
---
--- Usage:
---   ;squelch_pool          - hide matching messages
---   ;squelch_pool showme   - show what is being squelched

local HOOK_NAME = "squelch_pool_hook"

local SQUELCH_PATTERNS = {
    "speaks briefly with the worker",
    "speaks briefly with",
    "professional calipers a bit",
    "carefully bends the tip of his",
    "removes a pair of",
    "removes a pair of metal grips",
    "Please rephrase that command",
    "tries to empty the contents of",
    "takes.*some.*coins",
    "removes.*calipers",
    "moths takes.*calipers",
    "dropping.*calipers.*in.*hand",
    "refines (?:his|her) professional calipers a bit",
    "attaches an?.*keyring",
    "(?:removes|grabs?|puts?|produces)%s+(?:some|an?).*(?:box|strongbox|chest|trunk|coffer)",
    "(?:removes|grabs?|puts?)%s+(?:some|an?).*(?:caliper|calipers)",
    "(?:box|strongbox|chest|trunk|coffer) vanishes into the depths",
    "just opened%s+an?.*(?:caliper|calipers|box|strongbox|chest|trunk|coffer)",
    "to carefully measure the lock%.%.%.",
    "glass vial",
    "green%-tinted vial filled with thick acrid smoke",
    "(?:attaches|removes) an?.*toolkit",
    "put a pair of small steel jaws in (?:his|her)",
    "detaches a.*keyring",
    "no longer appears focused",
    "searches through a",
    "appears extremely focused",
    "briefly outlined by the woven yarn as",
    "and removes one item of note",
    "and carefully works it back and forth until it is firmly seated",
    "which takes off in search of silvers inside",
    "unties (?:his|her) pouch,.*then reties it quickly",
    "Suddenly it seems to spring to life as a tiny mechanical arm extends",
    "causing its bronze gears to whirl",
    "begins to glow with a white light for a few moments as a tiny",
    "moment later the gears spring to life as the",
    "moments before retreating back into the",
    "begins to glow with a white light for a few moments",
    "removes.*from in a large wastebasket",
}

local show_mode = Script.current.vars[1] and Script.current.vars[1]:lower() == "showme"

DownstreamHook.remove(HOOK_NAME)

DownstreamHook.add(HOOK_NAME, function(server_string)
    for _, pat in ipairs(SQUELCH_PATTERNS) do
        if Regex.test(server_string, pat) then
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
