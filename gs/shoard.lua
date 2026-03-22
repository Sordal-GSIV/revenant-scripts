--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: shoard
--- version: 1.2.1
--- author: SpiffyJr
--- contributors: elanthia-online
--- game: gs
--- description: Gem hoarding into locker jars with indexing, store, retrieve, bounty, and combine
--- tags: gem,hoarding,locker,jars
---
--- Changelog (from Lich5):
---   v1.2.1 (2025-11-10): Minor bugfixes in load method, default settings initialization
---   v1.2.0 (2025-03-22): Gem prefix normalization, combine command
---   v1.1.0 (2022-03-13): Standard locker support, help text, current-room add/delete
---   v1.0.0 (2021-10-11): Initial release
---
--- Usage:
---   ;shoard help              - Show help
---   ;shoard add [room]        - Add locker at current or specified room
---   ;shoard delete [room]     - Remove locker
---   ;shoard index             - Index nearest locker jars
---   ;shoard store             - Store gems from gemsack into locker jars
---   ;shoard list [filter]     - List locker contents (filter: alpha, or gem name)
---   ;shoard get N <gem>       - Retrieve N gems from locker
---   ;shoard go2               - Navigate to nearest locker
---   ;shoard bounty            - Raid hoard for bounty gems
---   ;shoard combine           - Merge duplicate gem jars
---   ;shoard debug             - Toggle debug mode

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function pad_left(s, w)
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

local function normalize_gem(name)
    local n = string.lower(name or "")
    n = string.gsub(n, "^containing%s+", "")
    n = string.gsub(n, "^pieces? of%s+", "")
    n = string.gsub(n, "^shards? of%s+", "")
    n = string.gsub(n, "^blue%-violet chunks? of%s+", "")
    n = string.gsub(n, "^chunks? of%s+", "")
    n = string.gsub(n, "^fragments? of%s+", "")
    n = string.gsub(n, "^slivers? of%s+", "")
    n = string.gsub(n, "^pinchs? of%s+", "")
    n = string.gsub(n, "^spindles? of%s+", "")
    n = string.gsub(n, "^some%s+", "")
    n = string.gsub(n, "%s+", " ")
    n = string.match(n, "^%s*(.-)%s*$") or n
    -- Normalize plurals
    n = string.gsub(n, "ies$", "y")
    n = string.gsub(n, "xes$", "x")
    n = string.gsub(n, "zes$", "z")
    n = string.gsub(n, "es$", "e")
    n = string.gsub(n, "s$", "")
    return n
end

local function fwi(room_id)
    local room = Map.find_room(tonumber(room_id))
    if not room or not room.location then return false end
    return Regex.test("Four Winds|Mist Harbor|Western Harbor", room.location)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_settings()
    local raw = CharSettings.shoard_lockers
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    return { debug = false, lockers = {} }
end

local function save_settings(s)
    CharSettings.shoard_lockers = Json.encode(s)
end

local sett = load_settings()

--------------------------------------------------------------------------------
-- Stow sack detection
--------------------------------------------------------------------------------

local function get_stow_sacks()
    local sacks = {}
    clear()
    put("stow list")
    local deadline = os.time() + 3
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            local id, stype = string.match(line, 'exist="([^"]+)"[^(]+%((%a+)%)')
            if id and stype then
                for _, obj in ipairs(GameObj.inv()) do
                    if obj.id == id then
                        sacks[stype] = obj
                        break
                    end
                end
            end
            if string.find(line, "<prompt") then break end
        else
            pause(0.05)
        end
    end
    return sacks
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local function closest_locker()
    local keys = {}
    for k, _ in pairs(sett.lockers) do
        table.insert(keys, tonumber(k) or k)
    end
    if #keys == 0 then return nil end
    local room = Room.current()
    if not room then return nil end
    return room:find_nearest(keys)
end

local function go2(place)
    Script.run("go2", tostring(place) .. " --disable-confirm")
    wait_while(function() return Script.running("go2") end)
end

