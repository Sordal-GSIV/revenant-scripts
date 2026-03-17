--- @revenant-script
--- name: jbackup
--- version: 1.0.0
--- author: elanthia-online
--- contributors: Jahadeem, Tysong
--- description: Character data backup utility with configurable retention
--- tags: backup,utility,files

--------------------------------------------------------------------------------
-- Configuration defaults
--------------------------------------------------------------------------------

local DEFAULT_FILES = {
    "data/entry.dat",
    "data/entry.yaml",
    "data/lich.db3",
    "data/alias.db3",
    "data/inv.db3",
    "data/ledger.db3",
    "data/jbackup.json",
}

local DEFAULT_FREQUENCY  = "daily"
local DEFAULT_RETENTION  = 14 -- days

local FREQUENCY_SECONDS = {
    daily   = 86400,
    weekly  = 604800,
    monthly = 2592000,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local output_lines = {}

local function log_msg(msg)
    table.insert(output_lines, "[" .. Script.name .. "] " .. msg)
end

local function flush_output()
    if #output_lines > 0 then
        respond(table.concat(output_lines, "\n"))
    end
end

local function format_size(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1048576 then
        return string.format("%.2f KB", bytes / 1024)
    else
        return string.format("%.2f MB", bytes / 1048576)
    end
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local config_path = "data/jbackup.json"

local function load_config()
    local cfg = {
        files          = {},
        frequency      = DEFAULT_FREQUENCY,
        retention_days = DEFAULT_RETENTION,
    }

    if File.exists(config_path) then
        local ok, data = pcall(function()
            return Json.decode(File.read(config_path))
        end)
        if ok and type(data) == "table" then
            cfg.files          = data.files or {}
            cfg.frequency      = data.frequency or DEFAULT_FREQUENCY
            cfg.retention_days = data.retention_days or DEFAULT_RETENTION
        else
            log_msg("WARNING: Failed to load config, using defaults")
        end
    else
        -- seed with defaults
        for _, f in ipairs(DEFAULT_FILES) do
            table.insert(cfg.files, f)
        end
    end

    if #cfg.files == 0 then
        for _, f in ipairs(DEFAULT_FILES) do
            table.insert(cfg.files, f)
        end
    end

    return cfg
end

local function save_config(cfg)
    local ok, err = pcall(function()
        File.write(config_path, Json.encode({
            files          = cfg.files,
            frequency      = cfg.frequency,
            retention_days = cfg.retention_days,
        }))
    end)
    if not ok then
        log_msg("WARNING: Failed to save config: " .. tostring(err))
    end
end

local function list_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Backup operations
--------------------------------------------------------------------------------

local backup_root = "jbackup"

local function ensure_dir(path)
    if not File.is_dir(path) then
        File.mkdir(path)
    end
end

local function should_backup(cfg)
    -- check most recent backup dir timestamp
    if not File.is_dir(backup_root) then return true end

    local dirs = File.list(backup_root) or {}
    if #dirs == 0 then return true end

    table.sort(dirs)
    local latest = dirs[#dirs]

    -- parse YYYYMMDD-HHMMSS from dir name
    local y, mo, d, h, mi, s = string.match(latest, "(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)")
    if not y then return true end

    local interval = FREQUENCY_SECONDS[string.lower(cfg.frequency)] or 86400
    local backup_ts = os.time({year=tonumber(y), month=tonumber(mo), day=tonumber(d),
                               hour=tonumber(h), min=tonumber(mi), sec=tonumber(s)})
    return (os.time() - backup_ts) >= interval
end

local function perform_backup(cfg, force)
    if not force and not should_backup(cfg) then
        log_msg("Skipping backup (frequency: " .. cfg.frequency .. ")")
        return false
    end

    ensure_dir(backup_root)

    local ts = os.date("%Y%m%d-%H%M%S")
    local backup_dir = backup_root .. "/" .. ts
    ensure_dir(backup_dir)

    local success_count = 0
    for _, rel in ipairs(cfg.files) do
        if File.exists(rel) then
            local ok, err = pcall(function()
                local content = File.read(rel)
                -- Recreate subdirectory structure
                local dir_part = string.match(rel, "^(.+)/[^/]+$")
                if dir_part then
                    ensure_dir(backup_dir .. "/" .. dir_part)
                end
                File.write(backup_dir .. "/" .. rel, content)
            end)
            if ok then
                log_msg("Backup success: " .. rel)
                success_count = success_count + 1
            else
                log_msg("ERROR: Failed to backup " .. rel .. ": " .. tostring(err))
            end
        else
            log_msg("Skipping: " .. rel .. " (does not exist)")
        end
    end

    -- cleanup old backups
    if success_count > 0 then
        cleanup_old(cfg)
    end

    return success_count > 0
end

function cleanup_old(cfg)
    if not File.is_dir(backup_root) then return 0 end

    local cutoff = os.time() - (cfg.retention_days * 86400)
    local removed = 0
    local dirs = File.list(backup_root) or {}

    for _, name in ipairs(dirs) do
        local y, mo, d, h, mi, s = string.match(name, "(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)")
        if y then
            local ts = os.time({year=tonumber(y), month=tonumber(mo), day=tonumber(d),
                                hour=tonumber(h), min=tonumber(mi), sec=tonumber(s)})
            if ts < cutoff then
                File.remove(backup_root .. "/" .. name)
                log_msg("Removed old backup: " .. name)
                removed = removed + 1
            end
        end
    end

    return removed
end

--------------------------------------------------------------------------------
-- CLI commands
--------------------------------------------------------------------------------

local function show_help()
    local name = Script.name
    log_msg("JBackup - Automated File Backup System")
    log_msg("")
    log_msg("Usage:")
    log_msg("")
    log_msg("  ;" .. name .. "                 Perform backup (respects frequency)")
    log_msg("  ;" .. name .. " now             Force backup now")
    log_msg("  ;" .. name .. " add <file>      Add file to backup list")
    log_msg("  ;" .. name .. " remove <file>   Remove file from backup list")
    log_msg("  ;" .. name .. " list            List files in backup configuration")
    log_msg("  ;" .. name .. " reset           Reset configuration to defaults")
    log_msg("  ;" .. name .. " cleanup         Remove old backups per retention policy")
    log_msg("  ;" .. name .. " config          Show current configuration")
    log_msg("  ;" .. name .. " help            Show this help menu")
    log_msg("")
end

local function cmd_list(cfg)
    log_msg("Files configured for backup:")
    log_msg("")
    for _, f in ipairs(cfg.files) do
        local status = File.exists(f) and "[OK]" or "[MISSING]"
        log_msg("  " .. status .. " " .. f)
    end
end

local function cmd_add(cfg, file)
    if not file or file == "" then
        log_msg("ERROR: No file specified")
        return
    end
    if not File.exists(file) then
        log_msg("ERROR: File does not exist: " .. file)
        return
    end
    if list_contains(cfg.files, file) then
        log_msg("File already in backup list: " .. file)
        return
    end
    table.insert(cfg.files, file)
    save_config(cfg)
    log_msg("Added to backup list: " .. file)
end

local function cmd_remove(cfg, file)
    if not file or file == "" then
        log_msg("ERROR: No file specified")
        return
    end
    local found = false
    for i, f in ipairs(cfg.files) do
        if f == file then
            table.remove(cfg.files, i)
            found = true
            break
        end
    end
    if found then
        save_config(cfg)
        log_msg("Removed from backup list: " .. file)
    else
        log_msg("File not found in backup list: " .. file)
    end
end

local function cmd_reset(cfg)
    cfg.files = {}
    for _, f in ipairs(DEFAULT_FILES) do
        table.insert(cfg.files, f)
    end
    cfg.frequency = DEFAULT_FREQUENCY
    cfg.retention_days = DEFAULT_RETENTION
    save_config(cfg)
    log_msg("Configuration reset to defaults")
end

local function cmd_config(cfg)
    log_msg("Current Configuration:")
    log_msg("")
    log_msg("  Frequency:      " .. cfg.frequency)
    log_msg("  Retention:      " .. cfg.retention_days .. " days")
    log_msg("")
    log_msg("  Files configured for backup (" .. #cfg.files .. "):")
    log_msg("")
    for _, f in ipairs(cfg.files) do
        local status = File.exists(f) and "[OK]" or "[MISSING]"
        log_msg("     " .. status .. " " .. f)
    end
    log_msg("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local cfg = load_config()
local cmd = Script.vars[1] and string.lower(Script.vars[1]) or nil

if cmd == "help" then
    show_help()
elseif cmd == "list" then
    cmd_list(cfg)
elseif cmd == "add" then
    cmd_add(cfg, Script.vars[2])
elseif cmd == "remove" then
    cmd_remove(cfg, Script.vars[2])
elseif cmd == "reset" then
    cmd_reset(cfg)
elseif cmd == "cleanup" then
    local count = cleanup_old(cfg)
    log_msg("Removed " .. count .. " old backup(s)")
elseif cmd == "config" then
    cmd_config(cfg)
elseif cmd == "now" then
    log_msg("Forcing manual backup...")
    if perform_backup(cfg, true) then
        log_msg("Manual backup completed successfully")
    else
        log_msg("ERROR: Manual backup failed")
    end
elseif cmd == nil then
    if perform_backup(cfg, false) then
        log_msg("Backup completed successfully")
    else
        log_msg("Backup skipped or completed with errors")
    end
else
    show_help()
end

flush_output()
