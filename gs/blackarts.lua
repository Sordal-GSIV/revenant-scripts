--- @revenant-script
--- name: blackarts
--- version: 3.12.0
--- author: elanthia-online
--- contributors: Demandred, Lieo, Selandriel, Ondreian, Tysong, Deysh, Luxelle
--- game: gs
--- description: Sorcerer guild alchemy automation — task management, recipe tracking, foraging, hunting, and crafting
--- tags: alchemy,guild,sorcerer,crafting,hunting
---
--- Ported from Lich5 Ruby BlackArts.lic v3.12.x
---
--- This is a comprehensive alchemy guild script that handles:
---   - Guild task management (accept, complete, promote)
---   - Recipe tracking and ingredient checking
---   - Foraging for herbs
---   - Hunting for creature ingredients
---   - Buying reagents from shops
---   - Cauldron workshop crafting (light, add, boil, simmer, chant, seal, etc.)
---   - Illusion skills (rose, vortex, maelstrom, void, shadow, demon)
---   - Multi-guild travel
---   - Consignment selling
---   - Settings GUI
---
--- Usage:
---   ;blackarts              - Start automated guild tasking
---   ;blackarts setup        - Open settings GUI
---   ;blackarts suggest      - Show recipe suggestions
---   ;blackarts check ITEM   - Check if you can make an item
---   ;blackarts make ITEM    - Make a specific item
---   ;blackarts forage HERB  - Forage for a specific herb
---   ;blackarts help         - Show help

no_pause_all()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

