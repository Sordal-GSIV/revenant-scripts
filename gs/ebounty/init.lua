--- @revenant-script
--- name: ebounty
--- version: 2.0.0
--- author: elanthia-online (ported to Revenant)
--- description: Adventurer's Guild bounty automation — culling, gems, herbs, skins, heirlooms, escorts, rescues, bandits

require("lib/gs/bounty")

local settings_mod = require("settings")
local util = require("util")
local task = require("task")
local gui = require("gui_settings")

-- Runtime state
local state = {
    settings = nil,
    creature = nil,
    start_room = nil,
    start_time = os.time(),
    leader = "",
    only_required = false,
    close_containers = {},
    bad_rooms = {},
}

util.state = state
state.settings = settings_mod.load()
state.bad_rooms = settings_mod.build_bad_rooms(state.settings)

-- Death watchdog
local function setup_death_monitor()
    DownstreamHook.add("ebounty_death_watch", function(line)
        if dead() then
            if Script.running("bigshot") then Script.kill("bigshot") end
            if Script.running("go2") then Script.kill("go2") end
            if (state.settings.death_script or "") ~= "" then
                util.run_scripts(state.settings.death_script)
            end
        end
        return line
    end)
end

-- Cleanup
before_dying(function()
    DownstreamHook.remove("ebounty_death_watch")
    if state.settings.basic and state.start_room then util.go2(state.start_room) end
    if Script.running("bigshot") then Script.kill("bigshot") end
    for _, bag_id in ipairs(state.close_containers) do fput("close #" .. bag_id) end
end)

-- Help
local function show_help()
    respond("[ebounty] Commands:")
    respond("  ;ebounty           - Run bounty loop")
    respond("  ;ebounty once      - Run one bounty and quit")
    respond("  ;ebounty setup     - Open settings GUI")
    respond("  ;ebounty remove    - Remove current bounty")
    respond("  ;ebounty forage bounty")
    respond("  ;ebounty forage \"herb\" <qty> [\"loc\"]")
    respond("  ;ebounty list|location|creature|bounty|debug|version")
end

-- CLI routing
local arg1 = Script.vars[1]

if arg1 == "version" or arg1 == "ver" then
    echo("EBounty Version: 2.0.0 (Revenant)")

elseif arg1 == "help" then
    show_help()

elseif arg1 == "debug" then
    state.settings.debug = not state.settings.debug
    settings_mod.save(state.settings)
    echo("Debug mode: " .. tostring(state.settings.debug))

elseif arg1 == "list" then
    respond("[ebounty] Settings:")
    for k, v in pairs(state.settings) do
        if type(v) == "table" then respond("  " .. k .. ": " .. table.concat(v, ", "))
        else respond("  " .. k .. ": " .. tostring(v)) end
    end

elseif arg1 == "setup" or arg1 == "settings" then
    if Script.vars[2] then
        local key, val = Script.vars[2], Script.vars[3] or ""
        local current = state.settings[key]
        if current ~= nil then
            if type(current) == "boolean" then
                state.settings[key] = ({["on"]=true,["true"]=true,["yes"]=true,["1"]=true})[val:lower()] or false
            elseif type(current) == "number" then
                state.settings[key] = tonumber(val) or current
            else
                state.settings[key] = val
            end
            settings_mod.save(state.settings)
            echo("Updated " .. key .. " = " .. tostring(state.settings[key]))
        else echo("Unknown setting: " .. key) end
    else
        state.settings = gui.show(state.settings)
    end

elseif arg1 == "remove" then
    if not Map.current_room() then echo("Start in a mapped room."); return end
    state.start_room = Map.current_room()
    task.bounty_remove(true)
    util.go2(state.start_room)

elseif arg1 == "forage" then
    if not Script.vars[2] then echo("Usage: ;ebounty forage bounty | ;ebounty forage \"herb\" <qty> [\"loc\"]"); return end
    local return_room = Map.current_room()
    if Script.vars[2] == "bounty" then
        local info = Bounty.parse()
        if info and info.type == "herb" then task.forage_bounty(info.herb, info.number, info.area)
        else echo("No herb bounty active") end
    elseif Script.vars[3] then
        task.forage_bounty(Script.vars[2], tonumber(Script.vars[3]) or 1, Script.vars[4] or "nearest")
    end
    if return_room then util.go2(return_room) end

elseif arg1 == "location" then
    local info = Bounty.parse()
    if info and info.area then util.msg("yellow", "Location: " .. info.area)
    else util.msg("yellow", "No location for current bounty") end

elseif arg1 == "creature" then
    local info = Bounty.parse()
    if info and info.creature then util.msg("yellow", "Creature: " .. info.creature)
    else util.msg("yellow", "No creature for current bounty") end

elseif arg1 == "bounty" then
    local info = Bounty.parse()
    if info then for k, v in pairs(info) do respond("  " .. k .. ": " .. tostring(v)) end
    else echo("No bounty info") end

else
    -- Default: run bounty loop
    if not Map.current_room() then echo("Start in a mapped room."); return end

    if not state.settings.basic then
        local required = {"bigshot"}
        if state.settings.healing_script == "" and not state.settings.skip_healing then required[#required+1] = "eherbs" end
        if state.settings.selling_script == "" then required[#required+1] = "eloot" end
        local missing = {}
        for _, name in ipairs(required) do
            if not Script.exists(name) then missing[#missing+1] = name end
        end
        if #missing > 0 then echo("Missing: " .. table.concat(missing, ", ")); return end
    end

    state.start_room = Map.current_room()
    if arg1 == "once" then state.settings.once_and_done = true end

    setup_death_monitor()
    task.bounty_check()
end
