--- @revenant-script
--- name: bigshot
--- version: 1.0.0
--- author: elanthia-online
--- contributors: SpiffyJr, Tillmen, Kalros, Hazado, Tysong, Athias, Falicor, Deysh, Nisugi
--- depends: go2 >= 1.0, eloot >= 1.0
--- description: Full hunting automation — combat, navigation, rest, bounty, group
--- game: gs
---
--- Changelog (from Lich5):
---   v5.12.1 (2026-02-08)
---     - fix for cast_signs/cmd_rapid to prevent double casting due to 0sec castRT
---   v5.12.0 (2026-02-08)
---     - add ES/EB/EC/ED for spell, buff, cooldown, and debuff command checks
---   v5.11.4 (2026-01-14)
---     - add splashy command check for Rooms that are splashy(wet)
---     - add essence command check to check for sorcerer shadow essence
---     - unhide if hidden as a head/leader to allow followers to join
---     - add ATTACK event to attack routine if followers get separated
---     - allow non-incant spell COMMANDs to respect extra cast/evoke/channel
---     - force GROUP OPEN after disband when doing independent travel
---   v5.11.3 (2026-01-12)
---     - bugfix in follower rejoining leader
---     - bugfix for missing id's in attack stance, wander stance, and stand up
---   v5.11.2 (2026-01-09)
---     - optimize get_valid_neighbors to eval timeto as being valid numerics
---   v5.11.1 (2026-01-09)
---     - bugfix in sort_npcs
---   v5.11.0 (2025-11-29)
---     - add support for boon creatures
---     - add toggle to stop for dead group members
---     - refactor find_routine, ma_looter, check_mind, ready_to_hunt?, ready_to_rest?
---     - removed gather_ammo
---     - reworked debug process
---     - refactor attack loop for followers
---     - refactor escape from oozes, crawlers, and roa'ters
---     - removed voln_favor method for Lich::Resources.voln_favor
---     - update default fried to be 100
---     - refactor sort_npcs so if valid targets is left blank it targets everything
---   v5.10.0 (2025-10-31)
---     - update BSAreaRooms
---     - fix MA so leader has group open
---     - tighten follower loop
---     - MA lead can identify expected group number at startup
---     - head/tail can now be started in any order
---     - removed old companion_check method
---     - bugfix when using negative mana value in cmd_spell
---     - refactor group class
---     - bugfix for bigclaim when follower is hidden
---     - update cmd sleep to not change stance
---     - add command for valid creatures similar to mob
---     - bugfix in disarm if target has no weapon
---     - add gemstone support
---   v5.9.13 (2025-10-27)
---     - fix for dhurl command to respect ambush settings
---   v5.9.12 (2025-10-24)
---     - bugfix for stance dancing for unarmed and force
---   v5.9.11 (2025-10-11)
---     - bugfix for encumbrance command check
---   v5.9.10 (2025-10-03)
---     - bugfix in cmd_spell targetting to send proper gameobj ID# string
---   v5.9.9 (2025-10-02)
---     - add missing $rest_reasons
---   v5.9.8 (2025-09-30)
---     - bugfix for cmd_rapid to use cooldown instead of penalty check
---   v5.9.7 (2025-09-30)
---     - bugfix when Spell[597].active? in cast_signs
---   v5.9.6 (2025-09-09)
---     - add support for 902 and 411
---     - remove custom issue_command for Lich method
---     - added cast_spell method
---     - updated Society Abilities section to ignore rapidfire cool down
---   v5.9.5 (2025-07-22)
---     - remove companion_check calls
---     - add check_disks param to bigclaim?
---     - add claim check to attack_break and need_to_loot
---     - add coupdegrace buff check and command check
---     - increase bs_move timeout from 2 to 5
---   v5.9.4 (2025-07-08)
---     - bugfix for leader final loot to only work if claim is true
---   v5.9.3 (2025-07-02)
---     - bugfix for shield bash if using CMan instead of shield
---     - bugfix for FORCE cmd
---     - bugfix for cmd_tether to end if link is broken
---   v5.9.2 (2025-06-30)
---     - bugfix in cmd_tether potential npc logic
---   v5.9.1 (2025-06-27)
---     - Fix for head/tails bs_wander groupcheck logic
---   v5.9.0 (2025-04-03)
---     - Convert to use Group and Claim modules from core Lich5
---     - bugfix in cmd_assaults for confusion
---     - add logic to cmd_unravel for creature gone/dead
---     - adds cmd_depress for 1015/Song of Depression
---     - adds cmd_phase for 704/Phase
---     - adds final room loot option for leader in head/tail
---     - add disarm weapon to cmd_cman
---     - add Feat support for Chastise & Excoriate
---     - add Righteous Rebuke, Ardor of the Scourge, Glorious Momentum
---   v5.8.5 (2025-03-28)
---     - bugfix for follower resting commands
---     - add cooldown detection to cmd_spell and 140/919/211/215/219/1619/1650
---   v5.8.4 (2025-03-19)
---     - remove deprecated calls
---   v5.8.3 (2025-03-10)
---     - bugfix in run_script to use exact naming
---   v5.8.2 (2025-02-26)
---     - bugfix in run_script needing EXACT match
---     - bugfix in command_check split_check
---   v5.8.1 (2025-02-26)
---     - add garrote command to buffXX command check validity
---   v5.8.0 (2025-02-20)
---     - add custom fog option
---     - option to force resting if looting leaves a box in your hand
---     - enable pre-rest commands to call scripts
---     - add ancient & !ancient command checks
---     - add animate & !animate command checks
---     - change command_checks to lambdas for optimization
---   v5.7.10 (2025-02-18)
---     - add option for cmd_tether to recast upon death
---   v5.7.9 (2025-02-15)
---     - fix stand() to not stand if casting 608 and kneeling with crossbow
---   v5.7.8 (2025-02-11)
---     - update $bigshot_status to utilize :ready instead of :hunting
---   v5.7.7 (2025-02-10)
---     - bugfix in cmd_curse due to custom prep/curse logic
---   v5.7.6 (2025-02-08)
---     - bugfix where claims was including characters disk
---   v5.7.5 (2025-01-30)
---     - bugfix in resting method for fog_return
---   v5.7.4 (2025-01-22)
---     - adjust loop delay for efury and tether
---     - bugfix for constant redefinition
---     - bugfix in bs_wander when should_flee? is true
---   v5.7.3 (2025-01-20)
---     - added command tether for spell 706
---     - update to efury command
---     - fix for constant redefinition Ruby warnings
---   v5.7.2 (2025-01-15)
---     - added implosion(720) cooldown
---     - added check for voidweaver buff from 720
---   v5.7.1 (2025-01-13)
---     - added client input into debug file
---   v5.7.0 (2025-01-12)
---     - added debug logging to file
---   v5.6.11 (2025-01-02)
---     - added cmd_rapid for rapidfire/515 usage
---     - added rapid/!rapid command check
---     - bugfix for room claim with disks
---   v5.6.10 (2024-12-22)
---     - added optional stand-up stance selection
---     - bugfix for surge and burst in command_check
---   v5.6.9 (2024-12-09)
---     - bugfix for group members in room claim
---     - bugfix for weapon reactions
---   v5.6.8 (2024-12-06)
---     - additional regex for rooted debuff
---     - bugfix for leader waiting to regroup during rest cycle
---   v5.6.7 (2024-12-06)
---     - bugfix for follower not attacking
---     - add cmd_wandolier
---   v5.6.6 (2024-12-02)
---     - typo in load_settings: 'maxstamina'
---   v5.6.5 (2024-11-23)
---     - added test method
---     - added ;bigshot list
---     - multiple bugfixes
---   v5.6.4 (2024-11-18)
---     - bugfix for ready_to_hunt stamina check when set to 100
---   v5.6.3 (2024-11-14)
---     - bugfix for the command check when rooted
---   v5.6.2 (2024-11-13)
---     - prevent UAC from trying to kick when rooted
---   v5.6.1 (2024-11-13)
---     - bugfix in bandit tracking
---     - bugfix in loot() method
---   v5.6.0 (2024-09-11)
---     - new room claim process inspired by ;overwatch and Lich::Claim
---     - additional targeting for bandits
---   v5.5.0 (2024-08-24)
---     - rework of debug messaging
---     - once command update for force
---     - support for worn items with wield command
---   v5.4.5 (2024-08-20)
---     - update spinButton to save properly when manually entered
---   v5.4.4 (2024-08-19)
---     - remove unused GUI elements
---   v5.4.3 (2024-08-19)
---     - updated wander wait to a spin button
---     - updated OOM spin button and check for negatives
---   v5.4.2 (2024-08-17)
---     - bugfix in cmd_spell to set Spell's @@after_stance
---   v5.4.1 (2024-08-14)
---     - room command check logic correction
---   v5.4.0 (2024-08-07)
---     - UI updates, Notes section, percent_stamina, wander stance
---   v5.3.17 (2024-08-05)
---     - added 506/celerity check
---     - fix for hunt_monitor not working for followers
---   v5.3.16 (2024-08-04)
---     - fix for ROOM being missed in command_check regex
---   v5.3.15 (2024-07-25)
---     - add ROOM command check
---   v5.3.14 (2024-07-24)
---     - bugfix for reset_variables
---   v5.3.13 (2024-07-19)
---     - bugfix for head/tail random looting
---     - bugfix for smite tracking in a group
---   v5.3.12 (2024-07-13)
---     - update profile_current and save_profile_name when using CLI
---     - bugfix ready_to_rest? should_rest lambda logic
---   v5.3.11 (2024-06-20)
---     - fix to break from cmd_assault command on cooldown
---   v5.3.10 (2024-06-15)
---     - added support for Seanette's Shout
---   v5.3.9 (2024-05-29)
---     - add additional missing cmd_assault regex matching
---   v5.3.8 (2024-05-18)
---     - remove superfluous check for escorts
---   v5.3.7 (2024-05-01)
---     - fix for Char.prof/Char.level to Stats.prof/Stats.level
---   v5.3.6 (2024-04-28)
---     - add additional custom disk noun
---   v5.3.5 (2024-04-24)
---     - handle all the new custom disk nouns
---   v5.3.4 (2024-03-29)
---     - fix for Tangle Weed (610) status "entangled"
---     - fix for kweed command to use EVOKE
---   v5.3.3 (2024-03-15)
---     - fix for cmd_briar to use MEASURE instead of LOOK
---     - fix for cmd_briar to support UCS worn gear and two weapon combat
---   v5.3.2 (2024-03-12)
---     - bugfix in check_required_values
---   v5.3.1 (2024-03-11)
---     - bugfix for UIDs in boundary rooms
---     - added cmd_curse for Sorcerer spell 715
---     - added cmd_store command
---   v5.3.0 (2023-11-29)
---     - added boundary return outside hunting area
---     - added double cast on fog options for Rift
---     - added warcry holler buff support
---     - added eachtarget command
---     - removed change log before 5.0.0
---   v5.2.2 (2023-11-21)
---     - bugfix bs_wander delay
---     - added Roa'ter and Ooze escape check
---   v5.2.1 (2023-11-15)
---     - add new efury, caststop, and wield cmd
---     - redo unravel/barddispel cmd
---   v5.2.0 (2023-10-02)
---     - general adjustment to group hunting
---     - group looting changes
---     - multiple rally rooms support
---     - added multiple return room waypoints
---     - added support for ranger tracking
---   v5.1.10 (2023-09-28)
---     - bugfix for ;bigshot quick stopping when another character enters
---     - changed BIGSHOT_VERSION to pull from title block
---   v5.1.9 (2023-09-24)
---     - fix to debug variable being hard set at launch to false
---   v5.1.8 (2023-09-18)
---     - add acid & steam to incant 518 allowances
---   v5.1.7 (2023-09-16)
---     - bugfix wracking not considering active COL signs
---     - added RT check for wand method
---   v5.1.6 (2023-09-12)
---     - bugfix for cmd_force when target has 115
---   v5.1.5 (2023-08-30)
---     - bugfix for calling escape_rooms for tail
---   v5.1.4 (2023-08-30)
---     - bugfix for Roa'ter and Ooze escape for head/tail
---   v5.1.3 (2023-08-26)
---     - add 335/Divine Wrath cooldown check
---     - change cmd_spell to use Spell.force_incant
---   v5.1.2 (2023-08-21)
---     - fix incorrect regex match for mighty blow
---   v5.1.1 (2023-08-14)
---     - fix missing regex match for censer command check
---   v5.1.0 (2023-08-07)
---     - add ooze_escape for getting out of Ooze Innards in HW
---   v5.0.0 (2023-07-19)
---     - move spell_is_selfcast? inside Bigshot class
---     - renamed various methods to snake case
---     - multiple bugfixes
---   Full prior changelog: https://gswiki.play.net/Script_Bigshot/Changelog

