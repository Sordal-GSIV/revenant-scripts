--- @revenant-script
--- name: inventory-buddy
--- version: 9.0.0
--- author: Dreaven
--- contributors: Tgo01
--- game: gs
--- description: Track inventory and locker contents across all characters with GUI browser
--- tags: inventory,locker,tracking,utility,gui
--- @lic-certified: complete 2026-03-20
---
--- Original Lich5 script by Dreaven (In game: Dreaven, Player's Corner: Tgo01,
--- Discord: Dreaven#6436, Email: LordDreaven@gmail.com)
--- Converted to Revenant Lua by elanthia-online contributors.
---
--- Changelog:
---   v9.0.0 - Converted to Revenant Lua; hook-based data capture; native Gui API
---   v9     - (Lich5) INV HANDS FULL for held items instead of GLANCE
---   v8     - (Lich5) Bug fix
---   v7     - (Lich5) Track character level, exp to level, exp to next TP
---   v6     - (Lich5) Characters sorted alphabetically in menu
---   v5     - (Lich5) reload command; fixed premium locker/manifest handling
---   v4     - (Lich5) Fixed locker manifest bugs
---   v3     - (Lich5) Multi-character search; marked/registered; bank/resource/ticket/exp tracking
---   v2     - (Lich5) Locker manifest support
---   v1     - (Lich5) Initial release
---
--- Usage:
---   ;inventory-buddy               -- start (leave running in background)
---   ;send inventory-buddy inv      -- open inventory browser window
---   ;send inventory-buddy update   -- update all info for this character and save
---   ;send inventory-buddy reload   -- save/reload database

local SCRIPT_NAME = Script.name
local DATA_FILE   = "inventory-buddy.json"
local HOOK_NAME   = SCRIPT_NAME .. "_data"

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local all_data      = {}
local save_all_data = true

-- Parser state machine
local STATE_IDLE       = "idle"
local STATE_INV        = "inv"        -- scanning main inventory (inv full)
local STATE_HANDS      = "hands"      -- scanning held items (inv hands full)
local STATE_LOCKER     = "locker"     -- scanning locker (LOOK IN LOCKER)
local STATE_LOCKER_MFT = "locker_mft" -- scanning locker manifest/recall
local STATE_BANKS      = "banks"      -- reading bank account output
local STATE_TICKETS    = "tickets"    -- reading ticket balance output

local parse_state          = STATE_IDLE
local locker_key           = nil  -- e.g. "Locker" or "Locker in Wehnimer's Landing"
local containers           = {}   -- container stack for inv parsing (1-based)
local last_container_index = 0    -- 0-based depth tracking

-- GUI state (nil when window is closed)
local gui_win        = nil
local gui_char_combo = nil
local gui_cont_combo = nil
local gui_inv_label  = nil
local gui_cur_char   = nil
local gui_cur_cont   = nil

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function add_commas(n)
    local s = tostring(n):gsub(",", "")
    if not s:match("^%-?%d+$") then return s end
    local rev = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return rev:match("^,?(.+)$") or rev
end

local function is_stat_key(k)
    return k == "Experience" or k == "Banks" or k == "Resources" or k == "Tickets"
end

local function is_locker_key(k)
    return k:sub(1, 6) == "Locker"
end

local function strip_marks(s)
    return s:gsub(" %(marked%)",""):gsub(" %(registered%)","")
end

-- Forward declarations (defined in GUI helpers section below)
local gui_get_char_names
local build_display_text

local function maybe_strip_marks(s)
    if all_data["Script Settings"] and all_data["Script Settings"]["Marked"] == "Yes" then
        return s
    end
    return strip_marks(s)
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local function load_all_info()
    if not File.exists(DATA_FILE) then return end
    local raw = File.read(DATA_FILE)
    if not raw or raw == "" then return end
    local ok, data = pcall(Json.decode, raw)
    if ok and type(data) == "table" then
        all_data = data
    else
        respond("[" .. SCRIPT_NAME .. "] Failed to parse save file: " .. tostring(data))
    end
end

local function save_data()
    if not save_all_data then return end
    -- Merge strategy: reload disk data first so other characters' entries are preserved.
    -- This mirrors the Ruby v3 flock approach (without OS-level locking).
    local char = Char.name
    if char and char ~= "" then
        local merged = {}
        if File.exists(DATA_FILE) then
            local raw = File.read(DATA_FILE)
            if raw and raw ~= "" then
                local ok2, d = pcall(Json.decode, raw)
                if ok2 and type(d) == "table" then merged = d end
            end
        end
        -- Overlay this character's current data and script settings
        if all_data[char] then merged[char] = all_data[char] end
        merged["Script Settings"] = all_data["Script Settings"]
        all_data = merged
    end
    local ok, encoded = pcall(Json.encode, all_data)
    if not ok then
        respond("[" .. SCRIPT_NAME .. "] Error encoding data: " .. tostring(encoded))
        return
    end
    File.write(DATA_FILE, encoded)
    respond("[" .. SCRIPT_NAME .. "] Data saved.")
    -- Refresh GUI if open
    if gui_char_combo then
        gui_char_combo:set_options(gui_get_char_names())
        if gui_cur_char then
            gui_char_combo:set_text(gui_cur_char)
        end
    end
    if gui_inv_label and gui_cur_char and gui_cur_cont then
        gui_inv_label:set_text(build_display_text(gui_cur_char, gui_cur_cont))
    end
end

--------------------------------------------------------------------------------
-- Data management
--------------------------------------------------------------------------------

local function ensure_script_settings()
    if not all_data["Script Settings"] then
        all_data["Script Settings"] = {}
    end
    for _, name in ipairs({ "Marked", "Save Option" }) do
        if all_data["Script Settings"][name] ~= "Yes" then
            all_data["Script Settings"][name] = "No"
        end
    end
end

local function start_container_hash()
    local char = Char.name
    ensure_script_settings()
    if not all_data[char] then
        all_data[char] = {}
    else
        -- Preserve only locker and stat data; clear inventory containers
        local keep = {}
        for k, v in pairs(all_data[char]) do
            if is_stat_key(k) or is_locker_key(k) then
                keep[k] = v
            end
        end
        all_data[char] = keep
    end
    all_data[char]["All Inventory"] = {}
    all_data[char]["Worn"]          = {}
    containers           = {}
    last_container_index = 0
    parse_state          = STATE_INV
end

local function auto_save()
    if save_all_data
       and all_data["Script Settings"]
       and all_data["Script Settings"]["Save Option"] == "Yes" then
        save_data()
    end
end

--------------------------------------------------------------------------------
-- Update everything
--------------------------------------------------------------------------------

local function update_everything()
    save_all_data = false
    local bar = string.rep("#", 80)
    respond(bar)
    respond("[" .. SCRIPT_NAME .. "] Starting full update.")
    respond("[" .. SCRIPT_NAME .. "] Avoid roundtime until update completes.")
    respond(bar)
    wait_until(function() return checkrt() == 0 end)
    put("inv full")
    pause(3)   -- inv full output can be lengthy
    put("bank account")
    pause(1)
    put("resource")
    pause(1)
    put("experience")
    pause(1)
    put("ticket balance")
    pause(2)   -- ticket output needs a moment to arrive
    respond(bar)
    respond("[" .. SCRIPT_NAME .. "] Update complete.")
    respond(bar)
    save_all_data = true
    save_data()
end

--------------------------------------------------------------------------------
-- GUI helpers
--------------------------------------------------------------------------------

gui_get_char_names = function()
    local names = { "All" }
    local chars = {}
    for k, _ in pairs(all_data) do
        if k ~= "Script Settings" then chars[#chars + 1] = k end
    end
    table.sort(chars)
    for _, n in ipairs(chars) do names[#names + 1] = n end
    return names
end

local function gui_get_container_names(char)
    if char == "All" then
        return { "Banks", "Experience", "Resources", "Tickets" }
    end
    local opts = { "All Inventory", "Stats" }
    local data = all_data[char]
    if data then
        -- Lockers first, sorted
        local lockers = {}
        for k, _ in pairs(data) do
            if is_locker_key(k) then lockers[#lockers + 1] = k end
        end
        table.sort(lockers)
        for _, k in ipairs(lockers) do opts[#opts + 1] = k end
        -- Then other inventory containers (not All Inventory, Worn, stat keys, locker keys)
        local others = {}
        for k, _ in pairs(data) do
            if k ~= "All Inventory" and k ~= "Worn"
               and not is_stat_key(k) and not is_locker_key(k) then
                others[#others + 1] = k
            end
        end
        table.sort(others)
        for _, k in ipairs(others) do opts[#opts + 1] = k end
    end
    return opts
end

build_display_text = function(char, container)
    if not char or not container then return "" end
    local lines = {}

    if container == "Stats" then
        -- Combined stats view for a single character
        local data = all_data[char]
        if not data then return "" end
        for _, sect in ipairs({ "Experience", "Banks", "Resources", "Tickets" }) do
            local d = data[sect]
            if d and next(d) then
                if sect == "Banks" then
                    lines[#lines + 1] = "Bank information:"
                    for bn, bv in pairs(d) do
                        lines[#lines + 1] = "  " .. bn .. ": " .. add_commas(bv)
                    end
                elseif sect == "Experience" then
                    lines[#lines + 1] = "Experience:"
                    for en, ev in pairs(d) do
                        lines[#lines + 1] = "  " .. en .. ": " .. add_commas(ev)
                    end
                elseif sect == "Resources" then
                    lines[#lines + 1] = "Resource information:"
                    for rn, rv in pairs(d) do
                        lines[#lines + 1] = "  " .. rn .. ": " .. add_commas(rv)
                    end
                elseif sect == "Tickets" then
                    lines[#lines + 1] = "Ticket information:"
                    for en, td in pairs(d) do
                        lines[#lines + 1] = "  " .. en .. ": "
                            .. add_commas(td["Ticket Value"] or 0)
                            .. " " .. (td["Ticket Name"] or "")
                    end
                end
                lines[#lines + 1] = ""
            end
        end

    elseif container == "Banks" then
        -- All characters' banks + grand total
        local totals = {}
        local grand  = 0
        local chars  = {}
        for c, _ in pairs(all_data) do
            if c ~= "Script Settings" then chars[#chars + 1] = c end
        end
        table.sort(chars)
        for _, c in ipairs(chars) do
            local d = all_data[c]
            if type(d) == "table" and d["Banks"] then
                lines[#lines + 1] = c .. ":"
                for bn, bv in pairs(d["Banks"]) do
                    lines[#lines + 1] = "  " .. bn .. ": " .. add_commas(bv)
                    if bn ~= "Total" then
                        totals[bn] = (totals[bn] or 0) + (tonumber(bv) or 0)
                        grand = grand + (tonumber(bv) or 0)
                    end
                end
                lines[#lines + 1] = ""
            end
        end
        lines[#lines + 1] = "Totals:"
        local bnames = {}
        for bn, _ in pairs(totals) do bnames[#bnames + 1] = bn end
        table.sort(bnames)
        for _, bn in ipairs(bnames) do
            lines[#lines + 1] = "  " .. bn .. ": " .. add_commas(totals[bn])
        end
        lines[#lines + 1] = "  Total: " .. add_commas(grand)

    elseif container == "Tickets" then
        -- All characters' tickets + totals
        local totals = {}
        local chars  = {}
        for c, _ in pairs(all_data) do
            if c ~= "Script Settings" then chars[#chars + 1] = c end
        end
        table.sort(chars)
        for _, c in ipairs(chars) do
            local d = all_data[c]
            if type(d) == "table" and d["Tickets"] and next(d["Tickets"]) then
                lines[#lines + 1] = c .. ":"
                for en, td in pairs(d["Tickets"]) do
                    lines[#lines + 1] = "  " .. en .. ": "
                        .. add_commas(td["Ticket Value"] or 0)
                        .. " " .. (td["Ticket Name"] or "")
                    if not totals[en] then
                        totals[en] = { value = 0, name = td["Ticket Name"] or "" }
                    end
                    totals[en].value = totals[en].value + (tonumber(td["Ticket Value"]) or 0)
                end
                lines[#lines + 1] = ""
            end
        end
        lines[#lines + 1] = "Totals:"
        local evts = {}
        for en, _ in pairs(totals) do evts[#evts + 1] = en end
        table.sort(evts)
        for _, en in ipairs(evts) do
            lines[#lines + 1] = "  " .. en .. ": "
                .. add_commas(totals[en].value) .. " " .. totals[en].name
        end

    elseif container == "Resources" then
        local chars = {}
        for c, _ in pairs(all_data) do
            if c ~= "Script Settings" then chars[#chars + 1] = c end
        end
        table.sort(chars)
        for _, c in ipairs(chars) do
            local d = all_data[c]
            if type(d) == "table" and d["Resources"] then
                lines[#lines + 1] = c .. ":"
                for rn, rv in pairs(d["Resources"]) do
                    lines[#lines + 1] = "  " .. rn .. ": " .. add_commas(rv)
                end
                lines[#lines + 1] = ""
            end
        end

    elseif container == "Experience" then
        local chars = {}
        for c, _ in pairs(all_data) do
            if c ~= "Script Settings" then chars[#chars + 1] = c end
        end
        table.sort(chars)
        for _, c in ipairs(chars) do
            local d = all_data[c]
            if type(d) == "table" and d["Experience"] then
                lines[#lines + 1] = c .. ":"
                for en, ev in pairs(d["Experience"]) do
                    lines[#lines + 1] = "  " .. en .. ": " .. add_commas(ev)
                end
                lines[#lines + 1] = ""
            end
        end

    else
        -- Regular inventory container
        local data = all_data[char]
        if data and data[container] then
            for _, item in ipairs(data[container]) do
                lines[#lines + 1] = item
            end
        end
    end

    return table.concat(lines, "\n")
end

-- Recursive search helpers (forward-declared for mutual recursion)
local search_inv_hash, search_inv_array

-- Patterns that indicate locker furniture holders (not real items)
local LOCKER_HOLDER_PATS = {
    "On a weapon rack:",
    "On an armor stand:",
    "In a clothing wardrobe:",
    "In a magical item bin:",
    "In a deep chest:",
    "There are no items in this locker",
}

local function is_locker_holder(s)
    for _, pat in ipairs(LOCKER_HOLDER_PATS) do
        if s:find(pat, 1, true) then return true end
    end
    return false
end

search_inv_hash = function(data, query, results, person, container)
    if type(data) ~= "table" then return end
    for item, value in pairs(data) do
        if type(value) == "table" then
            if #value > 0 then
                -- array-like: item is the container name
                search_inv_array(value, query, results, person, item)
            else
                -- hash-like: item becomes the new person context
                search_inv_hash(value, query, results, item, container)
            end
        elseif type(value) == "string" then
            if value:lower():find(query, 1, true) then
                if person and container and container ~= "All Inventory" then
                    results[#results + 1] = item .. " - " .. person .. " (" .. container .. ")"
                end
            end
        end
    end
end

search_inv_array = function(arr, query, results, person, container)
    for _, item in ipairs(arr) do
        if type(item) == "table" then
            search_inv_hash(item, query, results, person, container)
        elseif type(item) == "string" then
            if item:lower():find(query, 1, true) then
                if person and container and container ~= "All Inventory" then
                    results[#results + 1] = item .. " - " .. person .. " (" .. container .. ")"
                end
            end
        end
    end
end

local function do_search(item_query, char_query)
    item_query = trim(item_query):lower()
    char_query = trim(char_query)
    local results = {}

    if char_query ~= "" then
        local char = char_query:sub(1,1):upper() .. char_query:sub(2):lower()
        if all_data[char] then
            search_inv_hash({ [char] = all_data[char] }, item_query, results, nil, nil)
        else
            return nil, 'Character "' .. char .. '" not found.'
        end
    else
        search_inv_hash(all_data, item_query, results, nil, nil)
    end

    local lines = {}
    local count = 0
    for _, r in ipairs(results) do
        if not is_locker_holder(r) and r ~= "" then
            lines[#lines + 1] = trim(r)
            count = count + 1
        end
    end
    lines[#lines + 1] = count .. " items found"
    return table.concat(lines, "\n"), nil
end

--------------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------------

local function show_gui()
    if gui_win then return end

    local win  = Gui.window("Inventory Buddy", { width = 680, height = 620, resizable = true })
    local root = Gui.vbox()

    -- ── Row 1: character / container selectors and settings checkboxes ────────
    local top_row = Gui.hbox()
    local char_combo = Gui.editable_combo({
        hint    = "Character",
        options = gui_get_char_names(),
    })
    local cont_combo = Gui.editable_combo({
        hint    = "Container",
        options = {},
    })
    local marked_chk   = Gui.checkbox("Track Marked/Registered",
                            all_data["Script Settings"]["Marked"] == "Yes")
    local save_opt_chk = Gui.checkbox("Auto-Save on Update",
                            all_data["Script Settings"]["Save Option"] == "Yes")
    top_row:add(char_combo)
    top_row:add(cont_combo)
    top_row:add(marked_chk)
    top_row:add(save_opt_chk)
    root:add(top_row)

    -- ── Row 2: search ─────────────────────────────────────────────────────────
    local search_row = Gui.hbox()
    local item_search = Gui.input({ placeholder = "Item search..." })
    local char_search = Gui.input({ placeholder = "Character filter (blank = all)..." })
    search_row:add(Gui.label("Item:"))
    search_row:add(item_search)
    search_row:add(Gui.label("Character:"))
    search_row:add(char_search)
    root:add(search_row)

    -- ── Row 3: delete character ───────────────────────────────────────────────
    local del_row   = Gui.hbox()
    local del_entry = Gui.input({ placeholder = "Character name to delete" })
    local del_btn   = Gui.button("Delete Character")
    del_row:add(del_entry)
    del_row:add(del_btn)
    root:add(del_row)

    root:add(Gui.separator())

    -- ── Inventory display (scrollable label) ──────────────────────────────────
    local inv_label = Gui.label("")
    local scrolled  = Gui.scroll(inv_label)
    root:add(scrolled)

    win:set_root(root)

    -- Store widget references for use by save_data / hook refresh
    gui_win        = win
    gui_char_combo = char_combo
    gui_cont_combo = cont_combo
    gui_inv_label  = inv_label
    gui_cur_char   = nil
    gui_cur_cont   = nil

    -- ── Local helpers ─────────────────────────────────────────────────────────

    local function refresh_display()
        if gui_cur_char and gui_cur_cont then
            inv_label:set_text(build_display_text(gui_cur_char, gui_cur_cont))
        end
    end

    local function refresh_search()
        local iq = trim(item_search:get_text() or "")
        if iq == "" then
            refresh_display()
            return
        end
        local text, err = do_search(iq, char_search:get_text() or "")
        if err then
            inv_label:set_text(err)
        else
            inv_label:set_text(text or "")
        end
    end

    local function update_cont_combo(char)
        local opts = gui_get_container_names(char)
        cont_combo:set_options(opts)
        gui_cur_cont = opts[1]
        if gui_cur_cont then cont_combo:set_text(gui_cur_cont) end
        refresh_display()
    end

    -- ── Callbacks ─────────────────────────────────────────────────────────────

    char_combo:on_change(function(name)
        if not name or name == "" then return end
        gui_cur_char = name
        item_search:set_text("")
        char_search:set_text("")
        update_cont_combo(name)
    end)

    cont_combo:on_change(function(name)
        if not name or name == "" then return end
        gui_cur_cont = name
        item_search:set_text("")
        char_search:set_text("")
        refresh_display()
    end)

    item_search:on_change(function(_)
        refresh_search()
    end)

    char_search:on_change(function(_)
        if trim(item_search:get_text() or "") ~= "" then
            refresh_search()
        end
    end)

    marked_chk:on_change(function(checked)
        ensure_script_settings()
        all_data["Script Settings"]["Marked"] = checked and "Yes" or "No"
        save_data()
    end)

    save_opt_chk:on_change(function(checked)
        ensure_script_settings()
        all_data["Script Settings"]["Save Option"] = checked and "Yes" or "No"
        save_data()
    end)

    del_btn:on_click(function()
        local name = trim(del_entry:get_text() or "")
        if name == "" then
            respond("[" .. SCRIPT_NAME .. "] Enter the name of the character to delete.")
            return
        end
        -- Capitalize first letter
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        if all_data[name] then
            all_data[name] = nil
            del_entry:set_text("")
            char_combo:set_options(gui_get_char_names())
            inv_label:set_text("")
            gui_cur_char = nil
            gui_cur_cont = nil
            save_data()
            respond("[" .. SCRIPT_NAME .. "] " .. name .. " has been deleted.")
        elseif name == "" then
            respond("[" .. SCRIPT_NAME .. "] Enter the name of the character you want to delete.")
        else
            respond("[" .. SCRIPT_NAME .. "] " .. name .. " not found.")
        end
    end)

    win:on_close(function()
        gui_win        = nil
        gui_char_combo = nil
        gui_cont_combo = nil
        gui_inv_label  = nil
        gui_cur_char   = nil
        gui_cur_cont   = nil
    end)

    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Downstream hook: state-machine line processor
--------------------------------------------------------------------------------

local function process_line(line)
    local char = Char.name
    if not char or char == "" then return line end

    -- ── Inventory scan trigger ────────────────────────────────────────────────

    if line:find("^You are currently wearing:") then
        start_container_hash()
        return line
    end

    -- ── Active inventory / hands scanning ─────────────────────────────────────

    if parse_state == STATE_INV or parse_state == STATE_HANDS then

        -- 2-space indent: top-level worn item
        local sp, item = line:match("^(  )([A-Za-z].+)$")
        if sp and item then
            local clean = maybe_strip_marks(item)
            if parse_state == STATE_INV then
                all_data[char]["All Inventory"][#all_data[char]["All Inventory"] + 1] = sp .. clean
                -- Worn list stores the clean name without marks for container lookup
                all_data[char]["Worn"][#all_data[char]["Worn"] + 1] = strip_marks(item)
            else
                all_data[char]["All Inventory"][#all_data[char]["All Inventory"] + 1] = sp .. clean .. " (Held)"
            end
            -- Reset container stack for this new top-level item
            containers           = {}
            last_container_index = 0
            return line
        end

        -- 6+ space indent: item inside a container
        local spaces, nested = line:match("^(%s%s%s%s%s%s+)([A-Za-z].+)$")
        if spaces and nested then
            local nsp    = #spaces
            local clean  = maybe_strip_marks(nested)
            local raw    = strip_marks(nested)  -- for container-name storage
            all_data[char]["All Inventory"][#all_data[char]["All Inventory"] + 1] = spaces .. clean

            -- 0-based container depth index
            local ci = math.floor((nsp - 6) / 4)

            -- Sync container stack depth
            if last_container_index ~= ci then
                if last_container_index > ci then
                    for _ = 1, last_container_index - ci do
                        table.remove(containers)
                    end
                end
                last_container_index = ci
            end

            -- Determine container name at this depth (1-based Lua table)
            if containers[ci + 1] == nil then
                if ci == 0 then
                    -- Immediate child of the last worn item
                    local worn = all_data[char]["Worn"]
                    containers[1] = worn[#worn]
                else
                    -- Child of the previous container level
                    local parent = containers[ci]
                    if parent and all_data[char][parent] then
                        local plist = all_data[char][parent]
                        containers[ci + 1] = plist[#plist]
                    end
                end
                -- Deduplicate: if another key already contains this name, suffix it
                if containers[ci + 1] then
                    local cname = containers[ci + 1]
                    local count = 0
                    for k, _ in pairs(all_data[char]) do
                        if k:find(cname, 1, true) then count = count + 1 end
                    end
                    if count > 0 then
                        containers[ci + 1] = cname .. " " .. tostring(count + 1)
                    end
                end
            end

            local cname = containers[ci + 1]
            if cname then
                if not all_data[char][cname] or #all_data[char][cname] == 0 then
                    all_data[char][cname] = {}
                    -- Note which parent container holds this one
                    if ci > 0 and containers[ci] then
                        all_data[char][cname][1] = "This container is inside of " .. containers[ci]
                    end
                end
                all_data[char][cname][#all_data[char][cname] + 1] = raw
            end
            return line
        end

        -- End of wearing section (Items: N) — transition to hands scan
        if line:find("^%(Items: ") then
            if parse_state == STATE_INV then
                parse_state = STATE_HANDS
                put("inv hands full")
            else
                -- STATE_HANDS: scan complete
                parse_state = STATE_IDLE
                auto_save()
            end
            return line
        end

        -- No worn items — jump straight to hands
        if parse_state == STATE_INV and line:find("^You are carrying nothing at this time%.") then
            all_data[char]["Worn"] = { "NOTHING" }
            parse_state = STATE_HANDS
            put("inv hands full")
            return line
        end

        -- No held items
        if parse_state == STATE_HANDS and line:find("You are holding nothing at this time%.") then
            parse_state = STATE_IDLE
            auto_save()
            return line
        end
    end

    -- ── Locker: direct LOOK IN LOCKER output ─────────────────────────────────

    if line:find("^In the locker:") then
        all_data[char] = all_data[char] or {}
        all_data[char]["Locker"] = {}
        locker_key  = "Locker"
        parse_state = STATE_LOCKER
        return line
    end

    if parse_state == STATE_LOCKER then
        -- Format: "<holder description> [N]: item1, item2 (qty), ..."
        if line:match(".+ %[%d+%]: ") then
            local items_str = line:gsub("^.+ %[%d+%]: ", "")
            for item in items_str:gmatch("([^,]+)") do
                item = trim(item)
                if item ~= "" then
                    local base, qty = item:match("^(.+) %((%d+)%)$")
                    if base then
                        -- Quantity-stacked item
                        local n    = tonumber(qty) or 1
                        local keep = maybe_strip_marks(base)
                        for _ = 1, n do
                            all_data[char]["Locker"][#all_data[char]["Locker"] + 1] = keep
                        end
                    else
                        all_data[char]["Locker"][#all_data[char]["Locker"] + 1] = maybe_strip_marks(item)
                    end
                end
            end
        elseif line:find("^Total items:") then
            parse_state = STATE_IDLE
            save_data()
        end
        return line
    end

    -- ── Locker: single-line "In the locker you see ..." ──────────────────────

    if line:find("^In the locker you see ") then
        all_data[char] = all_data[char] or {}
        all_data[char]["Locker"] = {}
        local rest = line:gsub("^In the locker you see ", ""):gsub("%.$", "")
        -- Normalise "X and Y" → "X, Y" so the comma splitter handles 2-item lockers
        rest = rest:gsub(" and ", ", ")
        for item in rest:gmatch("[^,]+") do
            item = trim(item)
            if item ~= "" then
                all_data[char]["Locker"][#all_data[char]["Locker"] + 1] = maybe_strip_marks(item)
            end
        end
        save_data()
        return line
    end

    -- ── Locker: manifest / recall view ───────────────────────────────────────

    local town = line:match("^Looking in front of you, you see the contents of your locker in (.-):")
               or line:match("^Thinking back, you recall the contents of your locker in (.-):")
    if town then
        all_data[char]           = all_data[char] or {}
        locker_key               = "Locker in " .. town
        all_data[char][locker_key] = {}
        parse_state              = STATE_LOCKER_MFT
        return line
    end

    if parse_state == STATE_LOCKER_MFT then
        if line:find("^Obvious items:") or line:find("^Obvious exits:") then
            parse_state = STATE_IDLE
            save_data()
        elseif line:find("There are no items in this locker%.") then
            all_data[char][locker_key][#all_data[char][locker_key] + 1] = line
            parse_state = STATE_IDLE
            save_data()
        else
            all_data[char][locker_key][#all_data[char][locker_key] + 1] = maybe_strip_marks(line)
        end
        return line
    end

    -- ── Experience ───────────────────────────────────────────────────────────

    local level = line:match("^Level: (%d+)")
    if level then
        all_data[char] = all_data[char] or {}
        all_data[char]["Experience"] = all_data[char]["Experience"] or {}
        all_data[char]["Experience"]["Level"] = level
        return line
    end

    local total_exp = line:match("Total Exp: (.-)%s+Death's Sting:")
                   or line:match("Total Exp:%s*([%d,]+)")
    if total_exp then
        all_data[char] = all_data[char] or {}
        all_data[char]["Experience"] = all_data[char]["Experience"] or {}
        all_data[char]["Experience"]["Total Experience"] = total_exp:gsub(",", "")
        return line
    end

    local until_lvl = line:match("Exp until lvl: ([%d,]+)")
                   or line:match("Exp to next TP: ([%d,]+)")
    if until_lvl then
        all_data[char] = all_data[char] or {}
        all_data[char]["Experience"] = all_data[char]["Experience"] or {}
        all_data[char]["Experience"]["Until Level/Next TP"] = until_lvl:gsub(",", "")
        auto_save()
        return line
    end

    -- ── Banks ────────────────────────────────────────────────────────────────

    if line:find("^You currently have the following amounts on deposit:") then
        all_data[char] = all_data[char] or {}
        all_data[char]["Banks"] = {}
        parse_state = STATE_BANKS
        return line
    end

    if parse_state == STATE_BANKS then
        local bank_name, bank_val = line:match("^(.+): ([%d,]+)$")
        if bank_name then
            bank_name = trim(bank_name)
            all_data[char]["Banks"][bank_name] = bank_val:gsub(",", "")
            if bank_name:find("Total") then
                parse_state = STATE_IDLE
                auto_save()
            end
        elseif line:find("You currently have no open bank accounts%.") then
            parse_state = STATE_IDLE
            auto_save()
        end
        return line
    end

    -- ── Resources ────────────────────────────────────────────────────────────

    local weekly, total_r = line:match(".-: ([%d,]+)/50,000 %(Weekly%)%s+([%d,]+)/200,000 %(Total%)")
    if weekly and total_r then
        all_data[char] = all_data[char] or {}
        all_data[char]["Resources"] = {
            ["Weekly"] = weekly:gsub(",", ""),
            ["Total"]  = total_r:gsub(",", ""),
        }
        auto_save()
        return line
    end

    -- ── Tickets ──────────────────────────────────────────────────────────────

    if line:find("You take a moment to recall the alternative currencies you've collected%.%.%.") then
        all_data[char] = all_data[char] or {}
        all_data[char]["Tickets"] = {}
        parse_state = STATE_TICKETS
        return line
    end

    if parse_state == STATE_TICKETS then
        -- Prompt tag signals end of ticket output
        if line:find("<prompt", 1, true) then
            parse_state = STATE_IDLE
            auto_save()
        else
            -- "Event Name - 150 deeds." or "Event Name - 150 ticket name."
            local evt, val, tname = line:match("^(..-) %- (%d[%d,]*) (.+)%.$")
            if evt and val and tname then
                all_data[char]["Tickets"][trim(evt)] = {
                    ["Ticket Value"] = val:gsub(",", ""),
                    ["Ticket Name"]  = tname,
                }
            end
        end
        return line
    end

    return line
end

--------------------------------------------------------------------------------
-- Startup banner
--------------------------------------------------------------------------------

local function print_banner()
    local bar = string.rep("#", 80)
    respond(bar)
    respond("[" .. SCRIPT_NAME .. "] Leave running in background to keep database up to date.")
    respond("[" .. SCRIPT_NAME .. "] ;send " .. SCRIPT_NAME .. " inv    -- open inventory browser")
    respond("[" .. SCRIPT_NAME .. "] ;send " .. SCRIPT_NAME .. " update -- update all info and save")
    respond("[" .. SCRIPT_NAME .. "] ;send " .. SCRIPT_NAME .. " reload -- save/reload database")
    respond("[" .. SCRIPT_NAME .. "] Database updates when you use INV FULL or look in your locker.")
    respond(bar)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

load_all_info()
ensure_script_settings()

-- Warm up character data structure (without starting a scan)
local _char = Char.name
if _char and _char ~= "" then
    if not all_data[_char] then
        all_data[_char] = {}
    end
    all_data[_char]["All Inventory"] = all_data[_char]["All Inventory"] or {}
    all_data[_char]["Worn"]          = all_data[_char]["Worn"]          or {}
end

-- Register downstream hook for data capture
DownstreamHook.add(HOOK_NAME, process_line)

-- Cleanup on exit
before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    if gui_win then
        pcall(function() gui_win:close() end)
    end
end)

print_banner()

-- Initial full update to populate the database
update_everything()

--------------------------------------------------------------------------------
-- Main command loop
--------------------------------------------------------------------------------

while true do
    local cmd = get()

    -- Skip prompt-only lines and empty lines
    if cmd == "" or cmd:find("<prompt", 1, true) then
        -- nothing

    elseif cmd == "inv" then
        -- Open inventory browser (blocks until window is closed)
        if not gui_win then
            show_gui()
        end

    elseif cmd == "update" then
        -- Full update: resend all tracking commands
        update_everything()

    elseif cmd == "reload" then
        -- Save current data and reload
        save_data()

    end
end
