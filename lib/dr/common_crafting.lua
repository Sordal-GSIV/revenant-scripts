--- DRCC — DR Common Crafting utilities.
-- Ported from Lich5 common-crafting.rb (module DRCC).
-- Provides forge, sew, carve, enchanting action loops and tool management.
-- @module lib.dr.common_crafting
local M = {}

-------------------------------------------------------------------------------
-- Constants: bput response patterns
-------------------------------------------------------------------------------

-- Crucible
M.LOOK_CRUCIBLE_EMPTY     = "There is nothing in there"
M.LOOK_CRUCIBLE_NOT_FOUND = "I could not find"
M.LOOK_CRUCIBLE_MOLTEN    = "crucible you see some molten"

-- Anvil
M.LOOK_ANVIL_CLEAN     = "surface looks clean and ready"
M.LOOK_ANVIL_NOT_FOUND = "I could not find"

-- Book / recipe
M.BOOK_CHAPTER_TURN_SUCCESS  = "You turn"
M.BOOK_CHAPTER_DISTRACTED    = "You are too distracted"
M.BOOK_CHAPTER_ALREADY       = "is already turned"
M.BOOK_STUDY_SUCCESS         = "Roundtime"

-- Belt / tool access
M.BELT_UNTIE_SUCCESS   = "You remove"
M.BELT_UNTIE_NOT_FOUND = "Untie what"
M.BELT_UNTIE_WOUNDED   = "Your wounds hinder"

-- Get crafting tool
M.GET_SUCCESS     = "You get"
M.GET_ALREADY     = "You are already"
M.GET_NOT_FOUND   = "What were you referring to"
M.GET_PICKUP      = "You pick up"
M.GET_HEAVY       = "can't quite lift it"
M.GET_TIED        = "You should untie"

-- Put bag
M.PUT_BAG_SUCCESS     = "You put your"
M.PUT_BAG_TUCK        = "You tuck"
M.PUT_BAG_NOT_FOUND   = "What were you referring to"
M.PUT_BAG_TOO_BIG     = "is too .* to fit"
M.PUT_BAG_NO_ROOM     = "There's no room"
M.PUT_BAG_COMBINE     = "You combine"

-- Belt tie
M.TIE_BELT_SUCCESS = "you attach"
M.TIE_BELT_WOUNDED = "Your wounds hinder"

-- Repair
M.REPAIR_SUCCESS    = "Roundtime"
M.REPAIR_NOT_NEEDED = "not damaged enough"
M.REPAIR_ENGAGED    = "You cannot do that while engaged"
M.REPAIR_CONFUSED   = "cannot figure out how"

-- Bundle
M.BUNDLE_SUCCESS    = "You notate the"
M.BUNDLE_EXPIRED    = "This work order has expired"
M.BUNDLE_QUALITY    = "The work order requires items of a higher quality"
M.BUNDLE_WRONG_TYPE = "That isn't the correct type of item"
M.BUNDLE_NOT_HOLDING = "You need to be holding"

-- Consumable
M.CONSUMABLE_GET_SUCCESS   = "You get"
M.CONSUMABLE_GET_NOT_FOUND = "What were"

-- Tongs
M.ADJUST_TONGS_SHOVEL  = "You lock the tongs"
M.ADJUST_TONGS_TONGS   = "With a yank you fold the shovel"
M.ADJUST_TONGS_CANNOT  = "You cannot adjust"
M.ADJUST_TONGS_UNKNOWN = "You have no idea how"

--- Parts that cannot be purchased from crafting shops.
M.PARTS_CANNOT_PURCHASE = {
  "sufil", "blue flower", "muljin", "belradi", "dioica", "hulnik", "aloe",
  "eghmok", "lujeakave", "yelith", "cebi", "blocil", "hulij", "nuloe",
  "hisan", "gem", "pebble", "ring", "gwethdesuan", "brazier", "burin",
  "any", "ingot", "mechanism",
}

-- Track tongs state module-wide
local tongs_status = nil

-------------------------------------------------------------------------------
-- Tool get/stow helpers
-------------------------------------------------------------------------------

