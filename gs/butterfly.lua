--- @revenant-script
--- name: butterfly
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Replace names of characters, NPCs, mobs and loot with butterfly names
--- tags: fun, rename, butterfly
---
--- Usage:
---   ;butterfly     - Normal mode (replace names with butterflies)
---   ;butterfly pro - Replace every word with 'butterfly'

local mode = (script.vars[1] or ""):lower()

local BUTTERFLY_NAMES = {
    "Monarch", "Swallowtail", "Morpho", "Painted Lady", "Peacock",
    "Red Admiral", "Blue Morpho", "Luna Moth", "Tiger Swallowtail",
    "Fritillary", "Skipper", "Brimstone", "Apollo", "Adonis Blue",
    "Buckeye", "Viceroy", "Malachite", "Glasswing", "Ulysses",
    "Zebra Longwing", "Zebra Swallowtail", "Zephyr"
}

local name_cache = {}

local function get_butterfly(name)
    if not name_cache[name] then
        name_cache[name] = BUTTERFLY_NAMES[math.random(#BUTTERFLY_NAMES)] .. " Butterfly"
    end
    return name_cache[name]
end

add_hook("downstream", "butterfly_rename", function(text)
    if mode == "pro" then
        return text:gsub("%w+", "butterfly")
    end

    -- Replace known game object names with butterflies
    for _, collection in ipairs({"pcs", "npcs", "targets"}) do
        local objs = GameObj[collection]
        if objs then
            for _, obj in ipairs(objs) do
                if obj.name then
                    local escaped = obj.name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    text = text:gsub(escaped, get_butterfly(obj.name))
                end
            end
        end
    end
    return text
end)

before_dying(function()
    remove_hook("downstream", "butterfly_rename")
end)

echo("Butterfly mode: " .. (mode == "" and "normal" or mode))
while true do pause(1) end
