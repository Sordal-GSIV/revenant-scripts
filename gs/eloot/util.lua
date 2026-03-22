--- ELoot utility functions
-- Ported from eloot.lic lines 2227-3162
-- Contains both script utility methods and game utility methods.
--
-- Usage:
--   local Util = require("gs.eloot.util")
--   Util.msg({type = "yellow", text = "hello"}, data)

local Data = require("gs.eloot.data")

local M = {}

-- ---------------------------------------------------------------------------
-- Script utility methods (lines 2227-2552)
-- ---------------------------------------------------------------------------

--- Capitalize the first letter of each word in a string.
-- @param str string
-- @return string
function M.capitalize_words(str)
    if not str then return "" end
    str = tostring(str)
    return (str:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

--- Set up a DownstreamHook to track disk presence/destruction.
-- Registers hook "eloot_diskintegration" that watches for disk
-- disintegration, arrival, and summoning messages.
-- @param data table the ELoot data state
function M.disk_usage(data)
    if not data.settings.use_disk then return end
    -- Don't double-register
    -- (In Revenant, DownstreamHook.list() returns a table; check membership)
    local hooks = DownstreamHook.list and DownstreamHook.list() or {}
    for _, name in ipairs(hooks) do
        if name == "eloot_diskintegration" then return end
    end

    -- Initial check: is the disk in the room?
    local mine = Disk and Disk.mine and Disk.mine()
    if mine then
        data.disk = GameObj[mine.id]
    else
        data.disk = nil
    end

    local disk_noun = data.disk and data.disk.noun or ""
    local disk_name = data.disk and data.disk.name or ""

    DownstreamHook.add("eloot_diskintegration", function(server_line)
        -- Disk disintegration
        if data.disk and string.find(server_line, "disintegrates") then
            local esc_noun = disk_noun:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local esc_name = disk_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            if string.find(server_line, esc_noun) and string.find(server_line, esc_name) then
                data.disk = nil
            end
        end

        -- Disk arrives following you
        if string.find(server_line, "arrives, following you dutifully") then
            local mine2 = Disk and Disk.mine and Disk.mine()
            if mine2 and not data.disk then
                data.disk = GameObj[mine2.id]
            end
        end

        -- Disk summoned
        if string.find(server_line, "A small circular container suddenly appears and floats rather serenely over to you") then
            -- Brief wait for game object to register
            local attempts = 0
            while attempts < 20 do
                local mine3 = Disk and Disk.mine and Disk.mine()
                if mine3 then
                    data.disk = GameObj[mine3.id]
                    break
                end
                pause(0.2)
                attempts = attempts + 1
            end
        end

        return server_line  -- pass through
    end)
end

--- Reset the disk_full tracking table.
-- Rebuilds from Group.disks when rebuild is true; preserves previous
-- full/not-full state when rebuild is false.
-- @param data table the ELoot data state
-- @param rebuild boolean (default true)
function M.reset_disk_full(data, rebuild)
    if rebuild == nil then rebuild = true end

    local prev
    if rebuild then
        prev = {}
    elseif type(data.disk_full) == "table" then
        prev = data.disk_full
    else
        prev = {}
    end

    data.disk_full = {}
    local disks = Group and Group.disks and Group.disks() or {}
    for _, disk in ipairs(disks) do
        if prev[disk.name] ~= nil then
            data.disk_full[disk.name] = prev[disk.name]
        else
            data.disk_full[disk.name] = false
        end
    end
end

--- Normalize ready-list item key names.
-- @param item string
-- @return string normalized key
function M.fix_item_key(item)
    local s = tostring(item)
    if s == "secondary_weapon" then
        return "2weapon"
    elseif s == "ranged_weapon" then
        return "ranged"
    else
        return s
    end
end

--- Format a number with comma separators.
-- @param number number or string
-- @return string formatted number
function M.format_number(number)
    local str = tostring(number)
    local whole, decimal = str:match("^(-?%d+)%.?(%d*)$")
    if not whole then return str end

    local n = tonumber(whole)
    if n and (n > 999 or n < -999) then
        -- Insert commas into the integer part
        whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        -- Remove leading comma if present
        whole = whole:gsub("^,", ""):gsub("^%-,", "-")
    end

    if decimal and decimal ~= "" then
        return whole .. "." .. decimal
    else
        return whole
    end
end

--- Send a command and collect response lines matching a regex.
-- Retries on roundtime. Combines regex with RT detection.
-- @param command string game command to send
-- @param regex string|table pattern(s) to match response lines
-- @param opts table optional {silent=bool, quiet=bool}
-- @param data table the ELoot data state
-- @return table array of matching response lines
function M.get_command(command, regex, opts, data)
    opts = opts or {}
    local silent = opts.silent
    local quiet = opts.quiet or false

    if data and data.settings and data.settings.debug then
        silent = nil
        quiet = false
    end

    local rt_pattern = "Roundtime: %d+ [Ss]ec"
    local rt_pattern2 = "%.%.%.wait %d+ [Ss]ec"

    -- Build combined patterns table
    local patterns = {}
    if type(regex) == "table" then
        for _, p in ipairs(regex) do
            table.insert(patterns, p)
        end
    elseif type(regex) == "string" then
        table.insert(patterns, regex)
    end
    table.insert(patterns, rt_pattern)
    table.insert(patterns, rt_pattern2)

    local lines
    while true do
        -- Issue the command and collect matching lines
        lines = {}
        local result = dothistimeout(command, 3, patterns)
        if result then
            table.insert(lines, result)
        end

        -- Collect additional lines that match
        while true do
            local line = get_noblock()
            if not line then break end
            for _, pat in ipairs(patterns) do
                if string.find(line, pat) then
                    table.insert(lines, line)
                    break
                end
            end
        end

        M.msg({type = "debug", text = "command: " .. command .. " | lines - " .. table.concat(lines, ", ")}, data)

        -- Check if any line had roundtime; if so, wait and retry
        local has_rt = false
        for _, l in ipairs(lines) do
            if string.find(l, rt_pattern) or string.find(l, rt_pattern2) then
                has_rt = true
                break
            end
        end

        if has_rt then
            M.wait_rt()
        else
            break
        end
    end

    return lines
end

--- Simplified command + single response capture.
-- Sends a command, waits for a matching response. Retries on roundtime.
-- @param command string
-- @param regex string|table|nil pattern(s) to match (nil matches anything)
-- @param data table the ELoot data state (optional, for debug logging)
-- @return string|nil the matched response line
function M.get_res(command, regex, data)
    M.msg({type = "debug", text = "command: " .. command}, data)

    local rt_pattern = "Roundtime: %d+ [Ss]ec"
    local rt_pattern2 = "%.%.%.wait %d+ [Ss]ec"
    local rt_pattern3 = "Wait %d+ [Ss]ec"
    local itch_pattern = "An uncontrollable urge to scratch the rash"

    local patterns = {}
    if type(regex) == "table" then
        for _, p in ipairs(regex) do table.insert(patterns, p) end
    elseif type(regex) == "string" then
        table.insert(patterns, regex)
    else
        table.insert(patterns, ".")  -- match anything
    end
    table.insert(patterns, rt_pattern)
    table.insert(patterns, rt_pattern2)
    table.insert(patterns, rt_pattern3)
    table.insert(patterns, itch_pattern)

    local result
    while true do
        result = dothistimeout(command, 3, patterns)
        if not result then break end

        if string.find(result, rt_pattern) or string.find(result, rt_pattern2)
           or string.find(result, rt_pattern3) or string.find(result, itch_pattern) then
            M.wait_rt()
        else
            break
        end
    end

    return result
end

--- Display formatted output message.
-- Supports type-based coloring: yellow, orange, teal, green, plain, debug, info, error.
-- @param opts table {type=string, text=string, space=boolean}
-- @param data table the ELoot data state (for debug checks)
function M.msg(opts, data)
    opts = opts or {}
    local msg_type = opts.type or "yellow"
    local text = tostring(opts.text or "")
    local space = opts.space or false

    -- Skip debug messages unless debugging is enabled
    if msg_type == "debug" then
        if data and data.settings then
            if not data.settings.debug and not data.settings.debug_file then
                return
            end
        else
            return
        end
    end

    if space then respond("") end

    if msg_type == "debug" then
        -- Debug output: monospace
        if data and data.settings and data.settings.debug then
            respond("[eloot-debug] " .. text)
        end
    elseif msg_type == "info" then
        respond("[eloot] " .. text)
    elseif msg_type == "error" then
        respond("[eloot-ERROR] " .. text)
    else
        -- yellow, orange, teal, green, plain, etc.
        respond("[eloot] " .. text)
    end

    if space then respond("") end

    -- File-based debug logging
    if data and data.settings and data.settings.debug_file and data.debug_logger then
        data.debug_logger.log(text)
    end
end

--- Display full help text for the script.
function M.help()
    local name = Script.name or "eloot"
    local prefix = ";" -- lich char

    respond("")
    respond("========================================")
    respond("  *** Mark ANYTHING you don't want to lose. " .. M.capitalize_words(name) .. " is not perfect! ***")
    respond("========================================")
    respond("")
    respond("  Command                                  Description")
    respond("  -------                                  -----------")
    respond("  " .. prefix .. name .. " setup                      UI configuration tool")
    respond("")
    respond("  " .. prefix .. name .. "                            Loots items/creatures")
    respond("  " .. prefix .. name .. " ground                     Loots open boxes on the ground")
    respond("  " .. prefix .. name .. " sell                       Sells loot based on UI options")
    respond("  " .. prefix .. name .. " sell alchemy_mode          Doesn't sell alchemy reagents")
    respond("  " .. prefix .. name .. " deposit                    Deposits coins and notes")
    respond("")
    respond("  " .. prefix .. name .. " pool                       Only does the locksmith pool")
    respond("  " .. prefix .. name .. " pool deposit               Only deposits boxes")
    respond("  " .. prefix .. name .. " pool return                Only returns boxes")
    respond("")
    respond("  --- Command Line Options ---")
    respond("  " .. prefix .. name .. " --sellable <categories>    Items matching GameObj sellable categories")
    respond("  " .. prefix .. name .. " --type <things>            Items matching GameObj types")
    respond("  " .. prefix .. name .. " --sell <items>             Specific items")
    respond("")
    respond("  --- Hoarding ---")
    respond("  " .. prefix .. name .. " list <gem/reagent>         Lists hoarded inventory")
    respond("  " .. prefix .. name .. " reset <gem/reagent>        Resets hoarded inventory")
    respond("  " .. prefix .. name .. " deposit <gem/reagent>      Deposits item(s) into hoard")
    respond("  " .. prefix .. name .. " raid <gem/reagent> <item> x<amount>  Raids hoard for item(s)")
    respond("  " .. prefix .. name .. " bounty                     Raids hoard for bounty gems")
    respond("")
    respond("  --- Troubleshooting ---")
    respond("  " .. prefix .. name .. " debug                      Toggles debugging on or off")
    respond("  " .. prefix .. name .. " debug file                 Toggles logging to a file on or off")
    respond("  " .. prefix .. name .. " list                       Lists script settings")
    respond("  " .. prefix .. name .. " test                       Lists variables and their values")
    respond("")
    respond("  *** Mark ANYTHING you don't want to lose. " .. M.capitalize_words(name) .. " is not perfect! ***")
    respond("========================================")
    respond("")
end

--- Kill the sorter script if running, and restart it when eloot exits.
function M.manage_sorter()
    if running("sorter") then
        Script.kill("sorter")
        before_dying(function()
            Script.run("sorter")
        end)
    end
end

--- Wait for roundtime and cast roundtime to expire.
function M.wait_rt()
    pause(0.2)
    waitcastrt()
    waitrt()
    pause(0.2)
end

--- Word-wrap text to a given width.
-- @param text string
-- @param width number (default 60)
-- @return string wrapped text
function M.word_wrap(text, width)
    width = width or 60
    if not text then return "" end
    text = tostring(text)

    local result = {}
    local line = ""
    for word in text:gmatch("%S+") do
        if #line + #word + 1 > width then
            table.insert(result, line)
            line = word
        else
            if line == "" then
                line = word
            else
                line = line .. " " .. word
            end
        end
    end
    if line ~= "" then
        table.insert(result, line)
    end
    return table.concat(result, "\n")
end

--- Rate-limiting helper. Returns true if enough time has passed since
-- the last call to this method with the given method_name.
-- @param method_name string identifier for the rate-limited action
-- @param gap number minimum seconds between calls
-- @param data table the ELoot data state
-- @return boolean true if enough time has passed (or first call)
function M.time_between(method_name, gap, data)
    local current_time = os.time()

    if data.last_called[method_name] then
        local time_diff = current_time - data.last_called[method_name]
        if time_diff < gap then
            return false
        end
    end

    data.last_called[method_name] = current_time
    return true
end

--- Log an unlootable item and add it to the settings list.
-- @param item table GameObj item
-- @param data table the ELoot data state
function M.unlootable(item, data)
    M.msg({type = "debug", text = "item: " .. tostring(item and item.name or item)}, data)

    if not data.settings.log_unlootables then return end
    if not item or not item.type then return end
    -- Only log items with nil type (truly unrecognized)
    if item.type ~= nil then return end

    M.msg({type = "info", text = " " .. item.name .. " was not lootable, adding to list."}, data)
    table.insert(data.settings.unlootable, item.name)
    -- Caller is responsible for calling save_profile()
end

--- Debug test output: dump settings, sacks, disk, contents, ready list, etc.
-- @param data table the ELoot data state
-- @param debug boolean if true, return output as string instead of responding
-- @return string|nil formatted table output if debug is true
function M.test(data, debug)
    local lines = {}
    local function add(text) table.insert(lines, text) end

    add("========================================")
    add("  " .. (Script.name or "eloot") .. " v" .. tostring(data.version or "?"))
    add("========================================")
    add("")

    add("  *** Settings ***")
    add("  ----------------")
    if data.settings then
        for k, v in pairs(data.settings) do
            local val
            if type(v) == "table" then
                val = table.concat(v, ", ")
            else
                val = tostring(v)
            end
            add("  " .. tostring(k) .. " = " .. M.word_wrap(val))
        end
    end
    add("")

    add("  *** Disk ***")
    add("  ------------")
    if data.disk then
        add("  ID: " .. tostring(data.disk.id) .. "  Name: " .. tostring(data.disk.name))
    else
        add("  (no disk)")
    end
    add("")

    add("  *** Full Disk/Sack Check ***")
    add("  ----------------------------")
    local disk_full_parts = {}
    for k, v in pairs(data.disk_full) do
        table.insert(disk_full_parts, k .. "=" .. tostring(v))
    end
    add("  Disk Full: " .. table.concat(disk_full_parts, ", "))
    local sack_full_names = {}
    for _, s in ipairs(data.sacks_full) do
        table.insert(sack_full_names, s.name or tostring(s))
    end
    add("  Sacks Full: " .. table.concat(sack_full_names, ", "))
    add("")

    add("  *** Coin Hand ***")
    add("  -----------------")
    if data.coin_hand then
        add("  Coin Hand: " .. tostring(data.coin_hand.id) .. "  " .. tostring(data.coin_hand.name))
    else
        add("  (no coin hand)")
    end
    if data.coin_container then
        add("  Coin Container: " .. tostring(data.coin_container.id) .. "  " .. tostring(data.coin_container.name))
    else
        add("  (no coin container)")
    end
    add("")

    add("========================================")

    local output = table.concat(lines, "\n")
    if debug then
        return output
    else
        respond("")
        for _, l in ipairs(lines) do
            respond(l)
        end
        respond("")
    end
end

-- ---------------------------------------------------------------------------
-- Game utility methods (lines 2554-3158)
-- ---------------------------------------------------------------------------

--- Phase a box using Spell 704 (Phase).
-- Only phases boxes that aren't enruned/mithril and if the spell is known/affordable.
-- @param box table GameObj box
-- @param data table the ELoot data state
function M.box_phase(box, data)
    if not box or not box.type then return end
    if not string.find(box.type, "box") then return end
    if box.name and string.find(box.name:lower(), "enruned") then return end
    if box.name and string.find(box.name:lower(), "mithril") then return end
    if not data.settings.loot_phase then return end
    if not Spell[704].known then return end
    if not Spell[704].affordable then return end

    while true do
        local cast_result = Spell[704].cast("at #" .. tostring(box.id))
        if not cast_result or not string.find(cast_result, "Spell Hindrance for") then
            break
        end
        if not Spell[704].affordable then break end
    end
end

--- Unphase a box (drop it so it solidifies, then pick it up).
-- @param box table GameObj box
-- @param data table the ELoot data state
-- @return table|nil the box GameObj after unphasing
function M.box_unphase(box, data)
    local lines = M.get_command("look at #" .. tostring(box.id), {"You see"}, {silent = true, quiet = true}, data)

    local is_shifting = false
    for _, line in ipairs(lines) do
        if string.find(line:lower(), "shifting") then
            is_shifting = true
            break
        end
    end
    if not is_shifting then return box end

    dothistimeout("drop #" .. tostring(box.id), 3, {"flickers in and out of existence"})
    M.wait_rt()

    M.get_command("glance hands", {"<right", "<left"}, {silent = true, quiet = true}, data)

    -- Find the box in either hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and rh.type and string.find(rh.type, "box") then
        return rh
    elseif lh and lh.type and string.find(lh.type, "box") then
        return lh
    end
    return nil
end

--- Change combat stance.
-- @param new_stance number target stance value (0-100)
-- @param data table the ELoot data state
function M.change_stance(new_stance, data)
    M.msg({type = "debug", text = "new_stance: " .. tostring(new_stance)}, data)

    -- Don't change stance if frenzied or dead
    if Effects and Effects.Debuffs and Effects.Debuffs.active and Effects.Debuffs.active("Frenzy") then
        return
    end
    if dead and dead() then return end

    -- Already at or above target stance
    if Char.stance_value and Char.stance_value >= new_stance then return end
    -- If requesting defensive (100), accept guarded (80) or higher
    if new_stance == 100 and Char.stance_value and Char.stance_value >= 80 then return end

    local stances = {
        [0]   = "offensive",
        [20]  = "advanced",
        [40]  = "forward",
        [60]  = "neutral",
        [80]  = "guarded",
        [100] = "defensive",
    }

    local cmd
    -- Check for Stance Perfection and non-standard values
    local standard_stances = {[0]=true, [20]=true, [40]=true, [60]=true, [80]=true, [100]=true}
    if CMan and CMan.available and CMan.available("Stance Perfection") and not standard_stances[new_stance] then
        cmd = "cman stance " .. tostring(new_stance)
    elseif stances[new_stance] then
        cmd = "stance " .. stances[new_stance]
    else
        cmd = "stance defensive"
    end

    local expiry = os.time() + 2
    while true do
        if Char.stance_value == new_stance then break end

        local res = dothistimeout(cmd, 2, {"You are now", "You move into", "Roundtime", "wait", "Your rage causes you"})
        if res and (string.find(res, "Roundtime: (%d+)") or string.find(res, "wait (%d+)")) then
            local rt_secs = tonumber(string.match(res, "Roundtime: (%d+)") or string.match(res, "wait (%d+)"))
            if rt_secs and rt_secs > 1 then
                pause(rt_secs - 1)
            end
            expiry = os.time() + 2
        elseif os.time() > expiry then
            break
        else
            break
        end
        pause(0.5)
    end
end

--- Handle cursed items: cast 315 (Remove Curse) or use eonake gauntlet.
-- @param obj table GameObj the cursed item
-- @param data table the ELoot data state
-- @return boolean true if the curse was handled (or item wasn't cursed)
function M.decurse(obj, data)
    if not obj or not obj.type or not string.find(obj.type, "cursed") then
        return true
    end

    if not data.settings.loot_types then return false end
    local has_cursed = false
    for _, t in ipairs(data.settings.loot_types) do
        if t == "cursed" then has_cursed = true; break end
    end
    if not has_cursed then return false end

    -- Try mana pulse if 315 is known but not affordable
    if Spell[315].known and not Spell[315].affordable then
        local mana_patterns = {
            "An invigorating rush of mana pulses through you",
            "You are too mentally fatigued to attempt this ability",
            "You're already at full mana",
            "Your mana control skills are not yet advanced",
        }
        dothistimeout("mana pulse", 2, mana_patterns)
    end

    -- Still can't afford it after mana pulse
    if Spell[315].known and not Spell[315].affordable then
        M.msg({type = "info", text = "** " .. obj.name .. " is cursed and you don't have enough mana to cast 315.", space = true}, data)
        return false
    end

    -- Cast 315
    if Spell[315].known and Spell[315].affordable then
        Spell[315].cast("at #" .. tostring(obj.id))
        return true
    end

    -- Try eonake gauntlet
    if data.gauntlet then
        local lines = M.get_command("look #" .. tostring(data.gauntlet.id),
            {"You are currently wearing the eonake gauntlet"},
            {silent = true, quiet = true}, data)

        local gauntlet_hand = nil
        for _, l in ipairs(lines) do
            local hand = string.match(l, "(right) hand") or string.match(l, "(left) hand")
            if hand then
                gauntlet_hand = hand
                break
            end
        end

        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()

        if rh and rh.name == "Empty" then
            if gauntlet_hand == "right" then return true end
            if gauntlet_hand == "left" then
                M.get_res("remove #" .. tostring(data.gauntlet.id), "You slip the gauntlet from", data)
                if not (rh and rh.id == data.gauntlet.id) then
                    M.get_res("swap", "You swap", data)
                end
                M.get_res("wear #" .. tostring(data.gauntlet.id), "You slip the eonake gauntlet over", data)
                return true
            end
        end

        if lh and lh.name == "Empty" then
            if gauntlet_hand == "left" then return true end
            if gauntlet_hand == "right" then
                M.get_res("remove #" .. tostring(data.gauntlet.id), "You slip the gauntlet from", data)
                if not (lh and lh.id == data.gauntlet.id) then
                    M.get_res("swap", "You swap", data)
                end
                M.get_res("wear #" .. tostring(data.gauntlet.id), "You slip the eonake gauntlet over", data)
                return true
            end
        end
    end

    return false
end

--- Find all boxes in containers and disk.
-- Opens containers, checks for box-type items, and loots open boxes.
-- @param data table the ELoot data state
-- @param set_selling_containers function reference to ELoot.set_selling_containers
-- @param inventory_module table reference to the Inventory module
-- @param loot_module table reference to the Loot module (for box_loot)
-- @return table array of box GameObj items
function M.find_boxes(data, set_selling_containers, inventory_module, loot_module)
    local box_sacks = set_selling_containers({type = "box"})

    M.msg({type = "debug", text = "box_sacks: " .. tostring(#box_sacks)}, data)

    local items = {}
    local checked_containers = {}

    for _, sack in ipairs(box_sacks) do
        if sack and not checked_containers[sack.id] then
            checked_containers[sack.id] = true
            inventory_module.open_single_container(sack)
            if sack.contents then
                for _, obj in ipairs(sack.contents) do
                    if obj.type and string.find(obj.type, "box") then
                        table.insert(items, obj)
                    end
                end
            end
        end
    end

    -- Check disk
    if data.settings.use_disk then
        M.wait_rt()
        M.wait_for_disk(data)
        if data.disk then
            inventory_module.open_single_container(data.disk)
            if data.disk.contents then
                for _, obj in ipairs(data.disk.contents) do
                    if obj.type and string.find(obj.type, "box") then
                        table.insert(items, obj)
                    end
                end
            end
        end
    end

    M.msg({type = "debug", text = "box_list before: " .. tostring(#items)}, data)

    -- Deduplicate by id
    local seen_ids = {}
    local box_list = {}
    for _, item in ipairs(items) do
        if not seen_ids[item.id] then
            seen_ids[item.id] = true
            table.insert(box_list, item)
        end
    end

    M.msg({type = "debug", text = "box_list after: " .. tostring(#box_list)}, data)

    -- Remove empty boxes, loot open ones
    local final_list = {}
    for _, box in ipairs(box_list) do
        if box.contents and #box.contents > 0 then
            local lines = M.get_command("look in #" .. tostring(box.id),
                {"<container", "That is closed", "You see the shifting form"},
                {silent = true, quiet = true}, data)

            local is_open = false
            for _, line in ipairs(lines) do
                if string.find(line:lower(), "in the") or string.find(line:lower(), "there is nothing") then
                    is_open = true
                    break
                end
            end

            if is_open then
                -- Box is open and has contents: loot it
                if box.contents and #box.contents > 0 then
                    if not M.in_hand(box) then
                        inventory_module.drag(box)
                    end
                    if loot_module and loot_module.box_loot then
                        loot_module.box_loot(box)
                    end
                end
                -- Don't add to final list (already looted)
            else
                table.insert(final_list, box)
            end
        end
    end

    return final_list
end

--- Find a trash receptacle in the current room.
-- @param data table the ELoot data state
-- @return table|nil GameObj-like table {id, noun, name} or nil
function M.find_trash(data)
    local lines = M.get_command("trash",
        {"You could discard items", "You do not notice"},
        {silent = true, quiet = true}, data)

    -- Check for no trash receptacle
    for _, line in ipairs(lines) do
        if string.find(line, "You do not notice a trash receptacle here") then
            return nil
        end
    end

    -- Parse the trash container from XML
    for _, line in ipairs(lines) do
        local exist, noun, name = string.match(line,
            'You could discard items in .- exist="(%-?%d+)" noun="(.-)">(.-)<')
        if exist then
            return {id = exist, noun = noun, name = name}
        end
    end

    return nil
end

--- Check if an item is in either hand.
-- @param obj table GameObj with .id field
-- @return boolean
function M.in_hand(obj)
    if not obj then return false end
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local rh_id = rh and rh.id
    local lh_id = lh and lh.id
    return obj.id == rh_id or obj.id == lh_id
end

--- Find the locksmith pool NPC worker in the current room.
-- Tries up to 20 times with brief pauses.
-- @param data table the ELoot data state
-- @return table|nil GameObj of the worker NPC
function M.find_worker(data)
    local worker = nil

    -- Check for a tag-based NPC name
    local name_from_tag = nil
    local current = Room.current()
    if current and current.tags then
        for _, tag in ipairs(current.tags) do
            local npc_name = string.match(tag, "^meta:boxpool:npc:(.+)$")
            if npc_name then
                name_from_tag = npc_name
                break
            end
        end
    end

    local search_names
    if name_from_tag then
        search_names = {name_from_tag}
    else
        search_names = {"worker", "trickster", "Jahck", "woman", "attendant", "gnome", "merchant", "dwarf"}
    end

    for attempt = 1, 20 do
        local npcs = GameObj.npcs()
        for _, obj in ipairs(npcs) do
            for _, nm in ipairs(search_names) do
                if string.find(obj.name, nm) then
                    worker = obj
                    break
                end
            end
            if worker then break end
        end
        if worker then break end

        -- Try looking to refresh room
        M.get_command("look", {"<resource picture"}, {silent = true, quiet = true}, data)
        pause(0.1)
    end

    if not worker then
        M.msg({type = "info", text = " Failed to find the locksmith pool NPC"}, data)
        M.msg({type = "info", text = " Update your map db; ;repository download-mapdb"}, data)
        M.msg({type = "info", text = " If the error persists then report this to Elanthia-Online"}, data)
        error("Failed to find locksmith pool NPC")
    end

    M.msg({type = "debug", text = "worker: " .. tostring(worker.name)}, data)
    return worker
end

--- Check if a room is in Four Winds Isle / Mist Harbor.
-- @param room table room object with .location field
-- @return boolean
function M.fwi(room)
    if not room or not room.location then return false end
    return string.find(room.location, "Four Winds") ~= nil
        or string.find(room.location, "Mist Harbor") ~= nil
        or string.find(room.location, "Western Harbor") ~= nil
end

--- Handle returning from Four Winds Isle.
-- Uses the FWI trinket to return to the mainland.
-- @param data table the ELoot data state
function M.fwi_return(data)
    local current_town = Room.find_nearest_by_tag and Room.find_nearest_by_tag("town")
    local town_id = current_town and current_town.id

    if town_id == 3668 then
        if not UserVars.mapdb_fwi_trinket then
            M.msg({type = "yellow", text = "  Please set your FWI trinket in go2 setup."}, data)
            error("FWI trinket not set")
        end

        M.go2(3669, data)

        if not UserVars.mapdb_fwi_return_room then
            local trinket_obj = GameObj[UserVars.mapdb_fwi_trinket]
            local worn = trinket_obj ~= nil
            if not worn then
                fput("get my " .. UserVars.mapdb_fwi_trinket)
            end
            local trinket = GameObj[UserVars.mapdb_fwi_trinket]
            if trinket then
                fput("turn #" .. tostring(trinket.id))
            end
            if not worn then
                fput("stow my " .. UserVars.mapdb_fwi_trinket)
            end
        else
            M.go2(UserVars.mapdb_fwi_return_room, data)
        end
    end
end

--- Check if the account is free-to-play.
-- @param data table the ELoot data state
-- @return boolean
function M.f2p(data)
    if GameState.game == "GST" then return false end
    if not data.account_type then return false end
    return string.find(data.account_type:lower(), "f2p") ~= nil
        or string.find(data.account_type:lower(), "free") ~= nil
end

--- Navigate to a destination using go2.
-- Handles FWI routing and urchin guide usage.
-- @param place string|number destination (tag name or room ID)
-- @param data table the ELoot data state
function M.go2(place, data)
    M.msg({type = "debug", text = "place: " .. tostring(place)}, data)

    if hidden and hidden() then fput("unhide") end
    if invisible and invisible() then fput("unhide") end

    -- FWI routing: if place is a string and sell_fwi is set, prefer FWI destinations
    if type(place) == "string" and data and data.settings and data.settings.sell_fwi then
        local rooms = Map.tags and Map.tags(place) or {}
        for _, room_id in ipairs(rooms) do
            local room = Map.find_room and Map.find_room(room_id)
            if room and M.fwi(room) then
                place = room_id
                break
            end
        end
    end

    -- Already at destination
    local current_id = Room.id
    if current_id == place then return end
    local current = Room.current()
    if current and current.tags then
        for _, tag in ipairs(current.tags) do
            if tag == place then return end
        end
    end

    if current_id == nil then
        M.msg({type = "error", text = " unknown room location"}, data)
    end

    -- Try urchin guide for string destinations
    if type(place) == "string" and data and data.settings
       and UserVars and UserVars.mapdb_use_urchins
       and UserVars.mapdb_urchins_expire and UserVars.mapdb_urchins_expire > 0
       and GameState.game ~= "GSIV" then

        -- Check we're not in the Hinterwilds
        local loc = current and current.location or ""
        if not string.find(loc, "the Hinterwilds") then
            -- Remap some destination names for urchin usage
            local urchin_place = place
            if place == "locksmith pool" then urchin_place = "locksmithpool"
            elseif place == "pawnshop" then urchin_place = "pawn"
            elseif place == "consignment" then urchin_place = "alchemy"
            end

            -- Leave nexus first
            if current and current.tags then
                for _, tag in ipairs(current.tags) do
                    if string.find(tag, "nexus") then
                        Script.run("go2", "town --disable-confirm")
                        break
                    end
                end
            end

            local result = dothistimeout("urchin guide " .. urchin_place, 3, data.urchin_msg)
            if result and string.find(result, "You currently have no access to the urchin") then
                UserVars.mapdb_use_urchins = false
                Script.run("go2", tostring(place) .. " --disable-confirm")
            elseif not result then
                M.msg({type = "error", text = " Unknown result from urchin guide usage."}, data)
            end
            return
        end
    end

    -- Standard go2
    Script.run("go2", tostring(place) .. " --disable-confirm")
end

--- Deposit a note at the nearest bank, then return.
-- @param data table the ELoot data state
function M.deposit_note(data)
    -- Find a note in hand
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local note = nil
    if rh and rh.noun and string.find(rh.noun, "^note$") or (rh and rh.noun and string.find(rh.noun, "^scrip$")) or (rh and rh.noun and string.find(rh.noun, "^chit$")) then
        note = rh
    elseif lh and lh.noun and (string.find(lh.noun, "^note$") or string.find(lh.noun, "^scrip$") or string.find(lh.noun, "^chit$")) then
        note = lh
    end
    if not note then return end

    local current_room = Room.id

    -- Navigate to nearest bank
    M.go2("bank", data)

    fput("deposit note")

    -- Wait for the note to leave our hands
    for _ = 1, 20 do
        if not M.in_hand(note) then break end
        pause(0.1)
    end

    M.go2(current_room, data)
end

--- Read the value of a note in hand.
-- @param data table the ELoot data state
-- @return number silver value of the note (0 if none found)
function M.read_note(data)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local note = nil

    for _, hand in ipairs({rh, lh}) do
        if hand and hand.noun then
            if hand.noun == "note" or hand.noun == "scrip" or hand.noun == "chit" then
                note = hand
                break
            end
        end
    end
    if not note then return 0 end

    local line = M.get_res("read #" .. tostring(note.id), "Hold in right hand to use", data)
    if line then
        local value = string.match(line, "has a value of (.-) silver and reads")
        if value then
            return tonumber(value:gsub(",", "")) or 0
        end
    end

    return 0
end

--- Check current silver on hand.
-- @param data table the ELoot data state
-- @return number silver amount
function M.silver_check(data)
    local wealth_pattern = "^You have (%S+) silver with you"
    local lines = M.get_command("wealth quiet", {wealth_pattern}, {silent = true, quiet = true}, data)
    local coins = 0

    local wealth = table.concat(lines, " ")
    -- Handle "but one" = 1, "no" = 0
    wealth = wealth:gsub("but one", "1")
    local amount = string.match(wealth, "You have (%S+) silver with you")
    if amount then
        if amount == "no" then
            coins = 0
        else
            coins = tonumber(amount:gsub(",", "")) or 0
        end
    end

    M.msg({type = "debug", text = "coins: " .. tostring(coins)}, data)
    return coins
end

--- Full silver deposit cycle.
-- Handles coin hands, sharing, banking, F2P limits, notes.
-- @param data table the ELoot data state
-- @param deposit_bag boolean whether to process the coin hand/bag
-- @param inventory_module table reference to the Inventory module
function M.silver_deposit(data, deposit_bag, inventory_module)
    M.msg({type = "debug"}, data)

    -- Handle coin hand deposit
    if data.coin_hand and deposit_bag and data.settings.sell_deposit_coinhand then
        if data.coin_container and inventory_module then
            inventory_module.free_hand()
            inventory_module.open_single_container(data.coin_container)
            inventory_module.drag(data.coin_hand)
        end

        if not data.coin_bag and not data.gambling_kit then
            fput("open #" .. tostring(data.coin_hand.id))
            M.wait_rt()
        else
            while true do
                local look_lines = M.get_command("look in #" .. tostring(data.coin_hand.id),
                    {"Inside the", "There is nothing", "That is closed"},
                    {silent = true, quiet = true}, data)

                local is_closed = false
                local has_coins = false
                local has_gambling = false
                local is_empty = false

                for _, l in ipairs(look_lines) do
                    if string.find(l:lower(), "that is closed") then is_closed = true end
                    if string.find(l, "approximately [,%d]+ silver coins") or string.find(l, "Get a job") then has_coins = true end
                    if string.find(l, "There are [,%d]+ silvers scattered") then has_gambling = true end
                    if string.find(l, "There is nothing in there") then is_empty = true end
                end

                if is_closed then
                    M.get_command("open #" .. tostring(data.coin_hand.id), data.silent_open, nil, data)
                    -- retry (continue loop)
                elseif has_coins and data.coin_bag then
                    M.get_res("get coins from #" .. tostring(data.coin_bag.id), "You reach into your", data)
                    data.coin_bag_full = false
                    M.wait_rt()
                    break
                elseif has_gambling and data.gambling_kit then
                    M.get_res("gather #" .. tostring(data.gambling_kit.id), "You dig inside", data)
                    data.gambling_kit_full = false
                    M.wait_rt()
                    break
                elseif is_empty then
                    data.coin_bag_full = false
                    data.gambling_kit_full = false
                    break
                else
                    break
                end
            end
        end

        -- Return coin hand to container
        if data.coin_container and inventory_module then
            inventory_module.store_item(data.coin_container, data.coin_hand)
        end
    end

    local current_silvers = M.silver_check(data)
    local keep_silvers = math.max(tonumber(data.settings.sell_keep_silver) or 0, 0)
    local share_silvers = current_silvers - keep_silvers

    -- Share silvers
    if data.settings.sell_share_silvers and share_silvers > 0 then
        fput("share " .. tostring(share_silvers))
    end

    -- Use coin hand if we have it and don't want to deposit the coins
    if not data.settings.sell_deposit_coinhand then
        M.use_coin_hand(data)
    end

    -- Head over to the bank if something to do
    current_silvers = M.silver_check(data)
    if current_silvers == keep_silvers then return end

    M.go2("bank", data)

    if not M.f2p(data) then
        if GameState.room_name == "[Pinefar, Depository]" then
            dothistimeout("give banker " .. tostring(current_silvers) .. " silver", 2, data.deposit_regex)
        else
            dothistimeout("deposit all", 2, data.deposit_regex)
        end
    else
        -- F2P bank deposit (limited balance)
        while true do
            local bank_lines = M.get_command("bank account", {"You currently have an account"}, {silent = true, quiet = true}, data)

            local silver_balance = 0
            local silver_max = 0
            for _, line in ipairs(bank_lines) do
                local bal = string.match(line, "in the amount of ([%d,]+) silver")
                if bal then silver_balance = tonumber(bal:gsub(",", "")) or 0 end
                local mx = string.match(line, "a maximum of ([%d,]+) silvers")
                if mx then silver_max = tonumber(mx:gsub(",", "")) or 0 end
            end

            current_silvers = M.silver_check(data)

            if (silver_balance + current_silvers) < silver_max then
                if current_silvers > 0 then
                    local combined = {}
                    for _, p in ipairs(data.deposit_regex) do table.insert(combined, p) end
                    table.insert(combined, "you don't have access")
                    local result = dothistimeout("deposit " .. tostring(current_silvers), 2, combined)
                    if result and string.find(result:lower(), "you don't have access") then
                        M.msg({type = "info", text = " You don't have a bank in this town. Exiting..."}, data)
                        error("No bank access")
                    end
                end
                break
            else
                local deposit_size = silver_max - silver_balance
                dothistimeout("deposit " .. tostring(deposit_size), 2, data.deposit_regex)

                current_silvers = M.silver_check(data)

                local note_size
                if current_silvers >= 10000 then
                    note_size = silver_max
                else
                    note_size = silver_max - (10000 - current_silvers)
                end
                dothistimeout("withdraw " .. tostring(note_size), 2, {"The teller"})
                -- Find and stow the note
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                local note_obj = nil
                for _, hand in ipairs({rh, lh}) do
                    if hand and hand.noun and (hand.noun == "note" or hand.noun == "scrip" or hand.noun == "chit") then
                        note_obj = hand
                        break
                    end
                end
                if note_obj and inventory_module then
                    inventory_module.single_drag(note_obj)
                end
            end
        end
    end

    -- Withdraw keeper silvers and stow note
    if GameState.room_name == "[Pinefar, Depository]" then
        if keep_silvers > 0 then
            dothistimeout("ask banker for " .. tostring(keep_silvers) .. " silvers", 2, data.withdraw_regex)
        end
    else
        if keep_silvers > 0 then
            dothistimeout("withdraw " .. tostring(keep_silvers), 2, data.withdraw_regex)
        end
    end

    -- Stow any note we got
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    for _, hand in ipairs({rh, lh}) do
        if hand and hand.noun and (hand.noun == "note" or hand.noun == "scrip" or hand.noun == "chit") then
            if inventory_module then
                inventory_module.single_drag(hand)
            end
            break
        end
    end
    M.wait_rt()
end

--- Withdraw silver for F2P accounts, handling note deposits as needed.
-- @param amount number silver to withdraw
-- @param data table the ELoot data state
-- @param inventory_module table reference to the Inventory module
function M.f2p_silver_withdraw(amount, data, inventory_module)
    local balance = 0
    local lines = M.get_command("check balance", {"The teller", "A prim teller"}, {silent = true, quiet = true}, data)
    for _, line in ipairs(lines) do
        local bal = string.match(line, "Your balance is currently at ([%d,]+)")
        if bal then balance = tonumber(bal:gsub(",", "")) or 0 end
    end

    if balance >= amount then
        dothistimeout("withdraw " .. tostring(amount) .. " silver", 2, {"The teller"})
        return
    end

    -- Need to deposit notes to cover the withdrawal
    -- (Assumes StowList is available via inventory_module)
    for _ = 1, 5 do
        -- Find a note in the default stow container
        -- This simplified version checks hands
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local note = nil
        for _, hand in ipairs({rh, lh}) do
            if hand and hand.noun and (hand.noun == "note" or hand.noun == "scrip" or hand.noun == "chit") then
                note = hand
                break
            end
        end
        if not note then break end

        -- Drain the account first
        if balance > 0 then
            dothistimeout("withdraw " .. tostring(balance) .. " silver", 2, {"The teller"})
            amount = amount - balance
            balance = 0
        end

        -- Deposit the note
        if inventory_module then inventory_module.drag(note) end
        local dep_lines = M.get_command("deposit #" .. tostring(note.id), {"You deposit", "You hand your"}, {silent = true, quiet = true}, data)
        local note_amount = 0
        for _, line in ipairs(dep_lines) do
            local na = string.match(line, "worth ([%d,]+)")
            if na then note_amount = tonumber(na:gsub(",", "")) or 0 end
        end
        if note_amount == 0 then break end

        local withdraw_amount = note_amount >= amount and amount or note_amount
        dothistimeout("withdraw " .. tostring(withdraw_amount) .. " silver", 2, {"The teller"})
        amount = amount - withdraw_amount
        if amount <= 0 then break end
    end
end

--- Standard silver withdrawal.
-- Goes to bank, deposits first if needed, then withdraws the requested amount.
-- @param amount number silver to withdraw
-- @param data table the ELoot data state
function M.silver_withdraw(amount, data)
    if M.silver_check(data) >= amount and Char.encumbrance_value and Char.encumbrance_value < 20 then
        return
    end

    M.go2("bank", data)
    M.silver_deposit(data)

    if GameState.room_name == "[Pinefar, Depository]" then
        fput("ask banker for " .. tostring(amount) .. " silvers")
    elseif M.f2p(data) then
        M.f2p_silver_withdraw(amount, data)
    else
        fput("withdraw " .. tostring(amount) .. " silvers")
    end

    if M.silver_check(data) < amount then
        M.msg({type = "info", text = " Not enough silver in current area's bank."}, data)
        error("Insufficient silver")
    end
end

--- Store silver in the coin hand container.
-- Handles coin bags, gambling kits, and plain coin hands.
-- @param data table the ELoot data state
-- @param inventory_module table reference to the Inventory module (optional)
function M.use_coin_hand(data, inventory_module)
    M.msg({type = "debug"}, data)

    if not data.coin_hand then return end
    local available_silver = M.silver_check(data)
    if available_silver <= 0 then return end

    -- Don't bother with gambling kit if we don't have enough silver
    if data.gambling_kit and available_silver < (data.settings.gambling_toss_min or 0) then
        return
    end

    -- Get the coin hand out of its container if needed
    if data.coin_container and inventory_module then
        inventory_module.free_hand()
        inventory_module.open_single_container(data.coin_container)
        inventory_module.drag(data.coin_hand)
    end

    if not data.coin_bag and not data.gambling_kit then
        -- Plain coin hand (cloak, etc.)
        dothistimeout("close #" .. tostring(data.coin_hand.id), 1, {"You feel your pockets lighten"})
    elseif (data.coin_bag and not data.coin_bag_full) or (data.gambling_kit and not data.gambling_kit_full) then
        if inventory_module then inventory_module.free_hand() end

        while true do
            local get_coins
            if data.coin_bag then
                get_coins = "put " .. tostring(available_silver) .. " silver in #" .. tostring(data.coin_bag.id)
            else
                get_coins = "toss #" .. tostring(data.gambling_kit.id)
            end

            local put_patterns = {
                "You place", "You toss",
                "There is only room", "That might work better",
                "needs to be open", "cannot find room",
                "coin .+ is already full!$",
            }
            local result = dothistimeout(get_coins, 3, put_patterns)

            if data.gambling_kit then M.wait_rt() end

            if result and (string.find(result, "That might work better if you opened") or string.find(result, "needs to be open")) then
                M.get_command("open #" .. tostring(data.coin_hand.id), data.silent_open, nil, data)
                -- retry (continue loop)
            elseif result and string.find(result, "coin .+ is already full!") then
                data.coin_bag_full = true
                break
            elseif result and string.find(result, "There is only room for") then
                local capacity = string.match(result, "There is only room for ([%d,]+) more coins")
                if capacity then
                    local cap = tonumber(capacity:gsub(",", "")) or 0
                    M.get_res("put " .. tostring(cap) .. " silver in #" .. tostring(data.coin_bag.id), "You place", data)
                end
                data.coin_bag_full = true
                break
            elseif result and string.find(result, "You cannot find room to store any more silver") then
                data.gambling_kit_full = true
                M.wait_rt()
                break
            else
                break
            end
        end
    end

    -- Return coin hand to container
    if data.coin_container and inventory_module then
        inventory_module.store_item(data.coin_container, data.coin_hand)
    end
end

--- Wait for the character's disk to arrive after room movement.
-- @param data table the ELoot data state
-- @param inventory_module table reference to the Inventory module (optional)
function M.wait_for_disk(data, inventory_module)
    M.msg({type = "debug"}, data)

    if not data.settings.use_disk then return end
    if not data.disk then return end

    local mine = Disk and Disk.mine and Disk.mine()
    local is_gone = data.disk.status and string.find(data.disk.status, "gone")

    if is_gone or not mine then
        M.msg({type = "info", text = " Waiting for your disk to arrive"}, data)

        for _ = 1, 50 do
            mine = Disk and Disk.mine and Disk.mine()
            if mine then break end
            pause(0.1)
        end
    end

    mine = Disk and Disk.mine and Disk.mine()
    if mine then
        data.disk = GameObj[mine.id]
        if inventory_module then
            inventory_module.open_single_container(data.disk)
        end
    else
        data.disk = nil
    end
end

return M
