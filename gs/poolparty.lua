--- @revenant-script
--- name: poolparty
--- version: 2.1.5
--- author: elanthia-online
--- contributors: Glaves, Steel Talon, Licel, Selfane
--- game: gs
--- description: Locksmith pool box deposit, retrieval, and looting automation
--- tags: locksmith,pool,boxes,loot,picking
---
--- Changelog (from Lich5):
---   v2.1.5 (2025-11-10): Use TRASH command for trashing items
---   v2.1.4 (2025-10-18): Loot option to match stow list before dumping
---   v2.1.3: Look-in-box option, already-unlocked handling, trickster NPC
---
--- Usage:
---   ;poolparty               - Deposit boxes, then loot finished ones
---   ;poolparty loot [n]      - Retrieve and loot up to n boxes
---   ;poolparty deposit       - Deposit boxes only
---   ;poolparty help          - Show all options
---
--- Configuration:
---   ;poolparty --tip-amount=25       - Set tip amount
---   ;poolparty --tip-type=percent    - Set tip type (percent or silver)
---   ;poolparty --skip-disk-wait      - Toggle disk checking
---   ;poolparty --deposit-all         - Toggle deposit all silver when done
---   ;poolparty --look-in-box         - Toggle looking in boxes before dumping
---   ;poolparty --loot-command        - Toggle loot command before dumping
---   ;poolparty --withdraw-amount=N   - Set withdrawal amount
---
--- Requires: lootsack set via ;vars set lootsack=<container>

--------------------------------------------------------------------------------
-- Config
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
-- NPC detection
--------------------------------------------------------------------------------

local NPC_NOUNS = Regex.new(
    "Gnome|gnome|Woman|woman|Attendant|attendant|Merchant|merchant|" ..
    "Worker|worker|Boss|boss|Jahck|jahck|Dwarf|dwarf|Trickster|trickster|" ..
    "Scoundrel|scoundrel|Pirate|pirate"
)

local function find_pool_master()
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        -- Room 17589 special case (only match attendant)
        if Room.id == 17589 then
            if string.find(npc.noun, "attendant") then return npc end
        else
            if NPC_NOUNS:test(npc.noun) then return npc end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function clear_hands()
    fput("stow all")
    empty_hands()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (rh and rh.id) or (lh and lh.id) then
        echo("Unable to clear hands. Make sure you have room.")
        return false
    end
    return true
end

local function find_lootsack()
    local sack_name = Vars.lootsack
    if not sack_name or sack_name == "" then
        echo("lootsack is not set. Use ;vars set lootsack=<container>")
        return nil
    end
    for _, obj in ipairs(GameObj.inv()) do
        if string.find(string.lower(obj.name), string.lower(sack_name), 1, true) then
            return obj
        end
    end
    echo("Could not find lootsack: " .. sack_name)
    return nil
end

local function check_silvers()
    clear()
    put("info")
    local deadline = os.time() + 3
    while os.time() < deadline do
        local line = get_noblock()
        if line then
            local amt = string.match(line, "Silver: ([%d,]+)")
            if amt then return tonumber(string.gsub(amt, ",", "")) or 0 end
        else
            pause(0.05)
        end
    end
    return 0
end

local function navigate_to_pool()
    Script.run("go2", "locksmith pool")
    wait_while(function() return Script.running("go2") end)
end

local function navigate_to_bank()
    Script.run("go2", "bank")
    wait_while(function() return Script.running("go2") end)
end

--------------------------------------------------------------------------------
-- Deposit
--------------------------------------------------------------------------------

local function deposit_one_box(npc, tip_str)
    local result = dothistimeout("give " .. npc.noun .. " " .. tip_str, 4,
        "You want a locksmith|doesn't appear to be a box|is already open|as many boxes")
    if not result then return false, "timeout" end

    if string.find(result, "doesn't appear to be a box") then return false, "not_a_box" end
    if string.find(result, "is already open") then return false, "already_open" end
    if string.find(result, "as many boxes") then return false, "pool_full" end

    -- Confirm
    result = dothistimeout("give " .. npc.noun .. " " .. tip_str, 4,
        "Your tip .* has been recorded|You don't have that much")
    if result and string.find(result, "Your tip") then
        return true, "ok"
    end
    return false, "no_silver"
