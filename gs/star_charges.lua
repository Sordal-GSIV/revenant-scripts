--- @revenant-script
--- name: star_charges
--- version: 1.0.0
--- author: Starsworn
--- game: gs
--- tags: charges, analyze, items, utility
--- description: Analyze items and display remaining charges in a table with low-charge warnings
---
--- Original Lich5 authors: Starsworn
--- Ported to Revenant Lua from star-charges.lic
---
--- Usage: ;star_charges

local ITEMS = {
    { "tattoo",  "tattoo" },
    { "pennant", "pennant" },
    { "spikes",  "spikes" },
    { "earring", "earring" },
}

local PENNANT_MAX = 200
local LOW_CHARGE_WARNING = 10
local TIMEOUT = 6

local CHARGE_LINE = "Charges:%s*%d+|%d+%s+of%s+%d+%s+charges?|holds%s+%d+%s+out%s+of%s+%d+%s+charges?"

local function run_analyze(noun)
    local line = dothistimeout("analyze " .. noun, TIMEOUT, CHARGE_LINE)
    wait(0.1)
    return line or ""
end

local function parse_charges(text, label)
    local cur, max = text:match("(%d+)%s+of%s+(%d+)%s+charges?")
    if cur then return tonumber(cur), tonumber(max) end

    cur, max = text:match("holds%s+(%d+)%s+out%s+of%s+(%d+)%s+charges?")
    if cur then return tonumber(cur), tonumber(max) end

    cur = text:match("Charges:%s*(%d+)")
    if cur then
        cur = tonumber(cur)
        max = (label == "pennant") and PENNANT_MAX or nil
        return cur, max
    end

    return nil, nil
end

local rows = {}
local warnings = {}

for _, item in ipairs(ITEMS) do
    local label, noun = item[1], item[2]
    local text = run_analyze(noun)
    local cur, max = parse_charges(text, label)

    local ratio
    if cur and max then
        ratio = cur .. "/" .. max
    elseif cur then
        ratio = cur .. "/?"
    else
        ratio = "N/A"
    end

    rows[#rows + 1] = { label, ratio }

    if cur and cur < LOW_CHARGE_WARNING then
        warnings[#warnings + 1] = label:upper() .. ": " .. cur .. " charges remaining"
    end
end

-- Resource: Covert Arts
local resource_text = dothistimeout("resource", TIMEOUT, "Covert Arts") or ""
local ca_cur, ca_max = resource_text:match("Covert Arts Charges:%s*(%d+)%s*/%s*(%d+)")
if ca_cur then
    ca_cur = tonumber(ca_cur)
    ca_max = tonumber(ca_max)
    rows[#rows + 1] = { "covert arts", ca_cur .. "/" .. ca_max }
    if ca_cur < LOW_CHARGE_WARNING then
        warnings[#warnings + 1] = "COVERT ARTS: " .. ca_cur .. " charges remaining"
    end
end

-- Format table
local name_w = 4
local chg_w = 7
for _, r in ipairs(rows) do
    if #r[1] > name_w then name_w = #r[1] end
    if #r[2] > chg_w then chg_w = #r[2] end
end

local function pad_right(s, w) return s .. string.rep(" ", w - #s) end
local function pad_left(s, w) return string.rep(" ", w - #s) .. s end

local line_sep = "+-" .. string.rep("-", name_w) .. "-+-" .. string.rep("-", chg_w) .. "-+"
echo(line_sep)
echo("| " .. pad_right("Item", name_w) .. " | " .. pad_right("Charges", chg_w) .. " |")
echo(line_sep)
for _, r in ipairs(rows) do
    echo("| " .. pad_right(r[1], name_w) .. " | " .. pad_right(r[2], chg_w) .. " |")
end
echo(line_sep)

if #warnings > 0 then
    echo("*** WARNING: LOW CHARGES ***")
    for _, w in ipairs(warnings) do
        echo("*** " .. w .. " ***")
    end
end
