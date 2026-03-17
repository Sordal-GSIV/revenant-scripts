--- @revenant-script
--- name: textsubs
--- version: 1.0.0
--- author: Seped
--- game: dr
--- description: Text substitution engine - replaces game text with enhanced versions (damage ratings, etc)
--- tags: text, substitution, display, damage
---
--- Ported from textsubs.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;textsubs   - Run in background to apply text substitutions

local subs = {}

local function add_sub(pattern, replacement)
    table.insert(subs, { pattern = pattern, replacement = replacement })
end

-- Default substitutions: damage rating numbers
local damage_levels = {
    { "no", "0/27" },
    { "dismal", "1/27" },
    { "poor", "2/27" },
    { "low", "3/27" },
    { "somewhat fair", "4/27" },
    { "fair", "5/27" },
    { "somewhat moderate", "6/27" },
    { "moderate", "7/27" },
    { "somewhat good", "8/27" },
    { "good", "9/27" },
    { "somewhat very good", "10/27" },
    { "very good", "11/27" },
    { "somewhat heavy", "12/27" },
    { "heavy", "13/27" },
    { "somewhat very heavy", "14/27" },
    { "very heavy", "15/27" },
    { "somewhat severe", "16/27" },
    { "severe", "17/27" },
    { "somewhat very severe", "18/27" },
    { "very severe", "19/27" },
    { "somewhat devastating", "20/27" },
    { "devastating", "21/27" },
    { "somewhat annihilating", "22/27" },
    { "annihilating", "23/27" },
    { "somewhat obliterating", "24/27" },
    { "obliterating", "25/27" },
    { "somewhat catastrophic", "26/27" },
    { "catastrophic", "27/27" },
}

local damage_types = {"puncture", "slice", "impact", "fire", "cold", "electric"}

for _, dl in ipairs(damage_levels) do
    for _, dt in ipairs(damage_types) do
        add_sub(
            dl[1] .. " " .. dt .. " damage",
            dl[1] .. " (" .. dl[2] .. ") " .. dt .. " damage"
        )
    end
end

echo("TextSubs loaded with " .. #subs .. " substitution rules.")
echo("Monitoring game output for text replacements...")

-- Register downstream hook
DownstreamHook.add("textsub", function(line)
    local modified = line
    for _, sub in ipairs(subs) do
        if modified:find(sub.pattern) then
            modified = modified:gsub(sub.pattern, sub.replacement)
        end
    end
    return modified
end)

before_dying(function()
    DownstreamHook.remove("textsub")
end)

-- Keep script alive
while true do
    pause(60)
end