--- Get a crafting tool, checking belt first, then bag.
-- @param name string Tool name
-- @param bag string Crafting bag name
-- @param bag_items table|nil Array of item names in the bag
-- @param belt table|nil Belt config { name=string, items=table }
-- @param skip_exit boolean|nil If true, don't halt on missing tool
-- @return boolean|nil true on success, nil on missing tool
function M.get_crafting_item(name, bag, bag_items, belt, skip_exit)
  if waitrt then waitrt() end

  -- Try belt first
  if belt and belt.items then
    for _, item in ipairs(belt.items) do
      if name:find(item, 1, true) or item:find(name, 1, true) then
        local result = DRC.bput("untie my " .. name .. " from my " .. belt.name,
          M.BELT_UNTIE_SUCCESS, "You are already", M.BELT_UNTIE_NOT_FOUND, M.BELT_UNTIE_WOUNDED)
        if Regex.test("You remove|You are already", result) then
          return true
        elseif result:find("wounds hinder") then
          -- TODO: safe-room recovery
          respond("[DRCC] Wounded, cannot untie " .. name)
          return nil
        end
        break
      end
    end
  end

  -- Build get command
  local cmd = "get my " .. name
  if bag_items then
    for _, bi in ipairs(bag_items) do
      if bi == name then
        cmd = cmd .. " from my " .. bag
        break
      end
    end
  end

  local result = DRC.bput(cmd,
    M.GET_SUCCESS, M.GET_ALREADY, "What do you", M.GET_NOT_FOUND,
    M.GET_PICKUP, M.GET_HEAVY, M.GET_TIED)

  if Regex.test("What|referring", result) then
    pause(2)
    if DRCI and DRCI.in_hands and DRCI.in_hands(name) then return true end
    respond("[DRCC] Missing crafting item: " .. name)
    if skip_exit then return nil end
    respond("[DRCC] Cannot continue crafting without required item.")
    return nil
  elseif result:find("quite lift") then
    return M.get_crafting_item(name, bag, bag_items, belt, skip_exit)
  elseif result:find("untie") then
    DRC.bput("untie my " .. name, "You remove", "You untie", "Untie what")
    return true
  end

  return true
end

--- Stow a crafting tool to belt or bag.
-- @param name string Tool name
-- @param bag string Crafting bag name
-- @param belt table|nil Belt config
-- @return boolean
function M.stow_crafting_item(name, bag, belt)
  if not name then return true end
  if waitrt then waitrt() end

  -- Try belt first
  if belt and belt.items then
    for _, item in ipairs(belt.items) do
      if name:find(item, 1, true) or item:find(name, 1, true) then
        local result = DRC.bput("tie my " .. name .. " to my " .. belt.name,
          M.TIE_BELT_SUCCESS, M.TIE_BELT_WOUNDED)
        if result:find("attach") then return true end
        -- Wounded — fall through to bag stow
        break
      end
    end
  end

  local result = DRC.bput("put my " .. name .. " in my " .. bag,
    M.PUT_BAG_TUCK, M.PUT_BAG_SUCCESS, M.PUT_BAG_NOT_FOUND,
    M.PUT_BAG_TOO_BIG, "Weirdly", M.PUT_BAG_NO_ROOM,
    "You can't put that there", M.PUT_BAG_COMBINE)

  if Regex.test("too .* to fit|Weirdly|no room", result) then
    fput("stow my " .. name)
  elseif result:find("can't put that there") then
    fput("put my " .. name .. " in my other " .. bag)
    return false
  end

  return true
end

-------------------------------------------------------------------------------
-- Recipe helpers
-------------------------------------------------------------------------------

