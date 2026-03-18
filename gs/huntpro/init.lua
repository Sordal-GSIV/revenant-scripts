-- huntpro/init.lua — Main entry point, arg parsing, mode dispatch, hunt loop
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara (19157 lines, "2026 Sun" version)
-- Original author: Jara — https://linktr.ee/TheJaraVerse
-- Please adhere to POLICY 18 & 19. Do not AFK script in Prime.
--
-- Usage: ;huntpro <style> <area>
--   Styles 1-2: UAC (brawling) — 1 = open, 2 = from hiding
--   Styles 3-4: Melee weapon  — 3 = open, 4 = ambush from hiding
--   Styles 5-6: Ranged        — 5 = open, 6 = from hiding
--   Styles 7-8: Ranged kneel  — 7 = open, 8 = from hiding
--   Style 9:    Pure caster   — spells only
--
-- Special areas: quick, qlite, grounded, group, follow, bounty, newbounty, fastbounty
-- Full zone list: see navigation.lua

local VERSION = "2026.1.0"
local LAST_UPDATE = "2026-03-18"

-- Suppress command echo
silence_me()

---------------------------------------------------------------------------
-- Module imports
---------------------------------------------------------------------------
local Config     = require("gs.huntpro.config")
local Combat     = require("gs.huntpro.combat")
local SpellMod   = require("gs.huntpro.spells")
local Navigation = require("gs.huntpro.navigation")
local Recovery   = require("gs.huntpro.recovery")
local Loot       = require("gs.huntpro.loot")
local GroupMod   = require("gs.huntpro.group")

---------------------------------------------------------------------------
-- Banner helpers
---------------------------------------------------------------------------
local function top_menu()
    respond("|0-100 Hunting Script - Please do not AFK Script in Prime.|")
    respond("")
end

local function bottom_menu()
    respond("")
    respond("|---------------------------------------------------------|")
end

local function show_help()
    top_menu()
    respond("Please adhere to POLICY 18 & 19.")
    respond("")
    respond("Usage: ;huntpro <style> <area>")
    respond("")
    respond("  Styles:")
    respond("    1  UAC melee (open)")
    respond("    2  UAC melee (from hiding)")
    respond("    3  Weapon melee (open)")
    respond("    4  Weapon melee (ambush)")
    respond("    5  Ranged (open)")
    respond("    6  Ranged (from hiding)")
    respond("    7  Ranged kneeling (open)")
    respond("    8  Ranged kneeling (from hiding)")
    respond("    9  Pure caster (spells only)")
    respond("")
    respond("  Special areas: quick, qlite, grounded, bounty, newbounty,")
    respond("                 fastbounty, group, follow, qfollow, cleanup")
    respond("")
    respond("  ;huntpro setup          — Open settings GUI")
    respond("  ;huntpro setup show     — Display current settings")
    respond("  ;huntpro setup change <key> <value> — Change a setting")
    respond("  ;huntpro setup reset    — Reset all settings")
    respond("  ;huntpro cleanup        — Run post-hunt cleanup")
    respond("  ;huntpro help           — This message")
    respond("")
    respond("  Huntpro Help: http://tinyurl.com/huntprohelp")
    respond("  Contact & Support: https://linktr.ee/TheJaraVerse")
    respond("  Version: " .. VERSION .. " (" .. LAST_UPDATE .. ")")
    bottom_menu()
end

---------------------------------------------------------------------------
-- Parse arguments
---------------------------------------------------------------------------
local args = Script.vars
local arg_full = args[0] or ""
local arg1 = args[1] and args[1]:lower() or ""
local arg2 = args[2] and args[2]:lower() or ""
local arg3 = args[3] or nil

---------------------------------------------------------------------------
-- Handle special commands (help, setup, cleanup)
---------------------------------------------------------------------------
if arg1 == "" or arg1 == "help" then
    show_help()
    return
end

if arg1 == "setup" then
    if arg2 == "show" or arg2 == "display" then
        local settings = Config.load()
        Config.display(settings)
        return
    elseif arg2 == "change" and args[3] and args[4] then
        local settings = Config.load()
        Config.change(settings, args[3]:lower(), args[4])
        return
    elseif arg2 == "reset" then
        Config.reset()
        respond(Char.name .. ", all huntpro settings reset to defaults.")
        return
    else
        -- Open GUI settings
        local GuiSettings = require("gs.huntpro.gui_settings")
        GuiSettings.show()
        return
    end
end

