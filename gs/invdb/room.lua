-- room.lua — room/property inventory scanning, upsert, delete, and query
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local db_mod     = require("gs/invdb/db")
local util       = require("gs/invdb/util")
local containers = require("gs/invdb/containers")
local inventory  = require("gs/invdb/inventory")

-- ---------------------------------------------------------------------------
-- Internal: insert scanned items into temp_room_item staging table
-- ---------------------------------------------------------------------------
local function stage_room_items(conn, room_object_id, items)
  local ts = db_mod.now()
  conn:exec("DELETE FROM temp_room_item WHERE room_object_id = :id",
    { id = room_object_id })

  for _, item in ipairs(items) do
    if item.name and item.name ~= "" then
      conn:exec([[
        INSERT INTO temp_room_item
          (room_object_id, level, path, type, name, link_name, containing,
           noun, amount, stack, stack_status, update_noun, gs_id, timestamp)
        VALUES
          (:room_object_id, :level, :path, :type, :name, :link_name, :containing,
           :noun, :amount, :stack, :stack_status, :update_noun, :gs_id, :timestamp)
      ]], {
        room_object_id = room_object_id,
        level          = item.level         or 0,
        path           = item.path          or "",
        type           = item.type          or "",
        name           = item.name,
        link_name      = item.link_name     or "",
        containing     = item.containing    or "",
        noun           = item.noun          or "",
        amount         = item.amount        or 1,
        stack          = item.stack         or "",
        stack_status   = item.stack_status  or "",
        update_noun    = item.update_noun   and 1 or 0,
        gs_id          = item.gs_id,
        timestamp      = ts,
      })
    end
  end
end

-- ---------------------------------------------------------------------------
-- Internal: merge temp_room_item into room_inventory
-- ---------------------------------------------------------------------------
local function room_inventory_merge(conn, room_object_id)
  local game = GameState.game or "GS3"
  local p = { room_object_id = room_object_id, game = game, timestamp = db_mod.now() }

  -- Ensure item records exist (upsert into item table)
  conn:exec([[
    INSERT OR IGNORE INTO item (name, noun, link_name, type, game)
    SELECT DISTINCT name, noun, link_name, type, :game
    FROM temp_room_item
    WHERE room_object_id = :room_object_id
      AND name <> ''
  ]], { room_object_id = room_object_id, game = game })

  -- Delete items no longer present in this room_object
  conn:exec([[
    DELETE FROM room_inventory
    WHERE room_inventory.room_object_id = :room_object_id
      AND NOT EXISTS (
        SELECT 1
        FROM temp_room_item t
          INNER JOIN item i ON t.name = i.name AND i.game = :game
        WHERE t.room_object_id = :room_object_id
          AND i.id           = room_inventory.item_id
          AND t.containing   = room_inventory.containing
          AND t.path         = room_inventory.path
          AND t.stack        = room_inventory.stack
          AND t.stack_status = room_inventory.stack_status
      )
  ]], p)

  -- Update changed amounts
  conn:exec([[
    UPDATE room_inventory SET
        amount    = (
          SELECT SUM(t.amount)
          FROM temp_room_item t
            INNER JOIN item i ON t.name = i.name AND i.game = :game
          WHERE t.room_object_id = :room_object_id
            AND i.id           = room_inventory.item_id
            AND t.containing   = room_inventory.containing
            AND t.path         = room_inventory.path
            AND t.stack        = room_inventory.stack
            AND t.stack_status = room_inventory.stack_status
        )
      , timestamp = :timestamp
    WHERE room_inventory.room_object_id = :room_object_id
      AND EXISTS (
        SELECT 1
        FROM temp_room_item t
          INNER JOIN item i ON t.name = i.name AND i.game = :game
        WHERE t.room_object_id = :room_object_id
          AND i.id            = room_inventory.item_id
          AND t.containing    = room_inventory.containing
          AND t.path          = room_inventory.path
          AND t.stack         = room_inventory.stack
          AND t.stack_status  = room_inventory.stack_status
      )
  ]], p)

  -- Insert new items not yet in room_inventory
  conn:exec([[
    INSERT INTO room_inventory
      (room_object_id, item_id, level, path, containing, amount, stack, stack_status, timestamp)
    SELECT
        t.room_object_id
      , i.id
      , t.level, t.path, t.containing
      , SUM(t.amount)
      , t.stack, t.stack_status
      , :timestamp
    FROM temp_room_item t
      INNER JOIN item i ON t.name = i.name AND i.game = :game
    WHERE t.room_object_id = :room_object_id
      AND NOT EXISTS (
        SELECT 1
        FROM room_inventory ri
        WHERE ri.room_object_id = :room_object_id
          AND ri.item_id      = i.id
          AND ri.containing   = t.containing
          AND ri.path         = t.path
          AND ri.stack        = t.stack
          AND ri.stack_status = t.stack_status
      )
    GROUP BY t.room_object_id, i.id, t.level, t.path, t.containing, t.stack, t.stack_status
  ]], p)

  -- Clear staging table for this room_object
  conn:exec("DELETE FROM temp_room_item WHERE room_object_id = :id",
    { id = room_object_id })
