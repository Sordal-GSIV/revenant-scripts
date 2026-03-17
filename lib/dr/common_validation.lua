--- Common Validation — DR character and script validation utilities.
-- Ported from Lich5 common-validation.rb (class CharacterValidator).
-- Provides character validation, in-game presence checks, and chat helpers.
-- @module lib.dr.common_validation
local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

M.FIND_NOT_FOUND = "There are no adventurers in the realms that match"

-------------------------------------------------------------------------------
-- CharacterValidator
-------------------------------------------------------------------------------

--- Create a new CharacterValidator instance.
-- In Lich5 this is a class that tracks validated characters and sends
-- lnet chat messages. Here we provide a table-based equivalent.
-- @param opts table { announce, should_sleep, greet, name }
-- @return table Validator instance
function M.CharacterValidator(opts)
  opts = opts or {}
  local self = {
    validated_characters = {},
    greet = opts.greet or false,
    name  = opts.name or "script",
  }

  -- Initial setup
  if waitrt then waitrt() end
  if opts.should_sleep then fput("sleep") end

  if opts.announce then
    local room_id = Room and Room.current and Room.current.id or "unknown"
    respond("[Validator] " .. self.name .. " is up in room " .. tostring(room_id))
  end

  --- Check if a character has been validated.
  -- @param character string Character name
  -- @return boolean
  function self.valid(character)
    for _, c in ipairs(self.validated_characters) do
      if c == character then return true end
    end
    return false
  end

  --- Validate a character (check if they exist in game).
  -- @param character string Character name
  function self.validate(character)
    if self.valid(character) then return end
    -- TODO: integrate with lnet when available
    respond("[Validator] Attempting to validate: " .. character)
  end

  --- Confirm a character as validated.
  -- @param character string Character name
  function self.confirm(character)
    if self.valid(character) then return end
    respond("[Validator] Successfully validated: " .. character)
    self.validated_characters[#self.validated_characters + 1] = character

    if self.greet then
      put("whisper " .. character .. " Hi! I'm your friendly neighborhood " ..
        self.name .. ". Whisper me 'help' for more details.")
    end
  end

  --- Check if a character is in game using the FIND command.
  -- @param character string Character name
  -- @return boolean
  function self.in_game(character)
    local result = DRC.bput("find " .. character,
      M.FIND_NOT_FOUND,
      "  " .. character .. ".",
      "Unknown command")
    return result:find(character) ~= nil and not result:find("no adventurers") ~= nil
  end

  return self
end

-------------------------------------------------------------------------------
-- Standalone validation helpers
-------------------------------------------------------------------------------

--- Assert that a setting exists and is not nil/empty.
-- @param value any The value to check
-- @param name string Human-readable name for error messages
-- @return boolean true if valid
function M.assert_exists(value, name)
  if value == nil or value == "" then
    respond("[Validation] Required setting missing: " .. tostring(name))
    return false
  end
  if type(value) == "table" and #value == 0 then
    respond("[Validation] Required setting is empty: " .. tostring(name))
    return false
  end
  return true
end

--- Validate multiple settings at once.
-- @param settings table Settings table
-- @param required table Array of required key names
-- @return boolean true if all valid
function M.validate_settings(settings, required)
  if not settings then
    respond("[Validation] No settings provided.")
    return false
  end
  local all_valid = true
  for _, key in ipairs(required) do
    if not M.assert_exists(settings[key], key) then
      all_valid = false
    end
  end
  return all_valid
end

--- Check that prerequisite scripts exist.
-- @param script_names table|string Script name(s) to check
-- @return boolean true if all exist
function M.check_prereqs(script_names)
  if type(script_names) == "string" then
    script_names = { script_names }
  end
  local all_ok = true
  for _, name in ipairs(script_names) do
    -- TODO: integrate with Script.exists? when available
    -- For now, try to require the script and see if it loads
    local ok = pcall(require, name)
    if not ok then
      respond("[Validation] Required script not found: " .. name)
      all_ok = false
    end
  end
  return all_ok
end

--- Validate that the character's guild matches expectations.
-- @param expected_guild string|table Expected guild name(s)
-- @return boolean
function M.validate_guild(expected_guild)
  if not DRStats or not DRStats.guild then
    respond("[Validation] Cannot check guild — DRStats not available.")
    return false
  end
  local guild = DRStats.guild
  if type(guild) == "function" then guild = guild() end

  if type(expected_guild) == "string" then
    return guild == expected_guild
  elseif type(expected_guild) == "table" then
    for _, g in ipairs(expected_guild) do
      if guild == g then return true end
    end
    respond("[Validation] Guild '" .. tostring(guild) .. "' not in expected list.")
    return false
  end
  return false
end

--- Validate that the character has minimum skill rank.
-- @param skill_name string Skill name
-- @param min_rank number Minimum required rank
-- @return boolean
function M.validate_skill(skill_name, min_rank)
  if not DRSkill or not DRSkill.getrank then
    respond("[Validation] Cannot check skill — DRSkill not available.")
    return false
  end
  local rank = DRSkill.getrank(skill_name)
  if rank < min_rank then
    respond("[Validation] " .. skill_name .. " rank " .. tostring(rank) ..
      " is below minimum " .. tostring(min_rank))
    return false
  end
  return true
end

return M
