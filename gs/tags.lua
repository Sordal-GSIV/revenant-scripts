--- @revenant-script
--- name: tags
--- version: 1.7.0
--- author: elanthia-online
--- contributors: Ondreian, Xanlin, Tysong
--- game: gs
--- description: Map room tagging utility - add/remove/list room tags, forage sense crawling
--- tags: tags,map,forage,herbs,sense,crawl
---
--- Changelog (from Lich5):
---   v1.7.0 (2026-01-20): added 'splashy' option for meta:splashy tag
---   v1.6.6 (2023-02-08): ignore tag adjustments
---   v1.6.5 (2023-02-07): removes herbs not present (with day/night support)
---   v1.6.0 (2022-11-05): collects climate and terrain data for rangers
---   v1.5.0 (2022-11-04): collects missing uids while crawling
---
--- Usage:
---   ;tags --add [tag1] [tag2]...[tagN]   adds a list of tags to the room
---   ;tags --rm  [tag1] [tag2]...[tagN]   removes a list of tags from the room
---   ;tags --sense                        forage sense the current room
---   ;tags --ls                           shows all current tags for the room
---   ;tags --crawl current                crawl the current area using survival sense
---   ;tags --crawl <location>             crawl an area using survival sense
---   ;tags + [tag]                        add a single tag
---   ;tags - [tag]                        remove a single tag

local Tags = {}

-- Command constants
local ADD         = "--add"
local REMOVE      = "--rm"
local LIST        = "--ls"
local SENSE       = "--sense"
local CRAWL       = "--crawl"
local TIME_OF_DAY = "--time"
local PLANEWALKER = "--planewalker"
local ADD_ONE     = "+"
local REMOVE_ONE  = "-"
local DIFF        = "--diff"
local LIST_ROOMS  = "--list"

-- Parse args
local vars = Script.vars
local cmd_type = vars[1]
local cmd_tags = {}
for i = 2, #vars do
    table.insert(cmd_tags, vars[i])
end

-- Module state
local disable_confirm   = false
local skip_sensed       = true
local ranger_rooms_only = false
local ranger_sense_only = false
local outside_only      = false
local check_splashy     = false
local verbose           = true
local last_time_of_day  = nil
local last_time_of_day_tag = nil

