--- @revenant-script
--- name: restock
--- version: 1.0.0
--- game: dr
--- author: elanthia-online
--- original-authors: elanthia-online (dr-scripts community)
--- description: Restocks consumable items from shops based on user settings configuration
--- tags: restock, shop, consumables, money
---
--- Ported from restock.lic (dr-scripts, Lich5) to Revenant Lua.
--- Original: https://github.com/elanthia-online/dr-scripts
---
--- @changelog
---   1.0.0 (2026-03-19) — Initial Revenant port
---
--- Compares current inventory counts against configured target quantities,
--- determines what needs restocking, withdraws sufficient coin including
--- Shard night-bribe padding, then purchases and stows each item.
---
--- @required-settings:
---   restock                  {key: config}  item key → restock config mapping
---   hometown                 string         character's home town
---   sell_loot_money_on_hand  string         coin to keep after depositing (e.g. "3 silver")
---   storage_containers       string[]       containers to open before counting
---
--- @optional-settings:
---   fang_cove_override_town  string  override hometown for Fang Cove characters
---   runestone_storage        string  container for runestone storage
---
--- @optional-per-item-fields:
---   min_quantity    integer  only restock when count drops below this threshold
---   countable_name  string   alternate noun for counting (when buy name differs)
---   clerk           string   NPC name; triggers "ask <clerk> for <item>" instead of buy
---   container       string   specific container to stow into
---   hometown        string   buy from this town instead of your hometown
---
--- @usage:
---   ;restock
---   ;restock debug
---
--- @example-settings (data/dr/profiles/yourchar-setup.json):
---   {
---     "hometown": "Crossing",
---     "sell_loot_money_on_hand": "3 silver",
---     "storage_containers": ["backpack"],
---     "restock": {
---       "arrow": { "quantity": 30 },
---       "bolt":  { "quantity": 20, "min_quantity": 5 }
---     }
---   }
---
--- @example-fully-custom-item (all fields required when not in base-consumables):
---   "restock": {
---     "lockpick": {
---       "name": "lockpick", "size": 1, "room": 1234, "price": 625,
---       "stackable": false, "quantity": 10,
---       "container": "lockpick ring", "countable_name": "pick"
---     }
---   }

-- ---------------------------------------------------------------------------
-- Parse args
-- ---------------------------------------------------------------------------

local debug_mode = false
for i = 1, #Script.vars do
  if Script.vars[i] and Script.vars[i]:lower() == "debug" then
    debug_mode = true
    break
  end
end

-- ---------------------------------------------------------------------------
-- Load settings and data
-- ---------------------------------------------------------------------------

local settings = get_settings()
local restock_config = settings.restock

if not restock_config or next(restock_config) == nil then
  respond("[restock] No 'restock' key in settings. Nothing to do.")
  return
end

local hometown = settings.fang_cove_override_town or settings.hometown
if not hometown then
  respond("[restock] Settings missing 'hometown'. Aborting.")
  return
end

local runestone_storage = settings.runestone_storage

-- Parse keep-copper from "3 silver" style string
local keep_copper = 0
if settings.sell_loot_money_on_hand then
  local amount_str, denom = settings.sell_loot_money_on_hand:match("^(%S+)%s+(.+)$")
  if amount_str and denom then
    keep_copper = DRCM.convert_to_copper(tonumber(amount_str) or 0, denom)
  end
end

-- Open storage containers so inventory counts are accurate
if settings.storage_containers then
  for _, container in ipairs(settings.storage_containers) do
    DRCI.open_container("my " .. container)
  end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Validate that a custom item hash has all required fields.
-- @param item table  Item configuration to check
-- @return boolean
local function valid_item_data(item)
  if debug_mode then echo("[restock] Validating item data: " .. Json.encode(item)) end
  for _, field in ipairs({"name", "size", "room", "price", "stackable", "quantity"}) do
    if item[field] == nil then return false end
  end
  return true
end

