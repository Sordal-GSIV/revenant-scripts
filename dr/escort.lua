--- @revenant-script
--- name: escort
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Navigation escort script - handles special travel paths between towns in DR
--- tags: travel, navigation, escort, ferry, bridge
---
--- Ported from escort.lic (Lich5) to Revenant Lua
---
--- Used by map pathing system for special inter-town travel segments.
--- Handles ferries, rope bridges, wilderness paths, and other non-standard navigation.
---
--- Usage:
---   ;escort   - Auto-detect current location and handle transit

local function detect_and_escort()
    local result = DRC.bput("look", {
        "Stone Bridge",
        "Stone Road",
        "Alfren's Ferry",
        "southern bank of the Segoltha",
        "aerie forgotten",
        "greying wooden boards",
        "Deer Trail",
        "North of a Ravine",
        "Rope Bridge",
        "thicket of scrub",
        "heavy brush scratches",
        "faint trail fades",
        "Scraggly trees",
        "Langenfirth Tree",
        "Stooping Cypress",
        "Galley Dock",
        "North Turnpike",
        "Obvious paths",
        "Obvious exits",
    })

    if result:find("Stone Bridge") then
        echo("Riverhaven to Crossing express path...")
        -- Haven to Crossing
        move("east")
    elseif result:find("Stone Road") then
        echo("Crossing to Riverhaven express path...")
        move("west")
    elseif result:find("Alfren's Ferry") then
        echo("Taking ferry across Segoltha River...")
        fput("go ferry")
        waitfor("reaches the dock")
    elseif result:find("southern bank") then
        echo("Ferry crossing from Leth side...")
        fput("go ferry")
        waitfor("reaches the dock")
    elseif result:find("aerie forgotten") then
        echo("Leth to Shard gondola...")
        fput("go platform")
    elseif result:find("greying wooden boards") then
        echo("Shard to Leth gondola...")
        fput("go platform")
    elseif result:find("Deer Trail") or result:find("North of a Ravine") or result:find("Rope Bridge") then
        echo("Crossing rope bridge...")
        move("go bridge")
    elseif result:find("Langenfirth Tree") then
        echo("Langenfirth to M'Riss ship...")
        fput("go galley")
    elseif result:find("Stooping Cypress") then
        echo("M'Riss departing...")
        fput("go galley")
    elseif result:find("Galley Dock") then
        echo("At galley dock, boarding...")
        fput("go galley")
    elseif result:find("North Turnpike") then
        echo("Handling Turnpike ritual area...")
        -- Check for people, move if needed
        move("north")
    else
        echo("No special escort needed at this location.")
    end
end

detect_and_escort()
