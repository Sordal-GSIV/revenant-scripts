-- @lic-certified: complete 2026-03-18
-- Original: combat-trainer.lic by elanthia-online community
-- Converted to Revenant Lua by elanthia-online
--
-- Full combat training automation — weapons, spells, loot, skills, guild abilities.
-- Supports all DR guilds: Warrior, Ranger, Thief, Bard, Empath, Cleric, Paladin,
-- Moon Mage, Necromancer, Barbarian, Trader, Warrior Mage.
--
-- Usage: ;combat-trainer [debug] [construct] [undead] [innocence] [d#] [r#]
--   debug      — enable verbose debug output
--   construct  — override empath no-attack restrictions for constructs
--   undead     — allow empath to attack undead when absolution is up
--   innocence  — empath Innocence mode: avoid actions that end the spell
--   d#         — dance threshold (d2 = keep 2 enemies alive to dance)
--   r#         — retreat threshold (r3 = retreat with 3+ enemies)

local SetupProcess     = require('dr/combat-trainer/setup_process')
local SpellProcess     = require('dr/combat-trainer/spell_process')
local PetProcess       = require('dr/combat-trainer/pet_process')
local AbilityProcess   = require('dr/combat-trainer/ability_process')
local LootProcess      = require('dr/combat-trainer/loot_process')
local ManipulateProcess = require('dr/combat-trainer/manipulate_process')
local TrainerProcess   = require('dr/combat-trainer/trainer_process')
local AttackProcess    = require('dr/combat-trainer/attack_process')

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

local function parse_arguments(args)
    local result = {
        debug     = false,
        construct = false,
        undead    = false,
        innocence = false,
        dance     = nil,
        retreat   = nil,
        flex      = {},
    }
    for _, arg in ipairs(args or {}) do
        local a = arg:lower()
        if a == 'debug' then
            result.debug = true
        elseif a == 'construct' then
            result.construct = true
        elseif a == 'undead' then
            result.undead = true
        elseif a == 'innocence' then
            result.innocence = true
        elseif a:match('^d%d+$') then
            result.dance = tonumber(a:match('%d+'))
        elseif a:match('^r%d+$') then
            result.retreat = tonumber(a:match('%d+'))
        else
            table.insert(result.flex, arg)
        end
    end
    return result
end

-------------------------------------------------------------------------------
-- Settings bootstrap
-------------------------------------------------------------------------------

local function load_settings(parsed_args)
    local settings = get_settings(parsed_args.flex)

    -- Inject CLI overrides
    settings.construct  = parsed_args.construct
    settings.undead     = parsed_args.undead
    settings.innocence  = parsed_args.innocence
    settings.debug_mode = parsed_args.debug

    if parsed_args.dance then
        settings.dance_threshold = parsed_args.dance
    end
    if parsed_args.retreat then
        settings.retreat_threshold = parsed_args.retreat
    end

    return settings
end

-------------------------------------------------------------------------------
-- Global flags registered at startup
-------------------------------------------------------------------------------

local function setup_global_flags()
    Flags.add('ct-spellcast',
        '^Your formation of a targeting pattern around .+ has completed%.',
        'Your target pattern has finished forming around the area',
        '^You feel fully prepared to cast your spell%.',
        "^Your spell pattern snaps into shape with little preparation!")

    Flags.add('last-stance',
        'Setting your Evasion stance to %d+%%, your Parry stance to %d+%%, and your Shield stance to %d+%%.  You have %d+ stance points left')
end

-------------------------------------------------------------------------------
-- Cleanup on script exit (before_dying equivalent)
-------------------------------------------------------------------------------

local ALL_FLAGS = {
    'using-corpse', 'pouch-full', 'container-full',
    'ct-successful-skin', 'ct-lodged', 'ct-parasite', 'ct-engaged',
    'active-mitigation', 'ct-spelllost', 'need-tkt-ammo', 'ct-spellcast',
    'glyph-mana-expired', 'ct-face-what', 'ct-aim-failed', 'ct-powershot-ammo',
    'ct-ranged-ammo', 'ct-ranged-loaded', 'ct-using-repeating-crossbow',
    'ct-ranged-ready', 'ct-accuracy-ready', 'ct-damage-ready', 'ct-need-bless',
    'last-stance', 'ct-regalia-expired', 'ct-starlight-depleted',
    'ct-regalia-succeeded', 'ct-germshieldlost', 'ct-itemdropped',
    'ct-shock-warning', 'ct-maneuver-cooldown-reduced', 'ct-attack-out-of-range',
    'ct-battle-cry-not-facing', 'ct-barbarian-whirlwind',
    'ct-barbarian-whirlwind-expired', 'war-stomp-ready', 'pounce-ready',
}

local function cleanup(settings)
    DRCA.release_cyclics(settings and settings.cyclic_no_release)
    DRCA.shatter_regalia()

    -- Close warrior mage fissure if open
    if DRStats.warrior_mage() then
        local objs = DRRoom.room_objs()
        for _, obj in ipairs(objs or {}) do
            if obj:find('fissure') then
                fput('close fissure')
                break
            end
        end
    end

    for _, flag in ipairs(ALL_FLAGS) do
        Flags.delete(flag)
    end
end

-------------------------------------------------------------------------------
-- Process orchestration
-------------------------------------------------------------------------------

local function make_processes(settings, equipment_manager)
    return {
        SetupProcess.new(settings, equipment_manager),
        SpellProcess.new(settings, equipment_manager),
        PetProcess.new(settings),
        AbilityProcess.new(settings),
        LootProcess.new(settings, equipment_manager),
        ManipulateProcess.new(settings),
        TrainerProcess.new(settings, equipment_manager),
        AttackProcess.new(settings),
    }
end

-------------------------------------------------------------------------------
-- Main combat loop
-------------------------------------------------------------------------------

local function start_combat(game_state, safety_process, combat_processes, settings)
    local stop_requested = false

    -- Hook for external stop signal (via Script.send_message or similar)
    Script.on_message(function(msg)
        if msg == 'stop' then
            stop_requested = true
        end
    end)

    while true do
        for _, process in ipairs(combat_processes) do
            safety_process:execute(game_state)
            local done = process:execute(game_state)
            if done then break end
        end

        pause(0.1)

        if game_state:done_cleaning_up() then
            echo('CombatTrainer::clean_up')
            Script.kill('tendme')
            break
        end

        if stop_requested and not game_state:cleaning_up() then
            game_state:next_clean_up_step()
            game_state:stop_weak_attacks()
            game_state:stop_analyze_combo()
            stop_requested = false
        end
    end
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------

local GameState    = require('dr/combat-trainer/game_state')
local SafetyProcess = require('dr/combat-trainer/safety_process')

local parsed_args      = parse_arguments(Script.args())
local settings         = load_settings(parsed_args)

-- Debug mode
if UserVars.combat_trainer_debug or settings.debug_mode then
    settings.debug_mode = true
end

-- Equip gear
local equipment_manager = EquipmentManager.new(settings)
equipment_manager:empty_hands()

-- Open storage containers
for _, container in ipairs(settings.storage_containers or {}) do
    fput('open my ' .. container)
end

-- Set default stance
DRC.bput('stance set ' .. (settings.default_stance or '60/20/20'), 'Setting your')

-- Wear initial gear set
local gear_set = settings.combat_trainer_gear_set or 'standard'
if settings.cycle_armors_regalia == nil or #(DRCA.parse_regalia() or {}) == 0 then
    equipment_manager:wear_equipment_set(gear_set)
end

setup_global_flags()

local game_state       = GameState.new(settings, equipment_manager)
local safety_process   = SafetyProcess.new(settings, equipment_manager)
local combat_processes = make_processes(settings, equipment_manager)

-- Register cleanup
Script.on_exit(function()
    cleanup(settings)
end)

start_combat(game_state, safety_process, combat_processes, settings)
