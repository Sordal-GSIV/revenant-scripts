--- @revenant-script
--- name: smoke
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Smoke training - inhale/exhale cigar images.
--- tags: smoke, training, performance
---
--- Usage: ;smoke <image> <cigar> <container> <lighter>

local image = Script.vars[1]
local cigar = Script.vars[2]
local container = Script.vars[3]
local lighter = Script.vars[4]

if not image or not cigar or not container or not lighter then
    echo("Usage: ;smoke <image> <cigar_noun> <container> <lighter_noun>")
    return
end

Flags.add("new-cig", "That was the last of your")

local function light_cig()
    local result = DRC.bput("get " .. cigar .. " from " .. container, "You get", "What were", "You need")
    if result == "What were" then
        echo("Out of cigars, exiting.")
        Flags.delete("new-cig")
        return false
    end
    DRC.bput("get " .. lighter, "You get", "What were", "You are already")
    fput("point " .. lighter .. " at " .. cigar)
    Flags.reset("new-cig")
    return true
end

if not light_cig() then return end

while true do
    if Flags["new-cig"] then
        if not light_cig() then return end
    end
    DRC.bput("inhale " .. cigar, "You take", "What were")
    DRC.bput("exhale line " .. image, "You blow", "You cast", "You need to have inhaled")
    waitrt()
    fput("smoke list")
end
