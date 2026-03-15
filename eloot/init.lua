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

local state = settings.load()
local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

local function show_help()
    respond("Usage: ;eloot [command]")
    respond("")
    respond("Commands:")
    respond("  (no args)        Loot: skin + search + room")
    respond("  sell             Full sell cycle (Plan 2)")
    respond("  box              Loot box in hand (Plan 3)")
    respond("  pool             Locksmith pool (Plan 3)")
    respond("  deposit          Deposit silver (Plan 2)")
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
    respond("[eloot] Sell pipeline not yet implemented (Plan 2)")
    return

elseif cmd == "box" then
    respond("[eloot] Box handling not yet implemented (Plan 3)")
    return

elseif cmd == "pool" then
    respond("[eloot] Locksmith pool not yet implemented (Plan 3)")
    return

elseif cmd and cmd ~= "" then
    show_help()
    return
end

-- Default: full loot cycle
respond("[eloot] Looting...")
local count = loot.loot_cycle(state)
respond("[eloot] Done. Looted " .. count .. " items.")
