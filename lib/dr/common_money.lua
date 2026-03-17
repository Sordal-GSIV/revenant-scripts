--- DRCM — DR Common Money utilities.
-- Ported from Lich5 common-money.rb (module DRCM).
-- Currency conversion, deposit/withdraw helpers, wealth tracking.
-- @module lib.dr.common_money
local variables = require("lib/dr/variables")

local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

--- Denomination tiers ordered from highest to lowest value.
-- Each entry: { copper_multiplier, name }
M.DENOMINATIONS = {
  { 10000, "platinum" },
  { 1000,  "gold" },
  { 100,   "silver" },
  { 10,    "bronze" },
  { 1,     "copper" },
}

--- Maps denomination name to copper multiplier.
M.DENOMINATION_VALUES = {
  platinum = 10000,
  gold     = 1000,
  silver   = 100,
  bronze   = 10,
  copper   = 1,
}

--- The three DR currencies.
M.CURRENCIES = { "kronars", "lirums", "dokoras" }

--- Exchange rates between currencies.  EXCHANGE_RATES[from][to] = rate
M.EXCHANGE_RATES = {
  dokoras = { dokoras = 1, kronars = 1.385808991, lirums = 1.108646953 },
  kronars = { dokoras = 0.7216, kronars = 1, lirums = 0.8 },
  lirums  = { dokoras = 0.902, kronars = 1.25, lirums = 1 },
}

-------------------------------------------------------------------------------
-- Conversion helpers
-------------------------------------------------------------------------------

