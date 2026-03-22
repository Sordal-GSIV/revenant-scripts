--- Data persistence for gemstone tracker
-- JSON file storage with auto-save and backup

local M = {}

local SAVE_FILE = "gemstone_tracker.json"
local BACKUP_FILE = "gemstone_tracker_backup.json"

-- Current loaded data (shared mutable state)
M.gemstone_data = nil

---------------------------------------------------------------------------
-- Date/time helpers (EST/EDT aware via os.date)
---------------------------------------------------------------------------

function M.now()
    return os.time()
end

function M.now_date()
    -- Return a table with year, month, day, wday (1=Sunday)
    return os.date("*t", M.now())
end

function M.format_date(month, day, year)
    return month .. "/" .. day .. "/" .. year
end

function M.current_date_string()
    local d = M.now_date()
    return M.format_date(d.month, d.day, d.year)
end

function M.month_year_string()
    local d = M.now_date()
    return d.month .. "/" .. d.year
end

-- Get the Sunday..Saturday range for the week containing a given date table
function M.week_days(date_table)
    local days = {}
    -- wday: 1=Sunday in Lua
    local offset_to_sunday = date_table.wday - 1
    local sunday_time = os.time(date_table) - (offset_to_sunday * 86400)
    for i = 0, 6 do
        local day_time = sunday_time + (i * 86400)
        local dt = os.date("*t", day_time)
        table.insert(days, { month = dt.month, day = dt.day, year = dt.year })
    end
    return days
end

-- Check if a given month/day falls within the current week
function M.date_in_current_week(month, day)
    local today = M.now_date()
    local week = M.week_days(today)
    for _, wd in ipairs(week) do
        if wd.month == month and wd.day == day then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Data structure initialization
---------------------------------------------------------------------------

function M.ensure_defaults()
    if not M.gemstone_data then
        M.gemstone_data = {}
    end
    local d = M.gemstone_data
    d["Character Info"] = d["Character Info"] or {}
    d["Group"] = d["Group"] or {}
    d["Window Width"] = d["Window Width"] or 500
    d["Window Height"] = d["Window Height"] or 500
    d["Save Type Checkbox"] = d["Save Type Checkbox"] or "Yes"
    d["Last Backup Day"] = d["Last Backup Day"] or M.now_date().day
end

function M.ensure_character(name)
    local info = M.gemstone_data["Character Info"]
    if not info[name] then
        info[name] = {
            ["Critter Kills"] = {},
            ["Gemstone Finds"] = {},
            ["No First Gemstone Week Kills"] = {},
            ["No Second/Third Gemstone Week Kills"] = {},
            ["Last Reset Day"] = M.now_date().day,
            ["Last Reset Month"] = M.now_date().month,
        }
    end
    return info[name]
end

---------------------------------------------------------------------------
-- Load / Save
---------------------------------------------------------------------------

function M.load()
    if File.exists(SAVE_FILE) then
        local content = File.read(SAVE_FILE)
        if content and content ~= "" then
            local ok, parsed = pcall(Json.decode, content)
            if ok and parsed then
                M.gemstone_data = parsed
                echo("Gemstone info loaded.")
            else
                echo("WARNING: Failed to parse gemstone data file, starting fresh.")
                M.gemstone_data = {}
            end
        else
            M.gemstone_data = {}
        end
    else
        M.gemstone_data = {}
        echo("First time running gemstone-tracker. Use ;send show to open the tracker window.")
    end
    M.ensure_defaults()
end

function M.save()
    if not M.gemstone_data then return end
    M.ensure_defaults()

    -- Daily backup
    local d = M.now_date()
    if d.day ~= M.gemstone_data["Last Backup Day"] then
        M.gemstone_data["Last Backup Day"] = d.day
        local backup_json = Json.encode(M.gemstone_data)
        File.write(BACKUP_FILE, backup_json)
        echo("Gemstone BACKUP saved.")
    end

    local json_str = Json.encode(M.gemstone_data)
    File.write(SAVE_FILE, json_str)
    echo("Gemstone info saved.")
end

---------------------------------------------------------------------------
-- Character data helpers
---------------------------------------------------------------------------

