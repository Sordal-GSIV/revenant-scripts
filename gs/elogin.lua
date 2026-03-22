--- @revenant-script
--- @lic-audit: validated 2026-03-17
--- name: elogin
--- version: 2.0.3
--- author: elanthia-online
--- contributors: Phalen33, Lucullan
--- game: gs
--- description: Login automation for switching characters from within Revenant
--- tags: login
---
--- NOTE: This script is a Revenant adaptation of elogin.lic. Actual login
--- spawning requires Revenant's native multi-session support (engine feature).
--- Settings management (realm, character entries, flags) is fully implemented.
---
--- Changelog (from Lich5):
---   v2.0.3 (2026-02-26) - Update to new API calls for Lich 5.15
---   v2.0.2 (2026-02-26) - Resolve error for custom launch only entries
---   v2.0.1 (2026-01-17) - Add custom launch command support
---   v2.0.0 (2026-01-13) - Add Lich 5.13+ support
---   v1.2.3 (2024-12-02) - Wrap paths in quotes for spaces in path
---   v1.2.2 (2024-11-24) - Remove references to deprecated ;trust script
---   v1.2.1 (2024-10-10) - Anchor regex comparisons and convert to_s
---   v1.2.0 (2024-07-22) - Add support for GSTest instance
---   v1.1.3 (2023-11-15) - Change to Process.spawn for ruby process launch
---   v1.1.2 (2023-03-28) - Switch to native CLI login method
---   v1.1.1 (2023-01-23) - Update for Ruby v3 compatibility
---   v1.1.0 (2022-02-01) - Fix for Wrayth login method, add Lich version check
---   v1.0.0 (2015-09-19) - Initial release

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local VALID_GAME_CODES = {
    GS3 = true, GSX = true, GSF = true, GST = true,
    DR = true, DRX = true, DRF = true, DRT = true,
}

