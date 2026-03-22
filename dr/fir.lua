--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: fir
--- version: 1.1.0
--- author: Ondreian Warpstone
--- game: dr
--- description: Create Fir Familiar talismans (Cleric quest). Handles navigation, holy water acquisition, bark collection, and carving.
--- tags: cleric, familiar, crafting
---
--- Converted from fir.lic (Lich5 dr-scripts) to Revenant Lua.
--- Original: https://elanthipedia.play.net/Lich_script_repository#fir
--- Original authors: Ondreian Warpstone
---
--- Usage:
---   ;fir [number]   -- Create 1-3 fir familiar talismans (default: 1)
---
--- Requires: common, common-crafting, common-items, common-money, common-travel, equip-manager
--- Settings used: crafting_container, crafting_items_in_container, engineering_belt

local settings  = get_settings()
local bag       = settings.crafting_container
local bag_items = settings.crafting_items_in_container or {}
local belt      = settings.engineering_belt

-------------------------------------------------------------------------------
-- Arg parsing
-------------------------------------------------------------------------------

local num = 1
if Script.vars[1] then
    local n = tonumber(Script.vars[1])
    if n then
        if n > 3 then
            echo("****Cannot get more than 3 at a time!****")
            return
        end
        num = n
    end
end

-- Empty hands before starting
local em = DREMgr.EquipmentManager(settings)
em:empty_hands()

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function check_carving_knife()
    if not DRCI.exists("carving knife") then
        echo("**** You need a carving knife! ****")
        DRC.beep()
        return false
    end
    return true
end

local function get_holy_water()
    if DRCI.exists("silver vial") then return end

    if DRSkill.getrank("Thievery") >= 231 then
        DRCT.walk_to(19073)
        DRC.bput("steal silver vial in catalog", "Roundtime")
    else
        if not DRCM.ensure_copper_on_hand(500, nil, "Crossing") then
            echo("***STATUS*** Insufficient funds to buy silver vial")
            DRC.beep()
            return
        end
        DRCT.buy_item(19073, "silver vial")
    end

    DRCT.walk_to(5779)
    DRC.bput("fill my vial with water from basin", "You fill your silver vial with some water.")
    DRC.bput("stow my silver vial", "You put")
end

local function get_fir_bark(number)
    if DRCI.exists("fir bark") then return end

    DRCT.walk_to(989)
    for _ = 1, number do
        DRC.bput("pull tree", "releasing a small precious piece", "You should try again later.")
        DRC.bput("stow fir bark", "You put")
    end
end

local function goto_shard_temple()
    DRCT.walk_to(2807)
    move("north")
    move("north")
    move("north")
    move("north")
    move("north")
    move("northeast")
    move("northwest")
    move("northwest")
    move("north")
    move("north")
    move("east")
    move("east")
    move("northeast")
    move("east")
    move("east")
    move("climb stile")
    move("east")
    move("south")
    move("south")
    move("west")
    move("west")
end

local function open_wall()
    DRC.bput("put right hand in first hole", "You have passed the test of lore")
    DRC.bput("get fir bark", "you get")
    DRC.bput("put left hand in second hole", "You have passed the test of the tree")
    DRC.bput("stow right", "You put")
    DRC.bput("get my silver vial", "You get")
    DRC.bput("get water from vial", "You get some holy water")
    DRC.bput("stow vial", "You put")
    DRC.bput("put right hand in third hole", "A foreboding wall moves out of your way to allow passage!")
    DRC.bput("get my silver vial", "You get")
    DRC.bput("put water in my vial", "You put")
    DRC.bput("stow vial", "You put")
end

local function goto_old_man()
    local result = DRC.bput("west", "A voice whispers in your head", "You can't", "Obvious exits")
    if result:find("A voice whispers") or result:find("You can't") then
        return false
    end
    move("go stairs")
    return true
end

local function get_talisman(number)
    for _ = 1, number do
        local result = DRC.bput("get fir bark", "You get", "I could not find")
        if result:find("I could not find") then return end
        DRC.bput("give man", "The old man takes your bark")
        DRC.bput("stow right", "You put")
    end
end

local function carve()
    local result = DRC.bput("carve my talisman", "fine details", "Roundtime", "Round time")
    if not result:find("fine details") then
        carve()
    end
end

local function carve_talisman(number)
    for _ = 1, number do
        local result = DRC.bput("get fir talisman", "You get", "What were you referring to")
        if result:find("What were you referring to") then
            echo("No more talismans!")
            return
        end
        DRC.bput("rub my fir talisman", "You rub")
        DRCC.get_crafting_item("carving knife", bag, bag_items, belt)
        DRC.bput("swap", "You move")
        carve()
        DRCC.stow_crafting_item("carving knife", bag, belt)
        DRC.bput("stow talisman", "You put")
    end
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

if not check_carving_knife() then return end

get_holy_water()
get_fir_bark(num)
goto_shard_temple()

if not goto_old_man() then
    open_wall()
    goto_old_man()
end

get_talisman(num)
move("out")
DRCT.walk_to(2807)
carve_talisman(num)