--- Break a copper total into denominated display strings.
-- @param copper number Amount in copper
-- @return table Array of strings like "5 platinum", "3 gold"
function M.minimize_coins(copper)
  local display = {}
  local remaining = copper
  for _, denom in ipairs(M.DENOMINATIONS) do
    local mult = denom[1]
    local name = denom[2]
    local count = math.floor(remaining / mult)
    if count > 0 then
      display[#display + 1] = count .. " " .. name
    end
    remaining = remaining % mult
  end
  return display
end

--- Convert an amount to copper given a denomination name (prefix match).
-- @param amount number Numeric amount
-- @param denomination string Denomination name or prefix (e.g., "plat", "g")
-- @return number Copper value
function M.convert_to_copper(amount, denomination)
  if not denomination or denomination == "" then
    respond("[DRCM] Unknown denomination, assuming coppers")
    return math.floor(tonumber(amount) or 0)
  end
  denomination = denomination:lower():gsub("^%s+", ""):gsub("%s+$", "")
  for name, mult in pairs(M.DENOMINATION_VALUES) do
    if name:sub(1, #denomination) == denomination then
      return math.floor((tonumber(amount) or 0) * mult)
    end
  end
  respond("[DRCM] Unknown denomination '" .. denomination .. "', assuming coppers")
  return math.floor(tonumber(amount) or 0)
end

--- Return the canonical currency name from an abbreviation.
-- @param currency string Abbreviation (e.g., "k", "li", "dok")
-- @return string|nil Canonical name ("kronars", "lirums", "dokoras")
function M.get_canonical_currency(currency)
  if not currency then return nil end
  currency = currency:lower()
  for _, c in ipairs(M.CURRENCIES) do
    if c:sub(1, #currency) == currency then
      return c
    end
  end
  return nil
end

--- Convert an amount between DR currencies, accounting for exchange fees.
-- @param amount number Amount in copper of the source currency
-- @param from string Source currency ("kronars", "lirums", "dokoras")
-- @param to string Target currency
-- @param fee number Positive = received after fee; negative = needed to receive target
-- @return number Converted amount in copper of target currency
function M.convert_currency(amount, from, to, fee)
  local rates = M.EXCHANGE_RATES[from]
  if not rates then return amount end
  local rate = rates[to] or 1

  if fee < 0 then
    return math.ceil(math.ceil(amount / rate) / (1 + fee))
  else
    return math.floor(math.ceil(amount * rate) * (1 - fee))
  end
end

--- Get the currency for a hometown.
-- @param hometown string Hometown name (e.g., "Crossings")
-- @return string Currency name (e.g., "Kronars")
function M.hometown_currency(hometown)
  return variables.BANK_CURRENCIES[hometown] or "Kronars"
end

-- Alias for backward compatibility with crafting modules
M.town_currency = M.hometown_currency

-------------------------------------------------------------------------------
-- Wealth checking
-------------------------------------------------------------------------------

--- Check on-hand wealth for a specific currency.
-- @param currency string Currency name (e.g., "kronars")
-- @return number Copper amount on hand
function M.check_wealth(currency)
  local result = DRC.bput("wealth " .. currency,
    "%(%d+ copper " .. currency .. "%)",
    "No " .. currency)
  local coppers = result:match("%((%d+) copper")
  return tonumber(coppers) or 0
end

--- Check on-hand wealth for a hometown's currency.
-- @param hometown string Hometown name
-- @return number Copper amount on hand
function M.wealth(hometown)
  return M.check_wealth(M.hometown_currency(hometown))
end

--- Get total wealth across all currencies.
-- @return table { kronars=number, lirums=number, dokoras=number }
function M.get_total_wealth()
  local result_table = { kronars = 0, lirums = 0, dokoras = 0 }
  -- Issue wealth command and parse each currency line
  put("wealth")
  local timeout_at = os.time() + 5
  while os.time() < timeout_at do
    local line = get()
    if line then
      local coppers, currency = line:match("%((%d+) copper (%a+)%)")
      if coppers and currency then
        local canon = M.get_canonical_currency(currency)
        if canon then
          result_table[canon] = tonumber(coppers) or 0
        end
      end
      if line:find("Wealth:") and result_table.kronars + result_table.lirums + result_table.dokoras > 0 then
        break
      end
    else
      pause(0.1)
    end
  end
  return result_table
end

-------------------------------------------------------------------------------
-- Bank operations
-------------------------------------------------------------------------------

--- Ensure a minimum copper amount is on hand, withdrawing if necessary.
-- @param copper number Minimum copper needed
-- @param settings table Character settings (must have .hometown)
-- @param hometown string|nil Override hometown
-- @return boolean true if enough copper on hand
function M.ensure_copper_on_hand(copper, settings, hometown)
  hometown = hometown or (settings and settings.hometown) or "Crossings"
  local on_hand = M.wealth(hometown)
  if on_hand >= copper then return true end

  local withdrawals = M.minimize_coins(copper - on_hand)
  for _, amount_str in ipairs(withdrawals) do
    if not M.withdraw_exact_amount(amount_str, settings, hometown) then
      return false
    end
  end
  return true
end

--- Withdraw an exact amount from the bank.
-- @param amount_as_string string e.g., "5 platinum"
-- @param settings table Character settings
-- @param hometown string|nil Override hometown
-- @return boolean true on success
function M.withdraw_exact_amount(amount_as_string, settings, hometown)
  hometown = hometown or (settings and settings.hometown) or "Crossings"
  return M.get_money_from_bank(amount_as_string, settings, hometown)
end

--- Go to the bank and withdraw money.
-- @param amount_as_string string e.g., "5 platinum"
-- @param settings table Character settings
-- @param hometown string|nil Override hometown
-- @return boolean true on success
function M.get_money_from_bank(amount_as_string, settings, hometown)
  hometown = hometown or (settings and settings.hometown) or "Crossings"

  -- Walk to bank (requires DRCT and data files)
  -- TODO: DRCT.walk_to(get_data('town')[hometown]['deposit']['id'])

  for _ = 1, 5 do
    local result = DRC.bput("withdraw " .. amount_as_string,
      "The clerk counts", "The clerk tells",
      "The clerk glares at you",
      "You count out", "find a new deposit jar",
      "If you value your hands",
      "Hey!  Slow down!",
      "You don't have that much money",
      "have an account")

    if result:find("clerk counts") or result:find("You count out") then
      return true
    elseif result:find("glares") or result:find("Slow down") then
      pause(15)
    else
      return false
    end
  end
  return false
end

--- Deposit all coins at the bank.
-- @param keep_copper number Copper to keep on hand
-- @param settings table Character settings
-- @param hometown string|nil Override hometown
-- @return number, string Balance in copper and currency name
function M.deposit_coins(keep_copper, settings, hometown)
  if settings and settings.skip_bank then return 0, "Unknown" end
  hometown = hometown or (settings and settings.hometown) or "Crossings"

  -- TODO: DRCT.walk_to(bank room)
  DRC.bput("wealth", "Wealth:")
  DRC.bput("deposit all",
    "you drop all your", "You hand the clerk some coins",
    "You don't have any", "There is no teller here",
    "reached the maximum balance", "You find your jar",
    "Searching methodically")

  -- Withdraw the keep amount
  if keep_copper and keep_copper > 0 then
    local withdrawals = M.minimize_coins(keep_copper)
    for _, amount_str in ipairs(withdrawals) do
      M.withdraw_exact_amount(amount_str, settings, hometown)
    end
  end

  -- Check balance
  local balance_result = DRC.bput("check balance",
    "current balance is",
    "If you would like to open one",
    "As expected, there are",
    "Perhaps you should find a new deposit jar")

  -- Parse balance from response
  local bal_text = balance_result:match("current balance is (.*) %a+s?%.\"$")
                or balance_result:match("As expected, there are (.*) %a+s?%.$")
  local currency = balance_result:match("(Kronars?|Lirums?|Dokoras?)") or "Unknown"
  local balance = 0

  if bal_text then
    -- Parse compound amounts like "5 platinum, 3 gold and 2 silver"
    for amount, denom in bal_text:gmatch("(%d+)%s+(%a+)") do
      balance = balance + M.convert_to_copper(tonumber(amount) or 0, denom)
    end
  end

  return balance, currency
end

--- Check debt amount for a hometown.
-- @param hometown string Hometown name
-- @return number Debt in copper
function M.debt(hometown)
  local currency = M.hometown_currency(hometown)
  local result = DRC.bput("wealth", "(%d+) copper " .. currency, "Wealth:")
  local coppers = result:match("(%d+) copper")
  return tonumber(coppers) or 0
end

return M