-- Massive herb list for forage sense comparison
local herb_list = {
    "Elanthian snow rose","Gosaena's grace dianthus","Imaera's Lace","Mularosian whip vine",
    "acantha leaf","agave heart","alder bark","alligator lily","aloeas stem","alpine violet",
    "amber-hued mushroom","ambrominas leaf","angelica root","arctic brambles","arctic moss",
    "areca frond","auroral starflowers","ayana berry","ayana leaf","ayana lichen","ayana root",
    "ayana weed","ayana'al berry","ayana'al leaf","ayana'al lichen","ayana'al root",
    "azure iceblossom","banana leaf","barley grass","basal moss","bay leaf","bearberries",
    "bent stick","black acorn","black hook mushroom","black peppercorn","black slime",
    "black trafel mushroom","black vampire lily","black-tipped wyrm thorn","blackberries",
    "blackened moss","blackgrove root","blaestonberry blossom","bleeding heart rose",
    "bloodthorn stem","bloodwood twig","blue and white lantana","blue mold","blue moss",
    "blue passionflower","blue poppy","blue trafel mushroom","blue water lily",
    "blue whortleberry","blueberries","bolmara lichen","bougainvillea blossom",
    "branch of acacia","branch of kerria","bright blue iceblossom","bright green iceblossom",
    "bright pink plumeria","bright pink protea","bright red beet","bright red cranberry",
    "bright red iceblossom","bright red teaberry","broken twig","brostheras grass",
    "brown potato","brown-skinned kiwi","buckthorn berry","bunch of wild grapes",
    "bur-clover root","cactacae spine","cactus flower","calamia fruit","calamintha blossom",
    "calamintha flower","calmintha flower","canary yellow hibiscus","cardamom","cave moss",
    "cerulean starflowers","chives","cinnamon bark","cinnamon ferns","cloudberry",
    "cluster of butterflyweed","cluster of gorse","cluster of woad leaves","coppery rain lily",
    "coppery red gaura","coral hibiscus","coral plumeria","cordyline leaf","cothinar flower",
    "creeping fig vine","crimson crane flower","crimson dragonstalk","crimson heliconia",
    "crimson hibiscus","crowberry","crystalline stalk","cuctucae berry","cumin seeds",
    "daggerstalk mushroom","daggit root","dark blue honeyberries","dark cyan mistbloom",
    "dark pink plumeria","dark pink rain lily","dark purple date","date palm fronds",
    "deep plum direbloom","deep purple shockroot","dill","discolored fleshbinder bud",
    "ear of corn","earthen root","ebon drake claw root","ebon hibiscus","ebony twig",
    "edelweiss","elderberries","engorged bulb","ephlox moss","fairy primrose",
    "fairy's skirt mushroom","fennel bulb","feverfern stalk","fiddlehead fern",
    "fiery red iceblossom","fig","fire lily","flaeshorn berry","flaming violet",
    "flathead mushroom","fleshsore bulb","fountain grass","fragrant white lily","fresh basil",
    "fresh broccoli","fresh cilantro","fresh lemongrass","fresh oregano","frostflower",
    "frostweed","fuzzy peach","garlic","genkew mushroom","giant glowing toadstool",
    "ginger root","ginkgo nut","glowing toadstool","gok nut","gold-cored ruby starflowers",
    "golden apricot","golden aster","golden buttercup","golden flaeshorn berry",
    "golden heliconia","golden hook mushroom","golden poppy","gorse","green and red lantana",
    "green beans","green cabbage","green guava","green lichen","green mold","green olive",
    "green pear","green pepper","green tomato","handful of bearberries","handful of blueberries",
    "handful of currants","handful of elderberries","handful of huckleberries",
    "handful of mustard seeds","handful of oats","handful of pinenuts","handful of raspberries",
    "handful of snowberries","handful of walnuts","haphip root","heath aster","heavy stick",
    "honeysuckle vine","hop flowers","hosta flower","huckleberries","ice blue iceblossom",
    "ice tulip","iceblossoms","inky scorpidium moss","iris blossom","ironfern root",
    "juicy plum","juniper berry","karuka nuts","kylan berry","lady slipper blossom",
    "lapis-hued alpestris","large black toadstool","large sunflower","large white gardenia",
    "lavender heliconia","lavender iceblossom","layer of onion skin","leafy arugula","leek",
    "leopard-spotted heliconia","lettuce","light blue hydrangea","light red iceblossom",
    "lingonberry","lobster-claw heliconia","longgrass","luckbloom blossom",
    "luminescent blossom","luminescent green fungus","manroot stalk","marallis berry",
    "mass of congealed slime","matte black vampire lily","mezereon bark","mistweed",
    "misty pink dreamphlox","monkey grass","monstera frond","moonflower","moonflowers",
    "moonlight cactus-bloom","motherwort","mountain dryad","murdroot","murkweed",
    "mustard seeds","nettle leaf","night mare","nightbloom blossom","nightshade berry",
    "nutmeg","oak twig","ocotillo stick","off-white protea","oily flameleaf",
    "old man's beard lichen","onion skin","oozing fleshsore bulb","orange begonia",
    "orange crane flower","orange heliconia","orange pepper","orange rowanberry",
    "orange tiger lily","orange tomato","orange-yellow starfruit","orchil lichen","orris root",
    "oxblood lily","pale blue hibiscus","pale green iceblossom","pale peach mistbloom",
    "pale thornberry","pale violet iceblossom","pale yellow daffodil","pandanus twig",
    "pea pods","peach iceblossom","pearly green vine","pecans","pennyroyal stem",
    "pepperthorn root","perwinkle blue hibiscus","petrified shadowstalk","pin cushion protea",
    "pine cone","pine needles","pink and blue lantana","pink and violet mushroom",
    "pink begonia","pink clover blossom","pink heliconia","pink hydrangea","pink iceblossom",
    "pink mold","pink muhly grass","pink ostrich plume","pink passionflower","pink peony",
    "pink peppercorn","pink petunia","pink poppy","pink protea","pink rain lily",
    "pink water lily","plump black mulberries","pothinir grass","pristine white plumeria",
    "purple cabbage","purple clover blossom","purple crocus","purple eggplant",
    "purple hydrangea","purple mold","purple myklian","purple passion fruit",
    "purple passionflower","purple petunia","purple poppy","purple potato",
    "purple-tipped artichoke","rainbow chard","rainbow-striped mushroom","raspberries",
    "raw almonds","red begonia","red cherries","red clover blossom","red heliconia",
    "red lichen","red lychee","red mold","red myklian","red onion","red ostrich plume",
    "red passionflower","red pepper","red pincushion moss","red poppy","red tomato",
    "red trafel mushroom","red vornalite mushroom","red winterberry","red-black amaranth",
    "red-green mango","reeds","resurrection fern","rhubarb","rockberry","rose-marrow root",
    "rotting bile green fleshbulb","round white eggplant","russet gaura","rust orange gaura",
    "rust scorpidium moss","saffron alpestris","sagebrush root",
    "sanguine velvet martagon lily","sapphire blue rose","sassafras leaf","scallions",
    "scarlet direbloom","scarlet heliconia","shadowlace moss","shallot","short stick",
    "skeletal lace mushroom","sky-blue delphinuris","slender twig",
    "slime-covered grave blossom","small anemone","small apple","small banana",
    "small branch of acacia","small carnation","small coconut","small daisy","small dandelion",
    "small flower","small green olive","small lime","small loganberry","small peapod",
    "small primrose","small pumpkin","small rose","small turnip","small violet",
    "small wild rose","snapdragon stalk","snow lily","snow pansy","snow white iceblossom",
    "snowberries","soft orange iceblossom","soft white mushroom","soft white plumeria",
    "soft yellow iceblossom","some acantha leaf","some alder bark","some aloeas stem",
    "some ambrominas leaf","some angelica root","some arctic brambles","some arctic moss",
    "some barley grass","some basal moss","some blackened moss","some blue moss",
    "some bolmara lichen","some brostheras grass","some bur-clover root","some cactacae spine",
    "some calamia fruit","some cave moss","some cothinar flower","some cumin seeds",
    "some daggit root","some ephlox moss","some fetid black slime",
    "some glowing green lichen","some haphip root","some lettuce","some longgrass",
    "some mezereon bark","some mistweed","some monkey grass","some motherwort","some murkweed",
    "some nutmeg","some orchil lichen","some pennyroyal stem","some petrified shadowstalk",
    "some pine needles","some pothinir grass","some red lichen","some reeds",
    "some rose-marrow root","some shadowlace moss","some sovyn clove","some star anise",
    "some strigae cactus","some talneo root","some thyme","some torban leaf","some tree bark",
    "some tundra grass","some valerian root","some wheat grass","some wild sage",
    "some wingstem root","some wiregrass","some wolifrew lichen","some woth flower",
    "some wyrmwood bark","spear-headed heliconia","spearmint leaf",
    "spectral violet dreamphlox","spider lily","sponge mushroom",
    "spore-filled tangerine mushroom","spotted heart mushroom","sprig of Imaera's Lace",
    "sprig of alyssum","sprig of amaranth","sprig of bleeding-heart","sprig of boxwood",
    "sprig of clematis","sprig of columbine","sprig of dill","sprig of edelweiss",
    "sprig of foxglove","sprig of heliotrope","sprig of hellebore","sprig of holly",
    "sprig of ivy","sprig of jasmine","sprig of larkspur","sprig of lavender",
    "sprig of mistletoe","sprig of mournbloom","sprig of rosemary",
    "sprig of sky-blue delphinuris","sprig of sneezeweed","sprig of thanot",
    "sprig of wild lilac","sprig of wild phlox","stalk of bluebells","stalk of burdock",
    "stalk of cattail","stalk of celery","stalk of chicory","stalk of drakefern",
    "stalk of goldenrod","stalk of monkeyflower","stalk of tuberose","stalk of wormwood",
    "stalks of snakeroot","star anise","stargazer lily","stem of freesia flowers",
    "stem of verbena","stick","sticks","strand of seaweed","strigae cactus",
    "striped heart mushroom","striped tomato","sugar cane","sunburst blossom",
    "sunflower seeds","sweet onion","sweet potato","sweetfern stalk","talneo root",
    "tangerine hibiscus","tangerine mushroom","tarweed plant","teal pincushion moss",
    "tendril of vinca","thyme","tiger lily","tkaro root","tobacco leaves","torban leaf",
    "traesharm berry","tree bark","trollfear mushroom","trumpet vine tendril","tundra grass",
    "turquoise plumeria","turquoise vine","twisted black mawflower","twisted twig",
    "valerian root","vanilla bean","velvet martagon lily","velvety onyx rose",
    "vermilion fire lily","vert drake claw root","vibrant yellow plumeria","violet hibiscus",
    "violet-tipped starflowers","walnuts","water chestnut","wavepetal blossom","wheat grass",
    "white alligator lily","white baneberry","white begonia","white clover blossom",
    "white hook mushroom","white hydrangea","white lily","white mold","white passionflower",
    "white peony","white petunia","white poppy","white spider lily","white water lily",
    "wide pandanus fronds","wild beechnut","wild carrot","wild chokecherry","wild gooseberry",
    "wild grapes","wild orchid","wild pansy blossom","wild pink geranium","wild sage",
    "wild spinach","wild strawberry","wild tulip","wingstem root","winter rose",
    "wintergreen leaf","wiregrass","witchwood twig","withered black mushroom",
    "withered deathblossom","woad leaves","wolfsbane root","wolifrew lichen","wood violet",
    "woth flower","wyrm thorn","wyrmwood bark","yabathilium fruit","yellow and red lantana",
    "yellow clover blossom","yellow heliconia","yellow iceblossom","yellow lemon","yellow mold",
    "yellow ostrich plume","yellow papaya","yellow passionflower","yellow pepper","yellow poppy",
    "yellow primrose","yellow scale lichen","yellow squash","yellow tomato","yellow water lily",
    "yew twig","zucchini","black mawflower","black toadstool","congealed slime",
    "fleshbinder bud","grave blossom","green fleshbulb","rye grass","wintercrisp apple",
}

