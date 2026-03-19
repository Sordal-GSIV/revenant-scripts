--- @revenant-script
--- name: cobble
--- version: 54.0.0
--- author: Dreaven
--- contributors: Zoral
--- game: gs
--- @lic-certified: complete 2026-03-18
--- description: Automate cobbling (leatherworking) in multiple towns. Buys supplies, manages patterns, crafts items, and ranks up automatically.
--- tags: cobbling, crafting, leatherworking, guild
---
--- Original Lich5 script by Dreaven (Version 54)
--- Contact: In game: Dreaven | Player's Corner: Tgo01 | Discord: Dreaven#6436
--- BIG THANKS to Zoral for getting everything setup to work properly in River's Rest!
---
--- Usage:
---   ;cobble                    - Start cobbling (requires UserVars setup)
---   ;cobble <pelt|hide|skin>   - Use your own materials from cobbling sack first
---   ;cobble help               - Show help
---
--- Supported towns: Wehnimer's Landing, FWI, Cysaegir, Zul Logoth, Teras, River's Rest, Kraken's Fall
---
--- Required UserVars (set via ;vars set):
---   cobblingsack       - container for ALL cobbling supplies (e.g., "pack")
---   cobblingtown       - town abbreviation: landing, zul, cys, fwi, teras, kf, rr
---   cobblingrest       - "yes" or "no" — rest when mind is full
---   cobblingrestroom   - room number to rest in (if cobblingrest=yes)
---   cobblingrestcommand - optional pre-rest command (e.g., "go table")
---   cobblingbook       - noun for your pattern book (e.g., "patterns" or "book")
---   cobblingsack2      - optional second container for overflow / extra hides
---
--- Requires: go2 script for navigation

---------------------------------------------------------------------------
-- Town configuration data
---------------------------------------------------------------------------

local towns = {
    landing = {
        foreman = 15519, registrar = 4081, registrar_npc = "lass",
        storage = 15520, exit_cmd = "go door",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "hide",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "4082", "4083", "4084", "4078", "4079", "4080" },
    },
    zul = {
        foreman = 16862, registrar = 16860, registrar_npc = "dwarf",
        storage = 16863, exit_cmd = "out",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "skin",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "16865", "16865", "16865" },
    },
    cys = {
        foreman = 17169, registrar = 17168, registrar_npc = "woman",
        storage = 17170, exit_cmd = "go door",
        read_patterns = "read patterns", tap_patterns = "tap patterns",
        hide_type = "hide",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "4699", "4700", "4701", "4698", "17173", "4697" },
    },
    fwi = {
        foreman = 19396, registrar = 19395, registrar_npc = "gnome",
        storage = 19393, exit_cmd = "out",
        read_patterns = "read patterns on lectern", tap_patterns = "tap patterns on lectern",
        hide_type = "oilcloth",
        hide_low = 6, hide_high = 24, leather_low = 7, leather_high = 8,
        knife = 2, cord = 1, chalk = 3,
        workshops = { "19384", "19385", "19386", "19387", "19388", "19391", "19392" },
    },
    teras = {
        foreman = 14701, registrar = 14701, registrar_npc = "Bartober",
        storage = 14808, exit_cmd = "go door",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "pelt",
        hide_low = 4, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "14807", "14806", "14803", "14804", "14805", "14703" },
    },
    kf = {
        foreman = 29145, registrar = 29140, registrar_npc = "half-elf",
        storage = 29143, exit_cmd = "out",
        read_patterns = "read patterns on desk", tap_patterns = "tap patterns on desk",
        hide_type = "byssine",
        hide_low = 1, hide_high = 5, leather_low = 7, leather_high = 8,
        knife = 25, cord = 16, chalk = 18,
        workshops = { "29142", "29146", "29148", "30605", "30606", "29147" },
    },
    rr = {
        foreman = 24499, registrar = 24500, registrar_npc = "man",
        storage = 16167, exit_cmd = "go door",
        read_patterns = "read patterns", tap_patterns = "tap patterns",
        hide_type = "pelt",
        hide_low = 1, hide_high = 3, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "16168", "16169", "16170", "16172", "16173" },
    },
}

---------------------------------------------------------------------------
-- Workshop room name → room ID mapping
---------------------------------------------------------------------------

local workshop_map = {
    -- Landing
    ["butterfly"]   = 4082, ["drake"]       = 4082,
    ["ogre"]        = 4083, ["manticore"]   = 4083,
    ["minotaur"]    = 4084, ["centaur"]     = 4084,
    ["goblin"]      = 4078, ["orc"]         = 4078,
    ["faeroth"]     = 4079, ["kobold"]      = 4079,
    ["gargoyle"]    = 4080,
    -- Zul Logoth
    ["corestone-set"] = 16865, ["galena-set"] = 16865,
    -- Cysaegir
    ["agate-inlaid"]     = 4699, ["hyacinth-inlaid"]  = 4699,
    ["opal-inlaid"]      = 4700, ["jacinth-inlaid"]   = 4700,
    ["ruby-inlaid"]      = 4701, ["despanal-inlaid"]  = 4701,
    ["sapphire-inlaid"]  = 4698, ["feystone-inlaid"]  = 4698,
    ["heliodor-inlaid"]  = 17173, ["rosespar-inlaid"] = 17173,
    ["diamond-inlaid"]   = 4697,
    -- FWI
    ["bird-etched"]     = 19384, ["turtle-etched"]    = 19384,
    ["crane-etched"]    = 19385, ["dolphin-etched"]   = 19385,
    ["pelican-etched"]  = 19386,
    ["shell-etched"]    = 19388,
    ["seathrak-etched"] = 19391, ["wave-etched"]      = 19391,
    ["fish-etched"]     = 19392, ["trident-etched"]   = 19392,
    ["vine-painted"]    = 19387,
    -- Teras
    ["dragonsbreath sapphire-inlaid"] = 14807,
    ["green peridot-inlaid"]          = 14806,
    ["leopard quartz-inlaid"]         = 14803, ["asterfire quartz-inlaid"] = 14803,
    ["dragonfire emerald-inlaid"]     = 14804, ["star emerald-inlaid"]     = 14804,
    ["blue geode-inlaid"]             = 14805, ["purple geode-inlaid"]     = 14805,
    ["red sunstone-inlaid"]           = 14703, ["yellow sunstone-inlaid"]  = 14703,
    -- Kraken's Fall
    ["golden"]       = 29142,
    ["whistle"]      = 29146, ["ship"]         = 29146,
    ["storm"]        = 29148, ["monkey"]       = 29148,
    ["porpoise"]     = 30605, ["nymph"]        = 30605,
    ["sea hag"]      = 30606, ["kelpie"]       = 30606,
    ["badge"]        = 29147, ["captain's hat"] = 29147,
    -- River's Rest
    ["cowrie-inlaid"]  = 16168, ["abalone-inlaid"]  = 16168,
    ["coquina-inlaid"] = 16169, ["nassa-inlaid"]    = 16169,
    ["nautilus-inlaid"] = 16170, ["pearl-inlaid"]   = 16170,
    ["urchin-inlaid"]  = 16172, ["conch-inlaid"]    = 16172,
    ["chiton-inlaid"]  = 16173, ["tegula-inlaid"]   = 16173,
}

