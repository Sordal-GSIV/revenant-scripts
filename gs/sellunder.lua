--- @revenant-script
--- name: sellunder
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Auto-sell items to gemshop/pawnshop under a specified price ceiling
--- tags: selling,pawnshop,gemshop,sell
---
--- Changelog (from Lich5):
---   v1.0.0 (2026-01-11): initial release
---
--- Usage:
---   ;sellunder [price_ceiling] [--return]    sell items under price ceiling
---   ;sellunder <price> --single              sell item in right hand only
---   ;sellunder list                          show current settings
---   ;sellunder help                          show usage information
---   ;sellunder <price> --shop_type=gemshop   sell only at gemshop
---
--- Examples:
---   ;sellunder 60000                         sell items <= 60,000 silvers
---   ;sellunder 60000 --return                sell items and return to start
---   ;sellunder 60000 --single                sell only the item in right hand

local SellUnder = {}

-- Sell response patterns
local SELL_PATTERNS = {
    "I have no use for that",
    "glances at it briefly, then hands you",
    "scribbles out a .+ and hands it to you",
    "worth at least [%d,]+",
    "worth about [%d,]+",
}

local DEFAULT_SHOP_TYPES = {"gemshop", "pawnshop"}

---------------------------------------------------------------------------
-- Settings (persisted via CharSettings)
---------------------------------------------------------------------------
local function load_settings()
    local s = {}
    s.price_ceiling = tonumber(CharSettings.sellunder_price_ceiling)
    s.return_to_start = (CharSettings.sellunder_return == "true")

    local shop_str = CharSettings.sellunder_shop_types
    if shop_str and shop_str ~= "" then
        s.shop_types = {}
        for shop in shop_str:gmatch("[^,]+") do
            table.insert(s.shop_types, shop:match("^%s*(.-)%s*$"))
        end
    else
        s.shop_types = {"gemshop", "pawnshop"}
    end

    return s
end

local function save_settings(s)
    if s.price_ceiling then
        CharSettings.sellunder_price_ceiling = tostring(s.price_ceiling)
    end
    CharSettings.sellunder_return = tostring(s.return_to_start or false)
    CharSettings.sellunder_shop_types = table.concat(s.shop_types or DEFAULT_SHOP_TYPES, ",")
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function sell_response_match(line)
    for _, pat in ipairs(SELL_PATTERNS) do
        if line:find(pat) then return true end
    end
    return false
end

local function parse_price(line)
    local price_str = line:match("at least ([%d,]+)") or line:match("about ([%d,]+)")
    if price_str then
        return tonumber((price_str:gsub(",", "")))
    end
    return nil
end

---------------------------------------------------------------------------
-- Single item sell
---------------------------------------------------------------------------
local function sell_single_item(price_ceiling)
    local rh = GameObj.right_hand()
    if not rh then
        echo("Error: No item in right hand")
        return
    end

    echo("Attempting to sell " .. rh.name .. " (price ceiling: " .. tostring(price_ceiling) .. ")")

    fput("sell #" .. rh.id)
    local line = waitforre("I have no use for that|glances at it briefly|scribbles out|worth at least|worth about")

    if not line then
        echo("Response not recognized for " .. rh.name)
        return
    end

    if line:find("I have no use for that") then
        echo(rh.name .. " - merchant has no use for this item")
        return
    end

    local item_value = parse_price(line)
    if item_value then
        if item_value <= price_ceiling then
            echo(rh.name .. " valued at " .. tostring(item_value) .. " silvers - selling")
            fput("sell #" .. rh.id)
        else
            echo(rh.name .. " valued at " .. tostring(item_value) .. " silvers - over ceiling, keeping")
        end
    else
        echo("Item sold immediately (worthless or no price check)")
    end
end

---------------------------------------------------------------------------
-- Navigate to shop
---------------------------------------------------------------------------
local function navigate_to_shop(shop_type)
    local room = Room.current()
    if room and room.tags then
        for _, tag in ipairs(room.tags) do
            if tag == shop_type then return end
        end
    end
    echo("Traveling to " .. shop_type .. "...")
    Map.go2(shop_type)
    wait_while(function() return running("go2") end)
end

---------------------------------------------------------------------------
-- Process items from inventory containers
---------------------------------------------------------------------------
local function find_sellable_items(shop_type)
    local items = {}
    local inv = GameObj.inv()
    if not inv then return items end

    for _, container in ipairs(inv) do
        if container.contents then
            for _, item in ipairs(container.contents) do
                if item.sellable and item.sellable:find(shop_type) then
                    table.insert(items, {item = item, container = container})
                end
            end
        end
    end
    return items
end

