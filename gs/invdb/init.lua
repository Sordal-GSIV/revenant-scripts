-- @name         invdb
-- @description  Cross-character inventory database — items, lockers, bank, bounty, lumnis, resource
-- @author       Xanlin (original), Revenant port by Sordal
-- @original     invdb-beta.lic v20250606.1 by Xanlin
-- @game         GemStone IV
-- @tags         inventory, bank, locker, items, database
-- @gui          false
-- @lic-certified: complete 2026-03-19
--
-- Changelog:
--   20260319.1  Revenant port: converted invdb-beta.lic to Lua folder script.
--               Implemented missing Sqlite API in Rust (engine/src/lua_api/sqlite.rs).
--               Full feature parity with original; see help.lua for details.

-- ---------------------------------------------------------------------------
-- Module imports
-- ---------------------------------------------------------------------------
local db_mod    = require("gs/invdb/db")
local schema    = require("gs/invdb/schema")
local settings_mgr = require("gs/invdb/settings_mgr")
local query_mod = require("gs/invdb/query")
local inv_mod   = require("gs/invdb/inventory")
local locker    = require("gs/invdb/locker")
local bank      = require("gs/invdb/bank")
local bounty    = require("gs/invdb/bounty_tracker")
local lumnis    = require("gs/invdb/lumnis")
local resource  = require("gs/invdb/resource")
local help      = require("gs/invdb/help")
local util      = require("gs/invdb/util")

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------
local args_str = Script.args or ""

-- ---------------------------------------------------------------------------
-- Handle --settings flag before full startup
-- ---------------------------------------------------------------------------
if args_str:match("%-%-settings") or args_str:match("%-%-help") then
  local settings = settings_mgr.load()
  settings_mgr.print_settings(settings, Script.name or "invdb")
  return
end

-- ---------------------------------------------------------------------------
-- Help / changelog / version shortcuts
-- ---------------------------------------------------------------------------
local script_name = Script.name or "invdb"
if args_str:lower():match("^help") or args_str:lower():match("^%?") then
  help.print_help(script_name)
  return
end
if args_str:lower():match("^examples?") then
  help.print_examples(script_name)
  return
end
if args_str:lower():match("^changelog") then
  help.print_changelog(script_name)
  return
end
if args_str:lower():match("^version") then
  help.print_version()
  return
end

-- ---------------------------------------------------------------------------
-- Load settings; handle per-invocation --setting=value mutations
-- ---------------------------------------------------------------------------
local settings = settings_mgr.load()

