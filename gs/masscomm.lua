--- @revenant-script
--- name: masscomm
--- version: 2025.09.06
--- author: Vailan
--- game: gs
--- description: Mass spell casting coordinator with announcements (blurs 911, guards 419, colors 611)
--- tags: spellup, mass, blur, guard, color
---
--- Usage:
---   ;masscomm help          - Show help
---   ;masscomm now           - Cast immediately
---   ;masscomm here          - Announce in room, wait 2 min, cast

local blur_planned, guard_planned, color_planned = true, true, true
local announce_room = false
local block_announce = false

for _, arg in ipairs(script.vars) do
    local a = arg:lower()
    if a == "help" then
        respond("masscomm - Mass spell casting coordinator")
        respond(";masscomm now    - Cast immediately")
        respond(";masscomm here   - Announce in room and cast")
        respond(";masscomm spell=blurs/guards/colors - Restrict to one spell")
        exit()
    elseif a == "now" then block_announce = true; announce_room = false
    elseif a == "here" then announce_room = true
    elseif a:match("^spell=") then
        local spell = a:gsub("spell=", "")
        if spell:match("blur") then guard_planned = false; color_planned = false
        elseif spell:match("guard") then blur_planned = false; color_planned = false
        elseif spell:match("color") then blur_planned = false; guard_planned = false end
    end
end

if not script.vars[1] then
    respond("Usage: ;masscomm [now|here|spell=<type>|help]")
    exit()
end

-- Determine what we can cast
local blur_cycle = (Spell[911].known and blur_planned) and (math.floor(250 / (20 + (Spells.wizard or 0))) + 1) or nil
local guard_cycle = (Spell[419].known and guard_planned) and (math.floor(250 / (20 + (Spells.minorelemental or 0))) + 1) or nil
local color_cycle = (Spell[611].known and color_planned) and (math.floor(250 / (20 + (Spells.ranger or 0))) + 1) or nil

if not blur_cycle and not guard_cycle and not color_cycle then
    echo("You don't know any mass spells (611, 911, 419).")
    exit()
end

fput("group open")

-- Announce if needed
if not block_announce and announce_room then
    local spells = {}
    if blur_cycle then table.insert(spells, "Blurs") end
    if guard_cycle then table.insert(spells, "Guards") end
    if color_cycle then table.insert(spells, "Colors") end
    fput("recite Casting " .. table.concat(spells, " and ") .. " in two minutes!")
    pause(90); echo("30 seconds")
    fput("recite 30 seconds! Last call!")
    pause(20)
    fput("recite Casting in 10 seconds!")
    pause(10)
end

-- Cast spells
if blur_cycle then
    for i = 1, blur_cycle do
        while not Spell[911].affordable do pause(3) end
        Spell[911].cast()
        waitcastrt()
    end
end
if guard_cycle then
    for i = 1, guard_cycle do
        while not Spell[419].affordable do pause(3) end
        Spell[419].cast()
        waitcastrt()
    end
end
if color_cycle then
    for i = 1, color_cycle do
        while not Spell[611].affordable do pause(3) end
        Spell[611].cast()
        waitcastrt()
    end
end

if announce_room then
    fput("recite That should be four hours! Stay safe!")
end