---------------------------------------------------------------------------
-- State variables
---------------------------------------------------------------------------

local town_cfg               -- selected town config table
local cobble_sack            -- primary cobbling container
local cobble_sack2           -- overflow / second container
local cobble_book            -- pattern book noun
local cobble_town            -- town abbreviation string
local cobble_rest            -- "yes" or "no"
local cobble_rest_room       -- room id to rest in
local cobble_rest_command    -- optional pre-rest command
local my_workshop_room       -- the door keyword discovered at runtime
local my_workshop_number     -- room id of assigned workshop
local cobble_work_table      -- "worktable" or "red worktable"
local cobble_hide_or_skin    -- current material noun (hide/skin/pelt/oilcloth/byssine/velvet)
local cobble_exit_cmd        -- command to exit workshop area
local cobble_read_patterns   -- command to read patterns at registrar
local cobble_tap_patterns    -- command to tap patterns at registrar

local required_pattern       -- pattern text to match in book
local current_project_type   -- "shoes"/"boots"/"slippers"/"sandals"
local current_part           -- current material being worked on
local current_hide_order     -- order number for hides
local current_leather_order  -- order number for leather
local cobbling_skills        -- current cobbling rank (integer)
local pattern_book_number    -- page counter when flipping through book
local trash_container_name   -- trash container in workshop
local workshop_search_index  -- index when searching for workshop doors

local user_material = nil    -- optional user-specified pelt/hide/skin from args

---------------------------------------------------------------------------
-- Help / setup
---------------------------------------------------------------------------

local function show_help()
    respond("Simply type ;cobble and let this script do the rest.")
    respond("Typing ;cobble <pelt|hide|skin|etc> uses your own pelts found in")
    respond("your cobbling sack before attempting to buy materials from NPC.")
    respond("To change your cobbling sack type ;vars delete cobblingsack then run this script again.")
    respond("To change your town type ;vars delete cobblingtown then run this script again.")
end

local function show_sack_setup()
    respond("Must set your cobbling sack — this is where ALL cobbling supplies will be found.")
    respond("Do not remove cobbling supplies out of this container.")
    respond("Type ;vars set cobblingsack=<container name> to set your cobbling sack.")
    respond("For example type ;vars set cobblingsack=pack")
    respond("You can also set a second container by doing ;vars set cobblingsack2=<container name>")
    respond("This second container will only look for leathers, skins, and hides.")
end

local function show_town_setup()
    respond("Must set the town you will be doing cobbling in.")
    respond("Type ;vars set cobblingtown=<town> to set your town.")
    respond("  landing  - Wehnimer's Landing")
    respond("  zul      - Zul Logoth")
    respond("  cys      - Cysaegir")
    respond("  fwi      - FWI")
    respond("  teras    - Teras")
    respond("  kf       - Kraken's Fall")
    respond("  rr       - River's Rest")
    respond("For example type ;vars set cobblingtown=landing")
end

local function show_rest_setup()
    respond("If your mind is fried do you want the script to rest until your mind becomes clear?")
    respond("Type ;vars set cobblingrest=<yes|no>")
    respond("For example type ;vars set cobblingrest=yes")
end

local function show_rest_room_setup()
    respond("Enter the room number where you want to rest.")
    respond("Type ;vars set cobblingrestroom=<room number>")
    respond("For example type ;vars set cobblingrestroom=238")
    respond("Also type ;vars set cobblingrestcommand=<command> if you need a prerest command.")
    respond("For example type ;vars set cobblingrestcommand=go table")
    respond("Do not set cobblingrestcommand if you don't need a prerest command.")
end

local function show_book_setup()
    respond("Must set your cobbling patterns book noun.")
    respond("Enter the word you interact with the book (example: book or patterns).")
    respond("Enter patterns if you're using the book the cobbling NPC sells.")
    respond("Type ;vars set cobblingbook=<name of book>")
    respond("For example type ;vars set cobblingbook=patterns")
end

---------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------

local function error_out(proc_name)
    echo("Looks like you ran into a problem in " .. proc_name ..
         ". Please run the script again and if you run into the same problem " ..
         "please copy this line and about the previous 20 game lines and send " ..
         "the information to the author.")
    error("cobble: error in " .. proc_name)
end

local function wait_and_stuff()
    pause(1)
    waitrt()
    pause(1)
    waitrt()
    ensure_workshop()
end

--- Stow whatever is in hands into cobbling sack, overflow to sack2
local function stow_cobbling_supplies()
    local rh = GameObj.right_hand()
    if rh then
        local r = dothistimeout("put #" .. rh.id .. " in my " .. cobble_sack, 5,
            { "You put", "won't fit in the" })
        if r and r:find("won't fit in the") and cobble_sack2 then
            fput("put #" .. rh.id .. " in my " .. cobble_sack2)
        end
    end
    local lh = GameObj.left_hand()
    if lh then
        local r = dothistimeout("put #" .. lh.id .. " in my " .. cobble_sack, 5,
            { "You put", "won't fit in the" })
        if r and r:find("won't fit in the") and cobble_sack2 then
            fput("put #" .. lh.id .. " in my " .. cobble_sack2)
        end
    end
