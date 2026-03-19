--- @revenant-script
--- name: outdoorsmanship
--- version: 1.0.0
--- author: elanthia-online
--- game: dr
--- description: Train Outdoorsmanship (or Perception) by foraging or collecting items until XP goal is met
--- tags: training, outdoorsmanship, perception, foraging, collecting
---
--- Original: outdoorsmanship.lic by elanthia-online
---   https://elanthipedia.play.net/Lich_script_repository#outdoorsmanship
--- Converted to Revenant Lua by Sordal-GSIV
---
--- @lic-certified: complete 2026-03-18
---
--- Trains Outdoorsmanship (or Perception) by foraging or collecting items
--- until an XP goal is met or an attempt limit is reached.
--- Characters below rank 20 forage rocks; at rank 20+ the script uses
--- the collect command with a configurable item. Retreats from combat
--- before each attempt.
---
--- NOTE: Revenant's DRSkill.getxp uses a 0-19 learning-rate scale
---       (not the 0-34 scale from Lich5). Set outdoorsmanship_mindstate_goal
---       accordingly (e.g. goal of 3 means "gain 3 learning-rate steps").
---
--- Required settings (YAML):
---   forage_item: <item noun to collect at rank 20+>
---
--- Optional settings (YAML):
---   outdoors_room:                  Room ID to train in; trains in place if unset
---   crafting_training_spells:       Array of spell hashes for magic cycling
---   outdoorsmanship_mindstate_goal: Mindstates to gain (default 3, scale 0-19)
---   outdoorsmanship_skip_magic:     true/false — skip all magic routines
---   worn_trashcan:                  Worn container for disposing foraged items
---   worn_trashcan_verb:             Verb to use with worn trashcan (default: put)
---
--- Usage:
---   ;outdoorsmanship
---   ;outdoorsmanship perception
---   ;outdoorsmanship skip_magic
---   ;outdoorsmanship 5
---   ;outdoorsmanship room=1234
---   ;outdoorsmanship "blue flower"
---   ;outdoorsmanship 5 room=1234

-- Maximum mindstate value on Revenant's 0-19 learning-rate scale.
-- Lich5 used a 0-34 "mindstate" scale; Revenant's DRSkill.getxp returns 0-19.
local MINDSTATE_CAP = 19

-- Skill rank below which foraging rocks is used instead of collecting.
local FORAGE_RANK_THRESHOLD = 20

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

local arg_definitions = {
  {
    { name = 'perception',   regex = 'perception',  optional = true, description = 'Check Perception skill in place of Outdoorsmanship' },
    { name = 'skip_magic',   regex = 'skip_magic',  optional = true, description = 'Skip all magic routines, including buffing' },
    { name = 'mindstates',   regex = '^%d+',        optional = true, description = 'Number of mindstates or collection attempts before exiting. Defaults to 3' },
    { name = 'room',         regex = 'room=%d+',    optional = true, description = 'Specific room to forage in. Syntax: room=1234' },
    { name = 'collect_item', regex = '%w+',         optional = true, description = 'Item to collect. Uses forage_item setting if not set. Wrap "multiple words" in double quotes.' },
  }
}

local args = parse_args(arg_definitions)
if not args then return end

-------------------------------------------------------------------------------
-- Load settings
-------------------------------------------------------------------------------

local settings          = get_settings()
local training_spells   = settings.crafting_training_spells or {}
local targetxp          = tonumber(args.mindstates) or tonumber(settings.outdoorsmanship_mindstate_goal) or 3
local worn_trashcan     = settings.worn_trashcan
local worn_trashcan_verb = settings.worn_trashcan_verb
local outdoors_room     = settings.outdoors_room
local skip_magic        = args.skip_magic or settings.outdoorsmanship_skip_magic

-- Override room from argument (room=<id> syntax)
if args.room then
  local room_num = args.room:match('room=(%d+)')
  if room_num then
    outdoors_room = tonumber(room_num)
  end
end

-- Determine train method and item based on current Outdoorsmanship rank
local rank        = DRSkill.getrank('Outdoorsmanship')
local train_method = rank < FORAGE_RANK_THRESHOLD and 'forage' or 'collect'
local forage_item
if rank < FORAGE_RANK_THRESHOLD then
  forage_item = 'rock'
else
  forage_item = args.collect_item or settings.forage_item
end

local skill_name = args.perception and 'Perception' or 'Outdoorsmanship'
local start_exp  = DRSkill.getxp(skill_name)
local end_exp    = math.min(start_exp + targetxp, MINDSTATE_CAP)

-------------------------------------------------------------------------------
-- validate_settings — abort early with a message if anything is wrong
-------------------------------------------------------------------------------

local function validate_settings()
  if not forage_item then
    DRC.message("outdoorsmanship: 'forage_item' must be set in your YAML settings (rank 20+).")
    return false
  end
  if targetxp <= 0 then
    DRC.message("outdoorsmanship: mindstate goal must be positive (got " .. tostring(targetxp) .. ").")
    return false
  end
  if DRSkill.getxp(skill_name) >= end_exp then
    DRC.message("outdoorsmanship: " .. skill_name .. " already at " ..
      tostring(DRSkill.getxp(skill_name)) .. "/" .. tostring(MINDSTATE_CAP) ..
      " mindstates. Nothing to do.")
    return false
  end
  return true
end

-------------------------------------------------------------------------------
-- magic_cleanup — release prepared spell and harnessed mana
-------------------------------------------------------------------------------

local function magic_cleanup()
  if skip_magic then return end
  if #training_spells == 0 then return end
  -- Do not release symbiosis — see elanthia-online/dr-scripts#3141
  DRC.bput('release spell', 'You let your concentration lapse', "You aren't preparing a spell")
  DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")
end

-------------------------------------------------------------------------------
-- train_outdoorsmanship — main training loop
-------------------------------------------------------------------------------

local function train_outdoorsmanship()
  local attempt = 0
  while DRSkill.getxp(skill_name) < end_exp and attempt < targetxp do
    DRC.retreat()
    if not skip_magic then
      DRCA.crafting_magic_routine(settings)
    end
    if train_method == 'forage' then
      DRC.forage(forage_item)
      if DRCI.in_hands(forage_item) then
        DRCI.dispose_trash(forage_item, worn_trashcan, worn_trashcan_verb)
      end
    else
      DRC.collect(forage_item)
      -- DRC.collect already calls waitrt() internally; no explicit call needed
    end
    attempt = attempt + 1
  end
  magic_cleanup()
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

if not validate_settings() then return end

if outdoors_room then
  DRCT.walk_to(outdoors_room)
else
  DRC.message("outdoorsmanship: 'outdoors_room' not set. Training in current room.")
end

if not skip_magic then
  DRC.wait_for_script_to_complete('buff', {'outdoorsmanship'})
end

train_outdoorsmanship()
