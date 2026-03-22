--- @revenant-script
--- @lic-audit: collectible.lic validated 2026-03-18
--- name: collectible
--- author: Daedeus
--- game: gs
--- description: Search sacks for collectibles and deposit them at the local collectibles shop
--- tags: utility,collectibles,loot
---
--- Searches for collectibles in three locations:
---   - your gemsack
---   - your lootsack
---   - your overflowsack
--- Deposits them at the local collectibles shop.

--------------------------------------------------------------------------------
-- Collectible patterns (regex, matching original)
--------------------------------------------------------------------------------

local Collectibles = {
    "antique lockpick",
    "sliver of rough moonstone",
    "fossilized shell",
    "meteorite chipping",
    "small blue clay mortar",
    "marbled blue marble pestle",
    "some grey%-colored powder",
    "thin%-lipped clear glass bottle",
    "blood%-stained bandana",
    "Elanthian Guilds Council token",
    "ethereal chain",
    "ethereal pendant",
    "tiny ethereal orb",
    "piece of cloudy glass",
    "polished stone",
    "shard of cloudy soulstone",
    "golden piece of eight",
    "ruby shard",
    "luminescent sandstone chunk",
    "whisper of divine essence",
    "handful of (?:silver|gold|icy blue|iron|coral) flakes",
    "miniature (?:warrior|rogue|wizard|cleric|empath|sorcerer|ranger|bard|monk|paladin) figurine",
    "threaded (?:pink|grey|white|black|green) pearl",
    "(?:blue|yellow|red|black) cotton swathe",
    "ornate (?:Charl|Cholen|Eonak|Imaera|Jastev|Kai|Koar|Lorminstra|Lumnis|Oleani|Phoen|Ronan|Tonis|Andelas|Eorgina|Fash'lo'nae|Ivas|Luukos|Marlu|Mularos|Sheru|V'tull|Gosaena|Zelia|Huntress|Leya|Onar|Voln|Aeia|Jaston|Kuon|Meyno|Niima|Illoke|Amasalen|Arachne|Laethe|Tilamaire|Voaris|Voln) statuette",
    "(?:oblong|glossy|shiny|slick|rounded|cubic|flat|ovoid|heavy|mottled) smooth stone",
}

local function is_collectible(name)
    if not name then return false end
    for _, pattern in ipairs(Collectibles) do
        if Regex.test(name, pattern) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local start_room = Room.id

local sack_names = { UserVars.gemsack, UserVars.lootsack, UserVars.overflowsack }

-- Stow right hand if holding something
local right_item = nil
local rh = GameObj.right_hand()
if rh and rh.id then
    right_item = rh
    fput("stow #" .. rh.id)
end

local deposited = {}

local function go_collectible()
    local room = Room.current()
    if room and room.tags then
        for _, tag in ipairs(room.tags) do
            if tag == "collectibles" then return end
        end
    end
    Script.run("go2", "collectibles")
    wait_while(function() return running("go2") end)
end

for _, sack_name in ipairs(sack_names) do
    if sack_name and sack_name ~= "" then
        local sack = GameObj[sack_name]
        if sack then
            -- Force contents to load if empty
            local contents = sack.contents
            if not contents or #contents == 0 then
                fput("look in #" .. sack.id)
                pause(0.5)
                contents = sack.contents or {}
            end

            for _, item in ipairs(contents) do
                if is_collectible(item.name) then
                    echo("found collectible " .. item.name)
                    table.insert(deposited, item.name)
                    go_collectible()
                    fput("get #" .. item.id)
                    fput("deposit #" .. item.id)
                end
            end
        end
    end
end

-- Restore right hand item
if right_item then
    fput("get #" .. right_item.id)
end

-- Return to starting room if we moved
if Room.id ~= start_room then
    Script.run("go2", tostring(start_room))
    wait_while(function() return running("go2") end)
end

if #deposited == 0 then
    echo("We found no collectibles.")
else
    echo("We found and deposited " .. #deposited .. " items: ")
    for _, d in ipairs(deposited) do
        echo("--- " .. d)
    end
end
