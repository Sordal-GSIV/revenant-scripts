--- DRCI — DR Common Items manipulation.
-- Ported from Lich5 common-items.rb (module DRCI).
-- Provides stow, get, wear, remove, dispose, container management.
-- @module lib.dr.common_items
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Trash receptacle nouns found in game rooms.
M.TRASH_STORAGE = {
  "arms", "barrel", "basin", "basket", "bin", "birdbath", "bucket",
  "chamberpot", "gloop", "hole", "log", "puddle", "statue", "stump",
  "tangle", "tree", "turtle", "urn", "gelapod",
}

--- Patterns indicating successful drop/trash
M.DROP_TRASH_SUCCESS = {
  "You drop", "^You put", "You spread .* on the ground",
  "smashing it to bits", "As you open your hand to release",
  "You toss .* at the domesticated gelapod",
  "You feed .* a bit warily to the domesticated gelapod",
}

--- Patterns indicating failed drop/trash
M.DROP_TRASH_FAILURE = {
  "What were you referring to", "I could not find",
  "But you aren't holding that", "Perhaps you should be holding",
  "You're kidding, right", "You can't do that",
  "No littering", "Where do you want to put that",
}

--- Get/pickup success patterns
M.GET_ITEM_SUCCESS = {
  "You get", "You pick up", "You grab", "You accept",
}

--- Get/pickup failure patterns
M.GET_ITEM_FAILURE = {
  "What were you referring to", "I could not find",
  "You need a free hand", "But that is already in your inventory",
  "What do you want to get", "You can't pick that up",
}

--- Put away success patterns
M.PUT_AWAY_SUCCESS = {
  "^You put", "You tuck", "You place", "You slide",
  "You open .* and put", "You drop",
}

--- Put away failure patterns
M.PUT_AWAY_FAILURE = {
  "What were you referring to", "I could not find",
  "is too .* to fit", "There's no room",
  "You can't put that there", "Weirdly, you can't manage",
}

--- Wear item success patterns
M.WEAR_ITEM_SUCCESS = {
  "You put on", "You attach", "You slide .* on",
  "You work your way into", "You pull .* over",
  "You strap", "You drape", "You slip",
}

--- Wear item failure patterns
M.WEAR_ITEM_FAILURE = {
  "Wear what", "You can't wear that",
  "You are already wearing", "Remove what you're wearing first",
}

--- Remove item success patterns
M.REMOVE_ITEM_SUCCESS = {
  "You remove", "You pull .* free", "You sling",
  "You slide .* off", "You work your way out of",
  "You unbuckle", "You loosen", "You detach", "You yank",
}

--- Remove item failure patterns
M.REMOVE_ITEM_FAILURE = {
  "Remove what", "You aren't wearing that",
}

--- Tie item success patterns
M.TIE_ITEM_SUCCESS = {
  "you attach", "You tie",
}

--- Tie item failure patterns
M.TIE_ITEM_FAILURE = {
  "Tie what", "Your wounds hinder",
}

-------------------------------------------------------------------------------
-- Item reference helper
-------------------------------------------------------------------------------

--- Prefix an item name with "my " unless already prefixed or uses # ID syntax.
-- @param value string Item name
-- @return string Prefixed name
function M.item_ref(value)
  if not value then return value end
  if value:match("^my ") or value:match("^#") then
    return value
  end
  return "my " .. value
end

-------------------------------------------------------------------------------
-- Hand checking
-------------------------------------------------------------------------------

--- Check if an item is in either hand.
-- @param item string|table Item name or Item object with short_regex
-- @return boolean
function M.in_hands(item)
  if not item then return false end
  local name = type(item) == "string" and item or (item.short_name and item:short_name() or item.name)
  if not name then return false end

  local rh = DRC and DRC.right_hand and DRC.right_hand()
  local lh = DRC and DRC.left_hand and DRC.left_hand()
  if rh and rh:find(name, 1, true) then return true end
  if lh and lh:find(name, 1, true) then return true end
  return false
end

--- Check if an item is in the right hand.
-- @param item string Item name
-- @return boolean
function M.in_right_hand(item)
  if not item then return false end
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  return rh and rh:find(item, 1, true) ~= nil
end

--- Check if an item is in the left hand.
-- @param item string Item name
-- @return boolean
function M.in_left_hand(item)
  if not item then return false end
  local lh = DRC and DRC.left_hand and DRC.left_hand()
  return lh and lh:find(item, 1, true) ~= nil