end

-- ---------------------------------------------------------------------------
-- Internal: scan items in/on a named room object via traverse_container
-- Returns flat list of item tables
-- ---------------------------------------------------------------------------
local function scan_room_object(name, prepositions, settings, max_depth)
  max_depth  = max_depth  or 9
  prepositions = prepositions or "in"
  settings   = settings   or {}
  local all_items = {}

  -- Split comma-separated prepositions
  for prep in prepositions:gmatch("[^,]+") do
    prep = prep:match("^%s*(.-)%s*$")
    local items, _, _, _ = containers.traverse_container(
      name, prep, "", "", -1, settings.open_containers ~= false, max_depth, true)
    if items and #items > 0 then
      for _, it in ipairs(items) do
        table.insert(all_items, it)
      end
    end
  end

  return all_items
end

-- ---------------------------------------------------------------------------
-- room_object_refresh — scan one room_object and merge results into DB
-- ---------------------------------------------------------------------------
function M.room_object_refresh(conn, room_object_id, name, prepositions, settings)
  local items = scan_room_object(name, prepositions, settings)
  stage_room_items(conn, room_object_id, items)
  room_inventory_merge(conn, room_object_id)
end

-- ---------------------------------------------------------------------------
-- room_refresh — scan all registered room_objects for current room UID
-- ---------------------------------------------------------------------------
function M.room_refresh(conn, params, settings, uid)
  uid = uid or GameState.room_id
  if not uid then
    respond("invdb: room_refresh: could not determine room UID")
    return
  end

  local game = GameState.game or "GS3"

  local rows = conn:query2([[
    SELECT ro.id, ro.object, ro.prepositions, ro.depth
    FROM room_object ro
      INNER JOIN room r ON r.id = ro.room_id
    WHERE r.uid  = :uid
      AND r.game LIKE :game
    ORDER BY ro.id
  ]], { uid = uid, game = game })

  if not rows or #rows <= 1 then
    respond("invdb: no room_objects registered for current room (uid=" .. tostring(uid) .. ")")
    return
  end

  for i = 2, #rows do
    local row = rows[i]
    local ro_id     = row[1]
    local obj_name  = row[2]
    local preps     = row[3]
    local depth     = row[4] or 9
    respond("invdb: scanning " .. tostring(obj_name) .. "...")
    local items = scan_room_object(obj_name, preps, settings, depth)
    stage_room_items(conn, ro_id, items)
    room_inventory_merge(conn, ro_id)
  end
end

