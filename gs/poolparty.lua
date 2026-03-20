--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: poolparty
--- version: 3.0.1
--- author: elanthia-online
--- contributors: Glaves, Fulmen, Steel Talon, Licel, Selfane
--- game: gs
--- description: Locksmith pool box deposit, retrieval, and looting automation
--- tags: locksmith,pool,boxes,loot,picking
---
--- Changelog (from Lich5 poolparty_new.lic v2.1.4):
---   v3.0.1 (2026-03-20): Fix empty_hands() missing local def (runtime crash); remove
---     pre-deposit silver withdrawal (game auto-handles fees since v2.1.5); add
---     return-to-start-room for loot/deposit subcommands; fix ingotsell arg passing;
---     fix deposit_all=false branch incorrectly still depositing all silver.
---   v3.0.0 (2026-03-18): Full Revenant rewrite — no oleani-lib/slop-lib deps,
---     uses Revenant primitives (fput, dothistimeout, GameObj, Map.go2, CharSettings).
---     Disk support, plinite handling, trash/wastebin fallback, configurable tips,
---     per-character settings, full CLI.
---   v2.1.4 (Lich5): Loot option to match stow list before dumping
---   v2.1.3 (Lich5): Look-in-box option, already-unlocked handling, trickster NPC
---   v2.0.0 (Lich5): Rewrite by Steel Talon on Oleani framework
---   v1.x (Lich5): Original work by Glaves
---
--- Usage:
---   ;poolparty               - Deposit boxes, then loot finished ones
---   ;poolparty loot [n]      - Retrieve and loot up to n boxes
---   ;poolparty deposit       - Deposit boxes only
---   ;poolparty setup         - Show current settings
---   ;poolparty help          - Show all options
---
--- Configuration (toggle/set via CLI flags):
---   ;poolparty --tip-amount=25       - Set tip amount
---   ;poolparty --tip-type=percent    - Set tip type (percent or silver)
---   ;poolparty --skip-disk-wait      - Toggle disk checking
---   ;poolparty --deposit-all         - Toggle deposit all silver when done
---   ;poolparty --look-in-box         - Toggle looking in boxes before dumping
---   ;poolparty --loot-command        - Toggle loot command before dumping
---   ;poolparty --withdraw-amount=N   - Set withdrawal amount
---
--- Requires: lootsack set via ;vars set lootsack=<container>

local VERSION = "3.0.1"

--------------------------------------------------------------------------------
-- Config (per-character via CharSettings)
--------------------------------------------------------------------------------

local function load_config()
    return {
        tip_amount      = CharSettings.pp_tip_amount or "25",
        tip_type        = CharSettings.pp_tip_type or "percent",
        skip_disk_wait  = (CharSettings.pp_skip_disk_wait == "true"),
        deposit_all     = (CharSettings.pp_deposit_all == "true"),
        look_in_box     = (CharSettings.pp_look_in_box == "true"),
        loot_command    = (CharSettings.pp_loot_command == "true"),
        withdraw_amount = tonumber(CharSettings.pp_withdraw_amount) or 10000,
    }
end

local function save_config(cfg)
    CharSettings.pp_tip_amount      = tostring(cfg.tip_amount)
    CharSettings.pp_tip_type        = cfg.tip_type
    CharSettings.pp_skip_disk_wait  = tostring(cfg.skip_disk_wait)
    CharSettings.pp_deposit_all     = tostring(cfg.deposit_all)
    CharSettings.pp_look_in_box     = tostring(cfg.look_in_box)
    CharSettings.pp_loot_command    = tostring(cfg.loot_command)
    CharSettings.pp_withdraw_amount = tostring(cfg.withdraw_amount)
end

local config = load_config()

--------------------------------------------------------------------------------
-- NPC Detection
-- Matches the original Lich5 list: Gnome, Woman, Attendant, Merchant, Worker,
-- Boss, Jahck, Dwarf, Trickster, Scoundrel, Pirate
-- Room 17589 special case: only match "attendant"
--------------------------------------------------------------------------------

local NPC_PATTERNS = {
    "gnome", "woman", "attendant", "merchant", "worker",
    "boss", "jahck", "dwarf", "trickster", "scoundrel", "pirate",
}

