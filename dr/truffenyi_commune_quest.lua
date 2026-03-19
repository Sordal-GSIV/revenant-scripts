--- @revenant-script
--- name: truffenyi_commune_quest
--- version: 2.0
--- author: elanthia-online
--- original-author: LostRanger
--- game: dr
--- description: Automates the full Truffenyi commune Cleric quest — altar setup, vision vigil, shrine search, and ox rescue.
--- tags: cleric, quest, theurgy, truffenyi
--- @lic-certified: complete 2026-03-19
---
--- Steps:
---   altar      - Fill and pray at your miniature altar to receive the murky vial (run first).
---                Requires hometown set to Crossing in your settings file.
---   vial       - Drink the murky vial and respond to deity visions for 3+ hours (long-running).
---   findshrine - Search a pre-defined list of rooms near Therenborough to locate the hidden shrine,
---                then begins the shrine sequence automatically.
---   shrine     - Resume the shrine sequence from wherever you currently are in it.
---
--- Usage:
---   ;truffenyi_commune_quest altar
---   ;truffenyi_commune_quest vial
---   ;truffenyi_commune_quest findshrine
---   ;truffenyi_commune_quest shrine
---
--- Converted from truffenyi-commune-quest.lic (original author: LostRanger)
--- Changelog:
---   2026-03-19  Full port to Revenant Lua — all four steps implemented, Huldah vision added.

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Check if an NPC noun/name is present in the room (substring match).
local function npcs_has(name)
  local npcs = DRRoom and DRRoom.npcs
  if type(npcs) ~= "table" then return false end
  for _, v in ipairs(npcs) do
    if v:find(name, 1, true) then return true end
  end
  return false
end

--- Check if a room object is present in the room (substring match).
local function objs_has(name)
  local objs = DRRoom and DRRoom.room_objs
  if type(objs) ~= "table" then return false end
  for _, v in ipairs(objs) do
    if v:find(name, 1, true) then return true end
  end
  return false
end

--- Return true if the right hand holds an item matching substr.
local function rh_has(item)
  local rh = DRC.right_hand()
  return rh ~= nil and rh:find(item, 1, true) ~= nil
end

--- Return true if the left hand holds an item matching substr.
local function lh_has(item)
  local lh = DRC.left_hand()
  return lh ~= nil and lh:find(item, 1, true) ~= nil
end

-- ── Weasel interaction patterns ───────────────────────────────────────────────

local WEASEL_NO_JUMP = {
  "weasel chitters with joy at your vain attempts to reach him, scooting out a little farther",
  "weasel chitters with joy at your vain attempts to reach him, scooting out even farther",
  "Still having a bit of room to spare the weasel continues to creep out, moving even farther",
  "Still having a bit of room to spare the weasel continues to creep out, scooting a bit farther",
  "You jump back from",
}

local WEASEL_JUMP = {
  "Your fingertips brush the bottom edge of the stick at the highest point of your jump",
}

-- ── Step: altar ───────────────────────────────────────────────────────────────

