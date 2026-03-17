--- @revenant-script
--- name: hunt2
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Parse bounty task for critter name and start wander script to hunt it
--- tags: bounty,hunting,wander

local bounty = checkbounty()
local critter = nil

if not bounty or bounty == "" then
    echo("-----You do not have a suitable bounty-----")
    echo("-----Wandering for any target         -----")
    Script.run("wander")
    wait_while(function() return running("wander") end)
    return
end

local patterns = {
    "suppress (.+) activity",
    "recover .* lost after being attacked by a (.+) in",
    "visions of the child fleeing from a (.+) in",
    "hunt down and kill a particularly dangerous (.+) that",
    "SKIN them off the corpse of a (.+) or purchase",
}

for _, pat in ipairs(patterns) do
    local match = bounty:match(pat)
    if match then
        critter = match
        break
    end
end

if not critter then
    echo("-----You do not have a suitable bounty-----")
    echo("-----Wandering for any target         -----")
    Script.run("wander")
    wait_while(function() return running("wander") end)
    return
end

echo("Parsed critter: " .. critter)

-- Extract only the last word of the critter's name
critter = critter:match("(%S+)$") or critter
echo("Targeting: " .. critter)

Script.run("wander", critter)
wait_while(function() return running("wander") end)

put("target " .. critter)
