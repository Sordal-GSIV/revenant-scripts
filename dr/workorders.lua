--- @revenant-script
--- name: workorders
--- version: 1.0.0
--- author: Elanthia Online (lic)
--- game: dr
--- description: Automated crafting work order management — request, craft, bundle, and turn in.
--- tags: crafting, workorders, forging, tailoring, engineering, alchemy, artificing
--- @lic-certified: complete 2026-03-19
---
--- Supports all crafting disciplines:
---   blacksmithing, weaponsmithing, tailoring, shaping, carving, remedies, artificing
---
--- Usage:
---   ;workorders <discipline> [repair] [turnin]
---
--- Arguments:
---   discipline   blacksmithing|weaponsmithing|tailoring|shaping|carving|remedies|artificing
---   repair       Repair tools instead of crafting items
---   turnin       Get a work order and immediately turn in items already on hand
---
--- Examples:
---   ;workorders blacksmithing
---   ;workorders tailoring repair
---   ;workorders shaping turnin
---
--- Settings (in your profile JSON):
---   crafting_container        — bag that holds crafting supplies
---   crafting_items_in_container — item names kept in that bag
---   worn_trashcan             — worn container to discard scrap into
---   worn_trashcan_verb        — verb to use on worn trashcan
---   hometown                  — your base city
---   force_crafting_town       — override hometown for crafting
---   use_own_ingot_type        — metal name if using personal ingots
---   deed_own_ingot            — true to deed leftover ingots
---   carving_workorder_material_type — "bone" or "stone"
---   workorder_min_items       — minimum acceptable quantity
---   workorder_max_items       — maximum acceptable quantity
---   workorder_recipes         — discipline->list of recipe names to accept
---   workorder_cash_on_hand    — copper to keep on hand for purchases
---   craft_max_mindstate       — max learning rate index (0-19) before stopping
---   retain_crafting_materials — keep leftover materials instead of trashing
---   workorders_repair         — auto-repair tools after completing a work order
---   workorders_repair_own_tools — use own materials to repair (vs NPC)
---   workorders_override_store — forage herbs instead of buying from store
---   workorders_materials      — { metal_type, fabric_type, knit_type, wood_type, bone_type, stone_type }
---   workorder_diff            — difficulty tier (default "challenging"), or per-discipline table
---   workorders_force_heal     — run safe-room before starting
---   forging_tools / outfitting_tools / shaping_tools / carving_tools / alchemy_tools / enchanting_tools
---   forging_belt / outfitting_belt / engineering_belt / alchemy_belt / enchanting_belt
---   outfitting_room / engineering_room / alchemy_room / enchanting_room

-------------------------------------------------------------------------------
-- Pattern constants (Lua string.find patterns)
-------------------------------------------------------------------------------

local GIVE_LOGBOOK_SUCCESS_PATTERNS = {
  "You hand",
  "You can",
  "What were you",
  "Apparently the work order time limit has expired",
  "The work order isn't yet complete",
}

local GIVE_LOGBOOK_RETRY_PATTERNS = {
  "What were you",
  "You can",
  "What is it you're trying to give",
}

local NPC_NOT_FOUND_PATTERN = "What is it you're trying to give"

local REPAIR_GIVE_PATTERNS = {
  "I don't repair those here",
  "What is it",
  "There isn't a scratch on that",
  "Just give it to me again",
  "I will not",
  "I can't fix those",
}

-- Patterns that indicate no repair is needed (skip stow, wait for ticket)
local REPAIR_NO_NEED_PATTERNS = {
  "scratch",
  "I will not",
  "They only have so many uses",
}

local BUNDLE_SUCCESS_PATTERNS = {
  "You notate the",
  "This work order has expired",
  "The work order requires items of a higher quality",
  "Only undamaged enchanted items may be used with workorders",
  "That's not going to work",
}

local BUNDLE_FAILURE_PATTERNS = {
  "requires items of",
  "Only undamaged enchanted",
}

local WORK_ORDER_REQUEST_PATTERNS = {
  "^To whom",
  "order for .* I need %d+ ",
  "order for .* I need %d+ stacks %(5 uses each%) of .* quality",
  "You realize you have items bundled with the logbook",
  "You want to ask about shadowlings",
}

local READ_LOGBOOK_PATTERNS = {
  "This work order appears to be complete",
  "You must bundle and deliver %d+ more",
}

-- Carving material noun sequence (deed->pebble->stone->rock->rock->boulder)
local MATERIAL_NOUNS = { "deed", "pebble", "stone", "rock", "rock", "boulder" }

-- Fount patterns
local FOUNT_TAP_IN_BAG  = "You tap .* inside your"
local FOUNT_TAP_ON_BAG  = "You tap .* attached to your"
local FOUNT_TAP_NOT_FOUND = "I could not find"
local FOUNT_ANALYZE_PATTERN = "(%d+) uses? remaining"

-------------------------------------------------------------------------------
-- Helper utilities
-------------------------------------------------------------------------------

--- Check if a string matches any pattern in a list.
local function matches_any(str, patterns)
  if not str then return false end
  for _, pat in ipairs(patterns) do
    if str:find(pat) then return true end
  end
  return false
end

--- Check if an NPC name appears in the current room's NPC list.
local function npcs_include(name)
  local npcs = DRRoom and DRRoom.npcs
  if not npcs then return false end
  for _, n in ipairs(npcs) do
    if n:find(name, 1, true) then return true end
  end
  return false
end

--- Get a shallow copy of the ORDINALS table.
local function ordinals_copy()
  local copy = {}
  if ORDINALS then
    for i, v in ipairs(ORDINALS) do copy[i] = v end
  end
  return copy
end

--- Get current room ID.
local function current_room_id()
  if Map and Map.current_room then
    return Map.current_room()
  end
  return GameState and GameState.room_id
end

--- Get current room title/name.
local function room_name()
  return (GameState and GameState.room_name) or ""
end

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

local DISCIPLINES = {
  blacksmithing = true, weaponsmithing = true, tailoring = true,
  shaping = true, carving = true, remedies = true, artificing = true,
}

