--- DRCI — DR Common Items manipulation.
-- Ported from Lich5 common-items.rb (module DRCI).
-- Provides stow, get, wear, remove, dispose, container management.
-- @module lib.dr.common_items
local M = {}

-- smart_find is a global from builtins.lua; provide fallback for standalone loading
local smart_find = smart_find or function(text, pattern)
    return string.find(text, pattern) ~= nil
end

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Trash receptacle nouns found in game rooms.
M.TRASH_STORAGE = {
  "arms", "barrel", "basin", "basket", "bin", "birdbath", "bucket",
  "chamberpot", "gloop", "hole", "log", "puddle", "statue", "stump",
  "tangle", "tree", "turtle", "urn", "gelapod",
}

--- Patterns indicating successful drop/trash (7 patterns — full Lich5 parity)
M.DROP_TRASH_SUCCESS = {
  "^You drop",
  "^You put",
  "^You spread .* on the ground",
  "smashing it to bits",
  -- Item crumbles when leaves your hand, like a moonblade
  "^As you open your hand to release the",
  "^You toss .* at the domesticated gelapod",
  "^You feed .* a bit warily to the domesticated gelapod",
}

--- Patterns indicating failed drop/trash (15 patterns — full Lich5 parity)
M.DROP_TRASH_FAILURE = {
  "^What were you referring to",
  "^I could not find",
  "^But you aren't holding that",
  "^Perhaps you should be holding that first",
  "^You're kidding, right",
  "^You can't do that",
  "No littering",
  "^Where do you want to put that",
  "^You really shouldn't be loitering",
  "^You don't seem to be able to move",
  -- Cursed and unable to let go of items; find a Cleric to uncurse
  "^Oddly, when you attempt to stash it away safely",
  "^You need something in your right hand",
  "^You can't put that there",
  "^The domesticated gelapod glances warily at",  -- deeds
  "^You should empty it out, first",  -- container with items
}

--- Get/pickup success patterns (11 patterns — full Lich5 parity)
M.GET_ITEM_SUCCESS = {
  "you draw",  -- case-insensitive in Lich5; note: excludes "draw X's wounds" via negative lookahead in Ruby
  "^You get",
  "^You pick",
  "^You pluck",
  "^You slip",
  "^You scoop",
  "^You deftly remove",
  "^You are already holding",
  "^You fade in for a moment as you",
  "^You carefully lift",
  "^You carefully remove .* from the bundle",
  "^With a flick of your wrist, you stealthily unsheath",
}

--- Get/pickup failure patterns (21 patterns — full Lich5 parity)
M.GET_ITEM_FAILURE = {
  "^A magical force keeps you from grasping",
  "^You'll need both hands free",
  "^You need both hands free",
  "^You need a free hand",
  "^You can't pick that up with your hand that damaged",
  "^Your .* hand is too injured",
  "^You just can't",
  "^You stop as you realize the .* is not yours",
  "^You can't reach that from here",  -- on a mount like a flying carpet
  "^You don't seem to be able to move",
  "^You should untie",
  "^You can't do that",
  "^Get what",
  "^I could not",
  "^What were you",
  "already in your inventory",  -- wearing it
  "needs to be tended to be removed",  -- ammo lodged in you
  "push you over the item limit",  -- at item capacity
  "rapidly decays away",  -- item disappears when try to get it
  "cracks and rots away",  -- item disappears when try to get it
  "^You should stop practicing your Athletics skill before you do that",
}

--- Put away success patterns (25 patterns + SHEATH splat = ~34 total — full Lich5 parity)
--- Note: SHEATH_ITEM_SUCCESS is splatted in after definition below.
M.PUT_AWAY_SUCCESS = {
  "^You put your .* in",
  "^You hold out",
  "^You stuff",
  "^You tuck",
  "^You open your pouch and put",
  "^You guide your",  -- puppy storage
  "^You nudge your",  -- monkey storage
  -- Item crumbles when stowed, like a moonblade
  "^As you open your hand to release the",
  -- Thief binning a stolen item
  "nods toward you as your .* falls into the .* bin",
  "^You add",
  "^You rearrange",
  "^You combine the stacks",
  "^You secure",
  -- Success messages for putting item in a container OFF your person
  "^You drop",
  "^You set",
  "^You put",
  "^You carefully fit .* into your bundle",
  "^You gently set",
  -- SHEATH patterns are appended below after SHEATH_ITEM_SUCCESS definition
  "^You toss .* into",
}

--- Put away failure patterns (30 patterns — full Lich5 parity)
M.PUT_AWAY_FAILURE = {
  "^Stow what",
  "^I can't find your container for stowing things in",
  "^Please rephrase that command",
  "^What were you referring to",
  "^I could not find what you were referring to",
  "^There isn't any more room in",
  "^There's no room",
  "^(?:The|That).* too heavy to go in there",
  "^You (?:need to|should) unload",
  "^You can't do that",
  "^You just can't get",
  "^You can't put items",
  "^You can only take items out",
  "^You don't seem to be able to move",
  "^Perhaps you should be holding that first",
  "^Containers can't be placed in",
  "^The .* is not designed to carry anything",
  "^You can't put that.*there",
  "^Weirdly, you can't manage .* to fit",
  "^%[Containers can't be placed in",
  "even after stuffing it",
  "is too .* to (?:fit|hold)",
  "no matter how you arrange it",
  "close the fan",
  "to fit in the",
  "doesn't seem to want to leave you",  -- trying to put a pet in a home
  -- Cursed and unable to let go of items
  "Oddly, when you attempt to stash it away safely",
  "completely full",
  "That doesn't belong in there!",
  "exerts a steady force preventing",
}

--- Wear item success patterns (29 patterns — full Lich5 parity)
M.WEAR_ITEM_SUCCESS = {
  "^You put",
  "^You pull",
  "^You sling",
  "^You attach",
  "^You strap",
  "^You slide",
  "^You spin",
  "^You slip",
  "^You place",
  "^You hang",
  "^You tug",
  "^You struggle",
  "^You squeeze",
  "^You manage",
  "^You gently place",
  "^You toss one strap",
  "^You carefully loop",
  "^You work your way into",
  "^You are already wearing",
  "^Gritting your teeth, you grip",
  "^You expertly sling the",
  "put it on",  -- clerical collar thing
  "slide effortlessly onto your",
  "^You carefully arrange",
  "^A brisk chill rushes through you as you wear",
  "^You drape",
  "You lean over and slip your feet into the boots%.",
  "^You reach down and step into",
  "Gritting your teeth",
}

--- Wear item failure patterns (7 patterns — full Lich5 parity)
M.WEAR_ITEM_FAILURE = {
  "^You can't wear",
  "^You (?:need to|should) unload",
  "close the fan",
  "^You don't seem to be able to move",
  "^Wear what",
  "^I could not",
  "^What were you",
}