-- ---------------------------------------------------------------------------
-- property_refresh — navigate all rooms in a property and call room_refresh
-- ---------------------------------------------------------------------------
function M.property_refresh(conn, params, settings, property)
  local uid  = GameState.room_id
  local game = GameState.game or "GS3"

  -- Determine property name from current room if not provided
  if not property then
    local prow = conn:scalar(
      "SELECT property FROM room WHERE uid = :uid AND game LIKE :game LIMIT 1",
      { uid = uid, game = game })
    property = prow
  end

  if not property or property == "" then
    respond("invdb: property_refresh: property not found for current room")
    return
  end

  -- Get all rooms in this property
  local rows = conn:query2([[
    SELECT uid, lich_id FROM room
    WHERE property LIKE :property AND game LIKE :game
  ]], { property = property, game = game })

  if not rows or #rows <= 1 then
    respond("invdb: no rooms found for property: " .. property)
    return
  end

  -- Verify we are currently in the property
  local in_property = false
  for i = 2, #rows do
    if rows[i][1] == uid then in_property = true; break end
  end

  if not in_property then
    respond("invdb: not currently in property: " .. property)
    return
  end

  local start_room = GameState.room_id

  for i = 2, #rows do
    local room_uid  = rows[i][1]
    local room_lich = rows[i][2]
    if GameState.room_id ~= room_lich then
      Script.run("go2", tostring(room_lich))
      pause(0.2)
    end
    if GameState.room_id == room_lich then
      M.room_refresh(conn, params, settings, room_uid)
    end
  end

  -- Return to starting room
  if GameState.room_id ~= start_room then
    Script.run("go2", tostring(start_room))
  end
end

-- ---------------------------------------------------------------------------
-- sorted_view_scan_inventory — scan inventory containers for item categories
-- ---------------------------------------------------------------------------
function M.sorted_view_scan_inventory(conn, settings)
  local containers_with_contents, _ = inventory.containers_with_contents_get()
  if not containers_with_contents or not next(containers_with_contents) then
    respond("invdb: sorted_view_scan_inventory: no containers found")
    return
  end

  local open_containers = settings and settings.open_containers ~= false

  local merge_categories = {}
  for exist_id, _ in pairs(containers_with_contents) do
    local _, item_categories, _, _ = containers.traverse_container(
      "#" .. exist_id, "in", "", "", -1, open_containers)
    if type(item_categories) == "table" then
      for k, v in pairs(item_categories) do
        merge_categories[k] = v
      end
    end
  end

  -- Merge category data into temp_item_category / item table
  containers.item_category_merge(conn, merge_categories)
end

-- ---------------------------------------------------------------------------
-- sorted_view_scan_premium_locker — scan premium locker fixtures
-- ---------------------------------------------------------------------------
local PREMIUM_LOCKER_OBJECTS = {
  { name = "weapon rack",                  prep = "on" },
  { name = "armor stand",                  prep = "on" },
  { name = "clothing wardrobe",            prep = "in" },
  { name = "magical item bin",             prep = "in" },
  { name = "deep chest",                   prep = "in" },
  { name = "dark stained antique oak trunk", prep = "in" },
}

function M.sorted_view_scan_premium_locker(conn, settings)
  local open_containers = settings and settings.open_containers ~= false
  local merge_categories = {}
  local loot = GameObj.loot and GameObj.loot() or {}

  for _, fixture in ipairs(PREMIUM_LOCKER_OBJECTS) do
    -- Find the fixture in room loot by name
    local obj_id = nil
    for _, obj in ipairs(loot) do
      if obj.name == fixture.name then
        obj_id = obj.id
        break
      end
    end
    if obj_id then
      local _, item_categories, _, _ = containers.traverse_container(
        "#" .. tostring(obj_id), fixture.prep, "", "", 9, open_containers)
      if type(item_categories) == "table" then
        for k, v in pairs(item_categories) do
          merge_categories[k] = v
        end
      end
    end
  end

  containers.item_category_merge(conn, merge_categories)
end

