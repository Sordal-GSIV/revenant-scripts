--- @revenant-script
--- @lic-audit: validated 2026-03-17
--- name: fletchit
--- version: 2.2.0
--- author: elanthia-online
--- game: gs
--- tags: crafting,fletching
--------------------------------------------------------------------------------
-- FletchIt - Automated Fletching Script
--
-- Creates arrows, light bolts, and heavy bolts with full support for painting,
-- cresting, and auto-buying supplies. Learning mode drops shafts after nocking.
--
-- Setup:
--   ;fletchit setup   - Configure settings via GUI
--   ;fletchit help    - Show help
--   ;fletchit         - Start fletching
--   ;fletchit stop    - Stop after current arrow
--   ;fletchit bundle  - Bundle arrows/bolts in container
--
-- Original author: elanthia-online (Dissonance)
-- Lua conversion preserves all original functionality.
--
-- changelog:
--   2.2.0 (2026-03-05):
--     Significantly expanded capabilities of handling "trash" shafts when in learning mode.
--     Learning mode no longer requires glue, fletchings, paint, or paintsticks.
--     Learning mode will skip attempting to apply paint/paintsticks even when configured.
--   2.1.0 (2026-02-02):
--     Added debug mode setting to enable/disable debug logging
--     Fixed bug with cutting shafts
--     Fixed bug with setting arrow_type via GUI
--     Expanded stats tracking and display
--   2.0 (2025-01-02):
--     Complete refactor with modular architecture
--     Removed 1000+ lines of duplicate dead code
--     Standardized error handling with status symbols
--     Fixed arrow/bolt tracking logic
--     Improved messaging consistency
--     Added dynamic ammo type messages
--     Fixed mind percentage to use settings
--   1.0
--     Initial release as changes made to ;fletching script
--------------------------------------------------------------------------------

local VERSION = "2.2.0"

local Crafting    = require("gs/fletchit/crafting")
local Shopping    = require("gs/fletchit/shopping")
local Bundling    = require("gs/fletchit/bundling")
local GuiSettings = require("gs/fletchit/gui_settings")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

--- Correct PAINTS table — 25 entries from the Ruby original.
-- Maps numeric indices to paint color names as they appear in the fletcher shop.
-- Index 0 means no paint will be applied.
local PAINTS = {
    [0]  = "none",
    [1]  = "bright golden paint",
    [2]  = "fiery orange paint",
    [3]  = "bright yellow paint",
    [4]  = "dark russet paint",
    [5]  = "dark brown paint",
    [6]  = "silvery grey paint",
    [7]  = "twilight grey paint",
    [8]  = "storm grey paint",
    [9]  = "charcoal grey paint",
    [10] = "icy blue paint",
    [11] = "midnight blue paint",
    [12] = "dusky blue paint",
    [13] = "silvery white paint",
    [14] = "bone white paint",
    [15] = "pure white paint",
    [16] = "glossy black paint",
    [17] = "dull black paint",
    [18] = "inky black paint",
    [19] = "forest green paint",
    [20] = "hunter green paint",
    [21] = "dark green paint",
    [22] = "blood red paint",
    [23] = "glossy red paint",
    [24] = "dull red paint",
}

local AMMO_TYPES = {
    [1] = "arrow",
    [2] = "light bolt",
    [3] = "heavy bolt",
}

--- Default settings matching the Ruby original.
-- quiver→"backpack", axe→"handaxe", knife→"dagger", mind→"60", limit→""
local DEFAULT_SETTINGS = {
    sack         = "backpack",
    quiver       = "backpack",
    axe          = "handaxe",
    knife        = "dagger",
    bow          = "bow",
    enable_buying = false,
    paint        = 0,
    paintstick1  = "",
    paintstick2  = "",
    wood         = "limb of wood",
    fletchings   = "bundle of fletchings",
    limit        = "",
    waggle       = false,
    learning     = false,
    alerts       = false,
    tip          = "",
    drill        = "",
    ammo         = 1,
    mind         = "60",
    monitor_interaction = false,
    debug        = false,
}

--------------------------------------------------------------------------------
-- Stats tracking
--------------------------------------------------------------------------------

