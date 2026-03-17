--- @revenant-script
--- name: crits
--- version: 0.1.0
--- author: elanthia-online
--- game: gs
--- description: Display critical hit information from combat using CritRanks
--- tags: combat,information,crits
---
--- Prototype/demonstration script that watches for combat actions
--- and shows crit rank, location, and stun information.
---
--- Requires: lib/gs/critranks

local CritRanks = require("lib/gs/critranks")
local Messaging = require("lib/messaging")

-- Combat action patterns (from briefcombat)
local COMBAT_ACTIONS = {
    "gesture at",
    "gesture%.",
    "channel at",
    "[hurl|fire|swing|thrust] an? [%w %-%']+ at",
    "swing an? [%w %-%']+ at",
    "thrust(?: with)? a [%w %-%']+ at",
    "continue to sing a disruptive song",
    "draw an intricately glowing pattern in the air before",
    "weave another verse into .* harmony",
    "voice carries the power of thunder",
    "directing the sound of .* voice at",
    "punch",
    "attempt to punch",
    "attempt to jab",
    "attempt to grapple",
    "attempt to kick",
    "fire an? [%w %-%']+ at",
}

local function is_combat_line(line)
    for _, pat in ipairs(COMBAT_ACTIONS) do
        if line:find(pat) then return true end
    end
    return false
end

local function resolve_crit_rank(results)
    local str = ""
    local not_crit_stunned = true

    for _, combat_line in ipairs(results) do
        local crit_result = CritRanks.parse(combat_line)
        if crit_result and next(crit_result) then
            local stunned = crit_result.stunned or 0
            local fatal = crit_result.fatal or false

            if stunned > 0 or fatal then
                if stunned < 999 then
                    if str ~= "" then str = str .. "\n" end
                    if crit_result.type then
                        str = str .. crit_result.type .. " Rank: "
                    end
                    if crit_result.rank then
                        str = str .. tostring(crit_result.rank) .. " | "
                    end
                    if crit_result.location then
                        str = str .. crit_result.location:gsub("_", " ") .. " --> "
                    end
                    if crit_result.position then
                        str = str .. crit_result.position
                        if stunned > 0 then str = str .. " and " end
                        if fatal then str = str .. " and " end
                    end
                    if stunned > 0 then
                        str = str .. "stunned " .. tostring(stunned) .. " rounds. "
                    end
                    if fatal then
                        str = str .. " dead! "
                    end
                    not_crit_stunned = false
                elseif stunned == 999 and not_crit_stunned then
                    if crit_result.type then
                        str = str .. crit_result.type .. " | "
                    end
                    if crit_result.location then
                        str = str .. crit_result.location .. " --> "
                    end
                    str = str .. "stunned, but who knows for how long?"
                end
            end
        end
    end

    return str
end

-- Main loop
while true do
    local line = get()
    if is_combat_line(line) then
        local combat_results = { line }
        -- Collect lines until roundtime or damage
        for _ = 1, 30 do
            local next_line = get()
            combat_results[#combat_results + 1] = next_line
            if next_line:match("[Rr]oundtime") or next_line:match("exhausts itself") then
                break
            end
            if next_line:match("%.%.%.and cause %d+ points? of damage!") then
                break
            end
        end

        local result = resolve_crit_rank(combat_results)
        if result ~= "" then
            respond("")
            respond(result)
            respond("")
        end
    end
end
