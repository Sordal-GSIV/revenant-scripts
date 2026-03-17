--- @revenant-script
--- name: alchemy
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Alchemy crafting automation - remedies, poisons, and other alchemical recipes
--- tags: crafting, alchemy, remedies, poisons
---
--- Ported from alchemy.lic (Lich5) to Revenant Lua (3076 lines - core functionality)
---
--- Requires: common, common-crafting, common-items, common-money, common-travel
---
--- YAML Settings:
---   alchemy_belt, crafting_container, hometown
---
--- Usage:
---   ;alchemy <recipe>           - Craft a specific recipe
---   ;alchemy recipe <name>      - Look up recipe details
---   ;alchemy list               - List known recipes
---   ;alchemy help               - Show help

local settings = get_settings()
local bag = settings.crafting_container or "backpack"
local belt = settings.alchemy_belt
local hometown = settings.hometown or "Crossing"

local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or "help"

local function show_help()
    echo("=== Alchemy ===")
    echo("DR Alchemy crafting automation.")
    echo("")
    echo("Usage:")
    echo("  ;alchemy <recipe>      - Craft a recipe")
    echo("  ;alchemy list          - List recipes")
    echo("  ;alchemy help          - This help")
    echo("")
    echo("Alchemy Steps:")
    echo("  1. Get recipe book and study")
    echo("  2. Get mortar/pestle from belt")
    echo("  3. Add herbs and catalysts")
    echo("  4. Crush/grind/mix until complete")
    echo("  5. Pour into container")
    echo("")
    echo("Common recipes: healing salve, blister cream, naphtha,")
    echo("  bleeding poultice, jadice flower poultice, etc.")
end

local function craft_step(command, tool)
    waitrt()
    local result = DRC.bput(command, {
        "Roundtime",
        "You need",
        "You can't",
        "Applying the final touches",
        "You grind",
        "You crush",
        "You mix",
        "You pour",
        "You add",
        "needs more",
    })
    waitrt()
    return result
end

local function do_alchemy(recipe)
    echo("Starting alchemy: " .. recipe)

    -- Get book and study
    DRCC.get_crafting_item("alchemy book", bag, nil, belt)
    DRC.bput("study my book", {"Roundtime"})
    waitrt()
    DRCC.stow_crafting_item("alchemy book", bag, belt)

    -- Get mortar
    DRCC.get_crafting_item("mortar", bag, nil, belt)

    -- Main crafting loop
    local done = false
    local max_steps = 50
    local step = 0

    while not done and step < max_steps do
        step = step + 1
        local r = craft_step("crush my mortar with my pestle", "pestle")

        if r:find("final touches") then
            done = true
            echo("Alchemy complete!")
        elseif r:find("needs more") then
            echo("Recipe needs more ingredients. Add them and retry.")
            break
        elseif r:find("You can't") then
            echo("Cannot continue crafting.")
            break
        end
    end

    DRCC.stow_crafting_item("mortar", bag, belt)
end

if cmd == "help" then
    show_help()
elseif cmd == "list" then
    echo("=== Alchemy Recipes ===")
    echo("See your alchemy book for available recipes.")
    echo("Common: healing salve, blister cream, naphtha,")
    echo("  bleeding poultice, jadice flower poultice,")
    echo("  general tonic, unguent, etc.")
else
    do_alchemy(table.concat(args, " "))
end
