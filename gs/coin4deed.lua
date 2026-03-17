--- @revenant-script
--- name: coin4deed
--- version: 1.1.3
--- author: Athias
--- game: gs
--- description: Get coins from the Landing bank and go buy a deed
--- tags: deeds,utility
---
--- Usage:
---   ;coin4deed calculate   show deed cost
---   ;coin4deed coin        get one deed
---   ;coin4deed coin five   get five deeds
---   ;coin4deed coin ten    get ten deeds
---   ;coin4deed help        show help

local DEED_ROOM = 4045

local function get_gs3_level()
    local exp = Char.exp()
    if exp < 50000 then
        return math.floor(exp / 10000)
    elseif exp < 150000 then
        return 5 + math.floor((exp - 50000) / 20000)
    elseif exp < 300000 then
        return 10 + math.floor((exp - 150000) / 30000)
    elseif exp < 500000 then
        return 15 + math.floor((exp - 300000) / 40000)
    else
        return 20 + math.floor((exp - 500000) / 50000)
    end
end

local function count_deeds()
    fput("experience")
    return Experience.deeds()
end

local function deed_cost()
    local cur_deeds = count_deeds()
    local cur_level = get_gs3_level()
    return ((cur_level * 100) + 101) + (20 * (cur_deeds * cur_deeds))
end

local function help_menu()
    echo("Get deeds using coins from the Landing")
    echo("Usage:")
    echo("  Show deed cost        ;coin4deed calculate")
    echo("  Get deed using coins  ;coin4deed coin")
    echo("  Get multiple deeds    ;coin4deed coin five|ten")
    return
end

local function deed_calc()
    echo("Amount of coins needed: " .. tostring(deed_cost()))
end

local function get_deed()
    local silver_needed = deed_cost()
    local return_room = Map.current_room()

    Script.run("go2", "bank")
    wait_while(function() return Script.running("go2") end)
    fput("deposit all silver")

    local result = dothistimeout("withdraw " .. silver_needed .. " silvers", 5,
        "seem to have that much|transaction, hands you")
    if not result then
        echo("Something went wrong!")
        Script.run("go2", tostring(return_room))
        return false
    end

    if result:find("seem to have that much") then
        echo("You don't have enough coins for a deed!")
        Script.run("go2", tostring(return_room))
        return false
    end

    Script.run("go2", tostring(DEED_ROOM))
    wait_while(function() return Script.running("go2") end)

    if Map.current_room() == DEED_ROOM then
        fput("ring chime with mallet")
        fput("ring chime with mallet")
        fput("kneel")
        fput("drop " .. silver_needed .. " silvers")
        local deed_res = dothistimeout("ring chime with mallet", 5,
            "Thy offering pleases the Goddess")
        Script.run("go2", tostring(return_room))
        wait_while(function() return Script.running("go2") end)
        if deed_res and deed_res:find("Thy offering pleases") then
            echo("You got yourself another deed!")
            return true
        else
            echo("Something went wrong!")
            return false
        end
    else
        Script.run("go2", tostring(return_room))
        echo("Couldn't reach deed room!")
        return false
    end
end

-- Main
local action = Script.vars[1]

if not action or action == "" or action:match("help") then
    help_menu()
elseif action:match("calc") then
    deed_calc()
elseif action:match("coin") or action:match("silver") then
    local location = GameState.room_location or ""
    if not location:match("Wehnimer's Landing") then
        echo("You need to be in Wehnimer's Landing to run this script.")
        return
    end
    local count = 1
    local modifier = Script.vars[2]
    if modifier then
        if modifier:match("five") then count = 5
        elseif modifier:match("ten") then count = 10
        end
    end
    for _ = 1, count do
        if not get_deed() then break end
    end
else
    help_menu()
end
