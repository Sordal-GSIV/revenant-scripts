-- db.lua — database open/close, execute helpers, character CRUD, item merge
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local DB_NAME = "invdb.db3"

-- ---------------------------------------------------------------------------
-- Open the invdb database.  Returns conn or errors.
-- ---------------------------------------------------------------------------
function M.open()
  local conn, err = Sqlite.open(DB_NAME)
  if not conn then error("invdb: failed to open db: " .. (err or "unknown")) end
  conn:create_regexp_function()
  return conn
end

-- ---------------------------------------------------------------------------
-- Safe execute (non-SELECT).  Returns changes, nil | nil, error.
-- ---------------------------------------------------------------------------
function M.exec(conn, sql, params)
  local changes, err = conn:exec(sql, params)
  if err then
    respond("invdb: SQL error: " .. err)
    return nil, err
  end
  return changes, nil
end

-- ---------------------------------------------------------------------------
-- Safe query2 (SELECT returning array-of-arrays; row[1] = headers).
-- Returns rows table or empty table on error.
-- ---------------------------------------------------------------------------
function M.query2(conn, sql, params)
  local rows, err = conn:query2(sql, params)
  if err then
    respond("invdb: SQL error: " .. err)
    return {{}}
  end
  return rows or {{}}
end

-- ---------------------------------------------------------------------------
-- Safe scalar query.  Returns first value of first row or nil.
-- ---------------------------------------------------------------------------
function M.scalar(conn, sql, params)
  local val, err = conn:scalar(sql, params)
  if err then
    respond("invdb: SQL error: " .. err)
    return nil
  end
  return val
end

-- ---------------------------------------------------------------------------
-- current unix timestamp
-- ---------------------------------------------------------------------------
function M.now() return os.time() end

-- ---------------------------------------------------------------------------
-- Character helpers
-- ---------------------------------------------------------------------------

local function current_area()
  -- Try Room.current (map-backed)
  if Room and Room.current then
    local loc = Room.current.location
    if loc and loc ~= "" then
      return loc
        :gsub("the ?(town|hamlet|city|village|plains|free port|lowlands|tunnels and caverns|foothills|holdings|southern part|northern slopes|northern reaches|environs|somewhere)( o[fn] )?", "")
        :gsub(",.*$", "")
        :gsub("^the ", "")
    end
  end
  -- Fallback: use location verb if not too crowded
  if GameState.room_id == nil then
    local loc_result = dothistimeout("location", 2,
      "You carefully survey your surroundings and guess that your current location is",
      "You can't do that",
      "You are too distracted"
    )
    if loc_result then
      local area = loc_result:match("guess that your current location is (.-) or somewhere close")
      if area then
        return area
          :gsub("the ?(town|hamlet|city|village)", "")
          :gsub(",.*$", "")
          :gsub("^%s*the%s*", "")
      end
    end
  end
  return "unknown"
end

local function society_info()
  local societies = {
    ["Council of Light"]     = "CoL",
    ["Order of Voln"]        = "Voln",
    ["Guardians of Sunfist"] = "GoS",
    ["None"]                 = "none",
  }
  local status = ""
  local rank   = ""
  if Society then
    status = Society.status or ""
    rank   = tostring(Society.rank or "")
  end
  local abbr = societies[status] or status
  return abbr, rank
end

local function citizenship_info()
  if Char and Char.citizenship then
    return Char.citizenship or ""
  end
  return ""
end

-- Returns account_name, subscription.
-- Tries Account module first, then parses the `account` verb.
local function account_get_verb()
  local name_out, sub_out = nil, nil
  local lines = quiet_command("account", "^<pushBold/>(?:Game|Account)", nil, 5)
  for _, l in ipairs(lines) do
    local a, b = l:match("^<pushBold/>(..-)<popBold/> *(.*)")
    if a and a:match("Account Name") then name_out = b:match("^%s*(.-)%s*$") end
    if a and a:match("Account Type|Subscription") then sub_out = b:match("^%s*(.-)%s*$") end
  end
  return name_out, sub_out
end

function M.account_get()
  local name, sub = nil, nil
  -- Try built-in Account module
  if Account then
    if Account.name and #Account.name > 2 then name = Account.name end
    sub = Account.subscription and Account.subscription:lower() or nil
    if sub and sub:match("^free") then sub = "f2p" end
    if sub and sub:match("internal") then sub = "premium" end
  end
  if not name or not sub then
    name, sub = account_get_verb()
  end
  return (name or ""):gsub("^%l", string.upper), (sub or ""):lower()
