--- @revenant-script
--- name: warlogin
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Force Warlock3 launch by temporarily modifying saved entry data
--- tags: warlock, login, launcher, utility
---
--- Ported from warlogin.lic (305 lines)
---
--- This script temporarily modifies entry.yaml or entry.dat to set a custom_launch
--- for Warlock3, spawns lich.rbw, then restores the original entry after a delay.
---
--- NOTE: This script is deeply tied to Lich5's Ruby infrastructure (entry.yaml/dat,
--- Marshal, RbConfig, Process.spawn). In Revenant, the login/launch process is
--- handled differently by the Rust engine. This conversion preserves the logic
--- for reference but adapts it to Revenant's architecture.
---
--- Usage:
---   ;warlogin <character name>
---   ;warlogin <character name> <restore_delay_seconds>

local WARLOCK_LAUNCH = "warlock --host localhost --port %port% --key %key%"
local DEFAULT_RESTORE_DELAY = 8

local function die(msg)
    echo(msg)
    return
end

local function realm_to_game_code(realm)
    if realm == "platinum" then return "GSX"
    elseif realm == "shattered" then return "GSF"
    elseif realm == "test" then return "GST"
    else return "GS3"
    end
end

-- Parse arguments
local args = script.vars or {}
if not args[1] or args[1]:lower() == "help" then
    echo("Usage:")
    echo("  ;warlogin <character name>")
    echo("  ;warlogin <character name> <restore_delay_seconds>")
    echo("")
    echo("Forces Warlock3 launch with:")
    echo("  " .. WARLOCK_LAUNCH)
    echo("")
    echo("NOTE: This script is designed for the Lich5 launcher infrastructure.")
    echo("In Revenant, use the engine's --frontend warlock option instead.")
    return
end

local char_name = args[1]:sub(1,1):upper() .. args[1]:sub(2):lower()
local delay = DEFAULT_RESTORE_DELAY
if args[2] and args[2]:match("^%d+$") then
    delay = tonumber(args[2])
    if delay < 1 then delay = DEFAULT_RESTORE_DELAY end
end

local realm = (CharSettings["realm"] or "prime"):lower()
local game_code = realm_to_game_code(realm)

echo("Character: " .. char_name)
echo("Realm: " .. realm .. " (" .. game_code .. ")")
echo("Restore delay: " .. delay .. " seconds")
echo("")

-- In Revenant, the login process is handled by the Rust engine.
-- The original script modifies entry.yaml/entry.dat files to inject
-- the Warlock custom_launch command, spawns lich.rbw, then spawns
-- a helper script to restore the original entry after a delay.

-- Check for entry files
local yaml_path = DATA_DIR .. "/entry.yaml"
local dat_path = DATA_DIR .. "/entry.dat"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local store = nil
if file_exists(yaml_path) then
    store = "yaml"
elseif file_exists(dat_path) then
    store = "dat"
end

if not store then
    echo("NOTE: No Lich5 entry store found (entry.yaml / entry.dat).")
    echo("This is expected in Revenant. Use the engine's launch options instead:")
    echo("  cargo run -- --listen 127.0.0.1:4900 --frontend warlock ...")
    echo("")
    echo("If you need to launch Warlock3 for a separate Lich5 instance,")
    echo("you'll need to run this from within Lich5 itself.")
    return
end

-- For Lich5 compatibility mode: attempt the YAML modification
if store == "yaml" then
    echo("Found entry.yaml - attempting Warlock3 launch injection...")

    -- Read the YAML
    local f = io.open(yaml_path, "r")
    if not f then
        die("Error: Cannot read " .. yaml_path)
        return
    end
    local content = f:read("*a")
    f:close()

    -- Simple search for the character entry and inject custom_launch
    -- This is a simplified approach; full YAML parsing would be better
    local pattern = "char_name: " .. char_name
    if not content:find(pattern) then
        die("Error: No saved entry found for " .. char_name .. " (" .. realm .. "/" .. game_code .. ")")
        return
    end

    -- Save backup
    local backup_path = yaml_path .. ".warlogin_backup_" .. os.time()
    local bf = io.open(backup_path, "w")
    if bf then
        bf:write(content)
        bf:close()
        echo("Backup saved to: " .. backup_path)
    end

    -- Inject custom_launch (find the character block and add/replace custom_launch)
    local modified = content:gsub(
        "(char_name: " .. char_name .. ".-game_code: " .. game_code .. ")",
        "%1\n    custom_launch: " .. WARLOCK_LAUNCH
    )

    local wf = io.open(yaml_path, "w")
    if wf then
        wf:write(modified)
        wf:close()
        echo("Injected Warlock3 custom_launch for " .. char_name)
    end

    -- Schedule restore after delay
    echo("Will restore original entry in " .. delay .. " seconds...")
    task.new(function()
        sleep(delay)
        local rf = io.open(yaml_path, "w")
        if rf then
            rf:write(content)
            rf:close()
            echo("Restored original entry.yaml")
        end
        -- Clean up backup
        os.remove(backup_path)
    end)

    echo("Launch injection complete. The entry will be restored automatically.")
else
    echo("entry.dat (legacy format) detected. Marshal format requires Ruby runtime.")
    echo("Please use entry.yaml format or launch Warlock3 manually.")
end
