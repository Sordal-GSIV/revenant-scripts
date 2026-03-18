--- @revenant-script
--- name: eloot
--- version: 2.7.0
--- author: elanthia-online
--- contributors: SpiffyJr, Athias, Demandred, Tysong, Deysh, Ondreian, Lieo, Lobe, Etheirys
--- game: gs
--- description: Loot/sell pipeline — skin, search, box, sell, pool, hoard, bounty integration
--- tags: loot, sell, skin, boxes, pool, hoard, bounty
--- @lic-audit: validated 2026-03-18
---
--- Changelog (recent):
---   v2.7.0  (2026-01-19) ground looting, group disk box support, ingot selling, trash verb
---   v2.6.7  (2026-01-18) silver breakdown bugfix
---   v2.6.6  (2026-01-17) bank withdraw bugfix, disable f2p locksmith pool
---   v2.6.5  (2026-01-16) new loot commands in locksmith pool
---   v2.6.4  (2026-01-12) upper limit of appraisal from 1M to 10M
---   v2.6.3  (2025-12-02) failed bounty children NPC fix, debug update, blood band fix
---   v2.6.2  (2025-11-21) force looting of bounty heirloom items
---   v2.6.1  (2025-11-11) open_loot_containers and get_weapon_inv fixes
---   v2.6.0  (2025-10-26) bloodband support, save_trash_box fix, tip default fix
---   v2.5.7  (2025-10-19) debt bugfix for locker entry
---   v2.5.6  (2025-10-08) ranged weapon store/ready fix
---   v2.5.5  (2025-10-05) non-standard ready/stow list items fix
---   v2.5.4  (2025-10-04) nil items fix, return_hands logic fix
---   v2.5.3  (2025-10-03) return_hands bugfix, toggle righthand/lefthand off
---   v2.5.2  (2025-10-02) incorrect method call typo fix
---   v2.5.1  (2025-09-30) store/ready secondary_weapon to 2weapon fix
---   v2.5.0  (2025-09-19) ReadyList/StowList migration, SG trash fix
---   v2.4.11 (2025-09-12) always use locksmith on gem bounty option
---   v2.4.10 (2025-09-06) rework box contents check, coins on ground fix
---   v2.4.9  (2025-09-05) regex fix in use_coin_hand
---   v2.4.8  (2025-08-30) coin_bag_full false when empty fix
---   v2.4.7  (2025-08-15) debug file with parameter start support
---   v2.4.6  (2025-08-12) encumbered after box opening — deposit silvers fix
---   v2.4.5  (2025-07-22) default locksmith_withdrawal_amount fix
---   v2.4.4  (2025-07-16) custom tip withdrawal, bulk sell typo, overflow clean
---   v2.4.3  (2025-07-15) town locksmith regex fix
---   v2.4.2  (2025-07-09) f2p silver withdrawal fix
---   v2.4.1  (2025-06-05) lighten load in pool return, box loot coin deposit fix

-- ---------------------------------------------------------------------------
-- Submodule requires
-- ---------------------------------------------------------------------------

