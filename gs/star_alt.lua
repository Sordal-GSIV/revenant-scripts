--- @revenant-script
--- name: star_alt
--- version: 2.0.0
--- author: unknown
--- game: gs
--- description: Track character alts with formatted table display and find integration
--- tags: utility, alts, tracking
--- @lic-certified: complete 2026-03-20
---
--- Ported from star-alt.lic (elanthia-online/scripts community)
--- No explicit author credited in original source
---
--- changelog:
---   2.0.0 (2026-03-20)
---     Full rewrite: JSON-serialized CharSettings (required by star_watch integration),
---     formatted table display, find-all with result capture + main annotation,
---     ensure_star_watch_running, duplicate checks, proper error messages,
---     multi-word format_name, notes alias, notes in display_entry.
---   1.0.0 - Initial stub
---
--- Usage:
---   ;star_alt list [name]          - List all or a specific character's roster
---   ;star_alt add <main> [alts...] - Add a main and optionally alts
---   ;star_alt remove <main> <alt>  - Remove an alt
---   ;star_alt removemain <main>    - Remove a main and all their alts
---   ;star_alt note <name> <note>   - Add a note for a character
---   ;star_alt find <name>          - See if that character is online
---   ;star_alt find all             - See who's online from all saved characters
---   ;star_alt reset                - Reset all data (use with caution!)
---   ;star_alt <name>               - Look up a character's roster
---   ;star_alt help                 - Show this help

-- Column widths for the full table display
local W_MAIN  = 12
local W_ALTS  = 18
local W_NOTES = 30

-- ============================================================
-- Data layer: JSON-serialized CharSettings
-- star_watch.lua reads CharSettings.main_alts expecting JSON:
--   {"MainChar": ["Alt1", "Alt2"]}
-- Notes are stored separately in CharSettings.notes.
-- ============================================================

local function load_main_alts()
    local raw = CharSettings.main_alts
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    if not ok or type(t) ~= "table" then return {} end
    return t
end

local function load_notes()
    local raw = CharSettings.notes
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    if not ok or type(t) ~= "table" then return {} end
    return t
end

local function save_main_alts(t)
    CharSettings.main_alts = Json.encode(t)
end

local function save_notes(t)
    CharSettings.notes = Json.encode(t)
end

-- ============================================================
-- Helpers
-- ============================================================

