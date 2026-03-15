--- Typed accessor library for UserVars.
---
--- UserVars stores everything as strings (engine serializes via tostring).
--- These helpers coerce on read and supply defaults.

local M = {}

--- Get a raw value with optional default.
function M.get(key, default)
  local val = UserVars[key]
  if val == nil then return default end
  return val
end

--- Get as string. Errors if stored value is not a string type.
function M.get_string(key, default)
  local val = UserVars[key]
  if val == nil then return default end
  if type(val) ~= "string" then
    error("vars.get_string: '" .. key .. "' is not a string (got " .. type(val) .. ")", 2)
  end
  return val
end

--- Get as number. Coerces string representations like "1.5".
--- Errors if the value cannot be converted to a number.
function M.get_number(key, default)
  local val = UserVars[key]
  if val == nil then return default end
  local n = tonumber(val)
  if n == nil then
    error("vars.get_number: '" .. key .. "' cannot be coerced to number (got: " .. tostring(val) .. ")", 2)
  end
  return n
end

--- Get as boolean. Coerces "true"/"false" strings.
--- Errors if the value is not recognisable as boolean.
function M.get_bool(key, default)
  local val = UserVars[key]
  if val == nil then return default end
  if val == "true" or val == true then return true end
  if val == "false" or val == false then return false end
  error("vars.get_bool: '" .. key .. "' cannot be coerced to bool (got: " .. tostring(val) .. ")", 2)
end

--- Set a variable.
function M.set(key, value)
  UserVars[key] = value
end

--- Delete a variable.
function M.unset(key)
  UserVars[key] = nil
end

return M