local Data        = require("gs.eloot.data")
local Settings    = require("gs.eloot.settings")
local Util        = require("gs.eloot.util")
local Inventory   = require("gs.eloot.inventory")
local Loot        = require("gs.eloot.loot")
local Sell        = require("gs.eloot.sell")
local Pool        = require("gs.eloot.pool")
local Hoard       = require("gs.eloot.hoard")
local Region      = require("gs.eloot.region")
local GuiSettings = require("gs.eloot.gui_settings")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local VERSION = "2.7.0"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Display help text.
local function show_help()
    local name = Script.name or "eloot"
    respond("")
    respond("  *** Mark ANYTHING you don't want to lose. Eloot is not perfect! ***")
    respond("  " .. string.rep("-", 60))
    respond(string.format("  %-45s %s", "Command", "Description"))
    respond("  " .. string.rep("-", 60))
    respond(string.format("  %-45s %s", ";" .. name .. " setup", "Settings window"))
    respond("")
    respond(string.format("  %-45s %s", ";" .. name, "Loots items/creatures"))
    respond(string.format("  %-45s %s", ";" .. name .. " ground", "Loots open boxes on the ground"))
    respond(string.format("  %-45s %s", ";" .. name .. " sell", "Sells loot based on settings"))
    respond(string.format("  %-45s %s", ";" .. name .. " sell alchemy_mode", "Sell without reagents"))
    respond(string.format("  %-45s %s", ";" .. name .. " deposit", "Deposits coins and notes"))
    respond("")
    respond(string.format("  %-45s %s", ";" .. name .. " pool", "Locksmith pool"))
    respond(string.format("  %-45s %s", ";" .. name .. " pool deposit", "Only deposit boxes"))
    respond(string.format("  %-45s %s", ";" .. name .. " pool return", "Only return boxes"))
    respond("  " .. string.rep("-", 60))
    respond("  Command Line Options")
    respond("  " .. string.rep("-", 60))
    respond(string.format("  %-45s %s", ";" .. name .. " --sellable <categories>", "GameObj sellable categories"))
    respond(string.format("  %-45s %s", ";" .. name .. " --type <things>", "GameObj types"))
    respond(string.format("  %-45s %s", ";" .. name .. " --sell <items>", "Specific items"))
    respond("  " .. string.rep("-", 60))
    respond("  Hoarding")
    respond("  " .. string.rep("-", 60))
    respond(string.format("  %-45s %s", ";" .. name .. " list <gem/reagent>", "List hoarded inventory"))
    respond(string.format("  %-45s %s", ";" .. name .. " reset <gem/reagent>", "Reset hoarded inventory"))
    respond(string.format("  %-45s %s", ";" .. name .. " deposit <gem/reagent>", "Deposit into hoard"))
    respond(string.format("  %-45s %s", ";" .. name .. " raid <type> <item> x<N>", "Raid hoard"))
    respond(string.format("  %-45s %s", ";" .. name .. " bounty", "Raid hoard for bounty gems"))
    respond("  " .. string.rep("-", 60))
    respond("  Troubleshooting")
    respond("  " .. string.rep("-", 60))
    respond(string.format("  %-45s %s", ";" .. name .. " debug", "Toggle debug mode"))
    respond(string.format("  %-45s %s", ";" .. name .. " debug file", "Toggle debug to file"))
    respond(string.format("  %-45s %s", ";" .. name .. " list", "List script settings"))
    respond("  " .. string.rep("-", 60))
    respond("  *** Mark ANYTHING you don't want to lose. Eloot is not perfect! ***")
    respond("")
end