local night_only = {
    "amber-hued mushroom","auroral starflowers","black vampire lily","cerulean starflowers",
    "fire lily","gold-cored ruby starflowers","misty pink dreamphlox","moonflower",
    "moonlight cactus-bloom","nightbloom blossom","oxblood lily","skeletal lace mushroom",
    "spectral violet dreamphlox","spider lily","trollfear mushroom",
    "violet-tipped starflowers","white hook mushroom",
}

local day_only = {
    "golden hook mushroom","red trafel mushroom","red vornalite mushroom",
    "spotted heart mushroom","striped heart mushroom","sunburst blossom",
}

local ignore_tags = {
    "closed", "duplicate", "gone", "meta:latched", "meta:che", "meta:event",
    "meta:fest", "meta:game:GSPlat", "meta:game:GSF", "meta:game:GST",
    "meta:game:GSIV", "meta:locker", "meta:locker annex", "meta:jail cell",
    "meta:map:virtual room", "meta:mentor", "meta:mho", "meta:mobile",
    "meta:private home", "meta:private property", "meta:pay-to-play",
    "meta:quest", "meta:society:Council of Light", "meta:society:Order of Voln",
    "meta:society:Guardians of Sunfist", "meta:storyline", "meta:taskroom",
    "meta:transport", "meta:transition", "meta:trap", "meta:underwater",
    "meta:workroom", "missing", "no forageables", "no-auto-map",
    "private property", "rewritten", "urchin-hideout",
}

