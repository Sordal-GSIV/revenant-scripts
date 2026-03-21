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
-- Uses the go2 script for pathfinding. Monitors for combat engagement,
-- locked/closed doors, and timeouts — matching Lich5 obstacle handling.
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

  -- Handle unknown room: try to orient via room description
  if Room and Room.id == nil and Map and Map.list then
    respond("[DRCT] In an unknown room, attempting to navigate to " .. room_num)
    local desc = XMLData and XMLData.room_description and XMLData.room_description:match("^%s*(.-)%s*$") or ""
    local title = XMLData and XMLData.room_title or ""
    local matches = {}
    for _, r in ipairs(Map.list) do
      if r.description and r.title then
        local desc_match = false
        if type(r.description) == "table" then
          for _, d in ipairs(r.description) do
            if d == desc then desc_match = true; break end
          end
        elseif r.description == desc then
          desc_match = true
        end
        local title_match = false
        if type(r.title) == "table" then
          for _, t in ipairs(r.title) do
            if t == title then title_match = true; break end
          end
        elseif r.title == title then
          title_match = true
        end
        if desc_match and title_match then
          matches[#matches + 1] = r
        end
      end
    end
    if #matches == 0 or #matches > 1 then
      respond("[DRCT] Failed to find a matching room from unknown location.")
      return false
    end
    local found = matches[1]
    if found.id == room_num then return true end
    if found.wayto and found.wayto[tostring(room_num)] then
      fput(found.wayto[tostring(room_num)])
      return Room and Room.id == room_num
    end
    -- Try to take one step and recurse
    if Map.findpath then
      local path = Map.findpath(found, Map[room_num])
      if path and #path > 0 then
        local way = found.wayto and found.wayto[tostring(path[1])]
        if way then fput(way) end
      end
    end
    return M.walk_to(room_num)
  end

  -- Register obstacle flags (closed shops, engagement)
  if Flags and Flags.add then
    Flags.add("travel-closed-shop",
      "The door is locked up tightly for the night",
      "You smash your nose",
      "^A servant (blocks|stops)")
    Flags.add("travel-engaged", "You are engaged")
  end

  -- Start go2 as a background script
  local script_handle
  if Script and Script.start then
    script_handle = Script.start("go2", { tostring(room_num) })
  elseif start_script then
    script_handle = start_script("go2", { tostring(room_num) }, { force = true })
  else
    fput("go2 " .. room_num)
  end

  -- Monitor loop: watch for obstacles and timeout
  local timer = os.time()
  local prev_room = (XMLData and XMLData.room_description or "") .. (XMLData and XMLData.room_title or "")

  local function script_running()
    if not script_handle then return false end
    if Script and Script.running then
      if type(Script.running) == "function" then
        return Script.running(script_handle)
      elseif type(Script.running) == "table" then
        for _, s in ipairs(Script.running) do
          if s == script_handle then return true end
        end
        return false
      end
    end
    return false
  end

  local function kill_go2()
    if not script_handle then return end
    if kill_script then
      kill_script(script_handle)
    elseif Script and Script.kill then
      Script.kill(script_handle)
    end
  end

  local function restart_go2()
    if Script and Script.start then
      return Script.start("go2", { tostring(room_num) })
    elseif start_script then
      return start_script("go2", { tostring(room_num) })
    else
      fput("go2 " .. room_num)
      return nil
    end
  end

  local ok, err = pcall(function()
    while script_running() do
      -- Check for closed/locked doors
      if Flags and Flags["travel-closed-shop"] then
        Flags.reset("travel-closed-shop")
        kill_go2()
        local door_result = DRC and DRC.bput("open door", "It is locked", "You .+", "What were") or ""
        if not door_result:find("You open") then
          restart_on_fail = false
          return
        end
        timer = os.time()
        script_handle = restart_go2()
      end

      -- Check for combat engagement
      if Flags and Flags["travel-engaged"] then
        Flags.reset("travel-engaged")
        kill_go2()
        if DRC and DRC.retreat then DRC.retreat() end
        timer = os.time()
        script_handle = restart_go2()
      end

      -- Timeout handling (90 seconds without progress)
      if os.time() - timer > 90 then
        kill_go2()
        pause(0.5)
        if not restart_on_fail then return end
        timer = os.time()
        script_handle = restart_go2()
      end

      -- Reset timer on room change or escort script running
      local cur_room = (XMLData and XMLData.room_description or "") .. (XMLData and XMLData.room_title or "")
      if cur_room ~= prev_room then
        timer = os.time()
      end
      if Script and Script.running then
        local function is_running(name)
          if type(Script.running) == "function" then return Script.running(name) end
          if type(Script.running) == "table" then
            for _, s in ipairs(Script.running) do
              if s == name then return true end
            end
          end
          return false
        end
        if is_running("escort") or is_running("bescort") then
          timer = os.time()
        end
      end
      prev_room = cur_room
      pause(0.5)
    end
  end)

  -- Clean up flags
  if Flags and Flags.delete then
    Flags.delete("travel-closed-shop")
    Flags.delete("travel-engaged")
  end

  if not ok then
    respond("[DRCT] walk_to error: " .. tostring(err))
  end

  -- If we didn't arrive, retry once
  if room_num ~= (Room and Room.id) and restart_on_fail then
    respond("[DRCT] Failed to navigate to room " .. room_num .. ", attempting again.")
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

--- Refill a lockpick container (ring/stacker) by buying lockpicks in a town.
-- Walks to the locksmithing shop for the given town, buys lockpicks one at a time,
-- and loads them onto the container.
-- @param lockpick_type string Type of lockpick to buy (e.g. "ordinary", "stout", "slim")
-- @param town string Hometown name (e.g. "Crossing", "Riverhaven")
-- @param container string Lockpick container item name
-- @param count number Number of lockpicks to buy
function M.refill_lockpick_container(lockpick_type, town, container, count)
  if not count or count < 1 then return end

  -- Town -> locksmith room ID mapping (from base-town.yaml)
  local LOCKSMITH_ROOMS = {
    ["Crossing"]     = 19125,
    ["Riverhaven"]   = 19096,
    ["Shard"]        = 9817,
    ["Ain Ghazal"]   = 13190,
    ["Hibarnhvidar"] = 13190,
    ["Muspar'i"]     = 7613,
  }

  local room_id = LOCKSMITH_ROOMS[town]
  if not room_id then
    respond("[DRCT] No locksmith location found for town '" .. tostring(town) .. "'. Skipping refill.")
    return
  end

  M.walk_to(room_id)

  if Room and Room.id ~= room_id then
    respond("[DRCT] Could not reach locksmith in '" .. town .. "'. Skipping refill.")
    return
  end

  for _ = 1, count do
    M.buy_item(room_id, lockpick_type .. " lockpick")
    -- Load the just-purchased lockpick onto the ring
    local result = DRC.bput("put my lockpick on my " .. container,
      "You put", "You slide", "You place",
      "What were you referring to", "There's no room",
      "mixing types is not allowed", "is too .* to fit")
    if result:find("mixing types") or result:find("no room") or result:find("too .* to fit") then
      respond("[DRCT] Failed to put lockpick on " .. container .. ". Stopping refill.")
      break
    end
  end

  -- Leave the shop (be polite to Thieves who need the room empty)
  DRC.fix_standing()
  local exits = Room and Room.exits
  if exits then
    for _, exit in ipairs(exits) do
      if exit == "out" then
        fput("out")
        break
      end
    end
  end
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
-- Uses Dijkstra shortest-path distances. Unreachable rooms are removed.
-- @param target_list table Array of room IDs (numbers or strings)
-- @return table Sorted array of reachable room IDs
function M.sort_destinations(target_list)
  -- Normalise to integers
  local rooms = {}
  for _, v in ipairs(target_list) do
    rooms[#rooms + 1] = tonumber(v)
  end

  if not Map or not Map.dijkstra or not Room or not Room.id then
    return rooms
  end

  local _, shortest_distances = Map.dijkstra(Room.id)
  if not shortest_distances then return rooms end

  -- Remove unreachable rooms (nil distance), keep current room
  local reachable = {}
  for _, id in ipairs(rooms) do
    if shortest_distances[id] ~= nil or id == Room.id then
      reachable[#reachable + 1] = id
    end
  end

  table.sort(reachable, function(a, b)
    local da = shortest_distances[a] or 0
    local db = shortest_distances[b] or 0
    return da < db
  end)

  return reachable
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
-- Uses Dijkstra shortest-path cost, matching Lich5's Map.dijkstra(origin, destination).
-- @param origin number Origin room ID
-- @param destination number Destination room ID
-- @return number|nil Path cost, or nil if unreachable
function M.time_to_room(origin, destination)
  if not Map or not Map.dijkstra then return nil end
  local _, shortest_paths = Map.dijkstra(origin, destination)
  if not shortest_paths then return nil end
  return shortest_paths[destination]
end

--- Get the room ID for a named target in a hometown.
-- Reads from data/dr/base-town.json (via get_data("town")).
-- @param hometown string Hometown name
-- @param target string Target key (e.g., "deposit", "locksmithing", "pawnshop", "thief_bin")
-- @return number|nil Room ID
function M.get_hometown_target_id(hometown, target)
  local town_data = get_data("town")
  if not town_data then return nil end
  local ht = town_data[hometown]
  if not ht then return nil end
  local entry = ht[target]
  if not entry then return nil end
  local id = entry.id or entry
  if type(id) == "number" then return id end
  return nil
end

return M