local args_lib = require("lib/args")
local config = require("config")
local area_rooms = require("area_rooms")
local command_check = require("command_check")
local commands = require("commands")
local state_mod = require("state")
local navigation = require("navigation")
local recovery = require("recovery")
local group = require("group")

local state = config.load()
local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

local function show_help()
    respond("Usage: ;bigshot [mode] [options]")
    respond("")
    respond("Modes:")
    respond("  solo               Hunt solo (default)")
    respond("  quick              Hunt in current room only")
    respond("  bounty             Hunt with bounty tracking")
    respond("  single / once      One hunt cycle then exit")
    respond("  head N             Lead group of N followers")
    respond("  tail / follow      Follow group leader")
    respond("  setup              Open settings GUI")
    respond("  profile save NAME  Save settings profile")
    respond("  profile load NAME  Load settings profile")
    respond("  profile list       List saved profiles")
    respond("  display            Show all current settings")
    respond("  help               Show this help")
end

-- === Non-hunting command dispatch ===

if cmd == "help" then
    show_help()
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "display" then
    respond("[bigshot] Current settings:")
    local keys = {}
    for k in pairs(state) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = state[k]
        if type(v) == "table" then
            respond("  " .. k .. " = [" .. table.concat(v, ", ") .. "]")
        else
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "profile" then
    local subcmd = parsed.args[2]
    local name = parsed.args[3]
    if subcmd == "save" and name then
        config.save_profile(state, name)
    elseif subcmd == "load" and name then
        local profile = config.load_profile(name)
        if profile then
            for k, v in pairs(profile) do state[k] = v end
            config.save(state)
            respond("[bigshot] Loaded and saved profile: " .. name)
        end
    elseif subcmd == "list" then
        local profiles = config.list_profiles()
        if #profiles == 0 then
            respond("[bigshot] No saved profiles")
        else
            respond("[bigshot] Saved profiles:")
            for _, p in ipairs(profiles) do respond("  " .. p) end
        end
    else
        respond("Usage: ;bigshot profile <save|load|list> [name]")
    end
    return
