--- @revenant-script
--- name: dirty_deeds
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Rogue/thief deed tracking and automation
--- tags: thief, rogue, deeds, tracking
---
--- Ported from dirty-deeds.lic (Lich5 lib/) to Revenant Lua
---
--- Tracks and automates various rogue/thief deeds and activities.
---
--- Usage:
---   ;dirty_deeds          - Start deed tracking
---   ;dirty_deeds list     - Show tracked deeds
---   ;dirty_deeds help     - Show help

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "start"

local deeds = CharSettings.get("dirty_deeds_log") or {}

local function show_help()
    echo("=== Dirty Deeds ===")
    echo("Rogue/Thief deed tracking and automation.")
    echo("")
    echo("Usage:")
    echo("  ;dirty_deeds          - Start tracking")
    echo("  ;dirty_deeds list     - Show deed log")
    echo("  ;dirty_deeds reset    - Clear deed log")
    echo("  ;dirty_deeds help     - This help")
end

local function show_list()
    echo("=== Deed Log ===")
    if #deeds == 0 then
        echo("No deeds recorded.")
    else
        for i, d in ipairs(deeds) do
            echo("  " .. i .. ". " .. d)
        end
    end
end

if cmd == "help" then
    show_help()
elseif cmd == "list" then
    show_list()
elseif cmd == "reset" then
    deeds = {}
    CharSettings.set("dirty_deeds_log", deeds)
    echo("Deed log cleared.")
else
    echo("=== Dirty Deeds ===")
    echo("Tracking rogue activities...")
    while true do
        local line = get()
        if line then
            if line:find("You .* steal") or line:find("You .* pick.*pocket")
                or line:find("You .* mark ") or line:find("You .* backstab") then
                table.insert(deeds, os.date() .. ": " .. line)
                CharSettings.set("dirty_deeds_log", deeds)
            end
        end
    end
end
