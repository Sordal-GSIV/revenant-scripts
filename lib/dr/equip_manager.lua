--- EquipmentManager — DR equipment set management.
-- Ported from Lich5 equip-manager.rb (class EquipmentManager).
-- Provides weapon swap, armor change, equipment sets, sheath/wield logic.
-- @module lib.dr.equip_manager
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Sheath success patterns.
M.SHEATH_SUCCESS = {
  "Sheathing", "You sheath", "You secure your",
  "You slip", "You hang", "You strap", "You easily strap",
  "With a flick of your wrist you stealthily sheath",
  "The .* slides easily",
}

--- Sheath failure patterns.
M.SHEATH_FAILURE = {
  "Sheath your .* where", "There's no room",
  "is too small to hold that", "is too wide to fit",
  "Your .* hand is too injured",
}

--- All weapon skills usable for swap.
M.WEAPON_SKILLS = {
  "light edged", "medium edged", "heavy edged", "two-handed edged",
  "light blunt", "medium blunt", "heavy blunt", "two-handed blunt",
  "light thrown", "heavy thrown",
  "short staff", "quarter staff", "halberd", "pike",
}

M.STOW_HELPER_MAX_RETRIES = 10

local STOW_RECOVERY_PATTERNS = {
    "unload",
    "close the fan",
    "You are a little too busy",
    "You don't seem to be able to move",
    "is too small to hold that",
    "Your wounds hinder your ability to do that",
    "Sheath your .* where",  -- NOTE: "Sheath" not "Sheathe"
}

local SKILL_ALIASES = {
    {pattern = "^he$",              skill = "heavy edged"},
    {pattern = "heavy edge",        skill = "heavy edged"},
    {pattern = "large edge",        skill = "heavy edged"},
    {pattern = "one%-handed",       skill = "heavy edged"},
    {pattern = "^2he$",             skill = "two%-handed edged"},
    {pattern = "^the$",             skill = "two%-handed edged"},
    {pattern = "twohanded edge",    skill = "two%-handed edged"},
    {pattern = "two%-handed edge",  skill = "two%-handed edged"},
    {pattern = "^hb$",              skill = "heavy blunt"},
    {pattern = "heavy blunt",       skill = "heavy blunt"},
    {pattern = "large blunt",       skill = "heavy blunt"},
    {pattern = "^2hb$",             skill = "two%-handed blunt"},
    {pattern = "^thb$",             skill = "two%-handed blunt"},
    {pattern = "twohanded blunt",   skill = "two%-handed blunt"},
    {pattern = "two%-handed blunt", skill = "two%-handed blunt"},
    {pattern = "^se$",              skill = "(?:light|medium) edged"},
    {pattern = "small edged",       skill = "(?:light|medium) edged"},
    {pattern = "light edge",        skill = "(?:light|medium) edged"},
    {pattern = "medium edge",       skill = "(?:light|medium) edged"},
    {pattern = "^sb$",              skill = "(?:light|medium) blunt"},
    {pattern = "small blunt",       skill = "(?:light|medium) blunt"},
    {pattern = "light blunt",       skill = "(?:light|medium) blunt"},
    {pattern = "medium blunt",      skill = "(?:light|medium) blunt"},
    {pattern = "^lt$",              skill = "light thrown"},
    {pattern = "light thrown",      skill = "light thrown"},
    {pattern = "^ht$",              skill = "heavy thrown"},
    {pattern = "heavy thrown",      skill = "heavy thrown"},
    {pattern = "stave",             skill = "(?:short|quarter) staff"},
    {pattern = "polearm",           skill = "(?:halberd|pike)"},
    {pattern = "^ow$",              skill = "offhand weapon"},
    {pattern = "offhand weapon",    skill = "offhand weapon"},
}

-------------------------------------------------------------------------------
-- Item class
-------------------------------------------------------------------------------

