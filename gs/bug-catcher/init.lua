--- @revenant-script
--- name: bug-catcher
--- version: 1.5.0
--- author: Timbalt
--- description: Bug catching automation with GUI — find, catch, and collect bugs from jars
--- game: gs
--- @lic-certified: complete 2026-03-19
---
--- Port of bug-catcher.lic v1.5 by Timbalt
--- Original: Lich5 GTK3 GUI script for catching bugs from jars
---
--- Usage:
---   ;bug-catcher
---   - Go to Settings tab first and configure jar noun, jarsack, bugsack
---   - Go to Bug Catcher tab, search/select a bug, set count, click Start
---   - Script navigates to closest bug room, catches bugs, returns to start room
---
--- Changelog (from Lich5):
---   v1.5 — nearby towns filter, whisper options (paper/gem/candy), search dropdown

local bugs_data = require("bug-catcher/bugs_data")

----------------------------------------------------------------------
-- Nearby-town map (same as original)
----------------------------------------------------------------------
local NEARBY_TOWNS = {
    ["Wehnimer's Landing"]  = { "Wehnimer's Landing", "Solhaven", "Icemule Trace", "the Red Forest" },
    ["Solhaven"]            = { "Solhaven", "Wehnimer's Landing", "Icemule Trace", "the Red Forest" },
    ["River's Rest"]        = { "River's Rest" },
    ["Icemule Trace"]       = { "Icemule Trace", "Wehnimer's Landing", "Solhaven", "the Red Forest" },
    ["the Red Forest"]      = { "the Red Forest", "Ta'Vaalor", "Ta'Illistim", "Cysaegir" },
    ["Ta'Vaalor"]           = { "Ta'Vaalor", "Ta'Illistim", "Cysaegir", "the Red Forest" },
    ["Ta'Illistim"]         = { "Ta'Illistim", "Ta'Vaalor", "Cysaegir", "the Red Forest" },
    ["Cysaegir"]            = { "Cysaegir", "Ta'Vaalor", "Ta'Illistim", "the Red Forest" },
}

----------------------------------------------------------------------
-- Build flat bugs list from data
----------------------------------------------------------------------
local function build_bugs_list()
    local list = {}
    for town, bugs in pairs(bugs_data) do
        for _, bug in ipairs(bugs) do
            table.insert(list, {
                name  = bug.name,
                noun  = bug.noun,
                town  = town,
                rooms = bug.rooms,
            })
        end
    end
    -- Sort by town then name for consistent ordering
    table.sort(list, function(a, b)
        if a.town == b.town then return a.name < b.name end
        return a.town < b.town
    end)
    return list
end

local bugs_list = build_bugs_list()

----------------------------------------------------------------------
-- Get current town from room location
----------------------------------------------------------------------
local function get_current_town()
    local room = Room.current()
    if not room or not room.location then return nil end
    -- Strip common prefixes like "the town of", "the village of", etc.
    local loc = room.location
    loc = Regex.replace("^(?:the town of|the village of|the isle of|the Isle of|the city of)\\s+", loc, "")
    return loc
end

----------------------------------------------------------------------
-- Check if a town is "nearby" the current location
----------------------------------------------------------------------
local function get_nearby_towns()
    local current = get_current_town()
    if not current then return nil end
    local nearby = NEARBY_TOWNS[current]
    if nearby then return nearby end
    -- Fallback: just current town
    return { current }
end

----------------------------------------------------------------------
-- Filter bugs list by search text and nearby towns
----------------------------------------------------------------------
local function filter_bugs(filter_text, nearby)
    local grouped = {}
    local order = {}
    local lower_filter = string.lower(filter_text or "")

    for _, bug in ipairs(bugs_list) do
        if not bug.name then goto continue end

        -- Filter by nearby towns if available
        if nearby then
            local found = false
            for _, t in ipairs(nearby) do
                if bug.town == t then found = true; break end
            end
            if not found then goto continue end
        end

        -- Filter by search text
        if lower_filter ~= "" and not string.find(string.lower(bug.name), lower_filter, 1, true) then
            goto continue
        end

        if not grouped[bug.town] then
            grouped[bug.town] = {}
            table.insert(order, bug.town)
        end
        table.insert(grouped[bug.town], bug)

        ::continue::
    end

    table.sort(order)
    return grouped, order
end

----------------------------------------------------------------------
-- Find bug data by name
----------------------------------------------------------------------
local function find_bug_by_name(name)
    for _, bug in ipairs(bugs_list) do
        if bug.name == name then return bug end
    end
    return nil
end

