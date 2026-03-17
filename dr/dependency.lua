--- @revenant-script
--- name: dependency
--- version: 2.2.4
--- author: rpherbig
--- game: dr
--- description: DR script dependency manager - loads required modules, sets game flags, validates environment
--- tags: core, dependency, setup, flags
---
--- Ported from dependency.lic (Lich5) to Revenant Lua
---
--- Core bootstrapper for the DR script ecosystem. Ensures required flags are set,
--- loads data files, and provides the custom_require functionality.
---
--- Usage:
---   ;dependency   - Run once per session to initialize DR script environment

local DEPENDENCY_VERSION = "2.2.4"

no_pause_all()
no_kill_all()

-- Verify we're in DR
if GameState.game and not GameState.game:find("^DR") then
    echo("This script is for DragonRealms only.")
    return
end

echo("=== Dependency v" .. DEPENDENCY_VERSION .. " ===")
echo("Initializing DR script environment...")

-- Set required flags
local function set_flags()
    echo("Setting ShowRoomID and MonsterBold flags...")
    fput("flag ShowRoomID on")
    fput("flag MonsterBold on")
end

set_flags()

-- Module loader - provides custom_require equivalent
local loaded_modules = {}

function custom_require(modules)
    for _, mod in ipairs(modules) do
        if not loaded_modules[mod] then
            local ok = start_script(mod)
            if ok then
                pause(0.5)
                loaded_modules[mod] = true
                echo("  Loaded: " .. mod)
            else
                echo("  WARNING: Could not load " .. mod)
            end
        end
    end
end

-- Data file loader
function get_data(name)
    -- In Revenant, data files are loaded from the data/ directory
    local data = Data.load(name)
    if data then return data end
    echo("WARNING: Could not load data file: " .. name)
    return {}
end

-- Settings loader
function get_settings()
    local settings = CharSettings.get("dr_settings") or {}
    -- Merge with defaults
    settings.hometown = settings.hometown or "Crossing"
    settings.safe_room = settings.safe_room or nil
    return settings
end

echo("DR dependency initialization complete.")
echo("Modules: custom_require, get_data, get_settings available.")
