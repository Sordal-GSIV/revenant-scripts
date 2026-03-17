--- @revenant-script
--- name: uberfletch
--- version: 1.1.0
--- author: unknown
--- contributors: unknown
--- game: gs
--- description: Advanced fletching automation — arrows, bolts, darts with painting and drilling
--- tags: fletching,crafting,arrows,bolts
---
--- Ported from Lich5 Ruby uberfletch.lic
---
--- Usage:
---   ;uberfletch               - Start making arrows/bolts/darts
---   ;uberfletch setup         - Configure settings
---   ;uberfletch bundle        - Bundle finished arrows
---   ;uberfletch stop          - Stop after current arrow (while running)
---   ;uberfletch help          - Show help

no_pause_all()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

local PAINTS = {
    [0] = "none",
    [1] = "black paint",
    [2] = "blue paint",
    [3] = "brown paint",
    [4] = "green paint",
    [5] = "grey paint",
    [6] = "orange paint",
    [7] = "pink paint",
    [8] = "red paint",
    [9] = "white paint",
    [10] = "yellow paint",
}

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    fletch_sack        = "",
    fletch_quiver      = "",
    fletch_knife       = "knife",
    fletch_bow         = "bow",
    fletch_axe         = "hatchet",
    fletch_wood        = "limb of wood",
    fletch_fletchings  = "bundle of fletchings",
    fletch_paint       = 0,
    fletch_paintstick1 = "",
    fletch_paintstick2 = "",
    fletch_flip        = false,
    fletch_drilling    = false,
    fletch_drill       = "drill",
    fletch_arrowhead   = "barbed arrowhead",
    fletch_limit       = 0,
    fletch_light       = false,
    fletch_enable_buying = false,
    waggle             = false,
    XP_TO_STOP         = 80,
}

local settings = load_json("uberfletch_settings", DEFAULT_SETTINGS)
for k, v in pairs(DEFAULT_SETTINGS) do
    if settings[k] == nil then settings[k] = v end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local start_time = os.time()
local arrows_made = 0
local arrows_failed = 0
local spent_silver = 0
local finished = false

--------------------------------------------------------------------------------
-- Container helpers
--------------------------------------------------------------------------------

local function stow(hand, container)
    if hand == "left" then
        fput("put left in my " .. container)
    elseif hand == "right" then
        fput("put right in my " .. container)
    end
end

local function get_knife()
    if not checkleft() or not Regex.test(checkleft(), settings.fletch_knife) then
        fput("get my " .. settings.fletch_knife)
        sleep(0.5)
    end
end

local function get_container_contents(sack)
    if not sack or sack == "" then return {} end
    local container = GameObj.find_inv(sack)
    if not container then return {} end

    -- Force look to populate contents
    if not container.contents or #container.contents == 0 then
        dothistimeout("look in my " .. sack, 5, Regex.new("^In the|^There is nothing"))
        sleep(0.5)
    end

    return container.contents or {}
end

local function haste()
    -- Attempt to use haste if available (e.g., from a spell or item)
    -- In Revenant, this is a no-op if not available
end

--------------------------------------------------------------------------------
-- Shaft making
--------------------------------------------------------------------------------

