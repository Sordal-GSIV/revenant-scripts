--- @revenant-script
--- name: burgle
--- version: 1.0.0
--- author: DR-scripts community contributors (original burgle.lic)
--- original-authors: DR-scripts community contributors
--- game: dr
--- description: Breaking and Entering script for training Locksmithing/Athletics and acquiring loot. Use at your own risk - very high fines if caught.
--- tags: thief,lockpicking,athletics,burglary,training,stealing
--- source: https://elanthipedia.play.net/Lich_script_repository#burgle
--- @lic-certified: complete 2026-03-19
---
--- Conversion notes vs Lich5:
---   * DRSkill.getxp returns 0-19 (was 0-34); max_priority_mindstate default scaled from 26 to 14.
---   * EquipmentManager.new.empty_hands -> DREMgr.empty_hands() or EquipmentManager instance.
---   * XMLData.room_title -> GameState.room_name; XMLData.room_exits -> GameState.room_exits.
---   * Ruby class converted to module-level functions with locals.
---   * parse_args from dependency.lua used for argument parsing.
---   * $HOMETOWN_LIST replaced with town data keys from base-town.json.
---   * Flags module works identically. before_dying for cleanup.
---   * Script.running? -> Script.running(); start_script -> Script.run().
---   * DRC.hide? -> DRC.hide(); hidden? -> hidden(); invisible? -> invisible().
---   * DRCT.get_hometown_target_id now reads from base-town.json data.

require("dependency")

math.randomseed(os.time())

-- ============================================================================
-- Constants
-- ============================================================================

local REVERSE_DIRECTION = {
  east      = "west",
  west      = "east",
  south     = "north",
  north     = "south",
  northeast = "southwest",
  southwest = "northeast",
  northwest = "southeast",
  southeast = "northwest",
}

local ROOM_SEARCHABLE_OBJECTS = {
  ["Kitchen"]   = "counter",
  ["Bedroom"]   = "bed",
  ["Armory"]    = "rack",
  ["Library"]   = "bookshelf",
  ["Sanctum"]   = "desk",
  ["Work Room"] = "table",
}

-- Hometown list for parse_args options (all towns from base-town.json that have services)
local HOMETOWN_LIST = {
  "Crossing", "Dirge", "Leth Deriel", "Shard", "Riverhaven",
  "Therenborough", "Langenfirth", "Ratha", "Aesry", "Mer'Kresh",
  "Hibarnhvidar", "Muspar'i", "Fang Cove", "Rossman's Landing",
  "Throne City", "Hara'jaal", "Boar Clan", "Ain Ghazal",
  "Arthe Dale", "Knife Clan", "Wolf Clan", "Chyolvea",
  "Steelclaw Clan", "Raven's Point",
}

-- ============================================================================
-- State
-- ============================================================================

local scripts_to_unpause = {}
local settings = nil
local burgle_settings = nil
local loot_container = nil
local use_lockpick_ring = nil
local lockpick_container = nil
local max_priority_mindstate = 14  -- Lich5 default 26 scaled to 0-19 range
local rope_adjective = "heavy"
local loot_room_id = nil
local worn_trashcan = nil
local worn_trashcan_verb = nil
local entry_type = nil
local burgle_room = nil
local loot_type = nil
local hometown = nil
local burgle_before_scripts = {}
local burgle_after_scripts = {}
local loot_list = {}
local search_count = 0
local follow_mode = false
local item_whitelist = {}

-- ============================================================================
-- Utility helpers
-- ============================================================================

--- Check if a value is in a table.
local function table_includes(tbl, val)
  if not tbl then return false end
  for _, v in ipairs(tbl) do
    if v == val then return true end
  end
  return false
end

--- Fuzzy-match an item name against what's currently held, word-by-word.
--- Mirrors Lich5's held_item helper from steal.lic.
local function held_item(item)
  local hands = { DRC.right_hand(), DRC.left_hand() }
  for _, hand_item in ipairs(hands) do
    if hand_item then
      for word in hand_item:gmatch("%S+") do
        if item:find(word, 1, true) then
          return hand_item
        end
      end
    end
  end
  return nil
end

--- Check if string matches any pattern in a list (plain match).
local function matches_any(str, patterns)
  if not str or not patterns then return false end
  for _, p in ipairs(patterns) do
    if str:find(p, 1, true) then return true end
  end
  return false
end

--- Capitalize first letter of each word, handling apostrophe-prefixed words.
local function sentence_case(str)
  if not str then return nil end
  return str:gsub("(%a)([%w_']*)", function(first, rest)
    return first:upper() .. rest
  end)
