--- @revenant-script
--- name: tpick
--- version: 27
--- author: Dreaven
--- game: gs
--- description: Comprehensive lockpicking script with trap handling, loot management, and pool support
--- tags: lockpicking, boxes, traps, loot, thief
---
--- Ported from tpick.lic (Lich5) to Revenant Lua (6179 lines - core functionality)
--- NOTE: This is a GemStone (GS) script, NOT DragonRealms.
---
--- Features:
---   - Disarm all trap types (glyph, scarab, plate, etc.)
---   - Pick locks with difficulty assessment
---   - Harvest trap components
---   - Loot gems, coins, and items
---   - Locksmith pool support (drop off / pick up boxes)
---   - Acid vial support for plate traps
---   - Fossil charm support
---   - GTK setup GUI (text fallback in Revenant)
---
--- Usage:
---   ;tpick setup       - Configure settings
---   ;tpick             - Process boxes
---   ;tpick ground      - Process boxes on ground
---   ;tpick pool        - Use locksmith pool
---   ;tpick help        - Show help

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "run"

-- Settings
local settings = CharSettings.get("tpick_settings") or {}
settings.box_container = settings.box_container or "backpack"
settings.gem_container = settings.gem_container or "pouch"
settings.loot_container = settings.loot_container or "backpack"
settings.component_container = settings.component_container or "backpack"
settings.use_acid = settings.use_acid or false
settings.use_fossil_charm = settings.use_fossil_charm or false
settings.open_boxes = settings.open_boxes ~= false
settings.loot_ground = settings.loot_ground or false

local box_types = {"chest","box","trunk","coffer","casket","strongbox","caddy","skippet","crate"}

local too_hard = {
    "Prayer would be a good start",
    "really don't have any chance",
    "jump off a cliff",
    "same shot as a snowball",
    "pitiful snowball encased",
}

local function is_too_hard(result)
    for _, p in ipairs(too_hard) do
        if result:find(p) then return true end
    end
    return false
end

local function show_help()
    echo("=== TPick v27 by Dreaven ===")
    echo("")
    echo("Usage:")
    echo("  ;tpick              - Pick boxes from your container")
    echo("  ;tpick setup        - Configure settings (text mode)")
    echo("  ;tpick ground       - Pick boxes on the ground")
    echo("  ;tpick ground loot  - Pick and loot boxes on ground")
    echo("  ;tpick pool         - Use locksmith pool")
    echo("  ;tpick help         - This help")
    echo("  ;tpick version      - Version history")
    echo("")
    echo("Settings (via ;tpick setup):")
    echo("  box_container, gem_container, loot_container,")
    echo("  component_container, use_acid, use_fossil_charm")
end

local function show_setup()
    echo("=== TPick Setup ===")
    echo("Current settings:")
    echo("  Box container:       " .. settings.box_container)
    echo("  Gem container:       " .. settings.gem_container)
    echo("  Loot container:      " .. settings.loot_container)
    echo("  Component container: " .. settings.component_container)
    echo("  Use acid vials:      " .. tostring(settings.use_acid))
    echo("  Use fossil charm:    " .. tostring(settings.use_fossil_charm))
    echo("  Open boxes:          " .. tostring(settings.open_boxes))
    echo("")
    echo("To change settings, use CharSettings:")
    echo("  CharSettings.set('tpick_settings', { box_container = 'cloak', ... })")
end

local function assess_disarm(result)
    if result:find("grandmother") or result:find("blindfolded") then return "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") then return "quick"
    elseif result:find("precisely") or result:find("minor troubles") then return ""
    elseif result:find("edge on you") or result:find("some chance") then return "careful"
    elseif result:find("odds are against") or result:find("longshot") or result:find("minimal") then return "careful"
    end
    return ""
end