-- ---------------------------------------------------------------------------
-- room_upsert — insert or update room record for current room
-- ---------------------------------------------------------------------------
function M.room_upsert(conn, params)
  local uid     = GameState.room_id
  local game    = GameState.game or "GS3"
  local title   = GameState.room_title or ""
  local nickname = title:match(",([^,]+)$") or title
  nickname = nickname:gsub("%[", ""):gsub("%]", ""):match("^%s*(.-)%s*$")

  -- Override fields from params
  local property = params.property or ""
  local lich_id  = GameState.lich_id

  -- Try insert
  conn:exec([[
    INSERT INTO room (uid, lich_id, title, nickname, property, game)
    SELECT :uid, :lich_id, :title, :nickname, :property, :game
    WHERE NOT EXISTS (SELECT 1 FROM room WHERE uid = :uid AND game = :game)
  ]], {
    uid      = uid,
    lich_id  = lich_id,
    title    = title,
    nickname = nickname,
    property = property,
    game     = game,
  })

  -- Update if already existed
  conn:exec([[
    UPDATE room SET
        lich_id  = :lich_id
      , title    = :title
      , nickname = COALESCE(:nickname, nickname, '')
      , property = :property
    WHERE uid  = :uid
      AND game = :game
  ]], {
    uid      = uid,
    lich_id  = lich_id,
    title    = title,
    nickname = nickname,
    property = property,
    game     = game,
  })

  respond("invdb: room upserted (uid=" .. tostring(uid) .. ")")
end

-- ---------------------------------------------------------------------------
-- room_object_upsert — insert or update a room_object record
-- ---------------------------------------------------------------------------
function M.room_object_upsert(conn, params)
  local game   = GameState.game or "GS3"
  local uid    = GameState.room_id

  local object       = params.object       or params.name   or ""
  local prepositions = params.prepositions or params.preps  or "in"
  local depth        = tonumber(params.depth) or 9
  local special      = params.special or ""

  if object == "" then
    respond("invdb: room_object_upsert: object name required")
    return
  end

  -- Get room_id
  local room_id = conn:scalar(
    "SELECT id FROM room WHERE uid = :uid AND game LIKE :game",
    { uid = uid, game = game })

  if not room_id then
    respond("invdb: room_object_upsert: room not found for current UID. Run 'upsert rooms' first.")
    return
  end

  -- Try insert
  conn:exec([[
    INSERT INTO room_object (room_id, object, prepositions, depth, special)
    SELECT :room_id, :object, :prepositions, :depth, :special
    WHERE NOT EXISTS (
      SELECT 1 FROM room_object WHERE room_id = :room_id AND object = :object)
  ]], {
    room_id      = room_id,
    object       = object,
    prepositions = prepositions,
    depth        = depth,
    special      = special,
  })

  -- Update if already existed
  conn:exec([[
    UPDATE room_object SET
        prepositions = :prepositions
      , depth        = :depth
      , special      = :special
    WHERE room_id = :room_id
      AND object  = :object
  ]], {
    room_id      = room_id,
    object       = object,
    prepositions = prepositions,
    depth        = depth,
    special      = special,
  })

  respond("invdb: room_object upserted: " .. object)
end

-- ---------------------------------------------------------------------------
-- room_delete — delete room record(s)
-- ---------------------------------------------------------------------------
function M.room_delete(conn, params)
  local game = GameState.game or "GS3"
  local uid  = params.uid or GameState.room_id

  conn:exec([[
    DELETE FROM room WHERE game LIKE :game AND uid = :uid
  ]], { game = game, uid = uid })

  respond("invdb: room deleted (uid=" .. tostring(uid) .. ")")
end

-- ---------------------------------------------------------------------------
-- room_object_delete — delete room_object record(s)
-- ---------------------------------------------------------------------------
function M.room_object_delete(conn, params)
  local game   = GameState.game or "GS3"
  local uid    = params.uid or GameState.room_id
  local object = params.object or params.name

  local sql_where = ""
  local qargs = { game = game, uid = uid }

  if object then
    sql_where = " AND ro.object LIKE :object"
    qargs.object = object
  end

  conn:exec([[
    DELETE FROM room_object
    WHERE id IN (
      SELECT ro.id
      FROM room_object ro
        INNER JOIN room r ON ro.room_id = r.id
      WHERE r.uid  = :uid
        AND r.game LIKE :game
    ]] .. sql_where .. [[
    )
  ]], qargs)

  respond("invdb: room_object(s) deleted")
