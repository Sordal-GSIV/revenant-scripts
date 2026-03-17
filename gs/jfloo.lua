--- @revenant-script
--- name: jfloo
--- version: 1.0.0
--- author: Jara
--- game: gs
--- description: Instant chronomage day-pass travel between connected towns
--- tags: travel, chronomage, day pass
---
--- IMT <-> Landing, Ta'Vaalor <-> Ta'Illistim
--- Cost: 5k silvers per 24 hours

local function hand_check()
    if checkleft() and checkright() then fput("stow all")
    elseif checkright() then fput("stow right")
    elseif checkleft() then fput("stow left") end
end

local function silver_check()
    return (Lich.silver_count and Lich.silver_count() or 0) >= 5000
end

hand_check()

if not silver_check() then
    Script.run("go2", "bank")
    fput("withdraw 5000 silvers")
end

Script.run("go2", "chronomage")

local room_id = Room.current.id
local my_town, portal_room

if room_id == 8634 then my_town = "Landing"; portal_room = 8635
elseif room_id == 8916 then my_town = "Icemule"; portal_room = 15619
elseif room_id == 13169 then my_town = "Ta'Illistim"; portal_room = 1276
elseif room_id == 5883 then my_town = "Ta'Vaalor"
else
    echo("Not at a supported chronomage office.")
    exit()
end

-- Try existing pass
local result = dothistimeout("get my day pass", 5, "day pass from|Get what")
if result and result:match("day pass from") then
    -- Use existing pass
elseif result and result:match("Get what") then
    -- Buy new pass
    local dest
    if my_town == "Landing" then dest = "icemule"
    elseif my_town == "Icemule" then dest = "wehnimer"
    elseif my_town == "Ta'Illistim" then dest = "ta'vaalor"
    elseif my_town == "Ta'Vaalor" then dest = "ta'illistim" end

    local clerk = "clerk"
    if room_id == 8916 then clerk = "halfling"
    elseif room_id == 13169 then clerk = "attendant" end

    fput("ask " .. clerk .. " for " .. dest)
    fput("ask " .. clerk .. " for " .. dest)
end

-- Use the pass
if portal_room then
    Script.run("go2", tostring(portal_room))
elseif my_town == "Ta'Vaalor" then
    fput("go staircase")
end

result = dothistimeout("raise my day pass", 5, "whirlwind of color|pass is expired|not valid")
if result and result:match("whirlwind") then
    fput("stow my day pass")
    Script.run("go2", "town")
    echo("Thanks for using Jfloo!")
elseif result then
    fput("drop my day pass")
    echo("Pass invalid. Try again.")
end