-- Capitalize the first letter of each word (handles multi-word names).
-- "john smith" -> "John Smith", "STARSWORN" -> "Starsworn"
local function format_name(name)
    if not name or name == "" then return "" end
    return (tostring(name):gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

-- Word-wrap text to fit within width, returning a table of lines.
local function wrap_text(text, width)
    if not text or text == "" then return {""} end
    local out, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            table.insert(out, line)
            line = word
        end
    end
    if line ~= "" then table.insert(out, line) end
    if #out == 0 then table.insert(out, "") end
    return out
end

-- Right-pad (or truncate) s to exactly n characters.
local function pad_right(s, n)
    s = tostring(s or "")
    if #s > n then return s:sub(1, n) end
    return s .. (" "):rep(n - #s)
end

-- Given a name that may be a main or an alt, return the canonical main, or nil.
local function resolve_main(name, main_alts)
    local n  = format_name(name)
    if main_alts[n] then return n end
    local nl = n:lower()
    for main, alts in pairs(main_alts) do
        for _, alt in ipairs(alts) do
            if tostring(alt):lower() == nl then return main end
        end
    end
    return nil
end

-- ============================================================
-- Ensure star-watch is running
-- ============================================================

local function ensure_star_watch_running()
    local ok, running = pcall(Script.running, "star_watch")
    if ok and running then return end
    local started, err = pcall(Script.run, "star_watch")
    if not started then
        echo("star-alt: couldn't auto-start star_watch (" .. tostring(err) .. "). Run ;star_watch manually if needed.")
    end
end

ensure_star_watch_running()

-- ============================================================
-- List
-- ============================================================

local function list_alts(name)
    local main_alts = load_main_alts()
    local notes     = load_notes()

    if next(main_alts) == nil then
        echo("No alts have been added yet.")
        return
    end

    -- Single-entry lookup: print roster + note for one name
    if name then
        local main = resolve_main(name, main_alts)
        if not main then
            echo(format_name(name) .. " does not exist.")
            return
        end
        local alts = main_alts[main] or {}
        local roster = {main}
        for _, a in ipairs(alts) do table.insert(roster, a) end
        echo("Characters for " .. main .. ": " .. table.concat(roster, ", "))
        local note = (notes[main] or ""):match("^%s*(.-)%s*$")
        if note ~= "" then echo("Notes: " .. note) end
        return
    end

    -- Full formatted table
    local border = "+-" .. ("-"):rep(W_MAIN) .. "-+-" .. ("-"):rep(W_ALTS) .. "-+-" .. ("-"):rep(W_NOTES) .. "-+"
    echo(border)
    echo("| " .. pad_right("Main", W_MAIN) .. " | " .. pad_right("Alts", W_ALTS) .. " | " .. pad_right("Notes", W_NOTES) .. " |")
    echo(border)

    local sorted_mains = {}
    for m in pairs(main_alts) do table.insert(sorted_mains, m) end
    table.sort(sorted_mains)

    for _, main in ipairs(sorted_mains) do
        local raw_alts   = main_alts[main] or {}
        local note       = (notes[main] or ""):match("^%s*(.-)%s*$")
        local alt_lines  = #raw_alts > 0 and raw_alts or {""}
        local note_lines = wrap_text(note, W_NOTES)
        local max_rows   = math.max(#alt_lines, #note_lines)

        for i = 1, max_rows do
            local main_cell = (i == 1) and main or ""
            local alt_cell  = tostring(alt_lines[i] or "")
            local note_cell = note_lines[i] or ""
            local alt_wrapped = wrap_text(alt_cell, W_ALTS)

            if #alt_wrapped > 1 then
                echo("| " .. pad_right(main_cell, W_MAIN) .. " | " .. pad_right(alt_wrapped[1], W_ALTS) .. " | " .. pad_right(note_cell, W_NOTES) .. " |")
                for j = 2, #alt_wrapped do
                    echo("| " .. pad_right("", W_MAIN) .. " | " .. pad_right(alt_wrapped[j], W_ALTS) .. " | " .. pad_right("", W_NOTES) .. " |")
                end
            else
                echo("| " .. pad_right(main_cell, W_MAIN) .. " | " .. pad_right(alt_cell, W_ALTS) .. " | " .. pad_right(note_cell, W_NOTES) .. " |")
            end
        end
    end

    echo(border)
end

-- ============================================================
-- Mutators
-- ============================================================

local function add_alt(main_name, alt_name)
    main_name = format_name(main_name)
    local main_alts = load_main_alts()
    main_alts[main_name] = main_alts[main_name] or {}

    if alt_name then
        alt_name = format_name(alt_name)
        for _, existing in ipairs(main_alts[main_name]) do
            if existing == alt_name then
                echo(alt_name .. " is already an alt of " .. main_name .. ".")
                return
            end
        end
        table.insert(main_alts[main_name], alt_name)
        save_main_alts(main_alts)
        echo("Added " .. alt_name .. " as an alt of " .. main_name .. ".")
    else
        save_main_alts(main_alts)
        echo("Added " .. main_name .. " as a main character.")
    end
end

local function remove_alt(main_name, alt_name)
    main_name = format_name(main_name)
    alt_name  = format_name(alt_name)
    local main_alts = load_main_alts()
    local alts = main_alts[main_name]
    if not alts then
        echo(main_name .. " does not exist.")
        return
    end
    for i, v in ipairs(alts) do
        if v == alt_name then
            table.remove(alts, i)
            save_main_alts(main_alts)
            echo("Removed " .. alt_name .. " from the alts of " .. main_name .. ".")
            return
        end
    end
    echo(alt_name .. " is not an alt of " .. main_name .. ".")
end

local function remove_main(main_name)
    main_name = format_name(main_name)
    local main_alts = load_main_alts()
    if not main_alts[main_name] then
        echo(main_name .. " does not exist.")
        return
    end
    main_alts[main_name] = nil
    save_main_alts(main_alts)
    local notes = load_notes()
    notes[main_name] = nil
    save_notes(notes)
    echo("Removed " .. main_name .. " and all their alts.")
end

local function reset_alts()
    save_main_alts({})
    save_notes({})
    echo("Reset all main and alt information.")
end

local function add_note(name, note)
    name = format_name(name)
    local notes = load_notes()
    notes[name] = note
    save_notes(notes)
    echo("Added note to " .. name .. ": " .. note)
end

-- ============================================================
-- Display
-- ============================================================

local function display_entry(name)
    local main_alts = load_main_alts()
    local notes     = load_notes()
    local main = resolve_main(name, main_alts)
    if not main then
        echo(format_name(name) .. " does not exist.")
        return
    end
    local alts = main_alts[main] or {}
    local alt_str = #alts > 0 and table.concat(alts, ", ") or "(none)"
    echo("Main: " .. main .. " - Alts: " .. alt_str)
    local note = (notes[main] or ""):match("^%s*(.-)%s*$")
    if note ~= "" then echo("Notes: " .. note) end
end

-- ============================================================
-- Find
-- ============================================================

local function find_character(name)
    local main_alts = load_main_alts()
    local main = resolve_main(name, main_alts)
    if not main then
        echo(format_name(name) .. " does not exist.")
        return
    end
    local names_to_find = {main}
    for _, a in ipairs(main_alts[main] or {}) do
        table.insert(names_to_find, a)
    end
    fput("find " .. table.concat(names_to_find, " "))
end

-- Issue a "find" command and capture the response via a downstream hook.
-- Lines that are purely alphabetic (individual found names) are collected and
-- squelched from the client window. Returns a list of found name strings.
local function capture_find_results(group)
    local captured   = {}
    local done_flag  = false
    local hook_id    = "star_alt_find_capture"

    before_dying(function() DownstreamHook.remove(hook_id) end)

    DownstreamHook.add(hook_id, function(line)
        if line:match("Brave Adventurer") or line:match("There are no adventurers") then
            done_flag = true
            return nil  -- squelch terminator
        elseif not done_flag and line:match("^%s*[A-Za-z]+%s*$") then
            local name = line:match("^%s*(.-)%s*$")
            if name and #name > 0 then
                table.insert(captured, name)
            end
            return nil  -- squelch individual name lines
        end
        return line
    end)

    put("find " .. table.concat(group, " "))
    local deadline = os.time() + 5
    wait_until(function() return done_flag or os.time() > deadline end)
    pause(0.1)
    DownstreamHook.remove(hook_id)
    return captured
end

local function find_all_characters()
    local main_alts = load_main_alts()
    if next(main_alts) == nil then
        echo("No characters saved.")
        return
    end

    -- Collect all unique names and build a reverse map: lowercased name -> main
    local all_names    = {}
    local name_to_main = {}

    for main, alts in pairs(main_alts) do
        if not name_to_main[main:lower()] then
            table.insert(all_names, main)
        end
        name_to_main[main:lower()] = main  -- main maps to itself

        for _, alt in ipairs(alts) do
            local a = tostring(alt):match("^%s*(.-)%s*$")
            if a and #a > 0 and not name_to_main[a:lower()] then
                table.insert(all_names, a)
                name_to_main[a:lower()] = main
            end
        end
    end

    -- Issue find commands in batches of 9 (matching original behavior)
    local found_adventurers = {}
    local i = 1
    while i <= #all_names do
        local group = {}
        for j = i, math.min(i + 8, #all_names) do
            table.insert(group, all_names[j])
        end
        i = i + 9

        local results = capture_find_results(group)
        for _, found_name in ipairs(results) do
            local main_of = name_to_main[found_name:lower()]
            -- Annotate alts with their main; mains need no annotation
            if main_of and main_of:lower() ~= found_name:lower() then
                table.insert(found_adventurers, found_name .. " (" .. main_of .. ")")
            else
                table.insert(found_adventurers, found_name)
            end
        end

        if i <= #all_names then pause(0.5) end
    end

    -- Deduplicate results
    local seen, unique = {}, {}
    for _, n in ipairs(found_adventurers) do
        if not seen[n] then
            seen[n] = true
            table.insert(unique, n)
        end
    end

    if #unique == 0 then
        echo("No adventurers questing from your list.")
    else
        echo("Brave Adventurers Questing: " .. table.concat(unique, ", "))
    end
end

-- ============================================================
-- Arg dispatch
-- ============================================================

local args = Script.vars
local cmd  = args[1]

if cmd == "list" then
    list_alts(args[2])

elseif cmd == "add" then
    if args[2] then
        local main     = args[2]
        local has_alts = false
        local i        = 3
        while args[i] do
            add_alt(main, args[i])
            has_alts = true
            i = i + 1
        end
        if not has_alts then add_alt(main) end
    else
        echo("Usage: ;star_alt add <main> [<alt> ...]")
    end

elseif cmd == "remove" then
    if args[2] and args[3] then
        remove_alt(args[2], args[3])
    else
        echo("Usage: ;star_alt remove <main> <alt>")
    end

elseif cmd == "removemain" then
    if args[2] then
        remove_main(args[2])
    else
        echo("Usage: ;star_alt removemain <main>")
    end

elseif cmd == "note" or cmd == "notes" then
    if args[2] and args[3] then
        local parts = {args[3]}
        local i = 4
        while args[i] do table.insert(parts, args[i]); i = i + 1 end
        add_note(args[2], table.concat(parts, " "))
    else
        echo("Usage: ;star_alt note <name> <note>")
    end

elseif cmd == "reset" then
    reset_alts()

elseif cmd == "find" then
    if args[2] == "all" then
        find_all_characters()
    elseif args[2] then
        find_character(args[2])
    else
        echo("Usage: ;star_alt find <name> | find all")
    end

elseif cmd == nil or cmd == "help" then
    echo("Usage: ;star_alt list | list <name> | add <main> [<alt> ...] | remove <main> <alt> | removemain <main> | note <name> <note> | find <name> | find all | reset")

else
    -- Bare name lookup: ;star_alt Tatterclaws
    display_entry(cmd)
end