-- Apply any --key=value flags from args
local clean_args = args_str
for arg in args_str:gmatch("%-%-[%w_=: ]+") do
  if settings_mgr.apply_boolean(settings, arg)
    or settings_mgr.apply_string(settings, arg)
    or settings_mgr.apply_integer(settings, arg) then
    -- strip handled flags from args being passed to parser
    clean_args = clean_args:gsub(arg:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%0"), "")
  end
end

-- Handle delay= autostart delay
local delay_secs = clean_args:match("delay=(%d+)")
if delay_secs then
  pause(tonumber(delay_secs))
  clean_args = clean_args:gsub("delay=%d+", "")
end

-- ---------------------------------------------------------------------------
-- Parse action / target / params
-- ---------------------------------------------------------------------------
local action, target, params = query_mod.parse_args(clean_args:match("^%s*(.-)%s*$"))

-- ---------------------------------------------------------------------------
-- Open / migrate DB
-- ---------------------------------------------------------------------------
local conn, open_err = Sqlite.open("invdb.db")
if not conn then
  respond("invdb: could not open database: " .. (open_err or "unknown error"))
  return
end

-- Register REGEXP function for query operations
conn:create_regexp_function()

local ok, migrate_err = pcall(schema.migrate, conn)
if not ok then
  respond("invdb: schema migration failed: " .. tostring(migrate_err))
  conn:close()
  return
end

-- Create temp tables (idempotent each session)
local ok2, temp_err = pcall(schema.create_temp_tables, conn)
if not ok2 then
  respond("invdb: create_temp_tables failed: " .. tostring(temp_err))
  conn:close()
  return
end

-- Cleanup on script exit
before_dying(function()
  if conn then conn:close() end
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local character_id = nil

local function ensure_character_id()
  if not character_id then
    character_id = db_mod.character_id_get(conn)
  end
  return character_id
end

-- Get account name and subscription from Account object or DB fallback
local account_name = nil
local subscription = nil
local locker_location = nil

local function ensure_account()
  if account_name and subscription then return end

  -- Try Account global first
  if Account and Account.name and #Account.name > 2 then
    account_name = Account.name
    local sub = Account.subscription and Account.subscription:lower() or ""
    if sub:match("^free") then
      subscription = "f2p"
    elseif sub:match("internal") then
      subscription = "premium"
      locker_location = "multi"
    else
      subscription = sub ~= "" and sub or "standard"
    end
    return
  end

  -- Scrape `account` command
  local data = quiet_command("account", "^<pushBold/>(?:Game|Account)", nil, 5)
  if data and #data > 0 then
    for _, line in ipairs(data) do
      local label, val = line:match("<pushBold/>([^<]+)<popBold/> *(.*)")
      if label and val then
        val = val:match("^%s*(.-)%s*$")
        if label:find("Account Name") then
          account_name = val
        elseif label:find("Account Type") or label:find("Subscription") then
          subscription = val:lower()
        end
      end
    end
  end

  -- Normalize subscription
  if subscription then
    if subscription:match("^free") then
      subscription = "f2p"
    elseif subscription:match("premium") or subscription:match("internal") then
      subscription = "premium"
      locker_location = "multi"
    else
      subscription = "standard"
    end
  else
    subscription = "standard"
  end
  account_name = account_name or GameState.account or GameState.name
end

-- ---------------------------------------------------------------------------
-- REFRESH action
-- ---------------------------------------------------------------------------
if action == "refresh" then
  ensure_character_id()

  -- Account info required for char/item/locker/all
  if target:match("^char") or target:match("^item") or target:match("^locker") or target == "all" then
    ensure_account()
    if not locker_location then
      locker_location = locker.locker_info()
    end
  end

  -- Character refresh
  if target:match("^char") or target == "all" then
    respond("invdb: updating character...")
    db_mod.character_refresh(conn)
    character_id = db_mod.character_id_get(conn)
  end

  -- Bounty refresh (skip f2p and low level)
  if target == "bounty" or target == "all" then
    ensure_account()
    local level = Stats.level or 0
    if subscription ~= "f2p" and level >= 10 then
      respond("invdb: updating bounty...")
      bounty.bounty_refresh(conn, character_id)
    end
  end

  -- Lumnis refresh (skip f2p)
  if target == "lumnis" or (target == "all" and settings.lumnis) then
    ensure_account()
    if subscription ~= "f2p" then
      respond("invdb: updating lumnis...")
      lumnis.lumnis_refresh(conn, character_id)
    end
  end

  -- Resource refresh (skip f2p)
  if target == "resource" or (target == "all" and settings.resource) then
    ensure_account()
    if subscription ~= "f2p" then
      respond("invdb: updating resource...")
      resource.resource_refresh(conn, character_id)
    end
  end

  -- Bank refresh
  if target:match("^bank") or target == "all" then
    respond("invdb: updating bank account...")
    bank.bank_refresh(conn, character_id)
  end

  -- Tickets refresh
  if target:match("^tickets?") or target == "all" then
    respond("invdb: updating ticket balance...")
    bank.ticket_refresh(conn, character_id)
  end

  -- Inventory / locker refresh
  if target:match("^inv") or target:match("^locker") or target:match("^item") or target == "all" then
    local loc_filter = nil
    if target:match("^inv") then
      loc_filter = "inv"
    elseif target:match("^locker") then
      loc_filter = "locker"
    end

    respond("invdb: scanning inventory...")

    -- Get locker locations from DB
    local locs = {}
    local loc_rows = conn:query2([[
      SELECT id, type, name, abbr FROM location WHERE type = 'locker' ORDER BY id
    ]], {})
    if loc_rows and #loc_rows > 1 then
      for i = 2, #loc_rows do
        local row = loc_rows[i]
        locs[tostring(row[1])] = { id = row[1], type = row[2], name = row[3], abbr = row[4] }
      end
    end

    if loc_filter ~= "locker" then
      inv_mod.refresh_inventory(conn, character_id, settings, "inv")
    end
    if loc_filter ~= "inv" then
      locker.refresh_locker(conn, character_id, settings, account_name, subscription, locker_location, locs)
    end
  end

  -- Maybe vacuum
  db_mod.maybe_vacuum(conn, settings)

  respond("invdb: refresh complete.")

-- ---------------------------------------------------------------------------
-- QUERY action
-- ---------------------------------------------------------------------------
elseif action == "query" or action == "q" then
  query_mod.do_query(conn, "query", target, params, settings)

-- ---------------------------------------------------------------------------
-- SUM action
-- ---------------------------------------------------------------------------
elseif action == "sum" or action == "total" then
  query_mod.do_query(conn, "sum", target, params, settings)

-- ---------------------------------------------------------------------------
-- COUNT action
-- ---------------------------------------------------------------------------
elseif action == "count" or action == "c" then
  query_mod.do_query(conn, "count", target, params, settings)

-- ---------------------------------------------------------------------------
-- EXPORT action
-- ---------------------------------------------------------------------------
elseif action == "export" then
  local fmt = params.format or "csv"
  local export_dir = params.dir or "data/"
  local timestamp  = os.date("%Y%m%d_%H%M%S")
  local filename   = params.file
    or (target .. "_" .. timestamp .. "." .. (fmt == "csv" and "csv" or "txt"))
  local filepath   = export_dir .. filename

  -- Build SQL
  local sql, qargs
  if target:match("^bank$") or target:match("^sbank$") then
    if target == "sbank" then
      sql, qargs = query_mod.sum_bank_sql(params)
    else
      sql, qargs = query_mod.query_bank_sql(params)
    end
  elseif target:match("^tickets?$") or target == "stickets" then
    if target == "stickets" then
      sql, qargs = query_mod.sum_tickets_sql(params)
    else
      sql, qargs = query_mod.query_tickets_sql(params)
    end
  elseif target:match("^char") then
    sql, qargs = query_mod.query_char_sql(params)
  else
    sql, qargs = query_mod.query_item_sql(params, "export")
  end

  local rows, err = conn:query2(sql, qargs)
  if err then
    respond("invdb export error: " .. err)
  elseif not rows or #rows <= 1 then
    respond("invdb: no rows to export for " .. target)
  else
    -- Write to file
    local sep = (fmt == "csv") and "," or (fmt == "pipe" and "|" or "\t")
    local file, ferr = io.open(filepath, "w")
    if not file then
      respond("invdb: could not open export file: " .. (ferr or filepath))
    else
      for _, row in ipairs(rows) do
        local line_parts = {}
        for _, col in ipairs(row) do
          local s = tostring(col or "")
          if fmt == "csv" and s:find("[,\"\n]") then
            s = '"' .. s:gsub('"', '""') .. '"'
          end
          table.insert(line_parts, s)
        end
        file:write(table.concat(line_parts, sep) .. "\n")
      end
      file:close()
      respond(string.format("invdb: exported %d row(s) from %s to %s",
        #rows - 1, target, filepath))
    end
  end

-- ---------------------------------------------------------------------------
-- DELETE action
-- ---------------------------------------------------------------------------
elseif action == "delete" then
  local char_filter = params.character or params.char
  if not char_filter then
    respond("invdb delete: requires char=<name> filter")
  else
    ensure_character_id()
    if target:match("all|char|bank|silver|wealth") then
      -- Delete bank data for character
      conn:exec([[
        DELETE FROM silver WHERE character_id = (
          SELECT id FROM character WHERE name LIKE :char AND game LIKE :game)
      ]], { char = char_filter .. "%", game = GameState.game })
    end
    if target:match("all|tickets") then
      conn:exec([[
        DELETE FROM tickets WHERE character_id = (
          SELECT id FROM character WHERE name LIKE :char AND game LIKE :game)
      ]], { char = char_filter .. "%", game = GameState.game })
    end
    if target:match("all|char|inv|item|locker") then
      conn:exec([[
        DELETE FROM char_inventory WHERE character_id = (
          SELECT id FROM character WHERE name LIKE :char AND game LIKE :game)
      ]], { char = char_filter .. "%", game = GameState.game })
    end
    if target:match("all|char") then
      conn:exec([[
        DELETE FROM character WHERE name LIKE :char AND game LIKE :game
      ]], { char = char_filter .. "%", game = GameState.game })
    end
    respond("invdb: delete complete for char=" .. char_filter)
  end

-- ---------------------------------------------------------------------------
-- RESET action (requires confirm suffix)
-- ---------------------------------------------------------------------------
elseif action == "reset" then
  if not args_str:lower():match("confirm") then
    respond("invdb: reset requires 'confirm' — e.g. ';invdb reset confirm all'")
    respond("invdb: WARNING: this permanently deletes all data for the target.")
  else
    local reset_target = target or "all"
    respond("invdb: resetting " .. reset_target .. "...")
    schema.drop_tables(conn, reset_target)
    respond("invdb: reset complete. Re-run without arguments to rebuild schema.")
  end

-- ---------------------------------------------------------------------------
-- Unrecognized
-- ---------------------------------------------------------------------------
else
  respond("invdb: unknown action '" .. action .. "'. Try ';invdb help'.")
end

conn:close()
conn = nil
