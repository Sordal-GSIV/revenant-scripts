--- @revenant-script
--- name: startup-manager
--- version: 1.0.0
--- author: Ondreian
--- description: GitHub Actions-style script dependency management with topological sort
--- tags: startup,dependencies,management
---
--- Usage:
---   ;startup-manager                    # Load global + current character
---   ;startup-manager --character=Name   # Load global + specific character
---   ;startup-manager --global-only      # Load only global scripts
---   ;startup-manager --dry-run          # Show what would be loaded
---   ;startup-manager --validate         # Check dependencies only
---   ;startup-manager --init             # Create config files
---   ;startup-manager --migrate          # Migrate from autostart
---   ;startup-manager --migrate --dry-run # Preview migration
---   ;startup-manager --help             # Show help
---
--- Config files: data/startup-manager/
---   global.json          -- Scripts for all characters
---   <character>.json     -- Character-specific scripts
---
--- Original author: Ondreian
--- Changelog (from Lich5):
---   v1.0.0 (2026-03-20) - initial port from startup-manager.lic
---                          Config format changed YAML -> JSON (no YAML parser in Revenant)
---                          Migration reads from data/startup-manager/autostart-export.json
---                          or data/startup-manager/migrate.txt (Lich5 Marshal not available)
--- @lic-certified: complete 2026-03-20

local VERSION    = "1.0.0"
local CONFIG_DIR = "data/startup-manager"
local GLOBAL_CONFIG    = CONFIG_DIR .. "/global.json"
local MIGRATE_EXPORT   = CONFIG_DIR .. "/autostart-export.json"
local MIGRATE_SIMPLE   = CONFIG_DIR .. "/migrate.txt"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function has_arg(arg)
    for _, v in ipairs(Script.vars) do
        if v == arg then return true end
    end
    return false
end

