-- bank.lua — bank accounts, silvers, tickets scraping and refresh
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local db_mod = require("gs/invdb/db")

-- ---------------------------------------------------------------------------
-- bank_account — scrape `bank account` command
-- Returns: { bank_name = amount, ..., Total = total }
-- ---------------------------------------------------------------------------
function M.bank_account()
  local cmd   = "bank account"
  local start = "^You currently have the following amounts on deposit|You currently have an account|You haven't opened a bank account yet"
  local ep    = "^(?:<popBold/>)?<prompt"

  local result = quiet_command(cmd, start, ep, 5)
  local accounts = {}

  -- patterns
  local pat_multi  = " *(.+): ([%d,]+)"
  local pat_single = "You currently have an account with the (.-)%s+in the amount of ([%d,]+) silver"
  local pat_none   = "You haven't opened a bank account yet"

  for _, line in ipairs(result) do
    if line:find(pat_none:sub(1,20), 1, true) then
      break
    end
    local bank, amount = line:match(pat_single)
    if bank then
      amount = tonumber(amount:gsub(",", "")) or 0
      accounts[bank] = amount
      accounts["Total"] = amount
    else
      bank, amount = line:match(pat_multi)
      if bank and amount then
        amount = tonumber(amount:gsub(",", "")) or 0
        accounts[bank:match("^%s*(.-)%s*$")] = amount
      end
    end
  end

  return accounts
end

-- ---------------------------------------------------------------------------
-- bank_merge — merge bank account data into DB
-- ---------------------------------------------------------------------------
function M.bank_merge(conn, character_id)
  local ts = db_mod.now()
  local accounts = M.bank_account()

  -- Create temp_silver if not exists
  db_mod.exec(conn, [[
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_silver (
        character_id   INTEGER NOT NULL
      , bank           TEXT    NOT NULL
      , amount         INTEGER NOT NULL
      , timestamp      INTEGER NOT NULL
      , UNIQUE(character_id, bank)
    )]])

  -- Insert into temp
  local ins_sql = "INSERT OR REPLACE INTO temp_silver (character_id, bank, amount, timestamp) VALUES (:character_id, :bank, :amount, :timestamp)"
  for bank_name, amount in pairs(accounts) do
    db_mod.exec(conn, ins_sql, {
      character_id = character_id,
      bank         = bank_name,
      amount       = amount,
      timestamp    = ts,
    })
  end

  -- Delete removed banks
  db_mod.exec(conn, [[
    DELETE FROM silver
    WHERE silver.character_id = :character_id
      AND NOT EXISTS (
        SELECT 1 FROM temp_silver t
          INNER JOIN bank b ON t.bank = b.name
        WHERE t.character_id = silver.character_id
          AND b.id = silver.bank_id
      )]], { character_id = character_id })

  -- Update existing
  db_mod.exec(conn, [[
    WITH cte (character_id, bank_id, amount, timestamp) AS (
      SELECT t.character_id, b.id, t.amount, t.timestamp
      FROM temp_silver t
        INNER JOIN bank b ON t.bank = b.name
    )
    UPDATE silver SET
        amount    = (SELECT amount    FROM cte WHERE silver.character_id = cte.character_id AND silver.bank_id = cte.bank_id AND silver.amount <> cte.amount)
      , timestamp = (SELECT timestamp FROM cte WHERE silver.character_id = cte.character_id AND silver.bank_id = cte.bank_id AND silver.amount <> cte.amount)
    WHERE EXISTS (
      SELECT 1 FROM cte
      WHERE silver.character_id = cte.character_id
        AND silver.bank_id = cte.bank_id
        AND silver.amount <> cte.amount
    )]])

  -- Insert new
  db_mod.exec(conn, [[
    WITH cte (character_id, bank_id, amount, timestamp) AS (
      SELECT t.character_id, b.id, t.amount, t.timestamp
      FROM temp_silver t
        INNER JOIN bank b ON t.bank = b.name
    )
    INSERT INTO silver (character_id, bank_id, amount, timestamp)
      SELECT character_id, bank_id, amount, timestamp
      FROM cte
      WHERE NOT EXISTS (
        SELECT 1 FROM silver i
        WHERE i.character_id = cte.character_id
          AND i.bank_id      = cte.bank_id
      )
      ORDER BY character_id, bank_id]])

  -- Clean up temp
  db_mod.exec(conn, "DELETE FROM temp_silver WHERE character_id = :character_id",
              { character_id = character_id })
end

-- ---------------------------------------------------------------------------
-- bank_refresh
-- ---------------------------------------------------------------------------
function M.bank_refresh(conn, character_id)
  M.bank_merge(conn, character_id)
end

