--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: ebounty
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Deysh, Nisugi, Tysong, Rinualdo
--- description: Adventurer's Guild bounty automation — culling, gems, herbs, skins, heirlooms, escorts, rescues, bandits
--- game: gs
---
--- Changelog (from Lich5):
---   v1.9.7 (2025-03-01)
---     - bugfix expedite vouchers when already ready to get new task
---   v1.9.6 (2025-02-17)
---     - bugfix to not try searching SG for taskmaster when already in room
---   v1.9.5 (2025-02-06)
---     - bugfix in forage_bounty when using optional location in CLI argument
---   v1.9.4 (2025-02-04)
---     - optimize location_list finding in forage_find room logic
---   v1.9.3 (2025-02-04)
---     - bugfix in forage_find room
---   v1.9.2 (2025-01-27)
---     - add CLI support for ;ebounty forage bounty
---     - add CLI support for ;ebounty forage "herb" <qty> "location"
---     - bugfix in heirloom_search and forage_bounty to use Claim.mine?
---     - anchor ending gem names in search functions
---     - fix resting spot for SG shattered
---     - fix forage tag in starting room crash
---     - fix between script(s) added erroneous commas
---   v1.9.1 (2025-01-18)
---     - bugfix for running gem tracking script
---   v1.9.0 (2025-01-08)
---     - added support for ranger track
---   v1.8.1 (2025-12-24)
---     - added option to regroup before quiting if started in group
---   v1.8.0 (2025-11-18)
---     - added option to get a new bounty before quitting
---   v1.7.5 (2025-11-11)
---     - bugfix in minimum Lich required checks
---   v1.7.4 (2025-11-11)
---     - bugfix for go2_rest - settings[:resting_room] converted to array
---   v1.7.3 (2025-10-01)
---     - updates for Sailor's Grief
---     - added support for uids
---     - bugfix for saving settings
---     - general code cleanup
---   v1.7.2 (2025-09-08)
---     - change requirement to 5.12.5 due to heirloom text change
---   v1.7.1 (2025-09-07)
---     - bugfix for change in Heirloom return messaging
---   v1.7.0 (2025-09-05)
---     - add option to select boost bounty type
---   v1.6.5 (2025-08-15)
---     - bugfix for stowing herbs
---   v1.6.4 (2025-08-05)
---     - remove version check for bigshot
---   v1.6.3 (2025-08-03)
---     - bugfix mana check when changing aspect while 650 is active
---     - bugfix for hiding is 608 doesn't work
---   v1.6.2 (2025-04-21)
---     - bugfix for NPCs not populating quickly upon room entry
---   v1.6.1 (2025-04-21)
---     - bugfix for HW bounty turnin
---   v1.6.0 (2025-03-29)
---     - remove custom bounty and use Lich Bounty API
---     - remove custom issue_command to Lich::Util.issue_command
---     - remove depreciated code
---     - update references of ego2 to escortgo2
---   v1.5.6 (2025-03-27)
---     - bugfix for set_eval not adding additional skins
---   v1.5.5 (2025-03-19)
---     - remove deprecated Lich calls
---   v1.5.4 (2025-03-10)
---     - another bugfix for bundled skins
---   v1.5.3 (2025-03-08)
---     - bugfix when counting bundled skins
---   v1.5.2 (2025-02-09)
---     - bugfix when only foraging and needing healed
---   v1.5.1 (2025-01-07)
---     - bugfix for forage turn-in
---   v1.5.0 (2024-12-24)
---     - added buffing option when resting
---     - added using a script to handling resting location
---     - added option to rest at nearest table
---     - added remove bounty if heirloom item gets lost
---     - bugfix for bounty eval not setting EBounty.data.complete_mind
---     - bugfix for ask_guard in HW
---   v1.4.5 (2024-11-26)
---     - added option to use bigshot setting for resting location
---     - bugfix for profile dropdown sorting
---     - bugfix stop script from looping if started without child in room
---   v1.4.4 (2024-11-22)
---     - bugfix in should_hunt
---   v1.4.3 (2024-11-18)
---     - missing criteria in should_hunt?
---     - bugfix in wait_for_bounty
---     - removed EBounty.data.wait
---   v1.4.2 (2024-11-16)
---     - bugfix for when to rest
---   v1.4.1 (2024-11-07)
---     - will continue hunting after bounty complete until Bigshot Should Rest? is met
---     - bugfix in setup
---     - bugfix for should_hunt? spamming experience check
---     - bugfix for should_hunt? exp_pause incorrectly included
---   v1.4.0 (2024-08-23)
---     - expanded resting options
---     - added optional death recovery support
---     - added spinbutton for room delay for bandit bounties
---     - bugfix in gem bounty running hording script with parameters
---     - bugfix in bandit hunting variables
---     - removed script change log before v1.3.0
---   v1.3.11 (2024-09-24)
---     - fix to allow for CLI foraging without setting Gem/Default profile
---   v1.3.10 (2024-08-19)
---     - bugfix for ask_guard response
---   v1.3.9 (2024-08-14)
---     - logic fix when once_and_done is set and rejected bounty not exiting
---   v1.3.8 (2024-07-12)
---     - add timer to not spam INFO during should_hunt?
---   v1.3.7 (2024-07-08)
---     - add quiet info command to should_hunt? to refresh stats
---   v1.3.6 (2024-06-23)
---     - update ebounty fog routine to match bigshot
---   v1.3.5 (2024-05-15)
---     - add exit if gembounty complete but using eloot sell excludes gems
---   v1.3.4 (2024-05-01)
---     - Change Char.prof to Stats.prof
---   v1.3.3 (2024-04-13)
---     - bug in escort task acceptance
---   v1.3.2 (2024-04-09)
---     - bug in forage for 1011 song of peace usage
---   v1.3.1 (2024-04-01)
---     - updated keep_hunting not to run in bigshot bounty mode
---     - consolidated herbalist names and switched to ID for turnin
---     - removed change log before v1.1.14
---   v1.3.0 (2024-03-17)
---     - added exclusion options for individual gems and locations
---     - added help section
---     - bugfix for UI title
---   Full prior changelog: https://gswiki.play.net/Lich:Script_Ebounty