local function make_shafts()
    local contents = get_container_contents(settings.fletch_sack)
    local wood = nil
    for _, obj in ipairs(contents) do
        if obj.noun == "wood" then
            wood = obj
            break
        end
    end

    if not wood then return end

    dothistimeout(string.format("get 1 #%s", wood.id), 3, Regex.new("You remove"))
    get_knife()
    haste()
    fput("cut my wood with my " .. settings.fletch_knife)
    sleep(1)
    waitrt()

    if not Regex.test(checkright() or "", "shaft") then
        stow("left", settings.fletch_sack)
        return
    end

    fput("cut my wood with my " .. settings.fletch_knife)
    sleep(1)
    waitrt()

    stow("left", settings.fletch_sack)
    stow("right", settings.fletch_sack)
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function paint_shaft(shaft_type)
    if settings.fletch_paint == 0 then return end

    stow("left", settings.fletch_sack)
    local paint_parts = {}
    local paint_str = PAINTS[settings.fletch_paint] or ""
    for word in string.gmatch(paint_str, "%S+") do
        paint_parts[#paint_parts + 1] = word
    end

    if #paint_parts == 0 then return end

    fput("get my " .. paint_parts[1] .. " paint")
    local deadline = os.time() + 6
    while true do
        if Regex.test(checkleft() or "", "paint") then break end
        if os.time() > deadline then
            echo("Run out of paint")
            return
        end
        sleep(0.5)
    end

    haste()
    local check = dothistimeout("paint my shaft", 3, Regex.new("You carefully smear a bit of paint"))
    if not check then
        echo("Could not determine if painting was successful")
        return
    end

    matchtimeout(40, "The paint on your " .. shaft_type .. " shaft has dried.")
    stow("left", settings.fletch_sack)
end

local function apply_paintstick(stick_setting, shaft_type)
    if not stick_setting or stick_setting == "" then return end

    stow("left", settings.fletch_sack)
    fput("get my " .. stick_setting)
    local deadline = os.time() + 6
    while true do
        if Regex.test(checkleft() or "", "paintstick") then break end
        if os.time() > deadline - 3 then
            fput("get my " .. stick_setting)
        end
        if os.time() > deadline then
            echo("Could not get paintstick")
            return
        end
        sleep(0.5)
    end

    haste()
    dothistimeout("paint my shaft", 3, Regex.new("You carefully apply a band of"))
    matchtimeout(40, "The paint on your " .. shaft_type .. " shaft has dried.")
    waitrt()
    stow("left", settings.fletch_sack)
end

--------------------------------------------------------------------------------
-- Arrow making
--------------------------------------------------------------------------------

local function make_arrow()
    local contents = get_container_contents(settings.fletch_sack)
    local shaft = nil
    for _, obj in ipairs(contents) do
        if Regex.test(obj.name or "", "arrow.*shaft") then
            shaft = obj
            break
        end
    end

    if not shaft then
        echo("Can't find an arrow shaft")
        return
    end

    dothistimeout(string.format("get 1 #%s", shaft.id), 3, Regex.new("You remove"))
    get_knife()

    -- Cut shaft
    haste()
    fput("cut my shaft with my " .. settings.fletch_knife)
    sleep(1)
    waitrt()

    if not Regex.test(checkright() or "", "shaft") then
        stow("left", settings.fletch_sack)
        return
    end

    -- Painting
    paint_shaft("arrow")
    apply_paintstick(settings.fletch_paintstick1, "arrow")
    apply_paintstick(settings.fletch_paintstick2, "arrow")

    -- Cut nocks
    if settings.fletch_paint ~= 0 or (settings.fletch_paintstick1 and settings.fletch_paintstick1 ~= "") then
        get_knife()
    end
    haste()
    fput("cut nock in my shaft with my " .. settings.fletch_knife)
    sleep(2)
    waitrt()

    if not Regex.test(checkright() or "", "shaft") then
        stow("left", settings.fletch_sack)
        return
    end
    stow("left", settings.fletch_sack)

    -- Measure with bow
    waitrt()
    local check = dothistimeout("remove my " .. settings.fletch_bow, 1, Regex.new("You sling|remove what"))
    if not check or Regex.test(check, "remove what") then
        echo("Failed to get bow")
        return
    end

    haste()
    dothistimeout("measure my shaft with my " .. settings.fletch_bow, 3,
        Regex.new("you carefully un-nock the shaft"))
    sleep(1)
    waitrt()
    dothistimeout("wear my " .. settings.fletch_bow, 3, Regex.new("You sling"))

    -- Final cut
    get_knife()
    haste()
    dothistimeout("cut my shaft with my " .. settings.fletch_knife, 3,
        Regex.new("Using your previous mark"))
    sleep(1)
    waitrt()

    if not Regex.test(checkright() or "", "shaft") then
        stow("left", settings.fletch_sack)
        return
    end
    stow("left", settings.fletch_sack)

    -- Glue
    fput("get my glue")
    local deadline = os.time() + 6
    while true do
        if Regex.test(checkleft() or "", "glue") then break end
        if os.time() > deadline then
            echo("Failed to get glue")
            return
        end
        sleep(0.1)
    end

    haste()
    dothistimeout("put my glue on my shaft", 3, Regex.new("You carefully smear a bit of glue"))
    sleep(1)
    waitrt()
    stow("left", settings.fletch_sack)

    -- Fletchings
    fput("get 3 my fletching in my " .. settings.fletch_sack)
    deadline = os.time() + 6
    while true do
        if Regex.test(checkleft() or "", "fletching") then break end
        if os.time() > deadline then
            echo("Failed to get fletchings")
            return
        end
        sleep(0.1)
    end

    haste()
    check = dothistimeout("put my fletching on my shaft", 3,
        Regex.new("You attach your|so you discard|Luckily, you are able to salvage"))
    if check and Regex.test(check, "so you discard") then
        waitrt()
        return
    end

    matchtimeout(60, "The glue on your arrow shaft has dried.")
    waitrt()

    if not Regex.test(checkright() or "", "shaft") then
        stow("left", settings.fletch_sack)
        return
    end

    -- Flip
    haste()
    if settings.fletch_flip then
        fput("flip my shaft")
    end

    -- Drilling/arrowhead or final cuts
    if settings.fletch_drilling then
        dothistimeout("get my " .. settings.fletch_drill .. " from my " .. settings.fletch_sack, 2,
            Regex.new("You remove"))
        dothistimeout("turn my " .. settings.fletch_drill, 6,
            Regex.new("and look at your now drilled shaft"))
        waitrt()
        fput("put my " .. settings.fletch_drill .. " in my " .. settings.fletch_sack)

        dothistimeout("get my " .. settings.fletch_arrowhead .. " from my " .. settings.fletch_sack, 3,
            Regex.new("You remove"))
        dothistimeout("turn my " .. settings.fletch_arrowhead, 3,
            Regex.new("As you turn the arrowhead into the shaft"))
        waitrt()
    else
        get_knife()
        fput("cut my shaft with my " .. settings.fletch_knife)
        fput("cut my shaft with my " .. settings.fletch_knife)
        matchtimeout(6, "With a few quick cuts,")
        waitrt()
        stow("left", settings.fletch_sack)
    end
end

--------------------------------------------------------------------------------
-- Bundling
--------------------------------------------------------------------------------

local function bundle_arrows()
    local contents = get_container_contents(settings.fletch_quiver)
    local arrows = {}
    for _, obj in ipairs(contents) do
        if Regex.test(obj.name or "", "arrow|bolt|dart") and not Regex.test(obj.name or "", "bundle") then
            arrows[#arrows + 1] = obj
        end
    end

    if #arrows == 0 then
        echo("No arrows found to bundle")
        return
    end

    fput("get 1 #" .. arrows[1].id)
    for i = 2, #arrows do
        fput("get 1 #" .. arrows[i].id)
        fput("bundle")
        if checkleft() then
            stow("left", settings.fletch_quiver)
        end
    end
    stow("right", settings.fletch_quiver)
    echo("Bundling complete")
end

--------------------------------------------------------------------------------
-- Check needed items
--------------------------------------------------------------------------------

local function check_needed_items(contents)
    local needed = {}

    -- Check for wood
    local has_wood = false
    local has_shaft = false
    for _, obj in ipairs(contents) do
        if obj.noun == "wood" then has_wood = true end
        if Regex.test(obj.name or "", "shaft") then has_shaft = true end
    end

    if not has_wood and not has_shaft then
        needed[#needed + 1] = settings.fletch_wood
    end

    -- Check fletchings
    local has_fletchings = false
    for _, obj in ipairs(contents) do
        if Regex.test(obj.name or "", "fletching") then
            has_fletchings = true
            break
        end
    end
    if not has_fletchings then
        needed[#needed + 1] = settings.fletch_fletchings or "bundle of fletchings"
    end

    return needed
end

--------------------------------------------------------------------------------
-- Rest check
--------------------------------------------------------------------------------

local function checkrest()
    while percentmind() >= settings.XP_TO_STOP do
        sleep(30)
        fput("exp")
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function setup()
    local win = Gui.window("UberFletch Setup", 400, 550)
    local box = Gui.vbox(win)

    Gui.label(box, "=== UberFletch Configuration ===")
    Gui.label(box, "")

    Gui.label(box, "Containers:")
    Gui.entry(box, "Supply sack:", settings.fletch_sack, function(val)
        settings.fletch_sack = val; save_json("uberfletch_settings", settings)
    end)
    Gui.entry(box, "Quiver:", settings.fletch_quiver, function(val)
        settings.fletch_quiver = val; save_json("uberfletch_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Tools:")
    Gui.entry(box, "Knife:", settings.fletch_knife, function(val)
        settings.fletch_knife = val; save_json("uberfletch_settings", settings)
    end)
    Gui.entry(box, "Bow:", settings.fletch_bow, function(val)
        settings.fletch_bow = val; save_json("uberfletch_settings", settings)
    end)
    Gui.entry(box, "Axe:", settings.fletch_axe, function(val)
        settings.fletch_axe = val; save_json("uberfletch_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Materials:")
    Gui.entry(box, "Wood type:", settings.fletch_wood, function(val)
        settings.fletch_wood = val; save_json("uberfletch_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Options:")
    Gui.checkbox(box, "Flip shaft", settings.fletch_flip, function(val)
        settings.fletch_flip = val; save_json("uberfletch_settings", settings)
    end)
    Gui.checkbox(box, "Use drilling", settings.fletch_drilling, function(val)
        settings.fletch_drilling = val; save_json("uberfletch_settings", settings)
    end)
    Gui.checkbox(box, "Auto-buy supplies", settings.fletch_enable_buying, function(val)
        settings.fletch_enable_buying = val; save_json("uberfletch_settings", settings)
    end)

    Gui.show(win)
end

--------------------------------------------------------------------------------
-- Upstream hook for in-script commands
--------------------------------------------------------------------------------

local HOOK_ID = "uberfletch_hook"

Hook.add(HOOK_ID, "upstream", function(line)
    if Regex.test(line, "^(?:<c>)?" .. Script.char .. "(?:uberfletch|fletching)$") then
        local elapsed = os.time() - start_time
        local hrs = math.floor(elapsed / 3600)
        local mins = math.floor((elapsed % 3600) / 60)
        local secs = elapsed % 60
        respond(string.format("\nRunning for %02d:%02d:%02d, made %d, ruined %d, spent %d silver\n",
            hrs, mins, secs, arrows_made, arrows_failed, spent_silver))
        return nil  -- consume
    elseif Regex.test(line, "^(?:<c>)?" .. Script.char .. "(?:uberfletch|fletching) (?:stop|done|end|finish)$") then
        finished = true
        respond("\nOnce current arrow is complete script will end\n")
        return nil  -- consume
    end
    return line
end)

before_dying(function()
    Hook.remove(HOOK_ID)
end)

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cmd = (Script.vars[1] or ""):lower()

if Regex.test(cmd, "setup|config|configure") then
    setup()
    return
elseif cmd == "bundle" then
    bundle_arrows()
    return
elseif cmd == "help" or cmd ~= "" then
    respond("")
    respond("UberFletch - Advanced fletching automation")
    respond("  ;uberfletch          - Start making arrows")
    respond("  ;uberfletch setup    - Configure settings")
    respond("  ;uberfletch bundle   - Bundle finished arrows")
    respond("  ;uberfletch stop     - Stop after current arrow")
    respond("  ;uberfletch help     - This help message")
    respond("")
    return
end

-- Validate settings
local warnings = {}
if settings.fletch_sack == "" then
    warnings[#warnings + 1] = "Supply container not set"
end
if settings.fletch_quiver == "" then
    warnings[#warnings + 1] = "Quiver not set"
end
if settings.fletch_knife == "" then
    warnings[#warnings + 1] = "Knife not set"
end
if settings.fletch_bow == "" then
    warnings[#warnings + 1] = "Bow not set"
end

if #warnings > 0 then
    for _, w in ipairs(warnings) do
        echo("WARNING: " .. w)
    end
    echo("Run ;uberfletch setup to configure")
    setup()
    return
end

-- Main loop
silence_me()
empty_left_hand()
empty_right_hand()

while true do
    if settings.waggle then
        start_script("waggle")
        wait_while(function() return running("waggle") end)
    end

    -- Check for supplies
    local contents = get_container_contents(settings.fletch_sack)
    local needed = check_needed_items(contents)

    if #needed > 0 then
        if not settings.fletch_enable_buying then
            echo("Run out of " .. needed[1] .. " and buying is disabled")
            break
        end
        for _, item in ipairs(needed) do
            respond("Out of " .. item)
        end
        respond("Buying not yet implemented in Lua port — please restock manually")
        break
    end

    -- Make shafts if we have wood
    contents = get_container_contents(settings.fletch_sack)
    local has_wood = false
    for _, obj in ipairs(contents) do
        if obj.noun == "wood" then has_wood = true; break end
    end
    if has_wood then
        make_shafts()
    end

    -- Rest check
    checkrest()

    -- Make arrow/bolt/dart
    contents = get_container_contents(settings.fletch_sack)
    if Regex.test(settings.fletch_bow, "^crossbow") then
        -- Bolt making (simplified — same core steps)
        make_arrow()
    elseif Regex.test(settings.fletch_bow, "^dart") then
        make_arrow()
    else
        make_arrow()
    end

    -- Stow result
    if Regex.test(checkright() or "", "^bolt|^dart|^arrow") then
        stow("right", settings.fletch_quiver)
        arrows_made = arrows_made + 1
    else
        arrows_failed = arrows_failed + 1
    end

    -- Report
    local elapsed = os.time() - start_time
    local hrs = math.floor(elapsed / 3600)
    local mins = math.floor((elapsed % 3600) / 60)
    local secs = elapsed % 60
    respond(string.format("\nRunning for %02d:%02d:%02d, made %d arrows, ruined %d, spent %d silver\n",
        hrs, mins, secs, arrows_made, arrows_failed, spent_silver))

    if finished then break end
    if settings.fletch_limit > 0 and arrows_made >= settings.fletch_limit then break end
end