--- Remove item success patterns (23 patterns — full Lich5 parity)
M.REMOVE_ITEM_SUCCESS = {
  "^Dropping your shoulder",
  "^The .* slide",
  "^Without any effort",
  "^You .* slide",
  "^You detach",
  "^You loosen",
  "^You pull",
  "^You.*remove",
  "^You slide",
  "^You sling",
  "^You slip",
  "^You struggle",
  "^You take",
  "you tug",  -- case-insensitive in Lich5
  "^You untie",
  "as you remove",
  "slide themselves off of your",
  "you manage to loosen",
  "you unlace",
  "^You slam the heels",
  "^You work your way out",
  "^Grunting with momentary exertion",
  "^With masterful grace, you ready",
}

--- Remove item failure patterns (7 patterns — full Lich5 parity)
M.REMOVE_ITEM_FAILURE = {
  "^You'll need both hands free",
  "^You need a free hand",
  "^You aren't wearing",
  "^You don't seem to be able to move",
  "^Remove what",
  "^I could not",
  "^What were you",
}

--- Tie item success patterns (4 patterns — full Lich5 parity)
M.TIE_ITEM_SUCCESS = {
  "^You .*tie",
  "^You attach",
  "has already been tied off",
  "Tie it off when it's empty%?",
}

--- Tie item failure patterns (8 patterns — full Lich5 parity)
M.TIE_ITEM_FAILURE = {
  "^There's no more free ties",
  "^Tie what",
  "^You are a little too busy",
  "^You don't seem to be able to move",
  "^You must be holding",
  "^Your wounds hinder your ability to do that",
  "close the fan",
  "doesn't seem to fit",
}

--- Untie item success patterns (2 patterns — full Lich5 parity)
M.UNTIE_ITEM_SUCCESS = {
  "^You remove",
  "You untie",  -- case-insensitive in Lich5
}

--- Untie item failure patterns (4 patterns — full Lich5 parity)
M.UNTIE_ITEM_FAILURE = {
  "^You don't seem to be able to move",
  "^You fumble with the ties",
  "^Untie what",
  "^What were you referring",
}

--- Sheath item success patterns (upstream 375b9a0)
M.SHEATH_ITEM_SUCCESS = {
    "^Sheathing", "^You sheath", "^You secure your", "^You slip",
    "^You hang", "^You (?:easily )?strap",
    "^With a flick of your wrist,? you stealthily sheath",
    "^With fluid and stealthy movements you slip",
    "^The .* slides easily",
}
M.SHEATH_ITEM_FAILURE = {
    "^Sheath your .* where", "^There's no room",
    "is too small to hold that", "is too wide to fit",
    "^Your .* hand is too injured",
}

-- Splat SHEATH_ITEM_SUCCESS into PUT_AWAY_SUCCESS (Lich5: *SHEATH_ITEM_SUCCESS_PATTERNS)
for _, p in ipairs(M.SHEATH_ITEM_SUCCESS) do table.insert(M.PUT_AWAY_SUCCESS, p) end

--- Wield item success patterns (upstream 375b9a0)
M.WIELD_ITEM_SUCCESS = {
    "you draw", "^You deftly remove", "^You slip",
    "^With a flick of your wrist,? you stealthily unsheath",
    "^With fluid and stealthy movements you draw",
    "^The .* slides easily out",
}
M.WIELD_ITEM_FAILURE = {
    "^Wield what", "^Your .* hand is too injured",
}

--- Swap hands patterns (upstream 375b9a0)
M.SWAP_HANDS_SUCCESS = { "^You move" }
M.SWAP_HANDS_FAILURE = { "^Will alone cannot conquer the paralysis" }

--- Unload weapon patterns (upstream 375b9a0)
M.UNLOAD_WEAPON_SUCCESS = {
    "^You unload", "^Your .* fall.* to your feet%.$",
    "As you release the string", "^You .* unloading",
}
M.UNLOAD_WEAPON_FAILURE = {
    "But your .* isn't loaded", "You can't unload such a weapon",
    "You don't have a ranged weapon to unload",
    "You must be holding the weapon to do that",
}

--- Container closed patterns (upstream 375b9a0)
M.CONTAINER_IS_CLOSED = {
    "^But that's closed", "^That is closed", "^While it's closed",
}

--- Retry patterns (upstream 375b9a0)
M.DROP_TRASH_RETRY = {
    "^If you still wish to drop it", "would damage it",
    "^Something appears different about", "perhaps try doing that again",
}
M.PUT_AWAY_ITEM_RETRY = {
    "Something appears different about", "perhaps try doing that again",
}

--- Worn trashcan verb patterns (upstream 375b9a0)
M.WORN_TRASHCAN_VERB = {
    "^You drum your fingers", "^You pull a lever",
    "^You poke your finger around",
}

--- Braid too long (upstream 375b9a0)
M.BRAID_TOO_LONG_PATTERN = "The braided (.+) is too long"

--- Accept pattern (upstream 375b9a0)
M.ACCEPT_SUCCESS_PATTERN = "You accept (%w+)'s offer and are now holding"

--- Rummage success patterns (full Lich5 parity)
M.RUMMAGE_SUCCESS = {
    "^You rummage through .* and see",
    "^In the .* you see",
    "there is nothing",
}
M.RUMMAGE_FAILURE = {
    "^You don't seem to be able to move",
    "^I could not find",
    "^I don't know what you are referring to",
    "^What were you referring to",
}

--- Tap success patterns (6 patterns — full Lich5 parity)
M.TAP_SUCCESS = {
    "^You tap%s(?!into).*",  -- The `.*` captures entire phrase for parsing
    "^You (?:thump|drum) your finger",  -- Fancy verbiage tap
    "^As you tap",
    "^The orb is delicate",  -- Favor orb
    "^You .* on the shoulder",  -- Tapped someone
    "^You suddenly forget what you were doing",  -- tessera with full hands
}

--- Tap failure patterns (4 patterns — full Lich5 parity)
M.TAP_FAILURE = {
    "^You don't seem to be able to move",
    "^I could not find",
    "^I don't know what you are referring to",
    "^What were you referring to",
}

--- Open container success patterns (6 patterns — full Lich5 parity)
M.OPEN_CONTAINER_SUCCESS = {
    "^You open",
    "^You slowly open",
    "^The .* opens",
    "^You unbutton",
    "(?:It's|is) already open",
    "^You spread your arms, carefully holding your bag well away from your body",
}

