--- @revenant-script
--- name: healsubs
--- version: 1.0.0
--- author: Seped
--- game: dr
--- description: Wound text substitution - replaces wound descriptions with severity indicators
--- tags: healing, wounds, display, substitution
---
--- Ported from healsubs.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;healsubs   - Run in background to apply wound display substitutions

local subs = {}

-- Body parts to track
local body_parts = {
    "head", "left eye", "right eye", "neck", "chest",
    "abdomen", "back", "left arm", "right arm",
    "left hand", "right hand", "left leg", "right leg",
    "skin",
}

-- Wound severity levels (external)
local wound_external = {
    { "minor abrasions",  "X_______" },
    { "faint scuffing",   "X_______" },
    { "minor cuts",       "XX______" },
    { "cuts and bruises",  "XX______" },
    { "bruises",          "XXX_____" },
    { "deep cuts",        "XXXX____" },
    { "severe lacerations","XXXXX___" },
    { "gaping wounds",    "XXXXXX__" },
    { "grievous wounds",  "XXXXXXX_" },
    { "mangled",          "XXXXXXXX" },
}

local function add_sub(pattern, replacement)
    table.insert(subs, { pattern = pattern, replacement = replacement })
end

-- Build substitution rules for each body part and severity
for _, part in ipairs(body_parts) do
    for _, ws in ipairs(wound_external) do
        local label = part:upper()
        while #label < 14 do label = label .. " " end
        add_sub(
            ws[1] .. " .-" .. part,
            label .. " -Fresh External-     [" .. ws[2] .. "]"
        )
    end
end

echo("HealSubs loaded with " .. #subs .. " wound display rules.")

DownstreamHook.add("healsub", function(line)
    local modified = line
    for _, sub in ipairs(subs) do
        if modified:find(sub.pattern) then
            modified = modified:gsub(sub.pattern, sub.replacement)
        end
    end
    return modified
end)

before_dying(function()
    DownstreamHook.remove("healsub")
end)

while true do
    pause(60)
end