-- ---------------------------------------------------------------------------
-- ticket_balance — scrape `ticket balance` command
-- Returns: list of { source, amount, currency }
-- ---------------------------------------------------------------------------
function M.ticket_balance()
  local cmd   = "ticket balance"
  local start = "You take a moment to recall the alternative"
  local ep    = "^(?:<popBold/>)?<prompt"

  local data = quiet_command(cmd, start, ep, 5)
  local balances = {}

  local pat_none  = "You haven't collected any alternative currencies"
  local pat_split = "^ +(.-)%s+%- ([%d,]+) (.-)%."

  local joined = table.concat(data, "\n")
  if joined:find(pat_none:sub(1, 25), 1, true) then
    return balances
  end

  for _, line in ipairs(data) do
    local src, amt, cur = line:match(pat_split)
    if src then
      table.insert(balances, {
        source   = src:match("^%s*(.-)%s*$"),
        amount   = tonumber(amt:gsub(",", "")) or 0,
        currency = cur:match("^%s*(.-)%s*$"),
      })
    end
  end

  return balances
end

-- ---------------------------------------------------------------------------
-- ticket_merge — merge ticket balance data into DB
-- ---------------------------------------------------------------------------
function M.ticket_merge(conn, character_id)
  local ts     = db_mod.now()
  local tickets = M.ticket_balance()

  if #tickets == 0 then
    -- delete all tickets for this character
    db_mod.exec(conn, "DELETE FROM tickets WHERE character_id = :character_id",
                { character_id = character_id })
    return
  end

  -- Create temp_tickets
  db_mod.exec(conn, [[
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_tickets (
        character_id   INTEGER NOT NULL
      , source         TEXT    NOT NULL
      , amount         INTEGER NOT NULL
      , currency       TEXT    NOT NULL
      , timestamp      INTEGER NOT NULL
      , UNIQUE(character_id, source)
    )]])

  -- Insert into temp
  local ins = "INSERT OR REPLACE INTO temp_tickets (character_id, source, amount, currency, timestamp) VALUES (:character_id, :source, :amount, :currency, :timestamp)"
  for _, t in ipairs(tickets) do
    db_mod.exec(conn, ins, {
      character_id = character_id,
      source       = t.source,
      amount       = t.amount,
      currency     = t.currency,
      timestamp    = ts,
    })
  end

  -- Delete removed tickets
  db_mod.exec(conn, [[
    DELETE FROM tickets
    WHERE tickets.character_id = :character_id
      AND NOT EXISTS (
        SELECT 1 FROM temp_tickets t
        WHERE t.character_id = tickets.character_id
          AND t.source       = tickets.source
          AND t.currency     = tickets.currency
      )]], { character_id = character_id })

  -- Update changed amounts
  db_mod.exec(conn, string.format([[
    WITH cte (character_id, source, amount, currency) AS (
      SELECT t.character_id, t.source, t.amount, t.currency
      FROM temp_tickets t
      WHERE t.character_id = %d
    )
    UPDATE tickets SET
        amount    = (SELECT amount FROM cte WHERE tickets.character_id = cte.character_id AND tickets.source = cte.source AND tickets.amount <> cte.amount AND tickets.currency = cte.currency)
      , timestamp = %d
    WHERE tickets.character_id = %d
      AND EXISTS (
        SELECT 1 FROM cte
        WHERE tickets.character_id = cte.character_id
          AND tickets.source = cte.source
          AND tickets.amount <> cte.amount
          AND tickets.currency = cte.currency
      )]], character_id, ts, character_id))

  -- Insert new
  db_mod.exec(conn, string.format([[
    WITH cte (character_id, source, amount, currency) AS (
      SELECT t.character_id, t.source, t.amount, t.currency
      FROM temp_tickets t
      WHERE t.character_id = %d
    )
    INSERT INTO tickets (character_id, source, amount, currency, timestamp)
      SELECT character_id, source, amount, currency, %d
      FROM cte
      WHERE NOT EXISTS (
        SELECT 1 FROM tickets i
        WHERE i.character_id = cte.character_id
          AND i.source       = cte.source
          AND i.currency     = cte.currency
      )
      ORDER BY character_id, source]], character_id, ts))

  -- Clean up temp
  db_mod.exec(conn, "DELETE FROM temp_tickets WHERE character_id = :character_id",
              { character_id = character_id })
end

-- ---------------------------------------------------------------------------
-- ticket_refresh
-- ---------------------------------------------------------------------------
function M.ticket_refresh(conn, character_id)
  M.ticket_merge(conn, character_id)
end

-- ---------------------------------------------------------------------------
-- ticket_delete — delete tickets for current character
-- ---------------------------------------------------------------------------
function M.ticket_delete(conn, character_id)
  if character_id then
    db_mod.exec(conn, "DELETE FROM tickets WHERE character_id = :character_id",
                { character_id = character_id })
  end
end

return M
