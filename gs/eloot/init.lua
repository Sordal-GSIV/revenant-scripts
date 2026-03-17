--- @revenant-script
--- name: eloot
--- version: 1.0.0
--- author: elanthia-online
--- original_author: SpiffyJr (sloot)
--- contributors: SpiffyJr, Athias, Demandred, Tysong, Deysh, Ondreian, Lieo, Lobe, Etheirys
--- depends: go2 >= 1.0
--- description: Full loot/sell/hoard pipeline
--- game: gs
---
--- Changelog (from Lich5):
---   v2.7.0 (2026-01-19)
---     - added ground looting of boxes
---     - added support for group disks when looting boxes
---     - added selling of ingots if too heavy to store
---     - updated find_trash to fully use trash verb
---     - general inventory code cleanup
---     - bugfix for depositing extra silver in pool method
---     - bugfix in go2_locker to stop withdrawing silver when using house locker
---   v2.6.7 (2026-01-18)
---     - bugfix in silver breakdown
---   v2.6.6 (2026-01-17)
---     - bugfix for bank withdraw
---     - disable f2p locksmith pool
---   v2.6.5 (2026-01-16)
---     - update for new loot commands in locksmith pool
---   v2.6.4 (2026-01-12)
---     - increase upper limit of appraisal amount from 1,000,000 to 10,000,000
---   v2.6.3 (2025-12-02)
---     - bugfix trying to skin/loot failed bounty children npcs
---     - update debug messaging
---     - bugfix in blood band/bracer settings
---   v2.6.2 (2025-11-21)
---     - force looting of bounty heirloom items if found
---   v2.6.1 (2025-11-11)
---     - bugfix in open_loot_containers
---     - bugfix in get_weapon_inv
---   v2.6.0 (2025-10-26)
---     - add bloodband support
---     - bugfix for save_trash_box method
---     - bugfix box tipping default missing on first run
---     - bugfix for open_single_container when using a string
---     - moved tooltips out of UI xml
---   v2.5.7 (2025-10-19)
---     - bugfix for debt when entering locker
---   v2.5.6 (2025-10-08)
---     - bugfix for store/ready ranged_weapon to ranged
---   v2.5.5 (2025-10-05)
---     - bugfix for non-standard ready/stow list items
---   v2.5.4 (2025-10-04)
---     - bugfix for nil items
---     - bugfix in logic for return_hands
---   v2.5.3 (2025-10-03)
---     - bugfix for return_hands
---     - toggle righthand and lefthand off at initialization
---     - minimum lich version to 5.12.9
---   v2.5.2 (2025-10-02)
---     - bugfix for incorrect method call typo
---   v2.5.1 (2025-09-30)
---     - bugfix for store/ready secondary_weapon to 2weapon
---   v2.5.0 (2025-09-19)
---     - switch to using Lich methods ReadyList and StowList
---     - removed change log in script before 2.4.0
---     - fix for SG trash can
---   v2.4.11 (2025-09-12)
---     - add option to always use the locksmith when a gem bounty is active
---   v2.4.10 (2025-09-06)
---     - rework box contents check to store box instead of pausing
---     - bugfix for looting coins on the ground
---   v2.4.9 (2025-09-05)
---     - bugfix in regex for use_coin_hand method
---   v2.4.8 (2025-08-30)
---     - bugfix for setting ELoot.data.coin_bag_full to false when empty
---   v2.4.7 (2025-08-15)
---     - if debug to file enabled, allow for when started with a parameter
---   v2.4.6 (2025-08-12)
---     - fix encumbered after box opening by depositing silvers in process_boxes
---   v2.4.5 (2025-07-22)
---     - bugfix for default locksmith_withdrawl_amount
---   v2.4.4 (2025-07-16)
---     - allow customizable locksmith tip amount withdrawal
---     - typo correction in bulk sell gem method
---     - force clean overflow containers from sell_container list
---     - utilize File.join for save/load
---     - bugfix in pool_return to allow up to 2 seconds for GameObj
---     - remove Unicode characters in formula explanation
---   v2.4.3 (2025-07-15)
---     - bugfix for town locksmith regex to open box after return being too generic
---   v2.4.2 (2025-07-09)
---     - bugfix for silver withdrawals failing on f2p accounts
---   v2.4.1 (2025-06-05)
---     - bugfix for unable to lighten load during pool return
---     - bugfix for box loot to deposit coins if too many
---     - change class checks to is_a? checks
---   Full prior changelog: https://gswiki.play.net/Lich:Script_Eloot