-- Get sorted list of character names
function M.character_names()
    local names = {}
    for name, _ in pairs(M.gemstone_data["Character Info"]) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Count gemstones found this month for a character
function M.gems_found_this_month(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char or not char["Gemstone Finds"] then return 0 end

    local current_month = M.now_date().month
    local count = 0
    local finds = char["Gemstone Finds"]

    -- Look at the last 3 finds (max gemstones per month)
    local keys = {}
    for date_key, _ in pairs(finds) do
        table.insert(keys, date_key)
    end
    table.sort(keys)

    local last_three = {}
    for i = math.max(1, #keys - 2), #keys do
        if keys[i] then table.insert(last_three, keys[i]) end
    end

    for _, date_key in ipairs(last_three) do
        local parts = {}
        for p in date_key:gmatch("[^/]+") do table.insert(parts, p) end
        local month_found = tonumber(parts[1])
        if month_found == current_month then
            count = count + 1
        end
    end
    return count
end

-- Check if character found a gemstone in the current week
function M.found_gem_this_week(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char or not char["Gemstone Finds"] then return false end

    local finds = char["Gemstone Finds"]
    local keys = {}
    for date_key, _ in pairs(finds) do
        table.insert(keys, date_key)
    end
    if #keys == 0 then return false end
    table.sort(keys)
    local last_key = keys[#keys]

    local parts = {}
    for p in last_key:gmatch("[^/]+") do table.insert(parts, p) end
    local month_found = tonumber(parts[1])
    local day_found = tonumber(parts[2])

    return M.date_in_current_week(month_found, day_found)
end

-- Get the last gemstone find date key for a character
function M.last_find_key(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char or not char["Gemstone Finds"] then return nil end
    local keys = {}
    for date_key, _ in pairs(char["Gemstone Finds"]) do
        table.insert(keys, date_key)
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    return keys[#keys]
end

-- Get total kills for a character's current week
function M.current_kills(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char or not char["Critter Kills"] then return 0 end
    local total = 0
    for _, count in pairs(char["Critter Kills"]) do
        total = total + count
    end
    return total
end

-- Get kill breakdown sorted by count (descending)
function M.kill_breakdown(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char or not char["Critter Kills"] then return {} end
    local entries = {}
    for critter, count in pairs(char["Critter Kills"]) do
        table.insert(entries, { critter = critter, count = count })
    end
    table.sort(entries, function(a, b) return a.count > b.count end)
    return entries
end

-- Record a kill for a character
function M.record_kill(name, critter)
    local char = M.ensure_character(name)
    char["Critter Kills"][critter] = (char["Critter Kills"][critter] or 0) + 1
end

-- Record a gemstone find
function M.record_gemstone(name, critter)
    local char = M.ensure_character(name)
    local d = M.now_date()
    local date_key = M.format_date(d.month, d.day, d.year)

    local total_kills = M.current_kills(name)

    char["Gemstone Finds"][date_key] = {
        ["Date Found"] = os.date("%Y-%m-%d %H:%M:%S", M.now()),
        ["Critter Found On"] = critter,
        ["Total Kills"] = total_kills,
    }
    return date_key
end

-- Reset weekly kills for a character (archiving to no-gem stats)
function M.reset_weekly_kills(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char then return end

    local found_gs_last_week = false
    local finds = char["Gemstone Finds"]
    local keys = {}
    for date_key, _ in pairs(finds) do
        table.insert(keys, date_key)
    end
    if #keys > 0 then
        table.sort(keys)
        local last_key = keys[#keys]
        local parts = {}
        for p in last_key:gmatch("[^/]+") do table.insert(parts, p) end
        local month_found = tonumber(parts[1])
        local day_found = tonumber(parts[2])

        -- Check if last find was in the previous week
        local today = M.now_date()
        if char["Last Reset Month"] == today.month then
            local offset = today.wday - 1
            local sunday = os.time({year=today.year, month=today.month, day=today.day}) - (offset * 86400)
            local prev_sunday = sunday - (7 * 86400)
            for i = 0, 6 do
                local dt = os.date("*t", prev_sunday + (i * 86400))
                if dt.day == day_found and dt.month == month_found then
                    found_gs_last_week = true
                    break
                end
            end
        else
            -- Different month — check current week
            local week = M.week_days(today)
            for _, wd in ipairs(week) do
                if wd.day == day_found and wd.month == month_found then
                    found_gs_last_week = true
                    break
                end
            end
        end
    end

    if not found_gs_last_week then
        local total_kills = M.current_kills(name)
        local my = M.month_year_string()
        local gems_month = M.gems_found_this_month(name)
        if gems_month == 0 and char["Last Reset Month"] == M.now_date().month then
            char["No First Gemstone Week Kills"][my] = (char["No First Gemstone Week Kills"][my] or 0) + total_kills
        else
            char["No Second/Third Gemstone Week Kills"][my] = (char["No Second/Third Gemstone Week Kills"][my] or 0) + total_kills
        end
    end

    char["Critter Kills"] = {}
end

-- Check if we need to reset weekly data
function M.check_reset(name)
    local char = M.gemstone_data["Character Info"][name]
    if not char then return end

    local today = M.now_date()
    local week = M.week_days(today)
    local new_week = true
    for _, wd in ipairs(week) do
        if wd.day == char["Last Reset Day"] then
            new_week = false
            break
        end
    end

    local new_month = (today.month ~= char["Last Reset Month"])

    if (new_week and char["Last Reset Day"]) or new_month then
        -- Reset for all group members or just this character
        local group = M.gemstone_data["Group"]
        if #group > 0 and group[1] == GameState.name then
            for _, gname in ipairs(group) do
                M.reset_weekly_kills(gname)
                local gchar = M.gemstone_data["Character Info"][gname]
                if gchar then
                    gchar["Last Reset Day"] = today.day
                    gchar["Last Reset Month"] = today.month
                end
            end
        elseif not M.in_group(name) then
            M.reset_weekly_kills(name)
            char["Last Reset Day"] = today.day
            char["Last Reset Month"] = today.month
        end
    end
end

-- Check if a name is in the group
function M.in_group(name)
    for _, gname in ipairs(M.gemstone_data["Group"]) do
        if gname == name then return true end
    end
    return false
end

-- Is this character the group captain?
function M.is_captain()
    local group = M.gemstone_data["Group"]
    return #group > 0 and group[1] == GameState.name
end

---------------------------------------------------------------------------
-- Stats computation for history view
---------------------------------------------------------------------------

function M.compute_stats(month_filter, year_filter)
    -- month_filter/year_filter: nil = all time, numbers = specific month
    local stats = {
        total_gems = 0,
        kills_first = 0,
        kills_no_first = 0,
        kills_second_third = 0,
        kills_no_second_third = 0,
        first_gems = 0,
        second_third_gems = 0,
        total_common = 0,
        total_regional = 0,
        total_common_common = 0,
        total_common_regional = 0,
        total_rare_common = 0,
        total_rare_regional = 0,
        total_legendary_common = 0,
        total_legendary_regional = 0,
        critter_info = {},
        property_info = {},
        property_rarity = {},
        total_properties = 0,
    }

    local all_time = (month_filter == nil)

    for name, char in pairs(M.gemstone_data["Character Info"]) do
        -- Accumulate no-gem week kills
        if char["No First Gemstone Week Kills"] then
            if all_time then
                for _, v in pairs(char["No First Gemstone Week Kills"]) do
                    stats.kills_no_first = stats.kills_no_first + v
                end
            else
                local key = month_filter .. "/" .. year_filter
                local v = char["No First Gemstone Week Kills"][key]
                if v then stats.kills_no_first = stats.kills_no_first + v end
            end
        end
        if char["No Second/Third Gemstone Week Kills"] then
            if all_time then
                for _, v in pairs(char["No Second/Third Gemstone Week Kills"]) do
                    stats.kills_no_second_third = stats.kills_no_second_third + v
                end
            else
                local key = month_filter .. "/" .. year_filter
                local v = char["No Second/Third Gemstone Week Kills"][key]
                if v then stats.kills_no_second_third = stats.kills_no_second_third + v end
            end
        end

        -- Current week kills (add to no-gem if applicable for current month)
        local today = M.now_date()
        local current_my = today.month .. "/" .. today.year
        if (all_time) or (month_filter == today.month and year_filter == today.year) then
            if not M.found_gem_this_week(name) then
                local cur_kills = M.current_kills(name)
                local gems_month = M.gems_found_this_month(name)
                if gems_month == 0 then
                    stats.kills_no_first = stats.kills_no_first + cur_kills
                else
                    stats.kills_no_second_third = stats.kills_no_second_third + cur_kills
                end
            end
        end

        -- Process gem finds
        if char["Gemstone Finds"] then
            for date_key, find in pairs(char["Gemstone Finds"]) do
                local parts = {}
                for p in date_key:gmatch("[^/]+") do table.insert(parts, p) end
                local fm = tonumber(parts[1])
                local fy = tonumber(parts[3])

                if all_time or (fm == month_filter and fy == year_filter) then
                    stats.total_gems = stats.total_gems + 1

                    -- Critter tracking
                    local critter = find["Critter Found On"] or "Unknown"
                    stats.critter_info[critter] = (stats.critter_info[critter] or 0) + 1

                    -- Gem position (1st/2nd/3rd of month)
                    local position = find["Gemstone Found This Month"]
                    if position == "First" then
                        stats.kills_first = stats.kills_first + (find["Total Kills"] or 0)
                        stats.first_gems = stats.first_gems + 1
                    elseif position == "Second" or position == "Third" then
                        stats.kills_second_third = stats.kills_second_third + (find["Total Kills"] or 0)
                        stats.second_third_gems = stats.second_third_gems + 1
                    end

                    -- Rarity classification
                    local p1r = find["Property One Rarity"]
                    local p2r = find["Property Two Rarity"]
                    local p3r = find["Property Three Rarity"]
                    local gr = find["Gemstone Rarity"]

                    if p1r == "Common" and p2r == "Common" then
                        stats.total_common_common = stats.total_common_common + 1
                    elseif (p1r == "Common" or p1r == "Regional") and (p2r == "Common" or p2r == "Regional") then
                        stats.total_common_regional = stats.total_common_regional + 1
                    elseif gr == "Common" then
                        stats.total_common = stats.total_common + 1
                    elseif gr == "Regional" then
                        stats.total_regional = stats.total_regional + 1
                    elseif p1r == "Common" and p2r == "Rare" and (p3r == "None" or not p3r) then
                        stats.total_rare_common = stats.total_rare_common + 1
                    elseif p1r == "Regional" and p2r == "Rare" and (p3r == "None" or not p3r) then
                        stats.total_rare_regional = stats.total_rare_regional + 1
                    elseif p1r == "Common" and p3r == "Legendary" then
                        stats.total_legendary_common = stats.total_legendary_common + 1
                    elseif p1r == "Regional" and p3r == "Legendary" then
                        stats.total_legendary_regional = stats.total_legendary_regional + 1
                    end

                    -- Property tracking
                    for _, prop_key in ipairs({"Property One Text", "Property Two Text", "Property Three Text"}) do
                        local prop = find[prop_key]
                        if prop and prop ~= "None" then
                            stats.property_info[prop] = (stats.property_info[prop] or 0) + 1
                            stats.total_properties = stats.total_properties + 1
                        end
                    end
                    for _, rar_key in ipairs({"Property One Rarity", "Property Two Rarity", "Property Three Rarity"}) do
                        local rar = find[rar_key]
                        if rar and rar ~= "None" then
                            stats.property_rarity[rar] = (stats.property_rarity[rar] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    return stats
end

-- Get all unique month/year strings across all characters
function M.all_months()
    local months = {}
    local seen = {}
    for _, char in pairs(M.gemstone_data["Character Info"]) do
        if char["Gemstone Finds"] then
            for date_key, _ in pairs(char["Gemstone Finds"]) do
                local parts = {}
                for p in date_key:gmatch("[^/]+") do table.insert(parts, p) end
                local key = parts[1] .. "/" .. (parts[3] or parts[2])
                if not seen[key] then
                    seen[key] = true
                    table.insert(months, key)
                end
            end
        end
    end
    table.sort(months)
    return months
end

return M
