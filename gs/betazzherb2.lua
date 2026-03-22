--- @revenant-script
--- name: betazzherb2
--- version: 5.3.0
--- author: Zzentar
--- contributors: Baswab, Gibreficul, Gnomad, Tsalinx
--- game: gs
--- description: Locate and forage herbs by name and quantity, with optional location filtering
--- tags: foraging, herbs, bounty
---
--- Usage:
---   ;betazzherb2 <herb name> <qty> [location]
---   ;betazzherb2 some pothinir grass 9 greymist woods
---   ;betazzherb2 some acantha leaf 17
---   ;betazzherb2 setup
---   ;betazzherb2 credits
---
--- Notes:
---   - Item name must match exactly (most herbs have 'some' in front)
---   - No combat capabilities -- do not leave unattended

-- Settings
local settings = CharSettings.load() or {}
local lootsack = UserVars.lootsack

local arg0 = Script.vars[0] or ""

if arg0 == "credits" then
    respond("* Zzherb was created by the late Ken Dumas, longtime player of Zzentar and others.")
    respond("* If you got to play with him, you were lucky. If not, you missed out. Rest in peace.")
    respond("*")
    respond("* Location function added by Baswab/Gibreficul.")
    respond("* Gnomad added some extra features and is trying to just keep things working nicely.")
    respond("* Ongoing maintenance by Tsalinx.")
    return
end

if arg0 == "setup" then
    echo("Setup is not yet available in Revenant. Set variables manually:")
    echo("  UserVars.lootsack = 'backpack'")
    echo("  CharSettings.kneel_to_forage = true/false")
    echo("  CharSettings.sanct_rooms = true/false")
    echo("  CharSettings.hide_to_forage = true/false")
    echo("  CharSettings.stow_stuff = true/false")
    return
end

-- Settings toggle: ;betazzherb2 --setting=value
if arg0:match("^%-%-(.+)=(.+)") then
    local setting, status = arg0:match("^%-%-(.+)=(.+)")
    local valid = { lootsack = true, sanct_rooms = true, kneel_to_forage = true, hide_to_forage = true, stow_stuff = true }
    if not valid[setting] then
        echo(setting .. " is not something you can set.")
        return
    end
    if setting == "lootsack" then
        UserVars.lootsack = status
        echo("lootsack set to " .. status)
        return
    end
    if status:match("true") or status:match("yes") or status:match("on") then
        settings[setting] = true
        CharSettings.save()
        echo(setting .. " is now on.")
    elseif status:match("false") or status:match("no") or status:match("off") then
        settings[setting] = false
        CharSettings.save()
        echo(setting .. " is now off.")
    else
        echo(status .. " is not a valid option for " .. setting .. ".")
    end
    return
end

if arg0:match("^%-%-(.+)$") then
    local setting = arg0:match("^%-%-(.+)$")
    if setting == "lootsack" then
        echo("Your lootsack is currently set to " .. tostring(UserVars.lootsack))
    elseif settings[setting] ~= nil then
        echo(setting .. " is currently " .. (settings[setting] and "on" or "off") .. ".")
    else
        echo(setting .. " is not something you can set.")
    end
    return
end

-- Validate hands
if checkleft() and checkright() then
    echo("YOU MUST HAVE AT LEAST ONE HAND EMPTY TO USE THIS SCRIPT.")
    echo("WAITING UNTIL YOU EMPTY A HAND.")
    wait_until(function() return not checkleft() or not checkright() end)
    echo("OK, CONTINUING.")
end

if not lootsack then
    respond("*** ERROR ***")
    respond("* You must set up a lootsack for your herbs.")
    respond("* Run ;betazzherb2 setup or set: UserVars.lootsack = 'backpack'")
    return
end

-- Parse arguments: herb qty [location]
local herb, qty, location
local bounty_mode = false

