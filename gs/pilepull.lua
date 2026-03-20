--- @revenant-script
--- name: pilepull
--- version: 1.0.1
--- author: Tysong
--- contributors: Shattered community
--- game: gs
--- description: Treasure pile search automation for Shattered (1M silver per search)
--- tags: loot, mania, treasure, pile, shattered
--- @lic-certified: complete 2026-03-20
---
--- Usage:
---   ;pilepull          - Search the pile
---   ;pilepull cleanup  - Bundle/organize found items
---
--- Changelog:
---   v1.0.1 (2026-03-01) - slight fix to retry item handling after prize pulling
---   v1.0.0 (2025-08-31) - initial release

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
local WITHDRAW_AMOUNT = 100000000  -- 100M silvers per bank run
local KEEP_SPOON     = false       -- keep steel spoon prizes
local KEEP_WISP      = false       -- keep wisp prizes (not yet implemented)
local KEEP_NEXUS     = false       -- keep nexus orb prizes

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local prize_pile          = nil
local inventory_quantity  = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Check current silver on hand via the `coins` command.
local function silver_check()
    local line = dothistimeout("coins", 5, "silver")
    if not line then return 0 end
    local amount = line:match("(%d[%d,]*) silver")
    if not amount then return 0 end
    return tonumber((amount:gsub(",", ""))) or 0
end

--- Detect the prize pile in the room by looking for pile/prizes nouns
--- and verifying with a `look #id` command.
local function detect_pile()
    for _, noun in ipairs({"pile", "prizes"}) do
        local loot = GameObj.loot() or {}
        for _, item in ipairs(loot) do
            if item.noun == noun then
                local result = dothistimeout(
                    "look #" .. item.id, 2,
                    "SEARCH the %w+ to get something from the %w+!"
                )
                if result and result:match("SEARCH the %w+ to get something from the %w+!") then
                    prize_pile = item
                    return
                end
            end
        end
    end
    echo("Could not find a prize pile, be sure to start script in front of a treasure pile! Exiting!")
    exit()
end

--- Navigate to bank, deposit all, withdraw configured amount, return.
local function bank_run()
    local current_location = Room.id
    Script.run("go2", "u8213023")
    fput("deposit all")
    local result = dothistimeout(
        "withdraw " .. WITHDRAW_AMOUNT .. " silver", 2,
        "you don't seem to have that much",
        "hands you [%d,]+ silvers"
    )
    if result and result:match("you don't seem to have that much") then
        echo("Not enough silver, exiting!")
        exit()
    end
    Script.run("go2", tostring(current_location))
end

--- Search the pile once. Returns true if a prize was pulled, false if
--- silver ran out. Retries on "recently searched" and other transient msgs.
local function search_pile()
    while true do
        local result = dothistimeout(
            "search #" .. prize_pile.id, 2,
            "In order to search through a pile of mania prizes",
            "You do not have enough silver to SEARCH",
            "You hand over 1,000,000",
            "You've recently searched through",
            "You have too many items to search%."
        )
        if not result then
            -- timeout / no match, retry
        elseif result:match("In order to search through") then
            -- informational, retry
        elseif result:match("You've recently searched through") then
            pause(0.3)
            -- retry
        elseif result:match("You do not have enough silver to SEARCH") then
            return false
        elseif result:match("You have too many items to search") then
            echo("You have too many items! Handle that!")
            exit()
        elseif result:match("You hand over 1,000,000") then
            pause(1)
            waitrt()
            return true
        end
    end
end

--- Handle the item that lands in your right hand after a search.
--- Tries up to 2 times to clear both hands.
local function handle_loot()
    for _ = 1, 2 do
        waitrt()
        local rh = GameObj.right_hand()
        if rh and rh.name then
            local name = rh.name
            if name:match("booklet") then
                fput("redeem booklet")
            elseif name:match("steel spoon") then
                if KEEP_SPOON then
                    fput("stow all")
                else
                    fput("trash my spoon")
                end
            elseif name:match("nexus orb") then
                if KEEP_NEXUS then
                    fput("stow all")
                else
                    fput("trash my orb")
                end
            else
                fput("stow all")
            end
        end

        -- Wait up to 3 seconds for hands to be empty
        for _ = 1, 30 do
            local r = GameObj.right_hand()
            local l = GameObj.left_hand()
            local r_empty = (not r) or (r.id == nil)
            local l_empty = (not l) or (l.id == nil)
            if r_empty and l_empty then
                return
            end
            pause(0.1)
        end
    end

    echo("Couldn't handle item received, likely full containers, exiting!")
    exit()
end