end

-- ---------------------------------------------------------------------------
-- Character insert (if not exists) — returns character_id
-- ---------------------------------------------------------------------------
function M.character_insert(conn, name, game, account_name, subscription, locker_location)
  name  = name  or GameState.name
  game  = game  or GameState.game
  local area         = current_area()
  local society, society_rank = society_info()
  local citizenship  = citizenship_info()
  local prof = (Stats and Stats.prof) or ""
  local race = (Stats and Stats.race) or ""
  local level = GameState.level or 0
  local exp   = (Stats and Stats.exp) or 0

  local sql = [[
    INSERT INTO character (name, game, account, prof, race, level, exp, area,
                           subscription, locker, citizenship, society, society_rank, timestamp)
    SELECT :name, :game, :account, :prof, :race, :level, :exp, :area,
           :subscription, :locker, :citizenship, :society, :society_rank, :timestamp
    WHERE NOT EXISTS (
      SELECT 1 FROM character WHERE name = :name AND game = :game
    )]]
  M.exec(conn, sql, {
    name         = name,
    game         = game,
    account      = account_name or "",
    prof         = prof,
    race         = race,
    level        = level,
    exp          = exp,
    area         = area,
    subscription = subscription or "",
    locker       = locker_location or "",
    citizenship  = citizenship,
    society      = society,
    society_rank = society_rank,
    timestamp    = M.now(),
  })
  return M.scalar(conn, "SELECT id FROM character WHERE name = :name AND game = :game",
                  { name = name, game = game })
end

-- Insert a "fake" character entry for family vault (premium account locker).
function M.insert_fake_character(conn, account_name, subscription, game)
  game = game or GameState.game
  local name_spoof = account_name .. "_"
  local sql = [[
    INSERT INTO character (name, game, account, prof, race, level, exp, area,
                           subscription, locker, timestamp)
    SELECT :name, :game, :account, '', '', 0, 0, '', :subscription, '', :timestamp
    WHERE NOT EXISTS (SELECT 1 FROM character WHERE name = :name AND game = :game)]]
  M.exec(conn, sql, {
    name = name_spoof, game = game, account = account_name,
    subscription = subscription or "", timestamp = M.now(),
  })
  return M.scalar(conn, "SELECT id FROM character WHERE name = :name AND game = :game",
                  { name = name_spoof, game = game })
end

-- ---------------------------------------------------------------------------
-- Get or create character_id for current character.
-- ---------------------------------------------------------------------------
function M.character_id_get(conn, name, game, account_name, subscription, locker_location)
  name = name or GameState.name
  game = game or GameState.game
  local id = M.scalar(conn, "SELECT id FROM character WHERE name = :name AND game = :game",
                      { name = name, game = game })
  if not id then
    id = M.character_insert(conn, name, game, account_name, subscription, locker_location)
  end
  return id
end

-- ---------------------------------------------------------------------------
-- Update character record for current character.
-- ---------------------------------------------------------------------------
function M.character_refresh(conn, account_name, subscription, locker_location)
  local area = current_area()
  local society, society_rank = society_info()
  local citizenship = citizenship_info()
  local prof  = (Stats and Stats.prof) or ""
  local race  = (Stats and Stats.race) or ""
  local level = GameState.level or 0
  local exp   = (Stats and Stats.exp) or 0
  local sql = [[
    UPDATE character SET
        account      = COALESCE(:account, account)
      , prof         = :prof
      , race         = :race
      , level        = :level
      , exp          = :exp
      , area         = :area
      , subscription = COALESCE(:subscription, subscription)
      , locker       = COALESCE(:locker, locker)
      , citizenship  = :citizenship
      , society      = :society
      , society_rank = :society_rank
      , timestamp    = :timestamp
    WHERE name = :name AND game = :game]]
  M.exec(conn, sql, {
    name         = GameState.name,
    game         = GameState.game,
    account      = account_name or "",
    prof         = prof,
    race         = race,
    level        = level,
    exp          = exp,
    area         = area,
    subscription = subscription or "",
    locker       = locker_location or "",
    citizenship  = citizenship,
    society      = society,
    society_rank = society_rank,
    timestamp    = M.now(),
  })