if arg1 == "cleanup" then
    local settings = Config.load()
    local hp = {}
    for k, v in pairs(settings) do hp[k] = v end
    hp.loot_script = (settings.loot_script ~= "0") and settings.loot_script or "eloot"
    hp.cleanloot_script = (settings.cleanloot_script ~= "0") and settings.cleanloot_script or hp.loot_script
    Navigation.cleanup(hp)
    return
end

---------------------------------------------------------------------------
-- Validate style and area
---------------------------------------------------------------------------
if not arg1:find("^[1-9]$") then
    respond("Invalid style: " .. arg1 .. ". Must be 1-9.")
    show_help()
    return
end

if arg2 == "" then
    respond("You must specify a hunting area.")
    show_help()
    return
end

if not Navigation.is_valid_zone(arg2) then
    respond("Unknown hunting zone: " .. arg2)
    respond("Use ;huntpro help for the zone list.")
    return
end

---------------------------------------------------------------------------
-- Load settings and build runtime state (hp table)
---------------------------------------------------------------------------
local settings = Config.load()
local hp = {}

-- Copy settings into runtime state
for k, v in pairs(settings) do
    hp[k] = v
end

-- Parse key settings into usable types
hp.my_style = arg1
hp.my_area = arg2
hp.my_room_number = GameState.room_id
hp.my_area_level = 0
hp.my_area_type = "Living"
hp.action = 0
hp.return_why = nil
hp.extra_fried = 0

-- Loot script resolution
hp.loot_script = (settings.loot_script ~= "0") and settings.loot_script or "eloot"
hp.cleanloot_script = (settings.cleanloot_script ~= "0") and settings.cleanloot_script or hp.loot_script

-- Boolean conversions
hp.stay_offensive = (settings.stay_offensive ~= "0")
hp.combat_cleanup = (settings.combat_cleanup ~= "0")
hp.hunt_while_fried = (settings.hunt_while_fried ~= "0")
hp.no_crowd_control = (settings.no_crowd_control ~= "0")
hp.no_cman_control = (settings.no_cman_control ~= "0")
hp.no_shield_control = (settings.no_shield_control ~= "0")
hp.no_weapon_control = (settings.no_weapon_control ~= "0")
hp.no_society = (settings.no_society ~= "0")
hp.no_berserk = (settings.no_berserk ~= "0")
hp.no_waggle = (settings.no_waggle ~= "0")
hp.no_herbs = (settings.no_herbs ~= "0")
hp.use_herbs = (settings.use_herbs ~= "0")
hp.use_wands = (settings.use_wands ~= "0")
hp.deedmana = (settings.deedmana ~= "0")
hp.wrack = (settings.wrack ~= "0")
hp.nocleanupherbs = (settings.nocleanupherbs ~= "0")
hp.meditate = (settings.meditate ~= "0")
hp.disable_mana = (settings.disable_mana ~= "0")
hp.disable_stamina = (settings.disable_stamina ~= "0")
hp.disable_encumbrance = (settings.disable_encumbrance ~= "0")
hp.evoke_default = (settings.evoke_default ~= "0")
hp.sanctify_330 = (settings.sanctify_330 ~= "0")
hp.style9_arcaneblast = (settings.style9_arcaneblast ~= "0")
hp.noquartz = (settings.noquartz ~= "0")
hp.camo = (settings.camo ~= "0")
hp.taxi = (settings.taxi ~= "0")
hp.boost_long = (settings.boost_long ~= "0")

-- Flee counter
hp.flee_counter = tonumber(settings.flee) or 0

-- Stance defaults
hp.stance_offensive = (settings.offensive_stance ~= "0") and settings.offensive_stance or "offensive"
hp.stance_defensive = (settings.defensive_stance ~= "0") and settings.defensive_stance or "guarded"

-- Force skip arrays
hp.force_skip_array = {}
if settings.force_skip_list ~= "0" then
    table.insert(hp.force_skip_array, settings.force_skip_list)
end
if settings.force_skip_list2 ~= "0" then
    table.insert(hp.force_skip_array, settings.force_skip_list2)
end
if settings.force_skip_list3 ~= "0" then
    table.insert(hp.force_skip_array, settings.force_skip_list3)
end

-- Compound ignore
hp.compound_ignore_array = {}
if settings.compound_ignore ~= "0" then
    table.insert(hp.compound_ignore_array, settings.compound_ignore)
end

---------------------------------------------------------------------------
-- Society detection
---------------------------------------------------------------------------
if settings.character_society == "Voln" then
    hp.my_society = "Voln"
elseif settings.character_society == "Col" then
    hp.my_society = "Col"
elseif settings.character_society == "Gos" then
    hp.my_society = "Gos"
else
    hp.my_society = "None"
end

