--- @revenant-script
--- name: egemhoarder
--- version: 1.2.0
--- author: elanthia-online
--- contributors: Caithris, Falicor
--- game: gs
--- description: Premium/Platinum locker gem hoarding with multi-locker, raid, and search
--- tags: gems,hoarding,locker,jars
---
--- Changelog (from Lich5):
---   v1.2.0 (2025-09-09): Convert to YAML/JSON instead of lich.db3
---   v1.1.0 (2025-09-08): Module wrapper, CharSettings sort workaround
---   v1.0.1 (2024-04-04): Help text updates
---   v1.0.0 (2024-04-03): Fork of gemhoarder2 with Ruby 3.x compatibility
---
--- Usage:
---   ;egemhoarder               - Store gems into locker jars (default)
---   ;egemhoarder help          - Show help
---   ;egemhoarder newlocker     - Register a new locker
---   ;egemhoarder list          - List all gems in jars
---   ;egemhoarder alpha         - List gems alphabetically
---   ;egemhoarder search <str>  - Search for a gem
---   ;egemhoarder raid <gem> N  - Raid N of a gem (or "all")
---   ;egemhoarder set <gem> N F - Set gem to N count, F=true/false full
---   ;egemhoarder forget        - Forget all locker contents
---
--- Requires: gemsack and lootsack set via ;vars

silence_me()

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local DATA_FILE = "data/egemhoarder.json"

local function load_hoard()
    if File.exists(DATA_FILE) then
        local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function save_hoard(h)
    File.write(DATA_FILE, Json.encode(h))
end

local hoard = load_hoard()

before_dying(function()
    save_hoard(hoard)
end)

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

local function strip_prefix(name)
    local n = name or ""
    n = string.gsub(n, "^containing ", "")
    n = string.gsub(n, "^large ", "")
    n = string.gsub(n, "^medium ", "")
    n = string.gsub(n, "^small ", "")
    n = string.gsub(n, "^tiny ", "")
    n = string.gsub(n, "^some ", "")
    return n
end

local function sorted_jars()
    local jars = hoard.jars or {}
    local copy = {}
    for _, j in ipairs(jars) do
        table.insert(copy, {
            gem = j.gem,
            count = j.count or 0,
            full = j.full or false,
            location = j.location or "",
        })
    end
    table.sort(copy, function(a, b) return a.count > b.count end)
    return copy
end

local function find_inv_obj(name)
    for _, obj in ipairs(GameObj.inv()) do
        if string.find(string.lower(obj.name), string.lower(name), 1, true) then
            return obj
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Display helpers
--------------------------------------------------------------------------------

local function display_jars(jars)
    respond(pad_left("gem", 35) .. " " .. pad_left("count", 5) .. " " .. pad_left("full", 8) .. "   " .. pad_right("location", 30))
    respond(pad_left("---", 35) .. " " .. pad_left("-----", 5) .. " " .. pad_left("----", 8) .. "   " .. pad_right("------------", 30))
    for _, jar in ipairs(jars) do
        local full_str = tostring(jar.full)
        respond(pad_left(jar.gem, 35) .. " " .. pad_left(tostring(jar.count), 5) .. " " .. pad_left(full_str, 8) .. "   " .. pad_right(jar.location, 30))
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

local cmd = args[1] and string.lower(args[1]) or "none"

if cmd == "help" then
    respond("Usage: ;egemhoarder [help|newlocker|list|alpha|search|forget|raid|set]")
    respond("   help:                      prints this list")
    respond("   newlocker:                 add a new locker to your list")
    respond("   list:                      list all gems currently in jars")
    respond("   alpha:                     list gems alphabetically")
    respond("   search <string>:           search jars for matching gem")
    respond("   forget:                    forget all locker contents")
    respond("   raid <gem|all> <amount>:   raid gems from locker")
    respond("   set <gem> <amount> <full>: set gem count manually")

elseif cmd == "list" then
    display_jars(sorted_jars())

elseif cmd == "alpha" then
    local jars = sorted_jars()
    table.sort(jars, function(a, b) return a.gem < b.gem end)
    display_jars(jars)

elseif cmd == "search" then
    local term = args[2] or ""
    local jars = sorted_jars()
    local filtered = {}
    for _, j in ipairs(jars) do
        if string.find(string.lower(j.gem), string.lower(term), 1, true) then
            table.insert(filtered, j)
        end
    end
    display_jars(filtered)