--- Open container failure patterns (9 patterns — full Lich5 parity)
M.OPEN_CONTAINER_FAILURE = {
    "^Please rephrase that command",
    "^What were you referring to",
    "^I could not find what you were referring to",
    "^You don't want to ruin your spell just for that do you",
    "^It would be a shame to disturb the silence of this place for that",
    "^This is probably not the time nor place for that",
    "^You don't seem to be able to move",
    "^There is no way to do that",
    "^You can't do that",
    "^Open what",
}

--- Close container success patterns (4 patterns — full Lich5 parity)
M.CLOSE_CONTAINER_SUCCESS = {
    "^You close",
    "^You quickly close",
    "^You pull",
    "is already closed",
}

--- Close container failure patterns (9 patterns — full Lich5 parity)
M.CLOSE_CONTAINER_FAILURE = {
    "^Please rephrase that command",
    "^What were you referring to",
    "^I could not find what you were referring to",
    "^You don't want to ruin your spell just for that do you",
    "^It would be a shame to disturb the silence of this place for that",
    "^This is probably not the time nor place for that",
    "^You don't seem to be able to move",
    "^There is no way to do that",
    "^You can't do that",
}

--- Lower item success patterns (2 patterns — full Lich5 parity)
M.LOWER_SUCCESS = {
    "^You lower",
    -- Item crumbles when leaves your hand, like a moonblade
    "^As you open your hand to release the",
}

--- Lower item failure patterns (5 patterns — full Lich5 parity)
M.LOWER_FAILURE = {
    "^You don't seem to be able to move",
    "^But you aren't holding anything",
    "^Please rephrase that command",
    "^What were you referring to",
    "^I could not find what you were referring to",
}

--- Lift item success patterns (1 pattern — full Lich5 parity)
M.LIFT_SUCCESS = {
    "^You pick up",
}

--- Lift item failure patterns (4 patterns — full Lich5 parity)
M.LIFT_FAILURE = {
    "^There are no items lying at your feet",
    "^What did you want to try and lift",
    "can't quite lift it",
    "^You are not strong enough to pick that up",
}

--- Give item success patterns (5 patterns — full Lich5 parity)
M.GIVE_ITEM_SUCCESS = {
    "has accepted your offer",
    "your ticket and are handed back",
    "Please don't lose this ticket!",
    "^You hand .* gives you back a repair ticket",
    "^You hand .* your ticket and are handed back",
}

--- Give item failure patterns (10 patterns — full Lich5 parity)
M.GIVE_ITEM_FAILURE = {
    "I don't repair those here",
    "There isn't a scratch on that",
    "give me a few more moments",
    "I will not repair something that isn't broken",
    "I can't fix those",
    "has declined the offer",
    "^Your offer to .* has expired",
    "^You may only have one outstanding offer at a time",
    "^What is it you're trying to give",
    "Lucky for you!  That isn't damaged!",
}

--- Stow item combined patterns (rebuilt with expanded GET + PUT_AWAY arrays)
M.STOW_ITEM_SUCCESS = {}
for _, p in ipairs(M.GET_ITEM_SUCCESS) do table.insert(M.STOW_ITEM_SUCCESS, p) end
for _, p in ipairs(M.PUT_AWAY_SUCCESS) do table.insert(M.STOW_ITEM_SUCCESS, p) end

M.STOW_ITEM_FAILURE = {}
for _, p in ipairs(M.GET_ITEM_FAILURE) do table.insert(M.STOW_ITEM_FAILURE, p) end
for _, p in ipairs(M.PUT_AWAY_FAILURE) do table.insert(M.STOW_ITEM_FAILURE, p) end

M.STOW_ITEM_RETRY = {}
for _, p in ipairs(M.PUT_AWAY_ITEM_RETRY) do table.insert(M.STOW_ITEM_RETRY, p) end

--- Patterns indicating a gem pouch fill succeeded.
M.FILL_POUCH_SUCCESS_PATTERNS = {
  "^You open",
  "^You fill your",
  "^There aren't any gems",
}

--- Patterns indicating the pouch needs to be tied before filling.
M.FILL_POUCH_NEEDS_TIE_PATTERNS = {
  "^You'd better tie it up before putting",
  "^You'll need to tie it up before",
}

--- Pattern indicating the gem pouch is too full.
M.FILL_POUCH_FULL_PATTERN = "is too full to fit"

--- Patterns indicating a gem pouch fill command failed.
M.FILL_POUCH_FAILURE_PATTERNS = {
  "^Please rephrase that command",
  "^What were you referring to",
}

--- Pattern matching the start of INV BELT output.
M.INV_BELT_START_PATTERN = "^All of your items worn attached to the belt:"

--- Pattern matching the end of INV BELT output.
M.INV_BELT_END_PATTERN = "^%[Use INVENTORY HELP"

-------------------------------------------------------------------------------
-- Item reference helper
-------------------------------------------------------------------------------

--- Prefix an item name with "my " unless already prefixed or uses # ID syntax.
-- @param value string Item name
-- @return string Prefixed name
function M.item_ref(value)
  if not value or value == "" then return value end
  if value:lower():find("^my ") or value:find("^#") then
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
function M.stow_hand(hand, retries)
  retries = retries or 3
  if retries <= 0 then
    echo("DRCI: stow_hand exceeded max retries")
    return false
  end

  local all = { M.BRAID_TOO_LONG_PATTERN }
  for _, p in ipairs(M.CONTAINER_IS_CLOSED) do table.insert(all, p) end
  for _, p in ipairs(M.STOW_ITEM_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.STOW_ITEM_FAILURE) do table.insert(all, p) end
  for _, p in ipairs(M.STOW_ITEM_RETRY) do table.insert(all, p) end

  local result = DRC.bput("stow " .. hand, unpack(all))
  if not result then return false end

  -- Braid handling
  local braid_name = result:match("The braided (.+) is too long")
  if braid_name then
    local noun = DRC.get_noun and DRC.get_noun(braid_name) or braid_name:match("%S+$")
    M.dispose_trash(noun)
    return M.stow_hand(hand, retries - 1)
  end

  -- Retry patterns
  for _, p in ipairs(M.STOW_ITEM_RETRY) do
    if smart_find(result, p) then return M.stow_hand(hand, retries - 1) end
  end

  -- Success
  for _, p in ipairs(M.STOW_ITEM_SUCCESS) do
    if smart_find(result, p) then return true end
  end

  return false
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
function M.stow_item(item, retries)
  retries = retries or 3
  if retries <= 0 then
    echo("DRCI: stow_item exceeded max retries")
    return false
  end
  return M.put_away_item(item, nil)
end

