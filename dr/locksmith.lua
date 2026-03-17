--- @revenant-script
--- name: locksmith
--- version: 1.0.0
--- author: Crannach
--- game: dr
--- description: Box opening script - disarm traps, harvest components, pick locks
--- tags: lockpicking, boxes, traps, components
---
--- Ported from locksmith.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;locksmith   - Process box currently in hand (disarm, harvest, pick)

local function identify_trap()
    waitrt()
    local result = DRC.bput("disarm identify", {
        "It seems harmless",
        "already located and identified",
        "pinholes .* sealed with dirt",
        "lumpy green rune",
        "pin and shaft lodged",
        "pin lodged against the tumblers",
        "glass tube filled with a black gaseous",
        "pinholes .* indicate that something is awry",
        "shattered glass tube",
        "small black crystal",
        "nothing of interest",
        "bronze seal .* lock",
        "glass tube of milky%-white",
        "tiny bronze face",
        "tiny needle .* greenish",
        "Disarm what",
        "don't see any reason",
        "two silver studs",
        "harmlessly out",
        "rendering it harmless",
        "deflated bladder",
        "laughable matter",
        "fails to reveal",
    })

    if result:find("Disarm what") then return "no_box" end
    if result:find("seems harmless") or result:find("sealed with dirt") or result:find("harmlessly")
        or result:find("deflated bladder") or result:find("rendering it harmless") then
        return "disarmed"
    end
    if result:find("fails to reveal") then return "unknown" end
    return "identified"
end

local function disarm_trap()
    waitrt()
    local result = DRC.bput("disarm", {
        "not yet fully disarmed",
        "unable to make any progress",
        "Roundtime",
        "pack it into the pinholes",
        "shove the pin away",
        "wedge a small stick",
        "nudge the black crystal",
        "move the rune away",
        "pry the seal away",
        "bend it away from the tiny hammer",
        "pry the bronze face",
        "pry at the studs",
        "bend the head of the needle",
        "spits several clouds",
    })

    if result:find("not yet fully disarmed") then return "partial" end
    if result:find("unable to make") then return "retry" end
    return "done"
end

local function analyze_trap()
    waitrt()
    local result = DRC.bput("disarm analyze", {
        "retrieve the rune",
        "already analyzed",
        "unable to determine",
        "glass tubes .* worth something",
        "break the hammer off",
        "pull the crystal out",
        "pry the pin free",
        "detach the seal",
        "remove the hammer",
        "free it with some effort",
        "extract the needle",
        "extract the silver studs",
    })
    if result:find("unable to determine") then return false end
    return true
end

local function harvest_trap()
    waitrt()
    local result = DRC.bput("disarm harvest", {
        "already been completely harvested",
        "fumble around",
        "inept fumblings",
        "completely unsuitable",
        "unable to determine",
        "Roundtime",
    })
    if result:find("Roundtime") then
        waitrt()
        fput("stow left")
        return true
    end
    return false
end

local function identify_lock()
    waitrt()
    local result = DRC.bput("pick identify", {
        "not fully disarmed",
        "fails to teach you anything",
        "already inspected",
        "grandmother could open",
        "laughable matter",
        "would be a longshot",
        "Prayer would be a good",
        "some chance of being able",
        "precisely at your skill level",
        "simple matter for you to unlock",
        "trivially constructed",
        "should not take long",
        "not even locked",
        "minor troubles",
        "odds are against",
        "edge on you",
        "lockpick ring .* empty hand",
    })
    if result:find("not fully disarmed") then return "trapped" end
    if result:find("not even locked") then return "open" end
    if result:find("fails to teach") then return "unknown" end
    if result:find("empty hand") then
        fput("empty left hand")
        return "retry"
    end
    return "identified"
end

local function pick_lock()
    waitrt()
    local result = DRC.bput("pick", {
        "unable to make any progress",
        "another lock protecting",
        "not even locked",
        "more appropriate tool",
        "Roundtime",
    })
    if result:find("another lock") then return "more_locks" end
    if result:find("unable to make") then return "retry" end
    if result:find("not even locked") or result:find("Roundtime") then return "done" end
    if result:find("appropriate tool") then return "bad_tool" end
    return "done"
end

-- Main logic
local trap_status = identify_trap()
if trap_status == "no_box" then
    echo("No box in hand!")
    return
end

-- Disarm trap
while trap_status ~= "disarmed" do
    if trap_status == "unknown" then
        trap_status = identify_trap()
    elseif trap_status == "identified" then
        local dr = disarm_trap()
        if dr == "done" then
            trap_status = "disarmed"
        elseif dr == "partial" or dr == "retry" then
            -- continue
        end
    end
end

-- Analyze and harvest
if analyze_trap() then
    harvest_trap()
end

-- Pick lock
local lock_status = identify_lock()
while lock_status ~= "open" do
    if lock_status == "unknown" or lock_status == "retry" or lock_status == "trapped" then
        lock_status = identify_lock()
    elseif lock_status == "identified" then
        local pr = pick_lock()
        if pr == "done" then
            lock_status = "open"
        elseif pr == "more_locks" then
            lock_status = identify_lock()
        end
    end
end

echo("Box opened!")