elseif cmd == "set" then
    local gem = args[2]
    local count = tonumber(args[3]) or 0
    local is_full = (args[4] and string.lower(args[4]) == "true") or false
    local location = args[5]

    if not gem then
        respond("Please specify which gem to modify.")
        return
    end

    if not location then
        -- Get current location
        clear()
        put("location")
        local deadline = os.time() + 3
        while os.time() < deadline do
            local line = get_noblock()
            if line then
                local loc = string.match(line, "current location is (.+) or somewhere close")
                if loc then location = loc; break end
            else
                pause(0.05)
            end
        end
        location = location or "Unknown"
    end

    if not hoard.jars then hoard.jars = {} end

    if count > 0 then
        -- Remove existing entry for this gem
        local new_jars = {}
        for _, j in ipairs(hoard.jars) do
            if j.gem ~= gem then table.insert(new_jars, j) end
        end
        table.insert(new_jars, { gem = gem, count = count, full = is_full, location = location })
        hoard.jars = new_jars
        respond(gem .. ", " .. count .. ", " .. tostring(is_full) .. ", " .. location .. " added.")
    else
        local new_jars = {}
        for _, j in ipairs(hoard.jars) do
            if j.gem ~= gem then table.insert(new_jars, j) end
        end
        hoard.jars = new_jars
        respond("Removing " .. gem .. " from the list.")
    end
    save_hoard(hoard)

elseif cmd == "forget" then
    hoard.jars = nil
    hoard.known_lockers = nil
    save_hoard(hoard)
    respond("Locker contents forgotten.")

