-- query.lua — where_builder, SQL generation, query/sum/count/export dispatch
-- Ported from invdb-beta.lic by Xanlin (original author).

local Util = require("gs.invdb.util")
local M = {}

-- ---------------------------------------------------------------------------
-- where_builder — convert parsed input params into SQL WHERE clause + qargs
-- context: 'bank' | 'character' | 'char_inventory' | 'item' | 'tickets'
--          'room_inventory' | etc.
-- aggregate: bool (used to adjust logic for sum/count)
-- action: 'query' | 'delete' | 'count' | 'sum'
-- Returns: where_clause (string), qargs (table), extras (table)
-- ---------------------------------------------------------------------------
function M.where_builder(params, context, aggregate, action)
  params    = params   or {}
  context   = context  or 'item'
  aggregate = aggregate ~= false
  action    = action   or 'query'

  local where_parts = {}
  local qargs  = {}
  local extras = {}

  -- Always filter by game unless explicitly overridden
  local game_val = params.game or GameState.game or "GS3"
  if game_val then
    qargs.game_filter = game_val
    if context == 'bank' then
      table.insert(where_parts, "c.game LIKE :game_filter")
    elseif context == 'tickets' then
      table.insert(where_parts, "c.game LIKE :game_filter")
    elseif context == 'character' then
      table.insert(where_parts, "c.game LIKE :game_filter")
    elseif context == 'char_inventory' or context == 'item' then
      table.insert(where_parts, "c.game LIKE :game_filter")
    elseif context == 'room_inventory' then
      table.insert(where_parts, "r.game LIKE :game_filter")
    end
  end

  -- Character filter
  local char_val = params.char or params.character or params["c"]
  if char_val then
    -- Support pipe-separated multi-character: char=Xanlin|Soliere
    if char_val:find("|") or char_val:find(",") then
      local chars = {}
      for c in char_val:gmatch("[^|,]+") do
        table.insert(chars, c:match("^%s*(.-)%s*$"))
      end
      qargs.char_array = chars
      -- Build "c.name IN ('a','b',...)" inline
      local quoted = {}
      for _, c in ipairs(chars) do
        table.insert(quoted, "'" .. c:gsub("'","''") .. "'")
      end
      if context == 'bank' or context == 'tickets' or context == 'character' then
        table.insert(where_parts, "c.name IN (" .. table.concat(quoted, ",") .. ")")
      elseif context == 'char_inventory' or context == 'item' then
        table.insert(where_parts, "c.name IN (" .. table.concat(quoted, ",") .. ")")
      end
    else
      -- Single char with LIKE wildcard support
      local like_val = char_val:gsub("%*", "%%")
      qargs.character_filter = like_val
      if context == 'bank' or context == 'tickets' or context == 'character' then
        table.insert(where_parts, "c.name LIKE :character_filter")
      elseif context == 'char_inventory' or context == 'item' then
        table.insert(where_parts, "c.name LIKE :character_filter")
      end
    end
  end

  -- Search filter (item name or other primary field)
  local search_val = params.search or params["name"]
  if not search_val then
    -- Free text (anything that isn't a keyed param) is used as search
    search_val = params._text
  end
  if search_val and search_val ~= "" then
    -- Regex match: =/.../
    local regex_pattern = search_val:match("^=/(.+)/$")
    if regex_pattern then
      qargs.search_regex = regex_pattern
      if context == 'char_inventory' or context == 'item' then
        table.insert(where_parts, "i.name REGEXP :search_regex")
      end
    else
      -- Wildcard match: * → %
      local like_val = search_val:gsub("%*", "%%")
      -- Exact match prefix: =value means exact
      if like_val:match("^=") then
        like_val = like_val:sub(2)
      else
        -- Wrap with % for contains search unless already has %
        if not like_val:match("%%") then
          like_val = "%" .. like_val .. "%"
        end
      end
      qargs.search_filter = like_val
      if context == 'char_inventory' or context == 'item' then
        table.insert(where_parts, "i.name LIKE :search_filter")
      elseif context == 'bank' then
        table.insert(where_parts, "b.name LIKE :search_filter")
      elseif context == 'tickets' then
        table.insert(where_parts, "t.source LIKE :search_filter")
      elseif context == 'character' then
        table.insert(where_parts, "c.name LIKE :search_filter")
      end
    end
  end

  -- Type filter
  local type_val = params.type or params["t"]
  if type_val then
    local like_val = "%" .. type_val:gsub("%*", "%%") .. "%"
    qargs.type_filter = like_val
    table.insert(where_parts, "i.type LIKE :type_filter")
  end

  -- Category filter
  local cat_val = params.category
  if cat_val then
    qargs.category_filter = "%" .. cat_val:gsub("%*","%%") .. "%"
    table.insert(where_parts, "i.category LIKE :category_filter")
  end

  -- Noun filter
  local noun_val = params.noun or params["n"]
  if noun_val then
    local like_val = noun_val:gsub("%*", "%%")
    qargs.noun_filter = like_val
    table.insert(where_parts, "i.noun LIKE :noun_filter")
  end

  -- Path filter
  local path_val = params.path or params["p"]
  if path_val then
    local like_val = path_val:gsub("%*", "%%")
    if not like_val:match("%%") then like_val = like_val .. "%" end
    qargs.path_filter = like_val
    table.insert(where_parts, "v.path LIKE :path_filter")
  end

  -- Stack filter
  local stack_val = params.stack or params["s"]
  if stack_val then
    qargs.stack_filter = stack_val:gsub("%*","%%")
    table.insert(where_parts, "v.stack LIKE :stack_filter")
  end

  -- Stack status / epf filter
  local epf_val = params.epf or params.stack_status
  if epf_val then
    qargs.stack_status_filter = "%" .. epf_val:gsub("%*","%%") .. "%"
    table.insert(where_parts, "v.stack_status LIKE :stack_status_filter")
  end

  -- Marked filter
  if params.marked then
    qargs.marked_filter = params.marked
    table.insert(where_parts, "v.marked = :marked_filter")
  end

  -- Registered filter
  if params.registered then
    qargs.registered_filter = params.registered
    table.insert(where_parts, "v.registered = :registered_filter")
  end

  -- Hidden filter
  if params.hidden then
    qargs.hidden_filter = params.hidden
    table.insert(where_parts, "v.hidden = :hidden_filter")
  end

  -- Amount comparisons: amount>=100, amount<500
  local amount_expr = params.amount or params.qty
  if amount_expr then
    local op, val = amount_expr:match("^([<>=!]+)(%d+)$")
    if op and val then
      -- Map != to <>
      op = op == "!=" and "<>" or op
      qargs.amount_filter = op .. val
      table.insert(where_parts, "v.amount " .. op .. val)
    end
  end

  -- Location type filter: inv|locker
  local loc_val = params.location or params["l"]
  if loc_val then
    if loc_val:match("^inv") then
      qargs.location_type_filter = "inv"
      table.insert(where_parts, "l.type = :location_type_filter")
    elseif loc_val:match("^loc") then
      qargs.location_type_filter = "locker"
      table.insert(where_parts, "l.type = :location_type_filter")
    else
      -- Treat as abbreviation or name search
      qargs.location_abbr_filter = loc_val:gsub("%*","%%")
      table.insert(where_parts, "(l.abbr LIKE :location_abbr_filter OR l.name LIKE :location_abbr_filter)")
    end
  end

  -- Bank filter
  local bank_val = params.bank or params["b"]
  if bank_val and context == 'bank' then
    qargs.bank_filter = "%" .. bank_val:gsub("%*","%%") .. "%"
    table.insert(where_parts, "b.name LIKE :bank_filter")
  end

  -- Account filter
  if params.account then
    qargs.account_filter = params.account:gsub("%*","%%")
    table.insert(where_parts, "c.account LIKE :account_filter")
  end

  -- Race filter
  if params.race then
    qargs.race_filter = "%" .. params.race:gsub("%*","%%") .. "%"
    if context == 'character' then
      table.insert(where_parts, "c.race LIKE :race_filter")
    end
  end

  -- Prof filter
  if params.prof or params.profession then
    qargs.prof_filter = "%" .. (params.prof or params.profession):gsub("%*","%%") .. "%"
    if context == 'character' then
      table.insert(where_parts, "c.prof LIKE :prof_filter")
    end
  end

  -- Room filters
  if params.uid then
    qargs.uid_filter = tonumber(params.uid)
    table.insert(where_parts, "r.uid = :uid_filter")
  end
  if params.lich_id then
    qargs.lich_id_filter = tonumber(params.lich_id)
    table.insert(where_parts, "r.lich_id = :lich_id_filter")
  end
  if params.property then
    qargs.property_filter = "%" .. params.property:gsub("%*","%%") .. "%"
    table.insert(where_parts, "r.property LIKE :property_filter")
  end
  if params.nickname then
    qargs.nickname_filter = "%" .. params.nickname:gsub("%*","%%") .. "%"
    table.insert(where_parts, "(r.nickname LIKE :nickname_filter OR r.title LIKE :nickname_filter)")
  end

  -- Extras: orderby, groupby, limit, delay
  if params.orderby then extras.orderby = params.orderby end
  if params.groupby  then extras.groupby  = params.groupby  end
  if params.limit    then extras.limit    = tonumber(params.limit) end
  if params.delay    then extras.delay    = tonumber(params.delay) end
  if params.format   then extras.format   = params.format end
  if params.dir      then extras.dir      = params.dir end
  if params.file     then extras.file     = params.file end

  -- Build WHERE clause string
  local where_clause = ""
  if #where_parts > 0 then
    where_clause = "\n    WHERE " .. table.concat(where_parts, "\n      AND ")
  end

  return where_clause, qargs, extras
end

-- ---------------------------------------------------------------------------
-- SQL generators
-- ---------------------------------------------------------------------------

function M.query_item_sql(params, style)
  local where, qargs, extras = M.where_builder(params, 'char_inventory')

  local select = [[
    SELECT
        c.name
      , l.abbr AS loc
      , v.path
      , v.amount AS qty
      , i.type
      , i.category
      , substr(v.stack,1,3) AS stk
      , ' ' || substr(v.stack_status,1,1) AS epf
      , v.marked AS m
      , v.registered AS r
      , v.hidden AS h
      , (i.name || rtrim(' ' || v.containing)) AS item]]

  if style == 'export' then
    select = [[
    SELECT
        c.account, c.name, l.name AS location, l.abbr AS loc
      , v.level, v.path, v.amount AS qty
      , i.type, i.category, v.stack, v.stack_status
      , i.name AS item, i.noun
      , i.timestamp
      , d.note, d.inspect, d.analyze, d.look, d.recall, d.loresong]]
  end

  local from = [[
    FROM char_inventory v
      INNER JOIN item i ON i.id = v.item_id
      INNER JOIN location l ON l.id = v.location_id
      INNER JOIN character c ON c.id = v.character_id
      LEFT JOIN item_detail d ON d.item_id = v.item_id]]

  local orderby = "\n    ORDER BY c.name, l.type, l.name, v.level, v.path, i.noun, i.name"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = ""
  if extras.limit then limit_sql = "\n    LIMIT " .. extras.limit end

  return select .. from .. where .. orderby .. limit_sql, qargs
end

function M.sum_item_sql(params)
  local where, qargs, extras = M.where_builder(params, 'item')
  local groupby_extra = extras.groupby or ""

  local select = [[
    SELECT
        i.type AS type
      , sum(v.amount) AS amount]]
  if groupby_extra:match("char") then select = select .. "\n      , c.name AS name" end
  if groupby_extra:match("loc")  then select = select .. "\n      , l.abbr AS loc" end
  if groupby_extra:match("noun") then select = select .. "\n      , i.noun AS noun" end
  -- Add gem/reagent pivot columns
  if qargs.type_filter and qargs.type_filter:match("gem|reagent") then
    select = select .. "\n      , sum(CASE WHEN stack='' THEN amount ELSE 0 END) AS loose"
    select = select .. "\n      , sum(CASE WHEN stack='jar' THEN amount ELSE 0 END) AS jarred"
  end
  select = select .. "\n      , i.name AS item"

  local from = [[
    FROM char_inventory v
      INNER JOIN item i ON i.id = v.item_id
      INNER JOIN location l ON l.id = v.location_id
      INNER JOIN character c ON c.id = v.character_id
      LEFT JOIN item_detail d ON d.item_id = v.item_id]]

  local groupby = "\n    GROUP BY i.type, i.name"
  if groupby_extra:match("char") then groupby = groupby .. ", c.name" end
  if groupby_extra:match("loc")  then groupby = groupby .. ", l.abbr" end
  if groupby_extra:match("noun") then groupby = groupby .. ", i.noun" end

  local orderby = "\n    ORDER BY i.type, amount"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = ""
  if extras.limit then limit_sql = "\n    LIMIT " .. extras.limit end

  -- Build union for totals
  local total_select = select:gsub("[lic]%.[a-z]+", "'total'"):gsub("sum%(", "sum(")
  local sql = select .. from .. where .. groupby
  sql = sql .. "\nUNION ALL\n" .. total_select .. from .. where .. "\nGROUP BY i.type"
  sql = sql .. orderby .. limit_sql
  return sql, qargs
end

function M.count_item_sql(params)
  local where, qargs, extras = M.where_builder(params, 'item')
  -- Restrict to standard/premium characters only
  where = where .. [[

      AND c.subscription NOT LIKE 'f%'
      AND (
           (c.name LIKE '%\_' ESCAPE '\' AND l.abbr = 'fam')
        OR (c.name NOT LIKE '%\_' ESCAPE '\' AND c.subscription LIKE 'standard' AND l.abbr = 'locker')
        OR (c.name NOT LIKE '%\_' ESCAPE '\' AND c.subscription NOT LIKE 'standard' AND l.abbr NOT IN ('fam','locker'))
        )]]

  local select = [[
    SELECT
        c.name AS character
      , l.abbr AS location
      , sum(CASE WHEN v.stack='' THEN v.amount ELSE 0 END) AS count]]
  if not qargs.search_filter and not qargs.search_regex and not qargs.type_filter and not qargs.noun_filter then
    select = select .. "\n      , sum(CASE WHEN i.type='box' THEN v.amount ELSE 0 END) AS boxes"
  end
  if qargs.search_filter then
    select = select .. "\n      , i.name AS item"
  end

  local from = [[
    FROM char_inventory v
      INNER JOIN item i ON i.id = v.item_id
      INNER JOIN location l ON l.id = v.location_id
      INNER JOIN character c ON c.id = v.character_id
      LEFT JOIN item_detail d ON d.item_id = v.item_id]]

  local groupby = "\n    GROUP BY c.name, l.id, l.abbr"
  if qargs.search_filter then groupby = groupby .. ", i.name" end

  local orderby = "\n    ORDER BY c.name, l.id"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. groupby .. orderby .. limit_sql, qargs
end

function M.query_char_sql(params)
  local where, qargs, extras = M.where_builder(params, 'character')

  -- Exclude fake (account_) characters by default unless explicitly filtered
  if not qargs.character_filter then
    where = where ~= "" and (where .. "\n      AND c.name NOT LIKE '%\\_' ESCAPE '\\'")
      or "\n    WHERE c.name NOT LIKE '%\\_' ESCAPE '\\'"
  end

  local select = [[
    SELECT
        c.account
      , c.name AS character
      , lower(c.game) AS game
      , substr(c.prof,1,3) AS pro
      , substr(replace(c.race,'alf-',''),1,2) AS rc
      , c.level AS lvl
      , c.area
      , substr(c.subscription,1,3) AS sub
      , coalesce(l.abbr, c.locker) AS lockr
      , c.citizenship
      , c.society
      , c.society_rank AS rank
      , c.timestamp AS updated
      , i.inv]]

  local from = [[
    FROM character c
      LEFT JOIN (SELECT l.name AS locker_name, l.abbr FROM location l) AS l
        ON c.locker = l.locker_name
      LEFT JOIN (
        SELECT i.character_id, sum(amount) AS inv
        FROM char_inventory AS i
        WHERE i.stack = '' AND i.location_id < 3
        GROUP BY i.character_id
      ) i ON c.id = i.character_id]]

  local orderby = "\n    ORDER BY c.game, c.name"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. orderby .. limit_sql, qargs
end

function M.query_bank_sql(params)
  local where, qargs, extras = M.where_builder(params, 'bank')

  local select = [[
    SELECT
        c.name AS character
      , b.name AS bank
      , s.amount
      , s.timestamp AS updated]]
  local from = [[
    FROM silver s
      INNER JOIN bank b ON s.bank_id = b.id
      INNER JOIN character c ON s.character_id = c.id]]

  local orderby = "\n    ORDER BY c.name, b.id"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. orderby .. limit_sql, qargs
end

function M.sum_bank_sql(params)
  local where, qargs, extras = M.where_builder(params, 'bank')
  if not qargs.search_filter then
    where = where ~= "" and (where .. "\n      AND b.name <> 'Total'")
      or "\n    WHERE b.name <> 'Total'"
  end

  local select = [[
    SELECT
        b.name AS bank
      , sum(s.amount) AS amount
      , replace(group_concat(DISTINCT c.name),',',', ') AS characters]]
  local from = [[
    FROM silver s
      INNER JOIN bank b ON s.bank_id = b.id
      INNER JOIN character c ON s.character_id = c.id]]

  local groupby = "\n    GROUP BY b.name"
  local orderby = "\n    ORDER BY bank"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end

  local sql = select .. from .. where .. groupby
  if not qargs.search_filter then
    sql = sql .. "\nUNION ALL\n"
      .. select:gsub("b%.name", "'grand total'") .. from .. where
  end
  sql = sql .. orderby
  return sql, qargs
end

function M.query_tickets_sql(params)
  local where, qargs, extras = M.where_builder(params, 'tickets')

  local select = [[
    SELECT
        c.name AS character
      , c.game
      , t.source
      , t.amount
      , t.currency
      , t.timestamp AS updated]]
  local from = [[
    FROM tickets t
      INNER JOIN character c ON t.character_id = c.id]]

  local orderby = "\n    ORDER BY t.source, c.name"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. orderby .. limit_sql, qargs
end

function M.sum_tickets_sql(params)
  local where, qargs, extras = M.where_builder(params, 'tickets')

  local select = [[
    SELECT
        t.source AS source
      , sum(t.amount) AS amount
      , t.currency AS currency
      , replace(group_concat(DISTINCT c.name),',',', ') AS characters]]
  local from = [[
    FROM tickets t
      INNER JOIN character c ON t.character_id = c.id]]

  local groupby = "\n    GROUP BY t.source, t.currency"
  local orderby = "\n    ORDER BY source"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. groupby .. orderby .. limit_sql, qargs
end

function M.query_rooms_sql(params)
  local where, qargs, extras = M.where_builder(params, 'room')

  local select = [[
    SELECT
        r.property
      , r.title
      , CASE WHEN r.nickname = '' THEN r.title ELSE r.nickname END AS nickname
      , r.uid
      , r.lich_id
      , r.timestamp AS updated]]
  local from = [[
    FROM room r]]

  -- Override game filter to use r.game
  local orderby = "\n    ORDER BY r.property, r.title"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end

  return select .. from .. where .. orderby, qargs
end

function M.count_room_inventory_sql(params)
  local where, qargs, extras = M.where_builder(params, 'room_inventory', true, 'count')
  local gby = extras.groupby or ""

  local select = [[
    SELECT
        r.property
      , CASE WHEN r.nickname = '' THEN r.title ELSE r.nickname END AS room]]
  if gby:match("uid")      then select = select .. "\n      , r.uid" end
  if gby:match("lich_id")  then select = select .. "\n      , r.lich_id" end
  if gby:match("object")   then select = select .. "\n      , ro.object" end
  if gby:match("path")     then select = select .. "\n      , ri.path" end
  if gby:match("type")     then select = select .. "\n      , i.type" end
  if gby:match("category") then select = select .. "\n      , i.category" end
  if gby:match("noun")     then select = select .. "\n      , i.noun" end
  if gby:match("item|name") then select = select .. "\n      , i.name AS item" end
  select = select .. "\n      , sum(ri.amount) AS qty"

  local from = [[
    FROM room r
      INNER JOIN room_object ro ON r.id = ro.room_id
      INNER JOIN room_inventory ri ON ro.id = ri.room_object_id
      INNER JOIN item i ON i.id = ri.item_id]]

  local groupby = "\n    GROUP BY r.property, r.nickname, r.title"
  if gby:match("uid")      then groupby = groupby .. ", r.uid" end
  if gby:match("lich_id")  then groupby = groupby .. ", r.lich_id" end
  if gby:match("object")   then groupby = groupby .. ", ro.object" end
  if gby:match("path")     then groupby = groupby .. ", ri.path" end
  if gby:match("type")     then groupby = groupby .. ", i.type" end
  if gby:match("category") then groupby = groupby .. ", i.category" end
  if gby:match("noun")     then groupby = groupby .. ", i.noun" end
  if gby:match("item|name") then groupby = groupby .. ", i.name" end

  local orderby = "\n    ORDER BY r.property"
  if extras.orderby then orderby = "\n    ORDER BY " .. extras.orderby end
  local limit_sql = extras.limit and ("\n    LIMIT " .. extras.limit) or ""

  return select .. from .. where .. groupby .. orderby .. limit_sql, qargs
end

-- ---------------------------------------------------------------------------
-- Query dispatch — run a query and print results
-- ---------------------------------------------------------------------------
function M.do_query(conn, action, target, params, settings)
  local sql, qargs

  -- Determine SQL based on action + target
  if action == "sum" or action == "total" then
    if target:match("^bank$") or target:match("^sbank$") then
      sql, qargs = M.sum_bank_sql(params)
    elseif target:match("^tickets$") or target:match("^stickets$") then
      sql, qargs = M.sum_tickets_sql(params)
    else
      sql, qargs = M.sum_item_sql(params)
    end
  elseif action == "count" or action:match("^c$") then
    sql, qargs = M.count_item_sql(params)
  elseif target:match("^char") then
    sql, qargs = M.query_char_sql(params)
  elseif target:match("^bank$") then
    sql, qargs = M.query_bank_sql(params)
  elseif target:match("^tickets?$") then
    sql, qargs = M.query_tickets_sql(params)
  elseif target:match("^rooms?$") then
    sql, qargs = M.query_rooms_sql(params)
  elseif target:match("^room_inv") or target:match("^prop") then
    sql, qargs = M.count_room_inventory_sql(params)
  else
    -- Default: item query
    sql, qargs = M.query_item_sql(params)
  end

  -- Register REGEXP function if needed
  if sql:find("REGEXP") then
    conn:create_regexp_function()
  end

  local rows, err = conn:query2(sql, qargs)
  if err then
    respond("invdb query error: " .. err)
    return
  end

  local row_count = rows and (#rows - 1) or 0
  if settings then
    Util.check_output_size(row_count, settings.confirm_large_output)
  end

  respond(Util.format_table(rows, settings and settings.date_format))
end

-- ---------------------------------------------------------------------------
-- Parse input arguments into action, target, params table, free text
-- ---------------------------------------------------------------------------
function M.parse_args(args_str)
  args_str = args_str or ""

  local action = nil
  local target = nil
  local params = {}
  local text_parts = {}

  -- Known actions (longest match first)
  local ACTION_PATTERNS = {
    {"^refresh",     "refresh"},
    {"^query",       "query"},
    {"^sum",         "sum"},
    {"^total",       "sum"},
    {"^count",       "count"},
    {"^export",      "export"},
    {"^reset",       "reset"},
    {"^delete",      "delete"},
    {"^remove",      "remove"},
    {"^update",      "update"},
    {"^add",         "update"},
    {"^scan",        "scan"},
    {"^q%f[%A]",     "query"},
    {"^s%f[%A]",     "sum"},
    {"^c%f[%A]",     "count"},
  }

  local TARGET_PATTERNS = {
    {"^all$",            "all"},
    {"^account$",        "account"},
    {"^bank$",           "bank"},
    {"^sbank$",          "sbank"},
    {"^bounty$",         "bounty"},
    {"^char",            "char"},
    {"^inv$",            "inv"},
    {"^inventory$",      "inv"},
    {"^item",            "item"},
    {"^locker$",         "locker"},
    {"^lumnis$",         "lumnis"},
    {"^resource$",       "resource"},
    {"^stickets$",       "stickets"},
    {"^tickets?$",       "tickets"},
    {"^room_inv",        "room_inventory"},
    {"^room_obj",        "room_objects"},
    {"^rooms?$",         "rooms"},
    {"^prop",            "property"},
    {"^item_detail$",    "item_detail"},
    {"^item_base$",      "item_base"},
    {"^item_note$",      "item_note"},
  }

  local tokens = {}
  for token in args_str:gmatch("%S+") do
    table.insert(tokens, token)
  end

  local i = 1
  while i <= #tokens do
    local tok = tokens[i]

    -- @debug flags
    if tok:match("^@") then
      params["_flag_" .. tok:sub(2)] = true
      i = i + 1

    -- key=value pairs
    elseif tok:match("^[%w_]+[=<>!]") then
      local key, op, val = tok:match("^([%w_]+)([=<>!]+)(.*)")
      if key and val then
        -- If value is empty, peek at next token
        if val == "" and tokens[i+1] and not tokens[i+1]:match("^[%w_]+=") then
          val = tokens[i+1]
          i = i + 1
        end
        params[key:lower()] = op .. val
        -- Normalize: "=value" means exact, strip = for most
        if op == "=" then
          params[key:lower()] = val
        else
          params[key:lower()] = op .. val
        end
      end
      i = i + 1

    -- --setting flags are handled before this function, skip here
    elseif tok:match("^%-%-") then
      i = i + 1

    -- action detection (first unkeyed word)
    elseif not action then
      local matched = false
      for _, ap in ipairs(ACTION_PATTERNS) do
        if tok:lower():match(ap[1]) then
          action = ap[2]
          matched = true
          break
        end
      end
      if not matched then
        -- Could be a target or free text
        local target_matched = false
        for _, tp in ipairs(TARGET_PATTERNS) do
          if tok:lower():match(tp[1]) then
            target = tp[2]
            target_matched = true
            action = "query" -- default action if target is given first
            break
          end
        end
        if not target_matched then
          -- Free text search
          action = "query"
          target = "item"
          table.insert(text_parts, tok)
        end
      end
      i = i + 1

    -- target detection (second unkeyed word)
    elseif not target then
      local matched = false
      for _, tp in ipairs(TARGET_PATTERNS) do
        if tok:lower():match(tp[1]) then
          target = tp[2]
          matched = true
          break
        end
      end
      if not matched then
        table.insert(text_parts, tok)
      end
      i = i + 1

    -- remaining tokens: free text
    else
      table.insert(text_parts, tok)
      i = i + 1
    end
  end

  -- Defaults
  action = action or "refresh"
  target = target or (action == "refresh" and "all" or "item")

  -- Free text becomes search filter
  if #text_parts > 0 then
    params._text = table.concat(text_parts, " ")
  end

  return action, target, params
end

-- ---------------------------------------------------------------------------
-- Upsert helpers — temp-table merge pattern used by all refresh operations
-- ---------------------------------------------------------------------------

-- Merge temp_item → item + char_inventory for a given character + location range
function M.merge_inventory(conn, character_id, location_ids_str, ts)
  -- 1. Upsert items into the item catalog
  local _, e = conn:exec([[
    INSERT OR IGNORE INTO item (name, noun, link_name, type, category, game)
    SELECT DISTINCT t.name, t.noun, t.link_name, t.type, '', :game
    FROM temp_item t
    WHERE t.character_id = :char_id
      AND t.update_noun = 1
      AND NOT EXISTS (SELECT 1 FROM item i WHERE i.name = t.name AND i.game = :game)
  ]], {char_id = character_id, game = GameState.game})
  if e then respond("invdb merge_inventory item upsert: " .. e) end

  -- 2. Update noun/type on existing items from inventory (where we have the id link)
  conn:exec([[
    UPDATE item SET
        noun = (SELECT t.noun FROM temp_item t WHERE t.name = item.name AND t.update_noun = 1 LIMIT 1)
      , type = (SELECT t.type FROM temp_item t WHERE t.name = item.name LIMIT 1)
    WHERE game = :game
      AND EXISTS (SELECT 1 FROM temp_item t WHERE t.name = item.name AND t.character_id = :char_id)
  ]], {char_id = character_id, game = GameState.game})

  -- 3. Update item categories
  conn:exec([[
    UPDATE item SET category = (
      SELECT tc.category FROM temp_item_category tc WHERE tc.name = item.name AND tc.game = :game LIMIT 1
    )
    WHERE game = :game
      AND EXISTS (SELECT 1 FROM temp_item_category tc WHERE tc.name = item.name AND tc.game = :game)
  ]], {game = GameState.game})

  -- 4. Delete char_inventory rows for this char+location that are no longer present
  conn:exec([[
    DELETE FROM char_inventory
    WHERE character_id = :char_id
      AND location_id IN (]] .. location_ids_str .. [[)
      AND NOT EXISTS (
        SELECT 1 FROM temp_item t
          INNER JOIN item i ON i.name = t.name AND i.game = :game
        WHERE t.character_id = :char_id
          AND i.id = char_inventory.item_id
          AND t.path = char_inventory.path
          AND t.stack = char_inventory.stack
      )
  ]], {char_id = character_id, game = GameState.game})

  -- 5. Upsert char_inventory
  conn:exec([[
    INSERT INTO char_inventory
      (character_id, location_id, item_id, containing, path, level, amount, stack, stack_status, marked, registered, hidden, timestamp)
    SELECT
        t.character_id
      , t.location_id
      , i.id
      , t.containing
      , t.path
      , t.level
      , t.amount
      , t.stack
      , t.stack_status
      , t.marked
      , t.registered
      , t.hidden
      , t.timestamp
    FROM temp_item t
      INNER JOIN item i ON i.name = t.name AND i.game = :game
    WHERE t.character_id = :char_id
    ON CONFLICT(character_id, location_id, item_id, containing, path, stack, stack_status, marked, registered, hidden) DO UPDATE SET
        amount    = excluded.amount
      , level     = excluded.level
      , timestamp = excluded.timestamp
  ]], {char_id = character_id, game = GameState.game})

  -- 6. Clear temp tables for next use
  conn:exec("DELETE FROM temp_item WHERE character_id = :char_id", {char_id = character_id})
  conn:exec("DELETE FROM temp_item_category WHERE game = :game", {game = GameState.game})
end

-- Merge temp_silver → silver for a given character
function M.merge_silver(conn, character_id)
  -- Delete rows not in temp
  conn:exec([[
    DELETE FROM silver
    WHERE character_id = :char_id
      AND NOT EXISTS (
        SELECT 1 FROM temp_silver t
        WHERE t.character_id = :char_id AND t.bank_id = silver.bank_id
      )
  ]], {char_id = character_id})

  -- Upsert
  conn:exec([[
    INSERT INTO silver (character_id, bank_id, amount, timestamp)
    SELECT character_id, bank_id, amount, timestamp FROM temp_silver
    WHERE character_id = :char_id
    ON CONFLICT(character_id, bank_id) DO UPDATE SET
        amount    = excluded.amount
      , timestamp = excluded.timestamp
  ]], {char_id = character_id})

  conn:exec("DELETE FROM temp_silver WHERE character_id = :char_id", {char_id = character_id})
end

-- Merge temp_tickets → tickets for a given character
function M.merge_tickets(conn, character_id)
  conn:exec([[
    DELETE FROM tickets
    WHERE character_id = :char_id
      AND NOT EXISTS (
        SELECT 1 FROM temp_tickets t
        WHERE t.character_id = :char_id AND t.source = tickets.source
      )
  ]], {char_id = character_id})

  conn:exec([[
    INSERT INTO tickets (character_id, source, amount, currency, timestamp)
    SELECT character_id, source, amount, currency, timestamp FROM temp_tickets
    WHERE character_id = :char_id
    ON CONFLICT(character_id, source) DO UPDATE SET
        amount    = excluded.amount
      , currency  = excluded.currency
      , timestamp = excluded.timestamp
  ]], {char_id = character_id})

  conn:exec("DELETE FROM temp_tickets WHERE character_id = :char_id", {char_id = character_id})
end

return M