local function find_locker_entrance()
    local all = {}
    for _, obj in ipairs(GameObj.loot() or {}) do table.insert(all, obj) end
    for _, obj in ipairs(GameObj.room_desc() or {}) do table.insert(all, obj) end
    return all
end

local function go2_locker(id)
    id = id or closest_locker()
    if not id then
        echo("** No lockers configured. Use ;shoard add")
        return
    end

    -- Check if already in locker booth
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^locker$") or string.match(obj.noun, "^counter$") then
            return
        end
    end

    go2(id)

    -- Check again after navigating
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^locker$") or string.match(obj.noun, "^counter$") then
            return
        end
    end

    -- Try to enter through opening/curtain/tapestry
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^opening$") or string.match(obj.noun, "^curtain$") or string.match(obj.noun, "^tapestry$") then
            local noun = obj.noun
            -- CHE locker: tapestry hides the opening
            if noun == "tapestry" then noun = "opening" end
            local current = Room.id
            move("go " .. noun)
            if current == Room.id then
                echo(">> Someone is using that locker. Waiting until they're done...")
                wait_while(function() return current == Room.id end)
            end
            return
        end
    end

    echo("** Failed to find locker entrance.")
end

local function leave_locker()
    -- Only leave if in a locker-tagged room
    local room = Room.current()
    if room and room.tags then
        local in_locker = false
        for _, tag in ipairs(room.tags) do
            if string.find(tag, "locker") then in_locker = true; break end
        end
        if not in_locker then return end
    end

    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^opening$") or string.match(obj.noun, "^curtain$") or string.match(obj.noun, "^tapestry$") then
            local noun = obj.noun
            -- CHE locker: tapestry hides the opening
            if noun == "tapestry" then noun = "opening" end
            local current = Room.id
            move("go " .. noun)
            wait_while(function() return current == Room.id end)
            return
        end
    end
end

local function open_locker()
    dothistimeout("open locker", 3, "As you open|That is already|You open")
end

local function close_locker()
    dothistimeout("close locker", 3, "faint creak|That is already|You close")
end

local function find_locker_obj()
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^locker$") or string.match(obj.noun, "^chest$") then
            return obj
        end
    end
    -- Try counter (some locker areas use a counter with locker on top)
    for _, obj in ipairs(GameObj.room_desc() or {}) do
        if string.match(obj.noun, "^counter$") then
            fput("look on #" .. obj.id)
            pause(0.1)
            if obj.contents then
                for _, c in ipairs(obj.contents) do
                    if string.match(c.noun, "locker") then
                        dothistimeout("look in #" .. c.id, 3, "In the|There is nothing")
                        return c
                    end
                end
            end
        end
    end
    return nil
end

local function get_locker_with_contents()
    local locker = find_locker_obj()
    if not locker then return nil end

    if not locker.contents then
        dothistimeout("look in #" .. locker.id, 3, "In the|There is nothing")
        local deadline = os.time() + 3
        while locker.contents == nil and os.time() < deadline do
            pause(0.1)
        end
    end

    if not locker.contents then
        echo("** Failed to get locker contents.")
        return nil
    end

    return locker
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function cmd_add(room_id)
    room_id = room_id or Room.id
    local key = tostring(room_id)
    if sett.lockers[key] then
        echo("** Locker already exists.")
        return
    end
    sett.lockers[key] = { empty = 0, jars = {} }
    save_settings(sett)
    local keys = {}
    for k, _ in pairs(sett.lockers) do table.insert(keys, k) end
    echo(">> Lockers set to: " .. table.concat(keys, ", ") .. ".")
end

local function cmd_delete(room_id)
    room_id = room_id or Room.id
    local key = tostring(room_id)
    if not sett.lockers[key] then
        echo("** You have not added that locker.")
        return
    end
    sett.lockers[key] = nil
    save_settings(sett)
    local keys = {}
    for k, _ in pairs(sett.lockers) do table.insert(keys, k) end
    echo(">> Lockers set to: " .. table.concat(keys, ", ") .. ".")
end

