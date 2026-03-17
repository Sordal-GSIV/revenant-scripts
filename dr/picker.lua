--- @revenant-script
--- name: picker
--- version: 1.0.0
--- author: Gizmo
--- game: dr
--- description: Auto-picker for Thieves - disarm, harvest, pick, loot, and dismantle boxes from a container
--- tags: lockpicking, thief, boxes, components
---
--- Ported from picker.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;picker <container>   - Process all boxes in the given container
---
--- Requires: lockpick ring worn, hands free, componentsack and gempouch set

local container = Script.vars[1]
if not container then
    echo("Usage: ;picker <box_container>")
    return
end

local componentsack = CharSettings.get("componentsack") or "backpack"
local gempouch = CharSettings.get("gempouch") or "pouch"

local box_types = {"chest", "casket", "trunk", "caddy", "strongbox", "skippet", "box", "crate", "coffer"}

local too_hard_patterns = {
    "Prayer would be a good start",
    "really don't have any chance",
    "jump off a cliff",
    "same shot as a snowball",
    "pitiful snowball",
}

local function is_too_hard(result)
    for _, p in ipairs(too_hard_patterns) do
        if result:find(p) then return true end
    end
    return false
end

local function find_next_box()
    local result = DRC.bput("look in my " .. container, box_types)
    for _, bt in ipairs(box_types) do
        if result:find(bt) then return bt end
    end
    return nil
end

local function disarm_box()
    waitrt()
    local result = DRC.bput("disarm id", {
        "grandmother could defeat", "blindfolded",
        "trivially constructed", "simple matter for you to disarm",
        "should not take long", "precisely at your skill level",
        "with only minor troubles", "edge on you",
        "some chance of being able to disarm", "odds are against",
        "would be a longshot", "amazingly minimal chance",
        "Prayer would be a good", "really don't have any chance",
        "jump off a cliff", "same shot as a snowball", "pitiful snowball",
        "fails to reveal",
    })

    if is_too_hard(result) then return false end
    if result:find("fails to reveal") then return disarm_box() end

    local speed = ""
    if result:find("grandmother") or result:find("blindfolded") then speed = "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") then speed = "quick"
    elseif result:find("some chance") or result:find("odds are against") or result:find("longshot") or result:find("minimal chance") then speed = "care"
    end

    while true do
        waitrt()
        local r = DRC.bput("disarm " .. speed, {
            "proves too difficult", "not yet fully disarmed",
            "did not disarm", "caused something to shift",
            "unable to make any progress", "Roundtime",
        })
        if r:find("Roundtime") then break end
    end

    -- Analyze and harvest
    waitrt()
    DRC.bput("disarm anal", {"unable to determine", "Roundtime"})
    waitrt()
    local hr = DRC.bput("disarm harvest", {
        "fumble around", "too much for it to be successfully harvested",
        "but are unable to extract", "Roundtime",
    })
    if hr:find("Roundtime") then
        waitrt()
        fput("stow left in " .. componentsack)
    end
    return true
end

local function pick_box(box)
    waitrt()
    DRC.bput("pick anal", {"unable to determine", "Roundtime"})
    waitrt()
    local result = DRC.bput("pick id", {
        "fails to teach", "blindfolded", "grandmother could",
        "trivially constructed", "should not take long",
        "simple matter for you to unlock", "with only minor troubles",
        "got a good shot", "precisely at your skill level",
        "some chance of being able to pick", "odds are against",
        "would be a longshot", "amazingly minimal chance",
        "Prayer would be a good", "really don't have any chance",
        "jump off a cliff", "same shot as a snowball", "pitiful snowball",
    })

    if is_too_hard(result) then return false end
    if result:find("fails to teach") then return pick_box(box) end

    local speed = ""
    if result:find("grandmother") or result:find("blindfolded") then speed = "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") or result:find("minor troubles") then speed = "quick"
    elseif result:find("longshot") or result:find("minimal chance") then speed = "care"
    end

    while true do
        waitrt()
        local r = DRC.bput("pick " .. speed, {
            "unable to make any progress",
            "You discover another lock",
            "Roundtime",
        })
        if r:find("Roundtime") then break end
        if r:find("another lock") then return pick_box(box) end
    end
    return true
end

-- Main loop
while true do
    local box = find_next_box()
    if not box then
        echo("*** OUT OF BOXES! ***")
        break
    end

    fput("get my " .. box)
    pause(1)

    if not disarm_box() then
        echo("*** THIS BOX IS VERY HARD - SKIPPING ***")
        fput("put my " .. box .. " in my " .. container)
    else
        if pick_box(box) then
            waitrt()
            fput("open my " .. box)
            pause(0.5)
            fput("fill my " .. gempouch .. " with " .. box)
            pause(0.5)
            -- Get coins
            while true do
                local cr = DRC.bput("get coin", {"You pick up", "What were you referring to"})
                if cr:find("What were you") then break end
            end
            -- Dismantle
            DRC.bput("dismantle " .. box .. " salvage",
                {"repeat this request", "Roundtime"})
            waitrt()
        else
            echo("*** LOCK TOO HARD - SKIPPING ***")
            fput("put my " .. box .. " in my " .. container)
        end
    end
end