local function do_altar()
  local settings = get_settings()
  if settings.hometown ~= "Crossing" then
    DRC.message("*****\n*****\nDue to needing different favor orbs from any of the 39 aspects, " ..
      "your hometown should be set to Crossing before running this step.\n*****\n*****")
    pause(10)
    return
  end

  if not DRCI.exists("miniature altar") then
    echo("Could not find the miniature altar needed to start the quest.  Are you sure you're on it?")
    return
  end

  -- Read altar description to determine the three required immortal aspects
  local altar_look = DRC.bput("look my miniature altar",
    "A carving along the front of the miniature altar depicts")
  if altar_look == "" then
    echo("Failed to read altar.  Bailing out!")
    return
  end

  -- Split into front-carving and back-carving text
  local altar_front, altar_back = altar_look:match("(.-)%.%s+On the back, another%s+(.+)")
  if not altar_front then
    altar_front = altar_look
    altar_back  = altar_look
  end
  local front = altar_front:lower()
  local back  = (altar_back or altar_look):lower()

  -- Neutral aspect — animal on front carving
  local neutral_aspect
  if     front:find("raven")    then neutral_aspect = "kertigen"
  elseif front:find("unicorn")  then neutral_aspect = "hodierna"
  elseif front:find("wolf")     then neutral_aspect = "meraud"
  elseif front:find("panther")  then neutral_aspect = "damaris"
  elseif front:find("boar")     then neutral_aspect = "everild"
  elseif front:find("ox")       then neutral_aspect = "truffenyi"
  elseif front:find("cobra")    then neutral_aspect = "Hav'roth"
  elseif front:find("dolphin")  then neutral_aspect = "eluned"
  elseif front:find("ram")      then neutral_aspect = "glythtide"
  elseif front:find("cat")      then neutral_aspect = "tamsine"
  elseif front:find("wren")     then neutral_aspect = "faenella"
  elseif front:find("lion")     then neutral_aspect = "chadatru"
  elseif front:find("scorpion") then neutral_aspect = "urrem'tier"
  end

  -- Light aspect — object on front carving
  local light_aspect
  if     front:find("wrapped gift")      then light_aspect = "divyaush"
  elseif front:find("sheath of grain")   then light_aspect = "berengaria"
  elseif front:find("black staff")       then light_aspect = "firulf"
  elseif front:find("batch of feathers") then light_aspect = "phelim"
  elseif front:find("bundle of pelts")   then light_aspect = "kuniyo"
  elseif front:find("toy bridge")        then light_aspect = "alamhif"
  elseif front:find("seashell")          then light_aspect = "peri'el"
  elseif front:find("lodestone")         then light_aspect = "lemicus"
  elseif front:find("wedding ring")      then light_aspect = "saemaus"
  elseif front:find("olive laurel")      then light_aspect = "albreda"
  elseif front:find("silver flute")      then light_aspect = "murrula"
  elseif front:find("intricate sword")   then light_aspect = "rutilor"
  elseif front:find("scythe")            then light_aspect = "eylhaar"
  end

  -- Dark aspect — scene on back carving
  local dark_aspect
  if     back:find("overloaded wagon travelling toward a wooden bridge") then
    dark_aspect = "zachriedek"
  elseif back:find("long row of dismembered bodies leading toward a broken altar") then
    dark_aspect = "asketi"
  elseif back:find("disheveled man weeping behind two women who are locked in combat") then
    dark_aspect = "kerenhappuch"
  elseif back:find("small desert village ravaged by a sand storm") then
    dark_aspect = "dergati"
  elseif back:find("riotous party") then
    dark_aspect = "trothfang"
  elseif back:find("tithe box sitting outside of a small chapel") then
    dark_aspect = "huldah"
  elseif back:find("scene of wilted crops") then
    dark_aspect = "ushnish"
  elseif back:find("simply dressed mage sleeping underneath an elm tree") then
    dark_aspect = "drogor"
  elseif back:find("haggard looking gnome lying on his side") then
    dark_aspect = "be'ort"
  elseif back:find("outskirts of a small village") and back:find("trees skirting the border are fully engulfed in flames") then
    dark_aspect = "harawep"
  elseif back:find("young woman walking away from an orphanage") then
    dark_aspect = "idon"
  elseif back:find("man walking down the aisle of a courtroom") then
    dark_aspect = "botolf"
  elseif back:find("long beach after a horrific battle") then
    dark_aspect = "aldauth"
  end

  -- Validate all three determined
  if not neutral_aspect then echo("Could not determine neutral aspect!") end
  if not light_aspect   then echo("Could not determine light aspect!") end
  if not dark_aspect    then echo("Could not determine dark aspect!") end
  if not (neutral_aspect and light_aspect and dark_aspect) then
    echo("Bailing out!")
    return
  end
  echo("Neutral Aspect: " .. neutral_aspect)
  echo("Light Aspect:   " .. light_aspect)
  echo("Dark Aspect:    " .. dark_aspect)

  -- Fetch each favor orb and place it in the altar
  for _, immortal in ipairs({ neutral_aspect, light_aspect, dark_aspect }) do
    DRC.wait_for_script_to_complete("favor", { immortal })
    if not DRCI.get_item(immortal .. " orb") then
      echo("Failed to get orb for aspect - " .. immortal .. ".  Bailing out!")
      return
    end
    DRC.bput("put my " .. immortal .. " orb in my miniature altar",
      "You put your orb in the miniature altar")
  end

  if not DRCI.get_item("miniature altar") then
    echo("Somehow you lost your altar!  Bailing out!")
    return
  end

  DRC.bput("close my miniature altar", "You close")

  -- Pray at the altar; wait up to 90 seconds for the flames response that spawns the vial
  waitrt()
  put("pray my miniature altar")
  local altar_fired = false
  local timeout_at  = os.time() + 90
  while not altar_fired and os.time() < timeout_at do
    local line = get()
    if line then
      if line:find("The flames surrounding the object diminish slightly allowing you to") then
        altar_fired = true
      end
    else
      pause(0.1)
    end
  end
  if not altar_fired then
    DRC.message("Altar prayer timed out — did not see the flames response.  Check your orbs and try again.")
    return
  end

  DRC.bput("stow my murky vial", "You pick up", "You put", "You tuck")
  echo("Vial acquired - getting healed.")
  DRC.wait_for_script_to_complete("safe-room")
