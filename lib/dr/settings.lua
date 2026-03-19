--- DR Settings — get_settings and get_data for DR script compatibility.
-- Implements the Lich5 dr-scripts setup-file API for Revenant.
--
-- get_settings() loads character-specific JSON settings from:
--   1. data/dr/profiles/{charname}-setup.json  (preferred — create this file)
--   2. CharSettings.settings_json              (fallback — JSON-encoded via game)
--
-- get_data(type) loads static base data from:
--   data/dr/base-{type}.json
--
-- To configure, create a JSON file at:
--   scripts/data/dr/profiles/{YourCharName}-setup.json
--
-- Example minimal restock settings:
--   {
--     "hometown": "Crossing",
--     "sell_loot_money_on_hand": "3 silver",
--     "storage_containers": ["backpack"],
--     "restock": {
--       "arrow": { "quantity": 30 },
--       "bolt":  { "quantity": 20 }
--     }
--   }
--
-- @module lib.dr.settings

local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Ordinal strings for iterating stacked items (first, second, ..., twentieth).
M.ORDINALS = {
  "first",     "second",    "third",     "fourth",    "fifth",
  "sixth",     "seventh",   "eighth",    "ninth",     "tenth",
  "eleventh",  "twelfth",   "thirteenth","fourteenth","fifteenth",
  "sixteenth", "seventeenth","eighteenth","nineteenth","twentieth",
}

-------------------------------------------------------------------------------
-- Settings loader
-------------------------------------------------------------------------------

--- Load character-specific settings.
-- Looks for a JSON profile file named after the current character,
-- then falls back to CharSettings.settings_json.
-- @return table Settings table (empty table if nothing found)
function M.get_settings()
  local charname = (GameState and GameState.name) or ""
  charname = charname:lower()

  -- 1. Try per-character JSON profile file
  if charname ~= "" then
    local path = "data/dr/profiles/" .. charname .. "-setup.json"
    if File.exists(path) then
      local ok, data = pcall(function()
        return Json.decode(File.read(path))
      end)
      if ok and type(data) == "table" then
        return data
      end
      respond("[settings] Error parsing " .. path)
    end
  end

  -- 2. Fall back to CharSettings JSON blob
  local raw = CharSettings.settings_json
  if raw and raw ~= "" then
    local ok, data = pcall(Json.decode, raw)
    if ok and type(data) == "table" then
      return data
    end
  end

  respond("[settings] Warning: no settings found.")
  respond("[settings] Create: data/dr/profiles/" .. (charname ~= "" and charname or "charname") .. "-setup.json")
  return {}
end

--- Save settings back to character profile file.
-- Useful for scripts that persist per-run state.
-- @param settings table Settings table to save
-- @return boolean true on success
function M.save_settings(settings)
  local charname = (GameState and GameState.name) or ""
  charname = charname:lower()
  if charname == "" then
    respond("[settings] Cannot save: unknown character name")
    return false
  end

  local path = "data/dr/profiles/" .. charname .. "-setup.json"
  local ok, err = pcall(function()
    File.write(path, Json.encode(settings))
  end)
  if not ok then
    respond("[settings] Error saving settings: " .. tostring(err))
    return false
  end
  return true
end

-------------------------------------------------------------------------------
-- Data file loader
-------------------------------------------------------------------------------

--- Load a static base data file.
-- Reads data/dr/base-{type}.json.
-- @param data_type string Data type (e.g. "consumables", "town", "crafting")
-- @return table Data table (empty table if file not found or parse error)
function M.get_data(data_type)
  local path = "data/dr/base-" .. data_type .. ".json"
  if not File.exists(path) then
    respond("[settings] Warning: data file not found: " .. path)
    return {}
  end

  local ok, data = pcall(function()
    return Json.decode(File.read(path))
  end)
  if ok and type(data) == "table" then
    return data
  end

  respond("[settings] Error parsing data file: " .. path)
  return {}
end

return M
