--- @revenant-script
--- name: zzherb3
--- version: 1.0.0
--- author: Peggyanne
--- contributors: Zzentar, Baswab/Gibreficul
--- game: gs
--- description: Locates and forages specified herbs, returning you to starting room
--- tags: foraging, herbs
---
--- Usage: ;zzherb3 <herb name> <qty> [location]
--- Example: ;zzherb3 some pothinir grass 9 greymist woods

if checkleft() and checkright() then
    echo("YOU MUST HAVE AT LEAST ONE HAND EMPTY TO USE THIS SCRIPT.")
    exit()
end

local args = script.vars[0] or ""
local herb, qty, location

-- Parse arguments
local h, q, l = args:match("(.-)%s+(%d+)%s+(.*)")
if h then
    herb = h; qty = tonumber(q); location = l
else
    h, q = args:match("(.-)%s+(%d+)")
    if h then
        herb = h; qty = tonumber(q)
    else
        echo("Syntax: ;zzherb3 <herbname> <number> [location]")
        exit()
    end
end

local righthand = checkright() == nil
local herb_count = 0
local start_time = os.time()
local room = Room.id

echo("Number to find: " .. qty .. "  Item: " .. herb)
if location then echo("Location: " .. location) end

-- Find rooms with this herb
local target_list = {}
for _, r in ipairs(Room.list or {}) do
    if r.tags and r.tags[herb] then
        table.insert(target_list, r.id)
    end
end

if #target_list == 0 then
    echo("Can't find rooms with " .. herb)
    exit()
end

-- Sort by distance
local _, distances = Map.dijkstra(Room.id)
table.sort(target_list, function(a, b)
    return (distances[a] or 9999) < (distances[b] or 9999)
end)

-- Forage loop
for _, herb_room in ipairs(target_list) do
    if herb_count >= qty then break end

    Script.run("go2", tostring(herb_room))

    while herb_count < qty do
        if checknpcs() then break end

        fput("kneel")
        local result = dothistimeout("forage for " .. herb, 5, "You forage|unsuccessful|unable to find|can find no hint")
        pause(0.5)
        waitrt()

        if result and result:match("You forage") then
            fput("stow right")
            herb_count = herb_count + 1
        elseif not result or result:match("unable to find") or result:match("can find no hint") then
            echo("Bad room or foraged out")
            break
        end
    end
end

Script.run("go2", tostring(room))
echo("Found " .. herb_count .. " of " .. herb)
echo("It took " .. (os.time() - start_time) .. " seconds")