end

-- ── Step: vial ────────────────────────────────────────────────────────────────
-- All known vision triggers → prayer responses.
-- NOTE: Botolf and Aldauth have no confirmed vision triggers in the source data.
local VISIONS = {
  -- Light aspects
  { "working in front of a glowing forge",               "pray Divyaush"     },
  { "toiling in a dusty field",                          "pray Berengaria"   },
  { "huddled in front of a fire in an icy cavern",       "pray Kuniyo"       },
  { "surrounded by occupied cots",                       "pray Peri'el"      },
  { "alone on a raft",                                   "pray Lemicus"      },
  { "young child sitting in the corner",                 "pray Albreda"      },
  { "travelling the desert",                             "pray Murrula"      },
  { "tired and sore after a long day of harvesting crops", "pray Rutilor"    },
  { "sitting on a bar stool",                            "pray Saemaus"      },
  -- Dark aspects
  { "walking through one of your grain fields",          "pray Asketi"       },
  { "sitting amongst a group gathered at an outdoor wedding", "pray Be'ort"  },
  { "sitting on a grassy hilltop",                       "pray Dergati"      },
  { "In your vision the waters pull away from the shore","pray Drogor"       },
  { "facing a crackling fire next to the shore",         "pray Drogor"       },
  { "seated in a small chapel",                          "pray Huldah"       },
  { "seated in the front row of a concert hall",         "pray Idon"         },
  { "entertaining a neighboring farmer at your house",   "pray Kerenhappuch" },
  { "battling a small peccary",                          "pray Trothfang"    },
  { "standing in the snow peering into the window of a rival", "pray Zachriedek" },
}

local function do_vial()
  DREMgr.empty_hands()

  if DRCI.exists("murky vial") then
    DRC.message("This next step will take many hours (approx 3+) to complete.\n" ..
      "You should not be doing anything else except this during this time or you risk death and failure of the quest.")
    pause(5)
    DRC.message("If you are sure you wish to proceed, simply let the script continue, otherwise kill the script.")
    pause(15)
    DRC.message("Beginning quest process in 15 seconds.  Hope you are in a safe area.")
    pause(15)

    if not DRCI.get_item("murky vial") then
      echo("Somehow you lost your vial!  Bailing out!")
      return
    end

    -- First drink: liquid should NOT pour out (confirms correct vial)
    local r1 = DRC.bput("drink my murky vial",
      "You tilt the vial back, but the liquid doesn't pour out",
      "You tilt the vial back and drink deeply from it")
    if not r1:find("doesn't pour out") then
      echo("Somehow you have the wrong vial!  Bailing out!")
      return
    end

    -- Second drink: now drink deeply
    local r2 = DRC.bput("drink my murky vial",
      "You tilt the vial back and drink deeply from it",
      "You tilt the vial back, but the liquid doesn't pour out")
    if not r2:find("drink deeply") then
      echo("Somehow you have the wrong vial!  Bailing out!")
      return
    end
  else
    DRC.message("Assuming you already drank the vial.  If not, kill this script and figure out what happened to your vial.")
  end

  local start_time = os.time()
  DRC.message("Vial step started at " .. os.date("%c", start_time) .. ".")

  while true do
    waitrt()
    local line = get()
    if line then
      -- Respond to deity visions
      for _, v in ipairs(VISIONS) do
        if line:find(v[1], 1, true) then
          waitrt()
          DRC.bput(v[2], "In your")
          break
        end
      end

      -- Drop held item when stomach grumbles
      if line:find("Your stomach grumbles and you realize that you") then
        local held = checkright() or checkleft()
        if held then fput("drop " .. held) end
      end

      -- Quest completion signal
      if line:find("you have my attention, though really you are never far from my sight") then
        local finish_time = os.time()
        local elapsed     = math.floor((finish_time - start_time) / 60)
        DRC.message("Vial step finished at " .. os.date("%c", finish_time) ..
          "! This part of the quest took " .. elapsed .. " minutes to complete.")
        return
      end
    end
  end
end