end

-- ---------------------------------------------------------------------------
-- room_query — query room table
-- ---------------------------------------------------------------------------
function M.room_query(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "r.game LIKE :game" }
  local qargs = { game = game }

  if params.property then
    qargs.property = params.property .. "%"
    table.insert(where_parts, "r.property LIKE :property")
  end
  if params.uid then
    qargs.uid = params.uid
    table.insert(where_parts, "r.uid = :uid")
  end

  local sql = [[
    SELECT r.id, r.uid, r.lich_id, r.title, r.nickname, r.property, r.game
    FROM room r
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    ORDER BY r.uid
  ]]

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb room_query error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- room_object_query — query room_object table
-- ---------------------------------------------------------------------------
function M.room_object_query(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "r.game LIKE :game" }
  local qargs = { game = game }

  if params.uid then
    qargs.uid = params.uid
    table.insert(where_parts, "r.uid = :uid")
  end
  if params.object or params.name then
    qargs.object = (params.object or params.name) .. "%"
    table.insert(where_parts, "ro.object LIKE :object")
  end

  local sql = [[
    SELECT r.uid, r.nickname, ro.id, ro.object, ro.prepositions, ro.depth, ro.special
    FROM room_object ro
      INNER JOIN room r ON ro.room_id = r.id
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    ORDER BY r.uid, ro.object
  ]]

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb room_object_query error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- room_inventory_query — query room_inventory table
-- ---------------------------------------------------------------------------
function M.room_inventory_query(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "r.game LIKE :game" }
  local qargs = { game = game }

  if params.uid then
    qargs.uid = params.uid
    table.insert(where_parts, "r.uid = :uid")
  end
  if params.object or params.name then
    qargs.object = (params.object or params.name) .. "%"
    table.insert(where_parts, "ro.object LIKE :object")
  end
  if params.char or params.character then
    -- room_inventory doesn't filter by char, ignore
  end

  local orderby = params.orderby and ("ORDER BY " .. params.orderby) or "ORDER BY r.uid, ro.object, i.name"
  local limit   = params.limit and ("LIMIT " .. tonumber(params.limit)) or ""

  local sql = [[
    SELECT
        r.uid
      , r.nickname
      , ro.object
      , ro.prepositions
      , i.name
      , i.noun
      , i.type
      , ri.amount
      , ri.path
      , ri.stack
      , ri.stack_status
    FROM room_inventory ri
      INNER JOIN room_object ro ON ri.room_object_id = ro.id
      INNER JOIN room r         ON ro.room_id = r.id
      INNER JOIN item i         ON ri.item_id = i.id
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    ]] .. orderby .. " " .. limit

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb room_inventory_query error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- count_room_inventory — count items per room_object
-- ---------------------------------------------------------------------------
function M.count_room_inventory(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "r.game LIKE :game" }
  local qargs = { game = game }

  if params.uid then
    qargs.uid = params.uid
    table.insert(where_parts, "r.uid = :uid")
  end

  local sql = [[
    SELECT
        r.uid
      , r.nickname
      , ro.object
      , COUNT(DISTINCT ri.item_id)  AS items
      , SUM(ri.amount)              AS total_qty
    FROM room_inventory ri
      INNER JOIN room_object ro ON ri.room_object_id = ro.id
      INNER JOIN room r         ON ro.room_id = r.id
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    GROUP BY r.uid, r.nickname, ro.object
    ORDER BY r.uid, ro.object
  ]]

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb count_room_inventory error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- item_base_query — query item table (name/noun/type catalog)
-- ---------------------------------------------------------------------------
function M.item_base_query(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "i.game LIKE :game" }
  local qargs = { game = game }

  if params.search then
    local sv = params.search:gsub("%*", "%%")
    qargs.search = sv
    table.insert(where_parts, "i.name LIKE :search")
  end
  if params.noun then
    qargs.noun = params.noun:gsub("%*", "%%")
    table.insert(where_parts, "i.noun LIKE :noun")
  end
  if params.type then
    qargs.type = params.type:gsub("%*", "%%")
    table.insert(where_parts, "i.type LIKE :type")
  end

  local orderby = params.orderby and ("ORDER BY " .. params.orderby) or "ORDER BY i.id DESC"
  local limit   = params.limit and ("LIMIT " .. tonumber(params.limit)) or ""

  local sql = [[
    SELECT i.id, i.game, i.noun, i.category, i.type, i.name, i.link_name
    FROM item i
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    ]] .. orderby .. " " .. limit

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb item_base_query error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- item_detail_query — query item_detail table (notes/analyze/inspect etc.)
-- ---------------------------------------------------------------------------
function M.item_detail_query(conn, params)
  params = params or {}
  local game = params.game or GameState.game or "GS3"
  local where_parts = { "i.game LIKE :game" }
  local qargs = { game = game }

  if params.search then
    local sv = params.search:gsub("%*", "%%")
    qargs.search = sv
    table.insert(where_parts, "i.name LIKE :search")
  end
  if params.note then
    qargs.note = "%" .. params.note .. "%"
    table.insert(where_parts, "id.note LIKE :note")
  end

  local orderby = params.orderby and ("ORDER BY " .. params.orderby) or "ORDER BY id.note DESC"
  local limit   = params.limit and ("LIMIT " .. tonumber(params.limit)) or ""

  local sql = [[
    SELECT i.name, id.note, id.inspect, id.analyze, id.look, id.label,
           id.read, id.recall, id.loresong, id.assess, id.elemental,
           id.charge, id.script
    FROM item_detail id
      INNER JOIN item i ON i.id = id.item_id
    WHERE ]] .. table.concat(where_parts, " AND ") .. [[
    ]] .. orderby .. " " .. limit

  local rows, err = conn:query2(sql, qargs)
  if err then respond("invdb item_detail_query error: " .. err); return end
  respond(util.format_table(rows))