if arg0:match("^bounty") then
    -- Bounty mode: try to parse bounty string
    local bounty_str = bounty()
    if bounty_str and bounty_str:match("concoction that requires") then
        herb = bounty_str:match("concoction that requires (?:a |an )?(.+) found")
        location = bounty_str:match("found (?:on |in )?(.-)%s+(?:near|between|under)")
        qty = tonumber(bounty_str:match("retrieve (%d+)"))
        bounty_mode = true
    end
    if not herb then
        echo("This option only works if an herbalist has given you a bounty.")
        return
    end
else
    -- Standard: herb qty [location]
    herb, qty, location = arg0:match("^(.-)%s+(%d+)%s+(.*)")
    if not herb then
        herb, qty = arg0:match("^(.-)%s+(%d+)$")
    end
    qty = tonumber(qty)
end

if not herb or not qty then
    respond("***  ERROR ***")
    respond("*  Correct syntax: ;betazzherb2 <herbname> <number> [location]")
    respond("*  ;betazzherb2 some pothinir grass 9 greymist woods")
    respond("*  ;betazzherb2 some acantha leaf 17")
    respond("*  ;betazzherb2 setup    - for setup")
    respond("*  ;betazzherb2 credits  - for credits")
    return
end

-- Strip leading a/an
herb = herb:gsub("^an?%s+", "")

-- Herb name translations for bounty compatibility
local herb_translations = {
    ["ayana weed"]     = "ayana leaf",  ["ayana lichen"]  = "ayana leaf",
    ["ayana berry"]    = "ayana leaf",  ["ayana root"]    = "ayana leaf",
    ["length of deep purple shockroot"] = "deep purple shockroot",
    ["handful of blackberries"]  = "blackberries",
    ["waxy banana leaf"]         = "banana leaf",
    ["bulb of garlic"]           = "garlic",
    ["sprig of dill"]            = "dill",
    ["pod of cardamom"]          = "cardamom",
    ["handful of red cherries"]  = "red cherries",
    ["spherical sweet onion"]    = "sweet onion",
    ["stalk of fresh lemongrass"] = "fresh lemongrass",
    ["stalk of sugar cane"]      = "sugar cane",
    ["bunch of wild grapes"]     = "wild grapes",
    ["handful of dark blue honeyberries"] = "dark blue honeyberries",
    ["some fetid black slime"]   = "black slime",
    ["oblong red onion"]         = "red onion",
    ["handful of elderberries"]  = "elderberries",
    ["fragrant white lily"]      = "white lily",
    ["handful of plump black mulberries"] = "plump black mulberries",
    ["cluster of woad leaves"]   = "woad leaves",
    ["dark pink rain lily"]      = "pink rain lily",
    ["blue agave heart"]         = "agave heart",
    ["black-tipped wyrm thorn"]  = "wyrm thorn",
    ["handful of blueberries"]   = "blueberries",
    ["lumpy purple potato"]      = "purple potato",
    ["sprig of fresh cilantro"]  = "fresh cilantro",
    ["round brown potato"]       = "brown potato",
    ["clump of mold"]            = "blue mold",
    ["handful of walnuts"]       = "walnuts",
    ["handful of raspberries"]   = "raspberries",
    ["fuzzy brown-skinned kiwi"] = "brown-skinned kiwi",
    ["vermilion fire lily"]      = "fire lily",
    ["piece of long green okra"] = "long green okra",
    ["handful of huckleberries"] = "huckleberries",
    ["handful of bearberries"]   = "bearberries",
    ["handful of snowberries"]   = "snowberries",
    ["small round yuzu"]         = "round yuzu",
}

for pattern, replacement in pairs(herb_translations) do
    if herb:find(pattern, 1, true) then
        herb = replacement
        break
    end
end

