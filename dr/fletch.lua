--- @revenant-script
--- name: fletch
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Fletching script - make arrow/bolt shafts, heads, and assemble arrows
--- tags: crafting, fletching, arrows, bolts, engineering
---
--- Ported from fletch.lic (Lich5) to Revenant Lua
---
--- Requires: common, common-crafting, common-items, common-money, common-travel
---
--- Usage:
---   ;fletch shaft arrow <num_bundles>   - Make arrow shafts
---   ;fletch shaft bolt <num_bundles>    - Make bolt shafts
---   ;fletch head arrow <material> <num> - Make arrowheads
---   ;fletch arrow <material> <qty>      - Make arrows (shafts + heads + assembly)
---   ;fletch unbundle                    - Unbundle materials

local settings = get_settings()
local hometown = settings.hometown or "Crossing"
local belt = settings.engineering_belt
local bag = settings.crafting_container
local bag_items = settings.crafting_items_in_container or {}
local fletching_bag = settings.fletching_bag or "backpack"
local shaft_material = "balsa"

local shopping_data = {
    ["arrow flights"] = { room = 8864, order_number = 12, cost = 62 },
    ["bolt flights"]  = { room = 8864, order_number = 13, cost = 62 },
    ["wood glue"]     = { room = 8865, order_number = 13, cost = 437 },
}

local raw_mat_map = {
    ["angiswaerd"]   = "",
    ["boar-tusk"]    = "",
    ["cougar-claw"]  = "curved claw",
    ["drake-fang"]   = "",
    ["sabretooth"]   = "sabre teeth",
    ["soot-stained"] = "soot-stained claw",
}

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "help"

local function show_help()
    echo("=== Fletch ===")
    echo("Usage:")
    echo("  ;fletch shaft arrow <bundles>      - Make arrow shafts")
    echo("  ;fletch shaft bolt <bundles>        - Make bolt shafts")
    echo("  ;fletch head arrow <material> <num> - Make arrowheads")
    echo("  ;fletch arrow <material> <qty>      - Make complete arrows")
    echo("  ;fletch unbundle                    - Unbundle materials")
    echo("")
    echo("Materials: angiswaerd, boar-tusk, cougar-claw, drake-fang, sabretooth, soot-stained")
end

local function make_shafts(shaft_type)
    DRCC.get_crafting_item("shaper", bag, bag_items, belt)
    DRC.bput("get my " .. shaft_material .. " lumber", {"You get"})
    DRC.bput("shape my lumber into " .. shaft_type .. " shaft",
        {"You break the lumber"})
    DRCC.stow_crafting_item("shaper", bag, belt)
    fput("stow shaft")
end

local function make_heads(material, head_type)
    local raw = raw_mat_map[material] or material
    DRCC.get_crafting_item("shaper", bag, bag_items, belt)
    local r = DRC.bput("get my " .. raw .. " from my " .. fletching_bag,
        {"You get", "What were you", "already"})
    if r:find("What were you") then
        DRCC.stow_crafting_item("shaper", bag, belt)
        echo("OUT OF ARROWHEAD MATERIAL")
        return
    end
    DRC.bput("shape " .. raw .. " into " .. head_type .. "head",
        {"You repeatedly impact"})
    DRCC.stow_crafting_item("shaper", bag, belt)
    fput("put my " .. material .. " " .. head_type .. "head in my " .. fletching_bag)
end

if cmd == "shaft" then
    local shaft_type = args[2] or "arrow"
    local num = tonumber(args[3]) or 1
    for i = 1, num do
        make_shafts(shaft_type)
    end
    echo("Made " .. num .. " bundle(s) of " .. shaft_type .. " shafts.")
elseif cmd == "head" then
    local head_type = args[2] or "arrow"
    local material = args[3] or "cougar-claw"
    local num = tonumber(args[4]) or 1
    for i = 1, num do
        make_heads(material, head_type)
    end
    echo("Made " .. num .. " " .. material .. " " .. head_type .. "heads.")
elseif cmd == "arrow" then
    local material = args[2] or "cougar-claw"
    local qty = tonumber(args[3]) or 1
    echo("Making " .. qty .. " arrow bundle(s) from " .. material)
    echo("Full arrow assembly requires the crafting book and shaping system.")
    echo("Use ;fletch shaft, ;fletch head separately for now.")
elseif cmd == "unbundle" then
    DRC.bput("remove my bundle", {"You remove", "You sling"})
    DRC.bput("unbundle", {"You untie"})
    DRC.bput("stow rope", {"You put"})
    echo("Bundle unbundled.")
else
    show_help()
end