end

-- ---------------------------------------------------------------------------
-- item_note_upsert — add or update a note on an item (by right-hand item)
-- ---------------------------------------------------------------------------
function M.item_note_upsert(conn, params)
  local game = GameState.game or "GS3"
  local note = params.note or params.text or ""

  if note == "" then
    respond("invdb: item_note_upsert: note= required")
    return
  end

  -- Resolve item_id from params or from right-hand item
  local item_id = nil
  if params.item_id then
    item_id = tonumber(params.item_id)
  elseif params.name then
    item_id = conn:scalar(
      "SELECT id FROM item WHERE name = :name AND game = :game LIMIT 1",
      { name = params.name, game = game })
  else
    -- Use right-hand item name
    local rh = GameObj.right_hand()
    if rh and rh.name then
      item_id = conn:scalar(
        "SELECT id FROM item WHERE name = :name AND game = :game LIMIT 1",
        { name = rh.name, game = game })
      if not item_id then
        item_id = conn:scalar(
          "SELECT id FROM item WHERE link_name = :name AND game = :game LIMIT 1",
          { name = rh.name, game = game })
      end
    end
  end

  if not item_id then
    respond("invdb: item_note_upsert: could not find item (hold it or provide name=)")
    return
  end

  -- Ensure item_detail row exists
  conn:exec(
    "INSERT OR IGNORE INTO item_detail (item_id) VALUES (:item_id)",
    { item_id = item_id })

  conn:exec(
    "UPDATE item_detail SET note = :note WHERE item_id = :item_id",
    { note = note, item_id = item_id })

  respond("invdb: note saved for item_id=" .. tostring(item_id))
end

return M
