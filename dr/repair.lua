--- @revenant-script
--- name: repair
--- version: 1.0.0
--- author: elanthian (original repair.lic)
--- original-authors: elanthian, dr-scripts community contributors
--- game: dr
--- description: All-in-one repair script. Drops off and picks up gear at town repair shops, or self-repairs with wire brush and oil. Supports all 8 crafting disciplines and EquipmentManager gear.
--- tags: repair,crafting,tools,gear,maintenance
--- source: https://github.com/rpherbig/dr-scripts
--- @lic-certified: complete 2026-03-19
---
--- EXAMPLES:
---   ;repair forging                     — run to hometown shop, drop off + pick up forging tools
---   ;repair forging self_repair         — use wire brush and oil on forging tools
---   ;repair forging crossing            — drop off + pick up forging tools in Crossing
---   ;repair forging drop_off shard      — drop forging tools at Shard shop for later pickup
---   ;repair shield "iron bracer" pilum forging shard drop_off
---                                       — drop off specific items + forging tools at Shard
---
--- Conversion notes vs Lich5:
---   * parse_args uses Lua patterns; town extracted from flex args against KNOWN_TOWNS.
---   * immune_list persisted as JSON in UserVars.immune_list (os.time() Unix timestamps).
---   * repair_timer_snap persisted as Unix timestamp string in UserVars.repair_timer_snap.
---   * DRCI.give_item / DRCI.stow_item added to lib/dr/common_items.lua.
---   * os.time() replaces Ruby Time.now (same Unix epoch semantics).

-- ============================================================================
-- Known DR towns — mirrors $HOMETOWN_REGEX in Lich5
-- ============================================================================

local KNOWN_TOWNS = {
  "Crossings", "Dirge", "Ilaya Taipa", "Leth Deriel",
  "Aesry Surlaenis'a", "Hara'jaal", "Mer'Kresh", "Muspar'i", "Ratha",
  "Riverhaven", "Rossman's Landing", "Therenborough", "Throne City",
  "Ain Ghazal", "Boar Clan", "Chyolvea Tayeu'a", "Hibarnhvidar",
  "Fang Cove", "Raven's Point", "Shard",
}

-- ============================================================================
-- Crafting disciplines
-- ============================================================================

local DISCIPLINES = {
  "forging", "tinkering", "carving", "shaping",
  "outfitting", "alchemy", "enchanting", "engineering",
}

-- ============================================================================
-- Argument parsing
-- ============================================================================

local arg_definitions = {
  {
    { name = "drop_off",       regex = "^drop_off$",       optional = true, description = "Drop off gear only, do not pick up" },
    { name = "pick_up",        regex = "^pick_up$",        optional = true, description = "Pick up items only" },
    { name = "self_repair",    regex = "^self_repair$",    optional = true, description = "Use wire brush and oil to self-repair. WARNING: lots of RT." },
    { name = "reset_town",     regex = "^reset_town$",     optional = true, description = "Clears last_repair_town variable" },
    { name = "force_repair",   regex = "^force_repair$",   optional = true, description = "Ignore repair_timer setting" },
    { name = "script_summary", regex = "^script_summary$", optional = true, description = "Show repair options summary" },
  }
}

local args = parse_args(arg_definitions, true)

-- ============================================================================
-- Town matching (replaces $HOMETOWN_REGEX named arg from Lich5)
-- ============================================================================

--- Find a canonical DR town name in a flex-args table.
-- Tries exact match first, then prefix/substring match.
-- @return string|nil town_name, number|nil arg_index
local function find_town_in_flex(flex)
  for i, arg in ipairs(flex) do
    local lower = arg:lower()
    for _, town in ipairs(KNOWN_TOWNS) do
      if town:lower() == lower then return town, i end
    end
    for _, town in ipairs(KNOWN_TOWNS) do
      if town:lower():find(lower, 1, true) then return town, i end
    end
  end
  return nil, nil
end

local raw_flex = args.flex or {}
local town_from_args, town_arg_idx = find_town_in_flex(raw_flex)

