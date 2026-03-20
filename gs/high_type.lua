--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: high_type
--- version: 2.5.0
--- author: Ensayn
--- description: Item type-specific highlighting with universal link coloring. Replaces linktothefast.
--- game: gs
--- tags: highlighting, colors, links, item_types
---
--- Syntax:
---   ;high_type                       Show config; start daemon if not running
---   ;high_type quiet                 Start daemon silently
---   ;high_type add <type> <color>    Add or update type→color mapping
---   ;high_type remove <type>         Remove a type mapping
---   ;high_type reset                 Reset to defaults
---   ;high_type colors                Show color examples with live formatting
---   ;high_type help                  Show comprehensive help
---   ;high_type showconfig            Show current configuration
---   ;high_type setcharcolor <color>  Set default color for all character names
---   ;high_type clearcharcolor        Clear character default color
---   ;high_type debug                 Show debug information
---   ;ht [command]                    Alias for ;high_type
---
--- ;autostart add --global high_type quiet
---
--- Changelog (Revenant port from high_type.lic v2.5.0 by Ensayn):
---   Revenant port (2026-03-20):
---     - UserVars stores JSON strings (ht_types_to_color, ht_color_all_links, ht_character_default_color)
---     - GameObj.classify(noun, name) replaces GameObj.type_data pattern matching
---     - Hook receives raw XML; always emits XML (engine handles GSL conversion)
---     - Frontend.supports_xml() replaces $fake_stormfront
---     - GameState.login_time replaces $login_time startup delay
---     - Shared global _HIGH_TYPE_CONFIG allows command instances to update running hook
---     - DownstreamHook.PRIORITY_LAST ensures hook runs after recolor and other hooks
---     - ;ht alias handled via ht.lua redirect script
---   v2.5.0 (2025-09-20) - Added character default color (setcharcolor/clearcharcolor)
---   v2.4.0 (2025-09-20) - Added showconfig, remove commands and HT alias
---   v2.3.0 (2025-09-19) - Added runtime command processing
---   v2.2.1 (2025-09-18) - Fixed startup delay logic
---   v2.2.0 (2025-09-18) - Removed legacy maintenance commands
---   v2.1.0 (2025-09-18) - Reduced defaults to 5 core types
---   v2.0.0 (2025-09-14) - Added universal link coloring (replaces linktothefast)
---   v1.0.0 (2023-01-01) - Gift from Xanlin

local VERSION     = "2.5.0"
local SCRIPT_NAME = "high_type"
local HOOK_NAME   = "high_type"

local VALID_COLORS = {"speech", "whisper", "thought", "link", "selectedlink", "bold", "monsterbold"}
local VALID_COLORS_SET = {}
for _, c in ipairs(VALID_COLORS) do VALID_COLORS_SET[c] = true end

------------------------------------------------------------------------------
-- Shared config table (module-level global, persists across instances in the
-- shared Lua state). Command-mode instances update this directly so the
-- running hook sees changes without needing a reload.
------------------------------------------------------------------------------
if not _HIGH_TYPE_CONFIG then
    _HIGH_TYPE_CONFIG = {
        types_to_color          = {},
        color_all_links         = true,
        character_default_color = nil,
    }
end

local function load_config()
    local types_json = UserVars.ht_types_to_color
    _HIGH_TYPE_CONFIG.types_to_color          = types_json and Json.decode(types_json) or {}
    local color_all                            = UserVars.ht_color_all_links
    _HIGH_TYPE_CONFIG.color_all_links         = (color_all == nil or color_all == "true")
    _HIGH_TYPE_CONFIG.character_default_color = UserVars.ht_character_default_color  -- nil when absent
end

local function save_config()
    UserVars.ht_types_to_color          = Json.encode(_HIGH_TYPE_CONFIG.types_to_color)
    UserVars.ht_color_all_links         = _HIGH_TYPE_CONFIG.color_all_links and "true" or "false"
    UserVars.ht_character_default_color = _HIGH_TYPE_CONFIG.character_default_color
end

local function setup_defaults()
    load_config()
    if not next(_HIGH_TYPE_CONFIG.types_to_color) then
        _HIGH_TYPE_CONFIG.types_to_color = {
            gem       = "thought",   -- Purple/magenta for gems
            jewelry   = "thought",   -- Same color family as gems
            valuable  = "thought",   -- Consistent with gems
            box       = "speech",    -- Speech color for lockboxes
            boatcrate = "whisper",   -- Subdued for boat crates
        }
        _HIGH_TYPE_CONFIG.color_all_links         = true
        _HIGH_TYPE_CONFIG.character_default_color = nil
        save_config()
    end
end