end

--- Navigate using go2 script
local function go2(destination)
    if type(destination) == "table" then
        Script.run("go2", table.concat(destination, " "))
    else
        Script.run("go2", tostring(destination))
    end
    wait_while(function() return Script.running("go2") end)
    if invisible() then fput("unhide") end
end

--- Navigate to storage room
local function go_to_storage()
    go2(town_cfg.storage)
end

--- Navigate to foreman, with special handling for RR and Teras
local function go_to_foreman()
    go2(town_cfg.foreman)
    if cobble_town == "rr" then
        fput("go out")
        fput("go brass-handled door")
    end
    if town_cfg.registrar == 14701 then
        fput("go grey wooden door")
    end
end

--- Navigate to bank
local function go_to_bank()
    go2({ "bank", "--disable-confirm" })
end

--- Check if we're in a workshop area
local function inside_workshop()
    return room_name() and room_name():lower():find("workshop")
end

--- Ensure we're in the workshop; navigate there if not
local function ensure_workshop()
    if not inside_workshop() then
        go_to_workshop()
    end
end

--- Leave workshop room if inside one
local function leave_room_check()
    waitrt()
    if not standing() then fput("stand") end
    local room = room_name() or ""
    if room:lower():find("table") or room:lower():find("booth") then
        move("out")
    end
    if room:lower():find("workshop") then
        move(cobble_exit_cmd)
    end
end

--- Withdraw 10000 silvers from bank
local function get_10000_silvers()
    go_to_bank()
    fput("depo all")
    local withdraw_cmd
    if cobble_town == "kf" then
        withdraw_cmd = "withdraw 10000 note"
    else
        withdraw_cmd = "withdraw 10000 silvers"
    end
    local result = dothistimeout(withdraw_cmd, 10,
        { "you don't seem to have", "then hands you", "and hands it to you", "and hands you" })
    if result and result:find("you don't seem to have") then
        echo("You don't have enough silvers to continue with this script.")
        error("cobble: insufficient funds")
    elseif not result then
        error_out("get_10000_silvers")
    end
end

--- Find trash container in current room
local function find_trash_container()
    if trash_container_name then return end
    local loot = GameObj.loot()
    for _, item in ipairs(loot) do
        if item.name:find("crate") or item.name:find("barrel") or item.name:find("wastebarrel")
           or item.name:find("casket") or item.name:find("bin") or item.name:find("receptacle")
           or item.name:find("basket") or item.name:find("cask") then
            trash_container_name = item.noun
            return
        end
    end
    local desc = GameObj.room_desc()
    for _, item in ipairs(desc) do
        if item.name:find("crate") or item.name:find("barrel") or item.name:find("wastebarrel")
           or item.name:find("casket") or item.name:find("bin") or item.name:find("receptacle")
           or item.name:find("basket") or item.name:find("cask") then
            trash_container_name = item.noun
            return
        end
    end
end

---------------------------------------------------------------------------
-- Forward declarations for mutually-recursive functions
---------------------------------------------------------------------------

local check_rent_status, find_workshop, check_form, begin_work, start_form
local get_correct_pattern, correct_correct_pattern, gaze_pattern, get_chalk
local cut_hide, check_for_leather, check_for_hide, check_for_pattern_book
local check_for_cutting_knife, check_for_cord, check_for_chalk
local get_current_pattern, get_current_pattern_2, skill_level_stuff
local lower_quality_settings, check_guild_status

---------------------------------------------------------------------------
-- Workshop room number resolution
---------------------------------------------------------------------------

local function set_my_workshop_number()
    if not my_workshop_room then return end
    for keyword, room_id in pairs(workshop_map) do
        if my_workshop_room:find(keyword, 1, true) then
            my_workshop_number = room_id
            return
        end
    end
end

---------------------------------------------------------------------------
-- Navigation: go to workshop
---------------------------------------------------------------------------

function go_to_workshop()
    if not my_workshop_number then
        set_my_workshop_number()
    end
    if not my_workshop_number and cobble_town == "cys" then
        my_workshop_number = 4699
    end
    if not my_workshop_number then
        check_rent_status()
        return
    end
    go2(my_workshop_number)
    local result = dothistimeout("go " .. (my_workshop_room or "") .. " door", 10,
        { "appears to be locked", "opens easily as you pass" })
    if result and result:find("appears to be locked") then
        check_rent_status()
    elseif result and result:find("opens easily as you pass") then
        pause(0.1)
    elseif not result then
        error_out("go_to_workshop")
    end
end

---------------------------------------------------------------------------
-- Guild membership check
---------------------------------------------------------------------------

check_guild_status = function()
    local result = dothistimeout("artisan skills", 3, { "cobbling" })
    if result and result:lower():find("cobbling") then
        pause(0.1)
    else
        echo("You don't know cobbling yet, let's fix that.")
        pause(1)
        go_to_foreman()
        fput("ask foreman about join")
        waitrt()
        check_guild_status()
    end
end

---------------------------------------------------------------------------
-- Supply checks: pattern book, cutting knife, cord, chalk
---------------------------------------------------------------------------

check_for_pattern_book = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my " .. cobble_book .. " in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        echo("You need a pattern book, let's get that for you.")
        pause(1)
        stow_cobbling_supplies()
        go_to_bank()
        local r2 = dothistimeout("withdraw 2000 note", 10,
            { "you don't seem to have", "then hands you", "and hands it to you" })
        if r2 and r2:find("you don't seem to have") then
            echo("You don't have enough silvers to continue with this script.")
            error("cobble: insufficient funds for pattern book")
        elseif r2 and (r2:find("then hands you") or r2:find("and hands it to you")) then
            go2(town_cfg.registrar)
            if town_cfg.registrar == 14701 then
                fput("go dark brown wooden door")
            end
            if cobble_town == "rr" then
                fput("go out")
                fput("go brass-trimmed door")
            end
            fput("ask " .. town_cfg.registrar_npc .. " about book")
            fput("give " .. town_cfg.registrar_npc)
            check_for_pattern_book()
        elseif not r2 then
            error_out("check_for_pattern_book")
        end
    elseif result and result:find("You tap") then
        pause(0.1)
    elseif not result then
        error_out("check_for_pattern_book")
    end