----------------------------------------------------------------------
-- Core: find and collect bugs
----------------------------------------------------------------------
local function find_and_collect_bug(bug_name, count, whisper_options, status_label)
    local jar_noun = CharSettings.bugs_jar_noun
    local jarsack  = CharSettings.bugs_jarsack
    local bugsack  = CharSettings.bugs_bugsack

    if not jar_noun or jar_noun == "" or not jarsack or jarsack == "" or not bugsack or bugsack == "" then
        status_label:set_text("Error: Set jar noun, jarsack, and bugsack in Settings tab.")
        return
    end

    local return_room = Room.current() and Room.current().id

    -- Navigate to bug room if known
    local bug_data = find_bug_by_name(bug_name)
    if bug_data and bug_data.rooms and #bug_data.rooms > 0 then
        local current_id = return_room or 0
        local closest = bug_data.rooms[1]
        local closest_dist = math.abs(closest - current_id)
        for _, room_id in ipairs(bug_data.rooms) do
            local dist = math.abs(room_id - current_id)
            if dist < closest_dist then
                closest = room_id
                closest_dist = dist
            end
        end
        status_label:set_text("Traveling to room " .. tostring(closest) .. "...")
        Script.run("go2", tostring(closest))
        wait_while(function() return running("go2") end)
        pause(1)
    end

    -- Make sure jar is in hand
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    local has_jar = (lh and lh.noun == jar_noun) or (rh and rh.noun == jar_noun)
    if not has_jar then
        fput("get my " .. jar_noun .. " from my " .. jarsack)
        pause(1)
        lh = GameObj.left_hand()
        rh = GameObj.right_hand()
        has_jar = (lh and lh.noun == jar_noun) or (rh and rh.noun == jar_noun)
        if not has_jar then
            status_label:set_text("Error: Jar not found in jarsack!")
            return
        end
    end

    local caught = 0
    while caught < count do
        status_label:set_text("Hunting '" .. bug_name .. "'\n   (" .. tostring(caught + 1) .. "/" .. tostring(count) .. ")")

        -- Peer into jar until we find the target bug
        while true do
            local result = dothistimeout("peer " .. jar_noun, 5, ".")
            if result and string.find(result, bug_name, 1, true) then
                status_label:set_text("Found '" .. bug_name .. "'\n   (" .. tostring(caught + 1) .. "/" .. tostring(count) .. ")")
                break
            end
            pause(0.1)
        end

        fput("shake " .. jar_noun)
        pause(2)

        -- Apply whisper options
        for _, opt in ipairs(whisper_options) do
            fput("whisper my " .. jar_noun .. " option " .. opt)
            pause(2)
        end

        fput("pluck " .. jar_noun)
        pause(2)

        -- Find the bug in hand
        lh = GameObj.left_hand()
        rh = GameObj.right_hand()
        local bug_obj = nil
        for _, obj in ipairs({ lh, rh }) do
            if obj then
                local obj_lower = string.lower(obj.noun)
                local bug_lower = string.lower(bug_name)
                if string.find(bug_lower, obj_lower, 1, true) or string.find(obj_lower, bug_lower, 1, true) then
                    bug_obj = obj
                    break
                end
            end
        end

        if bug_obj then
            fput("put my " .. bug_obj.noun .. " in my " .. bugsack)
        else
            status_label:set_text("Error: No bug in hand")
            -- Stow jar before returning
            fput("put my " .. jar_noun .. " in my " .. jarsack)
            return
        end

        caught = caught + 1
        status_label:set_text("'" .. bug_name .. "' collected\n   (" .. tostring(caught) .. "/" .. tostring(count) .. ")")
        pause(1)
    end

    status_label:set_text("All " .. bug_name .. "'s caught\n   " .. tostring(caught) .. "/" .. tostring(count))
    fput("put my " .. jar_noun .. " in my " .. jarsack)
    pause(1)

    -- Return to starting room
    if return_room then
        Script.run("go2", tostring(return_room))
        wait_while(function() return running("go2") end)
    end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local win = Gui.window("Bug Catcher!", { width = 500, height = 420, resizable = true })
local root = Gui.vbox()

local tabs = Gui.tab_bar({ "Bug Catcher!", "Settings" })
root:add(tabs)

----------------------------------------------------------------------
-- Tab 1: Bug Catcher
----------------------------------------------------------------------
local tab1 = Gui.vbox()

-- Search input
local search_input = Gui.input({ placeholder = "Search bugs..." })
tab1:add(search_input)

-- Bug dropdown (editable combo)
local nearby = get_nearby_towns()
local grouped, order = filter_bugs("", nearby)