--- Create an Item descriptor (mirrors DRC::Item from Lich5).
-- @param opts table Item configuration
-- @return table Item object
function M.Item(opts)
  opts = opts or {}
  local item = {
    name             = opts.name,
    leather          = opts.leather,
    worn             = opts.worn or false,
    hinders_locks    = opts.hinders_locks,
    container        = opts.container,
    swappable        = opts.swappable or false,
    tie_to           = opts.tie_to,
    adjective        = opts.adjective,
    bound            = opts.bound or false,
    wield            = opts.wield or false,
    transforms_to    = opts.transforms_to,
    transform_verb   = opts.transform_verb,
    transform_text   = opts.transform_text,
    lodges           = opts.lodges ~= false,  -- default true
    skip_repair      = opts.skip_repair or false,
    ranged           = opts.ranged or false,
    needs_unloading  = opts.needs_unloading,
  }

  if item.needs_unloading == nil then
    item.needs_unloading = item.ranged
  end

  --- Get the short name (adjective.noun or just noun).
  function item.short_name(self)
    if self.adjective then
      return self.adjective .. "." .. self.name
    end
    return self.name
  end

  --- Check if a description matches this item.
  function item.matches(self, description)
    if not description then return false end
    if self.adjective then
      return description:find(self.adjective) and description:find(self.name)
    end
    return description:find(self.name) ~= nil
  end

  return item
end

-------------------------------------------------------------------------------
-- EquipmentManager instance
-------------------------------------------------------------------------------

