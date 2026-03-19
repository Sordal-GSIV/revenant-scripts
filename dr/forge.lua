--- @revenant-script
--- name: forge
--- version: 2.0.0
--- author: Elanthia Online (lic), Seped/Mallitek (original)
--- game: dr
--- description: Blacksmithing, armorsmithing, and weaponsmithing automation.
--- tags: crafting, forging, weapons, armor, blacksmithing
--- @lic-certified: complete 2026-03-18
---
--- Handles the complete forging workflow:
---   - Crafting new items from book recipes or instructions
---   - Tempering finished weapons/armor
---   - Enhancements: honing, balancing, lightening, reinforcing
---   - Automatic forge rental renewal
---   - Assembly of multi-part items (hilts, handles, padding)
---   - Private forge navigation
---
--- Usage:
---   ;forge [finish] <book_type> <chapter> <recipe_name> <metal> <noun> [skip] [debug]
---   ;forge [finish] instructions <metal> <noun> [skip] [debug]
---   ;forge <enhancement> <noun> [skip] [debug]
---   ;forge resume <book_type> <noun> [debug]
---
--- Arguments:
---   finish       hold|log|stow|trash  What to do with the finished item (default: hold)
---   book_type    blacksmithing|armorsmithing|weaponsmithing
---   chapter      Chapter number in the recipe book
---   recipe_name  Recipe name (quote multi-word: "steel throwing hammer")
---   metal        Metal type (e.g., steel, mithril, vultite)
---   noun         Noun of the item being crafted
---   enhancement  temper|balance|hone|lighten|reinforce
---   skip         Skip restocking consumables
---   debug        Show debug output
---
--- Examples:
---   ;forge weaponsmithing 4 "steel throwing hammer" steel hammer
---   ;forge instructions steel sword
---   ;forge temper sword
---   ;forge hone sword
---   ;forge resume weaponsmithing hammer
---   ;forge log weaponsmithing 4 "steel throwing hammer" steel hammer

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

