--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: widgetsearch
--- version: 1.0.1
--- author: Tysong
--- contributors: Luxelle
--- game: gs
--- tags: duskruin, battle vault, fizwixit, widget, gear
--- description: Scan inventory for tiny brass gears and categorize by theme/type
---
--- Original Lich5 authors: Tysong, Luxelle
--- Ported to Revenant Lua from widgetsearch.lic v1.0.1
---
--- Usage:
---   ;widgetsearch           - list all gears found
---   ;widgetsearch 60        - grab first theme #60 gear
---   ;widgetsearch duration  - grab first duration gear
---   ;widgetsearch uses      - grab first uses/day gear

local GEAR_DESCRIPTIONS = {
    ["1"]  = "A stunning viridian-sanded cove",
    ["2"]  = "An amphitheatre in the clouds",
    ["3"]  = "An elegant salon with sanguine roses and alabaster floors",
    ["4"]  = "A darkened bakery with hints of trouble",
    ["5"]  = "A waterlily pond where capyxitas frolic",
    ["6"]  = "A rudimentary thatched hut",
    ["7"]  = "A cozy tavern",
    ["8"]  = "Backstage at a darkened theatre with a view from a prop closet",
    ["9"]  = "A darkened stage with its curtains closed",
    ["10"] = "A proscenium theatre with a box seat view",
    ["11"] = "A giant mushroom theatre",
    ["12"] = "A crafting room",
    ["13"] = "A fighting ring outside a ramshackle barn",
    ["14"] = "A gazebo filled with teadragons",
    ["15"] = "A cozy library",
    ["16"] = "An ancient library",
    ["17"] = "A dungeon stage",
    ["18"] = "A magistrate's hall with an observation chamber",
    ["19"] = "A dock deep within a bayou",
    ["20"] = "A beautiful autumn clearing",
    ["21"] = "An isolated beach with a hidden cavern",
    ["22"] = "A moonlit meadow",
    ["23"] = "A ruin deep in the forest",
    ["24"] = "A cemetery and its mausoleum",
    ["25"] = "A grand foyer with a bit of a blood problem",
    ["26"] = "A training ground with a view from the crenels",
    ["27"] = "A tower somewhen",
    ["28"] = "A map-covered chamber",
    ["29"] = "A soothing tea thief hideaway",
    ["30"] = "An opulent library with a secret",
    ["31"] = "Somewhere in the stars, with a view from a distant nebula",
    ["32"] = "A bug jar adventure",
    ["33"] = "A throne room and audience gallery",
    ["34"] = "A stagnant mire",
    ["35"] = "A blossoming garden",
    ["36"] = "A desert sanctuary",
    ["37"] = "A prison cell",
    ["38"] = "A festive performance circle embraced by market sprawl",
    ["39"] = "A bend in a lazy river, sheltered by a great oak",
    ["40"] = "An ill-traveled road filled with fog",
    ["41"] = "A manicured lawn with a gazebo",
    ["42"] = "A moonlit road and a fortuneteller's tent",
    ["43"] = "A snowy mountain pass",
    ["44"] = "A misty wood with a fire-warmed clearing",
    ["45"] = "A lair on a volcanic cliff",
    ["46"] = "A beleria-strewn square",
    ["47"] = "A Lornonite altar",
    ["48"] = "A lakeshore in the woods",
    ["49"] = "An ephemeral oasis",
    ["50"] = "A forge yard",
    ["51"] = "A couturier's garden",
    ["52"] = "An expansive cookery",
    ["53"] = "A swamp and its hovel",
    ["54"] = "An elegant winter-themed ballroom",
    ["55"] = "A secure strategy area",
    ["56"] = "An alchemical laboratory",
    ["57"] = "An arid city courtyard enclosed by multifoil arches",
    ["58"] = "A ceremonial terrace in the southern jungles",
    ["59"] = "A lone altar in a desert wasteland",
    ["60"] = "A darkened alley with a seedy tavern",
    ["61"] = "A desert bazaar",
    ["62"] = "A jungle bazaar on the waterways",
    ["63"] = "A royal salon with a secret",
    ["64"] = "An outdoor theatre-in-the-round",
    ["65"] = "A lecture hall",
    ["66"] = "Somewhere over Wehnimer's Landing",
    ["uses"]     = "x/day increase, max of 4",
    ["duration"] = "increase duration from 30 to 60 minutes",
}