--- Look up a recipe by name from a recipe list.
-- @param recipes table Array of recipe tables (each with 'name' key)
-- @param item_name string Name to search for
-- @return table|nil Matching recipe
function M.recipe_lookup(recipes, item_name)
  local matches = {}
  for _, recipe in ipairs(recipes) do
    if recipe.name and recipe.name:lower():find(item_name:lower(), 1, true) then
      matches[#matches + 1] = recipe
    end
  end
  if #matches == 0 then
    respond("[DRCC] No recipe matches: " .. item_name)
    return nil
  end
  if #matches == 1 then return matches[1] end
  -- Try exact match
  for _, recipe in ipairs(matches) do
    if recipe.name == item_name then return recipe end
  end
  respond("[DRCC] Multiple recipes match '" .. item_name .. "', using first.")
  return matches[1]
end

--- Find and study a recipe in a book (v2 — supports master crafting books).
-- When master_book is provided, navigates to the book_type section first,
-- then delegates to find_recipe. Without master_book, assumes the book is
-- already in hand and proceeds directly.
-- @param chapter number|string Chapter number
-- @param recipe_name string Recipe name to search for
-- @param master_book string|nil Master crafting book noun (nil = individual "book" in hand)
-- @param book_type string|nil Section name for master books (e.g., "weaponsmithing")
function M.find_recipe2(chapter, recipe_name, master_book, book_type)
  local book = master_book or "book"
  if master_book and book_type then
    -- Navigate to the smithing-type section of the master book first
    DRC.bput("turn my " .. master_book .. " to " .. book_type,
      M.BOOK_CHAPTER_TURN_SUCCESS, M.BOOK_CHAPTER_ALREADY,
      M.BOOK_CHAPTER_DISTRACTED, "I could not find", "Turn what")
  end
  M.find_recipe(chapter, recipe_name, book)
end

--- Find and study a recipe in a book.
-- @param chapter number|string Chapter number
-- @param match_string string Pattern to match in recipe listing
-- @param book string|nil Book noun (default "book")
function M.find_recipe(chapter, match_string, book)
  book = book or "book"
  DRC.bput("turn my " .. book .. " to chapter " .. tostring(chapter),
    M.BOOK_CHAPTER_TURN_SUCCESS, M.BOOK_CHAPTER_DISTRACTED, M.BOOK_CHAPTER_ALREADY)
  local result = DRC.bput("read my " .. book, "Page %d+:")
  local page = result:match("Page (%d+):%s*.*" .. match_string)
  if page then
    DRC.bput("turn my " .. book .. " to page " .. page, "You turn", "already on page")
    DRC.bput("study my " .. book, M.BOOK_STUDY_SUCCESS)
  end
end

-------------------------------------------------------------------------------
-- Crafting room finders
-------------------------------------------------------------------------------

--- Find an empty crucible room.
-- @param hometown string Hometown name
function M.find_empty_crucible(hometown)
  -- TODO: integrate with crafting data files
  respond("[DRCC] find_empty_crucible: stub for " .. tostring(hometown))
end

--- Check if the current anvil is clean.
-- @return boolean
function M.clean_anvil()
  local result = DRC.bput("look on anvil",
    M.LOOK_ANVIL_NOT_FOUND, M.LOOK_ANVIL_CLEAN, "anvil you see")
  if result:find("clean and ready") then return true end
  if result:find("could not find") then return false end
  -- Has stuff on it — try to clean
  DRC.bput("clean anvil", "You drag the", "remove them yourself")
  return true
end

--- Check if the crucible is empty.
-- @return boolean
function M.empty_crucible()
  local result = DRC.bput("look in cruc",
    M.LOOK_CRUCIBLE_NOT_FOUND, M.LOOK_CRUCIBLE_EMPTY, "crucible you see")
  if result:find("nothing in there") then return true end
  if result:find("could not find") then return false end
  if result:find("molten") then
    fput("tilt crucible")
    fput("tilt crucible")
    return M.empty_crucible()
  end
  -- Has items — try to clean them out
  -- TODO: parse items and dispose
  return false
end

--- Find a sewing room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_sewing_room(hometown, override)
  if override then
    DRCT.walk_to(override)
  else
    -- TODO: integrate with crafting data files
    respond("[DRCC] find_sewing_room: stub for " .. tostring(hometown))
  end
end

--- Find a shaping room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_shaping_room(hometown, override)
  if override then
    DRCT.walk_to(override)
  else
    respond("[DRCC] find_shaping_room: stub for " .. tostring(hometown))
  end
end

--- Find a loom room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_loom_room(hometown, override)
  if override then
    DRCT.walk_to(override)
  else
    respond("[DRCC] find_loom_room: stub for " .. tostring(hometown))
  end
end

--- Find an anvil room.
-- @param hometown string Hometown name
function M.find_anvil(hometown)
  respond("[DRCC] find_anvil: stub for " .. tostring(hometown))
end

--- Find a grindstone room.
-- @param hometown string Hometown name
function M.find_grindstone(hometown)
  respond("[DRCC] find_grindstone: stub for " .. tostring(hometown))
end

--- Find an enchanting/brazier room.
-- @param hometown string Hometown name
-- @param override number|nil
function M.find_enchanting_room(hometown, override)
  if override then
    DRCT.walk_to(override)
  else
    respond("[DRCC] find_enchanting_room: stub for " .. tostring(hometown))
  end
end

--- Find a spinning wheel room.
-- @param hometown string
function M.find_wheel(hometown)
  respond("[DRCC] find_wheel: stub for " .. tostring(hometown))
end

-------------------------------------------------------------------------------
-- Consumable management
-------------------------------------------------------------------------------

--- Check and restock consumables (oil, wire brush, etc.).
-- @param name string Consumable name
-- @param room number Shop room ID
-- @param number number|string Order number
-- @param bag string Crafting bag
-- @param bag_items table Bag item list
-- @param belt table|nil Belt config
-- @param min_count number Minimum uses required (default 3)
function M.check_consumables(name, room, number, bag, bag_items, belt, min_count)
  min_count = min_count or 3
  local current_room = Room and Room.id

  local result = DRC.bput("get my " .. name .. " from my " .. bag,
    M.CONSUMABLE_GET_SUCCESS, M.CONSUMABLE_GET_NOT_FOUND)

  if result:find("You get") then
    local count_result = DRC.bput("count my " .. name,
      "has (%d+) uses remaining", "You count out (%d+) yards")
    local count = tonumber(count_result:match("(%d+)")) or 0
    if count < min_count then
      if DRCT and DRCT.dispose then DRCT.dispose(name) end
      M.check_consumables(name, room, number, bag, bag_items, belt, min_count)
      return
    end
    M.stow_crafting_item(name, bag, belt)
  else
    if DRCT and DRCT.order_item then
      DRCT.order_item(room, number)
    end
    M.stow_crafting_item(name, bag, belt)
  end

  if current_room and DRCT and DRCT.walk_to then
    DRCT.walk_to(current_room)
  end
end

-------------------------------------------------------------------------------
-- Tool repair
-------------------------------------------------------------------------------

--- Repair own tools with wire brush and oil.
-- @param info table Crafting info (finisher-room, finisher-number, etc.)
-- @param tools table|string Tool name(s) to repair
-- @param bag string Crafting bag
-- @param bag_items table Bag items
-- @param belt table|nil Belt config
function M.repair_own_tools(info, tools, bag, bag_items, belt)
  if type(tools) == "string" then tools = { tools } end
  if #tools == 0 then return end

  for _, tool_name in ipairs(tools) do
    M.get_crafting_item(tool_name, bag, bag_items, belt, true)
    if not (DRC and DRC.right_hand and DRC.right_hand()) then
      goto continue
    end

    -- Wire brush
    M.get_crafting_item("wire brush", bag, bag_items, belt)
    local result = DRC.bput("rub my " .. tool_name .. " with my wire brush",
      M.REPAIR_SUCCESS, M.REPAIR_NOT_NEEDED, M.REPAIR_ENGAGED, M.REPAIR_CONFUSED)
    M.stow_crafting_item("wire brush", bag, belt)

    if result:find("not damaged") then
      M.stow_crafting_item(tool_name, bag, belt)
      goto continue
    end

    -- Oil
    if not result:find("engaged") and not result:find("figure out") then
      M.get_crafting_item("oil", bag, bag_items, belt)
      DRC.bput("pour my oil on my " .. tool_name, M.REPAIR_SUCCESS, M.REPAIR_NOT_NEEDED)
      M.stow_crafting_item("oil", bag, belt)
    end

    M.stow_crafting_item(tool_name, bag, belt)
    ::continue::
  end
end

-------------------------------------------------------------------------------
-- Tongs management
-------------------------------------------------------------------------------

--- Get and adjust tongs to the desired configuration.
-- @param usage string "shovel", "tongs", "reset shovel", or "reset tongs"
-- @param bag string Crafting bag
-- @param bag_items table Bag items
-- @param belt table|nil Belt config
-- @param adjustable_tongs boolean|nil Whether tongs are adjustable
-- @return boolean true if tongs are in the desired configuration
function M.get_adjust_tongs(usage, bag, bag_items, belt, adjustable_tongs)
  if usage == "reset shovel" or usage == "reset tongs" then
    tongs_status = nil
    adjustable_tongs = true
    local target = usage:match("reset (%a+)")
    return M.get_adjust_tongs(target, bag, bag_items, belt, adjustable_tongs)
  end

  if usage == "shovel" then
    if tongs_status == "shovel" then
      if not (DRCI and DRCI.in_hands and DRCI.in_hands("tongs")) then
        M.get_crafting_item("tongs", bag, bag_items, belt)
      end
      return true
    end
    if not adjustable_tongs then return false end
    if not (DRCI and DRCI.in_hands and DRCI.in_hands("tongs")) then
      M.get_crafting_item("tongs", bag, bag_items, belt)
    end
    local result = DRC.bput("adjust my tongs",
      M.ADJUST_TONGS_SHOVEL, M.ADJUST_TONGS_TONGS, M.ADJUST_TONGS_CANNOT, M.ADJUST_TONGS_UNKNOWN)
    if Regex.test("cannot|no idea", result) then
      respond("[DRCC] Tongs are not adjustable.")
      M.stow_crafting_item("tongs", bag, belt)
      return false
    elseif result:find("yank") then
      -- Now in tongs mode, adjust again to shovel
      DRC.bput("adjust my tongs", M.ADJUST_TONGS_SHOVEL)
    end
    tongs_status = "shovel"
    return true

  elseif usage == "tongs" then
    if not (DRCI and DRCI.in_hands and DRCI.in_hands("tongs")) then
      M.get_crafting_item("tongs", bag, bag_items, belt)
    end
    if tongs_status == "tongs" then return true end
    if not adjustable_tongs then return false end
    local result = DRC.bput("adjust my tongs",
      M.ADJUST_TONGS_SHOVEL, M.ADJUST_TONGS_TONGS, M.ADJUST_TONGS_CANNOT, M.ADJUST_TONGS_UNKNOWN)
    if Regex.test("cannot|no idea", result) then
      respond("[DRCC] Tongs are not adjustable.")
      return false
    elseif result:find("lock") then
      -- Now in shovel mode, adjust again to tongs
      DRC.bput("adjust my tongs", M.ADJUST_TONGS_TONGS)
    end
    tongs_status = "tongs"
    return true
  end

  return false
end

-------------------------------------------------------------------------------
-- Logbook bundling
-------------------------------------------------------------------------------

--- Bundle a crafted item with a logbook.
-- @param logbook string Logbook type (e.g., "forging")
-- @param noun string Item noun
-- @param container string Crafting container
function M.logbook_item(logbook, noun, container)
  if DRCI and DRCI.get_item then
    DRCI.get_item(logbook .. " logbook")
  end
  local result = DRC.bput("bundle my " .. noun .. " with my logbook",
    M.BUNDLE_SUCCESS, M.BUNDLE_EXPIRED, M.BUNDLE_QUALITY,
    M.BUNDLE_WRONG_TYPE, M.BUNDLE_NOT_HOLDING)

  if Regex.test("expired|quality|correct type", result) then
    if DRCI and DRCI.dispose_trash then DRCI.dispose_trash(noun) end
  elseif result:find("holding") then
    if DRCI and DRCI.get_item and DRCI.get_item(noun, container) then
      local r2 = DRC.bput("bundle my " .. noun .. " with my logbook",
        M.BUNDLE_SUCCESS, M.BUNDLE_EXPIRED, M.BUNDLE_QUALITY, M.BUNDLE_WRONG_TYPE)
      if Regex.test("expired|quality|correct type", r2) then
        if DRCI and DRCI.dispose_trash then DRCI.dispose_trash(noun) end
      end
    end
  end

  if DRCI and DRCI.put_away_item then
    DRCI.put_away_item(logbook .. " logbook", container)
  end
end

-------------------------------------------------------------------------------
-- Crafting cost calculation
-------------------------------------------------------------------------------

--- Estimate the copper cost of a crafting project.
-- @param recipe table Recipe data
-- @param hometown string Hometown name
-- @param parts table|nil Array of part names
-- @param quantity number Number to craft
-- @param material table|nil Stock material data
-- @return number Estimated copper cost
function M.crafting_cost(recipe, hometown, parts, quantity, material)
  local total = 0

  if material then
    if material["stock-name"] and (material["stock-name"] == "alabaster"
        or material["stock-name"] == "granite"
        or material["stock-name"] == "marble") then
      total = total + (material["stock-value"] or 0) * quantity
    elseif material["stock-volume"] and material["stock-volume"] > 0 then
      local stock_to_order = math.ceil((recipe.volume / material["stock-volume"]) * quantity)
      total = total + stock_to_order * (material["stock-value"] or 0)
    end
  end

  if parts then
    for _, part in ipairs(parts) do
      local dominated = false
      for _, skip in ipairs(M.PARTS_CANNOT_PURCHASE) do
        if part == skip then dominated = true; break end
      end
      if not dominated then
        -- TODO: look up stock value from crafting data
        total = total + 1000 * quantity  -- placeholder
      end
    end
  end

  total = total + 1000  -- consumables overhead

  -- Adjust for hometown currency
  local currency = DRCM and DRCM.hometown_currency and DRCM.hometown_currency(hometown) or "Kronars"
  if currency == "Lirums" then
    total = math.ceil(total * 0.8)
  elseif currency == "Dokoras" then
    total = math.ceil(total * 0.7216)
  end

  return total
end

return M
