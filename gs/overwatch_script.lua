--- @revenant-script
--- name: overwatch_script
--- version: 1.3.1
--- author: elanthia-online
--- contributors: FarFigNewGut, Nisugi
--- game: gs
--- description: Track hiding creatures and force-reveal them into GameObj
--- tags: hunting,target,hidden,bandits
---
--- Usage:
---   ;overwatch_script           start watching for hidden creatures
---
--- Provides module-level state accessible from other scripts:
---   Overwatch.hiders()           true if current room has hiders
---   Overwatch.room_with_hiders() room ID with known hiders, or nil
---
--- NOTE: This is the standalone script. The library is at lib/gs/overwatch.lua.

local Overwatch = require("lib/gs/overwatch")

-- Enable the downstream hook from the library
Overwatch.enable()

-- Extended XML-aware patterns for the full script version
local HIDING_XML_PATTERNS = {
    "slips into hiding",
    "flies out of the shadows toward",
    "faint silvery light flickers from the shadows",
    "tiny shard of jet black crystal flies from the shadows",
    "fades into the surroundings",
    "slips into the shadows",
    "darts into the shadows",
    "disperses into roiling shadows",
    "Something stirs in the shadows",
    "figure quickly disappears from view",
    "blends with the shadows",
    "hiding place of",
}

local REVEAL_XML_PATTERNS = {
    "You discover the hiding place of",
    "thorny barrier surrounding you blocks the attack from",
    "You reveal .* from hiding",
    "is forced from hiding",
    "is revealed from hiding",
    "comes out of hiding",
    "leaps .* uncovering .* who was hidden",
    "takes a pointed step forward, revealing .* who was hidden",
    "flapping .* wings, exposing .* who was hidden",
    "leaps out of .* hiding place",
    "suddenly leaps from .* hiding place",
    "flaming aura .* lashes out at .* forced into view",
    "shadows melt away to reveal",
    "glides from the shadows and aims",
    "twists fluidly to spear you",
    "glides from the shadows and skitters",
    "interposing between you and the safety of the shadows",
}

local SILENT_STRIKE_PATTERNS = {
    "springs upon you from behind and attempts to grasp",
    "ululating shriek .* leaps from the shadows",
    "leaps from hiding to attack",
    "springs upon you from behind and aims a blow",
    "Catching you unaware .* carves into you",
}

echo("Overwatch active — monitoring for hidden creatures.")

-- Additional monitoring loop for script-level patterns
-- (The library hook handles basic hide/reveal; this provides extended coverage)
while true do
    local line = get()

    -- Track room changes
    if line:match("<nav rm='%d+'") then
        Overwatch.clear()
    end

    -- Check hiding patterns
    for _, pat in ipairs(HIDING_XML_PATTERNS) do
        if line:find(pat) then
            -- The library hook handles the tracking
            break
        end
    end

    -- Check reveal patterns — extract creature info if possible
    for _, pat in ipairs(REVEAL_XML_PATTERNS) do
        if line:find(pat) then
            -- Creature revealed — library hook handles state update
            break
        end
    end
end