end

check_for_cutting_knife = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my cutting knife in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        echo("You need a cutting knife, let's get that for you.")
        pause(1)
        go_to_storage()
        fput("order " .. town_cfg.knife)
        local r2 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r2 and r2:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. town_cfg.knife, "buy")
            check_for_cutting_knife()
        elseif r2 and r2:find("hands you") then
            check_for_cutting_knife()
        elseif not r2 then
            error_out("check_for_cutting_knife")
        end
    elseif result and result:find("You tap") then
        pause(0.1)
    elseif not result then
        error_out("check_for_cutting_knife")
    end
end

check_for_cord = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my knotted cord in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        echo("You need a cord, let's get that for you.")
        pause(1)
        go_to_storage()
        fput("order " .. town_cfg.cord)
        local r2 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r2 and r2:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. town_cfg.cord, "buy")
            check_for_cord()
        elseif r2 and r2:find("hands you") then
            check_for_cord()
        elseif not r2 then
            error_out("check_for_cord")
        end
    elseif result and result:find("You tap") then
        pause(0.1)
    elseif not result then
        error_out("check_for_cord")
    end
end

check_for_chalk = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my chalk in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        echo("You need some chalk, let's get that for you.")
        pause(1)
        go_to_storage()
        fput("order " .. town_cfg.chalk)
        local r2 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r2 and r2:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. town_cfg.chalk, "buy")
            check_for_chalk()
        elseif r2 and r2:find("hands you") then
            check_for_chalk()
        elseif not r2 then
            error_out("check_for_chalk")
        end
    elseif result and result:find("You tap") then
        pause(0.1)
    elseif not result then
        error_out("check_for_chalk")
    end
end

---------------------------------------------------------------------------
-- Material checks: leather and hide
---------------------------------------------------------------------------

check_for_leather = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my leather in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        -- Try sack2
        if cobble_sack2 then
            local r2 = dothistimeout("tap my leather in my " .. cobble_sack2, 10,
                { "You tap", "What were you referring to", "You tap your foot impatiently" })
            if r2 and r2:find("You tap") then
                return -- found in sack2
            elseif not r2 then
                error_out("check_for_leather")
            end
        end
        -- Need to buy leather
        leave_room_check()
        go_to_storage()
        fput("order " .. current_leather_order)
        local r3 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r3 and r3:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. current_leather_order, "buy")
            stow_cobbling_supplies()
        elseif r3 and r3:find("hands you") then
            stow_cobbling_supplies()
        elseif not r3 then
            error_out("check_for_leather")
        end
    elseif result and result:find("You tap") then
        -- Already have leather
    elseif not result then
        error_out("check_for_leather")
    end
end

check_for_hide = function()
    stow_cobbling_supplies()
    local result = dothistimeout("tap my " .. current_part .. " in my " .. cobble_sack, 10,
        { "You tap", "What were you referring to", "You tap your foot impatiently" })
    if result and (result:find("What were you referring to") or result:find("You tap your foot impatiently")) then
        -- Try sack2
        if cobble_sack2 then
            local r2 = dothistimeout("tap my " .. current_part .. " in my " .. cobble_sack2, 10,
                { "You tap", "What were you referring to", "You tap your foot impatiently" })
            if r2 and r2:find("You tap") then
                return -- found in sack2
            elseif not r2 then
                error_out("check_for_hide")
            end
        end
        -- Need to buy hide
        leave_room_check()
        go_to_storage()
        fput("order " .. current_hide_order)
        local r3 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r3 and r3:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. current_hide_order, "buy")
            stow_cobbling_supplies()
        elseif r3 and r3:find("hands you") then
            stow_cobbling_supplies()
        elseif not r3 then
            error_out("check_for_hide")
        end
    elseif result and result:find("You tap") then
        -- Already have hide
    elseif not result then
        error_out("check_for_hide")
    end
end

---------------------------------------------------------------------------
-- Rent / workshop management
---------------------------------------------------------------------------

check_rent_status = function()
    workshop_search_index = 0
    leave_room_check()
    go_to_foreman()

    if cobble_town == "kf" then
        fput("get my chit")
    end

    local need_public_workshop = false
    local result = dothistimeout("ask foreman about rent", 10, {
        "ya gots a perfectly good one already",
        "looks up and scowls at you",
        "you already have a workshop here",
        "It is always amusing when the customer already has a workshop",
        "Just head upstairs to the wide golden oak door",
        "You should answer yes or answer no",
        "I could offer you a space in the public workshop",
        "I see you've got a workshop already",
    })
    if result and (result:find("ya gots a perfectly good one already")
                   or result:find("looks up and scowls at you")
                   or result:find("you already have a workshop here")
                   or result:find("It is always amusing")
                   or result:find("Just head upstairs")
                   or result:find("I see you've got a workshop already")) then
        if my_workshop_room then
            set_my_workshop_number()
            check_form()
        else
            find_workshop()
        end
        return
    elseif result and result:find("You should answer yes or answer no") then
        local r2 = dothistimeout("answer yes", 10, {
            "glances at you and rolls his eyes",
            "You need coins or",
            "deducts the rental cost",
            "takes your 1000 silvers",
        })
        if r2 and (r2:find("glances at you") or r2:find("You need coins or")) then
            get_10000_silvers()
            check_rent_status()
        elseif r2 and (r2:find("deducts the rental cost") or r2:find("takes your 1000 silvers")) then
            find_workshop()
        elseif not r2 then
            error_out("check_rent_status")
        end
        return
    elseif result and result:find("I could offer you a space in the public workshop") then
        need_public_workshop = true
    elseif not result then
        error_out("check_rent_status")
    end

    -- Handle public workshop request
    if need_public_workshop then
        local r3 = dothistimeout("ask foreman for public", 10, {
            "ya gots a perfectly good one already",
            "looks up and scowls at you",
            "you already have a workshop here",
            "It is always amusing",
            "Just head upstairs",
            "You should answer yes or answer no",
            "I could offer you a space in the public workshop",
        })
        if r3 and (r3:find("ya gots a perfectly good one already")
                   or r3:find("looks up and scowls at you")
                   or r3:find("you already have a workshop here")
                   or r3:find("It is always amusing")
                   or r3:find("Just head upstairs")) then
            if my_workshop_room then
                set_my_workshop_number()
                check_form()
            else
                find_workshop()
            end
        elseif r3 and r3:find("You should answer yes or answer no") then
            local r4 = dothistimeout("answer yes", 10, {
                "glances at you and rolls his eyes",
                "You need coins or",
                "deducts the rental cost",
                "takes your 1000 silvers",
            })
            if r4 and (r4:find("glances at you") or r4:find("You need coins or")) then
                get_10000_silvers()
                check_rent_status()
            elseif r4 and (r4:find("deducts the rental cost") or r4:find("takes your 1000 silvers")) then
                find_workshop()
            elseif not r4 then
                error_out("check_rent_status")
            end
        elseif not r3 then
            error_out("check_rent_status")
        end
    end
