--- @revenant-script
--- name: crush
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Alchemy crush training with mortar and pestle.
--- tags: alchemy, crafting, training
---
--- Converted from crush.lic

local settings = get_settings()
local bag = settings.crafting_container or "backpack"

DREMgr.empty_hands()
DRC.bput("get my mortar", "You get")

local function empty_mortar()
    DRC.bput("tilt my mortar", "You grab", "The mortar is empty")
    DRC.bput("tilt my mortar", "You grab", "The mortar is empty")
end

local function forage_flower()
    DRC.bput("kick pile", "e")
    DRC.bput("collect blue flower", "You manage to collect")
    waitrt()
    DRC.bput("get blue flower", "You get")
    DRC.bput("put my flow in my mort", "You put")
end

local function crush_flower()
    local result = DRC.bput("crush flower in my mortar with my pestle",
        "Roundtime", "You complete crushing the contents")
    if result == "Roundtime" then
        return crush_flower()
    else
        DRC.bput("put my pestle in my " .. bag, "You put")
    end
end

while DRSkill.getxp("Alchemy") <= 32 and DRSkill.getrank("Alchemy") <= 80 do
    if settings.crafting_training_spells then
        DRCA.crafting_magic_routine(settings)
    end
    empty_mortar()
    forage_flower()
    DRC.bput("get my pestle", "You get")
    crush_flower()
    empty_mortar()
end

DREMgr.empty_hands()
wait_for_script_to_complete("outdoorsmanship", {"34"})