end

-- ============================================================================
-- Loot management
-- ============================================================================

-- Forward declarations for mutual recursion
local drop_item

--- Try to put an item into the loot container.
-- @return boolean true if item was stored
local function put_item(item)
  local result = DRC.bput("put my " .. item .. " in my " .. loot_container,
    "What were you", "You put", "You drop",
    "You can't do that", "You can't put that there",
    "no matter how you arrange it", "even after stuffing",
    "too %w+ to fit in", "There isn't any more room",
    "perhaps try doing that again", "That's too heavy to go in there",
    "Weirdly, you can't manage", "There's no room")
  if result:find("perhaps try doing that again") then
    return put_item(item)
  elseif result:find("You put") or result:find("You drop") then
    return true
  elseif result:find("What were you") then
    -- Fuzzy re-lookup: the game couldn't resolve the name, try matching held items
    local handheld = held_item(item)
    if handheld then
      drop_item(handheld)
    end
    return false
  else
    -- Can't store, drop it
    drop_item(item)
    return false
  end
end

--- Drop an item, retrying if needed.
drop_item = function(item)
  local result = DRC.bput("drop my " .. item,
    "You drop", "You spread", "You wince",
    "would damage it", "smashing it to bits",
    "Something appears different about", "What were you")
  if result:find("would damage it") or result:find("Something appears different about") then
    drop_item(item)
  elseif result:find("What were you") then
    local handheld = held_item(item)
    if handheld then
      drop_item(handheld)
    end
  end
end

--- Store loot from hands (rope/lockpick get stowed, loot gets put in container).
local function store_loot()
  if Flags["burgle-footsteps"] then return end

  local function process_hand(hand_fn, hand_name)
    local item = hand_fn()
    if not item then return end

    -- Rope or lockpick -> stow
    if item:find("lockpick$") or item:find("rope$") then
      DRCI.stow_hand(hand_name)
      return
    end

    -- Whitelisted items always kept
    if matches_any(item, item_whitelist) then
      put_item(item)
      return
    end

    -- Regular loot
    if loot_type == "trashcan" then
      DRCI.dispose_trash(item, worn_trashcan, worn_trashcan_verb)
    else
      -- drop, bin, pawn, keep all store temporarily then process later
      if put_item(item) then
        table.insert(loot_list, item)
      end
    end
  end

  process_hand(DRC.right_hand, "right")
  if Flags["burgle-footsteps"] then return end
  process_hand(DRC.left_hand, "left")
end

--- Pawn an item at the local pawnshop.
local function pawn_item(item)
  local result = DRC.bput("sell my " .. item,
    "You sell your",
    "You'll want to empty that first",
    "shakes .+ head and says",
    "Relf briefly glances at your",
    "Ishh briefly glances at your",
    "Oweede growls and says,",
    "There's folk around here that'd slit",
    "but it's much too fine for me.",
    "Bynari laughs")
  if not result:find("You sell your") then
    drop_item(item)
  end
end

--- Execute extra scripts (before/after hooks).
local function execute_extra_scripts(extra_scripts)
  if not extra_scripts then return end
  for _, script in ipairs(extra_scripts) do
    DRC.message("***STATUS*** EXECUTE " .. script)
    -- Split script name from args
    local parts = {}
    for word in script:gmatch("%S+") do
      table.insert(parts, word)
    end
    local script_name = table.remove(parts, 1)
    local script_args = table.concat(parts, " ")
    DRC.wait_for_script_to_complete(script_name, script_args ~= "" and script_args or nil)
  end
end

--- Process accumulated loot after exiting the house.
local function process_loot()
  if not loot_type then return end
  if not loot_type:find("drop") and not loot_type:find("pawn")
     and not loot_type:find("bin") and not loot_type:find("trashcan") then
    return
  end
  if #loot_list == 0 then return end

  if loot_room_id then
    DRCT.walk_to(loot_room_id)
  end

  for _, item in ipairs(loot_list) do
    local result = DRC.bput("get " .. item .. " from my " .. loot_container,
      "You get", "What were you referring to")
    if result:find("You get") then
      if loot_type == "bin" then
        DRC.bput("put " .. item .. " in bin",
          "nods toward you as your .* falls into the .* bin")
      elseif loot_type == "pawn" then
        pawn_item(item)
      elseif loot_type == "drop" then
        drop_item(item)
      end
    end
    -- "What were you referring to" = stacked/missing, skip
  end