---------------------------------------------------------------------------
-- Weapon attune auto-detection
---------------------------------------------------------------------------
if not hp.weapon_attune or hp.weapon_attune == "0" then
    if (Skills.brawling or 0) >= 10 then hp.weapon_attune = "brawling"
    elseif (Skills.blunt_weapons or 0) >= 10 then hp.weapon_attune = "blunt"
    elseif (Skills.edged_weapons or 0) >= 10 then hp.weapon_attune = "edged"
    elseif (Skills.polearm_weapons or 0) >= 10 then hp.weapon_attune = "polearm"
    elseif (Skills.ranged_weapons or 0) >= 10 then hp.weapon_attune = "ranged"
    elseif (Skills.two_handed_weapons or 0) >= 10 then hp.weapon_attune = "2hw"
    end
end

-- Pure casters don't use weapon techniques
if Stats.prof == "Wizard" or Stats.prof == "Cleric" or
   Stats.prof == "Empath" or Stats.prof == "Sorcerer" then
    hp.no_weapon_control = true
end

---------------------------------------------------------------------------
-- Combat control auto-detection
---------------------------------------------------------------------------
hp.crowd_control_enabled = (Stats.level or 0) >= 20
hp.cman_control_enabled = (Stats.level or 0) >= 20 and (Skills.combat_maneuvers or 0) >= 1

if (Skills.combat_maneuvers or 0) == 0 then
    hp.no_cman_control = true
end
if (Skills.shield_use or 0) == 0 then
    hp.no_shield_control = true
end

-- CMan detection from infomon
hp.cman_tackle = true  -- basic cman everyone can try
hp.cman_sweep = (Skills.combat_maneuvers or 0) >= 5
hp.cman_mightyblow = (Skills.combat_maneuvers or 0) >= 10
hp.cman_footstomp = (Skills.combat_maneuvers or 0) >= 5
hp.cman_disarm = (Skills.combat_maneuvers or 0) >= 15
hp.cman_trip = (Skills.combat_maneuvers or 0) >= 5
hp.cman_headbutt = (Skills.combat_maneuvers or 0) >= 10
hp.cman_bullrush = (Skills.combat_maneuvers or 0) >= 15
hp.cman_mug = (Skills.combat_maneuvers or 0) >= 10
hp.cman_bearhug = (Skills.combat_maneuvers or 0) >= 20
hp.cman_spellcleave = (Skills.combat_maneuvers or 0) >= 20
hp.cman_spinattack = (Skills.combat_maneuvers or 0) >= 15
hp.cman_staggeringblow = (Skills.combat_maneuvers or 0) >= 15
hp.cman_truestrike = (Skills.combat_maneuvers or 0) >= 10
hp.cman_crowdpress = (Skills.combat_maneuvers or 0) >= 10
hp.cman_dirtkick = (Skills.combat_maneuvers or 0) >= 5
hp.cman_feint = (Skills.combat_maneuvers or 0) >= 5
hp.cman_swiftkick = (Skills.combat_maneuvers or 0) >= 5
hp.cman_groinkick = (Skills.combat_maneuvers or 0) >= 10
hp.cman_haymaker = (Skills.combat_maneuvers or 0) >= 15
hp.cman_sundershield = (Skills.combat_maneuvers or 0) >= 15
hp.cman_suckerpunch = (Skills.combat_maneuvers or 0) >= 5
hp.cman_nosetweak = (Skills.combat_maneuvers or 0) >= 5
hp.cman_berserk = (settings.berserk ~= "0") and Stats.prof == "Warrior"
hp.cman_vaultkick = (Skills.combat_maneuvers or 0) >= 10

-- Shield techniques
hp.shield_shieldbash = (Skills.shield_use or 0) >= 5
hp.shield_shieldstrike = (Skills.shield_use or 0) >= 10
hp.shield_steelyresolve = (Skills.shield_use or 0) >= 15
hp.shield_shieldpin = (Skills.shield_use or 0) >= 15
hp.shield_shieldpush = (Skills.shield_use or 0) >= 10
hp.shield_shieldtrample = (Skills.shield_use or 0) >= 20
hp.shield_shieldthrow = (Skills.shield_use or 0) >= 25
hp.shield_shieldcharge = (Skills.shield_use or 0) >= 30

-- Ranged cock support
hp.use_cock = false
if hp.my_style == "7" or hp.my_style == "8" then
    if settings.no_cock == "0" then
        hp.use_cock = true
    end
end

-- Empath self-heal
if Stats.prof == "Empath" and (Stats.level or 0) >= 40 then
    hp.empath_self_heal = true
end