elseif cmd == "raid" then
    local gem_arg = args[2]
    local count = tonumber(args[3]) or 1

    if not gem_arg then
        respond("Usage: ;egemhoarder raid <gem|all> [amount]")
        return
    end

    -- Get current location
    clear()
    put("location")
    local location = "Unknown"
    local deadline = os.time() + 3
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            local loc = string.match(line, "current location is (.+) or somewhere close")
            if loc then location = loc; break end
        else
            pause(0.05)
        end
    end

    local gemsack_name = Vars.gemsack or ""
    if gemsack_name == "" then
        echo("gemsack is not set. Use ;vars set gemsack=<container>")
        return
    end
    local gemsack = find_inv_obj(gemsack_name)
    if not gemsack then
        echo("Could not find gemsack: " .. gemsack_name)
        return
    end

    -- Find matching jars at this location
    local targets = {}
    for _, jar in ipairs(hoard.jars or {}) do
        if jar.location == location then
            if gem_arg == "all" then
                if jar.count >= count then table.insert(targets, jar) end
            else
                if jar.gem == gem_arg or jar.gem == gem_arg .. "s" or jar.gem == gem_arg .. "es" then
                    if jar.count >= count then table.insert(targets, jar) end
                end
            end
        end
    end

    if #targets == 0 then
        echo("No matching gems found at " .. location .. " with enough quantity.")
        return
    end

    -- Open locker to get jars
    dothistimeout("close locker", 1, "You close|That is already|faint creak")
    local open_result = dothistimeout("open locker", 5, 'exist="')
    if not open_result then
        echo("Failed to open locker.")
        return
    end

    local locker_id = string.match(open_result, 'exist="(%d+)"')
    if not locker_id then
        echo("Could not identify locker.")
        return
    end

    -- Try bin first, then wardrobe
    for _, jar_data in ipairs(targets) do
        -- Look in bin/wardrobe for the jar
        for _, furniture in ipairs({ "bin", "wardrobe" }) do
            dothistimeout("close locker", 1, "You close|That is already|faint creak")
            local res = dothistimeout("open locker", 5, 'noun="' .. furniture .. '"')
            if res then
                local furn_id = string.match(res, 'exist="(%d+)" noun="' .. furniture .. '"')
                if furn_id then
                    dothistimeout("look in #" .. furn_id, 3, "In the")
                    pause(0.3)

                    -- Find matching jar
                    local container_contents = GameObj.containers and GameObj.containers[furn_id] or {}
                    for _, obj in ipairs(container_contents) do
                        if (string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$"))
                            and obj.after_name then
                            local stripped = strip_prefix(obj.after_name)
                            if string.find(stripped, jar_data.gem, 1, true) then
                                fput("get #" .. obj.id .. " from #" .. furn_id)
                                for _ = 1, count do
                                    dothistimeout("shake #" .. obj.id, 3, "shake")
                                    -- Determine which hand has the gem
                                    local rh = GameObj.right_hand()
                                    local lh = GameObj.left_hand()
                                    local gem_obj = nil
                                    if rh and rh.id ~= obj.id then gem_obj = rh
                                    elseif lh and lh.id ~= obj.id then gem_obj = lh end
                                    if gem_obj then
                                        fput("put #" .. gem_obj.id .. " in #" .. gemsack.id)
                                    end
                                    jar_data.count = jar_data.count - 1
                                    jar_data.full = false
                                end

                                if jar_data.count < 1 then
                                    -- Move empty jar to chest
                                    fput("put #" .. obj.id .. " in chest")
                                    -- Remove from hoard
                                    local new_jars = {}
                                    for _, j in ipairs(hoard.jars) do
                                        if j ~= jar_data then table.insert(new_jars, j) end
                                    end
                                    hoard.jars = new_jars
                                else
                                    fput("put #" .. obj.id .. " in " .. furniture)
                                end
                                goto next_target
                            end
                        end
                    end
                end
            end
        end
        ::next_target::
    end

    dothistimeout("close locker", 1, "You close|That is already|faint creak")
    save_hoard(hoard)

elseif cmd == "newlocker" or cmd == "none" then
    -- Validate requirements
    local gemsack_name = Vars.gemsack or ""
    local lootsack_name = Vars.lootsack or ""
    if gemsack_name == "" then
        echo("gemsack is not set. Use ;vars set gemsack=<container>")
        return
    end
    if lootsack_name == "" then
        echo("lootsack is not set. Use ;vars set lootsack=<container>")
        return
    end

    local gemsack = find_inv_obj(gemsack_name)
    local lootsack = find_inv_obj(lootsack_name)
    if not gemsack then echo("Could not find gemsack: " .. gemsack_name); return end
    if not lootsack then echo("Could not find lootsack: " .. lootsack_name); return end

    -- Open gemsack and lootsack
    dothistimeout("open #" .. gemsack.id, 5, "You open|already open|You carefully|You unfasten")
    dothistimeout("look in #" .. gemsack.id, 5, "In .* you see")
    dothistimeout("open #" .. lootsack.id, 5, "You open|already open|You carefully|You unfasten")

    empty_hands()

    -- Open locker
    dothistimeout("close locker", 1, "You close|That is already|faint creak")
    local open_result = dothistimeout("open locker", 5, 'exist="')
    if not open_result then
        echo("Failed to open locker.")
        return
    end

    -- Get location
    clear()
    put("location")
    local location = "Unknown"
    local ldeadline = os.time() + 3
    while os.time() < ldeadline do
        local line = get_noblock()
        if line then
            local loc = string.match(line, "current location is (.+) or somewhere close")
            if loc then location = loc; break end
        else
            pause(0.05)
        end
    end

    if cmd == "newlocker" or not hoard.jars then
        -- Index this locker
        echo("Indexing locker at " .. location .. "...")

        hoard.jars = hoard.jars or {}
        hoard.known_lockers = hoard.known_lockers or {}

        -- First move all jars from wardrobe/bin to chest for scanning
        for _, jtype in ipairs({ "jar", "beaker", "bottle" }) do
            echo("Moving all " .. jtype .. "s from wardrobe/bin into chest")
            while true do
                dothistimeout("get " .. jtype .. " from wardrobe", 3, "You remove|Get what")
                local res = dothistimeout("put my " .. jtype .. " in chest", 3, "You put|I could not find")
                if not res or not string.find(res, "You put") then break end
            end
            while true do
                dothistimeout("get " .. jtype .. " from bin", 3, "You remove|Get what")
                local res = dothistimeout("put my " .. jtype .. " in chest", 3, "You put|I could not find")
                if not res or not string.find(res, "You put") then break end
            end
        end

        -- Reopen chest and scan jars
        dothistimeout("close locker", 1, "You close|That is already|faint creak")
        open_result = dothistimeout("open locker", 5, 'noun="chest"')
        local locker_id = string.match(open_result or "", 'exist="(%d+)"')

        if locker_id then
            dothistimeout("look in #" .. locker_id, 3, "In the")
            pause(0.5)
            local contents = GameObj.containers and GameObj.containers[locker_id] or {}

            for _, obj in ipairs(contents) do
                if string.match(obj.noun, "^jar$") or string.match(obj.noun, "^bottle$") or string.match(obj.noun, "^beaker$") then
                    if obj.after_name then
                        local look_res = dothistimeout("look in #" .. obj.id .. " from #" .. locker_id, 3,
                            "Inside .* you see %d+ portion|could not find")
                        if look_res and string.find(look_res, "portion") then
                            local ct = string.match(look_res, "you see (%d+) portion")
                            local is_full = string.find(look_res, "It is full") ~= nil
                            local gem = strip_prefix(obj.after_name)

                            table.insert(hoard.jars, {
                                gem = gem,
                                count = tonumber(ct) or 0,
                                full = is_full,
                                location = location,
                            })

                            -- Sort jar: full -> wardrobe, partial -> bin
                            fput("get #" .. obj.id .. " from #" .. locker_id)
                            if is_full then
                                fput("put #" .. obj.id .. " in wardrobe")
                            else
                                fput("put #" .. obj.id .. " in bin")
                            end
                        end
                    end
                end
            end
        end

        -- Track known locker
        local found = false
        for _, loc in ipairs(hoard.known_lockers) do
            if loc == location then found = true; break end
        end
        if not found then table.insert(hoard.known_lockers, location) end

        save_hoard(hoard)
        respond("Locker indexed and sorted. " .. #(hoard.jars) .. " jars cataloged.")

        if cmd == "newlocker" then
            respond("Re-run without arguments to deposit gems.")
            return
        end
    end

    -- Default: store gems into existing jars
    if cmd == "none" then
        echo("Storing gems from gemsack into locker jars...")

        -- Open bin to access partial jars
        dothistimeout("close locker", 1, "You close|That is already|faint creak")
        open_result = dothistimeout("open locker", 5, 'noun="bin"')
        local bin_id = string.match(open_result or "", 'exist="(%d+)"')

        if bin_id then
            dothistimeout("look in #" .. bin_id, 3, "In the")
            pause(0.3)
            local bin_contents = GameObj.containers and GameObj.containers[bin_id] or {}

            for _, jar_obj in ipairs(bin_contents) do
                if (string.match(jar_obj.noun, "^jar$") or string.match(jar_obj.noun, "^bottle$") or string.match(jar_obj.noun, "^beaker$"))
                    and jar_obj.after_name then
                    local stripped = strip_prefix(jar_obj.after_name)
                    local jar_data = nil
                    for _, j in ipairs(hoard.jars) do
                        if j.gem == stripped then jar_data = j; break end
                    end

                    -- Find matching gems in gemsack
                    local matching = {}
                    for _, gem_obj in ipairs(gemsack.contents or {}) do
                        if strip_prefix(gem_obj.name) == stripped then
                            table.insert(matching, gem_obj)
                        end
                    end

                    if #matching > 0 and jar_data and not jar_data.full then
                        fput("get #" .. jar_obj.id .. " from #" .. bin_id)
                        for _, gem in ipairs(matching) do
                            local res = dothistimeout("_drag #" .. gem.id .. " #" .. jar_obj.id, 3,
                                "You add|is full|does not appear")
                            if res and string.find(res, "filling it") then
                                jar_data.count = jar_data.count + 1
                                jar_data.full = true
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break
                            elseif res and string.find(res, "You add") then
                                jar_data.count = jar_data.count + 1
                            elseif res and string.find(res, "is full") then
                                jar_data.full = true
                                fput("put #" .. gem.id .. " in #" .. gemsack.id)
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break
                            else
                                fput("put #" .. gem.id .. " in #" .. lootsack.id)
                            end
                        end
                        if checkright() then
                            fput("put #" .. jar_obj.id .. " in #" .. bin_id)
                        end
                    end
                end
            end
        end

        dothistimeout("close locker", 1, "You close|That is already|faint creak")
        save_hoard(hoard)
        fill_hands()
        echo("Gem storage complete.")
    end
end
