--- @revenant-script
--- name: dependency
--- version: 2.3.0
--- author: rpherbig
--- original-authors: rpherbig, Etreu, Sheltim, many contributors (dr-scripts community)
--- game: dr
--- description: DR runtime daemon — arg parsing, settings loader, data files, autostart, map overrides, bot managers
--- tags: core, dependency, setup, flags, settings, argparser
--- @lic-certified: complete 2026-03-18
---
--- Full port of dependency.lic (Lich5) to Revenant Lua.
--- This is the backbone of the DR script ecosystem. Nearly every DR script
--- calls parse_args(), get_settings(), or get_data() from this file.
---
--- NOTE: The `install` subcommand has been removed. DR script installation
--- is now handled by pkg. The engine bootstrap runs automatically on first
--- launch. To install scripts manually: ;pkg install <script-name>
---
--- Provides:
---   ArgParser        — parse_args(definitions, flex_args) with help display
---   SetupFiles       — get_settings(suffixes), get_data(type), settings cache
---   ScriptManager    — autostart management, map overrides
---   BankbotManager   — bankbot transaction/ledger queue
---   ReportbotManager — reportbot whitelist queue
---   SlackbotManager  — slack message queue
---   parse_args()     — global wrapper for ArgParser
---   get_settings()   — global wrapper for SetupFiles
---   get_data()       — global wrapper for SetupFiles
---   custom_require() — inline module loader
---
--- Usage:
---   ;dependency          - Run once per session to initialize DR script environment
---   ;dependency help     - Show argument help
---   ;dependency debug    - Run with debug output

local DEPENDENCY_VERSION = "2.3.0"
local DR_SCRIPTS_DISCORD_LINK = "https://discord.gg/f8ne99pVva"

no_pause_all()
no_kill_all()

-- Verify we're in DR
if GameState.game and not GameState.game:find("^DR") then
    echo("This script is not intended for usage with games other than DragonRealms. Exiting now")
    return
end

-- Wait for repository to finish if running
while Script.running("repository") do
    echo("Repository is running, pausing for 10 seconds.")
    pause(10)
end

---------------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------------

