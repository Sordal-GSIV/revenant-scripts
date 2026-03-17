--- @revenant-script
--- name: inventory_buddy
--- version: 9.0.0
--- author: Dreaven
--- game: dr
--- description: Track inventory, locker contents, banks, resources, and experience across all characters
--- tags: inventory, locker, tracker, database, search
---
--- Usage:
---   ;inventory_buddy              - Start tracking (runs in background)
---   ;send inv                     - Open inventory display
---   ;send update                  - Update all info for current character
---   ;send reload                  - Save/reload database
---
--- The database updates automatically when you:
---   - Type INV FULL (inventory)
---   - LOOK in your locker or use a locker manifest
---   - Type BANK ACCOUNT, RESOURCE, EXPERIENCE, TICKET BALANCE

local json = require("json")

local save_file = "inventory-buddy.json"
local all_data = {}
local scanning_inventory = false
local scanning_hands = false
local save_enabled = true
local settings_keys = { "Marked", "Save Option" }

local function add_commas(n)
    local s = tostring(n)
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        result = s:sub(i, i) .. result
        count = count + 1
        if count % 3 == 0 and i > 1 and s:sub(i - 1, i - 1) ~= "-" then
            result = "," .. result
        end
    end
    return result
end

local function load_data()
    local f = io.open(save_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and data then
            all_data = data
        end
    end
end

local function save_data()
    if not save_enabled then return end
    local ok, content = pcall(json.encode, all_data)
    if ok then
        local f = io.open(save_file, "w")
        if f then
            f:write(content)
            f:close()
            respond(";inventory-buddy: Data saved.")
        end
    end
end

local function init_character()
    local name = Char.name
    if not all_data[name] then
        all_data[name] = {}
    end
    -- Preserve stats and locker data, clear inventory
    local preserved = {}
    for key, val in pairs(all_data[name]) do
        if key:match("^Experience") or key:match("^Banks") or key:match("^Resources")
            or key:match("^Tickets") or key:match("^Locker") then
            preserved[key] = val
        end
    end
    all_data[name] = preserved
    all_data[name]["All Inventory"] = {}
    all_data[name]["Worn"] = {}

    if not all_data["Script Settings"] then
        all_data["Script Settings"] = {}
    end
    for _, key in ipairs(settings_keys) do
        if all_data["Script Settings"][key] ~= "Yes" then
            all_data["Script Settings"][key] = "No"
        end
    end
end

local function should_save_auto()
    return all_data["Script Settings"] and all_data["Script Settings"]["Save Option"] == "Yes"
end

local function track_marked()
    return all_data["Script Settings"] and all_data["Script Settings"]["Marked"] == "Yes"
end

local function strip_marked(item)
    if track_marked() then return item end
    return item:gsub(" %(marked%)", ""):gsub(" %(registered%)", "")
end

local function search_items(query)
    local results = {}
    local count = 0
    for char_name, char_data in pairs(all_data) do
        if char_name ~= "Script Settings" and type(char_data) == "table" then
            for container, items in pairs(char_data) do
                if type(items) == "table" and container ~= "All Inventory" then
                    for _, item in ipairs(items) do
                        if type(item) == "string" and item:lower():find(query:lower(), 1, true) then
                            table.insert(results, item:match("^%s*(.-)%s*$") .. " - " .. char_name .. " (" .. container .. ")")
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return results, count
end

local function show_inventory(char_name, container)
    if not all_data[char_name] then
        echo("Character '" .. char_name .. "' not found.")
        return
    end
    if not container then container = "All Inventory" end
    local items = all_data[char_name][container]
    if not items then
        echo("Container '" .. container .. "' not found for " .. char_name .. ".")
        return
    end

    echo("=== " .. char_name .. " - " .. container .. " ===")
    for _, item in ipairs(items) do
        echo("  " .. tostring(item))
    end
    echo("(" .. #items .. " items)")
end

local function show_all_characters()
    echo("=== Characters in Database ===")
    local names = {}
    for name, _ in pairs(all_data) do
        if name ~= "Script Settings" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local containers = 0
        if type(all_data[name]) == "table" then
            for _ in pairs(all_data[name]) do
                containers = containers + 1
            end
        end
        echo("  " .. name .. " (" .. containers .. " data entries)")
    end
end

local function show_banks()
    echo("=== Bank Accounts ===")
    local grand_total = 0
    for name, data in pairs(all_data) do
        if name ~= "Script Settings" and type(data) == "table" and data["Banks"] then
            echo(name .. ":")
            for bank, amount in pairs(data["Banks"]) do
                echo("  " .. bank .. ": " .. add_commas(amount))
                if bank ~= "Total" then
                    grand_total = grand_total + (tonumber(tostring(amount):gsub(",", "")) or 0)
                end
            end
            echo("")
        end
    end
    echo("Grand Total: " .. add_commas(grand_total))
end

local function update_everything()
    save_enabled = false
    echo("Updating all information for " .. Char.name .. "...")
    echo("Avoid roundtime or commands until update is complete.")
    waitrt()
    put("inv full")
    pause(1)
    put("bank account")
    pause(1)
    put("resource")
    pause(1)
    put("experience")
    pause(1)
    put("ticket balance")
    pause(1)
    echo("Update complete.")
    save_enabled = true
    save_data()
end

-- Initialize
load_data()
init_character()

echo(string.rep("#", 80))
echo("Message from ;inventory_buddy")
echo("Leave the script running in the background to keep the database up to date.")
echo("Commands: ;send inv | ;send update | ;send reload")
echo("Database updates on: INV FULL, LOOK in locker, BANK ACCOUNT, RESOURCE, EXPERIENCE")
echo(string.rep("#", 80))

update_everything()

-- Main watch loop
local current_worn = nil
local containers = {}
local last_container_index = 0

while true do
    local line = get()
    if line then
        local name = Char.name

        -- Inventory scanning
        if line:find("^You are currently wearing:") then
            init_character()
            scanning_inventory = true
            scanning_hands = false
            containers = {}
            last_container_index = 0

        elseif line:match("^  ([a-zA-Z].+)") and (scanning_inventory or scanning_hands) then
            local item = line:match("^  (.+)")
            item = strip_marked(item)
            if scanning_hands then
                table.insert(all_data[name]["All Inventory"], "  " .. item .. " (Held)")
            else
                table.insert(all_data[name]["All Inventory"], "  " .. item)
            end
            table.insert(all_data[name]["Worn"], item)

        elseif line:match("^      ([a-zA-Z].+)") and (scanning_inventory or scanning_hands) then
            local item = line:match("^%s+(.+)")
            item = strip_marked(item)
            table.insert(all_data[name]["All Inventory"], line:match("^(%s+)") .. item)
            -- Track container contents
            local spaces = #(line:match("^(%s+)") or "")
            local container_idx = math.floor((spaces - 6) / 4)
            if container_idx >= 0 and containers[container_idx] then
                local cname = containers[container_idx]
                if not all_data[name][cname] then
                    all_data[name][cname] = {}
                end
                table.insert(all_data[name][cname], item)
            end

        elseif line:find("%(Items:") and scanning_inventory then
            scanning_inventory = false
            scanning_hands = true
            put("inv hands full")

        elseif line:find("You are carrying nothing at this time") then
            init_character()
            table.insert(all_data[name]["Worn"], "NOTHING")
            scanning_inventory = false
            scanning_hands = true
            put("inv hands full")

        elseif line:find("%(Items:") and scanning_hands then
            scanning_inventory = false
            scanning_hands = false
            if should_save_auto() then save_data() end

        elseif line:find("You are holding nothing at this time") and scanning_hands then
            scanning_hands = false
            scanning_inventory = false
            if should_save_auto() then save_data() end

        -- Locker management
        elseif line:find("^In the locker:") then
            all_data[name]["Locker"] = {}
            while true do
                local lline = get()
                if lline then
                    if lline:find("Total items:") then
                        save_data()
                        break
                    end
                    if lline:match("%[%d+%]:") then
                        for item in lline:gmatch("[^,]+") do
                            item = item:match("^%s*(.-)%s*$")
                            if #item > 0 then
                                table.insert(all_data[name]["Locker"], strip_marked(item))
                            end
                        end
                    end
                end
            end

        elseif line:find("^In the locker you see ") then
            all_data[name]["Locker"] = {}
            local items_str = line:gsub("In the locker you see ", ""):gsub("%.$", "")
            for item in items_str:gmatch("[^,]+") do
                item = item:gsub("^ and ", ""):match("^%s*(.-)%s*$")
                if #item > 0 then
                    table.insert(all_data[name]["Locker"], strip_marked(item))
                end
            end
            save_data()

        elseif line:find("contents of your locker in") then
            local town = line:match("contents of your locker in (.-):")
            if town then
                local key = "Locker in " .. town
                all_data[name][key] = {}
                while true do
                    local lline = get()
                    if lline then
                        if lline:find("Obvious items:") or lline:find("There are no items") then
                            save_data()
                            break
                        end
                        table.insert(all_data[name][key], strip_marked(lline))
                    end
                end
            end

        -- Experience
        elseif line:match("Level: (%d+)") then
            if not all_data[name]["Experience"] then all_data[name]["Experience"] = {} end
            all_data[name]["Experience"]["Level"] = line:match("Level: (%d+)")

        elseif line:match("Total Exp: (.-)%s+Death") then
            if all_data[name]["Experience"] then
                all_data[name]["Experience"]["Total Experience"] = line:match("Total Exp: (.-)%s+Death"):gsub(",", "")
            end

        elseif line:match("Exp until lvl: ([%d,]+)") or line:match("Exp to next TP: ([%d,]+)") then
            if all_data[name]["Experience"] then
                local val = (line:match("Exp until lvl: ([%d,]+)") or line:match("Exp to next TP: ([%d,]+)")):gsub(",", "")
                all_data[name]["Experience"]["Until Level/Next TP"] = val
                if should_save_auto() then save_data() end
            end

        -- Bank management
        elseif line:find("You currently have the following amounts on deposit:") then
            all_data[name]["Banks"] = {}
            while true do
                local bline = get()
                if bline then
                    local bank, amount = bline:match("(.+):%s+(.+)")
                    if bank and amount then
                        all_data[name]["Banks"][bank:match("^%s*(.-)%s*$")] = amount:gsub(",", "")
                        if bline:find("Total:") then break end
                    end
                    if bline:find("no open bank accounts") then break end
                end
            end
            if should_save_auto() then save_data() end

        -- Resource management
        elseif line:match("/%s*50,000 %(Weekly%)") then
            local weekly = line:match("(%d[%d,]+)/%s*50,000"):gsub(",", "")
            local total = line:match("(%d[%d,]+)/%s*200,000"):gsub(",", "")
            all_data[name]["Resources"] = { Weekly = weekly, Total = total }
            if should_save_auto() then save_data() end

        -- Script commands via ;send
        elseif line == "inv" then
            echo("=== Inventory Buddy ===")
            show_all_characters()
            echo("")
            echo("Commands: ;send search <item> | ;send banks | ;send <charname>")

        elseif line == "update" then
            update_everything()

        elseif line == "reload" then
            save_data()

        elseif line == "banks" then
            show_banks()

        elseif line:match("^search (.+)") then
            local query = line:match("^search (.+)")
            local results, count = search_items(query)
            echo("=== Search: " .. query .. " ===")
            for _, r in ipairs(results) do
                echo("  " .. r)
            end
            echo(count .. " items found")

        elseif all_data[line] and line ~= "Script Settings" then
            show_inventory(line)
        end
    end
end
