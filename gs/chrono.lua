--- @revenant-script
--- name: chrono
--- version: 1.0.0
--- author: Alastir
--- contributors: Ryjex
--- game: gs
--- description: Automates chronomage travel between major towns
--- tags: travel, chronomage, utility
---
--- Usage: ;chrono <town> [room#]
--- Example: ;chrono icemule 2300

if script.vars[1] == "help" then
    echo("Usage: ;chrono <town> [room#]")
    echo("Towns: landing, teras, illistim, solhaven, vaalor, icemule")
    exit()
end

local dest = script.vars[0] or ""
local endpoint = script.vars[2] and tonumber(script.vars[2]) or 4

-- Determine destination
local dest_name, ask_for
if dest:match("[Ww]eh") or dest:match("[Ll]an") or dest:match("[Ww][Ll]") then
    dest_name = "WL"; ask_for = "Wehnimer's Landing"
elseif dest:match("[Ss]ol") or dest:match("[Ss][Hh]") then
    dest_name = "SH"; ask_for = "Solhaven"
elseif dest:match("[Ii]ce") or dest:match("[Mm]ule") or dest:match("[Ii][Tt]") then
    dest_name = "IMT"; ask_for = "Icemule"
elseif dest:match("[Ii]lli") or dest:match("[Tt][Ii]") then
    dest_name = "TI"; ask_for = "Ta'Illistim"
elseif dest:match("[Vv]al") or dest:match("[Tt][Vv]") then
    dest_name = "TV"; ask_for = "Ta'Vaalor"
else
    echo("Unknown destination. Use: landing, solhaven, icemule, illistim, vaalor")
    exit()
end

echo("Heading to " .. dest_name)

-- Determine current location
local chrono_room, portal_room
local result = dothistimeout("location", 5, "You carefully survey")
if result and result:match("Wehnimer") then
    chrono_room = 8634; portal_room = 8635
elseif result and result:match("Icemule") then
    chrono_room = 8916; portal_room = 15619
elseif result and result:match("Solhaven") then
    chrono_room = 14358; portal_room = 14359
elseif result and result:match("Illistim") then
    chrono_room = 13169; portal_room = 1276
elseif result and result:match("Vaalor") then
    chrono_room = 5883; portal_room = 13779
else
    echo("Cannot determine current location!")
    exit()
end

-- Check for existing pass or buy one
Script.run("go2", tostring(chrono_room))

local silvers = Lich.silver_count and Lich.silver_count() or 0
if silvers < 5000 then
    Script.run("go2", "bank")
    fput("withdraw " .. (5000 - silvers) .. " sil")
    Script.run("go2", tostring(chrono_room))
end

fput("ask clerk for " .. ask_for)
fput("ask clerk for " .. ask_for)
pause(1)

Script.run("go2", tostring(portal_room))
fput("raise my day pass")
pause(2)
fput("stow my day pass")

if endpoint ~= 4 then
    Script.run("go2", tostring(endpoint))
end

echo("Arrived! Welcome to " .. dest_name)
