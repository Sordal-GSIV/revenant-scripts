local settings = require("settings")

local M = {}

local function find_by_uid(uid_str)
    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r and r.uid then
            local match = false
            if type(r.uid) == "string" then
                match = (r.uid == uid_str)
            elseif type(r.uid) == "table" then
                for _, u in ipairs(r.uid) do
                    if tostring(u) == uid_str then match = true; break end
                end
            end
            if match then return id end
        end
    end
    return nil
end

local function find_by_text(search, current_room_id)
    local matches = {}
    local search_lower = search:lower()
    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r and r.title and r.title:lower():find(search_lower, 1, true) then
            matches[#matches + 1] = { id = id, title = r.title }
        end
        if #matches >= 100 then break end  -- cap search results
    end
    return matches
end

function M.resolve(target, current_room_id)
    if not target or target == "" then
        return nil, false, "no target specified"
    end

    -- 1. UID lookup (u12345)
    local uid_str = target:match("^u(%d+)$")
    if uid_str then
        local id = find_by_uid(uid_str)
        if id then return id, false, nil end
        return nil, false, "no room found with UID: u" .. uid_str
    end

    -- 2. Numeric room ID
    local num = tonumber(target)
    if num then
        local room = Map.find_room(num)
        if room then return num, false, nil end
        return nil, false, "room " .. target .. " not found in map database"
    end

    -- 3. Goback
    if target:lower() == "goback" then
        local start = settings.get_start_room()
        if start then return start, false, nil end
        return nil, false, "no start room saved — run go2 first, then use goback"
    end

    -- 4. Custom targets
    local targets = settings.load_targets()
    -- Exact match first, then prefix match
    local custom_val = targets[target]
    if not custom_val then
        for name, val in pairs(targets) do
            if name:lower():find(target:lower(), 1, true) == 1 then
                custom_val = val
                break
            end
        end
    end
    if custom_val then
        if type(custom_val) == "number" then
            return custom_val, false, nil
        elseif type(custom_val) == "table" then
            -- Array of IDs — find nearest
            local best_id = nil
            local best_steps = math.huge
            for _, id in ipairs(custom_val) do
                local path = Map.find_path(current_room_id, id)
                if path and #path < best_steps then
                    best_steps = #path
                    best_id = id
                end
            end
            if best_id then return best_id, false, nil end
            return nil, false, "no reachable custom target rooms for: " .. target
        end
    end

    -- 5. Tag match
    local tag_result = Map.find_nearest_by_tag(target)
    if tag_result and tag_result.id then
        local steps = tag_result.path and #tag_result.path or 0
        return tag_result.id, (steps > 20), nil
    end

    -- 6. Text search
    local matches = find_by_text(target, current_room_id)
    if #matches == 0 then
        return nil, false, "no rooms found matching: " .. target
    elseif #matches == 1 then
        return matches[1].id, true, nil
    else
        -- Multiple matches — print paginated list, wait for user selection
        respond("[go2] Found " .. #matches .. " rooms matching '" .. target .. "':")
        local page_size = 25
        local page = 0
        while true do
            local start_idx = page * page_size + 1
            local end_idx = math.min(start_idx + page_size - 1, #matches)
            for i = start_idx, end_idx do
                local m = matches[i]
                respond("  " .. i .. ". [" .. m.id .. "] " .. m.title)
            end
            if end_idx < #matches then
                respond("  Type a number to select, or 'next' for more, or 'cancel':")
            else
                respond("  Type a number to select, or 'cancel':")
            end

            local input = get()
            if not input then
                return nil, false, "cancelled"
            end
            input = input:match("^%s*(.-)%s*$")  -- trim

            if input:lower() == "cancel" or input:lower() == "q" then
                return nil, false, "cancelled"
            elseif input:lower() == "next" and end_idx < #matches then
                page = page + 1
            else
                local choice = tonumber(input)
                if choice and matches[choice] then
                    return matches[choice].id, false, nil
                else
                    respond("[go2] Invalid selection: " .. input)
                end
            end
        end
    end
end

return M
