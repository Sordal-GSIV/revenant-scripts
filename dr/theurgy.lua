--- @revenant-script
--- name: theurgy
--- version: 1.0
--- author: Gohhlkaspi, Eledryn, elanthia-online (original Lich5)
--- game: dr
--- description: Full theurgy ritual and commune automation for DR clerics, paladins, and other
---   devotion-based guilds. Handles supply purchasing, all rituals (tithe, bath, incense, wine,
---   prayer mat, bead meditation, sirese seed, altar cleaning, dancing, etc.) and all communes
---   (Eluned, Tamsine, Truffenyi, Kertigen). Supports prayer mats and town-specific shops.
--- tags: theurgy, ritual, commune, cleric, paladin, devotion, favor
--- @lic-certified: complete 2026-03-19
---
--- Original: theurgy.lic (https://elanthipedia.play.net/Lich_script_repository#theurgy)
--- Converted to Revenant Lua with full feature parity.
---
--- Settings (in your profile JSON):
---   hometown               : "Crossing" (required)
---   theurgy_supply_container: "satchel" — container for theurgy supplies
---   prayer_mat_container   : "pack"     — container for prayer mat (defaults to supply_container)
---   water_holder           : "vial"     — item that holds holy water
---   flint_lighter          : "flint"    — flint to light incense
---   prayer_mat             : "mat"      — prayer mat item name (if using one)
---   theurgy_use_prayer_mat : true/false — whether to use prayer mat instead of altar
---   theurgy_prayer_mat_room: 1900       — room ID to unroll mat
---   immortal_aspect        : "lion"     — your aspect for bead meditation
---   favor_god              : "meraud"   — god to pray to
---   communes               : ["Eluned","Tamsine","Truffenyi","Kertigen"]
---   theurgy_blacklist      : ["carve_bead","tithe"] — rituals to skip
---   theurgy_whitelist      : []                      — if set, only these rituals
---   theurgy_exp_threshold  : 0          — stop when Theurgy XP learning falls below this (0=run all)
---   theurgy_supply_levels  : { "incense": { "min": 1, "target": 3 } }
---   safe_room              : 12345      — safe room for parchment invocation
---   crafting_container     : "toolbox"  — for carve-bead sub-script
---   engineering_belt       : "belt"     — for carve-bead sub-script
---   tithe                  : true/false — whether to run tithe sub-script
---   fang_cove_override_town: "Crossing" — if in Fang Cove, use another town's shops

-------------------------------------------------------------------------------
-- Requires
-------------------------------------------------------------------------------

local DRCTH = require("lib/dr/common_theurgy")

-------------------------------------------------------------------------------
-- Load settings and data
-------------------------------------------------------------------------------

local settings = get_settings()

local hometown = settings.fang_cove_override_town or settings.hometown
if not hometown then
  respond("[theurgy] Error: no 'hometown' in settings. Please configure your profile.")
  return
end

local all_theurgy_data = get_data("theurgy")
if not all_theurgy_data then
  respond("[theurgy] Error: could not load theurgy data from data/dr/base-theurgy.json")
  return
end

local data = all_theurgy_data[hometown]
if not data then
  respond("[theurgy] Error: no theurgy data for hometown '" .. hometown .. "'")
  respond("[theurgy] Available: Crossing, Ratha, Shard, Aesry, Boar Clan, Hibarnhvidar, Haven")
  return
end

local immortal_to_aspect = all_theurgy_data.immortal_to_aspect or {}

-------------------------------------------------------------------------------
-- Config (mirrors TheurgyActions instance variables)
-------------------------------------------------------------------------------

local safe_room             = settings.safe_room
local immortal_aspect       = settings.immortal_aspect
local bag                   = settings.crafting_container
local bag_items             = settings.crafting_items_in_container
local belt                  = settings.engineering_belt
local supply_ctr            = settings.theurgy_supply_container
local prayer_mat_ctr        = settings.prayer_mat_container or supply_ctr
local water_holder          = settings.water_holder
local flint_lighter         = settings.flint_lighter
local prayer_mat            = (settings.theurgy_use_prayer_mat and settings.prayer_mat) or nil
local prayer_mat_room       = settings.theurgy_prayer_mat_room
local chosen_communes       = settings.communes or {}
local favor_god             = settings.favor_god
local theurgy_exp_threshold = settings.theurgy_exp_threshold or 0

-- Mutable state
local mat_unrolled    = false
local research_topic  = nil
local worn_chain      = false    -- prayer chain was worn, not in supply container
local item_info       = {}       -- name -> { name, shop, stackable, parts, count, restock, target }
local rituals         = {}       -- ordered list of ritual action tables
local communes        = {}       -- ordered list of commune action tables

-------------------------------------------------------------------------------
-- Flags
-------------------------------------------------------------------------------

Flags.add("theurgy-commune",
  "fully prepared to seek assistance from the Immortals once again",
  "You will not be able to open another divine conduit yet",
  "You grind some dirt in your fist",
  "You feel warmth spread throughout your body",
  "The power of Truffenyi has answered your prayer",
  "The thick smell of ozone fills your nostrils",
  "You stop as you realize that you have attempted a commune too recently in the past.")
Flags.add("theurgy-eluned",
  "You grind some dirt in your fist",
  "The waters of Eluned are still in your thoughts")
Flags.add("theurgy-tamsine",
  "You feel warmth spread throughout your body",
  "You have been recently enlightened by Tamsine")
Flags.add("theurgy-truffenyi",
  "The power of Truffenyi has answered your prayer",
  "You are still captivated by Truffenyi's favor")
Flags.add("theurgy-kertigen",
  "The thick smell of ozone fills your nostrils",
  "The sounds of Kertigen's forge still ring in your ears")
Flags.add("research_done", "^Breakthrough!")

before_dying(function()
  Flags.delete("theurgy-commune")
  Flags.delete("theurgy-eluned")
  Flags.delete("theurgy-tamsine")
  Flags.delete("theurgy-truffenyi")
  Flags.delete("theurgy-kertigen")
  Flags.delete("research_done")
end)

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------

--- Check if a value is in an array.
local function includes(arr, val)
  if type(arr) ~= "table" then return false end
  for _, v in ipairs(arr) do
    if v == val then return true end
  end
  return false
end

--- Count an item for supply tracking.
-- Handles stackable (count parts/uses), any-container, and container-specific.
-- @param item_table table { name, stackable, any_container, ... }
-- @return number
local function count(item_table)
  if not item_table then return 0 end
  local name = item_table.name
  if item_table.stackable then
    -- count_item_parts scans ordinals across all inventory
    return DRCI.count_item_parts(name)
  elseif item_table.any_container then
    -- Tap check: see if item exists anywhere
    local result = DRC.bput("tap my " .. name,
      "You tap", "I could not find", "What were you referring to",
      "already in your inventory")
    if result:find("You tap") or result:find("already in") then return 1 end
    if DRCI.in_hands(name) then return 1 end
    return 0
  else
    return DRCI.count_items_in_container(name, supply_ctr)
  end
end

--- Check if holy water is available in the water holder.
-- Gets the holder from supply_ctr, checks contents, puts back.
-- @return boolean
local function holy_water()
  if not supply_ctr or not water_holder then return false end
  if not DRCI.get_item(water_holder, supply_ctr) then return false end
  local has = DRCI.inside("holy water", water_holder)
  DRCI.put_away_item(water_holder, supply_ctr)
  return has
end

--- Get the aspect corresponding to the character's most recent favor.
-- @return string|nil Aspect name (e.g. "lion"), or nil if no favor
local function last_favor_aspect()
  local result = DRC.bput("favor",
    "You are not currently favored",
    "Your most recent favor was granted by")
  if result:find("not currently favored") then return nil end
  local god_name = result:match("Your most recent favor was granted by (%a[%a']+)")
  if not god_name then return nil end
  return immortal_to_aspect[god_name]
end

--- Build the item_info map by counting existing supplies.
-- @param ritual_list table Array of ritual/commune tables (each has .items)
local function collect_item_info(ritual_list)
  -- Gather unique items across all rituals and communes
  local seen = {}
  local all_items = {}
  for _, action in ipairs(ritual_list) do
    for _, item in ipairs(action.items or {}) do
      if not seen[item.name] then
        seen[item.name] = true
        all_items[#all_items + 1] = item
      end
    end
  end

  item_info = {}
  local supply_levels = settings.theurgy_supply_levels or {}
  for _, item in ipairs(all_items) do
    local n = item.name
    local c = count(item)
    local levels = supply_levels[n] or {}
    item_info[n] = {
      name       = n,
      shop       = item.shop,
      stackable  = item.stackable or false,
      parts      = (item.shop and item.shop.parts) or item.parts or 1,
      count      = c,
      on_hand    = c > 0,
      restock    = c < (levels.min or 1),
      target     = levels.target or 1,
    }
  end
end

-------------------------------------------------------------------------------
-- Research management (pause/resume spell research around bless casting)
-------------------------------------------------------------------------------

local function complete_or_interrupt_research()
  local research_types = { "Fundamental", "Augmentation", "Stream", "Sorcery", "Utility", "Warding" }
  local result = DRC.bput("research status",
    "(%d+)%% complete with a portion",
    "not researching anything",
    "project about")
  if result:find("not researching anything") then return end

  for _, r in ipairs(research_types) do
    if result:lower():find(r:lower()) then
      research_topic = r
      break
    end
  end

  if result:find("complete with a portion") then
    local pct = tonumber(result:match("(%d+)%%"))
    if pct and pct >= 60 then
      local wait_time = (101 - pct) * 3
      Flags.reset("research_done")
      pause(wait_time)
    else
      respond("[theurgy] Stopping research to cast.")
      fput("RESEARCH CANCEL")
    end
  end
end

local function continue_research()
  if not research_topic then return end
  if Flags.get("research_done") then return end
  fput("RESEARCH " .. research_topic:upper() .. " 300")
end

-------------------------------------------------------------------------------
-- Prayer mat management
-------------------------------------------------------------------------------

--- Walk to a room ID, rolling up the prayer mat first if needed.
local function safe_walk_to(id)
  if mat_unrolled then
    DRCI.stow_hands()
    DRC.bput("roll " .. prayer_mat,
      "carefully gather up",
      "need to be holding that first", "not on the ground")
    DRCI.put_away_item(prayer_mat, prayer_mat_ctr)
    mat_unrolled = false
  end
  DRCT.walk_to(id)
end

--- Navigate to the altar or unroll the prayer mat in its room.
local function walk_to_altar_or_prayer_mat()
  if mat_unrolled then return end

  if prayer_mat then
    local room_id = nil
    if type(prayer_mat_room) == "table" and prayer_mat_room.id then
      room_id = prayer_mat_room.id
    elseif type(prayer_mat_room) == "number" then
      room_id = prayer_mat_room
    else
      respond("[theurgy] theurgy_prayer_mat_room must be a room ID number or {id: N} table.")
      return
    end
    DRCT.walk_to(room_id)
    DRCI.stow_hands()
    DRCI.get_item(prayer_mat, prayer_mat_ctr)
    DRC.bput("unroll " .. prayer_mat,
      "reverently lay your", "need to be holding that first")
    mat_unrolled = true
  elseif data.altar then
    DRCT.walk_to(data.altar.id)
  end
end

--- Roll up the prayer mat and put it away.
local function roll_prayer_mat()
  if not mat_unrolled then return end
  DRCI.stow_hands()
  DRC.bput("roll " .. prayer_mat,
    "carefully gather up",
    "need to be holding that first", "not on the ground")
  DRCI.put_away_item(prayer_mat, prayer_mat_ctr)
  mat_unrolled = false
end

-------------------------------------------------------------------------------
-- Town-specific purchase methods
-------------------------------------------------------------------------------

local function buy_taffelberries()
  DRC.bput("order 14",
    "puts some sugar-dipped taffelberries on the bar",
    "You don't have enough money to afford that")
  fput("get taffelberries")
end

local function buy_parchment()
  DRC.bput("read placard", "The placard reads")
  pause(1)
  DRC.bput("order 4 from monk",
    "You decide to purchase the parchment",
    "You realize you don't have enough")
  DRC.bput("unroll my parchment",
    "You reverently unroll",
    "I could not find", "What were you referring to")
end

local function buy_wine_shard()
  DRC.bput("order 10",
    "The publican places a flute",
    "You don't have enough money to afford that")
  DRC.bput("get wine on bar", "You get a flute", "What were you referring")
end

local function buy_oil_hib()
  DRC.bput("buy oil in chest",
    "You decide to purchase",
    "You realize you don't have enough")
end

local PURCHASE_METHODS = {
  buy_taffelberries = buy_taffelberries,
  buy_parchment     = buy_parchment,
  buy_wine_shard    = buy_wine_shard,
  buy_oil_hib       = buy_oil_hib,
}

--- Purchase a single supply item (one unit).
-- Handles custom purchase methods, shop navigation, and bless-on-purchase.
-- @param item_table table { name, stackable, ... }
-- @param shop table { id, price, method?, needs_bless?, parts? }
local function buy_single_supply(item_table, shop)
  if shop.method then
    local fn = PURCHASE_METHODS[shop.method]
    if fn then
      fn()
    else
      respond("[theurgy] Unknown purchase method: " .. shop.method)
      return
    end
  else
    DRCT.buy_item(shop.id, item_table.name)
  end

  -- Bless if the shop requires it and we know Bless
  if shop.needs_bless and DRSpells.known_p("Bless") then
    complete_or_interrupt_research()
    DRCA.cast_spell(
      { abbrev = "bless", mana = 1, prep_time = 2, cast = "cast my " .. item_table.name },
      settings)
    continue_research()
  end
end

--- Buy all needed supplies.
-- Walks to holy water source if needed, then visits shops in room-ID order.
local function buy_supplies()
  -- Gather items that need restocking
  local items_to_buy = {}
  for _, info in pairs(item_info) do
    if info.restock and info.shop then
      items_to_buy[#items_to_buy + 1] = info
    end
  end
  -- Sort by shop room ID so we walk efficiently
  table.sort(items_to_buy, function(a, b)
    return (a.shop.id or 0) < (b.shop.id or 0)
  end)

  -- Estimate total cost and ensure funds
  if #items_to_buy > 0 then
    local total_cost = 0
    for _, info in ipairs(items_to_buy) do
      total_cost = total_cost + (info.shop.price or 0)
    end
    DRCM.ensure_copper_on_hand(total_cost + 300, settings, hometown)
  end

  -- Fill holy water if needed
  if data.holy_water and water_holder then
    if not holy_water() then
      safe_walk_to(data.holy_water.id)
      DRCI.get_item(water_holder, supply_ctr)
      local tries = 0
      while tries < 10 do
        local r = DRC.bput(
          "fill " .. water_holder .. " with water from " .. data.holy_water.noun,
          "You fill", "There is no more room")
        if r:find("There is no more room") then break end
        tries = tries + 1
      end
      DRCI.put_away_item(water_holder, supply_ctr)
      DRCI.stow_hands()
    end
  end

  -- Buy each item
  for _, info in ipairs(items_to_buy) do
    local shop = info.shop

    -- Remove burnt incense before restocking (interferes with stacking)
    if info.name == "incense" then
      if DRCI.get_item("burnt incense", supply_ctr) then
        DRCI.dispose_trash("burnt incense")
        info.count = 0
      end
    end

    local num_to_buy = math.ceil((info.target - info.count) / info.parts)
    if num_to_buy <= 0 then num_to_buy = 1 end

    safe_walk_to(shop.id)

    if info.stackable then
      for _ = 1, num_to_buy do
        buy_single_supply(info, shop)
        DRCI.get_item(info.name, supply_ctr)
        DRC.bput("combine " .. info.name .. " with " .. info.name,
          "You combine", "You can't combine", "You must be holding")
        DRCI.put_away_item(info.name, supply_ctr)
      end
    else
      for _ = 1, (info.target - info.count) do
        buy_single_supply(info, shop)
        DRCI.put_away_item(info.name, supply_ctr)
      end
    end

    info.count = info.count + num_to_buy * info.parts
  end
end

-------------------------------------------------------------------------------
-- RITUALS
-------------------------------------------------------------------------------

local function tithe()
  DRC.wait_for_script_to_complete("tithe")
  return true
end

local function carve_bead()
  DRC.wait_for_script_to_complete("carve-bead")
  return true
end

local function study_wall()
  -- Skip if any cyclic spell is active (studying would interrupt it)
  local active = DRSpells.active_spells()
  for _, _ in pairs(active) do
    -- If we have ANY active spells, play it safe and skip
    -- (full cyclic check would require spells data file)
    break
  end

  safe_walk_to(5872)
  move("go stair")
  waitfor("Four beautifully detailed figures")
  safe_walk_to(5846)

  local pull_result = DRC.bput("pull candle",
    "You tug at the silver candlestick but it",
    "You grasp hold of the silver candlestick and pull it back")

  if pull_result:find("pull it back") then
    local study_result = DRC.bput("study wall",
      "Turning your attention to the sigils",
      "interrupt your research")
    if study_result:find("Turning your attention") then
      waitfor("as your understanding of the sigils gradually slips away.")
    else
      respond("[theurgy] Researching - skipping Study Wall.")
    end
    pause(1)
    move("go small hatch")
  end

  safe_walk_to(5756)
  move("go stair")
  waitfor("A low relief has been carefully carved")
  return true
end

local function refectory()
  safe_walk_to(5988)
  DRC.bput("meditate", "You bow your head and contemplate")
  waitrt()
  return true
end

--- Count beads on the prayer chain (must be holding it).
-- @return number
local function count_prayer_beads()
  local result = DRC.bput("look at my chain",
    "Strung on to the prayer bead chain you see",
    "There are currently no beads on it.")
  if result:find("no beads") then return 0 end
  local bead_list = result:match("prayer bead chain you see (.-)%.")
  if not bead_list then return 0 end
  local nouns = DRC.list_to_nouns(bead_list)
  return #nouns
end

--- Get the prayer chain from inventory/worn/container.
-- @return boolean true if chain is now in hand
local function get_prayer_chain()
  local result = DRC.bput("get prayer chain",
    "You get", "I could not find",
    "What were you referring to", "already in your inventory")
  if result:find("I could not find") or result:find("What were you") then
    return false
  end
  if result:find("already in your inventory") then
    fput("remove my prayer chain")
    worn_chain = true
  end
  return true
end

--- Return the prayer chain to its original location.
local function replace_prayer_chain()
  if worn_chain then
    DRC.bput("wear prayer chain",
      "You attach", "You are already wearing that", "Wear what?")
  else
    DRCI.put_away_item("prayer chain", supply_ctr)
  end
  worn_chain = false
end

local function meditate_bead()
  if not get_prayer_chain() then return false end

  if count_prayer_beads() == 0 then
    replace_prayer_chain()
    return false
  end

  safe_walk_to(data.altar.id)
  fput("kneel")
  DRC.bput("meditate my prayer chain", "You clutch")
  waitfor("suddenly detaches from your prayer bead chain")
  DRC.fix_standing()
  replace_prayer_chain()
  waitrt()
  return true
end

local function sirese_seed()
  if not holy_water() then return false end

  safe_walk_to(data.gather_sirese.id)

  -- Invasion check
  local npcs = DRRoom.npcs()
  local ignored = settings.ignored_npcs or {}
  for _, npc in ipairs(npcs) do
    if not includes(ignored, npc) then
      respond("[theurgy] NPCs present, skipping sirese seed (invasion check).")
      return false
    end
  end

  -- Gather a seed
  local gathered = false
  for _ = 1, 20 do
    local result = DRC.bput("gather seed",
      "You find a tiny",
      "This is not a good",
      "You come up empty")
    waitrt()
    if result:find("You find a tiny") then
      gathered = true
      break
    end
  end
  if not gathered then return false end

  safe_walk_to(data.plant_sirese.id)
  DRC.bput("plant seed", "You carefully dig a hole")
  DRCI.get_item(water_holder, supply_ctr)
  DRC.bput("sprinkle " .. water_holder .. " on room", "You sprinkle some holy water")
  DRCI.put_away_item(water_holder, supply_ctr)
  return true
end

local function bathe()
  safe_walk_to(data.bath.id)
  for _, dir in ipairs(data.bath.path_in or {}) do
    move(dir)
  end
  local herbs = data.herbs or { "sage", "lavender" }
  for _, herb in ipairs(herbs) do
    DRCI.get_item(herb, supply_ctr)
    fput("rub my " .. herb)
    pause(1)
  end
  waitfor("You wake up once more, blinking dazedly.")
  DRC.fix_standing()
  for _, dir in ipairs(data.bath.path_out or {}) do
    move(dir)
  end
  return true
end

local function pray_badge()
  local result = DRC.bput("remove pilgrim badge",
    "You take off", "Remove what")
  if result:find("You take off") then
    fput("pray pilgrim badge")
    pause(2)
    waitrt()
    DRC.bput("wear pilgrim badge",
      "You put on a", "You are already")
  else
    -- Badge may be in bag, not worn
    local get_result = DRC.bput("get badge",
      "You get", "I could not find", "What were you referring to")
    if get_result:find("I could not find") or get_result:find("What were you") then
      return false
    end
    fput("pray pilgrim badge")
    pause(2)
    waitrt()
    DRCI.put_away_item("pilgrim badge", supply_ctr)
  end
  return true
end

local function dance()
  walk_to_altar_or_prayer_mat()
  local end_conds = {
    "flawless performance to those on high",
    "In your condition",
    "Your dance reaches its conclusion",
  }
  local all_pats = {
    "flawless performance to those on high",
    "In your condition",
    "Your dance reaches its conclusion",
    "You begin to dance",
    "Your actions grow",
    "Your dance",
    "but you falt",
  }
  local dance_target = prayer_mat or "altar"
  local done = false
  while not done do
    local result = DRC.bput("dance " .. dance_target, table.unpack(all_pats))
    for _, ec in ipairs(end_conds) do
      if result:find(ec) then done = true; break end
    end
    if not done then
      pause(1)
      waitrt()
      DRC.fix_standing()
    end
  end
  return true
end

local function incense()
  walk_to_altar_or_prayer_mat()
  DRC.bput("get " .. flint_lighter,
    "You get", "I could not find", "What were you referring to")

  -- Use burnt incense first if available (prevents stack interference)
  if DRCI.inside("burnt incense", supply_ctr) then
    DRCI.get_item("burnt incense", supply_ctr)
  else
    DRCI.get_item("incense", supply_ctr)
  end

  -- Get flint if it's not available (may be in a container/eddy)
  local flint_dropped = false
  if not DRCI.exists("flint") then
    DRC.bput("lower my incense to ground", "You")
    DRCI.get_item("flint", supply_ctr)
    flint_dropped = true
  end

  -- Light incense (retry until lit)
  for _ = 1, 10 do
    local result = DRC.bput("light my incense with flint",
      "nothing happens", "bursts into flames",
      "much too dark in here to do that")
    waitrt()
    if result:find("bursts into flames") then break end
  end

  -- Return flint to container if we retrieved it manually
  if flint_dropped then
    DRCI.put_away_item("flint", supply_ctr)
    DRC.bput("get my incense", "You get", "What were")
  end

  local altar_target = prayer_mat or "altar"
  fput("wave incense at " .. altar_target)
  fput("snuff incense")
  DRCI.put_away_item("incense", supply_ctr)
  DRCI.stow_hands()
  pause(1)
  return true
end

local function wine()
  walk_to_altar_or_prayer_mat()
  if not DRCI.get_item("wine", supply_ctr) then return false end

  if prayer_mat then
    DRC.fix_standing()
    DRC.bput("kneel " .. prayer_mat, "You humbly kneel")
  end

  complete_or_interrupt_research()
  DRCA.cast_spell(
    { abbrev = "bless", mana = 1, prep_time = 2, cast = "cast my wine" },
    settings)
  continue_research()

  DRC.bput("pour wine on " .. (prayer_mat or "altar"),
    "You quietly pour", "Pour what")
  DRC.fix_standing()
  DRCI.put_away_item("wine", supply_ctr)
  return true
end

local function recite_prayer()
  safe_walk_to(data.altar.id)
  local char_name = GameState.name or "faithful"
  fput("recite Meraud, power the holy fires that unleash my righteous vengeance;"
    .. "Chadatru, guide my sword to swing in justice;"
    .. "Everild, give me the power to conquer my enemies;"
    .. "Truffenyi, let me not lose sight of compassion and mercy;"
    .. "Else, I will become like those I despise;"
    .. "Urrem'tier, receive into your fetid grasp these wicked souls;"
    .. "May the Tamsine's realms never know their evil ways again;"
    .. "May all the Immortals guide your faithful soldier " .. char_name .. ".")
  pause(1)
  waitrt()
  return true
end

local function clean_altar()
  if not holy_water() then return false end
  safe_walk_to(data.altar.id)
  DRCI.get_item(water_holder, supply_ctr)
  DRC.bput("clean altar with holy water", "Roundtime")
  waitfor("You finish your job")
  DRCI.put_away_item(water_holder, supply_ctr)
  waitrt()
  return true
end

local function kiss_altar()
  walk_to_altar_or_prayer_mat()
  if prayer_mat then
    DRC.fix_standing()
    DRC.bput("kneel " .. prayer_mat, "You humbly kneel")
  else
    DRC.bput("kneel", "You kneel down", "Subservient type")
  end
  DRC.bput("kiss " .. (prayer_mat or "altar"), "You bend forward to kiss")
  DRC.fix_standing()
  return true
end

local function clean_anloral()
  local aspect = last_favor_aspect()
  if not aspect then return false end

  local description = aspect .. " pin"
  local dirty_msgs = {
    "A thin layer of dust",
    "streaks of clumped dust",
    "thickly caked grime",
  }
  local result = DRC.bput("look my " .. description,
    "It is clean", "I could not find", table.unpack(dirty_msgs))

  local is_dirty = false
  for _, msg in ipairs(dirty_msgs) do
    if result:find(msg) then is_dirty = true; break end
  end
  if not is_dirty then return false end
  if not holy_water() then return false end

  DRCI.get_item(water_holder, supply_ctr)
  DRC.bput("clean " .. description .. " with holy water",
    "You pour some holy water",
    "You need to be holding",
    "The immaculate anloral",
    "That doesn't appear")
  waitrt()
  DRCI.put_away_item(water_holder, supply_ctr)
  return true
end

local function embarass_myself()
  if not DRCI.inside("parchment", supply_ctr) then return false end
  safe_walk_to(safe_room)
  DRCI.get_item("golden parchment", supply_ctr)
  fput("invoke my parchment")
  waitfor("You conclude")
  DRCI.put_away_item("golden parchment", supply_ctr)
  return true
end

-------------------------------------------------------------------------------
-- COMMUNES
-------------------------------------------------------------------------------

--- Check if we can initiate any commune right now (global cooldown).
-- Returns true if no global commune flag is set, or if "fully prepared" message
-- has been received since the last commune.
local function can_commune()
  if #communes == 0 then return false end
  local match = Flags.get("theurgy-commune")
  if not match then return true end   -- no commune attempted yet
  return match:find("fully prepared to seek assistance from the Immortals once again") ~= nil
end

--- Check if a specific commune (by flag name suffix) is off its individual cooldown.
-- @param flag_key string e.g. "eluned", "tamsine"
local function commune_ready(flag_key)
  return not Flags.get("theurgy-" .. flag_key)
end

local function commune_eluned()
  safe_walk_to(data.dirt_foraging.id)
  if not DRC.forage("dirt", 5) then return false end
  DRCI.get_item(water_holder, supply_ctr)
  local result = DRC.bput("commune eluned",
    "completed this commune too recently",
    "You struggle to commune",
    "you have attempted a commune too recently in the past",
    "You grind some dirt in your fist")
  DRCI.put_away_item(water_holder, supply_ctr)
  -- Drop leftover dirt if in hand
  local lh = DRC.left_hand()
  local rh = DRC.right_hand()
  if (lh and lh:find("dirt")) or (rh and rh:find("dirt")) then
    DRC.bput("drop dirt",
      "You drop some", "But you aren't holding", "What were you referring")
  end
  return result:find("You grind some dirt in your fist") ~= nil
end

local function commune_tamsine()
  if not holy_water() then return false end
  pause(1)
  waitrt()
  DRCI.get_item(water_holder, supply_ctr)
  local char_name = GameState.name or "yourself"
  DRC.bput("sprinkle " .. water_holder .. " on " .. char_name,
    "You sprinkle yourself", "Sprinkle what?")
  local result = DRC.bput("commune tamsine",
    "completed this commune too recently",
    "You struggle to commune",
    "you have attempted a commune too recently in the past",
    "You feel warmth spread throughout your body")
  DRCI.put_away_item(water_holder, supply_ctr)
  return result:find("You feel warmth spread throughout your body") ~= nil
end

local function commune_truffenyi()
  DRCI.stow_hands()
  local offered_item = nil

  if DRCI.inside("taffelberries", supply_ctr) then
    offered_item = "taffelberries"
    DRCI.get_item("taffelberries", supply_ctr)
  elseif DRSpells.known_p("Glythtide's Gift") then
    complete_or_interrupt_research()
    Flags.add("theurgy-gg-drink",
      "hearty chuckle as .* appears in your .* hand!",
      "Both your hands are full!")
    DRCA.cast_spell(
      { abbrev = "gg", mana = 5, prep_time = 2, cast = "cast drink" },
      settings)
    local gg_match = Flags["theurgy-gg-drink"]
    Flags.delete("theurgy-gg-drink")
    if gg_match and not gg_match:find("Both your hands") then
      offered_item = gg_match:match("hearty chuckle as (%a+) appears in your")
    end
    if not offered_item then
      continue_research()
      return false
    end
    continue_research()
  else
    return false
  end

  DRC.bput("commune truffenyi",
    "completed this commune too recently",
    "You struggle to commune",
    "you have attempted a commune too recently in the past",
    "The power of Truffenyi has answered your prayer")
  pause(1)

  local rh = DRC.right_hand()
  if rh and rh:find("orb") then
    fput("drop orb")
    return true
  elseif offered_item == "taffelberries" then
    fput("get taffelberries")
    DRCI.put_away_item("taffelberries", supply_ctr)
  elseif offered_item then
    DRC.bput("drop " .. offered_item,
      "You drop", "What were you referring", "But you aren't holding")
  end
  return false
end

local function commune_kertigen()
  if DRCI.inside("holy oil", supply_ctr) then
    DRCI.get_item("holy oil", supply_ctr)
  elseif DRSpells.known_p("Bless") then
    DRCI.get_item("some oil", supply_ctr)
    complete_or_interrupt_research()
    DRCA.cast_spell(
      { abbrev = "bless", mana = 1, prep_time = 2, cast = "cast oil" },
      settings)
    continue_research()
  else
    return false
  end

  local rh = DRC.right_hand()
  if rh and rh:find("holy oil") then
    local char_name = GameState.name or "yourself"
    DRC.bput("sprinkle oil on " .. char_name,
      "You sprinkle yourself", "Sprinkle what?")
    DRCI.put_away_item("oil", supply_ctr)
    local result = DRC.bput("commune kertigen",
      "You struggle to commune",
      "completed this commune too recently",
      "you have attempted a commune too recently in the past",
      "The thick smell of ozone fills your nostrils")
    return result:find("ozone") ~= nil
  else
    DRCI.stow_hands()
    return false
  end
end

local COMMUNE_DISPATCH = {
  eluned   = commune_eluned,
  tamsine  = commune_tamsine,
  truffenyi= commune_truffenyi,
  kertigen = commune_kertigen,
}

--- Perform the next available commune (rotates through commune list).
-- @return boolean true if a commune was performed
local function perform_next_commune()
  for i = 1, #communes do
    if not can_commune() then return false end

    local commune = communes[i]
    -- Rotate so next call tries a different one first
    table.remove(communes, i)
    communes[#communes + 1] = commune

    if commune_ready(commune.flag_key) then
      DRCI.stow_hands()
      -- Re-check items (may have been consumed)
      local ok = true
      for _, item in ipairs(commune.items or {}) do
        if count(item) == 0 then ok = false; break end
      end
      if ok then
        local fn = COMMUNE_DISPATCH[commune.flag_key]
        if fn and fn() then return true end
      end
    end
  end
  return false
end

-------------------------------------------------------------------------------
-- RITUAL dispatch
-------------------------------------------------------------------------------

local RITUAL_DISPATCH = {
  tithe           = tithe,
  carve_bead      = carve_bead,
  study_wall      = study_wall,
  refectory       = refectory,
  meditate_bead   = meditate_bead,
  sirese_seed     = sirese_seed,
  bathe           = bathe,
  pray_badge      = pray_badge,
  dance           = dance,
  incense         = incense,
  wine            = wine,
  recite_prayer   = recite_prayer,
  clean_altar     = clean_altar,
  kiss_altar      = kiss_altar,
  clean_anloral   = clean_anloral,
  embarass_myself = embarass_myself,
}

--- Perform and remove the next ritual from the queue.
local function perform_next_ritual()
  if #rituals == 0 then return end
  local ritual = table.remove(rituals, 1)
  local fn = RITUAL_DISPATCH[ritual.method]
  if fn then
    fn()
  else
    respond("[theurgy] Unknown ritual method: " .. tostring(ritual.method))
  end
end

--- Attempt a commune first; fall through to a ritual.
local function perform_next_action()
  if not perform_next_commune() then
    perform_next_ritual()
  end
end

--- Check if any rituals remain.
-- @return boolean
local function rituals_remain()
  return #rituals > 0
end

--- Check if we should continue (exp threshold).
-- @return boolean
local function should_continue()
  if theurgy_exp_threshold > 0 then
    return DRSkill.getxp("Theurgy") < theurgy_exp_threshold
  end
  return true
end

-------------------------------------------------------------------------------
-- Build ritual and commune lists
-------------------------------------------------------------------------------

--- Build the full list of all possible rituals in order.
-- @return table Array of ritual action tables { method, items? }
local function all_rituals()
  local r = {}

  -- Tithe (Crossing only, if configured)
  if settings.tithe and data.almsbox and data.almsbox.id then
    r[#r + 1] = { method = "tithe" }
  end

  -- Crossing-specific
  if hometown == "Crossing" then
    if DRStats.circle >= 30 then
      r[#r + 1] = { method = "study_wall" }
    end
    r[#r + 1] = { method = "refectory" }
  end

  -- Carve bead (Engineering 140+, has immortal_aspect, knows Bless)
  if DRSkill.getrank("Engineering") > 140
      and immortal_aspect
      and DRSpells.known_p("Bless") then
    r[#r + 1] = { method = "carve_bead" }
  end

  -- Sirese seed (if town supports it)
  if data.gather_sirese and data.plant_sirese then
    r[#r + 1] = { method = "sirese_seed" }
  end

  -- Bathe (if town has a bath)
  if data.bath then
    local herbs = data.herbs or { "sage", "lavender" }
    local herb_items = {}
    for _, h in ipairs(herbs) do
      herb_items[#herb_items + 1] = { name = h, shop = data.herb_shop }
    end
    r[#r + 1] = { method = "bathe", items = herb_items }
  end

  -- Pray badge (always)
  r[#r + 1] = { method = "pray_badge" }

  -- Altar-based rituals (altar present OR using prayer mat)
  if data.altar or prayer_mat then
    -- Bead meditation (altar required, immortal_aspect configured)
    if data.altar and immortal_aspect then
      r[#r + 1] = {
        method = "meditate_bead",
        items = { { name = "prayer chain", any_container = true } },
      }
    end

    -- Clean altar (altar required, no prayer mat)
    if data.altar and not prayer_mat then
      r[#r + 1] = { method = "clean_altar" }
    end

    -- Recite prayer (altar required, no prayer mat)
    if data.altar and not prayer_mat then
      r[#r + 1] = { method = "recite_prayer" }
    end

    -- Kiss altar
    r[#r + 1] = { method = "kiss_altar" }

    -- Dance (circle 10+)
    if DRStats.circle >= 10 then
      r[#r + 1] = { method = "dance" }
    end

    -- Incense
    r[#r + 1] = {
      method = "incense",
      items = {
        { name = "incense", shop = data.incense_shop, stackable = true, parts = 10 },
        { name = "flint",   shop = data.flint_shop },
      },
    }

    -- Wine (bless required, cleric spell)
    if DRSpells.known_p("Bless") then
      r[#r + 1] = {
        method = "wine",
        items = {
          { name = "wine", shop = data.wine_shop },
        },
      }
    end
  end

  -- Clean anloral (aspect pin from favor god)
  r[#r + 1] = { method = "clean_anloral" }

  -- Embarass myself (parchment invocation)
  r[#r + 1] = {
    method = "embarass_myself",
    items = { { name = "golden parchment", shop = data.parchment_shop } },
  }

  return r
end

--- Build the ritual list filtered by blacklist/whitelist settings.
-- Also removes rituals where a required item is unavailable (no shop, not in hand).
local function get_rituals()
  local all = all_rituals()
  local blacklist = settings.theurgy_blacklist or {}
  local whitelist = settings.theurgy_whitelist or {}

  -- Filter blacklist
  local filtered = {}
  for _, r in ipairs(all) do
    if not includes(blacklist, r.method) then
      filtered[#filtered + 1] = r
    end
  end

  -- Apply whitelist
  if #whitelist > 0 then
    local wl_filtered = {}
    for _, r in ipairs(filtered) do
      if includes(whitelist, r.method) then
        wl_filtered[#wl_filtered + 1] = r
      end
    end
    filtered = wl_filtered
  end

  -- Remove rituals with unobtainable items (no shop, not on hand)
  local final = {}
  for _, r in ipairs(filtered) do
    local ok = true
    for _, item in ipairs(r.items or {}) do
      local info = item_info[item.name]
      if info and not info.on_hand and not info.shop then
        ok = false
        respond("[theurgy] Skipping ritual '" .. r.method
          .. "': missing item '" .. item.name .. "' with no shop.")
        break
      end
    end
    if ok then final[#final + 1] = r end
  end

  return final
end

--- Build the commune list based on settings.communes and circle requirements.
local function get_communes()
  local c = {}

  -- Eluned: circle > 3, Outdoorsmanship > 20, town has dirt foraging
  if DRStats.circle > 3
      and DRSkill.getrank("Outdoorsmanship") > 20
      and data.dirt_foraging
      and includes(chosen_communes, "Eluned") then
    c[#c + 1] = {
      name     = "eluned",
      flag_key = "eluned",
      items    = {},
    }
  end

  -- Truffenyi: circle > 60
  if DRStats.circle > 60 and includes(chosen_communes, "Truffenyi") then
    local items = {}
    if not DRSpells.known_p("Glythtide's Gift") then
      items[#items + 1] = { name = "taffelberries", shop = data.taffelberry_shop }
    end
    c[#c + 1] = {
      name     = "truffenyi",
      flag_key = "truffenyi",
      items    = items,
    }
  end

  -- Tamsine: circle > 2
  if DRStats.circle > 2 and includes(chosen_communes, "Tamsine") then
    c[#c + 1] = {
      name     = "tamsine",
      flag_key = "tamsine",
      items    = {},
    }
  end

  -- Kertigen: circle > 8, needs oil
  if DRStats.circle > 8 and includes(chosen_communes, "Kertigen") then
    c[#c + 1] = {
      name     = "kertigen",
      flag_key = "kertigen",
      items    = {
        { name = "oil", shop = data.oil_shop, stackable = true, parts = 5 },
      },
    }
  end

  -- Remove communes with unobtainable items
  local final = {}
  for _, commune in ipairs(c) do
    local ok = true
    for _, item in ipairs(commune.items or {}) do
      local info = item_info[item.name]
      if info and not info.on_hand and not info.shop then
        ok = false
        respond("[theurgy] Skipping commune '" .. commune.name
          .. "': missing item '" .. item.name .. "' with no shop.")
        break
      end
    end
    if ok then final[#final + 1] = commune end
  end

  return final
end

-------------------------------------------------------------------------------
-- Main prayer
-------------------------------------------------------------------------------

local function pray()
  waitrt()
  local god = favor_god or "meraud"
  DRC.bput("pray " .. god,
    god, "Lady of healing", "reward of hard effort", "sign with your hand",
    "god of the Void", "bane of accursed", "blessing be upon your love",
    "honorable and true", "glory shine on us", "fire across the lands",
    "madness and pain", "floods strike down",
    "Lady of supreme beauty", "Meraud", "meraud")
  waitrt()
end

-------------------------------------------------------------------------------
-- Main execution
-------------------------------------------------------------------------------

respond("[theurgy] Starting theurgy routine for " .. hometown)

-- Build item_info: count existing supplies (includes both ritual and commune items)
local all_items_for_info = {}
-- We'll build the full lists first without filtering (to know what to count)
-- Use combined all_rituals + get_communes items
local temp_rituals = all_rituals()
local temp_communes = {}  -- Build minimal commune info for item counting
if DRStats.circle > 3 and DRSkill.getrank("Outdoorsmanship") > 20
    and data.dirt_foraging and includes(chosen_communes, "Eluned") then
  temp_communes[#temp_communes + 1] = { items = {} }
end
if DRStats.circle > 60 and includes(chosen_communes, "Truffenyi") then
  local items = {}
  if not DRSpells.known_p("Glythtide's Gift") then
    items[1] = { name = "taffelberries", shop = data.taffelberry_shop }
  end
  temp_communes[#temp_communes + 1] = { items = items }
end
if DRStats.circle > 2 and includes(chosen_communes, "Tamsine") then
  temp_communes[#temp_communes + 1] = { items = {} }
end
if DRStats.circle > 8 and includes(chosen_communes, "Kertigen") then
  temp_communes[#temp_communes + 1] = {
    items = { { name = "oil", shop = data.oil_shop, stackable = true, parts = 5 } }
  }
end

collect_item_info(temp_rituals)
for _, c in ipairs(temp_communes) do
  for _, item in ipairs(c.items or {}) do
    if not item_info[item.name] then
      local cnt = count(item)
      local levels = (settings.theurgy_supply_levels or {})[item.name] or {}
      item_info[item.name] = {
        name      = item.name,
        shop      = item.shop,
        stackable = item.stackable or false,
        parts     = (item.shop and item.shop.parts) or item.parts or 1,
        count     = cnt,
        on_hand   = cnt > 0,
        restock   = cnt < (levels.min or 1),
        target    = levels.target or 1,
      }
    end
  end
end

-- Now build final ritual/commune lists (item_info populated)
rituals = get_rituals()
communes = get_communes()

respond("[theurgy] Rituals: " .. #rituals
  .. ", Communes: " .. #communes)

-- Pray, buy supplies, run rituals and communes, then issue commune
pray()
buy_supplies()

while rituals_remain() and should_continue() do
  perform_next_action()
end

roll_prayer_mat()
fput("commune")

respond("[theurgy] Theurgy routine complete.")