local function parse_args()
  local raw = script_args or ""
  local tokens = {}
  for t in raw:gmatch("%S+") do tokens[#tokens + 1] = t:lower() end

  local discipline = tokens[1]
  if not discipline or not DISCIPLINES[discipline] then
    respond("[workorders] Usage: ;workorders <discipline> [repair] [turnin]")
    respond("[workorders] Disciplines: blacksmithing weaponsmithing tailoring shaping carving remedies artificing")
    return nil
  end

  local repair = false
  local turnin = false
  for i = 2, #tokens do
    if tokens[i] == "repair" then repair = true end
    if tokens[i] == "turnin" then turnin = true end
  end

  return { discipline = discipline, repair = repair, turnin = turnin }
end

-------------------------------------------------------------------------------
-- State (set during work_order, used by helpers)
-------------------------------------------------------------------------------

local S = {}  -- shared script state

-------------------------------------------------------------------------------
-- Tool helpers
-------------------------------------------------------------------------------

local function get_tool(name)
  return DRCC.get_crafting_item(name, S.bag, S.bag_items, S.belt, true)
end

local function stow_tool(name)
  if not name or name == "" then return end
  DRCC.stow_crafting_item(name, S.bag, S.belt)
end

-------------------------------------------------------------------------------
-- NPC / room navigation
-------------------------------------------------------------------------------

--- Walk through room_list looking for npc, return true if found.
local function find_npc(room_list, npc)
  for _, room_id in ipairs(room_list) do
    if npcs_include(npc) then return true end
    DRCT.walk_to(room_id)
  end
  return npcs_include(npc)
end

-------------------------------------------------------------------------------
-- Bundling
-------------------------------------------------------------------------------

--- Bundle a crafted item with the logbook.
-- Returns false and discards item on failure.
local function bundle_item(noun, logbook)
  -- "small sphere" → "fount" once placed on brazier
  if noun == "small sphere" then noun = "fount" end

  if not DRCI.get_item(logbook .. " logbook") then
    respond("[workorders] Failed to get " .. logbook .. " logbook for bundling")
    return false
  end

  local result = DRC.bput("bundle my " .. noun .. " with my logbook", table.unpack(BUNDLE_SUCCESS_PATTERNS))

  if matches_any(result, BUNDLE_FAILURE_PATTERNS) then
    respond("[workorders] Bundle failed — " .. result .. ". Disposing item.")
    DRCI.dispose_trash(noun, S.worn_trashcan, S.worn_trashcan_verb)
  end

  DRCI.stow_hands()
  return true
end

-------------------------------------------------------------------------------
-- Work order request
-------------------------------------------------------------------------------

--- Request a work order from the NPC, retrying up to 500 times.
-- Returns item_name, quantity on success or terminates on failure.
local function request_work_order(recipes, npc_rooms, npc, npc_last_name, discipline, logbook, diff)
  local match_names = {}
  for _, r in ipairs(recipes) do match_names[r.name] = true end

  diff = diff or "challenging"
  DRCI.stow_hands()

  for _ = 1, 500 do
    if not find_npc(npc_rooms, npc_last_name) then
      respond("[workorders] Could not find NPC " .. npc_last_name .. " — will retry")
      -- continue loop
    else
      -- Get logbook if not already holding something
      if not DRC.left_hand() and not DRC.right_hand() then
        if not DRCI.get_item(logbook .. " logbook") then
          respond("[workorders] Failed to get " .. logbook .. " logbook for work order request")
          -- continue loop
          goto continue
        end
      end

      local result = DRC.bput("ask " .. npc .. " for " .. diff .. " " .. discipline .. " work",
        table.unpack(WORK_ORDER_REQUEST_PATTERNS))

      if result:find("You want to ask about shadowlings") then
        pause(10)
        fput("say Hmm.")

      elseif result:find("order for .* I need %d+") then
        -- Try standard item pattern
        local item, quantity = result:match("order for (.*%)%. I need (%d+) ")
        if not item then
          -- Try stacks pattern
          item, quantity = result:match("order for (.*%)%. I need (%d+) stacks %(5 uses each%)")
        end
        if item and quantity then
          quantity = tonumber(quantity)
          if S.min_items <= quantity and quantity <= S.max_items and match_names[item] then
            stow_tool("logbook")
            respond("[workorders] Accepted work order for " .. quantity .. " " .. item)
            return item, quantity
          end
        end

      elseif result:find("You realize you have items bundled with the logbook") then
        if not DRCI.untie_item("logbook") then
          respond("[workorders] Failed to untie logbook")
        end
        local lh = DRC.left_hand()
        local rh = DRC.right_hand()
        if lh and lh:find("logbook") then
          DRCI.dispose_trash(rh, S.worn_trashcan, S.worn_trashcan_verb)
        else
          DRCI.dispose_trash(lh, S.worn_trashcan, S.worn_trashcan_verb)
        end
        -- Ensure logbook is in hand
        lh = DRC.left_hand()
        rh = DRC.right_hand()
        if not (lh and lh:find("logbook")) and not (rh and rh:find("logbook")) then
          if not DRCI.get_item("logbook") then
            respond("[workorders] Failed to get logbook after untying")
          end
        end
      end
    end

    ::continue::
  end

  stow_tool("logbook")
  respond("[workorders] Failed to get a suitable work order after 500 attempts")
  return nil, nil
end

-------------------------------------------------------------------------------
-- Work order completion (turn-in)
-------------------------------------------------------------------------------

local function complete_work_order(info)
  DRCI.stow_hands()

  while true do
    if not find_npc(info["npc-rooms"], info.npc_last_name) then
      respond("[workorders] Could not find NPC " .. tostring(info.npc_last_name) .. " in any expected rooms")
      return
    end
    if not DRCI.get_item(info.logbook .. " logbook") then
      respond("[workorders] Failed to get " .. info.logbook .. " logbook for turn-in")
      return
    end

    DRC.release_invisibility()
    local result = DRC.bput("give logbook to " .. info.npc,
      table.unpack(GIVE_LOGBOOK_SUCCESS_PATTERNS))

    -- Exit loop unless we hit a retry pattern
    if not matches_any(result, GIVE_LOGBOOK_RETRY_PATTERNS) then
      break
    end
  end

  stow_tool("logbook")
  respond("[workorders] Work order completed and turned in")
end

-------------------------------------------------------------------------------
-- Tool repair
-------------------------------------------------------------------------------

local function repair_items(info, tools)
  if S.workorders_repair_own_tools then
    local cur = current_room_id()
    DRCM.ensure_copper_on_hand(1500, S.settings, S.hometown)
    DRCT.walk_to(cur)
    DRCC.repair_own_tools(
      get_data("crafting").blacksmithing and get_data("crafting").blacksmithing[S.hometown] or {},
      tools, S.bag, S.bag_items, S.belt)
    respond("[workorders] Tool repair using own materials completed")
    return
  end

  DRCT.walk_to(info["repair-room"])

  for _, tool_name in ipairs(tools) do
    get_tool(tool_name)
    local result = DRC.bput("give " .. info["repair-npc"], table.unpack(REPAIR_GIVE_PATTERNS))

    if matches_any(result, REPAIR_NO_NEED_PATTERNS) then
      stow_tool(tool_name)
    elseif result:find("give") then
      -- NPC accepted it — wait for repair ticket
      DRC.bput("give " .. info["repair-npc"], "repair ticket")
      if not DRCI.put_away_item("ticket") then
        respond("[workorders] Failed to stow repair ticket")
      end
    end
  end

  -- Wait for all repair tickets to be fulfilled
  while DRCI.get_item(info["repair-npc"] .. " ticket") do
    -- Wait until ticket says ready
    while true do
      local r = DRC.bput("look at my ticket", "should be ready by now", "Looking at the")
      if r:find("should be ready by now") then break end
      pause(30)
    end
    DRC.bput("give " .. info["repair-npc"], "You hand")
    pause(1)
    local rh = DRC.right_hand()
    local lh = DRC.left_hand()
    if rh and rh ~= "" then stow_tool(rh) end
    if lh and lh ~= "" then stow_tool(lh) end
  end

  respond("[workorders] Tool repair at NPC completed")
end

-------------------------------------------------------------------------------
-- Material / recipe helpers
-------------------------------------------------------------------------------

--- Calculate items per stock unit and scrap status.
-- Returns: recipe, items_per_stock, spare_stock, scrap
local function find_recipe_data(materials_info, recipe, quantity)
  local items_per_stock = math.floor(materials_info["stock-volume"] / recipe.volume)
  local spare_stock = (materials_info["stock-volume"] % recipe.volume) ~= 0 and
                      (materials_info["stock-volume"] % recipe.volume) or nil

  local scrap = spare_stock or ((quantity % items_per_stock) ~= 0)

  return recipe, items_per_stock, spare_stock, scrap
end

--- Open door and enter.
local function go_door()
  fput("open door")
  DRC.fix_standing()
  fput("go door")
end

--- Buy parts from a part room.
local function buy_parts(parts, partroom)
  if not parts then return end
  for _, part in ipairs(parts) do
    DRCT.buy_item(partroom, part)
    stow_tool(part)
  end
end

--- Order recipe parts from crafting shops.
local function order_parts(parts, quantity)
  if not parts then return end
  local crafting_data = get_data("crafting")
  local recipe_parts = crafting_data.recipe_parts or {}

  for _, part in ipairs(parts) do
    local data = recipe_parts[part] and recipe_parts[part][S.hometown]
    if not data then
      respond("[workorders] No part data for: " .. part .. " in " .. S.hometown)
    else
      for _ = 1, quantity do
        if data["part-number"] then
          DRCT.order_item(data["part-room"], data["part-number"])
        else
          DRCT.buy_item(data["part-room"], part)
        end
        stow_tool(part)
      end
    end
  end
end

--- Order cloth or yarn from stock, combining stacks as we go.
local function order_fabric(stock_room, stock_needed, stock_number, fabric_type)
  for _ = 1, stock_needed do
    DRCT.order_item(stock_room, stock_number)
    local rh = DRC.right_hand()
    local lh = DRC.left_hand()
    if rh and rh:find(fabric_type, 1, true) and lh and lh:find(fabric_type, 1, true) then
      DRC.bput("combine " .. fabric_type .. " with " .. fabric_type, "You combine")
    end
  end
  stow_tool(fabric_type)
end

-------------------------------------------------------------------------------
-- Ingot volume helpers
-------------------------------------------------------------------------------

local function ingot_volume()
  local res = DRC.bput("analyze my ingot", "About %d+ volume")
  return tonumber(res:match("(%d+)")) or 0
end

local function deed_ingot_volume()
  local res = DRC.bput("read my deed", "Volume:%s*%d+")
  return tonumber(res:match("(%d+)")) or 0
end

-------------------------------------------------------------------------------
-- Herb gathering helpers
-------------------------------------------------------------------------------

local function gather_process_herb(herb, herb_volume_to_purchase)
  respond("[workorders] Gathering herb: " .. herb)
  DRC.wait_for_script_to_complete("alchemy", { herb, "forage", tostring(herb_volume_to_purchase) })
  DRC.wait_for_script_to_complete("alchemy", { herb, "prepare" })
end

--- Count and combine herb stacks; order or forage more if needed.
-- is_herb2: if true, only needs quantity*2 volume (secondary herb)
local function count_combine_rem(stock_room, quantity, herb, herb_stock, is_herb2)
  local found_stack = true
  local herb_volume_total = 0
  local last_herb_volume = 0
  local last_descriptor = ""

  -- Only use the last word for tapping (handles multi-word herb names)
  local herb_for_tapping = herb:match("(%S+)$") or herb

  local need_herb_volume = is_herb2 and (quantity * 2) or (quantity * 25)

  local ordinals = ordinals_copy()
  local idx = 1

  while found_stack and idx <= #ordinals do
    local stack_descriptor = ordinals[idx]
    idx = idx + 1

    local tap_result = DRC.bput(
      "tap " .. stack_descriptor .. " " .. herb_for_tapping .. " in my " .. S.bag,
      "You tap (.*) inside your",
      "I could not find",
      "You lightly tap")

    local tap_item = tap_result:match("You tap (.*) inside your")
    local herb_volume = 0

    if not tap_item then
      found_stack = false
    else
      if tap_item:find(herb, 1, true) then
        local count_result = DRC.bput(
          "count " .. stack_descriptor .. " " .. herb_for_tapping .. " in my " .. S.bag,
          "I could not find",
          "You count out %d+ pieces%.")
        herb_volume = tonumber(count_result:match("You count out (%d+) pieces%.")) or 0
      end
      -- If wrong item type, herb_volume stays 0 and we continue
    end

    if herb_volume > 0 then
      herb_volume_total = herb_volume_total + herb_volume

      -- Combine stacks if they fit in a single stack (max 75)
      if (herb_volume + last_herb_volume) <= 75 and last_herb_volume > 0 then
        DRC.bput("get " .. stack_descriptor .. " " .. herb_for_tapping .. " from my " .. S.bag, "You get")
        DRC.bput("get " .. last_descriptor .. " " .. herb_for_tapping .. " from my " .. S.bag, "You get")
        local combined = DRC.bput("combine", "You combine", "That stack of herbs")
        if combined:find("You combine") then
          last_herb_volume = herb_volume + last_herb_volume
          -- Re-insert descriptor (one fewer stack now)
          table.insert(ordinals, idx, stack_descriptor)
        end
        stow_tool(DRC.left_hand() or "")
        stow_tool(DRC.right_hand() or "")
      else
        last_descriptor = stack_descriptor
        last_herb_volume = herb_volume
      end
    end

    if not found_stack then break end
  end

  local herb_volume_to_purchase = need_herb_volume - herb_volume_total
  if herb_volume_to_purchase <= 0 then return end

  local herb_to_purchase = math.ceil(herb_volume_to_purchase / 25.0)

  if not herb_stock or S.workorders_override_store then
    gather_process_herb(herb, herb_volume_to_purchase)
  end

  if herb_stock and not S.workorders_override_store then
    for _ = 1, herb_to_purchase do
      DRCT.order_item(stock_room, herb_stock)
      stow_tool(DRC.left_hand() or "")
      stow_tool(DRC.right_hand() or "")
    end
  end

  stow_tool(DRC.left_hand() or "")
  stow_tool(DRC.right_hand() or "")
end

-------------------------------------------------------------------------------
-- Enchanting helpers (DRCC functions not yet in common_crafting.lua)
-------------------------------------------------------------------------------

--- Order enchanting components and stow them.
local function order_enchant(stock_room, stock_needed, stock_number, bag, belt)
  for _ = 1, stock_needed do
    DRCT.order_item(stock_room, stock_number)
    local lh = DRC.left_hand()
    local rh = DRC.right_hand()
    if lh and lh ~= "" then DRCC.stow_crafting_item(lh, bag, belt) end
    if rh and rh ~= "" then DRCC.stow_crafting_item(rh, bag, belt) end
  end
end

--- Check for and restock a mana fount if uses are insufficient.
local function fount_check(stock_room, stock_number, quantity, bag, bag_items, belt)
  local tap_result = DRC.bput("tap my fount",
    FOUNT_TAP_IN_BAG, FOUNT_TAP_ON_BAG, FOUNT_TAP_NOT_FOUND)

  if tap_result:find("You tap") then
    -- Fount found in/on bag; check uses
    local analyze_result = DRC.bput("analyze my fount", FOUNT_ANALYZE_PATTERN)
    local uses = tonumber(analyze_result:match(FOUNT_ANALYZE_PATTERN)) or 0
    if uses < quantity + 1 then
      DRCC.get_crafting_item("fount", bag, bag_items, belt, true)
      DRCI.dispose_trash("fount", S.worn_trashcan, S.worn_trashcan_verb)
      DRCI.stow_hands()
      order_enchant(stock_room, 1, stock_number, bag, belt)
    end
  else
    -- Check if fount is on brazier
    local on_brazier = DRC.bput("tap my fount on my brazier",
      "You tap .* on the", FOUNT_TAP_NOT_FOUND)
    if on_brazier:find("You tap") then
      local analyze_result = DRC.bput("analyze my fount on my brazier", FOUNT_ANALYZE_PATTERN)
      local uses = tonumber(analyze_result:match(FOUNT_ANALYZE_PATTERN)) or 0
      if uses < quantity then
        DRCI.stow_hands()
        order_enchant(stock_room, 1, stock_number, bag, belt)
      end
    else
      order_enchant(stock_room, 1, stock_number, bag, belt)
    end
  end
end

--- Check for and restock enchanting sigil-scrolls.
-- Returns true if sigils are available, false if they must be found manually.
local function check_for_existing_sigil(sigil_name, stock_number, quantity, bag, belt, info)
  local noun = sigil_name:match("(%S+)$") or sigil_name
  local tmp_count = DRCI.count_items_in_container(noun .. " sigil-scroll", bag) or 0

  if tmp_count >= quantity then return true end

  local need = quantity - tmp_count

  if stock_number then
    respond("[workorders] Need " .. need .. " more " .. sigil_name .. " sigil-scrolls — ordering")
    order_enchant(info["stock-room"], need, stock_number, bag, belt)
    return true
  else
    respond("[workorders] Cannot purchase " .. sigil_name .. " sigil-scrolls — must find them manually")
    return false
  end
end

-------------------------------------------------------------------------------
-- Crafting methods
-------------------------------------------------------------------------------

--- Forge items using standard shop ingots.
local function forge_items(info, materials_info, item, quantity)
  local recipe = find_recipe_data(materials_info, item, quantity)
  local remaining_volume = 0

  -- Skip room-trashcan disposal if worn trashcan is set
  local trash_room = (S.worn_trashcan and S.worn_trashcan_verb) and nil or info["trash-room"]

  DRCM.ensure_copper_on_hand(S.cash_on_hand or 5000, S.settings, S.hometown)

  for _ = 1, quantity do
    if remaining_volume < recipe.volume then
      if remaining_volume > 0 then
        DRCT.dispose(materials_info["stock-name"] .. " ingot", trash_room, S.worn_trashcan, S.worn_trashcan_verb)
      end
      DRCT.order_item(info["stock-room"], materials_info["stock-number"])
      DRCC.stow_crafting_item(materials_info["stock-name"] .. " ingot", S.bag, S.belt)
      remaining_volume = materials_info["stock-volume"]
    end

    DRC.wait_for_script_to_complete("smith", { materials_info["stock-name"], item.name })
    bundle_item(recipe.noun, info.logbook)

    remaining_volume = remaining_volume - recipe.volume
  end

  if remaining_volume > 0 then
    DRCT.dispose(materials_info["stock-name"] .. " ingot", trash_room, S.worn_trashcan, S.worn_trashcan_verb)
  end
end

--- Forge items using the player's own ingots/deeds.
local function forge_items_with_own_ingot(info, materials_info, item, quantity)
  local recipe = find_recipe_data(materials_info, item, quantity)
  local volume = 0
  local smelt = false

  if not DRCI.get_item(S.use_own_ingot_type .. " ingot") then
    if not DRCI.get_item(S.use_own_ingot_type .. " deed") then
      respond("[workorders] Out of material/deeds for forging")
      return
    end
    volume = deed_ingot_volume()
    fput("tap my deed")
    pause(1)
    DRCI.get_item_if_not_held(S.use_own_ingot_type .. " ingot")
  end

  if volume == 0 then volume = ingot_volume() end
  DRCI.stow_hands()

  if volume < quantity * recipe.volume then
    smelt = true
    if not DRCI.get_item(S.use_own_ingot_type .. " deed") then
      respond("[workorders] Out of material/deeds for forging (need more volume)")
      DRCI.stow_hands()
      return
    end
    deed_ingot_volume()
    fput("tap my deed")
    pause(1)
    DRCI.get_item_if_not_held(S.use_own_ingot_type .. " ingot")
    volume = ingot_volume()
  end

  DRCI.stow_hands()

  if volume < quantity * recipe.volume then
    respond(string.format("[workorders] Insufficient material volume (have %d, need %d)",
      volume, quantity * recipe.volume))
    return
  end

  for _ = 1, quantity do
    DRC.wait_for_script_to_complete("smith", { S.use_own_ingot_type, item.name })
    bundle_item(recipe.noun, info.logbook)
  end

  if smelt then
    DRCC.find_empty_crucible(S.hometown)
    for _ = 1, 2 do
      if not DRCI.get_item(S.use_own_ingot_type .. " ingot") then
        respond("[workorders] Failed to get " .. S.use_own_ingot_type .. " ingot for smelting")
        break
      end
      fput("put my ingot in crucible")
    end
    DRC.wait_for_script_to_complete("smelt", {})
    DRCI.stow_hands()
  end

  if not S.deed_own_ingot then return end

  -- Re-deed remaining ingot
  local deed_check = DRC.bput("look my deed packet",
    "You count %d+ deed claim forms remaining",
    "I could not find what you were referring to")
  if not deed_check:find("You count %d+ deed claim forms remaining") then
    DRCM.ensure_copper_on_hand(S.cash_on_hand or 10000, S.settings, S.hometown)
    DRCT.order_item(S.deeds_room, S.deeds_number)
    if not DRCI.put_away_item("packet") then
      respond("[workorders] Failed to stow deed packet after ordering")
    end
  end

  if not DRCI.get_item(S.use_own_ingot_type .. " ingot") then
    respond("[workorders] Failed to get " .. S.use_own_ingot_type .. " ingot for deeding")
    return
  end
  if not DRCI.get_item("packet") then
    respond("[workorders] Failed to get deed packet for deeding")
    return
  end
  fput("push my ingot with packet")
  if not DRCI.put_away_item("packet") then
    respond("[workorders] Failed to stow deed packet")
  end
  if not DRCI.put_away_item("deed") then
    respond("[workorders] Failed to stow deed")
  end
end

--- Carve items from bone or stone.
local function carve_items(info, materials_info, item, quantity)
  DRCM.ensure_copper_on_hand(S.cash_on_hand or 5000, S.settings, S.hometown)
  local recipe, items_per_stock, spare_stock, scrap = find_recipe_data(materials_info, item, quantity)
  local material_volume = 0
  local bone_carving = recipe.material == "bone"

  -- Check surface polish
  if DRCI.get_item("surface polish") then
    local count_result = DRC.bput("count my polish", "The surface polish has %d+ uses remaining")
    local uses = tonumber(count_result:match("The surface polish has (%d+) uses remaining")) or 0
    if uses < 3 then
      DRCI.dispose_trash("polish", S.worn_trashcan, S.worn_trashcan_verb)
      DRCT.order_item(info["polish-room"], info["polish-number"])
    end
  else
    DRCT.order_item(info["polish-room"], info["polish-number"])
  end
  stow_tool("polish")

  order_parts(recipe.part, quantity)

  for count = 0, quantity - 1 do
    -- Discard spare stone fragment from previous iteration
    if count > 0 and spare_stock then
      DRCI.dispose_trash(
        materials_info["stock-name"] .. " " .. (MATERIAL_NOUNS[material_volume + 1] or "rock"),
        S.worn_trashcan, S.worn_trashcan_verb)
    end

    -- Restock material when starting or when current stock is exhausted
    if items_per_stock == 0 or (count % items_per_stock) == 0 then
      if count > 0 then
        if room_name():find("Workshop") then go_door() end
        local wait_start = os.time()
        while not current_room_id() and os.time() - wait_start < 10 do pause(0.5) end
      end

      if bone_carving then
        DRC.bput("get my " .. materials_info["stock-name"] .. " stack",
          "What were", "You get", "You pick")
        while true do
          local cnt_r = DRC.bput("count my " .. materials_info["stock-name"] .. " stack",
            "You count.*%d+", "I could not")
          local cnt = tonumber(cnt_r:match("(%d+)")) or 0
          if cnt >= recipe.volume then break end
          DRCT.order_item(info["stock-room"], materials_info["stock-number"])
          DRC.bput("combine", "combine")
        end
      else
        DRCT.order_item(info["stock-room"], materials_info["stock-number"])
        if S.engineering_room then
          fput("tap my deed")
          material_volume = materials_info["stock-volume"]
        else
          material_volume = 0
        end
      end

      DRCI.stow_hands()
    end

    if not bone_carving then
      local noun_idx = material_volume + 1
      local rock_noun = MATERIAL_NOUNS[noun_idx] or "rock"
      local rock_result = DRC.bput(
        "get " .. materials_info["stock-name"] .. " " .. rock_noun,
        "You get", "What were", "You are not strong", "You pick up", "but can't quite lift it")
      if not rock_result:find("You are not strong") and not rock_result:find("can't quite lift it") then
        DRCC.find_shaping_room(S.hometown, S.engineering_room)
      end
    else
      DRCC.find_shaping_room(S.hometown, S.engineering_room)
    end

    -- Ensure carving item is in left hand
    local rh = DRC.right_hand()
    if rh and rh:lower():find(recipe.noun or "") then
      DRC.bput("swap", "You move")
    end

    local noun_idx = material_volume + 1
    local rock_noun = MATERIAL_NOUNS[noun_idx] or "rock"
    DRC.wait_for_script_to_complete("carve", {
      tostring(recipe.chapter),
      recipe.name,
      materials_info["stock-name"],
      bone_carving and "stack" or rock_noun,
      recipe.noun,
    })

    if material_volume == 0 then
      material_volume = materials_info["stock-volume"]
    end
    material_volume = material_volume - recipe.volume

    bundle_item(recipe.noun, info.logbook)
  end

  -- Cleanup leftover material
  if bone_carving then
    fput("get my " .. materials_info["stock-name"] .. " stack")
    if DRC.left_hand() or DRC.right_hand() then
      DRCI.stow_hands()
      if not S.retain_crafting_materials then
        DRCI.dispose_trash(materials_info["stock-name"] .. " stack", S.worn_trashcan, S.worn_trashcan_verb)
      end
    end
  elseif scrap then
    local noun_idx = material_volume + 1
    local rock_noun = MATERIAL_NOUNS[noun_idx] or "rock"
    DRCI.dispose_trash(
      materials_info["stock-name"] .. " " .. rock_noun,
      S.worn_trashcan, S.worn_trashcan_verb)
  end

  if room_name():find("Workshop") then go_door() end
end

--- Shape wood items.
local function shape_items(info, materials_info, item, quantity)
  DRCM.ensure_copper_on_hand(S.cash_on_hand or 10000, S.settings, S.hometown)
  local recipe, items_per_stock, spare_stock, scrap = find_recipe_data(materials_info, item, quantity)

  for count = 0, quantity - 1 do
    if items_per_stock == 0 or (count % items_per_stock) == 0 then
      -- Dispose or retain spare lumber from previous cycle
      if count > 0 and spare_stock then
        if not S.retain_crafting_materials then
          DRCI.dispose_trash(materials_info["stock-name"] .. " lumber",
            S.worn_trashcan, S.worn_trashcan_verb)
        else
          DRC.bput("stow feet", "You put", "What", "Stow what?")
          DRC.bput("get my " .. materials_info["stock-name"] .. " lumber", "What were", "You get")
          DRC.bput("get my other " .. materials_info["stock-name"] .. " lumber", "What were", "You get")
          DRC.bput("combine", "combine")
          local lh = DRC.left_hand()
          local rh = DRC.right_hand()
          if lh then stow_tool(lh) end
          if rh then stow_tool(rh) end
        end
      end

      if count > 0 then
        if room_name():find("Workshop") then go_door() end
        local wait_start = os.time()
        while not current_room_id() and os.time() - wait_start < 10 do pause(0.5) end
      end

      -- Ensure enough lumber volume
      DRC.bput("get my " .. materials_info["stock-name"] .. " lumber", "What were", "You get")
      while true do
        local cnt_r = DRC.bput("count my " .. materials_info["stock-name"] .. " lumber",
          "You count.*%d+", "I could not")
        local cnt = tonumber(cnt_r:match("(%d+)")) or 0
        if cnt >= recipe.volume then break end
        DRCT.order_item(info["stock-room"], materials_info["stock-number"])
        DRC.bput("combine", "combine")
      end
      stow_tool("lumber")

      buy_parts(recipe.part, info["part-room"])
      DRCC.find_shaping_room(S.hometown, S.engineering_room)
    end

    DRC.wait_for_script_to_complete("shape", {
      "log",
      tostring(recipe.chapter),
      recipe.name,
      materials_info["stock-name"],
      recipe.noun,
    })

    local result = DRC.bput("read my engineering logbook", table.unpack(READ_LOGBOOK_PATTERNS))
    local remaining = tonumber(result:match("You must bundle and deliver (%d+) more"))
    if remaining then
      if count + 1 + remaining ~= quantity then break end
    end
  end

  -- Cleanup lumber
  if scrap and not S.retain_crafting_materials then
    DRCI.dispose_trash(materials_info["stock-name"] .. " lumber", S.worn_trashcan, S.worn_trashcan_verb)
  end
  if S.retain_crafting_materials then
    local lh = DRC.left_hand()
    local rh = DRC.right_hand()
    if lh then stow_tool(lh) end
    if rh then stow_tool(rh) end
    if scrap then
      DRC.bput("stow feet", "You put", "What", "Stow what?")
      DRC.bput("get my " .. materials_info["stock-name"] .. " lumber", "What were", "You get")
      DRC.bput("get my other " .. materials_info["stock-name"] .. " lumber", "What were", "You get")
      DRC.bput("combine", "combine")
      lh = DRC.left_hand()
      rh = DRC.right_hand()
      if lh then stow_tool(lh) end
      if rh then stow_tool(rh) end
    end
  end

  if room_name():find("Workshop") then go_door() end
end

--- Sew cloth or leather items.
local function sew_items(info, materials_info, recipe, quantity)
  DRCM.ensure_copper_on_hand(S.cash_on_hand or 5000, S.settings, S.hometown)

  -- Count existing cloth in bag
  local existing = 0
  local get_r = DRC.bput(
    "get " .. materials_info["stock-name"] .. " cloth from my " .. S.bag,
    "What were", "You get")
  if get_r:find("You get") then
    while true do
      local get2 = DRC.bput(
        "get " .. materials_info["stock-name"] .. " cloth from my " .. S.bag,
        "What were", "You get")
      if not get2:find("You get") then break end
      DRC.bput(
        "combine " .. materials_info["stock-name"] .. " cloth with " .. materials_info["stock-name"] .. " cloth",
        "You combine")
    end
    local cnt_r = DRC.bput("count my " .. materials_info["stock-name"] .. " cloth",
      "You count out %d+ yards")
    existing = tonumber(cnt_r:match("You count out (%d+) yards")) or 0
  end

  local stock_needed = math.ceil((quantity * recipe.volume - existing) / 10.0)
  if stock_needed < 0 then stock_needed = 0 end
  order_fabric(info["stock-room"], stock_needed, materials_info["stock-number"],
    materials_info["stock-name"] .. " cloth")
  order_parts(recipe.part, quantity)

  DRCC.find_sewing_room(S.hometown, S.outfitting_room)

  for count = 0, quantity - 1 do
    DRC.wait_for_script_to_complete("sew", {
      "log", "sewing",
      tostring(recipe.chapter),
      recipe.name,
      materials_info["stock-name"],
      recipe.noun,
    })
    local result = DRC.bput("read my outfitting logbook", table.unpack(READ_LOGBOOK_PATTERNS))
    local remaining = tonumber(result:match("You must bundle and deliver (%d+) more"))
    if remaining then
      if count + 1 + remaining ~= quantity then break end
    end
  end

  local leftover = (quantity * recipe.volume) % 10 ~= 0
  if leftover and not S.retain_crafting_materials then
    DRCI.dispose_trash(materials_info["stock-name"] .. " cloth", S.worn_trashcan, S.worn_trashcan_verb)
  end
  if S.retain_crafting_materials then
    local lh = DRC.left_hand()
    local rh = DRC.right_hand()
    if lh then stow_tool(lh) end
    if rh then stow_tool(rh) end
  end
end

--- Knit yarn items (chapter 5 tailoring).
local function knit_items(info, materials_info, recipe, quantity)
  DRCM.ensure_copper_on_hand(S.cash_on_hand or 5000, S.settings, S.hometown)

  -- Count existing yarn in bag
  local existing = 0
  local get_r = DRC.bput("get yarn from my " .. S.bag, "What were", "You get")
  if get_r:find("You get") then
    while true do
      local get2 = DRC.bput("get yarn from my " .. S.bag, "What were", "You get")
      if not get2:find("You get") then break end
      DRC.bput(
        "combine " .. materials_info["stock-name"] .. " yarn with " .. materials_info["stock-name"] .. " yarn",
        "You combine")
    end
    local cnt_r = DRC.bput("count my yarn", "You count out %d+ yards")
    existing = tonumber(cnt_r:match("You count out (%d+) yards")) or 0
  end

  local stock_needed = math.ceil((quantity * recipe.volume - existing) / 100.0)
  if stock_needed < 0 then stock_needed = 0 end
  order_fabric(info["stock-room"], stock_needed, materials_info["stock-number"], "yarn")

  DRCC.find_sewing_room(S.hometown, S.outfitting_room)

  for count = 0, quantity - 1 do
    DRC.wait_for_script_to_complete("sew", {
      "log", "knitting",
      tostring(recipe.chapter),
      recipe.name,
      materials_info["stock-name"],
      recipe.noun,
    })
    local result = DRC.bput("read my outfitting logbook", table.unpack(READ_LOGBOOK_PATTERNS))
    local remaining = tonumber(result:match("You must bundle and deliver (%d+) more"))
    if remaining then
      if count + 1 + remaining ~= quantity then break end
    end
  end

  local leftover = (quantity * recipe.volume) % 10 ~= 0
  if leftover and not S.retain_crafting_materials then
    -- Use knit stock name from info if provided, else use materials_info
    local knit_name = info["knit-stock-name"] or materials_info["stock-name"]
    DRCI.dispose_trash(knit_name .. " yarn", S.worn_trashcan, S.worn_trashcan_verb)
  end
  if S.retain_crafting_materials then
    local lh = DRC.left_hand()
    local rh = DRC.right_hand()
    if lh then stow_tool(lh) end
    if rh then stow_tool(rh) end
  end
end

--- Brew remedies (alchemy).
local function remedy_items(info, _materials_info, recipe, quantity)
  DRCM.ensure_copper_on_hand(S.cash_on_hand or 5000, S.settings, S.hometown)

  -- Gather/buy herbs
  count_combine_rem(info["stock-room"], quantity, recipe.herb1, recipe.herb1_stock)

  local herb2_needed
  if not recipe.herb2 then
    herb2_needed = "na"
  else
    count_combine_rem(info["stock-room"], quantity, recipe.herb2, recipe.herb2_stock, true)
    herb2_needed = recipe.herb2
  end

  DRCT.walk_to(S.alchemy_room)

  local leftovers = 0
  for _ = 1, quantity do
    DRC.wait_for_script_to_complete("remedy", {
      "remedies",
      tostring(recipe.chapter),
      recipe.name,
      recipe.herb1,
      herb2_needed,
      info.catalyst or "",
      recipe.container or "",
      recipe.noun,
    })

    if not DRCI.get_item(info.logbook .. " logbook") then
      respond("[workorders] Failed to get " .. info.logbook .. " logbook for bundling remedy")
      break
    end

    local result = DRC.bput("bundle my " .. recipe.noun .. " with logbook",
      "You notate", "You put", "You notice the workorder", "The work order requires items of a higher quality")

    if result:find("You notice the workorder") then
      -- Item has stacks — split and use the 5-use portion
      stow_tool(DRC.right_hand() or "")
      DRC.bput("Mark my " .. recipe.noun .. " at 5", "You measure")
      DRC.bput("Break my " .. recipe.noun, "You carefully")
      local cnt_r = DRC.bput("count my first " .. recipe.noun, "You count out %d+ uses remaining%.")
      local cnt = tonumber(cnt_r:match("You count out (%d+) uses remaining%.")) or 0
      if cnt == 5 then
        if not DRCI.put_away_item("second " .. recipe.noun) then
          respond("[workorders] Failed to stow second " .. recipe.noun)
        end
      else
        if not DRCI.put_away_item("first " .. recipe.noun) then
          respond("[workorders] Failed to stow first " .. recipe.noun)
        end
      end
      leftovers = leftovers + 1
      bundle_item(recipe.noun, info.logbook)

    elseif result:find("You notate") or result:find("You put") then
      if not DRCI.put_away_item("logbook") then
        respond("[workorders] Failed to stow logbook after bundling remedy")
      end

    elseif result:find("higher quality") then
      respond("[workorders] Work order requires higher quality items. Disposing and stopping.")
      DRCI.dispose_trash(recipe.noun, S.worn_trashcan, S.worn_trashcan_verb)
      if not S.retain_crafting_materials then
        if recipe.herb1 then
          while DRCI.exists(recipe.herb1) do
            DRCI.dispose_trash(recipe.herb1, S.worn_trashcan, S.worn_trashcan_verb)
          end
        end
        if recipe.herb2 then
          while DRCI.exists(recipe.herb2) do
            DRCI.dispose_trash(recipe.herb2, S.worn_trashcan, S.worn_trashcan_verb)
          end
        end
      end
      local lh = DRC.left_hand()
      local rh = DRC.right_hand()
      if lh then stow_tool(lh) end
      if rh then stow_tool(rh) end
      break
    end
  end

  -- Dispose leftover split-remedy pieces
  for _ = 1, leftovers do
    DRCI.dispose_trash(recipe.noun, S.worn_trashcan, S.worn_trashcan_verb)
  end

  if S.retain_crafting_materials then return end

  -- Dispose leftover herbs
  if recipe.herb1 then
    while DRCI.exists(recipe.herb1) do
      DRCI.dispose_trash(recipe.herb1, S.worn_trashcan, S.worn_trashcan_verb)
    end
  end
  if recipe.herb2 then
    while DRCI.exists(recipe.herb2) do
      DRCI.dispose_trash(recipe.herb2, S.worn_trashcan, S.worn_trashcan_verb)
    end
  end
end

--- Enchant sigil-based items.
local function enchanting_items(info, _materials_info, recipe, quantity)
  local tally = 0
  local sigil_quantity = quantity

  DRCM.ensure_copper_on_hand(S.cash_on_hand or 20000, S.settings, S.hometown)

  -- Check each sigil slot (up to 4)
  local sigil_slots = {
    { name = recipe.enchant_stock1_name, stock = recipe.enchant_stock1 },
    { name = recipe.enchant_stock2_name, stock = recipe.enchant_stock2 },
    { name = recipe.enchant_stock3_name, stock = recipe.enchant_stock3 },
    { name = recipe.enchant_stock4_name, stock = recipe.enchant_stock4 },
  }

  for slot_idx, slot in ipairs(sigil_slots) do
    if not slot.name then break end

    -- Calculate quantity needed (multiply for duplicate sigil types)
    local sq = quantity
    if slot_idx == 2 and slot.name == sigil_slots[1].name then
      sq = sq * 2
    end
    if slot_idx == 3 then
      local match_count = 0
      for i = 1, 2 do
        if sigil_slots[i].name == slot.name then match_count = match_count + 1 end
      end
      sq = sq * (match_count + 1)
    end
    if slot_idx == 4 then
      local match_count = 0
      for i = 1, 3 do
        if sigil_slots[i].name == slot.name then match_count = match_count + 1 end
      end
      sq = sq * (match_count + 1)
    end

    if not check_for_existing_sigil(slot.name, slot.stock, sq, S.bag, S.belt, info) then
      tally = tally + 1
    end
  end

  if tally >= 1 then
    respond("[workorders] Missing " .. tally .. " required sigil type(s) for enchanting")
    return
  end

  -- Check enchanting component (the item to enchant)
  if recipe.item then
    local noun = recipe.noun:match("(%S+)$") or recipe.noun
    local have_count = DRCI.count_items_in_container(noun, S.bag) or 0
    if have_count < quantity then
      local need = quantity - have_count
      respond("[workorders] Need " .. need .. " more enchanting components")
      order_enchant(info["stock-room"], need, recipe.item, S.bag, S.belt)
    end
  end

  -- Check recipe parts
  if recipe.part then
    for _, p in ipairs(recipe.part) do
      local pnoun = p:match("(%S+)$") or p
      local have_count = DRCI.count_items_in_container(pnoun, S.bag) or 0
      if have_count < quantity then
        local need = quantity - have_count
        respond("[workorders] Need " .. need .. " more parts: " .. p)
        order_parts({ pnoun }, need)
      end
    end
  end

  -- Check fount
  fount_check(info["tool-room"], info.fount, quantity, S.bag, S.bag_items, S.belt)

  DRCI.stow_hands()

  DRCC.find_enchanting_room(S.hometown, S.enchanting_room)

  for count = 0, quantity - 1 do
    DRC.wait_for_script_to_complete("enchant", {
      tostring(recipe.chapter),
      recipe.name,
      recipe.noun,
    })

    local product
    if recipe.name:find("fount") then
      product = "fount"
    else
      product = recipe.noun:match("(%S+)$") or recipe.noun
    end

    bundle_item(product, info.logbook)

    local result = DRC.bput("read my enchanting logbook", table.unpack(READ_LOGBOOK_PATTERNS))
    local remaining = tonumber(result:match("You must bundle and deliver (%d+) more"))
    if remaining then
      if count + 1 + remaining ~= quantity then break end
    end
  end
end

-------------------------------------------------------------------------------
-- Main work_order orchestrator
-------------------------------------------------------------------------------

local function work_order(discipline, do_repair, do_turnin)
  S.settings     = get_settings()
  S.worn_trashcan      = S.settings.worn_trashcan
  S.worn_trashcan_verb = S.settings.worn_trashcan_verb
  S.bag          = S.settings.crafting_container or "backpack"
  S.bag_items    = S.settings.crafting_items_in_container or {}
  S.hometown     = S.settings.force_crafting_town or S.settings.hometown or "Crossing"
  S.use_own_ingot_type = S.settings.use_own_ingot_type
  S.deed_own_ingot     = S.settings.deed_own_ingot
  S.carving_type = S.settings.carving_workorder_material_type or "stone"
  S.min_items    = S.settings.workorder_min_items or 1
  S.max_items    = S.settings.workorder_max_items or 10
  S.recipe_overrides   = S.settings.workorder_recipes or {}
  S.cash_on_hand = S.settings.workorder_cash_on_hand
  -- craft_max_mindstate: Lich5 used 0-34 scale; Revenant DRSkill.getlearning() is 0-19
  -- Default to 19 (mind lock) if not set
  S.craft_max_mindstate = S.settings.craft_max_mindstate or 19
  S.retain_crafting_materials = S.settings.retain_crafting_materials
  S.workorders_repair       = S.settings.workorders_repair
  S.workorders_repair_own_tools = S.settings.workorders_repair_own_tools
  S.workorders_override_store   = S.settings.workorders_override_store
  local workorders_materials    = S.settings.workorders_materials or {}

  -- Register proper-repair flag (triggers when tool repair skill fires)
  Flags.add("proper-repair", "Your excellent training in the ways of tool repair")

  -- Optionally heal before starting
  if S.settings.workorders_force_heal then
    DRC.wait_for_script_to_complete("safe-room", { "force" })
  end

  -- Load data
  local crafting_data = get_data("crafting")
  local recipes_data  = get_data("recipes")

  -- Resolve discipline data (weaponsmithing shares blacksmithing data)
  local info = crafting_data[discipline] and crafting_data[discipline][S.hometown]
  if discipline == "weaponsmithing" then
    info = crafting_data.blacksmithing and crafting_data.blacksmithing[S.hometown]
  end

  if not info then
    respond("[workorders] No crafting settings found for discipline: " .. discipline .. " in " .. S.hometown)
    return
  end

  -- Build eligible recipe list
  local all_recipes = (recipes_data and recipes_data.crafting_recipes) or {}
  local recipes = {}
  if S.recipe_overrides[discipline] then
    local overrides = S.recipe_overrides[discipline]
    for _, r in ipairs(all_recipes) do
      local type_match = r.type and r.type:lower():find(discipline:lower())
      if type_match then
        for _, oname in ipairs(overrides) do
          if r.name and r.name:lower():find(oname:lower()) then
            recipes[#recipes + 1] = r
            break
          end
        end
      end
    end
  else
    for _, r in ipairs(all_recipes) do
      local type_match = r.type and r.type:lower():find(discipline:lower())
      if type_match and r.work_order then
        recipes[#recipes + 1] = r
      end
    end
  end

  -- Filter carving to specified material type
  if discipline == "carving" then
    local filtered = {}
    for _, r in ipairs(recipes) do
      if r.material == S.carving_type then filtered[#filtered + 1] = r end
    end
    recipes = filtered
  end

  if #recipes == 0 and not do_repair then
    respond("[workorders] No recipes found for discipline: " .. discipline)
    return
  end

  -- Load deeds data
  local deeds_data = crafting_data.deeds and crafting_data.deeds[S.hometown]
  if deeds_data then
    S.deeds_room   = deeds_data.room
    S.deeds_number = deeds_data.medium_number
  end

  -- Determine skill, tools, belt, craft method, and materials per discipline
  local skill = ""
  local tools = {}
  local craft_method = nil
  local materials_info = nil

  if discipline == "blacksmithing" or discipline == "weaponsmithing" then
    materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.metal_type]
    skill = "Forging"
    tools = S.settings.forging_tools or {}
    S.belt = S.settings.forging_belt
    if S.use_own_ingot_type then
      craft_method = forge_items_with_own_ingot
    else
      craft_method = forge_items
    end

  elseif discipline == "tailoring" then
    skill = "Outfitting"
    S.outfitting_room = S.settings.outfitting_room
    tools = S.settings.outfitting_tools or {}
    S.belt = S.settings.outfitting_belt

    -- method determined per item (sew vs knit), set after work order request
    craft_method = nil

  elseif discipline == "shaping" then
    materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.wood_type]
    skill = "Engineering"
    S.engineering_room = S.settings.engineering_room
    tools = S.settings.shaping_tools or {}
    S.belt = S.settings.engineering_belt
    craft_method = shape_items

  elseif discipline == "carving" then
    if S.carving_type == "bone" then
      materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.bone_type]
    else
      materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.stone_type]
    end
    skill = "Engineering"
    S.engineering_room = S.settings.engineering_room
    tools = S.settings.carving_tools or {}
    S.belt = S.settings.engineering_belt
    craft_method = carve_items

  elseif discipline == "remedies" then
    skill = "Alchemy"
    S.alchemy_room = S.settings.alchemy_room
    tools = S.settings.alchemy_tools or {}
    S.belt = S.settings.alchemy_belt
    craft_method = remedy_items

  elseif discipline == "artificing" then
    skill = "Enchanting"
    S.enchanting_room = S.settings.enchanting_room
    tools = S.settings.enchanting_tools or {}
    S.belt = S.settings.enchanting_belt
    craft_method = enchanting_items

  else
    respond("[workorders] No discipline found: " .. discipline)
    return
  end

  -- Repair-only mode
  if do_repair then
    repair_items(info, tools)
    return
  end

  -- Check mindstate cap before starting
  if skill ~= "" and DRSkill.getlearning(skill) > S.craft_max_mindstate then
    respond(string.format(
      "[workorders] Exiting — %s learning rate (%d) exceeds max (%d)",
      skill, DRSkill.getlearning(skill), S.craft_max_mindstate))
    return
  end

  -- Request work order
  local item_name, quantity = request_work_order(
    recipes, info["npc-rooms"], info.npc, info.npc_last_name,
    discipline, info.logbook,
    type(S.settings.workorder_diff) == "table"
      and S.settings.workorder_diff[discipline]
       or S.settings.workorder_diff)

  if not item_name then return end

  -- Find the matching recipe
  local item = nil
  for _, r in ipairs(recipes) do
    if r.name == item_name then item = r; break end
  end

  if not item then
    respond("[workorders] Recipe not found for ordered item: " .. item_name)
    return
  end

  -- For tailoring: determine sew vs knit based on chapter
  if discipline == "tailoring" then
    if item.chapter == 5 then
      materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.knit_type]
      craft_method = knit_items
    elseif item.chapter then
      materials_info = crafting_data.stock and crafting_data.stock[workorders_materials.fabric_type]
      craft_method = sew_items
    else
      respond("[workorders] Unknown chapter for tailoring item: " .. tostring(item.name))
      return
    end
  end

  -- Turn-in mode: grab items already on hand and bundle them
  if do_turnin then
    for _ = 1, quantity do
      DRCI.get_item(item.noun, S.settings.default_container)
      bundle_item(item.noun, info.logbook)
    end
  elseif craft_method then
    craft_method(info, materials_info, item, quantity)
  else
    respond("[workorders] No craft method resolved for " .. discipline .. " — cannot craft")
    return
  end

  complete_work_order(info)

  if S.workorders_repair then
    repair_items(info, tools)
  end
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------

local args = parse_args()
if args then
  local ok, err = pcall(function()
    work_order(args.discipline, args.repair, args.turnin)
  end)
  if not ok then
    respond("[workorders] Error: " .. tostring(err))
  end
end

-- Cleanup
Flags.delete("proper-repair")
