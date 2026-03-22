--- @revenant-script
--- name: plat_to_prime_copy
--- version: 1.1.1
--- author: Tysong
--- game: gs
--- description: Copy Lich settings from Platinum to Prime (or other server variants)
--- tags: lich, utility, platinum, lichdb, gsplat
--- requires_trust: true
---
--- Ported from plat_to_prime_copy.lic (259 lines)
---
--- This script copies character settings (script auto settings, uservars, aliases)
--- from one game instance (e.g. GSPlat) to another (e.g. GSIV).
--- It operates on the lich.db3 and alias.db3 SQLite databases.
---
--- Usage:
---   ;plat_to_prime_copy
---   ;plat_to_prime_copy from:Mymain to:Somealt
---   ;plat_to_prime_copy from:Mymain to:Somealt source:GSPlat target:GSIV

local sqlite3 = require("lsqlite3")

-- Parse arguments
local args = script.vars[0] or ""

local settings_source = GameState.name
local settings_target = GameState.name
local game_source = "GSPlat"
local game_target = "GSIV"

-- Parse from: argument
local from_match = args:match("%-?%-?from[=: ](%w+)")
if from_match then
    settings_source = from_match:sub(1,1):upper() .. from_match:sub(2):lower()
end

-- Parse to: argument
local to_match = args:match("%-?%-?to[=: ](%w+)")
if to_match then
    settings_target = to_match:sub(1,1):upper() .. to_match:sub(2):lower()
end

-- Parse source: argument
local source_match = args:match("%-?%-?source[=: ]([%w%d]+)")
if source_match then
    local s = source_match:lower()
    if s:match("gsplat") then game_source = "GSPlat"
    elseif s:match("gsiv") or s:match("gs4") or s:match("gs3") then game_source = "GSIV"
    elseif s:match("gsf") then game_source = "GSF"
    elseif s:match("gst") then game_source = "GST"
    end
end

-- Parse target: argument
local target_match = args:match("%-?%-?target[=: ]([%w%d]+)")
if target_match then
    local t = target_match:lower()
    if t:match("gsplat") then game_target = "GSPlat"
    elseif t:match("gsiv") or t:match("gs4") or t:match("gs3") then game_target = "GSIV"
    elseif t:match("gsf") then game_target = "GSF"
    elseif t:match("gst") then game_target = "GST"
    end
end

local copy_go2 = (game_source ~= game_target)
local scope_source = game_source .. ":" .. settings_source
local scope_target = game_target .. ":" .. settings_target

-- Backup databases
local timestamp = os.time()
local backup_suffix = string.format("-FROM-%s_%s-TO-%s_%s-%d.bak",
    game_source, settings_source, game_target, settings_target, timestamp)

local alias_db_path = DATA_DIR .. "/alias.db3"
local lich_db_path = DATA_DIR .. "/lich.db3"

local function file_copy(src, dst)
    local inf = io.open(src, "rb")
    if not inf then return false end
    local data = inf:read("*a")
    inf:close()
    local outf = io.open(dst, "wb")
    if not outf then return false end
    outf:write(data)
    outf:close()
    return true
end

local function db_execute_retry(db, sql)
    local max_retries = 10
    for i = 1, max_retries do
        local rc = db:exec(sql)
        if rc == sqlite3.OK then return true end
        if rc == sqlite3.BUSY then
            sleep(0.1)
        else
            echo("SQL error: " .. db:errmsg())
            return false
        end
    end
    echo("SQL busy timeout after retries")
    return false
end

echo("Existing alias.db3 backed up to " .. alias_db_path .. backup_suffix)
file_copy(alias_db_path, alias_db_path .. backup_suffix)

echo("Existing lich.db3 backed up to " .. lich_db_path .. backup_suffix)
file_copy(lich_db_path, lich_db_path .. backup_suffix)

