--- ELoot loot module
-- Ported from eloot.lic ELoot::Loot submodule (lines 4467-5090).
-- Handles searching dead creatures, skinning, looting items/boxes/bags.
--
-- Usage:
--   local Loot = require("gs.eloot.loot")
--   Loot.room(data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires to avoid circular dependencies
-- ---------------------------------------------------------------------------

local function Util()      return require("gs.eloot.util") end
local function Inventory() return require("gs.eloot.inventory") end
local function Sell()      return require("gs.eloot.sell") end

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

local function any_match_multi(lines, patterns)
    if not lines then return false end
    for _, l in ipairs(lines) do
        for _, pat in ipairs(patterns) do
            if l:find(pat) then return true end
        end
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

local function contains_name(tbl, name)
    if not tbl or not name then return false end
    for _, v in ipairs(tbl) do
        if v == name then return true end
    end
    return false
end

--- Check if a name matches any pattern in a list.
local function name_matches_any(name, list)
    if not name or not list or #list == 0 then return false end
    for _, pat in ipairs(list) do
        if string.find(name, pat) then return true end
    end
    return false
end

--- Build a combined Lua pattern alternation from a list of strings.
-- For simple substring matching, returns a function that checks all entries.
local function make_matcher(list)
    if not list or #list == 0 then return function() return false end end
    return function(str)
        if not str then return false end
        for _, pat in ipairs(list) do
            if string.find(str, pat) then return true end
        end
        return false
    end
end

-- ---------------------------------------------------------------------------
-- 1. bag_loot (lines 4467-4511)
-- Loot bags dropped by creatures that have treasure in them.
-- ---------------------------------------------------------------------------

--- Loot a bag container dropped by a creature.
-- @param bag table GameObj bag
-- @param data table ELoot data state
-- @return string|nil "crumbly" if bag crumbles, nil otherwise
function M.bag_loot(bag, data)
    if contains(data.checked_bags, bag.id) then return end

    local lines = Util().get_command("open #" .. bag.id,
        { "crumbles? and decays? away", "<exposeContainer", "That is already open",
          "<container", "There doesn't seem to be any way to do that",
          "I could not find what you were referring to" },
        { silent = true, quiet = true }, data)

    if any_match(lines, "crumbles? and decays? away") then
        if not (bag.name and (string.find(bag.name, "bandana") or string.find(bag.name, "flowing robes"))) then
            Util().msg({ type = "info", text = " " .. tostring(bag) .. " was crumbly, adding to list" }, data)
            table.insert(data.settings.crumbly, bag.name)
            Util().save_profile(data)
        end
        return "crumbly"
    end

    if any_match_multi(lines, {
        "There doesn't seem to be any way to do that",
        "I could not find what you were referring to"
    }) then
        table.insert(data.checked_bags, bag.id)
        return
    end

    lines = Util().get_command("look in #" .. bag.id,
        { "<container", "That is closed" },
        { silent = true, quiet = true }, data)

    if any_match(lines, "I could not find what you were referring to") then
        return false
    end

    local objs = M.reject_invalid_loot(bag.contents or {}, data)

    if #objs == 0 then
        table.insert(data.checked_bags, bag.id)
        return
    end

    objs = M.loot_specials(objs, data)

    if #objs == 0 then
        table.insert(data.checked_bags, bag.id)
        return
    end

    M.loot_regular(objs, nil, nil, data)

    table.insert(data.checked_bags, bag.id)
end

-- ---------------------------------------------------------------------------
-- 2. box_loot (lines 4513-4557)
-- Loot box contents: open, look, drag each item.
-- ---------------------------------------------------------------------------

--- Loot the contents of a box.
-- @param box table GameObj box
-- @param location string|nil silver tracking key (e.g. "Town Locksmith")
-- @param data table ELoot data state
function M.box_loot(box, location, data)
    if box.type == "box" then
        local line = Util().get_res("open #" .. box.id, { "open", "locked" }, data)
        if line and string.find(line, "locked") then
            Inventory().single_drag(box, nil, data)
            return
        end

        local quiet_msg = data.settings.display_box_contents and false or true
        Util().get_command("look in #" .. box.id, data.look_regex,
            { silent = quiet_msg, quiet = quiet_msg }, data)

        -- Make sure the item's contents are available
        if not Inventory().container_contents(box, nil, data) then
            Inventory().single_drag(box, nil, data)
            return
        end

        local start_silvers = Util().silver_check(data)
        local contents = box.contents or {}
        local has_coins = false
        for _, obj in ipairs(contents) do
            if obj.name and string.find(obj.name, "silver coins") then
                has_coins = true
                break
            end
        end

        while has_coins do
            if data.charm then
                Util().get_res("point #" .. data.charm.id .. " at #" .. box.id,
                    { "You summon" }, data)
                if location and data.silver_breakdown then
                    data.silver_breakdown[location] = (data.silver_breakdown[location] or 0)
                        + (Util().silver_check(data) - start_silvers)
                end
            else
                local res = Util().get_res("get coins from #" .. box.id,
                    { "You gather the remaining", "Get what",
                      "You can only collect", "You cannot hold any more silvers" }, data)
                if res and string.find(res, "You gather the remaining") then
                    if location and data.silver_breakdown then
                        data.silver_breakdown[location] = (data.silver_breakdown[location] or 0)
                            + (Util().silver_check(data) - start_silvers)
                    end
                    Util().wait_rt()
                    break
                elseif res and (string.find(res, "You can only collect") or
                                string.find(res, "You cannot hold any more silvers")) then
                    if location and data.silver_breakdown then
                        data.silver_breakdown[location] = (data.silver_breakdown[location] or 0)
                            + (Util().silver_check(data) - start_silvers)
                    end
                    Util().wait_rt()
                    local room = Room.current().id
                    Util().silver_deposit(nil, data)
                    start_silvers = Util().silver_check(data)
                    Util().go2(room, data)
                else
                    Util().msg({ type = "info", text = " Unknown get coin result...Exiting!" }, data)
                    error("eloot: unknown get coin result")
                end
            end
            -- Recheck for coins
            contents = box.contents or {}
            has_coins = false
            for _, obj in ipairs(contents) do
                if obj.name and string.find(obj.name, "silver coins") then
                    has_coins = true
                    break
                end
            end
        end

        local objs = box.contents or {}
        if #objs > 0 then
            objs = M.loot_specials(objs, data)
        end
        if #objs > 0 then
            M.loot_regular(objs, "Box", box, data)
        end
        Sell().save_trash_box(box, data)

    elseif box.type == "plinite" then
        Util().get_res("pluck #" .. box.id, { "You carefully pluck" }, data)
        Inventory().free_hands({ both = true }, data)
    end
end

-- ---------------------------------------------------------------------------
-- 3. box_loot_ground (lines 4559-4631)
-- Loot all boxes on ground (handles group disks, phasing).
-- ---------------------------------------------------------------------------

--- Loot all boxes on the ground.
-- @param data table ELoot data state
function M.box_loot_ground(data)
    Inventory().free_hands({ both = true }, data)

    local loot_list = GameObj.loot() or {}
    local box_list = {}
    for _, x in ipairs(loot_list) do
        if x.type == "box" then
            table.insert(box_list, x)
        end
    end

    for _, box in ipairs(box_list) do
        local line = Util().get_res("open #" .. box.id, { "open", "locked" }, data)
        if line and string.find(line, "That is locked") then
            goto continue
        end

        local quiet_msg = data.settings.display_box_contents and false or true
        Util().get_command("look in #" .. box.id, data.look_regex,
            { silent = quiet_msg, quiet = quiet_msg }, data)

        if not Inventory().container_contents(box, nil, data) then
            goto continue
        end

        -- Drag the box to our hand
        Inventory().drag(box, nil, data)

        -- Get the coins
        local contents = box.contents or {}
        local has_coins = false
        for _, obj in ipairs(contents) do
            if obj.name and string.find(obj.name, "silver coins") then
                has_coins = true
                break
            end
        end

        while has_coins do
            if data.charm then
                Util().get_res("point #" .. data.charm.id .. " at #" .. box.id,
                    { "You summon" }, data)
            else
                local res = Util().get_res("get coins from #" .. box.id,
                    { "You gather the remaining", "Get what",
                      "You can only collect", "You cannot hold any more silvers" }, data)
                if res and string.find(res, "You gather the remaining") then
                    Util().wait_rt()
                elseif res and (string.find(res, "You can only collect") or
                                string.find(res, "You cannot hold any more silvers")) then
                    Util().wait_rt()
                    Util().msg({ type = "info", text = " Can't hold any more coins...Exiting!" }, data)
                    error("eloot: can't hold any more coins")
                end
            end
            -- Recheck for coins
            contents = box.contents or {}
            has_coins = false
            for _, obj in ipairs(contents) do
                if obj.name and string.find(obj.name, "silver coins") then
                    has_coins = true
                    break
                end
            end
        end

        -- Loot the rest of the stuff
        local objs = box.contents or {}
        if #objs > 0 then
            objs = M.loot_specials(objs, data)
        end
        if #objs > 0 then
            M.loot_regular(objs, "Box", box, data)
        end

        local save_box = contains(data.settings.sell_loot_types, "box")
        local valuable_box_pat = "gold|mithril|silver"

        local function is_valuable(name)
            return name and (string.find(name, "gold") or string.find(name, "mithril") or string.find(name, "silver"))
        end

        -- If it's a save box and empty, just store it; don't toss Reliquaries
        local box_contents = box.contents or {}
        if (save_box and #box_contents == 0 and is_valuable(box.name)) or
           (box.name and string.find(box.name:lower(), "reliquary")) then
            Inventory().single_drag(box, false, data)
            goto continue
        end

        local trash = Util().find_trash(data)
        local toss_cmd = trash and "trash" or "drop"

        local has_cursed = false
        for _, obj in ipairs(box_contents) do
            if obj.type and string.find(obj.type, "cursed") then
                has_cursed = true
                break
            end
        end

        if save_box and is_valuable(box.name) and not has_cursed then
            for _, item in ipairs(box_contents) do
                Inventory().drag(item, nil, data)
                fput(toss_cmd .. " #" .. item.id)
                Util().wait_rt()

                -- if it's not gone it might be special -- save it
                if Util().in_hand(item) then
                    Inventory().single_drag(item, nil, data)
                end
            end
        else
            -- Attempt to trash the box up to 4 times
            for _ = 1, 4 do
                if not Util().in_hand(box) then break end
                fput(toss_cmd .. " #" .. box.id)
                Util().wait_rt()
            end
        end

        if Util().in_hand(box) then
            Inventory().single_drag(box, false, data)
        end

        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- 4. loot_all (lines 4633-4688)
-- Loot entire room contents.
-- ---------------------------------------------------------------------------

--- Loot all valid items in the room using the `loot room` command.
-- @param items table list of GameObj items expected to be lootable
-- @param data table ELoot data state
function M.loot_all(items, data)
    waitrt()

    Inventory().free_hand(data)

    local res = Util().get_command("loot room",
        { "<dialogData", "There is no loot", "You need a free hand to do that",
          "With a discerning eye", "You note some treasure of interest",
          "You can't.*It's closed!" }, nil, data)

    if any_match(res, "There is no loot") then
        for _, item in ipairs(items) do
            Util().unlootable(item, data)
        end
        return true
    end

    if any_match(res, "You can't.*It's closed!") then
        local items_opened = {}
        for _, item in ipairs(items) do
            local item_type = item.type
            local bag
            if item_type and StowList.stow_list[item_type]
               and not contains(data.sacks_full, StowList.stow_list[item_type]) then
                bag = StowList.stow_list[item_type]
            else
                bag = StowList.stow_list.default
            end

            if bag and not contains_name(items_opened, bag.name) then
                table.insert(items_opened, bag.name)

                local keys = GameObj.containers()
                if keys[bag.id] and type(bag.contents) == "table" then
                    local look_lines = Util().get_command("look in #" .. bag.id, data.look_regex,
                        { silent = true, quiet = true }, data)

                    if any_match(look_lines, "That is closed%.") then
                        table.insert(data.settings.auto_close, bag.name)
                        Util().msg({ type = "info", text = " " .. bag.name .. " must be an autocloser, adding to list." }, data)
                        Util().save_profile(data)
                    end
                end
            end
        end
    end

    -- Didn't get it all? Something in-hand?
    if any_match_multi(res, {
        "gather up and stow",
        "pick up and stow",
        "but quickly realize",
        "before realizing you have no room"
    }) then
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        for _, hand in ipairs({rh, lh}) do
            for _, thing in ipairs(items) do
                if thing.id == hand.id then
                    Inventory().single_drag(hand, nil, data)
                    break
                end
            end
        end

        -- Anything left?
        local remaining = GameObj.loot() or {}
        local objs = M.reject_invalid_loot(remaining, data)
        if #objs == 0 then return end

        -- Still here so rerun Loot.room
        M.room(data)
    end
end

-- ---------------------------------------------------------------------------
-- 5. loot_regular (lines 4690-4753)
-- Loot regular (non-special) items.
-- ---------------------------------------------------------------------------

--- Loot regular items from room, box, or container.
-- @param objs table list of GameObj items
-- @param from_where string|nil "Room", "Box", or nil
-- @param box table|nil the box GameObj (when from_where == "Box")
-- @param data table ELoot data state
function M.loot_regular(objs, from_where, box, data)
    Util().msg({ type = "debug", text = "objs: " .. tostring(#objs) .. " | from_where: " .. tostring(from_where) }, data)

    local valid = M.valid_objs(objs, data)
    local invalid = M.invalid_objs(objs, data)

    -- Reject coins from valid if not wanted
    if from_where == "Room" and not contains(data.settings.loot_types, "coins") then
        local new_valid = {}
        for _, o in ipairs(valid) do
            if not (o.name and string.find(o.name, "silver coin")) then
                table.insert(new_valid, o)
            end
        end
        valid = new_valid
        -- Add coin objects to invalid
        local loot_list = GameObj.loot() or {}
        for _, o in ipairs(loot_list) do
            if o.name and string.find(o.name, "silver coin") then
                table.insert(invalid, o)
            end
        end
    end

    Util().msg({ type = "debug", text = "valid: " .. #valid }, data)
    Util().msg({ type = "debug", text = "invalid: " .. #invalid }, data)

    local loot_cmd_items = "clothing|jewelry|gem|herb|skin|wand|scroll|potion|reagent|trinket|lockpick|treasure|forageable|magic|collectible|lockandkey"

    if #invalid > 0 and #valid > 0 then
        Inventory().free_hand(data)
        if from_where == "Room" then
            for _, obj in ipairs(valid) do
                if obj.type and string.find(obj.type, loot_cmd_items) then
                    Inventory().single_loot(obj, data)
                else
                    Inventory().single_drag(obj, nil, data)
                end
            end
        else
            for _, thing in ipairs(valid) do
                Inventory().single_drag(thing, nil, data)
            end
        end
    elseif #invalid == 0 and #valid > 0 then
        Inventory().free_hand(data)
        Util().msg({ type = "debug", text = "invalid empty, valid present" }, data)

        if from_where == "Room" then
            M.loot_all(valid, data)
        elseif from_where == "Box" then
            Util().get_command("loot #" .. box.id,
                { "You search through", "You can't.*It's closed!", "There is no loot", "In an attempt" },
                { silent = false, quiet = false }, data)
            Util().wait_rt()

            -- If bag fills up it can leave an item in hand
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            for _, item in ipairs({rh, lh}) do
                if item.type ~= "box" then
                    Inventory().single_drag(item, nil, data)
                end
            end

            -- If there are still box contents the default container has filled up
            local box_contents = box.contents or {}
            if #box_contents > 0 then
                local remaining_valid = M.valid_objs(box_contents, data)
                for _, thing in ipairs(remaining_valid) do
                    Inventory().single_drag(thing, nil, data)
                end
            end
        else
            for _, thing in ipairs(valid) do
                Inventory().single_drag(thing, nil, data)
            end
        end
    end

    -- Report left-behind items
    local left_behind = {}
    for _, inv_obj in ipairs(invalid) do
        table.insert(left_behind, inv_obj.name or "?")
    end
    if #left_behind > 0 then
        local suffix = #left_behind > 1 and "s" or ""
        Util().msg({ type = "info", text = " Left the following item" .. suffix .. ": " .. table.concat(left_behind, ", ") .. "." }, data)
    end

    Util().msg({ type = "debug", text = "End of method" }, data)
end

-- ---------------------------------------------------------------------------
-- 6. loot_specials (lines 4755-4807)
-- Loot special items (box, clothing, collectible, cursed, jewelry, etc.).
-- ---------------------------------------------------------------------------

--- Process special items: boxes, clothing bags, cursed, collectibles, etc.
-- Items that are "special" are looted immediately and removed from the list.
-- Returns the remaining non-special objects for regular looting.
-- @param objs table list of GameObj items
-- @param data table ELoot data state
-- @return table remaining non-special objects
function M.loot_specials(objs, data)
    Util().msg({ type = "debug", text = "objs: " .. tostring(#objs) }, data)

    -- Open sacks for looting the room
    Inventory().open_loot_containers(objs, data)

    local special_types = { "box", "clothing", "collectible", "cursed", "jewelry", "food", "breakable", "lm trap" }

    local loot_types_match = make_matcher(data.settings.loot_types)
    local loot_keep_match = make_matcher(data.settings.loot_keep or {})

    -- Uncommon items in HW that loot room doesn't work on
    local uncommon_loot = {
        "stygian valravn quill",
        "nacreous disir feather",
        "silver%-veined black draconic idol"
    }
    local uncommon_match = make_matcher(uncommon_loot)

    local remaining = {}
    for _, thing in ipairs(objs) do
        local should_remove = false

        -- Try bag_loot on clothing items
        if thing.type and string.find(thing.type, "clothing") then
            local result = M.bag_loot(thing, data)
            if result == "crumbly" then
                should_remove = true
                goto next_item
            end
        end

        -- Exclusion check
        if data.exclude and #data.exclude > 0 and thing.name and name_matches_any(thing.name, data.exclude) then
            goto keep_item
        end

        -- Oblivion quartz at level 100
        if thing.name and thing.name == "shard of oblivion quartz" and
           Stats.level == 100 and contains(data.settings.loot_types, "gem") then
            goto keep_item
        end

        -- Doomstone/urglaes fang without cursed loot type
        if thing.name and (string.find(thing.name, "doomstone") or string.find(thing.name, "urglaes fang"))
           and not contains(data.settings.loot_types, "cursed") then
            goto keep_item
        end

        -- Check if this is a special item we should handle now
        do
            local is_special = false

            -- Type matches both loot_types and special_types
            if thing.type then
                local matches_loot = false
                local matches_special = false
                for _, lt in ipairs(data.settings.loot_types) do
                    if string.find(thing.type, lt) then matches_loot = true; break end
                end
                for _, st in ipairs(special_types) do
                    if string.find(thing.type, st) then matches_special = true; break end
                end
                if matches_loot and matches_special then is_special = true end
            end

            -- lockandkey type
            if thing.type and string.find(thing.type, "lockandkey") then is_special = true end

            -- loot_keep match
            if data.settings.loot_keep and #data.settings.loot_keep > 0 and
               thing.name and loot_keep_match(thing.name) then
                is_special = true
            end

            -- Cursed items with cursed enabled
            if thing.type and string.find(thing.type, "cursed") and
               contains(data.settings.loot_types, "cursed") then
                is_special = true
            end

            -- Uncommon weapon with weapon enabled
            if thing.type and string.find(thing.type, "weapon") and string.find(thing.type, "uncommon") and
               contains(data.settings.loot_types, "weapon") then
                is_special = true
            end

            -- Uncommon armor with armor enabled
            if thing.type and string.find(thing.type, "armor") and string.find(thing.type, "uncommon") and
               contains(data.settings.loot_types, "armor") then
                is_special = true
            end

            -- Magic orbs
            if thing.name and string.find(thing.name, "orb") and
               thing.type and string.find(thing.type, "magic") and
               contains(data.settings.loot_types, "magic") then
                is_special = true
            end

            -- Uncommon loot items from HW
            if thing.name and uncommon_match(thing.name) and
               contains(data.settings.loot_types, "uncommon") then
                is_special = true
            end

            -- Silver coins
            if thing.name and string.find(thing.name, "silver coin") and
               contains(data.settings.loot_types, "coins") then
                is_special = true
            end

            if not is_special then
                goto keep_item
            end
        end

        -- Handle the special item
        if thing.name and string.find(thing.name, "silver coin") then
            local coin_cmd
            if data.charm then
                coin_cmd = "rub #" .. data.charm.id
            else
                coin_cmd = "get coins"
            end
            Util().get_res(coin_cmd, { "you gather", "you summon" }, data)
        else
            if Util().decurse(thing, data) then
                Inventory().free_hand(data)
                Inventory().single_drag(thing, nil, data)
            end
        end

        should_remove = true
        goto next_item

        ::keep_item::
        -- Item is NOT special, keep it in remaining
        table.insert(remaining, thing)

        ::next_item::
    end

    Util().msg({ type = "debug", text = "After specials check objs: " .. #remaining }, data)
    return remaining
end

-- ---------------------------------------------------------------------------
-- 7. occassional_skinner (lines 4809-4818)
-- Check for occasional skin-able creatures.
-- ---------------------------------------------------------------------------

--- Check if a normally unskinnable creature can sometimes be skinned.
-- @param obj table GameObj dead creature
-- @param data table ELoot data state
-- @return boolean true if creature is occasionally skinnable
function M.occassional_skinner(obj, data)
    if obj.name and string.find(obj.name, "rotting chimera") then
        local lines = Util().get_command("describe chimera",
            { "The twisted and confused form" },
            { silent = true, quiet = true }, data)
        if any_match(lines, "A huge scorpion tail rises high from the rear") then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 8. reject_invalid_loot (lines 4820-4836)
-- Filter out invalid loot items.
-- ---------------------------------------------------------------------------

--- Remove invalid items from the loot list.
-- Filters by reject_loot_names, reject_loot_nouns, disks, weapon/armor, etc.
-- @param objs table list of GameObj items
-- @param data table ELoot data state
-- @return table filtered list of valid items
function M.reject_invalid_loot(objs, data)
    local name_match = make_matcher(data.reject_loot_names or {})
    local noun_match = make_matcher(data.reject_loot_nouns or {})
    local keep_match = make_matcher(data.settings.loot_keep or {})
    local disk_nouns_match = data.disk_nouns_regex and make_matcher(
        type(data.disk_nouns_regex) == "table" and data.disk_nouns_regex or { data.disk_nouns_regex }
    ) or function() return false end

    local result = {}
    for _, obj in ipairs(objs) do
        local reject = false

        -- Keep items in loot_keep list
        if data.settings.loot_keep and #data.settings.loot_keep > 0 and
           obj.name and keep_match(obj.name) then
            table.insert(result, obj)
            goto continue
        end

        -- Keep bounty heirloom items
        if Bounty and Bounty.task and Bounty.task.heirloom and
           Bounty.task:heirloom() and Bounty.task.requirements and
           Bounty.task.requirements.item and obj.name and
           string.find(obj.name:lower(), Bounty.task.requirements.item:lower()) then
            table.insert(result, obj)
            goto continue
        end

        -- Reject by name
        if obj.name and name_match(obj.name) then reject = true end

        -- Reject disks (capitalized name + disk noun)
        if not reject and obj.name and disk_nouns_match(obj.name) then
            -- Check for capital letter pattern: "Name disk"
            if string.find(obj.name, "^%u%l+ ") then
                reject = true
            end
        end

        -- Reject by noun
        if not reject and obj.noun and noun_match(obj.noun) then reject = true end

        -- Reject negative IDs
        if not reject and obj.id and tonumber(obj.id) and tonumber(obj.id) < 0 then reject = true end

        -- Reject weapon/armor that isn't uncommon/clothing
        if not reject and obj.type then
            if (string.find(obj.type, "weapon") or string.find(obj.type, "armor")) and
               not string.find(obj.type, "uncommon") and not string.find(obj.type, "clothing") then
                reject = true
            end
        end

        -- Reject logged unlootables
        if not reject and data.settings.unlootable and data.settings.log_unlootables then
            if contains_name(data.settings.unlootable, obj.name) then
                reject = true
            end
        end

        -- Reject crumbly items
        if not reject and data.settings.crumbly and obj.name then
            if contains_name(data.settings.crumbly, obj.name) then
                reject = true
            end
        end

        if not reject then
            table.insert(result, obj)
        end

        ::continue::
    end

    return result
end

-- ---------------------------------------------------------------------------
-- 9. should_grab_item (lines 4838-4860)
-- Check if specific item should be grabbed.
-- ---------------------------------------------------------------------------

--- Determine if a specific item should be looted.
-- @param thing table GameObj item
-- @param data table ELoot data state
-- @return boolean true if item should be grabbed
function M.should_grab_item(thing, data)
    -- If its on the exclude list, return false
    if data.exclude and #data.exclude > 0 and thing.name and name_matches_any(thing.name, data.exclude) then
        return false
    end

    -- Oblivion quartz isn't cursed if you are level 100
    if thing.name and thing.name == "shard of oblivion quartz" and
       Stats.level == 100 and contains(data.settings.loot_types, "gem") then
        return true
    end

    -- Cursed items need separate handling due to gems
    if thing.type and string.find(thing.type, "cursed") and
       not contains(data.settings.loot_types, "cursed") then
        return false
    end

    -- Keep it if it's a type we want
    if thing.type then
        for _, lt in ipairs(data.settings.loot_types) do
            if string.find(thing.type, lt) then return true end
        end
    end

    -- Keep if it's our current bounty heirloom assignment
    if Bounty and Bounty.task and Bounty.task.heirloom and Bounty.task:heirloom() and
       Bounty.task.requirements and Bounty.task.requirements.item and
       thing.name and string.find(thing.name:lower(), Bounty.task.requirements.item:lower()) then
        return true
    end

    -- If the type is something we don't want, return false
    if thing.type and data.all_loot_categories then
        local not_wanted = {}
        for _, cat in ipairs(data.all_loot_categories) do
            if not contains(data.settings.loot_types, cat) then
                table.insert(not_wanted, cat)
            end
        end
        for _, nw in ipairs(not_wanted) do
            if string.find(thing.type, nw) then return false end
        end
    end

    -- Anything left, lets take
    return true
end

-- ---------------------------------------------------------------------------
-- 10. valid_objs / invalid_objs (lines 4862-4868)
-- Filter objects by type.
-- ---------------------------------------------------------------------------

--- Select only items we want to loot.
-- @param objs table list of GameObj items
-- @param data table ELoot data state
-- @return table list of wanted items
function M.valid_objs(objs, data)
    local result = {}
    for _, o in ipairs(objs) do
        if M.should_grab_item(o, data) then
            table.insert(result, o)
        end
    end
    return result
end

--- Select only items we do NOT want to loot.
-- @param objs table list of GameObj items
-- @param data table ELoot data state
-- @return table list of unwanted items
function M.invalid_objs(objs, data)
    local result = {}
    for _, o in ipairs(objs) do
        if not M.should_grab_item(o, data) then
            table.insert(result, o)
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 11. room (lines 4870-4881)
-- Main room loot entry point.
-- ---------------------------------------------------------------------------

--- Loot the current room.
-- @param data table ELoot data state
function M.room(data)
    local loot_list = GameObj.loot() or {}
    local objs = M.reject_invalid_loot(loot_list, data)

    if #objs > 0 then
        objs = M.loot_specials(objs, data)
    end

    if #objs > 0 then
        M.loot_regular(objs, "Room", nil, data)
    end
end

-- ---------------------------------------------------------------------------
-- 12. search (lines 4883-4946)
-- Search dead creatures.
-- ---------------------------------------------------------------------------

--- Search dead creatures in the room.
-- Handles bounty children, failed bounties, search messaging, Sigil of Determination.
-- @param objs table|nil list of dead creatures (defaults to GameObj.dead())
-- @param data table ELoot data state
function M.search(objs, data)
    objs = objs or (GameObj.dead() or {})
    if #objs == 0 then return end

    local regex_at_feet = '<pushBold/> %*%* A glint of light catches your eye, and you notice an? <a exist="(%d+)" noun="([%w%-]+)">([%w%s%-]+)</a>.*? at your feet! %*%*'
    local inhand_critters = "skayl|glacei|tumbleweed|plant|shrub|creeper|vine|bush|caedera|golem|elemental"

    for _, thing in ipairs(objs) do
        -- Skip excluded critters
        if data.settings.critter_exclude and #data.settings.critter_exclude > 0 and
           thing.name and name_matches_any(thing.name, data.settings.critter_exclude) then
            goto next_creature
        end

        -- Skip children
        if thing.name and string.find(thing.name, "child") then
            goto next_creature
        end

        -- Skip gone creatures
        if thing.status and string.find(thing.status, "gone") then
            goto next_creature
        end

        -- Go defensive if setting is on
        if data.settings.loot_defensive then
            Util().change_stance(100, data)
        end

        -- Blood bands
        if data.settings.use_bloodbands and data.blood_band then
            fput("raise #" .. data.blood_band.id .. " at #" .. thing.id)
        end

        -- Handle in-hand creatures
        local free_hand = nil
        if thing.name and name_matches_any(thing.name, { "skayl", "glacei", "tumbleweed", "plant", "shrub", "creeper", "vine", "bush", "caedera", "golem", "elemental" }) then
            if thing.name and (string.find(thing.name, "tumbleweed") or string.find(thing.name, "plant") or
               string.find(thing.name, "shrub") or string.find(thing.name, "creeper") or
               string.find(thing.name, "vine") or string.find(thing.name, "bush")) then
                Inventory().free_hands({ left = true }, data)
            else
                Inventory().free_hand(data)
            end

            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if rh.id == nil and lh.id == nil then
                free_hand = "left"
            else
                free_hand = (rh.id == nil) and "right" or "left"
            end
        end

        -- Loot it (up to 3 attempts)
        for attempt = 1, 3 do
            waitrt()
            local results = Util().get_command("loot #" .. thing.id,
                { "You search", "You plunge", "You break",
                  "not in any condition", "see well enough to search",
                  "You can only loot creatures",
                  "Geez!  It's still alive!  Not a good time for that%." },
                { silent = false, quiet = false }, data)

            Util().msg({ type = "debug", text = "Thing: " .. tostring(thing.id) .. "-" .. tostring(thing.name) .. ", Results: " .. tostring(results[1]) }, data)

            -- Sigil of Determination on fail
            if any_match(results, "not in any condition") and
               data.settings.sigil_determination_on_fail and
               Spell["Sigil of Determination"] and
               Spell["Sigil of Determination"].affordable and
               not Spell["Sigil of Determination"].active then
                Spell["Sigil of Determination"]:cast()
                goto next_attempt
            end

            -- Check for items at feet
            if results then
                for _, line in ipairs(results) do
                    local id, noun, name = string.match(line, regex_at_feet)
                    if id then
                        Inventory().free_hand(data)
                        -- Create a simple object reference for drag
                        local found_obj = { id = id, noun = noun, name = name }
                        Inventory().single_drag(found_obj, nil, data)
                    end
                end
            end

            -- Break conditions
            if any_match_multi(results, {
                "You search", "You plunge", "You break",
                "not in any condition", "see well enough to search",
                "You can only loot creatures",
                "Geez!  It's still alive!"
            }) then
                break
            end

            if thing == nil or (thing.status and string.find(thing.status, "gone")) then
                break
            end

            ::next_attempt::
        end

        -- Some creatures put an item directly in your hand
        if free_hand and thing.name and name_matches_any(thing.name, { "skayl", "glacei", "tumbleweed", "plant", "shrub", "creeper", "vine", "bush", "caedera", "golem", "elemental" }) then
            local check_hand
            if free_hand == "right" then
                check_hand = GameObj.right_hand()
            else
                check_hand = GameObj.left_hand()
            end
            if check_hand.name ~= "Empty" then
                Inventory().single_drag(check_hand, nil, data)
            end
        end

        ::next_creature::
    end

    -- If the setting is on, always end in defensive
    if data.settings.loot_defensive then
        Util().change_stance(100, data)
    end
end

-- ---------------------------------------------------------------------------
-- 13. skin_obj_types (lines 4948-5059)
-- Skin by weapon type (edged/blunt).
-- ---------------------------------------------------------------------------

--- Skin dead creatures using a specific weapon type.
-- Handles weapon swap, kneeling, resolve sigils, 604 spell, skin messaging.
-- @param objs table list of dead creatures to skin
-- @param skin_type string ":blunt" or ":normal"
-- @param data table ELoot data state
function M.skin_obj_types(objs, skin_type, data)
    if #objs == 0 then return end

    local dont_stow = false
    waitrt()

    local skinner

    if skin_type == "blunt" then
        -- Check skinner and sheath in case ReadyList/StowList got updated
        Util().ensure_items({ key = "skin_weapon_blunt", list = ReadyList.ready_list, inventory = data.weapon_inv }, data)
        Util().ensure_items({ key = "skin_sheath_blunt", list = ReadyList.ready_list, check_hidden = true }, data)

        skinner = ReadyList.ready_list.skin_weapon_blunt
        Util().msg({ type = "debug", text = "blunt skinner: " .. tostring(skinner) }, data)
        if not skinner then
            Util().msg({ type = "info", text = " No blunt weapon found. Please run setup and make sure it's listed." }, data)
            return
        end
        Inventory().free_hands({ both = true }, data)
    else
        -- Check skinner and sheath in case ReadyList/StowList got updated
        Util().ensure_items({ key = "skin_weapon", list = ReadyList.ready_list, inventory = data.weapon_inv }, data)
        Util().ensure_items({ key = "skin_sheath", list = ReadyList.ready_list, check_hidden = true }, data)

        if not ReadyList.ready_list.skin_weapon or tostring(ReadyList.ready_list.skin_weapon) == "" then
            skinner = GameObj.right_hand()
            Util().msg({ type = "info", text = " No edged skinning weapon found. Using your right hand." }, data)
        else
            skinner = ReadyList.ready_list.skin_weapon
        end

        Util().msg({ type = "debug", text = "edged skinner: " .. tostring(skinner) }, data)

        if Util().in_hand(skinner) then
            dont_stow = true
        end

        if not dont_stow then
            Inventory().free_hand(data)
        end
    end

    if not Util().in_hand(skinner) then
        waitrt()
        Inventory().drag(skinner, nil, data)
    end

    local lh = GameObj.left_hand()
    local skinner_hand = (skinner.id == lh.id) and "left" or "right"

    -- Safe to kneel?
    local targets = GameObj.targets and GameObj.targets() or {}
    while #targets == 0 and data.settings.skin_kneel and not kneeling() do
        dothistimeout("kneel", 3, { "You kneel down%.$", "You move to", "You are already kneeling%.$" })
        targets = GameObj.targets and GameObj.targets() or {}
    end

    -- Sigil of Resolve?
    if data.settings.skin_resolve and
       Spell["Sigil of Resolve"] and
       Spell["Sigil of Resolve"].affordable and
       not Spell["Sigil of Resolve"].active then
        Spell["Sigil of Resolve"]:cast()
    end

    -- 604 spell
    if data.settings.skin_604 and Spell[604] and Spell[604].affordable and
       (not Spell[604].active or (Spell[604].timeleft and (Spell[604].timeleft * 60) <= 10)) then
        local max_attempts = 20
        local attempts = 0
        while (not Spell[604].active or (Spell[604].timeleft and (Spell[604].timeleft * 60) <= 5))
              and attempts < max_attempts do
            Spell[604]:cast()
            pause(0.1)
            attempts = attempts + 1
        end
    end

    local skin_patterns = {
        "You skinned",
        "You botched",
        "already been",
        "cannot skin",
        "must be a member",
        "can only skin",
        "You are unable to break through",
        "You break through the crust of the",
        "You crack open a portion",
        "Because your account is free",
        "it's not possible to get a worthwhile",
    }

    -- Skin em
    for _, obj in ipairs(objs) do
        local res = dothistimeout("skin #" .. obj.id .. " " .. skinner_hand, 2, skin_patterns)
        if res and string.find(res, "You cannot skin") then
            table.insert(data.settings.unskinnable, obj.name)
            Util().save_profile(data)
        elseif res and (string.find(res, "You break through the crust") or
                        string.find(res, "You crack open a portion")) then
            local lh2 = GameObj.left_hand()
            fput("stow gem #" .. lh2.id)
        end
    end

    waitrt()

    if dont_stow then return end

    local bag
    if skin_type == "blunt" then
        bag = ReadyList.ready_list.skin_sheath_blunt or StowList.stow_list.default
    else
        bag = ReadyList.ready_list.skin_sheath or StowList.stow_list.default
    end

    Inventory().store_item(bag, skinner, true, data)

    if Util().in_hand(skinner) then
        Inventory().store_item(StowList.stow_list.default, skinner, nil, data)
    end
end

-- ---------------------------------------------------------------------------
-- 14. skin (lines 5061-5084)
-- Main skin method: determine weapon, dispatch to skin_obj_types.
-- ---------------------------------------------------------------------------

--- Skin dead creatures. Determines weapon type and dispatches.
-- @param objs table|nil list of dead creatures (defaults to GameObj.dead())
-- @param data table ELoot data state
function M.skin(objs, data)
    objs = objs or (GameObj.dead() or {})

    -- Filter out unskinnable creatures
    local filtered = {}
    for _, obj in ipairs(objs) do
        local skip = false

        -- Unskinnable (unless occasional skinner)
        if contains_name(data.settings.unskinnable, obj.name) and not M.occassional_skinner(obj, data) then
            skip = true
        end

        -- Bandits
        if obj.type and string.find(obj.type, "bandit") then skip = true end

        -- Ethereal/ghostly/etc
        if obj.name and (string.find(obj.name, "ethereal") or string.find(obj.name, "ghostly") or
           string.find(obj.name, "unwordly") or string.find(obj.name, "Grimswarm") or
           string.find(obj.name, "child")) then
            skip = true
        end

        -- Skin exclude list
        if data.settings.skin_exclude and #data.settings.skin_exclude > 0 and
           obj.name and name_matches_any(obj.name, data.settings.skin_exclude) then
            skip = true
        end

        -- Critter exclude list
        if data.settings.critter_exclude and #data.settings.critter_exclude > 0 and
           obj.name and name_matches_any(obj.name, data.settings.critter_exclude) then
            skip = true
        end

        if not skip then
            table.insert(filtered, obj)
        end
    end

    if #filtered == 0 then return end

    -- Split by blunt requirement
    local blunt_names = { "krynch", "stone mastiff", "krag dweller", "cavern urchin" }
    local blunts = {}
    local normals = {}
    for _, obj in ipairs(filtered) do
        local is_blunt = false
        for _, bn in ipairs(blunt_names) do
            if obj.name and string.find(obj.name:lower(), bn:lower()) then
                is_blunt = true
                break
            end
        end
        if is_blunt then
            table.insert(blunts, obj)
        else
            table.insert(normals, obj)
        end
    end

    M.skin_obj_types(normals, "normal", data)
    M.skin_obj_types(blunts, "blunt", data)

    -- Stand up if kneeling
    local new_stance = Char.percent_stance
    if not standing() then
        local targets = GameObj.targets and GameObj.targets() or {}
        if #targets == 0 then
            Util().change_stance(0, data)
        end
        for _ = 1, 10 do
            if standing() then break end
            dothistimeout("stand", 3, { "You stand", "You quickly roll", "You are already standing" })
        end
        if Char.percent_stance ~= new_stance then
            Util().change_stance(new_stance, data)
        end
    end
end

return M
