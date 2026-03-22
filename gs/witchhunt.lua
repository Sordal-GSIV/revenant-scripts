--- @revenant-script
--- name: witchhunt
--- version: 1.0
--- author: Alastir (original Lich5 script)
--- game: gs
--- description: Witch's Cottage (Bittermere Woods) mini-game automation — all 7 tasks
--- tags: event, bittermere, witch, cottage, seasonal
---
--- Syntax:
---   ;witchhunt pay        — Single run (pay and complete one task)
---   ;witchhunt run        — Nonstop runs (loop until out of cubes)
---   ;witchhunt gourd      — Decorating the Gourd task only
---   ;witchhunt guard      — Gourd Guard task only
---   ;witchhunt candles    — Tallows Tails (candle making) task only
---   ;witchhunt torches    — Wards of the Old Ones (torch lighting) task only
---   ;witchhunt mushrooms  — Mulching the Mushrooms task only
---   ;witchhunt wisps      — Eyes of the Unliving (will-o'-wisps) task only
---   ;witchhunt ferns      — Harvesting the Fiddleheads task only
---
--- Prerequisites:
---   1. Start in room #34818
---   2. Set variables:
---      ;vars set lootsack=container   (where treasure drops are stored)
---      ;vars set eventsack=container  (where enruned stone cubes are stored)
---
--- Changelog (from Lich5 witchhunt.lic):
---   v1.0 (2024-10-26) - Original release by Alastir
---   Revenant port: Ruby→Lua conversion, Regex patterns, respond_to_window for loot stream
---
--- @lic-certified: complete 2026-03-19

require("lib/vars")

-- ============================================================
-- State
-- ============================================================
local start_time = 0
local nonstop = false

-- Room location arrays for each task
local torch_locations = {}
local wisp_locations = {}
local mushroom_locations = {}
local gourd_locations = {}
local fern_locations = {}
local wisp_drop_spyglass = false

-- ============================================================
-- Helpers
-- ============================================================

local function format_elapsed(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-- ============================================================
-- Loot Processing
-- ============================================================

local function process_loot()
    fput("glance")
    pause(0.2)

    local lh = GameObj.left_hand()
    if lh and lh.id then
        fput("swap")
    end

    pause(0.2)

    local rh = GameObj.right_hand()
    if rh and rh.id then
        respond_to_window("loot", "Found: " .. rh.name)
        local name = rh.name
        if name:find("clump of dirt")
            or name:find("wilted flower")
            or name:find("gourd husk")
            or name:find("glass jar")
            or name:find("onyx%-flecked rock")
            or name:find("grey stone") then
            fput("drop right")
        elseif name:find("fusion token") then
            fput("put token in my " .. (Vars.lootsack or "backpack"))
        elseif name:find("green orb") then
            fput("put orb in my " .. (Vars.lootsack or "backpack"))
        else
            pause_script(Script.name)
        end
    end
end

local function finished()
    local elapsed = os.time() - start_time
    respond_to_window("loot", "Finished in: " .. format_elapsed(elapsed))
    process_loot()
end

-- ============================================================
-- Entry cube management
-- ============================================================

local function get_entry()
    if GameState.room_id == 34818 then
        dothistimeout("get my cube from my " .. (Vars.eventsack or "backpack"), 3,
            "You get ", "You grab ", "You reach ", "You remove ", "You retrieve ")
    else
        pause_script(Script.name)
        respond("You are not in the starting room #34818!")
    end
end

local function stow_entry()
    dothistimeout("put my cube in my " .. (Vars.eventsack or "backpack"), 2,
        "You place ", "You put ", "You toss ")
end

-- ============================================================
-- Ferns — Harvesting the Fiddleheads
-- ============================================================

local FERN_DEFAULT = {
    "34932", "34930", "34928", "34926",  -- Hag's Hollow
    "34872",
    "34924", "34922", "34920", "34918",  -- Crimson Loop
    "34916", "34914", "34912", "34910",  -- Verdant Way
    "34882",
    "34902", "34904", "34906", "34908",  -- Shadowfern Way
}

local function turn_in_fern()  -- forward declaration filled below
end

local function sense_fern()  -- forward declaration
end

local function find_ferns()  -- forward declaration
end

turn_in_fern = function()
    Script.run("go2", "34890")
    local result = dothistimeout("give nymph", 5,
        "You must bring me %d+ more, hear?",
        "You must bring me 1 more, hear?",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    else
        find_ferns()
    end
end

local function climb_fern()
    multifput("climb fern", "get fern", "climb fern")
    pause(0.3)
end

sense_fern = function()
    local result = dothistimeout("sense", 5,
        "Aha!  You sense the existence of a mature frond on the fiddlehead fern.",
        "While you are able to sense the existence of a frond on the fiddlehead fern, you don't sense that it's ready for harvesting.")
    if result and result:find("mature frond") then
        pause(0.3)
        waitrt()
        climb_fern()
        turn_in_fern()
    else
        find_ferns()
    end
end

find_ferns = function()
    local next_room = fern_locations[1]
    echo("Heading to " .. tostring(next_room))
    Script.run("go2", next_room)

    table.remove(fern_locations, 1)
    echo("Rooms left: " .. #fern_locations)
    if #fern_locations == 0 then
        for i, v in ipairs(FERN_DEFAULT) do
            fern_locations[i] = v
        end
    end
    echo("The next room will be " .. tostring(fern_locations[1]))
    sense_fern()
end

-- ============================================================
-- Gourd Guard
-- ============================================================

local GOURD_GUARD_DEFAULT = {
    "34871", "34929", "34927", "34926",
    "34891", "34921", "34919", "34918",
    "34887", "34913", "34911", "34910",
    "34883", "34905", "34907", "34908",
}

local function get_room_gourd()  -- forward declaration
end

local function gourd_guard()  -- forward declaration
end

local function get_box_gourd()
    dothistimeout("get gourd in box", 5,
        "You remove .* from in an ornately decorated gourd collection box")
end

gourd_guard = function()
    local rh = GameObj.right_hand()
    if not rh or rh.noun ~= "gourd" then
        Script.run("go2", "34875")
        get_box_gourd()
    end

    local next_room = gourd_locations[1]
    echo("Heading to " .. tostring(next_room))
    Script.run("go2", next_room)

    table.remove(gourd_locations, 1)
    echo("Rooms left: " .. #gourd_locations)
    if #gourd_locations == 0 then
        for i, v in ipairs(GOURD_GUARD_DEFAULT) do
            gourd_locations[i] = v
        end
    end
    echo("The next room will be " .. tostring(gourd_locations[1]))
    get_room_gourd()
end

get_room_gourd = function()
    local result = dothistimeout("get gourd", 5,
        "You recall that you need to replace %d+ more rotten gourd",
        "You recall that you need to replace 1 more rotten gourd",
        "There's no need to replace it.",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    else
        gourd_guard()
    end
end

-- ============================================================
-- Mushrooms — Mulching the Mushrooms
-- ============================================================

local MUSHROOM_DEFAULT = {
    "34933", "34930", "34928", "34873", "34890",
    "34925", "34922", "34920", "34889",
    "34917", "34914", "34912", "34885", "34884",
    "34901", "34904", "34906", "34909", "34876",
}

local function sprinkle_bag()  -- forward declaration
end

local function find_mushrooms()  -- forward declaration
end

local function observe_mushroom()  -- forward declaration
end

local function get_mulch_bag()
    dothistimeout("get bag", 5, "You pick up a large bag of mulch.")
end

sprinkle_bag = function()
    local result = dothistimeout("sprinkle my bag", 5,
        "You recall that you need to mulch %d+ more mushroom",
        "You recall that you need to mulch 1 more mushroom",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    else
        find_mushrooms()
    end
end

observe_mushroom = function()
    local result = dothistimeout("observe mushroom", 5,
        "It appears the area beneath the mushroom could use some gardening assistance!",
        "The mushroom doesn't seem to need any gardening assistance.")
    if result and result:find("could use some gardening assistance") then
        pause(0.3)
        waitrt()
        sprinkle_bag()
    else
        find_mushrooms()
    end
end

find_mushrooms = function()
    local next_room = mushroom_locations[1]
    echo("Heading to " .. tostring(next_room))
    Script.run("go2", next_room)

    table.remove(mushroom_locations, 1)
    echo("Rooms left: " .. #mushroom_locations)
    if #mushroom_locations == 0 then
        for i, v in ipairs(MUSHROOM_DEFAULT) do
            mushroom_locations[i] = v
        end
    end
    echo("The next room will be " .. tostring(mushroom_locations[1]))
    observe_mushroom()
end

local function mushrooms()
    Script.run("go2", "34877")
    local rh = GameObj.right_hand()
    if not rh or rh.noun ~= "bag" then
        get_mulch_bag()
    end
    find_mushrooms()
end

-- ============================================================
-- Will-o'-Wisps — Eyes of the Unliving
-- ============================================================

local WISP_DEFAULT = { "34869", "34818" }

local function give_lantern()  -- forward declaration
end

local function find_wisps()  -- forward declaration
end

local function wave_lantern()
    local result = dothistimeout("wave my lantern", 5,
        "Opening a small door on the front of a glass-paned lantern, you swing it back and forth near the will-o'-wisp.")
    if result then
        Script.run("go2", "34818")
        give_lantern()
    end
end

local function peer_spyglass()
    local result = dothistimeout("peer my spyglass", 5,
        "Unfortunately, you didn't locate any will-o'-wisps.",
        "You recently checked here for a will-o'-wisp.",
        "Out of the corner of your eye, you spot a glowing light that appears to be a will-o'-wisp!")
    if result and result:find("spot a glowing light") then
        pause(0.3)
        waitrt()
        wave_lantern()
    else
        find_wisps()
    end
end

give_lantern = function()
    if wisp_drop_spyglass then
        fput("drop my spyglass")
    end
    local result = dothistimeout("give lantern to witch", 5,
        "You recall that you need to capture %d+ more will%-o'%-wisps to complete your task.",
        "You recall that you need to capture 1 more will%-o'%-wisp to complete your task.",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        wisp_drop_spyglass = false
        finished()
    elseif result and result:find("1 more will") then
        wisp_drop_spyglass = true
        find_wisps()
    elseif result then
        wisp_drop_spyglass = false
        find_wisps()
    else
        pause_script(Script.name)
    end
end

find_wisps = function()
    local next_room = wisp_locations[1]
    echo("Heading to " .. tostring(next_room))
    Script.run("go2", next_room)

    table.remove(wisp_locations, 1)
    echo("Rooms left: " .. #wisp_locations)
    if #wisp_locations == 0 then
        for i, v in ipairs(WISP_DEFAULT) do
            wisp_locations[i] = v
        end
    end
    echo("The next room will be " .. tostring(wisp_locations[1]))
    peer_spyglass()
end

local function get_spyglass()
    Script.run("go2", "34869")
    local lh = GameObj.left_hand()
    if not lh or lh.noun ~= "spyglass" then
        dothistimeout("get spyglass", 5,
            "You take a wooden spyglass from a fern-lined woven reed basket.")
    end
end

local function wisps()
    local rh = GameObj.right_hand()
    if not rh or rh.noun ~= "lantern" then
        fput("get lantern")
    end
    get_spyglass()
    find_wisps()
end

-- ============================================================
-- Torches — Wards of the Old Ones
-- ============================================================

local TORCH_DEFAULT = {
    "34870", "34871", "34932", "34930", "34928", "34926",
    "34890", "34891", "34924", "34922", "34920", "34918",
    "34886", "34887", "34916", "34914", "34912", "34910",
    "34882", "34883", "34881", "34876",
}

local function get_candle()
    Script.run("go2", "34870")
    dothistimeout("get candle in crate", 5,
        "You remove .* candle from in a wax%-dotted white birch crate")
end

local function torches()  -- forward declaration
end

local function light_torch()
    local result = dothistimeout("light torch", 5,
        "You recall that you need to light %d+ more torches to complete your task.",
        "You recall that you need to light 1 more torch to complete your task.",
        "A brightly glowing torch is already burning.",
        "An extinguished torch is already burning.",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    elseif result and (result:find("already burning")) then
        torches()
    elseif result then
        pause(0.3)
        waitrt()
        torches()
    end
end

torches = function()
    local rh = GameObj.right_hand()
    if not rh or rh.noun ~= "candle" then
        get_candle()
    end

    local next_room = torch_locations[1]
    echo("Heading to " .. tostring(next_room))
    Script.run("go2", next_room)

    table.remove(torch_locations, 1)
    echo("Rooms left: " .. #torch_locations)
    if #torch_locations == 0 then
        for i, v in ipairs(TORCH_DEFAULT) do
            torch_locations[i] = v
        end
    end
    echo("The next room will be " .. tostring(torch_locations[1]))
    light_torch()
end

-- ============================================================
-- Decorating the Gourd
-- ============================================================

local function gourd()  -- forward declaration
end

local function get_brush()
    dothistimeout("get brush", 5, "You take a .* brush from a small basket")
end

local function dip_brush()
    dothistimeout("dip my brush in paint", 5, "Do you want to dip")
    local result = dothistimeout("dip my brush in paint", 5, "You dip your")
    if result then
        pause(0.3)
        waitrt()
    end
end

local function get_gourd()
    pause(0.3)
    waitrt()
    dothistimeout("get gourd", 5, "You take .* gourd")
end

local function paint_gourd()
    local result = dothistimeout("paint my gourd", 5, "With a steady hand, you set out to decorate your")
    if result then
        pause(0.3)
        waitrt()
    end
end

local function box_gourd()
    pause(0.1)
    waitrt()
    local result = dothistimeout("put my gourd in box", 5,
        "You recall that you need to decorate and deposit %d+ more gourds to complete your task.",
        "You recall that you need to decorate and deposit 1 more gourd to complete your task.",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    else
        gourd()
    end
end

gourd = function()
    Script.run("go2", "34878")
    get_brush()
    dip_brush()
    get_gourd()
    paint_gourd()
    pause(0.3)
    waitrt()
    Script.run("go2", "34875")
    box_gourd()
end

-- ============================================================
-- Tallows Tails — Candle Making
-- ============================================================

local function candles()  -- forward declaration
end

local function get_cube_wax()
    dothistimeout("get cube in bucket", 5, "You take a wax cube from a metal bucket.")
end

local function pot_cube()
    dothistimeout("put my cube in pot", 5,
        "You plop your wax cube into the pot")
end

local function get_vial()
    dothistimeout("get vial on rack", 5, "You take .* vial from a display rack")
end

local function pour_vial()
    dothistimeout("pour my vial in pot", 5, "Do you want to pour")
    local result = dothistimeout("pour my vial in pot", 5, "You pour your")
    if result then
        pause(0.3)
        waitrt()
    end
end

local function push_pot()
    dothistimeout("push pot", 5, "Carefully grabbing the pot's side handles")
    pause(0.3)
    waitrt()
end

local function crate_candle()
    local result = dothistimeout("put my candle in crate", 5,
        "You recall that you need to create and donate %d+ more candles to complete your task.",
        "You recall that you need to create and donate 1 more candle to complete your task.",
        "She also stuffs 30 soul shards in your pocket.")
    if result and result:find("soul shards") then
        finished()
    else
        candles()
    end
end

candles = function()
    Script.run("go2", "34879")
    get_cube_wax()
    pot_cube()
    get_vial()
    pour_vial()
    push_pot()
    Script.run("go2", "34870")
    crate_candle()
end

-- ============================================================
-- Pay / Task Assignment
-- ============================================================

local function pay()
    start_time = os.time()
    get_entry()
    dothistimeout("pay", 5, "Slowly reaching beneath the table as she speaks")
    local result = dothistimeout("pay", 5,
        'You have been assigned the task: "Decorating the Gourd".',
        'You have been assigned the task: "Tallows Tails".',
        'You have been assigned the task: "Wards of the Old Ones".',
        'You have been assigned the task: "Mulching the Mushrooms".',
        'You have been assigned the task: "Gourd Guard".',
        'You have been assigned the task: "Harvesting the Fiddleheads".',
        'You have been assigned the task: "Eyes of the Unliving".',
        "You need an enruned stone cube to participate in the Undergrowth of Bittermere Woods.")

    if not result then
        respond("No task assignment received!")
        return
    end

    waitrt()
    stow_entry()

    if result:find("Decorating the Gourd") then
        gourd()
    elseif result:find("Tallows Tails") then
        candles()
    elseif result:find("Wards of the Old Ones") then
        for i, v in ipairs(TORCH_DEFAULT) do torch_locations[i] = v end
        torches()
    elseif result:find("Eyes of the Unliving") then
        for i, v in ipairs(WISP_DEFAULT) do wisp_locations[i] = v end
        wisps()
    elseif result:find("Mulching the Mushrooms") then
        for i, v in ipairs(MUSHROOM_DEFAULT) do mushroom_locations[i] = v end
        mushrooms()
    elseif result:find("Gourd Guard") then
        for i, v in ipairs(GOURD_GUARD_DEFAULT) do gourd_locations[i] = v end
        gourd_guard()
    elseif result:find("Harvesting the Fiddleheads") then
        for i, v in ipairs(FERN_DEFAULT) do fern_locations[i] = v end
        find_ferns()
    elseif result:find("enruned stone cube") then
        respond("Out of enruned stone cubes!")
        return
    end
end

local function run()
    if nonstop then
        while true do
            if nonstop then
                pay()
            else
                break
            end
        end
    else
        if GameState.room_id == 34818 then
            pay()
        else
            respond("Something bad happened!")
        end
    end
end

-- ============================================================
-- Startup banner
-- ============================================================

respond("This script provided by Alastir")
respond("")
respond("Variables used:")
respond("Vars.eventsack = Where entries are stored (Best to use a non-scripted container)")
respond("Vars.eventsack is set to " .. tostring(Vars.eventsack))
respond("You can change this by typing -- ;vars set eventsack=container")
respond("")
respond("Vars.lootsack = Where treasure drops are stored")
respond("Vars.lootsack is set to " .. tostring(Vars.lootsack))
respond("You can change this by typing -- ;vars set lootsack=container")
respond("")
respond("")
respond("This is a smart script, and will give you data in the Stormfront Loot window if opened")
respond("The script should be started in room #34818")
respond("")
respond(";unpause witchhunt if you are satisfied with this setup.")
pause_script(Script.name)

-- ============================================================
-- Command dispatch
-- ============================================================

local arg = Script.vars[1]

if arg and arg:lower():find("gourd") and not arg:lower():find("guard") then
    gourd()
elseif arg and arg:lower():find("guard") then
    for i, v in ipairs(GOURD_GUARD_DEFAULT) do gourd_locations[i] = v end
    gourd_guard()
elseif arg and arg:lower():find("candles") then
    candles()
elseif arg and arg:lower():find("torches") then
    for i, v in ipairs(TORCH_DEFAULT) do torch_locations[i] = v end
    torches()
elseif arg and arg:lower():find("mushrooms") then
    for i, v in ipairs(MUSHROOM_DEFAULT) do mushroom_locations[i] = v end
    mushrooms()
elseif arg and arg:lower():find("wisps") then
    for i, v in ipairs(WISP_DEFAULT) do wisp_locations[i] = v end
    wisps()
elseif arg and arg:lower():find("ferns") then
    for i, v in ipairs(FERN_DEFAULT) do fern_locations[i] = v end
    find_ferns()
elseif arg and arg:lower():find("pay") then
    nonstop = false
    pay()
elseif arg and arg:lower():find("run") then
    nonstop = true
    run()
elseif not arg then
    nonstop = true
    run()
end