respond(string.rep("-", 64))
respond("copy from: " .. scope_source)
respond("copy to:   " .. scope_target)
respond("will overwrite existing UserVars, Script GameSettings/CharSettings/Settings, and character aliases for " .. scope_target)
respond("!!! pausing script.  Unpause if input shown above is correct. ")
respond(string.rep("-", 64))
pause_script()

-- Open lich.db3
local db = sqlite3.open(lich_db_path)
if not db then
    echo("Error: could not open lich.db3")
    return
end

-- Update aliases
Script.run("alias", "stop")
local alias_db = sqlite3.open(alias_db_path)
if alias_db then
    local alias_source = (game_source:lower() .. "_" .. settings_source:lower()):gsub("[^a-z_]", "")
    local alias_target = (game_target:lower() .. "_" .. settings_target:lower()):gsub("[^a-z_]", "")

    db_execute_retry(alias_db, "DROP TABLE IF EXISTS " .. alias_target .. ";")
    db_execute_retry(alias_db, "CREATE TABLE IF NOT EXISTS " .. alias_target ..
        " (trigger TEXT NOT NULL, target TEXT NOT NULL, UNIQUE(trigger));")
    db_execute_retry(alias_db, string.format(
        "INSERT INTO %s (trigger, target) SELECT trigger, target FROM %s;",
        alias_target, alias_source))
    respond(alias_source .. " aliases copied to " .. alias_target)
    alias_db:close()
end
Script.run("alias")

-- Delete existing script settings for target
db_execute_retry(db, "DELETE FROM script_auto_settings WHERE scope='" .. scope_target .. "'")
respond(scope_target .. " script settings deleted")

-- Delete and copy uservars
db_execute_retry(db, "DELETE FROM uservars WHERE scope='" .. scope_target .. "'")
respond(scope_target .. " uservars deleted")

db_execute_retry(db, string.format(
    "INSERT INTO uservars (hash, scope) SELECT hash, '%s' FROM uservars WHERE scope='%s'",
    scope_target, scope_source))
respond(scope_source .. " uservars copied to " .. scope_target)

-- Copy script settings (only those not already existing)
db_execute_retry(db, string.format([[
    INSERT INTO script_auto_settings (script, scope, hash)
    SELECT script, '%s', hash
    FROM script_auto_settings AS sas
    WHERE scope='%s'
      AND NOT EXISTS (
        SELECT 1 FROM script_auto_settings i
        WHERE i.script = sas.script AND i.scope = '%s'
      )
]], scope_target, scope_source, scope_target))
respond(scope_source .. " script settings copied to " .. scope_target)

-- Overwrite global go2 if source/target are different games
if copy_go2 then
    db_execute_retry(db, string.format(
        "DELETE FROM script_auto_settings WHERE script='go2' AND scope IN ('%s:','%s')",
        game_target, game_target))
    respond(game_target .. " go2 settings deleted")

    -- Check if target go2 exists
    local stmt = db:prepare("SELECT 1 FROM script_auto_settings WHERE scope=? AND script='go2'")
    stmt:bind_values(game_target)
    local exists = (stmt:step() == sqlite3.ROW)
    stmt:finalize()

    if not exists then
        db_execute_retry(db, string.format([[
            INSERT INTO script_auto_settings (script, hash, scope)
            SELECT 'go2', hash, '%s:' FROM script_auto_settings
            WHERE scope='%s:' AND script='go2'
              AND NOT EXISTS (
                SELECT 1 FROM script_auto_settings
                WHERE scope='%s:' AND script='go2'
              )
        ]], game_target, game_source, game_target))

        db_execute_retry(db, string.format([[
            INSERT INTO script_auto_settings (script, hash, scope)
            SELECT 'go2', hash, '%s' FROM script_auto_settings
            WHERE scope='%s' AND script='go2'
              AND NOT EXISTS (
                SELECT 1 FROM script_auto_settings
                WHERE scope='%s' AND script='go2'
              )
        ]], game_target, game_source, game_target))

        respond(game_source .. " go2 settings copied to " .. game_target)
    end
end

db:close()
echo("Settings copy complete.")