local args_lib = require("lib/args")
local settings = require("settings")
local data = require("data")
local loot = require("loot")
local sell = require("sell")
local boxes = require("boxes")
local hoard = require("hoard")
local disk = require("disk")

local state = settings.load()
disk.install_monitor()
before_dying(function() disk.remove_monitor() end)

local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

local function show_help()
    respond("Usage: ;eloot [command]")
    respond("")
    respond("Commands:")
    respond("  (no args)        Loot: skin + search + room")
    respond("  sell             Full sell cycle (gems, skins, scrolls, deposit)")
    respond("  deposit          Deposit silver at bank")
    respond("  box              Loot box in hand")
    respond("  ground           Loot all boxes on the ground")
    respond("  pool             Locksmith pool: deposit + return boxes")
    respond("  pool deposit     Deposit boxes to locksmith pool")
    respond("  pool return      Retrieve and loot boxes from locksmith pool")
    respond("  hoard [gem|alchemy]  Hoard items to locker (default: gem)")
    respond("  raid <gem|alchemy> <item> [count]  Take items from hoard locker")
    respond("  skin             Skin only")
    respond("  setup            Open settings GUI")
    respond("  settings <k> <v> Update a setting")
    respond("  list             Show current settings")
    respond("  help             Show this help")
end

if cmd == "help" then
    show_help()
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "list" then
    respond("[eloot] Current settings:")
    for k, v in pairs(state) do
        if type(v) == "table" then
            respond("  " .. k .. " = " .. table.concat(v, ", "))
        else
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "settings" then
    local key = parsed.args[2]
    local val = parsed.args[3]
    if not key or not val then
        respond("Usage: ;eloot settings <key> <value>")
        return
    end
    if val == "on" or val == "true" then val = true
    elseif val == "off" or val == "false" then val = false
    end
    state[key] = val
    settings.save(state)
    respond("[eloot] Set " .. key .. " = " .. tostring(val))
    return

elseif cmd == "skin" then
    respond("[eloot] Skinning...")
    loot.skin(state)
    respond("[eloot] Done.")
    return

elseif cmd == "sell" then
    sell.sell_cycle(state)
    return

elseif cmd == "deposit" then
    sell.deposit(state)
    return

elseif cmd == "box" then
    local rh = GameObj.right_hand()
    if rh and rh:type_p("box") then
        boxes.loot_box(rh, state)
    else
        respond("[eloot] No box in hand")
    end
    return

elseif cmd == "ground" then
    local loot_items = GameObj.loot()
    for _, item in ipairs(loot_items) do
        if item:type_p("box") then
            fput("get #" .. item.id)
            local rh = GameObj.right_hand()
            if rh then boxes.loot_box(rh, state) end
        end
    end
    return

elseif cmd == "pool" then
    local subcmd = parsed.args[2]
    if subcmd == "deposit" then
        boxes.locksmith_pool_deposit(state)
    elseif subcmd == "return" then
        boxes.locksmith_pool_return(state)
    else
        boxes.locksmith_pool(state)
    end
    return

elseif cmd == "hoard" then
    local htype = parsed.args[2] or "gem"
    hoard.hoard_items(htype, state)
    return

elseif cmd == "raid" then
    local htype = parsed.args[2] or "gem"
    local item_name = parsed.args[3]
    local count = tonumber(parsed.args[4]) or 1
    if item_name then
        hoard.raid(htype, item_name, count, state)
    else
        respond("Usage: ;eloot raid gem|alchemy <item> [count]")
    end
    return

elseif cmd and cmd ~= "" then
    show_help()
    return
end

-- Default: full loot cycle
respond("[eloot] Looting...")
local count = loot.loot_cycle(state)
respond("[eloot] Done. Looted " .. count .. " items.")
