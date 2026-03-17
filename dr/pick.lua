--- @revenant-script
--- name: pick
--- version: 1.0.0
--- author: Seped
--- game: dr
--- description: Full lockpicking automation - disarm, harvest, pick, loot boxes from a container
--- tags: lockpicking, thief, boxes, training
---
--- Ported from pick.lic (Lich5) to Revenant Lua
---
--- Requires: common, events, drinfomon, pick-setup
---
--- Usage:
---   ;pick   - Process boxes from configured container
---
--- Settings (via CharSettings):
---   box_source, box_storage, lockpick_type, use_lockpick_ring,
---   stop_on_mindlock, harvest_traps, lockpicking_armor,
---   gem_nouns, treasure_nouns, trash_nouns, pick_buff

local box_source = CharSettings.get("box_source") or "backpack"
local box_storage = CharSettings.get("box_storage") or "backpack"
local lockpick_type = CharSettings.get("lockpick_type") or "ordinary"
local use_ring = CharSettings.get("use_lockpick_ring") or false
local stop_on_ml = CharSettings.get("stop_on_mindlock") or false
local harvest = CharSettings.get("harvest_traps") or false
local armor = CharSettings.get("lockpicking_armor") or {}
local pick_buff = CharSettings.get("pick_buff") or ""

local box_nouns = {"chest", "box", "trunk", "coffer", "casket", "strongbox", "caddy", "skippet", "crate"}

Flags.add("disarm-more", "not yet fully disarmed")

local function stop_picking()
    return stop_on_ml and (DRSkill.getxp("Locksmithing") or 0) >= 34
end

local function get_boxes()
    local result = DRC.bput("look in my " .. box_source, box_nouns)
    for _, bn in ipairs(box_nouns) do
        if result:find(bn) then return true end
    end
    return false
end

local function disarm_box(box)
    waitrt()
    local result = DRC.bput("disarm my " .. box .. " identify", {
        "fails to reveal", "something to shift",
        "laughable matter", "grandmother could",
        "trivially constructed", "simple matter for you to disarm",
        "should not take long", "precisely at your skill level",
        "with only minor troubles", "edge on you",
        "some chance", "odds are against",
        "would be a longshot", "amazingly minimal",
        "Prayer would be a good", "really don't have any chance",
        "jump off a cliff", "snowball",
    })

    -- Too hard
    if result:find("longshot") or result:find("minimal") or result:find("Prayer")
        or result:find("really don't") or result:find("cliff") or result:find("snowball") then
        return false
    end

    if result:find("fails to reveal") or result:find("something to shift") then
        return disarm_box(box)
    end

    local speed = ""
    if result:find("grandmother") or result:find("blindfolded") then speed = "quick"
    elseif result:find("some chance") or result:find("odds are against") then speed = "careful"
    end

    waitrt()
    Flags.reset("disarm-more")
    local dr = DRC.bput("disarm my " .. box .. " " .. speed, {
        "Roundtime", "unable to make any progress",
        "springs out", "acid sprays", "scythe blade",
        "electrical charge", "cloud of thick green",
        "sharp snap", "blinding flash",
    })

    if dr:find("springs out") or dr:find("acid") or dr:find("scythe")
        or dr:find("electrical") or dr:find("green vapor") or dr:find("snap")
        or dr:find("flash") then
        echo("** SPRUNG TRAP **")
        return false
    end

    waitrt()

    -- Harvest if enabled
    if harvest then
        DRC.bput("disarm my " .. box .. " analyze", {"already analyzed", "unable to determine", "Roundtime"})
        waitrt()
        local hr = DRC.bput("disarm my " .. box .. " harvest", {
            "fumble around", "too much for it", "unsuitable",
            "already been completely harvested", "Roundtime",
        })
        if hr:find("Roundtime") then
            waitrt()
            if checkleft() then
                DRCI.dispose_trash(checkleft())
            end
        end
    end

    if Flags.get("disarm-more") then
        return disarm_box(box)
    end

    return true
end

local function pick_box(box)
    if not use_ring and not checkleft() then
        DRC.bput("get my lockpick", {"You get", "referring to"})
    end

    waitrt()
    local result = DRC.bput("pick my " .. box .. " ident", {
        "edge on you", "some chance", "odds are against",
        "longshot", "minimal chance",
        "trivially constructed", "simple matter",
        "should not take long", "precisely at",
        "minor troubles",
        "grandmother", "blindfolded",
        "fails to teach",
        "not even locked",
        "more appropriate tool",
    })

    if result:find("not even locked") then return true end
    if result:find("fails to teach") then return pick_box(box) end
    if result:find("more appropriate tool") then
        DRC.bput("get my lockpick", {"You get", "referring to"})
        return pick_box(box)
    end

    local speed = "careful"
    if result:find("trivially") or result:find("simple matter") or result:find("should not take long")
        or result:find("precisely") or result:find("minor troubles") then
        speed = "quick"
    elseif result:find("grandmother") or result:find("blindfolded") then
        speed = "blind"
    end

    while true do
        waitrt()
        local pr = DRC.bput("pick my " .. box .. " " .. speed, {
            "another lock protecting",
            "unable to make any progress",
            "Roundtime",
            "more appropriate tool",
        })
        if pr:find("Roundtime") then return true end
        if pr:find("another lock") then return pick_box(box) end
        if pr:find("more appropriate tool") then
            DRC.bput("get my lockpick", {"You get", "referring to"})
        end
    end
end

local function loot_box(box)
    waitrt()
    DRC.bput("open my " .. box, {"you see", "already open"})
    -- Get all items
    fput("get coin from my " .. box)
    fput("stow my " .. box)
end

-- Main
if pick_buff == "hol" then
    fput("pre hol 20")
end

DRC.remove_armor(armor)
fput("sit")

if pick_buff == "hol" then
    pause(15)
    fput("cast")
end

while get_boxes() do
    if stop_picking() then break end

    local found = false
    for _, bn in ipairs(box_nouns) do
        local r = DRC.bput("get my " .. bn .. " from my " .. box_source,
            {"You get", "What were you"})
        if r:find("You get") then
            found = true
            if disarm_box(bn) then
                pick_box(bn)
                waitrt()
                if not use_ring then fput("stow left") end
                loot_box(bn)
                DRC.bput("dismantle my " .. bn, {"repeat this request", "Roundtime"})
                waitrt()
            else
                DRC.bput("put my " .. bn .. " in my " .. box_storage, {"You put"})
            end
            break
        end
    end
    if not found then break end
end

fput("stand")
DRC.wear_armor(armor)
echo("Done picking!")
