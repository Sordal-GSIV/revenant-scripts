-- schema.lua — DB schema, migrations, and temp table setup for invdb
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

-- Current schema version this build expects
M.SCHEMA_VERSION = 12

-- ---------------------------------------------------------------------------
-- migrate(conn) — bring an opened invdb SQLite connection up to version 12.
-- Idempotent: safe to call on an already-current database.
-- ---------------------------------------------------------------------------
function M.migrate(conn)
  local uv, err = conn:scalar("pragma user_version")
  if err then error("invdb schema: pragma user_version: " .. err) end
  local user_version = uv or 0

  -- -------------------------------------------------------------------------
  -- Version 0 → 1: initial tables
  -- -------------------------------------------------------------------------
  if user_version == 0 then
    local sql = [[
      CREATE TABLE IF NOT EXISTS character (
          id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , name          TEXT    NOT NULL
        , game          TEXT    NOT NULL DEFAULT ''
        , account       TEXT    NOT NULL DEFAULT ''
        , prof          TEXT    NOT NULL DEFAULT ''
        , race          TEXT    NOT NULL DEFAULT ''
        , level         INTEGER NOT NULL DEFAULT 0
        , exp           INTEGER NOT NULL DEFAULT 0
        , area          TEXT    NOT NULL DEFAULT ''
        , subscription  TEXT    NOT NULL DEFAULT ''
        , locker        TEXT    NOT NULL DEFAULT ''
        , citizenship   TEXT    NOT NULL DEFAULT ''
        , society       TEXT    NOT NULL DEFAULT ''
        , society_rank  TEXT    NOT NULL DEFAULT ''
        , timestamp     INTEGER NOT NULL DEFAULT 0
        , UNIQUE (name, game)
      );
      CREATE TABLE IF NOT EXISTS bank (
          id      INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , name    TEXT    NOT NULL UNIQUE
        , abbr    TEXT    NOT NULL UNIQUE
      );
      CREATE TABLE IF NOT EXISTS silver (
          character_id INTEGER NOT NULL REFERENCES character(id)
        , bank_id      INTEGER NOT NULL REFERENCES bank(id)
        , amount       INTEGER NOT NULL
        , timestamp    INTEGER NOT NULL
        , UNIQUE (character_id, bank_id)
      );
      CREATE TABLE IF NOT EXISTS location (
          id      INTEGER NOT NULL PRIMARY KEY
        , type    TEXT    NOT NULL
        , name    TEXT    NOT NULL UNIQUE
        , abbr    TEXT    NOT NULL UNIQUE
      );
      CREATE INDEX IF NOT EXISTS ix_character_name_game ON character(name, game);
    ]]
    local _, e = conn:exec_batch(sql)
    if e then error("invdb schema v0→1: " .. e) end

    -- Seed bank reference data
    local bank_seed = [[
      INSERT OR IGNORE INTO bank(id,name,abbr) VALUES
         (1,  'First Elanith Secured Bank',       'wl')
        ,(2,  'Great Bank of Kharam-Dzu',          'teras')
        ,(3,  'Vornavis Bank of Solhaven',          'sol')
        ,(4,  'Bank of Torre County',               'rr')
        ,(5,  'Icemule Trace Bank',                 'im')
        ,(6,  'Bank of Kharag''doth Dzulthu',       'zul')
        ,(7,  'United City-States Bank',            'en')
        ,(8,  'Four Winds Bank',                    'fwi')
        ,(9,  'Cysaegir Bank',                      'cy')
        ,(11, 'Kraken''s Fall Bank',                'kf')
        ,(99, 'Total',                              'total');
    ]]
    local _, e2 = conn:exec_batch(bank_seed)
    if e2 then error("invdb schema v0→1 bank seed: " .. e2) end

    -- Seed location reference data
    local loc_seed = [[
      INSERT OR IGNORE INTO location(id,type,name,abbr) VALUES
         (1 ,'inv'   ,'hands',               'hands')
        ,(2 ,'inv'   ,'inv',                  'inv')
        ,(6 ,'inv'   ,'alongside',            'alongside')
        ,(10,'locker','locker',               'locker')
        ,(11,'locker','Wehnimer''s Landing',  'wl')
        ,(12,'locker','Teras Isle',           'teras')
        ,(13,'locker','Solhaven',             'sol')
        ,(14,'locker','River''s Rest',        'rr')
        ,(15,'locker','Icemule Trace',        'im')
        ,(16,'locker','Zul Logoth',           'zul')
        ,(17,'locker','Ta''Illistim',         'ti')
        ,(18,'locker','Ta''Vaalor',           'tv')
        ,(19,'locker','Mist Harbor',          'fwi')
        ,(20,'locker','Cysaegir',             'cy')
        ,(21,'locker','Kraken''s Fall',       'kf')
        ,(30,'locker','Astral Vault',         'av')
        ,(40,'locker','Family Vault',         'fam');
    ]]
    local _, e3 = conn:exec_batch(loc_seed)
    if e3 then error("invdb schema v0→1 loc seed: " .. e3) end

    conn:pragma("user_version", 1)
    user_version = 1
  end

  -- -------------------------------------------------------------------------
  -- Version 1 → 2 (no-op migration in original)
  -- -------------------------------------------------------------------------
  if user_version == 1 then
    conn:pragma("user_version", 2)
    user_version = 2
  end

  -- -------------------------------------------------------------------------
  -- Version 2 → 3: add tickets table
  -- -------------------------------------------------------------------------
  if user_version == 2 then
    local _, e = conn:exec_batch([[
      CREATE TABLE IF NOT EXISTS tickets (
          character_id  INTEGER NOT NULL REFERENCES character(id)
        , source        TEXT    NOT NULL
        , amount        INTEGER NOT NULL
        , currency      TEXT    NOT NULL DEFAULT ''
        , timestamp     INTEGER NOT NULL
        , UNIQUE(character_id, source)
      );
    ]])
    if e then error("invdb schema v2→3: " .. e) end
    conn:pragma("user_version", 3)
    user_version = 3
  end

  -- -------------------------------------------------------------------------
  -- Version 3 → 4: add hidden column to item (old schema only)
  -- -------------------------------------------------------------------------
  if user_version == 3 then
    -- Old-schema item table may lack 'hidden' column; attempt to add
    conn:exec("ALTER TABLE item ADD COLUMN hidden TEXT DEFAULT ''")
    conn:pragma("user_version", 4)
    user_version = 4
  end

  -- -------------------------------------------------------------------------
  -- Version 4 → 5: add Kraken's Fall locker
  -- -------------------------------------------------------------------------
  if user_version == 4 then
    conn:exec_batch([[
      INSERT OR IGNORE INTO location(id,type,name,abbr)
        VALUES (21,'locker','Kraken''s Fall','kf');
    ]])
    conn:pragma("user_version", 5)
    user_version = 5
  end

  -- -------------------------------------------------------------------------
  -- Version 5 → 6: add Kraken's Fall bank; fix Total bank id to 99
  -- -------------------------------------------------------------------------
  if user_version == 5 then
    conn:exec_batch([[
      INSERT OR IGNORE INTO bank(id,name,abbr) VALUES (11,'Kraken''s Fall Bank','kf');
      UPDATE bank SET id = 99 WHERE name = 'Total';
    ]])
    conn:pragma("user_version", 6)
    user_version = 6
  end

  -- -------------------------------------------------------------------------
  -- Version 6 → 7: fix Cysaegir / Kraken's Fall location ids
  -- -------------------------------------------------------------------------
  if user_version == 6 then
    conn:exec_batch([[
      DELETE FROM location WHERE id >= 20;
      INSERT OR IGNORE INTO location(id,type,name,abbr)
        VALUES (20,'locker','Cysaegir','cy'), (21,'locker','Kraken''s Fall','kf');
    ]])
    conn:pragma("user_version", 7)
    user_version = 7
  end

  -- -------------------------------------------------------------------------
  -- Version 7 → 8: add alongside location
  -- -------------------------------------------------------------------------
  if user_version == 7 then
    conn:exec_batch([[
      INSERT OR IGNORE INTO location(id,type,name,abbr)
        VALUES (6,'inv','alongside','alongside');
    ]])
    conn:pragma("user_version", 8)
    user_version = 8
  end

  -- -------------------------------------------------------------------------
  -- Version 8 → 9: add Astral/Family vault; restructure character table
  -- -------------------------------------------------------------------------
  if user_version == 8 then
    conn:exec_batch([[
      DELETE FROM location WHERE abbr IN ('av','fam');
      INSERT OR IGNORE INTO location(id,type,name,abbr)
        VALUES (30,'locker','Astral Vault','av'), (40,'locker','Family Vault','fam');
    ]])
    -- Ensure character table has subscription, locker columns (add if missing)
    conn:exec("ALTER TABLE character ADD COLUMN subscription TEXT NOT NULL DEFAULT ''")
    conn:exec("ALTER TABLE character ADD COLUMN locker TEXT NOT NULL DEFAULT ''")
    conn:pragma("user_version", 9)
    user_version = 9
  end

  -- -------------------------------------------------------------------------
  -- Version 9 → 10: add lumnis, resource, account tables;
  --                  add citizenship/society/society_rank to character
  -- -------------------------------------------------------------------------
  if user_version == 9 then
    local _, e = conn:exec_batch([[
      CREATE TABLE IF NOT EXISTS lumnis (
          character_id  INTEGER NOT NULL PRIMARY KEY REFERENCES character(id)
        , status        TEXT    NOT NULL DEFAULT ''
        , triple        INTEGER NOT NULL DEFAULT 0
        , double        INTEGER NOT NULL DEFAULT 0
        , total         INTEGER NOT NULL DEFAULT 0
        , start_day     TEXT    NOT NULL DEFAULT ''
        , start_time    TEXT    NOT NULL DEFAULT ''
        , last_schedule TEXT    NOT NULL DEFAULT ''
        , timestamp     INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS resource (
          character_id  INTEGER NOT NULL PRIMARY KEY REFERENCES character(id)
        , energy        TEXT    NOT NULL DEFAULT ''
        , weekly        INTEGER NOT NULL DEFAULT 0
        , total         INTEGER NOT NULL DEFAULT 0
        , suffused      INTEGER NOT NULL DEFAULT 0
        , favor         INTEGER NOT NULL DEFAULT 0
        , bonus         INTEGER NOT NULL DEFAULT 0
        , timestamp     INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS account (
          account         TEXT    NOT NULL PRIMARY KEY
        , premium_points  INTEGER NOT NULL DEFAULT 0
        , simucoin        INTEGER NOT NULL DEFAULT 0
        , timestamp       INTEGER NOT NULL DEFAULT 0
      );
    ]])
    if e then error("invdb schema v9→10: " .. e) end
    conn:exec("ALTER TABLE character ADD COLUMN citizenship TEXT NOT NULL DEFAULT ''")
    conn:exec("ALTER TABLE character ADD COLUMN society TEXT NOT NULL DEFAULT ''")
    conn:exec("ALTER TABLE character ADD COLUMN society_rank TEXT NOT NULL DEFAULT ''")
    conn:pragma("user_version", 10)
    user_version = 10
  end

  -- -------------------------------------------------------------------------
  -- Version 10 → 11: new normalized item/char_inventory schema +
  --                   room/room_object/room_inventory tables
  -- -------------------------------------------------------------------------
  if user_version == 10 then
    local _, e = conn:exec_batch([[
      CREATE TABLE IF NOT EXISTS item (
          id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , name      TEXT    NOT NULL
        , noun      TEXT    NOT NULL DEFAULT ''
        , link_name TEXT    NOT NULL DEFAULT ''
        , type      TEXT    NOT NULL DEFAULT 'unknown'
        , category  TEXT    NOT NULL DEFAULT ''
        , game      TEXT    NOT NULL DEFAULT ''
        , UNIQUE(name, game)
      );
      CREATE TABLE IF NOT EXISTS item_detail (
          item_id   INTEGER NOT NULL PRIMARY KEY
        , note      TEXT NOT NULL DEFAULT ''
        , inspect   TEXT NOT NULL DEFAULT ''
        , analyze   TEXT NOT NULL DEFAULT ''
        , look      TEXT NOT NULL DEFAULT ''
        , label     TEXT NOT NULL DEFAULT ''
        , read      TEXT NOT NULL DEFAULT ''
        , recall    TEXT NOT NULL DEFAULT ''
        , loresong  TEXT NOT NULL DEFAULT ''
        , assess    TEXT NOT NULL DEFAULT ''
        , elemental TEXT NOT NULL DEFAULT ''
        , charge    TEXT NOT NULL DEFAULT ''
        , script    TEXT NOT NULL DEFAULT ''
        , CONSTRAINT fk_item_detail_item FOREIGN KEY (item_id) REFERENCES item(id) ON DELETE CASCADE
      );
      CREATE TABLE IF NOT EXISTS char_inventory (
          id           INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , character_id INTEGER NOT NULL
        , location_id  INTEGER NOT NULL
        , item_id      INTEGER NOT NULL
        , containing   TEXT    NOT NULL DEFAULT ''
        , path         TEXT    NOT NULL DEFAULT ''
        , level        INTEGER NOT NULL DEFAULT 0
        , amount       INTEGER NOT NULL DEFAULT 1
        , stack        TEXT    NOT NULL DEFAULT ''
        , stack_status TEXT    NOT NULL DEFAULT ''
        , marked       TEXT    NOT NULL DEFAULT ''
        , registered   TEXT    NOT NULL DEFAULT ''
        , hidden       TEXT    NOT NULL DEFAULT ''
        , timestamp    INTEGER NOT NULL
        , UNIQUE(character_id, location_id, item_id, containing, path, stack, stack_status, marked, registered, hidden)
        , CONSTRAINT fk_inv_char FOREIGN KEY (character_id) REFERENCES character(id) ON DELETE CASCADE
        , CONSTRAINT fk_inv_loc  FOREIGN KEY (location_id)  REFERENCES location(id)  ON DELETE CASCADE
        , CONSTRAINT fk_inv_item FOREIGN KEY (item_id)      REFERENCES item(id)      ON DELETE CASCADE
      );
      CREATE TABLE IF NOT EXISTS room (
          id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , uid       INTEGER NOT NULL
        , lich_id   INTEGER
        , property  TEXT    NOT NULL DEFAULT ''
        , nickname  TEXT    NOT NULL DEFAULT ''
        , title     TEXT    NOT NULL DEFAULT ''
        , game      TEXT    NOT NULL DEFAULT ''
        , UNIQUE (uid, game)
      );
      CREATE TABLE IF NOT EXISTS room_object (
          id           INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , room_id      INTEGER NOT NULL
        , object       TEXT    NOT NULL
        , prepositions TEXT    NOT NULL DEFAULT 'in,on,under,behind'
        , depth        INTEGER NOT NULL DEFAULT 2
        , special      TEXT    NOT NULL DEFAULT ''
        , UNIQUE(room_id, object)
        , CONSTRAINT fk_room_object FOREIGN KEY (room_id) REFERENCES room(id) ON DELETE CASCADE
      );
      CREATE TABLE IF NOT EXISTS room_inventory (
          id             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
        , room_object_id INTEGER NOT NULL
        , item_id        INTEGER NOT NULL
        , containing     TEXT    NOT NULL DEFAULT ''
        , path           TEXT    NOT NULL DEFAULT ''
        , level          INTEGER NOT NULL DEFAULT 0
        , amount         INTEGER NOT NULL DEFAULT 1
        , stack          TEXT    NOT NULL DEFAULT ''
        , stack_status   TEXT    NOT NULL DEFAULT ''
        , timestamp      INTEGER NOT NULL
        , UNIQUE(room_object_id, item_id, path, containing, stack, stack_status)
        , CONSTRAINT fk_ri_ro   FOREIGN KEY (room_object_id) REFERENCES room_object(id) ON DELETE CASCADE
        , CONSTRAINT fk_ri_item FOREIGN KEY (item_id)        REFERENCES item(id)        ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS ix_item_name    ON item(name);
      CREATE INDEX IF NOT EXISTS ix_inv_char_loc ON char_inventory(character_id, location_id);
    ]])
    if e then error("invdb schema v10→11: " .. e) end
    conn:pragma("user_version", 11)
    user_version = 11
  end

  -- -------------------------------------------------------------------------
  -- Version 11 → 12: add bounty table
  -- -------------------------------------------------------------------------
  if user_version == 11 then
    local _, e = conn:exec_batch([[
      CREATE TABLE IF NOT EXISTS bounty (
          character_id  INTEGER NOT NULL PRIMARY KEY
        , type          TEXT    NOT NULL DEFAULT ''
        , area          TEXT    NOT NULL DEFAULT ''
        , requirements  TEXT    NOT NULL DEFAULT ''
        , task          TEXT    NOT NULL DEFAULT ''
        , timestamp     INTEGER NOT NULL DEFAULT 0
        , UNIQUE(character_id)
        , CONSTRAINT fk_bounty_char FOREIGN KEY (character_id) REFERENCES character(id) ON DELETE CASCADE
      );
    ]])
    if e then error("invdb schema v11→12: " .. e) end
    conn:pragma("user_version", 12)
    user_version = 12
  end
end

-- ---------------------------------------------------------------------------
-- create_temp_tables(conn) — session-lifetime staging tables for upsert merges.
-- Called once after migration, before any refresh operation.
-- ---------------------------------------------------------------------------
function M.create_temp_tables(conn)
  local _, e = conn:exec_batch([[
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_item (
        character_id  INTEGER NOT NULL
      , location_id   INTEGER NOT NULL
      , level         INTEGER NOT NULL DEFAULT 0
      , path          TEXT    NOT NULL DEFAULT ''
      , type          TEXT    NOT NULL DEFAULT ''
      , name          TEXT    NOT NULL
      , link_name     TEXT    NOT NULL DEFAULT ''
      , containing    TEXT    NOT NULL DEFAULT ''
      , noun          TEXT    NOT NULL DEFAULT ''
      , amount        INTEGER NOT NULL
      , stack         TEXT    NOT NULL DEFAULT ''
      , stack_status  TEXT    NOT NULL DEFAULT ''
      , marked        TEXT    NOT NULL DEFAULT ''
      , registered    TEXT    NOT NULL DEFAULT ''
      , hidden        TEXT    NOT NULL DEFAULT ''
      , update_noun   INTEGER NOT NULL DEFAULT 0
      , gs_id         INTEGER
      , timestamp     INTEGER NOT NULL
    );
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_item_category (
        name     TEXT NOT NULL PRIMARY KEY
      , category TEXT NOT NULL
      , game     TEXT NOT NULL
    );
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_room_item (
        room_object_id  INTEGER NOT NULL
      , path            TEXT    NOT NULL DEFAULT ''
      , level           INTEGER NOT NULL DEFAULT 0
      , type            TEXT    NOT NULL DEFAULT ''
      , name            TEXT    NOT NULL
      , link_name       TEXT    NOT NULL DEFAULT ''
      , containing      TEXT    NOT NULL DEFAULT ''
      , noun            TEXT    NOT NULL DEFAULT ''
      , amount          INTEGER NOT NULL
      , stack           TEXT    NOT NULL DEFAULT ''
      , stack_status    TEXT    NOT NULL DEFAULT ''
      , update_noun     INTEGER NOT NULL DEFAULT 0
      , gs_id           INTEGER
      , timestamp       INTEGER NOT NULL
    );
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_silver (
        character_id INTEGER NOT NULL
      , bank_id      INTEGER NOT NULL
      , amount       INTEGER NOT NULL
      , timestamp    INTEGER NOT NULL
    );
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_tickets (
        character_id INTEGER NOT NULL
      , source       TEXT    NOT NULL
      , amount       INTEGER NOT NULL
      , currency     TEXT    NOT NULL DEFAULT ''
      , timestamp    INTEGER NOT NULL
    );
  ]])
  if e then error("invdb create_temp_tables: " .. e) end
end

-- ---------------------------------------------------------------------------
-- drop_tables(conn, target) — destructive reset, for ;invdb reset confirm
-- ---------------------------------------------------------------------------
function M.drop_tables(conn, target)
  if target:match("bank|all") then
    conn:exec("DROP TABLE IF EXISTS silver")
    conn:exec("DROP TABLE IF EXISTS bank")
  end
  if target:match("bounty|all") then
    conn:exec("DROP TABLE IF EXISTS bounty")
  end
  if target:match("tickets|all") then
    conn:exec("DROP TABLE IF EXISTS tickets")
  end
  if target:match("all") then
    conn:exec("DROP TABLE IF EXISTS location")
  end
  if target:match("items?$|item_detail|all") then
    conn:exec("DROP TABLE IF EXISTS item_detail")
  end
  if target:match("items?$|all") then
    conn:exec("DROP TABLE IF EXISTS char_inventory")
  end
  if target:match("items?$|all") then
    conn:exec("DROP TABLE IF EXISTS item")
  end
  if target:match("room_inventory|all") then
    conn:exec("DROP TABLE IF EXISTS room_inventory")
  end
  if target:match("room_object|all") then
    conn:exec("DROP TABLE IF EXISTS room_object")
  end
  if target:match("room$|all") then
    conn:exec("DROP TABLE IF EXISTS room")
  end
  if target:match("resource|all") then
    conn:exec("DROP TABLE IF EXISTS resource")
  end
  if target:match("lumnis|all") then
    conn:exec("DROP TABLE IF EXISTS lumnis")
  end
  if target:match("all") then
    conn:exec("DROP TABLE IF EXISTS character")
    conn:exec("DROP TABLE IF EXISTS account")
  end
  conn:pragma("user_version", 0)
end

return M