--- Create a new EquipmentManager.
-- @param settings table|nil Character settings with gear and gear_sets
-- @return table EquipmentManager instance
function M.EquipmentManager(settings)
  local em = {
    _items     = nil,
    _gear_sets = {},
    _sort_head = false,
  }

  --- Load items from settings.
  function em.items(self, settings_override)
    if self._items then return self._items end
    local s = settings_override or settings or {}

    if s.gear_sets then
      for set_name, gear_list in pairs(s.gear_sets) do
        self._gear_sets[set_name] = gear_list
      end
    end
    self._sort_head = s.sort_auto_head or false

    self._items = {}
    if s.gear then
      for _, g in ipairs(s.gear) do
        self._items[#self._items + 1] = M.Item(g)
      end
    end
    return self._items
  end

  --- Find an item by description.
  function em.item_by_desc(self, description)
    if not description then return nil end
    for _, item in ipairs(self:items()) do
      if item:matches(description) then return item end
    end
    return nil
  end

  --- Convert an array of descriptions to Item objects.
  function em.desc_to_items(self, descs)
    local result = {}
    for _, desc in ipairs(descs) do
      local item = self:item_by_desc(desc)
      if item then result[#result + 1] = item end
    end
    return result
  end

  --- Wear an item (get and put on).
  function em.wear_item(self, item)
    if not item then
      respond("[EquipMgr] No item to wear.")
      return false
    end
    if self:get_item(item) then
      return DRCI and DRCI.wear_item and DRCI.wear_item(item:short_name()) or false
    end
    return false
  end

  --- Get an item from wherever it's stored.
  function em.get_item(self, item)
    if not item then return false end
    if DRCI and DRCI.in_hands and DRCI.in_hands(item) then return true end

    local success = false
    if item.wield then
      local result = DRC.bput("wield my " .. item:short_name(),
        "You draw", "You deftly remove", "You slip",
        "With a flick", "Wield what",
        "Your right hand is too injured",
        "Your left hand is too injured")
      success = not (result:find("Wield what") or result:find("too injured"))
    elseif item.tie_to then
      success = DRCI and DRCI.untie_item and DRCI.untie_item(item:short_name(), item.tie_to) or false
    elseif item.worn then
      success = DRCI and DRCI.remove_item and DRCI.remove_item(item:short_name()) or false
    elseif item.container then
      success = DRCI and DRCI.get_item and DRCI.get_item(item:short_name(), item.container) or false
    else
      success = DRCI and DRCI.get_item and DRCI.get_item(item:short_name()) or false
    end

    -- Handle transforms after successful get
    if success and item.transforms_to then
      local cmd = item.transform_verb or ("turn my " .. item:short_name())
      DRC.bput(cmd, item.transform_text or "shifts", "What were", "Turn what")
      if waitrt then waitrt() end
    end

    return success
  end

  --- Remove an item and stow it properly.
  function em.remove_item(self, item, retries)
    if not item then return false end
    retries = retries or 2
    if retries <= 0 then
      echo("EquipmentManager: remove_item exceeded max retries")
      return false
    end

    local result = DRC.bput("remove my " .. item:short_name(),
      "You remove", "You pull", "You sling", "You slide",
      "You work your way out", "You unbuckle", "You loosen",
      "You detach", "You yank", "^Grunting with momentary exertion",
      "Remove what", "You aren't wearing that",
      "constricts tighter", "You'll need both hands free")
    if waitrt then waitrt() end

    if result:find("constricts") then
      respond("[EquipMgr] " .. item:short_name() .. " is not ready to be removed.")
      return false
    end
    if result:find("Remove what") or result:find("aren't wearing") then
      return false
    end
    if result:find("both hands free") or result:find("need a free hand") then
      -- Save current hand contents BEFORE lowering
      local saved_left = DRC.left_hand and DRC.left_hand() or nil
      local saved_right = DRC.right_hand and DRC.right_hand() or nil
      -- Lower both hands; check success (E4)
      local lowered = true
      if DRCI then
        if saved_left and not DRCI.lower_item(saved_left) then
            echo("EquipmentManager: Unable to lower " .. saved_left .. " for remove")
            lowered = false
        end
        if saved_right and not DRCI.lower_item(saved_right) then
            echo("EquipmentManager: Unable to lower " .. saved_right .. " for remove")
            lowered = false
        end
      end
      if not lowered then
        echo("EquipmentManager: Unable to empty your hands to remove " .. item:short_name())
        return false
      end
      -- Recursive remove
      local success = self:remove_item(item, retries - 1)
      -- Restore items (reverse order)
      if DRCI then
        if saved_right then DRCI.get_item(saved_right) end
        if saved_left then DRCI.get_item(saved_left) end
        -- Check hand order and swap if needed
        local new_left = DRC.left_hand and DRC.left_hand() or nil
        local new_right = DRC.right_hand and DRC.right_hand() or nil
        if (new_left ~= saved_left) or (new_right ~= saved_right) then
          DRC.bput("swap", "You move", "Will alone cannot conquer")
        end
      end
      return success
    end

    -- After successful remove, handle transforms_to (E1, Lich5 lines 263-271)
    if item.transforms_to and DRCI and DRCI.in_hands and DRCI.in_hands(item.transforms_to) then
        local transform_desc = item.transforms_to
        local transform_item = self:item_by_desc(transform_desc)
        if transform_item then
            item = transform_item
        else
            echo("EquipmentManager: Could not find transformed item matching '" .. transform_desc .. "' in gear list")
            return false
        end
    end
    -- Route to stow destination (E5, Lich5 lines 272-276)
    if item.tie_to or item.wield or item.container then
        self:stow_by_type(item)
    else
        -- Try generic stow; if no room, fall back to wearing
        local stow_patterns = {}
        local base = DRCI and DRCI.PUT_AWAY_SUCCESS or {"You put"}
        for _, p in ipairs(base) do stow_patterns[#stow_patterns + 1] = p end
        stow_patterns[#stow_patterns + 1] = "There isn't any more room"
        stow_patterns[#stow_patterns + 1] = "straps have all been used"
        stow_patterns[#stow_patterns + 1] = "is too long to fit"
        local result = DRC.bput("stow my " .. item:short_name(), unpack(stow_patterns))
        if result and (result:find("more room") or result:find("too long to fit") or result:find("straps have all been used")) then
            self:stow_helper("wear my " .. item:short_name(), item:short_name(),
                DRCI and DRCI.WEAR_ITEM_SUCCESS or {}, DRCI and DRCI.WEAR_ITEM_FAILURE or {})
        end
    end
    if waitrt then waitrt() end
    return true
  end

  --- Stow helper with retry logic and failure detection.
  -- @param action string game command
  -- @param item_name string short name for logging
  -- @param success_patterns table success pattern strings
  -- @param failure_patterns table|nil terminal failure patterns (default {})
  -- @param retries number|nil remaining retries
  -- @return boolean true on success, false on failure
  function em.stow_helper(self, action, item_name, success_patterns, failure_patterns, retries)
    success_patterns = success_patterns or {}
    failure_patterns = failure_patterns or {}
    retries = retries or M.STOW_HELPER_MAX_RETRIES
    if retries <= 0 then
      echo("EquipmentManager: stow_helper exceeded max retries for '" .. action .. "'")
      return false
    end

    local all = {}
    for _, p in ipairs(success_patterns) do all[#all + 1] = p end
    for _, p in ipairs(failure_patterns) do all[#all + 1] = p end
    for _, p in ipairs(STOW_RECOVERY_PATTERNS) do all[#all + 1] = p end

    local result = DRC.bput(action, unpack(all))

    if not result or result == "" then
      echo("EquipmentManager: stow_helper got no response for '" .. action .. "'")
      return false
    end

    -- Check terminal failure
    for _, p in ipairs(failure_patterns) do
      if smart_find(result, p) then
        echo("EquipmentManager: stow_helper failed for '" .. action .. "': " .. result)
        return false
      end
    end

    -- Check success
    for _, p in ipairs(success_patterns) do
      if smart_find(result, p) then
        return true
      end
    end

    -- Recovery
    if smart_find(result, "unload") then
      self:unload_weapon(item_name)
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "close the fan") then
      DRC.bput("close my " .. item_name, "You close", "already closed", "What were")
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "You are a little too busy") then
      if DRC.retreat then DRC.retreat() end
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "You don't seem to be able to move") then
      pause(1)
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "is too small to hold that") then
      fput("swap my " .. item_name)
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "wounds hinder") or smart_find(result, "Sheath your .* where") then
      return self:stow_helper("stow my " .. item_name, item_name,
        DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {}, retries - 1)
    else
      pause(0.5)
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    end
  end

  --- Route item to correct stow destination.
  function em.stow_by_type(self, item)
    if item.tie_to then
      return self:stow_helper("tie my " .. item:short_name() .. " to my " .. item.tie_to,
        item:short_name(), DRCI.TIE_ITEM_SUCCESS, DRCI.TIE_ITEM_FAILURE)
    elseif item.wield then
      return self:stow_helper("sheath my " .. item:short_name(),
        item:short_name(), DRCI.SHEATH_ITEM_SUCCESS, DRCI.SHEATH_ITEM_FAILURE)
    elseif item.container then
      return self:stow_helper("put my " .. item:short_name() .. " in my " .. item.container,
        item:short_name(), DRCI.PUT_AWAY_SUCCESS, DRCI.PUT_AWAY_FAILURE)
    else
      return self:stow_helper("stow my " .. item:short_name(),
        item:short_name(), DRCI.PUT_AWAY_SUCCESS, DRCI.PUT_AWAY_FAILURE)
    end
  end

  --- Wield a weapon into the right hand.
  function em.wield_weapon(self, description, skill)
    if not description or description == "" then return false end
    local weapon = self:item_by_desc(description)
    if not weapon then
      respond("[EquipMgr] No weapon matches: " .. description)
      return false
    end

    if self:get_item(weapon) then
      if skill and weapon.swappable then
        self:swap_to_skill(weapon.name, skill)
      end
      -- Handle offhand
      if skill == "Offhand Weapon" then
        local rh = DRC and DRC.right_hand and DRC.right_hand()
        if rh then
          local result = DRC.bput("swap", "You move", "Will alone cannot conquer")
          return result:find("You move") ~= nil
        end
      end
      return true
    end
    return false
  end

  --- Wield a weapon into the left (off) hand.
  function em.wield_weapon_offhand(self, description, skill)
    if not description or description == "" then return false end
    local weapon = self:item_by_desc(description)
    if not weapon then
      respond("[EquipMgr] No weapon matches: " .. description)
      return false
    end

    if self:get_item(weapon) then
      if skill and weapon.swappable then
        self:swap_to_skill(weapon.name, skill)
      end
      if DRCI and DRCI.in_right_hand and DRCI.in_right_hand(weapon) then
        local result = DRC.bput("swap", "You move", "Will alone cannot conquer")
        return result:find("You move") ~= nil
      end
    end
    return false
  end

  --- Swap a weapon to a different weapon skill configuration.
  function em.swap_to_skill(self, noun, skill)
    if not noun or not skill then return false end

    -- Normalize skill aliases
    local proper_skill = skill
    for _, alias in ipairs(SKILL_ALIASES) do
      if skill:lower():find(alias.pattern) then
        proper_skill = alias.skill
        break
      end
    end
    skill = proper_skill

    -- Offhand weapon: no swap needed, just leave in left hand (Lich5 early return)
    if skill == "offhand weapon" then
        return true
    end

    -- Fan handling
    if noun:lower():find("fan") then
      local cmd = skill:lower():find("edged") and "open" or "close"
      DRC.bput(cmd .. " my fan", "you snap", "already")
      return true
    end

    for _ = 1, #M.WEAPON_SKILLS + 1 do
      pause(0.25)
      local result = DRC.bput("swap my " .. noun,
        skill:lower(),
        "You have nothing to swap",
        "Your .* hand is too injured",
        "Will alone cannot conquer",
        "You move a",
        "You must have two free hands")

      if result:find("two free hands") then
        if DRCI then
          local lh = DRC and DRC.left_hand and DRC.left_hand()
          local rh = DRC and DRC.right_hand and DRC.right_hand()
          if lh and not lh:lower():find(noun:lower()) then DRCI.stow_hand("left") end
          if rh and not rh:lower():find(noun:lower()) then DRCI.stow_hand("right") end
        end
        -- Verify hands are actually free now (E7)
        local lh2 = DRC.left_hand and DRC.left_hand() or nil
        local rh2 = DRC.right_hand and DRC.right_hand() or nil
        local hands_ok = true
        if lh2 and not lh2:lower():find(noun:lower()) then hands_ok = false end
        if rh2 and not rh2:lower():find(noun:lower()) then hands_ok = false end
        if not hands_ok then
            echo("EquipmentManager: Unable to free hands for weapon swap")
            return false
        end
      elseif result:find("nothing to swap") or result:find("too injured") or result:find("Will alone") then
        return false
      elseif result:lower():find(" " .. skill:lower() .. " ") then
        return true
      end
    end
    return false
  end

  --- Unload a ranged weapon with 3-scenario ammo recovery.
  function em.unload_weapon(self, name)
    if not name then return end
    local all = {}
    if DRCI then
      for _, p in ipairs(DRCI.UNLOAD_WEAPON_SUCCESS) do all[#all + 1] = p end
      for _, p in ipairs(DRCI.UNLOAD_WEAPON_FAILURE) do all[#all + 1] = p end
    else
      all = {"You unload", "falls .* to your feet", "As you release",
             "isn't loaded", "You can't unload", "You don't have a ranged", "You must be holding"}
    end

    local result = DRC.bput("unload my " .. name, unpack(all))
    if not result then return end

    -- Check failure
    if DRCI then
      for _, p in ipairs(DRCI.UNLOAD_WEAPON_FAILURE) do
        if smart_find(result, p) then
          if waitrt then waitrt() end
          return
        end
      end
    end

    -- Scenario 1: Ammo fell to feet
    local ammo = result:match("(%w+) fall.* from your .* to your feet")
    if ammo then
      if DRCI and DRCI.lower_item then
        if not DRCI.lower_item(name) then
          echo("EquipmentManager: Unable to lower " .. name .. " to pick up ammo")
          if waitrt then waitrt() end
          return
        end
        DRCI.put_away_item(ammo)
        if not DRCI.get_item(name) then
          echo("EquipmentManager: Unable to pick " .. name .. " back up after unloading")
        end
      end
      if waitrt then waitrt() end
      return
    end

    -- Scenario 2: Bow release, ammo tumbles
    if result:find("As you release the string") then
      local tumbled = result:match("the (%w+) tumbles")
      if tumbled and DRCI and DRCI.lower_item then
        if not DRCI.lower_item(name) then
          echo("EquipmentManager: Unable to lower " .. name .. " to pick up ammo")
          if waitrt then waitrt() end
          return
        end
        DRCI.put_away_item(tumbled)
        if not DRCI.get_item(name) then
          echo("EquipmentManager: Unable to pick " .. name .. " back up after unloading")
        end
      end
      if waitrt then waitrt() end
      return
    end

    -- Scenario 3: Normal unload, ammo in hand (E9: independent checks, not elseif)
    if result:find("You unload") or result:find("unloading") then
      local left = DRC.left_hand and DRC.left_hand() or nil
      local right = DRC.right_hand and DRC.right_hand() or nil
      if left and not left:find(name) then
        if DRCI then DRCI.stow_hand("left") end
      end
      if right and not right:find(name) then
        if DRCI then DRCI.stow_hand("right") end
      end
    end

    -- waitrt at end (E9, Lich5 placement — after all ammo recovery)
    if waitrt then waitrt() end
  end

  --- Stow all weapons currently in hands.
  function em.stow_weapon(self, description, transform_depth)
    transform_depth = transform_depth or 3
    if not description then
      local rh = DRC and DRC.right_hand and DRC.right_hand()
      local lh = DRC and DRC.left_hand and DRC.left_hand()
      if rh then self:stow_weapon(rh) end
      if lh then self:stow_weapon(lh) end
      return
    end

    local weapon = self:item_by_desc(description)
    if not weapon then
      if DRCI then DRCI.stow_hand("right"); DRCI.stow_hand("left") end
      return
    end

    -- Unload FIRST, before any routing (E2, matches Lich5 order)
    if weapon.needs_unloading then
      self:unload_weapon(weapon:short_name())
    end

    -- Worn items get re-worn (not stowed)
    if weapon.worn then
        self:stow_helper("wear my " .. weapon:short_name(), weapon:short_name(),
            DRCI and DRCI.WEAR_ITEM_SUCCESS or {}, DRCI and DRCI.WEAR_ITEM_FAILURE or {})
        return
    end

    -- Handle transforms
    if weapon.transforms_to then
      if transform_depth <= 0 then
        echo("EquipmentManager: stow_weapon exceeded max transform depth")
        return
      end
      local cmd = weapon.transform_verb or ("turn my " .. weapon:short_name())
      DRC.bput(cmd, weapon.transform_text or "shifts", "What were", "Turn what")
      if waitrt then waitrt() end
      return self:stow_weapon(weapon.transforms_to, transform_depth - 1)
    end

    self:stow_by_type(weapon)
  end

  --- Turn a multi-form weapon to a specific form.
  function em.turn_to_weapon(self, old_noun, new_noun)
    if old_noun == new_noun then return true end  -- Already in correct form
    local result = DRC.bput("turn my " .. old_noun .. " to " .. new_noun,
      "Turn what", "Which weapon did you want to pull out",
      "shifts .* before resolving itself into")
    if waitrt then waitrt() end
    -- Verify the correct form was reached (E10, matches Lich5 regex check)
    if result and result:find("shifts") then
        if result:lower():find(new_noun:lower()) then
            return true
        end
        echo("EquipmentManager: weapon shifted but not to expected form " .. new_noun)
        return false
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- Gear set diff helpers (private)
  ---------------------------------------------------------------------------

  --- Remove currently worn items that are NOT in the target gear set.
  -- combat_items are raw description strings from get_combat_items();
  -- target_items are Item objects from desc_to_items().
  -- Mirrors Lich5 remove_unmatched_items: rejects descriptions matched by
  -- any target item's short_regex, looks up the remainder in the master
  -- gear list, and removes each one.
  -- @param combat_items table Array of description strings currently worn
  -- @param target_items table Array of Item objects in the target set
  function em.remove_unmatched_items(self, combat_items, target_items)
    for _, desc in ipairs(combat_items) do
      -- Check whether any target item matches this worn description
      local dominated = false
      for _, target in ipairs(target_items) do
        if target:matches(desc) then
          dominated = true
          break
        end
      end
      if not dominated then
        -- Look up the full Item from master gear list
        local item = self:item_by_desc(desc)
        if item then
          self:remove_item(item)
        end
      end
    end
  end

  --- Wear items from the target set that are NOT currently worn.
  -- If a target item is currently in-hand, stow it first so wear_item
  -- can retrieve it from its container.  Returns items that could not
  -- be worn (missing from containers).
  -- Mirrors Lich5 wear_missing_items (lines 157-170).
  -- @param target_items table Array of Item objects to wear
  -- @param combat_items table Array of description strings currently worn
  -- @return table Array of Item objects that could not be worn
  function em.wear_missing_items(self, target_items, combat_items)
    local lost = {}
    for _, target in ipairs(target_items) do
      -- Already worn?
      local already_worn = false
      for _, desc in ipairs(combat_items) do
        if target:matches(desc) then
          already_worn = true
          break
        end
      end
      if not already_worn then
        -- If item is in hand, stow it first (Lich5 lines 165-166)
        local rh = DRC and DRC.right_hand and DRC.right_hand() or nil
        local lh = DRC and DRC.left_hand and DRC.left_hand() or nil
        local in_hand = (rh and target:matches(rh)) or (lh and target:matches(lh))
        if in_hand then
          self:stow_weapon(target:short_name())
        end
        -- Now wear from container
        if not self:wear_item(target) then
          table.insert(lost, target)
        end
      end
    end
    return lost
  end

  --- Notify the user about missing gear items via bold messaging + beep.
  -- Mirrors Lich5 notify_missing (lines 138-146).
  -- @param lost_items table Array of Item objects that couldn't be found
  function em.notify_missing(self, lost_items)
    if not lost_items or #lost_items == 0 then return end
    if DRC and DRC.beep then DRC.beep() end
    local names = {}
    for _, item in ipairs(lost_items) do
      table.insert(names, item:short_name())
    end
    echo("EquipmentManager: MISSING EQUIPMENT - Please verify these items are in a closed container and not lost:")
    echo("EquipmentManager: " .. table.concat(names, ", "))
    pause()
    if DRC and DRC.beep then DRC.beep() end
  end

  ---------------------------------------------------------------------------
  -- wear_equipment_set — full diff approach
  ---------------------------------------------------------------------------

  --- Wear an equipment set by name, using diff logic.
  -- Removes items not in the target set, wears items missing from current.
  -- Mirrors Lich5 wear_equipment_set? (lines 94-115).
  -- @param set_name string Gear set name
  -- @return boolean True if all items successfully worn
  function em.wear_equipment_set(self, set_name)
    if not set_name then return false end
    local gear_list = self._gear_sets[set_name]
    if not gear_list then
      respond("[EquipMgr] Gear set not found: " .. set_name)
      return false
    end

    local target_items = self:desc_to_items(gear_list)

    -- Get current combat items as description strings
    local combat_items = self:get_combat_items()

    -- Step 1: Remove worn items not in target set
    self:remove_unmatched_items(combat_items, target_items)

    -- Step 2: Wear items missing from current
    local lost_items = self:wear_missing_items(target_items, combat_items)

    -- Step 3: Notify about missing items
    self:notify_missing(lost_items)

    -- Sort if configured
    if self._sort_head then
      DRC.bput("sort auto head", "Your inventory is now arranged")
    end

    return #lost_items == 0
  end

  --- Return held gear to its proper storage (E6: gear-set membership check).
  function em.return_held_gear(self, gear_set)
    gear_set = gear_set or "standard"
    local rh = DRC and DRC.right_hand and DRC.right_hand()
    local lh = DRC and DRC.left_hand and DRC.left_hand()
    if not rh and not lh then return true end

    local held = {}
    if lh then held[#held + 1] = lh end
    if rh then held[#held + 1] = rh end

    -- Build gear set items list (Lich5 checks gear set membership for wear-back)
    local gear_set_items = self:desc_to_items(self._gear_sets[gear_set] or {})

    local all_ok = true
    for _, held_item in ipairs(held) do
      -- Check gear set membership first (Lich5 line 437)
      local gs_info = nil
      for _, gs_item in ipairs(gear_set_items) do
        if gs_item:matches(held_item) then
          gs_info = gs_item
          break
        end
      end

      if gs_info then
        -- Item is in the gear set: unload if needed, then wear
        if gs_info.needs_unloading then
          self:unload_weapon(gs_info:short_name())
        end
        self:stow_helper("wear my " .. gs_info:short_name(), gs_info:short_name(),
          DRCI and DRCI.WEAR_ITEM_SUCCESS or {}, DRCI and DRCI.WEAR_ITEM_FAILURE or {})
      else
        -- Not in gear set; check general gear list
        local info = self:item_by_desc(held_item)
        if info then
          if info.needs_unloading then
            self:unload_weapon(info:short_name())
          end
          self:stow_by_type(info)
        else
          -- Unknown item, generic stow (E6)
          all_ok = false
          if DRCI then
            if held_item == (DRC.left_hand and DRC.left_hand()) then
              DRCI.stow_hand("left")
            else
              DRCI.stow_hand("right")
            end
          end
        end
      end
    end
    return all_ok
  end

  --- Remove all worn items matching a predicate function.
  -- @param predicate function Function(item) -> boolean
  -- @return table List of removed Item objects (for later re-wearing)
  function em.remove_gear_by(self, predicate)
    local removed = {}
    for _, item in ipairs(self:items()) do
      if item.worn and predicate(item) then
        if self:remove_item(item) then
          removed[#removed + 1] = item
        end
      end
    end
    return removed
  end

  --- Wear a list of Item objects (re-equip previously removed gear).
  -- @param items table List of Item objects to wear
  function em.wear_items(self, items)
    if not items then return end
    for _, item in ipairs(items) do
      self:wear_item(item)
    end
  end

  --- Empty both hands, preferring return_held_gear over generic stow.
  function em.empty_hands(self)
    if not em:return_held_gear() then
      if DRCI and DRCI.stow_hands then
        DRCI.stow_hands()
      end
    end
  end

  --- Get list of currently worn combat items by parsing INV COMBAT output.
  -- Mirrors Lich5 get_combat_items: issues "inv combat" and returns stripped
  -- description strings (header/footer lines excluded).
  -- @return table Array of item description strings
  function em.get_combat_items(self)
    put("inv combat")
    local lines = {}
    local collecting = false
    local timeout_at = os.time() + 10
    while os.time() < timeout_at do
      local line = get_noblock()
      if line then
        local stripped = DRC.strip_xml and DRC.strip_xml(line) or line
        stripped = stripped:match("^%s*(.-)%s*$") or stripped
        if stripped == "All of your worn combat equipment:"
            or stripped == "You aren't wearing anything like that." then
          collecting = true
        elseif stripped:find("^Use INVENTORY HELP") then
          break
        elseif collecting and stripped ~= "" then
          table.insert(lines, stripped)
        end
        if line:find("<prompt") then break end
      else
        pause(0.1)
      end
    end
    return lines
  end

  --- Get currently worn combat items matching a description list.
  -- Mirrors Lich5 matching_combat_items: converts both the filter list and
  -- the INV COMBAT output to Item objects and returns the intersection.
  -- @param list table Array of descriptions to filter by
  -- @return table Array of Item objects currently worn that match the list
  function em.matching_combat_items(self, list)
    local filter_gear = self:desc_to_items(list)
    local gear = self:desc_to_items(self:get_combat_items())
    local result = {}
    for _, g in ipairs(gear) do
      for _, f in ipairs(filter_gear) do
        if g == f then
          table.insert(result, g)
          break
        end
      end
    end
    return result
  end

  --- @deprecated Use matching_combat_items instead.
  em.worn_items = em.matching_combat_items

  --- Check if a description matches any item in the gear list.
  -- Mirrors Lich5 listed_item?: finds an item whose short_regex matches desc.
  -- @param desc string Item description to check
  -- @return table|nil Matching Item object, or nil if not found
  function em.listed_item(self, desc)
    return self:item_by_desc(desc)
  end

  --- @deprecated Use listed_item instead.
  em.is_listed_item = em.listed_item

  -- Initialize items if settings provided
  if settings then em:items(settings) end

  return em
end

-------------------------------------------------------------------------------
-- Module-level convenience
-------------------------------------------------------------------------------

--- Empty both hands without requiring a settings-loaded EquipmentManager instance.
-- Stows both hands via DRCI. Equivalent to EquipmentManager():empty_hands()
-- when no gear settings are needed (e.g., clearing hands before a quest action).
function M.empty_hands()
  if DRCI and DRCI.stow_hands then
    DRCI.stow_hands()
  end
end

return M