local function cmd_index()
    local id = tostring(closest_locker())
    go2_locker(tonumber(id))
    open_locker()

    local locker = get_locker_with_contents()
    if not locker then
        echo("** Failed to find locker.")
        return
    end

    dothistimeout("look in #" .. locker.id, 3, "In the|There is nothing")
    pause(0.5)

    local empty_count = 0
    local jars = {}
    local contents = locker.contents or {}

    for _, obj in ipairs(contents) do
        if string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$") then
            if not obj.after_name then
                empty_count = empty_count + 1
            else
                local res = dothistimeout("look in #" .. obj.id .. " from #" .. locker.id, 3,
                    "Inside .* you see %d+ portion")
                if res then
                    local count_str = string.match(res, "you see (%d+) portion")
                    local full = string.find(res, "It is full") ~= nil
                    if count_str then
                        table.insert(jars, {
                            gem   = normalize_gem(obj.after_name),
                            count = tonumber(count_str) or 0,
                            full  = full,
                        })
                    end
                end
            end
        end
    end

    sett.lockers[id] = { empty = empty_count, jars = jars }
    save_settings(sett)
    echo(">> Indexed: " .. #jars .. " jars, " .. empty_count .. " empty")

    close_locker()
end

local function cmd_list(filter)
    for room_id, data in pairs(sett.lockers) do
        local room     = Map.find_room(tonumber(room_id))
        local location = room and room.location or ""
        local title    = room and room.title or ""
        local header   = ""
        if location ~= "" then header = location .. " - " end
        if title ~= ""    then header = header .. title .. " - " end
        respond("")
        respond(header .. "Locker Room #: " .. room_id ..
                " (" .. #data.jars .. " jars, " .. data.empty .. " empty)")
        respond(pad_right("Name", 40) .. pad_left("Count", 6) .. "  Full")
        respond(string.rep("-", 40) .. " " .. string.rep("-", 5) .. "  " .. string.rep("-", 4))

        local sorted = {}
        for _, j in ipairs(data.jars) do table.insert(sorted, j) end

        if filter == "alpha" then
            table.sort(sorted, function(a, b) return a.gem < b.gem end)
        elseif filter and filter ~= "" then
            local filtered = {}
            for _, j in ipairs(sorted) do
                if string.find(string.lower(j.gem), string.lower(filter), 1, true) then
                    table.insert(filtered, j)
                end
            end
            sorted = filtered
        else
            table.sort(sorted, function(a, b) return a.count > b.count end)
        end

        for _, jar in ipairs(sorted) do
            respond(pad_right(jar.gem, 40) .. pad_left(tostring(jar.count), 5) .. "  " .. (jar.full and "yes" or "no"))
        end
        respond(string.rep("-", 40) .. " " .. string.rep("-", 5) .. "  " .. string.rep("-", 4))
        respond("")
    end
end

local function cmd_get_gems(count, gem_name, room_id)
    if not count or count == 0 then
        echo("** Invalid gem count. Try a number greater than 0.")
        return
    end
    if not gem_name or gem_name == "" then
        echo("** Invalid or missing gem name.")
        return
    end

    room_id = room_id or tostring(closest_locker())
    if not sett.lockers[room_id] then cmd_index() end

    local locker_data = sett.lockers[room_id]
    if not locker_data then
        echo("** No locker data after index. Aborting.")
        return
    end

    local gem_key = normalize_gem(gem_name)
    local jar_data = nil
    for _, j in ipairs(locker_data.jars) do
        if normalize_gem(j.gem) == gem_key then
            jar_data = j
            break
        end
    end

    if not jar_data or jar_data.count < count then
        echo(">> Sorry, you do not have enough to get " .. count .. " of " .. gem_name .. ".")
        return
    end

    go2_locker()
    open_locker()

    local locker = get_locker_with_contents()
    if not locker then echo("** Failed to find locker."); return end
    dothistimeout("look in #" .. locker.id, 3, "In the|There is nothing")
    pause(0.3)

    local jar = nil
    for _, obj in ipairs(locker.contents or {}) do
        if string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$") then
            if obj.after_name and normalize_gem(obj.after_name) == gem_key then
                jar = obj
                break
            end
        end
    end

    if jar then
        fput("get #" .. jar.id .. " from #" .. locker.id)
        for _ = 1, count do
            fput("shake #" .. jar.id)
            fput("stow left gem")
            jar_data.count = jar_data.count - 1
            jar_data.full  = false
        end
        fput("put #" .. jar.id .. " in locker")
    end

    if jar_data.count <= 0 then
        locker_data.empty = locker_data.empty + 1
        local new_jars = {}
        for _, j in ipairs(locker_data.jars) do
            if j ~= jar_data then table.insert(new_jars, j) end
        end
        locker_data.jars = new_jars
    end

    save_settings(sett)
    close_locker()
    leave_locker()
end

local function cmd_store()
    local room_id = tostring(closest_locker())
    if not sett.lockers[room_id] then cmd_index() end

    local sacks   = get_stow_sacks()
    local gemsack = sacks["gem"]
    if not gemsack then
        echo("** No gem stow container set.")
        return
    end

    dothistimeout("look in #" .. gemsack.id, 3, "In the|There is nothing")
    pause(0.3)

    local locker_data = sett.lockers[room_id]
    if not locker_data then
        echo("** No locker data. Run ;shoard index first.")
        return
    end

    -- Jars that have a matching gem in gemsack and are not full
    local jars_to_fill = {}
    for _, jar in ipairs(locker_data.jars) do
        if not jar.full then
            local gem_key = normalize_gem(jar.gem)
            local has_match = false
            for _, obj in ipairs(gemsack.contents or {}) do
                if obj:type_p("gem") and normalize_gem(obj.name) == gem_key then
                    has_match = true; break
                end
            end
            if has_match then
                table.insert(jars_to_fill, jar)
            end
        end
    end

    -- Gems in gemsack that don't have a jar yet (new gem types)
    local gems_to_store = {}
    local seen_new = {}
    for _, obj in ipairs(gemsack.contents or {}) do
        if obj:type_p("gem") then
            local obj_key = normalize_gem(obj.name)
            local has_jar = false
            for _, jar in ipairs(locker_data.jars) do
                if normalize_gem(jar.gem) == obj_key then has_jar = true; break end
            end
            if not has_jar and not seen_new[obj_key] then
                seen_new[obj_key] = true
                table.insert(gems_to_store, obj_key)
            end
        end
    end

    if #jars_to_fill == 0 and #gems_to_store == 0 then
        echo(">> Nothing to store.")
        return
    end

    go2_locker()
    open_locker()

    local locker = get_locker_with_contents()
    if not locker then echo("** Failed to find locker."); return end
    dothistimeout("look in #" .. locker.id, 3, "In the|There is nothing")
    pause(0.3)

    -- Helper: drag a single gem into a jar, update jar_data
    local function drag_gem(gem, jar, jar_data)
        local res = dothistimeout("_drag #" .. gem.id .. " #" .. jar.id, 3,
            "You add|You put|is full|does not appear")
        if res and string.find(res, "filling it") then
            jar_data.count = jar_data.count + 1
            jar_data.full  = true
        elseif res and (string.find(res, "You add") or string.find(res, "You put")) then
            jar_data.count = jar_data.count + 1
        elseif res and string.find(res, "is full") then
            jar_data.full = true
            fput("stow #" .. gem.id)
        else
            fput("stow #" .. gem.id)
        end
    end

    -- Fill existing jars
    for _, jar_data in ipairs(jars_to_fill) do
        local gem_key = normalize_gem(jar_data.gem)
        local jar_obj = nil
        for _, obj in ipairs(locker.contents or {}) do
            if (string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$"))
                and obj.after_name and normalize_gem(obj.after_name) == gem_key then
                jar_obj = obj
                break
            end
        end

        if not jar_obj then
            echo("** Failed to find existing jar for " .. jar_data.gem .. ": this shouldn't happen!")
        else
            fput("get #" .. jar_obj.id .. " from #" .. locker.id)
            pause(0.1)
            for _, gem in ipairs(gemsack.contents or {}) do
                if gem:type_p("gem") and normalize_gem(gem.name) == gem_key then
                    drag_gem(gem, jar_obj, jar_data)
                    pause(0.1)
                    if jar_data.full then break end
                end
            end
            fput("put #" .. jar_obj.id .. " in locker")
        end
    end

    -- Store new gem types into empty jars
    if locker_data.empty > 0 then
        for _, gem_name in ipairs(gems_to_store) do
            -- Find an empty jar in locker
            local empty_jar = nil
            for _, obj in ipairs(locker.contents or {}) do
                if (string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$"))
                    and not obj.after_name then
                    empty_jar = obj
                    break
                end
            end

            if not empty_jar then
                echo("** Failed to find empty jar for " .. gem_name ..
                     ": put some empty jars in your locker, run ;shoard index, then rerun ;shoard store")
                break
            end

            fput("get #" .. empty_jar.id .. " from #" .. locker.id)

            local jar_data = { gem = gem_name, count = 0, full = false }
            local gem_key  = normalize_gem(gem_name)

            for _, gem in ipairs(gemsack.contents or {}) do
                if gem:type_p("gem") and normalize_gem(gem.name) == gem_key then
                    drag_gem(gem, empty_jar, jar_data)
                    if jar_data.full then break end
                end
            end

            locker_data.empty = locker_data.empty - 1
            table.insert(locker_data.jars, jar_data)
            fput("put #" .. empty_jar.id .. " in locker")
        end
    end

    save_settings(sett)
    close_locker()
    leave_locker()
end

local function cmd_bounty()
    local task = Bounty.task
    if not task or task == "" then
        echo("** No active bounty.")
        return
    end

    -- Parse gem bounty: "The gem dealer in <realm>, ..., has received orders from multiple customers
    -- requesting (an?|some) <gem>.  You have been tasked to retrieve <count>"
    local re        = Regex.new("The gem dealer in ([^,]+), [^,]+, has received orders from multiple customers requesting (?:an?|some) ([^.]+)\\.  You have been tasked to retrieve (\\d+)")
    local caps      = re:captures(task)
    if not caps then
        echo("** No gem bounty found in current task.")
        return
    end

    local realm      = caps[1]
    local gem        = normalize_gem(caps[2])
    local gems_needed = tonumber(caps[3])

    -- Check what we already have in gemsack
    local sacks   = get_stow_sacks()
    local gemsack = sacks["gem"]
    if not gemsack then
        echo("** No gem stow container set.")
        return
    end
    dothistimeout("look in #" .. gemsack.id, 3, "In the|There is nothing")
    pause(0.3)

    local gems_on_hand = {}
    for _, obj in ipairs(gemsack.contents or {}) do
        if obj:type_p("gem") and gem == normalize_gem(obj.name) then
            table.insert(gems_on_hand, obj)
        end
    end

    gems_needed = gems_needed - #gems_on_hand
    echo(">> Checking for " .. gem .. " in " .. realm ..
         ". Need: " .. (gems_needed + #gems_on_hand) ..
         ", Have: " .. #gems_on_hand .. ".")

    -- Find the gemshop in realm
    local gemshop_id = nil
    local gemshop_ids = Map.tags("gemshop")
    for _, rid in ipairs(gemshop_ids) do
        local room = Map.find_room(rid)
        if room and room.location and Regex.test(realm, room.location) then
            gemshop_id = rid
            break
        end
    end

    if not gemshop_id then
        echo("** Failed to find gemshop for realm: " .. realm)
        return
    end

    -- Raid stockpile if needed
    if gems_needed > 0 then
        -- Prefer FWI locker if we have one
        local has_fwi_locker = false
        for locker_id, _ in pairs(sett.lockers) do
            if fwi(locker_id) then
                go2(tonumber(locker_id))
                has_fwi_locker = true
                break
            end
        end

        if not has_fwi_locker then
            go2(gemshop_id)
        end

        local closest_id     = tostring(closest_locker())
        local closest_data   = sett.lockers[closest_id]
        local jar_data       = nil
        if closest_data then
            for _, j in ipairs(closest_data.jars) do
                if j.gem == gem then jar_data = j; break end
            end
        end

        if gems_needed > 0 and jar_data and jar_data.count >= gems_needed then
            cmd_get_gems(gems_needed, gem, closest_id)
        end
    end

    -- Refresh on-hand count
    dothistimeout("look in #" .. gemsack.id, 3, "In the|There is nothing")
    pause(0.3)
    gems_on_hand = {}
    for _, obj in ipairs(gemsack.contents or {}) do
        if obj:type_p("gem") and gem == normalize_gem(obj.name) then
            table.insert(gems_on_hand, obj)
        end
    end

    -- Go to gemshop and sell
    go2(gemshop_id)
    for _, gem_obj in ipairs(gems_on_hand) do
        fput("get #" .. gem_obj.id)
        fput("sell #" .. gem_obj.id)
    end
end

local function cmd_combine()
    local id = tostring(closest_locker())
    go2_locker(tonumber(id))
    open_locker()

    local cached = sett.lockers[id]
    if not cached or not cached.jars then
        echo("** No cached index found. Run ;shoard index first.")
        return
    end

    -- Find gem types with more than one jar in the cached index
    local gem_counts = {}
    for _, jar in ipairs(cached.jars) do
        local key = normalize_gem(jar.gem)
        gem_counts[key] = (gem_counts[key] or 0) + 1
    end

    local locker = get_locker_with_contents()
    if not locker then
        echo("** Failed to find locker.")
        return
    end

    -- Get current jars from locker (what's actually there)
    local current_jars = {}
    for _, obj in ipairs(locker.contents or {}) do
        if (string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$"))
            and obj.after_name then
            local key = normalize_gem(obj.after_name)
            if not current_jars[key] then current_jars[key] = {} end
            table.insert(current_jars[key], obj)
        end
    end

    -- Process each duplicated gem type
    for gem_name, count in pairs(gem_counts) do
        if count < 2 then goto continue end
        local jars = current_jars[gem_name]
        if not jars or #jars < 2 then goto continue end

        echo(">> Combining " .. gem_name .. " jars...")

        -- Look inside each jar to get counts
        local jar_details = {}
        for _, jar in ipairs(jars) do
            local res = dothistimeout("look in #" .. jar.id .. " from #" .. locker.id, 3,
                "Inside .* you see %d+ portion")
            pause(0.1)
            if res then
                local cnt_str = string.match(res, "you see (%d+) portion")
                if cnt_str then
                    table.insert(jar_details, {
                        jar_obj = jar,
                        count   = tonumber(cnt_str) or 0,
                        full    = string.find(res, "It is full") ~= nil,
                    })
                end
            end
        end

        if #jar_details < 2 then goto continue end

        -- Pick destination: jar with most gems
        table.sort(jar_details, function(a, b) return a.count > b.count end)
        local dest_data = jar_details[1]
        local dest_jar  = dest_data.jar_obj
        local sources   = {}
        for i = 2, #jar_details do table.insert(sources, jar_details[i]) end

        -- Step 1: Extract gems from source jars into gemsack
        local collected_gem_ids = {}

        for _, jd in ipairs(sources) do
            if jd.count <= 0 then goto next_source end

            local jar = jd.jar_obj
            fput("get #" .. jar.id .. " from #" .. locker.id)
            pause(0.5)

            local extracted  = 0
            local attempts   = 0
            local max_tries  = jd.count * 2

            while extracted < jd.count and attempts < max_tries do
                local res = dothistimeout("shake #" .. jar.id, 3,
                    "fall into your left hand|That was the last|You'll need a free hand")

                if res and string.find(res, "You'll need a free hand") then
                    -- Left hand full: stow and retry without counting this as an attempt
                    echo(">> Left hand full while shaking. Stowing...")
                    fput("stow left")
                    pause(0.5)
                else
                    local gem = GameObj.left_hand()
                    if not gem or not gem:type_p("gem") then break end

                    table.insert(collected_gem_ids, gem.id)
                    fput("stow left gem")
                    extracted = extracted + 1
                    pause(0.5)
                    attempts  = attempts + 1
                end
            end

            if attempts >= max_tries then
                echo("** Extraction failed after " .. max_tries .. " attempts for " .. gem_name .. ". Aborting combine.")
                fput("put #" .. jar.id .. " in locker")
                close_locker()
                leave_locker()
                return
            end

            fput("put #" .. jar.id .. " in locker")
            pause(0.5)

            ::next_source::
        end

        -- Step 2: Deposit collected gems into destination jar
        fput("get #" .. dest_jar.id .. " from #" .. locker.id)
        pause(0.5)

        for _, gem_id in ipairs(collected_gem_ids) do
            local res = dothistimeout("_drag #" .. gem_id .. " #" .. dest_jar.id, 3,
                "You add|You put|is full|does not appear")
            if res and string.find(res, "is full") then break end
        end

        fput("put #" .. dest_jar.id .. " in locker")
        pause(0.5)

        echo(">> Combined " .. gem_name .. " jars.")

        -- Reopen locker between gem types
        open_locker()

        ::continue::
    end

    close_locker()
    leave_locker()
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("shoard - Gem Hoarding Script (originally by SpiffyJr, maintained by elanthia-online)")
    respond("")
    respond("shoard is a gem hoarding script designed to make hoarding gems in lockers as fast and easy as possible.")
    respond("")
    respond("Gem hoarding:")
    respond("  add [room number]          adds locker of current or optionally defined [room number] as hoarding location.")
    respond("                             For reliability this should be set to the room OUTSIDE the booth.")
    respond("  bounty                     Attempts to raid hoard for bounty gems")
    respond("  combine                    Attempt to combine duplicate gem entries into a single container")
    respond("  debug                      Toggle debug mode")
    respond("  delete [room number]       deletes locker of current or optionally defined [room number] as hoarding location")
    respond("  get # <gem name>           get gems from closest locker hoard")
    respond("  go2                        go2 the nearest locker")
    respond("  index                      index the nearest locker")
    respond("  list [alpha|gem name]      list locker contents")
    respond("  store                      store gems in the nearest locker")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

-- Partial-match command dispatch (mirrors Lich5 ^cmd^ prefix trick)
local command_list = "^add^bounty^combine^debug^delete^get^go2^index^list^store"

local raw_cmd = args[1] and string.lower(args[1]) or nil

if not raw_cmd then
    show_help()
    return
end

-- Find first match in command_list using prefix
local matched_cmd = nil
local pat = "%^(" .. raw_cmd .. "[^%^]*)"
local m = string.match(command_list, pat)
if m then matched_cmd = m end

if not matched_cmd then
    show_help()
    return
end

if matched_cmd == "add" then
    cmd_add(args[2] and tonumber(args[2]) or nil)
elseif matched_cmd == "bounty" then
    cmd_bounty()
elseif matched_cmd == "combine" then
    cmd_combine()
elseif matched_cmd == "debug" then
    sett.debug = not sett.debug
    save_settings(sett)
    if sett.debug then
        echo(">> Debug mode enabled.")
    else
        echo(">> Debug mode disabled.")
    end
elseif matched_cmd == "delete" then
    cmd_delete(args[2] and tonumber(args[2]) or nil)
elseif matched_cmd == "get" then
    local count = tonumber(args[2]) or 0
    local gem   = table.concat(args, " ", 3)
    cmd_get_gems(count, gem)
elseif matched_cmd == "go2" then
    go2_locker()
elseif matched_cmd == "index" then
    cmd_index()
elseif matched_cmd == "list" then
    local filter = table.concat(args, " ", 2)
    cmd_list(filter)
elseif matched_cmd == "store" then
    cmd_store()
else
    show_help()
end