end

---------------------------------------------------------------------------
-- Find workshop by trying doors
---------------------------------------------------------------------------

find_workshop = function()
    leave_room_check()
    if workshop_search_index >= #town_cfg.workshops then
        echo("Couldn't find your workshop.")
        error("cobble: workshop not found")
    end
    workshop_search_index = (workshop_search_index or 0) + 1
    local room_id = town_cfg.workshops[workshop_search_index]
    go2(room_id)

    local result = dothistimeout("go door", 10, {
        "opens easily as you pass through into your workshop",
        "appears to be locked",
    })
    if result and result:find("opens easily as you pass through into your workshop") then
        -- Extract the door description (e.g., "butterfly", "golden")
        local door_desc = result:match("The (.-) [Oo]?a?k? ?doors? opens easily")
            or result:match("The (.-) door opens easily")
        if door_desc then
            my_workshop_room = door_desc
        end
        if my_workshop_room and my_workshop_room:find("golden") then
            cobble_work_table = "red worktable"
        else
            cobble_work_table = "worktable"
        end
        set_my_workshop_number()
        check_form()
    elseif result and result:find("appears to be locked") then
        -- Try "go other door"
        local r2 = dothistimeout("go other door", 10, {
            "opens easily as you pass through into your workshop",
            "appears to be locked",
            "Where are you trying to go",
        })
        if r2 and r2:find("opens easily as you pass through into your workshop") then
            local door_desc = r2:match("The (.-) [Oo]?a?k? ?doors? opens easily")
                or r2:match("The (.-) door opens easily")
            if door_desc then
                my_workshop_room = door_desc
            end
            if my_workshop_room and my_workshop_room:find("golden") then
                cobble_work_table = "red worktable"
            else
                cobble_work_table = "worktable"
            end
            set_my_workshop_number()
            check_form()
        elseif r2 and (r2:find("appears to be locked") or r2:find("Where are you trying to go")) then
            find_workshop()
        elseif not r2 then
            error_out("find_workshop")
        end
    elseif not result then
        error_out("find_workshop")
    end
end

---------------------------------------------------------------------------
-- Skill level determination and pattern/project assignment
---------------------------------------------------------------------------

skill_level_stuff = function()
    local result = dothistimeout("art skills", 10, { "In the skill of cobbling" })
    if result and result:lower():find("in the skill of cobbling") then
        local rank_str = result:match("cobbling,%s+%a+%s+(%d+)%s+ranks")
        if rank_str then
            cobbling_skills = tonumber(rank_str)
        end
    elseif not result then
        error_out("skill_level_stuff")
    end

    if not cobbling_skills then
        cobbling_skills = 0
    end

    if cobbling_skills >= 500 then
        echo("You are a master at cobbling! Congratulations!")
        return
    end

    -- Determine required pattern and project type based on skill level
    if cobbling_skills == 49 or cobbling_skills == 99 or cobbling_skills == 149 or cobbling_skills == 199 then
        -- Rank-up tier: use higher quality materials
        if cobbling_skills == 49 then
            required_pattern = "pattern for a pair of shoes"
            current_project_type = "shoes"
        elseif cobbling_skills == 99 then
            required_pattern = "pattern for a pair of boots"
            current_project_type = "boots"
        elseif cobbling_skills == 149 then
            required_pattern = "pattern for a pair of slippers"
            current_project_type = "slippers"
        elseif cobbling_skills == 199 then
            required_pattern = "pattern for a pair of sandals"
            current_project_type = "sandals"
        end
        current_hide_order = town_cfg.hide_high
        if cobble_town == "kf" then
            cobble_hide_or_skin = "velvet"
        end
        current_leather_order = town_cfg.leather_high
    elseif cobbling_skills <= 48 then
        required_pattern = "pattern for a pair of shoes"
        current_project_type = "shoes"
        lower_quality_settings()
    elseif cobbling_skills <= 98 then
        required_pattern = "pattern for a pair of boots"
        current_project_type = "boots"
        lower_quality_settings()
    elseif cobbling_skills <= 148 then
        required_pattern = "pattern for a pair of slippers"
        current_project_type = "slippers"
        lower_quality_settings()
    elseif cobbling_skills <= 499 then
        required_pattern = "pattern for a pair of sandals"
        current_project_type = "sandals"
        lower_quality_settings()
    end
end

