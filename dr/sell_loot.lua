--- @revenant-script
--- name: sell_loot
--- version: 1.0.0
--- author: rpherbig
--- original-authors: rpherbig, dr-scripts community contributors
--- game: dr
--- description: Sell gems, metals/stones, bundles, and trap components; exchange and deposit coins. Full port of sell-loot.lic.
--- tags: loot, sell, gems, bundle, trap, coins, deposit, exchange
--- source: https://github.com/rpherbig/dr-scripts
--- @lic-certified: complete 2026-03-19
---
--- Full port of sell-loot.lic (Lich5) to Revenant Lua.
---
--- USAGE:
---   ;sell_loot                         — sell to hometown, deposit coins
---   ;sell_loot --town=crossing         — override sell/deposit town
---   ;sell_loot --amount=3 --type=silver — keep 3 silver on hand after deposit
---   ;sell_loot --town=shard --amount=5 --type=gold
---
--- SETTINGS (in your character profile JSON):
---   hometown                    — default town for all operations
---   sell_loot_town              — override town specifically for sell_loot
---   sell_loot_skip_bank         — true = skip the bank/exchange step
---   sell_loot_skip_exchange     — true = exchange currencies but skip bank deposit
---   sell_loot_money_on_hand     — default keep amount, e.g. "3 silver"
---   sell_loot_pouch             — true = sell gems from gem pouch
---   gem_pouch_adjective         — adjective of gem pouch (e.g. "velvet")
---   gem_pouch_noun              — noun of gem pouch (e.g. "pouch")
---   spare_gem_pouch_container   — container holding a spare gem pouch
---   sell_loot_metals_and_stones — true = sell metals/stones from container
---   sell_loot_metals_and_stones_container — container name for metals/stones
---   sell_loot_ignored_metals_and_stones   — array of material names to skip
---   sell_loot_bundle            — true = sell skin bundle
---   sell_loot_traps             — true = sell trap components (Thieves only)
---   sell_loot_skip_pouch_close  — true = leave gem pouch open after selling
---   pick.component_container    — trap component container (from pick settings)
---   component_container         — trap component container (fallback)
---   bankbot_name                — name of bankbot PC
---   bankbot_room_id             — room ID where bankbot can be found
---   bankbot_deposit_threshold   — copper amount to keep before giving bankbot
---   bankbot_enabled             — true = use bankbot instead of bank
---   sort_auto_head              — true = run "sort auto head" after wearing trap container

-- ============================================================================
-- Argument parsing
-- ============================================================================

local raw = Script and Script.vars and Script.vars[0] or ""
local args = { town = nil, amount = nil, type = nil }

-- Parse --town=X, --amount=N, --type=T from raw args
for token in raw:gmatch("%S+") do
  local k, v = token:match("^%-%-([%w_]+)=(.+)")
  if k then args[k] = v end
end