-- Herb zones (auto-enable herbs)
if hp.my_area:find("moonmyklian") or hp.my_area:find("moonmagru") or
   hp.my_area:find("pineglacei") or hp.my_area:find("icebush") or
   hp.my_area:find("iceshrub") then
    hp.use_herbs = true
end

---------------------------------------------------------------------------
-- Group setup
---------------------------------------------------------------------------
GroupMod.setup(hp)

-- Follow/group mode special area handling
if hp.my_area == "group" then
    hp.group_ai = "2"
elseif hp.my_area == "follow" or hp.my_area == "qfollow" then
    hp.captain = arg3 or hp.captain
    hp.follow_mode_enabled = true
end

---------------------------------------------------------------------------
-- Town detection for bounties
---------------------------------------------------------------------------
hp.bounty_town = Config.detect_town()

---------------------------------------------------------------------------
-- Setup companion scripts
---------------------------------------------------------------------------
hp.script_one = (settings.run_script ~= "0") and settings.run_script or nil
hp.script_two = (settings.run_script2 ~= "0") and settings.run_script2 or nil
hp.script_three = (settings.run_script3 ~= "0") and settings.run_script3 or nil

-- Start companion scripts if zone scripts enabled
if settings.zonescripts ~= "0" then
    if hp.script_one and not Script.running(hp.script_one) then
        Script.run(hp.script_one)
    end
    if hp.script_two and not Script.running(hp.script_two) then
        Script.run(hp.script_two)
    end
    if hp.script_three and not Script.running(hp.script_three) then
        Script.run(hp.script_three)
    end
end

-- Start society script
if not hp.no_society then
    if hp.my_society == "Voln" and Script.exists("symbolz") then
        if not Script.running("symbolz") then Script.run("symbolz") end
    elseif hp.my_society == "Gos" and Script.exists("isigils") then
        if not Script.running("isigils") then Script.run("isigils") end
    elseif hp.my_society == "Col" and Script.exists("isigns") then
        if not Script.running("isigns") then Script.run("isigns") end
    end
end

-- Bard song manager
if Stats.prof == "Bard" and Script.exists("song-manager") then
    if not Script.running("song-manager") then Script.run("song-manager") end
end

-- Reactive script for melee styles
if hp.my_style:find("[12345678]") and Script.exists("reactive") then
    if not Script.running("reactive") then Script.run("reactive") end
end

---------------------------------------------------------------------------
-- Register exit cleanup hook
---------------------------------------------------------------------------
before_dying(function()
    GroupMod.kill_scripts(hp)
    DownstreamHook.remove("huntpro_bounty_intel")
    DownstreamHook.remove("huntpro_berserk_watch")
    DownstreamHook.remove("huntpro_group_listen")
end)

---------------------------------------------------------------------------
-- Register downstream hooks for game events
---------------------------------------------------------------------------

-- Berserk end detection (warrior)
DownstreamHook.add("huntpro_berserk_watch", function(line)
    if not line then return line end
    if line:find("You feel your berserking subside") or
       line:find("You calm down") then
        Combat.state.ragemode = false
    end
    return line
end)

---------------------------------------------------------------------------
-- Level 0 check
---------------------------------------------------------------------------
if (Stats.level or 0) == 0 then
    top_menu()
    respond(Char.name .. ", you appear to be level 0.")
    respond("I'm going to try to take you to town to reach level 1.")
    bottom_menu()
    pause(5)
    Map.go2("town")
    return
end

---------------------------------------------------------------------------
-- MStrike setup
---------------------------------------------------------------------------
if hp.my_style ~= "9" then
    Combat.mstrike_setup(hp)
end

---------------------------------------------------------------------------
-- Announce start
---------------------------------------------------------------------------
top_menu()
respond("Hello " .. Char.name .. ", I'm Huntpro.")
respond("")
respond("  Style: " .. hp.my_style .. "  |  Area: " .. hp.my_area)
respond("  Society: " .. hp.my_society .. "  |  Weapon Attune: " .. (hp.weapon_attune or "none"))
respond("  Loot Script: " .. hp.loot_script)
if hp.stay_offensive then respond("  Stance: Stay Offensive") end
if hp.force_target and hp.force_target ~= "0" then
    respond("  Force Target: " .. hp.force_target)
end
bottom_menu()

---------------------------------------------------------------------------
-- Navigate to hunting zone
---------------------------------------------------------------------------
Navigation.go_to_zone(hp)

-- Nil room recovery
if not (hp.my_area:find("qlite") or hp.my_area:find("quick") or hp.my_area:find("grounded")) then
    if not GameState.room_id then
        local attempts = 0
        while not GameState.room_id and attempts < 10 do
            walk()
            attempts = attempts + 1
        end
    end
