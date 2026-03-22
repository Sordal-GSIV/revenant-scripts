--- @revenant-script
--- name: inventory-manager
--- version: 2.0.0
--- author: Ethrel
--- game: dr
--- description: Cross-character inventory database — save, search, list, count, remove
--- tags: inventory, management, vault, storage, search, database
---
--- Ported from inventory-manager.lic (dr-scripts) to Revenant Lua
--- Original author: Ethrel
--- Changelog:
---   2.0.0 (2026-03-19) - Full conversion from dr-scripts/inventory-manager.lic:
---     save (character, vault_book, vault_standard, vault_family, vault_regular,
---     family_vault, register, eddy, storage_box, storage_book, scrolls, home,
---     servant, shop, pocket), search across all characters, list inventory,
---     count items, remove character data, nesting/container tracking,
---     inventory_manager_ignores, inventory_manager_vault_surfaces support,
---     version migration from legacy format
---   1.0.0             - Initial port
---
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;inventory-manager save                 - Save current character inventory
---   ;inventory-manager save vault_book      - Save vault via vault book
---   ;inventory-manager save vault_standard  - Save vault via VAULT STANDARD
---   ;inventory-manager save vault_family    - Save vault via VAULT FAMILY
---   ;inventory-manager save vault_regular   - Save vault via rummage (must be at open vault)
---   ;inventory-manager save family_vault    - Save family vault via rummage
---   ;inventory-manager save register        - Save deed register contents
---   ;inventory-manager save eddy            - Save eddy contents
---   ;inventory-manager save storage_box     - Save caravan storage box via rummage
---   ;inventory-manager save storage_book    - Save storage book contents
---   ;inventory-manager save scrolls         - Save spell scrolls from stacker
---   ;inventory-manager save home            - Save home inventory
---   ;inventory-manager save servant         - Save shadow servant inventory
---   ;inventory-manager save shop            - Save trader shop inventory
---   ;inventory-manager save pocket          - Save secret pocket contents
---   ;inventory-manager count                - Count all inventory items
---   ;inventory-manager count "purple pouch" - Count items matching description
---   ;inventory-manager search sword         - Search all characters for item
---   ;inventory-manager search sword --nest  - Search with nesting info
---   ;inventory-manager list                 - List all characters in database
---   ;inventory-manager list Charname        - List full inventory for character
---   ;inventory-manager list Charname --nest - List with nesting info
---   ;inventory-manager remove Charname      - Remove character from database

local args_lib = require("lib/args")

local ITEM_DB_PATH = "data/dr/inventory.json"
local VERSION = "2.00"

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local active_character = GameState.name
local item_data = {}
local settings = get_settings()
local inventory_ignores = settings.inventory_manager_ignores or {}
local vault_surfaces = settings.inventory_manager_vault_surfaces or {}

--------------------------------------------------------------------------------
-- Persistence / Helpers (defined before load_db which depends on them)
--------------------------------------------------------------------------------

--- Check if item string has a valid source tag.
local function valid_data_row(item)
  return item:find("%(vault%)") or item:find("%(register%)") or item:find("%(eddy%)")
      or item:find("%(caravan_box%)") or item:find("%(Family%)") or item:find("%(pocket%)")
      or item:find("%(character%)") or item:find("%(home%)") or item:find("%(shadow_servant%)")
      or item:find("%(trader_shop%)") or item:find("%(spell_scroll%)")
end

--- Save the inventory database to disk.
local function save_db()
  File.write(ITEM_DB_PATH, Json.encode(item_data))
end

--- Load the inventory database from disk.
local function load_db()
  if not File.exists(ITEM_DB_PATH) then
    -- Ensure data/dr directory exists
    if not File.is_dir("data/dr") then
      File.mkdir("data/dr")
    end
    item_data = { version = VERSION }
    File.write(ITEM_DB_PATH, Json.encode(item_data))
    return
  end

  local raw = File.read(ITEM_DB_PATH)
  if not raw or raw == "" then
    item_data = { version = VERSION }
    File.write(ITEM_DB_PATH, Json.encode(item_data))
    return
  end

  item_data = Json.decode(raw)
  if not item_data then
    DRC.message("Failed to parse inventory database!")
    item_data = { version = VERSION }
    return
  end

  -- Version migration from legacy format
  local ver = item_data.version
  if ver ~= VERSION then
    for k, v in pairs(item_data) do
      if k ~= "version" and type(v) == "table" then
        for i, item_str in ipairs(v) do
          if type(item_str) == "string" and not valid_data_row(item_str) then
            v[i] = item_str .. " (character)"
          end
        end
      end
    end
    item_data.version = VERSION
    save_db()
  end
