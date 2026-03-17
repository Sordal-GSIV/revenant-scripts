--- @revenant-script
--- name: ktsearcher
--- version: 1.0
--- author: unknown
--- game: dr
--- description: KillerTofu search companion - pauses on death to loot.
--- tags: killertofu, loot, search
---
--- Converted from ktsearcher.lic

silence_me()

local death_messages = {
    "ceases all movement", "stops all movement",
    "the deer softly exhales its final breath",
    "one last time and lies still", "growls low and dies",
    "growls one last time and collapses",
    "whines briefly before closing its eyes forever",
    "clawing in vain at the air until it ceases all movement",
    "shudders, then goes limp", "uncoils rapidly before expiring",
    "falls to the ground with a crash", "before its death rattle",
    "skull-tipped staff disappears", "rock guardian collapses",
    "forest geni cries out", "deadwood dryad slumps",
    "flickering out as the blightwater nyad collapses",
    "The room is too cluttered", "howls in pain until its eyes glaze",
    "is already quite dead",
}

while true do
    local line = get()
    if line then
        for _, msg in ipairs(death_messages) do
            if line:find(msg, 1, true) then
                pause_script("killertofu")
                start_script("ktlooter")
                wait_while(function() return running("ktlooter") end)
                pause(0.5)
                unpause_script("killertofu")
                break
            end
        end
    end
end