local stats = {}

local function add_stat(key, value)
    stats[key] = (stats[key] or 0) + value
end

local function get_stat(key)
    return stats[key] or 0
end

local function set_stat(key, value)
    stats[key] = value
end

local function update_session_stats(start_time)
    local session_time = os.time() - start_time
    set_stat("session_time_seconds", session_time)

    local bolts_made = get_stat("light_bolts_completed") + get_stat("heavy_bolts_completed")
    local arrows_made = get_stat("arrows_completed") + bolts_made
    local spent_silver = get_stat("silver_spent_supplies")

    if arrows_made > 0 and session_time > 0 then
        local ammo_per_hour = math.floor((arrows_made / (session_time / 3600.0)) * 100 + 0.5) / 100
        set_stat("ammo_per_hour", ammo_per_hour)
        if spent_silver > 0 then
            local silver_per_ammo = math.floor((spent_silver / arrows_made) * 100 + 0.5) / 100
            set_stat("silver_spent_per_ammo", silver_per_ammo)
        end
    end
end

--- Show stats in brief or full format.
-- @param brief boolean
-- @param start_time number os.time() at session start
-- @param ammo_name string plural ammo name for display
local function show_stats(brief, start_time, ammo_name)
    respond("")

    -- Calculate session time
    if brief and start_time then
        local session_time = os.time() - start_time
        set_stat("session_time_seconds", session_time)
    end

    local session_seconds = get_stat("session_time_seconds")
    local bolts_made   = get_stat("light_bolts_completed") + get_stat("heavy_bolts_completed")
    local bolts_failed = get_stat("light_bolts_failed") + get_stat("heavy_bolts_failed")
    local arrows_made   = get_stat("arrows_completed") + bolts_made
    local arrows_failed = get_stat("arrows_failed") + bolts_failed
    local spent_silver  = get_stat("silver_spent_supplies")

    local hours   = math.floor(session_seconds / 3600)
    local minutes = math.floor((session_seconds % 3600) / 60)
    local seconds = session_seconds % 60

    if brief then
        -- Brief progress format
        local time_str = ""
        if hours > 0 then time_str = time_str .. hours .. " hours, " end
        if minutes > 0 or hours > 0 then time_str = time_str .. minutes .. " minutes " end
        time_str = time_str .. seconds .. " seconds"

        respond("Running for " .. time_str)
        respond("Made " .. arrows_made .. " " .. (ammo_name or "arrows") .. ", ruined " .. arrows_failed .. " " .. (ammo_name or "arrows") .. ", spent " .. spent_silver .. " silver")

        if arrows_made > 0 and session_seconds > 60 then
            local rate = math.floor((arrows_made / (session_seconds / 3600.0)) * 10 + 0.5) / 10
            local cost_per_ammo = spent_silver > 0 and (math.floor((spent_silver / arrows_made) * 100 + 0.5) / 100) or 0
            respond("Rate: " .. rate .. "/hr, Cost: " .. cost_per_ammo .. "s each")
        end
    else
        -- Full stats format
        respond("=== FletchIt Session Statistics ===")

        if session_seconds > 0 then
            local time_str = ""
            if hours > 0 then time_str = time_str .. hours .. "h " end
            if minutes > 0 or hours > 0 then time_str = time_str .. minutes .. "m " end
            time_str = time_str .. seconds .. "s"
            respond("Session Duration: " .. time_str)

            local aph = get_stat("ammo_per_hour")
            if aph and aph > 0 then
                respond("Production Rate: " .. aph .. " per hour")
            end

            local spa = get_stat("silver_spent_per_ammo")
            if spa and spa > 0 then
                respond("Cost Per Item: " .. spa .. " silver")
            end

            respond("")
        end

        -- Show all detailed stats
        local skip_keys = { session_time_seconds = true, ammo_per_hour = true, silver_spent_per_ammo = true }
        local sorted_keys = {}
        for k, _ in pairs(stats) do
            if not skip_keys[k] then table.insert(sorted_keys, k) end
        end
        table.sort(sorted_keys)

        for _, k in ipairs(sorted_keys) do
            local v = stats[k]
            if v and v > 0 then
                -- Format key: replace underscores with spaces, capitalize words
                local formatted = string.gsub(k, "_", " ")
                formatted = string.gsub(formatted, "(%a)([%w_]*)", function(first, rest)
                    return string.upper(first) .. rest
                end)
                respond(formatted .. ": " .. tostring(v))
            end
        end
        respond("=====================================")
    end

    respond("Note: Some stats may be approximate if starting mid-arrow/bolt.")
    respond("")
