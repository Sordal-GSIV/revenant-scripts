-- resolver.lua — go2 target resolution
-- Translates user input (room #, tag, text, custom target, special keyword) → room_id

local settings    = require("settings")
local pathfinder  = require("pathfinder")

local M = {}

local game = GameState.game or ""

local function is_gs() return game:find("^GS") ~= nil end
local function is_dr() return game:find("^DR") ~= nil end

-------------------------------------------------------------------------------
-- UID lookup
-------------------------------------------------------------------------------

local function find_by_uid(uid_str)
    -- Prefer engine helper if available
    if Map.ids_from_uid then
        local ids = Map.ids_from_uid(tonumber(uid_str))
        if ids and #ids > 0 then return ids[1] end
    end
    -- Manual scan fallback
    local uid_num = tonumber(uid_str)
    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r and r.uid then
            if type(r.uid) == "number" and r.uid == uid_num then return id end
            if type(r.uid) == "string" and r.uid == uid_str then return id end
            if type(r.uid) == "table" then
                for _, u in ipairs(r.uid) do
                    if tostring(u) == uid_str then return id end
                end
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Text search (title + description)
-------------------------------------------------------------------------------

local function find_by_text(search)
    local matches = {}
    local sl = search:lower()
    -- Build a simple alternation pattern for ".." separators like go2.lic
    local chk_esc  = search:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
    local chk_re   = chk_esc:gsub("%%%.%%%(%%%.%%.%.%)%?", "|"):gsub("%%%.%%.", "|")

    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r then
            local matched = false
            -- title
            if r.title then
                local t = type(r.title) == "table" and r.title[1] or r.title
                if t and t:lower():find(sl, 1, true) then matched = true end
            end
            -- description
            if not matched and r.description then
                local d = type(r.description) == "table" and r.description[1] or r.description
                if d and d:lower():find(sl, 1, true) then matched = true end
            end
            if matched then
                local title = r.title
                if type(title) == "table" then title = title[1] end
                matches[#matches + 1] = {
                    id       = id,
                    title    = title or ("Room " .. id),
                    location = r.location or "",
                    uid      = r.uid,
                }
            end
            if #matches >= 200 then break end  -- cap
        end
    end
    return matches
end

-------------------------------------------------------------------------------
-- Paginated room list prompt (for multi-match text search)
-------------------------------------------------------------------------------

local function prompt_room_selection(matches)
    respond("[go2] " .. #matches .. " matching rooms found:")
    local page_size = 20
    local first = 1
    while true do
        local last = math.min(first + page_size - 1, #matches)
        respond("")
        for i = first, last do
            local m = matches[i]
            local uid_str = ""
            if m.uid then
                local u = type(m.uid) == "table" and m.uid[1] or m.uid
                if u then uid_str = " uid:" .. tostring(u) end
            end
            respond(string.format("  %4d: %-38s (%d) %s%s",
                i, m.title:sub(1, 38), m.id,
                m.location ~= "" and ("[" .. m.location .. "] ") or "",
                uid_str))
        end
        respond("")
        if last < #matches then
            respond("select a room (send 1-" .. last .. ") or 'next' for more:")
        else
            respond("select a room (send 1-" .. last .. "):")
        end
        clear()
        local line = nil
        while not line or not line:match("^%s*%S") do line = get() end
        line = line:match("^%s*(.-)%s*$")
        if line:lower() == "next" then
            if last < #matches then
                first = first + page_size
            end
        else
            local choice = tonumber(line)
            if choice and matches[choice] then
                return matches[choice].id
            end
            respond("[go2] Invalid selection: " .. line)
        end
    end
end

-------------------------------------------------------------------------------
-- Elemental Confluence resolver (GS only)
-- Returns a destination room ID inside the Confluence, or nil + err
-------------------------------------------------------------------------------

local function resolve_confluence(variant, current_room_id, state)
    -- Variant: "confluence", "confluence-hot", "confluence-cold", "instability"
    if GameState.room_name == "[Elemental Confluence]" and variant == "confluence" then
        return nil, false, "you're already in the Elemental Confluence"
    end

    -- Load the confluence helper library if available
    local ok_cf, cf = pcall(require, "lib/gs/confluence")
    if ok_cf and cf then
        local result = cf.resolve(variant, current_room_id, state)
        if result then
            return result, false, nil
        end
        return nil, false, "failed to find Elemental Confluence path"
    end

    -- Fallback: look for instability tag in nearby rooms
    local instability_ids = {}
    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r and r.tags then
            for _, t in ipairs(r.tags) do
                if t == "instability" or t:find("confluence") then
                    instability_ids[#instability_ids + 1] = id
                    break
                end
            end
        end
    end
    if #instability_ids == 0 then
        return nil, false, "no Confluence/instability rooms found in map database"
    end
    local best = pathfinder.find_nearest_in_list(current_room_id, instability_ids)
    if best then return best, true, nil end
    return nil, false, "no reachable Confluence room found"
end

-------------------------------------------------------------------------------
-- Locker resolver (GS only, CHE-aware, requires Lich ≥ 5.12.2 equivalent)
-------------------------------------------------------------------------------

local function resolve_locker(current_room_id)
    -- Determine CHE membership
    local che = nil
    if Char and Char.che then
        che = Char.che
    end

    local target_tags = {}
    if che == nil or che == "none" then
        target_tags[#target_tags + 1] = "public locker"
    else
        target_tags[#target_tags + 1] = "meta:che:" .. che .. ":locker"
        target_tags[#target_tags + 1] = "meta:che:" .. che .. ":entrance_locker"
        target_tags[#target_tags + 1] = "meta:che:" .. che .. ":entrance_annex"
        target_tags[#target_tags + 1] = "meta:che:" .. che .. ":entrance_che"
    end

    -- Gather candidate rooms
    local target_list = {}
    local tag_set = {}
    for _, t in ipairs(target_tags) do tag_set[t] = true end
    for _, id in ipairs(Map.list()) do
        local r = Map.find_room(id)
        if r and r.tags then
            for _, t in ipairs(r.tags) do
                if tag_set[t] then
                    target_list[#target_list + 1] = id
                    break
                end
            end
        end
    end

    if #target_list == 0 then
        return nil, false, "no locker rooms found in map database for CHE: " .. tostring(che)
    end

    if che and che ~= "none" then
        -- De-duplicate: remove redundant entrance types whose location overlaps closer room types
        local function get_locations(tag_key)
            local locs = {}
            for _, id in ipairs(target_list) do
                local r = Map.find_room(id)
                if r and r.tags then
                    for _, t in ipairs(r.tags) do
                        if t == ("meta:che:" .. che .. ":" .. tag_key) then
                            if r.location then locs[r.location] = true end
                            break
                        end
                    end
                end
            end
            return locs
        end

        local locker_locs          = get_locations("locker")
        local entrance_locker_locs = get_locations("entrance_locker")

        local function has_location_in(loc_set, loc)
            return loc ~= nil and loc_set[loc]
        end

        local filtered = {}
        for _, id in ipairs(target_list) do
            local r    = Map.find_room(id)
            local loc  = r and r.location or nil
            local keep = true

            if r and r.tags then
                for _, t in ipairs(r.tags) do
                    local suffix = t:match("^meta:che:[^:]+:(.+)$")
                    if suffix == "entrance_locker" then
                        if has_location_in(locker_locs, loc) then keep = false end
                    elseif suffix == "entrance_annex" or suffix == "entrance_che" then
                        if has_location_in(locker_locs, loc) or has_location_in(entrance_locker_locs, loc) then
                            keep = false
                        end
                    end
                    if not keep then break end
                end
            end

            if keep then filtered[#filtered + 1] = id end
        end
        target_list = filtered
    end

    if #target_list == 0 then
        return nil, false, "all locker rooms filtered — cannot determine target"
    end

    local best, steps = pathfinder.find_nearest_in_list(current_room_id, target_list)
    if not best then
        return nil, false, "no reachable locker room found"
    end

    return best, (steps and steps > 20), nil
end

-------------------------------------------------------------------------------
-- Guild resolver (GS only)
-------------------------------------------------------------------------------

local function resolve_guild(variant, current_room_id)
    local prof = Stats and Stats.profession
    if not prof then
        return nil, false, "cannot determine profession for guild lookup"
    end
    local tag = prof:lower() .. " " .. variant:lower()
    local result = Map.find_nearest_by_tag(tag)
    if result and result.id then
        return result.id, false, nil
    end
    return nil, false, "no " .. tag .. " found in map database"
end

-------------------------------------------------------------------------------
-- Public resolve function
-------------------------------------------------------------------------------

function M.resolve(target, current_room_id)
    if not target or target:match("^%s*$") then
        return nil, false, "no target specified"
    end
    target = target:match("^%s*(.-)%s*$")  -- trim

    -- 1. UID lookup (u12345)
    local uid_str = target:match("^[uU](%d+)$")
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
        local id = settings.get_start_room()
        if id then return id, false, nil end
        return nil, false, "no start room saved — run go2 first, then use goback"
    end

    -- 4. Elemental Confluence (GS)
    if is_gs() then
        local conf_variant = target:lower()
        if conf_variant == "confluence" or conf_variant == "confluence-hot"
           or conf_variant == "confluence-cold" or conf_variant == "instability" then
            return resolve_confluence(conf_variant, current_room_id, settings.load())
        end
    end

    -- 5. Locker (GS)
    if is_gs() and target:lower() == "locker" then
        return resolve_locker(current_room_id)
    end

    -- 6. Guild / guild shop (GS)
    if is_gs() then
        local tl = target:lower()
        if tl == "guild" or tl == "guild shop" then
            return resolve_guild(tl == "guild" and "guild" or "guild shop", current_room_id)
        end
    end

    -- 7. Custom targets (exact match, then prefix match)
    local targets = settings.load_targets()
    local custom_val = targets[target]
    if not custom_val then
        local tl = target:lower()
        for name, val in pairs(targets) do
            if name:lower() == tl then
                custom_val = val
                break
            end
        end
    end
    if not custom_val then
        local tl = target:lower()
        for name, val in pairs(targets) do
            if name:lower():find(tl, 1, true) == 1 then
                custom_val = val
                break
            end
        end
    end
    if custom_val then
        if type(custom_val) == "number" then
            local room = Map.find_room(custom_val)
            if room then
                respond("[go2] Custom target → room " .. custom_val)
                return custom_val, false, nil
            end
            return nil, false, "custom target room " .. custom_val .. " not in map"
        elseif type(custom_val) == "table" then
            -- Array of IDs — find nearest
            local best, steps = pathfinder.find_nearest_in_list(current_room_id, custom_val)
            if best then
                respond("[go2] Nearest custom target room: " .. best)
                return best, false, nil
            end
            return nil, false, "no reachable rooms in custom target list"
        end
    end

    -- 8. Tag match
    local tag_result = Map.find_nearest_by_tag(target)
    if tag_result and tag_result.id then
        local steps = tag_result.path and #tag_result.path or 0
        return tag_result.id, (steps > 20), nil
    end

    -- 9. Text search (titles + descriptions)
    local matches = find_by_text(target)
    if #matches == 0 then
        return nil, false, "no rooms found matching: " .. target
    elseif #matches == 1 then
        return matches[1].id, true, nil
    else
        local chosen = prompt_room_selection(matches)
        if chosen then return chosen, false, nil end
        return nil, false, "cancelled"
    end
end

return M
