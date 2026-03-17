--- @revenant-script
--- name: gemstone_tracker
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Track gemstone drops, values, and statistics across hunting sessions
--- tags: gems, tracking, loot, statistics
---
--- Ported from gemstone-tracker.lic (Lich5 lib/) to Revenant Lua
---
--- Monitors gem drops, tracks values, and provides session statistics.
---
--- Usage:
---   ;gemstone_tracker          - Start tracking gems
---   ;gemstone_tracker report   - Show current session stats
---   ;gemstone_tracker reset    - Reset counters

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "start"

local gems_found = CharSettings.get("gem_tracker_gems") or {}
local session_gems = {}
local total_value = 0

local function add_gem(name, value)
    table.insert(session_gems, { name = name, value = value or 0 })
    total_value = total_value + (value or 0)
end

local function show_report()
    echo("=== Gemstone Tracker Report ===")
    echo("Session gems found: " .. #session_gems)
    echo("Estimated total value: " .. total_value)
    echo("")
    if #session_gems > 0 then
        for i, g in ipairs(session_gems) do
            echo("  " .. i .. ". " .. g.name .. (g.value > 0 and (" (" .. g.value .. ")") or ""))
        end
    else
        echo("No gems tracked this session.")
    end
end

if cmd == "report" then
    show_report()
    return
elseif cmd == "reset" then
    session_gems = {}
    total_value = 0
    echo("Gemstone tracker reset.")
    return
end

echo("=== Gemstone Tracker ===")
echo("Monitoring for gem drops...")

-- Watch for gem-related messages
while true do
    local line = get()
    if line then
        -- Common gem pickup messages
        local gem = line:match("You pick up a[n]? (.+)")
            or line:match("You gather (.+ gem)")
            or line:match("You find a[n]? (.+ gem)")
        if gem then
            add_gem(gem, 0)
            echo("Gem tracked: " .. gem .. " (Total: " .. #session_gems .. ")")
        end
    end
end
