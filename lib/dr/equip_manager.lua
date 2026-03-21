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

    if item.wield then
      local result = DRC.bput("wield my " .. item:short_name(),
        "You draw", "You deftly remove", "You slip",
        "With a flick", "Wield what",
        "Your right hand is too injured",
        "Your left hand is too injured")
      return not (result:find("Wield what") or result:find("too injured"))
    elseif item.tie_to then
      return DRCI and DRCI.untie_item and DRCI.untie_item(item:short_name(), item.tie_to) or false
    elseif item.worn then
      return DRCI and DRCI.remove_item and DRCI.remove_item(item:short_name()) or false
    elseif item.container then
      return DRCI and DRCI.get_item and DRCI.get_item(item:short_name(), item.container) or false
    else
      return DRCI and DRCI.get_item and DRCI.get_item(item:short_name()) or false
    end
  end

  --- Remove an item and stow it properly.
  function em.remove_item(self, item)
    if not item then return end
    local result = DRC.bput("remove my " .. item:short_name(),
      "You remove", "You pull", "You sling", "You slide",
      "You work your way out", "You unbuckle", "You loosen",
      "You detach", "You yank",
      "Remove what", "You aren't wearing that",
      "constricts tighter")
    if waitrt then waitrt() end

    if result:find("constricts") then
      respond("[EquipMgr] " .. item:short_name() .. " is not ready to be removed.")
      return false
    end
    if result:find("Remove what") or result:find("aren't wearing") then
      return false
    end

    -- Stow based on item properties
    if item.tie_to then
      self:stow_helper("tie my " .. item:short_name() .. " to my " .. item.tie_to,
        item:short_name(), DRCI and DRCI.TIE_ITEM_SUCCESS or {}, DRCI and DRCI.TIE_ITEM_FAILURE or {})
    elseif item.wield then
      self:stow_helper("sheath my " .. item:short_name(),
        item:short_name(), DRCI and DRCI.SHEATH_ITEM_SUCCESS or {}, DRCI and DRCI.SHEATH_ITEM_FAILURE or {})
    elseif item.container then
      self:stow_helper("put my " .. item:short_name() .. " in my " .. item.container,
        item:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
    else
      self:stow_helper("stow my " .. item:short_name(),
        item:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
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
      if DRCI then DRCI.stow_hand("left"); DRCI.stow_hand("right") end
      return self:stow_helper("stow my " .. item_name, item_name,
        DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {}, retries - 1)
    elseif smart_find(result, "close the fan") then
      DRC.bput("close my " .. item_name, "You close", "already closed", "What were")
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "too busy") or smart_find(result, "can't .* move") then
      if DRC.retreat then DRC.retreat() end
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
    elseif smart_find(result, "wounds hinder") or smart_find(result, "Sheath your .* where") then
      return self:stow_helper("stow my " .. item_name, item_name,
        DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {}, retries - 1)
    else
      pause(0.5)
      return self:stow_helper(action, item_name, success_patterns, failure_patterns, retries - 1)
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
          if lh and not lh:find(noun) then DRCI.stow_hand("left") end
          if rh and not rh:find(noun) then DRCI.stow_hand("right") end
        end
      elseif result:find("nothing to swap") or result:find("too injured") or result:find("Will alone") then
        return false
      elseif result:lower():find(skill:lower()) then
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
    if waitrt then waitrt() end
    if not result then return end

    -- Check failure
    if DRCI then
      for _, p in ipairs(DRCI.UNLOAD_WEAPON_FAILURE) do
        if smart_find(result, p) then return end
      end
    end

    -- Scenario 1: Ammo fell to feet
    local ammo = result:match("(%w+) fall.* from your .* to your feet")
    if ammo then
      if DRCI and DRCI.lower_item then
        if not DRCI.lower_item(name) then
          echo("EquipmentManager: Unable to lower " .. name .. " to pick up ammo")
          return
        end
        DRCI.put_away_item(ammo)
        if not DRCI.get_item(name) then
          echo("EquipmentManager: Unable to pick " .. name .. " back up after unloading")
        end
      end
      return
    end

    -- Scenario 2: Bow release, ammo tumbles
    if result:find("As you release the string") then
      local tumbled = result:match("the (%w+) tumbles")
      if tumbled and DRCI and DRCI.lower_item then
        if not DRCI.lower_item(name) then
          echo("EquipmentManager: Unable to lower " .. name .. " to pick up ammo")
          return
        end
        DRCI.put_away_item(tumbled)
        if not DRCI.get_item(name) then
          echo("EquipmentManager: Unable to pick " .. name .. " back up after unloading")
        end
      end
      return
    end

    -- Scenario 3: Normal unload, ammo in hand
    if result:find("You unload") or result:find("unloading") then
      local left = DRC.left_hand and DRC.left_hand()
      local right = DRC.right_hand and DRC.right_hand()
      if left and not left:find(name) then
        if DRCI then DRCI.stow_hand("left") end
      elseif right and not right:find(name) then
        if DRCI then DRCI.stow_hand("right") end
      end
    end
  end

  --- Stow all weapons currently in hands.
  function em.stow_weapon(self, description)
    if not description then
      local rh = DRC and DRC.right_hand and DRC.right_hand()
      local lh = DRC and DRC.left_hand and DRC.left_hand()
      if rh then self:stow_weapon(rh) end
      if lh then self:stow_weapon(lh) end
      return
    end

    local weapon = self:item_by_desc(description)
    if not weapon then return end

    if weapon.needs_unloading then
      self:unload_weapon(weapon:short_name())
    end

    if weapon.wield then
      self:stow_helper("sheath my " .. weapon:short_name(),
        weapon:short_name(), DRCI and DRCI.SHEATH_ITEM_SUCCESS or {}, DRCI and DRCI.SHEATH_ITEM_FAILURE or {})
    elseif weapon.worn then
      self:stow_helper("wear my " .. weapon:short_name(),
        weapon:short_name(), DRCI and DRCI.WEAR_ITEM_SUCCESS or {}, DRCI and DRCI.WEAR_ITEM_FAILURE or {})
    elseif weapon.tie_to then
      self:stow_helper("tie my " .. weapon:short_name() .. " to my " .. weapon.tie_to,
        weapon:short_name(), DRCI and DRCI.TIE_ITEM_SUCCESS or {}, DRCI and DRCI.TIE_ITEM_FAILURE or {})
    elseif weapon.container then
      self:stow_helper("put my " .. weapon:short_name() .. " in my " .. weapon.container,
        weapon:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
    else
      self:stow_helper("stow my " .. weapon:short_name(),
        weapon:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
    end
  end

  --- Wear an equipment set by name.
  function em.wear_equipment_set(self, set_name)
    if not set_name then return false end
    local gear_list = self._gear_sets[set_name]
    if not gear_list then
      respond("[EquipMgr] Gear set not found: " .. set_name)
      return false
    end

    local target_items = self:desc_to_items(gear_list)

    -- Get current combat items
    -- TODO: parse 'inv combat' output
    -- For now, just wear all target items
    for _, item in ipairs(target_items) do
      self:wear_item(item)
    end

    if self._sort_head then
      DRC.bput("sort auto head", "Your inventory is now arranged")
    end
    return true
  end

  --- Return held gear to its proper storage.
  function em.return_held_gear(self, gear_set)
    gear_set = gear_set or "standard"
    local rh = DRC and DRC.right_hand and DRC.right_hand()
    local lh = DRC and DRC.left_hand and DRC.left_hand()
    if not rh and not lh then return true end

    local held = {}
    if lh then held[#held + 1] = lh end
    if rh then held[#held + 1] = rh end

    for _, held_item in ipairs(held) do
      local info = self:item_by_desc(held_item)
      if info then
        if info.needs_unloading then
          self:unload_weapon(info:short_name())
        end
        -- Stow according to item type
        if info.worn then
          self:stow_helper("wear my " .. info:short_name(),
            info:short_name(), DRCI and DRCI.WEAR_ITEM_SUCCESS or {}, DRCI and DRCI.WEAR_ITEM_FAILURE or {})
        elseif info.tie_to then
          self:stow_helper("tie my " .. info:short_name() .. " to my " .. info.tie_to,
            info:short_name(), DRCI and DRCI.TIE_ITEM_SUCCESS or {}, DRCI and DRCI.TIE_ITEM_FAILURE or {})
        elseif info.wield then
          self:stow_helper("sheath my " .. info:short_name(),
            info:short_name(), DRCI and DRCI.SHEATH_ITEM_SUCCESS or {}, DRCI and DRCI.SHEATH_ITEM_FAILURE or {})
        elseif info.container then
          self:stow_helper("put my " .. info:short_name() .. " in my " .. info.container,
            info:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
        else
          self:stow_helper("stow my " .. info:short_name(),
            info:short_name(), DRCI and DRCI.PUT_AWAY_SUCCESS or {}, DRCI and DRCI.PUT_AWAY_FAILURE or {})
        end
      end
    end
    return true
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