-- ── Step: findshrine ─────────────────────────────────────────────────────────
-- Room ID list sourced directly from the original .lic script.
local SHRINE_SEARCH_ROOMS = {
  3173, 3172, 3171, 3170, 3160, 3161, 3159, 3158, 3162, 3163, 3164, 3165,
  3166, 3167, 3187, 3207, 3208, 3211, 3209, 3212, 3213, 3210, 3168, 3174,
  3175, 3176, 3177, 3178, 3183, 3184, 3185, 3182, 3186, 3179, 3180, 3181,
  3156, 3157, 3155, 3154, 3153, 3152, 3151, 3121, 3119, 3120, 3112, 3118,
  3114, 3113, 3115, 3117, 3116, 3122, 3124, 3123, 3125, 3126, 3128, 3129,
  3127,
}

local function find_shrine()
  for _, room_id in ipairs(SHRINE_SEARCH_ROOMS) do
    DRCT.walk_to(room_id)
    local result = DRC.bput("search shrine",
      "You notice a quiet spot nearby that everyone else seems to overlook",
      "I could not find what you were referring to",
      "You don't find anything of interest here")
    if result:find("You notice a quiet spot nearby that everyone else seems to overlook") then
      return true
    end
  end
  DRC.message("Could not find shrine after traversing full list.  You will need to find it manually.")
  return false
end

-- ── Step: shrine — sub-phases ─────────────────────────────────────────────────

local function do_shrine_enter_clearing()
  DREMgr.empty_hands()
  if checkroom("Therenborough, Small Shrine") then
    DRC.bput("KNEEL", "You kneel down upon", "You rise to a kneeling")
    DRC.bput("PRAY TRUFFENYI", "You close your eyes and welcome")
    waitfor("Hoof prints speckle this grassy clearing")
  end
  DRC.fix_standing()
  move("go gap")
end

local function do_shrine_follow_magpie()
  DREMgr.empty_hands()
  if checkroom("Deep Forest, Shaded Path") then
    move("east")
  end
end

local function do_shrine_catch_weasel()
  DREMgr.empty_hands()
  if not checkroom("Deep Forest, Open Clearing") then return end

  -- Wait for the magpie to arrive
  while not npcs_has("magpie") do
    pause(1)
  end

  -- Keep jumping for the weasel's stick until the freshly-dug pit appears
  while not checkroomdescrip("The freshly-dug pit is clearly") do
    if DRStats.fatigue() > 50 then
      DRC.fix_standing()
      local jump_result = DRC.bput("jump weasel",
        table.unpack(WEASEL_NO_JUMP), table.unpack(WEASEL_JUMP))

      -- Determine which group matched
      local no_jump = false
      for _, p in ipairs(WEASEL_NO_JUMP) do
        if jump_result:find(p, 1, true) then no_jump = true; break end
      end

      if no_jump then
        pause(1)
      else
        -- Good jump — whistle the magpie to distract the weasel
        local whistle_result = DRC.bput("whistle magpie",
          "The brown magpie ignores you",
          "the scruffy weasel focusing its attention on clinging to the bobbing branch rather than taunting you with the stick")
        if whistle_result:find("the scruffy weasel focusing") then
          local grab_result = DRC.bput("jump weasel",
            "You manage to grab hold of the stick while the weasel",
            "You start to make an effort to jump up")
          if grab_result:find("You manage to grab hold") then
            waitfor("The freshly-dug pit is clearly")
            return
          end
        end
      end
    else
      -- Rest until stamina recovers
      DRC.bput("lie", "You lie down")
      while DRStats.fatigue() < 95 do
        pause(2)
      end
      DRC.fix_standing()
    end
  end
end

