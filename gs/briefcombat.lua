--- @revenant-script
--- name: briefcombat
--- version: 1.0.3
--- author: Daedeus
--- contributors: Tysong, Ragz
--- game: gs
--- description: Combat text filtering/abbreviation for cleaner output
--- tags: brief,combat,condensing,squelch
---
--- Changelog (from Lich5):
---   v1.0.3 (2026-02-02): --flares/--no-flares, --numbers/--no-numbers, fix ball spell detection
---   v1.0.2 (2026-01-31): standard mode keeps numbers and body part damage
---   v1.0.1 (2026-01-29): bugfix in instance variable location
---   v1.0.0 (2026-01-25): refactor into module, CharSettings support
---
--- Usage:
---   ;briefcombat              - compress other players' combat messages
---   ;briefcombat -x           - extreme mode (aggressive compression)
---   ;briefcombat all          - also compress your own actions
---   ;briefcombat --no-extreme - disable extreme mode
---   ;briefcombat --no-all     - stop compressing own actions
---   ;briefcombat --numbers    - show damage rolls (default: on)
---   ;briefcombat --no-numbers - hide damage rolls
---   ;briefcombat --flares     - show flare messaging (default: on)
---   ;briefcombat --no-flares  - hide flare messaging
---   ;briefcombat --exclude=<players> - exclude players from compression
---   ;briefcombat --list       - show current settings
---   ;briefcombat --help       - show help

---------------------------------------------------------------------------
-- Settings (persisted in CharSettings)
---------------------------------------------------------------------------
local function load_bool_setting(key, default)
    local raw = CharSettings["briefcombat_" .. key]
    if raw == nil or raw == "" then return default end
    return raw == "true"
end

local function save_bool_setting(key, val)
    CharSettings["briefcombat_" .. key] = tostring(val)
end

local function load_string_setting(key, default)
    local raw = CharSettings["briefcombat_" .. key]
    if raw == nil or raw == "" then return default end
    return raw
end

local function save_string_setting(key, val)
    CharSettings["briefcombat_" .. key] = val or ""
end

---------------------------------------------------------------------------
-- Parse arguments
---------------------------------------------------------------------------
local args = Script.vars
local extreme_mode = nil
local compress_self = nil
local show_numbers = nil
local show_flares = nil
local excluded_players = {}
local debug_mode = false

-- Check for --help/--list first
for i = 1, #args do
    local a = args[i]
    if not a then break end
    local lower = a:lower()
    if lower == "--help" or lower == "-h" then
        respond([[

===========================================================================
                                BRIEFCOMBAT HELP
===========================================================================

Dramatically shortens most combat text.

USAGE:
  ;briefcombat [OPTIONS]

OPTIONS:
  all, --all              Compress your own combat actions (default: false)
  --no-all                Don't compress your own actions
  --numbers               Show damage rolls (default: true)
  --no-numbers            Hide damage rolls
  --flares                Show flare messaging (default: true)
  --no-flares             Hide flare messaging
  -x, --extreme           Extreme mode (default: false)
  --no-extreme            Disable extreme mode
  --exclude=<players>     Exclude specific players from compression
  -d, --debug             Enable debug output
  --list                  Show current settings
  -h, --help              Show this help message

===========================================================================
        ]])
        return
    elseif lower == "--list" then
        respond("")
        respond("===========================================================================")
        respond("                         BRIEFCOMBAT CURRENT SETTINGS")
        respond("===========================================================================")
        respond("")
        respond("Extreme Mode:     " .. tostring(load_bool_setting("extreme", false)))
        respond("Compress Self:    " .. tostring(load_bool_setting("compress_self", false)))
        respond("Show Numbers:     " .. tostring(load_bool_setting("show_numbers", true)))
        respond("Show Flares:      " .. tostring(load_bool_setting("show_flares", true)))
        respond("Excluded Players: " .. load_string_setting("excluded", ""))
        respond("")
        respond("===========================================================================")
        return
    end
end

-- Parse remaining args
for i = 1, #args do
    local a = args[i]
    if not a then break end
    local lower = a:lower()

    if lower == "-x" or lower == "--extreme" then
        extreme_mode = true
    elseif lower == "--no-extreme" then
        extreme_mode = false
    elseif lower == "all" or lower == "--all" then
        compress_self = true
    elseif lower == "--no-all" then
        compress_self = false
    elseif lower == "--numbers" then
        show_numbers = true
    elseif lower == "--no-numbers" then
        show_numbers = false
    elseif lower == "--flares" then
        show_flares = true
    elseif lower == "--no-flares" then
        show_flares = false
    elseif lower == "--debug" or lower == "-d" then
        debug_mode = true
    elseif lower:find("^--exclude=") then
        local players_str = a:match("^--exclude=(.+)")
        if players_str then
            -- Remove quotes
            players_str = players_str:gsub("[\"']", "")
            for name in players_str:gmatch("[^, ]+") do
                table.insert(excluded_players, name)
            end
        end
    end