end

--------------------------------------------------------------------------------
-- Debug logging
--------------------------------------------------------------------------------

local debug_enabled = false

local function debug_log(msg)
    if debug_enabled then
        echo("[DEBUG] " .. msg)
    end
end

--------------------------------------------------------------------------------
-- Settings management
--------------------------------------------------------------------------------

local function load_settings()
    local raw = CharSettings.fletchit_settings
    if raw then
        local ok, saved = pcall(Json.decode, raw)
        if ok and type(saved) == "table" then
            -- Merge with defaults
            for k, v in pairs(DEFAULT_SETTINGS) do
                if saved[k] == nil then saved[k] = v end
            end
            -- Migration: convert old 0-based ammo type to 1-based
            if saved.ammo == 0 then
                saved.ammo = 1
                debug_log("Migrated old ammo type 0 to 1 (arrow)")
            end
            return saved
        end
    end
    -- Copy defaults
    local s = {}
    for k, v in pairs(DEFAULT_SETTINGS) do s[k] = v end
    return s
end

local function save_settings(s)
    debug_log("save_settings called with " .. tostring(#(s or {})) .. " keys")
    CharSettings.fletchit_settings = Json.encode(s)
end

--------------------------------------------------------------------------------
-- Settings validation and normalization (matching Ruby Validator module)
--------------------------------------------------------------------------------

--- Validate that all required settings are configured.
-- @param settings table
-- @return table array of warning strings
local function validate_settings(settings)
    debug_log("validate_settings called")
    local warnings = {}

    if not settings.sack or settings.sack == "" then
        table.insert(warnings, "The container for your supplies has not been set")
    end
    if not settings.quiver or settings.quiver == "" then
        table.insert(warnings, "The container for finished arrows has not been set")
    end
    if not settings.knife or settings.knife == "" then
        table.insert(warnings, "Knife/dagger has not been set")
    end
    if not settings.bow or settings.bow == "" then
        table.insert(warnings, "Bow/crossbow has not been set")
    end
    if not settings.axe or settings.axe == "" then
        table.insert(warnings, "Axe has not been set")
    end
    if not settings.wood or settings.wood == "" then
        table.insert(warnings, "Wood type has not been set")
    end
    -- Validate wood contains expected keywords
    if settings.wood and settings.wood ~= "" then
        if not string.find(settings.wood, "wood") and not string.find(settings.wood, "log")
           and not string.find(settings.wood, "branch") and not string.find(settings.wood, "limb") then
            table.insert(warnings, "Wood setting may be incorrect (should be 'limb of wood' or similar)")
        end
    end
    -- Validate fletchings contains "fletching"
    if settings.fletchings and settings.fletchings ~= "" then
        if not string.find(settings.fletchings, "fletching") then
            table.insert(warnings, "Fletchings setting may be incorrect (should be 'bundle of fletchings' or similar)")
        end
    end

    return warnings
end

--- Normalize settings: strip articles from wood/fletchings, append "paintstick" to paintstick colors.
-- @param settings table
-- @return table normalized settings
local function normalize_settings(settings)
    debug_log("normalize_settings called")

    -- Remove leading articles from wood
    if settings.wood then
        settings.wood = string.gsub(settings.wood, "^%s*a%s+", "")
        settings.wood = string.gsub(settings.wood, "^%s*an%s+", "")
        settings.wood = string.gsub(settings.wood, "^%s*some%s+", "")
    end

    -- Remove leading articles from fletchings
    if settings.fletchings then
        settings.fletchings = string.gsub(settings.fletchings, "^%s*a%s+", "")
        settings.fletchings = string.gsub(settings.fletchings, "^%s*an%s+", "")
        settings.fletchings = string.gsub(settings.fletchings, "^%s*some%s+", "")
    end

    -- Auto-add paintstick if missing
    if settings.paintstick1 and #settings.paintstick1 > 0 and not string.find(settings.paintstick1, "paintstick") then
        settings.paintstick1 = settings.paintstick1:match("^%s*(.-)%s*$") .. " paintstick"
    end
    if settings.paintstick2 and #settings.paintstick2 > 0 and not string.find(settings.paintstick2, "paintstick") then
        settings.paintstick2 = settings.paintstick2:match("^%s*(.-)%s*$") .. " paintstick"
    end

    return settings
end

--------------------------------------------------------------------------------
-- Formatted settings display (matching Ruby show_current_settings)
--------------------------------------------------------------------------------

local function show_current_settings(settings)
    respond("")
    respond("FletchIt v" .. VERSION .. " - Current Settings")
    respond("")
    respond("Containers:")
    respond("  Supply Container: " .. (settings.sack or ""))
    respond("  Quiver: " .. (settings.quiver or ""))
    respond("")
    respond("Tools:")
    respond("  Axe: " .. (settings.axe or ""))
    respond("  Knife: " .. (settings.knife or ""))
    respond("  Bow: " .. (settings.bow or ""))
    respond("")
    respond("Ammunition:")
    local ammo_name = AMMO_TYPES[settings.ammo] or "Unknown"
    respond("  Type: " .. ammo_name)
    respond("")
    respond("Supplies:")
    respond("  Wood: " .. (settings.wood or ""))
    local paint_name = settings.paint == 0 and "None" or (PAINTS[settings.paint] or "Unknown")
    respond("  Paint: " .. paint_name)
    respond("  Paintstick 1: " .. (settings.paintstick1 == "" and "None" or settings.paintstick1))
    respond("  Paintstick 2: " .. (settings.paintstick2 == "" and "None" or settings.paintstick2))
    respond("  Fletchings: " .. (settings.fletchings or ""))
    respond("")
    respond("Options:")
    respond("  Auto-buy supplies: " .. (settings.enable_buying and "Yes" or "No"))
    respond("  Learning mode: " .. (settings.learning and "Yes" or "No"))
    if settings.learning then
        respond("  Mind threshold: " .. tostring(settings.mind) .. "%")
    end
    respond("  Waggle (haste): " .. (settings.waggle and "Yes" or "No"))
    respond("  Alerts: " .. (settings.alerts and "Yes" or "No"))
    respond("  Debug mode: " .. (settings.debug and "Yes" or "No"))
    local limit_text = (tonumber(settings.limit) or 0) > 0 and tostring(settings.limit) or "No limit"
    respond("  Limit: " .. limit_text)
    respond("")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("FletchIt v" .. VERSION .. " - Automated Fletching Script")
    respond("")
    respond("Commands:")
    respond("  ;fletchit          - Start fletching")
    respond("  ;fletchit setup    - Configure settings via GUI")
    respond("  ;fletchit settings - Display current settings")
    respond("  ;fletchit bundle   - Bundle existing arrows")
    respond("  ;fletchit help     - Show this help")
    respond("  ;fletchit stop     - Stop after current arrow")
    respond("")
    respond("While running:")
    respond("  ;fletchit          - See progress report")
    respond("  ;fletchit stats    - Detailed statistics")
    respond("")
    respond("This script needs a mapped room if you want it to buy items.")
    respond("Run ';fletchit setup' to configure settings.")
    respond("")
end

--------------------------------------------------------------------------------
-- Monitor interaction (alerts)
--------------------------------------------------------------------------------

--- Set up a downstream hook to watch for GM checks, whispers, player interactions.
-- @param settings table
local function monitor_interaction(settings)
    debug_log("monitor_interaction called")
    if not settings.alerts then return end

    local hook_name = "fletchit_monitor_" .. tostring(os.time())

    DownstreamHook.add(hook_name, function(line)
        -- Check for GM/policy/interaction patterns
        -- Matches the exact Ruby regex from the original
        if string.find(line, "SEND")
            or string.find(line, "POLICY")
            or string.find(line, "peaking to you")
            or string.find(line, "unresponsive")
            or string.find(line, "taps you")
            or string.find(line, "nods to you")
            or string.find(line, "lease respond")
            or string.find(line, "not in control")
            or string.find(line, "character")
            or string.find(line, "violation")
            or string.find(line, "lease speak")
            or string.find(line, "peak out loud")
            or string.find(line, "Y U SHOU D")
            or string.find(line, "whispers,")
            or string.find(line, "speaking to you")
            or string.find(line, "smiles at you")
            or string.find(line, "waves to you")
            or string.find(line, "grins at you")
            or string.find(line, "hugs you")
            or string.find(line, "takes hold your hand")
            or string.find(line, "grabs your hand")
            or string.find(line, "clasps your hand")
            or string.find(line, "trying to drag you") then
            -- Exclude LNet messages
            if not string.find(line, "LNet") then
                -- Also check for the obfuscated REPORT pattern: R e p o r t (with optional spaces)
                echo("AUTOBOT ALERT: " .. line)
            end
        end
        return line -- pass through, don't squelch
    end)

    before_dying(function()
        DownstreamHook.remove(hook_name)
    end)
end

--------------------------------------------------------------------------------
-- Main execution
--------------------------------------------------------------------------------

local settings = load_settings()
debug_enabled = settings.debug or false

local cmd = Script.vars[1] and string.lower(Script.vars[1]) or nil

-- Command dispatch
if cmd and string.find(cmd, "setup") then
    GuiSettings.setup_gui(settings, PAINTS, AMMO_TYPES, save_settings, debug_log)
    return
elseif cmd and string.find(cmd, "bundle") then
    Bundling.bundle_arrows(settings, Crafting.stow, debug_log)
    return
elseif cmd and string.find(cmd, "settings") then
    show_current_settings(settings)
    return
elseif cmd and string.find(cmd, "help") then
    show_help()
    return
elseif cmd then
    -- Unknown command, show brief help
    respond("")
    respond("FletchIt - Automated Fletching Script")
    respond("")
    respond("This script needs a mapped room if you want it to buy items.")
    respond("Run ';fletchit setup' to configure settings.")
    respond("While running, ';fletchit' shows progress, ';fletchit stats' shows detailed stats, ';fletchit stop' ends gracefully.")
    respond("")
    return
end

-- Validate settings
local warnings = validate_settings(settings)
if #warnings > 0 then
    for _, w in ipairs(warnings) do echo("WARNING: " .. w) end
    echo("Run ;fletchit setup to configure.")
    -- Open setup GUI automatically on validation failure
    GuiSettings.setup_gui(settings, PAINTS, AMMO_TYPES, save_settings, debug_log)
    return
end

-- Normalize settings
settings = normalize_settings(settings)
save_settings(settings)

-- Reset stats for this session
stats = {}

-- Initialize tracking variables
local start_time = os.time()
local finished = false

-- Determine ammo type name for messages
local ammo_name = AMMO_TYPES[settings.ammo] or "arrow"
if not string.find(ammo_name, "s$") then ammo_name = ammo_name .. "s" end

-- Set up upstream hook for commands while running.
-- Accepts "stop|done|end|finish|finished" not just "stop".
local hook_name = "fletchit_hook_" .. tostring(os.time())
UpstreamHook.add(hook_name, function(line)
    local stripped = string.gsub(line, "^<c>", "")
    local lower = string.lower(stripped)

    if string.find(lower, "^;fletchit$") then
        show_stats(true, start_time, ammo_name)
        return nil
    elseif string.find(lower, "^;fletchit%s+stats$") then
        update_session_stats(start_time)
        show_stats(false, start_time, ammo_name)
        return nil
    elseif string.find(lower, "^;fletchit%s+stop$")
        or string.find(lower, "^;fletchit%s+done$")
        or string.find(lower, "^;fletchit%s+end$")
        or string.find(lower, "^;fletchit%s+finish$")
        or string.find(lower, "^;fletchit%s+finished$") then
        finished = true
        echo("")
        echo("Will stop after completing current " .. ammo_name:gsub("s$", ""))
        echo("")
        return nil
    end
    return line
end)

-- Set up before_dying to show stats and clean up
before_dying(function()
    UpstreamHook.remove(hook_name)
    -- Only show stats if we have any actual activity
    local has_activity = false
    for key, value in pairs(stats) do
        if key ~= "session_time_seconds" and value > 0 then
            has_activity = true
            break
        end
    end
    if has_activity then
        update_session_stats(start_time)
        show_stats(false, start_time, ammo_name)
    end
end)

-- Start interaction monitoring if enabled
monitor_interaction(settings)

-- Empty hands to start
Crafting.empty_hands(settings.sack, debug_log)

echo("FletchIt v" .. VERSION .. " started. Making " .. ammo_name .. "...")

-- Main fletching loop
while not finished do
    -- Run ewaggle if enabled
    if settings.waggle then
        Script.run("ewaggle")
    end

    -- Check for needed supplies
    local fletch_sack_contents = Shopping.get_container_contents(settings.sack, debug_log)
    local needed_items = Shopping.check_needed_items(settings, fletch_sack_contents, PAINTS, debug_log)

    if #needed_items > 0 then
        if not settings.enable_buying then
            echo("ERROR: Run out of " .. needed_items[1] .. " and auto-buying is disabled.")
            echo("Run ';fletchit setup' to enable auto-buying.")
            break
        end

        respond("")
        for _, item in ipairs(needed_items) do
            respond("Out of " .. item)
        end
        respond("Going to buy supplies...")
        respond("")
        pause(1)

        local silver_spent = Shopping.buy_items(settings, needed_items, add_stat, debug_log)
        local clamped = math.max(silver_spent, 0)
        add_stat("silver_spent_supplies", clamped)
        fletch_sack_contents = Shopping.get_container_contents(settings.sack, debug_log)
    end

    -- Make shafts if we have wood/logs AND no shafts remaining
    local has_shafts = false
    local has_wood = false
    for _, item in ipairs(fletch_sack_contents) do
        local noun = item.noun or ""
        if noun == "shaft" or noun == "shafts" then has_shafts = true end
        if noun == "wood" or noun == "log" then has_wood = true end
    end

    if not has_shafts and has_wood then
        waitrt()
        Crafting.make_shafts(settings, add_stat, debug_log)
    end

    -- Wait for mind to absorb if learning mode enabled
    if settings.learning then
        local mind_threshold = tonumber(settings.mind) or 60
        if GameState.mind_value and GameState.mind_value > mind_threshold then
            respond("")
            respond("Waiting for mind to drop below " .. mind_threshold .. "% (currently " .. tostring(GameState.mind_value) .. "%)...")
            respond("")
            local mind_wait_start = os.time()
            wait_while(function()
                return GameState.mind_value and GameState.mind_value > mind_threshold
            end)
            local mind_wait_time = os.time() - mind_wait_start
            add_stat("mind_wait_time_seconds", mind_wait_time)
        end
    end

    -- Make an arrow/bolt
    local result = Crafting.make_arrow(settings, PAINTS, add_stat, debug_log)

    -- Track results based on return status
    if result == "completed" then
        -- Completion already tracked inside finalize_arrow
    elseif result == "failed" then
        if settings.ammo == 1 then
            add_stat("arrows_failed", 1)
        elseif settings.ammo == 2 then
            add_stat("light_bolts_failed", 1)
        elseif settings.ammo == 3 then
            add_stat("heavy_bolts_failed", 1)
        end
    elseif result == "no_shafts" then
        add_stat("supply_shortage_events", 1)
    elseif result == "no_supplies" then
        add_stat("supply_shortage_events", 1)
    end

    -- Report progress (unless in learning mode)
    if not settings.learning then
        show_stats(true, start_time, ammo_name)
    end

    -- Check exit conditions
    if finished then break end

    local limit_val = tonumber(settings.limit) or 0
    if limit_val > 0 then
        local total_made = get_stat("arrows_completed") + get_stat("light_bolts_completed") + get_stat("heavy_bolts_completed")
        if total_made >= limit_val then break end
    end
end

respond("")
respond("Fletching complete!")
respond("")
