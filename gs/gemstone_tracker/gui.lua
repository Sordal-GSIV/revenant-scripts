--- GUI for gemstone tracker
-- Full tabbed interface: Current, History, Add Jewel, Group, Help, Settings

local data = require("data")
local constants = require("constants")

local M = {}

-- Shared GUI state
local win = nil
local widgets = {}
local state = {
    show_names = true,
    current_looter = nil,
    kills_this_hunt = 0,
    hunt_start = os.time(),
    pause_seconds = 0,
    pause_start = nil,
    is_paused = false,
    is_timer_paused = false,
    timer_pause_start = nil,
    selected_character = "Main",
    get_gemstone_info = false,
    temp_info = {},
    add_gemstone_name = nil,
    last_critter_looted = nil,
    last_gemstone_found = nil,
    people_found_this_week = {},
    gems_found_month = {},
    found_hash = nil,
    looter_current_kills = 0,
}

M.state = state

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function add_commas(n)
    local s = tostring(n)
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        count = count + 1
        result = s:sub(i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

local function pad_right(str, width)
    if #str >= width then return str end
    return str .. string.rep(" ", width - #str)
end

local function pad_left(str, width)
    if #str >= width then return str end
    return string.rep(" ", width - #str) .. str
end

local function pct(num, denom)
    if denom == 0 then return "0.00" end
    return string.format("%.2f", (num / denom) * 100)
end

---------------------------------------------------------------------------
-- Update current tab display
---------------------------------------------------------------------------

local function update_gemstone_finds_single(name)
    -- Returns text for a single character's gemstone status
    local char = data.gemstone_data["Character Info"][name]
    if not char then return "" end

    local gems_month = data.gems_found_this_month(name)
    state.gems_found_month[name] = gems_month

    local found_this_week = data.found_gem_this_week(name)
    if found_this_week then
        state.people_found_this_week[name] = true
    else
        state.people_found_this_week[name] = nil
    end

    local text = ""
    if found_this_week then
        local last_key = data.last_find_key(name)
        if last_key then
            local find = char["Gemstone Finds"][last_key]
            state.last_gemstone_found = last_key
            state.add_gemstone_name = name
            state.found_hash = find

            local kills = find["Total Kills"] or 0
            local critter = find["Critter Found On"] or "Unknown"

            -- Format the date
            local parts = {}
            for p in last_key:gmatch("[^/]+") do table.insert(parts, p) end
            local formatted = string.format("%02d/%02d/%s", tonumber(parts[1]), tonumber(parts[2]), parts[3])

            if find["Gemstone Rarity"] then
                text = text .. "\nGEMSTONE FOUND! [" .. (find["Gemstone Rarity"] or "") .. "]"
            else
                text = text .. "\nGEMSTONE FOUND!"
            end
            text = text .. "\nFound: " .. formatted
            text = text .. "\nTotal kills: " .. kills
            text = text .. "\nFound on: " .. critter

            -- Properties
            for _, prop_key in ipairs({"Property One", "Property Two", "Property Three"}) do
                local prop_text = find[prop_key .. " Text"]
                local prop_rarity = find[prop_key .. " Rarity"]
                if prop_text and prop_text ~= "None" then
                    text = text .. "\n  [" .. (prop_rarity or "?") .. "] " .. prop_text
                end
            end

            if find["Gemstone Found This Month"] then
                text = text .. "\n" .. find["Gemstone Found This Month"] .. " Gemstone Found This Month"
            end

            -- Show add button if rarity not yet recorded
            if not find["Gemstone Rarity"] then
                if widgets.add_gem_btn then widgets.add_gem_btn:set_text("Add Gemstone") end
                -- Determine which gem of the month
                if gems_month == 1 then
                    find["Gemstone Found This Month"] = "First"
                elseif gems_month == 2 then
                    find["Gemstone Found This Month"] = "Second"
                elseif gems_month == 3 then
                    find["Gemstone Found This Month"] = "Third"
                end
            end
        end
    end

    return text
end

local function update_main_view()
    -- Show all characters summary
    local chars = data.gemstone_data["Character Info"]
    local names = data.character_names()

    -- Find longest name for alignment
    local longest = 12
    for _, name in ipairs(names) do
        if #name > longest then longest = #name end
    end

    local header = pad_right("Name:", longest + 2) .. "Kills  Month  This Week\n"
    local lines_no_gem = {}
    local lines_gem = {}

    for _, name in ipairs(names) do
        local gems_month = data.gems_found_this_month(name)
        state.gems_found_month[name] = gems_month
        local found_week = data.found_gem_this_week(name)
        if found_week then
            state.people_found_this_week[name] = true
        else
            state.people_found_this_week[name] = nil
        end

        local display_name = state.show_names and name or string.rep("-", longest)
        local kills
        if found_week then
            local last_key = data.last_find_key(name)
            if last_key then
                kills = chars[name]["Gemstone Finds"][last_key]["Total Kills"] or 0
            else
                kills = 0
            end
        else
            kills = data.current_kills(name)
        end

        if name == state.current_looter then
            state.looter_current_kills = kills
        end

        local formatted_date = ""
        if found_week then
            local last_key = data.last_find_key(name)
            if last_key then
                local parts = {}
                for p in last_key:gmatch("[^/]+") do table.insert(parts, p) end
                formatted_date = string.format("%02d/%02d/%s", tonumber(parts[1]), tonumber(parts[2]), parts[3])
            end
        end

        local line = pad_right(display_name .. ":", longest + 2)
            .. pad_left(tostring(kills), 5) .. "   "
            .. pad_left(tostring(gems_month), 1) .. "    "
            .. formatted_date .. "\n"

        if found_week then
            table.insert(lines_gem, { name = name, gems = gems_month, line = line })
        else
            table.insert(lines_no_gem, { name = name, gems = gems_month, line = line })
        end
    end

    -- Sort by gems found (ascending), then name
    table.sort(lines_no_gem, function(a, b)
        if a.gems ~= b.gems then return a.gems < b.gems end
        return a.name < b.name
    end)
    table.sort(lines_gem, function(a, b)
        if a.gems ~= b.gems then return a.gems < b.gems end
        return a.name < b.name
    end)

    local text = header
    for _, entry in ipairs(lines_no_gem) do text = text .. entry.line end
    for _, entry in ipairs(lines_gem) do text = text .. entry.line end

    return text
end

local function update_single_view(name)
    local kills_text = ""
    local gem_text = ""

    -- Kill breakdown
    local breakdown = data.kill_breakdown(name)
    if #breakdown > 0 then
        kills_text = "Kill count:\n"
        local total = 0
        for _, entry in ipairs(breakdown) do
            total = total + entry.count
            kills_text = kills_text .. pad_left(tostring(entry.count), 5) .. " " .. entry.critter .. "\n"
        end
        kills_text = kills_text .. pad_left(tostring(total), 5) .. " Total kills"
    end

    -- Gemstone status
    gem_text = update_gemstone_finds_single(name)

    return kills_text, gem_text
end

local function format_time(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function update_hunt_info()
    if state.is_timer_paused then return "" end

    local elapsed = (os.time() - state.hunt_start) - state.pause_seconds
    if elapsed < 1 or state.kills_this_hunt < 1 then return "" end

    local kps = state.kills_this_hunt / elapsed
    local kpm = kps * 60

    local lines = {}
    table.insert(lines, "Hunt: " .. format_time(elapsed) .. "  Kills: " .. state.kills_this_hunt)
    table.insert(lines, string.format("KPM: %.2f", kpm))

    -- Find rate estimation
    if state.current_looter and state.gems_found_month[state.current_looter] and state.looter_current_kills > 0 then
        local total_kills = state.looter_current_kills
        local gems_found = state.gems_found_month[state.current_looter] or 0
        local first_rate = constants.FIND_RATE
        local second_third_rate = constants.UPPER_RATE_SECOND_THIRD
        local kills_remaining

        if gems_found == 0 then
            if total_kills >= first_rate then first_rate = total_kills + 100 end
            kills_remaining = first_rate - total_kills
        else
            if total_kills >= second_third_rate then second_third_rate = total_kills + 100 end
            kills_remaining = second_third_rate - total_kills
        end

        if kills_remaining > 0 then
            local eta_seconds = math.floor(kills_remaining / kps)
            lines[2] = string.format("KPM: %.2f  Kills: %d  Remaining: %d  ETA: %s",
                kpm, total_kills, kills_remaining, format_time(eta_seconds))

            if gems_found == 0 then
                local next_pct = string.format("%.3f", (1.0 / kills_remaining) * 100)
                local cum_pct = string.format("%.2f", (total_kills / first_rate) * 100)
                table.insert(lines, next_pct .. "% next kill — " .. cum_pct .. "% cumulative")
            else
                local x = 1.0 / 1500
                local chance = 1 - (1 - x) ^ total_kills
                local cum_pct = string.format("%.3f", chance * 100)
                local next_pct = string.format("%.3f", (1.0 / first_rate) * 100)
                table.insert(lines, next_pct .. "% next kill — " .. cum_pct .. "% cumulative")
            end
        end
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Build History Tab content
---------------------------------------------------------------------------

local function build_history_text(month_filter, year_filter)
    local stats = data.compute_stats(month_filter, year_filter)

    if stats.total_gems == 0 then
        return "No gemstones found for this period."
    end

    local text = ""
    text = text .. "Total Gems Found:               " .. stats.total_gems .. "\n"
    text = text .. "Total Common Gems:              " .. stats.total_common .. " (" .. pct(stats.total_common, stats.total_gems) .. "%)\n"
    text = text .. "Total Regional Gems:            " .. stats.total_regional .. " (" .. pct(stats.total_regional, stats.total_gems) .. "%)\n"
    text = text .. "Total Common/Common Gems:       " .. stats.total_common_common .. " (" .. pct(stats.total_common_common, stats.total_gems) .. "%)\n"
    text = text .. "Total Common/Regional Gems:     " .. stats.total_common_regional .. " (" .. pct(stats.total_common_regional, stats.total_gems) .. "%)\n"
    text = text .. "Total Rare/Common Gems:         " .. stats.total_rare_common .. " (" .. pct(stats.total_rare_common, stats.total_gems) .. "%)\n"
    text = text .. "Total Rare/Regional Gems:       " .. stats.total_rare_regional .. " (" .. pct(stats.total_rare_regional, stats.total_gems) .. "%)\n"
    text = text .. "Total Legendary/Common Gems:    " .. stats.total_legendary_common .. " (" .. pct(stats.total_legendary_common, stats.total_gems) .. "%)\n"
    text = text .. "Total Legendary/Regional Gems:  " .. stats.total_legendary_regional .. " (" .. pct(stats.total_legendary_regional, stats.total_gems) .. "%)\n"
    text = text .. "\n"

    -- 1st gemstone kills
    local total_first = stats.kills_first + stats.kills_no_first
    text = text .. "1st Gemstone Kills:             " .. add_commas(stats.kills_first) .. "\n"
    text = text .. "Kills With No Gem:              " .. add_commas(stats.kills_no_first) .. "\n"
    text = text .. "Total Kills:                    " .. add_commas(total_first) .. "\n"
    text = text .. "Gemstones Found:                " .. stats.first_gems .. "\n"
    if stats.first_gems > 0 then
        text = text .. "Average Kills Per Gem:          " .. string.format("%.2f", total_first / stats.first_gems) .. "\n"
    else
        text = text .. "Average Kills Per Gem:          0\n"
    end
    text = text .. "\n"

    -- 2nd/3rd gemstone kills
    local total_23 = stats.kills_second_third + stats.kills_no_second_third
    text = text .. "2nd/3rd Gemstone Kills:         " .. add_commas(stats.kills_second_third) .. "\n"
    text = text .. "Kills With No Gem:              " .. add_commas(stats.kills_no_second_third) .. "\n"
    text = text .. "Total Kills:                    " .. add_commas(total_23) .. "\n"
    text = text .. "Gemstones Found:                " .. stats.second_third_gems .. "\n"
    if stats.second_third_gems > 0 then
        text = text .. "Average Kills Per Gem:          " .. string.format("%.2f", total_23 / stats.second_third_gems) .. "\n"
    else
        text = text .. "Average Kills Per Gem:          0\n"
    end
    text = text .. "\n"

    -- Grand totals
    local grand_total = total_first + total_23
    text = text .. "Total Kills:                    " .. add_commas(grand_total) .. "\n"
    if stats.total_gems > 0 then
        text = text .. "Average Kills Per Gem:          " .. string.format("%.2f", grand_total / stats.total_gems) .. "\n"
    end

    -- Critters
    text = text .. "\nCritters Gemstones Found On:\n"
    local sorted_critters = {}
    for critter, count in pairs(stats.critter_info) do
        table.insert(sorted_critters, { critter = critter, count = count })
    end
    table.sort(sorted_critters, function(a, b) return a.count > b.count end)
    for _, entry in ipairs(sorted_critters) do
        text = text .. entry.count .. " " .. entry.critter .. "\n"
    end

    -- Properties
    text = text .. "\nGemstone Properties:\n"
    text = text .. stats.total_properties .. " Total Properties\n"
    for rar, count in pairs(stats.property_rarity) do
        text = text .. count .. " " .. rar .. "\n"
    end
    text = text .. "\n"

    local sorted_props = {}
    for prop, count in pairs(stats.property_info) do
        table.insert(sorted_props, { prop = prop, count = count })
    end
    table.sort(sorted_props, function(a, b) return a.count > b.count end)

    -- Align property counts
    local max_count_len = 0
    for _, entry in ipairs(sorted_props) do
        local s = string.format("%d (%.2f%%)", entry.count, (entry.count / stats.total_properties) * 100)
        if #s > max_count_len then max_count_len = #s end
    end
    for _, entry in ipairs(sorted_props) do
        local s = string.format("%d (%.2f%%)", entry.count, (entry.count / stats.total_properties) * 100)
        text = text .. pad_right(s, max_count_len) .. " " .. entry.prop .. "\n"
    end

    return text
end

---------------------------------------------------------------------------
-- Build single gemstone find detail (for History tab date selection)
---------------------------------------------------------------------------

local function build_find_detail(name, date_key)
    local char = data.gemstone_data["Character Info"][name]
    if not char or not char["Gemstone Finds"] or not char["Gemstone Finds"][date_key] then
        return "No data found."
    end

    local find = char["Gemstone Finds"][date_key]
    local parts = {}
    for p in date_key:gmatch("[^/]+") do table.insert(parts, p) end
    local formatted = string.format("%02d/%02d/%s", tonumber(parts[1]), tonumber(parts[2]), parts[3])

    local critter = find["Critter Found On"] or "Unknown"
    local kills = find["Total Kills"] or 0

    local text = ""
    local rarity = find["Gemstone Rarity"] or "Unknown"
    text = text .. "[" .. rarity .. "] GEMSTONE FOUND!\n"
    text = text .. "Found: " .. formatted .. "\n"
    text = text .. "Total kills: " .. kills .. "\n"
    text = text .. "Found on: " .. critter .. "\n"

    for _, prop_key in ipairs({"Property One", "Property Two", "Property Three"}) do
        local prop_text = find[prop_key .. " Text"]
        local prop_rarity = find[prop_key .. " Rarity"]
        if prop_text and prop_text ~= "None" then
            text = text .. "  [" .. (prop_rarity or "?") .. "] " .. prop_text .. "\n"
        end
    end

    if find["Gemstone Found This Month"] then
        text = text .. find["Gemstone Found This Month"] .. " Gemstone Found This Month\n"
    end

    return text
end

---------------------------------------------------------------------------
-- Build the main GUI window
---------------------------------------------------------------------------

function M.create_window()
    win = Gui.window("Gemstone Tracker", {
        width = data.gemstone_data["Window Width"] or 500,
        height = data.gemstone_data["Window Height"] or 500,
        resizable = true,
    })

    local root = Gui.vbox()

    ---------------------------------------------------------------------------
    -- Top bar: Character selector + buttons
    ---------------------------------------------------------------------------
    local top_bar = Gui.hbox()

    -- Character dropdown
    local char_options = { "Main" }
    for _, name in ipairs(data.character_names()) do
        table.insert(char_options, name)
    end
    local char_combo = Gui.editable_combo({
        text = "Main",
        hint = "Character",
        options = char_options,
    })
    widgets.char_combo = char_combo
    top_bar:add(char_combo)

    -- Names toggle button
    local names_btn = Gui.button("Names")
    names_btn:on_click(function()
        state.show_names = not state.show_names
        M.refresh_display()
    end)
    top_bar:add(names_btn)

    -- Pause updates button
    local pause_btn = Gui.button("Pause")
    pause_btn:on_click(function()
        state.is_paused = not state.is_paused
        pause_btn:set_text(state.is_paused and "Unpause" or "Pause")
    end)
    top_bar:add(pause_btn)

    -- Restart hunt timer
    local restart_btn = Gui.button("Restart")
    restart_btn:on_click(function()
        state.hunt_start = os.time()
        state.kills_this_hunt = 0
        state.pause_seconds = 0
        state.is_timer_paused = false
        state.timer_pause_start = nil
        M.refresh_display()
    end)
    top_bar:add(restart_btn)

    -- Pause hunt timer
    local pause_timer_btn = Gui.button("Pause Timer")
    widgets.pause_timer_btn = pause_timer_btn
    pause_timer_btn:on_click(function()
        if state.is_timer_paused then
            -- Unpause
            if state.timer_pause_start then
                state.pause_seconds = state.pause_seconds + (os.time() - state.timer_pause_start)
            end
            state.is_timer_paused = false
            state.timer_pause_start = nil
            pause_timer_btn:set_text("Pause Timer")
        else
            -- Pause
            state.is_timer_paused = true
            state.timer_pause_start = os.time()
            pause_timer_btn:set_text("Unpause Timer")
        end
    end)
    top_bar:add(pause_timer_btn)

    root:add(top_bar)

    ---------------------------------------------------------------------------
    -- Tab bar
    ---------------------------------------------------------------------------
    local tabs = Gui.tab_bar({"Current", "History", "Add Jewel", "Group", "Help", "Settings"})
    root:add(tabs)

    ---------------------------------------------------------------------------
    -- Current Tab
    ---------------------------------------------------------------------------
    local current_tab = Gui.scroll(Gui.vbox())
    local current_vbox = Gui.vbox()

    -- Hunt info label
    local hunt_label = Gui.label("Hunt Info")
    widgets.hunt_label = hunt_label
    current_vbox:add(hunt_label)

    current_vbox:add(Gui.separator())

    -- Kill count label
    local kill_label = Gui.label("")
    widgets.kill_label = kill_label
    current_vbox:add(kill_label)

    current_vbox:add(Gui.separator())

    -- Gemstone found label
    local gem_label = Gui.label("")
    widgets.gem_label = gem_label
    current_vbox:add(gem_label)

    -- Add Gemstone button (hidden by default)
    local add_gem_btn = Gui.button("Add Gemstone")
    widgets.add_gem_btn = add_gem_btn
    add_gem_btn:on_click(function()
        if not state.add_gem_visible then return end

        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_jewel = (rh and rh.noun == "jewel") or (lh and lh.noun == "jewel")
        if has_jewel then
            -- Ensure found_hash points to the actual find record
            local gem_name = state.add_gemstone_name
            local gem_key = state.last_gemstone_found
            if gem_name and gem_key then
                local char = data.gemstone_data["Character Info"][gem_name]
                if char and char["Gemstone Finds"] and char["Gemstone Finds"][gem_key] then
                    state.found_hash = char["Gemstone Finds"][gem_key]
                end
            end

            if not state.found_hash then
                echo("Cannot find the gemstone record. Try selecting the character and refreshing.")
                return
            end

            state.get_gemstone_info = true
            state.temp_info = {
                ["Property One Text"] = "None",
                ["Property Two Text"] = "None",
                ["Property Three Text"] = "None",
                ["Property One Rarity"] = "None",
                ["Property Two Rarity"] = "None",
                ["Property Three Rarity"] = "None",
                ["Gemstone Rarity"] = nil,
            }
            put("look at my jewel")
        else
            echo("You must be HOLDING the jewel to add info to the database.")
        end
    end)
    current_vbox:add(add_gem_btn)

    current_tab = Gui.scroll(current_vbox)
    tabs:set_tab_content(1, current_tab)

    ---------------------------------------------------------------------------
    -- History Tab
    ---------------------------------------------------------------------------
    local history_vbox = Gui.vbox()

    -- Month selector
    local month_options = { "All" }
    for _, m in ipairs(data.all_months()) do
        table.insert(month_options, m)
    end
    local history_combo = Gui.editable_combo({
        text = "All",
        hint = "Period",
        options = month_options,
    })
    widgets.history_combo = history_combo
    history_vbox:add(history_combo)

    local history_label = Gui.label("")
    widgets.history_label = history_label
    history_vbox:add(history_label)

    -- Refresh history when combo changes
    history_combo:on_change(function()
        M.refresh_history()
    end)

    tabs:set_tab_content(2, Gui.scroll(history_vbox))

    ---------------------------------------------------------------------------
    -- Add Jewel Tab
    ---------------------------------------------------------------------------
    local jewel_vbox = Gui.vbox()

    local jewel_info_label = Gui.label(
        "Add jewels found while the script was not running.\n"
        .. "Select a character from the dropdown first.\n"
        .. "For current-week jewels found while running, use the\n"
        .. "'Add Gemstone' button on the Current tab instead."
    )
    widgets.jewel_info_label = jewel_info_label
    jewel_vbox:add(jewel_info_label)

    jewel_vbox:add(Gui.section_header("Date"))
    local date_row = Gui.hbox()
    local month_input = Gui.input({ text = tostring(data.now_date().month), placeholder = "Month" })
    local day_input = Gui.input({ text = "1", placeholder = "Day" })
    local year_input = Gui.input({ text = tostring(data.now_date().year), placeholder = "Year" })
    widgets.jewel_month = month_input
    widgets.jewel_day = day_input
    widgets.jewel_year = year_input
    date_row:add(Gui.label("Month:"))
    date_row:add(month_input)
    date_row:add(Gui.label("Day:"))
    date_row:add(day_input)
    date_row:add(Gui.label("Year:"))
    date_row:add(year_input)
    jewel_vbox:add(date_row)

    local kills_row = Gui.hbox()
    local kills_input = Gui.input({ text = "0", placeholder = "Total kills when found" })
    widgets.jewel_kills = kills_input
    kills_row:add(Gui.label("Kills:"))
    kills_row:add(kills_input)
    jewel_vbox:add(kills_row)

    jewel_vbox:add(Gui.section_header("Critter"))
    local critter_combo = Gui.editable_combo({
        text = constants.critter_display_names[1] or "",
        hint = "Critter found on",
        options = constants.critter_display_names,
    })
    widgets.jewel_critter = critter_combo
    jewel_vbox:add(critter_combo)

    jewel_vbox:add(Gui.section_header("Gem of Month"))
    local month_gem_combo = Gui.editable_combo({
        text = "First",
        hint = "Which gem this month",
        options = { "First", "Second", "Third" },
    })
    widgets.jewel_month_gem = month_gem_combo
    jewel_vbox:add(month_gem_combo)

    jewel_vbox:add(Gui.section_header("Properties"))

    -- First property (Common + Regional)
    local first_prop_options = { "None" }
    for _, p in ipairs(constants.common_properties) do table.insert(first_prop_options, p) end
    for _, p in ipairs(constants.regional_properties) do table.insert(first_prop_options, p) end
    local first_prop = Gui.editable_combo({ text = "None", hint = "1st Property", options = first_prop_options })
    widgets.jewel_prop1 = first_prop
    jewel_vbox:add(Gui.label("First Property:"))
    jewel_vbox:add(first_prop)

    -- Second property (Common + Regional + Rare)
    local second_prop_options = { "None" }
    for _, p in ipairs(constants.common_properties) do table.insert(second_prop_options, p) end
    for _, p in ipairs(constants.regional_properties) do table.insert(second_prop_options, p) end
    for _, p in ipairs(constants.rare_properties) do table.insert(second_prop_options, p) end
    local second_prop = Gui.editable_combo({ text = "None", hint = "2nd Property", options = second_prop_options })
    widgets.jewel_prop2 = second_prop
    jewel_vbox:add(Gui.label("Second Property:"))
    jewel_vbox:add(second_prop)

    -- Third property (Legendary only)
    local third_prop_options = { "None" }
    for _, p in ipairs(constants.legendary_properties) do table.insert(third_prop_options, p) end
    local third_prop = Gui.editable_combo({ text = "None", hint = "3rd Property", options = third_prop_options })
    widgets.jewel_prop3 = third_prop
    jewel_vbox:add(Gui.label("Third Property:"))
    jewel_vbox:add(third_prop)

    jewel_vbox:add(Gui.section_header("Rarities"))

    local rarity_options = { "None", "Common", "Regional", "Rare", "Legendary" }
    local rarity_options_no_none = { "Common", "Regional", "Rare", "Legendary" }

    local r1 = Gui.editable_combo({ text = "None", hint = "Prop 1 Rarity", options = rarity_options })
    local r2 = Gui.editable_combo({ text = "None", hint = "Prop 2 Rarity", options = rarity_options })
    local r3 = Gui.editable_combo({ text = "None", hint = "Prop 3 Rarity", options = rarity_options })
    local gr = Gui.editable_combo({ text = "Common", hint = "Gemstone Rarity", options = rarity_options_no_none })
    widgets.jewel_r1 = r1
    widgets.jewel_r2 = r2
    widgets.jewel_r3 = r3
    widgets.jewel_gr = gr

    local rar_row1 = Gui.hbox()
    rar_row1:add(Gui.label("Prop 1:"))
    rar_row1:add(r1)
    rar_row1:add(Gui.label("Prop 2:"))
    rar_row1:add(r2)
    jewel_vbox:add(rar_row1)

    local rar_row2 = Gui.hbox()
    rar_row2:add(Gui.label("Prop 3:"))
    rar_row2:add(r3)
    rar_row2:add(Gui.label("Gemstone:"))
    rar_row2:add(gr)
    jewel_vbox:add(rar_row2)

    -- Save button
    jewel_vbox:add(Gui.separator())
    local save_jewel_btn = Gui.button("Save Jewel")
    save_jewel_btn:on_click(function()
        local sel_name = char_combo:get_text()
        if sel_name == "Main" then
            echo("Select a character first, not 'Main'.")
            return
        end

        local char = data.gemstone_data["Character Info"][sel_name]
        if not char then
            echo("Character '" .. sel_name .. "' not found in data.")
            return
        end

        local month = tonumber(month_input:get_text()) or 1
        local day = tonumber(day_input:get_text()) or 1
        local year = tonumber(year_input:get_text()) or data.now_date().year
        local date_key = data.format_date(month, day, year)

        local p1_text = first_prop:get_text()
        local p2_text = second_prop:get_text()
        local p3_text = third_prop:get_text()

        local find_data = {
            ["Date Found"] = string.format("%d-%02d-%02d 12:00:00", year, month, day),
            ["Critter Found On"] = critter_combo:get_text(),
            ["Total Kills"] = tonumber(kills_input:get_text()) or 0,
            ["Gemstone Found This Month"] = month_gem_combo:get_text(),
        }

        if p1_text ~= "None" then find_data["Property One Text"] = p1_text end
        if p2_text ~= "None" then find_data["Property Two Text"] = p2_text end
        if p3_text ~= "None" then find_data["Property Three Text"] = p3_text end

        local r1_text = r1:get_text()
        local r2_text = r2:get_text()
        local r3_text = r3:get_text()
        if r1_text ~= "None" then find_data["Property One Rarity"] = r1_text end
        if r2_text ~= "None" then find_data["Property Two Rarity"] = r2_text end
        if r3_text ~= "None" then find_data["Property Three Rarity"] = r3_text end
        find_data["Gemstone Rarity"] = gr:get_text()

        char["Gemstone Finds"][date_key] = find_data
        echo("Jewel information added for " .. sel_name .. " on " .. date_key .. "!")
        M.refresh_display()
    end)
    jewel_vbox:add(save_jewel_btn)

    tabs:set_tab_content(3, Gui.scroll(jewel_vbox))

    ---------------------------------------------------------------------------
    -- Group Tab
    ---------------------------------------------------------------------------
    local group_vbox = Gui.vbox()

    group_vbox:add(Gui.section_header("Group Management"))

    local group_display = Gui.label("Current group: " .. table.concat(data.gemstone_data["Group"] or {}, ", "))
    widgets.group_display = group_display
    group_vbox:add(group_display)

    local group_input = Gui.input({ text = "", placeholder = "Character name" })
    widgets.group_input = group_input
    group_vbox:add(group_input)

    local group_btn_row = Gui.hbox()
    local add_btn = Gui.button("Add")
    add_btn:on_click(function()
        local name = group_input:get_text()
        if name == "" then return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        name = name:gsub("[^a-zA-Z]", "")
        local group = data.gemstone_data["Group"]
        -- Don't add duplicates
        for _, g in ipairs(group) do
            if g == name then
                group_input:set_text("")
                return
            end
        end
        table.insert(group, name)
        -- Sort non-captain members
        if #group > 1 then
            local captain = table.remove(group, 1)
            table.sort(group)
            table.insert(group, 1, captain)
        end
        group_input:set_text("")
        group_display:set_text("Current group: " .. table.concat(group, ", "))
    end)
    group_btn_row:add(add_btn)

    local remove_btn = Gui.button("Remove")
    remove_btn:on_click(function()
        local name = group_input:get_text()
        if name == "" then return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        name = name:gsub("[^a-zA-Z]", "")
        local group = data.gemstone_data["Group"]
        for i, g in ipairs(group) do
            if g == name then
                table.remove(group, i)
                break
            end
        end
        group_input:set_text("")
        group_display:set_text("Current group: " .. table.concat(group, ", "))
    end)
    group_btn_row:add(remove_btn)

    local captain_btn = Gui.button("Captain")
    captain_btn:on_click(function()
        local name = group_input:get_text()
        if name == "" then return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        name = name:gsub("[^a-zA-Z]", "")
        local group = data.gemstone_data["Group"]
        -- Remove if already present
        for i, g in ipairs(group) do
            if g == name then
                table.remove(group, i)
                break
            end
        end
        -- Insert at front
        table.insert(group, 1, name)
        group_input:set_text("")
        group_display:set_text("Current group: " .. table.concat(group, ", "))
    end)
    group_btn_row:add(captain_btn)

    group_vbox:add(group_btn_row)

    group_vbox:add(Gui.separator())
    group_vbox:add(Gui.label(
        "IF UPDATING THIS LIST, close the script on ALL characters first,\n"
        .. "restart on one character, update the group, then close and reopen.\n\n"
        .. "IF YOU MULTI-ACCOUNT: Do not list someone in a group AND have\n"
        .. "them run the script — only the Captain runs the script.\n\n"
        .. "The Captain (first listed) runs the script and tracks stats for\n"
        .. "everyone in the group. All stats update in real time.\n\n"
        .. "Characters NOT in the group can run the script independently.\n"
        .. "Data syncs every 5 minutes via the save file."
    ))

    tabs:set_tab_content(4, Gui.scroll(group_vbox))

    ---------------------------------------------------------------------------
    -- Help Tab
    ---------------------------------------------------------------------------
    local help_vbox = Gui.vbox()
    help_vbox:add(Gui.section_header("Gemstone Tracker Help"))
    help_vbox:add(Gui.label(
        "Keep this script running in the background for accurate tracking.\n\n"
        .. "ADDING CHARACTERS:\n"
        .. "Characters are auto-added when they loot or mug a critter.\n\n"
        .. "ADDING GEMSTONES (current week):\n"
        .. "After finding a gemstone, select the character from the dropdown,\n"
        .. "go to the Current tab, hold the jewel in your hand, and click\n"
        .. "'Add Gemstone'. Properties are automatically recorded.\n\n"
        .. "ADDING GEMSTONES (past weeks):\n"
        .. "Go to the 'Add Jewel' tab, select the character, fill in the\n"
        .. "details, and click 'Save Jewel'.\n\n"
        .. "HUNT TIMER:\n"
        .. "The script tracks kills and time for the current session.\n"
        .. "Use 'Restart' to reset, 'Pause Timer' to pause/resume.\n"
        .. "From scripts: set $gemstone_tracker_restart_timer = true\n\n"
        .. "FIND RATES:\n"
        .. "Base rate: 1 in 1500 (pity counter lowers denominator by 1\n"
        .. "per loot). 2nd/3rd gem: ~90% by 3500 loots.\n\n"
        .. "SCROLLING:\n"
        .. "All tabs are scrollable if content exceeds the window.\n\n"
        .. "Author: Dreaven (Tgo01)\n"
        .. "Ported to Revenant Lua by AI assistant"
    ))

    -- Pretty save toggle
    local save_type_check = Gui.checkbox("Pretty save format (larger file)", data.gemstone_data["Save Type Checkbox"] == "Yes")
    save_type_check:on_change(function()
        data.gemstone_data["Save Type Checkbox"] = save_type_check:get_checked() and "Yes" or "No"
    end)
    help_vbox:add(save_type_check)

    tabs:set_tab_content(5, Gui.scroll(help_vbox))

    ---------------------------------------------------------------------------
    -- Settings Tab (Window size)
    ---------------------------------------------------------------------------
    local settings_vbox = Gui.vbox()
    settings_vbox:add(Gui.section_header("Window Settings"))
    settings_vbox:add(Gui.label("Close the script on all characters before changing.\nDefault: 500x500"))

    local size_row = Gui.hbox()
    local width_input = Gui.input({ text = tostring(data.gemstone_data["Window Width"] or 500), placeholder = "Width" })
    local height_input = Gui.input({ text = tostring(data.gemstone_data["Window Height"] or 500), placeholder = "Height" })
    size_row:add(Gui.label("Width:"))
    size_row:add(width_input)
    size_row:add(Gui.label("Height:"))
    size_row:add(height_input)
    settings_vbox:add(size_row)

    local apply_btn = Gui.button("Apply Size")
    apply_btn:on_click(function()
        local w = tonumber(width_input:get_text()) or 500
        local h = tonumber(height_input:get_text()) or 500
        data.gemstone_data["Window Width"] = w
        data.gemstone_data["Window Height"] = h
    end)
    settings_vbox:add(apply_btn)

    tabs:set_tab_content(6, Gui.scroll(settings_vbox))

    ---------------------------------------------------------------------------
    -- Character combo change handler
    ---------------------------------------------------------------------------
    char_combo:on_change(function()
        state.selected_character = char_combo:get_text()
        M.refresh_display()
    end)

    win:set_root(Gui.scroll(root))
    -- Don't show until ;send show
end

---------------------------------------------------------------------------
-- Refresh display (called periodically and on events)
---------------------------------------------------------------------------

function M.refresh_display()
    if not win or state.is_paused then return end

    local sel = state.selected_character or "Main"

    if sel == "Main" then
        local text = update_main_view()
        if widgets.kill_label then widgets.kill_label:set_text("") end
        if widgets.gem_label then widgets.gem_label:set_text(text) end
    else
        local kills_text, gem_text = update_single_view(sel)
        if widgets.kill_label then widgets.kill_label:set_text(kills_text) end
        if widgets.gem_label then widgets.gem_label:set_text(gem_text) end
    end

    -- Hunt info
    local hunt_text = update_hunt_info()
    if widgets.hunt_label then widgets.hunt_label:set_text(hunt_text ~= "" and hunt_text or "Hunt Info") end

    -- Add Gemstone button: show only when a gem was found this week but not yet recorded
    if widgets.add_gem_btn then
        local show_btn = false
        if sel ~= "Main" then
            local found_week = data.found_gem_this_week(sel)
            if found_week then
                local last_key = data.last_find_key(sel)
                if last_key then
                    local char = data.gemstone_data["Character Info"][sel]
                    local find = char and char["Gemstone Finds"] and char["Gemstone Finds"][last_key]
                    if find and not find["Gemstone Rarity"] then
                        show_btn = true
                    end
                end
            end
        end
        widgets.add_gem_btn:set_text(show_btn and "Add Gemstone" or "")
        state.add_gem_visible = show_btn
    end
end

function M.refresh_history()
    if not widgets.history_combo or not widgets.history_label then return end

    local sel = widgets.history_combo:get_text()

    if sel == "All" then
        local text = build_history_text(nil, nil)
        widgets.history_label:set_text(text)
    else
        -- Parse month/year from selection
        local parts = {}
        for p in sel:gmatch("[^/]+") do table.insert(parts, p) end
        if #parts == 2 then
            local month = tonumber(parts[1])
            local year = tonumber(parts[2])
            if month and year then
                -- Check if we're showing aggregate or per-character
                local char_sel = state.selected_character
                if char_sel and char_sel ~= "Main" then
                    -- Show individual find dates for this character
                    local char = data.gemstone_data["Character Info"][char_sel]
                    if char and char["Gemstone Finds"] then
                        local text = ""
                        for date_key, _ in pairs(char["Gemstone Finds"]) do
                            local dp = {}
                            for p in date_key:gmatch("[^/]+") do table.insert(dp, p) end
                            local fm = tonumber(dp[1])
                            local fy = tonumber(dp[3])
                            if fm == month and fy == year then
                                text = text .. build_find_detail(char_sel, date_key) .. "\n"
                            end
                        end
                        if text == "" then text = "No gemstones found this period." end
                        widgets.history_label:set_text(text)
                    else
                        widgets.history_label:set_text("No data for this character.")
                    end
                else
                    local text = build_history_text(month, year)
                    widgets.history_label:set_text(text)
                end
            end
        end
    end
end

function M.show_window()
    if win then
        M.refresh_display()
        M.refresh_history()
        win:show()
    end
end

function M.refresh_char_list()
    if widgets.char_combo then
        local options = { "Main" }
        for _, name in ipairs(data.character_names()) do
            table.insert(options, name)
        end
        widgets.char_combo:set_options(options)
    end
end

-- Handle gemstone info response from game (property/rarity parsing)
function M.process_gem_info_line(line)
    if not state.get_gemstone_info then return end

    local property = line:match("^Property:%s+(.+)")
    if property then
        property = property:gsub("%s*%(Rank %d+ of %d+%)%s*$", "")
        if state.temp_info["Property One Text"] == "None" then
            state.temp_info["Property One Text"] = property
        elseif state.temp_info["Property Two Text"] == "None" then
            state.temp_info["Property Two Text"] = property
        elseif state.temp_info["Property Three Text"] == "None" then
            state.temp_info["Property Three Text"] = property
        end
        return
    end

    local rarity = line:match("^Rarity:%s+(.+)")
    if rarity then
        if state.temp_info["Property One Rarity"] == "None" then
            state.temp_info["Property One Rarity"] = rarity
        elseif state.temp_info["Property Two Rarity"] == "None" then
            state.temp_info["Property Two Rarity"] = rarity
        elseif state.temp_info["Property Three Rarity"] == "None" then
            state.temp_info["Property Three Rarity"] = rarity
        end

        -- Track overall gemstone rarity (highest wins)
        if not state.temp_info["Gemstone Rarity"] then
            state.temp_info["Gemstone Rarity"] = rarity
        else
            local current = state.temp_info["Gemstone Rarity"]
            if rarity == "Legendary" then
                state.temp_info["Gemstone Rarity"] = "Legendary"
            elseif (current == "Common" or current == "Regional") and (rarity == "Rare" or rarity == "Legendary") then
                state.temp_info["Gemstone Rarity"] = rarity
            end
        end
        return
    end

    -- End of gemstone info
    if line:match("You note the telltale filaments") then
        -- Apply temp info to the found hash
        if state.found_hash then
            for k, v in pairs(state.temp_info) do
                state.found_hash[k] = v
            end
        end
        state.get_gemstone_info = false
        M.refresh_display()
    end
end

-- Cleanup
function M.close()
    if win then
        win:close()
        win = nil
    end
end

return M