lower_quality_settings = function()
    local found_needed_item = false
    current_hide_order = town_cfg.hide_low
    if cobble_town == "kf" then
        cobble_hide_or_skin = "byssine"
    end
    current_leather_order = town_cfg.leather_low

    -- Check if user specified a material via script args
    if user_material then
        local result = dothistimeout("tap my " .. user_material .. " in my " .. cobble_sack, 10,
            { "You tap", "What were you referring to", "You tap your foot impatiently" })
        if result and result:find("You tap") then
            cobble_hide_or_skin = user_material
            found_needed_item = true
        end
        if cobble_sack2 and not found_needed_item then
            local r2 = dothistimeout("tap my " .. user_material .. " in my " .. cobble_sack2, 10,
                { "You tap", "What were you referring to", "You tap your foot impatiently" })
            if r2 and r2:find("You tap") then
                cobble_hide_or_skin = user_material
            else
                echo("Couldn't find any " .. user_material .. "s in your cobbling sacks, buying materials from NPC.")
            end
        elseif not found_needed_item then
            echo("Couldn't find any " .. user_material .. "s in your cobbling sack, buying materials from NPC.")
        end
    end
end

---------------------------------------------------------------------------
-- Pattern book management
---------------------------------------------------------------------------

get_current_pattern = function()
    stow_cobbling_supplies()
    leave_room_check()
    go_to_bank()
    local result = dothistimeout("withdraw 200 note", 10,
        { "you don't seem to have", "then hands you", "and hands it to you" })
    if result and result:find("you don't seem to have") then
        echo("You don't have enough silvers to continue with this script.")
        error("cobble: insufficient funds for pattern")
    elseif result and (result:find("then hands you") or result:find("and hands it to you")) then
        go2(town_cfg.registrar)
        if town_cfg.registrar == 14701 then
            fput("go dark brown wooden door")
        end
        if cobble_town == "rr" then
            fput("go out")
            fput("go brass-trimmed door")
        end
        fput("get my " .. cobble_book)
        local r2 = dothistimeout(cobble_read_patterns, 10,
            { required_pattern, "open to the" })
        if r2 and r2:find(required_pattern) and not r2:find("dancing shoes") then
            fput(cobble_tap_patterns)
            fput("ask " .. town_cfg.registrar_npc .. " about pattern")
            fput("give " .. town_cfg.registrar_npc)
            waitrt()
            begin_work()
        elseif r2 and r2:find("open to the") then
            pattern_book_number = 1
            get_current_pattern_2()
        elseif not r2 then
            error_out("get_current_pattern")
        end
    elseif not result then
        error_out("get_current_pattern")
    end
end

get_current_pattern_2 = function()
    local result = dothistimeout("flip patterns " .. pattern_book_number, 10,
        { required_pattern, "You flip" })
    if result and result:find(required_pattern) then
        fput(cobble_tap_patterns)
        fput("ask " .. town_cfg.registrar_npc .. " about pattern")
        fput("give " .. town_cfg.registrar_npc)
        waitrt()
        begin_work()
    elseif result and result:find("You flip") then
        pattern_book_number = pattern_book_number + 1
        get_current_pattern_2()
    elseif not result then
        error_out("get_current_pattern_2")
    end
end

get_correct_pattern = function()
    ensure_workshop()
    -- Stow non-book items, get book
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_noun = rh and rh.noun or nil
    local lh_noun = lh and lh.noun or nil
    if rh_noun and rh_noun ~= cobble_book and rh then
        fput("put my " .. rh_noun .. " in my " .. cobble_sack)
    end
    if lh_noun and lh_noun ~= cobble_book and lh then
        fput("put my " .. lh_noun .. " in my " .. cobble_sack)
    end
    if rh_noun ~= cobble_book and lh_noun ~= cobble_book then
        fput("get my " .. cobble_book .. " from my " .. cobble_sack)
    end
    pause(1)

    local result = dothistimeout("read my " .. cobble_book, 10, {
        required_pattern,
        "The cover is embossed",
        "note that it has patterns for the following",
        "is open to the pattern",
        "There are no patterns yet",
    })
    if result and result:find(required_pattern) then
        pause(0.1)
    elseif result and result:find("The cover is embossed") then
        fput("open my " .. cobble_book)
        get_correct_pattern()
    elseif result and (result:find("note that it has patterns for the following") or result:find("is open to the pattern")) then
        local r2 = dothistimeout("flip patterns " .. pattern_book_number, 10,
            { "But there is only", "But there are only", "You flip" })
        if r2 and (r2:find("But there is only") or r2:find("But there are only")) then
            get_current_pattern()
        elseif r2 and r2:find("You flip") then
            pattern_book_number = pattern_book_number + 1
            pause(0.5)
            get_correct_pattern()
        elseif not r2 then
            error_out("get_correct_pattern")
        end
    elseif result and result:find("There are no patterns yet") then
        get_current_pattern()
    elseif not result then
        error_out("get_correct_pattern")
    end
end

correct_correct_pattern = function()
    ensure_workshop()
    -- Get book, stow non-book items
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_noun = rh and rh.noun or nil
    local lh_noun = lh and lh.noun or nil
    if rh_noun ~= cobble_book and lh_noun ~= cobble_book then
        fput("get my " .. cobble_book .. " from my " .. cobble_sack)
    end
    rh = GameObj.right_hand()
    lh = GameObj.left_hand()
    rh_noun = rh and rh.noun or nil
    lh_noun = lh and lh.noun or nil
    if rh_noun and rh_noun ~= cobble_book then
        fput("put my " .. rh_noun .. " in my " .. cobble_sack)
    end
    if lh_noun and lh_noun ~= cobble_book then
        fput("put my " .. lh_noun .. " in my " .. cobble_sack)
    end

    local result = dothistimeout("read my " .. cobble_book, 10, {
        required_pattern,
        "The cover is embossed",
        "note that it has patterns for the following",
        "is open to the pattern",
        "There are no patterns yet",
    })
    if result and result:find(required_pattern) then
        begin_work()
    elseif result and result:find("The cover is embossed") then
        fput("open my " .. cobble_book)
        correct_correct_pattern()
    elseif result and (result:find("note that it has patterns for the following") or result:find("is open to the pattern")) then
        local r2 = dothistimeout("flip patterns " .. pattern_book_number, 10,
            { "But there is only", "But there are only", "You flip" })
        if r2 and (r2:find("But there is only") or r2:find("But there are only")) then
            get_current_pattern()
        elseif r2 and r2:find("You flip") then
            pattern_book_number = pattern_book_number + 1
            pause(0.5)
            correct_correct_pattern()
        elseif not r2 then
            error_out("correct_correct_pattern")
        end
    elseif result and result:find("There are no patterns yet") then
        get_current_pattern()
    elseif not result then
        error_out("correct_correct_pattern")
    end
