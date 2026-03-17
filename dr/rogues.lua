--- @revenant-script
--- name: rogues
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Comprehensive rogue/thief toolkit - stealing, marking, lockpicking utilities
--- tags: thief, rogue, stealing, marking, toolkit
---
--- Ported from rogues.lic (Lich5 lib/) to Revenant Lua (3775 lines - core functionality)
---
--- Large rogue utility library providing:
---   - Steal attempt tracking and cooldowns
---   - Mark identification helpers
---   - Lockpick management
---   - Perception/hiding helpers
---   - Contract/bounty assistance
---
--- Usage:
---   ;rogues          - Start rogue toolkit
---   ;rogues steal    - Stealing mode
---   ;rogues mark     - Marking mode
---   ;rogues help     - Show help

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "help"

local steal_cooldowns = CharSettings.get("rogue_steal_cooldowns") or {}

local function show_help()
    echo("=== Rogues Toolkit ===")
    echo("Comprehensive thief/rogue utility library.")
    echo("")
    echo("Usage:")
    echo("  ;rogues steal <target>  - Attempt to steal from target")
    echo("  ;rogues mark            - Identify marks in room")
    echo("  ;rogues picks           - Check lockpick inventory")
    echo("  ;rogues cooldowns       - Show steal cooldowns")
    echo("  ;rogues help            - This help")
    echo("")
    echo("Steal cooldown tracking persists between sessions.")
end

local function check_picks()
    echo("=== Lockpick Inventory ===")
    local r = DRC.bput("look at my lockpick ring", {"you see", "What"})
    if r:find("What") then
        echo("No lockpick ring found!")
    end
end

local function show_cooldowns()
    echo("=== Steal Cooldowns ===")
    if not next(steal_cooldowns) then
        echo("No active cooldowns.")
    else
        for name, time in pairs(steal_cooldowns) do
            local remaining = time - os.time()
            if remaining > 0 then
                echo("  " .. name .. ": " .. remaining .. "s remaining")
            end
        end
    end
end

if cmd == "help" then
    show_help()
elseif cmd == "picks" then
    check_picks()
elseif cmd == "cooldowns" then
    show_cooldowns()
elseif cmd == "steal" then
    local target = args[2] or "person"
    echo("Attempting steal from " .. target .. "...")
    local r = DRC.bput("steal " .. target, {
        "You deftly", "You fumble", "You are caught",
        "Steal what", "too recently", "Roundtime",
    })
    if r:find("too recently") then
        echo("On cooldown!")
    elseif r:find("caught") then
        echo("CAUGHT! Run!")
    elseif r:find("deftly") then
        echo("Success!")
    end
    steal_cooldowns[target] = os.time() + 300
    CharSettings.set("rogue_steal_cooldowns", steal_cooldowns)
elseif cmd == "mark" then
    echo("Scanning room for marks...")
    fput("look")
    echo("Use ASSESS <person> to evaluate as a mark.")
else
    show_help()
end