end

-- Taxi mode — drop off and exit
if hp.taxi then
    top_menu()
    respond(Char.name .. ", you have arrived at your destination.")
    respond("Good luck with your hunt!")
    bottom_menu()
    GroupMod.kill_scripts(hp)
    return
end

---------------------------------------------------------------------------
-- Follow mode dispatch
---------------------------------------------------------------------------
if hp.follow_mode_enabled then
    GroupMod.follow_mode(hp)
    if hp.action == 99 then
        Navigation.safe_room(hp)
    end
    return
end

---------------------------------------------------------------------------
-- Spell upkeep before entering combat loop
---------------------------------------------------------------------------
SpellMod.society_upkeep(hp)
SpellMod.spell_upkeep(hp)

-- Loot boost
Loot.boost_loot(hp)

-- Quartz orb upkeep
SpellMod.upkeep_quartz(hp)

---------------------------------------------------------------------------
-- ====================== MAIN HUNT LOOP ======================
---------------------------------------------------------------------------
while true do
    -- Check if we should retreat
    if hp.action == 99 then
        Navigation.safe_room(hp)
        GroupMod.kill_scripts(hp)
        return
    end

    -- Check if we hit grounded room limit
    if hp.action == 95 and hp.my_room_number and GameState.room_id and
       GameState.room_id ~= hp.my_room_number then
        -- Left grounded room — stop
        top_menu()
        respond(Char.name .. ", you left your grounded room. Stopping.")
        bottom_menu()
        GroupMod.kill_scripts(hp)
        return
    end

    -- Status checks (health, mana, spirit, encumbrance, mind)
    local status = Recovery.status_check(hp)
    if status == "dead" then
        GroupMod.kill_scripts(hp)
        return
    elseif status == "retreat" then
        Navigation.safe_room(hp)
        GroupMod.kill_scripts(hp)
        return
    end

    -- Empath self-heal
    if hp.empath_self_heal then
        Recovery.empath_self_heal(hp)
    end

    -- Boost long
    if hp.boost_long then
        SpellMod.boost_long(hp)
    end

    -- Spell upkeep refresh
    SpellMod.spell_upkeep(hp)

    -- Combat check: are there targets in the room?
    local targets = GameObj.targets and GameObj.targets() or {}

    if #targets > 0 then
        -- COMBAT PHASE
        local scan_result = Combat.scan_targets(hp)

        if scan_result == "flee" then
            -- Something triggered flee (skip list, too many mobs, etc.)
            if hp.action == 97 then
                -- Quick/qlite mode: walk away and stop
                waitrt()
                walk()
                top_menu()
                respond(Char.name .. ", room change requested. Stopping combat.")
                bottom_menu()
                GroupMod.kill_scripts(hp)
                return
            elseif hp.action == 95 then
                -- Grounded: walk if possible
                if GameState.room_id then
                    waitrt()
                    walk()
                end
            else
                -- Normal: set retreat flag
                hp.action = 98
            end
        else
            -- Execute combat round
            local result = Combat.execute_round(hp)

            if result == "cast" then
                -- Style 9 spell casting
                local override = SpellMod.get_creature_spell_override(hp, Combat.state.current_target)
                local spell = override or SpellMod.choose_spell(hp)
                SpellMod.cast_at_target(hp, spell)
                Combat.stance_guarded(hp)
            elseif result == "wands" then
                -- Wand combat
                Loot.use_wands(hp, Combat.state.current_target)
            end

            -- Loot after combat (not in group/follow mode)
            if not (hp.my_area:find("group") or hp.my_area:find("follow") or hp.my_area:find("qfollow")) then
                Loot.run_loot(hp)
            end

            -- Reset combat action
            if not (hp.my_area:find("group") or hp.my_area:find("follow")) then
                Combat.endcombat_reset(hp)
            end
        end

        -- Check for retreat after combat
        if hp.action == 98 then
            hp.action = 0
            -- Walk to next room (flee from problem room)
            waitrt()
            walk()
        end

    else
        -- NO TARGETS — wander to next room

        -- Check zone boundaries
        Navigation.check_zone_boundary(hp)

        -- Deed mana opportunity
        if hp.deedmana and hp.my_society == "Voln" then
            SpellMod.deed_mana(hp)
        end

        -- Quartz upkeep between rooms
        SpellMod.upkeep_quartz(hp)

        -- Wander
        Navigation.wander(hp)
    end

    -- Brief pause to prevent tight-loop
    pause(0.25)
end