-- Helper: check if table contains value
local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

-- Helper: table difference (a - b)
local function table_diff(a, b)
    local result = {}
    for _, v in ipairs(a) do
        if not table_contains(b, v) then
            table.insert(result, v)
        end
    end
    return result
end

-- Helper: table intersection (a & b)
local function table_intersect(a, b)
    local result = {}
    for _, v in ipairs(a) do
        if table_contains(b, v) then
            table.insert(result, v)
        end
    end
    return result
end

-- Helper: table union with uniqueness
local function table_union(a, b)
    local result = {}
    local seen = {}
    for _, v in ipairs(a) do
        if not seen[v] then
            table.insert(result, v)
            seen[v] = true
        end
    end
    for _, v in ipairs(b) do
        if not seen[v] then
            table.insert(result, v)
            seen[v] = true
        end
    end
    return result
end

-- Remove current game from ignore list
local current_game_tag = "meta:game:" .. GameState.game
for i = #ignore_tags, 1, -1 do
    if ignore_tags[i] == current_game_tag then
        table.remove(ignore_tags, i)
    end
end

-- Logging
local function log(message, bold)
    if bold == nil then bold = true end
    if type(message) == "table" then
        for _, msg in ipairs(message) do
            log(msg, bold)
        end
        return
    end
    if bold then
        respond("<b>" .. tostring(message) .. "</b>")
    else
        respond(tostring(message))
    end