end

-- Apply settings (CLI overrides saved)
if extreme_mode ~= nil then
    save_bool_setting("extreme", extreme_mode)
else
    extreme_mode = load_bool_setting("extreme", false)
end

if compress_self ~= nil then
    save_bool_setting("compress_self", compress_self)
else
    compress_self = load_bool_setting("compress_self", false)
end

if show_numbers ~= nil then
    save_bool_setting("show_numbers", show_numbers)
else
    show_numbers = load_bool_setting("show_numbers", true)
end

if show_flares ~= nil then
    save_bool_setting("show_flares", show_flares)
else
    show_flares = load_bool_setting("show_flares", true)
end

if #excluded_players > 0 then
    save_string_setting("excluded", table.concat(excluded_players, ","))
else
    local saved = load_string_setting("excluded", "")
    if saved ~= "" then
        for name in saved:gmatch("[^,]+") do
            table.insert(excluded_players, name)
        end
    end
end

-- Always exclude self unless compress_self
if not compress_self then
    table.insert(excluded_players, "You")
end

-- Deduplicate excluded
local seen = {}
local unique_excluded = {}
for _, p in ipairs(excluded_players) do
    local key = p:lower() == "self" and "You" or p
    if not seen[key] then
        seen[key] = true
        table.insert(unique_excluded, key)
    end
end
excluded_players = unique_excluded

-- Startup messages
if extreme_mode then
    echo("Extreme mode! Will aggressively shorten non-essential text.")
else
    echo("Standard mode! Combat numbers and gore preserved. Use -x for extreme mode.")
end

if not compress_self then
    echo("Compressing others' combat messaging. Use 'all' to compress your own actions.")
else
    echo("Compressing all combat messaging. Use --no-all to see your own actions.")
end

if #excluded_players > 0 then
    echo("Excluding: " .. table.concat(excluded_players, ", "))
end

if debug_mode then
    echo("DEBUG MODE ENABLED")
end

-- Request MonsterBold
fput("set MonsterBold On")

---------------------------------------------------------------------------
-- Combat compression state
---------------------------------------------------------------------------
local compressing = false
local compressed_lines = {}
local targets_damage = {}
local targets_status = {}
local targets_last_message = {}
local targets_numbers = {}
local targets_flare = {}
local targets_aim_message = {}
local current_target = nil
local bounty_message = nil
local spell_guess = nil
local spell_cast_string = nil
local compress_last = nil
local compress_you_last = nil
local is_no_target = false
local first_line_has_damage = false

-- Simple squelch patterns
local simple_squelch = {
    "Roundtime:",
    "incandescent veil fades",
    "knobby layer of bark",
    "briefly before decaying into dust",
    "breathtaking display of ability",
    "looks determined and focused",
    "removes a single.*from",
    "nocks? an?",
    "surge of empowerment",
}

-- Status effect patterns
local status_effects = {
    stunned    = "stunned",
    frozen     = "freezes",
    knockdown  = "falls over",
    dead       = "falls to the .* motionless",
    pinned     = "pins? .* to the",
    webbed     = "ensnared in thick strands",
    buffeted   = "buffeted by",
}

-- Gesture/attack verb patterns (simplified for Lua pattern matching)
local combat_verbs = {
    "gestures? at",
    "gestures?%.",
    "channels? at",
    "waves? .+ at",
    "swings? .+ at",
    "thrusts? .+ at",
    "hurls? .+ at",
    "fires? .+ at",
    "throws? .+ at",
    "punches? .+ at",
    "charges? forward at",
    "lunges? forward at",
}

---------------------------------------------------------------------------
-- Hook function
---------------------------------------------------------------------------
local function check_excluded(line)
    for _, player in ipairs(excluded_players) do
        if line:find(player, 1, true) then
            return true
        end
    end
    return false
end

local function check_combat_start(line)
    -- Check if line starts a combat action
    for _, verb in ipairs(combat_verbs) do
        if line:find(verb) then
            return true
        end
    end
    return false
end

local function check_status(line, target_id)
    if not target_id then return end
    for status, pattern in pairs(status_effects) do
        if line:find(pattern) then
            if not targets_status[target_id] then
                targets_status[target_id] = {}
            end
            table.insert(targets_status[target_id], status)
        end
    end
end

