--- @revenant-script
--- name: shockquest
--- version: 1.16
--- author: Damiza Nihshyde
--- game: dr
--- description: Empath Shock quest - walk to quest locations, meditate vela seed, return to Nadigo.
--- tags: empath, quest, shock
--- Converted from shockquest.lic
--- @lic-certified: complete 2026-03-19

-- DRC, DRCT, DRStats are globals loaded by lib/dr/init

if not DRStats.empath() then
  echo("You're no Empath! Bye!!")
  return
end

local quest_done = false

-- Forward declarations
local get_seed, seed_meditate, nadigo_return

local function check_seed()
  local result = DRC.bput("tap my vela seed",
    "You tap a .+ vela'tohr seed",
    "I could not find what you were referring to")
  if result:find("I could not find what you were referring to") then
    echo("No seed detected! Heading to Nadigo.")
    DRCT.walk_to(15017)
    get_seed()
  end
end

get_seed = function()
  local result = DRC.bput("ask nadigo for shock",
    "Nadigo gazes at you searchingly, then nods",
    "Nadigo gives a slight nod of his head",
    "Nadigo closes his eyes and grows still",
    "Nadigo glances at you, \"It is still too soon")
  if result:find("Nadigo closes his eyes and grows still") or
     result:find("Nadigo gives a slight nod of his head") then
    -- NPC busy or mid-nod retry state — try again
    get_seed()
  elseif result:find("Nadigo gazes at you searchingly, then nods") then
    waitfor("Nadigo says, \"It's strung on a medallion.")
  elseif result:find("It is still too soon") then
    echo("You cannot start this quest again so soon!")
    quest_done = true
  end
end

seed_meditate = function(has_safe, safe_room)
  if quest_done then return end
  local result = DRC.bput("meditate seed",
    "to Nadigo for germination to complete your quest",
    "As the strange sensations subside",
    "You attempt to meditate, but have trouble concentrating",
    "You close your eyes and breathe deeply",
    "seed is still processing the energy")
  if result:find("to Nadigo for germination to complete your quest") then
    waitrt()
    nadigo_return()
  elseif result:find("You attempt to meditate, but have trouble concentrating") then
    if has_safe then DRCT.walk_to(safe_room) end
    echo("Unable to determine time, waiting 10 minutes and trying again.")
    pause(600)
  elseif result:find("seed is still processing the energy") then
    if has_safe then DRCT.walk_to(safe_room) end
    echo("Unable to determine time, waiting 10 minutes and trying again.")
    pause(600)
  elseif result:find("As the strange sensations subside") then
    if has_safe then DRCT.walk_to(safe_room) end
    echo("Success! Waiting 1 hour...")
    pause(600)
    echo("10 minutes down, 50 minutes remaining!")
    pause(600)
    echo("20 minutes down, 40 minutes remaining!")
    pause(600)
    echo("30 minutes down, 30 minutes remaining!")
    pause(600)
    echo("40 minutes down, 20 minutes remaining!")
    pause(600)
    echo("50 minutes down, 10 minutes remaining!")
    pause(600)
    echo("Wait time done! Continuing...")
  elseif result:find("You close your eyes and breathe deeply") then
    waitrt()
  end
end

nadigo_return = function()
  echo("Your seed is full! Returning to Nadigo!")
  DRCT.walk_to(15017)
  fput("remove my seed")
  fput("give nadigo")
  waitfor("Nadigo smiles at you, then turns away, gazing off into the woods.")
  echo("Your quest is completed!")
  quest_done = true
end

-- Main quest flow
check_seed()
if quest_done then return end

DRCT.walk_to(8741)
seed_meditate(true, 4105)
if quest_done then return end

DRCT.walk_to(4111)
seed_meditate()
if quest_done then return end

DRCT.walk_to(3996)
seed_meditate()
if quest_done then return end

DRCT.walk_to(6226)
seed_meditate(true, 6272)
if quest_done then return end

DRCT.walk_to(6260)
seed_meditate(true, 6272)
if quest_done then return end

DRCT.walk_to(2837)
seed_meditate()
if quest_done then return end

DRCT.walk_to(2701)
seed_meditate(true, 2780)
if quest_done then return end

DRCT.walk_to(1951)
seed_meditate()