-- gear_flex = flex args minus the matched town arg
local gear_flex = {}
for i, arg in ipairs(raw_flex) do
  if i ~= town_arg_idx then
    gear_flex[#gear_flex + 1] = arg
  end
end

-- ============================================================================
-- Settings
-- ============================================================================

local settings     = get_settings()
local bag          = settings.crafting_container
local bag_items    = settings.crafting_items_in_container
local cash_on_hand = settings.repair_withdrawal_amount
local repair_timer = settings.repair_timer
local sort_head    = settings.sort_auto_head
local force_repair = args.force_repair

-- Resolve town: arg → UserVars → settings.repair_town → settings.hometown
local raw_town = town_from_args
             or UserVars.last_repair_town
             or settings.repair_town
             or settings.hometown
             or ""

-- Normalize raw_town to canonical casing from KNOWN_TOWNS
local town = raw_town
do
  local lower = raw_town:lower()
  for _, known in ipairs(KNOWN_TOWNS) do
    if known:lower() == lower or known:lower():find(lower, 1, true) then
      town = known
      break
    end
  end
end

-- Toolbelt / toolset lists
local toolbelts_list = {}
local toolset_list   = {}
for _, name in ipairs(DISCIPLINES) do
  toolbelts_list[#toolbelts_list + 1] = settings[name .. "_belt"]
  toolset_list[#toolset_list + 1]     = settings[name .. "_tools"]
end

-- Load crafting data (for consumables restocking in self-repair mode)
local craft_data    = nil
local crafting_data = get_data("crafting")
if crafting_data and crafting_data["blacksmithing"] then
  craft_data = crafting_data["blacksmithing"][town]
end

-- ============================================================================
-- Immunity tracking
-- immune_list is a JSON object in UserVars mapping item_name → unix_expiry
-- ============================================================================

local function get_immune_list()
  local raw = UserVars.immune_list
  if not raw or raw == "" then return {} end
  local ok, t = pcall(Json.decode, raw)
  return (ok and type(t) == "table") and t or {}
end

local function save_immune_list(list)
  UserVars.immune_list = Json.encode(list)
end

local function is_immune(gear_item)
  local list = get_immune_list()
  local ts   = list[gear_item]
  return ts and ts >= os.time()
end

local function set_immune(gear_item)
  if not Flags["proper-repair"] then return end
  Flags.reset("proper-repair")
  local list = get_immune_list()
  list[gear_item] = os.time() + 7000
  save_immune_list(list)
end

-- ============================================================================
-- Repair timer persistence
-- ============================================================================

local function get_repair_timer_snap()
  return tonumber(UserVars.repair_timer_snap) or 0
end

local function set_repair_timer_snap()
  UserVars.repair_timer_snap = tostring(os.time())
end

local function should_repair()
  if not repair_timer or force_repair then return true end
  return repair_timer <= (os.time() - get_repair_timer_snap())
end

-- ============================================================================
-- Proper-repair immunity flag — detect expert repair message
-- ============================================================================

Flags.add("proper-repair", "Your excellent training in the ways of tool repair")

before_dying(function()
  Flags.delete("proper-repair")
end)

-- ============================================================================
-- Equipment manager
-- ============================================================================

local equipment_manager = DREMgr.EquipmentManager(settings)

-- ============================================================================
-- Reset last_repair_town
-- ============================================================================

local function reset_town(leave)
  if UserVars.last_repair_town then
    if leave then
      DRC.message("Last repair town was: " .. UserVars.last_repair_town .. ". Resetting.")
    end
    UserVars.last_repair_town = nil
  else
    DRC.message("Last repair town not defined.")
  end
end

if args.reset_town then
  reset_town(true)
  return
end

-- ============================================================================
-- Fang Cove time gate (closed evenings/nights)
-- ============================================================================

local function fang_closed()
  local tod = DRC.bput("time", "It is currently")
  local closed = { "evening", "night", "sunrise", "dawn", "early morning" }
  for _, period in ipairs(closed) do
    if tod:find(period, 1, true) then return true end
  end
  return false
end

if town == "Fang Cove" and fang_closed() then
  DRC.message("Fang Cove repair personnel are sleeping off their latest hangover, " ..
              "and are not available for repairs at this hour. " ..
              "Try back between mid-morning and sunset")
  return
end

-- ============================================================================
-- Repair info check
-- ============================================================================

local town_data   = get_data("town")
local repair_info = nil
if town_data and town_data[town] then
  repair_info = town_data[town]["metal_repair"]
end

if not repair_info and not args.self_repair then
  DRC.message("No repair info found for " .. tostring(town) .. ", exiting")
  reset_town()
  return
end

-- ============================================================================
-- Word-boundary match helper (mirrors Ruby's /\bterm\b/i)
-- ============================================================================

local function word_match(text, word)
  -- Escape regex special chars in word, then apply word boundaries
  local escaped = word:gsub("([%(%)%.%[%]%*%+%-%?%^%$%{%}%|\\\\])", "\\%1")
  return Regex.test("(?i)\\b" .. escaped .. "\\b", text)
end

-- ============================================================================
-- Smart get: checks toolbelts → toolsets → EquipmentManager → generic get
-- ============================================================================

local function smart_get_gear(gear_item)
  if not gear_item then return false end

  for _, belt in ipairs(toolbelts_list) do
    if type(belt) == "table" and type(belt.items) == "table" then
      for _, name in ipairs(belt.items) do
        if word_match(name, gear_item) then
          return DRCC.get_crafting_item(gear_item, bag, bag_items, belt)
        end
      end
    end
  end

  for _, tools in ipairs(toolset_list) do
    if type(tools) == "table" then
      for _, tool_name in ipairs(tools) do
        if word_match(tool_name, gear_item) then
          return DRCI.get_item(tool_name, bag)
        end
      end
    end
  end

  local em_items = equipment_manager.items()
  if em_items then
    for _, item_info in ipairs(em_items) do
      local short = item_info.short_name and item_info:short_name() or item_info.name
      if (short and word_match(short, gear_item))
          or (item_info.name and word_match(item_info.name, gear_item)) then
        return equipment_manager.get_item(item_info)
      end
    end
  end

  return DRCI.get_item(gear_item)
end

-- ============================================================================
-- Smart stow: checks toolbelts → toolsets → EquipmentManager return
-- ============================================================================

local function smart_stow_gear(gear_item)
  if not gear_item then return true end

  for _, belt in ipairs(toolbelts_list) do
    if type(belt) == "table" and type(belt.items) == "table" then
      for _, name in ipairs(belt.items) do
        if word_match(name, gear_item) then
          return DRCC.stow_crafting_item(gear_item, bag, belt)
        end
      end
    end
  end

  for _, tools in ipairs(toolset_list) do
    if type(tools) == "table" then
      for _, name in ipairs(tools) do
        if word_match(name, gear_item) then
          return DRCI.put_away_item(gear_item, bag)
        end
      end
    end
  end

  return equipment_manager.return_held_gear()
end

-- ============================================================================
-- Verify funds and restock self-repair consumables
-- ============================================================================

local function verify_funds(gear, repair_own)
  local current_room = GameState.room_id
  DRCM.ensure_copper_on_hand(cash_on_hand, settings, town)
  if repair_own and craft_data then
    DRCT.walk_to(current_room)
    DRCC.check_consumables("oil",
      craft_data["finisher-room"],
      craft_data["finisher-number"],
      bag, bag_items, nil, #gear)
    DRCC.check_consumables("wire brush",
      craft_data["finisher-room"],
      craft_data["wire-brush-number"] or 10,
      bag, bag_items, nil, #gear)
  end
end

-- ============================================================================
-- Self-repair using wire brush + oil
-- ============================================================================

local function self_repair(gear_item)
  local do_repeat = true
  while do_repeat do
    for _, tool in ipairs({ "wire brush", "oil" }) do
      DRCI.get_item(tool, bag)
      local cmd
      if tool == "wire brush" then
        cmd = "rub my " .. gear_item .. " with my wire brush"
      else
        cmd = "pour my oil on my " .. gear_item
      end

      local result = DRC.bput(cmd,
        "Roundtime",
        "not damaged enough",
        "You cannot do that while engaged",
        "cannot figure out how",
        "Pour what")

      if result:find("Roundtime") then
        waitrt()
        DRCI.put_away_item(tool, bag)
      elseif result:find("not damaged enough") then
        DRCI.put_away_item(tool, bag)
        do_repeat = false
        break
      elseif result:find("Pour what") then
        -- Out of oil — restock and retry
        if craft_data then
          DRCC.check_consumables("oil",
            craft_data["finisher-room"],
            craft_data["finisher-number"],
            bag, bag_items, nil)
        end
        DRCI.get_item(tool, bag)
        DRC.bput("pour my oil on my " .. gear_item, "Roundtime")
        waitrt()
        DRCI.put_away_item(tool, bag)
      elseif result:find("You cannot do that while engaged") then
        DRC.message("Cannot repair in combat")
        smart_stow_gear(gear_item)
        DRCI.put_away_item(tool, bag)
        return false  -- signal combat abort to repair_gear
      elseif result:find("cannot figure out how") then
        DRC.message("Something has gone wrong, moving to next item")
        DRCI.put_away_item(tool, bag)
        do_repeat = false
        break
      end
    end
  end
  set_immune(gear_item)
  smart_stow_gear(gear_item)
end

-- ============================================================================
-- Shop repair: give item to NPC, stow the repair ticket
-- ============================================================================

local function shop_repair(gear_item, ri)
  DRC.release_invisibility()
  if DRCI.give_item(ri["name"], gear_item) then
    DRCI.stow_item(ri["name"] .. " ticket")
  else
    smart_stow_gear(gear_item)
  end
end

-- ============================================================================
-- Repair gear list
-- ============================================================================

local function repair_gear(gear, info, repair_own)
  -- Filter out items still immune to damage
  local filtered = {}
  for _, item in ipairs(gear) do
    if not is_immune(item) then
      filtered[#filtered + 1] = item
    end
  end

  if #filtered == 0 then
    DRC.message("All items queued for repair remain immune to damage, exiting")
    return
  end

  local missing = {}
  verify_funds(filtered, repair_own)
  if not repair_own and info then
    DRCT.walk_to(info["id"])
  end

  for _, gear_item in ipairs(filtered) do
    if not smart_get_gear(gear_item) then
      DRC.message("Missing " .. gear_item .. ", skipping")
      missing[#missing + 1] = gear_item
    elseif repair_own then
      if self_repair(gear_item) == false then return end  -- combat abort
    else
      shop_repair(gear_item, info)
    end
  end

  if #missing > 0 then
    DRC.beep()
    for _, item in ipairs(missing) do
      DRC.message("Missing listed gear item: " .. item)
    end
  end
end

-- ============================================================================
-- Build gear list from selections (discipline names expand to tool lists)
-- ============================================================================

local function build_list(selections)
  local gear_list = {}
  local remaining = {}
  for _, s in ipairs(selections) do remaining[#remaining + 1] = s end

  for _, disc in ipairs(DISCIPLINES) do
    for i = #remaining, 1, -1 do
      if remaining[i] == disc then
        local tools = settings[disc .. "_tools"]
        if type(tools) == "table" then
          for _, t in ipairs(tools) do gear_list[#gear_list + 1] = t end
        elseif type(tools) == "string" then
          gear_list[#gear_list + 1] = tools
        end
        table.remove(remaining, i)
        break
      end
    end
  end

  -- Remaining args are literal item names
  for _, r in ipairs(remaining) do
    gear_list[#gear_list + 1] = r
  end
  return gear_list
end

-- ============================================================================
-- Prep full repair from all EquipmentManager items
-- ============================================================================

local function prep_full_repair()
  if not should_repair() then
    local elapsed   = math.floor((os.time() - get_repair_timer_snap()) / 60)
    local timer_min = math.floor((repair_timer or 0) / 60)
    DRC.message(string.format(
      "Last repair was %d minutes ago, which is less than your repair_timer settings\n" ..
      "Currently set to repair only once every %d minutes. Run with arg force_repair to repair anyways.",
      elapsed, timer_min))
    return nil
  end

  set_repair_timer_snap()
  local gear     = {}
  local em_items = equipment_manager.items()
  if em_items then
    for _, item in ipairs(em_items) do
      if not item.skip_repair then
        local adj  = item.adjective or ""
        local name = item.name or ""
        local full = (adj ~= "" and (adj .. " " .. name) or name):match("^%s*(.-)%s*$")
        if full ~= "" then gear[#gear + 1] = full end
      end
    end
  end
  return gear
end

-- ============================================================================
-- Pick up repaired items (give ticket → receive item → stow → repeat)
-- ============================================================================

local function pickup_repaired_items(ri)
  reset_town()
  local ticket_name = ri["name"] .. " ticket"
  if not DRCI.exists(ticket_name) then return end

  DRCT.walk_to(ri["id"])
  DRC.release_invisibility()

  while DRCI.get_item(ticket_name) do
    -- Wait until ticket is marked ready
    while true do
      local look = DRC.bput("look at my ticket",
        "should be ready by now",
        "Looking at the")
      if look:find("should be ready by now") then break end
      pause(30)
    end

    DRC.bput("give " .. ri["name"], "You hand", "takes your ticket")

    -- Wait for the repaired item to land in hand
    local item = nil
    while not item do
      local rh = DRC.right_hand()
      local lh = DRC.left_hand()
      if rh and rh ~= "" then
        item = rh
      elseif lh and lh ~= "" then
        item = lh
      else
        pause(0.01)
      end
    end

    smart_stow_gear(item)
  end
end

-- ============================================================================
-- Empty hands before starting
-- ============================================================================

equipment_manager.empty_hands()

-- ============================================================================
-- Main dispatch
-- ============================================================================

if args.drop_off then
  -- Drop-off only mode
  local gear_list
  if #gear_flex == 0 then
    gear_list = prep_full_repair()
  else
    gear_list = build_list(gear_flex)
  end
  if not gear_list then return end
  UserVars.last_repair_town = town
  repair_gear(gear_list, repair_info)

elseif args.pick_up then
  -- Pick-up only mode
  pickup_repaired_items(repair_info)
  if sort_head then fput("sort auto head") end

elseif #gear_flex == 0 then
  -- No specific items — full repair routine on all equipment
  local gear_list = prep_full_repair()
  if not gear_list then return end
  if not args.self_repair then UserVars.last_repair_town = town end
  repair_gear(gear_list, repair_info, args.self_repair)
  if not args.self_repair then
    pickup_repaired_items(repair_info)
    if sort_head then fput("sort auto head") end
  end

else
  -- Specific items provided — full routine on those items only
  local gear_list = build_list(gear_flex)
  if not args.self_repair then UserVars.last_repair_town = town end
  repair_gear(gear_list, repair_info, args.self_repair)
  if not args.self_repair then
    pickup_repaired_items(repair_info)
  end
end
