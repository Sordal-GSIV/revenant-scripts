--- @revenant-script
--- name: mana_report
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Record current mana into a SQLite database for multi-character tracking
--- tags: mana,report,database
---
--- Writes one row into mana_reports: name, cur_mana, max_mana, capped_mana, ts

local MANA_CAP = 300
local TIMEOUT  = 6

local function fetch_mana()
    fput("resource")
    local start = os.time()

    while (os.time() - start) < TIMEOUT do
        local line = get()
        if not line then break end

        local cur, max = line:match("Mana:%s+(%d+)/(%d+)")
        if cur and max then
            return tonumber(cur), tonumber(max)
        end

        if line:lower():find("^suffused essence:") then break end
    end
    return nil, nil
end

local cur, max = fetch_mana()
if not cur then
    echo("mana_report: failed to parse mana")
    return
end

local cap  = math.min(cur, MANA_CAP)
local ts   = os.time()
local name = Char.name

-- Store in CharSettings as a simple key-value record
-- (Full SQLite/Sequel not available in Revenant; use CharSettings for persistence)
CharSettings.mana_report_name = name
CharSettings.mana_report_cur  = tostring(cur)
CharSettings.mana_report_max  = tostring(max)
CharSettings.mana_report_cap  = tostring(cap)
CharSettings.mana_report_ts   = tostring(ts)

echo("mana_report: " .. name .. " cur=" .. cur .. " max=" .. max .. " cap=" .. cap)