-- Build initial options list
local function build_options(grp, ord)
    local opts = {}
    for _, town in ipairs(ord) do
        table.insert(opts, "--- " .. town .. " ---")
        for _, bug in ipairs(grp[town]) do
            table.insert(opts, "  " .. bug.name)
        end
    end
    return opts
end

local bug_combo = Gui.editable_combo({
    hint = "Select a bug...",
    options = build_options(grouped, order),
})
tab1:add(bug_combo)

-- Connect search to filter
search_input:on_change(function(text)
    local g, o = filter_bugs(text, nearby)
    bug_combo:set_options(build_options(g, o))
end)

-- Bug count
tab1:add(Gui.label("Amount to catch:"))
local count_input = Gui.input({ text = "1", placeholder = "1-100" })
tab1:add(count_input)

-- Whisper options
local whisper_paper = Gui.checkbox("Paper", false)
local whisper_gem   = Gui.checkbox("Gem", false)
local whisper_candy = Gui.checkbox("Candy", false)
local candy_type_input = Gui.input({ placeholder = "Type (e.g. chocolate, hard, chew)" })

tab1:add(whisper_paper)
tab1:add(whisper_gem)

local candy_row = Gui.hbox()
candy_row:add(whisper_candy)
candy_row:add(candy_type_input)
tab1:add(candy_row)

-- Status label
local status_label = Gui.label("Ready to catch bugs!")
tab1:add(status_label)

-- Start button
local catching = false
local start_btn = Gui.button("Start")
start_btn:on_click(function()
    if catching then return end

    -- Get selected bug name (strip leading whitespace from dropdown selection)
    local selected = bug_combo:get_text()
    if not selected or selected == "" then
        status_label:set_text("Select a bug first!")
        return
    end
    selected = selected:match("^%s*(.-)%s*$") -- trim
    if selected:sub(1, 3) == "---" then
        status_label:set_text("Select a bug, not a town header!")
        return
    end

    local cnt = tonumber(count_input:get_text()) or 1
    if cnt < 1 then cnt = 1 end
    if cnt > 100 then cnt = 100 end

    -- Build whisper options
    local whisper_opts = {}
    if whisper_paper:get_checked() then table.insert(whisper_opts, "paper") end
    if whisper_gem:get_checked() then table.insert(whisper_opts, "gem") end
    if whisper_candy:get_checked() then
        local candy_text = (candy_type_input:get_text() or ""):match("^%s*(.-)%s*$")
        if candy_text ~= "" then
            table.insert(whisper_opts, candy_text)
        end
    end

    catching = true
    status_label:set_text("Starting...")
    find_and_collect_bug(selected, cnt, whisper_opts, status_label)
    catching = false
end)
tab1:add(start_btn)

tabs:set_tab_content(1, tab1)

----------------------------------------------------------------------
-- Tab 2: Settings
----------------------------------------------------------------------
local tab2 = Gui.vbox()

tab2:add(Gui.section_header("Bug Catcher Settings"))
tab2:add(Gui.label("Configure your containers before catching bugs."))
tab2:add(Gui.separator())

tab2:add(Gui.label("Jar Noun:"))
local jar_noun_input = Gui.input({
    text = CharSettings.bugs_jar_noun or "",
    placeholder = "Enter jar noun (e.g. jar, bottle, etc.)",
})
tab2:add(jar_noun_input)

tab2:add(Gui.label("Jar Sack:"))
local jarsack_input = Gui.input({
    text = CharSettings.bugs_jarsack or "",
    placeholder = "Enter jarsack (container your jar is in)",
})
tab2:add(jarsack_input)

tab2:add(Gui.label("Bug Sack:"))
local bugsack_input = Gui.input({
    text = CharSettings.bugs_bugsack or "",
    placeholder = "Enter bugsack (container for bugs)",
})
tab2:add(bugsack_input)

local settings_status = Gui.label("")

local save_btn = Gui.button("Save")
save_btn:on_click(function()
    CharSettings.bugs_jar_noun = (jar_noun_input:get_text() or ""):match("^%s*(.-)%s*$")
    CharSettings.bugs_jarsack  = (jarsack_input:get_text() or ""):match("^%s*(.-)%s*$")
    CharSettings.bugs_bugsack  = (bugsack_input:get_text() or ""):match("^%s*(.-)%s*$")
    settings_status:set_text("Settings Saved!")
end)
tab2:add(save_btn)
tab2:add(settings_status)

tabs:set_tab_content(2, tab2)

----------------------------------------------------------------------
-- Window setup and main loop
----------------------------------------------------------------------
win:set_root(root)
win:show()

before_dying(function()
    win:close()
end)

Gui.wait(win, "close")