end

-- ============================================================================
-- Entry method management
-- ============================================================================

--- Check if an entry method item exists in inventory.
local function check_entry(etype)
  if etype:find("rope") then
    return DRCI.exists(rope_adjective .. " rope")
  elseif etype:find("lockpick") then
    if use_lockpick_ring then
      return DRCI.exists(lockpick_container)
    else
      return DRCI.exists("lockpick")
    end
  end
  return false
end

--- Resolve cycle/priority entry type — pick whichever entry method is available,
--- preferring the specified type.
local function check_cycle_priority(preferred)
  if preferred:find("rope") then
    if not check_entry("rope") then
      if not check_entry("lockpick") then
        DRC.message("Couldn't find any entry method.")
        return false
      else
        DRC.message("Set to cycle or priority, but could only find lockpick.")
      end
      entry_type = "lockpick"
    else
      entry_type = "rope"
    end
  elseif preferred:find("lockpick") then
    if not check_entry("lockpick") then
      if not check_entry("rope") then
        DRC.message("Couldn't find any entry method.")
        return false
      else
        DRC.message("Set to cycle or priority, but could only find rope.")
      end
      entry_type = "rope"
    else
      entry_type = "lockpick"
    end
  else
    DRC.message("Invalid priority type.")
    return false
  end
  return true
end

--- Get the entry item into your right hand.
local function get_entry(etype)
  if etype:find("rope") then
    local result = DRC.bput("get my " .. rope_adjective .. " rope",
      "You get", "You are already holding", "What were you")
    if result:find("What were you") then
      DRC.message("Couldn't find entry item: " .. rope_adjective .. " rope")
      return false
    end
  elseif etype:find("lockpick") then
    if use_lockpick_ring then
      return true  -- ring is worn, no need to get
    end
    local result = DRC.bput("get my lockpick",
      "You get", "You are already holding", "What were you")
    if result:find("What were you") then
      DRC.message("Couldn't find entry item: lockpick")
      return false
    end
  end
  return true
end

-- ============================================================================
-- Settings validation
-- ============================================================================

--- Validate bin settings — falls back to pawn if not a thief or no bin in town.
local function validate_bin_settings()
  if DRStats.thief() then
    loot_room_id = DRCT.get_hometown_target_id(hometown, "thief_bin")
    if not loot_room_id then
      DRC.message("Binning not supported in " .. hometown .. ". Attempting fallback to pawning loot.")
      pause(5)
      loot_type = "pawn"
      -- validate_pawn_settings inline
      loot_room_id = DRCT.get_hometown_target_id(hometown, "pawnshop")
      if not loot_room_id then
        loot_type = "drop"
        DRC.message("Pawning not supported in " .. hometown .. ". Fallback to dropping loot.")
      end
    end
  else
    DRC.message("You are not a thief. You can't use thief bins. Attempting fallback to pawning loot.")
    pause(5)
    loot_type = "pawn"
    loot_room_id = DRCT.get_hometown_target_id(hometown, "pawnshop")
    if not loot_room_id then
      loot_type = "drop"
      DRC.message("Pawning not supported in " .. hometown .. ". Fallback to dropping loot.")
    end
  end
end

--- Validate pawn settings — falls back to drop if no pawnshop in town.
local function validate_pawn_settings()
  loot_room_id = DRCT.get_hometown_target_id(hometown, "pawnshop")
  if not loot_room_id then
    loot_type = "drop"
    DRC.message("Pawning not supported in " .. hometown .. ". Fallback to dropping loot.")
  end
end