------------------------------------------------------------------------------
-- Display helpers
------------------------------------------------------------------------------
local function count_table(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function display_configuration()
    echo("=== High Type Configuration ===")
    local type_count = count_table(_HIGH_TYPE_CONFIG.types_to_color)
    echo("Item types configured for highlighting: " .. type_count)
    for t, c in pairs(_HIGH_TYPE_CONFIG.types_to_color) do
        echo(string.format("  %-12s -> %s", t, c))
    end
    echo("")
    echo("Universal link coloring: " .. (_HIGH_TYPE_CONFIG.color_all_links and "enabled" or "disabled"))
    echo("  - Colors ALL links with 'link' preset when enabled")
    echo("  - Item types override with specific colors")
    echo("  - Replaces linktothefast functionality")
    if _HIGH_TYPE_CONFIG.character_default_color then
        echo("Character default color: " .. _HIGH_TYPE_CONFIG.character_default_color)
        echo("  - All character names use this color instead of link default")
    else
        echo("Character default color: not set (using link default)")
    end
    echo("")
    echo("Available colors: " .. table.concat(VALID_COLORS, ", "))
    echo("")
    echo("Configuration stored in UserVars (shared with other scripts)")
    echo("=== End Configuration ===")
end

local function show_color_examples()
    echo("=== High Type Color Examples ===")
    echo("")
    echo("Available colors with examples:")
    echo("")
    local sample = "Sample Item Text"
    for _, color in ipairs(VALID_COLORS) do
        echo("  " .. color .. ":  (see below)")
        if color == "monsterbold" then
            _respond("  <pushBold/>" .. sample .. "<popBold/>\n")
        else
            _respond("  <preset id='" .. color .. "'>" .. sample .. "</preset>\n")
        end
    end
    echo("")
    echo("NOTE: If all colors look the same, your client presets may")
    echo("      be configured to use the same 'skin' color for all presets.")
    echo("=== End Color Examples ===")
end

local function show_help()
    echo("=== High Type v" .. VERSION .. " Help ===")
    echo("")
    echo("USAGE: ;high_type [command]   (or ;ht [command])")
    echo("")
    echo("DAEMON COMMANDS:")
    echo("  ;high_type             Show config; start daemon if not running")
    echo("  ;high_type quiet       Start daemon silently with item count")
    echo("")
    echo("RUNTIME COMMANDS (updates running daemon's config immediately):")
    echo("  ;high_type add <type> <color>    Add or update type→color mapping")
    echo("  ;high_type remove <type>          Remove a type from mapping")
    echo("  ;high_type reset                  Reset configuration to defaults")
    echo("  ;high_type showconfig             Show current configuration")
    echo("  ;high_type colors                 Show color examples")
    echo("  ;high_type setcharcolor <color>   Set default color for character names")
    echo("  ;high_type clearcharcolor         Clear character default color")
    echo("  ;high_type debug                  Show debug information")
    echo("  ;high_type help                   Show this help")
    echo("")
    echo("FEATURES:")
    echo("  - Universal link coloring (replaces linktothefast)")
    echo("  - Item type-specific highlighting using GameObj classification")
    echo("  - Shared configuration with other scripts via UserVars")
    echo("  - " .. #VALID_COLORS .. " available colors: " .. table.concat(VALID_COLORS, ", "))
    echo("")
    echo("EXAMPLES:")
    echo("  ;high_type add gem thought       # Gems use purple color")
    echo("  ;high_type add weapon speech     # Weapons use speech color")
    echo("  ;high_type remove boatcrate      # Stop highlighting boat crates")
    echo("  ;high_type setcharcolor whisper  # Character names in whisper color")
    echo("=== End Help ===")
end

------------------------------------------------------------------------------
-- Color application: wraps text in the appropriate XML preset tag.
-- Always emits XML — the engine's GslConverter handles GSL clients.
-- The `ref` argument may be a literal string like "$1" for use as a Regex
-- replacement backreference.
------------------------------------------------------------------------------
local function apply_color_preset(ref, color)
    if color == "monsterbold" then
        return "<pushBold/>" .. ref .. "<popBold/>"
    else
        return "<preset id='" .. color .. "'>" .. ref .. "</preset>"
    end
end

------------------------------------------------------------------------------
-- Downstream hook: process a raw XML chunk from the game server.
-- Receives the full multi-element XML string; returns modified string.
-- Three phases match the original Lich5 apply_type_colors proc exactly.
------------------------------------------------------------------------------
local function process_chunk(s)
    if not s then return s end
    local cfg = _HIGH_TYPE_CONFIG

    -- Phase 1: Universal link enhancement
    -- Wrap all <a> and <d> link tags with <preset id='link'>.
    -- Mirrors linktothefast behavior but runs PRIORITY_LAST, after linktothefast if both run.
    if cfg.color_all_links and (s:find("<a[ >]") or s:find("<d[ >]")) then
        s = s:gsub("(<a[^>]*>.-</a>)", "<preset id='link'>%1</preset>")
        s = s:gsub("(<d[^>]*>.-</d>)", "<preset id='link'>%1</preset>")
        -- Strip link presets inside <pushBold/>...<popBold/> blocks
        s = s:gsub("(<pushBold%s*/>.-<popBold%s*/>)", function(bold)
            return bold:gsub("<preset id='link'>(.-)</preset>", "%1")
        end)
        -- Strip link presets inside <b>...</b> bold text
        s = s:gsub("(<b%s*>.-</b%s*>)", function(bold)
            return bold:gsub("<preset id='link'>(.-)</preset>", "%1")
        end)
    end

    -- Phase 2: Character default color
    -- Apply a specific preset to all character-link tags (negative exist IDs = PCs/NPCs with names).
    if cfg.character_default_color and s:find('exist="%-') then
        local char_color = cfg.character_default_color
        s = s:gsub('<([ad]) exist="(%-[^"]+)"([^>]*)>([^<]+)</[ad]>', function(tag, exist_id, attrs, name)
            return string.format(
                "<preset id='%s'><%s exist=\"%s\"%s>%s</%s></preset>",
                char_color, tag, exist_id, attrs, name, tag
            )
        end)
    end

    -- Phase 3: Type-specific colorization
    -- Override the generic 'link' color with type-specific presets for classified items.
    if next(cfg.types_to_color) and s:find('<a exist="') then
        -- Identify items and their desired colors
        local color_queue = {}
        for exist_id, noun, item_name in s:gmatch('<a exist="([^"]+)" noun="([^"]+)">([^<]+)</a>') do
            local item_type = GameObj.classify(noun, item_name)
            if item_type then
                for type_key, color in pairs(cfg.types_to_color) do
                    -- item_type may be comma-separated (e.g. "gem,valuable"); plain find works
                    if item_type:find(type_key, 1, true) then
                        table.insert(color_queue, {id = exist_id, color = color})
                        break
                    end
                end
            end
        end
        -- Recolor each queued item: strip any 'link' wrapper, apply type-specific preset
        for _, entry in ipairs(color_queue) do
            -- Match: optional <preset id='link'> wrapper + item link tag + optional </preset>
            -- $1 captures the raw <a exist="...">NAME</a> tag for the replacement
            local pattern = "(?:<preset id='link'>)?(<a exist=\"" .. entry.id .. "\"[^>]*>[^<]*</a>)(?:</preset>)?"
            local re = Regex.new(pattern)
            s = re:replace_all(s, apply_color_preset("$1", entry.color))
        end
    end

    return s
end

------------------------------------------------------------------------------
-- Command handlers (called by command-mode instances; no daemon involvement)
------------------------------------------------------------------------------
local function handle_command(cmd, args)
    if cmd == "add" then
        local type_name  = args[2]
        local color_name = args[3]
        if type_name and color_name then
            type_name  = type_name:gsub('["\']', '')
            color_name = color_name:gsub('["\']', '')
            if not VALID_COLORS_SET[color_name] then
                echo("Invalid color: " .. color_name)
                echo("Valid colors: " .. table.concat(VALID_COLORS, ", "))
                return
            end
            _HIGH_TYPE_CONFIG.types_to_color[type_name] = color_name
            save_config()
            echo("Added: " .. type_name .. " => " .. color_name)
            echo("Configuration updated (hook reflects changes immediately)")
        else
            echo("Usage: ;high_type add <type> <color>")
            echo("Example: ;high_type add gem thought")
        end

    elseif cmd == "remove" then
        local type_name = args[2]
        if type_name then
            type_name = type_name:gsub('["\']', '')
            if _HIGH_TYPE_CONFIG.types_to_color[type_name] then
                _HIGH_TYPE_CONFIG.types_to_color[type_name] = nil
                save_config()
                echo("Removed: " .. type_name)
                echo("Configuration updated (hook reflects changes immediately)")
            else
                echo("Type '" .. type_name .. "' not found in configuration")
            end
        else
            echo("Usage: ;high_type remove <type>")
            echo("Example: ;high_type remove boatcrate")
        end

    elseif cmd == "reset" then
        echo("Resetting configuration to defaults...")
        _HIGH_TYPE_CONFIG.types_to_color          = {}
        _HIGH_TYPE_CONFIG.color_all_links         = true
        _HIGH_TYPE_CONFIG.character_default_color = nil
        setup_defaults()
        echo("Configuration reset complete! (hook reflects changes immediately)")
        display_configuration()

    elseif cmd == "colors" or cmd == "examples" then
        show_color_examples()

    elseif cmd == "help" then
        show_help()

    elseif cmd == "showconfig" or cmd == "config" or cmd == "show" then
        display_configuration()

    elseif cmd == "setcharcolor" then
        local color_name = args[2]
        if color_name then
            color_name = color_name:gsub('["\']', '')
            if VALID_COLORS_SET[color_name] then
                _HIGH_TYPE_CONFIG.character_default_color = color_name
                save_config()
                echo("Character default color set to: " .. color_name)
                echo("All character names will now use " .. color_name .. " color")
            else
                echo("Invalid color: " .. color_name)
                echo("Valid colors: " .. table.concat(VALID_COLORS, ", "))
            end
        else
            echo("Usage: ;high_type setcharcolor <color>")
            echo("Example: ;high_type setcharcolor whisper")
        end

    elseif cmd == "clearcharcolor" then
        _HIGH_TYPE_CONFIG.character_default_color = nil
        save_config()
        echo("Character default color cleared — characters use link default")

    elseif cmd == "debug" then
        echo("=== High Type Debug Info ===")
        echo("Version: " .. VERSION)
        local hook_registered = false
        for _, name in ipairs(DownstreamHook.list()) do
            if name == HOOK_NAME then hook_registered = true; break end
        end
        echo("Hook registered: " .. (hook_registered and "yes" or "no"))
        echo("Configured types: " .. count_table(_HIGH_TYPE_CONFIG.types_to_color))
        for t, c in pairs(_HIGH_TYPE_CONFIG.types_to_color) do
            echo("  " .. t .. " -> " .. c)
        end
        echo("color_all_links: " .. tostring(_HIGH_TYPE_CONFIG.color_all_links))
        echo("character_default_color: " .. tostring(_HIGH_TYPE_CONFIG.character_default_color))
        echo("=== End Debug ===")

    else
        echo("Unknown command: " .. cmd)
        echo("Commands: add, remove, reset, colors, help, showconfig, setcharcolor, clearcharcolor, debug")
        echo("Use ;high_type help for full documentation")
    end
end

------------------------------------------------------------------------------
-- Main entry point
------------------------------------------------------------------------------

-- Load / initialize configuration from UserVars
setup_defaults()

-- Parse startup arguments (Lich5-style: vars[0] = full string, vars[1..] = tokens)
local args_str = Script.vars[0] or ""
local args = {}
for word in args_str:gmatch("%S+") do
    table.insert(args, word)
end
local cmd = args[1] and args[1]:lower() or nil

-- Command mode: handle command then exit — hook is never registered here,
-- so before_dying cleanup is not needed and cannot accidentally remove the hook.
if cmd and cmd ~= "quiet" then
    handle_command(cmd, args)
    return
end

-- Daemon mode: check if hook is already registered (daemon already running)
local is_already_running = false
for _, name in ipairs(DownstreamHook.list()) do
    if name == HOOK_NAME then
        is_already_running = true
        break
    end
end

if is_already_running then
    if cmd == "quiet" then
        echo("High Type " .. VERSION .. " already active — "
            .. count_table(_HIGH_TYPE_CONFIG.types_to_color) .. " item types configured")
    else
        respond("[" .. SCRIPT_NAME .. " is already running. Use ;" .. SCRIPT_NAME .. " help for commands.]")
    end
    return
end

-- First run in daemon mode
if cmd == "quiet" then
    echo("High Type " .. VERSION .. " loaded silently — "
        .. count_table(_HIGH_TYPE_CONFIG.types_to_color) .. " item types configured")
else
    display_configuration()
end

-- Startup delay: wait if session is fresh (< 10 seconds since login)
local login_secs = GameState.login_time
if login_secs < 10 then
    local delay = math.ceil(10 - login_secs)
    echo(string.format(
        "High Type v%s starting — waiting %d seconds for session stabilization...",
        VERSION, delay
    ))
    pause(delay)
else
    echo(string.format(
        "High Type v%s starting — session already stable, no delay needed.",
        VERSION
    ))
end

-- Cleanup: remove hook when killed
before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

-- Register downstream hook at PRIORITY_LAST to run after recolor and other hooks
DownstreamHook.add(HOOK_NAME, process_chunk, DownstreamHook.PRIORITY_LAST)

echo(string.format(
    "High Type v%s active — link coloring and type highlighting enabled.",
    VERSION
))
echo(string.format(
    "Runtime commands: ;%s help, ;%s add <type> <color>, ;%s reset, etc.",
    SCRIPT_NAME, SCRIPT_NAME, SCRIPT_NAME
))

hide_me()

-- Keep alive
while true do
    pause(60)
end