-- Populate contents of uninspected containers (mirrors WidgetSearch.populate_inventory).
-- Issues "look in #<id>" for each inv item and held bag whose contents are not yet loaded.
local function populate_containers()
    local candidates = {}
    for _, item in ipairs(GameObj.inv()) do
        table.insert(candidates, item)
    end
    local rh = GameObj.right_hand()
    if rh then table.insert(candidates, rh) end
    local lh = GameObj.left_hand()
    if lh then table.insert(candidates, lh) end

    for _, item in ipairs(candidates) do
        if item.contents ~= nil then goto continue end
        if item.type == nil then goto continue end
        if item.type:find("jewelry") or item.type:find("weapon") or
           item.type:find("armor")   or item.type:find("uncommon") then
            goto continue
        end
        -- Issue look-in to trigger the engine to populate contents for this container
        quiet_command("look in #" .. item.id,
            "exposeContainer|clearContainer|There is nothing|glance", nil, 3)
        ::continue::
    end
end

-- Search all containers (inv + held bags) for tiny brass gears.
local function find_gears()
    local all_items = {}
    local containers = {}
    for _, item in ipairs(GameObj.inv()) do
        table.insert(containers, item)
    end
    local rh = GameObj.right_hand()
    if rh then table.insert(containers, rh) end
    local lh = GameObj.left_hand()
    if lh then table.insert(containers, lh) end

    for _, container in ipairs(containers) do
        if container.contents then
            for _, thing in ipairs(container.contents) do
                if thing.name == "tiny brass gear" then
                    all_items[#all_items + 1] = { id = thing.id, container = container }
                end
            end
        end
    end
    return all_items
end

local function analyze_items(found_items)
    local results = {}
    echo("Analyzing " .. #found_items .. " items, please be patient, do not do anything until finished.")
    for _, item in ipairs(found_items) do
        local lines = quiet_command("analyze #" .. item.id, "You analyze|You inspect")
        for _, line in ipairs(lines or {}) do
            local theme = line:match('The theme for this is "(%d+) %-')
            if theme then
                results[theme] = results[theme] or {}
                results[theme][#results[theme] + 1] = item
            elseif line:find("increasing its total minutes per use from 30 to 60") then
                results["duration"] = results["duration"] or {}
                results["duration"][#results["duration"] + 1] = item
            elseif line:find("total # of uses per day") then
                results["uses"] = results["uses"] or {}
                results["uses"][#results["uses"] + 1] = item
            end
        end
    end
    return results
end

-- Main
populate_containers()
local found = find_gears()
if #found == 0 then
    echo("No gears found!")
    return
end

local analyzed = analyze_items(found)
local argv = Script.vars[1]

if argv and argv:match("^%d+$") then
    local items = analyzed[argv]
    if items and #items > 0 then
        echo("You have " .. #items .. " matching theme " .. argv .. ".")
        echo("Retrieving one from " .. items[1].container.name .. " now.")
        fput("get #" .. items[1].id)
    else
        echo("Nothing found matching theme " .. argv)
    end
elseif argv and argv:match("duration") then
    local items = analyzed["duration"]
    if items and #items > 0 then
        echo("You have " .. #items .. " matching duration.")
        echo("Retrieving one from " .. items[1].container.name .. " now.")
        fput("get #" .. items[1].id)
    else
        echo("No duration gears found.")
    end
elseif argv and argv:match("uses?") then
    local items = analyzed["uses"]
    if items and #items > 0 then
        echo("You have " .. #items .. " matching uses.")
        echo("Retrieving one from " .. items[1].container.name .. " now.")
        fput("get #" .. items[1].id)
    else
        echo("No uses gears found.")
    end
else
    -- List all found gears sorted numerically (theme numbers first), then strings
    local sorted_keys = {}
    for k, _ in pairs(analyzed) do sorted_keys[#sorted_keys + 1] = k end
    table.sort(sorted_keys, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        if na then return true end
        if nb then return false end
        return a < b
    end)
    for _, key in ipairs(sorted_keys) do
        local desc = GEAR_DESCRIPTIONS[key] or ""
        echo(key .. " - " .. #analyzed[key] .. " found - " .. desc)
    end
end