--- Split a string into tokens, respecting double-quoted substrings.
local function split_args(s)
  if not s or s == "" then return {} end
  local tokens = {}
  local i = 1
  while i <= #s do
    while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end
    if i > #s then break end
    if s:sub(i, i) == '"' then
      i = i + 1
      local j = s:find('"', i, true)
      if j then
        tokens[#tokens + 1] = s:sub(i, j - 1)
        i = j + 1
      else
        tokens[#tokens + 1] = s:sub(i)
        break
      end
    else
      local j = s:find("%s", i)
      if j then
        tokens[#tokens + 1] = s:sub(i, j - 1)
        i = j
      else
        tokens[#tokens + 1] = s:sub(i)
        break
      end
    end
  end
  return tokens
end

local FINISH_OPTS    = { hold = true, log = true, stow = true, trash = true }
local ENHANCEMENTS   = { temper = true, balance = true, hone = true, lighten = true, reinforce = true }
local BOOK_TYPES     = { blacksmithing = true, armorsmithing = true, weaponsmithing = true }

--- Parse command-line arguments. Returns a table or nil on error.
local function parse_args()
  local argv = split_args(Script.vars and Script.vars[0] or "")
  if #argv == 0 then return nil end

  local args = {}
  local idx = 1

  -- resume mode: ;forge resume <book_type> <noun> [debug]
  if argv[idx] and argv[idx]:lower() == "resume" then
    args.resume = true
    idx = idx + 1
    local bt = argv[idx] and argv[idx]:lower()
    if bt and BOOK_TYPES[bt] then
      args.book_type = bt
      idx = idx + 1
    end
    args.noun = argv[idx]; idx = idx + 1
    while argv[idx] do
      if argv[idx]:lower() == "debug" then args.debug = true end
      idx = idx + 1
    end
    return args
  end

  -- Optional finish flag
  local first = argv[idx] and argv[idx]:lower()
  if first and FINISH_OPTS[first] then
    args.finish = first
    idx = idx + 1
  else
    args.finish = "hold"
  end

  local cur = argv[idx] and argv[idx]:lower()

  -- Enhancement mode: ;forge [finish] <enhancement> <noun> [skip] [debug]
  if cur and ENHANCEMENTS[cur] then
    args.recipe_name = cur
    idx = idx + 1
    args.noun = argv[idx]; idx = idx + 1
    while argv[idx] do
      local v = argv[idx]:lower()
      if v == "skip" then args.skip = true
      elseif v == "debug" then args.debug = true end
      idx = idx + 1
    end
    return args
  end

  -- Instructions mode: ;forge [finish] instructions <metal> <noun> [skip] [debug]
  if cur and cur == "instructions" then
    args.instructions = true
    idx = idx + 1
    args.metal = argv[idx]; idx = idx + 1
    args.noun  = argv[idx]; idx = idx + 1
    while argv[idx] do
      local v = argv[idx]:lower()
      if v == "skip" then args.skip = true
      elseif v == "debug" then args.debug = true end
      idx = idx + 1
    end
    return args
  end

  -- Book recipe mode: ;forge [finish] <book_type> <chapter> <recipe_name> <metal> <noun> [skip] [debug]
  if cur and BOOK_TYPES[cur] then
    args.book_type   = cur;         idx = idx + 1
    args.chapter     = argv[idx];   idx = idx + 1
    args.recipe_name = argv[idx];   idx = idx + 1
    args.metal       = argv[idx];   idx = idx + 1
    args.noun        = argv[idx];   idx = idx + 1
    while argv[idx] do
      local v = argv[idx]:lower()
      if v == "skip" then args.skip = true
      elseif v == "debug" then args.debug = true end
      idx = idx + 1
    end
    return args
  end

  return nil
end

-------------------------------------------------------------------------------
-- Parse and validate args up front
-------------------------------------------------------------------------------

local args = parse_args()
if not args then
  echo("Usage:")
  echo("  ;forge [hold|log|stow|trash] <blacksmithing|armorsmithing|weaponsmithing> <chapter> <recipe_name> <metal> <noun> [skip] [debug]")
  echo("  ;forge [hold|log|stow|trash] instructions <metal> <noun> [skip] [debug]")
  echo("  ;forge <temper|balance|hone|lighten|reinforce> <noun> [skip] [debug]")
  echo("  ;forge resume <blacksmithing|armorsmithing|weaponsmithing> <noun> [debug]")
  return
end

-------------------------------------------------------------------------------
-- Load settings
-------------------------------------------------------------------------------

local settings      = get_settings()
local hometown      = settings.hometown
local bag           = settings.crafting_container
local bag_items     = settings.crafting_items_in_container or {}
local forging_belt  = settings.forging_belt
local stamp         = settings.mark_crafted_goods
local cube          = settings.cube_armor_piece

-- Find hammer or mallet in forging_tools
local hammer = nil
if settings.forging_tools then
  for _, tool in ipairs(settings.forging_tools) do
    if tool:find("hammer") or tool:find("mallet") then
      hammer = tool
      break
    end
  end
end

-- Resolve enhancement aliases to full recipe names
local function resolve_recipe_name(name)
  if name == "hone"      then return "metal weapon honing"
  elseif name == "balance" then return "metal weapon balancing"
  elseif name == "lighten" then return "metal armor lightening"
  elseif name == "reinforce" then return "metal armor reinforcing"
  else return name
  end
end

local item        = args.noun
local metal       = args.metal
local chapter     = args.chapter
local book_type   = args.book_type
local recipe_name = resolve_recipe_name(args.recipe_name)
local finish      = args.finish or "hold"
local use_resume  = args.resume
local instruction = args.instructions
local debug_mode  = args.debug or settings.debug_mode
local use_private = settings.forge_use_private_forge
local private_cost = settings.forge_private_forge_cost or 5000
local show_progress = (settings.forge_show_progress ~= false)  -- default true
local adjustable_tongs = false
local next_spin   = 0    -- os.time() when grindstone is fast enough (cooldown)
local _script_done = false  -- set to true by complete_crafting/cleanup_and_exit to break work loop

-- Crafting data for this hometown
local crafting_info = nil
do
  local ok, data = pcall(get_data, "crafting")
  if ok and data and data.blacksmithing and hometown then
    crafting_info = data.blacksmithing[hometown]
  end
end

-- Current work command and location
local command      = nil
local home_tool    = nil
local home_command = nil
local location     = nil   -- "on anvil" / "on forge" / nil (held)

-------------------------------------------------------------------------------
-- Logging helpers
-------------------------------------------------------------------------------

local function debug_log(msg)
  if debug_mode then respond("[forge] " .. tostring(msg)) end
end

local function error_log(msg)
  respond("\27[1m[forge] " .. tostring(msg) .. "\27[0m")
end

local function info_log(msg)
  respond("[forge] " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Cleanup / exit
-------------------------------------------------------------------------------

local function magic_cleanup()
  DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
  DRC.bput("release mana",  "You release all",                  "You aren't harnessing any mana")
  DRC.bput("release symb",  "But you haven't",                  "You release", "Repeat this command")
end

local function stow_both_hands()
  DRCC.stow_crafting_item(DRC.right_hand(), bag, forging_belt)
  DRCC.stow_crafting_item(DRC.left_hand(),  bag, forging_belt)
end

local function cleanup_and_exit(msg)
  error_log(msg)
  _script_done = true
  stow_both_hands()
  magic_cleanup()
  Script.kill(Script.name)
end

-------------------------------------------------------------------------------
-- Tool management
-------------------------------------------------------------------------------

local function verify_tool_in_hand(next_tool)
  local check = (next_tool == "shovel" and adjustable_tongs) and "tongs" or next_tool
  if not DRCI.in_hands(check) then
    cleanup_and_exit("Failed to get " .. next_tool .. ".")
  end
end

local function get_tool(next_tool, skip)
  if next_tool == "tongs" then
    debug_log("Getting tongs (AjT false)")
    DRCC.get_crafting_item(next_tool, bag, bag_items, forging_belt)
  else
    DRCC.stow_crafting_item(DRC.right_hand(), bag, forging_belt)
    DRCC.get_crafting_item(next_tool, bag, bag_items, forging_belt, skip)
  end
end

local function swap_tool(next_tool, skip)
  debug_log("Next tool: " .. tostring(next_tool))
  debug_log("Holding it? " .. tostring(DRCI.in_hands(next_tool)))
  if next_tool:find("tongs") and adjustable_tongs then
    debug_log("Making tongs into tongs")
    DRCC.get_adjust_tongs("tongs", bag, bag_items, forging_belt, adjustable_tongs)
  elseif next_tool:find("shovel") and adjustable_tongs then
    debug_log("Making tongs into shovel")
    DRCC.get_adjust_tongs("shovel", bag, bag_items, forging_belt, adjustable_tongs)
  elseif not DRCI.in_hands(next_tool) then
    get_tool(next_tool, skip)
  end
  verify_tool_in_hand(next_tool)
end

local function ready_hammer_with_tongs()
  swap_tool(hammer)
  swap_tool("tongs")
end

local function stow_hammer_and_tongs()
  if DRCI.in_hands(hammer) then DRCC.stow_crafting_item(hammer, bag, forging_belt) end
  if DRCI.in_hands("tongs") then DRCC.stow_crafting_item("tongs", bag, forging_belt) end
end

-------------------------------------------------------------------------------
-- Item-in-hand helpers
-------------------------------------------------------------------------------

local function ensure_item_in_left_hand(target_item)
  target_item = target_item or item
  if DRCI.in_left_hand(target_item) then return end
  if DRCI.in_right_hand(target_item) then
    DRC.bput("swap", "You move", "You have nothing")
  else
    cleanup_and_exit("MISSING " .. target_item .. ". Please find it and restart.")
  end
end

local function prepare_item_in_left_hand(loc, context)
  loc     = loc or "on anvil"
  context = context or "work"
  if DRCI.in_left_hand(item) then return true end
  stow_hammer_and_tongs()
  local result = DRC.bput("get " .. item .. " " .. loc,
    "You get", "What were you referring to")
  if result:find("What were you") then
    error_log("Failed to get " .. item .. " from " .. loc .. " for " .. context)
  end
  ensure_item_in_left_hand()
  return true
end

-------------------------------------------------------------------------------
-- Validation
-------------------------------------------------------------------------------

local function validate_crafting_container()
  if not bag then
    cleanup_and_exit("No crafting_container configured in your YAML settings.")
  end
end

local function validate_hammer()
  if not hammer then
    cleanup_and_exit("No hammer or mallet found in forging_tools setting.")
  end
end

local function validate_free_hand()
  local right = DRC.right_hand()
  local left  = DRC.left_hand()
  local right_ok  = right == nil or right:find(item, 1, true) ~= nil
  local left_ok   = left  == nil or left:find(item, 1, true)  ~= nil
  local free_hand = right == nil or left == nil
  if free_hand and right_ok and left_ok then return end
  local held = {}
  if right and not right:find(item, 1, true) then held[#held + 1] = right end
  if left  and not left:find(item, 1, true)  then held[#held + 1] = left  end
  error_log("Need a free hand to forge. Currently holding: " .. table.concat(held, " and "))
  cleanup_and_exit("Please stow extra items and try again.")
end

local function setup_adjustable_tongs()
  adjustable_tongs = DRCC.get_adjust_tongs("reset tongs", bag, bag_items, forging_belt)
  debug_log("Tongs adjustable? " .. tostring(adjustable_tongs))
  DRCC.stow_crafting_item("tongs", bag, forging_belt)
end

-------------------------------------------------------------------------------
-- Navigation: private forge
-------------------------------------------------------------------------------

local PRIVATE_ENTRY_OK      = { "You head through", "You walk", "You go", "Obvious exits" }
local PRIVATE_ENTRY_BLOCKED = { "You don't have enough", "The sentry blocks",
                                "cannot enter", "You need to pay" }

local function attempt_private_forge_entry()
  debug_log("Attempting manual entry into private forge...")
  local all = {}
  for _, p in ipairs(PRIVATE_ENTRY_OK)      do all[#all + 1] = p end
  for _, p in ipairs(PRIVATE_ENTRY_BLOCKED) do all[#all + 1] = p end
  all[#all + 1] = "What were you"
  local result = DRC.bput("go door", table.unpack(all))
  for _, p in ipairs(PRIVATE_ENTRY_BLOCKED) do
    if result:find(p, 1, true) then
      error_log("BLOCKED from entering private forge. Check balance/restrictions.")
      cleanup_and_exit("Use a public forge or resolve the issue.")
      return
    end
  end
  if result:find("What were you") then
    error_log("No door found for private forge. Falling back to current location.")
  else
    info_log("Entered private forge.")
  end
end

local function go_to_private_forge()
  if not crafting_info then
    error_log("No crafting data for hometown '" .. tostring(hometown) .. "'. Using public forge.")
    return
  end
  local private_room = crafting_info["private_forge"]
  if not private_room then
    error_log("No private_forge defined for " .. tostring(hometown) .. ". Using public forge.")
    return
  end
  debug_log("Private forge room: " .. tostring(private_room))
  debug_log("Private forge cost: " .. tostring(private_cost) .. " copper")
  if not DRCM.ensure_copper_on_hand(private_cost, settings, hometown) then
    cleanup_and_exit("Unable to get " .. tostring(private_cost) .. " copper for private forge rental.")
  end
  debug_log("Navigating to private forge...")
  DRCT.walk_to(private_room)
  local cur = Map.current_room and Map.current_room() or GameState.room_id
  if cur == private_room then
    info_log("Arrived at private forge.")
    return
  end
  attempt_private_forge_entry()
end

-------------------------------------------------------------------------------
-- Rental management
-------------------------------------------------------------------------------

local MONTH_NUMS = {
  Jan=1, Feb=2, Mar=3, Apr=4,  May=5,  Jun=6,
  Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12,
}

--- Determine current US Eastern UTC offset in seconds.
local function eastern_utc_offset_secs()
  local utc = os.date("!*t", os.time())
  local year = utc.year
  -- US DST: 2nd Sunday March at 7:00 UTC → 1st Sunday November at 6:00 UTC
  local function first_sunday(month)
    local t = os.date("!*t", os.time{year=year, month=month, day=1, hour=0, min=0, sec=0})
    -- t.wday: 1=Sunday
    local days_until_sun = (8 - t.wday) % 7
    return 1 + days_until_sun
  end
  local mar_sun1 = first_sunday(3)
  local mar_sun2 = mar_sun1 + 7   -- 2nd Sunday
  local nov_sun1 = first_sunday(11)
  local dst_start = os.time{year=year, month=3,  day=mar_sun2, hour=7, min=0, sec=0}
  local dst_end   = os.time{year=year, month=11, day=nov_sun1, hour=6, min=0, sec=0}
  local now = os.time()
  return (now >= dst_start and now < dst_end) and (-4 * 3600) or (-5 * 3600)
end

--- Parse a DR Eastern-time string and return a rough Unix timestamp for comparison.
-- Format: "Sun Dec 28 23:39:15 ET 2025"
-- Note: assumes machine clock is reasonably close to Eastern time; off by ≤1h in other TZs.
local function parse_rental_expire(expire_str)
  local _, mon, day, h, m, s, year =
    expire_str:match("(%a+) (%a+) (%d+) (%d+):(%d+):(%d+) ET (%d+)")
  if not mon then return nil end
  local month = MONTH_NUMS[mon]
  if not month then return nil end
  -- Convert ET components to approximate UTC epoch:
  -- Treat as local time (os.time), then adjust by (local_offset - ET_offset).
  local et_off    = eastern_utc_offset_secs()
  local local_off = os.time() - os.time(os.date("!*t", os.time()))
  -- parsed as local-time epoch:
  local parsed_local = os.time{
    year  = tonumber(year),
    month = month,
    day   = tonumber(day),
    hour  = tonumber(h),
    min   = tonumber(m),
    sec   = tonumber(s),
  }
  -- actual UTC epoch of this ET wall-clock time:
  local expire_utc = parsed_local + local_off - et_off
  return expire_utc
end

local function renew_forge_rental()
  error_log("FORGE RENTAL EXPIRING — AUTO-RENEWING")
  Flags.reset("forge-rental-warning")
  local result = DRC.bput("mark notice",
    "You mark the notice", "renewed your rental", "extends your rental",
    "You don't have enough", "I could not find")
  if result:find("enough") then
    error_log("INSUFFICIENT FUNDS TO RENEW RENTAL")
  elseif result:find("could not find") then
    error_log("COULD NOT FIND NOTICE — CHECK LOCATION")
  else
    info_log("RENTAL RENEWED")
  end
end

local function check_rental_status()
  local result = DRC.bput("read notice",
    "It will expire", "I could not find", "What were you referring to")
  if not result:find("It will expire") then return end
  local expire_str = result:match("It will expire (.-)%.")
  if not expire_str then return end
  local expire_ts = parse_rental_expire(expire_str)
  if not expire_ts then
    error_log("Could not parse rental time: " .. expire_str)
    return
  end
  local minutes_remaining = math.floor((expire_ts - os.time()) / 60)
  debug_log("Rental expires: " .. expire_str .. " (" .. tostring(minutes_remaining) .. " min remaining)")
  if minutes_remaining < 10 then
    error_log("RENTAL LOW (" .. tostring(minutes_remaining) .. " min) — PRE-EMPTIVELY RENEWING")
    renew_forge_rental()
  elseif minutes_remaining < 20 then
    info_log("Rental has " .. tostring(minutes_remaining) .. " minutes remaining")
  end
end

-------------------------------------------------------------------------------
-- Consumable management
-------------------------------------------------------------------------------

local function check_all_consumables()
  if not crafting_info then return end
  DRCC.check_consumables("oil",        crafting_info["finisher-room"],
    crafting_info["finisher-number"],  bag, bag_items, forging_belt)
  local wire_brush_num = crafting_info["wire-brush-number"] or 10
  DRCC.check_consumables("wire brush", crafting_info["finisher-room"],
    wire_brush_num,                    bag, bag_items, forging_belt)
end

-------------------------------------------------------------------------------
-- Grindstone management
-------------------------------------------------------------------------------

local SPIN_MAX_RETRIES = 10

local function spin_grindstone(retries)
  retries = retries or SPIN_MAX_RETRIES
  if retries <= 0 then
    cleanup_and_exit("Failed to spin grindstone after " .. SPIN_MAX_RETRIES .. " attempts.")
    return
  end
  waitrt()
  if os.time() <= next_spin then return end
  local result = DRC.bput("turn grind",
    "keeping it spinning fast", "making it spin even faster",
    "not spinning fast enough", "Roundtime",
    "Turn what")
  if result:find("Turn what") then
    if crafting_info then DRCC.find_grindstone(hometown) end
    spin_grindstone(retries - 1)
  elseif result:find("not spinning fast enough") or result:find("Roundtime") then
    spin_grindstone(retries - 1)
  else
    next_spin = os.time() + 20
  end
end

-------------------------------------------------------------------------------
-- Progress reporting
-------------------------------------------------------------------------------

local function analyze_progress()
  local target = DRCI.in_hands(item) and ("my " .. item) or (item .. " " .. (location or ""))
  local result = DRC.bput("analyze " .. target,
    "practically finished", "final stage of completion",
    "approximately", "signs of", "I could not find", "Roundtime")
  local info = {}
  if result:find("practically finished") or result:find("final stage") then
    info.percent = 99
  else
    local pct = result:match("approximately (%d+)%%")
    if pct then info.percent = tonumber(pct) end
  end
  local quality = result:match("signs of (.-)%s+craftsmanship")
  if quality then info.quality = quality end
  if not info.percent and not info.quality then return nil end
  return info
end

local function report_progress_milestone(phase)
  if not show_progress then return end
  local progress = analyze_progress()
  if not progress then return end
  local pct_str = progress.percent and (tostring(progress.percent) .. "%") or "unknown"
  local qual_str = progress.quality or "unknown"
  info_log("[" .. phase .. "] Progress: " .. pct_str .. " | Quality: " .. qual_str)
end

-------------------------------------------------------------------------------
-- Assembly
-------------------------------------------------------------------------------

--- Extract the part noun from a forge-assembly matched game line.
-- Game text contains the part name inside parentheses, e.g.:
--   "another finished iron shield (handle)"
--   "appears ready to be reinforced with some (leather strips)"
local function extract_assembly_part(line)
  if not line then return nil end
  return line:match("%((.-)%)")
end

local function assemble_part()
  local asm_line = Flags["forge-assembly"]
  while asm_line do
    local tool = DRC.right_hand()
    DRCC.stow_crafting_item(tool, bag, forging_belt)
    local part = extract_assembly_part(asm_line)
    if not part then
      error_log("Could not determine assembly part from: " .. asm_line)
      break
    end
    if not DRCI.get_item(part) then
      cleanup_and_exit("Missing " .. part .. ". Cannot continue assembly.")
      return
    end
    local result = DRC.bput("assemble my " .. item .. " with my " .. part,
      "affix it securely in place",
      "and tighten the pommel to secure it",
      "carefully mark where it will attach when you continue crafting",
      "You layer the leather strips",
      "is not required to continue crafting")
    if result:find("not required") then
      DRCI.put_away_item(part, bag)
    end
    if tool then swap_tool(tool) end
    asm_line = Flags["forge-assembly"]
  end
end

-------------------------------------------------------------------------------
-- Ingot restow
-------------------------------------------------------------------------------

local function restow_ingot(ingot_line)
  local tool = DRC.right_hand()
  local temp_bag = ingot_line:match("in your (.-)%.")
  if not temp_bag then return end
  if bag:find(temp_bag, 1, true) then return end  -- already in the right bag
  DRCC.stow_crafting_item(tool, bag, forging_belt)
  if DRCI.get_item(metal .. " ingot", temp_bag) then
    if not DRCI.put_away_item(metal .. " ingot", bag) then
      error_log("Failed to stow " .. metal .. " ingot in " .. bag)
    end
  end
  if tool then swap_tool(tool) end
end

-------------------------------------------------------------------------------
-- Item location (for resume)
-------------------------------------------------------------------------------

local function configure_held_item_resume()
  recipe_name = "metal weapon balancing"
  command     = "analyze my " .. item
end

local function configure_anvil_resume()
  home_tool    = hammer
  recipe_name  = "metal thing"
  home_command = "pound " .. item .. " on anvil with my " .. hammer
  command      = "analyze " .. item .. " on anvil"
  location     = "on anvil"
end

local function configure_forge_resume()
  recipe_name  = "temper"
  home_tool    = "tongs"
  home_command = "turn " .. item .. " on forge with my tongs"
  stamp        = false
  command      = "analyze " .. item .. " on forge"
  location     = "on forge"
end

local function find_item()
  if DRCI.in_hands(item) then configure_held_item_resume(); return end
  local anvil_result = DRC.bput("look on anvil", "anvil you see", "clean and ready")
  if anvil_result:find("anvil you see") then configure_anvil_resume(); return end
  local forge_result = DRC.bput("look on forge", "forge you see", "There is nothing")
  if forge_result:find("forge you see") then configure_forge_resume(); return end
  cleanup_and_exit(item .. " not found on anvil, forge, or in hands.")
end

-------------------------------------------------------------------------------
-- Defaults setup
-------------------------------------------------------------------------------

local function setup_temper_defaults()
  home_tool    = "tongs"
  home_command = "turn " .. item .. " on forge with my tongs"
  stamp        = false
  swap_tool("tongs")
  ensure_item_in_left_hand("tongs")
  location     = "on forge"
  command      = command or ("put my " .. item .. " on the forge")
end

local function setup_weapon_enhancement_defaults()
  home_tool    = "wire brush"
  home_command = "push grindstone with my " .. item
  ensure_item_in_left_hand()
  if not use_resume then spin_grindstone() end
  chapter   = 10
  book_type = "weaponsmithing"
  stamp     = false
end

local function setup_armor_enhancement_defaults()
  home_tool    = "pliers"
  home_command = "push grindstone with my " .. item
  command      = command or ("pull my " .. item .. " with my pliers")
  ensure_item_in_left_hand()
  chapter   = 5
  book_type = "armorsmithing"
  stamp     = false
end

local function setup_crafting_defaults()
  location     = "on anvil"
  home_tool    = hammer
  home_command = "pound " .. item .. " on anvil with my " .. hammer
end

local function set_defaults()
  if recipe_name == "temper" then
    setup_temper_defaults()
  elseif recipe_name == "metal weapon honing" or recipe_name == "metal weapon balancing" then
    setup_weapon_enhancement_defaults()
  elseif recipe_name == "metal armor lightening" or recipe_name == "metal armor reinforcing" then
    setup_armor_enhancement_defaults()
  else
    setup_crafting_defaults()
  end
  debug_log("Recipe:       " .. tostring(recipe_name))
  debug_log("Home tool:    " .. tostring(home_tool))
  debug_log("Home command: " .. tostring(home_command))
  debug_log("Location:     " .. tostring(location))
  debug_log("Item noun:    " .. tostring(item))
end

-------------------------------------------------------------------------------
-- Preparation
-------------------------------------------------------------------------------

local function touch_cube()
  DRC.bput("touch my " .. cube,
    "Warm vapor swirls around your head",
    "A thin cloud of vapor manifests",
    "Touch what")
end

local function study_instructions()
  local result = DRC.bput("study my instructions", "Roundtime", "Study them again")
  if result:find("again") then
    DRC.bput("study my instructions", "Roundtime", "Study them again")
  end
end

local function prep_with_instructions()
  DRCC.get_crafting_item(item .. " instructions", bag, bag_items, forging_belt)
  if not DRCI.in_hands("instructions") then
    cleanup_and_exit("Failed to get " .. item .. " instructions.")
    return
  end
  study_instructions()
  DRCC.stow_crafting_item(item .. " instructions", bag, forging_belt)
end

local function warn_about_skill_cap()
  if DRSkill.getrank("Forging") == 175 then
    error_log("You will need to upgrade to a journeyman or master book before 176 ranks!")
  end
end

local function prep_with_book()
  if settings.master_crafting_book then
    DRCC.get_crafting_item(settings.master_crafting_book, bag, bag_items, forging_belt)
    if not DRCI.in_hands(settings.master_crafting_book) then
      cleanup_and_exit("Failed to get master crafting book.")
      return
    end
    DRCC.find_recipe2(chapter, recipe_name, settings.master_crafting_book, book_type)
    DRCC.stow_crafting_item(settings.master_crafting_book, bag, forging_belt)
  else
    -- Individual book
    DRCC.get_crafting_item(book_type .. " book", bag, bag_items, forging_belt)
    if not DRCI.in_hands("book") then
      cleanup_and_exit("Failed to get " .. tostring(book_type) .. " book.")
      return
    end
    warn_about_skill_cap()
    DRCC.find_recipe2(chapter, recipe_name)
    DRCC.stow_crafting_item("book", bag, forging_belt)
  end
end

local function prep_ingot()
  DRCC.get_crafting_item(metal .. " ingot", bag, bag_items, forging_belt, true)
  if not DRCI.in_hands("ingot") then
    cleanup_and_exit("Failed to get " .. metal .. " ingot.")
    return
  end
  DRC.bput("put my ingot on anvil", "You put")
  ready_hammer_with_tongs()
  command = "pound ingot on anvil with my " .. hammer
end

local function prep()
  DRCA.crafting_magic_routine(settings)
  if instruction then
    prep_with_instructions()
  elseif not recipe_name:find("temper") then
    prep_with_book()
  end
  swap_tool(home_tool)
  if metal then prep_ingot() end
end

-------------------------------------------------------------------------------
-- Completion
-------------------------------------------------------------------------------

local function stamp_item()
  swap_tool("stamp")
  DRC.bput("mark my " .. item .. " with my stamp",
    "carefully hammer the stamp",
    "You cannot figure out how to do that",
    "too badly damaged")
  DRCC.stow_crafting_item("stamp", bag, forging_belt)
end

local function finalize_item()
  if finish:find("log") then
    DRCC.logbook_item("engineering", item, bag)
    info_log(item .. " logged to engineering logbook.")
  elseif finish:find("stow") then
    if DRCC.stow_crafting_item(item, bag, forging_belt) then
      info_log(item .. " stowed in " .. bag)
    else
      error_log("Failed to stow " .. item .. ". Item may still be in hand.")
    end
  elseif finish:find("trash") then
    DRCI.dispose_trash(item)
    info_log(item .. " disposed.")
  else
    info_log(item .. " complete. Holding in hand.")
  end
end

local function complete_crafting()
  _script_done = true
  DRCC.stow_crafting_item(DRC.right_hand(), bag, forging_belt)
  if stamp then stamp_item() end
  finalize_item()
  magic_cleanup()
  Flags.delete("forge-assembly")
  Flags.delete("work-done")
  Flags.delete("ingot-restow")
  Flags.delete("forge-rental-warning")
  Script.kill(Script.name)
end

-------------------------------------------------------------------------------
-- Work result handlers
-------------------------------------------------------------------------------

local function handle_tool_not_suitable()
  swap_tool(home_tool)
  command = home_command
end

local function handle_temper_continue()
  swap_tool("tongs")
  command = "turn " .. item .. " on forge with my tongs"
end

local function handle_temper_already_done()
  error_log(item .. " has already been tempered. Further heating would damage it.")
  cleanup_and_exit("Nothing to do.")
end

local function handle_fuel_needed()
  local shovel_item = adjustable_tongs and "tongs" or "shovel"
  debug_log("Tool for shovel (AjT=" .. tostring(adjustable_tongs) .. "): " .. shovel_item)
  swap_tool("shovel")
  command = "push fuel with my " .. shovel_item
end

local function handle_bellows_needed()
  swap_tool("bellows")
  command = "push my bellows"
end

local function handle_tongs_turn()
  ready_hammer_with_tongs()
  command = "turn " .. item .. " on anvil with my tongs"
end

local function handle_cooling()
  report_progress_milestone("Cooling")
  stow_both_hands()
  command = "push tub"
end

local function handle_wire_brush()
  swap_tool("wire brush")
  command = "rub my " .. item .. " with my brush"
end

local function handle_pounding()
  if DRCI.in_hands(item) then
    DRC.bput("put my " .. item .. " on anvil", "You put")
  end
  ready_hammer_with_tongs()
  command = "pound " .. item .. " on anvil with my " .. hammer
end

local function handle_grindstone()
  report_progress_milestone("Grinding")
  prepare_item_in_left_hand("from anvil", "grindstone work")
  if use_resume then home_tool = "wire brush" end
  command = "push grindstone with my " .. item
end

local function handle_pliers()
  report_progress_milestone("Pliers")
  prepare_item_in_left_hand("from anvil", "pliers work")
  swap_tool("pliers")
  command = "pull my " .. item .. " with my pliers"
end

local function handle_oiling()
  report_progress_milestone("Oiling")
  if home_tool == "tongs" or not DRCI.in_left_hand(item) then
    DRCC.stow_crafting_item(DRC.left_hand(), bag, forging_belt)
    local r = DRC.bput("get " .. item .. " " .. (location or ""),
      "You get", "What were you referring to")
    if r:find("What were you") then
      error_log("Failed to get " .. item .. " from " .. tostring(location) .. " for oiling.")
    end
  end
  ensure_item_in_left_hand()
  swap_tool("oil", true)
  command = "pour my oil on my " .. item
end

local function handle_oil_empty()
  if crafting_info then
    DRCC.check_consumables("oil", crafting_info["finisher-room"],
      crafting_info["finisher-number"], bag, bag_items, forging_belt)
  end
  swap_tool("oil")
end

local function handle_handle_assembly()
  local r = DRC.bput("get " .. item .. " from anvil", "You get", "What were you referring to")
  if r:find("What were you") then
    error_log("Failed to get " .. item .. " from anvil for handle assembly.")
  end
  ensure_item_in_left_hand()
  assemble_part()
  DRC.bput("put my " .. item .. " on anvil", "You put")
  ready_hammer_with_tongs()
  command = "pound " .. item .. " on anvil with my " .. hammer
end

local function handle_roundtime()
  waitrt()
  local work_done = Flags["work-done"]
  debug_log("Work done? " .. tostring(work_done))
  if work_done then complete_crafting() end
  swap_tool(home_tool)
  if home_tool == hammer then
    DRCC.get_adjust_tongs("tongs", bag, bag_items, forging_belt, adjustable_tongs)
  end
  command = home_command
end

-------------------------------------------------------------------------------
-- Execute work command
-------------------------------------------------------------------------------

-- All patterns for the main work command dispatch
local WORK_PATTERNS = {
  -- Tongs errors
  "You must be holding some metal tongs",
  "That tool does not seem",
  -- Tool not suitable
  "doesn't appear suitable",
  -- Temper states
  "You glance down at the hot coals of the forge",
  "ensure even heating in the forge",
  "has already been tempered",
  -- Fuel / bellows
  "needs more fuel",
  "need some more fuel",
  "Almost all of the coal has been consumed",
  "fire dims and produces less heat",
  "fire flickers and is unable to consume its fuel",
  "The forge fire has died down",
  -- Tongs turn
  "straightening along the horn of the anvil",
  "would benefit from some soft reworking.",
  "set using tongs",
  "sets using tongs",
  "into wire using a mandrel or mold set",
  "metal is in need of some gentle bending",
  -- Wire brush
  "The grinding has left many nicks and burs",
  -- Grindstone slow
  "not spinning fast enough",
  -- Pounding
  "must be pounded free",
  "the armor now needs reassembly with a hammer",
  "looks ready to be pounded",
  "appears ready for more pounding",
  "anything that would obstruct pounding of the metal",
  "appears ready for pounding the assembled handle",
  -- Grindstone
  "ready for grinding away of the excess metal",
  "now appears ready for grinding and polishing",
  "thinning the armor's metal at a grindstone",
  "The armor is ready to be lightened",
  "ready to be ground away",
  "You think adjusting the armor",
  -- Cooling
  "in the slack tub",
  "The metal is ready to be cooled",
  -- Pliers
  "Some pliers are now required",
  "appear ready to be woven",
  "using a pair of pliers",
  "using pliers",
  "ready for more bending of links and plates",
  -- Oil
  "in need of some oil to preserve",
  "protection by pouring oil on it",
  "metal will quickly rust",
  "to be cleaned of the clay",
  -- Assembly / handle
  "now needs the handle assembled and pounded into place",
  "Ingredients can be added",
  -- Errors
  "You need a larger volume of metal",
  "I could not find what you were referring to",
  "Pour what",
  -- Completion
  "Applying the final touches",
  -- Roundtime (catch-all)
  "Roundtime",
}

local function execute_work_command()
  return DRC.bput(command, table.unpack(WORK_PATTERNS))
end

local function handle_work_result(result)
  -- Tongs errors
  if result:find("You must be holding some metal tongs") or
     result:find("That tool does not seem") then
    DRCC.get_adjust_tongs("tongs", bag, bag_items, forging_belt, adjustable_tongs)

  elseif result:find("doesn't appear suitable") then
    handle_tool_not_suitable()

  -- Temper
  elseif result:find("You glance down at the hot coals of the forge") then
    command = "put my " .. item .. " on the forge"
  elseif result:find("ensure even heating in the forge") then
    handle_temper_continue()
  elseif result:find("has already been tempered") then
    handle_temper_already_done()

  -- Fuel
  elseif result:find("needs more fuel") or result:find("need some more fuel") or
         result:find("Almost all of the coal has been consumed") then
    handle_fuel_needed()

  -- Bellows
  elseif result:find("fire dims and produces less heat") or
         result:find("fire flickers and is unable to consume its fuel") or
         result:find("The forge fire has died down") then
    handle_bellows_needed()

  -- Tongs turn
  elseif result:find("straightening along the horn of the anvil") or
         result:find("would benefit from some soft reworking.") or
         result:find("set using tongs") or result:find("sets using tongs") or
         result:find("into wire using a mandrel or mold set") or
         result:find("metal is in need of some gentle bending") then
    handle_tongs_turn()

  -- Cooling
  elseif result:find("in the slack tub") or result:find("The metal is ready to be cooled") then
    handle_cooling()

  -- Wire brush
  elseif result:find("The grinding has left many nicks and burs") then
    handle_wire_brush()

  -- Pounding
  elseif result:find("must be pounded free") or
         result:find("the armor now needs reassembly with a hammer") or
         result:find("looks ready to be pounded") or
         result:find("appears ready for more pounding") or
         result:find("anything that would obstruct pounding of the metal") or
         result:find("appears ready for pounding the assembled handle") then
    handle_pounding()

  -- Grindstone slow
  elseif result:find("not spinning fast enough") then
    spin_grindstone()

  -- Grindstone work
  elseif result:find("ready for grinding away of the excess metal") or
         result:find("now appears ready for grinding and polishing") or
         result:find("thinning the armor's metal at a grindstone") or
         result:find("The armor is ready to be lightened") or
         result:find("ready to be ground away") or
         result:find("You think adjusting the armor") then
    handle_grindstone()

  -- Pliers
  elseif result:find("Some pliers are now required") or
         result:find("appear ready to be woven") or
         result:find("using a pair of pliers") or result:find("using pliers") or
         result:find("ready for more bending of links and plates") then
    handle_pliers()

  -- Oil
  elseif result:find("in need of some oil to preserve") or
         result:find("protection by pouring oil on it") or
         result:find("metal will quickly rust") or
         result:find("to be cleaned of the clay") then
    handle_oiling()

  -- Handle assembly
  elseif result:find("now needs the handle assembled and pounded into place") then
    handle_handle_assembly()

  -- Ingot too small
  elseif result:find("You need a larger volume of metal") then
    cleanup_and_exit("You need a larger ingot to forge this item.")

  -- Oil empty
  elseif result:find("Pour what") then
    handle_oil_empty()

  -- Item not found
  elseif result:find("I could not find what you were referring to") then
    cleanup_and_exit("Could not find item or tool. Check your setup.")

  -- Ingredients / assembly
  elseif result:find("Ingredients can be added") then
    assemble_part()

  -- Completion
  elseif result:find("Applying the final touches") then
    complete_crafting()

  -- Roundtime (default)
  elseif result:find("Roundtime") then
    handle_roundtime()
  end
end

-------------------------------------------------------------------------------
-- Main work loop
-------------------------------------------------------------------------------

local function work()
  while not _script_done do
    DRCA.crafting_magic_routine(settings)
    local rental_warn = Flags["forge-rental-warning"]
    if rental_warn then renew_forge_rental() end
    assemble_part()
    command = command or home_command
    if command:find("grindstone") then spin_grindstone() end

    local result = execute_work_command()
    debug_log("Work result: " .. tostring(result))
    debug_log("Assembly flag: " .. tostring(Flags["forge-assembly"]))

    local ingot_line = Flags["ingot-restow"]
    if ingot_line then restow_ingot(ingot_line) end

    handle_work_result(result)
  end
end

-------------------------------------------------------------------------------
-- Validation
-------------------------------------------------------------------------------

local function validate_setup()
  validate_crafting_container()
  validate_hammer()
  DRC.wait_for_script_to_complete("buff", {"forge"})
  validate_free_hand()
  if settings.adjustable_tongs and item ~= "tongs" then
    setup_adjustable_tongs()
  end
  if use_resume then find_item() end
end

-------------------------------------------------------------------------------
-- Register Flags
-------------------------------------------------------------------------------

Flags.add("forge-assembly",
  "another finished .+ %(handle%)",
  "another finished wooden %(hilt%)",
  "another finished wooden %(haft%)",
  "another finished .+ leather %(cord%)",
  "another finished .+ leather %(backing%)",
  "another finished .+ cloth %(padding%)",
  "another finished .+ wooden %(pole%)",
  "ready to be reinforced with some %(leather strips%)")

Flags.add("work-done",
  "from the successful .+ process",
  "shows a slightly reduced weight",
  "shows improved protection",
  "Applying the final touches",
  "was successfully")

Flags.add("ingot-restow",
  "split the ingot and leave the portion.+in your")

Flags.add("forge-rental-warning",
  "Your rental time is almost up")

-------------------------------------------------------------------------------
-- Cleanup on script exit
-------------------------------------------------------------------------------

before_dying(function()
  Flags.delete("forge-assembly")
  Flags.delete("work-done")
  Flags.delete("ingot-restow")
  Flags.delete("forge-rental-warning")
end)

-------------------------------------------------------------------------------
-- Main entry point
-------------------------------------------------------------------------------

validate_setup()

if use_private and not use_resume then
  go_to_private_forge()
end

check_rental_status()

if not args.skip then
  check_all_consumables()
end

set_defaults()

if use_resume then
  work()
end

prep()

if cube then touch_cube() end

work()