--- Check inventory count and exit if >= 400.
local function check_inventory_count()
    waitrt()
    local result = dothistimeout("inventory quantity", 3, "You are carrying [%d,]+ items%.")
    if result then
        local count_str = result:match("You are carrying ([%d,]+) items%.")
        if count_str then
            -- Remove commas and convert
            inventory_quantity = tonumber((count_str:gsub(",", "")))
            if inventory_quantity and inventory_quantity >= 400 then
                echo("You have too many items on you, preventing run as you should empty some stuff off your person")
                echo("Item cap is 500 and you have " .. tostring(inventory_quantity) .. ".")
                exit()
            end
            return
        end
    end
    echo("Couldn't detect current inventory quantity, exiting for safety reasons!")
    exit()
end

--- Force-populate container contents by looking in each inventory container.
local function populate_inventory()
    local inv = GameObj.inv() or {}
    for _, item in ipairs(inv) do
        -- Skip items that already have contents loaded
        if item.contents and type(item.contents) == "table" then
            goto continue
        end
        -- Skip jewelry/weapon/armor/uncommon typed items
        if item.type then
            if item.type:match("jewelry") or item.type:match("weapon")
                or item.type:match("armor") or item.type:match("uncommon") then
                goto continue
            end
        else
            goto continue  -- skip nil-typed items
        end

        -- Look inside to trigger container population
        fput("look in #" .. item.id)
        -- Wait briefly for container contents to populate
        for _ = 1, 20 do
            if item.contents and type(item.contents) == "table" then
                break
            end
            pause(0.1)
        end

        ::continue::
    end
end

--- Search all containers (or stow container) for items matching a pattern.
--- Returns a table of matching GameObj items.
local function find_items(pattern)
    local all_items = {}

    local inv = GameObj.inv() or {}
    for _, container in ipairs(inv) do
        if container.contents and type(container.contents) == "table" then
            for _, thing in ipairs(container.contents) do
                if thing.name and thing.name:match(pattern) then
                    table.insert(all_items, thing)
                end
            end
        end
    end

    return all_items
end

--- Helper: check if either hand is holding something
local function hands_occupied()
    local r = GameObj.right_hand()
    local l = GameObj.left_hand()
    local r_has = r and r.id ~= nil
    local l_has = l and l.id ~= nil
    return r_has, l_has
end

--- Helper: stow left hand only when both hands are occupied
--- (mirrors original: `stow left unless right.nil? || left.nil?`)
local function stow_if_both_full()
    local r_has, l_has = hands_occupied()
    if r_has and l_has then
        fput("stow left")
    end
end

--- Helper: stow all if either hand is occupied
local function stow_if_any()
    local r_has, l_has = hands_occupied()
    if r_has or l_has then
        fput("stow all")
    end
end

--- Bundle duplicate items by getting them and using bundle command.
--- @param pattern string  Lua pattern to match item names
--- @param action string   "bundle" or "pour"
--- @param pour_target string|nil  target for pour action (e.g., "in my second potion")
local function cleanup_item(pattern, action, pour_target)
    local found_items = find_items(pattern)
    if #found_items > 1 then
        for _, item in ipairs(found_items) do
            fput("get #" .. item.id)
            if action == "bundle" then
                multifput("bundle #" .. item.id, "bundle #" .. item.id)
            elseif action == "pour" and pour_target then
                multifput("pour #" .. item.id .. " " .. pour_target)
            end
            stow_if_both_full()
        end
    end
    stow_if_any()
end

--- Cleanup mode: search containers for bundlable items and consolidate them.
local function cleanup()
    populate_inventory()

    -- Glowing orbs (REIM stuff) - bundle duplicates
    cleanup_item("glowing orb", "bundle")

    -- Potent blue-green potion - SKE enhancive 30min recharge - pour to combine
    cleanup_item("potent blue%-green potion", "pour", "in my second potion")

    -- Potent yellow-green potions - SKE enhancive 30day recharge - pour to combine
    cleanup_item("potent yellow%-green potion", "pour", "in my second potion")

    -- Swirling yellow-green potions - regular enhancive 30day recharge - pour to combine
    cleanup_item("swirling yellow%-green potion", "pour", "in my second potion")

    -- Elanthian Guilds voucher pack - Professional Guild task reassigning - bundle
    cleanup_item("Elanthian Guilds voucher pack", "bundle")

    -- Adventurer's Guild voucher pack - Adv Guild task reassigning - bundle
    cleanup_item("Adventurer's Guild voucher pack", "bundle")

    -- Adventurer's Guild task waiver - 30 days exempt from Adv Guild task - bundle
    cleanup_item("Adventurer's Guild task waiver", "bundle")

    waitrt()
    stow_if_any()
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function main()
    detect_pile()
    check_inventory_count()

    if silver_check() < 1000000 then
        bank_run()
    end

    while true do
        if search_pile() then
            handle_loot()
        else
            cleanup()
            check_inventory_count()
            bank_run()
        end
    end
end

-- Entry point: cleanup mode or main loop
if Script.vars[1] == "cleanup" then
    cleanup()
else
    main()
end
