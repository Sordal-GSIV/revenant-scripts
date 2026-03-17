--- @revenant-script
--- name: advexp
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Advanced exp pulse info - shows base, ascension, and multiplier breakdown
--- tags: experience, exp, pulse, tracker
---
--- Usage:
---   ;advexp    - runs in background, reports each pulse's breakdown
---
--- Output format:
---   You absorb 121 experience points. Pulse: 38 Base: 97 Asc: 24 Mult: 3.2x

local function parse_exp_line(line, exp)
    -- Match "Key: Value" patterns (values may have commas)
    for key, val in line:gmatch("([A-Z][^:]+):%s+([%d,]+)") do
        exp[key:match("^%s*(.-)%s*$")] = tonumber((val:gsub(",", "")))
    end
end

local function get_exp()
    local exp = {}
    local result = quiet_command("exp", "Level:")
    for _, line in ipairs(result or {}) do
        parse_exp_line(line, exp)
    end
    return exp
end

local function calc_mult(exp1, exp2)
    local field_diff = (exp1["Field Exp"] or 0) - (exp2["Field Exp"] or 0)
    if field_diff == 0 then return 0 end
    return ((exp2["Total Exp"] or 0) - (exp1["Total Exp"] or 0)) / field_diff
end

local function diff_total(exp1, exp2)
    return (exp2["Total Exp"] or 0) - (exp1["Total Exp"] or 0)
end

local function diff_field(exp1, exp2)
    return (exp1["Field Exp"] or 0) - (exp2["Field Exp"] or 0)
end

local function diff_asc(exp1, exp2)
    return (exp2["Ascension Exp"] or 0) - (exp1["Ascension Exp"] or 0)
end

local function percent_capped(exp)
    local cap_exp = 7572500
    local multiple_list = {
        "", "double", "triple", "quadruple", "quintuple",
        "sextuple", "septuple", "octuple", "nonuple", "decuple",
        "undecuple", "duodecuple", "tredecuple", "quattuordecuple",
        "quindecuple", "sexdecuple", "septendecuple", "octodecuple",
        "novemdecuple", "vigintuple",
    }

    local xp = exp["Total Exp"] or 0
    local pcap = xp / cap_exp
    local floor_pcap = math.floor(pcap)

    if floor_pcap >= #multiple_list then
        respond("You are insane!")
    else
        local multiple = multiple_list[floor_pcap + 1]  -- Lua 1-indexed
        if floor_pcap > 0 then
            multiple = multiple .. " "
        end
        local pct = math.floor((pcap % 1) * 10000 + 0.5) / 100
        respond(string.format("You are %.2f%% to being %scapped", pct, multiple))
    end
end

status_tags()
local last_exp = get_exp()
local last_stats_exp = Stats.exp

while true do
    local line = get()
    if line then
        if line:find("<progressBar id='nextLvlPB'") then
            -- Only issue command if Stats.exp actually changed
            if Stats.exp ~= last_stats_exp then
                local exp = get_exp()
                local total = diff_total(last_exp, exp)
                local field = diff_field(last_exp, exp)
                local base = total - diff_asc(last_exp, exp)
                local asc = diff_asc(last_exp, exp)
                local mult = calc_mult(last_exp, exp)

                respond(string.format(
                    "You absorb %d experience points. Pulse: %d Base: %d Asc: %d Mult: %.1fx",
                    total, field, base, asc, mult
                ))

                last_exp = exp
                last_stats_exp = Stats.exp
            end

        elseif line:find("Experience:") then
            -- User manually typed EXP; parse it and show percent capped
            local pcap_exp = {}
            parse_exp_line(line, pcap_exp)
            while true do
                local next_line = get()
                if next_line then
                    parse_exp_line(next_line, pcap_exp)
                    if next_line:find("Exp until lvl:") or next_line:find("Exp to next TP:") then
                        break
                    end
                end
            end
            percent_capped(pcap_exp)
        end
    end
end