local function process_item(item_info, price_ceiling)
    local item = item_info.item
    local container = item_info.container

    fput("_drag #" .. item.id .. " right")
    pause(0.3)

    fput("sell #" .. item.id)
    local line = waitforre("I have no use for that|glances at it briefly|scribbles out|worth at least|worth about")

    if not line then
        echo("Response not recognized for " .. item.name)
        -- Return to container
        if GameObj.right_hand() then
            fput("_drag right #" .. container.id)
        end
        return
    end

    if line:find("I have no use for that") then
        -- Return to container
        if GameObj.right_hand() then
            fput("_drag right #" .. container.id)
        end
        return
    end

    local item_value = parse_price(line)
    if item_value then
        if item_value <= price_ceiling then
            echo(item.name .. " valued at " .. tostring(item_value) .. " silvers - selling")
            fput("sell #" .. item.id)
        else
            echo(item.name .. " valued at " .. tostring(item_value) .. " silvers - over ceiling, keeping")
            if GameObj.right_hand() then
                fput("_drag right #" .. container.id)
            end
        end
    else
        -- Already sold (worthless)
        if GameObj.right_hand() then
            fput("_drag right #" .. container.id)
        end
    end
end

---------------------------------------------------------------------------
-- Full sell run
---------------------------------------------------------------------------
local function run_seller(price_ceiling, shop_types, return_to_start)
    local starting_room = Room.current() and Room.current().id

    echo("Selling items valued at " .. tostring(price_ceiling) .. " silvers or under")
    echo("Checking shops: " .. table.concat(shop_types, ", "))

    for _, shop_type in ipairs(shop_types) do
        navigate_to_shop(shop_type)

        local sellable = find_sellable_items(shop_type)
        for _, item_info in ipairs(sellable) do
            process_item(item_info, price_ceiling)
        end
    end

    echo("Selling complete!")

    if return_to_start and starting_room then
        local current = Room.current()
        if current and current.id ~= starting_room then
            echo("Returning to starting room...")
            Map.go2(tostring(starting_room))
            wait_while(function() return running("go2") end)
        end
    end
end

---------------------------------------------------------------------------
-- Display functions
---------------------------------------------------------------------------
local function display_settings()
    local s = load_settings()
    respond("")
    respond("Current Settings:")
    respond("=" .. string.rep("=", 49))
    if s.price_ceiling then
        respond("Price Ceiling: " .. tostring(s.price_ceiling) .. " silvers")
    else
        respond("Price Ceiling: Not set")
    end
    respond("Shop Types: " .. table.concat(s.shop_types, ", "))
    respond("Return to Start: " .. (s.return_to_start and "Yes" or "No"))
    respond("")
end

local function display_usage()
    respond([[

Usage:
  ;sellunder [price_ceiling] [--return]
  ;sellunder <price_ceiling> --single
  ;sellunder list
  ;sellunder help
  ;sellunder <price_ceiling> --shop_type=gemshop,pawnshop

Options:
  --return    Return to starting room after completion
  --single    Sell only the item in right hand at current location

Examples:
  ;sellunder 60000                Sell items <= 60,000 silvers
  ;sellunder 60000 --return       Sell items and return to start
  ;sellunder 60000 --single       Sell only item in right hand
  ;sellunder --shop_type=gemshop  Update shop type setting
    ]])
end

---------------------------------------------------------------------------
-- Parse arguments and run
---------------------------------------------------------------------------
local function main()
    local args = Script.vars
    local parsed = {
        price_ceiling = nil,
        shop_types = nil,
        return_to_start = nil,
        single_mode = false,
        show_help = false,
        show_list = false,
    }

    for i = 1, #args do
        local arg = args[i]
        if not arg then break end

        if arg == "help" then
            parsed.show_help = true
        elseif arg == "list" then
            parsed.show_list = true
        elseif arg:find("^--shop_type=") then
            parsed.shop_types = {}
            local shops_str = arg:match("^--shop_type=(.+)")
            for shop in shops_str:gmatch("[^,]+") do
                table.insert(parsed.shop_types, shop:match("^%s*(.-)%s*$"))
            end
        elseif arg == "--return" then
            parsed.return_to_start = true
        elseif arg == "--single" then
            parsed.single_mode = true
        elseif arg:match("^%d+$") then
            parsed.price_ceiling = tonumber(arg)
        end
    end

    if parsed.show_help then
        display_usage()
        return
    end

    if parsed.show_list then
        display_settings()
        return
    end

    local s = load_settings()
    local price_ceiling = parsed.price_ceiling or s.price_ceiling
    local shop_types = parsed.shop_types or s.shop_types
    local return_to_start = parsed.return_to_start
    if return_to_start == nil then return_to_start = s.return_to_start end

    -- Single item mode
    if parsed.single_mode then
        if not price_ceiling then
            echo("Error: Price ceiling not specified. Use: ;sellunder <price> --single")
            return
        end
        sell_single_item(price_ceiling)
        return
    end

    -- Settings-only update (shop_types given without price)
    if not parsed.price_ceiling and parsed.shop_types then
        s.shop_types = shop_types
        save_settings(s)
        echo("Settings updated. Shop Types: " .. table.concat(shop_types, ", "))
        return
    end

    -- Validate
    if not price_ceiling then
        echo("Error: Price ceiling not specified.")
        display_usage()
        return
    end

    if price_ceiling <= 0 then
        echo("Error: Price ceiling must be a positive number.")
        return
    end

    -- Save for future runs
    if parsed.price_ceiling then
        s.price_ceiling = price_ceiling
        s.shop_types = shop_types
        s.return_to_start = return_to_start
        save_settings(s)
    end

    run_seller(price_ceiling, shop_types, return_to_start)
end

main()
