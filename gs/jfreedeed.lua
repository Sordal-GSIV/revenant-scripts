--- @revenant-script
--- name: jfreedeed
--- version: 1.0.0
--- author: Jara
--- game: gs
--- tags: deeds, bank, temple, free account
--- description: Free-account deed script - buy 5 rubies and get deeds at the Landing temple
---
--- Original Lich5 authors: Jara
--- Ported to Revenant Lua from jfreedeed.lic
---
--- Usage: ;jfreedeed

silence_me()

local lootsack = UserVars.get("lootsack") or "pack"

local function getdeeds()
    Script.run("go2", "9269")
    fput("ord 5 14")
    fput("buy")
    fput("open my package")
    if lootsack == "pack" then
        fput("empty my package in my other " .. lootsack)
    else
        fput("empty my package in my " .. lootsack)
    end
    waitrt()
    wait(2)
    fput("drop package")
    fput("stow all")
    Script.run("go2", "4044")

    for _ = 1, 5 do
        fput("go tapestry")
        fput("ring chime with mallet")
        fput("ring chime with mallet")
        fput("kneel")
        fput("get my dwarf ruby from my " .. lootsack)
        fput("drop my dwarf ruby")
        fput("ring chime with mallet")
        fput("out")
    end

    Script.run("go2", "400")
    fput("deposit all")
    Script.run("go2", "town")
    wait(1)
    respond("")
    respond("You should have more deeds now.")
    respond("Thanks for using Jdeed!")
    respond("")
end

if checkleft() and checkright() then
    fput("stow all")
elseif checkright() then
    fput("stow right")
elseif checkleft() then
    fput("stow left")
end

if Regex.test(checkarea() or "", "Icemule Trace") then
    if Script.exists("jfloo") then
        Script.run("jfloo", "")
    end
end

Script.run("go2", "400")
fput("deposit all")
fput("open my " .. lootsack)
wait(3)

local note_amount = 50000
if Char.race == "Half-Krolvin" then
    note_amount = 75000
end

local result = dothistimeout("withdraw " .. note_amount .. " note", 5,
    "carefully records|makes some marks|through the books")

if result and Regex.test(result, "carefully records|makes some marks") then
    getdeeds()
elseif result and Regex.test(result, "through the books") then
    respond("Not enough money in bank to buy deeds.")
    respond("Try again when you have at least 50000 silvers.")
end