--- Give an item to a target (NPC or player).
-- Equivalent to Lich5's DRCI.give_item?
-- For NPC repair shops the response is immediate; player-to-player offers
-- are handled via retry (GIVE it again / already has an outstanding offer).
-- @param target string Target name (NPC or player)
-- @param item string|nil Item to give (nil = give whatever is held)
-- @return boolean true if the target accepted
function M.give_item(target, item, retries)
  retries = retries or 5
  if retries <= 0 then
    echo("DRCI: give_item exceeded max retries")
    return false
  end
  local cmd
  if item then
    cmd = "give " .. M.item_ref(item) .. " to " .. target
  else
    cmd = "give " .. target
  end

  local all = { "GIVE it again", "give it to me again",
                "^You don't need to specify the object",
                "already has an outstanding offer" }
  for _, p in ipairs(M.GIVE_ITEM_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.GIVE_ITEM_FAILURE) do table.insert(all, p) end

  local result = DRC.bput(cmd, {timeout = 35}, unpack(all))
  if not result then return false end

  -- Success
  for _, p in ipairs(M.GIVE_ITEM_SUCCESS) do
    if smart_find(result, p) then return true end
  end

  -- Failure
  for _, p in ipairs(M.GIVE_ITEM_FAILURE) do
    if smart_find(result, p) then return false end
  end

  -- Retry: "give it to me again"
  if result:find("give it to me again") then
    return M.give_item(target, item, retries - 1)
  end

  -- Retry: "already has an outstanding offer" — wait then retry
  if result:find("already has an outstanding offer") then
    pause(5)
    return M.give_item(target, item, retries - 1)
  end

  -- Retry: "GIVE it again" — wait for roundtime then retry
  if result:find("GIVE it again") then
    if waitrt then waitrt() end
    return M.give_item(target, item, retries - 1)
  end

  -- Hand-swap: "You don't need to specify the object"
  if result:find("You don't need to specify the object") then
    if M.in_right_hand(item) then
      return M.give_item(target, nil, retries - 1)
    elseif M.in_left_hand(item) then
      local swap_all = {}
      for _, p in ipairs(M.SWAP_HANDS_SUCCESS) do table.insert(swap_all, p) end
      for _, p in ipairs(M.SWAP_HANDS_FAILURE) do table.insert(swap_all, p) end
      local swap_result = DRC.bput("swap", unpack(swap_all))
      for _, p in ipairs(M.SWAP_HANDS_SUCCESS) do
        if smart_find(swap_result, p) then
          return M.give_item(target, nil, retries - 1)
        end
      end
      return false
    else
      echo("DRCI: give_item could not find '" .. tostring(item) .. "' in either hand")
      return false
    end
  end

  return false
end

