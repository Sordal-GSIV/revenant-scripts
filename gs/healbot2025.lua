--- @revenant-script
--- name: healbot2025
--- version: 0.76
--- author: Daedeus
--- contributors: Gib, Auryana
--- game: gs
--- description: Empath heal bot - responds to heal requests, appraises targets, tracks empaths
--- tags: empath, healing, healbot
---
--- Usage: ;healbot2025
---        ;healbot2025 invasion  - faster healing mode

local invasion = script.vars[1] and script.vars[1]:lower() == "invasion"
if invasion then echo("*** INVASION MODE ***") end

CharSettings["known_empaths"] = CharSettings["known_empaths"] or {}

local function gd_wound_transfer(person)
    fput("appraise " .. person)
    local line = matchwait("You take a quick appraisal")
    if not line then return end
    local parts = {"head","neck","right eye","left eye","back","chest","abdomen","left arm","right arm","left hand","right hand","left leg","right leg"}
    for _, part in ipairs(parts) do
        if line:match(part) then
            put("transfer " .. person .. " " .. part)
            pause(0.25)
        end
    end
    if not line:match("no apparent injuries") then
        while checkhealth() > 75 do
            fput("transfer " .. person)
            local r = matchwait("You take", "Nothing happens")
            if r:match("Nothing") then break end
        end
    end
end

local function healme()
    if checkhealth() < maxhealth() then fput("cure") end
    for _, part in ipairs({"head","left arm","right arm","nerves","left eye","right eye","left hand","right hand"}) do
        if Wounds[part] and Wounds[part] >= 2 then
            waitrt(); waitcastrt()
            if checkmana() >= 10 then fput("cure " .. part) end
        end
    end
end

echo("HealBot ready. Known empaths: " .. #CharSettings["known_empaths"])

while true do
    local line = matchwait(10, "whispers", "says", "asks", "taps you")

    if line then
        local healee = line:match("(%u%l+).*[whispers|says|asks].*heal")
            or line:match("(%u%l+).*[whispers|says|asks].*bleed")
            or line:match("(%u%l+).*[whispers|says|asks].*wound")
            or line:match("(%u%l+) taps you")

        if healee and not CharSettings["known_empaths"][healee] then
            echo("Healing " .. healee .. "...")
            local wait = invasion and 3 or 6
            if percentmind() > 70 then wait = 20 end
            pause(wait)

            fput("nod " .. healee)
            pause(2)
            gd_wound_transfer(healee)
        end
    end

    healme()
end
