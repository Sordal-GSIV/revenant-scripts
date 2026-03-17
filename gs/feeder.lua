--- @revenant-script
--- name: feeder
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- tags: feeder, discord, treasure, loot
--- description: Monitor for feeder/treasure/cache/lock-key announcements and relay to discord hook
---
--- Original Lich5 authors: elanthia-online
--- Ported to Revenant Lua from feeder.lic v1.0.0
---
--- Usage: ;feeder
--- Requires: discordhook script running

local feeder_patterns = {
    "^%*%*%* A prismatic display of color tints the air around you and arcs away, heralding your discovery of a legendary treasure! %*%*%*",
    "^%*%*%* A prismatic display of color arcs across the sky over .+, heralding the discovery of a legendary treasure! %*%*%*",
    "^%*%*%* A refracted display of prismatic color tints the air around you, heralding the distant discovery of a legendary treasure! %*%*%*",
    "^%*%*%* An arc of fire and lightning sweeps around you before rising away, announcing your discovery of an epic treasure! %*%*%*",
    "^%*%*%* An arc of fire and lightning sweeps across the sky over .+, heralding the discovery of an epic treasure! %*%*%*",
    "^%*%*%* A trio of candle%-like flames surrounded by lightning materialize in the air around you, announcing the distant discovery of an epic treasure! %*%*%*",
    "^%*%*%* A swirl of glimmering motes surrounds you before rising into the sky, indicating your discovery of a rare treasure! %*%*%*",
    "^%*%*%* A swirl of glimmering motes rises into the sky over .+, indicating the discovery of a rare treasure! %*%*%*",
    "^%*%*%* An array of glimmering motes grace the air around you, indicating the distant discovery of a rare treasure! %*%*%*",
    "^%*%*%* A glint of light draws your attention to your latest find! %*%*%*",
    "rare treasure! %*%*%*",
    "epic treasure! %*%*%*",
    "legendary treasure! %*%*%*",
}

local cache_patterns = {
    '^A bandit can be heard snarling, "One of our caches was plundered',
    "^You search around and find a cache of",
}

local lockandkey_patterns = {
    "^A (?:radiant|vibrant) (?:blood red|forest green|frosty white|rainbow%-hued|royal blue) (?:key|lock) appears on the ground!",
}

local gemstone_patterns = {
    "^%*%* A glint of light catches your eye, and you notice .* at your feet! %*%*",
}

local function matches_any(line, patterns)
    for _, pat in ipairs(patterns) do
        if Regex.test(line, pat) then return true end
    end
    return false
end

-- Check that discordhook is available
if not Script.exists("discordhook") then
    echo("Requires the discordhook script downloaded and ran prior to launching this script")
    return
end

wait(1)

while true do
    local line = get()
    if line then
        local stripped = line:match("^%s*(.-)%s*$")
        if matches_any(stripped, feeder_patterns) then
            echo("FEEDER FOUND! " .. stripped)
        elseif matches_any(stripped, cache_patterns) then
            echo("DR Sewer Cache FOUND! " .. stripped)
        elseif matches_any(stripped, lockandkey_patterns) then
            echo("Lock & Key FOUND! " .. stripped)
        elseif matches_any(stripped, gemstone_patterns) then
            echo("Gemstone FOUND! " .. stripped)
        end
    end
end