local VALID_FRONTENDS = {
    stormfront = true, wizard = true, avalon = true,
}

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
    echo("  ;elogin <char> --custom-launch=<launcher>         # e.g., --custom-launch=warlock")
    echo("  ;elogin <char> --stormfront|--wizard|--avalon     # override frontend")
    echo("  ;elogin <char> --GST|--GSF|--GSX                  # override game instance")
    echo("  ;elogin add <char> <user_id> <password>")
    echo("  ;elogin modify <char> <user_id> <password>")
    echo("  ;elogin delete <char> <game_code> [frontend]")
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
    respond(string.format("%-15s %-15s %-8s %-12s", "Account", "Character", "Instance", "Frontend"))
    respond(string.rep("-", 52))
    for _, entry in ipairs(entries) do
        respond(string.format("%-15s %-15s %-8s %-12s",
            entry.user_id or "",
            entry.char_name or "",
            entry.game_code or "",
            entry.frontend or ""))
    end
    echo("Total: " .. #entries .. " entries")
end

local function add_entry(char_name, user_id, password, opts)
    opts = opts or {}
    local entries = load_entries()
    local realm = get_realm()
    local game_code = opts.game_code or (realm and realm_to_game_code(realm) or "GS3")
    local frontend = opts.frontend or nil
    local custom_launch = opts.custom_launch or nil
    local custom_launch_dir = opts.custom_launch_dir or nil

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
        game_name = "GemStone IV",
        user_id = user_id:lower(),
        password = password,
        frontend = frontend,
        custom_launch = custom_launch,
        custom_launch_dir = custom_launch_dir,
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
            -- Preserve all fields, only update password
            entries[i].password = password
            found = true
            break
        end
    end

    if not found then
        echo("Modify failed. No entry found for character: " .. char_name .. " with account: " .. user_id)
        echo("Existing characters:")
        for _, e in ipairs(entries) do
            echo("  " .. (e.char_name or "?") .. " (" .. (e.game_code or "?") .. ") - " .. (e.user_id or "?"))
        end
        return
    end

    save_entries(entries)
    echo("Successfully modified login entry for " .. char_name .. " with account " .. user_id .. ".")
end

local function delete_entry(char_name, game_code, frontend)
    local entries = load_entries()

    -- Find matching entries
    local matches = {}
    for i, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower()
           and e.game_code and e.game_code:upper() == game_code:upper() then
            matches[#matches + 1] = i
        end
    end

    if #matches == 0 then
        echo("Delete failed. No matching entry found for " .. char_name .. " (" .. game_code .. ").")
        return
    end

    -- If multiple matches and no frontend specified, require disambiguation
    if #matches > 1 and not frontend then
        echo("Delete failed. Multiple entries exist for " .. char_name .. " (" .. game_code .. "). Specify frontend to delete a precise record.")
        return
    end

    -- Filter by frontend if specified
    local new_entries = {}
    local deleted = false
    for _, e in ipairs(entries) do
        local should_delete = e.char_name and e.char_name:lower() == char_name:lower()
            and e.game_code and e.game_code:upper() == game_code:upper()
        if should_delete and frontend then
            should_delete = e.frontend and e.frontend:lower() == frontend:lower()
        end
        if should_delete then
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

--- Find character entries matching name and game code.
--- Supports flexible matching: tries exact game_code first, then falls back
--- to any entry matching the character name.
local function find_character(entries, char_name, game_code)
    -- Exact match on both name and game code
    local exact = {}
    for _, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower()
           and e.game_code and e.game_code == game_code then
            exact[#exact + 1] = e
        end
    end
    if #exact > 0 then return exact end

    -- Fallback: match by name only
    local by_name = {}
    for _, e in ipairs(entries) do
        if e.char_name and e.char_name:lower() == char_name:lower() then
            by_name[#by_name + 1] = e
        end
    end
    return by_name
end

--- Select the best-fit entry from a list of candidates.
--- Prefers: exact game_code match > first entry with a frontend > first entry
local function select_best_fit(candidates, game_code, frontend_pref)
    if #candidates == 0 then return nil end
    if #candidates == 1 then return candidates[1] end

    -- Prefer exact game code match
    for _, c in ipairs(candidates) do
        if c.game_code == game_code then
            if not frontend_pref or (c.frontend and c.frontend:lower() == frontend_pref:lower()) then
                return c
            end
        end
    end

    -- Prefer matching frontend
    if frontend_pref then
        for _, c in ipairs(candidates) do
            if c.frontend and c.frontend:lower() == frontend_pref:lower() then
                return c
            end
        end
    end

    -- Return first match
    return candidates[1]
end

local function do_login(char_name, opts)
    opts = opts or {}
    local entries = load_entries()
    local realm = get_realm()
    if not realm then
        echo("No realm set. Use ;elogin set realm <prime|platinum|shattered|test>")
        return
    end

    local realm_game_code = realm_to_game_code(realm)
    local game_code = opts.instance or realm_game_code

    -- Find the character with flexible matching
    local candidates = find_character(entries, char_name, game_code)

    if #candidates == 0 then
        echo("No matching entry found for " .. char_name .. " in realm " .. realm .. ".")
        return
    end

    local entry = select_best_fit(candidates, game_code, opts.frontend)
    if not entry then
        echo("No matching entry found for " .. char_name .. " in realm " .. realm .. ".")
        return
    end

    -- Determine effective settings
    local effective_instance = opts.instance or entry.game_code or game_code
    local effective_frontend = opts.frontend or entry.frontend
    local effective_custom_launch = opts.custom_launch or entry.custom_launch

    echo("Logging in as " .. entry.char_name .. " (" .. effective_instance .. ")...")
    echo("Account: " .. (entry.user_id or "unknown"))
    echo("Game code: " .. effective_instance)
    if effective_frontend then
        echo("Frontend: " .. effective_frontend)
    end
    if effective_custom_launch then
        echo("Custom launch: " .. effective_custom_launch)
    end
    if opts.scripts and #opts.scripts > 0 then
        echo("Startup scripts: " .. table.concat(opts.scripts, ", "))
    end

    -- TODO: Revenant native login spawning
    -- This requires engine support for spawning new sessions.
    -- The entry data is fully prepared; the engine needs an API like:
    --   Engine.spawn_session({
    --     account = entry.user_id,
    --     password = entry.password,
    --     game = effective_instance,
    --     character = entry.char_name,
    --     frontend = effective_frontend,
    --     custom_launch = effective_custom_launch,
    --     scripts = opts.scripts,
    --   })
    echo("Note: Automatic login spawning requires Revenant's native multi-session support.")
end

--------------------------------------------------------------------------------
-- Argument parsing
--------------------------------------------------------------------------------

local function parse_args()
    local raw_args = Script.vars[0] or ""
    local args = {}
    for word in raw_args:gmatch("%S+") do
        args[#args + 1] = word
    end

    if #args == 0 then return { command = "help" } end

    local cmd = args[1]:lower()

    if cmd == "help" then
        return { command = "help" }
    elseif cmd == "set" then
        if args[2] and args[2]:lower() == "realm" and args[3] then
            return { command = "set_realm", realm = args[3]:lower() }
        end
        return { command = "help" }
    elseif cmd == "add" then
        if #args >= 4 then
            local name = args[2]:sub(1,1):upper() .. args[2]:sub(2)
            return { command = "add", char_name = name, user_id = args[3], password = args[4] }
        end
        return { command = "help" }
    elseif cmd == "modify" then
        if #args >= 4 then
            local name = args[2]:sub(1,1):upper() .. args[2]:sub(2)
            return { command = "modify", char_name = name, user_id = args[3], password = args[4] }
        end
        return { command = "help" }
    elseif cmd == "list" then
        return { command = "list" }
    elseif cmd == "delete" then
        if #args >= 3 then
            return { command = "delete", char_name = args[2], game_code = args[3], frontend = args[4] }
        end
        return { command = "help" }
    else
        -- Login command: parse character name and flags
        local char_name = args[1]:sub(1,1):upper() .. args[1]:sub(2)
        local custom_launch = nil
        local frontend = nil
        local instance = nil
        local scripts = {}

        for i = 2, #args do
            local arg = args[i]
            -- --custom-launch=VALUE
            local cl = arg:match("^%-%-custom%-launch=(.+)$")
            if cl then
                custom_launch = cl
            -- --stormfront, --wizard, --avalon
            elseif arg:lower():match("^%-%-stormfront$") then
                frontend = "stormfront"
            elseif arg:lower():match("^%-%-wizard$") then
                frontend = "wizard"
            elseif arg:lower():match("^%-%-avalon$") then
                frontend = "avalon"
            -- --GAMECODE (e.g., --GST, --GSF, --GSX, --DR)
            elseif arg:match("^%-%-") then
                local flag = arg:sub(3):upper()
                if VALID_GAME_CODES[flag] then
                    instance = flag
                end
            else
                -- Scripts list (comma-separated)
                for s in arg:gmatch("[^,]+") do
                    scripts[#scripts + 1] = s:match("^%s*(.-)%s*$")
                end
            end
        end

        return {
            command = "login",
            char_name = char_name,
            custom_launch = custom_launch,
            frontend = frontend,
            instance = instance,
            scripts = scripts,
        }
    end
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local parsed = parse_args()

if parsed.command == "help" then
    show_usage()
elseif parsed.command == "set_realm" then
    local valid_realms = { prime = true, platinum = true, shattered = true, test = true }
    if valid_realms[parsed.realm] then
        set_realm(parsed.realm)
        echo("Realm set to " .. parsed.realm .. ".")
    else
        echo("Invalid realm. Use: prime, platinum, shattered, or test.")
    end
elseif parsed.command == "add" then
    add_entry(parsed.char_name, parsed.user_id, parsed.password)
elseif parsed.command == "modify" then
    modify_entry(parsed.char_name, parsed.user_id, parsed.password)
elseif parsed.command == "list" then
    list_entries()
elseif parsed.command == "delete" then
    delete_entry(parsed.char_name, parsed.game_code, parsed.frontend)
elseif parsed.command == "login" then
    do_login(parsed.char_name, {
        scripts = parsed.scripts,
        custom_launch = parsed.custom_launch,
        frontend = parsed.frontend,
        instance = parsed.instance,
    })
end