end

---------------------------------------------------------------------------
-- Chalk management
---------------------------------------------------------------------------

get_chalk = function()
    ensure_workshop()
    fput("get my chalk from my " .. cobble_sack)
    pause(1)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_noun = rh and rh.noun or nil
    local lh_noun = lh and lh.noun or nil
    if rh_noun ~= "chalk" and lh_noun ~= "chalk" then
        stow_cobbling_supplies()
        leave_room_check()
        get_10000_silvers()
        go_to_storage()
        multifput("order " .. town_cfg.chalk, "buy")
        go_to_workshop()
        begin_work()
    end
end

---------------------------------------------------------------------------
-- Gaze pattern (copy pattern to worktable)
---------------------------------------------------------------------------

gaze_pattern = function()
    ensure_workshop()
    local result = dothistimeout("gaze " .. cobble_book, 10, {
        "slips awkwardly from your hand",
        "a current of air flips the page over",
        "You must flip the book open to a pattern first",
        "shattering off a large piece before you can copy the pattern",
        "You study the pattern for",
    })
    if result and result:find("slips awkwardly from your hand") then
        waitrt()
        ensure_workshop()
        get_chalk()
        gaze_pattern()
    elseif result and result:find("You study the pattern for") then
        begin_work()
    elseif result and (result:find("a current of air flips the page over") or result:find("You must flip the book open to a pattern first")) then
        waitrt()
        ensure_workshop()
        stow_cobbling_supplies()
        correct_correct_pattern()
    elseif result and result:find("shattering off a large piece before you can copy the pattern") then
        waitrt()
        ensure_workshop()
        leave_room_check()
        go_to_storage()
        fput("order " .. town_cfg.chalk)
        local r2 = dothistimeout("buy", 10, { "you do not have enough silver", "hands you" })
        if r2 and r2:find("you do not have enough silver") then
            get_10000_silvers()
            go_to_storage()
            multifput("order " .. town_cfg.chalk, "buy")
            go_to_workshop()
            begin_work()
        elseif r2 and r2:find("hands you") then
            go_to_workshop()
            begin_work()
        elseif not r2 then
            error_out("gaze_pattern")
        end
    elseif not result then
        error_out("gaze_pattern")
    end
end

---------------------------------------------------------------------------
-- Cut hide on worktable
---------------------------------------------------------------------------

cut_hide = function()
    waitrt()
    ensure_workshop()
    stow_cobbling_supplies()
    fput("get my cutting knife from my " .. cobble_sack)
    fput("cut " .. current_part .. " on " .. cobble_work_table)
    waitrt()
    ensure_workshop()
    begin_work()
end

---------------------------------------------------------------------------
-- Begin work: main crafting dispatch
---------------------------------------------------------------------------

begin_work = function()
    pattern_book_number = 1
    waitrt()
    ensure_workshop()

    local result = dothistimeout("look at " .. current_part .. " on " .. cobble_work_table, 10, {
        "Close examination shows pattern marks on the",
        "I could not find what you were referring to",
        "has been carefully measured as",
        "and precisely cut",
        "has been carefully prepared to be used",
    })

    if result and result:find("Close examination shows pattern marks on the") then
        -- Measured but not yet cut — need to measure and cut
        waitrt()
        ensure_workshop()
        stow_cobbling_supplies()
        fput("get my cord from my " .. cobble_sack)
        local r2 = dothistimeout("measure " .. current_part .. " on " .. cobble_work_table, 10,
            { "You try to transfer" })
        if r2 and r2:find("You try to transfer") then
            fput("measure " .. GameState.name)
            cut_hide()
        else
            cut_hide()
        end

    elseif result and result:find("I could not find what you were referring to") then
        -- No material on table — get materials, place, pattern, gaze
        check_for_hide()
        check_for_leather()
        ensure_workshop()
        -- Stow non-book items
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if rh and rh.noun ~= cobble_book then
            fput("put my " .. rh.noun .. " in my " .. cobble_sack)
        end
        if lh and lh.noun ~= cobble_book then
            fput("put my " .. lh.noun .. " in my " .. cobble_sack)
        end
        -- Get material from sack
        local r2 = dothistimeout("get my " .. current_part .. " from my " .. cobble_sack, 10,
            { "You remove", "Get what" })
        if r2 and r2:find("Get what") and cobble_sack2 then
            fput("get my " .. current_part .. " from my " .. cobble_sack2)
        end
        pause(1)
        fput("put my " .. current_part .. " on " .. cobble_work_table)
        -- Wait for confirmation
        while true do
            local line = get()
            if line and line:find("^You put") then break end
        end
        get_correct_pattern()
        get_chalk()
        gaze_pattern()
        waitrt()
        ensure_workshop()

    elseif result and result:find("has been carefully measured as") then
        -- Already measured, needs cutting
        cut_hide()

    elseif result and result:find("and precisely cut") then
        -- Cut material — check if it's hide or leather
        if current_part:find("hide") or current_part:find("skin") or current_part:find("pelt")
           or current_part:find("canvas") or current_part:find("oilcloth")
           or current_part:find("byssine") or current_part:find("velvet") then
            current_part = "leather"
            begin_work()
        elseif current_part == "leather" then
            start_form()
        end

    elseif result and result:find("has been carefully prepared to be used") then
        -- Prepared material — need pattern and chalk
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if rh and rh.noun ~= cobble_book then
            fput("put my " .. rh.noun .. " in my " .. cobble_sack)
        end
        if lh and lh.noun ~= cobble_book then
            fput("put my " .. lh.noun .. " in my " .. cobble_sack)
        end
        get_correct_pattern()
        get_chalk()
        gaze_pattern()
        waitrt()
        ensure_workshop()

    elseif not result then
        error_out("begin_work")
    end
end

---------------------------------------------------------------------------
-- Start form: assemble the item on the form
---------------------------------------------------------------------------

