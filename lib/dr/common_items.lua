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

--- Check if an item is in either hand (Lich5 compatibility alias for in_hands).
-- @param item string Item name
-- @return boolean
function M.in_hand(item)
    return M.in_hands(item)
end

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

--- Stow an item into its default container (STORE command).
-- Equivalent to Lich5's DRCI.stow_item?
-- @param item string Item name
-- @return boolean true on success
function M.stow_item(item)
  return M.put_away_item(item, nil)
end

--- Give an item to a target (NPC or player).
-- Equivalent to Lich5's DRCI.give_item?
-- For NPC repair shops the response is immediate; player-to-player offers
-- are handled via retry (GIVE it again / already has an outstanding offer).
-- @param target string Target name (NPC or player)
-- @param item string|nil Item to give (nil = give whatever is held)
-- @return boolean true if the target accepted
function M.give_item(target, item)
  local cmd
  if item then
    cmd = "give " .. M.item_ref(item) .. " to " .. target
  else
    cmd = "give " .. target
  end

  local result = DRC.bput(cmd,
    "has accepted your offer",
    "your ticket and are handed back",
    "Please don't lose this ticket!",
    "You hand .* gives you back a repair ticket",
    "You hand .* your ticket and are handed back",
    "I don't repair those here",
    "There isn't a scratch on that",
    "give me a few more moments",
    "I will not repair something that isn't broken",
    "I can't fix those",
    "has declined the offer",
    "Your offer to .* has expired",
    "You may only have one outstanding offer",
    "What is it you're trying to give",
    "Lucky for you!  That isn't damaged!",
    "GIVE it again",
    "give it to me again",
    "already has an outstanding offer")

  if result:find("GIVE it again") or result:find("give it to me again") then
    if waitrt then waitrt() end
    return M.give_item(target, item)
  end
  if result:find("already has an outstanding offer") then
    pause(5)
    return M.give_item(target, item)
  end

  return result:find("has accepted your offer") ~= nil
      or result:find("your ticket and are handed back") ~= nil
      or result:find("Please don't lose this ticket!") ~= nil
      or result:find("gives you back a repair ticket") ~= nil
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

--- Check if a worn item is currently being worn (uses tap command).
-- @param item string Item name
-- @return boolean
function M.wearing(item)
  if not item then return false end
  local result = M.tap(item)
  return result:find("wearing") ~= nil
end

--- Check if an item exists in inventory (optional container scope).
-- @param item string Item name
-- @param container string|nil Container to look inside, or nil for general inventory
-- @return boolean
function M.exists(item, container)
  if not item then return false end
  if container then
    return M.inside(item, container)
  end
  local result = M.tap(item)
  return not (result:find("I could not find") or result:find("What were you referring to"))
end

