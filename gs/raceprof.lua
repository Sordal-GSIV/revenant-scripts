--- @revenant-script
--- name: raceprof
--- version: 1.0.1
--- author: Parwyn
--- game: gs
--- description: Display character race and profession in Also Here section
--- tags: utility, race, profession, display
---
--- Usage:
---   ;raceprof              - Start the display hook
---   ;raceprof race <name> <race>  - Add/update race
---   ;raceprof prof <name> <prof>  - Add/update profession
---   ;raceprof remove <name>       - Remove a character
---   ;raceprof scan                - Scan WHO list
---   ;raceprof short/long          - Toggle display format

CharSettings["player_races"] = CharSettings["player_races"] or {}
CharSettings["player_professions"] = CharSettings["player_professions"] or {}

local SHORT_RACES = {Aelotoi="Ael", ["Burghal Gnome"]="BGn", ["Dark Elf"]="DkEf", Dwarf="Dw", Elf="Elf", Erithian="Er", ["Forest Gnome"]="FGn", Giantman="G", ["Half-Elf"]="H/E", ["Half-Krolvin"]="H/K", Halfling="Hf", Human="H", Sylvankind="Syl"}
local SHORT_PROFS = {Bard="Brd", Cleric="Clr", Empath="Emp", Monk="Mnk", Paladin="Pal", Ranger="Rgr", Rogue="Rog", Sorcerer="Sor", Warrior="War", Wizard="Wiz"}

local use_short = CharSettings["use_short"] or false

local args = script.vars
if args[1] == "race" and args[2] and args[3] then
    local name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
    CharSettings["player_races"][name] = args[3]
    echo(name .. " race set to " .. args[3])
elseif args[1] == "prof" and args[2] and args[3] then
    local name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
    CharSettings["player_professions"][name] = args[3]
    echo(name .. " profession set to " .. args[3])
elseif args[1] == "remove" and args[2] then
    local name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
    CharSettings["player_races"][name] = nil
    CharSettings["player_professions"][name] = nil
    echo(name .. " removed.")
elseif args[1] == "short" then
    CharSettings["use_short"] = true
    echo("Using shortened display.")
elseif args[1] == "long" then
    CharSettings["use_short"] = false
    echo("Using full display.")
elseif args[1] == "help" then
    respond(";raceprof race <name> <race> / prof <name> <prof> / remove <name> / scan / short / long")
else
    -- Run display hook
    echo("Raceprof display active. Use ;kill raceprof to stop.")

    add_hook("downstream", "raceprof_display", function(line)
        if line:match("Also here:") then
            for name in line:gmatch('noun="([^"]+)"') do
                local race = CharSettings["player_races"][name]
                local prof = CharSettings["player_professions"][name]
                if race or prof then
                    local r = race or "?"
                    local p = prof or "?"
                    if CharSettings["use_short"] then
                        r = SHORT_RACES[r] or r
                        p = SHORT_PROFS[p] or p
                    end
                    line = line:gsub(name .. "</a>", name .. " (" .. r .. "-" .. p .. ")</a>")
                end
            end
        end
        return line
    end)

    before_dying(function() remove_hook("downstream", "raceprof_display") end)
    while true do pause(1) end
end