end

local function do_deposit()
    echo("** [Starting Deposit] **")
    local tip_str = config.tip_amount .. " " .. (config.tip_type == "percent" and "percent" or "")
    local npc = find_pool_master()
    if not npc then
        echo("Unable to locate the locksmith pool NPC")
        return
    end

    local success_count = 0
    local failed = {}

    -- Deposit right hand if holding a box
    local rh = GameObj.right_hand()
    if rh and rh.type and string.find(rh.type, "box") then
        local ok, reason = deposit_one_box(npc, tip_str)
        if ok then success_count = success_count + 1
        else table.insert(failed, (rh.name or "unknown") .. " (" .. reason .. ")") end
    end

    -- Look for boxes in inventory
    local lootsack = find_lootsack()
    if lootsack and lootsack.contents then
        for _, item in ipairs(lootsack.contents) do
            if item.type and string.find(item.type, "box") then
                clear_hands()
                fput("get #" .. item.id)
                pause(0.5)
                local ok, reason = deposit_one_box(npc, tip_str)
                if ok then
                    success_count = success_count + 1
                else
                    table.insert(failed, (item.name or "unknown") .. " (" .. reason .. ")")
                    fput("stow right")
                end
            end
        end
    end

    echo("** Deposited " .. success_count .. " box(es). **")
    if #failed > 0 then
        echo("Failed to deposit " .. #failed .. " box(es):")
        for _, f in ipairs(failed) do echo("  " .. f) end
    end
end

--------------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------------

local function loot_one_box(lootsack)
    local npc = find_pool_master()
    if not npc then return false, "no_npc" end

    local result = dothistimeout("ask " .. npc.noun .. " about return", 4,
        "here's your|don't have any boxes|empty hand|lighten your load")
    if not result then return false, "timeout" end
    if string.find(result, "don't have any boxes") then return false, "no_boxes" end
    if string.find(result, "empty hand") or string.find(result, "lighten") then
        return false, "hands_full"
    end

    -- We should have a box in right hand now
    local box = GameObj.right_hand()
    if not box then return false, "no_box_in_hand" end

    -- Open it
    fput("open #" .. box.id)

    -- Loot coins
    fput("look in #" .. box.id)
    pause(0.5)

    if config.look_in_box then
        fput("look in #" .. box.id)
        pause(0.5)
    end

    -- Empty into lootsack
    if lootsack then
        fput("empty #" .. box.id .. " into #" .. lootsack.id)
        pause(0.5)
    end

    -- Trash the box
    local trash_result = dothistimeout("trash #" .. box.id, 4,
        "you feel pleased|items attached|trash receptacle")
    if trash_result and string.find(trash_result, "items attached") then
        -- Items still inside, try again
        if lootsack then
            fput("empty #" .. box.id .. " into #" .. lootsack.id)
        end
        dothistimeout("trash #" .. box.id, 4, "you feel pleased|trash receptacle")
    end

    return true, "ok"
end

local function do_loot(max_count)
    max_count = max_count or 100
    echo("** [Starting Loot] **")

    local lootsack = find_lootsack()
    if not lootsack then return end

    fput("open #" .. lootsack.id)

    local count = 0
    while count < max_count do
        clear_hands()
        local ok, reason = loot_one_box(lootsack)
        if not ok then
            if reason == "no_boxes" then
                echo("Pool has no more boxes for us.")
            else
                echo("Loot stopped: " .. reason)
            end
            break
        end
        count = count + 1
    end

    echo("** Looted " .. count .. " box(es). **")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("PoolParty v2.1.5")
    respond("")
    respond("Commands:")
    respond("  ;poolparty               - Deposit then loot")
    respond("  ;poolparty loot [n]      - Loot up to n boxes (default 100)")
    respond("  ;poolparty deposit       - Deposit boxes only")
    respond("  ;poolparty help          - This help")
    respond("")
    respond("Options:")
    respond("  --tip-amount=N           - Tip amount (current: " .. config.tip_amount .. ")")
    respond("  --tip-type=TYPE          - percent or silver (current: " .. config.tip_type .. ")")
    respond("  --skip-disk-wait         - Toggle disk wait (current: " .. tostring(config.skip_disk_wait) .. ")")
    respond("  --deposit-all            - Toggle deposit all (current: " .. tostring(config.deposit_all) .. ")")
    respond("  --look-in-box            - Toggle look before dump (current: " .. tostring(config.look_in_box) .. ")")
    respond("  --loot-command           - Toggle loot before dump (current: " .. tostring(config.loot_command) .. ")")
    respond("  --withdraw-amount=N      - Withdrawal amount (current: " .. config.withdraw_amount .. ")")
end

--------------------------------------------------------------------------------
-- Arg parsing
--------------------------------------------------------------------------------

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

-- Process flag options
for _, arg in ipairs(args) do
    if string.sub(arg, 1, 2) == "--" then
        local key_val = string.sub(arg, 3)
        local eq = string.find(key_val, "=")
        if eq then
            local key = string.sub(key_val, 1, eq - 1)
            local val = string.sub(key_val, eq + 1)
            key = string.gsub(key, "%-", "_")
            if key == "tip_amount" then
                config.tip_amount = val
                echo("Tip amount set to " .. val)
            elseif key == "tip_type" then
                if val == "percent" or val == "silver" then
                    config.tip_type = val
                    echo("Tip type set to " .. val)
                else
                    echo("Invalid tip type. Use percent or silver.")
                end
            elseif key == "withdraw_amount" then
                config.withdraw_amount = tonumber(val) or config.withdraw_amount
                echo("Withdraw amount set to " .. config.withdraw_amount)
            end
        else
            local key = string.gsub(key_val, "%-", "_")
            if key == "skip_disk_wait" then
                config.skip_disk_wait = not config.skip_disk_wait
                echo("Skip disk wait: " .. tostring(config.skip_disk_wait))
            elseif key == "deposit_all" then
                config.deposit_all = not config.deposit_all
                echo("Deposit all: " .. tostring(config.deposit_all))
            elseif key == "look_in_box" then
                config.look_in_box = not config.look_in_box
                echo("Look in box: " .. tostring(config.look_in_box))
            elseif key == "loot_command" then
                config.loot_command = not config.loot_command
                echo("Loot command: " .. tostring(config.loot_command))
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
        if not cmd then cmd = string.lower(arg)
        else table.insert(cmd_args, arg) end
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

if cmd == "help" then
    show_help()
elseif cmd == "loot" then
    local count = tonumber(cmd_args[1]) or 100
    local lootsack = find_lootsack()
    if not lootsack then return end
    fput("open #" .. lootsack.id)
    navigate_to_pool()
    do_loot(count)
    local silvers = check_silvers()
    if silvers > 0 then
        navigate_to_bank()
        fput("deposit all")
    end
elseif cmd == "deposit" then
    local lootsack = find_lootsack()
    if not lootsack then return end
    fput("open #" .. lootsack.id)
    navigate_to_pool()
    do_deposit()
else
    -- Check for flag-only invocation (settings change)
    local has_flags = false
    for _, arg in ipairs(args) do
        if string.sub(arg, 1, 2) == "--" then has_flags = true; break end
    end
    if has_flags then return end

    -- Default: deposit then loot
    local lootsack = find_lootsack()
    if not lootsack then return end
    fput("open #" .. lootsack.id)

    -- Withdraw silver
    local silvers = check_silvers()
    if silvers < config.withdraw_amount then
        navigate_to_bank()
        fput("withdraw " .. tostring(config.withdraw_amount - silvers) .. " silver")
    end

    navigate_to_pool()
    do_deposit()
    do_loot()

    silvers = check_silvers()
    if silvers > 0 then
        navigate_to_bank()
        fput("deposit all")
    end
end