end

-- Time of day detection
local function time_of_day()
    local time_map = {
        ["after midnight"]   = "night",
        ["morning twilight"] = "night",
        ["early morning"]    = "day",
        ["mid morning"]      = "day",
        ["afternoon"]        = "day",
        ["late afternoon"]   = "day",
        ["evening twilight"] = "night",
        ["late evening"]     = "night",
    }
    fput("time")
    local line = waitforre("It is currently")
    if line then
        local tod = line:match("It is currently (.-)%.")
        if tod and time_map[tod] then
            last_time_of_day = time_map[tod]
        end
    end
    return last_time_of_day or "???"
end

local function time_of_day_tag()
    local tod = time_of_day()
    last_time_of_day_tag = "meta:forage-sensed:" .. tod .. ":" .. os.date("!%Y-%m")
    return last_time_of_day_tag
end

-- Tag operations
function Tags.list()
    local room = Room.current()
    if room and room.tags then
        log("tags: " .. table.concat(room.tags, ", "))
    else
        log("tags: (none)")
    end
end

function Tags.add(tags_to_add)
    local room = Room.current()
    if not room then
        log("No current room.")
        return
    end
    local current_tags = room.tags or {}
    local new_tags = table_diff(tags_to_add, current_tags)
    if #new_tags == 0 then
        log(Script.name .. ": no tags added.")
    else
        for _, tag in ipairs(new_tags) do
            table.insert(room.tags, tag)
        end
        log(Script.name .. ": tags added to " .. tostring(room.id) .. ": " .. table.concat(new_tags, ", "))
    end
end

function Tags.remove(tags_to_remove)
    local room = Room.current()
    if not room then return end
    local removed = table_intersect(tags_to_remove, room.tags or {})
    if #removed > 0 then
        room.tags = table_diff(room.tags, removed)
        log(Script.name .. ": tags removed from " .. tostring(room.id) .. ": " .. table.concat(removed, ", "))
    end
end

-- Forage sense
local function forage_sense()
    if Skills.survival < 25 then
        echo("You do not have enough survival for this.")
        return {}
    end
    fput("forage sense")
    local line = waitforre("Glancing about|You do not spot any forag|You can't really do that while underwater|You are a ghost")
    if not line then return {} end

    local sense_tags = {}
    if line:find("Glancing about, you notice") then
        -- Parse herbs from the sense result
        local herb_str = line:gsub("Glancing about, you notice the immediate area should support specimens of ", "")
        herb_str = herb_str:gsub(", and ", ", ")
        herb_str = herb_str:gsub("%.$", "")
        for herb in herb_str:gmatch("[^,]+") do
            herb = herb:match("^%s*(.-)%s*$") -- trim
            if herb ~= "" then
                table.insert(sense_tags, herb)
            end
        end
        table.insert(sense_tags, "meta:forage-sensed")
        table.insert(sense_tags, time_of_day_tag())
    elseif line:find("You do not spot any forag") or line:find("you doubt that anything") then
        table.insert(sense_tags, "no forageables")
    elseif line:find("underwater") then
        table.insert(sense_tags, "meta:underwater")
        table.insert(sense_tags, "no forageables")
    elseif line:find("You are a ghost") then
        echo("Oops! You're dead. Quitting.")
        return nil
    else
        table.insert(sense_tags, "no forageables")
        echo("forage_sense: unknown sense result")
    end
    return sense_tags