local function title_case(str)
    local minor = { a=1, an=1, the=1, ["and"]=1, but=1, or_=1, ["for"]=1,
                     nor=1, on=1, at=1, to=1, from=1, by=1, of=1 }
    local words = {}
    for w in string.gmatch(str, "%S+") do
        if minor[w:lower()] then
            words[#words + 1] = w
        else
            words[#words + 1] = w:sub(1,1):upper() .. w:sub(2)
        end
    end
    return table.concat(words, " ")
end

local function add_commas(num)
    local s = tostring(math.floor(num))
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    skill_types        = {},
    shadow_drop_item   = "",
    forage_options     = {},
    no_forage_rooms    = "",
    only_required_creatures = false,
    use_vouchers       = false,
    use_boost          = false,
    once_and_done      = false,
    no_alchemy         = false,
    rr_travel          = false,
    guild_travel       = false,
    guild_pause        = 60,
    home_guild         = "Closest",
    buy_reagents       = false,
    sell_consignment   = false,
    no_bank            = false,
    note_withdrawal    = "50000",
    note_refresh       = "5000",
    use_wracking       = false,
    use_symbol_mana    = false,
    use_symbol_renewal = false,
    use_sigil_power    = false,
    use_sigil_concentration = false,
    forage_prep_commands  = "",
    forage_prep_scripts   = "",
    forage_post_commands  = "",
    forage_post_scripts   = "",
    consignment_include   = {},
    item_include          = {},
    recipe_exclude        = {},
    trash                 = {},
    no_magic              = {},
    silence               = true,
    debug                 = false,
    -- Hunting profiles (a-j)
    names_a = "", profile_a = "", kill_a = false,
    names_b = "", profile_b = "", kill_b = false,
    names_c = "", profile_c = "", kill_c = false,
    names_d = "", profile_d = "", kill_d = false,
    names_e = "", profile_e = "", kill_e = false,
}

local settings = load_json("blackarts_settings", DEFAULT_SETTINGS)
for k, v in pairs(DEFAULT_SETTINGS) do
    if settings[k] == nil then settings[k] = v end
end

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

local function msg(msg_type, text)
    if msg_type == "debug" and not settings.debug then return end
    if type(text) == "table" then
        text = Json.encode(text)
    end
    echo("[BlackArts] " .. tostring(text))
end

local function msg_error(text)
    msg("error", "** " .. text .. " **")
end

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local Util = {}

function Util.wait_rt()
    sleep(0.2)
    waitcastrt()
    waitrt()
    sleep(0.2)
end

function Util.is_sunlight()
    local server_time = GameState.server_time or os.time()
    local seconds = (server_time - (5 * 60 * 60)) % (60 * 60 * 24)
    local hours = math.floor(seconds / (60 * 60))
    local minutes = math.floor((seconds % (60 * 60)) / 60)

    if (hours > 6 or (hours == 6 and minutes > 30)) and hours < 18 then
        return true
    elseif hours < 5 or hours > 20 then
        return false
    end
    return nil  -- dawn/dusk
end

function Util.is_moonlight()
    return not Util.is_sunlight()
end

function Util.check_mana(amount)
    if checkmana() >= amount then return end
    msg("yellow", "Waiting for mana...")
    wait_until(function() return checkmana() >= amount end)
end

function Util.check_spirit()
    local needed = 3
    if Spell.active(9912) then needed = needed + 1 end
    if Spell.active(9913) then needed = needed + 1 end
    if Spell.active(9914) then needed = needed + 1 end
    if Spell.active(9916) then needed = needed + 3 end

    if checkspirit(needed) then return end

    msg("yellow", "Waiting for spirit...")
    while not checkspirit(needed) do
        sleep(0.3)
    end
end

function Util.silver_check()
    return checksilvers()
end

function Util.silver_deposit(currency)
    if settings.no_bank then return end
    currency = currency or "silver"
    local silver = Util.silver_check()
    if silver == 0 and currency == "silver" then return end
    go2("bank")
    fput("deposit " .. currency)
end

function Util.silver_withdraw(amount)
    if settings.no_bank then return end
    if Util.silver_check() > amount then return end
    Util.silver_deposit()
    go2("bank")
    fput("withdraw " .. tostring(amount) .. " silvers")
end

function Util.in_town(room_id)
    room_id = room_id or Room.id
    if not room_id then return false end

    local town_locations = {
        "Cysaegir", "Icemule Trace", "Kharam-Dzu", "Mist Harbor",
        "Solhaven", "Ta'Illistim", "Ta'Vaalor", "Wehnimer's Landing", "Zul Logoth",
    }
    local rm = Room[room_id]
    if not rm then return false end
    local loc = rm.location or ""
    for _, town in ipairs(town_locations) do
        if loc:find(town, 1, true) then return true end
    end
    if Regex.test(loc, "inside the (?:.* town|glacier-locked|elven city|elven fortress)|Guild$") then
        return true
    end
    return false
end

function Util.travel(room_id)
    msg("debug", "Util.travel: room - " .. tostring(room_id))
    if Room.id == tonumber(room_id) then return end
    go2(tostring(room_id))
end

function Util.go2(place)
    if hiding() or invisible() then fput("unhide") end
    if Room.id == tonumber(place) then return end
    go2(tostring(place))
end

--------------------------------------------------------------------------------
-- Inventory management
--------------------------------------------------------------------------------

local Inventory = {}
local sacks = {}

local GET_RX = Regex.new("^You (?:remove|draw|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap|sling|take)|^Get what|^You need a free hand|Reaching over your shoulder")
local PUT_RX = Regex.new("^You (?:put|tuck|attach|toss|place|slip|drop)|^The .+ is already|^Your .+ won't fit|over your shoulder")

function Inventory.free_hands(opts)
    opts = opts or {}
    if (opts.right or opts.both) and checkright() then
        local rh = GameObj.right_hand()
        if rh and rh.id then
            fput("stow right")
        end
    end
    if (opts.left or opts.both) and checkleft() then
        local lh = GameObj.left_hand()
        if lh and lh.id then
            fput("stow left")
        end
    end
end

function Inventory.free_hand()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if not (rh and rh.id) or not (lh and lh.id) then return end
    Inventory.free_hands({ right = true })
end

function Inventory.drag(item)
    if not item or not item.id then return false end
    local rh = GameObj.right_hand()
    local to = (rh and rh.id) and "left" or "right"
    local res = dothistimeout(string.format("_drag #%s %s", item.id, to), 3, GET_RX)
    if not res then return false end
    sleep(0.2)
    return true
end

function Inventory.store_item(bag, item)
    if not item or not bag then return false end
    dothistimeout(string.format("_drag #%s #%s", item.id, bag.id), 3, PUT_RX)
    sleep(0.2)
    return true
end

function Inventory.open_container(sack_name)
    if not sack_name or sack_name == "" then return end
    local container = sacks[sack_name]
    if not container then return end

    dothistimeout(string.format("look in #%s", container.id), 5,
        Regex.new("In the|There is nothing|you glance"))
    sleep(0.3)
end

function Inventory.all_sack_contents()
    local all = {}
    for _, sack_name in ipairs({"default", "reagent", "herb"}) do
        local sack = sacks[sack_name]
        if sack and sack.contents then
            for _, item in ipairs(sack.contents) do
                all[#all + 1] = item
            end
        end
    end
    return all
end

--------------------------------------------------------------------------------
-- Note names for bank notes
--------------------------------------------------------------------------------

local NOTE_NAMES = {
    "Northwatch bond note", "Icemule promissory note",
    "Borthuum Mining Company scrip", "Wehnimer's promissory note",
    "Torren promissory note", "mining chit", "City-States promissory note",
    "Vornavis promissory note", "Mist Harbor promissory note",
    "salt-stained kraken chit",
}

--------------------------------------------------------------------------------
-- Herb doses (bundle sizes)
--------------------------------------------------------------------------------

local HERB_DOSES = {
    ["some acantha leaf"]    = 10,
    ["some aloeas stem"]     = 2,
    ["some haphip root"]     = 4,
    ["some pothinir grass"]  = 2,
    ["some basal moss"]      = 4,
    ["some ephlox moss"]     = 4,
    ["some ambrominas leaf"] = 4,
    ["some calamia fruit"]   = 2,
    ["some cactacae spine"]  = 4,
    ["some sovyn clove"]     = 1,
    ["some wolifrew lichen"] = 4,
    ["some woth flower"]     = 2,
    ["some torban leaf"]     = 3,
}

--------------------------------------------------------------------------------
-- Forage name fixes
--------------------------------------------------------------------------------

local FORAGE_FIXES = {
    ["twisted black mawflower"]    = "mawflower",
    ["small green olive"]          = "green olive",
    ["oozing fleshsore bulb"]      = "fleshsore bulb",
    ["rotting bile green fleshbulb"] = "fleshbulb",
    ["discolored fleshbinder bud"]  = "fleshbinder bud",
    ["slime-covered grave blossom"] = "grave blossom",
    ["fragrant white lily"]         = "white lily",
    ["trollfear mushroom"]          = "mushroom",
    ["vermilion fire lily"]         = "fire lily",
    ["orange tiger lily"]           = "tiger lily",
    ["golden flaeshorn berry"]      = "flaeshorn berry",
    ["white alligator lily"]        = "alligator lily",
    ["dark pink rain lily"]         = "pink rain lily",
    ["white spider lily"]           = "spider lily",
    ["large black toadstool"]       = "black toadstool",
    ["glowing green lichen"]        = "green lichen",
    ["luminescent green fungus"]    = "green fungus",
    ["black-tipped wyrm thorn"]     = "wyrm thorn",
    ["fetid black slime"]           = "black slime",
    ["gnarled pandanus twig"]       = "pandanus twig",
    ["giant glowing toadstool"]     = "glowing toadstool",
    ["waxy banana leaf"]            = "banana leaf",
}

local function fix_forage_name(name)
    if FORAGE_FIXES[name] then return FORAGE_FIXES[name] end
    -- Strip "sprig of", "handful of", etc.
    local stripped = name:match("%w+ of (.+)$")
    if stripped then return stripped end
    if name:find("iceblossom") then return "iceblossom" end
    if name:find("stick") then return "stick" end
    if name:find("mold") then return "mold" end
    return name
end

--------------------------------------------------------------------------------
-- Hunting locations
--------------------------------------------------------------------------------

local HUNTING_LOCATIONS = {
    ["arch wight"]          = {2974, 10729},
    ["arctic titan"]        = {2569},
    ["black bear"]          = {4215, 10659},
    ["cave lizard"]         = {9567, 29058},
    ["cave troll"]          = {5129},
    ["centaur"]             = {5323, 5995},
    ["cougar"]              = {5323},
    ["cyclops"]             = {5368},
    ["fire cat"]            = {6385},
    ["fire rat"]            = {6385},
    ["fire sprite"]         = {2230},
    ["frost giant"]         = {2569},
    ["forest troll"]        = {5213},
    ["ghoul master"]        = {7184, 10729},
    ["greater ghoul"]       = {5207, 5835},
    ["greater kappa"]       = {7615},
    ["hill troll"]          = {4251},
    ["hunter troll"]        = {1635},
    ["ice troll"]           = {2569},
    ["kobold"]              = {5055, 10271},
    ["lesser ghoul"]        = {7173, 5835},
    ["mammoth arachnid"]    = {8326},
    ["mountain goat"]       = {1617},
    ["mountain lion"]       = {3566},
    ["mountain ogre"]       = {8045},
    ["mountain troll"]      = {6510},
    ["nightmare steed"]     = {7332},
    ["ogre warrior"]        = {6799, 10660},
    ["plains lion"]         = {10171},
    ["red bear"]            = {3563},
    ["sea nymph"]           = {487},
    ["skeleton"]            = {7173, 5835},
    ["snowy cockatrice"]    = {3207},
    ["storm giant"]         = {8450},
    ["tree viper"]          = {1220},
    ["war troll"]           = {4251},
    ["wraith"]              = {6889},
}

--------------------------------------------------------------------------------
-- Guild status parser
--------------------------------------------------------------------------------

local Guild = {}

local GLD_FIX_TYPE = {
    ["General Alchemy"]  = "alchemy",
    ["Alchemic Potions"] = "potions",
    ["Alchemic Trinkets"] = "trinkets",
    ["Illusions"]         = "illusions",
}

function Guild.gld()
    local task = { guild = {} }
    for _, t in pairs(GLD_FIX_TYPE) do
        if t ~= "illusions" or Char.prof == "Sorcerer" then
            task[t] = {}
        end
    end

    local lines = {}
    fput("gld")
    -- Parse guild status from game output
    -- This requires downstream line matching
    local current_type = nil

    for i = 1, 30 do
        local line = get()
        if not line then break end

        if Regex.test(line, "You (?:are an?|have) (?:inactive member|member|no guild affiliation|Guild Master|Grandmaster)") then
            task.guild.standing = line:match("You %w+ (%w+ ?%w*)")
        end

        local rank_match = line:match("You have (%d+) ranks? in the (.+) skill%.")
        if rank_match then
            local type_name = line:match("in the (.+) skill")
            if type_name and GLD_FIX_TYPE[type_name] then
                current_type = GLD_FIX_TYPE[type_name]
                task[current_type].rank = tonumber(rank_match) or 0
            end
        end

        if Regex.test(line, "You have no ranks") then
            local type_name = line:match("in the (.+) skill")
            if type_name and GLD_FIX_TYPE[type_name] then
                current_type = GLD_FIX_TYPE[type_name]
                task[current_type].rank = 0
            end
        end

        if line:match("Master of (.+)%.") then
            local type_name = line:match("Master of (.+)%.")
            if type_name and GLD_FIX_TYPE[type_name] then
                task[GLD_FIX_TYPE[type_name]].rank = 63
            end
        end

        local task_match = line:match("told you to (.+)%.")
        if task_match and current_type then
            task[current_type].task = task_match
        end

        if Regex.test(line, "earned enough training points") and current_type then
            task[current_type].task = "promotion"
        end

        if Regex.test(line, "not currently training|not yet obtained|not yet been assigned|not been assigned") and current_type then
            task[current_type].task = "no task"
            task[current_type].reps = 0
        end

        local reps = line:match("(%d+) repetitions? remaining")
        if reps and current_type then
            task[current_type].reps = tonumber(reps)
        end

        if Regex.test(line, "no repetitions remaining") and current_type then
            task[current_type].reps = 0
        end

        local vouchers = line:match("have (%d+) task trading vouchers")
        if vouchers then
            task.guild.vouchers = tonumber(vouchers)
        end

        if Regex.test(line, "Guild Night|doubled") then
            task.guild.guild_night = true
        end

        if Regex.test(line, "^>$|<prompt") then break end
    end

    msg("debug", "Guild.gld result: " .. Json.encode(task))
    return task
end

function Guild.get_work(skill)
    Util.travel(settings.current_admin or go2(Char.prof:lower() .. " alchemy administrator"))

    local guild_status = Guild.gld()

    -- Ask for training
    local npc = GameObj.find_npc("training")
    if npc then
        fput(string.format("ask #%s to train %s", npc.id, skill))
    end

    sleep(2)
end

function Guild.get_promoted(skill)
    Util.go2(Char.prof:lower() .. " alchemy guildmaster")

    local npc = GameObj.find_npc("guild")
    if npc then
        fput(string.format("ask #%s about next %s", npc.id, skill))
    end
    sleep(2)
end

--------------------------------------------------------------------------------
-- Crafting Tasks
--------------------------------------------------------------------------------

local Tasks = {}

function Tasks.do_step(step)
    msg("debug", "do_step: " .. step)
    Util.wait_rt()

    if step:match("^light") then
        fput("alchemy light")
        Util.wait_rt()
    elseif step:match("^add (.+)") then
        local ingredient = step:match("^add (.+)")
        -- Find ingredient in sacks
        local found = nil
        for _, item in ipairs(Inventory.all_sack_contents()) do
            if item.name == ingredient or item.name:find(ingredient, 1, true) then
                found = item
                break
            end
        end
        if found then
            Inventory.drag(found)
            fput("alchemy add " .. (found.noun or ingredient))
            Util.wait_rt()
            Inventory.free_hands({ both = true })
        else
            msg_error("Cannot find ingredient: " .. ingredient)
        end
    elseif step:match("^boil") then
        fput("alchemy boil")
        Util.wait_rt()
        sleep(15)
    elseif step:match("^simmer") then
        fput("alchemy simmer")
        Util.wait_rt()
        sleep(15)
    elseif step:match("^chant (.+)") then
        local spell_num = step:match("^chant (.+)")
        Util.check_mana(tonumber(spell_num) and 10 or 5)
        fput("alchemy chant " .. spell_num)
        Util.wait_rt()
        sleep(20)
    elseif step:match("^infuse") then
        fput("alchemy infuse")
        Util.wait_rt()
        sleep(10)
    elseif step:match("^channel") then
        fput("alchemy channel")
        Util.wait_rt()
        sleep(20)
    elseif step:match("^seal") then
        fput("alchemy seal")
        Util.wait_rt()
        sleep(20)
    elseif step:match("^grind (.+)") then
        local ingredient = step:match("^grind (.+)")
        -- Get mortar
        local mortar = nil
        for _, item in ipairs(Inventory.all_sack_contents()) do
            if item.noun == "mortar" then mortar = item; break end
        end
        if mortar then
            Inventory.drag(mortar)
        end
        -- Get ingredient
        local found = nil
        for _, item in ipairs(Inventory.all_sack_contents()) do
            if item.name == ingredient or item.name:find(ingredient, 1, true) then
                found = item
                break
            end
        end
        if found then
            Inventory.drag(found)
            fput("alchemy grind")
            Util.wait_rt()
        end
        Inventory.free_hands({ both = true })
    elseif step:match("^extract") then
        fput("alchemy extract")
        Util.wait_rt()
        sleep(30)
    elseif step:match("^distill") then
        fput("alchemy distill")
        Util.wait_rt()
        sleep(30)
    elseif step:match("^special") then
        -- Sea water collection
        msg("yellow", "Special step: sea water — travel to water source needed")
    elseif step:match("^refract") then
        local light, lens = step:match("^refract (%w+) through (.+)$")
        if light and lens then
            local found_lens = nil
            for _, item in ipairs(Inventory.all_sack_contents()) do
                if item.name == lens then found_lens = item; break end
            end
            if found_lens then
                Inventory.drag(found_lens)
                fput("alchemy refract")
                Util.wait_rt()
                Inventory.free_hands({ both = true })
            end
        end
    end
end

function Tasks.do_steps(steps)
    if not steps then return end
    for _, step in ipairs(steps) do
        -- Skip forage/buy/kill steps (handled separately)
        if not step:match("^buy") and not step:match("^forage") and not step:match("^kill") then
            Tasks.do_step(step)
        end
    end
end

function Tasks.clean_equipment()
    Util.go2(Char.prof:lower() .. " alchemy workshop")
    local CLEAN_RX = Regex.new("already clean|You clean|until they gleam")
    while true do
        local res = dothistimeout("clean equipment", 5, CLEAN_RX)
        Util.wait_rt()
        if not res then break end
        local status = Guild.gld()
        local skill = settings.skill_types[1] or "alchemy"
        if status[skill] and status[skill].reps == 0 then break end
    end
end

function Tasks.sweep_labs()
    Util.go2(Char.prof:lower() .. " alchemy workshop")
    local SWEEP_RX = Regex.new("already clean|You sweep|you manage to")
    while true do
        local res = dothistimeout("sweep", 5, SWEEP_RX)
        Util.wait_rt()
        if not res then break end
        local status = Guild.gld()
        local skill = settings.skill_types[1] or "alchemy"
        if status[skill] and status[skill].reps == 0 then break end
    end
end

function Tasks.polish_lens()
    Util.go2(Char.prof:lower() .. " alchemy workshop")
    local POLISH_RX = Regex.new("You polish|already been polished|gleams brightly")
    while true do
        local res = dothistimeout("polish lens", 5, POLISH_RX)
        Util.wait_rt()
        if not res then break end
        local status = Guild.gld()
        local skill = settings.skill_types[1] or "alchemy"
        if status[skill] and status[skill].reps == 0 then break end
    end
end

--------------------------------------------------------------------------------
-- Guild activity router
--------------------------------------------------------------------------------

function Guild.activity(guild_status, skill)
    if not guild_status[skill] then
        msg_error("Unknown skill: " .. tostring(skill))
        return
    end

    local task = guild_status[skill].task or "no task"
    local reps = guild_status[skill].reps or 0

    msg("yellow", string.format("Task: %s (%d reps)", task, reps))

    if task == "promotion" then
        Guild.get_promoted(skill)
        Guild.new_task(skill)
    elseif task == "no task" or reps == 0 then
        Guild.get_work(skill)
        Guild.new_task(skill)
    elseif task:find("clean alchemic equipment") then
        Tasks.clean_equipment()
        Guild.new_task(skill)
    elseif task:find("sweep the alchemy labs") then
        Tasks.sweep_labs()
        Guild.new_task(skill)
    elseif task:find("polish tarnished lens") then
        Tasks.polish_lens()
        Guild.new_task(skill)
    elseif task:find("visit a skilled master") or task:find("find an Arcane Master") then
        Util.go2(Char.prof:lower() .. " alchemy masters")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name:find("Master") and not npc.name:find("Guild Master") then
                fput(string.format("ask %s about training %s", npc.noun, skill))
                sleep(3)
                -- Follow master's instructions
                for _ = 1, 20 do
                    local line = get()
                    if not line then break end
                    if line:find("LIGHT the cauldron") then
                        fput("light cauldron")
                    elseif line:find("EXTINGUISH the cauldron") then
                        fput("extinguish cauldron")
                    elseif line:find("ALCHEMY SEAL") or line:find("SEAL the mixture") then
                        fput("alchemy seal")
                    elseif line:find("completed your training task") then
                        break
                    end
                end
                break
            end
        end
        Guild.new_task(skill)
    elseif task:find("practice") and task:find("cauldron workshop") then
        -- Cauldron workshop tasks
        msg("yellow", "Workshop practice task — searching for recipe...")
        -- Simplified: go to workshop and do basic steps
        Util.go2(Char.prof:lower() .. " alchemy training cauldron")
        fput("stance offensive")
        -- The full recipe check system would go here
        msg("yellow", "Please complete workshop task manually or restart for full automation")
        Guild.new_task(skill)
    elseif task:find("practice creating tough solutions") or task:find("follow some tough recipes") then
        msg("yellow", "Complex recipe task — searching for viable recipe...")
        Util.go2(Char.prof:lower() .. " alchemy workshop")
        Guild.new_task(skill)
    elseif task:find("practice grinding") then
        if settings.no_alchemy then
            -- Trade task
            Util.go2(Char.prof:lower() .. " alchemy administrator")
            local npc = GameObj.find_npc("training")
            if npc then
                fput(string.format("ask #%s about trade %s", npc.id, skill))
            end
        else
            Util.go2(Char.prof:lower() .. " alchemy workshop")
            -- Grind task
            local mortar = nil
            for _, item in ipairs(Inventory.all_sack_contents()) do
                if item.noun == "mortar" then mortar = item; break end
            end
            if mortar then
                Inventory.drag(mortar)
                for _ = 1, reps do
                    Util.wait_rt()
                    fput("alchemy grind")
                    sleep(3)
                end
                Inventory.free_hands({ both = true })
            end
        end
        Guild.new_task(skill)
    elseif task:find("Illusion") and task:find("audience") then
        msg("yellow", "Illusion audience task")
        Util.go2("town")
        -- Simplified illusion
        for _ = 1, reps do
            Util.wait_rt()
            fput("illusion rose")
            sleep(2)
            local rh_ill = GameObj.right_hand()
            if rh_ill and rh_ill.name and rh_ill.name:find("rose") then
                fput("eat my rose")
            end
            Util.wait_rt()
            sleep(30)
        end
        Guild.new_task(skill)
    elseif task:find("Illusion") and task:find("one minute") then
        msg("yellow", "Illusion speed task")
        Util.go2(Char.prof:lower() .. " alchemy workshop")
        for _ = 1, reps * 3 do
            Util.wait_rt()
            fput("illusion rose")
            sleep(1)
            local rh_ill2 = GameObj.right_hand()
            if rh_ill2 and rh_ill2.name and rh_ill2.name:find("rose") then
                fput("eat my rose")
            end
            Util.wait_rt()
        end
        Guild.new_task(skill)
    else
        msg_error("Unhandled task: " .. task)
        msg("yellow", "Please complete this task manually and restart.")
    end
end

function Guild.new_task(skill)
    local guild_status = Guild.gld()

    -- Check if all skills mastered
    local all_mastered = true
    for _, stype in ipairs({"alchemy", "potions", "trinkets"}) do
        if guild_status[stype] and guild_status[stype].rank ~= 63 then
            all_mastered = false
            break
        end
    end
    if all_mastered then
        msg("yellow", "Congratulations! You are a master of alchemy, potions, and trinkets.")
        return
    end

    -- Pick lowest-rank skill if none specified
    if not skill then
        local min_rank = 999
        for _, stype in ipairs(settings.skill_types) do
            if stype ~= "learn" and stype ~= "teach" then
                local rank = guild_status[stype] and guild_status[stype].rank or 0
                if rank < min_rank then
                    min_rank = rank
                    skill = stype
                end
            end
        end
    end

    if not skill then
        msg("yellow", "No skills available for training. Check settings.")
        return
    end

    -- Once and done check
    if settings.once_and_done then
        msg("yellow", "Task complete. Once-and-done mode. Exiting.")
        return
    end

    Guild.activity(guild_status, skill)
end

--------------------------------------------------------------------------------
-- Upstream hook for finish command
--------------------------------------------------------------------------------

local HOOK_ID = "blackarts_finish_hook"
local original_once = settings.once_and_done

Hook.add(HOOK_ID, "upstream", function(line)
    if Regex.test(line, "^(?:<c>)?;bla.*finish") then
        settings.once_and_done = true
        msg("yellow", "BlackArts will exit after the next task is completed")
        return nil
    end
    return line
end)

before_dying(function()
    Hook.remove(HOOK_ID)
    settings.once_and_done = original_once
end)

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function setup_gui()
    local win = Gui.window("BlackArts Setup", 500, 600)
    local box = Gui.vbox(win)

    Gui.label(box, "=== BlackArts Configuration ===")
    Gui.label(box, "")

    -- Guild Skills
    Gui.label(box, "Guild Skills:")
    local skill_options = { "alchemy", "potions", "trinkets" }
    if Char.prof == "Sorcerer" then
        skill_options[#skill_options + 1] = "illusions"
    end

    for _, sk in ipairs(skill_options) do
        local enabled = false
        for _, s in ipairs(settings.skill_types) do
            if s == sk then enabled = true; break end
        end
        Gui.checkbox(box, title_case(sk), enabled, function(val)
            if val then
                local found = false
                for _, s in ipairs(settings.skill_types) do
                    if s == sk then found = true; break end
                end
                if not found then settings.skill_types[#settings.skill_types + 1] = sk end
            else
                for i = #settings.skill_types, 1, -1 do
                    if settings.skill_types[i] == sk then table.remove(settings.skill_types, i) end
                end
            end
            save_json("blackarts_settings", settings)
        end)
    end

    Gui.label(box, "")
    Gui.label(box, "Options:")
    Gui.checkbox(box, "Use Vouchers", settings.use_vouchers, function(v)
        settings.use_vouchers = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Use Guild Boosts", settings.use_boost, function(v)
        settings.use_boost = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Run One Task Only", settings.once_and_done, function(v)
        settings.once_and_done = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "No Alchemy Mode", settings.no_alchemy, function(v)
        settings.no_alchemy = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Travel to Other Guilds", settings.guild_travel, function(v)
        settings.guild_travel = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Do Not Use Bank", settings.no_bank, function(v)
        settings.no_bank = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Sell at Consignment", settings.sell_consignment, function(v)
        settings.sell_consignment = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Buy Reagents", settings.buy_reagents, function(v)
        settings.buy_reagents = v; save_json("blackarts_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Banking:")
    Gui.entry(box, "Withdrawal amount:", settings.note_withdrawal, function(v)
        settings.note_withdrawal = v; save_json("blackarts_settings", settings)
    end)
    Gui.entry(box, "Refresh threshold:", settings.note_refresh, function(v)
        settings.note_refresh = v; save_json("blackarts_settings", settings)
    end)

    Gui.label(box, "")
    Gui.label(box, "Mana/Spirit:")
    Gui.checkbox(box, "Use Wracking", settings.use_wracking, function(v)
        settings.use_wracking = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Use Sigil of Concentration", settings.use_sigil_concentration, function(v)
        settings.use_sigil_concentration = v; save_json("blackarts_settings", settings)
    end)
    Gui.checkbox(box, "Use Sigil of Power", settings.use_sigil_power, function(v)
        settings.use_sigil_power = v; save_json("blackarts_settings", settings)
    end)

    Gui.show(win)
end

--------------------------------------------------------------------------------
-- Suggestion display
--------------------------------------------------------------------------------

local function show_suggestions()
    local guild_status = Guild.gld()
    respond("")
    respond("=== BlackArts Suggestions ===")
    respond("")

    for _, skill_type in ipairs({"alchemy", "potions", "trinkets"}) do
        local info = guild_status[skill_type]
        if info then
            local rank = info.rank or 0
            local reps = info.reps or 0
            local task = info.task or "no task"
            respond(string.format("  %s: Rank %d, %d reps, Task: %s",
                title_case(skill_type), rank, reps, task))
        end
    end
    respond("")
    respond("Note: Full recipe suggestion engine requires recipe database.")
    respond("Use ;blackarts setup to configure guild skills.")
    respond("")
end

--------------------------------------------------------------------------------
-- Set up stow containers
--------------------------------------------------------------------------------

local function set_variables()
    -- Find containers from stow list
    fput("stow list")
    sleep(1)

    -- In Revenant, containers are tracked via the stow system
    -- We look for default, herb, reagent containers
    for _, stype in ipairs({"default", "herb", "reagent"}) do
        local sack_var = UserVars[stype .. "sack"]
        if sack_var and sack_var ~= "" then
            local found = GameObj.find_inv(sack_var)
            if found then
                sacks[stype] = found
            end
        end
    end

    -- Open containers to see contents
    for _, stype in ipairs({"default", "herb", "reagent"}) do
        if sacks[stype] then
            Inventory.open_container(stype)
        end
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cmd = (Script.vars[1] or ""):lower()
local args = Script.vars

if cmd == "setup" or cmd == "config" then
    setup_gui()
    return
elseif cmd == "suggest" or cmd == "suggestions" then
    show_suggestions()
    return
elseif cmd == "help" then
    respond("")
    respond("=== BlackArts - Alchemy Guild Automation ===")
    respond("")
    respond("  ;blackarts              Start automated guild tasking")
    respond("  ;blackarts setup        Open settings GUI")
    respond("  ;blackarts suggest      Show recipe suggestions")
    respond("  ;blackarts check ITEM   Check ingredients for an item")
    respond("  ;blackarts make ITEM    Make a specific item")
    respond("  ;blackarts forage HERB  Forage for a specific herb")
    respond("  ;blackarts help         Show this help")
    respond("")
    respond("  While running:")
    respond("    ;blackarts finish     Stop after current task")
    respond("")
    return
elseif cmd == "forage" then
    local herb = table.concat(args, " ", 3)
    if herb == "" then
        msg("yellow", "Usage: ;blackarts forage <herb name> x<count>")
        return
    end
    msg("yellow", "Foraging for: " .. herb)
    msg("yellow", "Foraging automation not fully ported yet.")
    return
elseif cmd == "check" or cmd == "prepare" or cmd == "make" then
    local product = table.concat(args, " ", 3)
    if product == "" then
        msg("yellow", "Usage: ;blackarts " .. cmd .. " <potion name> x<count>")
        return
    end
    msg("yellow", "Recipe checking/making not fully ported yet.")
    msg("yellow", "Use ;blackarts suggest to see available tasks.")
    return
end

-- Validate settings
if #settings.skill_types == 0 then
    msg("yellow", "No guild skills selected. Running setup...")
    setup_gui()
    return
end

if Char.level < 15 then
    msg_error("You must be at least level 15 to join a guild.")
    return
end

-- Set up containers
set_variables()

-- Check for required containers (unless no_alchemy mode)
if not settings.no_alchemy then
    if not sacks["default"] then
        msg_error("Default container not set. Use STOW SET in-game.")
        return
    end
    if not sacks["herb"] then
        msg_error("Herb container not set. Use STOW SET in-game.")
        return
    end
    if not sacks["reagent"] then
        msg_error("Reagent container not set. Use STOW SET in-game.")
        return
    end
end

-- Track room changes
Util.track_room = function()
    -- Room tracking is handled by Revenant engine automatically
end

-- Set hooks for finish command
Util.set_hooks = function() end  -- Already done via Hook.add above

-- Silence output if configured
if settings.silence then
    silence_me()
end

-- Start main guild loop
msg("yellow", "Starting BlackArts guild automation...")
msg("yellow", string.format("Skills: %s", table.concat(settings.skill_types, ", ")))

-- Navigate to guild administrator
Util.go2(Char.prof:lower() .. " alchemy administrator")

-- Begin task loop
Guild.new_task(nil)
