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

--- Check if the current anvil is clean, and clean it if not.
-- Handles clutter on the anvil by dragging/removing items.
-- @return boolean true if anvil is clean and ready
function M.clean_anvil()
  local result = DRC.bput("look on anvil",
    M.LOOK_ANVIL_NOT_FOUND, M.LOOK_ANVIL_CLEAN, "anvil you see")
  if result:find("clean and ready") then return true end
  if result:find("could not find") then return false end
  -- Has stuff on it — try to clean
  local clean_result = DRC.bput("clean anvil", "You drag the", "remove them yourself")
  if clean_result:find("drag") then
    fput("clean anvil")
    if pause then pause() end
    if waitrt then waitrt() end
  else
    -- Items belong to someone else or need manual removal
    -- Try to get the last item noun and bucket it
    local items_match = result:match("anvil you see (.+)%.")
    if items_match then
      local clutter = items_match:match("(%S+)$")
      if clutter then
        local get_result = DRC.bput("get " .. clutter .. " from anvil",
          "You get", "is not yours")
        if get_result:find("not yours") then
          fput("clean anvil")
          fput("clean anvil")
        elseif get_result:find("You get") then
          DRC.bput("put " .. clutter .. " in bucket", "You drop")
        end
      end
    end
  end
  return true
end

