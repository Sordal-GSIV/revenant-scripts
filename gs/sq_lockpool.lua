--- @revenant-script
--- name: sq_lockpool
--- version: 1.0.0
--- author: Wolenthor
--- game: gs
--- tags: squelch, locksmith, pool, filter
--- description: Squelch common locksmith pool spam messages
---
--- Original Lich5 authors: Wolenthor
--- Ported to Revenant Lua from sq_lockpool.lic v1.0.0
---
--- Usage:
---   ;sq_lockpool          - hide matching messages
---   ;sq_lockpool showme   - show what is being squelched

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
    "(?:removes|grabs?|puts?)%s+an?.*(?:box|strongbox|chest|trunk|coffer)",
    "(?:removes|grabs?|puts?)%s+an?.*(?:caliper|calipers)",
    "just opened%s+an?.*(?:caliper|calipers|box|strongbox|chest|trunk|coffer)",
    "to carefully measure the lock%.%.%.",
    "glass vial",
    "detaches a.*keyring",
    "no longer appears focused",
    "searches through a",
    "appears extremely focused",
    "briefly outlined by the woven yarn as",
    "and removes one item of note",
    "and carefully works it back and forth until it is firmly seated",
    "which takes off in search of silvers inside",
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
    local line = get()
    -- keep script alive
end