end

-- === Hunting modes ===

local mode = cmd or "solo"
local single_run = (mode == "single" or mode == "once")
local quick_mode = (mode == "quick")
local bounty_mode = (mode == "bounty")

-- Validate hunting config
if not quick_mode then
    if not state.hunting_room_id or state.hunting_room_id == 0 then
        respond("[bigshot] Error: no hunting room configured. Run ;bigshot setup")
        return
    end
end

-- Build boundary room set
if not quick_mode then
    local room_count = area_rooms.build(state.hunting_room_id, state.hunting_boundaries or {})
    respond("[bigshot] Hunting area: " .. room_count .. " rooms from anchor " .. state.hunting_room_id)
end

-- Select command routine based on targets map
local function find_routine(target)
    if not target then return state.hunting_commands or {} end

    -- Check targets map for creature → letter mapping
    local letter = nil
    for creature_name, l in pairs(state.targets or {}) do
        if target.name:lower():find(creature_name:lower(), 1, true) then
            letter = l:lower()
            break
        end
    end

    if letter and letter ~= "a" then
        local key = "hunting_commands_" .. letter
        if state[key] and #state[key] > 0 then
            return state[key]
        end
    end

    return state.hunting_commands or {}
end

-- === Main attack function ===

local function attack(target)
    if not target then return end

    local routine = find_routine(target)
    if #routine == 0 then
        respond("[bigshot] No commands configured for " .. (target.name or "target"))
        return
    end

    respond("[bigshot] Attacking: " .. (target.name or "unknown") .. " [#" .. (target.id or "?") .. "]")
    commands.execute_routine(routine, target, state)