local function begin_compress(line)
    compressing = true
    compressed_lines = {line}
    targets_damage = {}
    targets_status = {}
    targets_last_message = {}
    targets_numbers = {}
    targets_flare = {}
    targets_aim_message = {}
    current_target = nil
    bounty_message = nil
    spell_guess = nil
    spell_cast_string = nil
    compress_last = nil
    compress_you_last = nil
    is_no_target = true
    first_line_has_damage = false

    -- Check for damage in first line
    local dmg = line:match("(%d+) points? of damage")
    if dmg then
        first_line_has_damage = true
    end
end

local function end_compress(line)
    compressing = false

    local num_targets = 0
    for _ in pairs(targets_damage) do num_targets = num_targets + 1 end

    -- Add last line (prompt)
    table.insert(compressed_lines, line)
    if bounty_message then
        table.insert(compressed_lines, bounty_message)
    end
    table.insert(compressed_lines, "")

    -- Build summary for targets
    if extreme_mode and num_targets > 0 then
        local num_dead = 0
        local num_stunned = 0
        local total_damage = 0

        for target_id, damage in pairs(targets_damage) do
            total_damage = total_damage + damage
            local status_arr = targets_status[target_id] or {}
            for _, s in ipairs(status_arr) do
                if s == "dead" then num_dead = num_dead + 1 end
                if s == "stunned" then num_stunned = num_stunned + 1 end
            end
        end

        if total_damage > 0 or num_dead > 0 or num_stunned > 0 then
            local parts = {}
            if num_dead > 0 then table.insert(parts, num_dead .. " KILLED") end
            if num_stunned > 0 then table.insert(parts, num_stunned .. " stunned") end
            if total_damage > 0 then table.insert(parts, total_damage .. " damage") end
            table.insert(compressed_lines, #compressed_lines, "  ... " .. table.concat(parts, ", ") .. "!")
        end
    elseif num_targets > 0 then
        -- Standard mode: show numbers and damage per target
        for target_id, damage in pairs(targets_damage) do
            if show_numbers and targets_numbers[target_id] then
                for _, roll in ipairs(targets_numbers[target_id]) do
                    table.insert(compressed_lines, #compressed_lines, roll)
                end
            end
            if show_flares and targets_flare[target_id] then
                for _, flare in ipairs(targets_flare[target_id]) do
                    table.insert(compressed_lines, #compressed_lines, flare)
                end
            end
            if damage > 0 then
                local msg = targets_last_message[target_id]
                if msg then
                    table.insert(compressed_lines, #compressed_lines, "  .. " .. tostring(damage) .. " damage!  " .. msg)
                else
                    table.insert(compressed_lines, #compressed_lines, "  .. " .. tostring(damage) .. " damage!")
                end
            end
        end
    end

    return table.concat(compressed_lines, "\n")
end

local function compress_line(line)
    compress_last = line
    if line:find("You") then compress_you_last = line end

    -- Check for damage
    local dmg = line:match("(%d+) points? of damage") or line:match("(%d+) damage")
    if dmg and current_target then
        targets_damage[current_target] = (targets_damage[current_target] or 0) + tonumber(dmg)
    end

    -- Check for combat rolls
    if line:find("CS:") or line:find("AS:") or line:find("UAF:") or line:find("d100") then
        if current_target then
            if not targets_numbers[current_target] then
                targets_numbers[current_target] = {}
            end
            table.insert(targets_numbers[current_target], line)
        end
        return
    end

    -- Check for flares (**)
    if line:find("%*%*") then
        if current_target then
            if not targets_flare[current_target] then
                targets_flare[current_target] = {}
            end
            table.insert(targets_flare[current_target], line)
        end
        return
    end

    -- Check for bounty
    if line:find("You succeeded in your task") or line:find("kills? remaining") then
        bounty_message = line
        return
    end

    -- Check status effects
    check_status(line, current_target)

    -- Track last message per target
    if current_target then
        targets_last_message[current_target] = line
    end
end

---------------------------------------------------------------------------
-- Main downstream hook
---------------------------------------------------------------------------
local function brief_hook(line)
    if not line then return line end

    -- If currently compressing
    if compressing then
        -- End on prompt
        if line:find("<prompt") or line:find("^>") then
            return end_compress(line)
        end
        compress_line(line)
        return nil -- squelch during compression
    end

    -- Check exclusions
    if check_excluded(line) then
        return line
    end

    -- Simple squelch patterns
    for _, pattern in ipairs(simple_squelch) do
        if line:find(pattern) then
            return nil
        end
    end

    -- Check for combat start
    if check_combat_start(line) then
        begin_compress(line)
        return nil
    end

    return line
end

---------------------------------------------------------------------------
-- Register hook and run
---------------------------------------------------------------------------
DownstreamHook.add("briefcombat", brief_hook)

before_dying(function()
    DownstreamHook.remove("briefcombat")
end)

-- Keep running
while true do
    pause(1)
end
