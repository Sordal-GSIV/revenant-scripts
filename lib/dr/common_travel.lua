--- DRCT — DR Common Travel utilities.
-- Ported from Lich5 common-travel.rb (module DRCT).
-- Provides walk_to, sell/buy/order at merchants, pathfinding helpers.
-- @module lib.dr.common_travel
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Direction reversal for path reversal.
M.DIRECTION_REVERSE = {
  northeast = "southwest", southwest = "northeast",
  northwest = "southeast", southeast = "northwest",
  north     = "south",     south     = "north",
  east      = "west",      west      = "east",
  up        = "down",      down      = "up",
}

--- Sell success patterns
M.SELL_SUCCESS_PATTERNS = {
  "hands? you %d+ %a+",
}

--- Sell failure patterns
M.SELL_FAILURE_PATTERNS = {
  "I need to examine the merchandise first",
  "That's not worth anything",
  "I only deal in pelts",
  "There's folk around here that'd slit a throat for this",
}

--- Buy price patterns — matched against merchant responses
M.BUY_PRICE_PATTERNS = {
  "prepared to offer it to you for (.*) %a+s?",
  "Let me but ask the humble sum of (.*) coins",
  "it would be just (%d*) %a+s?",
  "for a (%d*) %a+s?",
  "I can let that go for%.%.%.(%d*) %a+s?",
  "cost you (%d*) %a+s?",
  "it may be yours for just (.*) %a+s?",
  "I'll give that to you for (.*) %a+s?",
  "I'll let you have it for (.*) %a+s?",
  "I ask that you give (.*) copper %a+s?",
  "it'll be (.*) %a+s?",
  "the price of (.*) coins? is all I ask",
  "tis only (.*) %a+s?",
  "That will be (.*) copper %a+s?",
  "That'll be (.*) copper %a+s?",
  "to you for (.*) %a+s?",
}

--- Buy non-price patterns
M.BUY_NON_PRICE_PATTERNS = {
  "You decide to purchase",
  "Buy what",
}

-------------------------------------------------------------------------------
-- Navigation
-------------------------------------------------------------------------------

--- Walk to a room by room ID.
-- Uses the go2 script for pathfinding. Handles obstacles and engagement.
-- @param target_room number|string Target room ID (or tag string)
-- @param restart_on_fail boolean Retry on failure (default true)
-- @return boolean true if we arrived at the target room
function M.walk_to(target_room, restart_on_fail)
  if restart_on_fail == nil then restart_on_fail = true end
  if not target_room then return false end

  -- Convert string tags to room IDs
  if type(target_room) == "string" and target_room:match("%a") then
    target_room = M.tag_to_id(target_room)
    if not target_room then return false end
  end

  local room_num = tonumber(target_room)
  if not room_num then return false end

  -- Already there?
  if Room and Room.id then
    if Room.id == room_num then return true end
  end

  -- Stand up first
  if DRC then DRC.fix_standing() end

  -- Use go2 script for navigation
  -- TODO: integrate with script runner when available
  fput("go2 " .. room_num)

  -- Basic wait loop with timeout
  local timeout = 90
  local start = os.time()
  while os.time() - start < timeout do
    pause(1)
    if Room and Room.id == room_num then
      return true
    end
  end

  -- Failed — retry if allowed
  if restart_on_fail then
    respond("[DRCT] Failed to navigate to room " .. room_num .. ", retrying.")
    return M.walk_to(room_num, false)
  end

  return Room and Room.id == room_num
end

