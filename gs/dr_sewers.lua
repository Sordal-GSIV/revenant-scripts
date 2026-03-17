--- @revenant-script
--- name: dr_sewers
--- version: 1.0.0
--- author: Alastir
--- game: gs
--- description: Duskruin Bloodriven Village sewer search automation
--- tags: duskruin, sewers, bloodscrip, event
---
--- Usage:
---   ;dr_sewers
---   Vars: lootsack, keepsack
---
--- Searches sewers and stows items. Tracks bloodscrip earnings.

echo("This script provided by Alastir")
echo("Variables used:")
echo("Vars.lootsack = Where treasure is stored: " .. (Vars.lootsack or "not set"))
echo("Vars.keepsack = Where special drops are stored: " .. (Vars.keepsack or "not set"))
echo("Bloodscrip will be automatically redeemed into your TICKET BALANCE.")
echo(";unpause dr_sewers if you are satisfied with this setup.")
pause_script()

local grand_total = 0

local function stand_up()
    if not standing() then
        fput("stance offensive")
        fput("stand")
    end
end

local function enter_sewers()
    if percentencumbrance() > 50 then
        echo("You're carrying too much stuff!")
        pause_script()
    end
    local result = dothistimeout("go grate", 5, "The tunnel sweeper accepts|You need to redeem")
    if result and result:match("tunnel sweeper accepts") then
        stand_up()
        move("up"); move("up"); move("out")
        return true
    else
        echo("Out of booklets!")
        exit()
    end
end

local function search_sewers()
    local total = 0
    local knocks_left = 10
    while true do
        if checkright() and checkleft() then
            echo("Your hands are full!")
            pause_script()
        end
        local result = dothistimeout("search", 5, "bloodscrip|crystal|etched stone|rat|odd gem|recently searched|wave of sewage|don't find anything|slime dribble")
        if not result then break end

        if result:match("don't find anything") then break end

        local scrip = result:match("find (%d+) bloodscrip")
        if scrip then
            knocks_left = knocks_left - 1
            total = total + tonumber(scrip)
            echo("Found " .. scrip .. " bloodscrip. (" .. knocks_left .. " left)")
        end

        if result:match("crystal") or result:match("etched stone") then
            echo("Special find!")
            fput("put my stone in my " .. (Vars.lootsack or "pack"))
        end

        if result:match("recently searched") or result:match("wave of sewage") then
            waitrt()
            walk()
        end
        waitrt()
    end
    return total
end

-- Main loop
if not Room.current.title:match("Sewer") then
    Script.run("go2", "u8214001")
    enter_sewers()
end

while true do
    if Room.current.title:match("Cesspool") then
        Script.run("go2", "u8214001")
    elseif Room.current.uid and Room.current.uid == 8214001 then
        enter_sewers()
    else
        local total = search_sewers()
        grand_total = grand_total + total
        echo("Run total: " .. total .. " bloodscrip")
        echo("Grand total: " .. grand_total .. " bloodscrip")
    end
end
