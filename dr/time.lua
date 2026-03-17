--- @revenant-script
--- name: time
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Display DR in-game time and moon rise/set timers.
--- tags: time, moons, utility
--- Converted from time.lic

local now = os.time()
local daycal = 15335
local daycycle = (now + daycal) % 21600
local dayhour = math.floor(daycycle / 3600)
local dayminute = math.floor((daycycle % 3600) / 60)
local daysecond = daycycle % 60

local rwtime = daycycle * 4
local rwhour = math.floor(rwtime / 3600)
local rwminute = math.floor((rwtime % 3600) / 60)
local ampm = rwhour > 11 and "PM" or "AM"
if rwhour > 12 then rwhour = rwhour - 12 end

-- Moon data
local moons = {
    {name="Katamba", vis=10601, hid=10486, cycle=21087, cal=17376},
    {name="Xibar", vis=10472, hid=10373, cycle=20844, cal=1640},
    {name="Yavash", vis=10622, hid=10502, cycle=21124, cal=4798},
}

echo(string.format("   DR time:        %d:%02d:%02d", dayhour, dayminute, daysecond))
echo(string.format("   RW equivalent:  %d:%02d:%02d %s", rwhour, rwminute, daysecond, ampm))
echo("")
for _, m in ipairs(moons) do
    local mnow = (now + m.cal) % m.cycle
    local state, dur
    if mnow > m.vis then
        state = "HIDDEN, rises in"
        dur = m.cycle - mnow
    else
        state = "VISIBLE, sets in"
        dur = m.vis - mnow
    end
    local h = math.floor(dur / 3600)
    local mi = math.floor((dur % 3600) / 60)
    echo(string.format("   %-10s %s %d:%02d", m.name, state, h, mi))
end