local function find_pool_master()
    local npcs = GameObj.npcs()
    local room_id = GameState.room_id
    for _, npc in ipairs(npcs) do
        local noun_lower = string.lower(npc.noun)
        if room_id == 17589 then
            if noun_lower == "attendant" then return npc end
        else
            for _, pat in ipairs(NPC_PATTERNS) do
                if string.find(noun_lower, pat, 1, true) then
                    return npc
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Trash bin detection (from room description or loot objects)
-- Matches: barrel, bin, wastebasket, trashcan, bucket, wooden crate,
--          iron barrel, canister, wastebin
--------------------------------------------------------------------------------

local TRASH_NOUNS = {
    "barrel", "bin", "wastebasket", "trashcan", "bucket", "canister", "wastebin",
}

local function find_trash_bin()
    -- Check room description for trash keywords
    local desc = GameState.room_description or ""
    local desc_lower = string.lower(desc)
    for _, word in ipairs(TRASH_NOUNS) do
        if string.find(desc_lower, word, 1, true) then
            -- Found in description; look for matching loot object
            local loot = GameObj.loot()
            for _, obj in ipairs(loot) do
                local name_lower = string.lower(obj.name or "")
                if string.find(name_lower, word, 1, true) and obj.noun ~= "disk" then
                    return obj
                end
            end
        end
    end

    -- Fallback: check loot directly
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.noun ~= "disk" then
            local noun_lower = string.lower(obj.noun or "")
            for _, pat in ipairs(TRASH_NOUNS) do
                if string.find(noun_lower, pat, 1, true) then
                    return obj
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function msg(text)
    respond("[poolparty] " .. text)
end

-- Stow both held items. Returns true if hands are clear afterward.
local function empty_hands()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh and rh.id then fput("stow right") end
    if lh and lh.id then fput("stow left") end
end

local function clear_hands()
    multifput("sheath", "stow all")
    empty_hands()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (rh and rh.id) or (lh and lh.id) then
        msg("Unable to clear hands. Make sure you have room.")
        return false
    end
    return true
end

local function find_lootsack()
    local sack_name = UserVars.lootsack
    if not sack_name or sack_name == "" then
        msg("lootsack is not set. Use ;vars set lootsack=<container>")
        return nil
    end
    for _, obj in ipairs(GameObj.inv()) do
        if string.find(string.lower(obj.name), string.lower(sack_name), 1, true) then
            return obj
        end
    end
    msg("Could not find lootsack: " .. sack_name)
    return nil
end

local function find_disk()
    local char_name = GameState.name or ""
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        if obj.noun == "disk" and string.find(obj.name or "", char_name, 1, true) then
            return obj
        end
    end
    return nil
end

local function check_silvers()
    clear()
    put("info")
    local deadline = os.time() + 4
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            local amt = string.match(line, "Silver:%s*([%d,]+)")
            if amt then return tonumber((string.gsub(amt, ",", ""))) or 0 end
        else
            pause(0.05)
        end
    end
    return 0
end

local function navigate_to(destination)
    Map.go2(destination)
end

local function navigate_to_pool()
    navigate_to("locksmith pool")
end

local function navigate_to_bank()
    navigate_to("bank")
end

local function deposit_silver()
    local silvers = check_silvers()
    if silvers > 0 then
        navigate_to_bank()
        fput("deposit all")
    end
end

local function scan_boxes_in_container(container)
    local boxes = {}
    if not container or not container.contents then return boxes end
    for _, item in ipairs(container.contents) do
        local item_type = item.type or ""
        if string.find(item_type, "box") or (item.noun and item.noun == "plinite") then
            table.insert(boxes, item)
        end
    end
    return boxes
end

local function scan_boxes_in_hands()
    local boxes = {}
    local rh = GameObj.right_hand()
    if rh and rh.type and string.find(rh.type, "box") then
        table.insert(boxes, rh)
    end
    local lh = GameObj.left_hand()
    if lh and lh.type and string.find(lh.type, "box") then
        table.insert(boxes, lh)
    end
    return boxes
end

--------------------------------------------------------------------------------
-- Deposit Logic
--------------------------------------------------------------------------------