end

-- === Main hunting loop ===

local function do_hunt()
    respond("[bigshot] Hunting...")

    while true do
        -- Check death
        if dead and dead() then
            respond("[bigshot] Dead — stopping")
            return
        end

        -- Check flee
        local should_flee, flee_reason = state_mod.should_flee(state)
        if should_flee then
            respond("[bigshot] Fleeing: " .. flee_reason)
            navigation.escape(state)
            return
        end

        -- Check rest
        local should_rest, rest_reason = state_mod.should_rest(state)
        if should_rest then
            respond("[bigshot] Need rest: " .. rest_reason)
            return
        end

        -- Find target
        local target = state_mod.find_target(state.targets or {}, state)
        if target then
            attack(target)
            -- Loot after kill
            recovery.loot(state)
        else
            -- No targets in room — wander to next room
            if quick_mode then
                -- In quick mode, stay in this room
                pause(1)
                -- Check if new targets appeared
                target = state_mod.find_target(state.targets or {}, state)
                if not target then
                    respond("[bigshot] No more targets in room")
                    return
                end
            else
                local moved = navigation.wander(state)
                if not moved then
                    respond("[bigshot] Cannot move — stopping")
                    return
                end
            end
        end

        pause(0.3)
    end
end

-- === Cleanup ===

