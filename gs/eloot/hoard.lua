--- ELoot hoard module
-- Ported from eloot.lic ELoot::Hoard submodule (lines 3646-4467).
-- Handles gem and alchemy hoarding into lockers/containers.
-- Manages jar inventory, gem bounties, raid, deposit, and list operations.
--
-- Usage:
--   local Hoard = require("gs.eloot.hoard")
--   Hoard.hoard_items(nil, false, data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires to avoid circular dependencies
-- ---------------------------------------------------------------------------

local function Util()      return require("gs.eloot.util") end
local function Inventory() return require("gs.eloot.inventory") end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function any_match(lines, pattern)
    if not lines then return false end
    for _, l in ipairs(lines) do
        if l:find(pattern) then return true end
    end
    return false
end

local function contains(tbl, val)
    if not tbl or not val then return false end
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

--- Check if a GameObj noun matches jar/bottle/beaker.
local function is_jar(obj)
    if not obj or not obj.noun then return false end
    return obj.noun == "jar" or obj.noun == "bottle" or obj.noun == "beaker"
end

--- Find first line matching a pattern, return first capture.
local function find_match(lines, pattern)
    if not lines then return nil end
    for _, l in ipairs(lines) do
        local m = l:match(pattern)
        if m then return m end
    end
    return nil
end

--- Remove items from tbl_a that exist in tbl_b (by id).
local function subtract_by_id(tbl_a, tbl_b)
    local ids = {}
    for _, v in ipairs(tbl_b) do
        if v.id then ids[v.id] = true end
    end
    local result = {}
    for _, v in ipairs(tbl_a) do
        if not ids[v.id] then
            result[#result + 1] = v
        end
    end
    return result
end

--- Unique items by name (keep first occurrence).
local function unique_by_name(items)
    local seen = {}
    local result = {}
    for _, item in ipairs(items) do
        if item.name and not seen[item.name] then
            seen[item.name] = true
            result[#result + 1] = item
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 1. set_type_vars (lines 3646-3665)
-- Set working variables based on the type of hoarding (gem or alchemy).
-- ---------------------------------------------------------------------------

--- Set gem/alchemy hoard type variables on data.
-- @param hoard_type string "gem" or "alchemy"
-- @param data table ELoot data state
function M.set_type_vars(hoard_type, data)
    if hoard_type == data.hoard_type then return end
    data.hoard_type = hoard_type

    local s = data.settings
    local prefix = hoard_type

    -- Container list to hoard FROM
    data.container_settings = s[prefix .. "_horde_containers"] or {}
    -- Hoard everything toggle
    data.everything_list    = s[prefix .. "_everything_list"] or false
    -- List of excluded items
    data.everything         = s[prefix .. "_everything"] or {}
    -- Only hoard specific items toggle
    data.only_list          = s[prefix .. "_only_list"] or false
    -- List of specific items
    data.only               = s[prefix .. "_list"] or {}
    -- City where the locker is
    data.locker_city        = s[prefix .. "_locker_name"] or ""
    -- True/False toggle to use locker
    data.locker             = s[prefix .. "_horde_locker"] or false
    -- Container name in UI
    data.cache              = s[prefix .. "_horde_container"] or ""
    -- Inventory
    data.inventory          = s[prefix .. "_horde_inv"] or {}
    -- True/False toggle to hoard
    data.use_hoarding       = s[prefix .. "_horde"] or false
    -- CHE locker toggle
    data.use_house_locker   = s[prefix .. "_horde_locker_che"] or false
    -- Array of locations outside CHE locker room
    data.che_rooms          = s[prefix .. "_horde_che_rooms"] or ""
    -- Entry string into CHE locker
    data.che_entry          = s[prefix .. "_horde_che_entry"] or ""
    -- Exit string from CHE locker
    data.che_exit           = s[prefix .. "_horde_che_exit"] or ""
end

-- ---------------------------------------------------------------------------
-- 2. validate_hoarding_settings (lines 3667-3692)
-- Validate locker settings before hoarding.
-- ---------------------------------------------------------------------------

--- Validate that hoarding settings are properly configured.
-- @param data table ELoot data state
-- @return boolean true if settings are valid
function M.validate_hoarding_settings(data)
    local need_return = false

    if data.locker and (not data.locker_city or data.locker_city == "") then
        Util().msg({ text = " Hoard " .. data.hoard_type .. " in a locker is toggled on the UI but location is empty" }, data)
        need_return = true
    end

    if not data.cache or data.cache == "" then
        Util().msg({ text = " A gem hoarding container is not identified (yes, you need it for a locker too)" }, data)
        need_return = true
    end

    if not data.container_settings or #data.container_settings == 0 then
        Util().msg({ text = " No containers identified to hoard " .. data.hoard_type .. "s from." }, data)
        Util().msg({ text = " Please make selection in UI Gem/Alchemy Hoarding Tab" }, data)
        need_return = true
    end

    if need_return then
        Util().msg({ text = " The hoarding settings need updated.", space = true }, data)
        return false
    end

    return true
end

-- ---------------------------------------------------------------------------
-- 3. check_type (lines 3694-3715)
-- Check if an item matches the hoard type.
-- ---------------------------------------------------------------------------

--- Check whether an item matches the current hoard type.
-- @param item_name string item name to check
-- @param data table ELoot data state
-- @return boolean true if item matches the hoard type
function M.check_type(item_name, data)
    local obj_type = data.hoard_type == "alchemy" and "reagent" or data.hoard_type

    -- Normalize teeth -> tooth
    item_name = item_name:gsub("teeth", "tooth")
    local noun = item_name:match("(%S+)$") or item_name

    -- Check exclusion first
    local type_data = GameObj.type_data and GameObj.type_data(obj_type)
    if type_data then
        if type_data.exclusion and item_name:find(type_data.exclusion) then
            return false
        end
        -- Check name/noun match
        if type_data.name then
            local name_str = tostring(type_data.name)
            if name_str:find("%f[%w]" .. item_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%f[%W]") then
                return true
            end
            if item_name:find(name_str) then
                return true
            end
        end
        if type_data.noun then
            local noun_str = tostring(type_data.noun)
            if noun_str:find("%f[%w]" .. noun:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%f[%W]") then
                return true
            end
            if noun:find(noun_str) then
                return true
            end
        end
    end

    -- Reagent special cases
    if obj_type == "reagent" then
        if item_name:find("kezmonian honey beryl") or item_name:find("faintly glimmering dust") then
            return true
        end
        -- Check room tags for reagent matching
        local rooms = Room.list and Room.list() or {}
        for _, r in ipairs(rooms) do
            if r.tags then
                for _, tag in ipairs(r.tags) do
                    if tag:sub(-#item_name) == item_name then return true end
                    if item_name:sub(1, #tag) == tag and item_name:find("ayana") then return true end
                    if item_name:sub(-#tag) == tag then return true end
                end
            end
        end
    end

    -- Gem special cases: elemental talons
    if obj_type == "gem" then
        if item_name:find("deep blue sapphire.*talon")
            or item_name:find("fiery ruby.*talon")
            or item_name:find("glistening onyx.*talon")
            or item_name:find("sparkling emerald.*talon") then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 4. normalize_name (lines 3717-3757)
-- Normalize gem/alchemy name for tracking.
-- ---------------------------------------------------------------------------

--- Normalize an item name for hoard tracking.
-- Removes articles, sizes, descriptors, and depluralize.
-- @param name string|table item name or GameObj
-- @return string|nil normalized name
function M.normalize_name(name, data)
    if data then
        Util().msg({ type = "debug", text = "name: " .. tostring(name) }, data)
    end
    if not name then return nil end

    -- Handle GameObj-like objects
    if type(name) == "table" and name.full_name then
        name = name.full_name
    elseif type(name) ~= "string" then
        name = tostring(name)
    end

    -- Special cases before lowering
    local essence_match = name:match("essences? of (air|earth|water|fire)")
    if essence_match then
        return "essence of " .. essence_match
    end

    if name:find("golden seed") then
        return "tiny golden seed"
    end

    name = name:gsub("motes?", "mote")
    name = name:lower()

    -- Depluralizing rules (order matters: most specific first)
    local name_rules = {
        { suffix = "ies",    replacement = "y" },
        { suffix = "onyxes", replacement = "onyx" },
        { suffix = "zes",    replacement = "z" },
        { suffix = "s",      replacement = "" },
    }

    -- Remove articles, sizes, and descriptors
    local sizes = "tiny|small|medium|large|blue%-violet|pyrite%-capped vibrant"
    local articles = "some|an? |the"
    local descriptors = "%w+s? of(?: polished)?|polished"

    -- Build a cleanup pattern: strip leading articles, sizes, and descriptor phrases
    -- The Ruby regex: /^\s*(?:containing )?(?:articles)?\s*(?:sizes)?\s*(?:descriptors)?\s*(?:sizes)?\s*(.*?)\s*$/
    -- In Lua we do multiple gsub passes for clarity.

    -- Strip "containing " prefix
    name = name:gsub("^%s*containing%s+", "")

    -- Strip leading article
    name = name:gsub("^%s*some%s+", "")
    name = name:gsub("^%s*an?%s+", "")
    name = name:gsub("^%s*the%s+", "")

    -- Strip leading size descriptors
    for sz in string.gmatch(sizes, "[^|]+") do
        local pat = "^%s*" .. sz:gsub("%-", "%%-") .. "%s+"
        name = name:gsub(pat, "")
    end

    -- Strip descriptor phrases like "pieces of polished" or "cluster of"
    name = name:gsub("^%s*%w+s? of polished%s+", "")
    name = name:gsub("^%s*%w+s? of%s+", "")
    name = name:gsub("^%s*polished%s+", "")

    -- Strip trailing size descriptors that may appear after descriptor removal
    for sz in string.gmatch(sizes, "[^|]+") do
        local pat = "^%s*" .. sz:gsub("%-", "%%-") .. "%s+"
        name = name:gsub(pat, "")
    end

    -- Trim whitespace
    name = name:match("^%s*(.-)%s*$") or name

    -- Apply depluralization rules
    for _, rule in ipairs(name_rules) do
        local suf = rule.suffix
        local rep = rule.replacement
        local esc_suf = suf:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        if name:sub(-#suf) == suf then
            name = name:sub(1, -#suf - 1) .. rep
            break
        end
    end

    return name
end

-- ---------------------------------------------------------------------------
-- 5. go2_locker (lines 3759-3839)
-- Navigate to locker room.
-- ---------------------------------------------------------------------------

--- Navigate to the hoarding locker room.
-- Handles bank withdrawal, CHE lockers, debt, and locker room searching.
-- @param data table ELoot data state
function M.go2_locker(data)
    local lockers

    if data.use_house_locker then
        -- Parse comma-separated room IDs from CHE rooms setting
        lockers = {}
        for num in (data.che_rooms or ""):gmatch("(%d+)") do
            lockers[#lockers + 1] = Room[tonumber(num)]
        end
    else
        -- Find locker rooms by tag
        lockers = {}
        local all_rooms = Map.list and Map.list() or {}
        for _, room in ipairs(all_rooms) do
            if room.tags then
                local has_che = false
                local has_locker = false
                local has_public = false
                local location_match = false

                for _, tag in ipairs(room.tags) do
                    if tag:find("meta:che:" .. (data.locker_city or "")) then has_che = true end
                    if tag == "locker" then has_locker = true end
                    if tag == "publiclockers" then has_public = true end
                end

                if room.location and data.locker_city then
                    location_match = room.location:find(data.locker_city) ~= nil
                end

                if (has_che and has_locker) or (has_public and location_match) then
                    lockers[#lockers + 1] = room
                end
            end
        end
    end

    if not lockers or #lockers == 0 then
        Util().msg({ text = " Not able to hoard. Unable to find locker rooms.", space = true }, data)
        return
    end

    -- Determine locker town and current town
    local locker_nearest = Map.find_nearest_by_tag and Map.find_nearest_by_tag(lockers[1].id, "town")
    local locker_town = locker_nearest and Room[locker_nearest] and Room[locker_nearest].location or ""
    local current_nearest = Map.find_nearest_by_tag and Map.find_nearest_by_tag(Room.current().id, "town")
    local current_town = current_nearest and Room[current_nearest] and Room[current_nearest].location or ""

    -- Handle Four Winds Isle travel
    if locker_town:lower():find("the isle of four winds") and current_town ~= locker_town then
        -- Find a town room on FWI and go there first
        local fwi_rooms = Map.list and Map.list() or {}
        for _, room in ipairs(fwi_rooms) do
            if room.tags then
                for _, tag in ipairs(room.tags) do
                    if tag == "town" and Util().fwi(room) then
                        Util().go2(room.id, data)
                        -- Recalculate
                        locker_nearest = Map.find_nearest_by_tag(lockers[1].id, "town")
                        locker_town = locker_nearest and Room[locker_nearest] and Room[locker_nearest].location or ""
                        current_nearest = Map.find_nearest_by_tag(Room.current().id, "town")
                        current_town = current_nearest and Room[current_nearest] and Room[current_nearest].location or ""
                        break
                    end
                end
            end
        end
    end

    if not locker_nearest then
        Util().msg({ text = " Not able to hoard. Unable to find the locker town using room #" .. tostring(lockers[1].id) .. ".", space = true }, data)
        return
    elseif current_town ~= locker_town then
        Util().msg({ text = " Not able to hoard. Your hoarding locker is in " .. locker_town .. ".", space = true }, data)
        return
    end

    -- Withdraw silver for non-premium, non-CHE lockers
    if not (data.account_type or ""):lower():find("premium") and not data.use_house_locker then
        Util().silver_withdraw(2500, data)
    end

    local index = 1  -- 1-based in Lua

    -- Check if already at a locker room
    for i, location in ipairs(lockers) do
        if location.id == Room.current().id then
            index = i
            break
        end
    end

    while true do
        local place = lockers[index]
        Util().go2(place.id, data)
        waitrt()

        -- Some rooms go directly to the locker
        local room_objs = {}
        for _, obj in ipairs(GameObj.room_desc() or {}) do room_objs[#room_objs + 1] = obj end
        for _, obj in ipairs(GameObj.loot() or {}) do room_objs[#room_objs + 1] = obj end
        local found_locker = false
        for _, obj in ipairs(room_objs) do
            if obj.name and (obj.name:find("locker") or obj.name:find("counter")) then
                found_locker = true
                break
            end
        end
        if found_locker then break end

        -- Determine entry command
        local way_in
        if data.use_house_locker then
            way_in = data.che_entry
        else
            local loot_objs = GameObj.loot() or {}
            local desc_objs = GameObj.room_desc() or {}
            local way_in_obj = nil
            local all_objs = {}
            for _, o in ipairs(loot_objs) do all_objs[#all_objs + 1] = o end
            for _, o in ipairs(desc_objs) do all_objs[#all_objs + 1] = o end
            for _, obj in ipairs(all_objs) do
                if obj.noun == "opening" or obj.noun == "curtain" or obj.noun == "tapestry" then
                    way_in_obj = obj
                    break
                end
            end
            if way_in_obj then
                local noun = way_in_obj.noun
                if noun == "tapestry" then noun = "opening" end
                way_in = "go " .. noun
            else
                way_in = "go opening"
            end
        end

        local result = move(way_in)

        if result == true then break end

        -- Check for debt
        local recent = reget and reget(10) or {}
        local has_debt = false
        for _, line in ipairs(recent) do
            if line:lower():find("pay off") and line:lower():find("debt") then
                has_debt = true
                break
            end
        end

        if has_debt then
            local wealth_lines = Util().get_command("wealth quiet",
                { "^You have .* silver with you" }, nil, data)
            local wealth_text = table.concat(wealth_lines or {}, " ")
            local debt_amount = wealth_text:match("debt of ([%d,]+) silver")
            if debt_amount then
                local amount = tonumber(debt_amount:gsub(",", "")) or 0
                Util().silver_withdraw(amount, data)
                Util().go2("debt", data)
                waitrt()
                fput("pay " .. tostring(amount))
                Util().silver_withdraw(2500, data)
                -- redo: continue the loop at same index
                goto continue_locker_loop
            end
        end

        -- If last locker, wait and retry
        if index == #lockers then
            respond("")
            Util().msg({ text = " Not able to enter a locker. They might all be taken. Waiting 10 seconds then trying again.", space = true }, data)
            respond("")
            pause(10)
        end

        -- Increment index, wrapping around
        index = (index % #lockers) + 1

        ::continue_locker_loop::
    end

    waitrt()
end

-- ---------------------------------------------------------------------------
-- 6. open_locker (lines 3841-3884)
-- Open locker and parse contents.
-- ---------------------------------------------------------------------------

--- Open locker and find the stash container inside.
-- @param reset boolean if true, skip the open command
-- @param data table ELoot data state
function M.open_locker(reset, data)
    data.stash = nil
    local retries = 0
    local max_retries = 3
    local error_log = {}

    waitrt()

    local success = false

    while retries <= max_retries do
        -- Open the locker (unless resetting)
        if not reset then
            local open_result = Util().get_command("open locker",
                { 'exist=".-" noun="locker"', 'exist=".-" noun="chest"',
                  "That is already open%.", "<prompt time=" },
                nil, data)
            if open_result then
                error_log[#error_log + 1] = table.concat(open_result, "\n")
            end
        end

        waitrt()

        -- Find stash container in loot
        local loot = GameObj.loot() or {}
        for _, item in ipairs(loot) do
            if item.name and data.cache and item.name:find(data.cache) then
                data.stash = item
                break
            end
        end

        -- Maybe it's on a counter
        if not data.stash then
            local desc = GameObj.room_desc() or {}
            for _, item in ipairs(desc) do
                if item.name and item.name:find("counter") then
                    Util().get_command("look on #" .. item.id,
                        { "<container id='.-' title=" }, nil, data)
                    local contents = item.contents and item.contents() or {}
                    for _, c in ipairs(contents) do
                        if c.name and data.cache and c.name:find(data.cache) then
                            data.stash = c
                            break
                        end
                    end
                    break
                end
            end
        end

        if data.stash then
            -- Look inside the stash to populate contents
            Util().get_command("look in #" .. data.stash.id,
                { "<container id='.-' title=" }, nil, data)
            success = true
            break
        end

        retries = retries + 1
        if retries <= max_retries then
            Util().msg({ text = " Something went wrong. Retrying... (Retry " .. retries .. " of " .. max_retries .. ").", space = true }, data)
            pause(1)
        end
    end

    if not success then
        Util().msg({ text = " Not able to find the container in your locker for " .. data.hoard_type .. " hoarding." }, data)
        Util().msg({ text = " Please send the EO team the following on the discord scripting channel..." }, data)
        Util().msg({ text = " Room: " .. tostring(Room.current().id) .. " | container_name: " .. tostring(data.cache) }, data)
        error_log[#error_log + 1] = "Type: " .. tostring(data.hoard_type)
        Util().msg({ text = " Errors: " .. table.concat(error_log, " | ") }, data)
        M.leave_locker(data)
    end
end

-- ---------------------------------------------------------------------------
-- 7. leave_locker (lines 3886-3904)
-- Close locker and leave.
-- ---------------------------------------------------------------------------

--- Close the locker and exit the locker room.
-- @param data table ELoot data state
function M.leave_locker(data)
    local loot = GameObj.loot() or {}
    local locker_item = nil
    for _, item in ipairs(loot) do
        if item.name and (item.name:find("dark stained antique oak trunk")
            or item.name:find("counter")
            or item.name:find("locker")) then
            locker_item = item
            break
        end
    end

    -- Check if this is a locksmith room
    local current = Room.current()
    local is_locksmith_room = false
    if current and current.tags then
        for _, tag in ipairs(current.tags) do
            if tag == "locksmith" then
                is_locksmith_room = true
                break
            end
        end
    end

    if not locker_item or is_locksmith_room then return end

    Util().get_res("close locker", "^You", data)

    -- Determine exit command
    local way_out
    if data.use_house_locker then
        way_out = data.che_exit
    else
        local all_objs = {}
        for _, o in ipairs(GameObj.loot() or {}) do all_objs[#all_objs + 1] = o end
        for _, o in ipairs(GameObj.room_desc() or {}) do all_objs[#all_objs + 1] = o end
        local way_out_obj = nil
        for _, obj in ipairs(all_objs) do
            if obj.noun == "opening" or obj.noun == "curtain" or obj.noun == "tapestry" then
                way_out_obj = obj
                break
            end
        end
        if way_out_obj then
            local noun = way_out_obj.noun
            if noun == "tapestry" then noun = "opening" end
            way_out = "go " .. noun
        else
            way_out = "go opening"
        end
    end

    move(way_out)
    waitrt()
end

-- ---------------------------------------------------------------------------
-- 8. build_inventory (lines 3906-3943)
-- Build locker inventory from contents.
-- ---------------------------------------------------------------------------

--- Build the inventory of jar contents in the stash container.
-- @param refresh boolean if true, force rebuild even if inventory exists
-- @param data table ELoot data state
function M.build_inventory(refresh, data)
    if not refresh and data.inventory and #data.inventory > 0 then
        return
    end

    -- Premium lockers can use manifest
    if (data.locker or data.use_house_locker) and (data.account_type or ""):lower():find("premium") then
        local result = M.build_premium_locker_inventory(data)
        if result then return end
    end

    data.inventory = {}

    if not data.stash then return end

    -- Refresh contents
    Util().get_command("look in #" .. data.stash.id,
        { "<container id='.-' title=" }, nil, data)

    local contents = data.stash.contents and data.stash.contents() or {}

    -- Count jars with contents and empty jars
    local total_items = 0
    local empty_jars = 0
    for _, obj in ipairs(contents) do
        if is_jar(obj) then
            if obj.after_name and obj.after_name ~= "" then
                total_items = total_items + 1
            else
                empty_jars = empty_jars + 1
            end
        end
    end

    if empty_jars > 0 then
        data.inventory[#data.inventory + 1] = {
            item = "*** empty jars ***",
            count = empty_jars,
            full = "  -",
        }
    end

    local processed = 0
    for _, jar in ipairs(contents) do
        if is_jar(jar) and jar.after_name and jar.after_name ~= "" then
            local lines = Util().get_command(
                "look in #" .. jar.id .. " from #" .. data.stash.id,
                { "^Inside .- you see %d+ portion" }, nil, data)

            local count_str = find_match(lines, "^Inside .- you see (%d+) portion")
            if count_str then
                local count = tonumber(count_str) or 0
                local item = M.normalize_name(jar.after_name)
                if item then item = item:match("^%s*(.-)%s*$") or item end
                local is_full = any_match(lines, "It is full")

                if item and M.check_type(item, data) then
                    data.inventory[#data.inventory + 1] = {
                        item = item,
                        count = count,
                        full = is_full,
                    }
                end
            end

            processed = processed + 1
            if total_items > 0 then
                local percent = math.floor((processed / total_items) * 10000 + 0.5) / 100
                respond(" percent complete: " .. tostring(percent) .. "%")
            end
        end
    end

    Util().save_hoard_profile(data)
end

-- ---------------------------------------------------------------------------
-- 9. build_premium_locker_inventory (lines 3945-4014)
-- Premium locker with manifest.
-- ---------------------------------------------------------------------------

--- Build inventory from locker manifest command (premium accounts only).
-- @param data table ELoot data state
-- @return boolean true if successful, false/nil otherwise
function M.build_premium_locker_inventory(data)
    if data.use_house_locker then
        local rooms = {}
        for num in (data.che_rooms or ""):gmatch("(%d+)") do
            rooms[#rooms + 1] = tonumber(num)
        end
        if #rooms > 0 then
            local nearest = Map.find_nearest_by_tag and Map.find_nearest_by_tag(rooms[1], "town")
            if nearest and Room[nearest] then
                local loc = Room[nearest].location or ""
                data.locker_city = loc:gsub("the town of%s*", "")
                    :gsub("the city of%s*", "")
                    :gsub("the village of%s*", "")
                    :match("^%s*(.-)%s*$")
            end
        end
    end

    local all_lockers = {
        "Wehnimer's Landing", "Teras Isle", "Solhaven", "River's Rest",
        "Icemule Trace", "Zul Logoth", "Ta'Illistim", "Ta'Vaalor",
        "Mist Harbor", "Cysaegir", "Kraken's Fall", "Family Vault",
    }

    local locker_town = nil
    if data.cache and data.cache:lower():find("trunk") then
        locker_town = "Family Vault"
    end

    if not locker_town then
        local aliases = {
            ["Kharam-Dzu"]             = "Teras Isle",
            ["the Isle of Four Winds"] = "Mist Harbor",
        }
        locker_town = aliases[data.locker_city] or data.locker_city
    end

    -- Verify locker_town is in the known list
    if not contains(all_lockers, locker_town) then
        return false
    end

    data.inventory = {}

    -- Determine container keyword from cache name
    local start_from
    local cache_lower = (data.cache or ""):lower()
    if cache_lower:find("trunk")    then start_from = "bound in wrought iron"
    elseif cache_lower:find("chest")    then start_from = "deep chest"
    elseif cache_lower:find("rack")     then start_from = "weapon rack"
    elseif cache_lower:find("stand")    then start_from = "armor stand"
    elseif cache_lower:find("bin")      then start_from = "magical item bin"
    elseif cache_lower:find("wardrobe") then start_from = "clothing wardrobe"
    end

    local lines = Util().get_command("locker manifest " .. locker_town,
        { "Thinking back, you recall the contents", "Looking in front of you" }, nil, data)

    if not lines or not start_from then
        data.inventory = {}
        return nil
    end

    -- Find the line containing the container
    local start_index = nil
    for i, line in ipairs(lines) do
        if line:find(start_from, 1, true) then
            start_index = i
            break
        end
    end

    if not start_index then
        data.inventory = {}
        return nil
    end

    -- Find the end of this container section (empty line)
    local end_index = #lines + 1
    for i = start_index + 1, #lines do
        if lines[i]:match("^%s*$") then
            end_index = i
            break
        end
    end

    -- Extract container contents lines
    local extracted = {}
    for i = start_index + 1, end_index - 1 do
        extracted[#extracted + 1] = lines[i]
    end

    -- Count empty jars
    local empty_jars = 0
    for _, line in ipairs(extracted) do
        if (line:find("jar") or line:find("bottle") or line:find("beaker"))
            and not line:find("containing") then
            empty_jars = empty_jars + 1
        end
    end

    if empty_jars > 0 then
        data.inventory[#data.inventory + 1] = {
            item = "*** empty jars ***",
            count = empty_jars,
            full = "  -",
        }
    end

    -- Parse items with contents
    for _, line in ipairs(extracted) do
        local item_match, stored_str, capacity_str =
            line:match("containing%s(.-)%s+%((%d+)/(%d+)%)")
        if item_match then
            local item = M.normalize_name(item_match)
            if item then item = item:match("^%s*(.-)%s*$") or item end
            local stored = tonumber(stored_str) or 0
            local capacity = tonumber(capacity_str) or 0
            local is_full = (stored == capacity)

            if item and M.check_type(item, data) then
                data.inventory[#data.inventory + 1] = {
                    item = item,
                    count = stored,
                    full = is_full,
                }
            end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- 10. list_inventory (lines 4016-4033)
-- Display inventory to user.
-- ---------------------------------------------------------------------------

--- Display the hoard inventory in a formatted table.
-- @param hoard_type string "gem" or "alchemy"
-- @param data table ELoot data state
function M.list_inventory(hoard_type, data)
    M.set_type_vars(hoard_type, data)

    -- Sort inventory by item name
    local sorted = {}
    for _, entry in ipairs(data.inventory or {}) do
        sorted[#sorted + 1] = entry
    end
    table.sort(sorted, function(a, b) return (a.item or "") < (b.item or "") end)

    respond("")
    respond("  " .. hoard_type:sub(1, 1):upper() .. hoard_type:sub(2) .. " Inventory")
    respond("  " .. string.rep("-", 50))
    respond(string.format("  %-30s %8s %6s", hoard_type:sub(1, 1):upper() .. hoard_type:sub(2) .. "s", "Amount", "Full?"))
    respond("  " .. string.rep("-", 50))

    for _, entry in ipairs(sorted) do
        local full_str = entry.full
        if type(full_str) == "boolean" then
            full_str = entry.full and "yes" or "no"
        end
        respond(string.format("  %-30s %8d %6s",
            Util().capitalize_words(entry.item or ""),
            entry.count or 0,
            tostring(full_str)))
    end
    respond("  " .. string.rep("-", 50))
    respond("")
end

-- ---------------------------------------------------------------------------
-- 11. reset_inventory (lines 4035-4057)
-- Reset stored inventory.
-- ---------------------------------------------------------------------------

--- Reset the hoard inventory by physically re-scanning the locker.
-- @param hoard_type string "gem" or "alchemy"
-- @param data table ELoot data state
function M.reset_inventory(hoard_type, data)
    M.set_type_vars(hoard_type, data)
    if not M.validate_hoarding_settings(data) then return end

    local start_room = Room.current().id

    -- For non-premium accounts, need to go to locker
    if not ((data.locker or data.use_house_locker) and (data.account_type or ""):lower():find("premium")) then
        M.hoard_prep(data)
    end

    -- Build inventory (force refresh)
    M.build_inventory(true, data)

    -- Leave the locker
    M.leave_locker(data)

    -- Go back to original room
    Util().go2(start_room, data)

    -- Save the new inventory
    Util().save_hoard_profile(data)
end

-- ---------------------------------------------------------------------------
-- 12. hoard_prep (lines 4059-4072)
-- Prepare for hoarding session.
-- ---------------------------------------------------------------------------

--- Prepare for hoarding: navigate to locker or find stash container.
-- @param data table ELoot data state
function M.hoard_prep(data)
    if data.locker or data.use_house_locker then
        -- Check if already in a locker room
        local locker_item = nil
        local loot = GameObj.loot() or {}
        for _, item in ipairs(loot) do
            if item.name and (item.name:find("dark stained antique oak trunk")
                or item.name:find("counter")
                or item.name:find("locker")) then
                locker_item = item
                break
            end
        end

        local current = Room.current()
        local is_locksmith_room = false
        if current and current.tags then
            for _, tag in ipairs(current.tags) do
                if tag == "locksmith" then
                    is_locksmith_room = true
                    break
                end
            end
        end

        if is_locksmith_room or not locker_item then
            M.go2_locker(data)
        end

        M.open_locker(false, data)
        -- data.stash variable set when opening locker
    else
        -- Use a personal container
        local inv = GameObj.inv() or {}
        for _, i in ipairs(inv) do
            if i.name and data.cache and i.name:find(data.cache .. "%f[%W]") then
                data.stash = i
                break
            end
        end
        if data.stash then
            Inventory().open_single_container(data.stash, data)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 13. need_to_hoard (lines 4074-4110)
-- Check if hoarding is needed.
-- ---------------------------------------------------------------------------

--- Determine whether there is work to do for hoarding.
-- @param deposit boolean if true, always return true
-- @param data table ELoot data state
-- @return boolean true if hoarding is needed
function M.need_to_hoard(deposit, data)
    if deposit then return true end
    if not data.inventory or #data.inventory == 0 then return true end

    local bounty_gems = {}

    -- Check gem bounty
    if data.settings.gem_horde_turnin and Bounty.task
        and Bounty.task.gem and Bounty.task.gem()
        and data.hoard_type == "gem" then

        local gem_name, gem_number = M.check_gem_bounty(data)
        if gem_name then
            for _, item in ipairs(data.items_to_hoard or {}) do
                if item.name and item.name:find(gem_name) and #bounty_gems < gem_number then
                    bounty_gems[#bounty_gems + 1] = item
                end
            end

            local have_stock = nil
            for _, inv_item in ipairs(data.inventory) do
                if inv_item.item == gem_name then
                    have_stock = inv_item
                    break
                end
            end

            local need_gems = gem_number - #bounty_gems
            if need_gems > 0 and have_stock then
                return true
            end
        end
    end

    -- Check remaining items
    local remaining = subtract_by_id(data.items_to_hoard or {}, bounty_gems)

    for _, thing in ipairs(remaining) do
        local norm_name = M.normalize_name(thing.name)
        if norm_name then
            local esc_name = norm_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local inv_entry = nil
            for _, inv_item in ipairs(data.inventory) do
                if inv_item.item and inv_item.item:find(esc_name) then
                    inv_entry = inv_item
                    break
                end
            end

            if inv_entry then
                if inv_entry.full ~= true then
                    return true
                end
            else
                -- No jar for this item; check for empty jars
                local has_empty = false
                for _, inv_item in ipairs(data.inventory) do
                    if inv_item.item and inv_item.item:find("empty jar") then
                        has_empty = true
                        break
                    end
                end
                if has_empty then
                    return true
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 14. check_gem_bounty (lines 4112-4120)
-- Check active gem bounty.
-- ---------------------------------------------------------------------------

--- Return the gem bounty name and count if applicable.
-- @param data table ELoot data state
-- @return string|nil gem_name, number|nil gem_number
function M.check_gem_bounty(data)
    if not data.settings.gem_horde_turnin then return nil, nil end
    if not Bounty or not Bounty.task then return nil, nil end
    local task = Bounty.task
    if not task.gem or not task.gem() then return nil, nil end
    -- Check it's not just an assignment
    if task.type and tostring(task.type()):match("assignment$") then return nil, nil end

    local gem_name = M.normalize_name(task.gem())
    local gem_number = task.number and task.number() or 0

    return gem_name, gem_number
end

-- ---------------------------------------------------------------------------
-- 15. hoard_items (lines 4122-4165)
-- Main hoard method.
-- ---------------------------------------------------------------------------

--- Main hoarding entry point. Process gem and/or alchemy hoarding.
-- @param hoard_type string|nil "gem" or "alchemy"; nil means both
-- @param just_deposit boolean if true, only deposit (don't withdraw bounty gems)
-- @param data table ELoot data state
function M.hoard_items(hoard_type, just_deposit, data)
    data.hoard_deposit = {}
    local start_room = Room.current().id

    local types = { "gem", "alchemy" }
    for _, item_type in ipairs(types) do
        if hoard_type and hoard_type ~= item_type then
            goto continue_type
        end

        M.set_type_vars(item_type, data)

        if not data.use_hoarding then goto continue_type end
        if not M.validate_hoarding_settings(data) then goto continue_type end

        -- Create the list of items to store
        M.hoarding_list(nil, data)

        -- Next unless there is something to do
        if not M.need_to_hoard(just_deposit, data) then goto continue_type end

        -- Find the stash container and/or goto locker
        M.hoard_prep(data)

        -- Build inventory if needed
        M.build_inventory(false, data)

        -- Store the items
        M.store_items(just_deposit, data)

        -- Withdraw bounty gems if needed
        if data.settings.gem_horde_turnin
            and Bounty.task and Bounty.task.gem and Bounty.task.gem()
            and data.hoard_type == "gem"
            and not just_deposit then

            local gem_name, gem_number = M.check_gem_bounty(data)
            if gem_name then
                local gem_list = M.hoarding_list(gem_name, data)
                if gem_list and #gem_list < gem_number then
                    local need_for_bounty = gem_number - #gem_list
                    if need_for_bounty > 0 then
                        M.shake(need_for_bounty, gem_name, data)
                    end
                end
            end
        end

        ::continue_type::
    end

    -- Leave the locker
    M.leave_locker(data)

    -- Go back to original room
    Util().go2(start_room, data)
end

-- ---------------------------------------------------------------------------
-- 16. shake (lines 4167-4210)
-- Shake jar for contents.
-- ---------------------------------------------------------------------------

--- Shake items out of a jar.
-- @param number number how many items to shake out
-- @param name string normalized item name
-- @param data table ELoot data state
function M.shake(number, name, data)
    Util().msg({ type = "debug", text = "number: " .. tostring(number) .. " | name: " .. tostring(name) }, data)

    -- Refresh the cache
    Util().get_command("look in #" .. data.stash.id,
        { "<container id='.-' title=" }, nil, data)

    local contents = data.stash.contents and data.stash.contents() or {}
    local jar = nil
    local esc_name = name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for _, obj in ipairs(contents) do
        if is_jar(obj) and obj.after_name then
            local norm = M.normalize_name(obj.after_name)
            if norm and norm:find("^" .. esc_name .. "$") then
                jar = obj
                break
            end
        end
    end

    Util().msg({ type = "debug", text = "jar: " .. tostring(jar and jar.name or "nil") }, data)

    if not jar then return end

    -- Try to get the jar in hand
    for attempt = 1, 3 do
        Inventory().drag(jar, data)
        if Util().in_hand(jar, data) then break end
        if data.locker or data.use_house_locker then
            M.open_locker(true, data)
        end
    end

    -- Shake out items
    for i = 1, number do
        local lines = Util().get_command("shake #" .. jar.id,
            { 'You give your <a exist="' }, nil, data)

        -- Find the item that's not the jar
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local item = nil
        if rh and rh.id and tostring(rh.id) ~= tostring(jar.id) then
            item = rh
        elseif lh and lh.id and tostring(lh.id) ~= tostring(jar.id) then
            item = lh
        end

        if item then
            Inventory().store_item(data.stow_list and data.stow_list.default or nil, item, data)
        end

        if any_match(lines, "That was the last") then
            -- Remove from inventory
            local new_inv = {}
            for _, inv_item in ipairs(data.inventory) do
                if inv_item.item ~= name then
                    new_inv[#new_inv + 1] = inv_item
                end
            end
            data.inventory = new_inv
            Util().save_hoard_profile(data)
            break
        end
    end

    M.check_jar(name, data)

    -- Refresh locker contents
    Util().get_command("look in #" .. data.stash.id,
        { "<container id='.-' title=" }, nil, data)

    -- Put jar back
    for attempt = 1, 3 do
        Inventory().store_item(data.stash, jar, data)
        if not Util().in_hand(jar, data) then break end
        if data.locker or data.use_house_locker then
            M.open_locker(true, data)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 17. check_jar (lines 4212-4242)
-- Check jar inventory.
-- ---------------------------------------------------------------------------

--- Check a jar's current contents and update inventory tracking.
-- @param item_name string normalized item name
-- @param data table ELoot data state
function M.check_jar(item_name, data)
    local need_save = false

    -- Find the jar in hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local jar = nil
    if rh and is_jar(rh) then jar = rh end
    if not jar and lh and is_jar(lh) then jar = lh end

    if not jar then return end

    local jar_lines = Util().get_command("look in #" .. jar.id,
        { "^Inside .- you see %d+ portion", '^The <a exist=".-is empty' }, nil, data)

    local count_str = find_match(jar_lines, "^Inside .- you see (%d+) portion")
    if count_str then
        local count = tonumber(count_str) or 0
        local is_full = any_match(jar_lines, "It is full")
        local esc_name = item_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

        -- Find and update the inventory entry
        for _, inv_item in ipairs(data.inventory) do
            if inv_item.item and inv_item.item:find("^" .. esc_name .. "$") then
                inv_item.count = count
                inv_item.full = is_full
                need_save = true
                break
            end
        end

    elseif any_match(jar_lines, "is empty") then
        -- Update or add empty jar count
        local found = false
        for _, inv_item in ipairs(data.inventory) do
            if inv_item.item and inv_item.item:lower():find("empty jar") then
                inv_item.count = inv_item.count + 1
                found = true
                break
            end
        end
        if not found then
            data.inventory[#data.inventory + 1] = {
                item = "*** empty jars ***",
                count = 1,
                full = "  -",
            }
        end
        need_save = true
    end

    if need_save then
        Util().save_hoard_profile(data)
    end
end

-- ---------------------------------------------------------------------------
-- 18. hoarding_list (lines 4244-4268)
-- Compile list of items to hoard.
-- ---------------------------------------------------------------------------

--- Build the list of items to hoard from configured containers.
-- @param single string|nil if given, filter for items matching this name
-- @param data table ELoot data state
-- @return table list of matching items (when single is given)
function M.hoarding_list(single, data)
    data.items_to_hoard = {}
    local obj_type = data.hoard_type == "alchemy" and "reagent" or data.hoard_type

    -- Get containers to search
    local item_containers = {}
    local stow_list = data.stow_list or {}
    for _, key in ipairs(data.container_settings or {}) do
        local container = stow_list[key]
        if container then
            item_containers[#item_containers + 1] = container
        end
    end

    -- Gather items from containers
    for _, container in ipairs(item_containers) do
        Inventory().open_single_container(container, data)
        local contents = container.contents and container.contents() or {}
        for _, item in ipairs(contents) do
            data.items_to_hoard[#data.items_to_hoard + 1] = item
        end
    end

    -- If searching for a single item, return just matching items
    if single then
        local result = {}
        local esc = single:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        for _, item in ipairs(data.items_to_hoard) do
            if item.name and item.name:find(esc) then
                result[#result + 1] = item
            end
        end
        return result
    end

    -- Filter by type
    local typed = {}
    for _, item in ipairs(data.items_to_hoard) do
        if item.type and item.type:find(obj_type) then
            typed[#typed + 1] = item
        end
    end
    data.items_to_hoard = typed

    -- Apply exclusion list (everything_list means "hoard everything except these")
    if data.everything_list and data.everything and #data.everything > 0 then
        local filtered = {}
        for _, item in ipairs(data.items_to_hoard) do
            local excluded = false
            for _, excl in ipairs(data.everything) do
                if item.name and item.name:find(excl) then
                    excluded = true
                    break
                end
            end
            if not excluded then
                filtered[#filtered + 1] = item
            end
        end
        data.items_to_hoard = filtered
    end

    -- Apply inclusion list (only_list means "only hoard these items")
    if data.only_list and data.only and #data.only > 0 then
        local filtered = {}
        for _, item in ipairs(data.items_to_hoard) do
            local included = false
            for _, incl in ipairs(data.only) do
                if item.name and item.name:find(incl) then
                    included = true
                    break
                end
            end
            if included then
                filtered[#filtered + 1] = item
            end
        end
        data.items_to_hoard = filtered
    end

    return data.items_to_hoard
end

-- ---------------------------------------------------------------------------
-- 19. process_gems (lines 4270-4289)
-- Process gems for hoarding, accounting for gem bounty.
-- ---------------------------------------------------------------------------

--- Process a list of gems, removing those needed for a bounty.
-- @param inventory_gems table list of gem items
-- @param data table ELoot data state
-- @return table filtered list of gems to hoard
function M.process_gems(inventory_gems, data)
    if not data.settings.gem_horde_turnin then return inventory_gems end
    if not Bounty or not Bounty.task or not Bounty.task.gem then return inventory_gems end
    if not Bounty.task.gem() then return inventory_gems end
    if data.hoard_type ~= "gem" then return inventory_gems end

    local gem_name, gem_number = M.check_gem_bounty(data)
    if not gem_name then return inventory_gems end

    -- Check if the first item matches the bounty gem
    if #inventory_gems == 0 then return inventory_gems end
    local first_norm = M.normalize_name(inventory_gems[1].name)
    if first_norm ~= gem_name then return inventory_gems end

    -- Do we have enough?
    if #inventory_gems > gem_number then
        -- Remove gem_number items from the end
        for _ = 1, gem_number do
            table.remove(inventory_gems)
        end
    else
        local need_for_bounty = gem_number - #inventory_gems
        -- Check if we have stock in the locker
        local have_stock = false
        for _, thing in ipairs(data.inventory) do
            if thing.item == gem_name then
                have_stock = true
                break
            end
        end
        if have_stock then
            if need_for_bounty > 0 then
                M.shake(need_for_bounty, gem_name, data)
            end
            inventory_gems = {}
        end
    end

    return inventory_gems
end

-- ---------------------------------------------------------------------------
-- 20. get_gem_bounty (lines 4291-4298)
-- Retrieve gem bounty item from locker.
-- ---------------------------------------------------------------------------

--- Retrieve gems needed for a bounty from the hoard.
-- @param data table ELoot data state
function M.get_gem_bounty(data)
    if not data.settings.gem_horde_turnin then return end
    if not Bounty or not Bounty.task or not Bounty.task.gem then return end
    if not Bounty.task.gem() then return end

    local gem_name, gem_number = M.check_gem_bounty(data)
    if not gem_name then return end

    M.hoarding_list(gem_name, data)

    M.raid_cache({ "get_gem_bounty", "raid", "gem", gem_name, "x" .. tostring(gem_number) }, data)
end

-- ---------------------------------------------------------------------------
-- 21. store_items (lines 4300-4417)
-- Store items in locker. Complex: jar handling, overflow, full locker.
-- ---------------------------------------------------------------------------

--- Store hoarding items into jars in the stash container.
-- @param deposit boolean if true, skip gem bounty processing
-- @param data table ELoot data state
function M.store_items(deposit, data)
    local full_jars = {}

    local hoarding_items = unique_by_name(data.items_to_hoard or {})

    for _, item in ipairs(hoarding_items) do
        local jar = nil
        local item_name = M.normalize_name(item.name)
        Util().msg({ type = "debug", text = "item_name: " .. tostring(item_name) .. " | item.name: " .. tostring(item.name) }, data)

        if not item_name then goto continue_store end

        -- Skip items with full jars
        if contains(full_jars, item_name) then goto continue_store end

        -- Check if jar is full in inventory
        local inv_entry = nil
        for _, inv_item in ipairs(data.inventory) do
            if inv_item.item == item_name then
                inv_entry = inv_item
                break
            end
        end
        if inv_entry and inv_entry.full == true then
            full_jars[#full_jars + 1] = item_name
            Util().msg({ text = " Skipping deposit of " .. item.name .. " because its jar is full.", space = true }, data)
            goto continue_store
        end

        -- Skip gem bounty items
        if data.hoard_type == "gem" then
            local gem_name = M.check_gem_bounty(data)
            if gem_name and item_name == gem_name then
                Util().msg({ text = " Skipping deposit of " .. item.name .. " because its needed for a gem bounty.", space = true }, data)
                goto continue_store
            end
        end

        -- Get items matching this name from containers
        local items_to_hoard = M.hoarding_list(item.name, data)

        if not deposit then
            items_to_hoard = M.process_gems(items_to_hoard, data)
        end

        if #items_to_hoard == 0 then goto continue_store end

        -- Find existing jar for this item or an empty jar
        local contents = data.stash.contents and data.stash.contents() or {}
        local bottle = nil
        local empty = nil
        local esc_item_name = item_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

        for _, obj in ipairs(contents) do
            if is_jar(obj) then
                if obj.after_name then
                    local norm = M.normalize_name(obj.after_name)
                    if norm and norm:find("^" .. esc_item_name .. "$") then
                        bottle = obj
                        break
                    end
                elseif not empty then
                    empty = obj
                end
            end
        end

        -- Get the jar into hand
        if bottle then
            for attempt = 1, 3 do
                Inventory().drag(bottle, data)
                if Util().in_hand(bottle, data) then break end
                if data.locker or data.use_house_locker then
                    M.open_locker(true, data)
                end
            end

            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh and is_jar(rh) then jar = rh end
            if not jar and lh and is_jar(lh) then jar = lh end

        elseif empty then
            for attempt = 1, 3 do
                Inventory().drag(empty, data)
                if Util().in_hand(empty, data) then break end
                if data.locker or data.use_house_locker then
                    M.open_locker(true, data)
                end
            end

            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh and is_jar(rh) then jar = rh end
            if not jar and lh and is_jar(lh) then jar = lh end

            -- Update empty jar count
            for idx, inv_item in ipairs(data.inventory) do
                if inv_item.item and inv_item.item:lower():find("empty jar") then
                    local remaining_contents = data.stash.contents and data.stash.contents() or {}
                    local count = 0
                    for _, obj in ipairs(remaining_contents) do
                        if is_jar(obj) and (not obj.after_name or obj.after_name == "") then
                            count = count + 1
                        end
                    end
                    if count == 0 then
                        table.remove(data.inventory, idx)
                    else
                        data.inventory[idx].count = count
                    end
                    Util().save_hoard_profile(data)
                    break
                end
            end
        end

        if not jar then
            Util().msg({ text = " No empty jars found to store " .. item.name .. ".", space = true }, data)
            goto continue_store
        end

        -- Store each matching item into the jar
        local thing_name = nil
        for _, thing in ipairs(items_to_hoard) do
            thing_name = M.normalize_name(thing.name)

            Inventory().drag(thing, data)

            local result = Util().get_res("_drag #" .. thing.id .. " #" .. jar.id,
                "You .*add.*|You .*put.*|The.-is full", data)

            if result then
                if result:find("into your empty") then
                    -- New jar entry
                    data.inventory[#data.inventory + 1] = {
                        item = thing_name,
                        count = 1,
                        full = false,
                    }
                    -- Deduplicate
                    local seen = {}
                    local unique = {}
                    for _, inv_item in ipairs(data.inventory) do
                        if not seen[inv_item.item] then
                            seen[inv_item.item] = true
                            unique[#unique + 1] = inv_item
                        end
                    end
                    data.inventory = unique

                elseif result:find("is full") then
                    Util().msg({ text = "Something went wrong. Need to rebaseline inventory.", space = true }, data)

                    Inventory().store_item(data.stash, jar, data)
                    local stow_default = data.stow_list and data.stow_list.default or nil
                    Inventory().store_item(stow_default, thing, data)
                    waitrt()

                    M.build_inventory(true, data)
                    break
                end

                -- Track deposit
                data.hoard_deposit[#data.hoard_deposit + 1] = {
                    item = thing_name,
                    type = data.hoard_type,
                }

                -- Jar is filling up
                if result:find("filling it") then
                    break
                end
            end
        end

        -- Update jar inventory tracking
        if thing_name then
            M.check_jar(thing_name, data)
        end

        -- Refresh locker contents
        Util().get_command("look in #" .. data.stash.id,
            { "<container id='.-' title=" }, nil, data)

        -- Put jar back
        for attempt = 1, 3 do
            Inventory().store_item(data.stash, jar, data)
            if not Util().in_hand(jar, data) then break end
            if data.locker or data.use_house_locker then
                M.open_locker(true, data)
            end
        end

        ::continue_store::
    end
end

-- ---------------------------------------------------------------------------
-- 22. raid_cache (lines 4419-4461)
-- Raid locker for specific items.
-- ---------------------------------------------------------------------------

--- Raid the hoard cache for specific items.
-- @param options table command args: { ..., type, item_words..., xN }
-- @param data table ELoot data state
function M.raid_cache(options, data)
    Util().msg({ type = "debug", text = "options: " .. table.concat(options, " ") }, data)

    -- Validate type argument (index 3 in 1-based)
    if not options[3] or not (options[3]:find("gem") or options[3]:find("reagent") or options[3]:find("alchemy")) then
        Util().msg({ text = " To use this option - ;eloot raid <type> <item to get> x<how many>." }, data)
        Util().msg({ text = " Ex ;eloot raid gem blue diamond x5" }, data)
        Util().msg({ text = " <type> can be gem or reagent" }, data)
        return
    end

    Inventory().clear_hands(data)

    local hoard_type
    if options[3]:find("reagent") or options[3]:find("alchemy") then
        hoard_type = "alchemy"
    else
        hoard_type = "gem"
    end

    M.set_type_vars(hoard_type, data)

    -- Find the count (xN)
    local number = 1
    local search_parts = {}
    for i = 4, #options do
        local count_match = options[i]:match("^[Xx](%d+)$")
        if count_match then
            number = tonumber(count_match) or 1
        else
            search_parts[#search_parts + 1] = options[i]
        end
    end

    local search_string = table.concat(search_parts, " ")
    local item = M.normalize_name(search_string)
    if item then item = item:lower() end
    Util().msg({ type = "debug", text = "search_string: " .. search_string .. " | item: " .. tostring(item) }, data)

    -- Check if item exists in inventory
    if not item then
        Util().msg({ text = " Not able to find item in your cache." }, data)
        return
    end

    local esc_item = item:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local found = false
    for _, thing in ipairs(data.inventory or {}) do
        if thing.item and thing.item:find("^" .. esc_item .. "$") then
            found = true
            break
        end
    end

    if not found then
        Util().msg({ text = " Not able to find " .. item .. " in your cache." }, data)
        Util().msg({ text = " Run ;eloot reset " .. hoard_type .. " to re-baseline it if needed." }, data)
        return
    end

    local start_room = Room.current().id
    M.hoard_prep(data)

    M.shake(number, item, data)

    M.leave_locker(data)

    Util().go2(start_room, data)
    Inventory().return_hands(data)
end

return M