end

-- ---------------------------------------------------------------------------
-- item_category_merge — update item.category from a name→category map
-- ---------------------------------------------------------------------------
function M.item_category_merge(conn, item_categories, game)
  if not item_categories or not next(item_categories) then return end
  game = game or GameState.game
  local sql = [[
    UPDATE item SET category = :category
    WHERE name = :name AND game = :game AND category = '']]
  for name, category in pairs(item_categories) do
    M.exec(conn, sql, { category = category, name = name, game = game })
  end
end

-- ---------------------------------------------------------------------------
-- item_base_merge — insert/update item master records from a temp table
-- ---------------------------------------------------------------------------
function M.item_base_merge(conn, table_name, game)
  game = game or GameState.game
  -- Update existing items where link_name is empty
  local update_sql = string.format([[
    UPDATE item SET
        noun      = (SELECT noun      FROM %s t WHERE t.update_noun = 1 AND t.name = item.name LIMIT 1)
      , link_name = (SELECT link_name FROM %s t WHERE t.update_noun = 1 AND t.name = item.name LIMIT 1)
      , type      = (SELECT type      FROM %s t WHERE t.update_noun = 1 AND t.name = item.name LIMIT 1)
    WHERE item.game LIKE :game
      AND item.link_name = ''
      AND EXISTS (SELECT 1 FROM %s t WHERE t.update_noun = 1 AND t.name = item.name LIMIT 1)
  ]], table_name, table_name, table_name, table_name)
  M.exec(conn, update_sql, { game = game })

  -- Insert new items
  local insert_sql = string.format([[
    INSERT INTO item(name, link_name, noun, type, game)
    SELECT
        name
      , MAX(link_name) AS link_name
      , MAX(noun) AS noun
      , CASE WHEN TRIM(MAX(type)) = '' THEN 'unknown' ELSE MAX(type) END AS type
      , :game AS game
    FROM %s t
    WHERE NOT EXISTS (SELECT 1 FROM item i WHERE i.name = t.name AND i.game = :game)
      AND TRIM(name) <> ''
    GROUP BY name
  ]], table_name)
  M.exec(conn, insert_sql, { game = game })
end

