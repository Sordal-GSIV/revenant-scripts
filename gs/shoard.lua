--- @revenant-script
--- name: shoard
--- version: 1.2.1
--- author: SpiffyJr
--- contributors: elanthia-online
--- game: gs
--- description: Gem hoarding into locker jars with indexing, store, retrieve, bounty, and combine
--- tags: gem,hoarding,locker,jars
---
--- Changelog (from Lich5):
---   v1.2.1 (2025-11-10): Minor bugfixes in load, default settings init
---   v1.2.0 (2025-03-22): Gem prefix normalization, combine command
---   v1.1.0 (2022-03-13): Standard locker support, help text
---   v1.0.0 (2021-10-11): Initial release
---
--- Usage:
---   ;shoard help         - Show help
---   ;shoard add [room]   - Add locker at current or specified room
---   ;shoard delete [room]- Remove locker
---   ;shoard index        - Index nearest locker jars
---   ;shoard store        - Store gems from gemsack into locker jars
---   ;shoard list [filter] - List locker contents
---   ;shoard get N <gem>  - Retrieve N gems from locker
---   ;shoard go2          - Navigate to nearest locker
---   ;shoard bounty       - Raid hoard for bounty gems
---   ;shoard combine      - Merge duplicate gem jars

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
            local id, stype = string.match(line, 'exist="([^"]+)".-%((%a+)%)')
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
    return Room.find_nearest(keys)
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

    -- Check again
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^locker$") or string.match(obj.noun, "^counter$") then
            return
        end
    end

    -- Try to enter through opening/curtain
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^opening$") or string.match(obj.noun, "^curtain$") or string.match(obj.noun, "^tapestry$") then
            local current = Room.id
            move("go " .. (obj.noun == "tapestry" and "opening" or obj.noun))
            if current == Room.id then
                echo(">> Someone is using that locker. Waiting...")
                wait_while(function() return current == Room.id end)
            end
            return
        end
    end

    echo("** Failed to find locker entrance.")
end

local function leave_locker()
    for _, obj in ipairs(find_locker_entrance()) do
        if string.match(obj.noun, "^opening$") or string.match(obj.noun, "^curtain$") then
            local current = Room.id
            move("go " .. obj.noun)
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
    -- Try counter
    for _, obj in ipairs(GameObj.room_desc() or {}) do
        if string.match(obj.noun, "^counter$") then
            fput("look on #" .. obj.id)
            pause(0.1)
            if obj.contents then
                for _, c in ipairs(obj.contents) do
                    if string.match(c.noun, "locker") then return c end
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function cmd_add(room_id)
    room_id = room_id or Room.id
    room_id = tostring(room_id)
    if sett.lockers[room_id] then
        echo("** Locker already exists.")
        return
    end
    sett.lockers[room_id] = { empty = 0, jars = {} }
    save_settings(sett)
    echo(">> Locker added: " .. room_id)
end

local function cmd_delete(room_id)
    room_id = room_id or Room.id
    room_id = tostring(room_id)
    if not sett.lockers[room_id] then
        echo("** You have not added that locker.")
        return
    end
    sett.lockers[room_id] = nil
    save_settings(sett)
    echo(">> Locker removed: " .. room_id)
end