start_form = function()
    waitrt()
    ensure_workshop()
    stow_cobbling_supplies()

    -- Get hide from worktable, put on form
    fput("get " .. cobble_hide_or_skin .. " from " .. cobble_work_table)
    fput("put my " .. cobble_hide_or_skin .. " on form")
    fput("join " .. cobble_hide_or_skin .. " on form")
    wait_and_stuff()

    -- Get leather from worktable, join with hide on form
    fput("get leather from " .. cobble_work_table)
    fput("join leather with " .. cobble_hide_or_skin .. " on form")
    wait_and_stuff()

    -- Join project on form (3 times)
    fput("join " .. current_project_type .. " on form")
    wait_and_stuff()
    fput("join " .. current_project_type .. " on form")
    wait_and_stuff()
    fput("join " .. current_project_type .. " on form")
    wait_and_stuff()

    -- Get from form, rub twice
    multifput(
        "get " .. current_project_type .. " from form",
        "rub my " .. current_project_type,
        "rub my " .. current_project_type
    )

    -- Check if we need a rank-up
    if cobbling_skills == 49 or cobbling_skills == 99
       or cobbling_skills == 149 or cobbling_skills == 199 then
        leave_room_check()
        go_to_foreman()
        fput("ask foreman about rank")
        waitrt()
        check_rent_status()

    elseif cobbling_skills <= 499 then
        -- Trash the item
        find_trash_container()
        if trash_container_name then
            fput("put my " .. current_project_type .. " in " .. trash_container_name)
        else
            fput("drop my " .. current_project_type)
        end

        -- Rest if mind is full
        if cobble_rest == "yes" and GameState.mind_value and GameState.mind_value >= 100 then
            echo("Mind full, going to rest.")
            leave_room_check()
            if cobble_rest_room then
                go2(cobble_rest_room)
                if cobble_rest_command and cobble_rest_command ~= "" then
                    fput(cobble_rest_command)
                end
                wait_until(function()
                    return GameState.mind_value and GameState.mind_value <= 50
                end)
                echo("Mind at clear, heading back to do more cobbling.")
                fput("open my " .. cobble_sack)
            end
        end

        check_rent_status()
    end
end

---------------------------------------------------------------------------
-- Check form: entry point after finding workshop
---------------------------------------------------------------------------

check_form = function()
    pattern_book_number = 1
    ensure_workshop()
    skill_level_stuff()

    if cobbling_skills and cobbling_skills >= 500 then
        return
    end

    find_trash_container()

    -- Trash any leftover project items in hands
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local trash_nouns = { "shoes", "boots", "slippers", "sandals" }
    for _, noun in ipairs(trash_nouns) do
        if (rh and rh.noun == noun) or (lh and lh.noun == noun) then
            if trash_container_name then
                fput("put my " .. noun .. " in " .. trash_container_name)
            else
                fput("drop my " .. noun)
            end
        end
    end

    -- Check form for work in progress
    local result = dothistimeout("look on form", 10, {
        "hide", "skin", "pelt", "canvas", "oilcloth", "byssine", "velvet",
        "shoes", "boots", "slippers", "sandals",
        "There is nothing",
    })
    if result and (result:find("hide") or result:find("skin") or result:find("pelt")
                   or result:find("canvas") or result:find("oilcloth") or result:find("byssine")
                   or result:find("velvet") or result:find("shoes") or result:find("boots")
                   or result:find("slippers") or result:find("sandals")) then
        start_form()
    elseif result and result:find("There is nothing") then
        current_part = cobble_hide_or_skin
        stow_cobbling_supplies()
        begin_work()
    elseif not result then
        error_out("check_form")
    end
end

---------------------------------------------------------------------------
-- Main entry point
---------------------------------------------------------------------------

-- Handle help
if Script.vars[1] and Script.vars[1]:lower() == "help" then
    show_help()
    return
end

-- Validate required UserVars
cobble_sack = UserVars.cobblingsack
if not cobble_sack or cobble_sack == "" then
    show_sack_setup()
    return
end

cobble_town = UserVars.cobblingtown
if not cobble_town or cobble_town == "" then
    show_town_setup()
    return
end

cobble_rest = UserVars.cobblingrest
if not cobble_rest or cobble_rest == "" then
    show_rest_setup()
    return
end

if cobble_rest == "yes" then
    cobble_rest_room = UserVars.cobblingrestroom
    if not cobble_rest_room or cobble_rest_room == "" then
        show_rest_room_setup()
        return
    end
    cobble_rest_command = UserVars.cobblingrestcommand
end

cobble_book = UserVars.cobblingbook
if not cobble_book then
    show_book_setup()
    return
end

cobble_sack2 = UserVars.cobblingsack2

-- Optional user material from script args
if Script.vars[1] and Script.vars[1]:lower() ~= "help" then
    user_material = Script.vars[1]
end

-- Validate town selection
town_cfg = towns[cobble_town]
if not town_cfg then
    respond("Wrong value entered for cobblingtown.")
    show_town_setup()
    return
end

-- Validate rest setting
if cobble_rest ~= "yes" and cobble_rest ~= "no" then
    respond("Wrong value entered for cobblingrest.")
    respond("Type ;vars delete cobblingrest to remove current setting then run this script again.")
    return
end

-- Initialize town-specific state
cobble_hide_or_skin = town_cfg.hide_type
cobble_exit_cmd     = town_cfg.exit_cmd
cobble_read_patterns = town_cfg.read_patterns
cobble_tap_patterns  = town_cfg.tap_patterns
cobble_work_table    = "worktable"
workshop_search_index = 0

-- Check for existing workshop room setting
if UserVars.my_workshop_room and UserVars.my_workshop_room ~= "" then
    my_workshop_room = UserVars.my_workshop_room
    set_my_workshop_number()
end

-- Main sequence: leave current room, open sack, check supplies, find workshop
leave_room_check()
fput("open my " .. cobble_sack)
stow_cobbling_supplies()
check_guild_status()
check_for_pattern_book()
check_for_cutting_knife()
check_for_cord()
check_for_chalk()
check_rent_status()