-- ---------------------------------------------------------------------------
-- merge_item_by_location — full upsert of char_inventory for one location
-- Reads from temp_item, updates char_inventory.
-- ---------------------------------------------------------------------------
function M.merge_item_by_location(conn, character_id, location_id, game)
  game = game or GameState.game
  local merge_params = {
    character_id = character_id,
    location_id  = location_id,
    game         = game,
  }

  M.item_base_merge(conn, "temp_item", game)

  local cte = [[
    WITH cte AS (
      SELECT
          t.character_id, t.location_id, i.id AS item_id
        , t.level, t.path, t.containing
        , SUM(t.amount) AS amount
        , t.stack, t.stack_status
        , t.marked, t.registered, t.hidden
      FROM temp_item t
        INNER JOIN item i ON i.name = t.name AND i.game = :game
      WHERE t.character_id = :character_id
        AND t.location_id  = :location_id
      GROUP BY
          t.character_id, t.location_id, i.id
        , t.level, t.path, t.containing
        , t.stack, t.stack_status
        , t.marked, t.registered, t.hidden
    )
  ]]

  -- delete rows no longer present
  local delete_sql = [[
    DELETE FROM char_inventory
    WHERE char_inventory.character_id = :character_id
      AND char_inventory.location_id  = :location_id
      AND NOT EXISTS (
        SELECT 1 FROM temp_item t
          INNER JOIN item i ON i.name = t.name AND i.game = :game
        WHERE t.character_id = :character_id
          AND t.location_id  = :location_id
          AND i.id           = char_inventory.item_id
          AND t.containing   = char_inventory.containing
          AND t.path         = char_inventory.path
          AND t.stack        = char_inventory.stack
          AND t.stack_status = char_inventory.stack_status
          AND t.marked       = char_inventory.marked
          AND t.registered   = char_inventory.registered
          AND t.hidden       = char_inventory.hidden
      )]]
  M.exec(conn, delete_sql, merge_params)

  -- update changed amounts
  local ts = M.now()
  local update_sql = cte .. [[
    UPDATE char_inventory SET
        amount    = (
          SELECT amount FROM cte t
          WHERE t.character_id = :character_id
            AND t.location_id  = :location_id
            AND t.item_id      = char_inventory.item_id
            AND t.containing   = char_inventory.containing
            AND t.path         = char_inventory.path
            AND t.amount      <> char_inventory.amount
            AND t.stack        = char_inventory.stack
            AND t.stack_status = char_inventory.stack_status
            AND t.marked       = char_inventory.marked
            AND t.registered   = char_inventory.registered
            AND t.hidden       = char_inventory.hidden
        )
      , timestamp = :timestamp
    WHERE char_inventory.character_id = :character_id
      AND char_inventory.location_id  = :location_id
      AND EXISTS (
        SELECT 1 FROM cte t
        WHERE t.character_id = :character_id
          AND t.location_id  = :location_id
          AND t.item_id      = char_inventory.item_id
          AND t.containing   = char_inventory.containing
          AND t.path         = char_inventory.path
          AND t.amount      <> char_inventory.amount
          AND t.stack        = char_inventory.stack
          AND t.stack_status = char_inventory.stack_status
          AND t.marked       = char_inventory.marked
          AND t.registered   = char_inventory.registered
          AND t.hidden       = char_inventory.hidden
      )]]
  merge_params.timestamp = ts
  M.exec(conn, update_sql, merge_params)

  -- insert new rows
  local insert_sql = cte .. [[
    INSERT INTO char_inventory (
        character_id, location_id, item_id
      , level, path, containing, amount
      , stack, stack_status
      , marked, registered, hidden, timestamp
    )
    SELECT
        character_id, location_id, item_id
      , level, path, containing, amount
      , stack, stack_status
      , marked, registered, hidden, :timestamp
    FROM cte t
    WHERE NOT EXISTS (
      SELECT 1 FROM char_inventory i
      WHERE i.character_id = :character_id
        AND i.location_id  = :location_id
        AND i.path         = t.path
        AND i.containing   = t.containing
        AND i.item_id      = t.item_id
        AND i.stack        = t.stack
        AND i.stack_status = t.stack_status
        AND i.marked       = t.marked
        AND i.registered   = t.registered
        AND i.hidden       = t.hidden
    )
    ORDER BY character_id, location_id, path, item_id]]
  M.exec(conn, insert_sql, merge_params)

  -- clean up temp_item for this location
  M.exec(conn, [[DELETE FROM temp_item WHERE character_id = :character_id AND location_id = :location_id]],
         { character_id = character_id, location_id = location_id })
end

-- ---------------------------------------------------------------------------
-- drop_tables — for "reset" action
-- ---------------------------------------------------------------------------
function M.drop_tables(conn, target)
  target = target or "all"
  if target:match("bank|all") then
    conn:exec("DROP TABLE IF EXISTS silver")
    conn:exec("DROP TABLE IF EXISTS bank")
  end
  if target:match("bounty|all") then
    conn:exec("DROP TABLE IF EXISTS bounty") end
  if target:match("tickets|all") then
    conn:exec("DROP TABLE IF EXISTS tickets") end
  if target:match("all") then
    conn:exec("DROP TABLE IF EXISTS location") end
  if target:match("items?$|item_detail|all") then
    conn:exec("DROP TABLE IF EXISTS item_detail") end
  if target:match("items?$|all") then
    conn:exec("DROP TABLE IF EXISTS char_inventory") end
  if target:match("items?|all") then
    conn:exec("DROP TABLE IF EXISTS item") end
  if target:match("room_inventory|all") then
    conn:exec("DROP TABLE IF EXISTS room_inventory") end
  if target:match("room_object|all") then
    conn:exec("DROP TABLE IF EXISTS room_object") end
  if target:match("room$|all") then
    conn:exec("DROP TABLE IF EXISTS room") end
end

-- ---------------------------------------------------------------------------
-- vacuum — SQLite VACUUM (run periodically)
-- ---------------------------------------------------------------------------
function M.maybe_vacuum(conn, settings)
  local last_vacuum = settings.last_vacuum or 0
  if (last_vacuum + 36000) < os.time() then
    conn:exec("VACUUM")
    UserVars["invdb_setting_last_vacuum"] = tostring(os.time())
  end
end

return M