end

-- Ranger climate/terrain sense
local function ranger_sense()
    if Stats.prof ~= "Ranger" then return end
    fput("sense")
    local line = waitforre("indications of the|You carefully assess|You can't do that")
    if not line then return end

    if line:find("You carefully assess") then
        log("No new climate/terrain insight.")
    elseif line:find("indications of the") then
        local climate = line:match("the (.-) climate") or ""
        local terrain = line:match("the (.-) terrain") or line:match("the (.-) environment") or line:match("the (.-) forest") or ""
        climate = climate:match("^%s*(.-)%s*$") or ""
        terrain = terrain:match("^%s*(.-)%s*$") or ""
        log("climate: " .. climate .. "; terrain: " .. terrain)
    end
end

-- Splashy sense
local function splashy_sense()
    local room = Room.current()
    if not room then return end
    fput("splash")
    local line = waitforre("You just splashed yourself|How do you plan to do that here")
    if not line then return end
    if line:find("You just splashed yourself") then
        if not table_contains(room.tags, "meta:splashy") then
            table.insert(room.tags, "meta:splashy")
            if verbose then log("Added meta:splashy tag") end
        end
    elseif line:find("How do you plan to do that here") then
        for i = #room.tags, 1, -1 do
            if room.tags[i] == "meta:splashy" then
                table.remove(room.tags, i)
                if verbose then log("Removed meta:splashy tag") end
            end
        end
    end
end

-- Herbs not present (should be removed)
local function herbs_not_present(sense_tags)
    local filtered_herbs
    if last_time_of_day == "night" then
        filtered_herbs = table_diff(herb_list, day_only)
    elseif last_time_of_day == "day" then
        filtered_herbs = table_diff(herb_list, night_only)
    else
        filtered_herbs = table_diff(table_diff(herb_list, night_only), day_only)
    end
    local room = Room.current()
    if not room or not room.tags then return {} end
    local current_herbs = table_intersect(room.tags, filtered_herbs)
    return table_diff(current_herbs, sense_tags)
end

-- Full sense operation
function Tags.sense()
    if not ranger_sense_only then
        local sense_tags = forage_sense()
        if sense_tags == nil then return end -- ghost/dead
        Tags.add(sense_tags)

        -- Remove old meta tags and herbs not present
        local tags_to_remove = herbs_not_present(sense_tags)
        -- Remove "no forageables" if herbs were found
        local room = Room.current()
        if room and room.tags then
            local found_herbs = table_intersect(herb_list, sense_tags)
            if #found_herbs > 0 and table_contains(room.tags, "no forageables") then
                table.insert(tags_to_remove, "no forageables")
            end
        end
        if #tags_to_remove > 0 then
            Tags.remove(tags_to_remove)
        end
    end

    ranger_sense()
    if check_splashy then
        splashy_sense()
    end
end

