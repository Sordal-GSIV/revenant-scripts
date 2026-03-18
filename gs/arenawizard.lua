--- @revenant-script
--- name: arenawizard
--- version: 0.7
--- author: Elvidor
--- game: gs
--- description: Duskruin arena automation for bolting wizards
--- tags: duskruin, arena, wizard, combat
---
--- Usage: ;arenawizard help - show settings
---        ;arenawizard      - start (unpause when ready)

if script.vars[1] then
    respond("Duskruin Arena Wizard Script")
    respond("Set your lootsack: ;vars set lootsack=<container>")
    respond("Set book container: ;vars set eventsack=<container>")
    respond("Primary bolt (default 903): ;vars set primarybolt=<spell#>")
    respond("Secondary bolt (default 904): ;vars set secondarybolt=<spell#>")
    respond("Use rapid fire: ;vars set userapidfire=true/false")
    exit()
end

local primary = Vars.primarybolt or "903"
local secondary = Vars.secondarybolt or "904"
local use_rapid = Vars.userapidfire ~= "false" and Spell[515].known
local use_rest = Vars.userest ~= "false"
local rest_pct = tonumber(Vars.restuntil) or 50

echo("lootsack: " .. (Vars.lootsack or "not set"))
echo("Primary: " .. primary .. " | Secondary: " .. secondary)
echo("Unpause to begin")
pause_script()

local function start_entry()
    fput("get my booklet from my " .. (Vars.eventsack or "pack"))
    move("go entrance")
    fput("put my booklet in my " .. (Vars.eventsack or "pack"))
end

local function combat()
    local npcs = GameObj.npcs()
    local target = npcs and npcs[1]
    if not target then return end

    while target and not (target.status and target.status:match("dead|gone")) and not dead() do
        waitcastrt(); waitrt()
        if not standing() then fput("stand") end

        if use_rapid and not Spell[515].active and Spell[515].affordable then
            fput("incant 515")
        end

        local spell = primary
        if target.name and target.name:match("tsark|elemental|fire giant") then spell = secondary end

        if Spell[tonumber(spell)].affordable then
            fput("stance off")
            fput("incant " .. spell)
            fput("stance guard")
        else
            fput("mana pulse")
            pause(3)
        end

        npcs = GameObj.npcs()
        target = npcs and npcs[1]
    end
    fput("stance def")
end

local function collect_loot()
    fput("open my package")
    fput("empty my package into my " .. (Vars.lootsack or "pack"))
    pause(1)
    fput("drop package")
end

-- Navigate to arena
if not Room.title:match("Sands Approach") then
    Script.run("go2", "23780")
end

while true do
    if checkleft() and checkleft():match("package") then
        collect_loot()
    elseif Room.title and Room.title:match("Dueling Sands") then
        combat()
    elseif Room.title and Room.title:match("Sands Approach") then
        if use_rest then
            while percentmind() > rest_pct do pause(15) end
        end
        start_entry()
    else
        Script.run("go2", "23780")
    end
end
