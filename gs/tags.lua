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
--- @lic-certified: complete 2026-03-18

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
local last_time_of_day     = nil
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

-- GS4 "interesting" location tags (not forageables) for diff filtering
local gs_interesting_tags = {
    "advguard","advguard2","advguild","advpickup","alchemist","armorshop","bakery","bank",
    "bardguild","boutique","chronomage","clericguild","clericshop","collectibles",
    "consignment","empathguild","exchange","fletcher","forge","furrier","gemshop",
    "general store","herbalist","inn","locksmith pool","locksmith","mail","movers",
    "npccleric","npchealer","pawnshop","postoffice","rangerguild","smokeshop",
    "sorcererguild","sunfist","town","voln","warriorguild","weaponshop","wizardguild",
}
local gs_other_tags = { "urchin-access","node","supernode","locksmithpool" }

local ignore_tags = {
    "closed","duplicate","gone","meta:latched","meta:che","meta:event",
    "meta:fest","meta:game:GSPlat","meta:game:GSF","meta:game:GST",
    "meta:game:GSIV","meta:locker","meta:locker annex","meta:jail cell",
    "meta:map:virtual room","meta:mentor","meta:mho","meta:mobile",
    "meta:private home","meta:private property","meta:pay-to-play",
    "meta:quest","meta:society:Council of Light","meta:society:Order of Voln",
    "meta:society:Guardians of Sunfist","meta:storyline","meta:taskroom",
    "meta:transport","meta:transition","meta:trap","meta:underwater",
    "meta:workroom","missing","no forageables","no-auto-map",
    "private property","rewritten","urchin-hideout",
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

-- Helper: deduplicate a table in-place (returns new table)
local function table_uniq(t)
    local seen = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            table.insert(result, v)
            seen[v] = true
        end
    end
    return result
end

-- Merge dynamic ignore tags from all map tags matching meta:fest/mho/che/prof/gld/gender/event/quest
local all_map_tags = Map.all_tags and Map.all_tags() or {}
if type(all_map_tags) == "table" then
    for _, tag in ipairs(all_map_tags) do
        if tag:find("^meta:fest") or tag:find("^meta:mho") or tag:find("^meta:che")
           or tag:find("^meta:prof") or tag:find("^meta:gld") or tag:find("^meta:gender")
           or tag:find("^meta:locker annex") or tag:find("^meta:event") or tag:find("^meta:quest") then
            if not table_contains(ignore_tags, tag) then
                table.insert(ignore_tags, tag)
            end
        end
    end
end
ignore_tags = table_uniq(ignore_tags)
table.sort(ignore_tags)

-- Build crawl_if_current_tags: tags that should be removed from the ignore list when we're IN that room
local crawl_if_current_tags = {"meta:private property", "private property"}
if type(all_map_tags) == "table" then
    for _, tag in ipairs(all_map_tags) do
        if tag:find("^meta:fest") or tag:find("^meta:mho") or tag:find("^meta:che")
           or tag:find("^meta:prof") or tag:find("^meta:gld") or tag:find("^meta:storyline")
           or tag:find("^meta:mentor") or tag:find("^meta:society") or tag:find("^meta:quest")
           or tag:find("^meta:trap") then
            if not table_contains(crawl_if_current_tags, tag) then
                table.insert(crawl_if_current_tags, tag)
            end
        end
    end
end

-- Remove current game/profession/race/gender/society tags from ignore list
local function remove_ignore_tag(tag)
    for i = #ignore_tags, 1, -1 do
        if ignore_tags[i] == tag then
            table.remove(ignore_tags, i)
        end
    end
end

-- Remove current game tag (GS3=GST, GS1=GSPlat, GS4=GSIV)
if GameState and GameState.game then
    remove_ignore_tag("meta:game:" .. GameState.game)
    if GameState.game == "GST" then
        remove_ignore_tag("meta:game:GSIV")
    end
end
if Stats.prof and Stats.prof ~= "" then
    remove_ignore_tag("meta:prof:" .. Stats.prof:lower())
end
if Stats.gender and Stats.gender ~= "" then
    remove_ignore_tag("meta:gender:" .. Stats.gender:lower())
end
if Stats.race and Stats.race ~= "" then
    remove_ignore_tag("meta:race:" .. Stats.race:lower())
end
-- Remove character-specific tags (che, mho, gld, society)
if Char then
    if Char.che and Char.che ~= "" then
        remove_ignore_tag("meta:che:" .. tostring(Char.che))
    end
    if Char.mho then
        if type(Char.mho) == "table" then
            for _, m in ipairs(Char.mho) do
                remove_ignore_tag("meta:mho:" .. tostring(m))
            end
        end
    end
    if Char.gld and Char.gld ~= "" then
        remove_ignore_tag("meta:gld:" .. tostring(Char.gld):lower())
    end
end
if Society and Society.status and Society.status ~= "" then
    remove_ignore_tag("meta:society:" .. Society.status)
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

-- Get current map room object (nil if unknown)
local function current_room()
    local id = Room.id
    if not id then return nil end
    return Map.find_room(id)
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

-- Tag operations — mutate in-memory map via engine API
function Tags.list()
    local room = current_room()
    if room then
        local tags = table_uniq(room.tags or {})
        log("tags: " .. table.concat(tags, ", "))
    else
        log("tags: (none)")
    end
end

function Tags.add(tags_to_add)
    local room_id = Room.id
    if not room_id then log("No current room."); return end
    local room = Map.find_room(room_id)
    local current_tags = room and room.tags or {}
    local new_tags = table_diff(tags_to_add, current_tags)
    if #new_tags == 0 then
        log(Script.name .. ": no tags added.")
    else
        for _, tag in ipairs(new_tags) do
            Map.add_tag(room_id, tag)
        end
        log(Script.name .. ": tags added to " .. tostring(room_id) .. ": " .. table.concat(new_tags, ", "))
    end
end

function Tags.remove(tags_to_remove)
    local room_id = Room.id
    if not room_id then return end
    local room = Map.find_room(room_id)
    local removed = table_intersect(tags_to_remove, room and room.tags or {})
    if #removed > 0 then
        for _, tag in ipairs(removed) do
            Map.remove_tag(room_id, tag)
        end
        log(Script.name .. ": tags removed from " .. tostring(room_id) .. ": " .. table.concat(removed, ", "))
    end
end

-- Remove duplicate tags from current room
function Tags.uniq()
    local room_id = Room.id
    if not room_id then return end
    local room = Map.find_room(room_id)
    if not room or not room.tags then return end
    local seen = {}
    local dupes = {}
    for _, tag in ipairs(room.tags) do
        if seen[tag] then
            table.insert(dupes, tag)
        else
            seen[tag] = true
        end
    end
    for _, tag in ipairs(dupes) do
        Map.remove_tag(room_id, tag)
    end
end

-- Add missing XML UID to the map room's uid list
local function add_missing_uid()
    local room_id = Room.id
    if not room_id then return end
    -- In GS4, GameState.room_id == map room ID, but the server may also provide
    -- a separate XML room UID via the uid field. Use Room.id as the server uid.
    local room = Map.find_room(room_id)
    if not room then return end
    -- Check if this room_id is already recorded in the uid list
    local uid_field = room.uid
    local already_present = false
    if type(uid_field) == "number" then
        already_present = (uid_field == room_id)
    elseif type(uid_field) == "string" then
        already_present = (tonumber(uid_field) == room_id)
    elseif type(uid_field) == "table" then
        for _, v in ipairs(uid_field) do
            if tonumber(v) == room_id then
                already_present = true
                break
            end
        end
    end
    if not already_present then
        Map.add_uid(room_id, room_id)
        log("adding uid " .. tostring(room_id) .. " to room " .. tostring(room_id))
    end
end

-- Forage sense: send 'forage sense', parse herb results
local function forage_sense()
    if Skills.survival < 25 then
        echo("You do not have enough survival for this.")
        return {}
    end
    fput("forage sense")
    local line = waitforre("Glancing about|You do not spot any forag|you doubt that anything|You can't really do that while underwater|You are too distracted|You are a ghost")
    if not line then return {} end

    local sense_tags = {}
    if line:find("Glancing about, you notice") then
        -- Parse herb list from sense output
        local herb_str = line:gsub("Glancing about, you notice the immediate area should support specimens of ", "")
        herb_str = herb_str:gsub(", and ", ", ")
        herb_str = herb_str:gsub("%.$", "")
        for herb in herb_str:gmatch("[^,]+") do
            herb = herb:match("^%s*(.-)%s*$")
            if herb ~= "" then
                table.insert(sense_tags, herb)
            end
        end
        table.insert(sense_tags, "meta:forage-sensed")
        table.insert(sense_tags, time_of_day_tag())
    elseif line:find("you doubt that anything") or line:find("You do not spot any forag") then
        table.insert(sense_tags, "no forageables")
    elseif line:find("underwater") or line:find("You are too distracted") then
        table.insert(sense_tags, "meta:underwater")
        table.insert(sense_tags, "no forageables")
    elseif line:find("You are a ghost") then
        echo("Oops! You're dead. Quitting.")
        return nil
    else
        table.insert(sense_tags, "no forageables")
        echo(Script.name .. ": forage_sense: unknown sense result")
    end
    return sense_tags
end

-- Ranger climate/terrain sense — stores data in map via Map.set_climate/set_terrain
local function ranger_sense()
    if Stats.prof ~= "Ranger" then return end
    local room_id = Room.id
    if not room_id then return end
    local room = Map.find_room(room_id)

    -- Skip if already have climate+terrain and skip_sensed is on
    if skip_sensed and room and room.climate and room.terrain then return end

    fput("sense")
    local line = waitforre("indications of the|You carefully assess|You can't do that")
    if not line then return end

    if line:find("You carefully assess") then
        -- No new insight — mark as 'none' if nil so we know we tried
        if room then
            if not room.climate then Map.set_climate(room_id, "none") end
            if not room.terrain then Map.set_terrain(room_id, "none") end
        end
        -- Refresh after mutations
        room = Map.find_room(room_id)
        log("climate: " .. tostring(room and room.climate) .. "; terrain: " .. tostring(room and room.terrain))
    elseif line:find("indications of the") then
        local climate = line:match("the (.-) climate") or ""
        local terrain = line:match("the (.-) terrain")
                     or line:match("the (.-) environment")
                     or line:match("the (.-) forest")
                     or ""
        climate = climate:match("^%s*(.-)%s*$") or ""
        terrain = terrain:match("^%s*(.-)%s*$") or ""

        if room then
            if not room.climate and climate ~= "" then
                Map.set_climate(room_id, climate)
            elseif room.climate and room.climate ~= climate and verbose then
                log("sensed climate: " .. climate .. " does not match stored: " .. tostring(room.climate))
            end
            if not room.terrain and terrain ~= "" then
                Map.set_terrain(room_id, terrain)
            elseif room.terrain and room.terrain ~= terrain and verbose then
                log("sensed terrain: " .. terrain .. " does not match stored: " .. tostring(room.terrain))
            end
            room = Map.find_room(room_id)
        end
        if terrain == "" then log("room bug: room does not have terrain") end
        if climate == "" then log("room bug: room does not have climate") end
        log("climate: " .. tostring(room and room.climate) .. "; terrain: " .. tostring(room and room.terrain))
    else
        log("ranger_sense failed")
    end
end

-- Splashy sense: check if SPLASH verb works in this room → meta:splashy tag
local function splashy_sense()
    local room_id = Room.id
    if not room_id then return end
    fput("splash")
    local line = waitforre("You just splashed yourself|How do you plan to do that here")
    if not line then return end
    local room = Map.find_room(room_id)
    local has_tag = room and table_contains(room.tags or {}, "meta:splashy")
    if line:find("You just splashed yourself") then
        if not has_tag then
            Map.add_tag(room_id, "meta:splashy")
            if verbose then log("Added meta:splashy tag") end
        end
    elseif line:find("How do you plan to do that here") then
        if has_tag then
            Map.remove_tag(room_id, "meta:splashy")
            if verbose then log("Removed meta:splashy tag") end
        end
    end
end

-- Find herbs in room tags that are NOT in sense_tags (should be removed)
local function herbs_not_present(sense_tags)
    local filtered_herbs
    if last_time_of_day == "night" then
        filtered_herbs = table_diff(herb_list, day_only)
    elseif last_time_of_day == "day" then
        filtered_herbs = table_diff(herb_list, night_only)
    else
        filtered_herbs = table_diff(table_diff(herb_list, night_only), day_only)
    end
    local room = current_room()
    if not room or not room.tags then return {} end
    local current_herbs = table_intersect(room.tags, filtered_herbs)
    return table_diff(current_herbs, sense_tags)
end

-- Find stale forage-sensed meta tags (same time-of-day, different month)
local function old_meta()
    if not last_time_of_day_tag then time_of_day_tag() end
    local room = current_room()
    if not room or not room.tags then return {} end
    local old = {}
    local prefix = "meta:forage-sensed:" .. (last_time_of_day or "???")
    for _, tag in ipairs(room.tags) do
        if tag:find("^" .. prefix) and tag ~= last_time_of_day_tag then
            table.insert(old, tag)
        end
    end
    return old
end

-- Full sense operation for current room
function Tags.sense()
    if not ranger_sense_only then
        local sense_tags = forage_sense()
        if sense_tags == nil then return end -- ghost/dead

        Tags.add(sense_tags)

        -- Remove stale meta tags, herbs no longer present, and stale "no forageables"
        local tags_to_remove = {}
        for _, t in ipairs(old_meta()) do table.insert(tags_to_remove, t) end
        for _, t in ipairs(herbs_not_present(sense_tags)) do table.insert(tags_to_remove, t) end

        local room = current_room()
        if room and room.tags then
            local found_herbs = table_intersect(herb_list, sense_tags)
            if #found_herbs > 0 and table_contains(room.tags, "no forageables") then
                table.insert(tags_to_remove, "no forageables")
            end
        end
        if #tags_to_remove > 0 then
            Tags.remove(tags_to_remove)
        end

        Tags.uniq()
    end

    add_missing_uid()
    ranger_sense()
    if check_splashy then
        splashy_sense()
    end
end

-- Get location for the current room (resolving "current" keyword)
local function resolve_location(location)
    if not location or location == "" or location == "current" then
        local room = current_room()
        return room and room.location or ""
    end
    return location
end

-- Get crawl room lists (rooms to crawl, ignored rooms, skipped rooms)
local function crawl_rooms(location)
    local skip_list = {}
    local ignore_room_ids = {}

    location = resolve_location(location)

    -- Find actual location string: try exact match then fuzzy
    local all_ids = Map.list()
    local found_exact = false
    for _, id in ipairs(all_ids) do
        local r = Map.find_room(id)
        if r and r.location == location then
            found_exact = true
            break
        end
    end
    if not found_exact then
        for _, id in ipairs(all_ids) do
            local r = Map.find_room(id)
            if r and r.location and r.location:lower():find(location:lower(), 1, true) then
                log("Exact match for " .. tostring(location) .. " not found, using " .. tostring(r.location) .. " instead.")
                location = r.location
                break
            end
        end
    end

    -- Collect all rooms in this location, apply ranger/outside filters
    local room_ids = {}
    for _, id in ipairs(all_ids) do
        local r = Map.find_room(id)
        if r and r.location == location then
            local passes_outside = not outside_only
                or (r.paths and r.paths[1] and r.paths[1]:find("Obvious paths"))
            local passes_ranger = not ranger_rooms_only
                or (not r.climate or not r.terrain)
            if passes_outside and passes_ranger then
                table.insert(room_ids, id)
            end
        end
    end

    -- Build skip list: rooms already sensed this month/time-of-day
    if #room_ids > 0 and skip_sensed then
        local skip_tag = time_of_day_tag()
        for _, id in ipairs(room_ids) do
            local r = Map.find_room(id)
            if r then
                local skip = table_contains(r.tags or {}, skip_tag)
                -- For ranger-sense-only mode: also skip rooms with both climate+terrain set
                if not skip and ranger_sense_only and r.climate and r.terrain then
                    skip = true
                end
                if skip then
                    table.insert(skip_list, id)
                end
            end
        end
        room_ids = table_diff(room_ids, skip_list)
    end

    -- Filter out ignored rooms (tagged with ignore_tags or named " Table]")
    for _, id in ipairs(room_ids) do
        local r = Map.find_room(id)
        if r then
            local dominated = false
            for _, tag in ipairs(r.tags or {}) do
                if table_contains(ignore_tags, tag) then
                    dominated = true
                    break
                end
            end
            if not dominated and r.title and r.title:find(" Table%]$") then
                dominated = true
            end
            if dominated then
                table.insert(ignore_room_ids, id)
            end
        end
    end

    room_ids = table_diff(room_ids, ignore_room_ids)
    return room_ids, ignore_room_ids, skip_list, location
end

-- List rooms for a location (--list command)
function Tags.list_rooms(location)
    location = resolve_location(location)
    local room_ids, ignore_room_ids, skip_list, actual_location = crawl_rooms(location)

    if #room_ids + #ignore_room_ids + #skip_list == 0 then
        log("No rooms found for location: " .. tostring(actual_location))
        return
    end

    log("Skipping " .. #skip_list .. " room(s) because they are already tagged as being sensed for this month and this time of day.")
    for _, id in ipairs(skip_list) do
        local r = Map.find_room(id)
        if r then
            local uid_str = ""
            if type(r.uid) == "string" then uid_str = "u" .. r.uid
            elseif type(r.uid) == "table" and r.uid[1] then uid_str = "u" .. tostring(r.uid[1]) end
            respond(string.format("  %-5d  %-9s | %s", id, uid_str, r.title or "(unknown)"))
        end
    end

    log("Ignoring " .. #ignore_room_ids .. " room(s) because they are tagged with at least one of the following: " .. table.concat(ignore_tags, ", "))
    for _, id in ipairs(ignore_room_ids) do
        local r = Map.find_room(id)
        if r then
            local uid_str = ""
            if type(r.uid) == "string" then uid_str = "u" .. r.uid
            elseif type(r.uid) == "table" and r.uid[1] then uid_str = "u" .. tostring(r.uid[1]) end
            local matched = table_intersect(r.tags or {}, ignore_tags)
            local note = #matched > 0 and table.concat(matched, ", ") or "Table"
            respond(string.format("  %-5d  %-9s | %-44s | %s", id, uid_str, r.title or "(unknown)", note))
        end
    end

    log("Remaining " .. #room_ids .. " rooms in " .. tostring(actual_location) .. ":")
    for _, id in ipairs(room_ids) do
        local r = Map.find_room(id)
        if r then
            local uid_str = ""
            if type(r.uid) == "string" then uid_str = "u" .. r.uid
            elseif type(r.uid) == "table" and r.uid[1] then uid_str = "u" .. tostring(r.uid[1]) end
            respond(string.format("  %-5d  %-9s | %s", id, uid_str, r.title or "(unknown)"))
        end
    end
end

-- Crawl an area: navigate to each room and run sense
function Tags.crawl(location)
    if Skills.survival < 25 then
        echo("You do not have enough survival for this.")
        return
    end

    location = resolve_location(location)

    -- Handle 'confirm' and 'all' keywords embedded in location string
    if location:find("confirm") then
        disable_confirm = true
        location = location:gsub("%s*confirm%s*", " "):match("^%s*(.-)%s*$")
    end
    if location:match("%s*all%s*$") then
        skip_sensed = false
        location = location:gsub("%s*all%s*$", ""):match("^%s*(.-)%s*$")
        log("Will include rooms already marked as forage sensed for this month and time of day.")
    end

    local room_ids, ignore_room_ids, skip_list, actual_location = crawl_rooms(location)

    if #room_ids == 0 and #skip_list == 0 then
        log("No rooms found for " .. tostring(actual_location) .. ".")
        return
    elseif #room_ids == 0 then
        log("No rooms left to crawl for " .. tostring(actual_location) .. ".")
        return
    end

    if #skip_list > 0 then
        log("Skipping " .. #skip_list .. " room(s) because they are already tagged as being sensed for this month and this time of day.")
    end
    if #ignore_room_ids > 0 then
        log("Ignoring " .. #ignore_room_ids .. " room(s) tagged with an ignore tag.")
    end

    log("\nGoing to crawl " .. #room_ids .. " rooms in " .. tostring(actual_location) .. " starting in 2 seconds.")
    pause(2)

    while #room_ids > 0 do
        local from_id = Room.id

        -- Try to escape un-mapped position before navigating
        if not from_id then
            fput("out")
            pause(2)
            from_id = Room.id
            if not from_id then
                log("Cannot determine current location — aborting crawl.")
                break
            end
        end

        -- Find nearest remaining room using Dijkstra
        local nearest = Map.find_nearest_room(from_id, room_ids)
        if not nearest then
            log("None of the remaining rooms seem to have a path from here to there.")
            for _, id in ipairs(room_ids) do
                local r = Map.find_room(id)
                if r then
                    respond(string.format("  %-5d  %s", id, r.title or "(unknown)"))
                end
            end
            break
        end

        local closest = nearest.id

        -- Remove closest from remaining list
        for i = #room_ids, 1, -1 do
            if room_ids[i] == closest then
                table.remove(room_ids, i)
                break
            end
        end

        -- Path distance check: pause when more than 100 steps away
        if not disable_confirm then
            local path = Map.find_path(from_id, closest)
            if path and #path > 100 then
                local target_room = Map.find_room(closest)
                local title = target_room and target_room.title or tostring(closest)
                log("There are approximately " .. #path .. " rooms between you and " .. tostring(closest) .. ": " .. title)
                log("\nTo continue, unpause the script.  To abort, kill the script.")
                pause_script()
            end
        end

        -- Navigate to room (Map.go2 is blocking: waits for each step's prompt)
        local ok = Map.go2(closest)
        if not ok then
            log("unable to navigate to " .. tostring(closest))
        else
            local now = Room.id
            if now == closest then
                Tags.sense()
            else
                log("unable to reach " .. tostring(closest) .. " (ended up at " .. tostring(now) .. ")")
            end
        end
    end
end

-- BFS over location graph via wayto adjacency — returns neighboring location strings
local function location_neighbors(location_from)
    local neighbors = {}
    local seen = {}
    local all_ids = Map.list()
    for _, id in ipairs(all_ids) do
        local r = Map.find_room(id)
        if r and r.location == location_from and r.wayto then
            for dest_id_str, _ in pairs(r.wayto) do
                local dest_id = tonumber(dest_id_str)
                if dest_id then
                    local dest = Map.find_room(dest_id)
                    if dest and dest.location and dest.location ~= location_from and not seen[dest.location] then
                        table.insert(neighbors, dest.location)
                        seen[dest.location] = true
                    end
                end
            end
        end
    end
    return neighbors
end

-- Planewalker: BFS over the location graph, crawling each location
function Tags.planewalker()
    verbose = false
    local start_room = current_room()
    if not start_room or not start_room.location then
        echo("Cannot determine current location.")
        return
    end
    local queue   = { start_room.location }
    local visited = {}
    while #queue > 0 do
        local location = table.remove(queue, 1)
        visited[location] = true
        Tags.crawl(location)
        for _, neighbor in ipairs(location_neighbors(location)) do
            if not visited[neighbor] and neighbor ~= "the grasslands" then
                -- Avoid duplicates in queue
                local in_queue = false
                for _, q in ipairs(queue) do
                    if q == neighbor then in_queue = true; break end
                end
                if not in_queue then
                    table.insert(queue, neighbor)
                end
            end
        end
    end
end

-- Diff: compare live forage sense against stored tags, show gaps
function Tags.diff()
    local sense_tags = forage_sense()
    if not sense_tags then return end

    -- Strip meta tags from sense results
    local sense_herbs = {}
    for _, t in ipairs(sense_tags) do
        if not t:match("^meta") then table.insert(sense_herbs, t) end
    end

    local room = current_room()
    local room_tags = room and room.tags or {}

    -- Strip meta/map/urchin tags and known interesting/other tags from room tags
    local filtered_tags = {}
    for _, t in ipairs(room_tags) do
        if not t:match("^meta") and not t:match("^map") and not t:match("^urchin")
           and not table_contains(gs_interesting_tags, t) and not table_contains(gs_other_tags, t)
           and not table_contains(ignore_tags, t) or t == "no forageables" then
            table.insert(filtered_tags, t)
        end
    end

    -- Build "some X" variants for comparison (sense sometimes returns "some X")
    local spoof_some = {}
    for _, s in ipairs(sense_herbs) do
        table.insert(spoof_some, "some " .. s)
    end

    local same = table_intersect(filtered_tags, sense_herbs)
    local not_in_sense = table_diff(table_diff(filtered_tags, sense_herbs), spoof_some)
    local not_in_tags  = table_diff(sense_herbs, filtered_tags)

    table.sort(sense_herbs)
    table.sort(not_in_sense)
    table.sort(not_in_tags)

    local ignored = table_diff(room_tags, filtered_tags)
    respond("\nIgnoring these tags: " .. table.concat(ignored, ", "))
    respond("\nForage sense(" .. #sense_herbs .. "): " .. table.concat(sense_herbs, ", "))
    respond("\nIn tags and forage sense (" .. #same .. "): " .. table.concat(same, ", "))
    respond("\nNot in forage sense (" .. #not_in_sense .. "): " .. table.concat(not_in_sense, ", "))
    respond("\nNot in tags (" .. #not_in_tags .. "): " .. table.concat(not_in_tags, ", "))
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
    ;tags --crawl <location>             crawl an area using survival sense, pauses before moving more than 100 rooms
    ;tags --crawl <location> confirm     crawl an area and don't pause when moving more than 100 rooms away
    ;tags --crawl <location> all         crawl an area and don't skip recently sensed rooms
    ;tags --list <location>              list rooms for a location, whether to skip or crawl

  crawl options (can be mixed and matched)
    ;tags --crawl ranger                  # only does rooms that need climate/terrain
    ;tags --crawl climate                 # only does ranger sense for climate/terrain
    ;tags --crawl outside                 # only does outside rooms
    ;tags --crawl splashy                 # also checks if rooms allow SPLASH verb
    ;tags --crawl noskip                  # doesn't skip rooms already sensed

  single tag operations:
    ;tags + [tag]                        add a single tag
    ;tags - [tag]                        remove a single tag

  for --add/--rm operations with spaces in the name, use quotes:
    ;tags --add "small tomato" "onion skin"
    ;tags --rm "small tomato" "onion skin"
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
    check_splashy     = table_contains(cmd_tags, "splashy")
    if table_contains(cmd_tags, "noskip") then skip_sensed = false end
    Tags.sense()
elseif cmd_type == CRAWL then
    local anchor = Room.id
    -- If current room has crawl_if_current_tags, remove them from ignore list
    local cur = current_room()
    if cur and cur.tags then
        for _, tag in ipairs(cur.tags) do
            if table_contains(crawl_if_current_tags, tag) then
                remove_ignore_tag(tag)
            end
        end
    end
    outside_only      = table_contains(cmd_tags, "outside")
    ranger_sense_only = table_contains(cmd_tags, "climate")
    ranger_rooms_only = table_contains(cmd_tags, "ranger")
    check_splashy     = table_contains(cmd_tags, "splashy")
    if table_contains(cmd_tags, "noskip") then skip_sensed = false end
    if table_contains(cmd_tags, "confirm") then disable_confirm = true end
    -- Remove option keywords to get location
    local option_words = {outside=true, climate=true, ranger=true, splashy=true, noskip=true, confirm=true, all=true}
    local location_parts = {}
    for _, tag in ipairs(cmd_tags) do
        if not option_words[tag] then
            table.insert(location_parts, tag)
        end
    end
    Tags.crawl(table.concat(location_parts, " "))
    -- Return to start room after crawl
    local now = Room.id
    if anchor and now and now ~= anchor then
        Map.go2(anchor)
    end
elseif cmd_type == PLANEWALKER then
    outside_only      = table_contains(cmd_tags, "outside")
    ranger_sense_only = table_contains(cmd_tags, "climate")
    ranger_rooms_only = table_contains(cmd_tags, "ranger")
    check_splashy     = table_contains(cmd_tags, "splashy")
    if table_contains(cmd_tags, "noskip") then skip_sensed = false end
    Tags.planewalker()
elseif cmd_type == LIST_ROOMS then
    Tags.list_rooms(table.concat(cmd_tags, " "))
elseif cmd_type == TIME_OF_DAY then
    log(time_of_day())
elseif cmd_type == DIFF then
    Tags.diff()
else
    show_help()
end
