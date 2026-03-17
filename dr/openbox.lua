--- @revenant-script
--- name: openbox
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Try every possible verb on a box to open it
--- tags: boxes, locksmith, brute-force

local commands = {
    "BITE", "BOP", "BREAK", "BUTT", "CHOP", "CLAP", "CRUSH", "FLAP",
    "HUG", "JAB", "JUGGLE", "JUMP", "KICK", "KISS", "KNEE", "KNOCK",
    "LICK", "MARK", "NUDGE", "PANT", "PAT", "PEER", "PET", "PINCH",
    "POKE", "PROD", "PULL", "PUMMEL", "PUNCH", "PUSH", "READ", "RUB",
    "SCRAPE", "SCRATCH", "SHAKE", "SLAP", "SWING", "TAP", "THUMP",
    "TILT", "TIP", "TOUCH", "TUNE", "TURN", "UNBUNDLE", "UNCOIL",
    "UNLATCH", "UNLOAD", "UNLOCK", "UNTIE", "UNWRAP", "WHISTLE",
    "WIPE", "YANK",
}

for _, cmd in ipairs(commands) do
    fput(cmd .. " my box")
    pause(0.2)
end