end

-------------------------------------------------------------------------------
-- Get / Pick up items
-------------------------------------------------------------------------------

--- Get an item, optionally from a container.
-- @param item string Item to get
-- @param container string|nil Container to get from
-- @return boolean true on success
function M.get_item(item, container)
  if not item then return false end
  if M.in_hands(item) then return true end

  local cmd = "get " .. M.item_ref(item)
  if container then
    cmd = cmd .. " from " .. M.item_ref(container)
  end

  local all = {}
  for _, p in ipairs(M.GET_ITEM_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.GET_ITEM_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput(cmd, unpack(all))
  for _, p in ipairs(M.GET_ITEM_SUCCESS) do
    if result:find(p) then return true end
  end
  return false
end

--- Get an item only if not already held.
-- @param item string Item name
-- @return boolean
function M.get_item_if_not_held(item)
  if M.in_hands(item) then return true end
  return M.get_item(item)
end

-------------------------------------------------------------------------------
-- Put away / Stow items
-------------------------------------------------------------------------------

--- Put away an item into a container.
-- @param item string Item to put away
-- @param container string|nil Specific container (nil = default stow)
-- @return boolean true on success
function M.put_away_item(item, container)
  if not item then return false end

  local cmd
  if container then
    cmd = "put " .. M.item_ref(item) .. " in " .. M.item_ref(container)
  else
    cmd = "stow " .. M.item_ref(item)
  end

  local all = {}
  for _, p in ipairs(M.PUT_AWAY_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.PUT_AWAY_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput(cmd, unpack(all))
  for _, p in ipairs(M.PUT_AWAY_SUCCESS) do
    if result:find(p) then return true end
  end
  return false
end

--- Stow the item in a hand.
-- @param hand string "left" or "right"
-- @return boolean true on success
function M.stow_hand(hand)
  local result = DRC.bput("stow " .. hand,
    "You put", "You tuck", "Stow what", "You're not holding anything",
    "already in your inventory")
  return not (result:find("Stow what") or result:find("not holding"))
end

--- Stow both hands.
function M.stow_hands()
  M.stow_hand("right")
  M.stow_hand("left")
end

--- Lower an item to the ground.
-- @param item string Item to lower
-- @return boolean true on success
function M.lower_item(item)
  if not item then return false end
  local result = DRC.bput("lower " .. M.item_ref(item),
    "You lower", "You gently", "Lower what", "That is already")
  return result:find("You lower") ~= nil or result:find("You gently") ~= nil
end

-------------------------------------------------------------------------------
-- Wear / Remove items
-------------------------------------------------------------------------------

--- Wear an item.
-- @param item string Item to wear
-- @return boolean true on success
function M.wear_item(item)
  if not item then return false end

  local all = {}
  for _, p in ipairs(M.WEAR_ITEM_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.WEAR_ITEM_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput("wear " .. M.item_ref(item), unpack(all))
  for _, p in ipairs(M.WEAR_ITEM_SUCCESS) do
    if result:find(p) then return true end
  end
  return false
end

--- Remove a worn item.
-- @param item string Item to remove
-- @return boolean true on success
function M.remove_item(item)
  if not item then return false end

  local all = {}
  for _, p in ipairs(M.REMOVE_ITEM_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.REMOVE_ITEM_FAILURE) do all[#all + 1] = p end

  local result = DRC.bput("remove " .. M.item_ref(item), unpack(all))
  if waitrt then waitrt() end
  for _, p in ipairs(M.REMOVE_ITEM_SUCCESS) do
    if result:find(p) then return true end
  end
  return false
end

--- Untie an item from something.
-- @param item string Item to untie
-- @param from string|nil What it's tied to
-- @return boolean
function M.untie_item(item, from)
  if not item then return false end
  local cmd = "untie " .. M.item_ref(item)
  if from then cmd = cmd .. " from " .. M.item_ref(from) end
  local result = DRC.bput(cmd,
    "You remove", "You untie", "Untie what",
    "Your wounds hinder")
  return result:find("You remove") ~= nil or result:find("You untie") ~= nil
end

--- Tie an item to something.
-- @param item string Item to tie
-- @param to string What to tie to
-- @return boolean
function M.tie_item(item, to)
  if not item then return false end
  local result = DRC.bput("tie " .. M.item_ref(item) .. " to " .. M.item_ref(to),
    "you attach", "You tie", "Tie what", "Your wounds hinder")
  return result:find("attach") ~= nil or result:find("You tie") ~= nil
end

-------------------------------------------------------------------------------
-- Dispose / Trash
-------------------------------------------------------------------------------

--- Dispose of a trash item. Attempts to put in a room trashcan or drop.
-- @param item string Item to dispose
-- @param worn_trashcan string|nil Worn trashcan name
-- @param worn_trashcan_verb string|nil Verb (default "put")
function M.dispose_trash(item, worn_trashcan, worn_trashcan_verb)
  if not item then return end

  -- Try worn trashcan first
  if worn_trashcan then
    local verb = worn_trashcan_verb or "put"
    local result = DRC.bput(verb .. " " .. M.item_ref(item) .. " in " .. M.item_ref(worn_trashcan),
      "You put", "You tuck", "What were you referring to",
      "is too .* to fit", "There's no room")
    if result:find("You put") or result:find("You tuck") then return end
  end

  -- Try room trash receptacles
  for _, receptacle in ipairs(M.TRASH_STORAGE) do
    local result = DRC.bput("put " .. M.item_ref(item) .. " in " .. receptacle,
      "You put", "You drop", "You toss",
      "What were you referring to", "I could not find",
      "is too .* to fit", "There's no room",
      "You can't put that there")
    if result:find("You put") or result:find("You drop") or result:find("You toss") then
      return
    end
    if result:find("I could not find") then
      -- No such receptacle in room, try next
    end
  end

  -- Last resort: just drop it
  DRC.bput("drop " .. M.item_ref(item), "You drop", "You spread",
    "What were you referring to")
end

-------------------------------------------------------------------------------
-- Container queries
-------------------------------------------------------------------------------

--- Check if an item is inside a container.
-- @param item string Item to check for
-- @param container string Container name
-- @return boolean
function M.inside(item, container)
  local result = DRC.bput("look in " .. M.item_ref(container),
    "In the .* you see", "There is nothing in there",
    "I could not find", "That is closed")
  return result:find(item) ~= nil
end

--- Check if you have an item by looking in a container.
-- @param item string Item to find
-- @param container string|nil Container to check
-- @return boolean
function M.have_item_by_look(item, container)
  if container then
    return M.inside(item, container)
  end
  -- Check hands
  return M.in_hands(item)
end

--- Count items matching a name in a container.
-- @param item string Item name to count
-- @param container string Container to check
-- @return number Count of matching items
function M.count_items_in_container(item, container)
  local result = DRC.bput("look in " .. M.item_ref(container),
    "In the .* you see", "There is nothing in there",
    "I could not find")
  if not result:find("you see") then return 0 end

  local count = 0
  for _ in result:gmatch(item) do
    count = count + 1
  end
  return count
end

--- Open a container.
-- @param container string Container to open
-- @return boolean true if opened or already open
function M.open_container(container)
  local result = DRC.bput("open " .. M.item_ref(container),
    "You open", "That is already open",
    "What were you referring to", "It is locked")
  return result:find("You open") ~= nil or result:find("already open") ~= nil
end

--- Close a container.
-- @param container string Container to close
-- @return boolean
function M.close_container(container)
  local result = DRC.bput("close " .. M.item_ref(container),
    "You close", "That is already closed",
    "What were you referring to")
  return result:find("You close") ~= nil or result:find("already closed") ~= nil
end

--- Tap an item (returns the tap description).
-- @param item string Item to tap
-- @return string Result of tapping
function M.tap(item)
  if not item then return "" end
  return DRC.bput("tap " .. M.item_ref(item),
    "You tap", "I could not find", "What were you referring to")
end

--- Put an item away, trying container then default stow. "Unsafe" — no retry.
-- @param item string Item name
-- @param container string|nil Container
-- @param preposition string|nil Preposition (default "in"), e.g., "on"
-- @return boolean
function M.put_away_item_unsafe(item, container, preposition)
  if not item then return false end
  preposition = preposition or "in"
  local cmd
  if container then
    cmd = "put " .. M.item_ref(item) .. " " .. preposition .. " " .. M.item_ref(container)
  else
    cmd = "stow " .. M.item_ref(item)
  end
  local result = DRC.bput(cmd,
    "You put", "You tuck", "You slide", "You place",
    "What were you referring to", "is too .* to fit",
    "There's no room", "You can't put that there")
  return result:find("You put") ~= nil
      or result:find("You tuck") ~= nil
      or result:find("You slide") ~= nil
      or result:find("You place") ~= nil
end

return M