--- Validate all burgle settings before starting.
local function valid_burgle_settings()
  if not burgle_settings or not next(burgle_settings) then
    DRC.message("You have empty burgle_settings. These must be set before running.")
    return false
  end

  -- Handle array of rooms (sort by distance)
  if type(burgle_room) == "table" then
    burgle_room = DRCT.sort_destinations(burgle_room)[1]
  end
  if type(burgle_room) ~= "number" then
    DRC.message("Invalid burgle_settings:room setting. This must be room id of the room you want to burgle from.")
    return false
  end

  if not entry_type or not (entry_type:find("lockpick") or entry_type:find("rope") or entry_type:find("cycle") or entry_type:find("priority")) then
    DRC.message("Invalid burgle_settings:entry_type setting.")
    return false
  end

  local max_search = burgle_settings.max_search_count or 0
  if max_search > 0 then
    local result = DRC.bput("open my " .. loot_container,
      "already open", "You.+open", "You spread your arms",
      "Please rephrase that command", "What were you referring",
      "You can't do that",
      "This is probably not the time nor place for that")
    if result:find("This is probably not the time nor place") then
      if follow_mode then
        DRC.message("Couldn't verify your bag due to room restrictions. Allowing the script to continue assuming your " .. loot_container .. " is open and available.")
        return true
      else
        DRCT.walk_to(burgle_room)
        return valid_burgle_settings()
      end
    elseif result:find("Please rephrase") or result:find("What were you referring") or result:find("You can't do that") then
      DRC.message("You do not have a burgle_settings:loot_container set/set to container you have. Loot must have a place to be stored prior to exiting the house, even if dropping loot.")
      return false
    end
  end

  if loot_type then
    if loot_type:find("bin") then
      validate_bin_settings()
    elseif loot_type:find("pawn") then
      validate_pawn_settings()
    else
      loot_room_id = nil
    end
  end

  return true
end

-- ============================================================================
-- House navigation and looting
-- ============================================================================

--- Move within the house — sneaks when hidden, walks when not.
local function burgle_move(direction)
  local max_search = burgle_settings.max_search_count or 0
  if not invisible() and hidden() and search_count < max_search and not Flags["burgle-footsteps"] then
    local result = DRC.bput("sneak " .. direction,
      "Someone Else's Home", "Sneaking is an", "You can't", "In YOUR condition")
    if result:find("Someone Else's Home") then return end
  end
  DRC.bput(direction, "Someone Else's Home")
end

--- Search a room's target object for loot.
local function search_for_loot(target)
  if Flags["burgle-footsteps"] then return end
  if not target then return end

  -- Try to hide before searching
  if not invisible() then
    DRC.hide()
    if not hidden() then
      DRC.message("Couldn't hide. Searching to avoid delays.")
    end
  end

  if Flags["burgle-footsteps"] then return end

  local max_search = burgle_settings.max_search_count or 0
  local result = DRC.bput("search " .. target, "It looks valuable", "Roundtime", "I could not")
  waitrt()
  search_count = search_count + 1

  if result:find("It looks valuable") then
    if DRC.right_hand() and DRC.left_hand() then
      store_loot()
    end
    return
  elseif burgle_settings.retry and search_count < max_search and not Flags["burgle-footsteps"] then
    search_for_loot(target)
    return
  end
end

