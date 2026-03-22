--- sloot/items.lua
-- Item manipulation: get_item, put_item, free_hand, grab_loot, loot_it.
-- Mirrors the corresponding procs from sloot.lic v3.5.2.

local sacks_mod   = require("sloot/sacks")
local hooks_mod   = require("sloot/hooks")
local settings_mod = require("sloot/settings")

local M = {}

local GET_RX = Regex.new("^You (?:remove|grab|get|pick)|^You already have|^Get what")
local PUT_RX = Regex.new("^You (?:put|(?:discreetly )?tuck|attempt to shield|place|.* place|slip|wipe off the blade and sheathe|absent-mindedly drop|carefully add|find an incomplete bundle|untie your drawstring pouch)|^The .+ is already a bundle|^Your bundle would be too large|^The .+ is too large to be bundled|^As you place your .+ inside your .+, you notice")

--- Get an item, optionally from a container.
-- Returns true if item ends up in hand.
function M.get_item(item, from_sack)
    if not item then return false end
    waitrt()

    -- Already in hand?
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local item_id = type(item) == "table" and item.id or tostring(item)
    if (rh and rh.id == item_id) or (lh and lh.id == item_id) then
        return true
    end

    local id_str = "#" .. item_id
    local cmd
    if from_sack then
        local sack_id = type(from_sack) == "table" and from_sack.id or tostring(from_sack)
        cmd = "get " .. id_str .. " from #" .. sack_id
    else
        cmd = "get " .. id_str
    end

    fput(cmd)

    local noun = type(item) == "table" and item.noun or tostring(item)
    for _ = 1, 30 do
        waitrt()
        local rh2 = GameObj.right_hand()
        local lh2 = GameObj.left_hand()
        if (rh2 and rh2.id == item_id) or (lh2 and lh2.id == item_id) then
            return true
        end
        local line = get_noblock()
        if line then
            if Regex.test(line, "is out of your reach") then
                pause(4)
                return M.get_item(item, from_sack)
            elseif Regex.test(line, "^You can't pick that up\\.$|^Get what\\?$|crumbles and decays away|crumbles into a pile of dust") then
                return false
            end
        else
            pause(0.1)
        end
    end
    return false
end

--- Put an item into a container.
-- Handles closed-sack auto-open and overflow scenarios.
-- Returns true on success.
function M.put_item(item, sack)
    if not item or not sack then return false end
    waitrt()

    local item_id = type(item) == "table" and item.id or tostring(item)
    local sack_id = type(sack) == "table" and sack.id or tostring(sack)
    local sack_obj = type(sack) == "table" and sack or GameObj.find(sack_id)

    -- Confirm item still in hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if not (rh and rh.id == item_id) and not (lh and lh.id == item_id) then
        return false
    end

    fput("put #" .. item_id .. " in #" .. sack_id)

    local noun = type(item) == "table" and item.noun or tostring(item)
    for _ = 1, 30 do
        waitrt()
        local rh2 = GameObj.right_hand()
        local lh2 = GameObj.left_hand()
        if not (rh2 and rh2.id == item_id) and not (lh2 and lh2.id == item_id) then
            return true
        end
        local line = get_noblock()
        if line then
            if Regex.test(line, "^You can't put .* in .*\\.  It's closed!$") then
                -- Auto-open and retry
                if sack_obj then sacks_mod.open_sack(sack_obj) end
                return M.put_item(item, sack)
            elseif Regex.test(line, "^Your .* won't fit in .*\\.$|find there is no space for the") then
                return false
            end
        else
            pause(0.1)
        end
    end
    return false
end

--- Free up a hand for looting.
function M.free_hand(settings)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if not (rh and rh.noun) and not (lh and lh.noun) then return end -- both empty
    if (not rh or rh.noun == "") or (not lh or lh.noun == "") then return end -- one empty

    if settings.enable_stow_left then
        empty_left_hand()
    else
        empty_right_hand()
    end
end

--- Wait for disk, attempt Wizard summon if needed.
-- Returns disk GameObj or nil.
local function check_for_disk()
    local char_name = Char.name
    local disk = nil
    local notified = false
    for _ = 1, 25 do
        disk = GameObj.find(char_name .. " disk") or GameObj.find(char_name .. " coffin")
        if disk then break end
        pause(0.2)
        if not notified then
            echo("[SLoot] -- waiting on your disk to arrive")
            notified = true
        end
    end

    if not disk then
        hooks_mod.has_disk = false
        -- Wizard disk re-summon (spell 511, Familiar Gate)
        if Char.prof == "Wizard" and Char.level > 10 and Spell.known(511) then
            echo("[SLoot] Hooray! You're a Weezard!")
            if Spell.affordable(511) then
                Spell.cast(511)
                pause(2)
                disk = GameObj.find(char_name .. " disk") or GameObj.find(char_name .. " coffin")
            else
                echo("[SLoot] No mana, aborting disk summon.")
            end
        end
    end

    return disk
end