require("lib/bounty")

local settings_mod = require("settings")
local util = require("util")
local task = require("task")
local gui = require("gui_settings")

local state = {
    settings = nil,
    creature = nil,
    start_room = nil,
    start_time = os.time(),
    leader = "",
    only_required = false,
    close_containers = {},
    bad_rooms = {},
    remaining_skins = 0,
    remaining_gems = 0,
    complete_mind = nil,
    bandit_flag = false,
    location_start = nil,
    location_boundaries = nil,
    info_time = 0,
    skin = nil,
    gem = nil,
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
        if line and line:find("suppress bandit activity") then
            state.bandit_flag = true
        end
        return line
    end)
end

-- Cleanup
before_dying(function()
    DownstreamHook.remove("ebounty_death_watch")
    if state.settings.return_to_group and state.leader ~= "" then
        fput("join " .. state.leader)
    end
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
    respond("  ;ebounty setup <key> <value> - Update single setting")
    respond("  ;ebounty remove    - Remove current bounty")
    respond("  ;ebounty forage bounty")
    respond("  ;ebounty forage \"herb\" <qty> [\"loc\"]")
    respond("  ;ebounty load      - Reload settings from disk")
    respond("  ;ebounty list      - List all settings")
    respond("  ;ebounty location  - Show current bounty location")
    respond("  ;ebounty creature  - Show current bounty creature")
    respond("  ;ebounty bounty    - Show current bounty details")
    respond("  ;ebounty debug     - Toggle debug mode")
    respond("  ;ebounty version   - Show version")
    respond("  ;ebounty test      - Dump all settings")
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

elseif arg1 == "load" then
    state.settings = settings_mod.load()
    state.bad_rooms = settings_mod.build_bad_rooms(state.settings)
    echo("Settings reloaded.")

elseif arg1 == "test" then
    echo("EBounty v2.0.0 (Revenant)")
    for k, v in pairs(state.settings) do
        if type(v) == "table" then echo("  " .. k .. ": " .. table.concat(v, ", "))
        else echo("  " .. k .. ": " .. tostring(v)) end
    end

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

    if grouped() then
        state.leader = Group.leader or ""
    end

    setup_death_monitor()
    task.bounty_check()
end