--- Check if the crucible is empty, and empty it if not.
-- Handles molten metal (tilt) and clutter (get + dispose).
-- @return boolean true if crucible is empty
function M.empty_crucible()
  local result = DRC.bput("look in cruc",
    M.LOOK_CRUCIBLE_NOT_FOUND, M.LOOK_CRUCIBLE_EMPTY,
    M.LOOK_CRUCIBLE_MOLTEN, "crucible you see")
  if result:find("nothing in there") then return true end
  if result:find("could not find") then return false end
  if result:find("molten") then
    fput("tilt crucible")
    fput("tilt crucible")
    return M.empty_crucible()
  end
  -- Has items — parse and dispose
  local items_match = result:match("crucible you see (.+)%.")
  if items_match then
    -- Split on ", " and " and " separators, extract noun from each
    local parts = {}
    for part in items_match:gsub(" and ", ", "):gmatch("[^,]+") do
      part = part:match("^%s*(.-)%s*$") -- trim
      if part ~= "" then
        -- Strip article (some/a/an) and get the noun
        local noun = part:match("^%a+%s+(.+)$") or part
        noun = DRC and DRC.get_noun and DRC.get_noun(noun) or noun:match("(%S+)$")
        if noun then
          parts[#parts + 1] = noun
        end
      end
    end
    for _, junk in ipairs(parts) do
      if DRCI and DRCI.get_item_unsafe then
        DRCI.get_item_unsafe(junk, "crucible")
      end
      if DRCI and DRCI.dispose_trash then
        DRCI.dispose_trash(junk)
      end
    end
    return M.empty_crucible()
  end
  return false
end

--- Find an empty crucible room.
-- Checks current room first, then walks through town crucible rooms.
-- Also cleans the anvil after finding a crucible.
-- @param hometown string Hometown name
function M.find_empty_crucible(hometown)
  -- Check if there's already a crucible in this room
  local tap_result = DRC.bput("tap crucible", "I could not", "You tap.*crucible")
  if tap_result:find("You tap") then
    local pcs_clear = true
    if DRRoom and DRRoom.pcs and DRRoom.group_members then
      local others = {}
      for _, pc in ipairs(DRRoom.pcs()) do
        local dominated = false
        for _, gm in ipairs(DRRoom.group_members()) do
          if pc == gm then dominated = true; break end
        end
        if not dominated then others[#others + 1] = pc end
      end
      pcs_clear = #others == 0
    end
    if pcs_clear and M.empty_crucible() then
      M.clean_anvil()
      return true
    end
  end

  -- Walk to town crucible rooms
  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local bs = data["blacksmithing"] and data["blacksmithing"][hometown]
  if not bs then
    respond("[DRCC] No blacksmithing data for " .. tostring(hometown))
    return false
  end

  local crucibles = bs["crucibles"]
  local idle_room = bs["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(crucibles, idle_room, function()
      local pcs_clear = true
      if DRRoom and DRRoom.pcs and DRRoom.group_members then
        local others = {}
        for _, pc in ipairs(DRRoom.pcs()) do
          local dominated = false
          for _, gm in ipairs(DRRoom.group_members()) do
            if pc == gm then dominated = true; break end
          end
          if not dominated then others[#others + 1] = pc end
        end
        pcs_clear = #others == 0
      end
      return pcs_clear and M.empty_crucible()
    end)
  elseif crucibles and crucibles[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(crucibles[1])
  end

  M.clean_anvil()
  return true
end

--- Find an anvil room.
-- Checks current room first, then walks through town anvil rooms.
-- Also empties the crucible after finding an anvil.
-- @param hometown string Hometown name
function M.find_anvil(hometown)
  -- Check if there's already an anvil in this room
  local tap_result = DRC.bput("tap anvil", "I could not", "You tap.*anvil")
  if tap_result:find("You tap") then
    local pcs_clear = true
    if DRRoom and DRRoom.pcs and DRRoom.group_members then
      local others = {}
      for _, pc in ipairs(DRRoom.pcs()) do
        local dominated = false
        for _, gm in ipairs(DRRoom.group_members()) do
          if pc == gm then dominated = true; break end
        end
        if not dominated then others[#others + 1] = pc end
      end
      pcs_clear = #others == 0
    end
    if pcs_clear and M.clean_anvil() then
      M.empty_crucible()
      return true
    end
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local bs = data["blacksmithing"] and data["blacksmithing"][hometown]
  if not bs then
    respond("[DRCC] No blacksmithing data for " .. tostring(hometown))
    return false
  end

  local anvils = bs["anvils"]
  local idle_room = bs["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(anvils, idle_room, function()
      local pcs_clear = true
      if DRRoom and DRRoom.pcs and DRRoom.group_members then
        local others = {}
        for _, pc in ipairs(DRRoom.pcs()) do
          local dominated = false
          for _, gm in ipairs(DRRoom.group_members()) do
            if pc == gm then dominated = true; break end
          end
          if not dominated then others[#others + 1] = pc end
        end
        pcs_clear = #others == 0
      end
      return pcs_clear and M.clean_anvil()
    end)
  elseif anvils and anvils[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(anvils[1])
  end

  M.empty_crucible()
  return true
end

--- Find a grindstone room.
-- Checks current room first, then walks through town grindstone rooms.
-- @param hometown string Hometown name
function M.find_grindstone(hometown)
  -- Check if there's already a grindstone here
  local tap_result = DRC.bput("tap grindstone", "I could not", "You tap.*grindstone")
  if not tap_result:find("could not") then
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local bs = data["blacksmithing"] and data["blacksmithing"][hometown]
  if not bs then
    respond("[DRCC] No blacksmithing data for " .. tostring(hometown))
    return false
  end

  local grindstones = bs["grindstones"]
  local idle_room = bs["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(grindstones, idle_room)
  elseif grindstones and grindstones[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(grindstones[1])
  end
  return true
end

--- Find a spinning wheel room.
-- @param hometown string Hometown name
function M.find_wheel(hometown)
  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local tl = data["tailoring"] and data["tailoring"][hometown]
  if not tl then
    respond("[DRCC] No tailoring data for " .. tostring(hometown))
    return false
  end

  local wheels = tl["spinning-rooms"]
  local idle_room = tl["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(wheels, idle_room)
  elseif wheels and wheels[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(wheels[1])
  end
  return true
end

--- Find a sewing room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_sewing_room(hometown, override)
  if override then
    if DRCT and DRCT.walk_to then DRCT.walk_to(override) end
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local tl = data["tailoring"] and data["tailoring"][hometown]
  if not tl then
    respond("[DRCC] No tailoring data for " .. tostring(hometown))
    return false
  end

  local rooms = tl["sewing-rooms"]
  local idle_room = tl["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(rooms, idle_room)
  elseif rooms and rooms[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(rooms[1])
  end
  return true
end

--- Find a shaping room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_shaping_room(hometown, override)
  if override then
    if DRCT and DRCT.walk_to then DRCT.walk_to(override) end
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local sh = data["shaping"] and data["shaping"][hometown]
  if not sh then
    respond("[DRCC] No shaping data for " .. tostring(hometown))
    return false
  end

  local rooms = sh["shaping-rooms"]
  local idle_room = sh["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(rooms, idle_room)
  elseif rooms and rooms[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(rooms[1])
  end
  return true
end

--- Find a loom room.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_loom_room(hometown, override)
  if override then
    if DRCT and DRCT.walk_to then DRCT.walk_to(override) end
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local tl = data["tailoring"] and data["tailoring"][hometown]
  if not tl then
    respond("[DRCC] No tailoring data for " .. tostring(hometown))
    return false
  end

  local rooms = tl["loom-rooms"]
  local idle_room = tl["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(rooms, idle_room)
  elseif rooms and rooms[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(rooms[1])
  end
  return true
end

--- Find an enchanting/brazier room.
-- Checks current room first for an empty brazier, then walks through town rooms.
-- @param hometown string Hometown name
-- @param override number|nil Specific room to walk to
function M.find_enchanting_room(hometown, override)
  if override then
    if DRCT and DRCT.walk_to then DRCT.walk_to(override) end
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local art = data["artificing"] and data["artificing"][hometown]
  if not art then
    respond("[DRCC] No artificing data for " .. tostring(hometown))
    return false
  end

  local rooms = art["brazier-rooms"]
  local idle_room = art["idle-room"]
  if DRCT and DRCT.find_sorted_empty_room then
    DRCT.find_sorted_empty_room(rooms, idle_room, function()
      local pcs_clear = true
      if DRRoom and DRRoom.pcs and DRRoom.group_members then
        local others = {}
        for _, pc in ipairs(DRRoom.pcs()) do
          local dominated = false
          for _, gm in ipairs(DRRoom.group_members()) do
            if pc == gm then dominated = true; break end
          end
          if not dominated then others[#others + 1] = pc end
        end
        pcs_clear = #others == 0
      end
      return pcs_clear and M.clean_brazier()
    end)
  elseif rooms and rooms[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(rooms[1])
  end
  return true
end

--- Find a press/grinder room.
-- @param hometown string Hometown name
function M.find_press_grinder_room(hometown)
  -- Check if there's already a grinder here
  local tap_result = DRC.bput("tap grinder", "I could not", "You tap.*grinder")
  if not tap_result:find("could not") then
    return true
  end

  local data = get_data and get_data("crafting") or nil
  if not data then
    respond("[DRCC] No crafting data available")
    return false
  end
  local rem = data["remedies"] and data["remedies"][hometown]
  if not rem then
    respond("[DRCC] No remedies data for " .. tostring(hometown))
    return false
  end

  local rooms = rem["press-grinder-rooms"]
  if rooms and rooms[1] and DRCT and DRCT.walk_to then
    DRCT.walk_to(rooms[1])
  end
  return true
end

-------------------------------------------------------------------------------
-- Enchanting workflow
-------------------------------------------------------------------------------

--- Order enchanting supplies (sigil-scrolls / founts).
-- Walks to the stock room and orders the specified quantity.
-- @param stock_room number Room ID of the enchanting supply shop
-- @param stock_needed number How many to order
-- @param stock_number number|string Order number at the shop
-- @param bag string Crafting bag name
-- @param belt table|nil Belt config
function M.order_enchant(stock_room, stock_needed, stock_number, bag, belt)
  for _ = 1, stock_needed do
    if DRCT and DRCT.order_item then
      DRCT.order_item(stock_room, stock_number)
    end
    if DRC and DRC.left_hand then
      M.stow_crafting_item(DRC.left_hand(), bag, belt)
    end
    if DRC and DRC.right_hand then
      M.stow_crafting_item(DRC.right_hand(), bag, belt)
    end
    -- If both hands still full after stowing, skip remaining orders
    if DRC and DRC.left_hand and DRC.right_hand
       and DRC.left_hand() and DRC.right_hand() then
      -- hands full, continue to next iteration anyway (Ruby uses next unless)
    end
  end
end

--- Check and refill a fount (enchanting liquid container).
-- Taps to find the fount, analyzes remaining uses, and reorders if low.
-- @param stock_room number Room ID of the supply shop
-- @param stock_needed number How many founts to order if needed
-- @param stock_number number|string Order number at the shop
-- @param quantity number How many uses are needed
-- @param bag string Crafting bag name
-- @param bag_items table Bag item list
-- @param belt table|nil Belt config
function M.fount(stock_room, stock_needed, stock_number, quantity, bag, bag_items, belt)
  local tap_result = DRC.bput("tap my fount",
    "You tap .* inside your .*", "You tap .*your .*", "I could not find")

  if tap_result:find("inside your") or (tap_result:find("You tap") and not tap_result:find("could not")) then
    -- Fount is in bag or on person
    local analyze_result = DRC.bput("analyze my fount",
      "approximately (%d+) uses remaining")
    local uses = tonumber(analyze_result:match("(%d+)")) or 0
    if uses < (quantity + 1) then
      M.get_crafting_item("fount", bag, bag_items, belt)
      if DRCT and DRCT.dispose then DRCT.dispose("fount") end
      if DRCI and DRCI.stow_hands then DRCI.stow_hands() end
      M.order_enchant(stock_room, stock_needed, stock_number, bag, belt)
    end
  elseif tap_result:find("could not") then
    -- Try tapping fount on brazier
    local braz_result = DRC.bput("tap my fount on my brazier",
      "You tap .* atop a .*brazier", "I could not find")
    if braz_result:find("atop") then
      local analyze_result = DRC.bput("analyze my fount on my brazier",
        "approximately (%d+) uses remaining")
      local uses = tonumber(analyze_result:match("(%d+)")) or 0
      if uses < quantity then
        if DRCI and DRCI.stow_hands then DRCI.stow_hands() end
        M.order_enchant(stock_room, stock_needed, stock_number, bag, belt)
      end
    else
      -- No fount found at all — order new
      M.order_enchant(stock_room, stock_needed, stock_number, bag, belt)
    end
  end
end

--- Check if the enchanting brazier is clean, and clean it if not.
-- @return boolean true if brazier is clean
function M.clean_brazier()
  local result = DRC.bput("look on brazier",
    "There is nothing on there", "On the .*brazier you see")
  if result:find("nothing on there") then return true end
  if result:find("you see") then
    local clean_result = DRC.bput("clean brazier",
      "You prepare to clean off the brazier",
      "There is nothing",
      "The brazier is not currently lit")
    if clean_result:find("prepare to clean") then
      DRC.bput("clean brazier",
        "a massive ball of flame jets forward")
    end
    M.empty_brazier()
    return true
  end
  return false
end

--- Empty all items from the enchanting brazier.
-- Gets each item and disposes of it.
function M.empty_brazier()
  local result = DRC.bput("look on brazier",
    "On the .*brazier you see .*%.", "There is nothing")
  if result:find("nothing") then return end

  local items_str = result:match("brazier you see (.+)%.")
  if not items_str then return end

  -- Split on " and " to get individual items
  local items = {}
  for part in items_str:gsub(" and ", "\n"):gmatch("[^\n]+") do
    part = part:match("^%s*(.-)%s*$") -- trim
    if part ~= "" then
      -- Get the last word (noun)
      local noun = part:match("(%S+)$")
      if noun then items[#items + 1] = noun end
    end
  end

  for _, item in ipairs(items) do
    DRC.bput("get " .. item .. " from brazier", "You get")
    if DRCT and DRCT.dispose then
      DRCT.dispose(item)
    end
  end
end

--- Check if enough sigil-scrolls of a type exist in the bag.
-- Orders more if purchasable, warns if not.
-- @param sigil string Sigil name (e.g., "abolition")
-- @param stock_number number|string Order number for the sigil
-- @param quantity number How many are needed
-- @param bag string Crafting bag name
-- @param belt table|nil Belt config
-- @param info table Crafting info with 'stock-room' key
-- @return boolean true if enough sigils are available
function M.check_for_existing_sigil(sigil, stock_number, quantity, bag, belt, info)
  local tmp_count = 0
  if DRCI and DRCI.count_items_in_container then
    tmp_count = DRCI.count_items_in_container(sigil .. " sigil-scroll", bag) or 0
    tmp_count = tonumber(tmp_count) or 0
  end

  if tmp_count >= quantity then
    return true
  end

  -- Check if this is a purchasable sigil (primary or secondary)
  -- If globals for sigil patterns exist, use them
  local is_purchasable = false
  if PRIMARY_SIGILS_PATTERN and SECONDARY_SIGILS_PATTERN then
    if Regex and Regex.test then
      is_purchasable = Regex.test(PRIMARY_SIGILS_PATTERN, sigil .. " sigil")
                    or Regex.test(SECONDARY_SIGILS_PATTERN, sigil .. " sigil")
    end
  else
    -- Without pattern globals, assume purchasable if we have a stock number
    is_purchasable = (stock_number ~= nil)
  end

  if is_purchasable then
    local more = quantity - tmp_count
    M.order_enchant(info["stock-room"], more, stock_number, bag, belt)
    return true
  else
    respond("[DRCC] Not enough " .. sigil .. " sigil-scroll(s). You may need to harvest more.")
    return false
  end
end

-------------------------------------------------------------------------------
-- Metal counting
-------------------------------------------------------------------------------

--- Volume mapping for rummage size descriptors.
-- Maps the size words from rummage output to approximate volume units.
M.VOL_MAP = {
  tiny = 1, small = 2, medium = 5, large = 10, huge = 15,
}

--- Count raw metal ingots in a container by rummaging.
-- @param container string Container name to rummage in
-- @param metal_type string|nil Specific metal type to filter (nil = all)
-- @return table|nil Table of { metal = { volume, count } } or nil on error
function M.count_raw_metal(container, metal_type)
  local result = DRC.bput("rummage /M " .. container,
    "crafting materials but there is nothing in there like that",
    "While it's closed",
    "I don't know what you are referring to",
    "You feel about",
    "That would accomplish nothing",
    "looking for crafting materials and see .*%.")

  if result:find("nothing in there") then
    respond("[DRCC] No materials found.")
    return nil
  elseif result:find("closed") then
    if DRCI and DRCI.open_container then
      if not DRCI.open_container(container) then return nil end
    end
    return M.count_raw_metal(container, metal_type)
  elseif result:find("don't know") then
    respond("[DRCC] Container not found.")
    return nil
  elseif result:find("feel about") then
    respond("[DRCC] Try again when you're not invisible.")
    return nil
  elseif result:find("accomplish nothing") then
    return nil
  end

  local materials_str = result:match("crafting materials and see (.+)%.")
  if not materials_str then
    respond("[DRCC] Unexpected rummage result.")
    return nil
  end

  local h = {}
  -- Split "X and Y" into "X, Y" then split on commas
  local list_str = materials_str:gsub(" and ", ", ")
  for entry in list_str:gmatch("[^,]+") do
    entry = entry:match("^%s*(.-)%s*$") -- trim
    -- Entries look like: "a small bronze ingot" or "a tiny steel ingot"
    local words = {}
    for w in entry:gmatch("%S+") do words[#words + 1] = w end
    -- Typically: article(a/an) size_word metal_word noun(ingot)
    if #words >= 3 then
      local size_word = words[2]
      local metal = words[3]
      local volume = M.VOL_MAP[size_word] or 0
      if h[metal] then
        h[metal][1] = h[metal][1] + volume
        h[metal][2] = h[metal][2] + 1
      else
        h[metal] = { volume, 1 }
      end
    end
  end

  -- Report findings
  for k, v in pairs(h) do
    respond("[DRCC] " .. k .. " - " .. v[1] .. " volume - " .. v[2] .. " pieces")
  end

  if metal_type then
    return h[metal_type]
  end
  return h
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
