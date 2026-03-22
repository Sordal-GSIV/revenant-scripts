--- @revenant-script
--- name: osacrew
--- version: 6.0.6
--- author: Peggyanne (Bait#4376)
--- contributors: Revenant port by elanthia-online
--- game: gs
--- description: OSA ship crew companion — sails, repair, combat support, medical, cannons, navigation
--- tags: osa, ship, crew, sailing, combat
--- @lic-certified: complete 2026-03-18
---
--- Changelog (from original Lich5 version):
---   v6.0.6 (2026-02-13) AI-assisted GTK3/YAML rewrite; this Lua port
---   v6.0.5 (2026-01-26) Empath commander boarding fix; sinking via cannons fix
---   v6.0.4 (2026-01-25) Anti-poaching toggle; renamed setup method
---   v6.0.3 (2025-12-20) Commander/crew channel default to character name
---   v6.0.2 (2025-12-13) Crew swap YAML leftover fixes
---   v6.0.1 (2025-12-06) Removed Vars, added YAML, tooltips, defaults
---   v5.x.x (2025-09-21) Anti-poaching/hiding group member logic
---   v5.x.x (2025-08-03) Status report separated; gemstone/resource reports added
---   v5.x.x (2025-07-29) Changelog added; minor tweaks

-- ---------------------------------------------------------------------------
-- Submodule requires
-- ---------------------------------------------------------------------------

local Map     = require("gs.osacrew.map")
local Nav     = require("gs.osacrew.nav")
local Routes  = require("gs.osacrew.nav_routes")
local Medical = require("gs.osacrew.medical")
local Combat  = require("gs.osacrew.combat")
local Spellup = require("gs.osacrew.spellup")
local Gui     = require("gs.osacrew.gui")
local Cannons = require("gs.osacrew.cannons")
local Repair  = require("gs.osacrew.repair")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local VERSION      = "6.0.6"
local SETTINGS_KEY = "osacrew"

-- Keys persisted to CharSettings
local PERSIST_KEYS = {
    "commander", "crew_channel", "medical_officer", "checkformana",
    "osacrewtasks", "windedsails", "mana_spellup", "groupspellup",
    "selfspellup", "uselte", "lootsell", "needbless", "givebless",
    "blesser", "osacombat", "cannoneer", "loadonly", "fireonly",
    "loadandfire", "maincannons", "midcannons", "forwardcannons",
    "armor_specs",
    "have_armor_blessing",     "use_armor_blessing",     "need_armor_blessing",
    "have_armor_reinforcement","use_armor_reinforcement", "need_armor_reinforcement",
    "have_armor_support",      "use_armor_support",       "need_armor_support",
    "have_armor_casting",      "use_armor_casting",       "need_armor_casting",
    "have_armor_evasion",      "use_armor_evasion",       "need_armor_evasion",
    "have_armor_fluidity",     "use_armor_fluidity",      "need_armor_fluidity",
    "have_armor_stealth",      "use_armor_stealth",       "need_armor_stealth",
    "my_armor_spec", "uachands", "uacfeet", "stealth_disabler", "check_for_group",
    "Slooptimes", "Brigtimes", "Cartimes", "Galtimes", "Fritimes", "Mantimes",
    "averagetime", "gangplank", "ship_type", "ship_map", "enemy_type", "crewsize",
}

-- ---------------------------------------------------------------------------
-- Settings persistence
-- ---------------------------------------------------------------------------

local function save_settings(osa)
    local persist = {}
    for _, k in ipairs(PERSIST_KEYS) do
        persist[k] = osa[k]
    end
    CharSettings[SETTINGS_KEY] = Json.encode(persist)
end

local function load_settings()
    local raw = CharSettings[SETTINGS_KEY]
    if not raw or raw == "" then return {} end
    local ok, data = pcall(Json.decode, raw)
    return (ok and type(data) == "table") and data or {}
end

-- Boolean helper: return saved[k] if non-nil, else default_val
local function bsaved(saved, k, default_val)
    if saved[k] ~= nil then return saved[k] end
    return default_val
end

local function init_osa()
    local saved = load_settings()
    local name  = Char.name or ""
    local osa = {
        -- Persistent settings
        commander           = saved.commander           or name,
        crew_channel        = saved.crew_channel        or name,
        medical_officer     = saved.medical_officer     or "",
        checkformana        = saved.checkformana        or 80,
        osacrewtasks        = bsaved(saved, "osacrewtasks",    false),
        windedsails         = bsaved(saved, "windedsails",     false),
        mana_spellup        = bsaved(saved, "mana_spellup",    false),
        groupspellup        = bsaved(saved, "groupspellup",    false),
        selfspellup         = bsaved(saved, "selfspellup",     false),
        uselte              = bsaved(saved, "uselte",           false),
        lootsell            = bsaved(saved, "lootsell",         false),
        needbless           = bsaved(saved, "needbless",        false),
        givebless           = bsaved(saved, "givebless",        false),
        blesser             = saved.blesser             or "",
        osacombat           = bsaved(saved, "osacombat",        false),
        cannoneer           = bsaved(saved, "cannoneer",        false),
        loadonly            = bsaved(saved, "loadonly",         false),
        fireonly            = bsaved(saved, "fireonly",         false),
        loadandfire         = bsaved(saved, "loadandfire",      false),
        maincannons         = bsaved(saved, "maincannons",      false),
        midcannons          = bsaved(saved, "midcannons",       false),
        forwardcannons      = bsaved(saved, "forwardcannons",   false),
        armor_specs         = bsaved(saved, "armor_specs",      false),
        have_armor_blessing     = bsaved(saved, "have_armor_blessing",     false),
        use_armor_blessing      = bsaved(saved, "use_armor_blessing",      false),
        need_armor_blessing     = bsaved(saved, "need_armor_blessing",     false),
        have_armor_reinforcement= bsaved(saved, "have_armor_reinforcement",false),
        use_armor_reinforcement = bsaved(saved, "use_armor_reinforcement", false),
        need_armor_reinforcement= bsaved(saved, "need_armor_reinforcement",false),
        have_armor_support      = bsaved(saved, "have_armor_support",      false),
        use_armor_support       = bsaved(saved, "use_armor_support",       false),
        need_armor_support      = bsaved(saved, "need_armor_support",      false),
        have_armor_casting      = bsaved(saved, "have_armor_casting",      false),
        use_armor_casting       = bsaved(saved, "use_armor_casting",       false),
        need_armor_casting      = bsaved(saved, "need_armor_casting",      false),
        have_armor_evasion      = bsaved(saved, "have_armor_evasion",      false),
        use_armor_evasion       = bsaved(saved, "use_armor_evasion",       false),
        need_armor_evasion      = bsaved(saved, "need_armor_evasion",      false),
        have_armor_fluidity     = bsaved(saved, "have_armor_fluidity",     false),
        use_armor_fluidity      = bsaved(saved, "use_armor_fluidity",      false),
        need_armor_fluidity     = bsaved(saved, "need_armor_fluidity",     false),
        have_armor_stealth      = bsaved(saved, "have_armor_stealth",      false),
        use_armor_stealth       = bsaved(saved, "use_armor_stealth",       false),
        need_armor_stealth      = bsaved(saved, "need_armor_stealth",      false),
        my_armor_spec       = saved.my_armor_spec   or "",
        uachands            = saved.uachands        or "",
        uacfeet             = saved.uacfeet         or "",
        stealth_disabler    = saved.stealth_disabler or 0,
        check_for_group     = bsaved(saved, "check_for_group", false),
        -- Per-ship timing (persisted, rolling 50-sample averages)
        Slooptimes  = saved.Slooptimes  or {0.35},
        Brigtimes   = saved.Brigtimes   or {0.35},
        Cartimes    = saved.Cartimes    or {0.35},
        Galtimes    = saved.Galtimes    or {0.35},
        Fritimes    = saved.Fritimes    or {0.35},
        Mantimes    = saved.Mantimes    or {0.35},
        averagetime = saved.averagetime or 0.35,
        -- Persistent ship state
        gangplank   = saved.gangplank,
        ship_type   = saved.ship_type   or "",
        ship_map    = saved.ship_map    or {},
        enemy_type  = saved.enemy_type  or "pirate",
        crewsize    = saved.crewsize    or {},
        -- Runtime-only state (never persisted)
        cannoneer_boarded = false,
        cannoneer_thirty  = false,
        cannoneer_sunk    = false,
        cannoneer_stop    = false,
        depart            = false,
        piratehunter      = false,
        logging           = false,
        boarding          = false,
        sunk_ship         = false,
        winded            = false,
        matched_type      = false,
        everyone_in_group = {},
        everyone_hidden   = {},
        supportlist       = {},
        severlist         = {},
        mana_message      = "",
        endbalance        = 0,
        medicalofficer_patient = {},
    }
    return osa
end

-- ---------------------------------------------------------------------------
-- Pattern escaping helper
-- ---------------------------------------------------------------------------

local function ep(s)
    return (s or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

-- ---------------------------------------------------------------------------
-- Help text
-- ---------------------------------------------------------------------------

local SHIP_ART = [[
                                       ..
                                     .(  )`-._
                                   .'  ||     `._
                                 .'    ||        `.
                              .'       ||          `._
                            .'        _||_            `-.
                         .'          |====|              `..
                       .'             \__/               (  )
                     ( )               ||          _      ||
                     /|\               ||       .-` \     ||
                   .' | '              ||   _.-'    |     ||
                  /   |\ \             || .'   `.__.'     ||   _.-..
                .'   /| `.            _.-'   _.-'       _.-.`-'`._`.`
                \  .' |  |        .-.`    `./      _.-`.    `._.-'
                 |.   |  `.   _.-'   `.   .'     .'  `._.`---`
                .'    |   |  :   `._..-'.'        `._..'  ||
               /      |   \  `-._.'    ||                 ||
              |     .'|`.  |           ||_.--.-._         ||
              '    /  |  \ \       __.--'\    `. :        ||
               \  .'  |   \|   ..-'   \   `._-._.'        ||
]]

local function show_help()
    respond(SHIP_ART)
    respond("------------------------------------------------------------------------------")
    respond("   OSACrew Version: " .. VERSION)
    respond("")
    respond("   Usage: ")
    respond("")
    respond("   ;osacrew setup                       Opens the setup window")
    respond("   ;osacrew underway                    Will get your ship underway")
    respond("   ;osacrew underway anchor             Will raise the anchor")
    respond("   ;osacrew underway sails              Will lower your sails")
    respond("   ;osacrew navigation                  Will begin port to port travel")
    respond("   ;osacrew repair                      Will begin damage control on the ship")
    respond("   ;osacrew cannons                     Will man the cannons of your choosing")
    respond("   ;osacrew swap                        Enables you to swap commands with ease")
    respond("   ;osacrew orders                      Will await your commander to announce location of ship then board ship")
    respond("   ;osacrew disembark                   Will depart the crew at the next convenient location")
    respond("   ;osacrew settings                    Will show current settings")
    respond("   ;osacrew profile                     Will save/load profiles for different commander settings")
    respond("")
    respond("   This is a companion to OSACommander. It is run on your crew members to complete simple tasks on the ship including combat.")
    respond("   Enjoy")
    respond("")
    respond("   ~Peggyanne")
    respond(" PS: feel free to send any bugs via discord Bait#4376")
    respond("")
    respond("Changelog:")
    respond("")
    respond("           July 29, 2025 - Added A Changelog And Various Minor Tweaks.")
    respond("           July 30, 2025 - Added Gemstone Searches Via Killtracker To Status Reports.")
    respond("          August 3, 2025 - Separated Readout For Status Report, Added Gemstone Report And Resource Report.")
    respond("         August 26, 2025 - Fixed Slight Variable Error With Silvers Sharing.")
    respond("      September 21, 2025 - Yet Again More Changes To Anti-Poaching and Hiding Group Member Logic.")
    respond("        December 6, 2025 - Removed Vars Dependancy, Added Yaml Support, Added Tooltips and Added Default Values.")
    respond("       December 13, 2025 - Fixed Small Errors In Crew Swap Logic Leftover From Yaml Conversion.")
    respond("       December 20, 2025 - Added Default Value to Commander As Well As Crew Channel.")
    respond("        January 25, 2026 - Added Anti-Poaching Command For Toggle and Changed Name of Setup Method.")
    respond("        January 26, 2026 - Fixed Issue With Empath Commanders Stalling During Boarding and Fixed Issues With Sinking Ship Via Cannons.")
    respond("         Febuary 1, 2026 - Update Yaml Read/Write Methods To Include FLOCK Operations.")
    respond("        Febuary 13, 2026 - Gave In To The Hype And Rewrote YAML config and GTK3 Using AI.")
    respond("")
end

-- ---------------------------------------------------------------------------
-- Group tracking
-- ---------------------------------------------------------------------------

local function determine_group_members(osa)
    osa.everyone_in_group = {}
    osa.everyone_hidden   = {}
    fput("group")
    local result = matchtimeout(5,
        "You are leading",
        "You are grouped with",
        "You are not currently in a group")
    if not result then return end
    if result:find("not currently in a group") then return end
    -- Parse visible members
    for name in result:gmatch("[A-Z][a-z]+") do
        if name ~= "You" and name ~= "Your" then
            local hidden_match = result:find(name .. " who is hidden")
            local already_hidden = false
            for _, h in ipairs(osa.everyone_hidden) do
                if h == name then already_hidden = true; break end
            end
            if hidden_match then
                if not already_hidden then
                    table.insert(osa.everyone_hidden, name)
                end
            else
                local in_group = false
                for _, g in ipairs(osa.everyone_in_group) do
                    if g == name then in_group = true; break end
                end
                if not in_group and not already_hidden then
                    table.insert(osa.everyone_in_group, name)
                end
            end
        end
    end
end

local function group_add(osa, name)
    for _, n in ipairs(osa.everyone_in_group) do
        if n == name then return end
    end
    table.insert(osa.everyone_in_group, name)
end

local function group_remove(osa, name)
    for i, n in ipairs(osa.everyone_in_group) do
        if n == name then table.remove(osa.everyone_in_group, i); return end
    end
end

local function group_clear(osa)
    osa.everyone_in_group = {}
    osa.everyone_hidden   = {}
end

local function hidden_add(osa, name)
    group_remove(osa, name)
    for _, n in ipairs(osa.everyone_hidden) do
        if n == name then return end
    end
    table.insert(osa.everyone_hidden, name)
end

local function hidden_remove(osa, name)
    for i, n in ipairs(osa.everyone_hidden) do
        if n == name then table.remove(osa.everyone_hidden, i); return end
    end
    group_add(osa, name)
end

-- ---------------------------------------------------------------------------
-- Mana sharing
-- ---------------------------------------------------------------------------

local function mana_share(osa)
    local types = {}
    local my_types = {}
    if Skills and Skills.smc >= 24 then
        table.insert(types, "Spiritual"); table.insert(my_types, "Spiritual")
    end
    if Skills and Skills.mmc >= 24 then
        table.insert(types, "Mental"); table.insert(my_types, "Mental")
    end
    if Skills and Skills.emc >= 24 then
        table.insert(types, "Elemental"); table.insert(my_types, "Elemental")
    end
    osa.my_mana_types = my_types
    local n = #types
    if n == 0 then
        osa.mana_message = ""
    elseif n == 1 then
        osa.mana_message = "I Need " .. types[1] .. " Mana!"
    elseif n == 2 then
        osa.mana_message = "I Need " .. types[1] .. " or " .. types[2] .. " Mana!"
    else
        osa.mana_message = "I Need " .. types[1] .. ", " .. types[2] .. " or " .. types[3] .. " Mana!"
    end
end

-- ---------------------------------------------------------------------------
-- Settings display
-- ---------------------------------------------------------------------------

local function crew_display_settings(osa)
    respond("")
    respond("   Your Current Crew Settings Are As Follows:")
    respond("")
    respond("   Commander:            " .. (osa.commander or ""))
    respond("")
    respond("   Crew:                 " .. (osa.crew_channel or ""))
    respond("")
    respond("   Medical Officer:      " .. (osa.medical_officer or ""))
    respond("")
    local charname = Char.name or ""
    if charname == osa.commander then
        respond("")
        respond("   You Are Currently Commander.")
        respond("")
        respond("   Current Crew Size:    " .. #(osa.crewsize or {}))
        respond("")
    end
end

-- ---------------------------------------------------------------------------
-- Crew task complete
-- ---------------------------------------------------------------------------

local function crew_task_complete(osa)
    local charname = Char.name or ""
    if osa.commander and not osa.commander:find(charname, 1, true) then
        wait_until(function()
            local pcs = GameObj.pcs() or {}
            for _, pc in ipairs(pcs) do
                if pc.name == osa.commander then return true end
            end
            return false
        end)
        pause(math.random(1, 8))
        LNet.private(osa.commander, "Task Complete")
    end
end

-- ---------------------------------------------------------------------------
-- Mana send
-- ---------------------------------------------------------------------------

local function crew_send_mana(osa, manaperson)
    local mana_pct = Char.mana_pct or 0
    if mana_pct >= 50 and osa.matched_type then
        local pcs = GameObj.pcs() or {}
        local found = false
        for _, pc in ipairs(pcs) do
            if pc.name == manaperson then found = true; break end
        end
        if found then
            if Script.running("osacombat") then Script.pause("osacombat") end
            waitrt()
            waitcastrt()
            local send_amt = math.floor((Char.max_mana or 100) * 0.20)
            fput("send " .. send_amt .. " " .. manaperson)
            if Script.running("osacombat") then Script.unpause("osacombat") end
        end
    end
    osa.matched_type = false
end

-- ---------------------------------------------------------------------------
-- Sell loot / give coins
-- ---------------------------------------------------------------------------

local function crew_check_balance()
    fput("bank acc")
    local line = matchtimeout(5, "Total: [%d,]+")
    if line then
        local b = line:match("Total: ([%d,]+)")
        if b then return tonumber(b:gsub(",", "")) or 0 end
    end
    return 0
end

local function crew_sell_loot(osa)
    local beginbalance = crew_check_balance()
    Script.run("eloot", "sell")
    wait_while(function() return Script.running("eloot") end)
    local afterbalance = crew_check_balance()
    osa.endbalance = afterbalance - beginbalance
    wait_until(function()
        local pcs = GameObj.pcs() or {}
        for _, pc in ipairs(pcs) do
            if pc.name == osa.commander then return true end
        end
        return false
    end)
    fput("join " .. osa.commander)
    crew_task_complete(osa)
end

local function crew_give_coins(osa)
    if osa.endbalance and osa.endbalance > 0 then
        fput("withdraw " .. osa.endbalance .. " silver")
        osa.endbalance = 0
    end
    fput("give " .. osa.commander .. " all silvers")
end

-- ---------------------------------------------------------------------------
-- Receive / eat bread
-- ---------------------------------------------------------------------------

local function crew_eat_bread()
    local rh = GameObj.right_hand()
    if rh and rh.id then
        fput("gobble #" .. rh.id)
        local new_rh = GameObj.right_hand()
        if new_rh and new_rh.id then
            crew_eat_bread()
        end
    end
end

local function crew_receive_bread(osa)
    local med = ep(osa.medical_officer)
    local result = matchtimeout(30,
        med .. " offers you",
        med .. " offers .* a",
        med .. " offers .* some")
    if result and result:find(osa.medical_officer .. " offers you") then
        fput("accept")
        crew_eat_bread()
    elseif result then
        crew_receive_bread(osa)
    end
end

-- ---------------------------------------------------------------------------
-- Task check
-- ---------------------------------------------------------------------------

local function go_to_handler()
    Map.go2("handler")
    local room = Room and Room.current and Room.current()
    if room and room.location and room.location:find("Kraken") then
        Map.go2("28950")
    end
end

local function crew_check_task(osa)
    fput("osa task")
    local result = matchtimeout(5,
        "You do not currently have a task",
        "You should return to the Sea Hag",
        "Abandons your current task",
        "OSA TASK")
    if not result then
        crew_task_complete(osa)
        return
    end
    if result:find("do not currently have a task") then
        go_to_handler()
        fput("take board")
        pause(0.5)
        Map.go_to_tag(osa, "captains_quarters")
        crew_task_complete(osa)
    elseif result:find("return to the Sea Hag") then
        if Char.mind_pct and Char.mind_pct >= 100 then
            if osa.uselte then fput("boost long") end
            wait_until(function() return (Char.mind_pct or 0) < 100 end)
        end
        go_to_handler()
        fput("turn board")
        pause(0.5)
        fput("take board")
        pause(0.5)
        Map.go_to_tag(osa, "captains_quarters")
        crew_task_complete(osa)
    else
        crew_task_complete(osa)
    end
end

-- ---------------------------------------------------------------------------
-- Disembark
-- ---------------------------------------------------------------------------

local function crew_disembark(osa)
    osa.depart = true
    respond("")
    respond("   You Will Depart The Crew When The Crew Visits The Bank Next!")
    respond("   Thanks For Sailing With Us...")
    respond("")
end

-- ---------------------------------------------------------------------------
-- Crew swap (handshake with commander)
-- ---------------------------------------------------------------------------

local function crew_crew_swap(osa, args)
    local new_commander = args and args[2]
    if not new_commander or new_commander == "" then
        respond("")
        respond("   Please Select A Valid Commander:")
        respond("     ;osacrew swap <commander>")
        respond("")
        return
    end
    local charname = Char.name or ""
    LNet.private(new_commander, "Crewman " .. charname .. " Checking Onboard Captain!")
    local result = matchtimeout(3, "Excellent Crewman " .. ep(charname))
    if result then
        local med = result:match("Medical Officer Is: (.-)%. Our Shipboard")
        local ch  = result:match("Communications Channel Is: (.-)[\"$]")
        osa.commander       = new_commander
        if med and med ~= "" then osa.medical_officer = med end
        if ch  and ch  ~= "" then osa.crew_channel    = ch  end
        save_settings(osa)
        respond("")
        respond("   Your Crew Settings Have Changed And Now Are:")
        respond("")
        respond("   Crew:                " .. osa.crew_channel)
        respond("   Commander:           " .. osa.commander)
        respond("   Medical Officer:     " .. osa.medical_officer)
        respond("")
    else
        respond("   The Captain Didn't Respond, Try Again Later!")
    end
end

-- ---------------------------------------------------------------------------
-- Orders (wait for ship arrival, board)
-- ---------------------------------------------------------------------------

local function crew_start_orders(osa)
    local charname = Char.name or ""
    respond("   ---------------------------==========================================================================---------------------------")
    respond("")
    respond("                              Welcome Back Crewman " .. charname .. ", Waiting For The Ship To Arrive!")
    respond("")
    respond("   ---------------------------==========================================================================---------------------------")

    local cmd_pat = ep(osa.commander)
    local ch_pat  = ep(osa.crew_channel)
    local moor_pat = "%[" .. ch_pat .. "%]%-GSIV:" .. cmd_pat .. ": \"(.-) Is Now Moored In (.-). Room Number: (%d+)"

    while true do
        local line = get()
        if not line then break end
        local _ship, _town, room = line:match(moor_pat)
        if room then
            LNet.private(osa.commander, "Crewman " .. charname .. ", Requesting Permission To Come Aboard!")
            local perm = matchtimeout(30, "Permission Granted", "Permission Denied")
            if perm and perm:find("Permission Granted") then
                -- Navigate to gangplank room then board
                Map.go2(room)
                wait_while(function() return Script.running("go2") end)
                fput("go gangplank")
                Map.go_to_tag(osa, "captains_quarters")
                respond("   Crewman " .. charname .. " Standing By And Awaiting Orders Captain!")
                return
            elseif perm and perm:find("Permission Denied") then
                respond("   Sorry Shipmate, The Ship Has A Full Berth! Restarting Orders!")
                crew_start_orders(osa)
                return
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Profile save/load
-- ---------------------------------------------------------------------------

local function do_profile(osa, args)
    local sub  = (args and args[2]) and args[2]:lower() or ""
    local pname = (args and args[3]) or ""
    if sub == "save" and pname ~= "" then
        local data = {}
        for _, k in ipairs(PERSIST_KEYS) do data[k] = osa[k] end
        CharSettings[SETTINGS_KEY .. "_profile_" .. pname] = Json.encode(data)
        respond("   Profile '" .. pname .. "' saved.")
    elseif sub == "load" and pname ~= "" then
        local raw = CharSettings[SETTINGS_KEY .. "_profile_" .. pname]
        if raw and raw ~= "" then
            local ok, data = pcall(Json.decode, raw)
            if ok and type(data) == "table" then
                for _, k in ipairs(PERSIST_KEYS) do
                    if data[k] ~= nil then osa[k] = data[k] end
                end
                save_settings(osa)
                respond("   Profile '" .. pname .. "' loaded.")
            end
        else
            respond("   Profile '" .. pname .. "' not found.")
        end
    else
        respond("   Usage: ;osacrew profile save <name>  or  ;osacrew profile load <name>")
    end
end

-- ---------------------------------------------------------------------------
-- Dependency check
-- ---------------------------------------------------------------------------

local function check_dependency(name)
    if not Script.exists(name) then
        respond("")
        respond("   In order to run OSACrew you need " .. name)
        respond("   =================================================")
        respond("   Do you wish to download it now?")
        respond("       1. Yes")
        respond("       2. No")
        respond("   =================================================")
        respond("   Please Select an Option - ;send <#>")
        respond("")
        local answer = nil
        while not answer do
            local line = get()
            if line and line:match("^[12]$") then answer = line end
        end
        if answer == "1" then
            respond("   Downloading " .. name .. "...")
            Script.run("repository", "download " .. name .. " --author=elanthia-online")
            wait_while(function() return Script.running("repository") end)
            respond("   Download complete.")
        else
            echo("Very Well. Please restart OSACrew when you have " .. name .. ".")
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Unfurl masts helper (delegates to Nav)
-- ---------------------------------------------------------------------------

local function unfurl_masts(osa)
    local stype = osa.ship_type or ""
    if stype == "sloop" then
        Nav.one_mast(osa, Map)
    elseif stype == "brigantine" or stype == "carrack"
        or stype == "galleon"   or stype == "frigate" then
        Nav.two_masts(osa, Map)
    elseif stype == "man o' war" then
        Nav.three_masts(osa, Map)
    end
end

-- ---------------------------------------------------------------------------
-- Navigation helpers (thin wrappers)
-- ---------------------------------------------------------------------------

local function nav_fns(osa)
    return {
        cargo_hold      = function() Map.go_to_tag(osa, "cargo_hold") end,
        main_deck       = function() Map.go_to_tag(osa, "main_deck") end,
        helm            = function() Map.go_to_tag(osa, "helm") end,
        captains_quarters = function() Map.go_to_tag(osa, "captains_quarters") end,
        mid_deck        = function() Map.go_to_tag(osa, "mid_deck") end,
        forward_deck    = function() Map.go_to_tag(osa, "forward_deck") end,
        bow             = function() Map.go_to_tag(osa, "bow") end,
        crows_nest      = function() Map.go_to_tag(osa, "crows_nest") end,
        crew_quarters   = function() Map.go_to_tag(osa, "crew_quarters") end,
        mess_hall       = function() Map.go_to_tag(osa, "mess_hall") end,
        social_room     = function() Map.go_to_tag(osa, "social_room") end,
    }
end

-- ---------------------------------------------------------------------------
-- Main entry point
-- ---------------------------------------------------------------------------

local args = Script.vars or {}
local cmd  = (args[1] or ""):lower()

-- Version
if cmd:find("^ver") then
    respond("")
    respond("   OSACrew Version " .. VERSION)
    respond("")
    return
end

-- Help (early, before settings loaded)
if cmd == "help" or cmd == "?" then
    show_help()
    return
end

-- Load settings
local osa = init_osa()

-- Setup (GUI)
if cmd:find("^setup") or cmd:find("^setting") then
    if cmd:find("^setup") then
        Gui.open(osa, save_settings)
    else
        crew_display_settings(osa)
    end
    return
end

-- Profile
if cmd:find("^profile") then
    do_profile(osa, args)
    return
end

-- Repair / damage control
if cmd:find("^repair") then
    Map.ship_type(osa)
    local nf = nav_fns(osa)
    Repair.damage_control(osa, nf, save_settings)
    return
end

-- Underway
if cmd:find("^underway") then
    local sub = (args[2] or ""):lower()
    Map.ship_map(osa)
    if sub == "" then
        -- Full underway: sails + anchor
        Map.go_to_tag(osa, "main_deck")
        unfurl_masts(osa)
        waitrt()
        waitcastrt()
        Map.go_to_tag(osa, "helm")
        echo("Raising Anchor")
        Nav.raise_anchor()
        waitrt()
        fput("depart")
        fput("depart")
        fput("yell Underway!")
    elseif sub:find("sai") then
        Map.go_to_tag(osa, "main_deck")
        unfurl_masts(osa)
    elseif sub:find("anc") then
        Map.go_to_tag(osa, "helm")
        Nav.raise_anchor()
    else
        respond("   Please Select A Valid Underway Option: Sails or Anchor.")
        respond("   No Option Will default To Full Underway Process")
    end
    return
end

-- Navigation
if cmd:find("^nav") then
    local room = Room and Room.current and Room.current()
    if not room or not room.location or not room.location:find("Ships") then
        respond("   Please Restart When You Are On Your Ship")
        return
    end
    Map.ship_map(osa)
    osa.piratehunter = false
    Nav.crew_start_nav(osa, Map, Routes)
    -- falls through to main init + listener below
end

-- Cannons (direct dispatch + exit)
if cmd:find("^cannon") then
    osa.cannoneer_boarded = false
    osa.cannoneer_thirty  = false
    osa.cannoneer_sunk    = false
    osa.cannoneer_stop    = false
    Cannons.set_mode(osa, save_settings)
    Cannons.gunner_cycle(osa, save_settings, function(t) Map.go_to_tag(osa, t) end,
        function() Repair.damage_control(osa, nav_fns(osa), save_settings) end)
    osa.cannoneer_boarded = false
    osa.cannoneer_thirty  = false
    osa.cannoneer_sunk    = false
    osa.cannoneer_stop    = false
    return
end

-- Swap
if cmd:find("^swap") then
    crew_crew_swap(osa, args)
    -- falls through to main init + listener
end

-- Orders
if cmd:find("^orders") then
    crew_start_orders(osa)
    -- falls through to main init + listener
end

-- Disembark
if cmd:find("^disembark") then
    crew_disembark(osa)
    return
end

-- ---------------------------------------------------------------------------
-- Common startup validation
-- ---------------------------------------------------------------------------

if not osa.crew_channel or osa.crew_channel == "" then
    respond("*********** Your Crew Channel Is Not Set. Please set it via ;osacrew setup ***********")
    return
end
if not osa.commander or osa.commander == "" then
    respond("*********** Your Commander Is Not Set. Please set it via ;osacrew setup ***********")
    return
end

-- Inject ship room tags
Map.ship_type(osa)
Map.ship_map(osa)
determine_group_members(osa)
mana_share(osa)

-- Dependency checks
local deps = {"eloot", "eherbs", "foreach", "ewaggle", "ecure", "lnet"}
for _, dep in ipairs(deps) do
    if not check_dependency(dep) then return end
end

fput("flag sortedview on")

-- Init cannoneer flags (always reset on start)
osa.cannoneer_boarded = false
osa.cannoneer_thirty  = false
osa.cannoneer_sunk    = false
osa.cannoneer_stop    = false
osa.depart            = false
osa.piratehunter      = false
osa.logging           = false
if not osa.boarding  then osa.boarding  = false end
if not osa.sunk_ship then osa.sunk_ship = false end

-- Display settings on bare launch (no args)
if cmd == "" or cmd == "start" then
    crew_display_settings(osa)
end

-- Inject trashcan bucket tags for relevant captain's quarters rooms
for _, rid in ipairs({30129, 30175, 30180, 30124, 30140, 29042}) do
    if Map.add_tag then Map.add_tag(rid, "meta:trashcan:bucket") end
end

-- ---------------------------------------------------------------------------
-- before_dying hook
-- ---------------------------------------------------------------------------

before_dying(function()
    local charname = Char.name or ""
    if osa.crew_channel and osa.crew_channel ~= "" then
        if charname == osa.commander then
            LNet.channel(osa.crew_channel, "*Ding* *Ding* " .. (osa.commander or charname) .. " Departing!")
        else
            LNet.channel(osa.crew_channel, "*Ding* *Ding* Crewman " .. charname .. " Departing!")
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Upstream thread: intercept ;osacrew_project setup and ;osacrew help
-- ---------------------------------------------------------------------------

Script.start_thread(function()
    while true do
        local cmd_line = upstream_get()
        if cmd_line then
            if cmd_line:match("<c>;osacrew_project%s+setup") then
                Gui.open(osa, save_settings)
            elseif cmd_line:match("<c>;osacrew_project%s+help")
                or cmd_line:match("<c>;osacrew%s*$") then
                show_help()
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Main LNet listener loop
-- ---------------------------------------------------------------------------

local charname   = Char.name or ""
local crew_ch    = osa.crew_channel
local commander  = osa.commander

-- Pre-build commonly reused pattern prefixes (rebuilt if settings change mid-run)
local function build_patterns()
    local ch  = ep(osa.crew_channel)
    local cmd2 = ep(osa.commander)
    local med  = ep(osa.medical_officer)
    return {
        from_cmd   = "^%[" .. ch .. "%]%-GSIV:" .. cmd2 .. ": \"",
        from_crew  = "^%[" .. ch .. "%]%-GSIV:(.-):%s*\"",
        from_priv  = "^%[Private%]%-GSIV:(.-):%s*\"",
        med        = med,
        ch         = ch,
        cmd2       = cmd2,
    }
end

while true do
    local line = get()
    if not line then break end

    local p = build_patterns()

    -- ---------------------------------------------------------------------------
    -- Bless request from designated blesser
    -- ---------------------------------------------------------------------------
    if line:match("^%[" .. p.ch .. "%]%-GSIV:" .. ep(osa.blesser) ..
            ": \"Does Anyone Need A Bless%?\"") then
        if not Script.running("osacommander") and osa.needbless then
            Spellup.get_bless(osa)
        end

    -- ---------------------------------------------------------------------------
    -- Enemy vessel: cannons mode
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd ..
            "Enemy Vessel Detected, (.-) Sound General Quarters! Gunners Man Your Irons!\"") then
        local vessel = line:match("Enemy Vessel Detected, (.-) Sound General Quarters!")
        if vessel then
            local vl = vessel:lower()
            if vl:find("ethereal") then osa.enemy_type = "undead"
            elseif vl:find("krolvin") then osa.enemy_type = "krolvin"
            else osa.enemy_type = "pirate" end
        end
        Map.ship_map(osa)
        if osa.cannoneer then
            osa.cannoneer_boarded = false
            osa.cannoneer_thirty  = false
            osa.cannoneer_sunk    = false
            osa.cannoneer_stop    = false
            Cannons.gunner_cycle(osa, save_settings,
                function(t) Map.go_to_tag(osa, t) end,
                function() Repair.damage_control(osa, nav_fns(osa), save_settings) end)
        elseif osa.osacombat then
            if not Script.running("osacombat") then Script.run("osacombat") end
        else
            echo("You Are Not Currently In A Combatant Role, Ready Thyself For Combat!")
            fput("gird")
            if osa.medical_officer:find(charname) then
                Map.go_to_tag(osa, "captains_quarters")
            end
        end

    -- ---------------------------------------------------------------------------
    -- Enemy vessel: inbound (winded sails mode)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd ..
            "Enemy Vessel Detected, (.-) Inbound%. Sound General Quarters!\"") then
        local vessel = line:match("Enemy Vessel Detected, (.-) Inbound")
        if vessel then
            local vl = vessel:lower()
            if vl:find("ethereal") then osa.enemy_type = "undead"
            elseif vl:find("krolvin") then osa.enemy_type = "krolvin"
            else osa.enemy_type = "pirate" end
        end
        Map.ship_map(osa)
        if osa.windedsails then
            osa.winded = true
            Nav.winded_sails(osa, Map)
            wait_until(function()
                local pcs = GameObj.pcs() or {}
                for _, pc in ipairs(pcs) do
                    if pc.name == osa.commander then return true end
                end
                return false
            end)
            fput("join " .. osa.commander)
            osa.winded = false
        end
        if osa.osacombat then
            if not Script.running("osacombat") then Script.run("osacombat") end
        else
            echo("You Are Not Currently In A Combatant Role, Ready Thyself For Combat!")
            fput("gird")
            if osa.medical_officer:find(charname) then
                Map.go_to_tag(osa, "captains_quarters")
            end
        end

    -- ---------------------------------------------------------------------------
    -- Ship expects to make way (winded sails)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "(.-) Expects To Make Way From") then
        if osa.windedsails then
            osa.winded = true
            Nav.winded_sails(osa, Map)
            wait_until(function()
                local pcs = GameObj.pcs() or {}
                for _, pc in ipairs(pcs) do
                    if pc.name == osa.commander then return true end
                end
                return false
            end)
            fput("join " .. osa.commander)
            osa.winded = false
        end

    -- ---------------------------------------------------------------------------
    -- Turn To! (post-combat cleanup)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Turn To!\"") then
        Map.ship_type(osa)
        wait_until(function() return not Script.running("eloot") end)
        if osa.osacombat then
            Script.kill("osacombat")
            wait_while(function() return Script.running("osacombat") end)
        end
        waitrt()
        waitcastrt()
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.id) or (lh and lh.id) then
            fput("store both")
        end
        fput("leave")
        pause(0.5)
        fput("group open")
        local room = Room and Room.current and Room.current()
        local tags = (room and room.tags) or {}
        local in_cq = false
        for _, t in ipairs(tags) do
            if t == "captains_quarters" then in_cq = true; break end
        end
        if not in_cq then
            Repair.damage_control(osa, nav_fns(osa), save_settings)
        end

    -- ---------------------------------------------------------------------------
    -- Stop (halt combat)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Stop\"") then
        if osa.osacombat and Script.running("osacombat") then
            Script.kill("osacombat")
            wait_while(function() return Script.running("osacombat") end)
            waitrt()
            waitcastrt()
            fput("store both")
        end

    -- ---------------------------------------------------------------------------
    -- All Hands Make Ready To Get Underway
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "All Hands Make Ready To Get Underway!\"") then
        Map.ship_map(osa)
        if osa.osacrewtasks then
            fput("leave")
            pause(0.5)
            fput("group open")
            Map.go_to_tag(osa, "main_deck")
            unfurl_masts(osa)
            Map.go_to_tag(osa, "captains_quarters")
        else
            Map.go_to_tag(osa, "captains_quarters")
            echo("You Are Not Currently In A Crew Role, Please Standby To Standby!")
        end
        pause(1)
        local mana_threshold = tonumber(osa.checkformana) or 84
        if (Char.mana_pct or 100) <= mana_threshold then
            respond("")
            respond("          -----------------------------------------------------")
            respond("          |                Waiting For Mana                   |")
            respond("          -----------------------------------------------------")
            respond("")
            wait_until(function() return (Char.mana_pct or 0) >= mana_threshold + 1 end)
        end
        pause(5)
        wait_until(function()
            local room = Room and Room.current and Room.current()
            local tags = (room and room.tags) or {}
            for _, t in ipairs(tags) do
                if t == "captains_quarters" then return true end
            end
            return false
        end)
        crew_task_complete(osa)

    -- ---------------------------------------------------------------------------
    -- Status / Resource / Gemstone reports
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Status Report\"") then
        Spellup.status_check(osa)

    elseif line:match(p.from_cmd .. "Resource Report\"") then
        Spellup.resource_check(osa)

    elseif line:match(p.from_cmd .. "Gemstone Report\"") then
        Spellup.gemstone_check(osa)

    -- ---------------------------------------------------------------------------
    -- Spells / Spell Up
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Spells\"") then
        Spellup.spell_up(osa, osa.crew_channel, osa.supportlist)

    elseif line:match(p.from_cmd .. "Crew, Spell Up (.-)%.\"") then
        local pc = line:match("Crew, Spell Up (.-)\\.\"")
        if pc then Spellup.spell_individual(osa, pc) end

    -- ---------------------------------------------------------------------------
    -- Task Time
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Task Time!\"") then
        crew_check_task(osa)

    -- ---------------------------------------------------------------------------
    -- Deposit silvers
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Deposit\"") then
        fput("depo all")

    -- ---------------------------------------------------------------------------
    -- Sheath
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Sheath\"") then
        fput("sheath")

    -- ---------------------------------------------------------------------------
    -- Reset (restart osacrew)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Reset\"") then
        Script.kill("osacrew")
        wait_while(function() return Script.running("osacrew") end)
        Script.run("osacrew")

    -- ---------------------------------------------------------------------------
    -- Change Of Command
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Change Of Command: (.-)\"") then
        local new_cmd = line:match("Change Of Command: (.-)\"%s*$")
        if new_cmd and new_cmd ~= "" then
            osa.commander = new_cmd
            save_settings(osa)
            respond("")
            respond("   Your New Commanding Officer Is Now: " .. osa.commander)
            respond("")
        end

    -- ---------------------------------------------------------------------------
    -- Crew Swap (retune LNet channel)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Crew Swap: (.-)\"") then
        local new_ch = line:match("Crew Swap: (.-)\"%s*$")
        if new_ch and new_ch ~= "" then
            fput(";lnet untune " .. osa.crew_channel)
            pause(0.5)
            osa.crew_channel = new_ch
            save_settings(osa)
            pause(0.5)
            fput(";lnet tune " .. osa.crew_channel)
        end

    -- ---------------------------------------------------------------------------
    -- Pause / Unpause osacombat
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Pause\"") then
        if osa.osacombat and Script.running("osacombat") then
            Script.pause("osacombat")
        end

    elseif line:match(p.from_cmd .. "Unpause\"") then
        if osa.osacombat and Script.running("osacombat") then
            Script.unpause("osacombat")
        end

    -- ---------------------------------------------------------------------------
    -- Mana request
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch .. "%]%-GSIV:(.-):%s*\"I Need (.-) Mana!\"$") then
        local manaperson, mana_types_str = line:match(
            "^%[" .. p.ch .. "%]%-GSIV:(.-): \"I Need (.-) Mana!\"$")
        if manaperson and mana_types_str and manaperson ~= charname then
            osa.matched_type = false
            if osa.my_mana_types then
                for _, mt in ipairs(osa.my_mana_types) do
                    if mana_types_str:find(mt) then
                        osa.matched_type = true; break
                    end
                end
            end
            crew_send_mana(osa, manaperson)
        end

    -- ---------------------------------------------------------------------------
    -- Make Repairs
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Make Repairs!\"") then
        Repair.damage_control(osa, nav_fns(osa), save_settings)

    -- ---------------------------------------------------------------------------
    -- Can Anyone Bless? (commander asks, we respond if we can bless)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Can Anyone Bless%?\"") then
        if osa.givebless then
            LNet.private(osa.commander, "I Can Captain!")
            local req = matchtimeout(3,
                ep(charname) .. ", Will You Please Bless The Crew")
            if req then
                LNet.channel(osa.crew_channel, "Of Course Captain!")
                local blessname = {}
                LNet.channel(osa.crew_channel, "Does Anyone Need A Bless?")
                Spellup.who_needs_blessed(osa, blessname)
                for _, bname in ipairs(blessname) do
                    Spellup.give_bless(osa, bname)
                end
                LNet.channel(osa.crew_channel, "The Crew Has Been Properly Blessed Captain!")
            end
        end

    -- ---------------------------------------------------------------------------
    -- Commander designates a blesser
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "(.-), Will You Please Bless The Crew%?\"") then
        local blesser = line:match(ep(osa.commander) .. ": \"(.-), Will You Please Bless The Crew")
        if blesser then
            osa.blesser = blesser
            save_settings(osa)
        end

    -- ---------------------------------------------------------------------------
    -- Someone announces they will provide blessings
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Will Be Providing All Crew Blessings!\"") then
        local blesser = line:match("%]%-GSIV:(.-): \"I Will Be Providing")
        if blesser then
            osa.blesser = blesser
            save_settings(osa)
        end

    -- ---------------------------------------------------------------------------
    -- Quarters muster (report for duty)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Quarters! All Hands To Quarters For Muster") then
        pause(math.random(1, 5))
        LNet.private(osa.commander, "Crewman " .. charname .. " Reporting For Duty Captain!")

    -- ---------------------------------------------------------------------------
    -- Version check request
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Current Version Are As Follows") then
        LNet.channel(osa.crew_channel,
            "My Versions are as follows: Crew " .. VERSION)

    -- ---------------------------------------------------------------------------
    -- Report to location
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Crew, Report To: (.-)\"") then
        local dest = line:match("Crew, Report To: (.-)\"%s*$")
        if dest then
            local pcs = GameObj.pcs() or {}
            local cmd_present = false
            for _, pc in ipairs(pcs) do
                if pc.name == osa.commander then cmd_present = true; break end
            end
            if not cmd_present then
                Map.go2(dest)
                wait_while(function() return Script.running("go2") end)
            end
            pcs = GameObj.pcs() or {}
            for _, pc in ipairs(pcs) do
                if pc.name == osa.commander then
                    fput("join " .. osa.commander); break
                end
            end
        end

    -- ---------------------------------------------------------------------------
    -- Mana Spellup command
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Mana Spellup\"") then
        local prof = (Stats and Stats.prof) or ""
        if prof ~= "Warrior" and prof ~= "Rogue" then
            fput("mana spellup")
        end

    -- ---------------------------------------------------------------------------
    -- Crewman departing (remove from roster if commander)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"%*Ding%* %*Ding%* Crewman (.-) Departing!\"") then
        local _sender, departing = line:match(
            "%]%-GSIV:(.-): \"%*Ding%* %*Ding%* Crewman (.-) Departing!\"")
        if departing and charname == osa.commander then
            for i, n in ipairs(osa.crewsize) do
                if n == departing then
                    table.remove(osa.crewsize, i)
                    respond("   Removing " .. departing .. " From The Ship's Roster!")
                    save_settings(osa)
                    break
                end
            end
        end

    -- ---------------------------------------------------------------------------
    -- Crewman returning (add to roster if commander)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"Crewman (.-), Returning For Duty Captain!\"") then
        local _sender, returning = line:match(
            "%]%-GSIV:(.-): \"Crewman (.-), Returning For Duty Captain!\"")
        if returning and charname == osa.commander then
            local found = false
            for _, n in ipairs(osa.crewsize) do
                if n == returning then found = true; break end
            end
            if not found then
                table.insert(osa.crewsize, returning)
                respond("   Adding " .. returning .. " To The Ship's Roster!")
                save_settings(osa)
            end
        end

    -- ---------------------------------------------------------------------------
    -- Medical officer announces bread
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch .. "%]%-GSIV:" .. p.med ..
            ":%s*\"I Shall Supply The Bread!\"") then
        if osa.groupspellup or osa.selfspellup then
            fput("stow all")
            pause(math.random(1, 3))
            LNet.private(osa.medical_officer, "I Will Take Some Please.")
            crew_receive_bread(osa)
        end

    -- ---------------------------------------------------------------------------
    -- Let Us Break Bread Together (medical officer role)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"Let Us Break Bread Together!\"") then
        if osa.medical_officer:find(charname) then
            LNet.channel(osa.crew_channel, "I Shall Supply The Bread!")
            local breadlist = {}
            Medical.bread_orders(osa, breadlist)
            fput("stow all")
            fput("incant 203")
            crew_eat_bread()
            for _, person in ipairs(breadlist) do
                Medical.bread(osa, person)
            end
            LNet.channel(osa.crew_channel, "Bread Is Served!")
        end

    -- ---------------------------------------------------------------------------
    -- Connection test
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Connection Test: " .. ep(charname) .. "\"") then
        LNet.channel(osa.crew_channel, "Test Satisfactory Captain!")

    -- ---------------------------------------------------------------------------
    -- Lay Below (temporary dismissal)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Lay Below Crewman " .. ep(charname) .. "!\"") then
        LNet.channel(osa.crew_channel, "Lay Below, Aye Captain!")
        LNet.channel(osa.crew_channel, "*Ding* *Ding* Crewman " .. charname .. " Departing!")
        waitfor("^%[" .. p.ch .. "%]%-GSIV:" .. p.cmd2 ..
            ": \"Crewman " .. ep(charname) .. ", Quarterdeck!\"")
        LNet.channel(osa.crew_channel, "Crewman " .. charname .. ", Returning For Duty Captain!")

    -- ---------------------------------------------------------------------------
    -- Attention to Quarters
    -- ---------------------------------------------------------------------------
    elseif line:match("Attention To Quarters!") then
        fput("snap attention")
        waitfor("Post!")
        if osa.commander and charname ~= osa.commander then
            fput("salute " .. osa.commander)
        end

    -- ---------------------------------------------------------------------------
    -- Checking onboard (commander welcomes new crew)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[Private%]%-GSIV:(.-):%s*\"Crewman (.-) Checking Onboard Captain!\"") then
        if charname == osa.commander then
            local newcomer = line:match("%]%-GSIV:(.-): \"Crewman")
            if newcomer then
                pause(0.5)
                LNet.private(newcomer,
                    "Excellent Crewman " .. newcomer ..
                    ", Welcome Aboard! Our Medical Officer Is: " .. osa.medical_officer ..
                    ". Our Shipboard Communications Channel Is: " .. osa.crew_channel)
            end
        end

    -- ---------------------------------------------------------------------------
    -- Submit sever spell requests
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Submit your sever spell requests!\"") then
        pause(math.random(1, 3))
        -- (sever_spell vars not implemented; skip if empty)

    -- ---------------------------------------------------------------------------
    -- Collect sever spell requests (4-spell)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Require (.-), (.-), (.-) and (.-), Please\"") then
        local person, s1, s2, s3, s4 = line:match(
            "%]%-GSIV:(.-): \"I Require (.-), (.-), (.-) and (.-), Please\"")
        if person then
            table.insert(osa.severlist, {person, s1, s2, s3, s4})
        end

    -- ---------------------------------------------------------------------------
    -- Collect sever spell requests (3-spell)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Require (.-), (.-) and (.-), Please\"") then
        local person, s1, s2, s3 = line:match(
            "%]%-GSIV:(.-): \"I Require (.-), (.-) and (.-), Please\"")
        if person then
            table.insert(osa.severlist, {person, s1, s2, s3})
        end

    -- ---------------------------------------------------------------------------
    -- Collect sever spell requests (2-spell)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Require (.-) and (.-), Please\"") then
        local person, s1, s2 = line:match(
            "%]%-GSIV:(.-): \"I Require (.-) and (.-), Please\"")
        if person then
            table.insert(osa.severlist, {person, s1, s2})
        end

    -- ---------------------------------------------------------------------------
    -- Collect sever spell requests (1-spell)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Require (.-), Please\"") then
        local person, s1 = line:match("%]%-GSIV:(.-): \"I Require (.-), Please\"")
        if person then
            table.insert(osa.severlist, {person, s1})
        end

    -- ---------------------------------------------------------------------------
    -- Does Anyone Need Armor Adjustments? (respond with needs)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%].*\"Does Anyone Need Armor Adjustments%?\"") then
        pause(math.random(1, 3))
        local function request_armor(need_flag, spell_name, msg)
            if need_flag and Effects and Effects.Spells then
                if (Effects.Spells.time_left(spell_name) or 0) <= 120 then
                    LNet.channel(osa.crew_channel, msg)
                end
            end
        end
        request_armor(osa.need_armor_blessing,     "Armor Blessing",      "I Need Armor Blessing, Please")
        request_armor(osa.need_armor_reinforcement,"Armor Reinforcement", "I Need Armor Reinforcement, Please")
        request_armor(osa.need_armor_support,      "Armor Support",       "I Need Armor Support, Please")
        request_armor(osa.need_armor_casting,      "Armored Casting",     "I Need Armored Casting, Please")
        request_armor(osa.need_armor_evasion,      "Armored Evasion",     "I Need Armored Evasion, Please")
        request_armor(osa.need_armor_fluidity,     "Armored Fluidity",    "I Need Armored Fluidity, Please")
        request_armor(osa.need_armor_stealth,      "Armored Stealth",     "I Need Armored Stealth, Please")

    -- ---------------------------------------------------------------------------
    -- Crew member requests armor spec (add to supportlist if we have it)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Need (Armor|Armored) (.-), Please\"") then
        local person, _prefix, atype = line:match(
            "%]%-GSIV:(.-): \"I Need (Armor.-) (.-), Please\"")
        if person and atype and person ~= charname then
            local have_map = {
                Blessing      = osa.have_armor_blessing,
                Reinforcement = osa.have_armor_reinforcement,
                Support       = osa.have_armor_support,
                Casting       = osa.have_armor_casting,
                Evasion       = osa.have_armor_evasion,
                Fluidity      = osa.have_armor_fluidity,
                Stealth       = osa.have_armor_stealth,
            }
            if have_map[atype] then
                table.insert(osa.supportlist, {person, atype})
            end
        end

    -- ---------------------------------------------------------------------------
    -- Reactive opportunity combat
    -- ---------------------------------------------------------------------------
    elseif line:match("You could use this opportunity to (.-)!") then
        local opp = line:match("You could use this opportunity to (.-)!")
        if osa.use_reactive and opp then
            Combat.checkforenemies(osa)
            osa.reactive        = true
            osa.reactivetype    = opp
        else
            osa.reactive = false
        end

    -- ---------------------------------------------------------------------------
    -- Private medical requests (heal/spells/dims/bread/surge)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[Private%]%-GSIV:(.-):%s*\"(heal|spells|dims|bread|surge KS|surge)\"") then
        if osa.medical_officer:find(charname) then
            local person, req = line:match(
                "%]%-GSIV:(.-): \"(heal|spells|dims|bread|surge KS|surge)\"")
            if person and req then
                Script.pause("osacombat")
                if req == "heal" then
                    osa.medicalofficer_patient = {person}
                    Medical.checkup(osa, osa.medicalofficer_patient)
                    osa.medicalofficer_patient = {}
                elseif req == "surge KS" then
                    Medical.fix_muscles_ks(osa, person)
                elseif req == "surge" then
                    Medical.fix_muscles(osa, person)
                elseif req == "dims" then
                    -- dims is treated as poison/disease check
                    Medical.fix_poison(osa, person)
                elseif req == "spells" then
                    Medical.spells(osa, person)
                elseif req == "bread" then
                    Medical.bread(osa, person)
                end
                Script.unpause("osacombat")
            end
        end

    -- ---------------------------------------------------------------------------
    -- I Am Poisoned
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Am Poisoned!\"$") then
        if osa.medical_officer:find(charname) then
            local person = line:match("%]%-GSIV:(.-): \"I Am Poisoned!\"")
            if person then
                Script.pause("osacombat")
                Medical.fix_poison(osa, person)
                Script.unpause("osacombat")
            end
        end

    -- ---------------------------------------------------------------------------
    -- I Am Diseased
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Am Diseased!\"$") then
        if osa.medical_officer:find(charname) then
            local person = line:match("%]%-GSIV:(.-): \"I Am Diseased!\"")
            if person then
                Script.pause("osacombat")
                Medical.fix_disease(osa, person)
                Script.unpause("osacombat")
            end
        end

    -- ---------------------------------------------------------------------------
    -- I Am Injured
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[" .. p.ch ..
            "%]%-GSIV:(.-):%s*\"I Am Injured!\"$") then
        if osa.medical_officer:find(charname) then
            local person = line:match("%]%-GSIV:(.-): \"I Am Injured!\"")
            if person then
                Script.pause("osacombat")
                osa.medicalofficer_patient = {person}
                Medical.triage(osa, osa.medicalofficer_patient)
                Medical.checkup(osa, osa.medicalofficer_patient)
                Script.unpause("osacombat")
                osa.medicalofficer_patient = {}
            end
        end

    -- ---------------------------------------------------------------------------
    -- Enemy captain boards (trigger eloot + cleanup)
    -- ---------------------------------------------------------------------------
    elseif line:match("(Krolvin|Pirate|Ethereal) Captain shouts in rage aboard the") then
        if osa.cleanup and charname == osa.commander then
            wait_until(function()
                local targets = GameObj.targets() or {}
                for _, npc in ipairs(targets) do
                    local st = npc.status or ""
                    local nm = npc.name   or ""
                    local nn = npc.noun   or ""
                    if not st:find("dead") and not st:find("gone")
                       and not nm:find("animated") and not nn:find("arm")
                       and not nn:find("tentacle") then
                        return false
                    end
                end
                return true
            end)
            Script.run("eloot")
            wait_while(function() return Script.running("eloot") end)
            Script.run("osacommander", "cleanup")
        end

    -- ---------------------------------------------------------------------------
    -- Rogue wave (piratehunter)
    -- ---------------------------------------------------------------------------
    elseif line:match("A large swell crashes into the side of the") then
        if osa.piratehunter then
            Script.pause("osacommander")
            waitrt()
            Map.go_to_tag(osa, "helm")
            fput("yell Rogue Wave! Secure the Anchor!")
            waitrt()
            waitcastrt()
            Nav.raise_anchor()
            fput("turn wheel ship")
            waitrt()
            Map.go_to_tag(osa, "captains_quarters")
            Script.unpause("osacommander")
        end

    -- ---------------------------------------------------------------------------
    -- Sails furled (piratehunter)
    -- ---------------------------------------------------------------------------
    elseif line:match("The sound of ropes coming free of the rigging") then
        if osa.piratehunter then
            Script.pause("osacommander")
            waitrt()
            fput("yell The Sails Have Furled, Let Go the Halyard, Sheets, and Braces!")
            waitrt()
            waitcastrt()
            Map.go_to_tag(osa, "main_deck")
            unfurl_masts(osa)
            fput("turn wheel ship")
            waitrt()
            Map.go_to_tag(osa, "captains_quarters")
            Script.unpause("osacommander")
        end

    -- ---------------------------------------------------------------------------
    -- Off course drift (piratehunter)
    -- ---------------------------------------------------------------------------
    elseif line:match("The (.-) suddenly drifts from its course as the") then
        if osa.piratehunter then
            echo("The Ship Has Gone Off Course")
            Script.pause("osacommander")
            waitrt()
            Map.go_to_tag(osa, "helm")
            waitcastrt()
            Nav.crew_det_drift(osa)
            echo("Corrective Course Determined")
            Nav.crew_fix_wheel(osa, Map)
            fput("turn wheel ship")
            waitrt()
            Map.go_to_tag(osa, "captains_quarters")
            Script.unpause("osacommander")
        end

    -- ---------------------------------------------------------------------------
    -- Enemy ship approaching (start osacommander if piratehunter + commander)
    -- ---------------------------------------------------------------------------
    elseif line:match("A distant thudding of the drums of war|As the water falls.*materializes|carves through the ocean toward your") then
        if charname == osa.commander and osa.piratehunter then
            wait_until(function()
                local pcs = GameObj.pcs() or {}
                for _, pc in ipairs(pcs) do
                    local st = pc.status or ""
                    if st:find("sitting") or st:find("lying") or st:find("prone") or st:find("stunned") then
                        return false
                    end
                end
                return true
            end)
            Script.run("osacommander", "start")
        end

    -- ---------------------------------------------------------------------------
    -- Cannon fire from enemy (piratehunter)
    -- ---------------------------------------------------------------------------
    elseif line:match("A sudden booming of cannon fire erupts from the enemy") then
        if charname == osa.commander and not osa.boarding and osa.piratehunter then
            wait_until(function()
                local pcs = GameObj.pcs() or {}
                for _, pc in ipairs(pcs) do
                    local st = pc.status or ""
                    if st:find("sitting") or st:find("lying") or st:find("prone") or st:find("stunned") then
                        return false
                    end
                end
                return true
            end)
            Script.run("osacommander", "start")
        end

    -- ---------------------------------------------------------------------------
    -- 30-second warning
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd ..
            "Thirty second warning, drop what yer doing and prepare for battle") then
        osa.cannoneer_thirty = true

    -- ---------------------------------------------------------------------------
    -- Ships collide (boarding)
    -- ---------------------------------------------------------------------------
    elseif line:match("The sides of the (.-) collide against your (.-)") then
        osa.cannoneer_boarded = true

    -- ---------------------------------------------------------------------------
    -- "Send them to the bottom boys!" (target random)
    -- ---------------------------------------------------------------------------
    elseif line:match(ep(osa.commander) .. '.* exclaims, "Send them to the bottom boys!"') then
        fput("target random")

    -- ---------------------------------------------------------------------------
    -- Crew injured private message (commander holds for them)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[Private%]%-GSIV:(.-):%s*\"Captain, I've Been Injured and Will Return Shortly\"") then
        if charname == osa.commander then
            local injured = line:match("%]%-GSIV:(.-): \"Captain, I've Been Injured")
            if injured then
                if Script.running("osacombat") then Script.pause("osacombat") end
                if Script.running("osacommander") then Script.pause("osacommander") end
                local room = Room and Room.current and Room.current()
                local room_id = room and room.id or "unknown"
                LNet.private(injured, "Ok Crewman, We Are At " .. room_id .. " And Will Await Your Arrival")
                wait_until(function()
                    local pcs = GameObj.pcs() or {}
                    for _, pc in ipairs(pcs) do
                        if pc.name == injured then return true end
                    end
                    return false
                end)
                fput("hold " .. injured)
            end
        end

    -- ---------------------------------------------------------------------------
    -- Ship moored (update gangplank wayto)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd ..
            "(.-) Is Now Moored In (.-) Room Number: (%d+)") then
        local _ship, _town, room_id = line:match(
            ep(osa.commander) .. ": \"(.-) Is Now Moored In (.-) Room Number: (%d+)")
        if room_id then
            if osa.gangplank then
                if Map.del_tag then Map.del_tag(osa.gangplank, "myship") end
                Map.crew_clear_gangplank(osa)
            end
            osa.gangplank = tonumber(room_id)
            save_settings(osa)
            if Map.add_tag then Map.add_tag(osa.gangplank, "myship") end
            Map.crew_map_gangplank(osa)
        end

    -- ---------------------------------------------------------------------------
    -- Silvers (give coins to commander)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Silvers\"") then
        crew_give_coins(osa)

    -- ---------------------------------------------------------------------------
    -- Sell Your Loot
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Crew, Sell Your Loot!\"") then
        if osa.lootsell then
            crew_sell_loot(osa)
        else
            pause(5)
            crew_task_complete(osa)
        end

    -- ---------------------------------------------------------------------------
    -- At Ease (wait for mind < 100)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "At Ease, Crew!\"") then
        wait_until(function() return (Char.mind_pct or 0) < 100 end)
        crew_task_complete(osa)

    -- ---------------------------------------------------------------------------
    -- Services requested at a location (tpick ground)
    -- ---------------------------------------------------------------------------
    elseif line:match("^%[Private%]%-GSIV:" .. p.cmd2 ..
            ":%s*\"Your Services Are Requested At (.-) Crewman\"") then
        local dest = line:match("Services Are Requested At (.-) Crewman\"")
        if dest then
            Map.go2(dest)
            wait_while(function() return Script.running("go2") end)
            waitfor("^%[Private%]%-GSIV:" .. p.cmd2 .. ": \"That's All Of Them!\"")
            Script.run("tpick", "ground")
            wait_while(function() return Script.running("tpick") end)
            pause(5)
            LNet.private(osa.commander, "All Set, Captain!")
            Map.go_to_tag(osa, "captains_quarters")
        end

    -- ---------------------------------------------------------------------------
    -- Group tracking
    -- ---------------------------------------------------------------------------
    elseif line:match("(.-) removes you from") or
           line:match("(.-) disband") then
        group_clear(osa)

    elseif line:match("You join (.*)|(.+) gently takes hold of your hand") then
        determine_group_members(osa)

    elseif line:match("(.-) removes (.-) from the group%.") then
        local removed = line:match("removes (.-) from the group%.")
        if removed then group_remove(osa, removed) end

    elseif line:match("(.-) gently takes hold of (.+)'s hand%.") then
        local taker, taken = line:match("(.-) gently takes hold of (.+)'s hand%.")
        if taker and taken then
            local in_my = false
            for _, n in ipairs(osa.everyone_in_group) do
                if n == taker or taker == "You" then in_my = true; break end
            end
            if taker == "You" or in_my then
                group_add(osa, taken)
            end
        end

    elseif line:match("You notice your companion ([A-Z]%a+) slip away into hiding%.") then
        local hider = line:match("You notice your companion ([A-Z]%a+) slip away into hiding%.")
        if hider then hidden_add(osa, hider) end

    elseif line:match("You notice your companion ([A-Z]%a+) emerge from hiding nearby") then
        local emerger = line:match("You notice your companion ([A-Z]%a+) emerge from hiding")
        if emerger then hidden_remove(osa, emerger) end

    elseif line:match("(.-) joins your group%.") then
        local joiner = line:match("(.-) joins your group%.")
        if joiner then group_add(osa, joiner) end

    elseif line:match("You are leading (.*)%.") or
           line:match("You are grouped with (.*)%.") then
        determine_group_members(osa)

    elseif line:match("You leave (.+)'s group%.") or
           line:match("You are not currently in a group%.") then
        group_clear(osa)

    -- ---------------------------------------------------------------------------
    -- Stealth disabler (enemy hiding)
    -- ---------------------------------------------------------------------------
    elseif line:match("^Something stirs in the shadows%.")
        or line:match("^A (.-) darts into the shadows") then
        if osa.stealth_disabler ~= 0 then
            Combat.stealth_disabler_routine(osa)
            fput("target random")
        end

    -- ---------------------------------------------------------------------------
    -- Enable / Disable poaching
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Enable Poaching!\"") then
        if not osa.check_for_group then
            osa.check_for_group = true
            save_settings(osa)
            respond("")
            respond("-----------------------***|   Poaching Has Been Enabled   |***----------------------------")
            respond("")
        else
            respond("")
            respond("-----------------------***|   Poaching Is Already Enabled   |***----------------------------")
            respond("")
        end

    elseif line:match(p.from_cmd .. "Disable Poaching!\"") then
        if osa.check_for_group then
            osa.check_for_group = false
            save_settings(osa)
            respond("")
            respond("-----------------------***|   Poaching Has Been Disabled   |***----------------------------")
            respond("")
        else
            respond("")
            respond("-----------------------***|   Poaching Is Already Disabled   |***----------------------------")
            respond("")
        end

    -- ---------------------------------------------------------------------------
    -- Loot the Dead
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Loot the Dead, (.-)!\"") then
        local target = line:match("Loot the Dead, (.-)\"%s*$")
        if target then
            if target == charname or target == "Crew" then
                osa.osalooter = true
                respond("")
                if target == charname then
                    respond("Switching to Primary Party Looter")
                else
                    respond("Switching On Loot The Dead")
                end
                respond("")
            else
                osa.osalooter = false
            end
        end

    -- ---------------------------------------------------------------------------
    -- Steel Yourself (named individual)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Steel Yourself, " .. ep(charname) .. "!\"") then
        if not Script.running("osacombat") then
            Script.run("osacombat")
            pause(math.random(1, 8))
            LNet.private(osa.commander, "Ready For Combat Captain!")
        end

    -- ---------------------------------------------------------------------------
    -- Steel Yourselves Crew (all crew to combat)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Steel Yourselves Crew!\"") then
        if not Script.running("osacombat") then
            Script.run("osacombat")
            pause(math.random(1, 8))
            LNet.private(osa.commander, "Ready For Combat Captain!")
        end

    -- ---------------------------------------------------------------------------
    -- Tenebrous Cauldron (enemy ship sunk)
    -- ---------------------------------------------------------------------------
    elseif line:match("Tenebrous Cauldron%.  Victory is yours!") then
        if Script.running("osacommander") then
            osa.boarding = false
        end

    -- ---------------------------------------------------------------------------
    -- Enemy ship sinking
    -- ---------------------------------------------------------------------------
    elseif line:match("rapidly descends beneath the cold, dark waters%.") then
        if Script.running("osacommander") then
            osa.sunk_ship = true
        end

    -- ---------------------------------------------------------------------------
    -- Weapon torn free (record name)
    -- ---------------------------------------------------------------------------
    elseif line:match("^Your (.-) tears free from your hands and floats threateningly") then
        local weapon = line:match("^Your (.-) tears free")
        if weapon then
            -- Extract noun (last word)
            osa.myweapon = weapon:match("(%S+)%s*$") or weapon
        end

    -- ---------------------------------------------------------------------------
    -- Disease status
    -- ---------------------------------------------------------------------------
    elseif line:match("^A virulent green mist seeps out of") then
        osa.healing_status = "diseased"

    -- ---------------------------------------------------------------------------
    -- Spell Up Completed (Kroderine Soul join)
    -- ---------------------------------------------------------------------------
    elseif line:match(p.from_cmd .. "Spell Up Completed\"") then
        if Feat and Feat.known and Feat.known("Kroderine Soul") then
            pause(0.5)
            fput("join " .. osa.commander)
        end

    -- ---------------------------------------------------------------------------
    -- Dock workers shout (anti-stow trigger for commander)
    -- ---------------------------------------------------------------------------
    elseif line:match("A collection of dock workers can be heard shouting from nearby") then
        if charname == osa.commander and osa.anti_stow and not osa.no_stow then
            Script.run("osacommander", "anti_stow")
        end

    -- ---------------------------------------------------------------------------
    -- Obvious hiding (record for anti-poaching)
    -- ---------------------------------------------------------------------------
    elseif line:match("obvious signs of someone hiding") then
        osa.pc_hiding      = true
        local room = Room and Room.current and Room.current()
        osa.pc_hiding_room = room and room.id
    end
end
