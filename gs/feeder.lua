--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: feeder
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- tags: feeder, discord, treasure, loot, lock, key
--- description: Monitor for feeder/treasure/cache/lock-key/gemstone announcements and relay to discord hook
---
--- Original Lich5 authors: elanthia-online
--- Ported to Revenant Lua from feeder.lic v1.0.0
---
--- Version Control:
--- v1.0.0 (2025-10-09) - initial release
---
--- Usage: ;feeder
---        ;feeder --test        (skip main loop, just load module)
---        ;feeder --gemstonefail (run gemstone parse test)
--- Requires: discordhook script running

local discordhook = require("discordhook")

-- ── Pattern Groups ────────────────────────────────────────────────────────

-- Feeder / treasure find patterns (uses Regex for Regexp.union fidelity)
local feeder_patterns = {
    -- legendary
    Regex.new([[^\*\*\* A prismatic display of color tints the air around you and arcs away, heralding your discovery of a legendary treasure! \*\*\*]]),
    Regex.new([[^\*\*\* A prismatic display of color arcs across the sky over .+, heralding the discovery of a legendary treasure! \*\*\*]]),
    Regex.new([[^\*\*\* A refracted display of prismatic color tints the air around you, heralding the distant discovery of a legendary treasure! \*\*\*]]),
    -- epic
    Regex.new([[^\*\*\* An arc of fire and lightning sweeps around you before rising away, announcing your discovery of an epic treasure! \*\*\*]]),
    Regex.new([[^\*\*\* An arc of fire and lightning sweeps across the sky over .+, heralding the discovery of an epic treasure! \*\*\*]]),
    Regex.new([[^\*\*\* A trio of candle-like flames surrounded by lightning materialize in the air around you, announcing the distant discover(?:y)? of an epic treasure! \*\*\*]]),
    -- rare
    Regex.new([[^\*\*\* A swirl of glimmering motes surrounds you before rising into the sky, indicating your discovery of a rare treasure! \*\*\*]]),
    Regex.new([[^\*\*\* A swirl of glimmering motes rises into the sky over .+, indicating the discovery of a rare treasure! \*\*\*]]),
    Regex.new([[^\*\*\* An array of glimmering motes grace the air around you, indicating the distant discovery of a rare treasure! \*\*\*]]),
    -- general feeder
    Regex.new([[^\*\*\* A glint of light draws your attention to your latest find! \*\*\*]]),
    -- generic catch-all
    Regex.new([[(?:rare|epic|legendary) treasure! \*\*\*]]),
}

local cache_patterns = {
    Regex.new([[^A bandit can be heard snarling, "One of our caches was plundered for [\w,]+ bloodscrip!  Argh!!!"]]),
    Regex.new([[^You search around and find a cache of [\w,]+ bloodscrip, which you pocket!]]),
}

local lockandkey_patterns = {
    Regex.new([[^A (?:radiant|vibrant) (?:blood red|forest green|frosty white|rainbow-hued|royal blue) (?:key|lock) appears on the ground!]]),
}

local gemstone_patterns = {
    Regex.new([[^\*\* A glint of light catches your eye, and you notice .* at your feet! \*\*]]),
}

-- ── Helpers ───────────────────────────────────────────────────────────────

local function matches_any(line, patterns)
    for _, re in ipairs(patterns) do
        if re:test(line) then return true end
    end
    return false
end

local function build_description()
    local parts = {}

    -- Room title with map room ID
    local room_title = GameState.room_title or "Unknown Room"
    local room_id = Map.current_room()
    local room_uid = GameState.room_id
    if room_id then
        parts[#parts + 1] = room_title:gsub("%]$", " - " .. room_id .. "]")
    else
        parts[#parts + 1] = room_title
    end
    if room_uid then
        parts[#parts + 1] = "(u" .. tostring(room_uid) .. ")"
    end

    -- Loot objects
    local loot = GameObj.loot()
    if loot and #loot > 0 then
        local names = {}
        for _, item in ipairs(loot) do names[#names + 1] = item.name end
        parts[#parts + 1] = "Objects: " .. table.concat(names, ", ")
    end

    parts[#parts + 1] = ""

    -- NPCs
    local npcs = GameObj.npcs()
    if npcs and #npcs > 0 then
        local names = {}
        for _, npc in ipairs(npcs) do names[#names + 1] = npc.name end
        parts[#parts + 1] = "NPCs: " .. table.concat(names, ", ")
    else
        parts[#parts + 1] = "NPCs: "
    end

    -- PCs (Also here)
    local pcs = GameObj.pcs()
    if pcs and #pcs > 0 then
        local names = {}
        for _, pc in ipairs(pcs) do names[#names + 1] = pc.noun end
        parts[#parts + 1] = "Also here: " .. table.concat(names, ", ")
    else
        parts[#parts + 1] = "Also here: "
    end

    -- Room exits
    local exits = GameState.room_exits
    if exits and #exits > 0 then
        parts[#parts + 1] = "Obvious paths: " .. table.concat(exits, ", ")
    end

    -- Recent lines (reget 10)
    local recent = reget(10)
    if recent and #recent > 0 then
        parts[#parts + 1] = table.concat(recent, "")
    end

    return table.concat(parts, "\n")
end

-- ── Parse ─────────────────────────────────────────────────────────────────

local function parse(line)
    local stripped = line:match("^%s*(.-)%s*$")
    if not stripped or stripped == "" then return "noop" end

    if matches_any(stripped, feeder_patterns) then
        discordhook.msg("\nFEEDER FOUND!\n```" .. stripped .. "```", { description = build_description() })
        return "ok"
    elseif matches_any(stripped, cache_patterns) then
        discordhook.msg("\nDR Sewer Cache FOUND!\n```" .. stripped .. "```", { description = build_description() })
        return "ok"
    elseif matches_any(stripped, lockandkey_patterns) then
        discordhook.msg("\nLock & Key FOUND!\n```" .. stripped .. "```", { description = build_description() })
        return "ok"
    elseif matches_any(stripped, gemstone_patterns) then
        discordhook.msg("\nGemstone FOUND!\n```" .. stripped .. "```", { description = build_description() })
        return "ok"
    elseif stripped:find("Your passcode is to: ", 1, true) then
        local recent = reget(15)
        local context = recent and table.concat(recent, "\n") or stripped
        discordhook.msg("\nRogue Guild Invitation!\n```" .. context .. "```", { description = build_description() })
        return "ok"
    end

    return "noop"
end

-- ── Main / Test Modes ─────────────────────────────────────────────────────

-- Check that discordhook is available as a running script
if not Script.running("discordhook") then
    -- Wait briefly for it to start
    local waited = 0
    while not Script.running("discordhook") and waited < 5 do
        pause(1)
        waited = waited + 1
    end
    if not Script.running("discordhook") then
        echo("Requires the discordhook script downloaded and ran prior to launching this script")
        return
    end
end

-- Test modes
local vars = Script.vars or {}
local has_flag = function(flag)
    for i = 1, 20 do
        if vars[i] == flag then return true end
    end
    return false
end

if has_flag("--gemstonefail") then
    local result = parse(" ** A glint of light catches your eye, and you notice a marquise-cut sapphire jewel rippled by copper at your feet! **")
    echo("Result: " .. tostring(result))
    if result ~= "ok" then
        error("failed to parse gemstone drop!")
    end
    return
end

if has_flag("--test") then
    echo("Test mode — feeder module loaded but main loop skipped.")
    return
end

-- Main loop
while true do
    local line = get()
    if line then
        parse(line)
    end
end