local function do_shrine_free_ox()
  if not checkroom("Deep Forest, Inside the Pit") then return end

  -- Phase 1: Pull the ox repeatedly until the notched flat rock appears in the room.
  if rh_has("knobby stick") and not lh_has("flat rock")
     and not objs_has("notched flat rock")
     and not lh_has("burlap twine")
     and not objs_has("length of burlap twine") then
    while not objs_has("notched flat rock") do
      if DRStats.fatigue() > 50 then
        DRC.fix_standing()
        DRC.bput("pull ox", "Roundtime")
        waitrt()
      else
        DRC.bput("lie", "You lie down")
        while DRStats.fatigue() < 95 do pause(2) end
      end
    end
  end

  DRC.fix_standing()

  -- Phase 2: Pick up the rock, handling recovery path where twine is already tied.
  if rh_has("knobby stick") and not lh_has("flat rock")
     and objs_has("notched flat rock")
     and not lh_has("burlap twine")
     and not objs_has("length of burlap twine") then
    DRC.bput("get rock", "You pick up a notched")
    -- Recovery: if twine is already on the stick from a previous attempt, tie rock now
    local look = DRC.bput("look my stick",
      "A sturdy length of burlap twine has been tied to the end of the knobby",
      "The stick appears sturdy enough")
    if look:find("A sturdy length of burlap twine has been tied") then
      DRC.bput("tie rock to stick", "You carefully tie your knobby stick")
    end
    -- else: hold rock, wait for twine to appear (handled in phase 3/4)
  end

  -- Phase 3: Wait for a length of burlap twine to appear while holding the flat rock.
  if rh_has("knobby stick") and lh_has("flat rock")
     and not objs_has("length of burlap twine") then
    while not objs_has("length of burlap twine") do
      pause(2)
    end
  end

  -- Phase 4: Swap the flat rock for the burlap twine.
  if rh_has("knobby stick") and lh_has("flat rock")
     and objs_has("length of burlap twine") then
    DRC.bput("drop rock",  "You drop a notched flat")
    DRC.bput("get twine",  "You pick up a length of")
  end

  -- Phase 5: Tie twine to stick (left=twine, rock is back on ground).
  if rh_has("knobby stick") and lh_has("burlap twine")
     and objs_has("notched flat rock") then
    DRC.bput("tie twine to stick",
      "You carefully tie the twine around the end of your stick, leaving a free end to dangle in the wind")
  end

  -- Phase 6: Alternative — get rock and tie directly (no twine exchange needed).
  if rh_has("knobby stick") and not lh_has("burlap twine")
     and objs_has("notched flat rock") then
    DRC.bput("get rock",       "You pick up a notched")
    DRC.bput("tie rock to stick", "You carefully tie your knobby stick")
  end

  -- Phase 7: Dig the earthen ramp with the crude shovel.
  if rh_has("crude shovel") and not objs_has("finished earthen ramp") then
    while not objs_has("finished earthen ramp") do
      if DRStats.fatigue() > 40 then
        DRC.fix_standing()
        DRC.bput("dig", "Roundtime")
        waitrt()
      else
        DRC.bput("lie", "You lie down")
        while DRStats.fatigue() < 95 do pause(2) end
      end
    end
  end

  -- Phase 8: Push the ox up the ramp.
  if objs_has("finished earthen ramp") and npcs_has("ox") then
    DRC.bput("push ox", "You situate yourself behind the long")
  end

  -- Phase 9: Climb out after the ox has left.
  if objs_has("finished earthen ramp") and not npcs_has("ox") then
    move("go ramp")
  end

  DRC.message("Hooray! You finished.  Now just listen to the ox's spiel.")
end

-- ── Step: shrine — dispatcher ─────────────────────────────────────────────────

local function do_shrine()
  if not Regex.test(
    "Therenborough, Small Shrine|Deep Forest, Clearing|Deep Forest, Shaded Path|Deep Forest, Open Clearing|Deep Forest, Inside the Pit",
    Room and Room.title or "") then
    echo("You can only start this part once you've found the shrine.")
    echo("Bailing out!")
    return
  end

  if checkroom("Therenborough, Small Shrine") or checkroom("Deep Forest, Clearing") then
    do_shrine_enter_clearing()
    do_shrine_follow_magpie()
    do_shrine_catch_weasel()
    do_shrine_free_ox()
  elseif checkroom("Deep Forest, Shaded Path") then
    do_shrine_follow_magpie()
    do_shrine_catch_weasel()
    do_shrine_free_ox()
  elseif checkroom("Deep Forest, Open Clearing") then
    do_shrine_catch_weasel()
    do_shrine_free_ox()
  elseif checkroom("Deep Forest, Inside the Pit") then
    do_shrine_free_ox()
  end
end

-- ── Main ──────────────────────────────────────────────────────────────────────

local step = (Script.vars[1] or ""):lower()

if step == "altar" then
  do_altar()
elseif step == "vial" then
  do_vial()
elseif step == "findshrine" then
  if find_shrine() then
    do_shrine()
  end
elseif step == "shrine" then
  do_shrine()
else
  echo("Usage: ;truffenyi_commune_quest <altar|vial|findshrine|shrine>")
  echo("  altar      - Fill and pray at your miniature altar to receive the murky vial.")
  echo("  vial       - Drink the murky vial and respond to deity visions (3+ hours).")
  echo("  findshrine - Walk the search route to locate the hidden shrine, then do the shrine sequence.")
  echo("  shrine     - Resume shrine sequence from current location.")
end
