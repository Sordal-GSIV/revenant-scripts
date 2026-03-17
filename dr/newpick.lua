--- @revenant-script
--- name: newpick
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Advanced lockpicking script with intelligent difficulty assessment
--- tags: lockpicking, boxes, thief, advanced
---
--- Ported from newpick.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;newpick <container>   - Pick all boxes from container
---   ;newpick               - Pick box in hand

local container = Script.vars[1]

local box_types = {"chest","casket","trunk","caddy","strongbox","skippet","box","crate","coffer"}

local too_hard = {
    "Prayer would be a good start",
    "really don't have any chance",
    "jump off a cliff",
    "same shot as a snowball",
    "pitiful snowball",
}

local function is_too_hard(result)
    for _, p in ipairs(too_hard) do
        if result:find(p) then return true end
    end
    return false
end

local function assess_difficulty(result)
    if result:find("grandmother") or result:find("blindfolded") then return "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") then return "quick"
    elseif result:find("precisely") or result:find("minor troubles") then return "normal"
    elseif result:find("edge on you") or result:find("some chance") then return "careful"
    elseif result:find("odds are against") or result:find("longshot") or result:find("minimal") then return "careful"
    end
    return "normal"
end

local function disarm_box(box_prefix)
    waitrt()
    local id_cmd = "disarm " .. box_prefix .. "identify"
    local result = DRC.bput(id_cmd, {
        "grandmother could", "blindfolded", "trivially constructed",
        "simple matter for you to disarm", "should not take long",
        "precisely at your skill level", "with only minor troubles",
        "edge on you", "some chance of being able to disarm",
        "odds are against", "would be a longshot", "minimal chance",
        "Prayer would be a good", "really don't have any chance",
        "jump off a cliff", "snowball", "fails to reveal",
        "seems harmless", "already disarmed",
    })

    if result:find("harmless") or result:find("already disarmed") then return true end
    if is_too_hard(result) then return false end
    if result:find("fails to reveal") then return disarm_box(box_prefix) end

    local speed = assess_difficulty(result)

    while true do
        waitrt()
        local r = DRC.bput("disarm " .. box_prefix .. speed, {
            "proves too difficult", "not yet fully disarmed",
            "did not disarm", "caused something to shift",
            "unable to make any progress", "Roundtime",
        })
        if r:find("Roundtime") then break end
    end

    -- Analyze and harvest
    waitrt()
    DRC.bput("disarm " .. box_prefix .. "analyze", {"unable to determine", "already analyzed", "Roundtime"})
    waitrt()
    local hr = DRC.bput("disarm " .. box_prefix .. "harvest", {
        "fumble around", "too much", "unsuitable", "harvested", "Roundtime",
    })
    if hr:find("Roundtime") then
        waitrt()
        fput("stow left")
    end
    return true
end

local function pick_box(box_prefix)
    waitrt()
    DRC.bput("pick " .. box_prefix .. "analyze", {"unable to determine", "Roundtime"})
    waitrt()
    local result = DRC.bput("pick " .. box_prefix .. "identify", {
        "fails to teach", "grandmother", "blindfolded",
        "trivially constructed", "should not take long",
        "simple matter", "precisely", "minor troubles",
        "edge on you", "some chance", "odds are against",
        "longshot", "minimal", "Prayer", "really don't",
        "cliff", "snowball", "not even locked",
    })

    if result:find("not even locked") then return true end
    if is_too_hard(result) then return false end
    if result:find("fails to teach") then return pick_box(box_prefix) end

    local speed = assess_difficulty(result)

    while true do
        waitrt()
        local r = DRC.bput("pick " .. box_prefix .. speed, {
            "unable to make any progress",
            "another lock protecting",
            "Roundtime",
        })
        if r:find("Roundtime") then return true end
        if r:find("another lock") then return pick_box(box_prefix) end
    end
end

local function loot_and_dismantle(box)
    waitrt()
    fput("open my " .. box)
    pause(0.5)
    -- Get gems and coins
    fput("fill my pouch with " .. box)
    while true do
        local r = DRC.bput("get coin", {"You pick up", "What were you"})
        if r:find("What") then break end
    end
    DRC.bput("dismantle " .. box .. " salvage", {"repeat this request", "Roundtime"})
    waitrt()
end

if container then
    -- Process boxes from container
    while true do
        local box = nil
        local result = DRC.bput("look in my " .. container, box_types)
        for _, bt in ipairs(box_types) do
            if result:find(bt) then box = bt; break end
        end
        if not box then
            echo("No more boxes!")
            break
        end
        fput("get my " .. box .. " from my " .. container)
        pause(0.5)
        local prefix = "my " .. box .. " "
        if disarm_box(prefix) and pick_box(prefix) then
            loot_and_dismantle(box)
        else
            fput("put my " .. box .. " in my " .. container)
        end
    end
else
    -- Process box in hand
    local box = checkright() or "box"
    if disarm_box("") and pick_box("") then
        loot_and_dismantle(box)
    end
end

echo("Newpick complete!")
