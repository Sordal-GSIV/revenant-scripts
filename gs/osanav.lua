--- @revenant-script
--- name: osanav
--- version: 2.0.0
--- author: Peggyanne
--- game: gs
--- tags: sailing, navigation, ships, OSA
--- description: Navigate from one port to another using OSACrew methods
---
--- Original Lich5 authors: Peggyanne
--- Ported to Revenant Lua from osanav.lic v2.0.0
---
--- Usage:
---   ;osanav       - navigate from your ship
---   ;osanav help  - show help

local args = Script.current.vars

local function show_help()
    respond("OSANav Version: 2.0.0 (March 3, 2025)")
    respond("")
    respond("   Usage:")
    respond("   ;osanav       Must be ran from your ship and will navigate from one port to another.")
    respond("")
    respond("   Simple script to sail from one port to another.")
    respond("   In order for this to run, you must be using OSACrew.")
    respond("   This is a slave script set to run methods from OSACrew.")
    respond("")
    respond("   ~Peggyanne")
end

if args[1] and (args[1]:lower() == "help" or args[1] == "?") then
    show_help()
    return
end

if args[1] and args[1] == "version" then
    respond("")
    respond("OSANav Version 2.0.0")
    respond("")
    return
end

if not Script.running("osacrew") then
    respond("")
    respond("          ***** OSACrew is not running, please run OSACrew before using navigation ******")
    respond("")
else
    local cur = Room.current()
    if not cur or cur.location ~= "Ships" then
        respond("")
        respond("          Please Restart When You Are On Your Ship")
        respond("")
    else
        -- These methods are defined by OSACrew
        -- ship_map()
        -- crew_start_nav()
        echo("OSANav requires OSACrew methods ship_map() and crew_start_nav() to be available.")
        echo("Please ensure OSACrew is running and provides these functions.")
    end
end