--- Lower an item to the ground.
-- @param item string Item to lower
-- @return boolean true on success
function M.lower_item(item)
  if not item then return false end
  if not M.in_hands(item) then return false end

  -- Determine which hand holds the item
  local hand = "right"
  local lh = DRC.left_hand and DRC.left_hand() or nil
  if lh and lh:find(item, 1, true) then hand = "left" end

  local all = {}
  for _, p in ipairs(M.LOWER_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.LOWER_FAILURE) do table.insert(all, p) end
  local result = DRC.bput("lower ground " .. hand, unpack(all))
  if not result then return false end
  for _, p in ipairs(M.LOWER_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
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

  local all = {}
  for _, p in ipairs(M.UNTIE_ITEM_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.UNTIE_ITEM_FAILURE) do table.insert(all, p) end
  local result = DRC.bput(cmd, unpack(all))
  if not result then return false end
  for _, p in ipairs(M.UNTIE_ITEM_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
end

--- Tie an item to something.
-- @param item string Item to tie
-- @param to string What to tie to
-- @return boolean
function M.tie_item(item, to)
  if not item then return false end
  local place = to and (" to " .. M.item_ref(to)) or ""

  local all = {}
  for _, p in ipairs(M.TIE_ITEM_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.TIE_ITEM_FAILURE) do table.insert(all, p) end
  local result = DRC.bput("tie " .. M.item_ref(item) .. place, unpack(all))
  if not result then return false end
  for _, p in ipairs(M.TIE_ITEM_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Dispose / Trash
-------------------------------------------------------------------------------

--- Dispose of a trash item. Attempts to put in a room trashcan or drop.
-- @param item string Item to dispose
-- @param worn_trashcan string|nil Worn trashcan name
-- @param worn_trashcan_verb string|nil Verb (default "put")
function M.dispose_trash(item, worn_trashcan, worn_trashcan_verb, retries)
    if not item then return false end
    retries = retries or 3
    if retries <= 0 then
        echo("DRCI: dispose_trash exceeded max retries")
        return false
    end

    -- I1: Ensure item is in hand first (Lich5: get_item_if_not_held?)
    if not M.in_hands(item) then
        if not M.get_item(item) then
            return false  -- Can't pick up the item to dispose
        end
    end

    -- Build combined pattern list for bput
    local all_dispose = {}
    for _, p in ipairs(M.DROP_TRASH_SUCCESS) do table.insert(all_dispose, p) end
    for _, p in ipairs(M.DROP_TRASH_FAILURE) do table.insert(all_dispose, p) end

    -- Helper: check if result matches any success pattern
    local function is_success(result)
        if not result then return false end
        for _, p in ipairs(M.DROP_TRASH_SUCCESS) do
            if smart_find(result, p) then return true end
        end
        return false
    end

    -- I2: Worn trashcan handling (Lich5: put item in trashcan, then fire verb twice)
    if worn_trashcan then
        local cmd = "put " .. M.item_ref(item) .. " in " .. M.item_ref(worn_trashcan)
        local result = DRC.bput(cmd, unpack(all_dispose))
        if is_success(result) then
            -- Fire activation verb twice (Lich5 behavior)
            if worn_trashcan_verb then
                DRC.bput(worn_trashcan_verb .. " " .. M.item_ref(worn_trashcan), unpack(M.WORN_TRASHCAN_VERB))
                DRC.bput(worn_trashcan_verb .. " " .. M.item_ref(worn_trashcan), unpack(M.WORN_TRASHCAN_VERB))
            end
            return true
        end
        -- If worn trashcan failed, fall through to room trash
    end

    -- I4: Check for meta:trashcan room tag (Lich5 priority)
    if Room and Room.current and Room.current.tags then
        for _, tag in ipairs(Room.current.tags) do
            local meta_noun = tag:match("^meta:trashcan:(.+)$")
            if meta_noun then
                local cmd
                if meta_noun == "gelapod" then
                    cmd = "feed " .. M.item_ref(item) .. " to gelapod"
                else
                    cmd = "put " .. M.item_ref(item) .. " in " .. meta_noun
                end
                local result = DRC.bput(cmd, unpack(all_dispose))
                if is_success(result) then return true end
            end
        end
    end

    -- I3: Noun disambiguation table (Lich5 common-items.rb lines 688-716)
    local NOUN_ALIASES = {
        gloop = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("small bubbling cauldron of viscous gloop") then return "cauldron" end
                    if obj:find("bucket of viscous gloop") then return "bucket" end
                end
            end
            return "bucket"
        end,
        bucket = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("sturdy bucket") then return "sturdy bucket" end
                end
            end
            return "bucket"
        end,
        basket = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("waste basket") then return "waste basket" end
                end
            end
            return "basket"
        end,
        bin = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("small bin") then return "small bin" end
                    if obj:find("waste bin") then return "waste bin" end
                end
            end
            return "bin"
        end,
        arms = "statue",
        birdbath = "alabaster birdbath",
        turtle = "stone turtle",
        tree = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("dead tree with a darkened hollow") then return "hollow" end
                end
            end
            return "tree"
        end,
        basin = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("hollow stone basin") then return "stone basin" end
                end
            end
            return "basin"
        end,
        tangle = function(room_objs)
            if room_objs then
                for _, obj in ipairs(room_objs) do
                    if obj:find("tangle of thick roots forming a dark gap") then return "dark gap" end
                end
            end
            return "tangle"
        end,
    }

    -- Junk Yard room override (Lich5: XMLData.room_title == '[[A Junk Yard]]')
    if Room and Room.current and Room.current.title and Room.current.title:find("Junk Yard") then
        local cmd = "put " .. M.item_ref(item) .. " in bin"
        local result = DRC.bput(cmd, unpack(all_dispose))
        for _, p in ipairs(M.DROP_TRASH_SUCCESS) do
            if result and smart_find(result, p) then return true end
        end
    end

    -- Get room objects if DRRoom is available
    local room_objs = (DRRoom and DRRoom.room_objs) and DRRoom.room_objs() or nil

    -- Try room trash receptacles
    for _, noun in ipairs(M.TRASH_STORAGE) do
        local cmd
        if noun == "gelapod" then
            cmd = "feed " .. M.item_ref(item) .. " to gelapod"
        else
            local target = noun
            local alias = NOUN_ALIASES[noun]
            if type(alias) == "function" then
                target = alias(room_objs)
            elseif type(alias) == "string" then
                target = alias
            end
            cmd = "put " .. M.item_ref(item) .. " in " .. target
        end
        local result = DRC.bput(cmd, unpack(all_dispose))
        if is_success(result) then return true end
    end

    -- Last resort: just drop it
    DRC.bput("drop " .. M.item_ref(item), "You drop", "You spread",
        "What were you referring to")
    return false
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
  local all = {}
  for _, p in ipairs(M.OPEN_CONTAINER_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.OPEN_CONTAINER_FAILURE) do table.insert(all, p) end
  local result = DRC.bput("open " .. M.item_ref(container), unpack(all))
  if not result then return false end
  for _, p in ipairs(M.OPEN_CONTAINER_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
end

--- Close a container.
-- @param container string Container to close
-- @return boolean
function M.close_container(container)
  local all = {}
  for _, p in ipairs(M.CLOSE_CONTAINER_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.CLOSE_CONTAINER_FAILURE) do table.insert(all, p) end
  local result = DRC.bput("close " .. M.item_ref(container), unpack(all))
  if not result then return false end
  for _, p in ipairs(M.CLOSE_CONTAINER_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
end

--- Shared helper for rummage/look-in container with closed-container retry.
local function list_container_contents(verb, container, retries, parse_fn)
    if retries <= 0 then
        echo("DRCI: list_container_contents exceeded max retries")
        return nil
    end

    local cmd
    if verb == "rummage" then
        cmd = "rummage my " .. container
    else
        cmd = "look in my " .. container
    end

    local all_patterns = {
        "You rummage through", "In the .* you see",
        "There is nothing in there", "That is empty",
    }
    for _, p in ipairs(M.CONTAINER_IS_CLOSED) do table.insert(all_patterns, p) end
    table.insert(all_patterns, "I could not find")
    table.insert(all_patterns, "What were you referring")

    local result = DRC.bput(cmd, unpack(all_patterns))
    if not result then return nil end

    -- Closed container: open and retry
    for _, p in ipairs(M.CONTAINER_IS_CLOSED) do
        if smart_find(result, p) then
            M.open_container(container)
            return list_container_contents(verb, container, retries - 1, parse_fn)
        end
    end

    -- Empty
    if result:find("nothing in there") or result:find("That is empty") then
        return {}
    end

    -- Failure
    if result:find("could not find") or result:find("What were you referring") then
        return nil
    end

    return parse_fn(result)
end

--- Rummage through a container and return a list of item names.
-- Uses list_container_contents helper with closed-container retry.
-- @param container string Container to rummage
-- @param retries number|nil Max retries (default 2)
-- @return table|nil Array of item strings, or nil on failure
function M.rummage_container(container, retries)
    retries = retries or 2
    return list_container_contents("rummage", container, retries, function(result)
        local items_str = result:match("You rummage through .* and see .- (.+)%.")
        if not items_str then return {} end
        items_str = items_str:gsub(" and (a[n]? )", ", %1")
        local items = {}
        for item in items_str:gmatch("[^,]+") do
            item = item:match("^%s*a[n]?%s+(.+)") or item:match("^%s*some%s+(.+)") or item:match("^%s*(.+)")
            if item then table.insert(items, item:match("^%s*(.-)%s*$")) end
        end
        return items
    end)
end

--- Look in a container and return a list of item names.
-- Uses list_container_contents helper with closed-container retry.
-- @param container string Container to look in
-- @param retries number|nil Max retries (default 2)
-- @return table|nil Array of item strings, or nil on failure
function M.look_in_container(container, retries)
    retries = retries or 2
    return list_container_contents("look", container, retries, function(result)
        local items_str = result:match("In the .* you see .- (.+)%.")
        if not items_str then return {} end
        local items = {}
        for item in items_str:gmatch("[^,]+") do
            item = item:gsub("^%s*and%s+", "")
            item = item:match("^%s*a[n]?%s+(.+)") or item:match("^%s*some%s+(.+)") or item:match("^%s*(.+)")
            if item then table.insert(items, item:match("^%s*(.-)%s*$")) end
        end
        return items
    end)
end

--- Check if a container is empty.
-- @param container string Container to check
-- @return boolean true if container is empty, false if it has items or on failure
function M.container_is_empty(container)
    local contents = M.look_in_container(container)
    return contents ~= nil and #contents == 0
end

--- Tap an item (returns the tap description).
-- @param item string Item to tap
-- @return string Result of tapping
function M.tap(item, container)
  if not item then return "" end
  local from = ""
  if container then
    -- If container already starts with a preposition, use as-is
    if container:match("^[Ii]n ") or container:match("^[Oo]n ") or container:match("^[Uu]nder ")
        or container:match("^[Bb]ehind ") or container:match("^[Ff]rom ") then
      from = " " .. container
    else
      from = " from " .. M.item_ref(container)
    end
  end

  local all = {}
  for _, p in ipairs(M.TAP_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.TAP_FAILURE) do table.insert(all, p) end
  return DRC.bput("tap " .. M.item_ref(item) .. from, unpack(all))
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
  if not result then return false end
  for _, p in ipairs(M.TAP_SUCCESS) do
    if smart_find(result, p) then return true end
  end
  return false
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

--- Put an item away, trying container then default stow.
-- Includes closed-container recovery and retry logic (upstream 375b9a0).
-- @param item string Item name
-- @param container string|nil Container
-- @param retries number|nil Max retries (default 3)
-- @return boolean
function M.put_away_item_unsafe(item, container, retries)
  retries = retries or 3
  if retries <= 0 then
    echo("DRCI: put_away_item_unsafe exceeded max retries")
    return false
  end
  if not item then return false end

  local cmd = container and ("put my " .. item .. " in my " .. container)
                         or ("stow my " .. item)
  local all_patterns = {}
  for _, p in ipairs(M.PUT_AWAY_SUCCESS) do table.insert(all_patterns, p) end
  for _, p in ipairs(M.PUT_AWAY_FAILURE) do table.insert(all_patterns, p) end
  for _, p in ipairs(M.PUT_AWAY_ITEM_RETRY) do table.insert(all_patterns, p) end
  for _, p in ipairs(M.CONTAINER_IS_CLOSED) do table.insert(all_patterns, p) end

  local result = DRC.bput(cmd, unpack(all_patterns))

  -- Closed container recovery
  for _, p in ipairs(M.CONTAINER_IS_CLOSED) do
    if result and smart_find(result, p) then
      M.open_container(container)
      return M.put_away_item_unsafe(item, container, retries - 1)
    end
  end

  -- Retry patterns
  for _, p in ipairs(M.PUT_AWAY_ITEM_RETRY) do
    if result and smart_find(result, p) then
      return M.put_away_item_unsafe(item, container, retries - 1)
    end
  end

  -- Check success
  for _, p in ipairs(M.PUT_AWAY_SUCCESS) do
    if result and smart_find(result, p) then
      return true
    end
  end

  return false
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

-------------------------------------------------------------------------------
-- Stackable item counting
-------------------------------------------------------------------------------

--- Count the total number of parts/uses across all stacks of a named item.
-- Iterates ordinal prefixes (first, second, ...) sending COUNT commands until
-- the item is not found.  Returns the aggregate use-count from game responses.
-- Equivalent to Lich5's DRCI.count_item_parts.
-- @param item string Item name (e.g., "blank scroll") or "#ID" for unique item
-- @return number Total parts/uses found
function M.count_item_parts(item)
  if not item then return 0 end

  local COUNT_PATTERNS = {
    "and see there %w+ (.+) left%.",
    "There %w+ only (.+) parts? left",
    "There %w+ (.+) parts? left",
    "There's only (.+) parts? left",
    "There's (.+) parts? left",
    "The .+ has (.+) uses remaining%.",
    "There are enough left to create (.+) more",
    "You count out (.+) pieces? of material there",
    "There %w+ (.+) scrolls? left for use with crafting",
  }

  -- Word-to-number for common DR responses
  local WORD_NUMS = {
    zero=0,one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,
    ten=10,eleven=11,twelve=12,thirteen=13,fourteen=14,fifteen=15,
    sixteen=16,seventeen=17,eighteen=18,nineteen=19,twenty=20,
    ["twenty-five"]=25,thirty=30,forty=40,fifty=50,
  }

  local function parse_count(str)
    local n = tonumber(str)
    if n then return n end
    local lower = str:lower():match("^%s*(.-)%s*$")
    return WORD_NUMS[lower] or 0
  end

  local count = 0

  -- ID-referenced items are unique — count once without ordinal
  if item:sub(1, 1) == "#" then
    local result = DRC.bput("count " .. item,
      "I could not find what you were referring to",
      "tell you much of anything",
      unpack(COUNT_PATTERNS))
    if result:find("could not find") then return 0 end
    if result:find("tell you much") then return 1 end
    for _, pat in ipairs(COUNT_PATTERNS) do
      local cap = result:match(pat)
      if cap then return parse_count(cap) end
    end
    return 0
  end

  -- Iterate ordinals: "first blank scroll", "second blank scroll", ...
  for _, ord in ipairs(ORDINALS or {}) do
    waitrt()
    local ref = "my " .. ord .. " " .. item
    local result = DRC.bput("count " .. ref,
      "I could not find what you were referring to",
      "tell you much of anything",
      unpack(COUNT_PATTERNS))

    if result:find("could not find") then
      break  -- no more stacks
    elseif result:find("tell you much") then
      -- non-stackable item: count 1 per ordinal hit
      count = count + 1
    else
      local matched = false
      for _, pat in ipairs(COUNT_PATTERNS) do
        local cap = result:match(pat)
        if cap then
          count = count + parse_count(cap)
          matched = true
          break
        end
      end
      if not matched then break end
    end
  end

  return count
end

-------------------------------------------------------------------------------
-- Items at feet
-------------------------------------------------------------------------------

--- Attempt to lift an item from the floor.
-- Mirrors Lich5 DRCI.lift?(item) — sends LIFT <item> and returns true on success.
-- With no argument, attempts to lift any item at feet.
-- @param item string|nil Item noun to lift (optional)
-- @return boolean true if item was picked up, false otherwise
function M.lift(item, stow)
  if not item then return false end
  -- Necessary until adjectives are implemented for lift (Lich5 compat)
  local noun = item:match("(%S+)$") or item

  local all = {}
  for _, p in ipairs(M.LIFT_SUCCESS) do table.insert(all, p) end
  for _, p in ipairs(M.LIFT_FAILURE) do table.insert(all, p) end
  local result = DRC.bput("lift " .. noun, unpack(all))
  if not result then return false end

  for _, p in ipairs(M.LIFT_SUCCESS) do
    if smart_find(result, p) then
      if type(stow) == "string" then
        return M.put_away_item(noun, stow)
      elseif stow then
        return M.stow_item(noun)
      end
      return true
    end
  end
  return false
end

-------------------------------------------------------------------------------
-- Accept / Search
-------------------------------------------------------------------------------

--- Accept an offered item from another player.
-- @param timeout number|nil seconds to wait (default 5)
-- @return string|false giver's name on success, false on failure
function M.accept_item(timeout)
    timeout = timeout or 5
    local result = DRC.bput("accept", M.ACCEPT_SUCCESS_PATTERN, "Accept what?",
        "Both of your hands are full", "would push you over your item limit",
        "You have no offers",
        {timeout = timeout})
    if result then
        local name = result:match(M.ACCEPT_SUCCESS_PATTERN)
        if name then return name end
    end
    return false
end

--- Search inventory for an item.
-- @param item string item to search for
-- @return boolean true if found
function M.search(item)
    local result = DRC.bput("inv search " .. item,
        "An? .+ is", "Some .+ is",
        "You aren't carrying anything like that")
    if result and (result:find("is %a") or result:find("is being")) then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Inventory query methods
-------------------------------------------------------------------------------

--- Scroll name normalization substitutions (Lich5 parity).
-- Applied in order when parsing RUMMAGE /SC results.
local SCROLL_SUBS = {
  { "^a piece of ", "" },
  { "^an? ", "" },
  { "^some ", "" },
  { "%s+labeled with.*", "" },
  { "icy blue vellum scroll", "icy scroll" },
  { "green vellum scroll", "green scroll" },
  { "fetid antelope vellum", "antelope vellum" },
  { "papyrus roll", "papyrus.roll" },
  { "pallid red scroll", "pallid scroll" },
  { "%s+(bark|leaf|ostracon|papyrus|parchment|roll|scroll|tablet|vellum|manuscript)%s+.*", " %1" },
  { "crumpled paper", "crumpled" },
  { "pale ricepaper", "pale" },
  { "stormy grey", "stormy" },
  { "mossy green", "mossy" },
  { "dark purple", "dark" },
  { "vibrant red", "vibrant" },
  { "bright green", "bright" },
  { "icy blue", "blue" },
  { "pearl%-white silk", "silk" },
  { "ghostly white", "white" },
  { "crinkled violet", "crinkled" },
  { "drawing paper", "drawing" },
}

--- Count how many of an item exist (taps to find container, then counts).
-- Mirrors Lich5 DRCI.count_items — taps the item to determine which container
-- it's in, then delegates to count_items_in_container.
-- @param item string Item name
-- @return number Count
function M.count_items(item)
  if not item then return 0 end

  local result = M.tap(item)
  if not result then return 0 end

  -- Lich5 checks "inside your <container>"
  local container = result:match("inside your (.+)")
  if not container then return 0 end

  -- Strip trailing period if present
  container = container:match("^(.-)%.?$")
  return M.count_items_in_container(item, container)
end

--- Get inventory items by type (combat, armor, weapon, fluff, container).
-- Mirrors Lich5 DRCI.get_inventory_by_type — sends INVENTORY <type> and
-- parses the multi-line output, stripping articles and "(closed)" tags.
-- @param inv_type string Inventory type (default "combat")
-- @return table Array of item description strings
function M.get_inventory_by_type(inv_type)
  inv_type = inv_type or "combat"

  local start_pattern = "^All of your |^You aren't wearing anything like that|^Both of your hands are empty"
  local end_pattern = "^%[Use INVENTORY HELP"

  local result = DRC.bput("inventory " .. inv_type,
    "All of your", "You aren't wearing anything like that",
    "Both of your hands are empty")

  if not result then return {} end
  if result:find("aren't wearing") or result:find("hands are empty") then
    return {}
  end

  -- Collect lines until the INVENTORY HELP footer
  local lines = {}
  local timeout_at = os.time() + 5
  while os.time() < timeout_at do
    local line = get_noblock and get_noblock()
    if line then
      local stripped = line:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
      if stripped:find("^%[Use INVENTORY HELP") then break end
      if stripped:find("^Lying at your feet") then break end
      if stripped ~= "" and not stripped:find(start_pattern) then
        -- Strip articles and "(closed)" like Lich5
        stripped = stripped:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", ""):gsub("%s+%(closed%)", "")
        table.insert(lines, stripped)
      end
    else
      if pause then pause(0.1) end
    end
  end

  return lines
end

--- Get list of scrolls in a container via RUMMAGE /SC.
-- Mirrors Lich5 DRCI.get_scroll_list_in_container — delegates to DRC.rummage
-- with 'SC' parameter, then applies scroll-specific name normalization.
-- @param container string Container name
-- @return table Array of scroll adj+noun strings (e.g. "icy scroll")
function M.get_scroll_list_in_container(container)
  if not container then return {} end

  local result = DRC.bput("rummage /SC my " .. container,
    "but there is nothing in there like that",
    "looking for .* and see",
    "While it's closed",
    "I don't know what you are referring to",
    "You feel about",
    "That would accomplish nothing")

  if result:find("You feel about") then
    if DRC.release_invisibility then DRC.release_invisibility() end
    return M.get_scroll_list_in_container(container)
  end

  if result:find("nothing in there") or result:find("closed")
      or result:find("don't know") or result:find("accomplish nothing") then
    return {}
  end

  local text = result:match("looking for .* and see (.*)%.")
  if not text then return {} end

  -- Parse list and apply scroll-specific substitutions (Lich5 parity)
  local items = DRC.list_to_array(text)
  local scrolls = {}
  for _, entry in ipairs(items) do
    local s = entry:match("^%s*(.-)%s*$")
    for _, sub in ipairs(SCROLL_SUBS) do
      s = s:gsub(sub[1], sub[2])
    end
    s = s:match("^%s*(.-)%s*$")
    if s ~= "" then
      scrolls[#scrolls + 1] = s
    end
  end
  return scrolls
end

--- Count items in a Necromancer material stacker via STUDY.
-- Mirrors Lich5 DRCI.count_necro_stacker.
-- @param stacker string Stacker item name
-- @return number Count of items currently held
function M.count_necro_stacker(stacker)
  if not stacker then return 0 end

  local result = DRC.bput("study " .. M.item_ref(stacker),
    "currently holds %d+ items",
    "I could not find",
    "What were you referring to",
    "Study what")
  if not result then return 0 end

  local count = result:match("currently holds (%d+) items")
  if count then return tonumber(count) end
  return 0
end

-------------------------------------------------------------------------------
-- Gem Pouch Management
-------------------------------------------------------------------------------

--- Check if a gem pouch matching adj+noun is tied to belt.
-- Issues INV BELT and scans output for adj.*gem.*noun.
-- @param adj string Adjective (e.g. "black")
-- @param noun string Noun (e.g. "pouch")
-- @return boolean
function M.check_belt_for_pouch(adj, noun)
  local belt_contents = DRC.issue_command(
    "inv belt",
    M.INV_BELT_START_PATTERN,
    M.INV_BELT_END_PATTERN,
    { timeout = 3, silent = true, quiet = true, usexml = false, include_end = false }
  )
  if not belt_contents or #belt_contents == 0 then
    return false
  end
  local pouch_pattern = adj:lower() .. ".*gem.*" .. noun:lower()
  for _, line in ipairs(belt_contents) do
    if line:lower():find(pouch_pattern) then
      return true
    end
  end
  return false
end

--- Tie a gem pouch to belt.
-- @param adj string Adjective (e.g. "black")
-- @param noun string Noun (e.g. "pouch")
-- @return boolean
function M.tie_gem_pouch(adj, noun)
  return M.tie_item(adj .. " " .. noun)
end

--- Remove current pouch and stow it.
-- @param adj string Adjective (e.g. "black")
-- @param noun string Noun (e.g. "pouch")
-- @param container string|nil Container to stow in (nil = default stow)
-- @return boolean
function M.remove_and_stow_pouch(adj, noun, container)
  local pouch = adj .. " " .. noun
  if not M.remove_item(pouch) then
    DRC.message("bold", "DRCI: Unable to remove existing pouch.")
    return false
  end
  if container then
    return M.put_away_item(pouch, container) or M.stow_item(pouch) or false
  else
    return M.stow_item(pouch) or false
  end
end

--- Swap out a full gem pouch for a spare.
-- Removes the current (full) pouch, stows it, then obtains a spare from
-- the belt or a container, wears it, and optionally ties it.
-- @param adj string Pouch adjective (e.g. "black")
-- @param noun string Pouch noun (e.g. "pouch")
-- @param full_container string|nil Container to stow the full pouch
-- @param spare_container string|nil Container holding spare pouches
-- @param tie boolean Whether to tie the new pouch to belt
-- @return boolean Success
function M.swap_out_full_gempouch(adj, noun, full_container, spare_container, tie)
  -- Need a free hand to swap pouches
  local lh = DRC and DRC.left_hand and DRC.left_hand()
  local rh = DRC and DRC.right_hand and DRC.right_hand()
  if lh and rh then
    DRC.message("bold", "DRCI: No free hand. Not swapping pouches now.")
    return false
  end

  -- Step 1: Remove and stow the full pouch
  if not M.remove_and_stow_pouch(adj, noun, full_container) then
    DRC.message("bold", "DRCI: Remove and stow pouch routine failed.")
    return false
  end

  local pouch = adj .. " " .. noun

  -- Step 2: Check belt for a spare, otherwise get from container
  if M.check_belt_for_pouch(adj, noun) then
    DRC.message("plain", "DRCI: Found existing " .. pouch .. " on belt, using that.")
    if not M.untie_item(pouch) then
      DRC.message("bold", "DRCI: Could not untie existing pouch on belt.")
      return false
    end
  elseif not M.get_item(pouch, spare_container) then
    DRC.message("bold", "DRCI: No spare pouch found in " .. (spare_container or "default container") .. ".")
    return false
  end

  -- Step 3: Wear the new pouch
  if not M.wear_item(pouch) then
    DRC.message("bold", "DRCI: Could not wear new pouch.")
    return false
  end

  -- Step 4: Optionally tie to belt (non-fatal if it fails)
  if tie and not M.tie_gem_pouch(adj, noun) then
    DRC.message("bold", "DRCI: Could not tie new pouch.")
  end

  return true
end

--- Fill a gem pouch from a container, handling full pouches and untied state.
-- Loops fill commands with bounded retries. On success, continues filling.
-- On needs-tie, ties (or swaps if tie=false). On full, swaps out the pouch.
-- On failure, stops.
-- @param adj string Pouch adjective (e.g. "black")
-- @param noun string Pouch noun (e.g. "pouch")
-- @param source string Source container holding gems
-- @param full_container string|nil Where to stow full pouches
-- @param spare_container string|nil Where spare pouches are stored
-- @param tie boolean Whether to tie pouches to belt
-- @param retries number|nil Max retries (default 10)
function M.fill_gem_pouch_with_container(adj, noun, source, full_container, spare_container, tie, retries)
  retries = retries or 10
  if retries <= 0 then
    DRC.message("bold", "DRCI: fill_gem_pouch_with_container exceeded max retries")
    return
  end

  local pouch = adj .. " " .. noun

  -- Build match pattern list
  local all = {}
  for _, p in ipairs(M.FILL_POUCH_SUCCESS_PATTERNS) do table.insert(all, p) end
  table.insert(all, M.FILL_POUCH_FULL_PATTERN)
  for _, p in ipairs(M.FILL_POUCH_NEEDS_TIE_PATTERNS) do table.insert(all, p) end
  for _, p in ipairs(M.FILL_POUCH_FAILURE_PATTERNS) do table.insert(all, p) end

  local result = DRC.bput(
    "fill " .. M.item_ref(pouch) .. " with " .. M.item_ref(source),
    unpack(all))
  if not result then return end

  -- Check failure first
  for _, p in ipairs(M.FILL_POUCH_FAILURE_PATTERNS) do
    if smart_find(result, p) then
      DRC.message("bold", "DRCI: Fill failed - " .. result)
      return
    end
  end

  -- Check needs-tie
  for _, p in ipairs(M.FILL_POUCH_NEEDS_TIE_PATTERNS) do
    if smart_find(result, p) then
      if tie then
        -- Tie the pouch and retry
        if not M.tie_gem_pouch(adj, noun) then
          DRC.message("bold", "DRCI: Could not tie " .. pouch .. ".")
          return
        end
        return M.fill_gem_pouch_with_container(adj, noun, source,
          full_container, spare_container, tie, retries - 1)
      else
        -- Treat as full — swap out the pouch
        if not M.swap_out_full_gempouch(adj, noun, full_container, spare_container, tie) then
          DRC.message("bold", "DRCI: Could not swap gem pouches.")
          return
        end
        return M.fill_gem_pouch_with_container(adj, noun, source,
          full_container, spare_container, tie, retries - 1)
      end
    end
  end

  -- Check full
  if smart_find(result, M.FILL_POUCH_FULL_PATTERN) then
    if not M.swap_out_full_gempouch(adj, noun, full_container, spare_container, tie) then
      DRC.message("bold", "DRCI: Could not swap gem pouches.")
      return
    end
    return M.fill_gem_pouch_with_container(adj, noun, source,
      full_container, spare_container, tie, retries - 1)
  end

  -- Success — keep filling
  for _, p in ipairs(M.FILL_POUCH_SUCCESS_PATTERNS) do
    if smart_find(result, p) then
      return M.fill_gem_pouch_with_container(adj, noun, source,
        full_container, spare_container, tie, retries - 1)
    end
  end

  -- TODO: Lich5 uses Flags["pouch-full"] to detect mid-fill full pouches.
  -- Implement when the Flags system is available in the Lua engine.

  -- Optionally tie the pouch after successful fill
  if tie then
    M.tie_gem_pouch(adj, noun)
  end
end

return M