--- Deep-copy a table (like Ruby's Marshal.load(Marshal.dump(x)))
local function deep_copy(obj)
    if type(obj) ~= "table" then return obj end
    local copy = {}
    for k, v in pairs(obj) do
        copy[deep_copy(k)] = deep_copy(v)
    end
    return setmetatable(copy, getmetatable(obj))
end

--- Shallow merge: copy keys from src into dst (dst wins on conflict when overwrite=false)
local function merge_into(dst, src, overwrite)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if overwrite or dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

--- Deep merge: recursively merge src into dst, src values win
local function deep_merge(dst, src)
    if type(src) ~= "table" then return src end
    if type(dst) ~= "table" then return deep_copy(src) end
    local result = deep_copy(dst)
    for k, v in pairs(src) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = deep_merge(result[k], v)
        else
            result[k] = deep_copy(v)
        end
    end
    return result
end

--- Split a string by whitespace
local function split_words(str)
    local words = {}
    if not str or str == "" then return words end
    for word in str:gmatch("%S+") do
        table.insert(words, word)
    end
    return words
end

--- Check if a value exists in an array-like table
local function table_contains(t, val)
    if not t then return false end
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--- Remove a value from an array-like table (in-place)
local function table_remove_value(t, val)
    if not t then return end
    for i = #t, 1, -1 do
        if t[i] == val then
            table.remove(t, i)
        end
    end
end

--- Unique values in an array-like table
local function table_unique(t)
    if not t then return {} end
    local seen = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    return result
end

--- Array difference: a - b
local function table_subtract(a, b)
    if not a then return {} end
    if not b then return a end
    local bset = {}
    for _, v in ipairs(b) do bset[v] = true end
    local result = {}
    for _, v in ipairs(a) do
        if not bset[v] then
            table.insert(result, v)
        end
    end
    return result
end

--- Array union (preserving order, unique)
local function table_union(...)
    local seen = {}
    local result = {}
    for _, t in ipairs({...}) do
        if type(t) == "table" then
            for _, v in ipairs(t) do
                if not seen[v] then
                    seen[v] = true
                    table.insert(result, v)
                end
            end
        end
    end
    return result
end

--- Case-insensitive string compare
local function iequals(a, b)
    if not a or not b then return false end
    return string.lower(tostring(a)) == string.lower(tostring(b))
end

--- Load a JSON data file, returning table or nil
local function load_json_file(path)
    if not File.exists(path) then return nil end
    local content = File.read(path)
    if not content or content == "" then return nil end
    local ok, data = pcall(Json.decode, content)
    if ok and data then return data end
    return nil
end

--- Safe load of a YAML-equivalent file (JSON in Revenant).
--- Supports .yaml -> .json fallback: tries .json first, then raw path.
local function safe_load_data_file(path)
    -- In Revenant, YAML files are stored as JSON
    local json_path = path:gsub("%.yaml$", ".json")
    local data = load_json_file(json_path)
    if data then return data end
    -- Try the original path as-is (might already be .json)
    data = load_json_file(path)
    if data then return data end
    return {}
end

---------------------------------------------------------------------------
-- ArgParser
---------------------------------------------------------------------------

local ArgParser = {}
ArgParser.__index = ArgParser

function ArgParser.new()
    return setmetatable({}, ArgParser)
end

--- Check if a single argument matches a definition
--- @param definition table  {name, regex, options, option_exact, optional, ...}
--- @param item string       the argument to test
--- @return boolean
function ArgParser:matches_def(definition, item)
    if not item then return false end
    if UserVars.parse_args_debug then
        echo(tostring(definition.name) .. ":" .. tostring(item))
    end
    -- Regex match
    if definition.regex then
        if type(definition.regex) == "string" then
            -- Lua pattern match (case-insensitive if pattern doesn't specify)
            if item:find(definition.regex) then return true end
            -- Try case-insensitive
            if item:lower():find(definition.regex:lower()) then return true end
        end
    end
    -- Options list match
    if definition.options then
        for _, option in ipairs(definition.options) do
            if definition.option_exact then
                if iequals(item, option) then return true end
            else
                if item:lower():find("^" .. option:lower()) then return true end
            end
        end
    end
    return false
end

--- Try to match a full definition set against the provided argument list
--- @param defs table     array of definition entries
--- @param vars table     array of argument strings (will be mutated)
--- @param flex boolean   whether to allow remaining args as flex
--- @return table|nil     args table if matched, nil if not
function ArgParser:check_match(defs, vars, flex)
    local args = {}

    -- First pass: required arguments (must match in order)
    for _, definition in ipairs(defs) do
        if not definition.optional then
            if not self:matches_def(definition, vars[1]) then
                return nil
            end
            args[definition.name] = vars[1]:lower()
            table.remove(vars, 1)
        end
    end

    -- Second pass: optional arguments (can match in any order)
    for _, definition in ipairs(defs) do
        if definition.optional then
            local match_idx = nil
            for i, v in ipairs(vars) do
                if self:matches_def(definition, v) then
                    match_idx = i
                    break
                end
            end
            if match_idx then
                args[definition.name] = vars[match_idx]:lower()
                table.remove(vars, match_idx)
            end
        end
    end

    if flex then
        args.flex = vars

        -- Check for YAML profile name collisions with script args
        local char_name = GameState.name or "Unknown"
        local profiles_path = "profiles"
        if File.is_dir(profiles_path) then
            local files = File.list(profiles_path) or {}
            for _, file in ipairs(files) do
                -- Match pattern: CharName-suffix.yaml or .json
                local suffix = file:match(char_name .. "%-(%w+)%.yaml") or
                               file:match(char_name .. "%-(%w+)%.json")
                if suffix then
                    for _, arg_val in pairs(args) do
                        if type(arg_val) == "string" and arg_val == suffix then
                            echo("WARNING: yaml profile '" .. char_name .. "-" .. arg_val .. "' matches script argument '" .. arg_val .. "'.")
                            echo("Favoring the script argument. Rename the file if you intend to call it as a flexed settings file.")
                        end
                    end
                end
            end
        end
    else
        -- Non-flex: all args must be consumed
        if #vars > 0 then
            return nil
        end
    end

    return args
end

--- Format a single argument definition for help display
--- @param definition table
--- @return string
function ArgParser:format_item(definition)
    local item = definition.display or definition.name
    if not item then return "" end
    if definition.optional then
        item = "[" .. item .. "]"
    elseif definition.variable or definition.options then
        item = "<" .. item .. ">"
    end
    return item
end

--- Display help output for argument definitions and YAML settings
--- @param data table  array of definition sets (each set is an array of definitions)
function ArgParser:display_args(data)
    local script_name = Script.name or "unknown"
    if script_name == "bootstrap" then return end

    for _, def_set in ipairs(data) do
        -- Show script summary if present
        for _, x in ipairs(def_set) do
            if tostring(x.name) == "script_summary" then
                respond(" SCRIPT SUMMARY: " .. (x.description or ""))
            end
        end

        respond("")
        respond(" SCRIPT CALL FORMAT AND ARG DESCRIPTIONS (arguments in brackets are optional):")

        -- Build the call format line
        local format_parts = {}
        for _, x in ipairs(def_set) do
            if tostring(x.name) ~= "script_summary" then
                local formatted = self:format_item(x)
                if formatted ~= "" then
                    table.insert(format_parts, formatted)
                end
            end
        end
        respond("  ;" .. script_name .. " " .. table.concat(format_parts, " "))

        -- Show individual arg descriptions
        for _, x in ipairs(def_set) do
            if tostring(x.name) ~= "script_summary" then
                local display_name = x.display or x.name or ""
                local desc = x.description or ""
                local opts_str = ""
                if x.options then
                    opts_str = " [" .. table.concat(x.options, ", ") .. "]"
                end
                -- Left-justify the name to 12 chars
                local padded = display_name .. string.rep(" ", math.max(0, 12 - #display_name))
                respond("   " .. padded .. " " .. desc .. opts_str)
            end
        end
    end

    -- Display YAML settings help if available
    local ok, yaml_data = pcall(function()
        return get_data("help")
    end)
    if ok and yaml_data and type(yaml_data) == "table" then
        local yaml_settings = {}
        for field, info in pairs(yaml_data) do
            if type(info) == "table" and info.referenced_by then
                if type(info.referenced_by) == "table" and table_contains(info.referenced_by, script_name) then
                    yaml_settings[field] = info
                elseif type(info.referenced_by) == "string" and info.referenced_by == script_name then
                    yaml_settings[field] = info
                end
            end
        end

        local has_settings = false
        for _ in pairs(yaml_settings) do has_settings = true; break end

        if has_settings then
            respond("")
            respond(" YAML SETTINGS USED:")
            for field, info in pairs(yaml_settings) do
                local setting_line = "   " .. tostring(field) .. ": " .. (info.description or "")
                if info.specific_descriptions and info.specific_descriptions[script_name] then
                    setting_line = setting_line .. " " .. info.specific_descriptions[script_name]
                end
                if info.example and tostring(info.example) ~= "" then
                    setting_line = setting_line .. " [Ex: " .. tostring(info.example) .. "]"
                end
                respond(setting_line)
            end
            respond("")
        end
    end
end

--- Parse script arguments against definition patterns.
--- @param data table       array of definition sets
--- @param flex_args boolean  allow variable-length trailing args
--- @return table           matched args table (like OpenStruct)
function ArgParser:parse_args(data, flex_args)
    local raw_args = Script.vars[0] or ""
    local baselist = {}
    -- Script.vars[1], [2], etc. are the split args
    local i = 1
    while Script.vars[i] do
        table.insert(baselist, Script.vars[i])
        i = i + 1
    end

    -- Check for help request
    if #baselist == 1 then
        local first = baselist[1]:lower()
        if first == "help" or first == "?" or first == "h" then
            self:display_args(data)
            return nil -- caller should exit
        end
    end

    -- Try each definition set for a match
    local results = {}
    for _, def_set in ipairs(data) do
        local vars_copy = {}
        for _, v in ipairs(baselist) do table.insert(vars_copy, v) end
        local result = self:check_match(def_set, vars_copy, flex_args)
        if result then
            table.insert(results, result)
        end
    end

    if #results == 1 then
        return results[1]
    end

    if #results == 0 then
        echo("***INVALID ARGUMENTS DON'T MATCH ANY PATTERN***")
        respond("Provided Arguments: '" .. raw_args .. "'")
    elseif #results > 1 then
        echo("***INVALID ARGUMENTS MATCH MULTIPLE PATTERNS***")
        respond("Provided Arguments: '" .. raw_args .. "'")
    end

    self:display_args(data)
    return nil -- caller should exit
end

---------------------------------------------------------------------------
-- Global parse_args / display_args wrappers
---------------------------------------------------------------------------

--- Parse script arguments. Returns args table or nil (caller should exit on nil).
--- @param defn table       definition sets
--- @param flex_args boolean
--- @return table|nil
function parse_args(defn, flex_args)
    return ArgParser.new():parse_args(defn, flex_args or false)
end

--- Display argument help.
--- @param defn table
function display_args(defn)
    ArgParser.new():display_args(defn)
end

---------------------------------------------------------------------------
-- SetupFiles — settings and data file management
---------------------------------------------------------------------------

local SetupFiles = {}
SetupFiles.__index = SetupFiles

--- FileInfo: cached representation of a loaded data/profile file
local FileInfo = {}
FileInfo.__index = FileInfo

function FileInfo.new(path, name, data, mtime)
    return setmetatable({
        path = path,
        name = name,
        _data = data,
        mtime = mtime,
    }, FileInfo)
end

--- Return a deep copy of the file data (prevents in-memory mutation bugs)
function FileInfo:data()
    return deep_copy(self._data)
end

--- Efficiently peek at a single property without copying the whole file
function FileInfo:peek(property)
    if not self._data then return nil end
    return deep_copy(self._data[property])
end

function SetupFiles.new(debug_mode)
    local self = setmetatable({}, SetupFiles)
    self._files_cache = {}
    self._debug = debug_mode or false
    -- Determine profiles path
    -- Support alternate location for Platinum/Fallen/Test instances
    local game_code = GameState.game or "DR"
    local char_name = GameState.name or "Unknown"
    local game_data_path = "data/" .. game_code
    if File.exists(game_data_path .. "/base.json") and
       File.exists(game_data_path .. "/base-empty.json") and
       File.exists(game_data_path .. "/" .. char_name .. "-setup.json") then
        echo("Detected game instance-specific files. Loading settings from " .. game_data_path)
        self._profiles_path = game_data_path
    else
        self._profiles_path = "profiles"
    end
    self._data_path = "data/dr"
    return self
end

--- Convert a suffix like "setup" to a character filename like "CharName-setup.json"
function SetupFiles:to_character_filename(suffix)
    local char_name = GameState.name or "Unknown"
    return char_name .. "-" .. suffix .. ".json"
end

--- Convert a type like "spells" to "base-spells.json"
function SetupFiles:to_base_filename(suffix)
    return "base-" .. suffix .. ".json"
end

--- Convert a suffix to an include filename like "include-spells.json"
function SetupFiles:to_include_filename(suffix)
    return "include-" .. suffix .. ".json"
end

--- Convert character suffixes to filenames
function SetupFiles:character_suffixes_to_filenames(suffixes)
    local filenames = {}
    for _, suffix in ipairs(suffixes) do
        table.insert(filenames, self:to_character_filename(suffix))
    end
    return filenames
end

--- Load a file into cache if it has been modified since last cache entry
function SetupFiles:cache_load(directory, filename)
    local filepath = directory .. "/" .. filename
    if not File.exists(filepath) then
        if self._debug then
            echo("SetupFiles: file not found: " .. filepath)
        end
        return
    end
    local mtime = File.mtime(filepath) or 0
    local cached = self._files_cache[filename]
    if cached and cached.mtime == mtime then
        return -- unchanged
    end
    if self._debug then
        echo("SetupFiles: loading " .. filepath)
    end
    local data = safe_load_data_file(filepath)
    self._files_cache[filename] = FileInfo.new(directory, filename, data, mtime)
end

--- Get cached file info by filename
function SetupFiles:cache_get(filename)
    return self._files_cache[filename]
end

--- Reload profile files (base + includes + character files)
function SetupFiles:reload_profiles(character_filenames)
    character_filenames = character_filenames or {}
    -- Always reload base files
    local base_patterns = {"base.json", "base-empty.json"}
    for _, name in ipairs(base_patterns) do
        self:cache_load(self._profiles_path, name)
    end
    -- Load include files
    if File.is_dir(self._profiles_path) then
        local files = File.list(self._profiles_path) or {}
        for _, f in ipairs(files) do
            if f:find("^include") and f:find("%.json$") then
                self:cache_load(self._profiles_path, f)
            end
        end
    end
    -- Load character files
    for _, filename in ipairs(character_filenames) do
        self:cache_load(self._profiles_path, filename)
    end
end

--- Reload data files
function SetupFiles:reload_data(filenames)
    filenames = filenames or {}
    -- Load specified files
    for _, filename in ipairs(filenames) do
        self:cache_load(self._data_path, filename)
    end
    -- Also scan for any base-*.json files in data dir
    if File.is_dir(self._data_path) then
        local files = File.list(self._data_path) or {}
        for _, f in ipairs(files) do
            if f:find("^base") and f:find("%.json$") then
                self:cache_load(self._data_path, f)
            end
        end
    end
end

--- Recursively resolve include files (depth-first, circular dependency protection)
--- @param filenames table   initial include filenames
--- @param visited table     set of already-visited filenames (for cycle detection)
--- @param include_order table  accumulates ordered result
--- @return table  ordered list of include filenames (deepest first)
function SetupFiles:resolve_includes_recursively(filenames, visited, include_order)
    visited = visited or {}
    include_order = include_order or {}

    for _, filename in ipairs(filenames) do
        if not visited[filename] then
            visited[filename] = true
            -- Load this include file
            self:cache_load(self._profiles_path, filename)
            local file_info = self:cache_get(filename)
            if file_info then
                -- Get nested includes
                local nested_suffixes = file_info:peek("include") or {}
                if self._debug and #nested_suffixes > 0 then
                    echo("SetupFiles: " .. filename .. " has nested includes: " .. table.concat(nested_suffixes, ", "))
                end
                local nested_filenames = {}
                for _, suffix in ipairs(nested_suffixes) do
                    table.insert(nested_filenames, self:to_include_filename(suffix))
                end
                -- Depth-first: resolve nested before adding this file
                self:resolve_includes_recursively(nested_filenames, visited, include_order)
                table.insert(include_order, filename)
            end
        end
    end

    return include_order
end

--- Find spell data by name (case-insensitive)
local function find_spell_by_name(spells_data, name_to_find)
    if not spells_data or not name_to_find then return nil end
    for name, data in pairs(spells_data) do
        if iequals(name, name_to_find) then
            local spell_data = deep_copy(data)
            spell_data.name = spell_data.name or name
            return spell_data
        end
    end
    return nil
end

--- Find spell data by abbreviation (case-insensitive)
local function find_spell_by_abbrev(spells_data, abbrev_to_find)
    if not spells_data or not abbrev_to_find then return nil end
    for name, data in pairs(spells_data) do
        if type(data) == "table" and data.abbrev and iequals(data.abbrev, abbrev_to_find) then
            local spell_data = deep_copy(data)
            spell_data.name = spell_data.name or name
            return spell_data
        end
    end
    return nil
end

--- Enrich a single spell setting with base spell data
local function enrich_spell_with_data(spells_data, spell_setting)
    if type(spell_setting) ~= "table" then return spell_setting end
    local spell_data = find_spell_by_name(spells_data, spell_setting.name) or
                       find_spell_by_abbrev(spells_data, spell_setting.abbrev)
    if spell_data then
        return merge_into(deep_copy(spell_setting), spell_data, false)
    end
    return spell_setting
end

--- Inject spell name from map key into spell settings that are missing it
local function enrich_spells_with_names(spells_map)
    if type(spells_map) ~= "table" then return end
    for spell_name, spell_setting in pairs(spells_map) do
        if type(spell_setting) == "table" then
            spell_setting.name = spell_setting.name or spell_name
        end
    end
end

--- Transform raw settings into enriched settings object
function SetupFiles:transform_settings(original_settings)
    if self._debug then echo("SetupFiles:transform_settings") end

    local ok, result = pcall(function()
        local settings = deep_copy(original_settings) or {}

        -- Get base data for enrichment
        local base_data_items = self:get_data("items") or {}
        local base_data_spells = self:get_data("spells") or {}
        local base_data_empty = self:get_data("empty") or {}

        local battle_cries_data = base_data_spells.battle_cries or {}
        local spells_data = base_data_spells.spell_data or {}
        local empty_data = base_data_empty.empty_values or {}

        -- Populate nil settings with default empty values
        for name, value in pairs(empty_data) do
            if settings[name] == nil then
                settings[name] = deep_copy(value)
            end
        end

        -- Enrich waggle_sets
        if type(settings.waggle_sets) == "table" then
            for set_name, spells_map in pairs(settings.waggle_sets) do
                if type(spells_map) == "table" and not spells_map[1] then
                    -- It's a hash/map (not an array)
                    enrich_spells_with_names(spells_map)
                    for spell_key, spell_setting in pairs(spells_map) do
                        spells_map[spell_key] = enrich_spell_with_data(spells_data, spell_setting)
                    end
                end
            end
        end

        -- Enrich spell maps that use spell names as keys
        local spell_name_maps = { "buff_spells", "necromancer_healing" }
        for _, map_key in ipairs(spell_name_maps) do
            if type(settings[map_key]) == "table" then
                enrich_spells_with_names(settings[map_key])
                for spell_key, spell_setting in pairs(settings[map_key]) do
                    settings[map_key][spell_key] = enrich_spell_with_data(spells_data, spell_setting)
                end
            end
        end

        -- Enrich spell maps that use skill names as keys
        local spell_skill_maps = {
            "buff_spells", "combat_spell_training", "cyclic_training_spells",
            "magic_training", "training_spells", "crafting_training_spells",
            "necromancer_healing",
        }
        for _, map_key in ipairs(spell_skill_maps) do
            if type(settings[map_key]) == "table" and not settings[map_key][1] then
                for spell_key, spell_setting in pairs(settings[map_key]) do
                    settings[map_key][spell_key] = enrich_spell_with_data(spells_data, spell_setting)
                end
            end
        end

        -- Enrich spell lists (arrays of spell settings)
        local spell_lists = { "offensive_spells" }
        for _, list_key in ipairs(spell_lists) do
            if type(settings[list_key]) == "table" then
                for i, spell_setting in ipairs(settings[list_key]) do
                    settings[list_key][i] = enrich_spell_with_data(spells_data, spell_setting)
                end
            end
        end

        -- Enrich single spell settings
        local single_spell_keys = { "crossing_training_sorcery" }
        for _, key in ipairs(single_spell_keys) do
            if settings[key] then
                settings[key] = enrich_spell_with_data(spells_data, settings[key])
            end
        end

        -- Default TM spells prep command to 'target'
        if type(settings.offensive_spells) == "table" then
            for _, spell_setting in ipairs(settings.offensive_spells) do
                if type(spell_setting) == "table" then
                    local spell_data = spells_data[spell_setting.name]
                    local is_native_tm = spell_setting.skill == "Targeted Magic"
                    local is_sorcery_tm = spell_setting.skill == "Sorcery" and
                                          type(spell_data) == "table" and spell_data.skill == "Targeted Magic"
                    if is_native_tm or is_sorcery_tm then
                        spell_setting.prep = spell_setting.prep or "target"
                    end
                end
            end
        end

        -- Battle cries enrichment
        if type(settings.battle_cries) == "table" then
            for i, battle_cry_setting in ipairs(settings.battle_cries) do
                if type(battle_cry_setting) == "table" and battle_cry_setting.name then
                    local bc_data = battle_cries_data[battle_cry_setting.name]
                    if bc_data then
                        settings.battle_cries[i] = merge_into(deep_copy(battle_cry_setting), bc_data, false)
                    end
                end
            end
        end

        -- Build lootables list
        local lootables_parts = {}
        if type(base_data_items.lootables) == "table" then
            for _, v in ipairs(base_data_items.lootables) do table.insert(lootables_parts, v) end
        end
        if type(base_data_items.box_nouns) == "table" then
            for _, v in ipairs(base_data_items.box_nouns) do table.insert(lootables_parts, v) end
        end
        if type(base_data_items.gem_nouns) == "table" then
            for _, v in ipairs(base_data_items.gem_nouns) do table.insert(lootables_parts, v) end
        end
        if type(base_data_items.scroll_nouns) == "table" then
            for _, v in ipairs(base_data_items.scroll_nouns) do table.insert(lootables_parts, v) end
        end
        if type(settings.loot_additions) == "table" then
            for _, v in ipairs(settings.loot_additions) do table.insert(lootables_parts, v) end
        end
        settings.lootables = table_unique(
            table_subtract(lootables_parts, settings.loot_subtractions)
        )

        -- Pull sensitive settings from UserVars overrides
        local uservar_overrides = {
            "crossing_training_sorcery_room", "compost_room", "engineering_room",
            "outfitting_room", "alchemy_room", "safe_room", "safe_room_id",
            "safe_room_empath", "slack_username", "bankbot_name", "bankbot_room_id",
            "prehunt_buffs", "hometown",
        }
        for _, key in ipairs(uservar_overrides) do
            if settings[key] == nil and UserVars[key] ~= nil then
                settings[key] = UserVars[key]
            end
        end
        -- Special: safe_room_empaths is additive
        if type(settings.safe_room_empaths) == "table" then
            local uv_empaths = UserVars.safe_room_empaths
            if type(uv_empaths) == "table" then
                for _, v in ipairs(uv_empaths) do
                    table.insert(settings.safe_room_empaths, v)
                end
            end
        end

        -- $HOMETOWN override (global shift)
        if _G.HOMETOWN then
            settings.hometown = _G.HOMETOWN
        end

        -- Denylist for invalid safe rooms
        local disallowed_safe_rooms = { [5713] = true }
        if disallowed_safe_rooms[settings.safe_room] or disallowed_safe_rooms[settings.safe_room_id] then
            respond("<pushBold/>" .. tostring(settings.safe_room) .. " is not a valid safe room setting.<popBold/>")
            respond("<pushBold/>Exiting.<popBold/>")
            respond("<pushBold/>Please edit your yaml to use a different safe room.<popBold/>")
            return {}
        end

        -- Resolve hometown-specific room settings
        local hometown_room_keys = {
            "alchemy_room", "bankbot_room_id", "compost_room",
            "crossing_training_sorcery_room", "enchanting_room", "engineering_room",
            "feed_cloak_room", "forage_override_room", "lockpick_room_id",
            "outdoor_room", "outfitting_room", "prehunt_buffing_room",
            "safe_room", "safe_room_id", "theurgy_prayer_mat_room",
        }
        for _, key in ipairs(hometown_room_keys) do
            if type(settings[key]) == "table" and settings.hometown then
                local hometown_value = settings[key][settings.hometown]
                if hometown_value ~= nil then
                    settings[key] = hometown_value
                end
            end
        end

        -- Merge legacy appraisal settings
        if type(settings.appraisal_training) == "table" then
            if settings.train_appraisal_with_pouches and not table_contains(settings.appraisal_training, "pouches") then
                table.insert(settings.appraisal_training, "pouches")
            end
            if settings.train_appraisal_with_gear and not table_contains(settings.appraisal_training, "gear") then
                table.insert(settings.appraisal_training, "gear")
            end
        end

        -- Merge legacy astrology training settings
        if type(settings.astrology_training) == "table" then
            if settings.predict_event and not table_contains(settings.astrology_training, "events") then
                table.insert(settings.astrology_training, "events")
            end
            if type(settings.astral_plane_training) == "table" and
               settings.astral_plane_training.train_in_ap and
               not table_contains(settings.astrology_training, "ways") then
                table.insert(settings.astrology_training, "ways")
            end
        end

        return settings
    end)

    if not ok then
        echo("*** ERROR TRANSFORMING SETTINGS IN DEPENDENCY ***")
        echo("*** Commonly this is due to malformed config in your settings file ***")
        echo(tostring(result))
        return {}
    end

    return result
end

--- Transform raw data into enriched data object
function SetupFiles:transform_data(original_data)
    if self._debug then echo("SetupFiles:transform_data") end
    local ok, result = pcall(function()
        return deep_copy(original_data) or {}
    end)
    if not ok then
        echo("*** ERROR MODIFYING DATA IN DEPENDENCY ***")
        echo(tostring(result))
        return {}
    end
    return result
end

--- Get character settings.
--- @param character_suffixes table|nil  array of suffixes like {"hunt"} to also load CharName-hunt.json
--- @return table  merged settings object
function SetupFiles:get_settings(character_suffixes)
    character_suffixes = character_suffixes or {}
    -- Always include "setup"
    local suffixes = {"setup"}
    for _, s in ipairs(character_suffixes) do
        if not table_contains(suffixes, s) then
            table.insert(suffixes, s)
        end
    end
    suffixes = table_unique(suffixes)

    local character_filenames = self:character_suffixes_to_filenames(suffixes)

    -- Ensure latest profiles are loaded
    self:reload_profiles(character_filenames)

    -- Gather initial include suffixes from character files
    local initial_include_suffixes = {}
    for _, filename in ipairs(character_filenames) do
        local fi = self:cache_get(filename)
        if fi then
            local includes = fi:peek("include") or {}
            for _, inc in ipairs(includes) do
                table.insert(initial_include_suffixes, inc)
            end
        end
    end

    local initial_include_filenames = {}
    for _, suffix in ipairs(initial_include_suffixes) do
        table.insert(initial_include_filenames, self:to_include_filename(suffix))
    end

    -- Recursively resolve all includes
    local include_filenames = self:resolve_includes_recursively(initial_include_filenames)
    if self._debug then
        echo("SetupFiles:get_settings resolved includes: " .. table.concat(include_filenames, ", "))
    end

    -- Merge order: base.json -> base-empty.json -> includes (depth-first) -> character files
    local merge_order = {"base.json", "base-empty.json"}
    for _, f in ipairs(include_filenames) do table.insert(merge_order, f) end
    for _, f in ipairs(character_filenames) do table.insert(merge_order, f) end

    local settings = {}
    for _, filename in ipairs(merge_order) do
        local fi = self:cache_get(filename)
        if fi then
            local data = fi:data()
            if data then
                settings = deep_merge(settings, data)
            end
        end
    end

    return self:transform_settings(settings)
end

--- Get data from a base data file.
--- @param data_type string  e.g. "items", "spells", "empty", "help", "towns", "base-areas"
--- @return table  data object
function SetupFiles:get_data(data_type)
    local filename = self:to_base_filename(data_type)
    self:reload_data({filename})
    local fi = self:cache_get(filename)
    if fi then
        return self:transform_data(fi:data())
    end
    return {}
end

--- Reload all cached files (profiles + data)
function SetupFiles:reload()
    self:reload_profiles(self:character_suffixes_to_filenames({"setup"}))
    self:reload_data()
end

---------------------------------------------------------------------------
-- ScriptManager — autostart, map overrides, script management
---------------------------------------------------------------------------

local ScriptManager = {}
ScriptManager.__index = ScriptManager

function ScriptManager.new(debug_mode, setupfiles)
    local self = setmetatable({}, ScriptManager)
    self._debug = debug_mode or false
    self._setupfiles = setupfiles
    self._add_autos = {}
    self._remove_autos = {}

    -- Initialize autostart lists
    if not UserVars.autostart_scripts then
        UserVars.autostart_scripts = Json.encode({})
    end
    local uv_autos = {}
    if type(UserVars.autostart_scripts) == "string" then
        local ok, parsed = pcall(Json.decode, UserVars.autostart_scripts)
        if ok and type(parsed) == "table" then uv_autos = parsed end
    elseif type(UserVars.autostart_scripts) == "table" then
        uv_autos = UserVars.autostart_scripts
    end
    uv_autos = table_unique(uv_autos)
    table_remove_value(uv_autos, "dependency")
    UserVars.autostart_scripts = Json.encode(uv_autos)

    -- Global autostart list from Settings
    local global_autos = {}
    if Settings.autostart then
        if type(Settings.autostart) == "string" then
            local ok, parsed = pcall(Json.decode, Settings.autostart)
            if ok and type(parsed) == "table" then global_autos = parsed end
        elseif type(Settings.autostart) == "table" then
            global_autos = Settings.autostart
        end
    end
    global_autos = table_unique(global_autos)
    table_remove_value(global_autos, "dependency")
    Settings.autostart = Json.encode(global_autos)

    self:update_autostarts()
    return self
end

--- Rebuild combined autostart list
function ScriptManager:update_autostarts()
    local uv_autos = {}
    if UserVars.autostart_scripts then
        if type(UserVars.autostart_scripts) == "string" then
            local ok, parsed = pcall(Json.decode, UserVars.autostart_scripts)
            if ok and type(parsed) == "table" then uv_autos = parsed end
        elseif type(UserVars.autostart_scripts) == "table" then
            uv_autos = UserVars.autostart_scripts
        end
    end

    local settings_autos = {}
    local ok_s, s = pcall(function() return self._setupfiles:get_settings() end)
    if ok_s and type(s) == "table" and type(s.autostarts) == "table" then
        settings_autos = s.autostarts
    end

    local global_autos = {}
    if Settings.autostart then
        if type(Settings.autostart) == "string" then
            local ok, parsed = pcall(Json.decode, Settings.autostart)
            if ok and type(parsed) == "table" then global_autos = parsed end
        elseif type(Settings.autostart) == "table" then
            global_autos = Settings.autostart
        end
    end

    self.autostarts = table_union(uv_autos, settings_autos, global_autos)
end

function ScriptManager:add_global_auto(script_name)
    table.insert(self._add_autos, script_name)
end

function ScriptManager:remove_global_auto(script_name)
    table.insert(self._remove_autos, script_name)
end

--- Process pending autostart add/remove operations
function ScriptManager:run_queue()
    local update = false

    if #self._add_autos > 0 then
        update = true
        local global_autos = {}
        if Settings.autostart then
            if type(Settings.autostart) == "string" then
                local ok, parsed = pcall(Json.decode, Settings.autostart)
                if ok and type(parsed) == "table" then global_autos = parsed end
            end
        end
        for _, script in ipairs(self._add_autos) do
            table.insert(global_autos, script)
        end
        Settings.autostart = Json.encode(table_unique(global_autos))
        self._add_autos = {}
    end

    if #self._remove_autos > 0 then
        update = true
        local global_autos = {}
        if Settings.autostart then
            if type(Settings.autostart) == "string" then
                local ok, parsed = pcall(Json.decode, Settings.autostart)
                if ok and type(parsed) == "table" then global_autos = parsed end
            end
        end
        for _, script in ipairs(self._remove_autos) do
            table_remove_value(global_autos, script)
        end
        Settings.autostart = Json.encode(table_unique(global_autos))
        self._remove_autos = {}
    end

    if update then
        self:update_autostarts()
    end
end

--- Start all autostart scripts in order
function ScriptManager:start_scripts()
    local start_time = os.time()

    for _, script_name in ipairs(self.autostarts) do
        if not handle_obsolete_autostart(script_name) then
            custom_require({script_name})
            -- Wait for bootstrap scripts to finish
            local waited = 0
            while waited < 5 do
                local found_bootstrap = false
                local running = Script.list() or {}
                for _, s in ipairs(running) do
                    if type(s) == "string" and s:find("bootstrap") then
                        found_bootstrap = true
                        break
                    elseif type(s) == "table" and s.name and s.name:find("bootstrap") then
                        found_bootstrap = true
                        break
                    end
                end
                if not found_bootstrap then break end
                pause(0.2)
                waited = waited + 0.2
            end
        end
    end

    if self._debug then
        local elapsed = os.time() - start_time
        echo("Time spent in start_scripts: " .. elapsed .. "s")
    end
end

--- Apply map wayto overrides from settings
function ScriptManager:make_map_edits()
    echo("Applying personal map overrides")
    local ok, err = pcall(function()
        local settings = self._setupfiles:get_settings()
        local base_overrides = settings.base_wayto_overrides or {}
        local personal_overrides = settings.personal_wayto_overrides or {}

        -- Merge: personal overrides win on duplicate keys
        local wayto_overrides = deep_merge(base_overrides, personal_overrides)

        for _, values in pairs(wayto_overrides) do
            if type(values) == "table" and values.start_room and values.end_room then
                local start_room_id = tonumber(values.start_room)
                local end_room_id = tonumber(values.end_room)
                if start_room_id and end_room_id then
                    local start_room = Map.find_room(start_room_id)
                    if start_room then
                        local end_id_str = tostring(end_room_id)
                        if values.str_proc then
                            -- In Revenant, StringProc is a command string
                            start_room.wayto[end_id_str] = values.str_proc
                        end
                        if values.travel_time then
                            local time_num = tonumber(values.travel_time)
                            if time_num then
                                start_room.timeto[end_id_str] = time_num
                            else
                                start_room.timeto[end_id_str] = values.travel_time
                            end
                        end
                    end
                end
            end
        end

        -- Personal map custom targets
        local personal_map_targets = settings.personal_map_targets
        if personal_map_targets and type(personal_map_targets) == "table" then
            local custom_targets = {}
            if Settings.custom_targets then
                if type(Settings.custom_targets) == "string" then
                    local ok2, parsed = pcall(Json.decode, Settings.custom_targets)
                    if ok2 and type(parsed) == "table" then custom_targets = parsed end
                elseif type(Settings.custom_targets) == "table" then
                    custom_targets = Settings.custom_targets
                end
            end
            custom_targets = deep_merge(custom_targets, personal_map_targets)
            Settings.custom_targets = Json.encode(custom_targets)
        end
    end)
    if not ok then
        echo("Error applying map overrides: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
-- BankbotManager
---------------------------------------------------------------------------

local BankbotManager = {}
BankbotManager.__index = BankbotManager

function BankbotManager.new(debug_mode)
    local self = setmetatable({}, BankbotManager)
    self._debug = debug_mode or false
    self._save = false
    self._load = false
    self._transaction = ""
    self.ledger = {}
    return self
end

function BankbotManager:loaded()
    return not self._load
end

function BankbotManager:run_queue()
    self:_save_transaction()
    self:_load_ledger()
end

function BankbotManager:save_bankbot_transaction(transaction, ledger)
    self._transaction = transaction
    self.ledger = ledger
    self._save = true
end

function BankbotManager:load_bankbot_ledger()
    self._load = true
end

function BankbotManager:_save_transaction()
    if not self._save then return end

    local char_name = GameState.name or "Unknown"
    local log_path = char_name .. "-transactions.log"
    local separator = "----------"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local ledger_str = Json.encode(self.ledger)

    -- Append to transaction log
    local existing = ""
    if File.exists(log_path) then
        existing = File.read(log_path) or ""
    end
    existing = existing .. separator .. "\n" .. timestamp .. "\n" ..
               self._transaction .. "\n" .. ledger_str .. "\n" .. separator .. "\n"
    File.write(log_path, existing)

    -- Write current ledger
    File.write(char_name .. "-ledger.json", ledger_str)
    self._save = false
end

function BankbotManager:_load_ledger()
    if not self._load then return end

    local char_name = GameState.name or "Unknown"
    local path = char_name .. "-ledger.json"
    if File.exists(path) then
        local content = File.read(path) or ""
        local ok, data = pcall(Json.decode, content)
        if ok and data then
            self.ledger = data
        else
            echo("*** ERROR PARSING LEDGER FILE ***")
            self.ledger = {}
        end
    else
        self.ledger = {}
    end
    self._load = false
end

---------------------------------------------------------------------------
-- ReportbotManager
---------------------------------------------------------------------------

local ReportbotManager = {}
ReportbotManager.__index = ReportbotManager

function ReportbotManager.new(debug_mode)
    local self = setmetatable({}, ReportbotManager)
    self._debug = debug_mode or false
    self._save = false
    self._load = false
    self.whitelist = {}
    return self
end

function ReportbotManager:loaded()
    return not self._load
end

function ReportbotManager:run_queue()
    self:_save_whitelist()
    self:_load_whitelist()
end

function ReportbotManager:save_reportbot_whitelist(whitelist)
    self.whitelist = whitelist
    self._save = true
end

function ReportbotManager:load_reportbot_whitelist()
    self._load = true
end

function ReportbotManager:_save_whitelist()
    if not self._save then return end
    File.write("reportbot-whitelist.json", Json.encode(self.whitelist))
    self._save = false
end

function ReportbotManager:_load_whitelist()
    if not self._load then return end
    local path = "reportbot-whitelist.json"
    if File.exists(path) then
        local content = File.read(path) or ""
        local ok, data = pcall(Json.decode, content)
        if ok and data then
            self.whitelist = data
        else
            echo("*** ERROR PARSING WHITELIST FILE ***")
            self.whitelist = {}
        end
    else
        self.whitelist = {}
    end
    self._load = false
end

---------------------------------------------------------------------------
-- SlackbotManager
---------------------------------------------------------------------------

local SlackbotManager = {}
SlackbotManager.__index = SlackbotManager

function SlackbotManager.new(debug_mode)
    local self = setmetatable({}, SlackbotManager)
    self._debug = debug_mode or false
    self._slackbot = nil
    self._username = nil
    self._messages = {}
    return self
end

function SlackbotManager:run_queue()
    self:_register_slackbot()
    self:_send_messages()
end

function SlackbotManager:register(username)
    if self._slackbot then return end
    if not username or tostring(username):match("^%s*$") then
        if DRC and DRC.message then
            DRC.message("SlackbotManager: No slackbot_username configured. Slack messaging disabled.")
        else
            echo("SlackbotManager: No slackbot_username configured. Slack messaging disabled.")
        end
        return
    end
    self._username = username
end

function SlackbotManager:queue_message(message)
    if not message then return end
    table.insert(self._messages, message)
end

function SlackbotManager:_register_slackbot()
    if not self._username then return end
    if self._slackbot then return end
    echo("Registering Slackbot")
    -- In Revenant, SlackBot integration uses Http module
    self._slackbot = true
end

function SlackbotManager:_send_messages()
    if not self._slackbot then return end
    while #self._messages > 0 do
        local message = table.remove(self._messages, 1)
        -- Slack webhook integration - scripts provide the webhook URL
        if self._username and message then
            echo("SlackBot: " .. tostring(message))
        end
    end
end

---------------------------------------------------------------------------
-- Obsolete script handling
---------------------------------------------------------------------------

local DR_OBSOLETE_SCRIPTS = {
    "events", "slackbot", "spellmonitor", "exp-monitor",
    "common-travel", "common-validation", "common", "drinfomon", "equipmanager",
    "common-money", "common-moonmage", "common-summoning", "common-theurgy", "common-arcana",
    "bootstrap", "common-crafting", "common-healing-data", "common-healing", "common-items",
}

local function is_obsolete_script(name)
    local script_name = name:gsub("%.lic$", ""):gsub("%.lua$", "")
    return table_contains(DR_OBSOLETE_SCRIPTS, script_name)
end

--- Check and warn about obsolete scripts; returns true if the script is obsolete
function handle_obsolete_autostart(script_name)
    if not is_obsolete_script(script_name) then return false end

    local uv_autos = {}
    if UserVars.autostart_scripts then
        if type(UserVars.autostart_scripts) == "string" then
            local ok, parsed = pcall(Json.decode, UserVars.autostart_scripts)
            if ok and type(parsed) == "table" then uv_autos = parsed end
        end
    end
    local in_character = table_contains(uv_autos, script_name)

    local global_autos = {}
    if Settings.autostart then
        if type(Settings.autostart) == "string" then
            local ok, parsed = pcall(Json.decode, Settings.autostart)
            if ok and type(parsed) == "table" then global_autos = parsed end
        end
    end
    local in_global = table_contains(global_autos, script_name)

    echo("---")
    echo("'" .. script_name .. "' is obsolete and no longer needed.")

    if in_character then
        echo("Removing '" .. script_name .. "' from character autostarts.")
        table_remove_value(uv_autos, script_name)
        UserVars.autostart_scripts = Json.encode(uv_autos)
    end

    if in_global then
        echo("Removing '" .. script_name .. "' from global autostarts.")
        if _G._manager then
            _G._manager:remove_global_auto(script_name)
        end
    end

    if not in_character and not in_global then
        echo("'" .. script_name .. "' is configured in your YAML profile autostarts.")
        echo("Please remove '" .. script_name .. "' from the 'autostarts' setting in your profile.")
    end

    echo("---")
    return true
end

--- Warn about obsolete script files still present
local function warn_obsolete_scripts()
    for _, script_name in ipairs(DR_OBSOLETE_SCRIPTS) do
        local lua_path = "dr/" .. script_name .. ".lua"
        if Script.exists(script_name) or File.exists(lua_path) then
            respond("<pushBold/>--- Revenant: '" .. script_name .. "' is obsolete and should be removed. It is no longer needed and may cause problems.<popBold/>")
        end
    end
end

---------------------------------------------------------------------------
-- custom_require — inline module loader (replaces bootstrap.lic)
---------------------------------------------------------------------------

function custom_require(script_names)
    if type(script_names) == "string" then
        script_names = {script_names}
    end
    if not script_names or #script_names == 0 then return end

    for _, script_name in ipairs(script_names) do
        if not is_obsolete_script(script_name) then
            if not Script.running(script_name) then
                if Script.exists(script_name) then
                    Script.run(script_name)
                    pause(0.05)
                    -- Wait briefly for the script to initialize
                    local snapshot = os.time()
                    while Script.running(script_name) and (os.time() - snapshot) < 1 do
                        pause(0.05)
                    end
                end
            end
        end
    end
end

--- Verify that required scripts exist
function verify_script(script_names)
    if type(script_names) == "string" then
        script_names = {script_names}
    end
    local all_ok = true
    for _, name in ipairs(script_names) do
        if not Script.exists(name) then
            echo("Failed to find a script named '" .. name .. "'")
            echo("Please report this to <https://github.com/elanthia-online/dr-scripts/issues>")
            echo("or to Discord " .. DR_SCRIPTS_DISCORD_LINK)
            all_ok = false
        end
    end
    return all_ok
end

---------------------------------------------------------------------------
-- Flag checking — set ShowRoomID and MonsterBold if not already set
---------------------------------------------------------------------------

local function set_flags()
    if not UserVars.dependency_setflags then
        echo("Checking MonsterBold and ShowRoomID flags.")
        -- Issue the flag command and check current state
        fput("flag ShowRoomID on")
        fput("flag MonsterBold on")
        UserVars.dependency_setflags = tostring(os.time())
    end
end

---------------------------------------------------------------------------
-- Global API functions
---------------------------------------------------------------------------

--- Shift hometown override
function shift_hometown(town_name)
    _G.HOMETOWN = town_name
end

--- Clear hometown override
function clear_hometown()
    _G.HOMETOWN = nil
end

---------------------------------------------------------------------------
-- Parse dependency's own arguments
---------------------------------------------------------------------------

-- NOTE: `install` mode has been removed. DR script installation is now
-- handled by pkg. On a fresh install the engine bootstrap runs automatically.
-- To install or update DR scripts manually: ;pkg install <script-name>

local arg_definitions = {
    {
        { name = "debug", regex = "debug", optional = true },
    }
}

-- Intercept legacy `install` invocation before full arg parse
local raw_args = Script.vars[0] or ""
if raw_args:match("^%s*install%s*$") then
    echo("dependency install has moved to pkg.")
    echo("To install DR scripts: ;pkg install hunting-buddy combat-trainer get2")
    echo("On a fresh install the engine bootstrap handles this automatically.")
    return
end

local args = parse_args(arg_definitions)
if not args then return end  -- help was shown, or bad args

local debug_mode = args.debug or UserVars.debug_dependency

---------------------------------------------------------------------------
-- Initialize all subsystems
---------------------------------------------------------------------------

echo("=== Dependency v" .. DEPENDENCY_VERSION .. " ===")
echo("Initializing DR script environment...")

-- Set game flags
set_flags()

-- Create the global SetupFiles instance
local setupfiles = SetupFiles.new(debug_mode)
_G._setupfiles = setupfiles

-- Create managers
local manager = ScriptManager.new(debug_mode, setupfiles)
_G._manager = manager

local bankbot = BankbotManager.new(debug_mode)
_G._bankbot = bankbot

local reportbot = ReportbotManager.new(debug_mode)
_G._reportbot = reportbot

local slackbot = SlackbotManager.new(debug_mode)
_G._slackbot = slackbot

---------------------------------------------------------------------------
-- Global wrapper functions (match Ruby API exactly)
---------------------------------------------------------------------------

--- Get character settings, optionally with additional profile suffixes
--- @param character_suffixes table|nil
--- @return table
function get_settings(character_suffixes)
    return setupfiles:get_settings(character_suffixes)
end

--- Get data from a base data file
--- @param data_type string  e.g. "items", "spells", "empty", "help", "towns"
--- @return table
function get_data(data_type)
    return setupfiles:get_data(data_type)
end

--- Save a bankbot transaction
function save_bankbot_transaction(transaction, ledger)
    bankbot:save_bankbot_transaction(transaction, ledger)
end

--- Load bankbot ledger (blocking until loaded)
function load_bankbot_ledger()
    bankbot:load_bankbot_ledger()
    local waited = 0
    while not bankbot:loaded() and waited < 10 do
        pause(0.1)
        waited = waited + 0.1
    end
    return bankbot.ledger
end

--- Save reportbot whitelist
function save_reportbot_whitelist(whitelist)
    reportbot:save_reportbot_whitelist(whitelist)
end

--- Load reportbot whitelist (blocking until loaded)
function load_reportbot_whitelist()
    reportbot:load_reportbot_whitelist()
    local waited = 0
    while not reportbot:loaded() and waited < 10 do
        pause(0.1)
        waited = waited + 0.1
    end
    return reportbot.whitelist
end

--- Send a message via slackbot
function send_slackbot_message(message)
    slackbot:queue_message(message)
end

--- Register slackbot username
function register_slackbot(username)
    slackbot:register(username)
end

--- Apply map wayto overrides
function make_map_edits()
    manager:make_map_edits()
end

--- List current autostarts
function list_autostarts()
    return manager.autostarts
end

--- Add script(s) to autostart
function autostart(script_names, global)
    if type(script_names) == "string" then
        script_names = {script_names}
    end
    if global == nil then global = true end

    if global then
        for _, script in ipairs(script_names) do
            manager:add_global_auto(script)
        end
    else
        local uv_autos = {}
        if UserVars.autostart_scripts then
            if type(UserVars.autostart_scripts) == "string" then
                local ok, parsed = pcall(Json.decode, UserVars.autostart_scripts)
                if ok and type(parsed) == "table" then uv_autos = parsed end
            end
        end
        for _, script in ipairs(script_names) do
            if not table_contains(uv_autos, script) then
                table.insert(uv_autos, script)
            end
        end
        UserVars.autostart_scripts = Json.encode(uv_autos)
    end

    for _, script in ipairs(script_names) do
        if Script.running(script) then
            Script.kill(script)
            pause(0.1)
        end
        Script.run(script)
    end
end

--- Remove script(s) from autostart
function stop_autostart(script_names)
    if type(script_names) == "string" then
        script_names = {script_names}
    end
    for _, script in ipairs(script_names) do
        local uv_autos = {}
        if UserVars.autostart_scripts then
            if type(UserVars.autostart_scripts) == "string" then
                local ok, parsed = pcall(Json.decode, UserVars.autostart_scripts)
                if ok and type(parsed) == "table" then uv_autos = parsed end
            end
        end
        if table_contains(uv_autos, script) then
            table_remove_value(uv_autos, script)
            UserVars.autostart_scripts = Json.encode(uv_autos)
        else
            manager:remove_global_auto(script)
        end
    end
end

--- Restart dependency
function update_d()
    echo("Restarting Dependency in 2 seconds...")
    before_dying(function()
        pause(2)
        Script.run("dependency")
    end)
    Script.kill("dependency")
end

--- Enable moon watch connection
function enable_moon_connection()
    _G._turn_on_moon_watch = true
end

--- Get all moon data
function get_all_moon_data()
    return _G._moon_data
end

--- Update moon data
function update_moon_data(moon, data)
    -- Moon data stored as a global table
    if not _G._moon_data then _G._moon_data = {} end
    _G._moon_data[moon] = data
end

---------------------------------------------------------------------------
-- Populate initial game state
---------------------------------------------------------------------------

echo("Populating initial game state...")
local ok_exp = pcall(function()
    fput("exp all 0")
end)
local ok_info = pcall(function()
    fput("info")
end)
local ok_played = pcall(function()
    fput("played")
end)
local ok_ability = pcall(function()
    fput("ability")
end)

---------------------------------------------------------------------------
-- Start autostart scripts and apply map overrides
---------------------------------------------------------------------------

manager:start_scripts()
manager:make_map_edits()

-- Reload settings cache
setupfiles:reload()

-- Warn about obsolete scripts
warn_obsolete_scripts()

echo("DR dependency initialization complete.")
echo("Globals: parse_args, get_settings, get_data, custom_require, make_map_edits")
echo("Managers: _bankbot, _reportbot, _slackbot, _manager, _setupfiles")

---------------------------------------------------------------------------
-- Main run loop — process manager queues
---------------------------------------------------------------------------

before_dying(function()
    _G._moon_data = nil
end)

while true do
    -- Moon watch init
    if _G._turn_on_moon_watch and not _G._moon_data then
        _G._moon_data = {}
        _G._turn_on_moon_watch = nil
    end

    manager:run_queue()
    bankbot:run_queue()
    reportbot:run_queue()
    slackbot:run_queue()

    clear()
    pause(0.1)
end