--- Count boxes across all configured picking containers.
-- Checks picking_box_source, pick.picking_box_sources, pick.blacklist_container,
-- pick.too_hard_container from settings.
-- @param settings table Settings table with picking config
-- @return number Total box count
function M.count_all_boxes(settings)
  if not settings then return 0 end

  -- Gather all container names to check
  local seen = {}
  local containers = {}

  local function add(c)
    if type(c) == "table" then
      for _, v in ipairs(c) do add(v) end
    elseif type(c) == "string" and c ~= "" and not seen[c] then
      seen[c] = true
      containers[#containers + 1] = c
    end
  end

  add(settings.picking_box_source)
  if settings.pick then
    add(settings.pick.picking_box_sources)
    add(settings.pick.blacklist_container)
    add(settings.pick.too_hard_container)
  end

  local total = 0
  for _, container in ipairs(containers) do
    -- Rummage container for boxes (box/strongbox/etc.)
    local result = DRC.bput("rummage /I my " .. container,
      "but there is nothing in there like that",
      "looking for .* and see",
      "While it's closed", "I could not find",
      "That would accomplish nothing")
    if result:find("looking for") then
      -- Count items in the rummage result
      local item_text = result:match("looking for .* and see (.+)")
      if item_text then
        -- Count by splitting on commas/and
        local count = 0
        for _ in item_text:gmatch("[^,]+") do count = count + 1 end
        total = total + count
      end
    end
  end
  return total
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

-------------------------------------------------------------------------------
-- Lockpicking helpers
-------------------------------------------------------------------------------

--- Box material+noun patterns used by rummage /B results.
M.BOX_NOUNS = {
  "box", "caddy", "casket", "chest", "coffer", "crate", "skippet", "strongbox", "trunk",
}

--- Get list of box items in a container using rummage /B.
-- Returns adj+noun strings like "deobar strongbox", "iron chest".
-- @param container string Container to rummage
-- @return table Array of box item strings
function M.get_box_list_in_container(container)
  if not container then return {} end

  local result = DRC.bput("rummage /B my " .. container,
    "but there is nothing in there like that",
    "looking for .* and see",
    "While it's closed",
    "I could not find",
    "You feel about",
    "That would accomplish nothing")

  if result:find("You feel about") then
    if DRC and DRC.release_invisibility then DRC.release_invisibility() end
    return M.get_box_list_in_container(container)
  end

  if not result:find("looking for") then return {} end

  local text = result:match("looking for .* and see (.+)%.")
  if not text then return {} end

  -- Parse each item, stripping "a/an/some" article prefixes
  local items = DRC.list_to_array(text)
  local boxes = {}
  for _, item in ipairs(items) do
    local clean = item:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", "")
    -- Normalize ironwood -> iron (Lich5 compatibility)
    clean = clean:gsub("ironwood", "iron"):match("^%s*(.-)%s*$")
    if clean ~= "" then
      boxes[#boxes + 1] = clean
    end
  end
  return boxes
end

--- Count how many more lockpicks a lockpick container (ring/stacker) can hold.
-- Uses the APPRAISE QUICK command on the container.
-- @param container string Lockpick container name
-- @return number Number of additional lockpicks the container can accept (0 = full)
function M.count_lockpick_container(container)
  if not container then return 0 end

  local result = DRC.bput("appraise " .. M.item_ref(container) .. " quick",
    "it appears to be full",
    "it might hold an additional %d+",
    "%d+ lockpicks would probably fit",
    "I could not find",
    "What were you referring to")
  if waitrt then waitrt() end

  local count = result:match("(%d+)")
  return tonumber(count) or 0
end

--- Get a list of items in a container using look or rummage.
-- @param container string Container to inspect
-- @param verb string "look" or "rummage" (default "rummage")
-- @return table Array of item short-description strings (articles stripped)
function M.get_item_list(container, verb)
  if not container then return {} end
  verb = (verb or "rummage"):lower()

  if verb:sub(1, 1) == "l" then
    -- LOOK IN container
    local result = DRC.bput("look in " .. M.item_ref(container),
      "In the .* you see",
      "That is already open",
      "That is closed",
      "There is nothing in there",
      "I could not find")

    if result:find("I could not find") or result:find("That is closed")
        or result:find("nothing in there") then
      return {}
    end
    if result:find("That is already open") then
      result = DRC.bput("look in " .. M.item_ref(container),
        "In the .* you see", "There is nothing in there", "I could not find")
    end

    local contents = result:match("[Yy]ou see (.+)%.")
    if not contents then return {} end

    local arr = DRC.list_to_array(contents)
    local out = {}
    for _, item in ipairs(arr) do
      out[#out + 1] = item:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", ""):match("^%s*(.-)%s*$")
    end
    return out
  else
    -- RUMMAGE container
    local result = DRC.bput("rummage " .. M.item_ref(container),
      "You rummage through .* and see",
      "but there is nothing in there",
      "While it's closed",
      "I could not find",
      "You feel about",
      "That would accomplish nothing")

    if not result:find("You rummage") then return {} end

    local contents = result:match("You rummage through .* and see (.+)%.")
    if not contents then return {} end

    local arr = DRC.list_to_array(contents)
    local out = {}
    for _, item in ipairs(arr) do
      out[#out + 1] = item:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", ""):match("^%s*(.-)%s*$")
    end
    return out
  end
end

return M