-- Forage name translations (what to actually type in FORAGE command)
local forage_translations = {
    ["twisted black mawflower"]      = "mawflower",
    ["stem of freesia flowers"]      = "freesia flowers",
    ["small green olive"]            = "green olive",
    ["mass of congealed slime"]      = "congealed slime",
    ["oozing fleshsore bulb"]        = "fleshsore bulb",
    ["rotting bile green fleshbulb"] = "fleshbulb",
    ["discolored fleshbinder bud"]  = "fleshbinder bud",
    ["slime-covered grave blossom"] = "grave blossom",
    ["handful of elderberries"]      = "elderberries",
    ["sprig of wild lilac"]          = "lilac",
    ["fragrant white lily"]          = "white lily",
    ["handful of huckleberries"]     = "huckleberries",
    ["trollfear mushroom"]           = "mushroom",
    ["bunch of wild grapes"]         = "wild grapes",
    ["handful of blueberries"]       = "blueberries",
    ["handful of raspberries"]       = "raspberries",
    ["layer of onion skin"]          = "onion skin",
    ["vermilion fire lily"]          = "fire lily",
    ["handful of walnuts"]           = "walnuts",
    ["orange tiger lily"]            = "tiger lily",
    ["small branch of acacia"]       = "branch of acacia",
    ["golden flaeshorn berry"]       = "flaeshorn berry",
    ["white alligator lily"]         = "alligator lily",
    ["dark pink rain lily"]          = "pink rain lily",
    ["white spider lily"]            = "spider lily",
    ["handful of snowberries"]       = "snowberries",
    ["sprig of edelweiss"]           = "edelweiss",
    ["handful of bearberries"]       = "bearberries",
    ["cluster of woad leaves"]       = "woad leaves",
    ["large black toadstool"]        = "black toadstool",
    ["some glowing green lichen"]    = "green lichen",
    ["luminescent green fungus"]     = "green fungus",
    ["black-tipped wyrm thorn"]      = "wyrm thorn",
    ["some fetid black slime"]       = "black slime",
    ["sprig of sky-blue delphinuris"] = "delphinuris",
    ["handful of mustard seeds"]     = "mustard seeds",
    ["sprig of wild phlox"]          = "phlox",
    ["cluster of gorse"]             = "gorse",
    ["giant glowing toadstool"]      = "glowing toadstool",
}

local foragename = herb
for pattern, replacement in pairs(forage_translations) do
    if foragename == pattern then
        foragename = replacement
        break
    end
end

-- Handle iceblossom variants
if foragename:match("iceblossom$") then
    foragename = "iceblossom"
end
-- Handle stick variants
if foragename:match("^%w+ stick$") then
    foragename = "stick"
end
-- Handle mold variants
if foragename:match("%w+ mold$") then
    foragename = "mold"
end

if herb == "luminescent indigo mushroom" then
    respond("* You can't explicitly forage for luminescent indigo mushrooms.")
    respond("* All you can do is forage for some other herb and hope to accidentally find one.")
    return
end

-- Validate herb exists in map data
local herb_found = Room.tags_include(herb)
if not herb_found then
    local alt = herb:gsub("^some ", "")
    if Room.tags_include(alt) then
        herb = alt
        herb_found = true
    else
        alt = "some " .. herb
        if Room.tags_include(alt) then
            herb = alt
            herb_found = true
        end
    end
end

if not herb_found then
    echo("Error: can't find " .. herb .. " in the map database.")
    return
end

local start_room = Room.id
local start_time = os.time()

if location then
    echo("Number to find: " .. qty .. "  Item: " .. herb .. "  Location: " .. location)
else
    echo("Number to find: " .. qty .. "  Item: " .. herb)
end

-- Build target room list
local target_list = Room.find_by_tag(herb)

if location and location ~= "" then
    local filtered = {}
    for _, room_id in ipairs(target_list) do
        local room = Room[room_id]
        if room then
            local loc = room.location or ""
            local title = room.title or ""
            if loc:lower():find(location:lower(), 1, true) or title:lower():find(location:lower(), 1, true) then
                table.insert(filtered, room_id)
            end
        end
    end
    target_list = filtered
