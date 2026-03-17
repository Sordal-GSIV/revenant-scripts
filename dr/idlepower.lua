--- @revenant-script
--- name: idlepower
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Periodic concentration/perception/health actions while idle.
--- tags: training, idle, perception
---
--- Usage: ;idlepower [cycle_time]

local cycle_time = tonumber(Script.vars[1]) or 60

local function do_concentrate()
    local guild = DRStats.guild or ""
    if guild:match("Moon Mage") or guild:match("Warrior Mage") or guild:match("Trader") then
        fput("perc")
        waitrt()
    end
end

local function do_health()
    local guild = DRStats.guild or ""
    if guild:match("Empath") then
        fput("perc health")
        waitrt()
    end
end

local function do_hunt()
    if DRSkill.getxp("Perception") < 33 then
        fput("hunt")
        waitrt()
    end
end

while true do
    do_concentrate()
    do_hunt()
    do_health()
    pause(cycle_time)
end