--- Manage sorter script (kill and schedule restart).
local function manage_sorter(data)
    if running and running("sorter") then
        kill_script("sorter")
        before_dying(function()
            Script.run("sorter")
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Main entry point
-- ---------------------------------------------------------------------------

local args = Script.vars or {}
local cmd = args[1]

-- Version check
if cmd and cmd:lower():find("^ver") then
    respond("   Eloot Version: " .. VERSION)
    return
end

-- Dead check
if dead and dead() then
    Util.msg({ type = "yellow", text = " You appear to be dead, please rerun ELoot when you're not!", space = true })
    return
end

-- Berserk check
if Spell and Spell[1015] and Spell[1015].active then
    Util.msg({ type = "info", text = " Berserk is active, preventing you from looting.", space = true })
    return
end

-- Startup delay for autostart
if cmd and cmd:lower() == "start" then
    pause(2)
end

-- Initialize / Load settings
local data = Data.init()

local settings = Settings.load()
data.settings = settings
data.version = VERSION

-- Set inventory containers
Inventory.set_inventory(data)

-- Disk usage
Util.disk_usage(data)

-- Exit early for load command
if args[0] and args[0]:lower():find("load") then
    return
end

-- Track full sacks
if not data.settings.track_full_sacks then
    data.sacks_full = {}
    Util.reset_disk_full(data)
end

-- Group module check
if Group and Group.checked then
    if not Group.checked() then
        local lines = Util.get_command("group",
            { "^You are (?:grouped|leading|not currently)" }, nil, data)
    end
end

-- Sync up group disk variables
Util.reset_disk_full(data, false)

-- Sorter management
manage_sorter(data)

-- before_dying cleanup
before_dying(function()
    DownstreamHook.remove("eloot_diskintegration")
end)

-- ---------------------------------------------------------------------------
-- Command dispatch
-- ---------------------------------------------------------------------------

local full_cmd = args[0] or ""

if not cmd then
    -- Default: loot (skin + search + room)
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end

    Util.disk_usage(data)
    Loot.loot(data)

    if data.settings.keep_closed then
        Inventory.close_sell_containers(data)
    end

    return
end

-- Need a mapped room for everything below
if not Room.current() or not Room.current().id then
    Util.msg({ type = "yellow", text = " Please start " .. (Script.name or "eloot") .. " in a mapped room", space = true }, data)
    return
end

data.start_room = Room.current().id
_G.sell_ignore = _G.sell_ignore or {}
data.silver_breakdown = {}

-- Match command patterns
local cmd_lower = full_cmd:lower()

if cmd_lower:find("^debug") then
    -- Toggle debug mode
    local parts = {}
    for word in cmd_lower:gmatch("%S+") do parts[#parts + 1] = word end
    if parts[#parts] == "file" then
        data.settings.debug_file = not data.settings.debug_file
        Settings.save(data)
    else
        data.settings.debug = not data.settings.debug
        Settings.save(data)
    end

elseif cmd_lower == "start" then
    -- Already handled above
    return

elseif cmd_lower == "list" and not args[2] then
    -- List all settings
    Settings.list(data)

elseif cmd_lower:find("^box") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end

    local box = nil
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()

    if rh and rh.type and rh.type:find("box") then
        box = rh
        Inventory.free_hands({ left = true }, data)
    elseif lh and lh.type and lh.type:find("box") then
        box = lh
        Inventory.free_hands({ right = true }, data)
    elseif args[2] and args[2]:match("^%d+$") then
        local target_id = tonumber(args[2])
        local loot = GameObj.loot() or {}
        for _, l in ipairs(loot) do
            if tonumber(l.id) == target_id then
                box = l
                break
            end
        end
    end

    if box then
        Loot.box_loot(box, data)
    end
    Util.go2(data.start_room, data)

elseif cmd_lower:find("^sell") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end
    waitrt()

    -- Reset sack status
    data.sacks_full = {}

    if args[2] and args[2]:lower() == "alchemy_mode" then
        data.alchemy_mode = true
    end

    Util.disk_usage(data)
    Sell.sell(data)

    -- Reset bags after selling
    data.sacks_full = {}

    Util.go2(data.start_room, data)
    Sell.breakdown(data)
    data.alchemy_mode = false

elseif cmd_lower:find("^pool") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end

    local arg2 = args[2]
    local check = true
    local deposit_flag = true

    if arg2 then
        check = arg2:lower():find("check") or arg2:lower():find("return") or arg2:lower():find("loot")
        deposit_flag = arg2:lower():find("depo") ~= nil
    end

    Util.disk_usage(data)
    Pool.pool({ deposit = deposit_flag, check = check }, data)

    Sell.breakdown(data)

elseif full_cmd:find("%-%-sell") or full_cmd:find("%-%-sellable") or full_cmd:find("%-%-type") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end

    local match_type, things = full_cmd:match("%-%-(%w+)%s*=?%s*(.+)")
    if match_type and things then
        if match_type == "sellable" then
            Sell.custom_sellable(things, data)
        elseif match_type == "type" then
            Sell.custom_type(things, data)
        elseif match_type == "sell" then
            Sell.custom_list(things, data)
        end
    end

    Util.go2(data.start_room, data)
    Sell.breakdown(data)

elseif cmd_lower:find("^settings") or cmd_lower:find("^setup") then
    if args[2] then
        -- CLI settings update
        local setting_args = {}
        for i = 2, #args do
            setting_args[#setting_args + 1] = args[i]
        end
        Util.update_setting(setting_args, data)
    else
        -- GUI settings
        GuiSettings.open(data, function(new_settings)
            data.settings = new_settings
            Settings.save(data)
            Util.msg({ text = " Settings saved.", space = true }, data)
        end)
    end

elseif cmd_lower:find("^options") then
    -- List all setting names
    local keys = {}
    for k, _ in pairs(data.settings) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    Util.msg({ type = "default", text = table.concat(keys, "\n") }, data)

elseif cmd_lower:find("^raid") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end
    Hoard.raid_cache(args, data)
    Util.go2(data.start_room, data)

elseif cmd_lower:find("^(list)%s") or cmd_lower:find("^(deposit)%s") or cmd_lower:find("^(reset)%s") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end

    local do_what = args[1]:lower()
    local item = args[2] and args[2]:lower() or ""

    local hoard_type
    if item:find("reagent") or item:find("alchemy") then
        hoard_type = "alchemy"
    elseif item:find("gem") then
        hoard_type = "gem"
    end

    if hoard_type then
        if do_what:find("list") then
            Hoard.list_inventory(hoard_type, data)
        elseif do_what:find("deposit") then
            Hoard.hoard_items(hoard_type, true, data)
        elseif do_what:find("reset") then
            Hoard.reset_inventory(hoard_type, data)
            Hoard.list_inventory(hoard_type, data)
        end
    end

    Util.go2(data.start_room, data)

elseif cmd_lower:find("^bounty") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end
    Hoard.get_gem_bounty(data)

elseif cmd_lower:find("^load") then
    waitrt()
    data = Data.init()
    data.settings = Settings.load()
    Inventory.set_inventory(data)

elseif cmd_lower:find("^deposit") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end
    Util.silver_deposit(true, data)
    Util.go2(data.start_room, data)

elseif cmd_lower:find("^skin") then
    if data.settings.debug_file then
        data.debug_logger = Util.debug_logger_new(data)
    end
    Loot.skin(data)

elseif cmd_lower:find("^ground") then
    Loot.box_loot_ground(data)

elseif cmd_lower:find("^help") then
    show_help()

else
    show_help()
end
