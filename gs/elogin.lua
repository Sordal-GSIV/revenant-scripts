--- @revenant-script
--- name: elogin
--- version: 2.0.3
--- author: elanthia-online
--- contributors: Phalen33, Lucullan
--- game: gs
--- description: Login automation for switching characters from within Revenant
--- tags: login
---
--- NOTE: This script is a Revenant adaptation of elogin.lic. The Lich5 version
--- relies heavily on Lich's internal Ruby APIs (EntryStore, YAML login entries,
--- Process.spawn, etc.) which have no direct Revenant equivalent. This version
--- provides the settings management (realm, character entries) using CharSettings
--- and JSON persistence, but actual login spawning requires Revenant's native
--- multi-session support.
---
--- Changelog (from Lich5):
---   v2.0.3 (2026-02-26) - Update to new API calls for Lich 5.15
---   v2.0.2 (2026-02-26) - Resolve error for custom launch only entries
---   v2.0.1 (2026-01-17) - Add custom launch command support
---   v2.0.0 (2026-01-13) - Add Lich 5.13+ support
---   v1.0.0 (2015-09-19) - Initial release

--------------------------------------------------------------------------------
-- Settings helpers
--------------------------------------------------------------------------------

local function load_entries()
    local raw = CharSettings.elogin_entries
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_entries(entries)
    CharSettings.elogin_entries = Json.encode(entries)
end

local function get_realm()
    return CharSettings.elogin_realm or nil
end

local function set_realm(realm)
    CharSettings.elogin_realm = realm
end

local function realm_to_game_code(realm)
    if realm == "platinum" then return "GSX"
    elseif realm == "shattered" then return "GSF"
    elseif realm == "test" then return "GST"
    else return "GS3"
    end
end

--------------------------------------------------------------------------------
-- Entry management
--------------------------------------------------------------------------------

local function show_usage()
    echo("Usage:")
    echo("  ;elogin set realm <prime|platinum|shattered|test>")
    echo("  ;elogin <char> [script1,script2,...]")
    echo("  ;elogin add <char> <user_id> <password>")
    echo("  ;elogin modify <char> <user_id> <password>")
    echo("  ;elogin delete <char> <game_code>")
    echo("  ;elogin list")
    echo("  ;elogin help")
end

local function list_entries()
    local entries = load_entries()
    if #entries == 0 then
        echo("No saved character entries found.")
        return
    end

    respond("")
    respond(string.format("%-15s %-15s %-8s", "Account", "Character", "Instance"))
    respond(string.rep("-", 40))
    for _, entry in ipairs(entries) do
        respond(string.format("%-15s %-15s %-8s",
            entry.user_id or "",
            entry.char_name or "",
            entry.game_code or ""))
    end
    echo("Total: " .. #entries .. " entries")
end

local function add_entry(char_name, user_id, password)
    local entries = load_entries()
    local realm = get_realm()
    local game_code = realm and realm_to_game_code(realm) or "GS3"

    -- Check for duplicate
    for _, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower() and e.game_code == game_code then
            echo("Error: Character already exists for " .. char_name .. " (" .. game_code .. "). Use 'modify' to update.")
            return
        end
    end

    entries[#entries + 1] = {
        char_name = char_name,
        game_code = game_code,
        user_id = user_id:lower(),
        password = password,
    }
    save_entries(entries)
    echo("Successfully added login entry for " .. char_name .. " (" .. game_code .. ").")
end

local function modify_entry(char_name, user_id, password)
    local entries = load_entries()
    local found = false

    for i, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower()
           and e.user_id and e.user_id:lower() == user_id:lower() then
            entries[i].password = password
            found = true
            break
        end
    end

    if not found then
        echo("No entry found for " .. char_name .. " with account " .. user_id)
        return
    end

    save_entries(entries)
    echo("Successfully modified login entry for " .. char_name .. ".")
end

local function delete_entry(char_name, game_code)
    local entries = load_entries()
    local new_entries = {}
    local deleted = false

    for _, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower()
           and e.game_code and e.game_code:upper() == game_code:upper() then
            deleted = true
        else
            new_entries[#new_entries + 1] = e
        end
    end

    if not deleted then
        echo("No matching entry found for " .. char_name .. " (" .. game_code .. ").")
        return
    end

    save_entries(new_entries)
    echo("Deleted entry for " .. char_name .. " (" .. game_code .. ").")
end

local function do_login(char_name, scripts)
    local entries = load_entries()
    local realm = get_realm()
    if not realm then
        echo("No realm set. Use ;elogin set realm <prime|platinum|shattered|test>")
        return
    end

    local game_code = realm_to_game_code(realm)

    -- Find the character
    local entry = nil
    for _, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower() then
            if not e.game_code or e.game_code == game_code then
                entry = e
                break
            end
        end
    end

    if not entry then
        echo("No matching entry found for " .. char_name .. " in realm " .. realm .. ".")
        return
    end

    echo("Logging in as " .. entry.char_name .. " (" .. game_code .. ")...")

    -- In Revenant, actual session spawning would use the engine's native
    -- multi-session capability. For now, report what would happen.
    echo("Account: " .. (entry.user_id or "unknown"))
    echo("Game code: " .. game_code)
    if scripts and #scripts > 0 then
        echo("Startup scripts: " .. table.concat(scripts, ", "))
    end

    -- TODO: Revenant native login spawning
    echo("Note: Automatic login spawning requires Revenant's native multi-session support.")
end

--------------------------------------------------------------------------------
-- Argument parsing and dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if not arg1 or arg1:lower() == "help" then
    show_usage()
    return
end

local arg1_lower = arg1:lower()

if arg1_lower == "set" then
    local arg2 = Script.vars[2]
    local arg3 = Script.vars[3]
    if arg2 and arg2:lower() == "realm" and arg3 then
        local valid_realms = { prime = true, platinum = true, shattered = true, test = true }
        if valid_realms[arg3:lower()] then
            set_realm(arg3:lower())
            echo("Realm set to " .. arg3:lower() .. ".")
        else
            echo("Invalid realm. Use: prime, platinum, shattered, or test.")
        end
    else
        show_usage()
    end
elseif arg1_lower == "add" then
    local char = Script.vars[2]
    local user_id = Script.vars[3]
    local pw = Script.vars[4]
    if char and user_id and pw then
        add_entry(char:sub(1,1):upper() .. char:sub(2), user_id, pw)
    else
        show_usage()
    end
elseif arg1_lower == "modify" then
    local char = Script.vars[2]
    local user_id = Script.vars[3]
    local pw = Script.vars[4]
    if char and user_id and pw then
        modify_entry(char:sub(1,1):upper() .. char:sub(2), user_id, pw)
    else
        show_usage()
    end
elseif arg1_lower == "delete" then
    local char = Script.vars[2]
    local gc = Script.vars[3]
    if char and gc then
        delete_entry(char, gc)
    else
        show_usage()
    end
elseif arg1_lower == "list" then
    list_entries()
else
    -- Login command
    local char_name = arg1:sub(1,1):upper() .. arg1:sub(2)
    local scripts_str = Script.vars[2]
    local scripts = {}
    if scripts_str and not scripts_str:find("^%-%-") then
        for s in scripts_str:gmatch("[^,]+") do
            scripts[#scripts + 1] = s:match("^%s*(.-)%s*$")
        end
    end
    do_login(char_name, scripts)
end
