--- DRBanking — three-currency bank balance tracking.
-- Ported from Lich5 drbanking.rb
-- @module lib.dr.banking
local variables = require("lib/dr/variables")

local M = {}

-- Internal balances (stored as copper totals)
local balances = {
  Kronars = 0,
  Lirums  = 0,
  Dokoras = 0,
}

--- Parse a balance text string into a copper total.
-- Handles strings like "5 platinum, 3 gold Kronars" or "10 silver, 2 copper".
-- @param text string Balance text from game output
-- @return number Total value in copper
function M.parse_amount(text)
  if not text or text == "" then return 0 end
  local total = 0
  for amount, denom in text:gmatch("(%d+)%s+(%a+)") do
    local mult = variables.DENOMINATIONS[denom]
    if mult then
      total = total + (tonumber(amount) or 0) * mult
    end
  end
  return total
end

--- Set a currency balance and persist via Settings.
-- @param currency string "Kronars", "Lirums", or "Dokoras"
-- @param amount number Balance in copper
function M.set_balance(currency, amount)
  if balances[currency] == nil then return end
  balances[currency] = tonumber(amount) or 0
  -- Persist if Settings API is available
  local ok, Settings = pcall(require, "lib/settings")
  if ok and Settings and Settings.set then
    Settings.set("dr_bank_" .. currency, balances[currency])
  end
end

--- Get the balance for a currency.
-- @param currency string "Kronars", "Lirums", or "Dokoras"
-- @return number Balance in copper, or 0 if unknown
function M.balance(currency)
  return balances[currency] or 0
end

--- Get a copy of all balances.
-- @return table { Kronars=number, Lirums=number, Dokoras=number }
function M.balances()
  return {
    Kronars = balances.Kronars,
    Lirums  = balances.Lirums,
    Dokoras = balances.Dokoras,
  }
end

--- Load persisted balances from Settings.
function M.load()
  local ok, Settings = pcall(require, "lib/settings")
  if not ok or not Settings or not Settings.get then return end
  for _, currency in ipairs(variables.CURRENCIES) do
    local val = Settings.get("dr_bank_" .. currency)
    if val then
      balances[currency] = tonumber(val) or 0
    end
  end
end

return M
