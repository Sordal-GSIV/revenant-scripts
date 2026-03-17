--- @revenant-script
--- name: ebounty
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Enhanced bounty management - track, accept, and complete bounty tasks
--- tags: bounty, tasks, hunting, money
---
--- Ported from ebounty.lic (Lich5) to Revenant Lua (3355 lines - core functionality)
---
--- Usage:
---   ;ebounty          - Check current bounty status
---   ;ebounty accept   - Accept a new bounty
---   ;ebounty help     - Show help

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "status"

local function show_help()
    echo("=== Enhanced Bounty ===")
    echo("Bounty task management for DragonRealms.")
    echo("")
    echo("Usage:")
    echo("  ;ebounty              - Check bounty status")
    echo("  ;ebounty accept       - Accept new bounty")
    echo("  ;ebounty status       - Show current bounty")
    echo("  ;ebounty help         - This help")
    echo("")
    echo("Bounty types: bandit, creature, gem, herb, rescue, escort, forage")
end

local function check_bounty()
    local result = DRC.bput("task", {
        "You have no current task",
        "You have been tasked",
        "You were tasked",
        "Your current task is",
    })
    echo("Bounty status: " .. result)
    return result
end

if cmd == "help" then
    show_help()
elseif cmd == "accept" then
    echo("Accepting new bounty...")
    fput("task receive")
    pause(2)
    check_bounty()
else
    check_bounty()
end