local function deposit_one_box(npc, tip_str)
    -- First give attempt (triggers confirmation prompt)
    local result = dothistimeout(
        "give " .. npc.noun .. " " .. tip_str .. " confirm", 5,
        "has been recorded|doesn't appear to be a box|is already open|as many boxes|You don't have enough silver"
    )
    if not result then return false, "timeout" end

    if string.find(result, "doesn't appear to be a box") then return false, "not_a_box" end
    if string.find(result, "is already open") then return false, "already_open" end
    if string.find(result, "as many boxes") then return false, "pool_full" end
    if string.find(result, "You don't have enough silver") then return false, "no_silver" end
    if string.find(result, "has been recorded") then return true, "ok" end

    return false, "unknown"
end

local function do_deposit()
    msg("** [Starting Deposit] **")
    local tip_str = config.tip_amount .. " " .. (config.tip_type == "percent" and "percent" or "")

    local npc = find_pool_master()
    if not npc then
        msg("Unable to locate the locksmith pool NPC")
        return 0
    end

    local success_count = 0
    local failed = {}

    -- Check right hand
    local rh = GameObj.right_hand()
    if rh and rh.type and string.find(rh.type, "box") then
        local ok, reason = deposit_one_box(npc, tip_str)
        if ok then
            success_count = success_count + 1
        else
            table.insert(failed, (rh.name or "unknown") .. " (" .. reason .. ")")
            if reason == "already_open" then
                local sack = find_lootsack()
                if sack then fput("put #" .. rh.id .. " in #" .. sack.id) end
            end
        end
    end

    -- Check left hand
    local lh = GameObj.left_hand()
    if lh and lh.type and string.find(lh.type, "box") then
        fput("swap")
        pause(0.3)
        local ok, reason = deposit_one_box(npc, tip_str)
        if ok then
            success_count = success_count + 1
        else
            table.insert(failed, (lh.name or "unknown") .. " (" .. reason .. ")")
            if reason == "already_open" then
                local sack = find_lootsack()
                if sack then fput("put #" .. lh.id .. " in #" .. sack.id) end
            end
        end
    end

    -- Check for disk if not skipping
    if not config.skip_disk_wait then
        local disk = find_disk()
        if disk then
            -- Scan disk for boxes
            fput("look in #" .. disk.id)
            pause(1)
            if disk.contents then
                for _, item in ipairs(disk.contents) do
                    local item_type = item.type or ""
                    if string.find(item_type, "box") or (item.noun and item.noun == "plinite") then
                        if not clear_hands() then break end
                        fput("get #" .. item.id .. " from #" .. disk.id)
                        pause(0.5)
                        local ok2, reason2 = deposit_one_box(npc, tip_str)
                        if ok2 then
                            success_count = success_count + 1
                        else
                            table.insert(failed, (item.name or "unknown") .. " (" .. reason2 .. ")")
                            fput("stow right")
                        end
                    end
                end
            end
        end
    end

    -- Scan inventory containers for boxes
    local lootsack = find_lootsack()
    if lootsack then
        fput("look in #" .. lootsack.id)
        pause(1)
        local boxes = scan_boxes_in_container(lootsack)
        for _, box in ipairs(boxes) do
            if not clear_hands() then break end
            fput("get #" .. box.id .. " from #" .. lootsack.id)
            pause(0.5)
            -- Verify we got it
            local got = GameObj.right_hand()
            if not got or got.id ~= box.id then
                msg("Failed to get box from lootsack")
            else
                local ok3, reason3 = deposit_one_box(npc, tip_str)
                if ok3 then
                    success_count = success_count + 1
                else
                    table.insert(failed, (box.name or "unknown") .. " (" .. reason3 .. ")")
                    fput("put #" .. box.id .. " in #" .. lootsack.id)
                end
            end
        end
    end

    msg("** Deposited " .. success_count .. " box(es). **")
    if #failed > 0 then
        msg("Unable to deposit " .. #failed .. " box(es):")
        for _, f in ipairs(failed) do msg("  " .. f) end
    end
    return success_count
end

--------------------------------------------------------------------------------
-- Trash box logic
--------------------------------------------------------------------------------

local function trash_box(box)
    local result = dothistimeout("trash #" .. box.id, 5,
        "you feel pleased|items attached|trash receptacle|You notice more still")
    if result then
        if string.find(result, "you feel pleased") then
            return true
        end
        if string.find(result, "items attached") or string.find(result, "You notice more still") then
            -- Items still inside, try to empty and retry
            return false
        end
        if string.find(result, "trash receptacle") then
            -- No wastebin, try to drop
            fput("drop #" .. box.id)
            pause(0.3)
            -- Check if still in hand
            local rh = GameObj.right_hand()
            if rh and rh.id == box.id then
                fput("drop #" .. box.id)
            end
            return true
        end
    end
    -- Fallback: try drop
    fput("drop #" .. box.id)
    return true
end

--------------------------------------------------------------------------------
-- Loot Logic
--------------------------------------------------------------------------------

local function loot_one_box(lootsack)
    local npc = find_pool_master()
    if not npc then return false, "no_npc" end

    local result = dothistimeout("ask " .. npc.noun .. " about return", 5,
        "here's your|don't have any boxes|empty hand|lighten your load|need to lighten")
    if not result then return false, "timeout" end
    if string.find(result, "don't have any boxes") then return false, "no_boxes" end
    if string.find(result, "empty hand") or string.find(result, "lighten") then
        return false, "hands_full"
    end

    pause(0.3)

    -- We should have a box in right hand now
    local box = GameObj.right_hand()
    if not box or not box.id then return false, "no_box_in_hand" end

    local box_type = box.type or ""
    local box_noun = box.noun or ""

    -- Plinite cores go straight to lootsack
    if box_noun == "core" then
        if lootsack then
            fput("put #" .. box.id .. " in #" .. lootsack.id)
        else
            fput("stow right")
        end
        return true, "core"
    end

    -- Open the box
    fput("open #" .. box.id)
    pause(0.3)

    -- Use silver charm if we have one (auto-appraise coins in box)
    -- This is optional but nice; ignore errors
    local charm_result = dothistimeout("point my silver charm at #" .. box.id, 3,
        "Roundtime|You point|You don't")
    if charm_result then waitrt() end

    -- Loot coins first
    fput("get coins from #" .. box.id)
    pause(0.3)

    -- Look in box before dumping (if enabled)
    if config.look_in_box then
        fput("look in #" .. box.id)
        pause(0.5)
    end

    -- Loot items matching stow list (if enabled)
    if config.loot_command then
        fput("loot #" .. box.id)
        pause(0.5)
    end

    -- Empty remaining items into lootsack
    if lootsack then
        fput("empty #" .. box.id .. " in #" .. lootsack.id)
        pause(0.5)

        -- Check for items still in box (e.g. oversized ingots)
        local rh = GameObj.right_hand()
        if rh and rh.id == box.id and rh.contents and #rh.contents > 0 then
            msg("Box still has items that won't fit:")
            for _, item in ipairs(rh.contents) do
                msg("  - " .. (item.name or "unknown"))
            end
            -- Try to get items out individually
            for _, item in ipairs(rh.contents) do
                if item.noun == "ingot" then
                    fput("get #" .. item.id .. " from #" .. box.id)
                    pause(0.3)
                    -- Try running ingotsell if available
                    if Script.exists("ingotsell") then
                        msg("Launching ingotsell for oversized ingot")
                        Script.run("ingotsell", "#" .. item.id .. " #" .. lootsack.id)
                        wait_while(function() return Script.running("ingotsell") end)
                    else
                        fput("stow left")
                    end
                end
            end
            -- Try emptying again
            fput("empty #" .. box.id .. " in #" .. lootsack.id)
            pause(0.3)
        end
    end

    -- Trash or stow the empty box
    if string.find(box_type, "box") then
        trash_box(box)
    elseif string.find(box_type, "plinite") then
        -- Plinites: pluck then trash
        fput("pluck #" .. box.id)
        pause(0.5)
        -- Check if we got a core in left hand
        local lh = GameObj.left_hand()
        if lh and lh.noun == "core" and lootsack then
            fput("put #" .. lh.id .. " in #" .. lootsack.id)
        elseif lh and lh.id then
            fput("stow left")
        end
        trash_box(box)
    else
        -- Unknown box type - move to lootsack for safety
        msg("Unknown item type from pool - storing in lootsack")
        if lootsack then
            fput("put #" .. box.id .. " in #" .. lootsack.id)
        else
            fput("stow right")
        end
    end

    return true, "ok"
end

local function do_loot(max_count)
    max_count = max_count or 100
    msg("** [Starting Loot] **")

    local lootsack = find_lootsack()
    if not lootsack then return 0 end

    fput("open #" .. lootsack.id)

    local count = 0
    local attempts = 0

    while count < max_count do
        if not clear_hands() then
            msg("Cannot clear hands. Pausing.")
            pause(3)
            attempts = attempts + 1
            if attempts >= 3 then
                msg("Too many hand-clearing failures. Stopping.")
                break
            end
        else
            attempts = 0
        end

        local ok, reason = loot_one_box(lootsack)
        if not ok then
            if reason == "no_boxes" then
                msg("Pool has no more boxes for us.")
            elseif reason == "hands_full" then
                msg("Hands full or overloaded. Trying to clear...")
                if not clear_hands() then
                    msg("Cannot clear hands. Stopping loot.")
                    break
                end
            else
                msg("Loot stopped: " .. (reason or "unknown"))
                break
            end
            break
        end
        count = count + 1
        -- Reset attempts on success
        attempts = 0
    end

    msg("** Looted " .. count .. " box(es). **")
    return count
end

--------------------------------------------------------------------------------
-- Settings display
--------------------------------------------------------------------------------

local function show_settings()
    msg("PoolParty v" .. VERSION .. " - Current Settings:")
    msg("  tip-amount:      " .. config.tip_amount)
    msg("  tip-type:        " .. config.tip_type)
    msg("  skip-disk-wait:  " .. tostring(config.skip_disk_wait))
    msg("  deposit-all:     " .. tostring(config.deposit_all))
    msg("  look-in-box:     " .. tostring(config.look_in_box))
    msg("  loot-command:    " .. tostring(config.loot_command))
    msg("  withdraw-amount: " .. tostring(config.withdraw_amount))
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    msg("PoolParty v" .. VERSION)
    msg("  Original Authors: Glaves, Fulmen, Steel Talon")
    respond("")
    msg("Commands:")
    msg("  ;poolparty               - Deposit then loot")
    msg("  ;poolparty loot [n]      - Loot up to n boxes (default 100)")
    msg("  ;poolparty deposit       - Deposit boxes only")
    msg("  ;poolparty setup         - Show current settings")
    msg("  ;poolparty help          - This help")
    respond("")
    msg("Options (toggle/set):")
    msg("  --tip-amount=N           - Tip amount (current: " .. config.tip_amount .. ")")
    msg("  --tip-type=TYPE          - percent or silver (current: " .. config.tip_type .. ")")
    msg("  --skip-disk-wait         - Toggle disk wait (current: " .. tostring(config.skip_disk_wait) .. ")")
    msg("  --deposit-all            - Toggle deposit all (current: " .. tostring(config.deposit_all) .. ")")
    msg("  --look-in-box            - Toggle look before dump (current: " .. tostring(config.look_in_box) .. ")")
    msg("  --loot-command           - Toggle loot before dump (current: " .. tostring(config.loot_command) .. ")")
    msg("  --withdraw-amount=N      - Withdrawal amount (current: " .. tostring(config.withdraw_amount) .. ")")
    respond("")
    msg("Requires: lootsack set via ;vars set lootsack=<container>")
    respond("")
end

--------------------------------------------------------------------------------
-- Arg Parsing
--------------------------------------------------------------------------------

local raw_args = Script.vars[0] or ""
local args = {}
for word in string.gmatch(raw_args, "%S+") do
    table.insert(args, word)
end

-- Process flag options first
local has_flags = false
for _, arg in ipairs(args) do
    if string.sub(arg, 1, 2) == "--" then
        has_flags = true
        local key_val = string.sub(arg, 3)
        local eq = string.find(key_val, "=")
        if eq then
            local key = string.gsub(string.sub(key_val, 1, eq - 1), "%-", "_")
            local val = string.sub(key_val, eq + 1)
            if key == "tip_amount" then
                local num = tonumber(val)
                if num and num > 0 then
                    config.tip_amount = val
                    msg("Tip amount set to " .. val)
                else
                    msg("Tip amount must be a positive number.")
                end
            elseif key == "tip_type" then
                if val == "percent" or val == "silver" then
                    config.tip_type = val
                    msg("Tip type set to " .. val)
                else
                    msg("Invalid tip type. Use 'percent' or 'silver'.")
                end
            elseif key == "withdraw_amount" then
                local num = tonumber(val)
                if num and num > 0 then
                    config.withdraw_amount = num
                    msg("Withdraw amount set to " .. tostring(num))
                else
                    msg("Withdraw amount must be a positive number.")
                end
            end
        else
            local key = string.gsub(key_val, "%-", "_")
            if key == "skip_disk_wait" then
                config.skip_disk_wait = not config.skip_disk_wait
                msg("Skip disk wait: " .. tostring(config.skip_disk_wait))
            elseif key == "deposit_all" then
                config.deposit_all = not config.deposit_all
                msg("Deposit all: " .. tostring(config.deposit_all))
            elseif key == "look_in_box" then
                config.look_in_box = not config.look_in_box
                msg("Look in box: " .. tostring(config.look_in_box))
            elseif key == "loot_command" then
                config.loot_command = not config.loot_command
                msg("Loot command: " .. tostring(config.loot_command))
            end
        end
        save_config(config)
    end
end

-- Get non-flag command
local cmd = nil
local cmd_args = {}
for _, arg in ipairs(args) do
    if string.sub(arg, 1, 2) ~= "--" then
        if not cmd then
            cmd = string.lower(arg)
        else
            table.insert(cmd_args, arg)
        end
    end
end

--------------------------------------------------------------------------------
-- Validate prereqs
--------------------------------------------------------------------------------

local function validate_prereqs()
    local sack_name = UserVars.lootsack
    if not sack_name or sack_name == "" then
        msg("lootsack has not been set. Use ;vars set lootsack=<container>")
        return false
    end
    local lootsack = find_lootsack()
    if not lootsack then
        msg("Could not find lootsack: " .. sack_name)
        return false
    end
    fput("open #" .. lootsack.id)
    return true
end

--------------------------------------------------------------------------------
-- Main Execution
--------------------------------------------------------------------------------

local ok, err = pcall(function()
    if cmd == "help" then
        show_help()

    elseif cmd == "setup" or cmd == "settings" then
        show_settings()

    elseif cmd == "loot" then
        if not validate_prereqs() then return end
        local count = tonumber(cmd_args[1]) or 100
        local start_room = GameState.room_id
        navigate_to_pool()
        do_loot(count)
        deposit_silver()
        if start_room then navigate_to(tostring(start_room)) end

    elseif cmd == "deposit" then
        if not validate_prereqs() then return end
        local start_room = GameState.room_id
        navigate_to_pool()
        do_deposit()
        deposit_silver()
        if start_room then navigate_to(tostring(start_room)) end

    else
        -- If we only had flags, just save and exit
        if has_flags and not cmd then return end

        -- Default: deposit then loot
        if not validate_prereqs() then return end

        -- Record start room for return
        local start_room = GameState.room_id

        -- Silver checking disabled — game now auto-handles box fees (since v2.1.5)

        navigate_to_pool()
        do_deposit()
        do_loot()

        -- Deposit silvers only if deposit_all is enabled
        if config.deposit_all then
            deposit_silver()
        end

        -- Return to start room
        if start_room then
            navigate_to(tostring(start_room))
        end
    end
end)

if not ok then
    if err and string.find(tostring(err), "pool_full") then
        msg("Locksmith pool is full. Please drain boxes and rerun poolparty.")
    elseif err and string.find(tostring(err), "not_a_box") then
        msg("Tried to deposit a non-box. Check your inventory and rerun.")
    elseif err and string.find(tostring(err), "no_npc") then
        msg("Could not find the locksmith NPC.")
    else
        msg("Error: " .. tostring(err))
    end
end
