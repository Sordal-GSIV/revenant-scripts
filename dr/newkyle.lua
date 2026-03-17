--- @revenant-script
--- name: newkyle
--- version: 1.0.0
--- author: Kyle
--- game: dr
--- description: Updated hunting/combat script with buff management and weapon cycling
--- tags: combat, hunting, buffs, weapons, training
---
--- Ported from newkyle.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;newkyle <guild> <augm> <ward> <buffprep> <cambrinth>
---
--- Companion to ;newallpurpose for watchdog functionality.

local guild = Script.vars[1] or ""
local augm = Script.vars[2] or ""
local ward = Script.vars[3] or ""
local buffprep = Script.vars[4] or ""
local cambrinth = Script.vars[5] or ""

local function is_barb()
    return guild == "barb" or guild == "madm"
end

local function rebuff()
    if is_barb() then
        start_script("meditate")
        pause(1)
        start_script("warhorn")
        wait_while(function() return running("warhorn") end)
        return
    end

    -- Magic user rebuff
    fput("release")
    fput("prep " .. augm)
    if cambrinth ~= "" then
        fput("remove " .. cambrinth)
        fput("get " .. cambrinth)
        fput("charge " .. cambrinth .. " " .. buffprep)
        pause(1)
        waitrt()
        fput("invoke " .. cambrinth)
        pause(1)
        waitrt()
    end
    fput("cast")
    pause(1)
    waitrt()

    fput("release")
    fput("prep " .. ward)
    if cambrinth ~= "" then
        fput("charge " .. cambrinth .. " " .. buffprep)
        pause(1)
        waitrt()
        fput("invoke " .. cambrinth)
        pause(1)
        waitrt()
    end
    fput("cast")
    if cambrinth ~= "" then
        fput("wear " .. cambrinth)
    end
end

local function hunt_cycle()
    fput("hunt")
    pause(1)
    waitrt()

    -- Combat loop
    while true do
        waitrt()
        local r = DRC.bput("attack", {
            "Roundtime", "entangled in a web", "wait",
            "aren't close enough", "What do you want to advance",
            "fatigued", "tired", "exhausted",
            "nothing else to face", "You turn to",
            "What are you trying to attack",
        })

        if r:find("aren't close enough") or r:find("advance") then
            fput("advance")
            fput("bob")
        elseif r:find("nothing else to face") or r:find("You turn to") then
            fput("loot")
            fput("skin")
            waitrt()
            return true -- continue hunting
        elseif r:find("What are you trying") then
            return false -- need to find creatures
        elseif r:find("fatigued") or r:find("tired") or r:find("exhausted") then
            if is_barb() then
                fput("berserk avalanche")
                pause(2)
            else
                pause(5)
            end
        end
    end
end

echo("=== NewKyle Combat Script ===")
echo("Guild: " .. guild)

rebuff()

while true do
    if not hunt_cycle() then
        echo("No more targets. Rebuffing and searching...")
        rebuff()
        fput("hunt")
        pause(3)
    end
end
