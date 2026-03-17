--- @revenant-script
--- name: eloot
--- version: 1.0.0
--- author: Sordal
--- depends: go2 >= 1.0
--- description: Full loot/sell/hoard pipeline

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
