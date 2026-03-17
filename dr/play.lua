--- @revenant-script
--- name: play
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Periodically play a song for performance training.
--- tags: performance, music, training
---
--- Converted from play.lic

local song = UserVars.song or "ditty"

Flags.add("play-clean", "dirtiness may affect your performance")

local function can_play()
    local blocked = {"combat-trainer", "shape", "forge", "carve"}
    for _, s in ipairs(blocked) do
        if running(s) then return false end
    end
    return true
end

local function should_play()
    return DRSkill.getxp("Performance") <= 30 and can_play()
end

while true do
    if should_play() then
        fput("play " .. song .. " on zills")
    end
    pause(60)
end