local function get_arg_value(prefix)
    for _, v in ipairs(Script.vars) do
        if v:sub(1, #prefix) == prefix then
            return v:sub(#prefix + 1)
        end
    end
    return nil
end

local function char_config_file(character)
    character = character or string.lower(GameState.name or "unknown")
    return CONFIG_DIR .. "/" .. character .. ".json"
end

--------------------------------------------------------------------------------
-- Config I/O
--------------------------------------------------------------------------------

local function ensure_data_dir()
    if not File.is_dir(CONFIG_DIR) then
        File.mkdir(CONFIG_DIR)
    end
end

local function load_config(file_path)
    if not File.exists(file_path) then return {} end

    local ok, content = pcall(File.read, file_path)
    if not ok then
        respond("Error reading config " .. file_path .. ": " .. tostring(content))
        return {}
    end

    local ok2, data = pcall(Json.decode, content)
    if not ok2 then
        respond("Error parsing config " .. file_path .. ": " .. tostring(data))
        return {}
    end

    local scripts = (type(data) == "table" and data.scripts) or {}
    -- Ensure depends_on defaults to empty array if missing
    for _, sc in pairs(scripts) do
        if sc.depends_on == nil then
            sc.depends_on = {}
        end
    end
    return scripts
end

local function save_config(scripts, file_path)
    ensure_data_dir()
    local ok, err = pcall(File.write, file_path, Json.encode({ scripts = scripts }))
    if not ok then
        respond("Error saving config: " .. tostring(err))
    else
        respond("Configuration saved to: " .. file_path)
    end
end

--------------------------------------------------------------------------------
-- Dependency resolution — Kahn's algorithm (topological sort)
--------------------------------------------------------------------------------

local function resolve_dependencies(scripts)
    local dependencies = {}
    local dependents   = {}
    local in_degree    = {}

    for script_name, config in pairs(scripts) do
        dependencies[script_name] = config.depends_on or {}
        dependents[script_name]   = {}
        in_degree[script_name]    = 0
    end

    -- Build reverse graph and calculate in-degrees
    for script_name, deps in pairs(dependencies) do
        for _, dep in ipairs(deps) do
            if scripts[dep] then
                table.insert(dependents[dep], script_name)
                in_degree[script_name] = in_degree[script_name] + 1
            else
                respond("Warning: " .. script_name .. " depends on missing script: " .. dep)
            end
        end
    end

    -- Seed queue with zero-in-degree scripts (sorted for deterministic ordering)
    local queue = {}
    for script_name, degree in pairs(in_degree) do
        if degree == 0 then table.insert(queue, script_name) end
    end
    table.sort(queue)

    local result = {}
    while #queue > 0 do
        local current = table.remove(queue, 1)
        table.insert(result, current)

        local newly_ready = {}
        for _, dependent in ipairs(dependents[current]) do
            in_degree[dependent] = in_degree[dependent] - 1
            if in_degree[dependent] == 0 then
                table.insert(newly_ready, dependent)
            end
        end
        table.sort(newly_ready)
        for _, s in ipairs(newly_ready) do
            table.insert(queue, s)
        end
    end

    -- Detect circular dependencies
    local script_count = 0
    for _ in pairs(scripts) do script_count = script_count + 1 end

    if #result ~= script_count then
        local result_set = {}
        for _, s in ipairs(result) do result_set[s] = true end
        local remaining = {}
        for s in pairs(scripts) do
            if not result_set[s] then table.insert(remaining, s) end
        end
        table.sort(remaining)
        error("Circular dependency detected in scripts: " .. table.concat(remaining, ", "))
    end

    return result
end

--------------------------------------------------------------------------------
-- Script execution
--------------------------------------------------------------------------------

local function execute_scripts(ordered_scripts, all_scripts, dry_run)
    for _, script_name in ipairs(ordered_scripts) do
        local config = all_scripts[script_name]
        local args   = config.args

        if not Script.exists(script_name) then
            respond("  [SKIP]    " .. script_name .. " - script not found")
        elseif running(script_name) then
            respond("  [SKIP]    " .. script_name .. " - already running")
        elseif dry_run then
            local args_display = (args and args ~= "") and (" " .. args) or ""
            respond("  [DRY-RUN] Would start: " .. script_name .. args_display)
        else
            local args_display = (args and args ~= "") and (" " .. args) or ""
            local ok, err = pcall(function()
                if args and args ~= "" then
                    Script.run(script_name, args)
                else
                    Script.run(script_name)
                end
            end)
            if ok then
                respond("  [STARTED] " .. script_name .. args_display)
                pause(0.3)
            else
                respond("  [ERROR]   " .. script_name .. " - " .. tostring(err))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main load logic
--------------------------------------------------------------------------------

local function load_scripts(opts)
    opts = opts or {}
    local character    = opts.character
    local global_only  = opts.global_only  or false
    local dry_run      = opts.dry_run      or false
    local validate_only = opts.validate_only or false
    local char_name    = character or GameState.name or "unknown"

    respond("")
    respond("=== Startup Manager v" .. VERSION .. " ===")
    respond("Target: " .. char_name)
    if dry_run      then respond("(Dry run mode)") end
    if validate_only then respond("(Validation only)") end
    respond("")

    local ok, err = pcall(function()
        local global_scripts = load_config(GLOBAL_CONFIG)
        local char_key       = character and string.lower(character) or nil
        local char_scripts   = global_only and {} or load_config(char_config_file(char_key))

        -- Merge: character scripts override global on name collision
        local all_scripts = {}
        for k, v in pairs(global_scripts) do all_scripts[k] = v end
        for k, v in pairs(char_scripts)   do all_scripts[k] = v end

        local count = 0
        for _ in pairs(all_scripts) do count = count + 1 end

        if count == 0 then
            respond("No scripts configured. Use --init to create config files.")
            return
        end

        local ordered = resolve_dependencies(all_scripts)

        respond("=== Dependency Resolution ===")
        for i, script_name in ipairs(ordered) do
            local config      = all_scripts[script_name]
            local deps        = config.depends_on or {}
            local deps_str    = #deps == 0 and "none" or table.concat(deps, ", ")
            local args_str    = (config.args and config.args ~= "") and (" (args: " .. config.args .. ")") or ""
            respond("  " .. i .. ". " .. script_name .. args_str .. " - depends on: " .. deps_str)
        end
        respond("")

        if validate_only then return end

        respond("=== Script Execution ===")
        execute_scripts(ordered, all_scripts, dry_run)
        respond("")
        respond("=== Startup Complete ===")
        respond("")
    end)

    if not ok then
        respond("Startup Manager Error: " .. tostring(err))
        if has_arg("--debug") then error(err) end
    end
end

--------------------------------------------------------------------------------
-- Init — create example config files
--------------------------------------------------------------------------------

local function init_configs()
    ensure_data_dir()

    if not File.exists(GLOBAL_CONFIG) then
        local example = {
            scripts = {
                tilde = { args = nil,     depends_on = {} },
                shiva = { args = "--load", depends_on = { "tilde" } },
            }
        }
        File.write(GLOBAL_CONFIG, Json.encode(example))
        respond("Created: " .. GLOBAL_CONFIG)
    else
        respond("Already exists: " .. GLOBAL_CONFIG)
    end

    local char_file = char_config_file()
    if not File.exists(char_file) then
        local example = {
            scripts = {
                eloot = { args = "start", depends_on = {} },
            }
        }
        File.write(char_file, Json.encode(example))
        respond("Created: " .. char_file)
    else
        respond("Already exists: " .. char_file)
    end

    respond("")
    respond("Configuration files initialized.")
    respond("Edit them to customize your startup scripts:")
    respond("  Global:    " .. GLOBAL_CONFIG)
    respond("  Character: " .. char_config_file())
    respond("")
    respond('Config format (JSON):')
    respond('  { "scripts": {')
    respond('      "tilde": { "args": null,    "depends_on": [] },')
    respond('      "shiva": { "args": "--load", "depends_on": ["tilde"] }')
    respond('  }}')
    respond("")
end

--------------------------------------------------------------------------------
-- Migrate — import from autostart-export.json or migrate.txt
--
-- Revenant cannot read Lich5's Marshal-serialized SQLite blobs directly.
-- Instead, provide one of:
--   data/startup-manager/autostart-export.json
--     { "global":    [{"name":"tilde","args":[]}, ...],
--       "character": [{"name":"eloot","args":["start"]}, ...] }
--
--   data/startup-manager/migrate.txt   (simple one-script-per-line format)
--     tilde
--     shiva --load
--     eloot start
--     # lines starting with # are comments
--------------------------------------------------------------------------------

local function convert_scripts_list(list)
    local result = {}
    for _, info in ipairs(list) do
        local name = info.name
        local args = info.args
        if type(args) == "table" then
            args = #args > 0 and table.concat(args, " ") or nil
        end
        if args == "" then args = nil end
        result[name] = { args = args, depends_on = {} }
    end
    return result
end

local function migrate_from_autostart(dry_run)
    respond("")
    respond("=== Autostart Migration ===")
    if dry_run then respond("DRY RUN - no files will be written") end
    respond("")

    local autostart_data = {}
    local source = nil

    if File.exists(MIGRATE_EXPORT) then
        local ok, content = pcall(File.read, MIGRATE_EXPORT)
        if ok then
            local ok2, data = pcall(Json.decode, content)
            if ok2 then
                autostart_data = data
                source = MIGRATE_EXPORT
            else
                respond("Error parsing " .. MIGRATE_EXPORT .. ": " .. tostring(data))
            end
        end
    elseif File.exists(MIGRATE_SIMPLE) then
        local ok, content = pcall(File.read, MIGRATE_SIMPLE)
        if ok then
            local list = {}
            for line in content:gmatch("[^\n]+") do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" and not line:match("^#") then
                    local name, rest = line:match("^(%S+)%s*(.*)")
                    if name then
                        local args_list = {}
                        for a in rest:gmatch("%S+") do table.insert(args_list, a) end
                        table.insert(list, { name = name, args = args_list })
                    end
                end
            end
            autostart_data.global = list
            source = MIGRATE_SIMPLE
        end
    end

    if not source then
        respond("No migration source found.")
        respond("")
        respond("To migrate from an existing autostart configuration, create one of:")
        respond("")
        respond("  " .. MIGRATE_EXPORT)
        respond('    { "global":    [{"name":"tilde","args":[]},')
        respond('                   {"name":"shiva","args":["--load"]}],')
        respond('      "character": [{"name":"eloot","args":["start"]}] }')
        respond("")
        respond("  " .. MIGRATE_SIMPLE)
        respond("    # one script per line (args after the name)")
        respond("    tilde")
        respond("    shiva --load")
        respond("    eloot start")
        respond("")
        respond("Or use --init to start fresh with example config files.")
        return
    end

    respond("Reading from: " .. source)

    local global_list = autostart_data.global    or {}
    local char_list   = autostart_data.character or {}

    if #global_list == 0 and #char_list == 0 then
        respond("No autostart configuration found to migrate.")
        return
    end

    if not dry_run then ensure_data_dir() end

    -- Global scripts
    if #global_list > 0 then
        respond("Found " .. #global_list .. " global script(s):")
        for _, info in ipairs(global_list) do
            local args = info.args
            local args_str = ""
            if type(args) == "table" and #args > 0 then
                args_str = " (args: " .. table.concat(args, " ") .. ")"
            elseif type(args) == "string" and args ~= "" then
                args_str = " (args: " .. args .. ")"
            end
            respond("  - " .. info.name .. args_str)
        end

        local global_scripts = convert_scripts_list(global_list)
        local global_config  = { scripts = global_scripts }

        if dry_run then
            respond("")
            respond("Would create: " .. GLOBAL_CONFIG)
            respond(Json.encode(global_config))
        else
            File.write(GLOBAL_CONFIG, Json.encode(global_config))
            respond("")
            respond("Created: " .. GLOBAL_CONFIG)
        end
    end

    -- Character scripts
    if #char_list > 0 then
        local char_file = char_config_file()
        respond("")
        respond("Found " .. #char_list .. " character script(s):")
        for _, info in ipairs(char_list) do
            local args = info.args
            local args_str = ""
            if type(args) == "table" and #args > 0 then
                args_str = " (args: " .. table.concat(args, " ") .. ")"
            elseif type(args) == "string" and args ~= "" then
                args_str = " (args: " .. args .. ")"
            end
            respond("  - " .. info.name .. args_str)
        end

        local char_scripts = convert_scripts_list(char_list)
        local char_config  = { scripts = char_scripts }

        if dry_run then
            respond("")
            respond("Would create: " .. char_file)
            respond(Json.encode(char_config))
        else
            File.write(char_file, Json.encode(char_config))
            respond("")
            respond("Created: " .. char_file)
        end
    end

    if not dry_run then
        respond("")
        respond("=== Migration Complete ===")
        respond("")
        respond("Run: ;startup-manager --validate to verify the dependency resolution.")
        respond("")
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("Startup Manager v" .. VERSION)
    respond("")
    respond("Usage:")
    respond("  ;startup-manager                    # Load global + current character")
    respond("  ;startup-manager --character=Name   # Load global + specific character")
    respond("  ;startup-manager --global-only      # Load only global scripts")
    respond("  ;startup-manager --dry-run          # Show what would be loaded")
    respond("  ;startup-manager --validate         # Check dependencies only")
    respond("  ;startup-manager --init             # Create example config files")
    respond("  ;startup-manager --migrate          # Import from autostart export")
    respond("  ;startup-manager --migrate --dry-run # Preview migration")
    respond("  ;startup-manager --debug            # Re-raise errors with stack trace")
    respond("  ;startup-manager --help             # Show this help")
    respond("")
    respond("Configuration dir: " .. CONFIG_DIR .. "/")
    respond("  global.json         -- scripts for all characters")
    respond("  <character>.json    -- character-specific scripts")
    respond("")
    respond("Config format (JSON):")
    respond('  { "scripts": {')
    respond('      "tilde": { "args": null,     "depends_on": [] },')
    respond('      "shiva": { "args": "--load",  "depends_on": ["tilde"] },')
    respond('      "eloot": { "args": "start",   "depends_on": [] }')
    respond('  }}')
    respond("")
    respond("Migration (from Lich5 autostart):")
    respond("  Create: " .. MIGRATE_EXPORT)
    respond('    { "global":    [{"name":"tilde","args":[]}],')
    respond('      "character": [{"name":"eloot","args":["start"]}] }')
    respond("  or: " .. MIGRATE_SIMPLE)
    respond("    tilde")
    respond("    shiva --load")
    respond("  Then run: ;startup-manager --migrate")
    respond("")
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

if has_arg("--help") then
    show_help()
elseif has_arg("--init") then
    init_configs()
elseif has_arg("--migrate") then
    migrate_from_autostart(has_arg("--dry-run"))
elseif has_arg("--validate") then
    load_scripts({
        character    = get_arg_value("--character="),
        global_only  = has_arg("--global-only"),
        validate_only = true,
    })
else
    local ok, err = pcall(load_scripts, {
        character   = get_arg_value("--character="),
        global_only = has_arg("--global-only"),
        dry_run     = has_arg("--dry-run"),
    })
    if not ok then
        respond("Startup Manager Fatal Error: " .. tostring(err))
    end
end
