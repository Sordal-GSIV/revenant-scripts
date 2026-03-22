-- bounty_tracker.lua — bounty task scraping and DB refresh
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local db_mod = require("gs/invdb/db")

-- ---------------------------------------------------------------------------
-- bounty_parse — parse Bounty.task into structured data
-- Returns: { type, area, requirements, task }
-- Bounty.task is the plain-text task description from the bounty stream.
-- ---------------------------------------------------------------------------
function M.bounty_parse()
  local task = Bounty.task or ""
  task = task:match("^%s*(.-)%s*$")

  local btype = ""
  local area  = ""
  local req   = ""

  if task == "" then
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Check for succeeded
  if task:lower():find("succeeded") then
    req = "Succeeded"
    return { type = "succeeded", area = area, requirements = req, task = task }
  end

  -- Herb bounty: "collect N <herb> from <area>"
  local n_herb, herb, herb_area = task:match("collect (%d+) (.-) from the (.+)$")
  if n_herb and herb then
    btype = "herb"
    area  = herb_area and herb_area:match("^%s*(.-)%s*$") or ""
    req   = string.format("%s %s %s", n_herb, herb, area)
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Gem bounty: "collect N <gem(s)>"
  local n_gem, gem = task:match("collect (%d+) (.*gems?)")
  if n_gem and gem then
    btype = "gem"
    req   = string.format("%s %s", n_gem, gem:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Skin bounty: "skin N <quality> <creature(s)>"
  local n_skin, quality, skin_creature = task:match("skin (%d+) (%w+) (.*)")
  if n_skin and quality and skin_creature then
    btype = "skin"
    req   = string.format("%s %s %s", n_skin, quality, skin_creature:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Escort bounty: "escort .* from <start> to <destination>"
  local escort_start, escort_dest = task:match("from (.+) to (.+)$")
  if escort_start and task:lower():find("escort") then
    btype = "escort"
    req   = string.format("%s to %s",
      escort_start:match("^%s*(.-)%s*$"),
      escort_dest:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Heirloom / item retrieval: "retrieve .* from .* creature"
  local action_item, item_creature = task:match("(retrieve .+) from a? ?(.*)")
  if action_item and item_creature and task:lower():find("retrieve") then
    btype = "item"
    req   = string.format("%s from %s", action_item, item_creature:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Cull / kill / bandit / dangerous creature: "kill N <creature(s)>"
  local n_kill, kill_creature = task:match("kill (%d+) (.*)")
  if n_kill and kill_creature then
    btype = "creature"
    -- Extract area if present ("in <area>")
    local karea = kill_creature:match(" in the? (.+)$")
    if karea then
      area = karea:match("^%s*(.-)%s*$")
      kill_creature = kill_creature:match("^(.+) in the?")
    end
    req = string.format("%s %s", n_kill, kill_creature:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Bandit / assist bounty: "assist (N) <creature(s)>"
  local assist_n, assist_creature = task:match("assist (%d+) (.*)")
  if not assist_n then
    assist_creature = task:match("assist (.*)")
  end
  if assist_creature then
    btype = "bandit"
    req   = string.format("assist %s %s", assist_n or "", assist_creature:match("^%s*(.-)%s*$"))
    return { type = btype, area = area, requirements = req, task = task }
  end

  -- Fallback: store raw task with unknown type
  req = task
  return { type = btype, area = area, requirements = req, task = task }
end

-- ---------------------------------------------------------------------------
-- bounty_update — upsert bounty data into DB
-- ---------------------------------------------------------------------------
function M.bounty_update(conn, character_id, b)
  local ts = db_mod.now()

  -- Ensure row exists
  local existing = conn:scalar(
    "SELECT character_id FROM bounty WHERE character_id = :character_id",
    { character_id = character_id })
  if not existing then
    db_mod.exec(conn,
      "INSERT INTO bounty (character_id) VALUES (:character_id)",
      { character_id = character_id })
  end

  db_mod.exec(conn, [[
    UPDATE bounty SET
        type         = :type
      , area         = :area
      , requirements = :requirements
      , task         = :task
      , timestamp    = :timestamp
    WHERE character_id = :character_id
      AND (type         <> :type
        OR area         <> :area
        OR requirements <> :requirements
        OR task         <> :task
      )
  ]], {
    character_id = character_id,
    type         = b.type         or "",
    area         = b.area         or "",
    requirements = b.requirements or "",
    task         = b.task         or "",
    timestamp    = ts,
  })
end

-- ---------------------------------------------------------------------------
-- bounty_refresh — parse and persist bounty data
-- ---------------------------------------------------------------------------
function M.bounty_refresh(conn, character_id)
  local b = M.bounty_parse()
  M.bounty_update(conn, character_id, b)
end

-- ---------------------------------------------------------------------------
-- bounty_query — query and print bounty table
-- ---------------------------------------------------------------------------
function M.bounty_query(conn, params)
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
        c.name
      , bo.type
      , bo.area
      , bo.requirements
      , bo.timestamp AS updated
      , bo.task
    FROM bounty bo
      INNER JOIN character c ON bo.character_id = c.id
  ]] .. where .. "\n    ORDER BY c.account, c.name"

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb bounty_query error: " .. err); return end

  local util = require("gs/invdb/util")
  respond(util.format_table(rows))
end

return M