--- Phase a box (Sorcerer spell 704) to change its ID.
-- Returns the refreshed box GameObj.
local function try_phase_box(box)
    local in_right = GameObj.right_hand() and GameObj.right_hand().id == box.id
    dothistimeout("prep 704", 5, Regex.new("Phase"))
    local res = dothistimeout("cast #" .. box.id, 5,
        Regex.new("somewhat insubstantial|flickers in and out|becomes momentarily|resists the effects"))
    if res and Regex.test(res, "becomes momentarily") then
        -- Item got a new ID after phasing — refresh from hand
        if in_right then
            wait_until(function() return GameObj.right_hand() and GameObj.right_hand().noun ~= nil end)
            return GameObj.right_hand()
        else
            wait_until(function() return GameObj.left_hand() and GameObj.left_hand().noun ~= nil end)
            return GameObj.left_hand()
        end
    end
    return box
end

--- Grab a single loot item and stow it into the appropriate sack.
-- Mirrors grab_loot proc from sloot.lic.
function M.grab_loot(loot_obj, from_container, settings)
    if not loot_obj then return end
    local sacks = sacks_mod.sacks

    -- Find correct sack by trying each type in loot's type list
    local loot_types = {}
    if loot_obj.type then
        for t in loot_obj.type:gmatch("[^,]+") do
            loot_types[#loot_types + 1] = t:match("^%s*(.-)%s*$")
        end
    end

    -- Disk routing for boxes
    local disk = nil
    if loot_obj.type and loot_obj.type:find("box") and settings.enable_disking
       and hooks_mod.has_disk and not hooks_mod.disk_full then
        disk = check_for_disk()
        if not disk then
            echo("[SLoot] I can't seem to find your disk")
            hooks_mod.has_disk = false
        end
    end

    -- Find sack
    local sack = nil
    for _, t in ipairs(loot_types) do
        t = t:match("^%s*(.-)%s*$")
        if sacks[t] then
            sack = sacks[t]
            break
        end
    end

    if not sack then
        echo("[SLoot] unable to find sack for \"" .. (loot_obj.name or "?") .. "\" with type \"" .. (loot_obj.type or "?") .. "\"")
        echo("[SLoot] to loot manually, pause me for 5 seconds with ;p sloot")
        fput("look in #" .. loot_obj.id)
        pause(5)
        return
    end

    -- Get the item
    if not M.get_item(loot_obj, from_container) then
        echo("[SLoot] failed to get item \"" .. (loot_obj.name or "?") .. "\"")
        return
    end

    -- Try disk first
    if disk and M.put_item(loot_obj, disk) then
        return
    end

    -- Try phasing for boxes (Sorcerer spell 704)
    if loot_obj.type and loot_obj.type:find("box") and settings.enable_phasing
       and Spell.known(704) and Spell.affordable(704) and Char.level > 3
       and not (loot_obj.name or ""):find("mithril") and not (loot_obj.name or ""):find("enruned") then
        loot_obj = try_phase_box(loot_obj)
    end

    -- Stow in sack
    if not M.put_item(loot_obj, sack) then
        -- Try overflow sacks
        local overflow_str = settings.overflowsack or ""
        local stowed = false
        for overflow in overflow_str:gmatch("[^,]+") do
            overflow = overflow:match("^%s*(.-)%s*$")
            if overflow ~= "" then
                local osack = GameObj.find_inv(overflow)
                if osack then
                    if M.put_item(loot_obj, osack) then
                        -- Update sack reference for this type
                        sacks[loot_types[1] or ""] = osack
                        stowed = true
                        break
                    end
                end
            end
        end
        if not stowed then
            echo("[SLoot] failed to stow \"" .. (loot_obj.name or "?") .. "\" — dropping")
            fput("drop #" .. loot_obj.id)
        end
    end
end

--- Loot an array of items, skipping excluded IDs and excluded names.
-- @param array       array of GameObj
-- @param exclude_ids table of id -> true to skip once
-- @param settings    settings table
function M.loot_it(array, exclude_ids, settings)
    if not array then return end
    exclude_ids = exclude_ids or {}

    local loot_exclude = settings.loot_exclude or ""

    for _, loot_obj in ipairs(array) do
        -- Skip severed limbs
        if Regex.test(loot_obj.name or "", "severed.*(?:arm|leg)") then
            goto continue
        end

        -- Skip excluded IDs (self-drops mode)
        if exclude_ids[loot_obj.id] then
            exclude_ids[loot_obj.id] = nil
            goto continue
        end

        -- Skip loot_exclude regex
        if loot_exclude ~= "" and Regex.test(loot_obj.name or "", loot_exclude) then
            goto continue
        end

        -- Check if any type is enabled
        local item_types = loot_obj.type or ""
        local want = false
        for t in item_types:gmatch("[^,]+") do
            t = t:match("^%s*(.-)%s*$")
            if settings["enable_loot_" .. t] then
                want = true
                break
            end
        end

        if want then
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if not (rh and rh.id == loot_obj.id) and not (lh and lh.id == loot_obj.id) then
                M.free_hand(settings)
            end
            M.grab_loot(loot_obj, nil, settings)
        elseif loot_obj.name == "some silver coins" then
            dothistimeout("get #" .. loot_obj.id, 5,
                Regex.new("^You gather the remaining"))
        end

        ::continue::
    end
end

return M
