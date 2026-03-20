-- resource.lua — profession resource / Voln favor / suffusion scraping and DB refresh
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local db_mod  = require("gs/invdb/db")
local lumnis  = require("gs/invdb/lumnis")

-- ---------------------------------------------------------------------------
-- resource — scrape `resource` command
-- Returns: { energy, weekly, total, suffused, favor } or nil on error
-- ---------------------------------------------------------------------------
function M.resource()
  local cmd   = "resource"
  local start = "^<output class=\"mono"
  local ep    = "^(?:<popBold/>)?<prompt"

  local data = quiet_command(cmd, start, ep, 5)
  if not data or #data == 0 then
    respond("invdb: error checking resource")
    return nil
  end

  local res = {
    energy   = "",
    weekly   = 0,
    total    = 0,
    suffused = 0,
    favor    = 0,
  }

  -- Pattern captures "Key: value(rest" or "(Weekly) value"
  local pat = "([A-Z][^(]-:?|%(Weekly%))[%s]+([^%(]*)"

  for _, line in ipairs(data) do
    -- Strip bold tags
    local clean = line:gsub("<pushBold/>", ""):gsub("<popBold/>", "")

    -- Scan for "Key: value/max" or "(Weekly) value/max" pairs
    for raw_key, raw_val in clean:gmatch(pat) do
      -- Split on / or ( to separate value from max
      local val_str, max_str = raw_val:match("^([%d,]+)%s*/?%s*([%d,]*)")
      if not val_str then goto continue end

      -- Normalize key: remove trailing colon, strip "Voln " prefix,
      -- collapse "Suffused..." to "Suffused", lowercase
      local key = raw_key
        :gsub(":$", "")
        :match("^%s*(.-)%s*$")
        :gsub("^%(Weekly%)", "weekly")
        :gsub("^Voln ", "")
        :gsub("(Suffused).*$", "%1")
        :lower()

      local val = tonumber(val_str:gsub(",", "")) or 0
      local max = max_str and (tonumber(max_str:gsub(",", ""))) or nil

      if max == 50000 then
        -- This is the weekly guild energy line
        res.energy = key
        res.weekly = val
      elseif max == 200000 then
        -- Total pool
        res.total = val
      elseif key == "favor" then
        res.favor = val
      elseif key == "suffused" then
        res.suffused = val
      end

      ::continue::
    end
  end

  return res
end

-- ---------------------------------------------------------------------------
-- resource_update — upsert resource data into DB
-- Checks lumnis restart status and zeroes weekly if so
-- ---------------------------------------------------------------------------
function M.resource_update(conn, character_id, res)
  if not res then return end
  -- Skip if no profession resource and no favor
  if (res.energy == "" or res.energy == nil) and (res.favor == 0 or res.favor == nil) then
    return
  end

  local ts = db_mod.now()

  -- Ensure row exists
  local existing = conn:scalar(
    "SELECT character_id FROM resource WHERE character_id = :character_id",
    { character_id = character_id })
  if not existing then
    db_mod.exec(conn,
      "INSERT INTO resource (character_id) VALUES (:character_id)",
      { character_id = character_id })
  end

  -- Check lumnis status to zero out weekly if at restart boundary
  if res.energy and res.energy ~= "" then
    local lumnis_status, lumnis_ts = lumnis.lumnis_status_lookup(conn, character_id)
    if lumnis_ts and (os.time() - lumnis_ts) < 60 then
      -- Recent lumnis data available
      if lumnis_status == "restart" then res.weekly = 0 end
    else
      -- Refresh lumnis data
      lumnis.lumnis_refresh(conn, character_id)
      lumnis_status, _ = lumnis.lumnis_status_lookup(conn, character_id)
      if lumnis_status == "restart" then res.weekly = 0 end
    end
  end

  db_mod.exec(conn, [[
    UPDATE resource SET
        energy    = coalesce(:energy, '')
      , weekly    = :weekly
      , total     = :total
      , suffused  = :suffused
      , favor     = :favor
      , timestamp = :timestamp
    WHERE character_id = :character_id
      AND (weekly  <> :weekly
        OR total   <> :total
        OR favor   <> :favor
      )
  ]], {
    character_id = character_id,
    energy       = res.energy   or "",
    weekly       = res.weekly   or 0,
    total        = res.total    or 0,
    suffused     = res.suffused or 0,
    favor        = res.favor    or 0,
    timestamp    = ts,
  })
end

-- ---------------------------------------------------------------------------
-- resource_refresh — scrape and persist resource data
-- ---------------------------------------------------------------------------
function M.resource_refresh(conn, character_id)
  local res = M.resource()
  if not res then return end
  M.resource_update(conn, character_id, res)
end

-- ---------------------------------------------------------------------------
-- resource_query — query and print resource table
-- ---------------------------------------------------------------------------
function M.resource_query(conn, params)
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
      , substr(c.prof,1,3) AS pro
      , c.level AS lvl
      , e.energy
      , e.weekly
      , e.total
      , e.suffused
      , e.bonus
      , e.favor
      , e.timestamp AS updated
    FROM resource e
      INNER JOIN character c ON e.character_id = c.id
  ]] .. where .. "\n    ORDER BY c.account, c.name"

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb resource_query error: " .. err); return end

  local util = require("gs/invdb/util")
  respond(util.format_table(rows))
end

return M
