-- lumnis.lua — Gift of Lumnis status scraping and DB refresh
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local db_mod = require("gs/invdb/db")

-- ---------------------------------------------------------------------------
-- lumnis_status_lookup — fetch current lumnis status from DB
-- Returns: status (string), timestamp (integer)
-- ---------------------------------------------------------------------------
function M.lumnis_status_lookup(conn, character_id)
  local row = conn:query2(
    "SELECT status, timestamp FROM lumnis WHERE character_id = :character_id LIMIT 1",
    { character_id = character_id })
  if row and #row > 1 then
    return row[2][1], row[2][2]
  end
  return nil, nil
end

-- ---------------------------------------------------------------------------
-- lumnis_info — scrape `lumnis info` command
-- Returns: table with lumnis_status, double, triple, total, start_day,
--          start_time, last_schedule; or nil on f2p / error
-- ---------------------------------------------------------------------------
function M.lumnis_info()
  local cmd   = "lumnis info"
  local start = "^You have %d+|Your Gift of Lumnis|^Because your account is free"
  local ep    = "^(?:<popBold/>)?<prompt"

  local data = quiet_command(cmd, start, ep, 5)
  if not data or #data == 0 then
    respond("invdb: error checking lumnis info")
    return nil
  end

  local info = {
    lumnis_status = "",
    double        = 0,
    triple        = 0,
    total         = 0,
    start_day     = "",
    start_time    = "",
    last_schedule = "",
  }

  local joined = table.concat(data, "\n")
  -- Free-to-play: no lumnis
  if joined:find("Because your account is free, you do not have access", 1, true) then
    return nil
  end

  for _, line in ipairs(data) do
    -- "N points of triple/double"
    for val, key in line:gmatch("(%d[%d,]*) points of (triple|double)") do
      local n = tonumber(val:gsub(",", "")) or 0
      info[key] = n
    end
    -- "Your Gift of Lumnis has/will expired/restart"
    local stat = line:match("Your Gift of Lumnis (?:has|will) (expired|restart)")
    if stat then
      info.lumnis_status = stat
      if stat == "restart" then
        info.double = 7300
        info.triple = 7300
      end
    end
    -- "scheduled to start on <day>s at <time>"
    local sday, stime = line:match("scheduled to start on (%w+)s at (%d%d:%d%d)")
    if sday then
      info.start_day  = sday
      info.start_time = stime
    end
    -- "You last used a Lumnis scheduling option on <date>."
    local ls = line:match("You last used a Lumnis scheduling option on ([^%.]+)%.")
    if ls then
      info.last_schedule = ls:match("^%s*(.-)%s*$")
    end
  end

  info.total = (info.triple * 2) + info.double
  return info
end

-- ---------------------------------------------------------------------------
-- lumnis_update — upsert lumnis data into DB
-- ---------------------------------------------------------------------------
function M.lumnis_update(conn, character_id, info)
  local ts = db_mod.now()

  -- Ensure row exists
  local existing = conn:scalar(
    "SELECT character_id FROM lumnis WHERE character_id = :character_id",
    { character_id = character_id })
  if not existing then
    db_mod.exec(conn,
      "INSERT INTO lumnis (character_id) VALUES (:character_id)",
      { character_id = character_id })
  end

  db_mod.exec(conn, [[
    UPDATE lumnis SET
        status        = :status
      , triple        = :triple
      , double        = :double
      , total         = :total
      , start_day     = :start_day
      , start_time    = :start_time
      , last_schedule = :last_schedule
      , timestamp     = :timestamp
    WHERE character_id = :character_id
  ]], {
    character_id  = character_id,
    status        = info.lumnis_status or "",
    triple        = info.triple        or 0,
    double        = info.double        or 0,
    total         = info.total         or 0,
    start_day     = info.start_day     or "",
    start_time    = info.start_time    or "",
    last_schedule = info.last_schedule or "",
    timestamp     = ts,
  })
end

-- ---------------------------------------------------------------------------
-- lumnis_refresh — scrape and persist lumnis data
-- ---------------------------------------------------------------------------
function M.lumnis_refresh(conn, character_id)
  local info = M.lumnis_info()
  if not info then return end
  M.lumnis_update(conn, character_id, info)
end

-- ---------------------------------------------------------------------------
-- lumnis_query — query and print lumnis table
-- ---------------------------------------------------------------------------
function M.lumnis_query(conn, params)
  params = params or {}

  local where_parts = {}
  local qargs = {}

  local game = GameState.game or "GS3"
  qargs.game_filter = game
  table.insert(where_parts, "LOWER(c.game) LIKE LOWER(:game_filter)")

  if params.character then
    qargs.character_filter = params.character:gsub("%*", "%%")
    table.insert(where_parts, "c.name LIKE :character_filter")
  end

  local where = #where_parts > 0
    and ("\n    WHERE " .. table.concat(where_parts, "\n      AND "))
    or ""

  local sql = [[
    SELECT
        c.account
      , c.name
      , lower(c.game) AS game
      , u.status
      , u.triple
      , u.double
      , u.total
      , u.start_day
      , u.start_time
      , u.last_schedule
      , u.timestamp AS updated
    FROM lumnis u
      INNER JOIN character c ON u.character_id = c.id
  ]] .. where .. "\n    ORDER BY c.account, c.name"

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb lumnis_query error: " .. err); return end

  local util = require("gs/invdb/util")
  respond(util.format_table(rows))
end

return M
