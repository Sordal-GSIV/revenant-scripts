--- @revenant-script
--- name: idleaction
--- version: 1.0.1
--- author: Peggyanne
--- game: gs
--- tags: idle, roleplay, action, automation
--- description: Customizable idle ACTion script — randomly performs configured ACT commands at set intervals
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Peggyanne (Bait#4376 on Discord)
--- Ported to Revenant Lua from idleaction.lic v1.0.1
---
--- Changelog (from Lich5):
---   October 25, 2025 — Initial Release.
---   October 29, 2025 — Fixed Issue With Punctuation.
---
--- Features:
---   - Up to 100 custom ACT commands across 10 tabbed pages.
---   - Configurable idle timer interval (default 120 seconds).
---   - Randomly selects from non-empty action slots each interval.
---   - GUI setup window with ;idleaction setup
---
--- Usage:
---   ;idleaction                  - Start idle action loop
---   ;idleaction setup            - Open setup window
---   ;idleaction help             - Display help

local gui = require("gui")

local function show_help()
    respond("------------------------------------------------------------------------------")
    respond("   IdleACTion Version: 1.0.1")
    respond("")
    respond("   Usage: ")
    respond("")
    respond("   ;idleaction setup                       Opens the setup window")
    respond("")
    respond("   This is a customizable idle ACTion script, you can enter up to 100 different custom ACT commands.")
    respond("   At every defined interval the script will select one randomly and perform it.")
    respond("   Enjoy ")
    respond("")
    respond("   ~Peggyanne ")
    respond(" PS: feel free to send me any bugs via discord Bait#4376 and I'll try my best to fix them. ")
    respond("")
    respond("Changelog:")
    respond("")
    respond("           October 25, 2025 - Initial Release.")
    respond("           October 29, 2025 - Fixed Issue With Punctuation.")
    respond("")
end

--- Load saved settings from CharSettings (JSON-encoded table)
local function load_settings()
    local raw = CharSettings.idleaction
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

--- Save settings to CharSettings
local function save_settings(data)
    CharSettings.idleaction = Json.encode(data)
end

--- Collect all non-empty action strings from settings
local function get_actions(settings)
    local actions = {}
    for i = 1, 100 do
        local key = "message_" .. i
        local val = settings[key]
        if val and val ~= "" then
            actions[#actions + 1] = val
        end
    end
    return actions
end

--- Perform a random idle action
local function perform_idle_action(settings)
    local actions = get_actions(settings)
    if #actions == 0 then
        echo("No actions configured! Use ;idleaction setup to add some.")
        return
    end
    waitrt()
    waitcastrt()
    local chosen = actions[math.random(1, #actions)]
    put("act " .. chosen)
end

-- Parse arguments
local arg1 = Script.vars[1]

if arg1 and arg1:lower() == "setup" then
    local settings = load_settings()
    local result = gui.open_setup(settings)
    if result then
        save_settings(result)
        echo("Settings saved.")
    else
        echo("Setup cancelled (no changes saved).")
    end
    return
elseif arg1 == "?" or (arg1 and arg1:lower() == "help") then
    show_help()
    return
end

-- Main idle loop
local settings = load_settings()
local interval = tonumber(settings.seconds) or 120
if interval < 1 then interval = 1 end

echo("Starting idle actions every " .. interval .. " seconds. " .. #get_actions(settings) .. " action(s) configured.")
echo("Use ;idleaction setup to configure.")

while true do
    pause(interval)
    -- Reload settings each cycle so GUI changes take effect without restart
    settings = load_settings()
    interval = tonumber(settings.seconds) or 120
    if interval < 1 then interval = 1 end
    perform_idle_action(settings)
end
