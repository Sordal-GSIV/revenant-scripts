--- sloot/sell.lua
-- Full selling routine: chronomage rings, locksmith, locker, stockpile, sell items.
-- Mirrors sell proc from sloot.lic v3.5.2.

local items_mod    = require("sloot/items")
local sacks_mod    = require("sloot/sacks")
local coins_mod    = require("sloot/coins")
local locksmith_mod = require("sloot/locksmith")
local locker_mod   = require("sloot/locker")
local settings_mod = require("sloot/settings")

local M = {}

--- Collect all boxes from box sack, overflow sacks, and disk (if enabled).
local function find_boxes(settings)
    local hooks_mod = require("sloot/hooks")
    local boxes = {}

    local boxsack_name = settings_mod.uvar_get("boxsack")
    local boxsack = boxsack_name ~= "" and GameObj.find_inv(boxsack_name) or sacks_mod.sacks["box"]
    local check_sacks = {}
    if boxsack then check_sacks[#check_sacks + 1] = boxsack end

    -- Overflow sacks
    for overflow in (settings.overflowsack or ""):gmatch("[^,]+") do
        overflow = overflow:match("^%s*(.-)%s*$")
        local osack = overflow ~= "" and GameObj.find_inv(overflow) or nil
        if osack then check_sacks[#check_sacks + 1] = osack end
    end

    for _, sack in ipairs(check_sacks) do
        for _, obj in ipairs(sack.contents or {}) do
            if obj.type and obj.type:find("box") then
                boxes[#boxes + 1] = obj
            end
        end
    end

    -- Disk contents
    if settings.enable_disking and hooks_mod.has_disk then
        local char_name = Char.name
        local disk = GameObj.find(char_name .. " disk") or GameObj.find(char_name .. " coffin")
        if disk then
            if not disk.contents then
                dothistimeout("look in #" .. disk.id, 5, Regex.new("There is nothing|In the .*?"))
            end
            for _, obj in ipairs(disk.contents or {}) do
                if obj.type and obj.type:find("box") then
                    boxes[#boxes + 1] = obj
                end
            end
        end
    end

    return boxes
end

--- Full sell routine.
function M.sell(settings)
    local cur_room = Room.id
    local silver_breakdown = {}
    local found_sacks = {}
    local selling = {}
    local types = {}

    -- ── Chronomage rings ────────────────────────────────────────────────────
    if settings.enable_sell_chronomage then
        local jsack_name = settings_mod.uvar_get("jewelrysack")
        local jsack = jsack_name ~= "" and GameObj.find_inv(jsack_name) or sacks_mod.sacks["jewelry"]
        if jsack then
            local rings = {}
            for _, obj in ipairs(jsack.contents or {}) do
                if obj.name and obj.name:match("^%w+ gold ring$") then
                    rings[#rings + 1] = obj
                end
            end
            if #rings > 0 then
                go2("chronomage")
                local npc = GameObj.npcs()[1]
                if npc then
                    empty_hands()
                    for _, ring in ipairs(rings) do
                        fput("get #" .. ring.id)
                        fput("give #" .. ring.id .. " to #" .. npc.id)
                        local rh = GameObj.right_hand()
                        local lh = GameObj.left_hand()
                        if (rh and rh.id == ring.id) or (lh and lh.id == ring.id) then
                            fput("put #" .. ring.id .. " in #" .. jsack.id)
                        end
                    end
                    fill_hands()
                end
            end
        end
    end

    -- ── Find boxes ──────────────────────────────────────────────────────────
    local boxes = find_boxes(settings)

    -- ── Locker boxes ────────────────────────────────────────────────────────
    if #boxes > 0 and settings.enable_locker_boxes then
        locker_mod.locker_boxes(boxes, settings)
        boxes = find_boxes(settings)
    end

    -- ── Locksmith ───────────────────────────────────────────────────────────
    if #boxes > 0 and settings.enable_sell_locksmith then
        locksmith_mod.locksmith(boxes, silver_breakdown, settings)
    end

    -- ── Stockpile gems ──────────────────────────────────────────────────────
    if settings.enable_sell_stockpile then
        if (settings.locker or "") == "" then
            echo("[SLoot] warning: stockpiling is on but locker room is not set")
            pause(3)
        elseif locker_mod.need_to_stockpile(settings) or locker_mod.need_to_raid_stockpile() then
            if locker_mod.to_locker(settings) then
                if locker_mod.need_to_stockpile(settings) then
                    locker_mod.stockpile(settings)
                end
                if locker_mod.need_to_raid_stockpile() then
                    locker_mod.raid_stockpile(settings)
                end
                locker_mod.from_locker(settings)
            end
        end
    end

    -- ── Collect sell types ──────────────────────────────────────────────────
    for key, enabled in pairs(settings) do
        local stype = key:match("^enable_sell_type_(.+)$")
        if stype and enabled then
            types[#types + 1] = stype
            local ukey = stype .. "sack"
            local sname = settings_mod.uvar_get(ukey)
            if sname ~= "" then
                local found = GameObj.find_inv(sname)
                if found then
                    local already = false
                    for _, s in ipairs(found_sacks) do
                        if s.id == found.id then already = true; break end
                    end
                    if not already then found_sacks[#found_sacks + 1] = found end
                end
            end
        end
    end

    -- Also check overflow sacks
    for overflow in (settings.overflowsack or ""):gmatch("[^,]+") do
        overflow = overflow:match("^%s*(.-)%s*$")
        if overflow ~= "" then
            local osack = GameObj.find_inv(overflow)
            if osack then
                local already = false
                for _, s in ipairs(found_sacks) do
                    if s.id == osack.id then already = true; break end
                end
                if not already then found_sacks[#found_sacks + 1] = osack end
            end
        end
    end

    -- ── Scan sacks for sellable items ───────────────────────────────────────
    local sell_exclude = settings.sell_exclude or ""
    for _, sack in ipairs(found_sacks) do
        if not sack.contents then
            dothistimeout("look in #" .. sack.id, 5, Regex.new("In the .*?"))
        end
        for _, item in ipairs(sack.contents or {}) do
            -- Skip excluded items
            if sell_exclude ~= "" and Regex.test(item.name or "", sell_exclude) then goto next_item end
            if (item.name or ""):find("Guild voucher pack") then goto next_item end
            -- Item must be sellable
            if not item.sellable or item.sellable == "" then goto next_item end
            -- Item type must match a sell type
            local item_type_str = item.type or ""
            local matched = false
            for _, st in ipairs(types) do
                for it in item_type_str:gmatch("[^,]+") do
                    it = it:match("^%s*(.-)%s*$")
                    if it == st then matched = true; break end
                end
                if matched then break end
            end
            if not matched then goto next_item end

            local loc = item.sellable
            if not selling[loc] then selling[loc] = {} end
            selling[loc][#selling[loc] + 1] = item

            ::next_item::
        end
    end

    -- ── Sell empty boxes at pawnshop ────────────────────────────────────────
    if settings.enable_sell_type_empty_box then
        local bsack_name = settings_mod.uvar_get("boxsack")
        local bsack = bsack_name ~= "" and GameObj.find_inv(bsack_name) or sacks_mod.sacks["box"]
        if bsack then
            for _, obj in ipairs(bsack.contents or {}) do
                if obj.type and obj.type:find("box") then
                    if not selling["pawnshop"] then selling["pawnshop"] = {} end
                    selling["pawnshop"][#selling["pawnshop"] + 1] = obj
                end
            end
        end
    end

    -- ── Sell scarabs at gemshop ─────────────────────────────────────────────
    if settings.enable_sell_type_scarab then
        local bsack_name = settings_mod.uvar_get("boxsack")
        local bsack = bsack_name ~= "" and GameObj.find_inv(bsack_name) or sacks_mod.sacks["box"]
        if bsack then
            for _, obj in ipairs(bsack.contents or {}) do
                if obj.type and obj.type:find("scarab") then
                    if not selling["gemshop"] then selling["gemshop"] = {} end
                    selling["gemshop"][#selling["gemshop"] + 1] = obj
                end
            end
        end
    end

    -- ── Execute sells ───────────────────────────────────────────────────────
    local has_items = false
    for _ in pairs(selling) do has_items = true; break end

    if not has_items then
        echo("[SLoot] -- nothing to sell")
    else
        empty_hands()

        for location, items in pairs(selling) do
            local loc = location:match("^([^,]+)") or location
            local start_silver = checksilvers()

            go2(loc)

            for _, item in ipairs(items) do
                if items_mod.get_item(item, nil) then
                    dothistimeout("sell #" .. item.id, 5, Regex.new("ask|offer"))
                    -- If still in hand, try to stow back
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if (rh and rh.noun == item.noun) or (lh and lh.noun == item.noun) then
                        local first_type = (item.type or ""):match("^([^,]+)") or ""
                        first_type = first_type:match("^%s*(.-)%s*$")
                        local orig_sack = sacks_mod.sacks[first_type]
                                      or (settings_mod.uvar_get(first_type .. "sack") ~= "" and GameObj.find_inv(settings_mod.uvar_get(first_type .. "sack")))
                        if orig_sack then
                            items_mod.put_item(item, orig_sack)
                        else
                            fput("drop #" .. item.id)
                        end
                    end
                else
                    echo("[SLoot] -- failed to find " .. (item.name or "?"))
                end
            end

            silver_breakdown[loc] = checksilvers() - start_silver
        end
    end

    coins_mod.deposit_coins(settings)
    if cur_room then go2(tostring(cur_room)) end
    fill_hands()

    -- ── Report ──────────────────────────────────────────────────────────────
    local total = 0
    for _, silver in pairs(silver_breakdown) do total = total + silver end
    if total ~= 0 then
        echo("[SLoot] silver breakdown")
        for loc, silver in pairs(silver_breakdown) do
            echo("[SLoot]   " .. loc .. ": " .. silver)
        end
        echo("[SLoot] total: " .. total)
    end
end

return M