end

--- Check if a string starts with any of the given prefixes.
local function starts_with_any(str, prefixes)
  if not prefixes or #prefixes == 0 then return false end
  for _, prefix in ipairs(prefixes) do
    if str:sub(1, #prefix) == prefix then return true end
  end
  return false
end

--- Get character data, clearing entries of a specific inventory type.
local function get_item_data(inventory_type)
  if item_data[active_character] then
    local filtered = {}
    for _, line in ipairs(item_data[active_character]) do
      if not line:find("%(" .. inventory_type .. "%)") then
        filtered[#filtered + 1] = line
      end
    end
    item_data[active_character] = filtered
  else
    item_data[active_character] = {}
  end
end

--- Save and announce.
local function save_item_data(inventory_type)
  DRC.message("Saving " .. inventory_type .. " data for " .. active_character .. "!")
  save_db()
end

--- Strip nesting information from an item string.
local function strip_nesting(item)
  -- Match: "item tap (in container - X) (origin)" or "item tap (nested container - X (in container - Y)) (origin)"
  -- Simplify to just "item tap (origin)"
  local re = Regex.new("(?i)^(?P<tap>[a-z \"':!-]*(?:\\(closed\\))?)\\s\\((?:(?:nested container[a-z \"':!-]*)\\s\\()?(?:in container[a-z \"':!-]*)\\)?\\)\\s(?P<origin>\\(.*\\))$")
  local caps = re:captures(item)
  if caps and caps.tap and caps.origin then
    return caps.tap .. " " .. caps.origin
  end
  return item
end

--- Clean home inventory string — remove category prefix and trailing period.
local function clean_home_string(str)
  local colon_pos = str:find(":")
  if colon_pos then
    local result = str:sub(colon_pos + 2)
    if result:sub(-1) == "." then
      result = result:sub(1, -2)
    end
    return result
  end
  return str
end

--- Issue a command and capture all output lines until the start_pattern is seen,
--- then collect until prompt. Uses quiet_command for multi-line capture.
local function capture_command(command, start_pattern, timeout)
  timeout = timeout or 5
  waitrt()
  local lines = quiet_command(command, start_pattern, nil, timeout)
  return lines or {}
end

--- Parse rummage output — splits comma-separated items including "and" separator.
local function parse_rummage(line, prefix_len)
  if not line or #line == 0 then return {} end
  local content = line:sub(prefix_len + 1)
  -- Remove trailing period if present
  if content:sub(-1) == "." then
    content = content:sub(1, -2)
  end
  local parts = {}
  for piece in content:gmatch("[^,]+") do
    parts[#parts + 1] = piece
  end
  -- The last element may contain " and " splitting two items
  if #parts > 0 then
    local last = parts[#parts]
    local and_pos = last:find(" and ")
    if and_pos then
      parts[#parts] = last:sub(1, and_pos - 1)
      parts[#parts + 1] = last:sub(and_pos + 5)
    end
  end
  return parts
end

--------------------------------------------------------------------------------
-- Inventory Capture
--------------------------------------------------------------------------------

--- Generic inventory check — sends command, captures output, parses items.
local function check_inventory(command, start_pattern, inventory_type, rummage_length)
  -- Pause sorter if running
  local using_sorter = Script.running("sorter")
  if using_sorter then
    Script.kill("sorter")
  end

  get_item_data(inventory_type)

  local lines
  if rummage_length and rummage_length > 0 then
    -- Rummage commands return a single line of comma-separated items
    -- Use capture_command which returns all lines; the rummage output is the first line
    local capture = capture_command(command, start_pattern)
    if #capture > 0 then
      lines = parse_rummage(capture[1], rummage_length)
    else
      lines = {}
    end
  else
    lines = capture_command(command, start_pattern)
  end

  local container = ""
  local sub_container = ""

  for _, raw_line in ipairs(lines) do
    local line = raw_line
    -- Remove item counts for vault standard
    if command == "vault standard" then
      line = line:gsub("%(%d+%)", "")
    end
    local item = line:match("^%s*(.-)%s*$")  -- trim

    if not item or item == "" then goto continue end
    if starts_with_any(item, inventory_ignores) then goto continue end
    if starts_with_any(item, vault_surfaces) then
      container = item
      goto continue
    end

    -- Items starting with "-" are in containers
    if item:sub(1, 1) == "-" then
      item = item:sub(2)
      -- Check indentation level for nesting
      if raw_line:match("^%s%s%s%s%s%s%s%s+%-") then
        item = item:match("^%s*(.-)%s*$")
        item = item .. " (nested container - " .. sub_container .. ")"
      elseif raw_line:match("^%s%s%s%s%s%-") then
        item = item:match("^%s*(.-)%s*$")
        item = item .. " (in container - " .. container .. ")"
        sub_container = item:match("^(.-)%s*%(in container") or item
      else
        item = item:match("^%s*(.-)%s*$")
        container = item
      end
    elseif inventory_type == "character" then
      -- Worn items on character
      container = item:find("eddy") and "eddy" or item
      item = item .. " (worn)"
    elseif command == "read my storage book" or command == "read my vault book" or inventory_type == "shadow_servant" then
      -- Book/servant format: indentation-based nesting
      if raw_line:match("^%s%s%s%s%s%s%s%s+%a") then
        item = item .. " (nested container - " .. sub_container .. ")"
      elseif raw_line:match("^%s%s%s%s%s%s%a") then
        item = item .. " (in container - " .. container .. ")"
        sub_container = item:match("^(.-)%s*%(in container") or item
      else
        container = item
      end
    elseif command == "vault standard" then
      -- Vault standard: wider indentation after count removal
      if raw_line:match("^%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s+%a") then
        item = item .. " (nested container - " .. sub_container .. ")"
      elseif raw_line:match("^%s%s%s%s%s%s%s%s%s%s%s%a") then
        item = item .. " (in container - " .. container .. ")"
        sub_container = item:match("^(.-)%s*%(in container") or item
      else
        container = item
      end
    elseif inventory_type == "home" then
      if not item:match("^Attached:") then
        item = clean_home_string(item)
        container = item
      else
        item = clean_home_string(item)
        item = item .. " (attached to " .. container .. ")"
      end
    end

    item = item .. " (" .. inventory_type .. ")"
    table.insert(item_data[active_character], item)

    ::continue::
  end

  save_item_data(inventory_type)

  if using_sorter then
    Script.run("sorter")
  end
end

--------------------------------------------------------------------------------
-- Save Commands
--------------------------------------------------------------------------------

local function add_vault_standard()
  check_inventory("vault standard", "Vault Inventory:", "vault")
end

local function add_vault_family()
  check_inventory("vault family", "Vault Inventory:", "Family")
end

local function add_vault_book()
  if not DRCI.get_item_if_not_held("vault book") then
    DRC.message("Unable to find your vault book, exiting!")
    return
  end
  check_inventory("read my vault book", "Vault Inventory", "vault")
  DRCI.stow_item("book")
end

local function add_current_inv()
  check_inventory("inv list", "You have:", "character")
end

local function add_register_inv()
  if not DRCI.get_item_if_not_held("register") then
    DRC.message("Unable to find your register, exiting!")
    return
  end
  DRC.bput("turn my register to contents",
    "You flip your deed register", "already at the table of contents")
  -- Check for empty register first, then capture deeds
  local result = dothistimeout("read my register", 5,
    "Stored Deeds:", "You haven't stored any deeds in this register")
  if result and result:find("Stored Deeds") then
    -- Register has deeds — capture remaining output
    local lines = {}
    local start = os.time()
    while os.time() - start < 5 do
      local line = get_noblock()
      if line then
        if line:find("<prompt") or line == "" then break end
        table.insert(lines, line)
      else
        pause(0.1)
      end
    end
    get_item_data("register")
    for _, raw_line in ipairs(lines) do
      local item = raw_line:match("^%s*(.-)%s*$")
      if item and item ~= "" and not starts_with_any(item, inventory_ignores) then
        item = item .. " (register)"
        table.insert(item_data[active_character], item)
      end
    end
    save_item_data("register")
  else
    DRC.message("No deeds stored in register.")
  end
  DRCI.stow_item("register")
end

local function add_eddy_inv()
  DRC.message("*WARNING: Character inventory includes items found within Eddy. Using both will duplicate Eddy items.")
  check_inventory("inv eddy", "Inside a", "eddy")
end

local function add_storage_box_inv()
  check_inventory("rummage storage box", "You rummage through a storage box", "caravan_box", 41)
end

local function add_storage_book()
  if not DRCI.get_item_if_not_held("storage book") then
    DRC.message("Unable to find your storage book, exiting!")
    return
  end
  check_inventory("read my storage book", "in the known realms since 402", "caravan_box")
  DRCI.stow_item("book")
end

local function add_family_vault()
  check_inventory("rummage vault", "You rummage through a vault", "Family", 42)
end

local function add_vault_regular_inv()
  check_inventory("rummage vault", "You rummage through a secure vault", "vault", 42)
end

local function add_pocket_inv()
  check_inventory("rummage my pocket", "You rummage through a pocket", "pocket", 36)
end

local function add_scrolls()
  local scroll_sorter = settings.scroll_sorter or {}
  local stacker_container = scroll_sorter.stacker_container or settings.stacker_container
  if not stacker_container then
    DRC.message("You have no stacker_container defined for sort-scrolls or stack-scrolls!")
    return
  end

  get_item_data("spell_scroll")

  local stacker = scroll_sorter.stacker
  local scroll_stackers = settings.scroll_stackers or {}

  DRCI.open_container("my " .. stacker_container)

  local spells = {}

  if stacker then
    -- Using sort-scrolls: get all ten books and parse them
    for _ = 1, 10 do
      DRCI.get_item("tenth " .. stacker, stacker_container)
      local capture = capture_command("flip my " .. stacker:match("%S+$"), "You flip through the")
      for _, line in ipairs(capture) do
        local section, count = line:match("The (.+) section has (%d+)")
        if section and count then
          spells[#spells + 1] = section .. " (" .. count .. ") (spell_scroll)"
        end
      end
      DRCI.put_away_item(stacker, stacker_container)
    end
  else
    -- Using stack-scrolls: loop through scroll_stackers
    for _, scroll_stacker in ipairs(scroll_stackers) do
      DRCI.get_item(scroll_stacker, stacker_container)
      local capture = capture_command("flip my " .. scroll_stacker:match("%S+$"), "You flip through the")
      for _, line in ipairs(capture) do
        local section, count = line:match("The (.+) section has (%d+)")
        if section and count then
          spells[#spells + 1] = section .. " (" .. count .. ") (spell_scroll)"
        end
      end
      DRCI.put_away_item(scroll_stacker, stacker_container)
    end
  end

  table.sort(spells)
  for _, spell in ipairs(spells) do
    table.insert(item_data[active_character], spell)
  end

  save_item_data("spell_scroll")

  if scroll_sorter.close_container then
    DRCI.close_container("my " .. stacker_container)
  end
end

local function add_home()
  check_inventory("home recall", "The home contains:", "home")
end

local function add_shadow_servant()
  if not DRStats.moon_mage() then
    DRC.message("You're not a Moon Mage!")
    return
  end

  local npcs = DRRoom.npcs or {}
  local servant_found = false
  for _, npc in ipairs(npcs) do
    if npc == "Servant" or (type(npc) == "string" and npc:find("Servant")) then
      servant_found = true
      break
    end
  end
  if not servant_found then
    DRC.message("Your Shadow Servant isn't present.")
    return
  end

  DRC.bput("prepare PG", "You raise")
  pause(3)
  check_inventory("cast servant", "Within the belly", "shadow_servant")
end

local function add_trader_shop()
  if not DRStats.trader() then
    DRC.message("You're not a Trader!")
    return
  end

  get_item_data("trader_shop")

  local capture = capture_command("shop customer", "The following items contain goods for sale:")
  local surfaces = {}

  -- Parse surface commands from XML-tagged output
  for _, line in ipairs(capture) do
    local trimmed = line:match("^%s*(.-)%s*$")
    -- Extract command and surface name from <d cmd='...'> tags
    local cmd_str, name = trimmed:match("<d cmd='(.-)'>(.-)</d>")
    if cmd_str and name then
      surfaces[#surfaces + 1] = { name = name, cmd = cmd_str }
    end
  end

  -- Browse each surface for items
  for _, surface in ipairs(surfaces) do
    local items_capture = capture_command(surface.cmd, ", you see:")
    for _, line in ipairs(items_capture) do
      local trimmed = line:match("^%s*(.-)%s*$")
      local _, item_name = trimmed:match("<d cmd='(.-)'>(.-)</d>")
      if item_name then
        table.insert(item_data[active_character],
          item_name .. " (" .. surface.name .. ") (trader_shop)")
      end
    end
  end

  save_item_data("trader_shop")
end

--------------------------------------------------------------------------------
-- Query Commands
--------------------------------------------------------------------------------

--- Count items in inventory.
local function get_inv_count(desc)
  local count, closed = 0, 0
  if not desc then
    -- Count all items
    local capture = capture_command("inv list", "You have:")
    for _, line in ipairs(capture) do
      local item = line:match("^%s*(.-)%s*$")
      if item ~= "" and not starts_with_any(item, inventory_ignores) then
        count = count + 1
        if item:find("%(closed%)") then
          closed = closed + 1
        end
      end
    end
    DRC.message("You have " .. count .. " items, " .. closed .. " of which are (closed) containers.")
  else
    -- Count items matching description
    local capture = capture_command("inv search " .. desc, "rummage about your person")
    for _, line in ipairs(capture) do
      local item = line:match("^%s*(.-)%s*$")
      if item ~= "" and not starts_with_any(item, inventory_ignores) then
        count = count + 1
      end
    end
    DRC.message("You have " .. count .. " items matching \"" .. desc .. "\".")
  end
end

--- List character inventory or all characters.
local function list_character_inv(name, nested)
  if not name then
    DRC.message("There is inventory data for:")
    for k, v in pairs(item_data) do
      if k ~= "version" then
        DRC.message(k .. " - " .. #v)
      end
    end
    return
  end

  -- Capitalize first letter
  local cap_name = name:sub(1, 1):upper() .. name:sub(2):lower()
  if item_data[cap_name] then
    DRC.message("Inventory for " .. cap_name)
    for _, item in ipairs(item_data[cap_name]) do
      local display = nested and item or strip_nesting(item)
      DRC.message("   - " .. display)
    end
  else
    DRC.message("No data found for the character " .. cap_name .. "!")
  end
end

--- Search for an item across all characters.
local function search_for_item(item, nested)
  for k, v in pairs(item_data) do
    if k ~= "version" then
      local total_found = 0
      DRC.message("Checking " .. k .. ":")
      for _, data in ipairs(v) do
        local display = nested and data or strip_nesting(data)
        if display:lower():find(item:lower(), 1, true) then
          total_found = total_found + 1
          DRC.message("Match " .. total_found .. "): " .. display)
        end
      end
      local suffix = total_found > 1 and "es" or ""
      DRC.message("Found " .. total_found .. " match" .. suffix .. " on " .. k .. "\n")
    end
  end
end

--- Remove a character's inventory from the database.
local function remove_character_data(name_to_remove)
  if not name_to_remove or name_to_remove:lower() == "version" then return end

  local cap_name = name_to_remove:sub(1, 1):upper() .. name_to_remove:sub(2):lower()
  item_data[cap_name] = nil
  save_db()
  DRC.message("Removed " .. cap_name .. "'s data!")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

load_db()

local args = args_lib.parse(Script.vars[0] or "")
local cmd = args.args[1] and args.args[1]:lower() or nil
local sub = args.args[2] and args.args[2]:lower() or nil
local nested = args.nest or args.n or false

-- Save subcommand dispatch table
local save_commands = {
  vault_book      = add_vault_book,
  vault_standard  = add_vault_standard,
  vault_family    = add_vault_family,
  vault_regular   = add_vault_regular_inv,
  family_vault    = add_family_vault,
  register        = add_register_inv,
  eddy            = add_eddy_inv,
  storage_box     = add_storage_box_inv,
  storage_book    = add_storage_book,
  scrolls         = add_scrolls,
  home            = add_home,
  servant         = add_shadow_servant,
  shop            = add_trader_shop,
  pocket          = add_pocket_inv,
}

if cmd == "save" then
  if sub and save_commands[sub] then
    save_commands[sub]()
  else
    add_current_inv()
  end
elseif cmd == "count" or cmd == "check" then
  -- Remaining args after "count" are the description
  local desc = nil
  if #args.args > 1 then
    local parts = {}
    for i = 2, #args.args do
      parts[#parts + 1] = args.args[i]
    end
    desc = table.concat(parts, " ")
  end
  get_inv_count(desc)
elseif cmd == "search" then
  local item = args.args[2]
  if not item then
    DRC.message("Usage: ;inventory-manager search <item> [--nest]")
    return
  end
  search_for_item(item, nested)
elseif cmd == "list" then
  list_character_inv(args.args[2], nested)
elseif cmd == "remove" then
  local name = args.args[2]
  if not name then
    DRC.message("Usage: ;inventory-manager remove <character_name>")
    return
  end
  remove_character_data(name)
else
  DRC.message("Usage: ;inventory-manager <save|count|search|list|remove> [options]")
  DRC.message("  save [source]   - Save inventory (sources: vault_book, vault_standard,")
  DRC.message("                    vault_family, vault_regular, family_vault, register,")
  DRC.message("                    eddy, storage_box, storage_book, scrolls, home,")
  DRC.message("                    servant, shop, pocket)")
  DRC.message("  count [desc]    - Count items (optionally matching description)")
  DRC.message("  search <item>   - Search all characters for item [--nest]")
  DRC.message("  list [name]     - List characters or specific character inventory [--nest]")
  DRC.message("  remove <name>   - Remove character from database")
end
