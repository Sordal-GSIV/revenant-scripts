--- @revenant-script
--- name: fly
--- version: 1.0.0
--- author: Ryjex
--- game: gs
--- description: Premium teleportation and chronomage travel automation
--- tags: travel, teleport, chronomage, premium
---
--- Usage: ;fly <destination> [chrono]
--- Destinations: landing, teras, illistim, solhaven, rr, zul, vaalor, cys, icemule, kraken

local dest = script.vars[0] or ""
local use_chrono = dest:lower():match("chrono") and true or false
dest = dest:gsub("[Cc]hrono", ""):gsub("to ", ""):match("^%s*(.-)%s*$")

if script.vars[1] == "help" or dest == "" then
    echo("Usage: ;fly <destination>")
    echo("Destinations: landing, teras, illistim, solhaven, icemule, vaalor, zul, rr, kraken")
    exit()
end

local dest_name
if dest:match("[Ll]an") or dest:match("[Ww][Ll]") then dest_name = "Wehnimer's Landing"
elseif dest:match("[Ss]ol") or dest:match("[Ss][Hh]") then dest_name = "Solhaven"
elseif dest:match("[Ii]ce") or dest:match("[Mm]ule") then dest_name = "Icemule Trace"
elseif dest:match("[Ii]lli") or dest:match("[Tt][Ii]") then dest_name = "Ta'Illistim"
elseif dest:match("[Vv]al") or dest:match("[Tt][Vv]") then dest_name = "Ta'Vaalor"
elseif dest:match("[Zz]ul") or dest:match("[Zz][Ll]") then dest_name = "Zul Logoth"
elseif dest:match("[Tt]eras") or dest:match("[Kk][Dd]") then dest_name = "Kharam-Dzu"
elseif dest:match("[Rr][Rr]") or dest:match("[Rr]iver") then dest_name = "River's Rest"
elseif dest:match("[Cc]ys") then dest_name = "Cysaegir"
elseif dest:match("[Kk]rak") then dest_name = "Kraken's Fall"
else
    echo("Unknown destination. Use ;fly help")
    exit()
end

echo("Flying to " .. dest_name .. "...")
echo(";kill fly within 5 sec to cancel")
pause(5)

-- Try chronomage travel
Script.run("go2", "chronomage")
fput("stow right")
fput("stow left")
fput("ask clerk for " .. dest_name)
fput("ask clerk for " .. dest_name)
pause(1)

if checkleft() == "orb" or checkright() == "orb" then
    Script.run("go2", "chronomage")
    fput("read my orb")
    echo("Awaiting departure...")
else
    echo("Could not obtain travel orb. Check silvers and destination.")
end
