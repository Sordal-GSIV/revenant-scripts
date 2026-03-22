--- @revenant-script
--- name: osacommander
--- version: 4.0.5
--- author: Peggyanne (Bait#4376)
--- game: gs
--- description: OSA ship captain command script - manages crew, combat, navigation, and tasks for Open Sea Adventures
--- tags: osa, ships, combat, crew, captain, commander, sailing
--- @lic-certified: complete 2026-03-18
---
--- Usage:
---   ;osacommander help                         Display full command list
---   ;osacommander setup                        Opens setup menu for commander
---   ;osacommander crew                         Display crew management commands
---   ;osacommander info <ship type>             Gather ship info and save current ship type
---   ;osacommander begin                        Go to bank, retrieve ship, get underway
---   ;osacommander start                        Orders crew to start combat scripts
---   ;osacommander end                          Orders crew to begin end sequence
---   ;osacommander stop                         Orders crew to stop all combat scripts
---   ;osacommander exit                         Orders crew to attention and exit game
---   ;osacommander pause                        Pauses crew combat scripts
---   ;osacommander unpause                      Unpauses crew combat scripts
---   ;osacommander muster                       Takes roll call of crew
---   ;osacommander muster count                 Determine who present is not crew
---   ;osacommander broadcast                    Look ocean and broadcast ship location
---   ;osacommander summon                       Call crew to your location
---   ;osacommander summon force                 Force summon regardless of group status
---   ;osacommander underway                     Orders crew to get ship underway
---   ;osacommander repairs                      Orders crew to do repairs
---   ;osacommander return                       Turn off detection and return to port
---   ;osacommander spells                       Orders crew to begin spellups
---   ;osacommander spellup                      Orders crew to perform mana spellup
---   ;osacommander spellup <name>               Orders crew to spellup specific individual
---   ;osacommander silvers                      Orders crew to give silvers to commander
---   ;osacommander status                       Orders crew to display status info
---   ;osacommander resource                     Orders crew to display resource info
---   ;osacommander gemstone                     Orders crew to display gemstone info
---   ;osacommander task                         Orders crew to turn in and get new tasks
---   ;osacommander task count                   Determine who hasn't rogered up
---   ;osacommander sell                         Orders crew to sell loot and return
---   ;osacommander reset                        Orders crew to reset osacrew scripts
---   ;osacommander detection on/off             Toggle enemy ship detection
---   ;osacommander cleanup on/off               Toggle straggler cleanup detection
---   ;osacommander cleanup                      Begin cleanup process
---   ;osacommander scripted on/off              Toggle acceptance of outside scripted crew
---   ;osacommander noscript on/off              Toggle pause for non-scripting crew
---   ;osacommander poaching on/off              Toggle anti-poaching feature
---   ;osacommander combat                       Tell entire crew to start OSACombat
---   ;osacommander combat <name>                Tell specific crew member to start OSACombat
---   ;osacommander loot <name>                  Set specific crew member as looter
---   ;osacommander bless                        Begin blessing sequence for crew
---   ;osacommander sheath                       Orders crew to sheath weapons
---   ;osacommander testcon <crew member>        Test crew member connection
---   ;osacommander kick <crew member>           Remove crew member from duty
---   ;osacommander unkick <crew member>         Return crew member to duty
---   ;osacommander checkversion                 Check script versions for you and crew
---   ;osacommander bread                        Medical officer makes mana bread
---   ;osacommander undead                       Orders crew to start undead combat
---   ;osacommander update <scriptname>          Orders crew to update a script
---   ;osacommander anti_stow                    Anti-stow protection loop
---   ;osacommander settings                     Display all current settings
---   ;osacommander exp                          Display exp and resource stats
---
--- Change Log:
---   July 29, 2025    - Added changelog, loot command, silver sharing option
---   August 3, 2025   - Separated status into three reports
---   August 26, 2025  - Fixed variable error with silver sharing
---   September 22, 2025 - Fixed error in silver readout
---   December 6, 2025 - Removed Vars dependency, added YAML support, tooltips, defaults
---   January 20, 2026 - Fixed boarding times display
---   January 25, 2026 - Added anti-poaching command
---   January 26, 2026 - Fixed empath stalling and sinking ship issues
---   February 1, 2026 - Updated YAML read/write with FLOCK
---   February 13, 2026 - Rewrote config and GTK using AI
---   March 18, 2026   - Complete Revenant Lua conversion (full feature parity)
---
--- ~Peggyanne
---   Discord: Bait#4376

local VERSION = "4.0.5 (Lua - March 18, 2026)"

---------------------------------------------------------------------------
-- Settings (persisted via CharSettings / Json)
---------------------------------------------------------------------------
local function load_settings()
    local raw = CharSettings.osa_data
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function save_settings(data)
    CharSettings.osa_data = Json.encode(data)
end

local osa = load_settings()

local function osa_get(key, default)
    local v = osa[key]
    if v == nil then return default end
    return v
end

local function osa_set(key, value)
    osa[key] = value
    save_settings(osa)
end

local function osa_push(key, value)
    if type(osa[key]) ~= "table" then osa[key] = {} end
    table.insert(osa[key], value)
    save_settings(osa)
end

local function osa_delete_from(key, value)
    if type(osa[key]) ~= "table" then return end
    for i = #osa[key], 1, -1 do
        if osa[key][i] == value then table.remove(osa[key], i) end
    end
    save_settings(osa)
end

---------------------------------------------------------------------------
-- Ship room ID maps
---------------------------------------------------------------------------
local SHIP_MAPS = {
    sloop = {
        rooms = {29039, 29038, 29040, 29041, 29042},
        tags  = {"cargo_hold", "main_deck", "crows_nest", "helm", "captains_quarters"},
        main_deck = 29038, range = {29038, 29042}, max_crew = 2, cost = 5000,
        cannon_tags = {[29038] = "main_cannon"},
        masts = 1,
    },
    brigantine = {
        rooms = {30145, 30142, 30144, 30143, 30147, 30146, 30141, 30140},
        tags  = {"cargo_hold", "main_deck", "forward_deck", "crows_nest", "mess_hall", "crew_quarters", "helm", "captains_quarters"},
        main_deck = 30142, range = {30140, 30147}, max_crew = 4, cost = 7500,
        cannon_tags = {[30142] = "main_cannon", [30144] = "forward_cannon"},
        masts = 2,
    },
    carrack = {
        rooms = {30125, 30119, 30121, 30122, 30123, 30127, 30126, 30120, 30124},
        tags  = {"cargo_hold", "main_deck", "forward_deck", "bow", "crows_nest", "mess_hall", "crew_quarters", "helm", "captains_quarters"},
        main_deck = 30119, range = {30119, 30127}, max_crew = 7, cost = 7500,
        cannon_tags = {[30119] = "main_cannon", [30121] = "forward_cannon"},
        masts = 2,
    },
    galleon = {
        rooms = {30182, 30176, 30177, 30178, 30181, 30185, 30184, 30183, 30179, 30180},
        tags  = {"cargo_hold", "main_deck", "forward_deck", "bow", "crows_nest", "social_room", "mess_hall", "crew_quarters", "helm", "captains_quarters"},
        main_deck = 30176, range = {30176, 30186}, max_crew = 11, cost = 10000,
        cannon_tags = {[30176] = "main_cannon", [30177] = "forward_cannon"},
        masts = 2,
    },
    frigate = {
        rooms = {30167, 30166, 30171, 30172, 30173, 30170, 30169, 30168, 30174, 30175},
        tags  = {"cargo_hold", "main_deck", "forward_deck", "bow", "crows_nest", "social_room", "mess_hall", "crew_quarters", "helm", "captains_quarters"},
        main_deck = 30166, range = {30166, 30175}, max_crew = 13, cost = 10000,
        cannon_tags = {[30166] = "main_cannon", [30171] = "forward_cannon"},
        masts = 2,
    },
    ["man o' war"] = {
        rooms = {30136, 30130, 30131, 30132, 30133, 30135, 30134, 30139, 30138, 30137, 30128, 30129},
        tags  = {"cargo_hold", "main_deck", "mid_deck", "forward_deck", "bow", "crows_nest", "forward_crows_nest", "social_room", "mess_hall", "crew_quarters", "helm", "captains_quarters"},
        main_deck = 30130, range = {30128, 30139}, max_crew = 19, cost = 12500,
        cannon_tags = {[30130] = "main_cannon", [30131] = "mid_cannon", [30132] = "forward_cannon"},
        masts = 3,
    },
}

local ENEMY_SHIP_MAPS = {
    Sloop         = {"enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
    Brigantine    = {"enemy_forward_deck", "enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
    Carrack       = {"enemy_bow", "enemy_forward_deck", "enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
    Galleon       = {"enemy_bow", "enemy_forward_deck", "enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
    Frigate       = {"enemy_forward_deck", "enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
    ["Man O' War"] = {"enemy_bow", "enemy_forward_deck", "enemy_forward_crows_nest", "enemy_mid_deck", "enemy_main_deck", "enemy_crows_nest", "enemy_helm", "enemy_cargo_hold"},
}

---------------------------------------------------------------------------
-- Pier maps (for commander_begin ship-finding loop)
---------------------------------------------------------------------------
local PIER_MAPS = {
    ["Thrak"]          = {29738, 29739, 29740, 29741, 29742},
    ["Helga"]          = {30228, 30232, 30233, 30234, 30235},
    ["Beldrin"]        = {30223, 30227, 30229, 30230, 30231},
    ["Dakris"]         = {30221, 30222, 30224, 30225, 30226},
    ["Larton"]         = {30220, 30219, 30218, 30217, 30216},
    ["Green"]          = {30192, 30191, 30190, 30189, 30188},
    ["White"]          = {30193, 30209, 30210, 30211, 30212},
    ["Blue"]           = {30194, 30205, 30206, 30207, 30208},
    ["Gold"]           = {30195, 30201, 30202, 30203, 30204},
    ["Crimson"]        = {30196, 30197, 30198, 30199, 30200},
    ["Asterfire"]      = {30241, 30250, 30251, 30252, 30253},
    ["Geode"]          = {30242, 30249, 30254, 30255, 30256},
    ["Dreamstone"]     = {30243, 30248, 30257, 30258, 30259},
    ["Dragonfire"]     = {30244, 30247, 30260, 30261, 30262},
    ["Sunstone"]       = {30245, 30246, 30263, 30264, 30265},
    ["Dovesnail"]      = {29503, 29504, 29505, 29506, 29507},
    ["Wentletrap"]     = {29508, 29509, 29510, 29511, 29512},
    ["Moonsnail"]      = {29513, 29514, 29515, 29516, 29517},
    ["Sandsilver"]     = {29518, 29519, 29520, 29521, 29522},
    ["Hornsnail"]      = {29523, 29524, 29525, 29526, 29527},
    ["First"]          = {29033, 29034, 29035, 29036, 29037},
    ["Second"]         = {29032, 29044, 29045, 29046, 29150},
    ["Third"]          = {29043, 29151, 29152, 29153, 29154},
    ["Fourth"]         = {29155, 29156, 29157, 29158, 29159},
    ["Fifth"]          = {29060, 29061, 29062, 29063, 29064},
    ["Broken Pier"]    = {32350},
    ["Greying Pier"]   = {32347},
    ["Old Pier"]       = {32356},
    ["Decaying Pier"]  = {32355},
    ["Crumbling Pier"] = {32360},
    ["Cracked Pier"]   = {32359},
    ["Weathered Pier"] = {32358},
    ["Port Pier"]      = {32357},
    ["Starboard Pier"] = {32351},
    ["Salty Pier"]     = {32352},
    ["Rimy Pier"]      = {32353},
    ["Gelid Pier"]     = {32348},
    ["Snowy Pier"]     = {32349},
    ["Gleaming Pier"]  = {32370},
    ["Shivering Pier"] = {32371},
    ["Cold Pier"]      = {32372},
    ["Crab Pier"]      = {32340},
    ["Albatross Pier"] = {32346},
    ["Barrow Pier"]    = {32345},
    ["Highland Pier"]  = {32344},
    ["Moon Pier"]      = {32343},
    ["Shadowed Pier"]  = {32342},
    ["Crawling Pier"]  = {32341},
    ["Briar Pier"]     = {32354},
    ["Docks, Shoreline"] = {32339},
    ["Soaring Wyvern"] = {31502, 31517, 31516, 31503, 31518},
    ["Rampant Wyvern"] = {31500, 31501, 31515, 31514, 31513},
    ["Roaring Wyvern"] = {31498, 31499, 31508, 31507, 31506},
    ["Resting Wyvern"] = {31496, 31497, 31510, 31509, 31505},
    ["Staring Wyvern"] = {31494, 31495, 31512, 31511, 31504},
    ["Pier 1"]         = {32908, 32909, 32910, 32911, 32912},
    ["Pier 2"]         = {32907, 32913, 32914, 32915, 32916},
    ["Pier 3"]         = {32906, 32917, 32918, 32919, 32920},
    ["Pier 4"]         = {32905, 32921, 32922, 32923, 32924},
    ["Pier 5"]         = {32504, 32925, 32926, 32927, 32928},
    ["Acistira Pier"]  = {33831, 33832, 33833, 33834, 33835},
    ["Naefira Pier"]   = {33836, 33837, 33838, 33839, 33840},
    ["Taerethil Pier"] = {33841, 33842, 33843, 33844, 33845},
    ["Resaeun Pier"]   = {33846, 33847, 33848, 33849, 33850},
    ["Aelerine Pier"]  = {33851, 33852, 33853, 33854, 33855},
}

---------------------------------------------------------------------------
-- LNet messaging helpers
---------------------------------------------------------------------------
local function crew_channel()
    return osa_get("crew", GameState.name)
end

local function lnet_channel(msg)
    put("chat to " .. crew_channel() .. " " .. msg)
end

local function lnet_private(to, msg)
    put("chat to " .. to .. " " .. msg)
end

---------------------------------------------------------------------------
-- Navigation helpers
---------------------------------------------------------------------------
local function go_to_tag(tag)
    local room = Room.current()
    if room and room.tags then
        for _, t in ipairs(room.tags) do
            if t == tag then return end
        end
    end
    Script.run("go2", tag)
    wait_while(function() return running("go2") end)
end

local function main_deck()          go_to_tag("main_deck") end
local function helm()               go_to_tag("helm") end
local function cargo_hold()         go_to_tag("cargo_hold") end
local function crows_nest()         go_to_tag("crows_nest") end
local function captains_quarters()  go_to_tag("captains_quarters") end
local function forward_deck()       go_to_tag("forward_deck") end
local function bow()                go_to_tag("bow") end
local function mid_deck()           go_to_tag("mid_deck") end
local function mess_hall()          go_to_tag("mess_hall") end
local function crew_quarters()      go_to_tag("crew_quarters") end
local function social_room()        go_to_tag("social_room") end
local function forward_crows_nest() go_to_tag("forward_crows_nest") end
local function enemy_main_deck()    go_to_tag("enemy_main_deck") end
local function enemy_quarters()     go_to_tag("enemy_quarters") end
local function enemy_forward_deck() go_to_tag("enemy_forward_deck") end
local function enemy_bow()          go_to_tag("enemy_bow") end
local function enemy_mid_deck()     go_to_tag("enemy_mid_deck") end
local function enemy_crows_nest()   go_to_tag("enemy_crows_nest") end
local function enemy_helm()         go_to_tag("enemy_helm") end
local function enemy_forward_crows_nest() go_to_tag("enemy_forward_crows_nest") end

local function go_to_handler()
    Script.run("go2", "handler")
    wait_while(function() return running("go2") end)
    -- Kraken's Fall handler is room 28950
    local rid = Room.id
    if rid and tostring(rid):find("Kraken") then
        Script.run("go2", "28950")
        wait_while(function() return running("go2") end)
    end
end

---------------------------------------------------------------------------
-- Sail / Anchor operations (use dothistimeout, not fput)
---------------------------------------------------------------------------
local function lower_sail()
    while true do
        waitrt()
        local result = dothistimeout("lower sail", 5, "half mast|fully open|far as it can go")
        if not result then return end
        if string.find(result, "fully open") or string.find(result, "far as it can go") then
            waitrt()
            return true
        end
        waitrt() -- half mast — need another lower
    end
end

local function raise_anchor()
    while true do
        waitrt()
        local result = dothistimeout("push capstan", 5, "begin to push|one final push|anchor is already up")
        if not result then return end
        if string.find(result, "one final push") then
            waitrt()
            return true
        end
        if string.find(result, "anchor is already up") then return true end
        waitrt()
    end
end

local function pull_gangplank()
    fput("pull gangplank")
end

local function unfurl_masts(count)
    pull_gangplank()
    if count >= 1 then
        lower_sail(); waitrt()
        if count == 1 then
            fput("yell Main Mast Unfurled, She's Ready to Sail!")
            pause(0.5); move("west"); return
        end
        fput("yell Main Mast Unfurled"); pause(0.5); move("east")
    end
    if count >= 2 then
        lower_sail(); waitrt()
        if count == 2 then
            fput("yell Fore Mast Unfurled, She's Ready to Sail!")
            pause(0.5); move("west"); pause(0.5); move("west"); return
        end
        fput("yell Fore Mast Unfurled"); pause(0.5); move("east")
    end
    if count >= 3 then
        lower_sail(); waitrt()
        fput("yell Mizzen Mast Unfurled, She's Ready to Sail!")
        pause(0.5); move("west"); pause(0.5); move("west"); pause(0.5); move("west")
    end
end

---------------------------------------------------------------------------
-- Mana type detection
---------------------------------------------------------------------------
local function build_mana_message()
    local types = {}
    if Skills.spirit_mana_control and Skills.spirit_mana_control >= 24 then
        table.insert(types, "Spiritual")
    end
    if Skills.mental_mana_control and Skills.mental_mana_control >= 24 then
        table.insert(types, "Mental")
    end
    if Skills.elemental_mana_control and Skills.elemental_mana_control >= 24 then
        table.insert(types, "Elemental")
    end
    if #types == 0 then return "I Need Mana!" end
    if #types == 1 then return "I Need " .. types[1] .. " Mana!" end
    local last = table.remove(types)
    return "I Need " .. table.concat(types, ", ") .. " or " .. last .. " Mana!"
end

---------------------------------------------------------------------------
-- Crew tracking
---------------------------------------------------------------------------
local crew_members = {}
local warning_flag = false

local function crew_count()
    if type(crew_members) ~= "table" then return 0 end
    return #crew_members
end

local function take_muster()
    local start = os.time()
    while os.time() - start < 6 do
        local line = matchtimeout(6, "Crewman .* Reporting For Duty Captain")
        if line and string.find(line, "Reporting For Duty Captain") then
            local name = line:match("Crewman (.-) Reporting")
            if name then
                local found = false
                for _, n in ipairs(crew_members) do
                    if n == name then found = true; break end
                end
                if not found then table.insert(crew_members, name) end
            end
        else
            break
        end
    end
    osa_set("crewsize", crew_members)
end

local function call_muster()
    -- Check if muster is needed
    local pcs = GameObj.pcs()
    local pc_set = {}
    for _, pc in ipairs(pcs) do pc_set[pc.name] = true end
    local need_muster = false
    for _, cm in ipairs(crew_members) do
        if not pc_set[cm] then need_muster = true; break end
    end
    for name in pairs(pc_set) do
        local is_crew = false
        for _, cm in ipairs(crew_members) do if cm == name then is_crew = true; break end end
        if not is_crew then need_muster = true; break end
    end
    if not need_muster and crew_count() > 0 then
        respond("")
        respond(" ------ Crewsize Matches All Crew Present, Skipping Muster! ------ ")
        respond("")
        return
    end
    crew_members = {}
    osa_set("crewsize", crew_members)
    lnet_channel("Quarters! All Hands To Quarters For Muster, Instruction and Inspection!")
    take_muster()
    lnet_channel("All Present And Accounted For! We Have " .. crew_count() .. " Crew Onboard For A Total Compliment of " .. (crew_count() + 1) .. " Personnel!")
    pause(3)
end

local function wait_for_crew_tasks()
    local count = crew_count()
    if count == 0 then return end
    local received = 0
    while received < count do
        local line = matchtimeout(600, "Task Complete")
        if line and string.find(line, "Task Complete") then
            received = received + 1
        else
            break
        end
    end
end

---------------------------------------------------------------------------
-- Combat vessel messaging
---------------------------------------------------------------------------
local VESSEL_MESSAGES = {
    "We Are Engaging A %s Vessel, All Hands Man Your Battlestations!",
    "Surface Contact, Port Side, Bearing %03d, %s Vessel Inbound!",
    "Surface Contact, Starboard Side, Bearing %03d, %s Vessel Inbound!",
    "Surface Contact, Dead Ahead, %s Vessel Inbound!",
    "Cannon Fire Inbound, Brace For Shock! %s Vessel Approaching!",
    "%s Ship Detected, She's Caught Between The Devil And The Deep Blue Sea! To Your Battlestations!",
    "%s Vessel Inbound! She Be Sailing Close To The Wind Me Boys! Time To Make Waves!",
    "%s Vessel Starboard Side! She Be Choc-a-Block, Knock Seven Bells!",
    "%s Vessel Port Side! She Be Choc-a-Block, Knock Seven Bells!",
}

local function vessel_messaging(enemy_type)
    local idx = math.random(1, #VESSEL_MESSAGES)
    local msg = VESSEL_MESSAGES[idx]
    if string.find(msg, "%%03d") then
        local bearing = math.random(0, 359)
        fput("yell " .. string.format(msg, bearing, enemy_type))
    else
        fput("yell " .. string.format(msg, enemy_type))
    end
end

---------------------------------------------------------------------------
-- Enemy detection
---------------------------------------------------------------------------
local function determine_enemy_type()
    fput("look ocean")
    local line = matchtimeout(5, "You notice .* approaching your position")
    if line then
        local desc = line:match("You notice (.*) approaching your position")
        if desc then
            osa_set("enemyship", desc)
            if string.find(desc, "ethereal") then
                osa_set("enemy_type", "undead"); osa_set("creature_type", "undead")
            elseif string.find(desc, "krolvin") then
                osa_set("enemy_type", "krolvin"); osa_set("creature_type", "living")
            elseif string.find(desc, "dark") then
                osa_set("enemy_type", "pirate"); osa_set("creature_type", "living")
            end
            local ld = string.lower(desc)
            if string.find(ld, "sloop") then
                osa_set("enemy_ship_type", "Sloop")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Sloop"])
            elseif string.find(ld, "brigantine") then
                osa_set("enemy_ship_type", "Brigantine")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Brigantine"])
            elseif string.find(ld, "carrack") then
                osa_set("enemy_ship_type", "Carrack")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Carrack"])
            elseif string.find(ld, "galleon") then
                osa_set("enemy_ship_type", "Galleon")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Galleon"])
            elseif string.find(ld, "frigate") then
                osa_set("enemy_ship_type", "Frigate")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Frigate"])
            elseif string.find(ld, "man o' war") then
                osa_set("enemy_ship_type", "Man O' War")
                osa_set("enemy_ship_map", ENEMY_SHIP_MAPS["Man O' War"])
            end
        end
    else
        echo("Unable To Determine Enemy Type, Default Is: Pirate")
        osa_set("enemy_type", "pirate"); osa_set("creature_type", "living")
    end
end

local function determine_to_engage()
    local function contains(tbl, val)
        for _, v in ipairs(tbl) do if v == val then return true end end
        return false
    end
    local enemy_types = {}
    if osa_get("enemy_pirate", false) then table.insert(enemy_types, "pirate") end
    if osa_get("enemy_krolvin", false) then table.insert(enemy_types, "krolvin") end
    if osa_get("enemy_undead", false) then table.insert(enemy_types, "undead") end
    local board_ships = {}
    if osa_get("board_sloop", false) then table.insert(board_ships, "Sloop") end
    if osa_get("board_brigantine", false) then table.insert(board_ships, "Brigantine") end
    if osa_get("board_carrack", false) then table.insert(board_ships, "Carrack") end
    if osa_get("board_galleon", false) then table.insert(board_ships, "Galleon") end
    if osa_get("board_frigate", false) then table.insert(board_ships, "Frigate") end
    if osa_get("board_man", false) then table.insert(board_ships, "Man O' War") end
    local cannon_ships = {}
    if osa_get("fire_sloop", false) then table.insert(cannon_ships, "Sloop") end
    if osa_get("fire_brigantine", false) then table.insert(cannon_ships, "Brigantine") end
    if osa_get("fire_carrack", false) then table.insert(cannon_ships, "Carrack") end
    if osa_get("fire_galleon", false) then table.insert(cannon_ships, "Galleon") end
    if osa_get("fire_frigate", false) then table.insert(cannon_ships, "Frigate") end
    if osa_get("fire_man", false) then table.insert(cannon_ships, "Man O' War") end
    local engage = contains(enemy_types, osa_get("enemy_type", "")) and contains(board_ships, osa_get("enemy_ship_type", ""))
    osa_set("engage", engage)
    osa_set("cannon_engage", contains(cannon_ships, osa_get("enemy_ship_type", "")))
end

---------------------------------------------------------------------------
-- Wound / hand / box helpers
---------------------------------------------------------------------------
local BOX_NOUNS = {box=true, strongbox=true, coffer=true, trunk=true, chest=true}

local function is_box(item)
    return item and BOX_NOUNS[item.noun]
end

local function has_significant_wounds()
    if not Wounds then return false end
    local parts = {"head","neck","chest","abdomen","back","right_arm","left_arm",
                   "right_hand","left_hand","right_leg","left_leg","right_foot","left_foot"}
    for _, p in ipairs(parts) do
        if Wounds[p] and Wounds[p] > 1 then return true end
    end
    return false
end

local function commander_left_hand()
    local lh = GameObj.left_hand()
    if not lh or not lh.id then return end
    if is_box(lh) then
        fput("drop left")
    else
        if not dothistimeout("store left", 3, "You put|You stow") then fput("stow left") end
    end
end

local function commander_right_hand()
    local rh = GameObj.right_hand()
    if not rh or not rh.id then return end
    if is_box(rh) then
        fput("drop right")
    else
        if not dothistimeout("store right", 3, "You put|You stow") then fput("stow right") end
    end
end

local function inv_boxes()
    local result = {}
    for _, item in ipairs(GameObj.inv()) do
        if is_box(item) then table.insert(result, item) end
    end
    return result
end

local function loot_room_boxes()
    local result = {}
    for _, item in ipairs(GameObj.loot()) do
        if is_box(item) then table.insert(result, item) end
    end
    return result
end

---------------------------------------------------------------------------
-- Bank balance tracking
---------------------------------------------------------------------------
local bank_balance_begin = 0

local function check_bank_balance()
    fput("bank acc")
    local line = matchtimeout(5, "Total:")
    if line then
        local bal = line:match("Total: ([0-9,]+)")
        if bal then return tonumber(bal:gsub(",", "")) or 0 end
    end
    return 0
end

local function begin_balance()
    bank_balance_begin = check_bank_balance()
    osa_set("beginbalance", bank_balance_begin)
end

local function after_balance()
    local after = check_bank_balance()
    osa_set("afterbalance", after)
    local delta = after - bank_balance_begin
    osa_set("endbalance", delta)
    return delta
end

---------------------------------------------------------------------------
-- Bless protocol
---------------------------------------------------------------------------
local function receive_bless()
    local result = matchtimeout(15, "a moment and then gently dissipates|leaving a soft white afterglow|appears to become incorporated into it|but it quickly returns to normal")
    if not result then
        respond("")
        respond("                 Something May Have Gone Wrong With The Bless")
        respond("")
    end
end

local function self_bless()
    if Spell.known(1604) and Spell.affordable(1604) then Spell.cast(1604) end
    waitcastrt()
    if Spell.known(304) and Spell.affordable(304) then
        Spell.cast(304)
    else
        fput("symbol bless")
    end
end

local function get_self_bless()
    if not osa_get("needbless", false) or osa_get("blesser", "") == "" then return end
    local uachands = osa_get("uachands", "")
    local uacfeet  = osa_get("uacfeet",  "")
    if uachands == "" and uacfeet == "" then
        fput("gird"); pause(1)
    else
        if uachands ~= "" then fput("remove " .. uachands); pause(0.5) end
        if uacfeet  ~= "" then fput("remove " .. uacfeet) end
    end
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if lh and lh.id and rh and rh.id then
        self_bless(); waitrt(); waitcastrt()
        fput("swap")
        self_bless(); waitrt(); waitcastrt()
        fput("swap")
    else
        self_bless(); waitrt(); waitcastrt()
    end
    if uachands == "" and uacfeet == "" then
        fput("store both")
    else
        if uachands ~= "" then fput("wear " .. uachands); pause(0.5) end
        if uacfeet  ~= "" then fput("wear " .. uacfeet) end
    end
end

local function get_bless()
    if not osa_get("needbless", false) then return end
    local blesser = osa_get("blesser", "")
    if blesser == "" then return end
    lnet_private(blesser, "I Need Blessed Please!")
    waitfor("%[" .. crew_channel() .. "%]%-GSIV:" .. blesser .. ': "' .. GameState.name)
    local uachands = osa_get("uachands", "")
    local uacfeet  = osa_get("uacfeet",  "")
    if uachands == "" and uacfeet == "" then
        fput("gird")
    else
        if uachands ~= "" then fput("remove " .. uachands); pause(0.5) end
        if uacfeet  ~= "" then fput("remove " .. uacfeet) end
    end
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if lh and lh.id and rh and rh.id then
        lnet_private(blesser, "I Have Two.")
        lnet_private(blesser, "I Am Ready.")
        receive_bless()
        fput("swap")
        lnet_private(blesser, "Ok, The Next One Is Ready.")
        receive_bless()
    else
        lnet_private(blesser, "I Have One.")
        lnet_private(blesser, "I Am Ready.")
        receive_bless()
    end
    if uachands == "" and uacfeet == "" then
        fput("store both")
    else
        if uachands ~= "" then fput("wear " .. uachands); pause(0.5) end
        if uacfeet  ~= "" then fput("wear " .. uacfeet) end
    end
end

local function cast_bless(bless_target)
    local pat = '%[Private%]%-GSIV:' .. bless_target .. ': "I Am Ready|%[Private%]%-GSIV:' .. bless_target .. ': "Ok, The Next One Is Ready'
    local result = matchtimeout(5, pat)
    if not result then return end
    if Spell.known(1604) and Spell.affordable(1604) then Spell.cast(1604, bless_target) end
    waitcastrt()
    if Spell.known(304) and Spell.affordable(304) then
        Spell.cast(304, bless_target)
    else
        fput("symbol bless " .. bless_target)
    end
end

local function give_bless(bless_name)
    lnet_channel(bless_name)
    local pat = '%[Private%]%-GSIV:' .. bless_name .. ': "I Have One|%[Private%]%-GSIV:' .. bless_name .. ': "I Have Two'
    local result = matchtimeout(5, pat)
    if not result then return end
    if string.find(result, "I Have Two") then
        cast_bless(bless_name); cast_bless(bless_name)
    else
        cast_bless(bless_name)
    end
end

local function who_needs_blessed(blessnames)
    local result = matchtimeout(3, '%[Private%]%-GSIV:(.-): "I Need Blessed Please!"')
    if result then
        local name = result:match('%[Private%]%-GSIV:(.-): "I Need Blessed Please!"')
        if name then table.insert(blessnames, name) end
        who_needs_blessed(blessnames)
    end
end

local function begin_bless()
    if (Spell.known(304) or Spell.known(9802)) and osa_get("givebless", false) then
        lnet_channel("I Will Be Providing All Crew Blessings!")
        local blessnames = {}
        lnet_channel("Does Anyone Need A Bless?")
        who_needs_blessed(blessnames)
        for _, n in ipairs(blessnames) do give_bless(n) end
        lnet_channel("The Crew Has Been Properly Blessed!")
    else
        lnet_channel("Can Anyone Bless?")
        local result = matchtimeout(3, '%[Private%]%-GSIV:(.-): "I Can Captain!"')
        if result then
            local blesser = result:match('%[Private%]%-GSIV:(.-): "I Can Captain!"')
            if blesser then
                osa_set("blesser", blesser)
                lnet_channel(blesser .. ", Will You Please Bless The Crew?")
                waitfor('%[' .. crew_channel() .. '%]%-GSIV:' .. blesser .. ': "Does Anyone Need A Bless')
                get_bless()
                waitfor('%[' .. crew_channel() .. '%]%-GSIV:' .. blesser .. ': "The Crew Has Been Properly Blessed')
            end
        else
            lnet_channel("We Do Not Have Anyone Present Who Can Bless The Crew, We Will Continue Without!")
        end
    end
end

---------------------------------------------------------------------------
-- Spellup helpers
---------------------------------------------------------------------------
local function spellup_time_left()
    local timeleft = {}
    local active = Spell.active and Spell.active() or {}
    for _, s in ipairs(active) do
        if s.timeleft and s.timeleft <= 250 and s.timeleft > 2 then
            table.insert(timeleft, s.timeleft)
        end
    end
    local avg = 1
    if #timeleft > 0 then
        local sum = 0
        for _, v in ipairs(timeleft) do sum = sum + v end
        avg = sum / #timeleft
    end
    osa_set("waggletimeleft", avg)
    return avg
end

local function need_mana()
    while running("ewaggle") do
        local pct = Char and Char.percent_mana or 100
        if pct < 15 then
            lnet_channel(build_mana_message())
            wait_until(function() return (Char and Char.percent_mana or 100) > 15 end)
        end
        pause(1)
    end
end

local function determine_group_members()
    fput("group")
    local everyone = {}
    local start = os.time()
    while os.time() - start < 3 do
        local line = matchtimeout(1, "You are leading|You are grouped|GROUP HELP")
        if not line or string.find(line, "GROUP HELP") then break end
        for name in line:gmatch("[A-Z][a-z]+") do
            if name ~= "You" and name ~= "Your" then
                local found = false
                for _, e in ipairs(everyone) do if e == name then found = true; break end end
                if not found then table.insert(everyone, name) end
            end
        end
    end
    osa_set("everyone_in_my_group", everyone)
    return everyone
end

local function commander_apply_support()
    local supportlist = osa_get("supportlist", {})
    for _, entry in ipairs(supportlist) do
        local rec, spec_type = entry[1], entry[2]
        waitrt()
        fput("armor " .. string.lower(spec_type) .. " " .. rec)
        pause(5)
    end
end

local function commander_self_armor_spec()
    local spec = osa_get("my_armor_spec", "")
    if spec == "" then return end
    local lower_spec = string.lower(spec)
    for _, v in ipairs({"blessing","reinforcement","support","casting","evasion","fluidity","stealth"}) do
        if string.find(lower_spec, v) then
            pause(5); waitrt(); fput("armor " .. v); return
        end
    end
end

---------------------------------------------------------------------------
-- Stance / wait helpers
---------------------------------------------------------------------------
local function wait_rt()
    pause(0.1); waitrt(); waitcastrt()
end

local function change_stance(new_stance)
    dothistimeout("stance " .. new_stance, 3, "You are now|You move into|You fall back into|unable to change")
end

local function stance_defensive() wait_rt(); change_stance("defensive") end
local function stance_offensive() wait_rt(); change_stance("offensive") end

---------------------------------------------------------------------------
-- Cleanup subsystem
---------------------------------------------------------------------------
local STEALTH_DISABLER_SPELLS = {
    [1]="Dispel Invisibility", [2]="Searing Light",    [3]="Light",
    [4]="Censure",             [5]="Divine Wrath",      [6]="Elemental Wave",
    [7]="Major Elemental Wave",[8]="Cone of Elements",  [9]="Sunburst",
    [10]="Nature's Fury",      [11]="Grasp of the Grave",[12]="Implosion",
    [13]="Tremors",            [14]="Call Wind",         [15]="Aura of the Arkati",
    [16]="Judgement",
}

local function cast_disabler(spell_name)
    if not Spell.known(spell_name) then
        respond("")
        respond("You Have Selected A Stealth Disabling Spell You Do Not Know. Defaulting To Search.")
        respond("")
        fput("search"); waitrt(); waitcastrt(); return
    end
    fput("prep " .. spell_name); fput("cast")
    waitrt(); waitcastrt()
    if spell_name == "Light" then fput("search"); waitrt(); waitcastrt() end
end

local function cleanup_aoe_routine()
    local d = osa_get("stealth_disabler", 0)
    if d == 0 then
        stance_defensive(); fput("search"); waitrt(); waitcastrt()
    elseif d >= 1 and d <= 16 then
        cast_disabler(STEALTH_DISABLER_SPELLS[d] or "Light")
    elseif d == 17 then
        stance_offensive(); CMan.use("eviscerate"); stance_defensive()
    elseif d == 18 then
        stance_offensive(); Warcry.use("Cry", "All"); stance_defensive()
    elseif d == 19 then
        stance_defensive(); fput("symbol of sleep"); waitrt(); waitcastrt()
    end
end

local function cleanup_loot_routine()
    local dead_npcs = {}
    for _, npc in ipairs(GameObj.npcs()) do
        if npc.status == "dead" then table.insert(dead_npcs, npc) end
    end
    if #dead_npcs > 0 then
        Script.run("eloot"); wait_while(function() return running("eloot") end)
        if #loot_room_boxes() > 0 then
            local straggler = osa_get("straggler_boxes", {})
            table.insert(straggler, Room.id)
            osa_set("straggler_boxes", straggler)
        end
    end
end

local function cleanup_target_routine()
    if osa_get("enemy_type", "") == "pirate" then
        dothistimeout("target random", 3, "Could not find|You are now targeting")
        local alive = 0
        for _, npc in ipairs(GameObj.npcs()) do
            if not string.find(npc.status or "", "dead|gone") and
               not string.find(npc.name or "", "animated") then alive = alive + 1 end
        end
        if alive > 0 then fput("say Send them to the bottom boys!") end
    end
    waitrt(); waitcastrt()
    wait_until(function()
        local alive = 0
        for _, npc in ipairs(GameObj.npcs()) do
            if not string.find(npc.status or "", "dead|gone") and
               not string.find(npc.name or "", "animated") then alive = alive + 1 end
        end
        return alive < 1
    end)
    waitrt(); waitcastrt()
    cleanup_loot_routine()
end

local function cleanup_listen_routine()
    if not string.find(Room.title or "", "Enemy Ship") then return end
    waitrt(); waitcastrt()
    local result = dothistimeout("listen", 3, "cleared out all the enemies|listen carefully for any potential threats")
    if result and string.find(result, "cleared out all the enemies") then
        waitrt(); waitcastrt(); osa_set("cleanup_done", true)
    end
end

local function cleanup_pirate_routine()
    cleanup_aoe_routine()
    local result = matchtimeout(5, "slashes with a|lunges forward|flies out of the shadows|is revealed from hiding|boldly accosts|leaps out of|swings .* at you|stumbles slightly|springs from hiding|is forced out of hiding")
    if not result then return end
    waitrt(); waitcastrt()
    if string.find(result, "flies out of the shadows") then cleanup_aoe_routine() end
    cleanup_target_routine()
end

local cleanup_check_for_enemies  -- forward declaration
local commander_end_routine      -- forward declaration

local function cleanup_finished()
    local ctype = osa_get("cleanup_type")
    if not ctype then
        commander_end_routine()
    elseif ctype == "raze" then
        if running("osacombat") then
            Script.kill("osacombat"); wait_while(function() return running("osacombat") end)
        end
        pause(3); enemy_main_deck()
    elseif ctype == "spawn" then
        if running("osacombat") then
            Script.kill("osacombat"); wait_while(function() return running("osacombat") end)
        end
        pause(3); enemy_quarters()
    end
end

cleanup_check_for_enemies = function()
    if not string.find(Room.title or "", "Enemy Ship") then enemy_main_deck() end
    waitrt(); waitcastrt()
    local result = dothistimeout("listen", 3, "cleared out all the enemies|listen carefully for any potential threats")
    if result and string.find(result, "cleared out all the enemies") then
        waitrt(); waitcastrt()
        osa_set("cleanup_done", true)
        echo("Cleanup Completed, The Ship Is Now Safe")
        cleanup_finished(); return
    end
    -- Sweep all ship rooms
    local ship_rooms = osa_get("_cleanup_ship_rooms", {})
    for _, room_tag in ipairs(ship_rooms) do
        Script.run("go2", room_tag); wait_while(function() return running("go2") end)
        cleanup_listen_routine()
        if osa_get("cleanup_done", false) then cleanup_loot_routine(); break end
        if osa_get("enemy_type", "") == "pirate" then cleanup_pirate_routine() end
        cleanup_loot_routine(); cleanup_target_routine()
        if osa_get("cleanup_done", false) then break end
    end
    if not osa_get("cleanup_done", false) then cleanup_check_for_enemies() end
end

local function cleanup_begin_routine()
    osa_set("cleanup_done", false); osa_set("piratehunter", false)
    determine_enemy_type()
    local ship_rooms = {}
    for _, t in ipairs(osa_get("enemy_ship_map", {})) do table.insert(ship_rooms, t) end
    for _, t in ipairs(osa_get("ship_map", {})) do
        if t ~= "captains_quarters" then table.insert(ship_rooms, t) end
    end
    osa_set("_cleanup_ship_rooms", ship_rooms)
    cleanup_check_for_enemies()
end


-------------------------------------------------------------------------------
-- FORMAT HELPERS
-------------------------------------------------------------------------------

local function format_number(n)
    local s = tostring(math.floor(n or 0))
    local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return r
end

local function format_time(seconds)
    seconds = math.floor(seconds or 0)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function format_minutes(min_float)
    return format_time(math.floor((min_float or 0) * 60))
end

local function capitalize_words(s)
    return (s or ""):gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b:lower() end)
end

-------------------------------------------------------------------------------
-- STATS / REPORTING
-------------------------------------------------------------------------------

local function exp_check()
    if GameState.name ~= osa_get("commander", "") then return end
    local h, mh   = GameState.health or 0, GameState.health_max or 0
    local m, mm   = GameState.mana or 0, GameState.mana_max or 0
    local st, ms  = GameState.stamina or 0, GameState.stamina_max or 0
    local sp, msp = GameState.spirit or 0, GameState.spirit_max or 0
    echo("")
    echo(string.format("Your Stats: Health: %d/%d | Mana: %d/%d | Stamina: %d/%d | Spirit: %d/%d",
        h, mh, m, mm, st, ms, sp, msp))
    echo("")
end

local function commander_gemstone_check()
    if GameState.name ~= osa_get("commander", "") then return end
    if KillTracker and KillTracker.weekly_gemstone then
        echo("")
        echo(string.format(
            "    Your Gemstone Stats: Weekly Gemstone: %s | Monthly Gemstones: %s | Weekly Searches: %s",
            tostring(KillTracker.weekly_gemstone or 0),
            tostring(KillTracker.monthly_gemstones or 0),
            tostring(KillTracker.weekly_ascension_searches or 0)))
        echo("")
    end
end

-- forward declarations (implemented in chunk 4)
local commander_spell_up
local commander_broadcast_location

-------------------------------------------------------------------------------
-- NET LAUNCHER
-------------------------------------------------------------------------------

local fire_launcher   -- forward declare (mutual recursion with reel_launcher)
local reel_launcher

reel_launcher = function()
    waitrt()
    local r = dothistimeout("pull net-launcher", 3,
        "crate gets closer!|plopping onto the deck|clicking noise|no reason to pull")
    if r and string.find(r, "crate gets closer!") then
        waitrt(); reel_launcher()
    elseif r and (string.find(r, "plopping onto the deck") or
                  string.find(r, "no reason to pull")) then
        waitrt()
        local has_supply = false
        for _, item in ipairs(GameObj.loot()) do
            if item.name and string.find(item.name, "supply crate") then has_supply = true; break end
        end
        if has_supply then
            fput("take supply crate"); cargo_hold()
            fput("put crate in wood"); fput("put crate in balls")
            pause(1)
            local lh, rh = GameObj.left_hand(), GameObj.right_hand()
            if (lh and lh.noun == "crate") or (rh and rh.noun == "crate") then
                fput("drop supply crate")
            end
            main_deck()
        end
        for _, item in ipairs(GameObj.loot()) do
            if item.name and string.find(item.name, "salvage crate") then
                fput("take salvage crate"); fput("stow salvage crate"); break
            end
        end
        fire_launcher()
    else
        waitrt(); reel_launcher()
    end
end

fire_launcher = function()
    waitrt(); waitcastrt()
    local r = dothistimeout("fire net-launcher", 3,
        "pretend to fire|A clean miss!|A direct hit!|PULL on the crank|%.%.%.")
    if r and (string.find(r, "A clean miss!") or string.find(r, "PULL on the crank")) then
        waitrt(); reel_launcher(); fire_launcher()
    elseif r and string.find(r, "A direct hit!") then
        waitrt(); reel_launcher()
    elseif r and string.find(r, "%.%.%.") then
        waitrt(); fire_launcher()
    end
end

local function check_for_crate()
    waitrt(); main_deck()
    local r = dothistimeout("look ocean", 3,
        "crate floating near enough|Open waters:|Obvious paths:")
    if r and string.find(r, "crate floating near enough") then
        waitrt(); fire_launcher()
    end
end

-------------------------------------------------------------------------------
-- LOOT PIPELINE
-------------------------------------------------------------------------------

local function loot_boxes_on_ground()
    local boxes = {}
    for _, item in ipairs(GameObj.loot()) do
        if is_box(item) then table.insert(boxes, item) end
    end
    return boxes
end

local function commander_loot_silvers()
    local charm_adj  = osa_get("charm_adjective", "")
    local use_charm  = osa_get("fossil_charm", false)
    for _, box in ipairs(loot_boxes_on_ground()) do
        local r
        if use_charm and charm_adj ~= "" then
            r = dothistimeout("point my " .. charm_adj .. " charm at #" .. box.id, 5,
                "You summon a swarm of")
        else
            r = dothistimeout("get coins in #" .. box.id, 5, "You gather the")
        end
        if r then waitrt(); pause(0.5) end
    end
end

local function commander_loot_boxes()
    for _, box in ipairs(loot_boxes_on_ground()) do
        fput("open #" .. box.id)
        local r = dothistimeout("loot #" .. box.id, 5,
            "note some interesting treasure|no loot inside|remove .* which you promptly")
        if r and string.find(r, "note some interesting treasure") then
            waitrt(); pause(0.5)
            Script.run("eloot", "sell")
            wait_while(function() return Script.running("eloot") end)
            fput("loot #" .. box.id)
        elseif r then
            waitrt(); pause(0.5)
        end
    end
end

local function commander_loot_room()
    local r = dothistimeout("loot room", 3,
        "desperate attempt to pick up|discerning eye|There is no loot")
    if r and string.find(r, "desperate attempt") then
        commander_right_hand(); commander_left_hand()
        Script.run("go2", osa_get("gangplank_tag", "myship"))
        wait_while(function() return Script.running("go2") end)
        Script.run("eloot", "sell")
        wait_while(function() return Script.running("eloot") end)
        main_deck(); commander_loot_room()
    elseif r then
        waitrt(); pause(0.5)
    end
end

local function give_boxes_to_security_officer()
    local sec = osa_get("securityofficer", "")
    wait_until(function()
        for _, pc in ipairs(GameObj.pcs()) do
            if pc.name == sec then return true end
        end
        return false
    end)
    for _, box in ipairs(inv_boxes()) do
        fput("get #" .. box.id); fput("drop #" .. box.id)
    end
    lnet_private(sec, "That's All Of Them!")
    waitfor("All Set, Captain!")
    commander_loot_boxes(); commander_loot_silvers(); commander_loot_room()
    waitrt(); pause(0.5)
end

local done_with_sec_off = false

local function commander_yes_boxes()
    commander_right_hand(); commander_left_hand()
    pause(0.5)
    if osa_get("use_security_officer", false) then
        local sec_loc = osa_get("security_officer_location", "")
        Script.run("go2", sec_loc)
        wait_while(function() return Script.running("go2") end)
        give_boxes_to_security_officer()
    elseif osa_get("no_script_picking", false) then
        captains_quarters()
        for _, box in ipairs(inv_boxes()) do
            fput("get #" .. box.id); fput("drop #" .. box.id)
        end
    else
        Script.run("go2", osa_get("gangplank_tag", "myship"))
        wait_while(function() return Script.running("go2") end)
        Script.run("eloot", "pool deposit")
        wait_while(function() return Script.running("eloot") end)
    end
    pause(0.5); main_deck()
end

local function commander_have_boxes()
    done_with_sec_off = false
    local r = dothistimeout("loot room", 3, "There is no loot")
    if r and string.find(r, "There is no loot") then done_with_sec_off = true end
    commander_yes_boxes()
    if not done_with_sec_off then commander_have_boxes() end
end

-------------------------------------------------------------------------------
-- SELL LOOT / CREW SHARE / END-OF-ENCOUNTER
-------------------------------------------------------------------------------

local function commander_go_gangplank()
    local r = dothistimeout("go gangplank", 3,
        "As you approach the|Where are you trying to go|You make your way across")
    if r and string.find(r, "As you approach the") then
        fput("push gangplank"); pause(0.5); move("go gangplank")
    elseif r and string.find(r, "Where are you trying to go") then
        local ship_type = osa_get("commander_ship_type", "sloop")
        fput("go " .. (ship_type:match("^%S+") or ship_type))
    end
end

local function commander_start_handler()
    local lootsack = osa_get("lootsack", "backpack")
    local r = dothistimeout("get salvage crate from my " .. lootsack, 3,
        "Get what|You remove|You grab a|You retrieve|slip your hand")
    if r and string.find(r, "Get what") then
        echo("")
        _respond('<preset id="thought">*** All Out of Crates***</preset>')
        echo(""); return
    elseif r and (string.find(r, "You remove") or string.find(r, "You grab") or
                  string.find(r, "You retrieve") or string.find(r, "slip your hand")) then
        -- fall through to give
    else
        echo(" Hands Are Full, Clear Your Hands Then Type Yes To Continue")
        waitfor("A good positive attitude never hurts")
        commander_start_handler(); return
    end
    local npcs = GameObj.npcs()
    local last_npc = npcs[#npcs]
    if last_npc then
        pause(0.5)
        fput("give salvage crate to " .. last_npc.name)
        pause(0.5)
        fput("give salvage crate to " .. last_npc.name)
        pause(0.5)
        local rh = GameObj.right_hand()
        local box_noun = (rh and rh.noun) or "box"
        fput("open my " .. box_noun)
        fput("look in my " .. box_noun)
        fput("empty my " .. box_noun .. " into my " .. lootsack)
        waitrt(); pause(1)
        fput("throw my " .. box_noun)
    end
    commander_start_handler()
end

local function commander_give_coins()
    lnet_channel("Silvers"); pause(1); fput("depo all")
end

local function commander_check_task()
    local r = dothistimeout("osa task", 3,
        "do not currently have a task|return to the Sea Hag|Abandons your current task|Expedites your current task")
    if r and string.find(r, "do not currently have a task") then
        go_to_handler(); fput("take board"); pause(0.5); captains_quarters()
    elseif r and string.find(r, "return to the Sea Hag") then
        go_to_handler(); fput("turn board"); pause(0.5)
        fput("take board"); pause(0.5); captains_quarters()
    end
end

local function end_of_encounter()
    local ship_name = capitalize_words(osa_get("enemyship", "a pirate ship"))
    local boarding  = format_minutes(osa_get("boardingtime", 0))
    local clearing  = osa_get("clearing_time", "0:00")
    local enemies   = tostring(osa_get("enemy_count", "0"))
    local boxes     = tostring(osa_get("amount_of_boxes", 0))
    local silvers   = format_number(osa_get("endbalance", 0))
    osa_set("endbalancecommas", silvers)
    echo(""); echo(""); echo(""); echo("")
    _respond('<preset id="thought">                             --------------------------------------------------------------------------------</preset>')
    echo("")
    _respond('<preset id="speech">                                      --* Encounter With ' .. ship_name .. ' *--</preset>')
    echo("")
    _respond('<preset id="speech">                                          Time To Board Vessel:</preset>')
    _respond('<preset id="monster">                                          ' .. boarding .. '</preset>')
    echo("")
    _respond('<preset id="speech">                                          Time To Clear Vessel:</preset>')
    _respond('<preset id="monster">                                          ' .. clearing .. '</preset>')
    echo("")
    _respond('<preset id="speech">                                          Total Enemies Defeated This Vessel:</preset>')
    _respond('<preset id="monster">                                          ' .. enemies .. '</preset>')
    echo("")
    _respond('<preset id="speech">                                          Total Boxes Found This Vessel:</preset>')
    _respond('<preset id="monster">                                          ' .. boxes .. '</preset>')
    echo("")
    _respond('<preset id="speech">                                          Total Silver Made This Vessel:</preset>')
    _respond('<preset id="monster">                                          ' .. silvers .. '</preset>')
    echo("")
    _respond('<preset id="thought">                             --------------------------------------------------------------------------------</preset>')
    echo(""); echo(""); echo(""); echo("")
    lnet_channel(string.format(
        "Encounter With %s | Time To Board: %s | Time To Clear: %s | Enemies: %s | Boxes: %s | Silver: %s",
        ship_name, boarding, clearing, enemies, boxes, silvers))
    if osa_get("stowaways", false) then
        fput(string.format(
            'whisper ooc group Encounter: %s | Board: %s | Clear: %s | Enemies: %s | Boxes: %s | Silver: %s',
            ship_name, boarding, clearing, enemies, boxes, silvers))
    end
end

local function commander_crew_share()
    captains_quarters()
    wait_for_crew_tasks()
    commander_check_task()
    local crew = osa_get("crewsize", {})
    if #crew > 0 then
        wait_until(function()
            local pcs = {}
            for _, pc in ipairs(GameObj.pcs()) do pcs[pc.name] = true end
            for _, name in ipairs(crew) do if not pcs[name] then return false end end
            return true
        end)
        lnet_channel("Task Time!")
        wait_for_crew_tasks()
    end
    for _, pc in ipairs(GameObj.pcs()) do fput("hold #" .. pc.id) end
    if osa_get("stowaways", false) then
        fput("whisper group We are about to turn in the salvage crate and share loot, please let me know when you are ready to go.")
        waitfor("A good positive attitude never hurts")
    end
    go_to_handler()
    if osa_get("stowaways", false) then
        fput("whisper group Turn in any completed tasks and get a new one. Then, let me know when you're all set.")
        waitfor("A good positive attitude never hurts")
    end
    fput("stow all"); commander_start_handler()
    Script.run("go2", "bank")
    wait_while(function() return Script.running("go2") end)
    lnet_channel("Silvers"); pause(2); fput("depo all")
    if osa_get("share_silvers", false) then
        fput("depo all")
        after_balance()
        local earned = osa_get("endbalance", 0)
        if earned > 0 then
            fput("withdraw " .. tostring(earned) .. " silver"); pause(0.5)
        end
        fput("share all"); pause(0.5); fput("depo all")
        if osa_get("stowaways", false) then
            fput("whisper group Please deposit your silvers and let me know when you're all set")
            waitfor("A good positive attitude never hurts")
        end
        lnet_channel("Deposit")
    else
        fput("depo all"); after_balance()
    end
    pause(2); captains_quarters()
    spellup_time_left()
    local time_setting = tonumber(osa_get("time_left_setting", 90)) or 90
    if #crew > 1 and (osa_get("waggletimeleft", 999) <= time_setting) then
        commander_spell_up()
    else
        echo(" ------ Average Spell Duration Is Above Setting, Skipping Spellup ------ ")
    end
    end_of_encounter()
    if #crew == 0 then Script.run("osacrew", "repairs") end
end

local function commander_sell_loot()
    begin_balance()
    if osa_get("use_security_officer", false) then
        Script.run("eloot"); wait_while(function() return Script.running("eloot") end)
        local sec     = osa_get("securityofficer", "")
        local sec_loc = osa_get("security_officer_location", "")
        lnet_private(sec, "Your Services Are Requested At " .. sec_loc .. " Crewman")
    end
    commander_have_boxes()
    Script.run("go2", osa_get("gangplank_tag", "myship"))
    wait_while(function() return Script.running("go2") end)
    Script.run("eloot", "sell")
    wait_while(function() return Script.running("eloot") end)
    lnet_channel("Crew, Sell Your Loot!")
    commander_crew_share()
end

-------------------------------------------------------------------------------
-- RAZE / GET-TREASURE PIPELINE
-------------------------------------------------------------------------------

local function get_straggler_boxes()
    for _, room_id in ipairs(osa_get("straggler_boxes", {})) do
        Script.run("go2", tostring(room_id))
        wait_while(function() return Script.running("go2") end)
        for _, box in ipairs(loot_boxes_on_ground()) do
            fput("drag " .. box.name)
            if string.find(Room.title or "", "Enemy") then
                enemy_main_deck()
            else
                main_deck()
            end
            if string.find(Room.title or "", "Enemy") then fput("go gangplank") end
            fput("drag stop")
            Script.run("go2", tostring(room_id))
            wait_while(function() return Script.running("go2") end)
        end
    end
end

local function commander_hands_full()
    enemy_main_deck(); commander_left_hand(); commander_right_hand()
    for _, box in ipairs(inv_boxes()) do
        fput("get #" .. box.id); fput("drop #" .. box.id)
    end
    enemy_quarters()
end

-- forward declare (commander_get_treasure → commander_wait_yell → commander_raze_it → commander_after_raze)
local commander_get_treasure
local commander_wait_yell
local commander_raze_it
local commander_after_raze

commander_after_raze = function()
    waitrt(); helm()
    wait_until(function() return osa_get("sunk_ship", false) end)
    if osa_get("netlauncher", false) then check_for_crate() end
    helm()
    fput("turn wheel port")
    waitfor("drifts steadily toward the .* port")
    lnet_channel("Moored!")
    waitrt(); fput("yell Moored!")
    cargo_hold()
    fput("take supply crate")
    fput("put my crate in wood"); fput("put my crate in balls")
    pause(1)
    local lh, rh = GameObj.left_hand(), GameObj.right_hand()
    if (lh and lh.noun == "crate") or (rh and rh.noun == "crate") then
        fput("drop supply crate")
    end
    local crew = osa_get("crewsize", {})
    if #crew > 0 then
        captains_quarters(); pause(1.5)
        if osa_get("stowaways", false) then
            fput("whisper group I will now sell all the loot and drop our boxes in the locksmith pool. I will return shortly. Please do not depart the ship.")
        end
        fput("disband"); fput("group open"); pause(0.5)
    end
    commander_broadcast_location()
    commander_sell_loot()
end

commander_raze_it = function()
    local r = dothistimeout("raze", 3, "You grab a nearby|Are you sure you|You cannot raze")
    if r and string.find(r, "You grab a nearby") then
        commander_after_raze()
    elseif r and string.find(r, "Are you sure you") then
        commander_raze_it()
    elseif r and string.find(r, "You cannot raze") then
        fput("stow all"); Script.run("osacombat"); pause(3)
        osa_set("cleanup_type", "raze")
        cleanup_begin_routine()
        osa_set("cleanup_type", nil)
        commander_raze_it()
    else
        commander_raze_it()
    end
end

commander_wait_yell = function()
    fput("group open"); enemy_main_deck()
    local boxes = loot_boxes_on_ground()
    osa_set("amount_of_boxes", #boxes)
    for _, box in ipairs(boxes) do
        fput("drag " .. box.name); commander_go_gangplank(); pause(0.5)
    end
    fput("loot room")
    local crew = osa_get("crewsize", {})
    if #crew > 0 then
        captains_quarters(); wait_for_crew_tasks()
        if osa_get("stowaways", false) then
            fput("whisper group Next we will sink the enemy ship, please let me know when you're all set")
            waitfor("A good positive attitude never hurts")
        end
        for _, pc in ipairs(GameObj.pcs()) do fput("hold #" .. pc.id) end
        enemy_main_deck()
    end
    commander_raze_it()
end

commander_get_treasure = function()
    local r = dothistimeout("search pile", 5,
        "You search around in the|Are you sure you would|You take a moment to|How do you plan|You cannot SEARCH")
    if r and (string.find(r, "You search around in the") or string.find(r, "How do you plan")) then
        waitrt()
        local lh, rh = GameObj.left_hand(), GameObj.right_hand()
        if (lh and lh.noun == "crate") or (rh and rh.noun == "crate") then
            fput("stow all"); commander_wait_yell()
        else
            commander_hands_full(); commander_get_treasure()
        end
    elseif r and string.find(r, "Are you sure you would") then
        commander_get_treasure()
    elseif r and string.find(r, "You take a moment to") then
        commander_wait_yell()
    elseif r and string.find(r, "You cannot SEARCH") then
        fput("stow all"); Script.run("osacombat"); pause(3)
        osa_set("cleanup_type", "spawn")
        cleanup_begin_routine()
        osa_set("cleanup_type", nil)
        enemy_quarters(); commander_get_treasure()
    else
        enemy_quarters(); commander_get_treasure()
    end
end

local function commander_prep_it()
    move("down"); fput("drag supply crate"); move("up"); waitrt()
    fput("go gangplank"); fput("go gangplank"); fput("drag supply crate")
    waitrt(); move("down"); waitrt(); fput("drag stop")
    get_straggler_boxes()
    osa_set("straggler_boxes", {})
    enemy_quarters()
    fput("stow set " .. osa_get("lootsack", "backpack"))
    commander_get_treasure()
end

-------------------------------------------------------------------------------
-- AVG SINK TIME / SUNK SHIP
-------------------------------------------------------------------------------

local function avg_sink_time()
    local ship_type = osa_get("enemy_ship_type", "")
    if ship_type == "" then return end
    local key_times = ship_type .. "_sink_times"
    local key_best  = ship_type .. "_best_sink_time"
    local times     = osa_get(key_times, {})
    local sink      = osa_get("sinkingtime", 0)
    table.insert(times, sink)
    while #times > 50 do table.remove(times, 1) end
    osa_set(key_times, times)
    local min_t = times[1] or sink
    for _, t in ipairs(times) do if t < min_t then min_t = t end end
    local best = osa_get(key_best, 9999)
    if best >= min_t then best = min_t; osa_set(key_best, best) end
    osa_set("best_sink_time", best)
    local sum = 0
    for _, t in ipairs(times) do sum = sum + t end
    osa_set("average_sink_time", sum / #times)
end

local function commander_sunk_ship()
    avg_sink_time()
    local ship_name  = capitalize_words(osa_get("enemyship", "a pirate ship"))
    local ship_type  = osa_get("enemy_ship_type", "")
    local sink_t     = format_time(osa_get("sinkingtime", 0))
    local avg_t      = format_time(osa_get("average_sink_time", 0))
    local best_t     = format_time(osa_get("best_sink_time", 0))
    lnet_channel(string.format(
        "Encounter With %s | Time To Sink: %s | Avg Sink (%s): %s | Best Sink (%s): %s",
        ship_name, sink_t, ship_type, avg_t, ship_type, best_t))
    if osa_get("stowaways", false) then
        fput(string.format(
            'whisper ooc group Encounter: %s | Sink: %s | Avg: %s | Best: %s',
            ship_name, sink_t, avg_t, best_t))
    end
    osa_set("cleanup", false); osa_set("piratehunter", false)
    wait_until(function() return osa_get("sunk_ship", false) end)
    if Script.running("osacombat") then
        Script.kill("osacombat")
        wait_while(function() return Script.running("osacombat") end)
    end
    pause(3); lnet_channel("Turn To!")
    if has_significant_wounds() then
        Script.run("eherbs", "--buy=off --mending=on --skipscars=on --yaba=on --potions=on")
        wait_while(function() return Script.running("eherbs") end)
    end
    if has_significant_wounds() then echo("You still have some wounds!") end
    check_for_crate(); captains_quarters(); wait_for_crew_tasks()
    for _, pc in ipairs(GameObj.pcs()) do fput("hold #" .. pc.id) end
    osa_set("cleanup", true); osa_set("piratehunter", true)
    Script.exit()
end

-------------------------------------------------------------------------------
-- COMMANDER END ROUTINE (full implementation)
-------------------------------------------------------------------------------

commander_end_routine = function()
    local clearing_end = os.time()
    osa_set("clearing_end_time", clearing_end)
    if not osa_get("enemyship") then osa_set("enemyship", "a pirate ship") end
    local helmsman_end  = osa_get("helmsman_endtime", clearing_end)
    local clearing_min  = (clearing_end - helmsman_end) / 60.0
    osa_set("clearing_time", format_minutes(clearing_min))
    pause(2)
    local crew = osa_get("crewsize", {})
    if #crew > 0 then lnet_channel("Turn To!"); pause(2) end
    if has_significant_wounds() then
        Script.run("eherbs", "--buy=off --mending=on --skipscars=on --yaba=on --potions=on")
        wait_while(function() return Script.running("eherbs") end)
    end
    if has_significant_wounds() then echo("You still have some wounds, this may inhibit your ability to handle loot!") end
    if Script.running("osacombat") then
        Script.kill("osacombat")
        wait_while(function() return Script.running("osacombat") end)
    end
    enemy_main_deck()
    commander_prep_it()
end


-------------------------------------------------------------------------------
-- SHIP MAP (detect ship type from current room id)
-------------------------------------------------------------------------------

local SHIP_ROOM_RANGES = {
    { lo = 29038, hi = 29042, type = "sloop",      map = {"main_deck","cargo_hold","crows_nest","helm","captains_quarters"} },
    { lo = 30140, hi = 30147, type = "brigantine",  map = {"forward_deck","main_deck","crows_nest","cargo_hold","mess_hall","crew_quarters","helm","captains_quarters"} },
    { lo = 30119, hi = 30127, type = "carrack",     map = {"bow","forward_deck","crows_nest","main_deck","mess_hall","cargo_hold","crew_quarters","helm","captains_quarters"} },
    { lo = 30176, hi = 30186, type = "galleon",     map = {"bow","forward_deck","crows_nest","main_deck","social_room","mess_hall","cargo_hold","crew_quarters","helm","captains_quarters"} },
    { lo = 30166, hi = 30175, type = "frigate",     map = {"bow","forward_deck","crows_nest","main_deck","social_room","mess_hall","cargo_hold","crew_quarters","helm","captains_quarters"} },
    { lo = 30128, hi = 30139, type = "man o' war",  map = {"bow","forward_crows_nest","forward_deck","mid_deck","crows_nest","main_deck","social_room","mess_hall","cargo_hold","crew_quarters","helm","captains_quarters"} },
}

local function detect_ship_map()
    local id = tonumber(Room.id) or 0
    for _, entry in ipairs(SHIP_ROOM_RANGES) do
        if id >= entry.lo and id <= entry.hi then
            osa_set("ship_type",  entry.type)
            osa_set("ship_map",   entry.map)
            return
        end
    end
end

-------------------------------------------------------------------------------
-- BROADCAST LOCATION (simplified — no Room.wayto mutations)
-------------------------------------------------------------------------------

commander_broadcast_location = function()
    main_deck()
    fput("push gangplank")
    -- Look at the ocean to find docking room
    local r = dothistimeout("look ocean", 3, "Open waters:|Obvious paths:|%([0-9]+%)")
    local loc_title = Room.title or ""
    local loc_city  = Room.location or ""
    local room_id   = Room.id or "?"
    lnet_channel(string.format(
        "The Ship Is Now Moored In %s. Room Number: %s %s",
        loc_city, room_id, loc_title))
    -- Store gangplank room id for navigation
    osa_set("gangplank_id",  room_id)
    osa_set("gangplank_tag", "myship")
end

-------------------------------------------------------------------------------
-- HELMSMAN / NAVIGATOR / BOARDING
-------------------------------------------------------------------------------

local warning_given = false

local function commander_final_approach()
    wait_while(function()
        for _, pc in ipairs(GameObj.pcs()) do
            if pc.status and string.find(pc.status, "sitting|lying|prone|stunned") then return true end
        end
        return false
    end)
    main_deck()
    waitfor("collide against your")
    wait_while(function()
        for _, pc in ipairs(GameObj.pcs()) do
            if pc.status and string.find(pc.status, "sitting|lying|prone|stunned") then return true end
        end
        return false
    end)
    enemy_main_deck()
    local now = os.time()
    osa_set("helmsman_endtime", now)
    local board_min = (now - (osa_get("helmsman_start_time", now))) / 60.0
    osa_set("boardingtime", board_min)
end

local function commander_final_approach_2()
    wait_while(function()
        for _, pc in ipairs(GameObj.pcs()) do
            if pc.status and string.find(pc.status, "sitting|lying|prone|stunned") then return true end
        end
        return false
    end)
    enemy_main_deck()
    local now = os.time()
    osa_set("helmsman_endtime", now)
    local board_min = (now - (osa_get("helmsman_start_time", now))) / 60.0
    osa_set("boardingtime", board_min)
end

local function commander_helmsman()
    waitrt(); waitcastrt()
    wait_until(function()
        return not (Effects and Effects.Debuffs and
            (Effects.Debuffs.active("Stunned") or Effects.Debuffs.active("Webbed") or Effects.Debuffs.active("Bound")))
    end)
    local r = dothistimeout("turn wheel ship", 600,
        "The sides of the .* collide against your|in boarding range!|You will be upon the|Tenebrous Cauldron")
    if r and (string.find(r, "in boarding range!") or string.find(r, "You will be upon the")) then
        if warning_given then commander_final_approach() end
        waitrt(); pause(0.5)
        lnet_channel("Thirty second warning, drop what yer doing and prepare for battle. Here they come!")
        fput("yell Thirty second warning, drop what yer doing and prepare for battle. Here they come!")
        warning_given = true
        fput("group open")
        commander_final_approach()
    elseif r and string.find(r, "Tenebrous Cauldron") then
        commander_sunk_ship()
    elseif r and string.find(r, "The sides of the .* collide against your") then
        commander_final_approach_2()
    end
end

local function commander_navigator()
    waitrt(); waitcastrt()
    wait_until(function()
        return not (Effects and Effects.Debuffs and
            (Effects.Debuffs.active("Stunned") or Effects.Debuffs.active("Webbed") or Effects.Debuffs.active("Bound")))
    end)
    if not osa_get("boarding", false) then
        commander_sunk_ship(); return
    end
    local r = dothistimeout("turn wheel ship", 20,
        "You will be upon the|of boarding range!|The sides of the .* collide against your|in boarding range!|ways out!|sailing closer!|%.%.%.")
    if r and (string.find(r, "of boarding range!") or string.find(r, "ways out!") or string.find(r, "sailing closer!")) then
        commander_navigator()
    elseif r and string.find(r, "%.%.%.") then
        commander_navigator()
    elseif r and (string.find(r, "in boarding range!") or string.find(r, "You will be upon the")) then
        if warning_given then commander_final_approach() end
        waitrt(); warning_given = true
        fput("group open"); fput("turn wheel ship"); waitrt(); pause(0.5)
        lnet_channel("Thirty second warning, drop what yer doing and prepare for battle. Here they come!")
        fput("yell Thirty second warning, drop what yer doing and prepare for battle. Here they come!")
        commander_final_approach()
    elseif r and string.find(r, "The sides of the .* collide against your") then
        commander_final_approach_2()
    else
        commander_navigator()
    end
end

local function enemy_counter()
    local r = dothistimeout("listen", 10, "Enemies Left: ")
    if r then
        local n = r:match("Enemies Left: (.*%])")
        if n then osa_set("enemy_count", n) end
    end
end

local function commander_check_role()
    osa_set("boarding",   true)
    osa_set("sunk_ship",  false)
    warning_given = false
    if osa_get("helmsman_enabled", false) then
        commander_navigator()
    else
        commander_helmsman()
    end
end

-------------------------------------------------------------------------------
-- SHIP INFO / HANDLER / BOARD / START
-------------------------------------------------------------------------------

local function commander_ship_info()
    local ship_type = osa_get("commander_ship_type", "sloop")
    local r = dothistimeout("ship info " .. ship_type, 3, "Ship Name:|Captain")
    if r then
        local name = r:match('Ship Name: (.*) Ship Status')
        if name then
            osa_set("commander_ship_name", name:gsub('[",]', ''):gsub('%s+$', ''))
        end
        local gp = r:match("Gangplank Material: (.*) Gangplank Color:")
        if gp then
            gp = gp:gsub('[",]', ''):gsub('%s+$', '')
            if gp == "Not Set" then
                osa_set("commander_gangplank", "slender gangplank")
            else
                osa_set("commander_gangplank", gp .. " gangplank")
            end
        end
    end
    -- Check navigator role
    local role_r = dothistimeout("osa role", 3, "Current Role:|Navigator")
    if role_r then
        local role = role_r:match("Current Role: (.*) Active Bonuses")
        local rank = role_r:match("Navigator.*Rank: (.*) Total Experience")
        if role then role = role:gsub('[",%s]+$', '') end
        if rank then rank = rank:gsub('[",%s]+$', '') end
        if role == "Navigator" and (rank == "Veteran" or rank == "Master") then
            osa_set("helmsman_enabled", true)
        else
            osa_set("helmsman_enabled", false)
        end
    end
    echo("Checking Command Information"); pause(0.15)
    echo("."); pause(0.25); echo(".."); pause(0.35)
    echo("... Command Information Saved"); echo("")
end

local function commander_check_handler()
    local ship_type = osa_get("commander_ship_type", "sloop")
    local npcs = GameObj.npcs()
    local last_npc = npcs[#npcs]
    if not last_npc then return end
    local r = dothistimeout("ask " .. last_npc.name .. " about ret " .. ship_type, 3,
        "Looks like we have some space around the")
    if r then
        local loc = r:match("Looks like we have some space around the (.*)[.]")
        if loc then
            local pier_ids = PIER_MAPS[loc]
            if pier_ids then
                osa_set("pier_map", pier_ids)
            else
                -- fuzzy match
                for pier_name, ids in pairs(PIER_MAPS) do
                    if string.find(loc, pier_name:match("^%S+") or pier_name) then
                        osa_set("pier_map", ids); break
                    end
                end
            end
        end
    end
end

local function commander_board_ship()
    detect_ship_map()
    crows_nest()
    fput("ship flag black")
    local crew = osa_get("crewsize", {})
    if #crew > 0 then call_muster() end
    if #crew > 0 then
        -- commander_get_underway (defined below, called via forward-ref)
        waitrt(); waitcastrt()
        lnet_channel("All Hands Make Ready To Get Underway!")
        fput("yell All Hands Make Preparations For Getting Underway!")
        pause(2); waitrt(); waitcastrt()
        echo("Raising Anchor"); helm(); raise_anchor(); waitrt()
        if osa_get("anchor_aweigh", false) then
            fput("yell Anchor's Aweigh!")
            osa_set("anchor_aweigh", false)
        end
        captains_quarters(); wait_for_crew_tasks()
        if (GameState.mana_pct or 100) <= 84 then
            echo(" ----------- Waiting For Mana -----------")
            wait_until(function() return (GameState.mana_pct or 100) >= 85 end)
        end
        for _, pc in ipairs(GameObj.pcs()) do fput("hold #" .. pc.id) end
        fput("depart"); fput("depart")
        lnet_channel("Underway!"); fput("yell Underway!")
    else
        -- solo underway
        fput("yell Underway!")
        captains_quarters()
        if (GameState.mana_pct or 100) <= 84 then
            echo(" ----------- Waiting For Mana -----------")
            wait_until(function() return (GameState.mana_pct or 100) >= 85 end)
        end
    end
    waitrt()
end

local function commander_start_up()
    local crew = osa_get("crewsize", {})
    if #crew > 0 then call_muster() end
    for _, name in ipairs(osa_get("crewsize", {})) do fput("hold " .. name) end
    Script.run("go2", "bank")
    wait_while(function() return Script.running("go2") end)
    local ship_costs = {
        ["sloop"]       = 5000,
        ["brigantine"]  = 7500,
        ["carrack"]     = 7500,
        ["galleon"]     = 10000,
        ["frigate"]     = 10000,
        ["man o' war"]  = 12500,
    }
    local ship_type = osa_get("commander_ship_type", "sloop")
    local cost = ship_costs[ship_type] or 5000
    fput("withdraw " .. tostring(cost) .. " sil")
    go_to_handler()
    pause(0.5)
    commander_check_handler()
    local pier_map = osa_get("pier_map", {})
    local found_ship = false
    local ship_name = osa_get("commander_ship_name", "")
    for _, pier_id in ipairs(pier_map) do
        waitrt()
        Script.run("go2", tostring(pier_id))
        wait_while(function() return Script.running("go2") end)
        for _, item in ipairs(GameObj.loot()) do
            if item.name and string.find(item.name, ship_type) then
                local look_cmd = ship_type == "man o' war" and "look man" or ("look " .. ship_type)
                fput(look_cmd)
                local tr = matchtimeout(3, "Sprawling across the back of the")
                if tr then
                    local found_name = tr:match('it reads, "(.+)"')
                    if found_name and found_name == ship_name then
                        found_ship = true; break
                    end
                end
            end
        end
        if found_ship then break end
    end
    if not found_ship then
        echo("The Ship Isn't Here, Something Went Wrong, Restart")
        Script.exit(); return
    end
    commander_board_ship()
end

-------------------------------------------------------------------------------
-- SPELL UP
-------------------------------------------------------------------------------

commander_spell_up = function()
    call_muster()
    local med_off = osa_get("medical_officer", "")
    if med_off ~= "" and osa_get("use_bread", false) then
        lnet_channel("Let Us Break Bread Together!")
        waitfor("Bread Is Served!")
        pause(1)
    end
    lnet_channel("Does Anyone Need Armor Adjustments?"); pause(4)
    lnet_channel("Spells")
    -- Check mana spellup availability
    local mana_spellup_ok = false
    if osa_get("mana_spellup", false) then
        local mana_r = dothistimeout("mana", 3, "You have used the MANA SPELLUP ability")
        if mana_r then
            local used, total = mana_r:match("ability (%d+) out of (%d+) times")
            if used and total and tonumber(total) > 0 and tonumber(used) < tonumber(total) then
                mana_spellup_ok = true
            end
        end
        if mana_spellup_ok then
            spellup_time_left()
            if osa_get("waggletimeleft", 999) <= 90 then
                waitrt(); waitcastrt(); pause(0.2); fput("mana spellup")
            end
        end
    end
    -- Ewaggle spellup
    local group_spellup = osa_get("groupspellup", false)
    local self_spellup  = osa_get("selfspellup", false)
    if group_spellup then
        determine_group_members()
        local group_str = table.concat(osa_get("everyone_in_my_group", {}), " ")
        if self_spellup then
            Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. group_str .. " self")
        else
            Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. group_str)
        end
    elseif self_spellup then
        Script.run("ewaggle", "--start-at=181 --stop-at=240 self")
    end
    need_mana()
    wait_for_crew_tasks()
    wait_while(function() return Script.running("ewaggle") end)
    if osa_get("armor_specs", false) then
        commander_apply_support()
    end
    commander_self_armor_spec()
    pause(5); fput("group open")
    for _, name in ipairs(osa_get("crewsize", {})) do fput("hold " .. name) end
    lnet_channel("Spell Up Completed")
end

-------------------------------------------------------------------------------
-- CREW DISPLAY / MUSTER / ROGER / CREW MENU
-------------------------------------------------------------------------------

local function commander_muster_up()
    local crew = osa_get("crewsize", {})
    if not crew or #crew == 0 then
        echo("\n      You Have Not Built A Ships Roster Yet!\n       Please Call A Muster Then Try Again\n"); return
    end
    local pcs = {}
    for _, pc in ipairs(GameObj.pcs()) do pcs[pc.name] = true end
    local non_crew = {}
    for name, _ in pairs(pcs) do
        local is_crew = false
        for _, cm in ipairs(crew) do if cm == name then is_crew = true; break end end
        if not is_crew then table.insert(non_crew, name) end
    end
    if #non_crew > 0 then
        echo("\n      The Following People Present Are Not Part Of The Crew:\n")
        for _, n in ipairs(non_crew) do echo("        " .. n) end
        echo("")
    else
        echo("\n      All Present Adventurers Are Members Of The Crew!\n")
    end
end

local function commander_roger_up()
    local crew = osa_get("crewsize", {})
    if not crew or #crew == 0 then
        echo("\n      You Have Not Built A Ships Roster Yet!\n       Please Call A Muster Then Try Again\n"); return
    end
    -- taskcount would be tracked by wait_for_crew_tasks; display who responded
    echo("\n      Roger Up check — use ;osacommander task count for details\n")
end

local function commander_crew_menu(args)
    local sub = args and args[1] and args[1]:lower() or ""
    if sub == "" then
        echo([[
        Please Select A Valid Option:
            Login:   Logs In All Of Your Personal Crew
            Add:     Adds A Crew Member's Name To Your Personal Crew
            Delete:  Deletes A Crew Member From Your Personal Crew
            Clear:   Clears Your Personal Crew
            Display: Displays Your Personal Crew]])
        return
    end
    local roster = osa_get("roster", {})
    if sub == "login" then
        echo("\n            Login Sequence Initiated...\n")
        Script.run("elogin", "set realm prime")
        wait_while(function() return Script.running("elogin") end)
        for _, n in ipairs(roster) do
            echo("Logging In " .. n)
            Script.run("elogin", n)
            wait_while(function() return Script.running("elogin") end)
            pause(15)
        end
        echo("\n            Login Complete Captain!\n")
    elseif sub == "add" and args[2] then
        local name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
        echo("\n                Saving " .. name .. " To Your Personal Crew!\n")
        local found = false
        for _, n in ipairs(roster) do if n == name then found = true; break end end
        if not found then table.insert(roster, name); osa_set("roster", roster) end
    elseif sub == "delete" and args[2] then
        local name = args[2]:sub(1,1):upper() .. args[2]:sub(2):lower()
        echo("\n                Removing " .. name .. " From Your Personal Crew!\n")
        for i, n in ipairs(roster) do
            if n == name then table.remove(roster, i); osa_set("roster", roster); break end
        end
    elseif sub == "clear" then
        echo("\n                Clearing Your Personal Crew!\n")
        osa_set("roster", {})
    elseif sub == "display" then
        echo("\n                Your Personal Crew Includes:\n")
        for _, n in ipairs(roster) do echo("        " .. n) end
        echo("")
    end
end

-------------------------------------------------------------------------------
-- TOGGLE HELPERS
-------------------------------------------------------------------------------

local function ph_on()
    if not osa_get("piratehunter", false) then
        osa_set("piratehunter", true)
        echo("    *===============================================================================*")
        echo("    |                    *****Enemy Ship Detection Enabled*****                     |")
        echo("    *===============================================================================*")
    else echo("    Enemy Detection Already Enabled") end
end

local function ph_off()
    if osa_get("piratehunter", false) then
        osa_set("piratehunter", false)
        echo("    *===============================================================================*")
        echo("    |                    *****Enemy Ship Detection Disabled*****                    |")
        echo("    *===============================================================================*")
    else echo("    Enemy Detection Already Disabled") end
end

local function scripted_crew_on()
    if not osa_get("othersailors", false) then
        osa_set("othersailors", true)
        echo("    *===============================================================================*")
        echo("    |             *****You Are Now Accepting Outside Scripted Crew*****             |")
        echo("    *===============================================================================*")
    else echo("    Scripted Crew Is Enabled") end
end

local function scripted_crew_off()
    if osa_get("othersailors", false) then
        osa_set("othersailors", false)
        echo("    *===============================================================================*")
        echo("    |          *****You Are No Longer Accepting Outside Scripted Crew*****          |")
        echo("    *===============================================================================*")
    else echo("    Scripted Crew Is Disabled") end
end

local function anti_poaching_on()
    if not osa_get("check_for_group", false) then
        osa_set("check_for_group", true)
        lnet_channel("Disable Poaching!")
        echo("    *===========================================================*")
        echo("    |             *****Anti-Poaching Enabled*****               |")
        echo("    *===========================================================*")
    else echo("    Anti-Poaching Already Enabled") end
end

local function anti_poaching_off()
    if osa_get("check_for_group", false) then
        osa_set("check_for_group", false)
        lnet_channel("Enable Poaching!")
        echo("    *===========================================================*")
        echo("    |             *****Anti-Poaching Disabled*****              |")
        echo("    *===========================================================*")
    else echo("    Anti-Poaching Already Disabled") end
end

local function no_script_on()
    if not osa_get("stowaways", false) then
        osa_set("stowaways", true)
        echo("    *===============================================================================*")
        echo("    |                 *****Non-Scripting Guest Mode Enabled*****                    |")
        echo("    *===============================================================================*")
    else echo("    Non-Scripting Guest Mode Already Enabled") end
end

local function no_script_off()
    if osa_get("stowaways", false) then
        osa_set("stowaways", false)
        echo("    *===============================================================================*")
        echo("    |                 *****Non-Scripting Guest Mode Disabled*****                   |")
        echo("    *===============================================================================*")
    else echo("    Non-Scripting Guest Mode Already Disabled") end
end

local function cleanup_on()
    if not osa_get("cleanup", false) then
        osa_set("cleanup", true)
        echo("    *===============================================================================*")
        echo("    |               *****You Are Now Looking For Stragglers*****                    |")
        echo("    *===============================================================================*")
    else echo("    Cleanup Is Enabled") end
end

local function cleanup_off()
    if osa_get("cleanup", false) then
        osa_set("cleanup", false)
        echo("    *===============================================================================*")
        echo("    |             *****You Are No Longer Looking For Stragglers*****                |")
        echo("    *===============================================================================*")
    else echo("    Clean Up Is Disabled") end
end

-------------------------------------------------------------------------------
-- SETTINGS DISPLAY / HELP
-------------------------------------------------------------------------------

local function crew_display_settings()
    echo("")
    echo("  ========================================= OSA Commander Settings =========================================")
    echo("")
    echo(string.format("  Crew Channel:         %s",  osa_get("crew", "")))
    echo(string.format("  Commander:            %s",  osa_get("commander", "")))
    echo(string.format("  Ship Type:            %s",  osa_get("commander_ship_type", "")))
    echo(string.format("  Ship Name:            %s",  osa_get("commander_ship_name", "")))
    echo(string.format("  Loot Sack:            %s",  osa_get("lootsack", "")))
    echo(string.format("  Pirate Hunter:        %s",  tostring(osa_get("piratehunter", false))))
    echo(string.format("  Cleanup:              %s",  tostring(osa_get("cleanup", false))))
    echo(string.format("  Stowaways:            %s",  tostring(osa_get("stowaways", false))))
    echo(string.format("  Share Silvers:        %s",  tostring(osa_get("share_silvers", false))))
    echo(string.format("  Group Spellup:        %s",  tostring(osa_get("groupspellup", false))))
    echo(string.format("  Need Bless:           %s",  tostring(osa_get("needbless", false))))
    echo(string.format("  Give Bless:           %s",  tostring(osa_get("givebless", false))))
    echo(string.format("  Stealth Disabler:     %s",  tostring(osa_get("stealth_disabler", 0))))
    echo(string.format("  Board Types:          Sloop=%s Brig=%s Carrack=%s Galleon=%s Frigate=%s ManOWar=%s",
        tostring(osa_get("board_sloop", false)),
        tostring(osa_get("board_brigantine", false)),
        tostring(osa_get("board_carrack", false)),
        tostring(osa_get("board_galleon", false)),
        tostring(osa_get("board_frigate", false)),
        tostring(osa_get("board_man", false))))
    echo("")
end

local function commander_help_display()
    echo("")
    echo("  ╔══════════════════════════════════════════════════════════════════════╗")
    echo("  ║              OSACommander v" .. SCRIPT_VERSION .. " by Peggyanne                     ║")
    echo("  ╚══════════════════════════════════════════════════════════════════════╝")
    echo("")
    echo("  ;osacommander start             Begin encounter — helm, detect, engage")
    echo("  ;osacommander begin             Go to bank, find ship at pier, board")
    echo("  ;osacommander info <shiptype>   Save ship info (sloop/brig/carrack/gal/fri/man)")
    echo("  ;osacommander helmsman          Start helmsman loop (navigate + counter)")
    echo("  ;osacommander end               Run end-of-encounter loot pipeline")
    echo("  ;osacommander spells            Commander spell-up sequence")
    echo("  ;osacommander spellup [name]    Crew spellup broadcast / mana spellup")
    echo("  ;osacommander muster            Take roll call; 'muster count' = check roster")
    echo("  ;osacommander muster count      Show who is present but not on roster")
    echo("  ;osacommander task              Broadcast 'Task Time!'; 'task count' = roger check")
    echo("  ;osacommander bless             Run bless protocol")
    echo("  ;osacommander summon            Broadcast room id to crew")
    echo("  ;osacommander broadcast         Broadcast moored location")
    echo("  ;osacommander silvers           Deposit silvers and broadcast")
    echo("  ;osacommander stop              Stop all active loops")
    echo("  ;osacommander pause/unpause     Pause/unpause osacombat")
    echo("  ;osacommander status            Status report")
    echo("  ;osacommander gemstone          Gemstone report")
    echo("  ;osacommander combat [name]     Start osacombat / 'Steel Yourself' broadcast")
    echo("  ;osacommander loot [name]       Enable looter / 'Loot the Dead' broadcast")
    echo("  ;osacommander cleanup [on/off]  Enable/disable straggler cleanup; blank=begin sweep")
    echo("  ;osacommander detection on/off  Enable/disable enemy ship detection")
    echo("  ;osacommander noscript on/off   Enable/disable non-scripting guest mode")
    echo("  ;osacommander poaching on/off   Enable/disable anti-poaching")
    echo("  ;osacommander scripted on/off   Enable/disable outside scripted crew")
    echo("  ;osacommander crew <sub>        Manage personal crew roster (login/add/delete/clear/display)")
    echo("  ;osacommander muster [count]    Ships muster / roster check")
    echo("  ;osacommander kick/unkick <n>   Broadcast crew discipline messages")
    echo("  ;osacommander reset             Reset osacrew script")
    echo("  ;osacommander underway          Get underway sequence")
    echo("  ;osacommander return            Return to port and moor")
    echo("  ;osacommander repairs           Broadcast make repairs")
    echo("  ;osacommander settings          Display all current settings")
    echo("  ;osacommander version           Show script version")
    echo("")
end

-------------------------------------------------------------------------------
-- INTERACTIVE SETUP (CLI replacement for GTK UI)
-------------------------------------------------------------------------------

local function commander_setup()
    local function ask(prompt, default)
        echo(prompt .. (default ~= "" and (" [" .. default .. "]") or "") .. ": ")
        local ans = matchtimeout(120, ".*")
        if ans and ans ~= "" then return ans else return default end
    end
    echo("\n  === OSACommander Setup ===\n")
    local crew_ch  = ask("LNet crew channel name", osa_get("crew", ""))
    local cmd_name = ask("Commander character name", osa_get("commander", GameState.name or ""))
    local lootsack = ask("Loot sack noun (e.g. pack, backpack)", osa_get("lootsack", "backpack"))
    local ship_t   = ask("Ship type (sloop/brigantine/carrack/galleon/frigate/man o' war)", osa_get("commander_ship_type", "sloop"))
    osa_set("crew",                crew_ch)
    osa_set("commander",           cmd_name)
    osa_set("lootsack",            lootsack)
    osa_set("commander_ship_type", ship_t)
    save_settings()
    echo("\n  Settings saved. Run ;osacommander info <shiptype> to cache ship name.\n")
end

-------------------------------------------------------------------------------
-- MAIN DISPATCHER
-------------------------------------------------------------------------------

local function commander_begin_it(args)
    local cmd  = (args[1] or ""):lower()
    local sub  = (args[2] or ""):lower()
    local arg3 = args[3] or ""

    if cmd == "start" then
        osa_set("straggler_boxes", {})
        helm(); determine_enemy_type(); determine_to_engage()
        if osa_get("engage", false) then
            local no_bless = osa_get("no_bless", false)
            local etype    = osa_get("enemy_type", "")
            if etype ~= "undead" and no_bless then
                local crew = osa_get("crewsize", {})
                if #crew == 0 then
                    get_self_bless()
                    if osa_get("stowaways", false) then
                        fput("whisper group If you need any weapon blesses, speak now then let me know when you're all set")
                        waitfor("A good positive attitude never hurts")
                    end
                else
                    begin_bless()
                    if osa_get("stowaways", false) then
                        fput("whisper group If you need any weapon blesses, speak now then let me know when you're all set")
                        waitfor("A good positive attitude never hurts")
                    end
                    pause(1)
                end
            end
            vessel_messaging(osa_get("enemy_type", ""))
            cleanup_on()
            if osa_get("cannon_engage", false) then
                lnet_channel("Enemy Vessel Detected, " .. capitalize_words(osa_get("enemyship", "")) ..
                    " Inbound. Sound General Quarters! Gunners Man Your Irons!")
            else
                lnet_channel("Enemy Vessel Detected, " .. capitalize_words(osa_get("enemyship", "")) ..
                    " Inbound. Sound General Quarters!")
            end
            osa_set("helmsman_start_time", os.time())
            if not Script.running("osacombat") then
                Script.run("osacombat"); pause(3); wait_rt(); pause(0.1)
            end
            detect_ship_map(); helm()
            commander_check_role()
            enemy_counter()
        else
            lnet_channel("Crew, We Do Not Have Authorization To Engage This Vessel!")
            helm(); fput("turn wheel port")
            waitfor("drifts steadily toward the .* port")
            local crew = osa_get("crewsize", {})
            if #crew > 0 then call_muster() end
            if #crew > 0 then commander_board_ship() end
        end

    elseif cmd == "begin" then
        commander_start_up()

    elseif cmd == "info" then
        local ship = sub
        local max_crew_map = {
            slo=2, bri=4, car=7, gal=11, fri=13, man=19
        }
        local full_map = {
            slo="sloop", bri="brigantine", car="carrack",
            gal="galleon", fri="frigate", man="man o' war"
        }
        local matched = nil
        for abbr, full in pairs(full_map) do
            if ship:find(abbr) then matched = full; break end
        end
        if matched then
            osa_set("commander_ship_type", matched)
            for abbr, max in pairs(max_crew_map) do
                if ship:find(abbr) then osa_set("commander_max_crew", max); break end
            end
            commander_ship_info()
        else
            echo("Please Select A Valid Ship Type: Sloop, Brigantine, Carrack, Galleon, Frigate or Man O' War")
        end

    elseif cmd == "helmsman" then
        osa_set("helmsman_start_time", os.time())
        commander_check_role(); enemy_counter()

    elseif cmd == "end" then
        commander_end_routine()

    elseif cmd == "silvers" then
        commander_give_coins()

    elseif cmd == "version" then
        echo("OSACommander Version " .. SCRIPT_VERSION)

    elseif cmd == "stop" then
        lnet_channel("Stop")
        osa_set("cleanup",    false)
        osa_set("piratehunter", false)
        osa_set("boarding",   false)
        osa_set("sunk_ship",  false)
        if Script.running("osacombat") then
            Script.kill("osacombat")
            wait_while(function() return Script.running("osacombat") end)
        end

    elseif cmd == "spells" then
        commander_spell_up()

    elseif cmd == "spellup" then
        if sub ~= "" then
            lnet_channel("Crew, Spell Up " .. sub:sub(1,1):upper() .. sub:sub(2) .. ".")
            if osa_get("groupspellup", false) and not Feat.known("Kroderine Soul") then
                Script.run("ewaggle", "--start-at=181 --stop-at=240 " .. sub)
                need_mana()
            end
        else
            lnet_channel("Mana Spellup")
            local prof = GameState.profession or ""
            if prof ~= "Warrior" and prof ~= "Rogue" then fput("mana spellup") end
        end

    elseif cmd == "exit" then
        if Room.location == "Ships" then
            main_deck(); fput("push gangplank"); move("go gangplank")
        end
        local ship_name = osa_get("commander_ship_name", "")
        fput("recite " .. ship_name .. "!;Attention To Quarters!")
        pause(1.5); fput("snap attention"); pause(1.5)
        fput("salute"); fput("recite Post!"); pause(3); fput("exit")

    elseif cmd == "repairs" then
        lnet_channel("Make Repairs!")

    elseif cmd == "status" then
        lnet_channel("Status Report")
        exp_check()

    elseif cmd == "resource" then
        lnet_channel("Resource Report")

    elseif cmd == "gemstone" then
        lnet_channel("Gemstone Report")
        commander_gemstone_check()

    elseif cmd == "bread" then
        lnet_channel("Let Us Break Bread Together!")

    elseif cmd == "detection" then
        if sub == "on" then ph_on() elseif sub == "off" then ph_off() end

    elseif cmd == "noscript" then
        if sub == "on" then no_script_on() elseif sub == "off" then no_script_off() end

    elseif cmd == "poaching" then
        if sub == "on" then anti_poaching_off() elseif sub == "off" then anti_poaching_on() end

    elseif cmd == "scripted" then
        if sub == "on" then scripted_crew_on() elseif sub == "off" then scripted_crew_off() end

    elseif cmd == "cleanup" then
        if sub == "on" then cleanup_on()
        elseif sub == "off" then cleanup_off()
        else cleanup_begin_routine() end

    elseif cmd == "unkick" then
        if sub ~= "" then lnet_channel("Crewman " .. sub:sub(1,1):upper() .. sub:sub(2) .. ", Quarterdeck!") end

    elseif cmd == "kick" then
        if sub ~= "" then lnet_channel("Lay Below Crewman " .. sub:sub(1,1):upper() .. sub:sub(2) .. "!") end

    elseif cmd == "reset" then
        osa_set("logging", true)
        if Script.running("osacrew") then
            Script.kill("osacrew")
            wait_while(function() return Script.running("osacrew") end)
        end
        Script.run("osacrew")
        lnet_channel("Reset"); pause(2)
        osa_set("logging", false)

    elseif cmd == "task" then
        if sub == "" then
            lnet_channel("Task Time!")
        elseif sub:find("cou") then
            commander_roger_up()
        else
            echo([[
        Please Select A Valid Task Option:
            Count:     Will Determine Who Hasn't Rogered Up
            No Option: Will Call For The Crew To Get A Task]])
        end

    elseif cmd == "summon" then
        fput("group open")
        if sub == "force" then
            lnet_channel("Crew, Report To: " .. tostring(Room.id))
        else
            local crew = osa_get("crewsize", {})
            local pcs  = {}
            for _, pc in ipairs(GameObj.pcs()) do pcs[pc.name] = true end
            local missing = false
            for _, name in ipairs(crew) do if not pcs[name] then missing = true; break end end
            if missing then
                lnet_channel("Crew, Report To: " .. tostring(Room.id))
            else
                echo("\n--- Everyone Present, Skipping Summon\n")
            end
        end

    elseif cmd == "bless" then
        begin_bless()

    elseif cmd == "unpause" then
        lnet_channel("Unpause")
        if Script.running("osacombat") then Script.unpause("osacombat") end

    elseif cmd == "pause" then
        lnet_channel("Pause")
        if Script.running("osacombat") then Script.pause("osacombat") end

    elseif cmd == "muster" then
        if sub == "" then
            osa_set("crewsize", {})
            lnet_channel("Quarters! All Hands To Quarters For Muster, Instruction and Inspection!")
            take_muster()
            local n = #osa_get("crewsize", {})
            lnet_channel(string.format(
                "All Present And Accounted For! We Have %d Crew Onboard For A Total Compliment of %d Personnel!",
                n, n + 1))
            pause(3)
        elseif sub:find("cou") then
            commander_muster_up()
        else
            echo("Please Select A Valid Muster Option: Count or No Option")
        end

    elseif cmd == "crew" then
        commander_crew_menu({sub, arg3})

    elseif cmd == "broadcast" then
        commander_broadcast_location()

    elseif cmd == "testcon" then
        if sub ~= "" then lnet_channel("Connection Test: " .. sub:sub(1,1):upper() .. sub:sub(2)) end

    elseif cmd == "checkversion" then
        lnet_channel("Current Version: Commander " .. SCRIPT_VERSION)

    elseif cmd == "combat" then
        if sub == "" then
            lnet_channel("Steel Yourselves Crew!"); Script.run("osacombat")
        else
            lnet_channel("Steel Yourself, " .. sub:sub(1,1):upper() .. sub:sub(2) .. "!")
        end

    elseif cmd == "loot" then
        if sub == "" then
            osa_set("osalooter", true)
        else
            lnet_channel("Loot the Dead, " .. sub:sub(1,1):upper() .. sub:sub(2) .. "!")
        end

    elseif cmd == "sell" then
        lnet_channel("Crew, Sell Your Loot!")

    elseif cmd == "setup" then
        commander_setup()

    elseif cmd == "return" then
        ph_off(); helm(); wait_rt()
        fput("turn wheel port")
        waitfor("drifts steadily toward the .* port")
        lnet_channel("Moored!"); waitrt(); fput("yell Moored!")
        commander_broadcast_location(); captains_quarters()

    elseif cmd == "underway" then
        local crew = osa_get("crewsize", {})
        if #crew > 0 then call_muster() end
        osa_set("boarding",  false); osa_set("sunk_ship", false)
        commander_board_ship()

    elseif cmd == "settings" then
        crew_display_settings()

    else
        commander_help_display()
    end
end

-------------------------------------------------------------------------------
-- VALIDATION AND ENTRY
-------------------------------------------------------------------------------

local function validate_settings()
    local ok   = true
    local errs = {}
    if osa_get("crew", "") == "" then
        table.insert(errs, "crew channel not set  → run ;osacommander setup")
        ok = false
    end
    if osa_get("commander", "") == "" then
        table.insert(errs, "commander name not set → run ;osacommander setup")
        ok = false
    end
    if not ok then
        echo("")
        echo("  OSACommander: configuration incomplete:")
        for _, e in ipairs(errs) do echo("    - " .. e) end
        echo("")
    end
    return ok
end

local function before_dying()
    if Script.running("osacombat") then Script.kill("osacombat") end
    echo("OSACommander: character died — stopping.")
end

-- ── Main entry ───────────────────────────────────────────────────────────────

load_settings()

local raw_args = Script.args() or {}
local args     = {}
for _, a in ipairs(raw_args) do table.insert(args, a) end

-- Hook: stop on death
Script.on_death(before_dying)

-- Show help if no args
if #args == 0 then
    commander_help_display()
    Script.exit()
end

-- Setup bypass
local cmd0 = (args[1] or ""):lower()
if cmd0 == "setup" then
    commander_setup()
    Script.exit()
end

-- Validate before any real command
if not validate_settings() then
    Script.exit()
end

-- Dispatch
commander_begin_it(args)