--- Recursively rob rooms in the house.
-- @param direction string|nil The direction we came from (to avoid backtracking)
local function rob_the_place(direction)
  local visited = {}
  if direction then
    table.insert(visited, direction)
  end

  -- Parse room type from title: [Someone Else's Home, Kitchen]
  local room_name = GameState.room_name or ""
  local room_type = room_name:match("%[%[Someone Else's Home, (.+)%]%]")
  if not room_type then return end

  -- Search lootable objects unless room is blacklisted
  local room_blacklist = burgle_settings.room_blacklist or {}
  if not table_includes(room_blacklist, room_type) then
    search_for_loot(ROOM_SEARCHABLE_OBJECTS[room_type])
  end

  local max_search = burgle_settings.max_search_count or 0

  -- Explore other rooms
  local exits = GameState.room_exits or {}
  while #exits > #visited and search_count < max_search and not Flags["burgle-footsteps"] do
    -- Pick a random unvisited direction (matches Ruby .sample behavior)
    local unvisited = {}
    for _, exit in ipairs(exits) do
      if not table_includes(visited, exit) then
        table.insert(unvisited, exit)
      end
    end
    if #unvisited == 0 then break end
    local newdir = unvisited[math.random(#unvisited)]

    table.insert(visited, newdir)
    local reverse = REVERSE_DIRECTION[newdir]

    burgle_move(newdir)

    if not Flags["burgle-footsteps"] then
      rob_the_place(reverse)
    end

    burgle_move(reverse)
  end
end

-- ============================================================================
-- End / cleanup
-- ============================================================================

local function end_burgle()
  DRC.safe_unpause_list(scripts_to_unpause)
end

-- ============================================================================
-- Main burgle routine
-- ============================================================================

local function burgle()
  -- Check cooldown
  local recall = DRC.bput("burgle recall",
    "You should wait at least %d+ roisaen for the heat to die down",
    "The heat has died down from your last caper")
  if not recall:find("The heat has died down") then
    return false
  end

  if not follow_mode then
    -- Resolve entry type for cycle/priority modes
    if entry_type:find("priorityrope") then
      if DRSkill.getxp("Athletics") <= max_priority_mindstate or DRSkill.getxp("Athletics") < DRSkill.getxp("Locksmithing") then
        if not check_cycle_priority("rope") then return false end
      else
        if not check_cycle_priority("lockpick") then return false end
      end
    elseif entry_type:find("prioritylockpick") then
      if DRSkill.getxp("Locksmithing") <= max_priority_mindstate or DRSkill.getxp("Locksmithing") < DRSkill.getxp("Athletics") then
        if not check_cycle_priority("lockpick") then return false end
      else
        if not check_cycle_priority("rope") then return false end
      end
    elseif entry_type:find("rope") then
      if not check_entry(entry_type) then
        DRC.message("Couldn't find entry item: " .. rope_adjective .. " rope")
        return false
      end
    elseif entry_type:find("lockpick") then
      if not check_entry(entry_type) then
        if use_lockpick_ring then
          DRC.message("Couldn't find entry item: " .. lockpick_container)
        else
          DRC.message("Couldn't find entry item: lockpick")
        end
        return false
      end
    elseif entry_type:find("cycle") then
      local athl_xp = DRSkill.getxp("Athletics")
      local lock_xp = DRSkill.getxp("Locksmithing")
      if athl_xp < lock_xp then
        if not check_cycle_priority("rope") then return false end
      elseif athl_xp == lock_xp then
        if DRSkill.getrank("Athletics") < DRSkill.getrank("Locksmithing") then
          if not check_cycle_priority("rope") then return false end
        else
          if not check_cycle_priority("lockpick") then return false end
        end
      else
        if not check_cycle_priority("lockpick") then return false end
      end
    else
      DRC.message("Unknown entry method: " .. entry_type)
      return false
    end
  end

  -- Empty hands before starting
  local em = DREMgr.EquipmentManager(settings)
  em:empty_hands()
  if DRC.right_hand() or DRC.left_hand() then
    echo("Exited due to item that could not be stowed. Please check your hands and gear settings then try again.")
    return false
  end

  -- Travel to burgle room unless following
  if not follow_mode then
    if not DRCT.walk_to(burgle_room) then
      DRC.message("Unable to get to your burgle room. Exiting to prevent errors.")
      return false
    end
  end

  execute_extra_scripts(burgle_before_scripts)

  if not follow_mode then
    if not get_entry(entry_type) then return false end
  end

  -- Stop playing music to prevent race conditions with stealth
  if Script.running("performance") or Script.running("play") then
    DRC.bput("stop play", "In the name of love", "You stop playing", "But you're not performing anything")
  end

  -- Buff for burgle if waggle set exists
  if settings.waggle_sets and settings.waggle_sets.burgle then
    DRC.wait_for_script_to_complete("buff", "burgle")
  end

  DRC.fix_standing()

  -- Ensure hidden or invisible before starting
  if not invisible() then
    local hide_attempts = 3
    while not DRC.hide() do
      hide_attempts = hide_attempts - 1
      if hide_attempts <= 0 then
        DRC.message("Couldn't hide. Find a better room.")
        return false
      end
    end
  end

  -- Group burgle flags
  Flags.add("group-burgle-disband", "With aid from your group")
  Flags.add("group-burgle-leave", "With aid from his group", "With aid from her group")

  -- Enter the house
  if follow_mode then
    waitfor("Someone Else's Home")
  else
    DRC.bput("burgle", "Someone Else's Home")
  end

  -- Leave group so you aren't carried around
  if Flags["group-burgle-leave"] then
    fput("leave")
  elseif Flags["group-burgle-disband"] then
    fput("disband stalk")
    fput("disband group")
  else
    pause(1)  -- no indicator for 2-person rope entry group status
  end

  -- Rob the house
  local max_search = burgle_settings.max_search_count or 0
  if max_search > 0 then
    search_count = 0
    rob_the_place(nil)
  end

  -- Exit through window
  DRC.bput("go window", "You take a moment to reflect on the caper")

  -- Release invisibility since it breaks many things
  DRC.release_invisibility()

  -- Reset footsteps flag
  Flags.reset("burgle-footsteps")

  -- Store any remaining loot/items in hands
  store_loot()

  execute_extra_scripts(burgle_after_scripts)

  -- Process loot (pawn, bin, drop)
  process_loot()

  return true
end

-- ============================================================================
-- Argument parsing and initialization
-- ============================================================================

local arg_definitions = {
  {
    { name = "start",     regex = "^start$",  optional = false, description = "Required: prevents accidentally running burgle" },
    { name = "entry",     options = {"lockpick", "rope", "cycle", "prioritylockpick", "priorityrope"}, optional = true, description = "Override yaml setting for entry_type." },
    { name = "roomid",    regex = "^%d+$",    optional = true,  description = "Override yaml setting and go to room id (#) specified." },
    { name = "loot_type", options = {"drop", "keep", "pawn", "bin", "trashcan"}, optional = true, description = "Override yaml setting for loot." },
    { name = "hometown",  options = HOMETOWN_LIST, optional = true, description = "Override yaml hometown settings for bin and pawn." },
    { name = "follow",    options = {"follow"}, optional = true, description = "Follow another player, don't actually burgle. You must group with them first." },
  }
}

local args = parse_args(arg_definitions)
if not args then return end

-- Fix hometown to sentence case if specified
if args.hometown then
  args.hometown = sentence_case(args.hometown)
  -- Kludge fix for Mer'Kresh
  if args.hometown == "Mer'kresh" then
    args.hometown = "Mer'Kresh"
  end
end

follow_mode = args.follow ~= nil

-- Pause other scripts
scripts_to_unpause = DRC.safe_pause_list()

-- Start jail-buddy if not running
if not Script.running("jail-buddy") then
  if Script.exists("jail-buddy") then
    Script.run("jail-buddy")
  end
end

-- Load settings
settings = get_settings()
burgle_settings = settings.burgle_settings or {}
loot_container = burgle_settings.loot_container
use_lockpick_ring = burgle_settings.use_lockpick_ring
lockpick_container = burgle_settings.lockpick_container
-- Lich5 default 26 on 0-34 scale -> ~14 on 0-19 scale
max_priority_mindstate = burgle_settings.max_priority_mindstate or 14
rope_adjective = burgle_settings.rope_adjective or "heavy"
worn_trashcan = settings.worn_trashcan
worn_trashcan_verb = settings.worn_trashcan_verb
item_whitelist = burgle_settings.item_whitelist or {}

-- Override from command line args
entry_type = args.entry or burgle_settings.entry_type
if args.roomid then
  burgle_room = tonumber(args.roomid)
else
  burgle_room = burgle_settings.room
end
loot_type = args.loot_type or burgle_settings.loot

-- Validate trashcan settings
if loot_type and loot_type:find("trashcan") then
  if not worn_trashcan or not worn_trashcan_verb then
    echo("The `loot_type: trashcan` setting requires the base.yaml `worn_trashcan:` and `worn_trashcan_verb:` settings to be set in your yaml.")
    end_burgle()
    return
  end
end

hometown = args.hometown or burgle_settings.hometown or settings.burgle_town or settings.fang_cove_override_town or settings.hometown

burgle_before_scripts = burgle_settings.before or {}
burgle_after_scripts = burgle_settings.after or {}

-- Fallback lockpick settings from old pick config
if entry_type and (entry_type:find("lockpick") or entry_type:find("cycle")) then
  if use_lockpick_ring == nil or lockpick_container == nil then
    DRC.message("Settings for lockpick rings are now in burgle_settings:use_lockpick_ring and burgle_settings:lockpick_container.")
    DRC.message("Using old setting of use_lockpick_ring and lockpick_container from pick for now, but this will be removed in the future.")
    DRC.message("To reuse the same settings, please use anchors: https://github.com/elanthia-online/dr-scripts/wiki/YAML-Anchors")
    if use_lockpick_ring == nil then use_lockpick_ring = settings.use_lockpick_ring end
    if lockpick_container == nil then lockpick_container = settings.lockpick_container end
  end
end

-- Add footsteps warning flag (safe_mode default true)
if burgle_settings.safe_mode ~= false then
  Flags.add("burgle-footsteps", "Footsteps nearby make you wonder if you're pushing your luck.")
end

-- Register cleanup
before_dying(function()
  Flags.delete("burgle-footsteps")
  Flags.delete("group-burgle-leave")
  Flags.delete("group-burgle-disband")
end)

-- Validate settings
if not valid_burgle_settings() then
  DRC.message("It is very important that you check the documentation before running: https://elanthipedia.play.net/Lich_script_repository#burgle")
  DRC.message("This is a dangerous script to run if it's not understood. If you get caught there are very high fines, and the loss of all your items is possible if you can't pay your debt.")
  pause(10)
  end_burgle()
  return
end

-- Run the burgle
burgle()
end_burgle()
