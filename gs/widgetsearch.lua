--- @revenant-script
--- name: widgetsearch
--- version: 1.0.1
--- author: Tysong
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
    ["1"] = "A stunning viridian-sanded cove",
    ["2"] = "An amphitheatre in the clouds",
    ["3"] = "An elegant salon with sanguine roses",
    ["60"] = "A darkened alley with a seedy tavern",
    ["uses"] = "x/day increase, max of 4",
    ["duration"] = "increase duration from 30 to 60 minutes",
}

local function find_gears()
    local all_items = {}
    for _, container in ipairs(GameObj.inv()) do
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
    echo("Analyzing " .. #found_items .. " items, please be patient...")
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

local found = find_gears()
if #found == 0 then
    echo("No gears found!")
    return
end

local analyzed = analyze_items(found)
local argv = Script.current.vars[1]

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
        echo("You have " .. #items .. " duration gears.")
        fput("get #" .. items[1].id)
    else
        echo("No duration gears found.")
    end
elseif argv and argv:match("uses?") then
    local items = analyzed["uses"]
    if items and #items > 0 then
        echo("You have " .. #items .. " uses gears.")
        fput("get #" .. items[1].id)
    else
        echo("No uses gears found.")
    end
else
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
