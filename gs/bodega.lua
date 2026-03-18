--- @revenant-script
--- name: bodega
--- version: 0.6.0
--- author: Ondreian
--- game: gs
--- tags: playershops
--- description: Player shop directory scanner — parses in-game shop directories and generates JSON
---
--- Original Lich5 authors: Ondreian
--- Ported to Revenant Lua from bodega.lic v0.6
---
--- Usage: ;bodega --help
---
--- Features:
---   - Scans player shop directories and individual shops
---   - Generates JSON files for external consumption
---   - Smart scan mode (--smart) for incremental updates
---   - Exposes a Bodega module for other scripts
---   - Upload support (API-based, stubbed for Revenant)

local VERSION = "0.6.0"

local args_lib = require("lib/args")

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local DATA_DIR = GameState.data_dir or "data"
local BODEGA_DIR = DATA_DIR .. "/bodega"
local JSON_EXT = ".json"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function is_integer(s)
    return s and s:match("^[+-]?%d+$") ~= nil
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function escape_json_string(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

local function table_to_json(tbl, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local pad1 = string.rep("  ", indent + 1)

    if #tbl > 0 then
        -- Array
        local items = {}
        for _, v in ipairs(tbl) do
            if type(v) == "table" then
                items[#items+1] = pad1 .. table_to_json(v, indent + 1)
            elseif type(v) == "string" then
                items[#items+1] = pad1 .. '"' .. escape_json_string(v) .. '"'
            elseif type(v) == "number" then
                items[#items+1] = pad1 .. tostring(v)
            elseif type(v) == "boolean" then
                items[#items+1] = pad1 .. tostring(v)
            else
                items[#items+1] = pad1 .. '"' .. tostring(v) .. '"'
            end
        end
        return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
    else
        -- Object
        local items = {}
        for k, v in pairs(tbl) do
            local key_str = '"' .. escape_json_string(tostring(k)) .. '"'
            local val_str
            if type(v) == "table" then
                val_str = table_to_json(v, indent + 1)
            elseif type(v) == "string" then
                val_str = '"' .. escape_json_string(v) .. '"'
            elseif type(v) == "number" then
                val_str = tostring(v)
            elseif type(v) == "boolean" then
                val_str = tostring(v)
            elseif v == nil then
                val_str = "null"
            else
                val_str = '"' .. tostring(v) .. '"'
            end
            items[#items+1] = pad1 .. key_str .. ": " .. val_str
        end
        return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
    end
end

local function write_json(filepath, data)
    local f = io.open(filepath, "w")
    if f then
        f:write(table_to_json(data, 0))
        f:close()
        return true
    end
    return false
end

local function read_json_file(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    -- Simple JSON parsing — for production use a proper JSON library
    -- For now return nil to indicate no cached data
    return nil
end

local function ensure_dir(path)
    os.execute('mkdir -p "' .. path .. '"')
end

--------------------------------------------------------------------------------
-- Shop parsing patterns
--------------------------------------------------------------------------------

local SHOP_DIR_PATTERN   = "^%s*(%d+)%)%s+(.+)$"
local SHOP_ITEM_PATTERN  = "^%s*(.-)%s+(%d+)%s*$"
local PRICE_PATTERN      = "for%s+(%d[%d,]*)%s+silvers?"
local INSPECT_PATTERNS   = {
    show       = "show",
    long_desc  = "You see",
    weight     = "weighs? about",
    enchant    = "enchanted? to",
}

--------------------------------------------------------------------------------
-- Bodega module
--------------------------------------------------------------------------------

local Bodega = {
    shops = {},
    current_shop = nil,
    scan_count = 0,
    smart_mode = false,
}

--- Parse a shop directory listing from game output
function Bodega.parse_directory(lines)
    local entries = {}
    for _, line in ipairs(lines) do
        local num, name = line:match(SHOP_DIR_PATTERN)
        if num then
            entries[#entries+1] = {
                number = tonumber(num),
                name = trim(name),
            }
        end
    end
    return entries
end

--- Scan items on a single shelf/table in a shop
function Bodega.scan_shelf()
    local items = {}
    put("look")
    local lines = {}
    for i = 1, 20 do
        local line = get()
        if not line then break end
        lines[#lines+1] = line
        if line:match("^Obvious") or line:match("^$") then break end
    end

    -- Parse items from the room description (GameObj.loot for shop items)
    local room_items = GameObj.loot() or {}
    for _, item in ipairs(room_items) do
        local entry = {
            id = item.id,
            name = item.name or "",
            noun = item.noun or "",
            type = item.type or "",
        }
        items[#items+1] = entry
    end

    return items
end

--- Inspect a single item for detailed info
function Bodega.inspect_item(item_id)
    local info = { id = item_id }

    -- Look at item
    put("look #" .. item_id)
    local result = matchtimeout(3, "You see", "I could not find")
    if result and result:find("You see") then
        info.description = result
    end

    -- Appraise for price
    put("appraise #" .. item_id)
    local price_line = matchtimeout(3, "silvers", "cannot be", "I could not")
    if price_line then
        local price = price_line:match("(%d[%d,]*) silvers?")
        if price then
            info.price = tonumber(price:gsub(",", ""))
        end
    end

    return info
end

--- Scan an entire shop
function Bodega.scan_shop(shop_entry)
    echo("Scanning shop: " .. (shop_entry.name or "unknown"))
    local shop_data = {
        name = shop_entry.name,
        number = shop_entry.number,
        rooms = {},
        scanned_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    -- We're assumed to be inside the shop already
    local room_title = GameState.room_title or ""
    local room_items = Bodega.scan_shelf()

    shop_data.rooms[#shop_data.rooms+1] = {
        title = room_title,
        items = room_items,
    }

    -- Check for additional rooms (go door, etc.)
    local exits = GameState.room_exits_string or ""
    if exits:find("door") or exits:find("curtain") or exits:find("arch") then
        -- Try navigating through obvious exits
        for _, exit_word in ipairs({"door", "curtain", "arch", "opening"}) do
            if exits:find(exit_word) then
                local start_room = Map.current_room()
                put("go " .. exit_word)
                pause(1)
                if Map.current_room() ~= start_room then
                    local sub_items = Bodega.scan_shelf()
                    shop_data.rooms[#shop_data.rooms+1] = {
                        title = GameState.room_title or "",
                        items = sub_items,
                    }
                    put("out")
                    pause(1)
                end
            end
        end
    end

    Bodega.scan_count = Bodega.scan_count + 1
    return shop_data
end

--- Smart scan: compare with existing data and only inspect new/changed items
function Bodega.smart_scan(shop_entry, existing_data)
    local shop_data = Bodega.scan_shop(shop_entry)

    if not existing_data then return shop_data end

    -- Compare item IDs — only inspect items not in existing data
    local existing_ids = {}
    if existing_data.rooms then
        for _, room in ipairs(existing_data.rooms) do
            for _, item in ipairs(room.items or {}) do
                existing_ids[item.id] = true
            end
        end
    end

    local new_count = 0
    local removed_count = 0
    for _, room in ipairs(shop_data.rooms) do
        for _, item in ipairs(room.items or {}) do
            if not existing_ids[item.id] then
                new_count = new_count + 1
            end
        end
    end

    if new_count > 0 or removed_count > 0 then
        echo("Smart scan: " .. new_count .. " new items detected")
    else
        echo("Smart scan: no changes detected")
    end

    return shop_data
end

--- Save shop data to JSON file
function Bodega.save_shop(shop_data, output_dir)
    output_dir = output_dir or BODEGA_DIR
    ensure_dir(output_dir)

    local filename = (shop_data.name or "unknown"):gsub("[^%w%-_]", "_"):lower()
    local filepath = output_dir .. "/" .. filename .. JSON_EXT

    if write_json(filepath, shop_data) then
        echo("Saved: " .. filepath)
    else
        echo("Failed to save: " .. filepath)
    end
end

--- Upload shop data (stub — original used HTTP POST to GitHub site)
function Bodega.upload(shop_data)
    -- TODO: Implement HTTP upload
    -- Original used Net::HTTP to POST JSON to a GitHub Pages API
    echo("Upload not yet implemented in Revenant (TODO: HTTP client)")
end

--------------------------------------------------------------------------------
-- Command handlers
--------------------------------------------------------------------------------

local function cmd_scan(opts)
    echo("Bodega v" .. VERSION .. " — scanning player shops")

    local smart = opts.smart or false

    -- Get directory listing
    put("shop directory")
    pause(2)

    local dir_lines = {}
    for i = 1, 50 do
        local line = get()
        if not line then break end
        dir_lines[#dir_lines+1] = line
        if line:match("^$") or line:match("To visit") then break end
    end

    local entries = Bodega.parse_directory(dir_lines)
    if #entries == 0 then
        echo("No shops found in directory. Are you at a player shop directory?")
        return
    end

    echo("Found " .. #entries .. " shops")

    for _, entry in ipairs(entries) do
        put("shop " .. entry.number)
        pause(2)

        local shop_data
        if smart then
            local existing = read_json_file(BODEGA_DIR .. "/" .. (entry.name or ""):gsub("[^%w%-_]", "_"):lower() .. JSON_EXT)
            shop_data = Bodega.smart_scan(entry, existing)
        else
            shop_data = Bodega.scan_shop(entry)
        end

        Bodega.save_shop(shop_data)

        if opts.upload then
            Bodega.upload(shop_data)
        end

        -- Return to directory
        put("out")
        pause(1)
    end

    echo("Scan complete. " .. Bodega.scan_count .. " shops scanned.")
end

local function cmd_display(opts)
    echo("Bodega v" .. VERSION .. " — current settings")
    echo("  Data directory: " .. BODEGA_DIR)
    echo("  Smart mode: " .. tostring(Bodega.smart_mode))
    echo("  Shops scanned this session: " .. Bodega.scan_count)
end

local function cmd_help()
    local out = "\n"
    out = out .. "Bodega v" .. VERSION .. " — Player Shop Scanner\n\n"
    out = out .. "Usage:\n"
    out = out .. "  ;bodega              — scan all shops in current directory\n"
    out = out .. "  ;bodega --smart      — smart scan (only inspect new/changed items)\n"
    out = out .. "  ;bodega --upload     — scan and upload results\n"
    out = out .. "  ;bodega display      — show current settings\n"
    out = out .. "  ;bodega help         — show this help\n"
    out = out .. "\n"
    out = out .. "Notes:\n"
    out = out .. "  - You must be at a player shop directory to scan\n"
    out = out .. "  - JSON files are saved to " .. BODEGA_DIR .. "/\n"
    out = out .. "  - The Bodega module is exposed for other scripts\n"
    out = out .. "\n"
    respond(out)
end

--------------------------------------------------------------------------------
-- Expose module globally for other scripts
--------------------------------------------------------------------------------
_G.Bodega = Bodega

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

ensure_dir(BODEGA_DIR)

local input = Script.vars[1] or ""
local opts = {
    smart  = input:find("%-%-smart") ~= nil,
    upload = input:find("%-%-upload") ~= nil,
}

if input:match("^%s*$") or input:match("%-%-smart") or input:match("%-%-upload") then
    cmd_scan(opts)
elseif input:match("display") then
    cmd_display(opts)
elseif input:match("help") or input:match("%?") then
    cmd_help()
else
    cmd_help()
end