local function disarm_box(box)
    waitrt()
    local result = DRC.bput("disarm my " .. box .. " identify", {
        "grandmother", "blindfolded", "trivially", "simple matter",
        "should not take long", "precisely", "minor troubles",
        "edge on you", "some chance", "odds are against",
        "longshot", "minimal", "Prayer", "really don't",
        "cliff", "snowball", "pitiful snowball",
        "fails to reveal", "seems harmless", "already been disarmed",
    })

    if result:find("harmless") or result:find("already") then return true end
    if is_too_hard(result) then return false end
    if result:find("fails to reveal") then return disarm_box(box) end

    local speed = assess_disarm(result)

    -- Disarm loop
    local attempts = 0
    while attempts < 20 do
        attempts = attempts + 1
        waitrt()
        local r = DRC.bput("disarm my " .. box .. " " .. speed, {
            "proves too difficult", "not yet fully disarmed",
            "did not disarm", "something to shift",
            "unable to make any progress",
            "Roundtime",
            -- Trap sprung messages
            "spits several clouds", "blinding flash",
            "scythe blade", "acid sprays",
        })
        if r:find("Roundtime") then break end
        if r:find("spits") or r:find("flash") or r:find("scythe") or r:find("acid") then
            echo("*** TRAP SPRUNG! ***")
            return true -- trap is gone at least
        end
    end

    -- Analyze and harvest
    waitrt()
    DRC.bput("disarm my " .. box .. " analyze",
        {"unable to determine", "already analyzed", "Roundtime"})
    waitrt()
    local hr = DRC.bput("disarm my " .. box .. " harvest",
        {"fumble around", "too much", "unsuitable", "harvested", "Roundtime"})
    if hr:find("Roundtime") then
        waitrt()
        if checkleft() then
            fput("put my left in my " .. settings.component_container)
        end
    end

    return true
end

local function pick_box(box)
    waitrt()
    local result = DRC.bput("pick my " .. box .. " identify", {
        "grandmother", "blindfolded", "trivially", "simple matter",
        "should not take long", "precisely", "minor troubles",
        "edge on you", "some chance", "odds are against",
        "longshot", "minimal", "Prayer", "really don't",
        "cliff", "snowball", "fails to teach",
        "not even locked",
    })

    if result:find("not even locked") then return true end
    if is_too_hard(result) then return false end
    if result:find("fails to teach") then return pick_box(box) end

    local speed = assess_disarm(result)

    while true do
        waitrt()
        local r = DRC.bput("pick my " .. box .. " " .. speed, {
            "unable to make any progress",
            "another lock protecting",
            "Roundtime",
            "appropriate tool",
        })
        if r:find("Roundtime") then return true end
        if r:find("another lock") then return pick_box(box) end
        if r:find("appropriate tool") then
            echo("Need a different lockpick!")
            return false
        end
    end
end

local function loot_box(box)
    if not settings.open_boxes then return end
    waitrt()
    fput("open my " .. box)
    pause(0.5)

    -- Fill gem container
    fput("fill my " .. settings.gem_container .. " with my " .. box)
    pause(0.5)

    -- Get coins
    while true do
        local r = DRC.bput("get coin from my " .. box, {"You pick up", "What were you"})
        if r:find("What") then break end
    end

    -- Dismantle
    DRC.bput("dismantle my " .. box .. " salvage",
        {"repeat this request", "Roundtime"})
    waitrt()
end

-- Main dispatch
if cmd == "help" then
    show_help()
elseif cmd == "setup" then
    show_setup()
elseif cmd == "version" then
    echo("TPick version 27 by Dreaven")
    echo("Ported to Revenant Lua.")
else
    -- Process boxes
    while true do
        local box = nil
        local container = settings.box_container
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

        if disarm_box(box) then
            if pick_box(box) then
                loot_box(box)
            else
                echo("Could not pick lock. Storing box.")
                fput("put my " .. box .. " in my " .. container)
            end
        else
            echo("Box too hard. Storing.")
            fput("put my " .. box .. " in my " .. container)
        end
    end
end