--- Resolve a map tag to a room ID (closest match via Dijkstra).
-- @param target string Map tag to resolve
-- @return number|nil Room ID or nil
function M.tag_to_id(target)
  if not Map or not Map.list then
    respond("[DRCT] Map not available for tag lookup: " .. tostring(target))
    return nil
  end

  local start_room = Room and Room.id
  local target_list = {}

  for _, room in ipairs(Map.list) do
    if room.tags then
      for _, tag in ipairs(room.tags) do
        if tag == target then
          target_list[#target_list + 1] = room.id
          break
        end
      end
    end
  end

  if #target_list == 0 then
    respond("[DRCT] No go2 targets matching '" .. target .. "' found.")
    return nil
  end

  if start_room then
    for _, id in ipairs(target_list) do
      if id == start_room then
        respond("[DRCT] You're already here.")
        return start_room
      end
    end
  end

  -- If Dijkstra is available, find closest. Otherwise return first match.
  -- TODO: integrate with map pathfinding when available
  return target_list[1]
end

-------------------------------------------------------------------------------
-- Merchant interactions
-------------------------------------------------------------------------------

--- Sell an item at the current room's merchant.
-- @param room number Room ID of merchant
-- @param item string Item to sell
-- @return boolean true if sold
function M.sell_item(room, item)
  if DRCI and DRCI.in_hands and not DRCI.in_hands(item) then
    return false
  end
  M.walk_to(room)

  local all_patterns = {}
  for _, p in ipairs(M.SELL_SUCCESS_PATTERNS) do all_patterns[#all_patterns + 1] = p end
  for _, p in ipairs(M.SELL_FAILURE_PATTERNS) do all_patterns[#all_patterns + 1] = p end

  local result = DRC.bput("sell my " .. item, unpack(all_patterns))
  for _, p in ipairs(M.SELL_SUCCESS_PATTERNS) do
    if result:find(p) then return true end
  end
  return false
end

--- Buy an item from a merchant.
-- @param room number Room ID of merchant
-- @param item string Item to buy
function M.buy_item(room, item)
  M.walk_to(room)

  local all_patterns = {}
  for _, p in ipairs(M.BUY_PRICE_PATTERNS) do all_patterns[#all_patterns + 1] = p end
  for _, p in ipairs(M.BUY_NON_PRICE_PATTERNS) do all_patterns[#all_patterns + 1] = p end

  local result = DRC.bput("buy " .. item, unpack(all_patterns))

  -- Try to extract price and offer it
  for _, p in ipairs(M.BUY_PRICE_PATTERNS) do
    local amount = result:match(p)
    if amount then
      fput("offer " .. amount)
      return
    end
  end
end

--- Ask a merchant for an item.
-- @param room number Room ID of merchant
-- @param name string Merchant name
-- @param item string Item to ask for
-- @return boolean true if received
function M.ask_for_item(room, name, item)
  M.walk_to(room)
  local result = DRC.bput("ask " .. name .. " for " .. item,
    "hands you",
    "does not seem to know anything about that",
    "All I know about",
    "To whom are you speaking",
    "Usage: ASK")
  return result:find("hands you") ~= nil
end

--- Order an item by number from a menu.
-- @param room number Room ID of merchant
-- @param item_number number|string Order number
function M.order_item(room, item_number)
  M.walk_to(room)
  local result = DRC.bput("order " .. tostring(item_number),
    "Just order it again",
    "you don't have enough coins")
  if result:find("don't have enough coins") then return end
  DRC.bput("order " .. tostring(item_number), "takes some coins from you")
end

--- Dispose of a trash item, optionally walking to a trash room.
-- @param item string Item to dispose
-- @param trash_room number|nil Room to walk to first
-- @param worn_trashcan string|nil Worn trashcan name
-- @param worn_trashcan_verb string|nil Verb for worn trashcan
function M.dispose(item, trash_room, worn_trashcan, worn_trashcan_verb)
  if not item then return end
  if trash_room then M.walk_to(trash_room) end
  if DRCI and DRCI.dispose_trash then
    DRCI.dispose_trash(item, worn_trashcan, worn_trashcan_verb)
  else
    fput("drop my " .. item)
  end
end

-------------------------------------------------------------------------------
-- Path helpers
-------------------------------------------------------------------------------

--- Reverse a direction path.
-- @param path table Array of direction strings (full names required)
-- @return table|nil Reversed path, or nil on error
function M.reverse_path(path)
  if not path then return nil end
  local reversed = {}
  for i = #path, 1, -1 do
    local rev = M.DIRECTION_REVERSE[path[i]]
    if not rev then
      respond("[DRCT] No reverse direction found for '" .. tostring(path[i]) .. "'.")
      return nil
    end
    reversed[#reversed + 1] = rev
  end
  return reversed
end

--- Retreat from combat, delegating to DRC.retreat.
-- @param ignored_npcs table|nil
function M.retreat(ignored_npcs)
  if DRC and DRC.retreat then
    DRC.retreat(ignored_npcs)
  end
end

--- Find an empty room from a list of candidates.
-- Walks to each room and checks if PCs are present.
-- @param search_rooms table Array of room IDs
-- @param idle_room number|nil Room to wait in between searches
-- @param predicate function|nil Custom predicate (receives search_attempt)
-- @param max_search_attempts number|nil Max search cycles (default infinite)
-- @return boolean true if found an empty room
function M.find_empty_room(search_rooms, idle_room, predicate, max_search_attempts)
  max_search_attempts = max_search_attempts or 999
  local search_attempt = 0

  while search_attempt < max_search_attempts do
    search_attempt = search_attempt + 1
    respond("[DRCT] Search attempt " .. search_attempt .. " of " .. max_search_attempts)

    for _, room_id in ipairs(search_rooms) do
      M.walk_to(room_id)
      pause(0.1)

      local suitable
      if predicate then
        suitable = predicate(search_attempt)
      else
        -- Default: check that no other PCs are present
        if DRRoom and DRRoom.pcs then
          local pcs = DRRoom.pcs()
          suitable = (type(pcs) == "table" and #pcs == 0)
        else
          suitable = true -- assume OK if we can't check
        end
      end

      if suitable then return true end
    end

    -- No empty room found — wait and retry
    if idle_room and search_attempt < max_search_attempts then
      M.walk_to(idle_room)
      local wait_time = math.random(20, 40)
      respond("[DRCT] No empty room found, pausing " .. wait_time .. "s.")
      pause(wait_time)
    else
      respond("[DRCT] Failed to find an empty room, stopping search.")
      return false
    end
  end
  return false
end

--- Sort destination rooms by distance from current location.
-- @param target_list table Array of room IDs
-- @return table Sorted array of room IDs
function M.sort_destinations(target_list)
  -- TODO: integrate with Dijkstra pathfinding when Map API is available
  return target_list
end

--- Find a sorted empty room.
-- @param search_rooms table Array of room IDs
-- @param idle_room number|nil Idle waiting room
-- @param predicate function|nil Custom predicate
-- @return boolean
function M.find_sorted_empty_room(search_rooms, idle_room, predicate)
  local sorted = M.sort_destinations(search_rooms)
  return M.find_empty_room(sorted, idle_room, predicate)
end

--- Get the time (cost) to travel between two rooms.
-- @param origin number Origin room ID
-- @param destination number Destination room ID
-- @return number|nil Path cost, or nil if unreachable
function M.time_to_room(origin, destination)
  -- TODO: integrate with Map.dijkstra when available
  return nil
end

--- Get the room ID for a named target in a hometown.
-- @param hometown string Hometown name
-- @param target string Target key (e.g., "deposit", "locksmithing")
-- @return number|nil Room ID
function M.get_hometown_target_id(hometown, target)
  -- TODO: integrate with data files when available
  return nil
end

return M
