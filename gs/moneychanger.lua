--- @revenant-script
--- name: moneychanger
--- version: 1.0.2
--- author: Ondreian
--- game: gs
--- description: Better money parser — shorthand like 3m, 5k, 1.5b in commands
--- tags: utility,currency,money
---
--- Parses upstream commands for money shorthand and expands them:
---   shop withdraw 30m  →  shop withdraw 30000000
---   give Tony 3m       →  give Tony 3000000
---
--- Ignores speech commands (say, whisper, think, chat).

local FACTORS = {
    k = 1000,
    m = 1000000,
    b = 1000000000,
}

local MONEY_PATTERN = "(%d*%.?%d+)([kKmMbB])"

local IGNORE_VERBS = {
    whisper = true,
    say     = true,
    ["'"]   = true,
    think   = true,
    chat    = true,
}

local function parse_and_replace(cmd)
    -- Extract the verb (first word)
    local verb = cmd:match("^(%S+)")
    if not verb then return cmd end
    verb = verb:lower()
    if IGNORE_VERBS[verb] then return cmd end

    -- Replace all money shorthand occurrences
    local result = cmd:gsub(MONEY_PATTERN, function(num_str, factor_char)
        local num = tonumber(num_str)
        local factor = FACTORS[factor_char:lower()]
        if num and factor then
            return tostring(math.floor(num * factor))
        end
        return num_str .. factor_char
    end)
    return result
end

UpstreamHook.add("moneychanger", function(cmd)
    return parse_and_replace(cmd)
end)

before_dying(function()
    UpstreamHook.remove("moneychanger")
end)

echo("MoneyChanger active — use k/m/b suffixes in commands (e.g. 3m = 3000000)")

while true do
    sleep(1)
end
