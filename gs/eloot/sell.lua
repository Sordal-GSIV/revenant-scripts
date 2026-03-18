--- ELoot sell module
-- Ported from eloot.lic ELoot::Sell submodule (lines 5090-6692).
-- Handles selling loot at gemshops, pawnshops, furriers, consignment,
-- chronomage (gold rings), and collectible shops.
--
-- Usage:
--   local Sell = require("gs.eloot.sell")
--   Sell.sell(data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires to avoid circular dependencies
-- ---------------------------------------------------------------------------

local function Util()      return require("gs.eloot.util") end
local function Inventory() return require("gs.eloot.inventory") end
local function Loot()      return require("gs.eloot.loot") end
local function Pool()      return require("gs.eloot.pool") end

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

local function contains_id(tbl, id)
    if not tbl or not id then return false end
    for _, v in ipairs(tbl) do
        if v == id then return true end
    end
    return false
end

local function name_matches_any(name, list)
    if not name or not list or #list == 0 then return false end
    for _, pat in ipairs(list) do
        if string.find(name, pat) then return true end
    end
    return false
end

--- Global sell-ignore list (tracks IDs already processed this run).
_G.sell_ignore = _G.sell_ignore or {}

-- ---------------------------------------------------------------------------
-- 1. appraise (lines 5090-5122)
-- Appraise an item at a shop.
-- ---------------------------------------------------------------------------

--- Appraise an item and sell or stow based on limits.
-- @param item table GameObj item
-- @param location string shop type (e.g. "Gemshop", "Pawnshop")
-- @param data table ELoot data state
function M.appraise(item, location, data)
    -- Don't appraise jewelry at pawnshop
    if item.type and string.find(item.type, "jewelry") and location == "pawnshop" then
        return
    end

    local amount = 0
    local raw = nil

    local limit
    if location and string.find(location:lower(), "gemshop") then
        limit = data.settings.sell_appraise_gemshop
    else
        limit = data.settings.sell_appraise_pawnshop
    end

    local lines = Util().get_command("appraise #" .. item.id,
        { "^You ask .*to appraise" }, nil, data)

    for _, l in ipairs(lines) do
        local num = l:match("([%d,]+) silver")
            or l:match("([%d,]+) for it if you want to sell")
            or l:match("([%d,]+) for this if you'd like")
        if num then
            raw = num
            amount = tonumber(num:gsub(",", "")) or 0
            break
        end
    end

    local too_valuable = any_match(lines, "not buying anything this valuable today")

    if amount > (tonumber(limit) or 0) or too_valuable then
        local message
        if amount > (tonumber(limit) or 0) then
            message = " The " .. tostring(item) .. " appraises for " .. tostring(raw) .. ". That's above your settings."
        else
            message = " The " .. tostring(item) .. " appraises as too valuable to sell."
        end
        Util().msg({ type = "info", text = message }, data)

        -- Reset the appraisal container if the StowList got updated
        Util().ensure_items({ key = "appraisal_container", list = StowList.stow_list }, data)

        if not StowList.stow_list.appraisal_container or tostring(StowList.stow_list.appraisal_container) == "" then
            Inventory().single_drag(item, nil, data)
        else
            Inventory().store_item(StowList.stow_list.appraisal_container, item, nil, data)
        end
    elseif amount > 0 and amount <= (tonumber(limit) or 0) then
        M.sell_item(item, location, data)
    else
        Inventory().single_drag(item, nil, data)
    end
end

-- ---------------------------------------------------------------------------
-- 2. box_in_hand (lines 5124-5150)
-- Handle box in hand at start.
-- ---------------------------------------------------------------------------

--- Handle a box already in hand when sell starts.
-- @param deposit boolean whether depositing boxes to pool
-- @param data table ELoot data state
function M.box_in_hand(deposit, data)
    if deposit == nil then deposit = true end

    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if not ((rh.type == "box") or (lh.type == "box")) then return end

    -- Check for reliquary
    if (rh.noun == "reliquary") or (lh.noun == "reliquary") then
        Util().msg({ text = " Looks like you have a reliquary", space = true }, data)
        error("eloot: reliquary in hand")
    end

    -- Try locksmith pool
    while true do
        rh = GameObj.right_hand()
        lh = GameObj.left_hand()
        local item
        if rh.type == "box" then item = rh
        elseif lh.type == "box" then item = lh
        end

        if not item or not data.settings.sell_locksmith_pool then break end

        Pool().locksmith_pool({ item }, deposit, data)

        -- Check if still the same item. If it is then pool is full
        rh = GameObj.right_hand()
        lh = GameObj.left_hand()
        local still_box
        if rh.type == "box" then still_box = rh
        elseif lh.type == "box" then still_box = lh
        end
        if still_box and still_box.id == item.id then break end
    end

    -- Try town locksmith
    rh = GameObj.right_hand()
    lh = GameObj.left_hand()
    local item
    if rh.type == "box" then item = rh
    elseif lh.type == "box" then item = lh
    end
    if item and data.settings.sell_locksmith then
        M.locksmith({ item }, data)
    end

    -- Still have a box?
    rh = GameObj.right_hand()
    lh = GameObj.left_hand()
    if (rh.type == "box") or (lh.type == "box") then
        Util().msg({ text = " Not able to process the box in your hand. Exiting...", space = true }, data)
        error("eloot: unable to process box in hand")
    end
end

-- ---------------------------------------------------------------------------
-- 3. breakdown (lines 5152-5228)
-- Show silver breakdown report.
-- ---------------------------------------------------------------------------

--- Display the silver breakdown report.
-- @param data table ELoot data state
function M.breakdown(data)
    if (not data.silver_breakdown or next(data.silver_breakdown) == nil) and
       (not data.hoard_deposit or #(data.hoard_deposit or {}) == 0) then
        return
    end

    local lines_out = {}
    local total_silver = 0

    if data.silver_breakdown and next(data.silver_breakdown) ~= nil then
        local idx = 0
        local size = 0
        for _ in pairs(data.silver_breakdown) do size = size + 1 end

        for location, amount in pairs(data.silver_breakdown) do
            idx = idx + 1

            if not string.find(location, "Pool Dropoff") and
               not string.find(location, "Pool Depth") and
               not string.find(location, "Pool Open") and
               not string.find(location, "Town Dropoff") and
               not string.find(location, "Town Depth") and
               not string.find(location, "Town Open") then
                total_silver = total_silver + (tonumber(amount) or 0)
            end

            table.insert(lines_out, string.format("  %-25s %12s", location, "   " .. Util().format_number(amount)))

            if (string.find(location, "Pool Depth") or string.find(location, "Town Open")) and idx < size then
                table.insert(lines_out, "  " .. string.rep("-", 40))
            end
        end

        table.insert(lines_out, "  " .. string.rep("-", 40))
        table.insert(lines_out, string.format("  %-25s %12s", "Total", Util().format_number(total_silver)))
    end

    -- Gems hoarded
    if data.hoard_deposit and #data.hoard_deposit > 0 then
        local all_gems = {}
        for _, item in ipairs(data.hoard_deposit) do
            if item.type == "gem" then table.insert(all_gems, item) end
        end

        if #all_gems > 0 then
            table.insert(lines_out, "  " .. string.rep("-", 40))
            table.insert(lines_out, "          Gems Hoarded")
            table.insert(lines_out, "  " .. string.rep("-", 40))

            local seen = {}
            for _, obj in ipairs(all_gems) do
                if not seen[obj.item] then
                    seen[obj.item] = true
                    local count = 0
                    for _, it in ipairs(data.hoard_deposit) do
                        if it.item == obj.item then count = count + 1 end
                    end
                    table.insert(lines_out, string.format("  %-25s %12s",
                        Util().capitalize_words(obj.item), "   " .. tostring(count)))
                end
            end
        end

        local all_reagents = {}
        for _, item in ipairs(data.hoard_deposit) do
            if item.type == "reagent" then table.insert(all_reagents, item) end
        end

        if #all_reagents > 0 then
            table.insert(lines_out, "  " .. string.rep("-", 40))
            table.insert(lines_out, "        Reagents Hoarded")
            table.insert(lines_out, "  " .. string.rep("-", 40))

            local seen = {}
            for _, obj in ipairs(all_reagents) do
                if not seen[obj.item] then
                    seen[obj.item] = true
                    local count = 0
                    for _, it in ipairs(data.hoard_deposit) do
                        if it.item == obj.item then count = count + 1 end
                    end
                    table.insert(lines_out, string.format("  %-25s %12s",
                        Util().capitalize_words(obj.item), "   " .. tostring(count)))
                end
            end
        end
    end

    Util().wait_rt()
    respond("")
    respond("========================================")
    respond("         Eloot Breakdown")
    respond("========================================")
    for _, l in ipairs(lines_out) do
        respond(l)
    end
    respond("========================================")
    respond("")
    Util().wait_rt()
end

-- ---------------------------------------------------------------------------
-- 4. break_rocks (lines 5230-5245)
-- Break rocks for gems.
-- ---------------------------------------------------------------------------

--- Break rock-type items into gems.
-- @param data table ELoot data state
function M.break_rocks(data)
    local rock_sacks = Util().set_selling_containers(nil, data)

    for _, sack in ipairs(rock_sacks) do
        if sack then
            local contents = sack.contents or {}
            for _, item in ipairs(contents) do
                if item.type and string.find(item.type, "breakable") then
                    Inventory().drag(item, nil, data)
                    Util().get_res("break #" .. item.id, { "You squeeze the chunk of rock" }, data)
                    Inventory().free_hands({ both = true }, data)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 5. check_bounty_furrier (lines 5247-5345)
-- Check for furrier bounty items.
-- ---------------------------------------------------------------------------

--- Check if we have skins matching the current bounty and sell them at the furrier.
-- @param data table ELoot data state
function M.check_bounty_furrier(data)
    Util().msg({ type = "debug" }, data)

    if not contains(data.settings.sell_loot_types, "skin") then return end
    if not Bounty or not Bounty.task then return end
    if not (Bounty.task.skin and Bounty.task:skin()) then return end
    if Bounty.task.type and tostring(Bounty.task.type):find("assignment$") then return end

    local need_furrier = false
    local skin = Bounty.task:skin()
    -- Extract bundled skin pattern (last two words)
    local bundled_adj, bundled_noun = skin:match("(%w+)%s+(%w+)%s*$")
    local bundled_skin = bundled_adj and (bundled_adj .. " " .. bundled_noun) or nil

    local skin_sacks = Util().set_selling_containers({ type = "skin" }, data)

    for _, sack in ipairs(skin_sacks) do
        if sack and sack.contents then
            for _, obj in ipairs(sack.contents) do
                if obj.name and (string.find(obj.name, skin) or
                   (bundled_skin and string.find(obj.name, bundled_skin))) then
                    need_furrier = true
                    break
                end
            end
            if need_furrier then break end
        end
    end

    if not need_furrier then return end

    -- If we are sitting in FWI bring us back
    Util().fwi_return(data)

    -- Are we in the correct town?
    local location = Region and Region.furrier and Region.furrier()
    if not location then return end
    Util().go2(location, data)

    local start_silvers = Util().silver_check(data)

    Util().msg({ type = "debug", text = "skin_sacks: " .. tostring(#skin_sacks) }, data)
    for _, sack in ipairs(skin_sacks) do
        if not sack then goto next_sack end
        local has_skin = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and (string.find(obj.name, skin) or
               (bundled_skin and string.find(obj.name, bundled_skin))) then
                has_skin = true
                break
            end
        end
        if not has_skin then goto next_sack end

        local bulk_sell = true
        -- Check for bundles
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and string.find(obj.name, "bundle of") then
                bulk_sell = false
                break
            end
        end
        -- Check sell_exclude
        if #(data.settings.sell_exclude or {}) > 0 then
            for _, obj in ipairs(sack.contents or {}) do
                if obj.name and name_matches_any(obj.name, data.settings.sell_exclude) and
                   obj.sellable and string.find(obj.sellable, "furrier") then
                    bulk_sell = false
                    break
                end
            end
        end
        -- Check for non-bounty skins
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and not string.find(obj.name, skin) and
               obj.sellable and string.find(obj.sellable, "furrier") then
                bulk_sell = false
                break
            end
        end

        if bulk_sell then
            Util().msg({ type = "debug", text = "bulk_sell using sack: " .. tostring(sack) }, data)
            if not (checkright() == sack.noun or checkleft() == sack.noun) then
                Inventory().drag(sack, nil, data)
            end

            dothistimeout("sell #" .. sack.id, 3, { "inspects the contents carefully" })
            Inventory().wear(sack, data)

            local bulk_note = tonumber(Util().read_note(data)) or 0
            if bulk_note > 0 then
                data.silver_breakdown["Furrier"] = (data.silver_breakdown["Furrier"] or 0) + bulk_note
                if data.settings.sell_fwi then
                    Util().deposit_note(data)
                end
            end

            pause(0.5)
        else
            for _, item in ipairs(sack.contents or {}) do
                if contains_id(_G.sell_ignore, item.id) then goto next_item end
                if not (item.sellable and string.find(item.sellable, "furrier")) then goto next_item end
                if #(data.settings.sell_exclude or {}) > 0 and item.name and
                   name_matches_any(item.name, data.settings.sell_exclude) then
                    goto next_item
                end
                if not (item.name and (string.find(item.name, skin) or
                       (bundled_skin and string.find(item.name, bundled_skin)))) then
                    goto next_item
                end

                table.insert(_G.sell_ignore, item.id)
                Inventory().drag(item, nil, data)

                if item.name and string.find(item.name, "bundle") then
                    while Util().in_hand(item) do
                        local result = dothistimeout("bundle remove", 5, { "You remove", "Those were the last two" })
                        if result and string.find(result, "Those were the last two") then
                            M.sell_item(GameObj.right_hand(), "Furrier", data)
                            M.sell_item(GameObj.left_hand(), "Furrier", data)
                        else
                            local rh = GameObj.right_hand()
                            local s = (rh.id ~= item.id) and rh or GameObj.left_hand()
                            M.sell_item(s, "Furrier", data)
                        end
                    end
                else
                    M.sell_item(item, "Furrier", data)
                end

                ::next_item::
            end
        end

        Inventory().free_hands({ both = true }, data)
        Util().msg({ type = "debug", text = "bottom of each using sack" }, data)

        ::next_sack::
    end

    data.silver_breakdown["Furrier"] = (data.silver_breakdown["Furrier"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 6. check_bounty_gems (lines 5347-5417)
-- Check for gem bounty items.
-- ---------------------------------------------------------------------------

--- Check if we have gems matching the current bounty and sell them at the gemshop.
-- @param data table ELoot data state
function M.check_bounty_gems(data)
    Util().msg({ type = "debug", text = "bounty: " .. tostring(checkbounty and checkbounty() or "") }, data)

    if not contains(data.settings.sell_loot_types, "gem") then return end
    if not Bounty or not Bounty.task then return end
    if not (Bounty.task.gem and Bounty.task:gem()) then return end
    if Bounty.task.type and tostring(Bounty.task.type):find("assignment$") then return end

    local need_gemshop = false
    local gem = Bounty.requirements and Bounty.requirements.gem or nil
    if not gem then return end

    local gem_sacks = Util().set_selling_containers({ type = "gem" }, data)

    for _, sack in ipairs(gem_sacks) do
        if sack and sack.contents then
            for _, obj in ipairs(sack.contents) do
                if obj.name and string.find(obj.name, gem) then
                    need_gemshop = true
                    break
                end
            end
            if need_gemshop then break end
        end
    end

    if not need_gemshop then return end

    Util().fwi_return(data)

    local location = Region and Region.gemshop and Region.gemshop()
    if not location then return end
    Util().go2(location, data)

    local start_silvers = Util().silver_check(data)

    Inventory().free_hands({ both = true }, data)

    for _, sack in ipairs(gem_sacks) do
        if not sack then goto next_sack end
        local has_gem = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and string.find(obj.name:lower(), gem:lower()) then
                has_gem = true
                break
            end
        end
        if not has_gem then goto next_sack end

        local bulk_sell = true
        -- Check for non-bounty gems
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and not string.find(obj.name, gem) and
               obj.type and string.find(obj.type, "gem") then
                bulk_sell = false
                break
            end
        end
        -- Check sell_exclude
        if #(data.settings.sell_exclude or {}) > 0 then
            for _, obj in ipairs(sack.contents or {}) do
                if obj.name and name_matches_any(obj.name, data.settings.sell_exclude) and
                   obj.sellable and string.find(obj.sellable, "gemshop") then
                    bulk_sell = false
                    break
                end
            end
        end

        if bulk_sell then
            if not (checkright() == sack.noun or checkleft() == sack.noun) then
                Inventory().drag(sack, nil, data)
            end
            dothistimeout("sell #" .. sack.id, 3, { "inspects the contents carefully" })
            Inventory().wear(sack, data)
            pause(0.5)
            local bulk_note = tonumber(Util().read_note(data)) or 0
            if bulk_note > 0 then
                data.silver_breakdown["Gemshop"] = (data.silver_breakdown["Gemshop"] or 0) + bulk_note
                if data.settings.sell_fwi then
                    Util().deposit_note(data)
                end
            end
            Inventory().free_hands({ both = true }, data)
        else
            for _, item in ipairs(sack.contents or {}) do
                if not (item.name and string.find(item.name, gem)) then goto next_item end
                Inventory().drag(item, nil, data)
                M.sell_item(item, "Gemshop", data)
                Inventory().free_hands({ both = true }, data)
                ::next_item::
            end
        end

        ::next_sack::
    end

    data.silver_breakdown["Gemshop"] = (data.silver_breakdown["Gemshop"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 7. check_bounty (lines 5419-5422)
-- Main bounty check dispatcher.
-- ---------------------------------------------------------------------------

--- Run both bounty checks (furrier and gems).
-- @param data table ELoot data state
function M.check_bounty(data)
    M.check_bounty_furrier(data)
    M.check_bounty_gems(data)
end

-- ---------------------------------------------------------------------------
-- 8. check_items (lines 5424-5468)
-- Check for sellable items in containers.
-- ---------------------------------------------------------------------------

--- Scan inventory and determine which shop locations are needed.
-- @param opts table|nil {specific=table of types, items=table of GameObj}
-- @param data table ELoot data state
-- @return table list of shop location strings
function M.check_items(opts, data)
    opts = opts or {}
    local selling = {}
    data.gemshop_first = false

    local all_contents = opts.items or M.check_inventory(data)

    for _, thing in ipairs(all_contents) do
        if contains_id(_G.sell_ignore, thing.id) then goto next_thing end

        -- Skip ready-list items
        if ReadyList and ReadyList.ready_list then
            local skip = false
            for _, v in pairs(ReadyList.ready_list) do
                if type(v) == "table" and v.id == thing.id then skip = true; break end
            end
            if skip then goto next_thing end
        end

        -- Sell exclude
        if #(data.settings.sell_exclude or {}) > 0 and thing.name and
           name_matches_any(thing.name, data.settings.sell_exclude) then
            goto next_thing
        end

        -- Skip bound items and shimmering orbs
        if thing.name and (string.find(thing.name, "%bbound%b") or
           string.find(thing.name, "^shimmering %w+ orb$")) then
            goto next_thing
        end

        -- Skip already-selling types
        if contains(selling, thing.type) and thing.type ~= nil then goto next_thing end

        -- Specific type filter
        if opts.specific then
            if not contains(opts.specific, thing.type) then goto next_thing end
        end

        -- Clothing sellable at both pawnshop and gemshop
        if thing.type and string.find(thing.type, "clothing") and
           thing.sellable and string.find(thing.sellable, "pawnshop") and
           string.find(thing.sellable, "gemshop") then
            data.gemshop_first = true
        end

        -- Alchemy mode exclusions
        if data.alchemy_mode then
            if Vars and Vars.needed_reagents and #Vars.needed_reagents > 0 and
               thing.name and name_matches_any(thing.name, Vars.needed_reagents) then
                goto next_thing
            end
            if thing.noun and string.find(thing.noun, "^jar$|^beaker$|^bottle$") and
               not thing.after_name then
                goto next_thing
            end
        end

        -- Determine selling location
        if thing.name and data.regex_gold_rings and
           string.find(thing.name, data.regex_gold_rings) and data.settings.sell_gold_rings then
            if not contains(selling, "chronomage") then table.insert(selling, "chronomage") end
        elseif thing.type and string.find(thing.type, "scarab") and
               contains(data.settings.sell_loot_types, "scarab") then
            if not contains(selling, "gemshop") then table.insert(selling, "gemshop") end
        elseif thing.type and thing.type == "gem" and
               contains(data.settings.sell_loot_types, "gem") and
               thing.noun and (string.find(thing.noun, "thorn") or string.find(thing.noun, "berry")) then
            if not contains(selling, "gemshop") then table.insert(selling, "gemshop") end
        elseif thing.type and thing.type == "collectible" and data.settings.sell_collectibles then
            if not contains(selling, "collectibles") then table.insert(selling, "collectibles") end
        elseif contains(data.settings.sell_loot_types, "box") and thing.type == "box" then
            if not contains(selling, "pawnshop") then table.insert(selling, "pawnshop") end
        elseif thing.sellable and thing.type then
            -- Check if any of the item's types match our sell_loot_types
            local type_match = false
            for t in thing.type:gmatch("[^,]+") do
                t = t:match("^%s*(.-)%s*$")  -- trim
                for _, slt in ipairs(data.settings.sell_loot_types) do
                    if t == slt then type_match = true; break end
                end
                if type_match then break end
            end
            if type_match then
                for loc in thing.sellable:gmatch("[^,]+") do
                    loc = loc:match("^%s*(.-)%s*$")
                    if not contains(selling, loc) then
                        table.insert(selling, loc)
                    end
                end
            end
        end

        ::next_thing::
    end

    Util().msg({ type = "debug", text = table.concat(selling, ", ") }, data)
    return selling
end

-- ---------------------------------------------------------------------------
-- 9. check_inventory (lines 5470-5494)
-- Verify inventory for selling.
-- ---------------------------------------------------------------------------

--- Gather all sellable items from stow containers and disk.
-- @param data table ELoot data state
-- @return table list of GameObj items
function M.check_inventory(data)
    Util().msg({ type = "debug" }, data)

    local all_contents = {}

    for item_key, container in pairs(StowList.stow_list) do
        if container then
            local match = false
            for _, sell in ipairs(data.settings.sell_container or {}) do
                if string.find(tostring(item_key), sell, 1, true) then
                    match = true
                    break
                end
            end
            if match then
                Inventory().open_single_container(container, data)
                for _, c in ipairs(container.contents or {}) do
                    table.insert(all_contents, c)
                end
            end
        end
    end

    if data.settings.use_disk then
        Util().wait_for_disk(data)
        if data.disk then
            Inventory().open_single_container(data.disk, data)
            for _, c in ipairs(data.disk.contents or {}) do
                table.insert(all_contents, c)
            end
        end
    end

    -- Remove items in the sell_ignore list
    local filtered = {}
    for _, thing in ipairs(all_contents) do
        if not contains_id(_G.sell_ignore, thing.id) then
            table.insert(filtered, thing)
        end
    end

    return filtered
end

-- ---------------------------------------------------------------------------
-- 10. collectibles (lines 5496-5540)
-- Sell collectible items.
-- ---------------------------------------------------------------------------

--- Sell collectible items at the collectibles shop.
-- @param data table ELoot data state
function M.collectibles(data)
    if not data.settings.sell_collectibles then return end

    local places = {}
    local c1 = Room.current and Room.current().find_nearest_by_tag and Room.current().find_nearest_by_tag("collectible")
    local c2 = Room.current and Room.current().find_nearest_by_tag and Room.current().find_nearest_by_tag("collectibles")
    if c1 then table.insert(places, c1) end
    if c2 then table.insert(places, c2) end

    local go_place = Room.current().find_nearest(places)
    Util().go2(go_place, data)

    Inventory().free_hands({ both = true }, data)

    local collectible_sacks = Util().set_selling_containers({ type = "collectible" }, data)

    if Util().time_between("autoclosers", 30, data) then
        Inventory().check_auto_closer(data)
    end

    for _, sack in ipairs(collectible_sacks) do
        if not sack then goto next_sack end
        local has_collectible = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.type == "collectible" then has_collectible = true; break end
        end
        if not has_collectible then goto next_sack end

        for _, thing in ipairs(sack.contents or {}) do
            if contains_id(_G.sell_ignore, thing.id) then goto next_item end
            if thing.type ~= "collectible" then goto next_item end
            -- Skip ready-list items
            if ReadyList and ReadyList.ready_list then
                local skip = false
                for _, v in pairs(ReadyList.ready_list) do
                    if type(v) == "table" and v.id == thing.id then skip = true; break end
                end
                if skip then goto next_item end
            end
            if #(data.settings.sell_exclude or {}) > 0 and thing.name and
               name_matches_any(thing.name, data.settings.sell_exclude) then
                goto next_item
            end
            if thing.name and string.find(thing.name, "bound") then goto next_item end

            table.insert(_G.sell_ignore, thing.id)
            Inventory().drag(thing, nil, data)
            dothistimeout("deposit #" .. thing.id, 3, { "You hand your" })

            for _ = 1, 20 do
                if not Util().in_hand(thing) then break end
                pause(0.1)
            end

            Inventory().free_hands({ both = true }, data)

            ::next_item::
        end

        ::next_sack::
    end
end

-- ---------------------------------------------------------------------------
-- 11. consignment (lines 5542-5579)
-- Consignment shop selling.
-- ---------------------------------------------------------------------------

--- Sell reagent items at the consignment shop.
-- @param data table ELoot data state
function M.consignment(data)
    Util().go2("consignment", data)
    local start_silvers = Util().silver_check(data)
    Inventory().free_hands({ both = true }, data)

    local consignment_sacks = Util().set_selling_containers({ type = "reagent" }, data)

    if Util().time_between("autoclosers", 30, data) then
        Inventory().check_auto_closer(data)
    end

    for _, sack in ipairs(consignment_sacks) do
        if not sack then goto next_sack end
        local has_consignment = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.sellable and string.find(obj.sellable, "consignment") then
                has_consignment = true
                break
            end
        end
        if not has_consignment then goto next_sack end

        for _, thing in ipairs(sack.contents or {}) do
            if contains_id(_G.sell_ignore, thing.id) then goto next_item end
            if not (thing.sellable and string.find(thing.sellable, "consignment")) then goto next_item end
            -- Type check
            if thing.type then
                local type_match = false
                for t in thing.type:gmatch("[^,]+") do
                    t = t:match("^%s*(.-)%s*$")
                    for _, slt in ipairs(data.settings.sell_loot_types) do
                        if t == slt then type_match = true; break end
                    end
                    if type_match then break end
                end
                if not type_match then goto next_item end
            end
            -- Skip ready-list items
            if ReadyList and ReadyList.ready_list then
                local skip = false
                for _, v in pairs(ReadyList.ready_list) do
                    if type(v) == "table" and v.id == thing.id then skip = true; break end
                end
                if skip then goto next_item end
            end
            if #(data.settings.sell_exclude or {}) > 0 and thing.name and
               name_matches_any(thing.name, data.settings.sell_exclude) then
                goto next_item
            end
            if thing.name and string.find(thing.name, "bound") then goto next_item end

            -- Alchemy mode check
            if data.alchemy_mode and Vars and Vars.needed_reagents and
               #Vars.needed_reagents > 0 and thing.name and
               name_matches_any(thing.name, Vars.needed_reagents) then
                goto next_item
            end

            table.insert(_G.sell_ignore, thing.id)
            Inventory().drag(thing, nil, data)
            M.sell_item(thing, "Consignment", data)
            Inventory().free_hands({ both = true }, data)

            ::next_item::
        end

        ::next_sack::
    end

    data.silver_breakdown["Consignment"] = (data.silver_breakdown["Consignment"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 12. custom_list (lines 5581-5622)
-- Custom sell list command.
-- ---------------------------------------------------------------------------

--- Sell specific items by name pattern.
-- @param items string comma/pipe-separated list of item names
-- @param data table ELoot data state
function M.custom_list(items, data)
    -- Put items into an array and clean up
    local items_array = {}
    for item in items:gsub("/", ""):gmatch("[^,|]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(items_array, trimmed)
        end
    end

    -- Get the inventory
    local all_contents = M.check_inventory(data)

    -- Find the items
    local items_to_sell = {}
    for _, item in ipairs(all_contents) do
        for _, pat in ipairs(items_array) do
            if item.name and string.find(item.name, pat) then
                table.insert(items_to_sell, item)
                break
            end
        end
    end

    -- Check where to go for selling them
    local locations = M.check_items({ items = items_to_sell }, data)
    if #locations == 0 then return end

    Inventory().clear_hands(data)

    -- Go to each location and sell
    for _, place in ipairs(locations) do
        Util().go2(place, data)
        Util().wait_rt()

        for _, item in ipairs(items_to_sell) do
            Inventory().drag(item, nil, data)

            local appraise_types = data.settings.sell_appraise_types or {}
            if #appraise_types > 0 and item.type and name_matches_any(item.type, appraise_types) then
                M.appraise(item, place:sub(1, 1):upper() .. place:sub(2), data)
            else
                M.sell_item(item, place:sub(1, 1):upper() .. place:sub(2), data)
            end

            Inventory().free_hands({ both = true }, data)
        end
    end

    Util().silver_deposit(true, data)
    Inventory().return_hands(data)
end

-- ---------------------------------------------------------------------------
-- 13. custom_sellable (lines 5624-5666)
-- Custom sellable types.
-- ---------------------------------------------------------------------------

--- Sell items matching specific GameObj sellable categories.
-- @param sellable string comma/pipe-separated list of sellable categories
-- @param data table ELoot data state
function M.custom_sellable(sellable, data)
    Util().msg({ type = "debug", text = "sellable: " .. sellable }, data)
    local sellable_types = {}

    local sellable_array = {}
    for item in sellable:gsub("/", ""):gmatch("[^,|]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(sellable_array, trimmed)
        end
    end

    for _, item in ipairs(sellable_array) do
        local valid = (GameObj.sellable_data and GameObj.sellable_data()[item]) or
                      item == "collectible" or item == "chronomage"
        if valid then
            table.insert(sellable_types, item)
        else
            Util().msg({ type = "yellow", text = "  " .. Util().capitalize_words(item) .. " is not a valid sellable category." }, data)
            error("eloot: invalid sellable category: " .. item)
        end
    end

    if #sellable_types == 0 then return end

    local locations = M.check_items(nil, data)

    Inventory().clear_hands(data)

    if contains(sellable_types, "gemshop") then M.check_bounty_gems(data) end
    if contains(sellable_types, "furrier") then M.check_bounty_furrier(data) end

    if contains(sellable_types, "gemshop") or contains(sellable_types, "furrier") then
        locations = M.check_items(nil, data)
    end

    -- Intersection of locations and sellable_types
    local remaining_sellable = {}
    for _, loc in ipairs(locations) do
        if contains(sellable_types, loc) then
            table.insert(remaining_sellable, loc)
        end
    end

    if #remaining_sellable == 0 then return end

    M.go_sell(remaining_sellable, data)

    Util().silver_deposit(true, data)
    Inventory().return_hands(data)
end

-- ---------------------------------------------------------------------------
-- 14. custom_type (lines 5668-5733)
-- Custom type selling.
-- ---------------------------------------------------------------------------

--- Sell items matching specific GameObj types.
-- @param types string comma/pipe-separated list of types
-- @param data table ELoot data state
function M.custom_type(types, data)
    Util().msg({ type = "debug", text = "types: " .. types }, data)
    local sell_types = {}
    local recheck = false

    local types_array = {}
    for t in types:gsub("/", ""):gmatch("[^,|]+") do
        local trimmed = t:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(types_array, trimmed)
        end
    end

    for _, t in ipairs(types_array) do
        local valid = GameObj.type_data and GameObj.type_data()[t]
        if valid then
            table.insert(sell_types, t)
        else
            Util().msg({ type = "yellow", text = "  " .. Util().capitalize_words(t) .. " is not a valid GameObj type." }, data)
            error("eloot: invalid GameObj type: " .. t)
        end
    end

    if #sell_types == 0 then return end

    Inventory().clear_hands(data)

    -- Process boxes first
    if contains(sell_types, "box") then M.process_boxes(data) end

    local locations = M.check_items({ specific = sell_types }, data)
    if #locations == 0 then return end

    M.sell_buffs(data)

    if contains(sell_types, "gem") and contains(locations, "gemshop") then
        M.check_bounty_gems(data)
        recheck = true
    end

    if contains(sell_types, "skin") and contains(locations, "furrier") then
        M.check_bounty_furrier(data)
        recheck = true
    end

    if recheck then
        locations = M.check_items({ specific = sell_types }, data)
    end
    if #locations == 0 then return end

    if contains(locations, "chronomage") then M.gold_rings(data) end
    if contains(locations, "furrier") then M.furrier(data) end
    if contains(locations, "gemshop") then M.gemshop(sell_types, data) end
    if contains(locations, "consignment") then M.consignment(data) end
    if contains(locations, "pawnshop") then M.pawnshop(sell_types, data) end
    if contains(locations, "collectibles") then M.collectibles(data) end

    Util().silver_deposit(true, data)
    Inventory().return_hands(data)
end

-- ---------------------------------------------------------------------------
-- 15. dump_herbs_junk (lines 5735-5775)
-- Dump herbs and junk items.
-- ---------------------------------------------------------------------------

--- Dump herb, junk, and food items into the trash.
-- @param data table ELoot data state
function M.dump_herbs_junk(data)
    local dump_stuff = {}
    for _, t in ipairs({ "herb", "junk", "food" }) do
        if contains(data.settings.sell_loot_types, t) then
            table.insert(dump_stuff, t)
        end
    end

    local alchemy_regex = "^some ground|^flask of pure water|^some powdered|^some mashed|^handful of sea salt|^spirit shard|^tincture of"

    local sacks = Util().set_selling_containers(nil, data)
    local dump_items = {}
    for _, sack in ipairs(sacks) do
        for _, item in ipairs(sack.contents or {}) do
            local should_dump = false
            for _, dt in ipairs(dump_stuff) do
                if item.type and string.find(item.type, dt) then
                    should_dump = true
                    break
                end
            end
            if not should_dump and data.alchemy_mode and item.name and
               string.find(item.name, alchemy_regex) then
                should_dump = true
            end
            if should_dump and data.alchemy_mode and Vars and Vars.needed_reagents then
                for _, r in ipairs(Vars.needed_reagents) do
                    if item.name and string.find(item.name, r) then
                        should_dump = false
                        break
                    end
                end
            end
            if should_dump then table.insert(dump_items, item) end
        end
    end

    if #dump_items == 0 then return end

    local trash = Util().find_trash(data)
    if not trash then
        Util().go2("locksmith pool", data)
        trash = Util().find_trash(data)
    end

    local toss_cmd = trash and "trash" or "drop"

    for _, item in ipairs(dump_items) do
        Inventory().drag(item, nil, data)
        fput(toss_cmd .. " #" .. item.id)

        for _ = 1, 10 do
            if not Util().in_hand(item) then break end
            pause(0.1)
        end

        if Util().in_hand(item) then
            Util().msg({ type = "info", text = " " .. (item.name or "?") .. " isn't trashed so maybe its special...keeping it." }, data)
            Inventory().single_drag(item, nil, data)
        end
    end

    Inventory().free_hands({ both = true }, data)
end

-- ---------------------------------------------------------------------------
-- 16. furrier (lines 5777-5871)
-- Sell at furrier shop.
-- ---------------------------------------------------------------------------

--- Sell skins at the furrier shop.
-- @param data table ELoot data state
function M.furrier(data)
    Util().go2("furrier", data)
    local start_silvers = Util().silver_check(data)

    Inventory().free_hands({ both = true }, data)

    local skin_sacks = Util().set_selling_containers({ type = "skin" }, data)

    if Util().time_between("autoclosers", 30, data) then
        Inventory().check_auto_closer(data)
    end

    Util().msg({ type = "debug", text = "skin_sacks: " .. tostring(#skin_sacks) }, data)
    for _, sack in ipairs(skin_sacks) do
        Util().msg({ type = "debug", text = " Beginning: " .. tostring(sack) }, data)
        if not sack then goto next_sack end
        if not (contains(data.settings.sell_loot_types, "skin") or
                contains(data.settings.sell_loot_types, "reagent")) then
            goto next_sack
        end

        local has_furrier = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.sellable and string.find(obj.sellable, "furrier") then
                has_furrier = true
                break
            end
        end
        if not has_furrier then goto next_sack end

        Util().msg({ type = "debug", text = "Contents after next, sack: " .. tostring(sack) }, data)

        local bulk_sell = true
        -- Check for bundles during skin bounty
        local bounty_text = checkbounty and checkbounty() or ""
        if string.find(bounty_text, "You have been tasked to retrieve") then
            for _, obj in ipairs(sack.contents or {}) do
                if obj.name and string.find(obj.name, "bundle") then
                    bulk_sell = false
                    break
                end
            end
        end
        if data.alchemy_mode then bulk_sell = false end
        if #(data.settings.sell_exclude or {}) > 0 then
            for _, obj in ipairs(sack.contents or {}) do
                if obj.name and name_matches_any(obj.name, data.settings.sell_exclude) and
                   obj.sellable and string.find(obj.sellable, "furrier") then
                    bulk_sell = false
                    break
                end
            end
        end

        if bulk_sell then
            Util().msg({ type = "debug", text = "bulk_sell using sack: " .. tostring(sack) }, data)
            if not (checkright() == sack.noun or checkleft() == sack.noun) then
                Inventory().drag(sack, nil, data)
            end

            Util().silver_check(data)
            dothistimeout("sell #" .. sack.id, 3, { "inspects the contents carefully" })
            Inventory().wear(sack, data)

            local bulk_note = tonumber(Util().read_note(data)) or 0
            if bulk_note > 0 then
                data.silver_breakdown["Furrier"] = (data.silver_breakdown["Furrier"] or 0) + bulk_note
            end
            pause(0.5)
        end

        Inventory().free_hands({ both = true }, data)

        for _, item in ipairs(sack.contents or {}) do
            if contains_id(_G.sell_ignore, item.id) then goto next_item end
            if not (item.sellable and string.find(item.sellable, "furrier")) then goto next_item end
            if #(data.settings.sell_exclude or {}) > 0 and item.name and
               name_matches_any(item.name, data.settings.sell_exclude) then
                goto next_item
            end

            if data.alchemy_mode and Vars and Vars.needed_reagents and
               #Vars.needed_reagents > 0 and item.name and
               name_matches_any(item.name, Vars.needed_reagents) then
                goto next_item
            end

            table.insert(_G.sell_ignore, item.id)
            Inventory().drag(item, nil, data)

            if item.name and string.find(item.name, "bundle") then
                local bundle = GameObj.right_hand().id and GameObj.right_hand() or GameObj.left_hand()

                while Util().in_hand(bundle) do
                    local result = dothistimeout("bundle remove", 5, { "You remove", "Those were the last two" })
                    if result and string.find(result, "Those were the last two") then
                        M.sell_item(GameObj.right_hand(), "Furrier", data)
                        M.sell_item(GameObj.left_hand(), "Furrier", data)
                    else
                        local rh = GameObj.right_hand()
                        local skin = (rh.id ~= bundle.id) and rh or GameObj.left_hand()
                        M.sell_item(skin, "Furrier", data)
                    end
                end
            else
                M.sell_item(item, "Furrier", data)
            end

            ::next_item::
        end

        Inventory().free_hands({ both = true }, data)
        Util().msg({ type = "debug", text = " bottom of each - sack" }, data)

        ::next_sack::
    end

    data.silver_breakdown["Furrier"] = (data.silver_breakdown["Furrier"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 17. gemshop (lines 5873-5950)
-- Sell at gemshop.
-- ---------------------------------------------------------------------------

--- Sell gems and gemshop-sellable items at the gemshop.
-- @param sell_type table|nil list of specific types to sell (nil = all)
-- @param data table ELoot data state
function M.gemshop(sell_type, data)
    Util().go2("gemshop", data)
    local start_silvers = Util().silver_check(data)

    Inventory().free_hands({ both = true }, data)

    local gem_sacks = Util().set_selling_containers({ type = "gem" }, data)

    if Util().time_between("autoclosers", 30, data) then
        Inventory().check_auto_closer(data)
    end

    for _, sack in ipairs(gem_sacks) do
        if not sack then goto next_sack end
        local has_gemshop = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.sellable and string.find(obj.sellable, "gemshop") then
                has_gemshop = true
                break
            end
        end
        if not has_gemshop then goto next_sack end

        -- Bulk sell: no exclusions, has gems, gem type enabled, not alchemy mode
        local can_bulk = true
        if #(data.settings.sell_exclude or {}) > 0 then
            for _, obj in ipairs(sack.contents or {}) do
                if obj.name and name_matches_any(obj.name, data.settings.sell_exclude) and
                   obj.type and string.find(obj.type, "gem") then
                    can_bulk = false
                    break
                end
            end
        end
        local has_gems = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.type and string.find(obj.type, "gem") then has_gems = true; break end
        end
        if not has_gems then can_bulk = false end
        if not contains(data.settings.sell_loot_types, "gem") then can_bulk = false end
        if data.alchemy_mode then can_bulk = false end

        if can_bulk then
            if sell_type == nil or contains(sell_type, "gem") then
                if not (checkright() == sack.noun or checkleft() == sack.noun) then
                    Inventory().drag(sack, nil, data)
                end

                dothistimeout("sell #" .. sack.id, 3, { "inspects the contents carefully" })
                Inventory().wear(sack, data)
                pause(0.5)

                local bulk_note = tonumber(Util().read_note(data)) or 0
                if bulk_note > 0 then
                    data.silver_breakdown["Gemshop"] = (data.silver_breakdown["Gemshop"] or 0) + bulk_note
                end

                Inventory().free_hands({ both = true }, data)
            end
        end

        -- Loop thru remaining contents and sell/appraise whatever is left
        for _, item in ipairs(sack.contents or {}) do
            if contains_id(_G.sell_ignore, item.id) then goto next_item end
            if not ((item.sellable and string.find(item.sellable, "gemshop")) or
                    (item.noun and (string.find(item.noun, "thorn") or string.find(item.noun, "berry"))) or
                    (item.type and string.find(item.type, "scarab"))) then
                goto next_item
            end
            -- Type check against sell_loot_types
            if item.type then
                local type_match = false
                for t in item.type:gmatch("[^,]+") do
                    t = t:match("^%s*(.-)%s*$")
                    for _, slt in ipairs(data.settings.sell_loot_types) do
                        if t == slt then type_match = true; break end
                    end
                    if type_match then break end
                end
                if not type_match then goto next_item end
            end
            if #(data.settings.sell_exclude or {}) > 0 and item.name and
               name_matches_any(item.name, data.settings.sell_exclude) then
                goto next_item
            end
            if data.settings.sell_gold_rings and item.name and data.regex_gold_rings and
               string.find(item.name, data.regex_gold_rings) then
                goto next_item
            end
            if item.name and (string.find(item.name, "%bbound%b") or
               string.find(item.name, "^shimmering %w+ orb$")) then
                goto next_item
            end
            if sell_type then
                if not contains(sell_type, item.type) then goto next_item end
            end

            -- Alchemy mode check
            if data.alchemy_mode and Vars and Vars.needed_reagents and
               #Vars.needed_reagents > 0 and item.name and
               name_matches_any(item.name, Vars.needed_reagents) then
                goto next_item
            end

            if not (item.type and string.find(item.type, "clothing")) then
                table.insert(_G.sell_ignore, item.id)
            end

            -- Cursed items
            if item.type and string.find(item.type, "cursed") then
                if not contains(data.settings.sell_loot_types, "cursed") or
                   (not Spell[315].known and item.name and string.find(item.name, "urglaes fang")) then
                    Util().msg({ type = "info", text = "** " .. (item.name or "?") .. " is cursed. Can't touch that. You'll need to take a look", space = true }, data)
                    goto next_item
                elseif contains(data.settings.sell_loot_types, "cursed") then
                    if not Util().decurse(item, data) then goto next_item end
                end
            end

            Inventory().drag(item, nil, data)

            local appraise_types = data.settings.sell_appraise_types or {}
            if #appraise_types > 0 and item.type and name_matches_any(item.type, appraise_types) then
                M.appraise(item, "Gemshop", data)
            else
                M.sell_item(item, "Gemshop", data)
            end

            Inventory().free_hands({ both = true }, data)

            ::next_item::
        end

        ::next_sack::
    end

    data.silver_breakdown["Gemshop"] = (data.silver_breakdown["Gemshop"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 18. glam_and_shroud (lines 5952-6016)
-- Glamour/shroud buffs for better prices.
-- ---------------------------------------------------------------------------

--- Apply Glamour (1205) and Shroud of Deception (1212) for better shop prices.
-- @param data table ELoot data state
function M.glam_and_shroud(data)
    local glam = Spell[1205]
    local shroud = Spell[1212]

    if glam and glam.known and glam.affordable and
       Effects and Effects.Spells and Effects.Spells.time_left and
       Effects.Spells.time_left("Glamour") < 1 then
        wait_until(function() return glam.affordable end)
        glam:cast(GameState.name)
    end

    if shroud and shroud.known then
        local shroud_races = {
            "human", "giantman", "half-elf", "sylvankind", "dark elf",
            "elf", "dwarf", "halfling", "forest gnome", "burghal gnome",
            "half-krolvin", "erithian", "aelotoi"
        }
        local shroud_race_hash = {
            vo  = "human",
            ifw = "dwarf",
            wl  = "human",
            imt = "halfling",
            rr  = "human",
            kf  = "human",
            en  = "elf",
            ti  = "dwarf",
            zl  = "dwarf",
        }

        local town_room = Room[Room.current().find_nearest_by_tag("town")]
        if not town_room or not town_room.image then return end
        local town_key = town_room.image:match("^([^%-]+)")
        if town_room.image:lower():find("zul") then
            town_key = "zl"
        end
        local desired_race = shroud_race_hash[town_key]
        if not desired_race then return end

        local lines = Util().get_command("fame", { '<output class="mono"/>' },
            { silent = true, quiet = true }, data)

        local current_race, current_race_setting
        for _, line in ipairs(lines) do
            local race = line:match("You are a level %d+ ([%w%- ]+) [%w%- ]+%.")
            if race then
                current_race = race:lower()
                for i, r in ipairs(shroud_races) do
                    if r == current_race then
                        current_race_setting = i
                        break
                    end
                end
                break
            end
        end

        if current_race == desired_race then return true end

        local race_setting
        for i, r in ipairs(shroud_races) do
            if r == desired_race then race_setting = i; break end
        end

        if Effects and Effects.Spells and Effects.Spells.time_left and
           Effects.Spells.time_left("Shroud of Deception") < 2 then
            waitcastrt()
            wait_until(function() return shroud.affordable end)
            shroud:cast(GameState.name)
        end

        local profile_lines = Util().get_command("shroud profile",
            { "You are currently using profile" },
            { silent = true, quiet = true }, data)

        local shroud_profile
        for _, line in ipairs(profile_lines) do
            local prof = line:match("You are currently using profile.-(%d+)")
            if prof then shroud_profile = prof; break end
        end

        if shroud_profile and current_race_setting then
            before_dying(function()
                fput("shroud set " .. shroud_profile .. " race " .. current_race_setting)
            end)
            fput("shroud set " .. shroud_profile .. " race " .. race_setting)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 19. go_sell (lines 6018-6068)
-- Navigate to shops and sell.
-- ---------------------------------------------------------------------------

--- Navigate to each shop and sell items there.
-- @param selling table list of shop location strings
-- @param data table ELoot data state
function M.go_sell(selling, data)
    Util().msg({ type = "debug", text = "shop: " .. table.concat(selling, ", ") }, data)
    if #selling == 0 then return end

    M.sell_buffs(data)

    local rooms = {}
    for _, shop in ipairs(selling) do
        -- HW doesn't have some shops
        local town_nearest = Room.current().find_nearest_by_tag("town")
        if town_nearest then
            local town_room = Room[town_nearest]
            if town_room and town_room.uid and town_room.uid[1] == 7503205 and not data.settings.sell_fwi then
                if string.find(shop, "collect") or shop == "pawnshop" or shop == "consignment" or shop == "chronomage" then
                    goto next_shop
                end
            end
        end

        if shop == "chronomage" and Util().fwi and Util().fwi(Room.current()) then
            goto next_shop
        end
        if shop == "chronomage" and not (Util().fwi and Util().fwi(Room.current())) and data.settings.sell_fwi then
            M.gold_rings(data)
            goto next_shop
        end

        local room = Room.current().find_nearest_by_tag(shop)
        if room then table.insert(rooms, room) end

        ::next_shop::
    end

    while #rooms > 0 do
        -- Find closest room using dijkstra
        local closest_room = nil

        -- Prioritize gemshops if needed
        if data.gemshop_first then
            local gemshop_rooms = {}
            for _, room in ipairs(rooms) do
                if Room[room] and Room[room].tags then
                    for _, tag in ipairs(Room[room].tags) do
                        if tag == "gemshop" then
                            table.insert(gemshop_rooms, room)
                            break
                        end
                    end
                end
            end
            if #gemshop_rooms > 0 then
                closest_room = gemshop_rooms[1]
            end
            data.gemshop_first = false
        end

        -- Fallback to first room
        if not closest_room then
            closest_room = rooms[1]
        end

        if Char.percent_encumbrance and Char.percent_encumbrance > 80 then
            Util().silver_deposit(nil, data)
        end

        if Room[closest_room] and Room[closest_room].tags then
            local tags = Room[closest_room].tags
            local function has_tag(t)
                for _, tag in ipairs(tags) do if tag == t then return true end end
                return false
            end

            if has_tag("chronomage") then M.gold_rings(data) end
            if has_tag("furrier") then M.furrier(data) end
            if has_tag("gemshop") then M.gemshop(nil, data) end
            if has_tag("consignment") then M.consignment(data) end
            if has_tag("pawnshop") then M.pawnshop(nil, data) end
            if has_tag("collectibles") or has_tag("collectible") then M.collectibles(data) end
        end

        -- Remove closest room
        for i, r in ipairs(rooms) do
            if r == closest_room then
                table.remove(rooms, i)
                break
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 20. gold_rings (lines 6070-6109)
-- Handle gold rings (test, melt, sell).
-- ---------------------------------------------------------------------------

--- Give gold rings to the chronomage NPC.
-- @param data table ELoot data state
function M.gold_rings(data)
    if not data.settings.sell_gold_rings then return end

    Util().go2("chronomage", data)
    Inventory().free_hands({ both = true }, data)

    -- Find the NPC
    local npc_nouns = { "clerk", "agent", "halfling", "scallywag", "dwarf", "woman", "attendant", "guard" }
    local npc = nil
    local npcs = GameObj.npcs() or {}
    for _, n in ipairs(npcs) do
        for _, noun in ipairs(npc_nouns) do
            if n.noun and string.find(n.noun, noun) then
                npc = n
                break
            end
        end
        if npc then break end
    end
    if not npc then
        local room_desc = GameObj.room_desc() or {}
        for _, n in ipairs(room_desc) do
            for _, noun in ipairs(npc_nouns) do
                if n.noun and string.find(n.noun, noun) then
                    npc = n
                    break
                end
            end
            if npc then break end
        end
    end

    if not npc then return end

    local chrono_sacks = Util().set_selling_containers(nil, data)

    for _, sack in ipairs(chrono_sacks) do
        Inventory().open_single_container(sack, data)
    end

    for _, sack in ipairs(chrono_sacks) do
        if not sack then goto next_sack end
        local has_ring = false
        for _, obj in ipairs(sack.contents or {}) do
            if obj.name and data.regex_gold_rings and string.find(obj.name, data.regex_gold_rings) then
                has_ring = true
                break
            end
        end
        if not has_ring then goto next_sack end

        for _, item in ipairs(sack.contents or {}) do
            if contains_id(_G.sell_ignore, item.id) then goto next_item end
            if not (item.name and data.regex_gold_rings and string.find(item.name, data.regex_gold_rings)) then
                goto next_item
            end

            table.insert(_G.sell_ignore, item.id)
            Inventory().drag(item, nil, data)

            fput("give #" .. item.id .. " to #" .. npc.id)

            for _ = 1, 20 do
                if not Util().in_hand(item) then break end
                pause(0.1)
            end

            Inventory().free_hands({ both = true }, data)

            ::next_item::
        end

        ::next_sack::
    end
end

-- ---------------------------------------------------------------------------
-- 21. handle_ingot (lines 6111-6126)
-- Handle gold ingots.
-- ---------------------------------------------------------------------------

--- Sell a gold ingot at the gemshop.
-- @param gold_ingot table GameObj ingot
-- @param data table ELoot data state
function M.handle_ingot(gold_ingot, data)
    local original_room = Room.current().id
    Util().go2("gemshop", data)
    local start_silvers = Util().silver_check(data)

    M.sell_item(gold_ingot, "Gemshop", data)

    data.silver_breakdown["Gemshop"] = (data.silver_breakdown["Gemshop"] or 0)
        + (Util().silver_check(data) - start_silvers)

    -- Put note in container if needed
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    for _, i in ipairs({rh, lh}) do
        if i.noun and string.find(i.noun, "note") or
           string.find(i.noun or "", "scrip") or
           string.find(i.noun or "", "chit") then
            Inventory().single_drag(i, nil, data)
            break
        end
    end

    Util().go2(original_room, data)
end

-- ---------------------------------------------------------------------------
-- 22. inbetween_scripts (lines 6128-6142)
-- Run between-sell scripts.
-- ---------------------------------------------------------------------------

--- Run any scripts configured to run between selling phases.
-- @param data table ELoot data state
function M.inbetween_scripts(data)
    if not data.settings.between or #data.settings.between == 0 then return end

    -- Go back to the start room before running scripts
    Util().go2(data.start_room, data)

    for _, i in ipairs(data.settings.between) do
        local tokens = {}
        for tok in i:gmatch("%S+") do
            table.insert(tokens, tok)
        end
        if #tokens > 1 then
            Script.run(tokens[1], table.concat(tokens, ", ", 2))
        else
            Script.run(tokens[1])
        end
    end
end

-- ---------------------------------------------------------------------------
-- 23. locksmith (lines 6144-6182)
-- Town locksmith handling.
-- ---------------------------------------------------------------------------

--- Open boxes at the town locksmith.
-- @param boxes table list of box GameObj items
-- @param data table ELoot data state
function M.locksmith(boxes, data)
    Util().msg({ type = "debug", text = "boxes: " .. tostring(#boxes) }, data)

    -- If we're here, assume we emptied out the disk some
    Util().reset_disk_full(data)

    Util().silver_withdraw(data.settings.locksmith_withdraw_amount, data)

    Util().go2("locksmith", data)
    if Room.current().uid and contains(Room.current().uid, 7118381) then
        move("east")
    end
    Util().wait_for_disk(data)

    -- Find table/counter
    local room_desc = GameObj.room_desc() or {}
    local loot_list = GameObj.loot() or {}
    local all_room_objs = {}
    for _, o in ipairs(room_desc) do table.insert(all_room_objs, o) end
    for _, o in ipairs(loot_list) do table.insert(all_room_objs, o) end

    local table_obj = nil
    for _, obj in ipairs(all_room_objs) do
        if obj.noun and (string.find(obj.noun, "table$") or string.find(obj.noun, "counter$")) then
            table_obj = obj
            break
        end
    end

    if table_obj then
        if not table_obj.contents then
            dothistimeout("look on #" .. table_obj.id, 3, { "On the" })
        end

        if not table_obj.contents then
            respond("[eloot-ERROR] failed to find table contents")
        else
            local activator = nil
            for _, obj in ipairs(table_obj.contents) do
                if obj.noun == "bell" then activator = "ring bell"; break
                elseif obj.noun == "keys" then activator = "pull keys"; break
                elseif obj.noun == "chime" then activator = "ring chime"; break
                end
            end
            -- Also check loot for chimes
            if not activator then
                for _, obj in ipairs(loot_list) do
                    if obj.noun == "chime" then activator = "ring chime"; break end
                end
            end

            if activator then
                for _, box in ipairs(boxes) do
                    if not Util().in_hand(box) then
                        Inventory().free_hands({ both = true }, data)
                    end
                    M.locksmith_open(box, activator, data)
                end
            else
                Util().msg({ type = "error", text = " Failed to find a bell, keys, or chime on the table", space = true }, data)
            end
        end
    else
        Util().msg({ type = "error", text = " Failed to find a table", space = true }, data)
    end
end

-- ---------------------------------------------------------------------------
-- 24. locksmith_open (lines 6184-6216)
-- Locksmith open box.
-- ---------------------------------------------------------------------------

--- Open a box at the locksmith using the activator (bell/keys/chime).
-- @param box table GameObj box
-- @param activator string command to ring/pull the activator
-- @param data table ELoot data state
function M.locksmith_open(box, activator, data)
    local lines = Util().get_command("look in #" .. box.id,
        { "<container", "That is closed", "You see the shifting form" },
        { silent = true, quiet = true }, data)

    if not any_match_multi(lines, { "That is closed", "You see the shifting form" }) then
        return
    end

    if not Util().in_hand(box) then
        Inventory().drag(box, nil, data)
    end
    box = Util().box_unphase(box, data)

    lines = Util().get_command("open #" .. box.id,
        { "That is already open", "You open", "You throw back", "It appears to be locked" },
        { silent = true, quiet = true }, data)

    if any_match(lines, "locked") then
        local res = dothistimeout(activator, 2, { "Gimme ([%d,]+) silvers" })
        if res and string.find(res, "Gimme ([%d,]+) silvers") then
            local cost = res:match("Gimme ([%d,]+) silvers")
            if cost then
                cost = tonumber(cost:gsub(",", "")) or 0
                data.silver_breakdown["Town Locksmith"] = (data.silver_breakdown["Town Locksmith"] or 0) + (-1 * cost)
                data.silver_breakdown["Town Open"] = (data.silver_breakdown["Town Open"] or 0) + 1
            end
        end

        if not res then
            Util().msg({ type = "error", text = " Unknown locksmith response." }, data)
            Inventory().single_drag(box, false, data)
            return
        end

        local result = dothistimeout("pay", 2, { "accepts", "have enough" })
        if result and string.find(result, "have enough") then
            Inventory().single_drag(box, false, data)
            Util().silver_withdraw(data.settings.locksmith_withdraw_amount, data)
            Util().go2("locksmith", data)
            return M.locksmith_open(box, activator, data)
        end
    end

    Loot().box_loot(box, "Town Locksmith", data)
end

-- ---------------------------------------------------------------------------
-- 25. pawnshop (lines 6412-6510)
-- Pawn shop selling.
-- ---------------------------------------------------------------------------

--- Sell items at the pawnshop.
-- @param sell_type table|nil list of specific types to sell
-- @param data table ELoot data state
function M.pawnshop(sell_type, data)
    Util().go2("pawnshop", data)
    local start_silvers = Util().silver_check(data)
    Inventory().free_hands({ both = true }, data)

    local all_contents = {}
    for item_key, container in pairs(StowList.stow_list) do
        if container then
            local match = false
            for _, sell in ipairs(data.settings.sell_container or {}) do
                if string.find(tostring(item_key), sell, 1, true) then
                    match = true
                    break
                end
            end
            if match then
                for _, c in ipairs(container.contents or {}) do
                    table.insert(all_contents, c)
                end
            end
        end
    end

    if data.settings.use_disk then
        Util().wait_for_disk(data)
        if data.disk then
            Inventory().open_single_container(data.disk, data)
            for _, c in ipairs(data.disk.contents or {}) do
                table.insert(all_contents, c)
            end
        end
    end

    if Util().time_between("autoclosers", 30, data) then
        Inventory().check_auto_closer(data)
    end

    for _, thing in ipairs(all_contents) do
        if contains_id(_G.sell_ignore, thing.id) then goto next_thing end

        -- Must be sellable at pawnshop (but not gemshop), or be a box, or clothing
        if not ((thing.sellable and string.find(thing.sellable, "pawnshop") and
                 not string.find(thing.sellable, "gemshop")) or
                thing.type == "box" or
                (thing.type and string.find(thing.type, "clothing"))) then
            goto next_thing
        end

        -- Skip ready-list items
        if ReadyList and ReadyList.ready_list then
            local skip = false
            for _, v in pairs(ReadyList.ready_list) do
                if type(v) == "table" and v.id == thing.id then skip = true; break end
            end
            if skip then goto next_thing end
        end

        if #(data.settings.sell_exclude or {}) > 0 and thing.name and
           name_matches_any(thing.name, data.settings.sell_exclude) then
            goto next_thing
        end

        -- Type check against sell_loot_types
        if thing.type then
            local type_match = false
            for t in thing.type:gmatch("[^,]+") do
                t = t:match("^%s*(.-)%s*$")
                for _, slt in ipairs(data.settings.sell_loot_types) do
                    if t == slt then type_match = true; break end
                end
                if type_match then break end
            end
            if not type_match then goto next_thing end
        end

        if thing.name and (string.find(thing.name, "%bbound%b") or
           string.find(thing.name, "^shimmering %w+ orb$")) then
            goto next_thing
        end
        if data.settings.sell_gold_rings and thing.name and data.regex_gold_rings and
           string.find(thing.name, data.regex_gold_rings) then
            goto next_thing
        end
        if sell_type then
            if not contains(sell_type, thing.type) then goto next_thing end
        end

        table.insert(_G.sell_ignore, thing.id)

        -- Scroll keep check
        if thing.type and string.find(thing.type, "scroll") and
           data.settings.sell_keep_scrolls and #data.settings.sell_keep_scrolls > 0 then
            local no_vib = {}
            local vib_scrolls = {}
            for _, s in ipairs(data.settings.sell_keep_scrolls) do
                local str = tostring(s)
                if str:lower():find("v") then
                    local num = str:match("%d+")
                    if num then table.insert(vib_scrolls, num) end
                else
                    table.insert(no_vib, str)
                end
            end

            local scroll_lines = Util().get_command("read #" .. thing.id,
                { "It takes you a moment", "There is nothing there to read", "You can't do that" },
                { silent = true, quiet = true }, data)

            -- Check non-vibrant scrolls
            if #no_vib > 0 then
                local no_vib_pat = "%(" .. table.concat(no_vib, "|") .. "%)"
                local skip = false
                for _, line in ipairs(scroll_lines) do
                    if string.find(line, no_vib_pat) and not string.find(line, "vibrant") then
                        skip = true
                        break
                    end
                end
                if skip then goto next_thing end
            end

            -- Check vibrant scrolls
            if #vib_scrolls > 0 then
                local vib_pat = "%(" .. table.concat(vib_scrolls, "|") .. "%)"
                local skip = false
                for _, line in ipairs(scroll_lines) do
                    if string.find(line, vib_pat) and string.find(line, "vibrant") then
                        skip = true
                        break
                    end
                end
                if skip then goto next_thing end
            end
        end

        -- Cursed items
        if thing.type and string.find(thing.type, "cursed") then
            if not contains(data.settings.sell_loot_types, "cursed") then
                Util().msg({ type = "info", text = "** " .. (thing.name or "?") .. " is cursed. Can't touch that. You'll need to take a look", space = true }, data)
                goto next_thing
            else
                if not Util().decurse(thing, data) then goto next_thing end
            end
        end

        Inventory().drag(thing, nil, data)

        -- Analyze for Alter 41
        local analyze_lines = Util().get_command("analyze #" .. thing.id,
            { "You analyze" }, { silent = true, quiet = true }, data)
        if any_match(analyze_lines, "ALTER 41") then
            Util().msg({ type = "info", text = "** This analyzes as Alter 41. Keeping it **", space = true }, data)
            Inventory().single_drag(thing, nil, data)
            goto next_thing
        end

        local appraise_types = data.settings.sell_appraise_types or {}
        if (#appraise_types > 0 and thing.type and name_matches_any(thing.type, appraise_types)) or
           (thing.type and (string.find(thing.type, "uncommon") or
            string.find(thing.type, "weapon") or string.find(thing.type, "armor"))) then
            M.appraise(thing, "Pawnshop", data)
        elseif thing.type and string.find(thing.type, "box") then
            local look_line = Util().get_res("look in #" .. thing.id, data.look_regex, data)

            if look_line and (string.find(look_line, "There is nothing") or string.find(look_line, "In the")) then
                local box_contents = thing.contents or {}
                for _, box_item in ipairs(box_contents) do
                    if box_item.type and string.find(box_item.type, "cursed") and
                       Spell[315].known and Spell[315].affordable and
                       contains(data.settings.sell_loot_types, "cursed") then
                        Spell[315]:cast("at #" .. box_item.id)
                    elseif box_item.type and string.find(box_item.type, "cursed") and
                           not contains(data.settings.sell_loot_types, "cursed") then
                        Util().msg({ type = "info", text = "** " .. (box_item.name or "?") .. " is cursed. Stowing box. You'll need to take a look", space = true }, data)
                        Inventory().single_drag(thing, false, data)
                    else
                        Inventory().single_drag(box_item, false, data)
                    end
                end
                M.sell_item(thing, "Pawnshop", data)
            elseif look_line and string.find(look_line, "That is closed") then
                Util().msg({ type = "info", text = "** " .. (thing.name or "?") .. " is closed. Storing box..." }, data)
                Inventory().single_drag(thing, false, data)
            end
        else
            M.sell_item(thing, "Pawnshop", data)
        end

        Inventory().free_hands({ both = true }, data)

        ::next_thing::
    end

    data.silver_breakdown["Pawnshop"] = (data.silver_breakdown["Pawnshop"] or 0)
        + (Util().silver_check(data) - start_silvers)
end

-- ---------------------------------------------------------------------------
-- 26. process_boxes (lines 6554-6577)
-- Process all boxes.
-- ---------------------------------------------------------------------------

--- Process all boxes: locksmith pool, pool return, then town locksmith.
-- @param data table ELoot data state
function M.process_boxes(data)
    local boxes = Util().find_boxes(data)
    if #boxes == 0 then return end

    Util().msg({ type = "debug", text = "length: " .. tostring(#boxes) }, data)

    local should_check_pool = data.settings.always_check_pool or
        (data.settings.sell_locksmith_pool and #boxes > 0)
    local skip_for_gem_bounty = Bounty and Bounty.task and Bounty.task.gem and Bounty.task:gem() and
        data.settings.sell_locksmith and data.settings.locksmith_when_gem_bounty and #boxes > 0

    if should_check_pool and not skip_for_gem_bounty then
        if data.settings.sell_locksmith_pool then
            Pool().locksmith_pool(boxes, nil, data)
        end
        Pool().pool_return(nil, data)

        -- Refresh the boxes
        boxes = Util().find_boxes(data)
    end

    -- Go to Locksmith for remaining boxes
    if data.settings.sell_locksmith and #boxes > 0 then
        M.locksmith(boxes, data)
    end

    -- Deposit silvers if encumbered
    if Char.percent_encumbrance and Char.percent_encumbrance > 80 then
        Util().silver_deposit(nil, data)
    end
end

-- ---------------------------------------------------------------------------
-- 27. save_trash_box (lines 6579-6624)
-- Save or trash empty box.
-- ---------------------------------------------------------------------------

--- Save valuable boxes or trash the rest.
-- @param box table GameObj box
-- @param data table ELoot data state
function M.save_trash_box(box, data)
    Util().msg({ type = "debug", text = "box: " .. tostring(box) }, data)

    local return_room = Room.current().id
    local save_box = contains(data.settings.sell_loot_types, "box")

    local function is_valuable(name)
        return name and (string.find(name, "gold") or string.find(name, "mithril") or string.find(name, "silver"))
    end

    local box_contents = box.contents or {}

    -- If it's a save box and empty, just store it; don't toss Reliquaries
    if (save_box and #box_contents == 0 and is_valuable(box.name)) or
       (box.name and string.find(box.name:lower(), "reliquary")) then
        Inventory().single_drag(box, false, data)
        return
    end

    -- Find the trash can
    local trash = Util().find_trash(data)
    if not trash then
        Util().go2("locksmith pool", data)
        trash = Util().find_trash(data)
    end

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

            if Util().in_hand(item) then
                Inventory().single_drag(item, nil, data)
            end
        end
    else
        for _ = 1, 4 do
            if not Util().in_hand(box) then break end
            fput(toss_cmd .. " #" .. box.id)
            Util().wait_rt()
        end
    end

    if Util().in_hand(box) then
        Inventory().single_drag(box, false, data)
    end

    Util().go2(return_room, data)
end

-- ---------------------------------------------------------------------------
-- 28. sell (lines 6626-6659)
-- Main sell method.
-- ---------------------------------------------------------------------------

--- Main sell orchestrator.
-- box_in_hand -> clear_hands -> process_boxes -> break_rocks -> hoard -> bounty -> go_sell -> deposit -> dump
-- @param data table ELoot data state
function M.sell(data)
    if hidden and hidden() or (invisible and invisible()) then
        fput("unhide")
    end

    M.box_in_hand(nil, data)

    Inventory().clear_hands(data)

    M.process_boxes(data)

    M.inbetween_scripts(data)

    -- Break rocks
    if contains(data.settings.sell_loot_types, "breakable") then
        M.break_rocks(data)
    end

    -- Hoard stuff
    if data.settings.gem_horde or data.settings.alchemy_horde then
        local ok, Hoard = pcall(require, "gs.eloot.hoard")
        if ok and Hoard and Hoard.hoard_items then
            Hoard.hoard_items(data)
        end
    end

    -- Check bounties
    M.check_bounty(data)

    M.go_sell(M.check_items(nil, data), data)

    Util().silver_deposit(true, data)

    -- Dump herbs and junk
    M.dump_herbs_junk(data)

    Inventory().return_hands(data)

    -- Close any containers that were opened
    if data.settings.keep_closed then
        Inventory().close_sell_containers(data)
    end
end

-- ---------------------------------------------------------------------------
-- 29. sell_buffs (lines 6661-6672)
-- Apply sell buffs.
-- ---------------------------------------------------------------------------

--- Apply buffs for better sell prices (glamour/shroud, aspect of the lion).
-- @param data table ELoot data state
function M.sell_buffs(data)
    if data.settings.sell_shroud then
        M.glam_and_shroud(data)
    end

    if data.settings.sell_aspect and Spell[650] and Spell[650].known then
        if not (Spell[9018] and Spell[9018].active) and
           not (Spell[9019] and Spell[9019].active) then
            if Spell[650].affordable and not Spell[650].active then
                fput("prep 650")
                fput("assume lion")
            elseif Spell[650].active and checkmana(25) then
                waitcastrt()
                fput("assume lion")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 30. sell_item (lines 6674-6692)
-- Sell single item at current shop.
-- ---------------------------------------------------------------------------

--- Sell a single item at the current shop.
-- @param item table GameObj item
-- @param place string|nil shop name for silver tracking
-- @param data table ELoot data state
function M.sell_item(item, place, data)
    if not item or (item.name and item.name == "Empty") then return end

    local lines = Util().get_command("sell #" .. item.id,
        { "You offer to sell", "You ask" }, nil, data)

    -- Check for rejection
    if any_match_multi(lines, {
        "That's not quite my field",
        "That's basically worthless here",
        "Can't say I'm interested in that",
        "This is a pawnshop, sir, not a junkshop",
        "The company don't buy trash",
        "as if you were a lunatic"
    }) then
        return
    end

    -- Wait for item to leave hand
    for _ = 1, 20 do
        if not Util().in_hand(item) then break end
        pause(0.1)
    end

    local bulk_note = tonumber(Util().read_note(data)) or 0

    if bulk_note > 0 and place and data.silver_breakdown then
        data.silver_breakdown[place] = (data.silver_breakdown[place] or 0) + bulk_note
    end
end

return M