local function cmd_index()
    local id = tostring(closest_locker())
    go2_locker(tonumber(id))
    open_locker()

    local locker = find_locker_obj()
    if not locker then
        echo("** Failed to find locker.")
        return
    end

    -- Look in locker to populate contents
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
                            gem = normalize_gem(obj.after_name),
                            count = tonumber(count_str) or 0,
                            full = full,
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
        respond("")
        respond("Locker at room #" .. room_id .. " (" .. #data.jars .. " jars, " .. data.empty .. " empty)")
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
    end
end

local function cmd_get_gems(count, gem_name)
    if not count or count == 0 then
        echo("** Invalid gem count.")
        return
    end
    if not gem_name or gem_name == "" then
        echo("** Invalid or missing gem name.")
        return
    end

    local room_id = tostring(closest_locker())
    if not sett.lockers[room_id] then cmd_index() end

    local locker_data = sett.lockers[room_id]
    local gem_key = normalize_gem(gem_name)
    local jar_data = nil
    for _, j in ipairs(locker_data.jars) do
        if normalize_gem(j.gem) == gem_key then
            jar_data = j
            break
        end
    end

    if not jar_data or jar_data.count < count then
        echo(">> Not enough " .. gem_name .. " in hoard.")
        return
    end

    go2_locker()
    open_locker()

    local locker = find_locker_obj()
    if not locker then echo("** Failed to find locker"); return end
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
            jar_data.full = false
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

    local sacks = get_stow_sacks()
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

    -- Find jars that match gems in gemsack
    local has_gems = false
    if gemsack.contents then
        for _, obj in ipairs(gemsack.contents) do
            if obj.type and string.find(obj.type, "gem") then
                has_gems = true
                break
            end
        end
    end
    if not has_gems then
        echo(">> No gems to store.")
        return
    end

    go2_locker()
    open_locker()

    local locker = find_locker_obj()
    if not locker then echo("** Failed to find locker"); return end
    dothistimeout("look in #" .. locker.id, 3, "In the|There is nothing")
    pause(0.3)

    -- Fill existing jars
    for _, jar_data in ipairs(locker_data.jars) do
        if not jar_data.full then
            local gem_key = normalize_gem(jar_data.gem)
            local matching_gems = {}
            for _, obj in ipairs(gemsack.contents or {}) do
                if obj.type and string.find(obj.type, "gem") and normalize_gem(obj.name) == gem_key then
                    table.insert(matching_gems, obj)
                end
            end

            if #matching_gems > 0 then
                -- Find jar in locker
                local jar_obj = nil
                for _, obj in ipairs(locker.contents or {}) do
                    if (string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$"))
                        and obj.after_name and normalize_gem(obj.after_name) == gem_key then
                        jar_obj = obj
                        break
                    end
                end

                if jar_obj then
                    fput("get #" .. jar_obj.id .. " from #" .. locker.id)
                    pause(0.1)
                    for _, gem in ipairs(matching_gems) do
                        local res = dothistimeout("_drag #" .. gem.id .. " #" .. jar_obj.id, 3,
                            "You add|is full|does not appear")
                        if res and string.find(res, "filling it") then
                            jar_data.count = jar_data.count + 1
                            jar_data.full = true
                            break
                        elseif res and string.find(res, "You add") then
                            jar_data.count = jar_data.count + 1
                        elseif res and string.find(res, "is full") then
                            jar_data.full = true
                            fput("stow #" .. gem.id)
                            break
                        else
                            fput("stow #" .. gem.id)
                        end
                    end
                    fput("put #" .. jar_obj.id .. " in locker")
                end
            end
        end
    end

    save_settings(sett)
    close_locker()
    leave_locker()
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("shoard - Gem Hoarding Script (originally by SpiffyJr)")
    respond("")
    respond("  ;shoard add [room]     - Add locker at current or specified room")
    respond("  ;shoard delete [room]  - Remove locker")
    respond("  ;shoard bounty         - Raid hoard for bounty gems")
    respond("  ;shoard get N <gem>    - Get gems from nearest locker")
    respond("  ;shoard go2            - Navigate to nearest locker")
    respond("  ;shoard index          - Index nearest locker")
    respond("  ;shoard list [filter]  - List contents (filter: alpha, or gem name)")
    respond("  ;shoard store          - Store gems into nearest locker")
    respond("  ;shoard combine        - Merge duplicate gem jars")
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

local cmd = args[1] and string.lower(args[1]) or nil

if not cmd then
    show_help()
elseif cmd == "help" then
    show_help()
elseif cmd == "add" then
    cmd_add(args[2] and tonumber(args[2]) or nil)
elseif cmd == "delete" or cmd == "del" then
    cmd_delete(args[2] and tonumber(args[2]) or nil)
elseif cmd == "index" then
    cmd_index()
elseif cmd == "list" then
    local filter = ""
    for i = 2, #args do
        if i > 2 then filter = filter .. " " end
        filter = filter .. args[i]
    end
    cmd_list(filter)
elseif cmd == "get" then
    local count = tonumber(args[2]) or 0
    local gem = table.concat(args, " ", 3)
    cmd_get_gems(count, gem)
elseif cmd == "go2" then
    go2_locker()
elseif cmd == "store" then
    cmd_store()
elseif cmd == "bounty" then
    echo(">> Bounty raid not yet fully ported. Use ;shoard get N <gem> manually.")
elseif cmd == "combine" then
    echo(">> Combine not yet fully ported. Use ;shoard index to refresh after manual merge.")
else
    show_help()
end