--- Count stackable items (quivers of arrows, packs of bolts, etc.)
-- Iterates ordinals (first, second, ...) until the item is not found.
-- Handles empty containers by trashing them and re-checking the same ordinal.
-- @param item table  Item config (must have .name)
-- @return integer  Total count across all stacks
local function count_stackable_item(item)
  if debug_mode then echo("[restock] Counting stackable: " .. item.name) end

  local count = 0
  local i = 1

  while i <= #ORDINALS do
    local ordinal = ORDINALS[i]

    local count_msg = DRC.bput(
      "count my " .. ordinal .. " " .. item.name,
      "I could not find what you were referring to",
      "tell you much of anything",
      "and see there %a+ .+ left",
      "has about %d+ uses of .* remaining%.  It is labeled",
      "has about one use of .* remaining%.  It is labeled",
      "is empty%.$"
    )

    if count_msg:find("I could not find") then
      break
    elseif count_msg:find("tell you much of anything") then
      echo("[restock] " .. item.name .. " is marked stackable but is not — counting as non-stackable")
      -- Inline non-stackable count rather than mutual recursion
      local container = item.container
      if not container then
        local tap_line = DRC.bput("tap my " .. item.name, "inside your ", "I could not find")
        container = tap_line:match("inside your (.-)%.")
      end
      if container then
        local count_name = item.countable_name or item.name
        count = count + DRCI.count_items_in_container(count_name, container)
      end
      break
    elseif count_msg:find("has about one use of") then
      count = count + 1
      waitrt()
      i = i + 1
    elseif count_msg:find("has about") then
      local n = tonumber(count_msg:match("has about (%d+) uses of"))
      if n then count = count + n end
      waitrt()
      i = i + 1
    elseif count_msg:find("is empty") then
      echo("[restock] " .. ordinal .. " " .. item.name .. " is empty — trashing")
      DRC.bput("drop my " .. ordinal .. " " .. item.name,
        "You drop", "You spread", "What were you referring to")
      -- Redo same ordinal (don't increment i)
    else
      -- "and see there <word> <count> left"
      local count_txt = count_msg:match("and see there %a+ (.+) left")
      if count_txt then
        count_txt = count_txt:gsub("%-", " ")
        count = count + (DRC.text2num(count_txt) or 0)
      end
      waitrt()
      i = i + 1
    end
  end

  return count
end

--- Count non-stackable items in a container.
-- Discovers the container via "tap" if not specified in item config.
-- @param item table  Item config (must have .name; optional .container, .countable_name)
-- @return integer  Number of matching items found
local function count_nonstackable_item(item)
  if debug_mode then echo("[restock] Counting non-stackable: " .. item.name) end

  local container = item.container

  if not container then
    -- Discover which container the item is in via TAP
    local tap_line = DRC.bput("tap my " .. item.name,
      "inside your ", "I could not find")
    container = tap_line:match("inside your (.-)%.")
    if not container then
      return 0
    end
  end

  local count_name = item.countable_name or item.name
  return DRCI.count_items_in_container(count_name, container)
end

--- Parse the full restockable item list, merging user config with base-consumables.
-- User-specified fields take precedence over base-consumables defaults.
-- Items with a custom 'hometown' are returned as-is (fully specified).
-- @return table  Array of fully-populated item config tables
local function parse_restockable_items()
  local all_consumables = get_data("consumables")
  local hometown_data   = all_consumables[hometown] or {}
  local items = {}

  for key, value in pairs(restock_config) do
    if debug_mode then
      echo("[restock] Parsing item: " .. key .. " => " .. Json.encode(value))
    end

    -- Deep-copy value so we don't mutate the settings table
    local item = {}
    for k, v in pairs(value) do item[k] = v end

    if hometown_data[key] and not item.hometown then
      -- Known base-consumables item: fill in missing fields from base data
      local base = hometown_data[key]
      for k, v in pairs(base) do
        if item[k] == nil then item[k] = v end
      end
      items[#items + 1] = item
    elseif valid_item_data(item) then
      -- Fully custom item — user specified all required fields
      items[#items + 1] = item
    else
      echo("[restock] No base-consumables or explicit data for '" .. key ..
        "' in " .. hometown .. " — skipping")
    end
  end

  if debug_mode then echo("[restock] Parsed items: " .. Json.encode(items)) end
  return items
end

--- Purchase a single item.
-- Uses ask-for flow when a clerk is specified; otherwise standard buy.
-- @param item table  Item config with .room, .name; optional .clerk
local function purchase_item(item)
  if item.clerk then
    DRCT.walk_to(item.room)
    fput("ask " .. item.clerk .. " for " .. item.name)
  else
    DRCT.buy_item(item.room, item.name)
  end
end

--- Pick up item from counter when too encumbered to receive it in-hand.
-- Checks the last 3 game lines for the encumbrance message.
-- @param item table  Item config with .name
local function handle_encumbrance(item)
  local recent = reget(3) or {}
  for _, line in ipairs(recent) do
    if line:find("Seeing that you are too encumbered") then
      DRC.bput("get " .. item.name .. " from counter", "You get a")
      break
    end
  end
end

--- Stow a purchased item.
-- Priority: item.container > runestone_storage (for runestones) > default stow
-- @param item table  Item config with .name; optional .container
local function stow_item(item)
  if item.container then
    DRCI.put_away_item(item.name, item.container)
  elseif item.name:lower():find("runestone") and runestone_storage then
    DRCI.put_away_item(item.name, runestone_storage)
  else
    DRCI.stow_hands()
  end
end

--- Restock all items for a single town.
-- Counts inventory, determines need, withdraws coin, purchases, and stows.
-- @param item_list  table   Items to potentially restock
-- @param town       string  Town name to restock in
local function restock_items(item_list, town)
  local items_to_restock = {}
  local coin_needed = 0

  for _, item in ipairs(item_list) do
    local remaining
    if item.stackable then
      remaining = count_stackable_item(item)
    else
      remaining = count_nonstackable_item(item)
    end

    -- Skip if above min_quantity threshold
    if item.min_quantity and remaining >= item.min_quantity then
      goto continue
    end

    -- Skip if already at target quantity
    if remaining >= item.quantity then
      goto continue
    end

    local num_needed = item.quantity - remaining
    local buy_num = math.ceil(num_needed / item.size)
    coin_needed = coin_needed + (buy_num * item.price)
    item._buy_num = buy_num
    items_to_restock[#items_to_restock + 1] = item

    ::continue::
  end

  if #items_to_restock == 0 then return end

  DRCI.stow_hands()

  if coin_needed > 0 then
    -- Pad for Shard night-bribe (2502 copper per shop visit).
    -- Over-estimates intentionally; excess deposited at the end.
    coin_needed = coin_needed + 2502 * #items_to_restock
    if debug_mode then echo("[restock] Coin needed: " .. coin_needed) end
    DRCM.ensure_copper_on_hand(coin_needed, settings, town)
  end

  for _, item in ipairs(items_to_restock) do
    for _ = 1, item._buy_num do
      purchase_item(item)
      handle_encumbrance(item)
      stow_item(item)
    end
  end

  DRCM.deposit_coins(keep_copper, settings, town)
end

-- ---------------------------------------------------------------------------
-- Main: orchestrate restock across hometowns
-- ---------------------------------------------------------------------------

local all_items = parse_restockable_items()

-- Separate items with a custom hometown from the default group
local default_items    = {}
local custom_loc_items = {}
for _, item in ipairs(all_items) do
  if item.hometown then
    custom_loc_items[#custom_loc_items + 1] = item
  else
    default_items[#default_items + 1] = item
  end
end

-- Restock default-hometown items
restock_items(default_items, settings.hometown)

-- Restock custom-hometown items, grouped by town
local by_town = {}
for _, item in ipairs(custom_loc_items) do
  local t = item.hometown
  if not by_town[t] then by_town[t] = {} end
  by_town[t][#by_town[t] + 1] = item
end
for town, group in pairs(by_town) do
  restock_items(group, town)
end

respond("[restock] Done.")
