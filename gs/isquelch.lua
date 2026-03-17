--- @revenant-script
--- name: isquelch
--- version: 0.2.2
--- author: elanthia-online
--- game: gs
--- description: Configurable squelching of incoming lines via regex patterns
--- tags: squelching,squelch
---
--- Changelog (from Lich5):
---   v0.2.2 (2025-07-02) - Bugfix in Regex generation for NIL values
---   v0.2.1 (2024-07-12) - Bugfix in special Regexp character escaping
---   v0.2.0 (2020-12-03) - Export command for squelches
---   v0.1.0 (2020-12-02) - Import ignores from StormFront XML
---   v0.0.1 (2020-10-21) - Initial release

local SCRIPT_NAME = Script.name
local HOOK_NAME = SCRIPT_NAME .. "_filter"

--------------------------------------------------------------------------------
-- Settings (stored as JSON in UserVars)
--------------------------------------------------------------------------------

local function load_squelches()
    local raw = UserVars[SCRIPT_NAME]
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_squelches(list)
    UserVars[SCRIPT_NAME] = Json.encode(list)
end

local squelches = load_squelches()

--------------------------------------------------------------------------------
-- Regex rebuilding
--------------------------------------------------------------------------------

local combined_regex = nil

local function rebuild_regex()
    local patterns = {}
    for _, entry in ipairs(squelches) do
        if type(entry) == "table" and entry.enabled and entry.text and entry.text ~= "" then
            patterns[#patterns + 1] = entry.text
        end
    end
    if #patterns == 0 then
        combined_regex = nil
    else
        combined_regex = Regex.new(table.concat(patterns, "|"))
    end
end

--------------------------------------------------------------------------------
-- Downstream hook
--------------------------------------------------------------------------------

DownstreamHook.add(HOOK_NAME, function(line)
    if not line or line:match("^%s*$") then return line end
    if combined_regex and combined_regex:test(line) then
        return nil
    end
    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

rebuild_regex()

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function print_help()
    respond("Usage: ;isquelch <command> [arguments]")
    respond("")
    respond("Commands:")
    respond("  add <REGEX>       Adds REGEX to the squelch list")
    respond("  enable <INDEX>    Enables the pattern at INDEX (0-based)")
    respond("  disable <INDEX>   Disables the pattern at INDEX (0-based)")
    respond("  remove <INDEX>    Removes the pattern at INDEX (0-based)")
    respond("  list              Lists all patterns")
    respond("  stop              Quit isquelch")
    respond("  help              Show this help")
    respond("")
    respond("Examples:")
    respond('  ;isquelch add tossing the sand aside\\.$')
    respond("  ;isquelch list")
    respond("  ;isquelch disable 0")
    respond("  ;isquelch enable 0")
    respond("  ;isquelch remove 0")
end

local function print_squelches()
    if #squelches == 0 then
        respond("No squelch entries recorded.")
    else
        for i, entry in ipairs(squelches) do
            local text = (type(entry) == "table" and entry.text) or "?"
            local state = (type(entry) == "table" and entry.enabled) and "enabled" or "disabled"
            respond(string.format("%d. /%s/ (%s)", i - 1, text, state))
        end
    end
end

local function handle_command(args)
    if not args or args == "" then
        print_help()
        return false
    end

    local parts = {}
    for word in args:gmatch("%S+") do
        parts[#parts + 1] = word
    end

    local command = parts[1]:lower()
    local argument = table.concat(parts, " ", 2)
    local update = false

    if command == "add" then
        if argument == "" then
            print_help()
            return false
        end
        squelches[#squelches + 1] = { text = argument, enabled = true }
        respond("Added /" .. argument .. "/")
        update = true
    elseif command == "enable" then
        local idx = tonumber(argument)
        if not idx or idx < 0 or idx >= #squelches then
            respond("Invalid index")
            return false
        end
        squelches[idx + 1].enabled = true
        respond("Enabled entry " .. idx)
        update = true
    elseif command == "disable" then
        local idx = tonumber(argument)
        if not idx or idx < 0 or idx >= #squelches then
            respond("Invalid index")
            return false
        end
        squelches[idx + 1].enabled = false
        respond("Disabled entry " .. idx)
        update = true
    elseif command == "remove" or command == "rm" then
        local idx = tonumber(argument)
        if not idx or idx < 0 or idx >= #squelches then
            respond("Invalid index")
            return false
        end
        local text = squelches[idx + 1].text or "?"
        table.remove(squelches, idx + 1)
        respond("Removed /" .. text .. "/")
        update = true
    elseif command == "list" or command == "ls" then
        print_squelches()
    elseif command == "stop" then
        return true
    elseif command == "help" then
        print_help()
    else
        print_help()
    end

    if update then
        save_squelches(squelches)
        rebuild_regex()
    end
    return false
end

--------------------------------------------------------------------------------
-- Process initial arguments if any
--------------------------------------------------------------------------------

local initial_args = Script.vars[0]
if initial_args and initial_args ~= "" then
    if handle_command(initial_args) then return end
end

--------------------------------------------------------------------------------
-- Main upstream command loop
--------------------------------------------------------------------------------

local UPSTREAM_HOOK_ID = SCRIPT_NAME .. "_upstream"
local cmd_queue = {}

UpstreamHook.add(UPSTREAM_HOOK_ID, function(command)
    local match = command:match("^<?c?>?;" .. SCRIPT_NAME .. "%s*(.*)")
    if match then
        cmd_queue[#cmd_queue + 1] = match
        return nil
    end
    return command
end)

before_dying(function()
    UpstreamHook.remove(UPSTREAM_HOOK_ID)
end)

echo("iSquelch running. " .. #squelches .. " pattern(s) loaded. Type ;isquelch help for commands.")

while true do
    if #cmd_queue > 0 then
        local cmd = table.remove(cmd_queue, 1)
        if handle_command(cmd) then break end
    end
    pause(0.1)
end