before_dying(function()
    group.cleanup()
    config.save(state)
end)

-- === Pre-hunt setup ===

local function pre_hunt()
    -- Run hunting prep commands
    for _, cmd_str in ipairs(state.hunting_prep_commands or {}) do
        fput(cmd_str)
        pause(0.3)
    end

    -- Travel to hunting grounds
    if not quick_mode then
        -- Travel waypoints if configured
        navigation.travel_waypoints(state.waypoints)
        -- Go to hunting room
        navigation.goto_room(state.hunting_room_id)
    end
end

-- === Main execution ===

if mode == "tail" or mode == "follow" then
    -- Follower mode: listen for leader events
    group.install_listener()
    respond("[bigshot] Follower mode — listening for group commands")

    while true do
        local event = group.next_event()
        if event then
            if event.type == "ATTACK" then
                local target = state_mod.find_target(state.targets or {}, state)
                if target then attack(target) end
            elseif event.type == "FOLLOW_NOW" and event.room_id then
                navigation.goto_room(tonumber(event.room_id))
            elseif event.type == "LOOT" then
                recovery.loot(state)
            elseif event.type == "REST" then
                recovery.rest(state)
            elseif event.type == "GO2" and event.room_id then
                navigation.goto_room(tonumber(event.room_id))
            end
        end
        pause(0.1)
    end

elseif mode == "head" then
    -- Leader mode with group
    local count = tonumber(parsed.args[2]) or 1
    group.set_leader(true)
    respond("[bigshot] Leader mode — waiting for " .. count .. " followers")
    respond("[bigshot] (Group coordination via whisper — followers run ;bigshot tail)")

    -- Hunt loop with group broadcasts
    pre_hunt()
    while true do
        group.broadcast("FOLLOW_NOW", { room_id = Map.current_room() })
        do_hunt()

        group.broadcast("REST")
        recovery.rest(state)

        if not state_mod.ready_to_hunt(state) then
            respond("[bigshot] Not ready to hunt — waiting")
            recovery.wait_for_recovery(state)
        end

        pre_hunt()

        if single_run then
            respond("[bigshot] Single run complete")
            return
        end
    end

else
    -- Solo / quick / bounty / single mode
    respond("[bigshot] Starting in " .. mode .. " mode")

    pre_hunt()

    while true do
        do_hunt()
        recovery.rest(state)

        if single_run then
            respond("[bigshot] Single run complete")
            return
        end

        if not state_mod.ready_to_hunt(state) then
            recovery.wait_for_recovery(state)
        end

        pre_hunt()
    end
end
