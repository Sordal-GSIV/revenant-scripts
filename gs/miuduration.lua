--- @revenant-script
--- name: miuduration
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Echo expected MIU cast duration for a spell in an item
--- tags: miu,duration,magic,item
---
--- Usage:
---   ;miuduration <spell#>         Show duration table for all activator verbs
---   ;miuduration <spell#> <verb>  Show duration for a specific activator verb
---
--- Verbs: tap, rub, wave, raise, eat, drink

local VERBS = {
    tap = "tap", rub = "rub", wave = "wave", raise = "raise",
    eat = "eat", drink = "drink", bite = "eat", gobble = "eat",
}

local ACTIVATOR_LIST = {
    { "Tap",   "tap" },
    { "Rub",   "rub" },
    { "Wave",  "wave" },
    { "Raise", "raise" },
    { "Eat",   "eat" },
    { "Drink", "drink" },
}

local function fmt_duration(minutes)
    if not minutes or minutes < 0 then return nil end
    local m = math.floor(minutes)
    local frac = (minutes - m) * 60
    local s = math.floor(frac + 0.5)
    if s >= 60 then m = m + 1; s = 0 end
    if s > 0 then
        return m .. " min " .. s .. " sec"
    else
        return m .. " min"
    end
end

local vars = Script.vars
local spell_num_str = vars[1] or ""
local verb_arg = vars[2]

if spell_num_str == "" or tonumber(spell_num_str) == nil or tonumber(spell_num_str) == 0 then
    echo("Usage: ;miuduration <spell#> [verb]   e.g. ;miuduration 202 tap")
    return
end

local spell_num = tonumber(spell_num_str)
local spell = Spell[spell_num]

if not spell then
    echo("Unknown spell: " .. spell_num_str)
    return
end

if verb_arg then
    verb_arg = verb_arg:lower()
    verb_arg = VERBS[verb_arg] or verb_arg

    local ok, dur_min = pcall(function()
        return spell:time_per({ activator = verb_arg })
    end)

    if not ok or not dur_min then
        echo("Could not compute duration for " .. (spell.name or spell_num_str) ..
             " (" .. spell_num_str .. ") with verb '" .. verb_arg .. "'.")
    else
        echo("MIU duration " .. (spell.name or spell_num_str) ..
             " (" .. spell_num_str .. ") [" .. verb_arg .. "]: " ..
             (fmt_duration(dur_min) or "?") ..
             " (" .. string.format("%.2f", dur_min) .. " min)")
    end
else
    echo(" ")
    echo("MIU duration: " .. (spell.name or spell_num_str) .. " (" .. spell_num_str .. ")")
    echo("----------------------------------------")
    echo(string.format("%-6s  %s", "Verb", "Duration"))
    echo("----------------------------------------")
    for _, entry in ipairs(ACTIVATOR_LIST) do
        local label, act = entry[1], entry[2]
        local ok, dur_min = pcall(function()
            return spell:time_per({ activator = act })
        end)
        local dur_str = (ok and dur_min) and fmt_duration(dur_min) or "---"
        echo(string.format("%-6s  %s", label, dur_str))
    end
    echo("----------------------------------------")
    echo(" ")
end