-- Crawl an area
function Tags.crawl(location)
    if Skills.survival < 25 then
        echo("You do not have enough survival for this.")
        return
    end

    if not location or location == "" then
        local room = Room.current()
        if room then
            location = room.location or "current"
        else
            echo("Cannot determine current location.")
            return
        end
    end

    -- Find rooms matching location
    local all_rooms = Map.list()
    local room_ids = {}
    for _, room in ipairs(all_rooms) do
        if room.location == location then
            if not outside_only or (room.paths and room.paths[1] and room.paths[1]:find("Obvious paths")) then
                if not ranger_rooms_only or (not room.climate or not room.terrain) then
                    table.insert(room_ids, room.id)
                end
            end
        end
    end

    -- Filter out ignored rooms
    local filtered_ids = {}
    for _, id in ipairs(room_ids) do
        local room = Map.find_room(id)
        if room then
            local dominated = false
            for _, tag in ipairs(room.tags or {}) do
                if table_contains(ignore_tags, tag) then
                    dominated = true
                    break
                end
            end
            if not dominated then
                table.insert(filtered_ids, id)
            end
        end
    end

    if #filtered_ids == 0 then
        log("No rooms found for " .. tostring(location) .. ".")
        return
    end

    log("Going to crawl " .. #filtered_ids .. " rooms in " .. tostring(location) .. " starting in 2 seconds.")
    pause(2)

    local current = Room.current()
    for _, target_id in ipairs(filtered_ids) do
        Map.go2(tostring(target_id))
        wait_while(function() return running("go2") end)
        local now = Room.current()
        if now and now.id == target_id then
            Tags.sense()
        else
            log("unable to reach " .. tostring(target_id))
        end
    end
end

-- Help text
local function show_help()
    respond([[
  usage:
    ;tags --add [tag1] [tag2]...[tagN]   adds a list of tags to the room
    ;tags --rm  [tag1] [tag2]...[tagN]   removes a list of tags from the room
    ;tags --sense                        attempt to use your survival skill to add missing herbs to a room
    ;tags --ls                           shows all current tags for the room
    ;tags --crawl current                crawl the current area using survival sense
    ;tags --crawl <location>             crawl an area using survival sense
    ;tags --list <location>              list rooms for a location

  crawl options (can be mixed and matched)
    ;tags --crawl ranger                  # only does rooms that need climate/terrain
    ;tags --crawl climate                 # only does ranger sense for climate/terrain
    ;tags --crawl outside                 # only does outside rooms
    ;tags --crawl splashy                 # also checks if rooms allow SPLASH verb
    ;tags --crawl noskip                  # doesn't skip rooms already sensed

  single tag operations:
    ;tags + [tag]                        add a single tag
    ;tags - [tag]                        remove a single tag
    ]])
end

-- Main dispatch
if cmd_type == ADD then
    Tags.add(cmd_tags)
    Tags.list()
elseif cmd_type == REMOVE then
    Tags.remove(cmd_tags)
    Tags.list()
elseif cmd_type == LIST then
    Tags.list()
elseif cmd_type == ADD_ONE then
    Tags.add({table.concat(cmd_tags, " ")})
elseif cmd_type == REMOVE_ONE then
    Tags.remove({table.concat(cmd_tags, " ")})
    Tags.list()
elseif cmd_type == SENSE then
    ranger_sense_only = table_contains(cmd_tags, "climate")
    check_splashy = table_contains(cmd_tags, "splashy")
    if table_contains(cmd_tags, "noskip") then skip_sensed = false end
    Tags.sense()
elseif cmd_type == CRAWL then
    local anchor = Room.current() and Room.current().id
    outside_only = table_contains(cmd_tags, "outside")
    ranger_sense_only = table_contains(cmd_tags, "climate")
    ranger_rooms_only = table_contains(cmd_tags, "ranger")
    check_splashy = table_contains(cmd_tags, "splashy")
    if table_contains(cmd_tags, "noskip") then skip_sensed = false end
    -- Remove option keywords from tags to get location
    local location_parts = {}
    local option_words = {outside=true, climate=true, ranger=true, splashy=true, noskip=true}
    for _, tag in ipairs(cmd_tags) do
        if not option_words[tag] then
            table.insert(location_parts, tag)
        end
    end
    Tags.crawl(table.concat(location_parts, " "))
    local now = Room.current()
    if anchor and now and now.id ~= anchor then
        Script.run("go2", tostring(anchor))
    end
elseif cmd_type == TIME_OF_DAY then
    log(time_of_day())
elseif cmd_type == DIFF then
    -- Simplified diff: show current tags vs forage sense
    local sense = forage_sense()
    if sense then
        local room = Room.current()
        respond("Forage sense: " .. table.concat(sense, ", "))
        if room and room.tags then
            respond("Room tags: " .. table.concat(room.tags, ", "))
        end
    end
else
    show_help()
end
