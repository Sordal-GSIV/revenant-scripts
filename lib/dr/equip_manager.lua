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
  "Sheathing", "You sheathe", "You secure your",
  "You slip", "You hang", "You strap", "You easily strap",
  "With a flick of your wrist you stealthily sheathe",
  "The .* slides easily",
}

--- Sheath failure patterns.
M.SHEATH_FAILURE = {
  "Sheathe your .* where", "There's no room",
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
      self:stow_helper("tie my " .. item:short_name() .. " to my " .. item.tie_to, item:short_name())
    elseif item.wield then
      self:stow_helper("sheath my " .. item:short_name(), item:short_name())
    elseif item.container then
      self:stow_helper("put my " .. item:short_name() .. " into my " .. item.container, item:short_name())
    else
      DRC.bput("stow my " .. item:short_name(),
        "You put", "You tuck", "There isn't any more room",
        "straps have all been used", "is too long to fit")
    end
    if waitrt then waitrt() end
    return true
  end

  --- Stow helper with retry logic for common recovery scenarios.
  function em.stow_helper(self, action, weapon_name, retries)
    retries = retries or M.STOW_HELPER_MAX_RETRIES
    if retries <= 0 then
      respond("[EquipMgr] stow_helper exceeded max retries for: " .. action)
      return
    end

    local all = {}
    -- Add sheath/put success patterns
    for _, p in ipairs(M.SHEATH_SUCCESS) do all[#all + 1] = p end
    if DRCI then
      for _, p in ipairs(DRCI.PUT_AWAY_SUCCESS or {}) do all[#all + 1] = p end
      for _, p in ipairs(DRCI.TIE_ITEM_SUCCESS or {}) do all[#all + 1] = p end
      for _, p in ipairs(DRCI.WEAR_ITEM_SUCCESS or {}) do all[#all + 1] = p end
    end
    -- Recovery patterns
    all[#all + 1] = "unload"
    all[#all + 1] = "close the fan"
    all[#all + 1] = "You are a little too busy"
    all[#all + 1] = "You don't seem to be able to move"
    all[#all + 1] = "is too small to hold that"
    all[#all + 1] = "Your wounds hinder"
    all[#all + 1] = "Sheathe your .* where"

    local result = DRC.bput(action, unpack(all))

    if result:find("unload") then
      self:unload_weapon(weapon_name)
      self:stow_helper(action, weapon_name, retries - 1)
    elseif result:find("close the fan") then
      fput("close my " .. weapon_name)
      self:stow_helper(action, weapon_name, retries - 1)
    elseif result:find("little too busy") then
      DRC.retreat()
      self:stow_helper(action, weapon_name, retries - 1)
    elseif result:find("seem to be able to move") then
      pause(1)
      self:stow_helper(action, weapon_name, retries - 1)
    elseif result:find("too small") then
      fput("swap my " .. weapon_name)
      self:stow_helper(action, weapon_name, retries - 1)
    elseif result:find("wounds hinder") or result:find("Sheathe your") then
      self:stow_helper("stow my " .. weapon_name, weapon_name, retries - 1)
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

  --- Unload a ranged weapon.
  function em.unload_weapon(self, name)
    if not name then return end
    DRC.bput("unload my " .. name,
      "You unload", "falls .* to your feet",
      "As you release", "isn't loaded",
      "You can't unload", "You don't have a ranged",
      "You must be holding")
    if waitrt then waitrt() end
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
      self:stow_helper("sheath my " .. weapon:short_name(), weapon:short_name())
    elseif weapon.worn then
      self:stow_helper("wear my " .. weapon:short_name(), weapon:short_name())
    elseif weapon.tie_to then
      self:stow_helper("tie my " .. weapon:short_name() .. " to my " .. weapon.tie_to, weapon:short_name())
    elseif weapon.container then
      self:stow_helper("put my " .. weapon:short_name() .. " in my " .. weapon.container, weapon:short_name())
    else
      self:stow_helper("stow my " .. weapon:short_name(), weapon:short_name())
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
          self:stow_helper("wear my " .. info:short_name(), info:short_name())
        elseif info.tie_to then
          self:stow_helper("tie my " .. info:short_name() .. " to my " .. info.tie_to, info:short_name())
        elseif info.wield then
          self:stow_helper("sheath my " .. info:short_name(), info:short_name())
        elseif info.container then
          self:stow_helper("put my " .. info:short_name() .. " in my " .. info.container, info:short_name())
        else
          self:stow_helper("stow my " .. info:short_name(), info:short_name())
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
