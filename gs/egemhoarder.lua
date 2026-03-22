--- @revenant-script
--- name: egemhoarder
--- version: 1.2.0
--- author: elanthia-online
--- contributors: Caithris, Falicor
--- game: gs
--- description: Premium/Platinum locker gem hoarding with multi-locker, raid, and search
--- tags: gems,hoarding,locker,jars
--- @lic-certified: complete 2026-03-19
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
-- Persistence (per-character data file)
--------------------------------------------------------------------------------

local char_name = GameState.name or "unknown"
local DATA_DIR  = "data/" .. char_name
local DATA_FILE = DATA_DIR .. "/egemhoarder.json"

local function load_hoard()
    if File.exists(DATA_FILE) then
        local ok, data = pcall(function() return Json.decode(File.read(DATA_FILE)) end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function save_hoard(h)
    if not File.is_dir(DATA_DIR) then File.mkdir(DATA_DIR) end
    File.write(DATA_FILE, Json.encode(h))
end

local hoard = load_hoard()
local original_hoard_json = Json.encode(hoard)

before_dying(function()
    local current_json = Json.encode(hoard)
    if current_json ~= original_hoard_json then
        save_hoard(hoard)
    end
end)

--------------------------------------------------------------------------------
-- empty_hands / fill_hands (GS: stow to lootsack/restore from lootsack)
--------------------------------------------------------------------------------

local stashed_right = nil
local stashed_left  = nil

local function find_inv_obj(name)
    for _, obj in ipairs(GameObj.inv()) do
        if string.find(string.lower(obj.name), string.lower(name), 1, true) then
            return obj
        end
    end
    return nil
end

local function empty_hands()
    waitrt()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local lootsack_name = Vars.lootsack or ""
    local ls = (lootsack_name ~= "") and find_inv_obj(lootsack_name) or nil

    if rh and rh.name ~= "" and rh.name ~= "Empty" and rh.id then
        stashed_right = rh.id
        if ls then
            fput("put #" .. rh.id .. " in #" .. ls.id)
        else
            fput("stow right")
        end
    end
    if lh and lh.name ~= "" and lh.name ~= "Empty" and lh.id then
        stashed_left = lh.id
        if ls then
            fput("put #" .. lh.id .. " in #" .. ls.id)
        else
            fput("stow left")
        end
    end
end

local function fill_hands()
    waitrt()
    local lootsack_name = Vars.lootsack or ""
    local ls = (lootsack_name ~= "") and find_inv_obj(lootsack_name) or nil

    if stashed_right then
        if ls then
            fput("get #" .. stashed_right .. " from #" .. ls.id)
        else
            fput("get #" .. stashed_right)
        end
        stashed_right = nil
    end
    if stashed_left then
        if ls then
            fput("get #" .. stashed_left .. " from #" .. ls.id)
        else
            fput("get #" .. stashed_left)
        end
        stashed_left = nil
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local GEM_BLACKLIST = "oblivion quartz$|doomstone|urglaes fang"

local function strip_prefix(name)
    if not name then return "" end
    return (name
        :gsub("^containing ", "")
        :gsub("^large ", "")
        :gsub("^medium ", "")
        :gsub("^small ", "")
        :gsub("^tiny ", "")
        :gsub("^some ", ""))
end

local function pad_right(s, w)
    s = tostring(s or "")
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function pad_left(s, w)
    s = tostring(s or "")
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

-- Match gem name against jar gem (handles pluralization: s, es suffixes)
local function gem_matches_jar(gem_name, jar_gem)
    local g = strip_prefix(gem_name)
    local j = strip_prefix(jar_gem)
    if g == j         then return true end
    if g .. "s"  == j then return true end
    if g .. "es" == j then return true end
    if g == j .. "s"  then return true end
    if g == j .. "es" then return true end
    return false
end

local function sorted_jars()
    local copy = {}
    for _, j in ipairs(hoard.jars or {}) do
        table.insert(copy, {
            gem      = j.gem,
            count    = j.count or 0,
            full     = j.full or false,
            location = j.location or "",
        })
    end
    table.sort(copy, function(a, b) return a.count > b.count end)
    return copy
end

local function display_jars(jars)
    respond(pad_left("gem", 35) .. " " .. pad_left("count", 5) .. " " ..
            pad_left("full", 8)  .. "   " .. pad_right("location", 30))
    respond(pad_left("---", 35) .. " " .. pad_left("-----", 5) .. " " ..
            pad_left("----", 8)  .. "   " .. pad_right("------------", 30))
    for _, jar in ipairs(jars) do
        respond(pad_left(jar.gem, 35)              .. " " ..
                pad_left(tostring(jar.count), 5)   .. " " ..
                pad_left(tostring(jar.full), 8)    .. "   " ..
                pad_right(jar.location, 30))
    end
end

-- Get current room location name
local function get_location()
    local line = dothistimeout("location", 5, "current location is")
    if line then
        local loc = string.match(line, "current location is (.+) or somewhere close")
        if loc then return loc end
    end
    return "Unknown"
end

-- Open locker furniture by type; returns the furniture XML id or nil
local function open_locker_furniture(noun)
    dothistimeout("close locker", 1, "You close|That is already closed|faint")
    local res = dothistimeout("open locker", 5, 'exist="')
    if not res then return nil end
    -- First try exact noun match
    local id = string.match(res, 'exist="(%d+)" noun="' .. noun .. '"')
    if id then return id end
    -- Fallback: any exist="" match (for when noun order varies)
    return string.match(res, 'exist="(%d+)"')
end

-- Look in container and return its contents table
local function look_in(container_id)
    dothistimeout("look in #" .. container_id, 3, "In the|nothing")
    pause(0.3)
    return GameObj.containers()[container_id] or {}
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local cmd = Script.vars[1] and string.lower(Script.vars[1]) or "none"

-- ── HELP ─────────────────────────────────────────────────────────────────────
if cmd == "help" then
    respond("Usage: ;egemhoarder [help|newlocker|list|alpha|search|forget]")
    respond("   help:                      prints out this list.")
    respond("   newlocker:                 add a new locker to your list.")
    respond("   list:                      list all gems currently in jars.")
    respond("   alpha:                     list all gems currently in jars in alphabetical order.")
    respond("   search <string>:           list all gems currently in jars that match a search string.")
    respond("   forget:                    forget the gem contents in all your lockers.")
    respond("   raid <gem> <amount>:       raid <gem> where gem can be \"all\" for the specified amount.")
    respond("   set <gem> <amount> <full>: set the selected gem to the specified amount.")
    respond(" ")
    respond("   set example: ;egemhoarder \"golden beryl gems\" 15 false")
    respond("   another  set example: ;egemhoarder \"fire opals\" 0 false Solhaven")
    respond(" ")
    respond("   to delete a jar, please use an amount of 0")
    respond("   to move a jar to another locker, please first delete the jar, and then use the set command")
    respond("   with an amount, or run this script at your new locker location.")

-- ── LIST ─────────────────────────────────────────────────────────────────────
elseif cmd == "list" then
    display_jars(sorted_jars())

-- ── ALPHA ────────────────────────────────────────────────────────────────────
elseif cmd == "alpha" then
    local jars = sorted_jars()
    table.sort(jars, function(a, b) return a.gem < b.gem end)
    display_jars(jars)

-- ── SEARCH ───────────────────────────────────────────────────────────────────
elseif cmd == "search" then
    local term = Script.vars[2] or ""
    local filtered = {}
    for _, j in ipairs(sorted_jars()) do
        if string.find(string.lower(j.gem), string.lower(term), 1, true) then
            table.insert(filtered, j)
        end
    end
    display_jars(filtered)

-- ── SET ──────────────────────────────────────────────────────────────────────
elseif cmd == "set" then
    local gem      = Script.vars[2]
    local count    = tonumber(Script.vars[3])
    local is_full  = Script.vars[4] and string.lower(Script.vars[4]) == "true" or false
    local location = Script.vars[5]

    if not gem then
        respond("Please specify which gem to modify.")
        return
    end
    if not Script.vars[3] then
        respond("jar amount not specified, defaulting to removal.")
        count = 0
    else
        count = tonumber(Script.vars[3]) or 0
    end
    if not Script.vars[4] then
        respond("jar full true/false not specified, defaulting to false.")
        is_full = false
    end
    if not location then
        location = get_location()
        respond("setting location to " .. location .. ".")
    end

    hoard.jars = hoard.jars or {}

    if count > 0 then
        local new_jars = {}
        for _, j in ipairs(hoard.jars) do
            if j.gem ~= gem then table.insert(new_jars, j) end
        end
        table.insert(new_jars, { gem = gem, count = count, full = is_full, location = location })
        hoard.jars = new_jars
        respond(gem .. ", " .. count .. ", " .. tostring(is_full) .. ", " .. location .. " have been added.")
    else
        local new_jars = {}
        for _, j in ipairs(hoard.jars) do
            if j.gem ~= gem then table.insert(new_jars, j) end
        end
        hoard.jars = new_jars
        respond("Removing " .. gem .. " from the list.")
    end
    save_hoard(hoard)

-- ── FORGET ───────────────────────────────────────────────────────────────────
elseif cmd == "forget" then
    hoard.jars          = nil
    hoard.known_lockers = nil
    save_hoard(hoard)
    respond("Locker contents forgotten.")

-- ── RAID ─────────────────────────────────────────────────────────────────────
elseif cmd == "raid" then
    local gem_arg = Script.vars[2]
    local count   = tonumber(Script.vars[3]) or 1

    if not gem_arg then
        respond("Please specify a gem raid or use \"all\" to select all.")
        respond("Usage:")
        respond("        ;egemhoarder raid <gem|all> [amount]")
        return
    end
    if not Script.vars[3] then
        respond("defaulting to 1 gem to raid.")
    end

    local gemsack_name = Vars.gemsack or ""
    if gemsack_name == "" then
        echo("error: gemsack is not set. (;vars set gemsack=<container name>)")
        return
    end
    local gemsack = find_inv_obj(gemsack_name)
    if not gemsack then
        echo("error: failed to find your gemsack")
        return
    end

    local location = get_location()
    local preserve = (gem_arg == "all") and 1 or 0

    -- Categorize target jars at this location into wardrobe (full) and bin (partial)
    local gem_wardrobe = {}
    local gem_bin      = {}
    for _, jar in ipairs(hoard.jars or {}) do
        if jar.location == location then
            local match = gem_arg == "all"
                or jar.gem == gem_arg
                or jar.gem == gem_arg .. "s"
                or jar.gem == gem_arg .. "es"
            if match then
                if jar.full then
                    table.insert(gem_wardrobe, jar.gem)
                elseif (jar.count or 0) >= count then
                    table.insert(gem_bin, jar.gem)
                end
            end
        end
    end

    local function find_jar_hash(gem_name)
        for _, j in ipairs(hoard.jars or {}) do
            if j.gem == gem_name then return j end
        end
        return nil
    end

    local function shake_into_gemsack(jar_obj, jar_data, n)
        for _ = 1, n do
            dothistimeout("shake #" .. jar_obj.id, 3, "shake")
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local gem_obj = nil
            if rh and rh.id ~= jar_obj.id then
                gem_obj = rh
            elseif lh and lh.id ~= jar_obj.id then
                gem_obj = lh
            end
            if gem_obj then
                fput("put #" .. gem_obj.id .. " in #" .. gemsack.id)
            end
            jar_data.count = (jar_data.count or 1) - 1
            jar_data.full  = false
        end
    end

    -- Raid full jars from wardrobe
    for _, gem_item in ipairs(gem_wardrobe) do
        local jh = find_jar_hash(gem_item)
        if jh and (jh.count or 0) >= count then
            local furn_id = open_locker_furniture("wardrobe")
            if furn_id then
                local contents = look_in(furn_id)
                for _, obj in ipairs(contents) do
                    if string.match(obj.noun or "", "^jar$") or
                       string.match(obj.noun or "", "^bottle$") or
                       string.match(obj.noun or "", "^beaker$") then
                        if obj.after_name and gem_matches_jar(strip_prefix(obj.after_name), gem_item) then
                            local r = dothistimeout("get #" .. obj.id .. " from #" .. furn_id, 3, "You remove|Get what")
                            if r and string.find(r, "You remove") then
                                shake_into_gemsack(obj, jh, count)
                                if (jh.count or 0) < 1 then
                                    local nj = {}
                                    for _, j in ipairs(hoard.jars) do
                                        if j ~= jh then table.insert(nj, j) end
                                    end
                                    hoard.jars = nj
                                    fput("put #" .. obj.id .. " in chest")
                                else
                                    fput("put #" .. obj.id .. " in bin")
                                end
                            else
                                echo("Sorry. Locker has refreshed. Please re-start ;egemhoarder raid.")
                                save_hoard(hoard)
                                return
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    -- Raid partial jars from bin
    for _, gem_item in ipairs(gem_bin) do
        local jh = find_jar_hash(gem_item)
        if jh and (jh.count or 0) >= (count + preserve) then
            local furn_id = open_locker_furniture("bin")
            if not furn_id then furn_id = open_locker_furniture("locker") end
            if furn_id then
                local contents = look_in(furn_id)
                for _, obj in ipairs(contents) do
                    if string.match(obj.noun or "", "^jar$") or
                       string.match(obj.noun or "", "^bottle$") or
                       string.match(obj.noun or "", "^beaker$") then
                        if obj.after_name and gem_matches_jar(strip_prefix(obj.after_name), gem_item) then
                            local r = dothistimeout("get #" .. obj.id .. " from #" .. furn_id, 3, "You remove|Get what")
                            if r and string.find(r, "You remove") then
                                shake_into_gemsack(obj, jh, count)
                                if (jh.count or 0) < 1 then
                                    local nj = {}
                                    for _, j in ipairs(hoard.jars) do
                                        if j ~= jh then table.insert(nj, j) end
                                    end
                                    hoard.jars = nj
                                    fput("put #" .. obj.id .. " in chest")
                                else
                                    fput("put #" .. obj.id .. " in bin")
                                end
                            else
                                echo("Sorry. Locker has refreshed. Please restart ;egemhoarder raid")
                                save_hoard(hoard)
                                return
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    dothistimeout("close locker", 1, "You close|That is already closed|faint")
    save_hoard(hoard)

-- ── NEWLOCKER / DEFAULT (store gems) ─────────────────────────────────────────
elseif cmd == "newlocker" or cmd == "none" then

    local gemsack_name  = Vars.gemsack  or ""
    local lootsack_name = Vars.lootsack or ""

    if gemsack_name == "" then
        echo("error: gemsack is not set. (;vars set gemsack=<container name>)")
        return
    end
    if lootsack_name == "" then
        echo("error: lootsack is not set. (;vars set lootsack=<container name>)")
        return
    end

    local gemsack  = find_inv_obj(gemsack_name)
    local lootsack = find_inv_obj(lootsack_name)
    if not gemsack  then echo("error: failed to find your gemsack");  return end
    if not lootsack then echo("error: failed to find your lootsack"); return end

    -- Open gemsack / lootsack; remember which we opened so we can close them
    local close_gemsack  = false
    local close_lootsack = false

    local gs_res = dothistimeout("open #" .. gemsack.id, 5,
        "You open|You carefully|You unfasten|That is already open")
    if gs_res and (gs_res:find("You open") or gs_res:find("You carefully") or gs_res:find("You unfasten")) then
        close_gemsack = true
    else
        dothistimeout("look in #" .. gemsack.id, 5, "In .* you see")
        if not gemsack.contents then
            echo("error: failed to find gemsack contents")
            return
        end
    end

    local ls_res = dothistimeout("open #" .. lootsack.id, 5,
        "You open|You carefully|You unfasten|That is already open")
    if ls_res and (ls_res:find("You open") or ls_res:find("You carefully") or ls_res:find("You unfasten")) then
        close_lootsack = true
    end

    empty_hands()
    dothistimeout("close locker", 1, "You close|That is already closed|faint")

    -- Open locker to confirm it exists and get location
    local open_result = dothistimeout("open locker", 5, 'exist="')
    if not open_result then
        echo("error: failed to find locker")
        return
    end

    local location = get_location()

    hoard.jars          = hoard.jars          or {}
    hoard.known_lockers = hoard.known_lockers or {}

    ---- Initialise or register a new locker ----
    if not hoard.jars[1] or cmd == "newlocker" then

        if cmd == "newlocker" then
            -- Move all jars from wardrobe/bin to chest before scanning
            for _, jtype in ipairs({ "jar", "beaker", "bottle" }) do
                echo("Moving all " .. jtype .. "s from your wardrobe into your chest")
                while true do
                    dothistimeout("get " .. jtype .. " from wardrobe", 3, "You remove|Get what")
                    local r = dothistimeout("put my " .. jtype .. " in chest", 3, "You put|I could not find")
                    if not r or not r:find("You put") then break end
                end
                echo("Moving all " .. jtype .. "s from your bin into your chest")
                while true do
                    dothistimeout("get " .. jtype .. " from bin", 3, "You remove|Get what")
                    local r = dothistimeout("put my " .. jtype .. " in chest", 3, "You put|I could not find")
                    if not r or not r:find("You put") then break end
                end
            end
        end

        -- Scan chest for filled jars; retry if locker refreshes mid-scan
        local scan_done = false
        while not scan_done do
            scan_done = true
            local chest_id = open_locker_furniture("chest")
            if not chest_id then
                chest_id = string.match(open_result or "", 'exist="(%d+)"')
            end
            if chest_id then
                local contents = look_in(chest_id)
                for _, obj in ipairs(contents) do
                    if string.match(obj.noun or "", "^jar$") or
                       string.match(obj.noun or "", "^bottle$") or
                       string.match(obj.noun or "", "^beaker$") then
                        if obj.after_name then
                            local look_res = dothistimeout(
                                "look in #" .. obj.id .. " from #" .. chest_id, 3,
                                "Inside .* you see %d+ portion|could not find")
                            if look_res and look_res:find("could not find") then
                                scan_done = false
                                break
                            end
                            if look_res and look_res:find("portion") then
                                local ct      = look_res:match("you see (%d+) portion")
                                local is_full = look_res:find("It is full") ~= nil
                                local gem     = strip_prefix(obj.after_name)
                                local get_res = dothistimeout("get #" .. obj.id .. " from #" .. chest_id,
                                    3, "You remove|Get what")
                                if get_res and get_res:find("Get what") then
                                    scan_done = false
                                    break
                                end
                                table.insert(hoard.jars, {
                                    gem      = gem,
                                    count    = tonumber(ct) or 0,
                                    full     = is_full,
                                    location = location,
                                })
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
        end

        -- Track known locker
        local already_known = false
        for _, loc in ipairs(hoard.known_lockers) do
            if loc == location then already_known = true; break end
        end
        if not already_known then
            table.insert(hoard.known_lockers, location)
        end

        save_hoard(hoard)

        if cmd == "newlocker" then
            respond("New locker has been checked, sorted, and saved. Please re-run the script without arguments to deposit gems.")
            respond("Please make sure to run \";egemhoarder newlocker\" at any other locker you are storing gems in before depositing here!")
            dothistimeout("close locker", 1, "You close|That is already closed|faint")
            if close_gemsack  then fput("close #" .. gemsack.id)  end
            if close_lootsack then fput("close #" .. lootsack.id) end
            fill_hands()
            return
        end
    end

    ---- Verify this is a known locker ----
    local known = false
    for _, loc in ipairs(hoard.known_lockers) do
        if loc == location then known = true; break end
    end
    if not known then
        respond("WARNING! This locker doesn't appear to have been recorded!")
        respond("If you really want to store gems to this locker prior to recording, ;send continue.")
        respond("To record this locker, kill egemhoarder and rerun with the newlocker option.")
        waitfor("continue")
    end

    local not_suitable = {}   -- {[obj_id] = true} — gems that don't fit in any jar

    ---- Step 1: Fill partial jars in bin ----
    local bin_id = open_locker_furniture("bin")
    if not bin_id then bin_id = string.match(open_result or "", 'exist="(%d+)"') end

    if bin_id then
        local bin_contents = look_in(bin_id)
        for _, jar_obj in ipairs(bin_contents) do
            if (string.match(jar_obj.noun or "", "^jar$") or
                string.match(jar_obj.noun or "", "^bottle$") or
                string.match(jar_obj.noun or "", "^beaker$")) and jar_obj.after_name then

                local stripped = strip_prefix(jar_obj.after_name)
                local jar_data = nil
                for _, j in ipairs(hoard.jars) do
                    if j.gem == stripped then jar_data = j; break end
                end

                if jar_data and not jar_data.full then
                    -- Refresh gemsack contents before matching
                    local gs_fresh = find_inv_obj(gemsack_name)
                    if gs_fresh then gemsack = gs_fresh end
                    dothistimeout("look in #" .. gemsack.id, 3, "In .* you see")

                    local gem_list = {}
                    for _, gem_obj in ipairs(gemsack.contents or {}) do
                        if not not_suitable[gem_obj.id] and gem_matches_jar(strip_prefix(gem_obj.name), stripped) then
                            table.insert(gem_list, gem_obj)
                        end
                    end

                    if #gem_list > 0 then
                        fput("get #" .. jar_obj.id .. " from #" .. bin_id)
                        for _, gem in ipairs(gem_list) do
                            local res = dothistimeout("_drag #" .. gem.id .. " #" .. jar_obj.id, 3,
                                "You add|is full|does not appear")
                            if res and res:find("filling it") then
                                jar_data.count = (jar_data.count or 0) + 1
                                jar_data.full  = true
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break
                            elseif res and res:find("You add") then
                                jar_data.count = (jar_data.count or 0) + 1
                            elseif res and res:find("is full") then
                                jar_data.full = true
                                fput("put #" .. gem.id .. " in #" .. gemsack.id)
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break
                            elseif res and res:find("does not appear") then
                                not_suitable[gem.id] = true
                                fput("put #" .. gem.id .. " in #" .. lootsack.id)
                            else
                                fput("put #" .. gem.id .. " in #" .. gemsack.id)
                            end
                        end
                        if checkright() then
                            fput("put #" .. jar_obj.id .. " in #" .. bin_id)
                        end
                    end
                end
            end
        end
    end

    ---- Step 2: Fill empty jars in chest with new gem types ----
    local chest_id = open_locker_furniture("chest")
    if not chest_id then
        chest_id = string.match(open_result or "", 'exist="(%d+)"')
    end

    -- gem_hoard: gem names that already have a jar somewhere (not full at this loc, or elsewhere)
    local gem_hoard = {}
    for _, j in ipairs(hoard.jars) do
        if not j.full or j.location ~= location then
            gem_hoard[j.gem] = true
        end
    end

    local other_locker = {}  -- gems skipped because they belong to another locker
    local squelch      = {}  -- {[gem_name]=true} gem types that caused issues this run

    if chest_id then
        local chest_contents = look_in(chest_id)

        for _, jar_obj in ipairs(chest_contents) do
            if string.match(jar_obj.noun or "", "^jar$") or
               string.match(jar_obj.noun or "", "^bottle$") or
               string.match(jar_obj.noun or "", "^beaker$") then

                -- Refresh gemsack contents
                local gs_fresh = find_inv_obj(gemsack_name)
                if gs_fresh then gemsack = gs_fresh end
                dothistimeout("look in #" .. gemsack.id, 3, "In .* you see")

                -- Count eligible gems per type
                local gem_count = {}
                for _, gem_obj in ipairs(gemsack.contents or {}) do
                    if gem_obj:type_p("gem") and
                       not Regex.test(GEM_BLACKLIST, gem_obj.name) and
                       not not_suitable[gem_obj.id] then
                        local g = strip_prefix(gem_obj.name)

                        -- Check if gem already has a jar somewhere
                        local has_jar = false
                        for _, j in ipairs(hoard.jars) do
                            if gem_matches_jar(g, j.gem) then has_jar = true; break end
                        end
                        -- Check if gem already has a jar in this chest scan
                        local in_chest = false
                        if not has_jar then
                            for _, co in ipairs(chest_contents) do
                                if co.after_name and gem_matches_jar(g, strip_prefix(co.after_name))
                                    and not not_suitable[gem_obj.id] then
                                    in_chest = true; break
                                end
                            end
                        end

                        if not has_jar and not in_chest then
                            gem_count[g] = (gem_count[g] or 0) + 1
                        elseif has_jar then
                            -- Gem belongs to another locker — note it
                            local already = false
                            for _, n in ipairs(other_locker) do
                                if n == g then already = true; break end
                            end
                            if not already then
                                table.insert(other_locker, g)
                            end
                        end
                    end
                end

                -- Pick gem type with most copies in gemsack
                local best_gem   = nil
                local best_count = 0
                for name, cnt in pairs(gem_count) do
                    if cnt > best_count then
                        best_gem   = name
                        best_count = cnt
                    end
                end

                if best_gem and not squelch[best_gem] then
                    fput("get #" .. jar_obj.id .. " from #" .. chest_id)
                    local jar_data = nil

                    for _, gem_obj in ipairs(gemsack.contents or {}) do
                        if strip_prefix(gem_obj.name) == best_gem and not squelch[best_gem] then
                            local res = dothistimeout("_drag #" .. gem_obj.id .. " #" .. jar_obj.id, 3,
                                "filling it|You add|You put|is full|does not appear|Not all drag")

                            if res and res:find("filling it") then
                                if jar_data then
                                    jar_data.count = (jar_data.count or 0) + 1
                                    jar_data.full  = true
                                end
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break

                            elseif res and res:find("You put") then
                                -- Jar ended up in an unexpected place — retrieve it
                                fput("put #" .. jar_obj.id .. " in #" .. lootsack.id)
                                local back = dothistimeout("get #" .. jar_obj.id, 3, "You remove")
                                if back then
                                    local updated = GameObj[jar_obj.id]
                                    if updated and updated.after_name then
                                        local gem_name = strip_prefix(updated.after_name)
                                        if gem_hoard[gem_name] then
                                            fput("shake #" .. jar_obj.id)
                                            fput("put #" .. jar_obj.id .. " in chest")
                                            fput("put left in #" .. gemsack.id)
                                            squelch[best_gem] = true
                                            local already = false
                                            for _, n in ipairs(other_locker) do
                                                if n == gem_name then already = true; break end
                                            end
                                            if not already then
                                                table.insert(other_locker, gem_name)
                                            end
                                        else
                                            jar_data = { gem = gem_name, count = 1, full = false, location = location }
                                            table.insert(hoard.jars, jar_data)
                                            gem_hoard[gem_name] = true
                                        end
                                    end
                                end
                                break

                            elseif res and res:find("is full") then
                                fput("put #" .. gem_obj.id .. " in #" .. gemsack.id)
                                if jar_data then jar_data.full = true end
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break

                            elseif res and res:find("You add") then
                                if jar_data then
                                    jar_data.count = (jar_data.count or 0) + 1
                                else
                                    -- First gem added — record new jar entry
                                    local gem_name = best_gem
                                    local refreshed = GameObj[jar_obj.id]
                                    if refreshed and refreshed.after_name then
                                        gem_name = strip_prefix(refreshed.after_name)
                                    end
                                    jar_data = { gem = gem_name, count = 1, full = false, location = location }
                                    table.insert(hoard.jars, jar_data)
                                    gem_hoard[gem_name] = true
                                end

                            elseif res and res:find("does not appear") then
                                not_suitable[gem_obj.id] = true
                                fput("put #" .. gem_obj.id .. " in #" .. lootsack.id)

                            elseif res and res:find("Not all drag") then
                                fput("put #" .. gem_obj.id .. " in #" .. gemsack.id)
                                fput("put #" .. jar_obj.id .. " in wardrobe")
                                break
                            end
                        end
                    end

                    if checkright() then
                        fput("put #" .. jar_obj.id .. " in bin")
                    end
                end
            end
        end
    end

    dothistimeout("close locker", 1, "You close|That is already closed|faint")
    save_hoard(hoard)
    fill_hands()

    -- Report gems that belong to another locker
    if #other_locker > 0 then
        respond("Gems not lockered due to being already in another locker:")
        respond(pad_left("gem", 35) .. " " .. pad_left("count", 5) .. " " ..
                pad_left("full", 8)  .. "  "  .. pad_right("location", 30))
        respond(pad_left("---", 35) .. " " .. pad_left("-----", 5) .. " " ..
                pad_left("----", 8)  .. "  "  .. pad_right("--------", 30))
        for _, gem_name in ipairs(other_locker) do
            local jh = nil
            for _, j in ipairs(hoard.jars or {}) do
                if j.gem == gem_name or j.gem == gem_name .. "s" then
                    jh = j; break
                end
            end
            if jh and not jh.full then
                respond(pad_left(jh.gem, 35)            .. " " ..
                        pad_left(tostring(jh.count), 5) .. " " ..
                        pad_left(tostring(jh.full), 8)  .. "  " ..
                        pad_right(jh.location or "", 30))
            end
        end
    end

    if close_gemsack  then fput("close #" .. gemsack.id)  end
    if close_lootsack then fput("close #" .. lootsack.id) end
end