-- Positional fallback: ';sell_loot [town] [amount type]' or ';sell_loot [amount type]'
if not args.town and not args.amount then
  local toks = {}
  for t in raw:gmatch("%S+") do
    if not t:match("^%-%-") then toks[#toks+1] = t end
  end
  if #toks == 1 then
    -- Could be a town name (non-numeric) or an amount
    if toks[1]:match("^%d+$") then
      args.amount = toks[1]
    else
      args.town = toks[1]
    end
  elseif #toks == 2 then
    if toks[1]:match("^%d+$") then
      args.amount = toks[1]; args.type = toks[2]
    else
      args.town = toks[1]
    end
  elseif #toks == 3 then
    args.town = toks[1]; args.amount = toks[2]; args.type = toks[3]
  end
end

-- ============================================================================
-- Setup
-- ============================================================================

DRC.empty_hands()

Flags.add("tip-accepted", ".* accepts your tip and slips it away with a smile")
Flags.add("tip-declined", ".* declines your tip offer")
Flags.add("tip-expired",  "Your tip offer to .* has expired")

local settings = get_settings()
local town_data = get_data("town")

local hometown_key = args.town
  or settings.sell_loot_town
  or settings.hometown
  or "Crossing"

local character_hometown = DRC.get_town_name(hometown_key) or hometown_key

local hometown = town_data[character_hometown] or {}

local bankbot_name      = settings.bankbot_name
local bankbot_room_id   = settings.bankbot_room_id
local bankbot_threshold = settings.bankbot_deposit_threshold or 0
local bankbot_enabled   = settings.bankbot_enabled

local local_currency = (hometown.currency or "kronars"):lower()

local skip_bank     = settings.sell_loot_skip_bank
local skip_exchange = settings.sell_loot_skip_exchange

-- Parse the keep-on-hand amount
local keep_money_raw = settings.sell_loot_money_on_hand or "3 silver"
local keep_default_amt, keep_default_type = keep_money_raw:match("(%d+)%s+(%a+)")
local keep_amount      = args.amount or keep_default_amt or 3
local keep_denomination = args.type  or keep_default_type or "silver"
local keep_coppers_bank = DRCM.convert_to_copper(keep_amount, keep_denomination)

local sort_auto_head = settings.sort_auto_head

-- ============================================================================
-- Helper: resolve clerk when field may be a string or an array
-- ============================================================================

local function which_clerk(clerks)
  if type(clerks) == "string" then return clerks end
  if type(clerks) == "table" then
    for _, clerk in ipairs(clerks) do
      for _, pc_or_npc in ipairs(DRRoom.pcs or {}) do
        if pc_or_npc == clerk then return clerk end
      end
      -- Also check NPCs if available
    end
    -- If DRRoom didn't match, return first
    return clerks[1]
  end
  return tostring(clerks)
end

-- ============================================================================
-- sell_gems: rummage gem pouch, walk to gemshop, sell each gem
-- ============================================================================

local function sell_gems(container)
  DRC.release_invisibility()
  local open_result = DRC.bput("open my " .. container,
    "You open your", "You open a", "has been tied off",
    "What were you referring to", "That is already open")
  if open_result:find("has been tied off") or open_result:find("What were you referring to") then
    return
  end

  local gems = DRC.get_gems(container)
  if #gems > 0 then
    local gemshop = hometown.gemshop
    if not gemshop or not gemshop.id then
      echo("*** No gemshop configured for " .. character_hometown .. " ***")
    else
      if not DRCT.walk_to(gemshop.id) then return end
      local clerk = which_clerk(gemshop.name)
      for _, gem in ipairs(gems) do
        fput("get my " .. gem .. " from my " .. container)
        fput("sell my " .. gem .. " to " .. clerk)
      end
    end
  end

  if not settings.sell_loot_skip_pouch_close then
    fput("close my " .. container)
  end
end

-- ============================================================================
-- check_spare_pouch: restock gem pouch from spare container at gemshop
-- ============================================================================

local function check_spare_pouch(container, adj)
  fput("open my " .. container)
  if DRCI.inside(adj .. " pouch", container) then return end

  local gemshop = hometown.gemshop
  if not gemshop or not gemshop.id then return end
  DRCT.walk_to(gemshop.id)
  local clerk = which_clerk(gemshop.name)
  DRC.release_invisibility()
  fput("ask " .. clerk .. " for " .. adj .. " pouch")
  fput("put my pouch in my " .. container)
end

-- ============================================================================
-- sell_metals_and_stones: sell metal/stone nuggets and bars from container
-- ============================================================================

local function sell_metals_and_stones(container)
  DRC.release_invisibility()

  local item_data   = get_data("items")
  local metal_types = item_data.metal_types or {}
  local stone_types = item_data.stone_types or {}

  -- Build material union pattern
  local all_materials = {}
  for _, m in ipairs(metal_types) do all_materials[#all_materials+1] = m end
  for _, s in ipairs(stone_types) do all_materials[#all_materials+1] = s end

  local ignore_list = settings.sell_loot_ignored_metals_and_stones or {}
  local ignore_set = {}
  for _, name in ipairs(ignore_list) do
    ignore_set[name:lower()] = true
  end

  local items = DRCI.get_item_list(container)
  local to_sell = {}
  for _, item in ipairs(items) do
    -- Match: "<size> <material> <nugget|bar>"
    -- Try nugget first, then bar (Lua patterns don't support | alternation)
    local noun = nil
    local rest = nil
    local m1, m2 = item:match("^(.+)%s+(nugget)$")
    if m1 then rest, noun = m1, m2
    else m1, m2 = item:match("^(.+)%s+(bar)$")
      if m1 then rest, noun = m1, m2 end
    end
    if rest and noun then
      -- rest = "<size> <material>", extract the last word(s) as material
      -- by stripping the first size word
      local size_word, material = rest:match("^(%a+)%s+(.+)$")
      if size_word and material then
        local mat_lower = material:lower()
        if not ignore_set[mat_lower] then
          for _, m in ipairs(all_materials) do
            if m:lower() == mat_lower then
              to_sell[#to_sell+1] = material .. " " .. noun
              break
            end
          end
        end
      end
    end
  end

  if #to_sell > 0 then
    local gemshop = hometown.gemshop
    if not gemshop or not gemshop.id then
      echo("*** No gemshop configured for " .. character_hometown .. " ***")
      return
    end
    if not DRCT.walk_to(gemshop.id) then return end
    local clerk = which_clerk(gemshop.name)
    for _, item in ipairs(to_sell) do
      fput("get my " .. item .. " from my " .. container)
      fput("sell my " .. item .. " to " .. clerk)
    end
  end
end

-- ============================================================================
-- sell_bundle: count skins in bundle, walk to tannery, sell bundle
-- ============================================================================

local function sell_bundle()
  local count_result = DRC.bput("count my bundle",
    "You flip through .* bundle and find %d+ skin",
    "I could not find")
  local count = tonumber(count_result:match("%d+")) or 0
  if count <= 0 then return end

  local tannery = hometown.tannery
  if not tannery or not tannery.id then
    echo("*** No tannery configured for " .. character_hometown .. " ***")
    return
  end
  if not DRCT.walk_to(tannery.id) then return end

  local remove_result = DRC.bput("remove my bundle",
    "You remove", "You sling", "Remove what", "You take")
  if remove_result:find("Remove what") then return end

  DRC.release_invisibility()
  DRC.bput("sell my bundle",
    "ponders over the bundle", "sorts through it", "gives it a close inspection",
    "takes the bundle", "I don't think I can give you anything for that worthless thing")

  -- Handle what ends up in hand after selling
  local rh = DRC.right_hand() or ""
  local lh = DRC.left_hand()  or ""
  local in_hands = rh .. " " .. lh
  if in_hands:find("rope") then
    DRCI.put_away_item("rope")
  elseif in_hands:find("bundle") then
    if not DRCI.wear_item("bundle") then
      DRCI.put_away_item("bundle")
    end
  end
end

-- ============================================================================
-- sell_traps: Thieves only — bulk-sell trap components at locksmith
-- ============================================================================

local function sell_traps(container)
  if not DRStats.thief() then return end

  local look_result = DRC.bput("look in my " .. container,
    "There is nothing in there", "you see")
  if not look_result:find("you see") then return end

  DRC.release_invisibility()
  local remove_result = DRC.bput("remove my " .. container,
    "You remove", "What were you referring to",
    "You aren't wearing that", "Remove what")
  if remove_result:find("What were you referring to")
      or remove_result:find("You aren't wearing that")
      or remove_result:find("Remove what") then
    return
  end

  local locksmithing = hometown.locksmithing
  if not locksmithing or not locksmithing.id then
    echo("*** No locksmithing shop configured for " .. character_hometown .. " ***")
    DRC.bput("wear my " .. container, "You attach", "Wear what", "You are already wearing")
    return
  end

  if DRCT.walk_to(locksmithing.id) then
    local clerk = which_clerk(locksmithing.name)

    -- Locksmith won't accept while other PCs are in the room — wait up to 25s
    local wait_counter = 0
    while #(DRRoom.pcs or {}) > 0 do
      if wait_counter >= 5 then break end
      wait_counter = wait_counter + 1
      echo("Waiting for other players to leave the room...")
      pause(5)
    end

    local give_result = DRC.bput("give my " .. container .. " to " .. clerk,
      "hands it back to you along with some coins",
      "There's nothing in there",
      "What is it you're trying to give",
      "not interested in",
      "doesn't appear to be interested in your offer",
      "I don't have that in stock right now")

    if give_result:find("not interested in") then
      DRC.message("Remove non-trap components from " .. container .. " then try again.")
    elseif give_result:find("doesn't appear to be interested in your offer") then
      DRC.message("Only thieves can sell trap components in bulk to locksmiths. Try selling them individually at the pawnshop.")
    elseif give_result:find("I don't have that in stock right now") then
      DRC.message("Unable to sell " .. container .. " at this time. Try again later when no one else is in the shop with you.")
    end
  end

  DRC.bput("wear my " .. container, "You attach", "Wear what", "You are already wearing")
  if sort_auto_head then fput("sort auto head") end
end

-- ============================================================================
-- exchange_coins: walk to exchange, convert all foreign currencies
-- ============================================================================

local function exchange_coins()
  local exchange = hometown.exchange
  if not exchange or not exchange.id then
    echo("*** No exchange configured for " .. character_hometown .. " ***")
    return
  end
  DRCT.walk_to(exchange.id)
  DRC.release_invisibility()
  local exchange_to = local_currency
  for _, currency in ipairs(DRCM.CURRENCIES) do
    if currency:lower() ~= exchange_to:lower() then
      fput("exchange all " .. currency .. " for " .. exchange_to)
    end
  end
end

-- ============================================================================
-- give_money_to_bankbot: tip bankbot the deposit amount for a currency
-- ============================================================================

local function give_money_to_bankbot(currency, keep)
  local copper_on_hand = DRCM.check_wealth(currency)
  local deposit_amount = copper_on_hand - keep
  if deposit_amount <= 0 then return end

  DRCT.walk_to(bankbot_room_id)

  -- Check bankbot is present
  local found = false
  for _, pc in ipairs(DRRoom.pcs or {}) do
    if pc == bankbot_name then found = true; break end
  end
  if not found then return end

  Flags.reset("tip-accepted")
  Flags.reset("tip-expired")
  Flags.reset("tip-declined")

  local tip_result = DRC.bput(
    "tip " .. bankbot_name .. " " .. deposit_amount .. " " .. currency,
    "You offer",
    "I don't know who",
    "you really should keep every bronze you can get your hands on",
    "You already have a tip offer outstanding",
    "already has a tip offer pending",
    "But you don't have that much!")

  if tip_result:find("I don't know who") then
    echo("***Bankbot not found, skipping deposit***")
    return
  elseif tip_result:find("You already have a tip offer outstanding") then
    echo("***You already have a tip offer outstanding, skipping deposit***")
    return
  elseif tip_result:find("you really should keep every bronze") then
    echo("***ERROR*** UNABLE TO TIP DUE TO LOW CIRCLE, EXITING")
    return
  elseif tip_result:find("already has a tip offer pending") then
    echo("***Bankbot is busy, skipping deposit***")
    return
  elseif tip_result:find("But you don't have that much!") then
    echo("***Error calculating tip amount, please report on GitHub***")
    return
  end

  -- Wait for tip outcome
  local timeout_at = os.time() + 30
  while os.time() < timeout_at do
    if Flags["tip-accepted"] or Flags["tip-expired"] or Flags["tip-declined"] then
      break
    end
    pause(0.5)
  end
end

-- ============================================================================
-- Main execution
-- ============================================================================

-- 1. Sell gems from gem pouch
if settings.sell_loot_pouch then
  local gem_container = (settings.gem_pouch_adjective or "") .. " " .. (settings.gem_pouch_noun or "pouch")
  sell_gems(gem_container:match("^%s*(.-)%s*$"))
end

-- 2. Check/restock spare gem pouch
if settings.spare_gem_pouch_container then
  check_spare_pouch(settings.spare_gem_pouch_container, settings.gem_pouch_adjective or "")
end

-- 3. Sell metals and stones
if settings.sell_loot_metals_and_stones then
  sell_metals_and_stones(settings.sell_loot_metals_and_stones_container or "backpack")
end

-- 4. Sell skin bundle
if settings.sell_loot_bundle then
  sell_bundle()
end

-- 5. Sell trap components (Thieves only)
if settings.sell_loot_traps then
  local trap_container = (settings.pick and settings.pick.component_container)
    or settings.component_container
  if trap_container then
    sell_traps(trap_container)
  end
end

-- 6. Banking / deposit
if skip_bank and not bankbot_enabled then
  -- Nothing to do for banking
elseif bankbot_enabled and (not bankbot_name or not bankbot_room_id) then
  echo("*** bankbot_enabled but bankbot_name or bankbot_room_id not set ***")
elseif skip_bank and bankbot_enabled then
  -- Bankbot only — deposit all currencies, keeping threshold for local currency
  for _, currency in ipairs(DRCM.CURRENCIES) do
    local keep = currency:lower():find(local_currency:lower()) and bankbot_threshold or 0
    give_money_to_bankbot(currency, keep)
  end
else
  -- Normal bank flow
  if not skip_exchange then
    exchange_coins()
  end
  if bankbot_enabled then
    give_money_to_bankbot(local_currency, bankbot_threshold)
  else
    -- Walk to the bank deposit room before depositing
    local deposit = hometown.deposit
    if deposit and deposit.id then
      DRCT.walk_to(deposit.id)
    else
      echo("*** No deposit room configured for " .. character_hometown .. " — attempting deposit from current room ***")
    end
    DRCM.deposit_coins(keep_coppers_bank, settings)
  end
end

-- ============================================================================
-- Cleanup
-- ============================================================================

Flags.delete("tip-accepted")
Flags.delete("tip-declined")
Flags.delete("tip-expired")
