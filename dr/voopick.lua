--- @revenant-script
--- name: voopick
--- version: 1.0.0
--- author: Voodoo
--- game: dr
--- description: Box picking script with gem pouch management - disarm, pick, loot, fill pouches
--- tags: lockpicking, boxes, gems, pouches
---
--- Ported from voopick.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;voopick setup   - Configure containers
---   ;voopick         - Process all boxes

local box_sack = CharSettings.get("voopick_box_sack") or "backpack"
local loot_sack = CharSettings.get("voopick_loot_sack") or "backpack"
local empty_sack = CharSettings.get("voopick_empty_sack") or "backpack"

local args = Script.vars or {}
if args[1] and args[1]:lower():find("setup") then
    echo("=== VooPick Setup ===")
    echo("Set your containers via CharSettings:")
    echo("  voopick_box_sack   = container with boxes (current: " .. box_sack .. ")")
    echo("  voopick_loot_sack  = container for full gem pouches (current: " .. loot_sack .. ")")
    echo("  voopick_empty_sack = container for empty gem pouches (current: " .. empty_sack .. ")")
    return
end

local box_types = {"chest","skippet","casket","trunk","caddy","strongbox","box","crate","coffer"}

local function find_box()
    local result = DRC.bput("look in my " .. box_sack, box_types)
    for _, bt in ipairs(box_types) do
        if result:find(bt) then return bt end
    end
    return nil
end

local function disarm_box()
    waitrt()
    local result = DRC.bput("disarm ident", {
        "simple matter for you to disarm", "trivially constructed",
        "should not take long", "fails to reveal",
        "with only minor troubles", "precisely at your skill level",
        "edge on you", "could defeat this trap in her sleep",
        "blindfolded", "would be a longshot",
        "some chance", "Prayer would be a good",
        "odds are against", "blocking whatever would have come out",
        "safe", "harmless",
    })

    if result:find("blocking") or result:find("safe") or result:find("harmless") then
        return "already_disarmed"
    end
    if result:find("fails to reveal") then return disarm_box() end

    local speed = ""
    if result:find("sleep") or result:find("blindfolded") then speed = "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") then speed = "quick"
    elseif result:find("longshot") or result:find("some chance") or result:find("Prayer") or result:find("odds are against") then speed = "careful"
    end

    while true do
        pause(0.5)
        waitrt()
        local r = DRC.bput("disarm " .. speed, {
            "despite this mishap", "feeling your manipulation",
            "not yet fully disarmed", "unable to make any progress",
            "Roundtime",
        })
        if r:find("Roundtime") then break end
        if r:find("despite this mishap") then return disarm_box() end
    end
    return "disarmed"
end

local function analyze_and_harvest()
    waitrt()
    local ar = DRC.bput("disarm analyze", {"unable to determine", "already analyzed", "Roundtime"})
    if ar:find("unable") then
        return analyze_and_harvest()
    end
    waitrt()
    local hr = DRC.bput("disarm harvest", {"fumble around", "inept fumblings", "completely harvested", "Roundtime"})
    if hr:find("Roundtime") then
        waitrt()
        fput("stow left")
    end
end

local function pick_box(box)
    waitrt()
    local result = DRC.bput("pick my " .. box .. " ident", {
        "making any chance of picking it unlikely",
        "fails to teach", "precisely at your skill level",
        "should not take long", "junk barely worth",
        "simple matter for you", "blindfolded",
        "could open this in her sleep", "minor troubles",
        "some chance", "edge on you",
        "Prayer would be a good", "longshot",
        "odds are against", "why bother",
    })

    if result:find("why bother") then return true end
    if result:find("unlikely") then return false end
    if result:find("fails to teach") then return pick_box(box) end

    local speed = ""
    if result:find("sleep") or result:find("blindfolded") then speed = "blind"
    elseif result:find("should not take long") or result:find("junk") or result:find("simple matter") then speed = "quick"
    elseif result:find("longshot") or result:find("Prayer") or result:find("odds are against") then speed = "careful"
    end

    while true do
        waitrt()
        local r = DRC.bput("pick my " .. box .. " " .. speed, {
            "unable to make any progress",
            "soft click",
            "not even locked",
        })
        if r:find("soft click") then return pick_box(box) end  -- check for more locks
        if r:find("not even locked") then return true end
        -- retry on no progress
    end
end

-- Main loop
while true do
    local box = find_box()
    if not box then
        echo("*** Done - no more boxes! ***")
        break
    end

    fput("get " .. box)
    pause(0.5)

    local ds = disarm_box()
    if ds == "already_disarmed" or ds == "disarmed" then
        analyze_and_harvest()
    end

    if pick_box(box) then
        waitrt()
        fput("open my " .. box)
        pause(0.5)
        -- Get coins
        while true do
            local cr = DRC.bput("get coin", {"You pick up", "What"})
            if cr:find("What") then break end
        end
        -- Fill pouch
        local fr = DRC.bput("fill my pouch with my " .. box, {
            "fill your", "fill it with", "aren't any gems",
            "can't fit anything else",
        })
        if fr:find("can't fit") then
            fput("remove my pouch")
            fput("tie my pouch")
            fput("put my pouch in my " .. loot_sack)
            fput("get pouch from my " .. empty_sack)
            fput("wear my pouch")
            fput("fill my pouch with my " .. box)
        end
        -- Dismantle
        DRC.bput("dismantle my " .. box, {"repeat this request", "Roundtime"})
        waitrt()
    end
end
