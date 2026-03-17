--- @revenant-script
--- name: poisoncraft
--- version: 1.0.1
--- author: Ondreian
--- game: gs
--- description: Poison crafting automation — create and apply poisons to weapons
--- tags: rogue,poisoncraft,automation
---
--- Usage:
---   ;poisoncraft --poison=dreamer --limit=300
---   ;poisoncraft --help
---
--- Hold the weapon in your right hand before running.

local args = require("lib/args")

local POISONS = {
    disabling = {
        dreamer    = "Dreamer's Milk",
        merrybud   = "Merrybud",
        snailspace = "Snailspace Poison",
        dullard    = "Dullard's Folly",
        jester     = "Jester's Bane",
    },
    deadly = {
        ravager    = "Ravager's Revenge",
        ophidian   = "Ophidian Kiss",
        shatterlimb = "Shatterlimb Poison",
        fools      = "Fool's Deathwort",
        arachne    = "Arachne's Bite",
    },
}

local CHARGES_PER = {
    dreamer = 150, merrybud = 100, snailspace = 75, dullard = 50, jester = 50,
    ravager = 150, ophidian = 150, shatterlimb = 100, fools = 50, arachne = 50,
}

local function is_valid_poison(name)
    return POISONS.disabling[name] or POISONS.deadly[name]
end

local function is_deadly(name)
    return POISONS.deadly[name] ~= nil
end

local function show_help()
    respond("Poisoncraft automation for Gemstone IV")
    respond("")
    respond("Usage: ;poisoncraft --poison=<name> [--limit=<charges>]")
    respond("")
    respond("Available poisons:")
    for ptype, poisons in pairs(POISONS) do
        respond("  " .. ptype .. ":")
        for key, name in pairs(poisons) do
            respond("    " .. key .. " - " .. name)
        end
    end
    respond("")
    respond("Examples:")
    respond("  ;poisoncraft --poison=dreamer --limit=300")
    respond("  ;poisoncraft --poison=ravager")
end

local function recall_charges(item)
    local output = quiet_command("recall #" .. item.id, "As you recall|You are unable", 5)
    if not output then return 0 end
    for _, line in ipairs(output) do
        local charges = line:match("coated with (%d+) charges")
        if charges then return tonumber(charges) end
    end
    return 0
end

local function calculate_applications(charges, poison, limit)
    local per = CHARGES_PER[poison] or 50
    local remaining = limit - charges
    if remaining <= 0 then return 1 end
    local apps = math.ceil(remaining / per)
    return math.min(apps, 10)
end

local function buy_and_apply(item, poison, applications)
    local start_room = Map.current_room()
    Script.run("go2", "bank")
    fput("withdraw " .. (10000 * applications) .. " silver")
    Script.run("go2", "rogue guild shop")

    for _ = 1, applications do
        -- Order apothecary kit
        local output = quiet_command("order", "Catalog", 5)
        if output then
            for _, line in ipairs(output) do
                local order_num = line:match("(%d+)%..-apothecary kit")
                if order_num then
                    fput("order " .. order_num)
                    fput("buy")
                    break
                end
            end
        end
        fput("feat poisoncraft create " .. poison)
        fput("feat poisoncraft apply")
        fput("feat poisoncraft apply")
    end

    if start_room then
        Script.run("go2", tostring(start_room))
    end
end

-- Main
local opts = args.parse(Script.vars[0])

if opts.help then
    show_help()
    return
end

local poison = opts.poison
if not poison then
    echo("Please pass --poison=<name>")
    show_help()
    return
end

if not is_valid_poison(poison) then
    echo("Invalid poison: " .. poison)
    show_help()
    return
end

local rh = GameObj.right_hand()
if not rh then
    echo("Please hold the item you want to poison in your right hand.")
    return
end

if is_deadly(poison) and rh.type and not rh.type:match("weapon") then
    echo("Deadly poisons can only be applied to weapons.")
    return
end

local limit = tonumber(opts.limit) or 300
local charges = recall_charges(rh)
local applications = calculate_applications(charges, poison, limit)

echo("Current charges: " .. charges .. ", need " .. applications .. " application(s)")
buy_and_apply(rh, poison, applications)

charges = recall_charges(GameObj.right_hand())
echo(rh.name .. " now has " .. charges .. " charges")
