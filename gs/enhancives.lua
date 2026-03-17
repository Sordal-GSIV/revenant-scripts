--- @revenant-script
--- name: enhancives
--- version: 0.0.3
--- author: elanthia-online
--- game: gs
--- description: Enhancive item charge tracker -- monitors and warns at threshold
--- tags: core,mechanics,utility
---
--- Changelog (from Lich5):
---   v0.0.3 (2025-03-06) - removed unnecessary namespace scope
---   v0.0.2 (2024-07-26) - correct db entry to save threshold
---   v0.0.1 (2024-07-11) - released for testing

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local DATA_FILE = "data/enhancives.json"

local function load_settings()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
    return (ok and type(data) == "table") and data or {}
end

local function save_settings(s)
    File.write(DATA_FILE, Json.encode(s))
end

local settings = load_settings()
local first_run = false

if not settings.threshold then
    first_run = true
    settings.threshold = 5
    save_settings(settings)
end

local threshold = settings.threshold

--------------------------------------------------------------------------------
-- Enhancive scanning
--------------------------------------------------------------------------------

local ENHANCIVE_RX = Regex.new("noun=\"(\\w+)\">([\\w\\s\\-]+)</a>.*?\\((\\d+)/(\\d+) charges\\)")
local NO_ENHANCIVE_RX = Regex.new("^You are not (?:holding|wearing)")

local enhancive_items = {}
local no_enhancives = false

local function scan_enhancives()
    enhancive_items = {}
    no_enhancives = false
    local holding_count = 0

    local lines = dothistimeout("inventory enhancive list", 5, { "You are" })
    -- In Revenant, we use a simpler approach
    -- Capture lines from the command output
    -- For now we do a basic get loop
    pause(1)

    -- Simplified: send the command and parse output via downstream capture
    echo("Scanning enhancives...")
    fput("inventory enhancive list")
    pause(2)

    -- Since we can't easily capture multi-line output synchronously,
    -- we use a hook-based approach for the real implementation.
    -- For now, report based on what we know.
end

local function detect_low_charges()
    local results = {}
    for _, item in ipairs(enhancive_items) do
        if tonumber(item.current) and tonumber(item.current) <= threshold then
            results[#results + 1] = item.name
        end
    end
    return results
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function show_report()
    if #enhancive_items == 0 then
        respond("[Enhancives] No enhancive items tracked yet.")
        return
    end

    local function pad_right(s, w) return (#s >= w) and s or (s .. string.rep(" ", w - #s)) end
    local function pad_left(s, w) return (#s >= w) and s or (string.rep(" ", w - #s) .. s) end

    respond("")
    respond(pad_right("Noun", 12) .. pad_right("Name", 30) .. pad_left("Charges", 10) .. pad_left("Max", 8) .. "  Recharge")
    respond(string.rep("-", 70))

    for _, item in ipairs(enhancive_items) do
        local recharge = tonumber(item.current) <= threshold and " * Yes * " or "No"
        respond(pad_right(item.noun or "", 12) .. pad_right(item.name or "", 30) .. pad_left(item.current or "?", 10) .. pad_left(item.max or "?", 8) .. "  " .. recharge)
    end
    respond("")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("[Enhancives] Enhancive Item Charge Tracker")
    respond("")
    respond("Commands (run via ;enhancives <cmd>):")
    respond("  report     - Show current enhancive status")
    respond("  threshold N - Set charge warning threshold (current: " .. threshold .. ")")
    respond("  rescan     - Re-scan enhancive items")
    respond("  help       - Show this help")
    respond("")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 and arg1:lower() == "help" then
    show_help()
    return
elseif arg1 and arg1:lower() == "report" then
    show_report()
    return
elseif arg1 and arg1:lower() == "threshold" then
    local num = tonumber(Script.vars[2])
    if num then
        threshold = num
        settings.threshold = threshold
        save_settings(settings)
        echo("Threshold set to " .. threshold)
    else
        echo("Current threshold: " .. threshold)
    end
    return
elseif arg1 and arg1:lower() == "rescan" then
    scan_enhancives()
    return
end

--------------------------------------------------------------------------------
-- First run help
--------------------------------------------------------------------------------

if first_run then
    show_help()
end

--------------------------------------------------------------------------------
-- Main monitoring loop
--------------------------------------------------------------------------------

echo("Enhancives tracker started. Threshold: " .. threshold .. " charges.")

-- Set up a hook to capture enhancive data from inventory commands
local HOOK_NAME = "enhancives_capture"

DownstreamHook.add(HOOK_NAME, function(line)
    if not line then return line end
    local stripped = line:gsub("<.->", "")

    local m = ENHANCIVE_RX:match(stripped)
    if m then
        enhancive_items[#enhancive_items + 1] = {
            noun = m[1],
            name = m[2],
            current = m[3],
            max = m[4],
        }
    end

    if NO_ENHANCIVE_RX:test(stripped) then
        no_enhancives = true
    end

    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    save_settings(settings)
end)

while true do
    -- Periodically check
    local tracking = detect_low_charges()

    if no_enhancives then
        echo("You do not seem to have any enhancive items held or worn.")
    elseif #tracking == 0 and #enhancive_items > 0 then
        echo("Everything seems in order with your enhancives.")
    end

    if #tracking > 0 then
        for _, name in ipairs(tracking) do
            respond("[Enhancives] Your " .. name .. " is below your threshold!")
        end
    end

    -- Check every hour; re-scan
    pause(3600)
    enhancive_items = {}
    no_enhancives = false
    fput("inventory enhancive list")
    pause(2)
end