end

if #target_list == 0 then
    echo("No rooms found with that herb" .. (location and (" in " .. location) or "") .. ".")
    return
end

-- Sort by distance from current room
target_list = Room.sort_by_distance(target_list)

local righthand = checkright() == nil or settings.stow_stuff
local herb_count = 0
local shroom_count = 0

for _, herb_room in ipairs(target_list) do
    if herb_count >= qty then break end

    Script.run("go2", tostring(herb_room))

    if settings.stow_stuff then empty_hands() end

    -- Cast sanctuary if configured
    if settings.sanct_rooms and Spell[213]:known() and Spell[213]:affordable() then
        Spell[213]:cast()
    end

    -- Forage loop
    while herb_count < qty do
        -- Buffs
        if Spell[1035] and Spell[1035]:known() and not Spell[1035]:active() and settings.sing_tonis then
            Spell[1035]:cast()
        end

        if settings.kneel_to_forage and not kneeling() then
            fput("kneel")
        end

        if settings.hide_to_forage and not hidden() then
            fput("hide")
        end

        local result = dothistimeout("forage for " .. foragename, 5, {
            "You forage",
            "you must be able to use",
            "only the dead would not notice",
            "fruitless attempt",
            "unable to find anything useful",
            "can find no hint",
            "see no evidence",
            "fairly certain this is where it can be found",
            "stabs you in the finger",
            "sharp pain in your right hand",
            "burning sensation in your hand",
            "cannot take the remaining",
            "forage more than 15",
            "fumble about so badly",
        })

        pause(0.5)
        waitrt()

        if result and result:find("You forage briefly and manage to find") then
            local foragehand
            if righthand then
                foragehand = GameObj.right_hand
            else
                foragehand = GameObj.left_hand
            end

            if foragehand and foragehand.name == "luminescent indigo mushroom" then
                fput("mark #" .. foragehand.id)
                shroom_count = shroom_count + 1
            else
                herb_count = herb_count + 1
            end

            if foragehand then
                fput("put #" .. foragehand.id .. " in my " .. lootsack)
            end
        elseif result and result:find("sharp pain in your right hand") then
            if Spell[1102] and Spell[1102]:known() and Spell[1102]:affordable() then
                Spell[1102]:cast()
            end
        elseif result and result:find("you must be able to use") then
            fput("stow left")
        elseif result and result:find("fairly certain this is where it can be found") then
            echo("This is a night-only or day-only herb. Try again later.")
            if settings.stow_stuff then fill_hands() end
            Script.run("go2", tostring(start_room))
            return
        elseif not result or result:find("can find no hint") or result:find("see no evidence") then
            echo("Bad room or script timed out")
            break
        elseif result:find("unable to find anything useful") or result:find("cannot take the remaining") then
            echo("Foraged out")
            break
        elseif result:find("forage more than 15") then
            if settings.stow_stuff then fill_hands() end
            Script.run("go2", tostring(start_room))
            echo("F2P 15 herbs per hour limit reached")
            return
        end
    end

    if settings.stow_stuff then fill_hands() end
end

if settings.stow_stuff then fill_hands() end
Script.run("go2", tostring(start_room))

local elapsed = os.time() - start_time
echo("Found " .. herb_count .. " of " .. herb)
echo("It took " .. elapsed .. " seconds to find " .. herb_count .. " pieces of " .. foragename)

if herb_count < qty then
    echo("You still need " .. (qty - herb_count) .. " more pieces of " .. foragename .. ".")
end

if shroom_count > 0 then
    echo("")
    echo("You also found " .. shroom_count .. " luminescent indigo mushroom(s)!")
    echo("They are rare and can be used in ranger resist potions.")
    echo("They have been put in your " .. lootsack .. " and MARKed unsellable.")
end
