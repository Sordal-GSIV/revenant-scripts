--- @revenant-script
--- name: sew
--- version: 2.0.0
--- author: Elanthia Online (lic)
--- game: dr
--- description: Tailoring, knitting, and leather-working automation for DragonRealms outfitting.
--- tags: crafting, tailoring, sewing, knitting, leather, outfitting
--- @lic-certified: complete 2026-03-19
---
--- Handles the complete sewing/tailoring workflow:
---   - Crafting cloth and leather items from book recipes or instructions
---   - Knitting (yarn + needles, chapter 5)
---   - Enhancements: seal, reinforce, lighten
---   - Assembly of multi-part items (padding, handles, cords)
---   - Automatic rental room renewal
---   - Consumable restocking (thread, pins, wax)
---   - Resume mid-craft
---
--- Usage:
---   ;sew <finish> <knitting|sewing|leather> <chapter> <recipe_name> <material> <noun> [skip]
---   ;sew <finish> instructions <material> <noun> [knit] [skip]
---   ;sew <seal|reinforce|lighten> <noun>
---   ;sew resume <noun>
---
--- Arguments:
---   finish       hold|log|stow|trash  What to do with the finished item (default: hold)
---   chapter      Chapter number in the recipe book
---   recipe_name  Recipe name (quote multi-word: "small rucksack")
---   material     Material type (e.g., burlap, deer, silk, wool)
---   noun         Noun of the item being crafted
---   skip         Skip restocking consumables if low
---
--- Examples:
---   ;sew hold sewing 1 "small rucksack" burlap rucksack
---   ;sew log leather 2 "small backpack" deer backpack
---   ;sew stow knitting 5 "knit cap" wool cap
---   ;sew instructions deer pack
---   ;sew seal shirt
---   ;sew resume pack

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

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

local FINISH_OPTS   = { hold = true, log = true, stow = true, trash = true }
local ENHANCEMENTS  = { seal = true, reinforce = true, lighten = true }
local TYPE_OPTS     = { knitting = true, sewing = true, leather = true }

local function parse_args()
  local argv = split_args(Script.vars and Script.vars[0] or "")
  if #argv == 0 then return nil end

  local args = {}
  local idx  = 1

  -- resume mode: ;sew resume <noun>
  if argv[idx] and argv[idx]:lower() == "resume" then
    args.resume = true
    idx = idx + 1
    args.noun = argv[idx]; idx = idx + 1
    while argv[idx] do
      if argv[idx]:lower() == "skip" then args.skip = true end
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

  -- Enhancement mode: ;sew [finish] <seal|reinforce|lighten> <noun>
  if cur and ENHANCEMENTS[cur] then
    args.recipe_name = cur
    idx = idx + 1
    args.noun = argv[idx]; idx = idx + 1
    while argv[idx] do
      if argv[idx]:lower() == "skip" then args.skip = true end
      idx = idx + 1
    end
    return args
  end

  -- Instructions mode: ;sew [finish] instructions <material> <noun> [knit] [skip]
  if cur and cur == "instructions" then
    args.instructions = true
    idx = idx + 1
    args.material = argv[idx]; idx = idx + 1
    args.noun     = argv[idx]; idx = idx + 1
    while argv[idx] do
      local v = argv[idx]:lower()
      if v == "knit"  then args.knit = true
      elseif v == "skip" then args.skip = true end
      idx = idx + 1
    end
    return args
  end

  -- Normal mode: ;sew [finish] <knitting|sewing|leather> <chapter> <recipe_name> <material> <noun> [skip]
  if cur and TYPE_OPTS[cur] then
    args.type_      = cur;          idx = idx + 1
    args.chapter    = argv[idx];    idx = idx + 1
    args.recipe_name = argv[idx];   idx = idx + 1
    args.material   = argv[idx];    idx = idx + 1
    args.noun       = argv[idx];    idx = idx + 1
    while argv[idx] do
      local v = argv[idx]:lower()
      if v == "skip"  then args.skip = true
      elseif v == "knit" then args.knit = true end
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
  echo("  ;sew [hold|log|stow|trash] <knitting|sewing|leather> <chapter> <recipe_name> <material> <noun> [skip]")
  echo("  ;sew [hold|log|stow|trash] instructions <material> <noun> [knit] [skip]")
  echo("  ;sew <seal|reinforce|lighten> <noun>")
  echo("  ;sew resume <noun>")
  return
end

-------------------------------------------------------------------------------
-- Load settings
-------------------------------------------------------------------------------

local settings         = get_settings()
local hometown         = settings.force_crafting_town or settings.hometown
local bag              = settings.crafting_container
local bag_items        = settings.crafting_items_in_container or {}
local belt             = settings.outfitting_belt
local stamp            = settings.mark_crafted_goods
local cube             = settings.cube_armor_piece
local worn_trashcan    = settings.worn_trashcan
local worn_trashcan_verb = settings.worn_trashcan_verb

-- Resolve enhancement recipe name aliases
local recipe_name = args.recipe_name or ""
if recipe_name == "lighten"   then recipe_name = "tailored armor lightening"
elseif recipe_name == "seal"  then recipe_name = "tailored armor sealing"
elseif recipe_name == "reinforce" then recipe_name = "tailored armor reinforcing"
end

local noun        = args.noun
local mat_type    = args.material
local chapter     = args.chapter and tonumber(args.chapter) or 1
local finish      = args.finish or "hold"
local use_resume  = args.resume
local instruction = args.instructions
local knit        = args.knit or (chapter == 5)

-- All cloth material types
local CLOTH = {
  silk=true, wool=true, burlap=true, cotton=true, felt=true, linen=true,
  electroweave=true, steelsilk=true, arzumodine=true, bourde=true,
  dergatine=true, dragonar=true, faeweave=true, farandine=true,
  imperial=true, jaspe=true, khaddar=true, ruazin=true, titanese=true,
  zenganne=true,
}

-- Resolve crafting room data
local crafting_info = nil
do
  local ok, data = pcall(get_data, "crafting")
  if ok and data and data.tailoring and hometown then
    crafting_info = data.tailoring[hometown]
  end
end

-- Current tool tracking
local home_tool    = nil
local home_command = nil
local _script_done = false

-------------------------------------------------------------------------------
-- Logging helpers
-------------------------------------------------------------------------------

local function error_log(msg)
  respond("\27[1m[sew] " .. tostring(msg) .. "\27[0m")
end

local function info_log(msg)
  respond("[sew] " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Cleanup / exit
-------------------------------------------------------------------------------

local function magic_cleanup()
  if not settings.crafting_training_spells or
     #settings.crafting_training_spells == 0 then return end
  DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
  DRC.bput("release mana",  "You release all",                  "You aren't harnessing any mana")
  DRC.bput("release symb",  "But you haven't",                  "You release", "Repeat this command")
end

local function cleanup_and_exit(msg)
  if msg then error_log(msg) end
  _script_done = true
  magic_cleanup()
  Script.kill(Script.name)
end

-------------------------------------------------------------------------------
-- Noun dot-notation helper
-- DR uses "small.rucksack" notation for disambiguation; game XML uses space.
-- ".tr('.', ' ')" from Ruby → gsub in Lua
-------------------------------------------------------------------------------

local function noun_plain(n)
  return (n or noun):gsub("%.", " ")
end

-------------------------------------------------------------------------------
-- Items-at-feet diagnostic
-------------------------------------------------------------------------------

local function list_at_feet()
  -- Send the inventory command; output shows in client window automatically.
  -- Collect and display a summary if lines are available.
  fput("inv atfeet")
  local lines = {}
  local line = get_noblock()
  local timeout_end = os.time() + 3
  while os.time() < timeout_end do
    line = get_noblock()
    if line then
      if line:find("All of your items lying at your feet") then break end
      if line:find("Use INVENTORY HELP") then break end
      if line ~= "" then lines[#lines + 1] = line end
    else
      pause(0.1)
    end
  end
  if #lines > 0 then
    info_log("Items at feet: " .. table.concat(lines, ", "))
  end
end

-------------------------------------------------------------------------------
-- Tool management
-------------------------------------------------------------------------------

local function swap_tool(next_tool, skip)
  if not next_tool then return end
  local rh = DRC.right_hand()
  if rh and rh:find(next_tool, 1, true) then return end
  DRCC.stow_crafting_item(rh, bag, belt)
  DRCC.get_crafting_item(next_tool, bag, bag_items, belt, skip or false)
end

-------------------------------------------------------------------------------
-- Hand position check
-- Ensures item is in left hand; if in right, swaps. Otherwise errors out.
-------------------------------------------------------------------------------

local function check_hand(item)
  if DRCI.in_right_hand(item) then
    DRC.bput("swap", "You move", "You have nothing")
  else
    error_log("Please hold the item or material you wish to work on. Expected '" .. item .. "' in right hand.")
    magic_cleanup()
    Script.kill(Script.name)
  end
end

-------------------------------------------------------------------------------
-- Feet cleanup
-------------------------------------------------------------------------------

local function lift_or_stow_feet()
  if DRCI.lift() then
    local right = DRC.right_hand()
    local left  = DRC.left_hand()
    local nplain = noun_plain()
    if right and not right:find(nplain, 1, true) then
      DRCC.stow_crafting_item(right, bag, belt)
    end
    if left and not left:find(nplain, 1, true) then
      DRCC.stow_crafting_item(left, bag, belt)
    end
  else
    DRC.bput("stow feet", "You put", "Stow what")
  end
end

-------------------------------------------------------------------------------
-- Rental management
-------------------------------------------------------------------------------

local MONTH_NUMS = {
  Jan=1, Feb=2, Mar=3, Apr=4,  May=5,  Jun=6,
  Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12,
}

local function eastern_utc_offset_secs()
  local utc  = os.date("!*t", os.time())
  local year = utc.year
  local function first_sunday(month)
    local t = os.date("!*t", os.time{year=year, month=month, day=1, hour=0, min=0, sec=0})
    return 1 + (8 - t.wday) % 7
  end
  local mar_sun2    = first_sunday(3) + 7
  local nov_sun1    = first_sunday(11)
  local dst_start   = os.time{year=year, month=3,  day=mar_sun2, hour=7, min=0, sec=0}
  local dst_end     = os.time{year=year, month=11, day=nov_sun1, hour=6, min=0, sec=0}
  local now         = os.time()
  return (now >= dst_start and now < dst_end) and (-4 * 3600) or (-5 * 3600)
end

local function parse_rental_expire(expire_str)
  local _, mon, day, h, m, s, year =
    expire_str:match("(%a+) (%a+) (%d+) (%d+):(%d+):(%d+) ET (%d+)")
  if not mon then return nil end
  local month = MONTH_NUMS[mon]
  if not month then return nil end
  local et_off    = eastern_utc_offset_secs()
  local local_off = os.time() - os.time(os.date("!*t", os.time()))
  local parsed_local = os.time{
    year  = tonumber(year),
    month = month,
    day   = tonumber(day),
    hour  = tonumber(h),
    min   = tonumber(m),
    sec   = tonumber(s),
  }
  return parsed_local + local_off - et_off
end

local function renew_rental()
  error_log("RENTAL EXPIRING — AUTO-RENEWING")
  Flags.reset("sew-rental-warning")
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
    error_log("Could not parse rental expiry time: " .. tostring(expire_str))
    return
  end
  local minutes_remaining = math.floor((expire_ts - os.time()) / 60)
  if minutes_remaining < 10 then
    error_log("RENTAL LOW (" .. tostring(minutes_remaining) .. " min) — AUTO-RENEWING")
    renew_rental()
  elseif minutes_remaining < 20 then
    error_log("Rental has " .. tostring(minutes_remaining) .. " minutes remaining")
  end
end

-------------------------------------------------------------------------------
-- Assembly part extraction
-- The sew-assembly flag stores the matched game line. We parse the part
-- name from it, replicating the Ruby captures-join approach.
-------------------------------------------------------------------------------

local function extract_sew_part(line)
  if not line then return nil end
  -- "ready to be assembled with some small cloth padding"
  local s1, s2 = line:match("with some (%a+) cloth (%a+)")
  if s1 and s2 then return s1 .. " " .. s2 end         -- e.g. "small padding"
  -- "another finished steel shield handle"
  if line:find("shield") and line:find("handle") then return "handle" end
  -- "another finished wooden hilt" / "another finished wooden haft"
  local wooden_part = line:match("another finished wooden (%a+)")
  if wooden_part then return wooden_part end
  -- "another finished long leather cord" / "another finished small leather backing"
  local la, lb = line:match("another finished (%a+) leather (%a+)")
  if la and lb then return la .. " " .. lb end          -- e.g. "small cord"
  -- "another finished small cloth padding"
  local ca, cb = line:match("another finished (%a+) cloth (%a+)")
  if ca and cb then return ca .. " " .. cb end          -- e.g. "small padding"
  -- "another finished long wooden pole"
  local wa, wb = line:match("another finished (%a+) wooden (%a+)")
  if wa and wb then return wa .. " " .. wb end          -- e.g. "long pole"
  return nil
end

local function assemble_part()
  local asm_line = Flags["sew-assembly"]
  while asm_line do
    local tool = DRC.right_hand()
    if tool then DRCC.stow_crafting_item(tool, bag, belt) end
    local part = extract_sew_part(asm_line)
    Flags.reset("sew-assembly")
    if not part then
      error_log("Could not determine assembly part from: " .. tostring(asm_line))
      break
    end
    DRCC.get_crafting_item(part, bag, bag_items, belt)
    DRC.bput("assemble my " .. noun .. " with my " .. part,
      "affix it securely in place",
      "and tighten the pommel to secure it",
      "carefully mark where it will attach when you continue crafting")
    if tool then swap_tool(tool) end
    asm_line = Flags["sew-assembly"]
  end
end

-------------------------------------------------------------------------------
-- Preparation
-------------------------------------------------------------------------------

local function prep()
  DRCA.crafting_magic_routine(settings)

  if instruction then
    -- Instructions mode: get and study the instruction sheet
    DRCC.get_crafting_item(noun .. " instructions", bag, bag_items, belt)
    local study_result = DRC.bput("study my instructions", "Roundtime", "Study them again")
    if study_result:find("again") then
      DRC.bput("study my instructions", "Roundtime", "Study them again")
    end
  elseif settings.master_crafting_book then
    DRCC.find_recipe2(chapter, recipe_name, settings.master_crafting_book, "tailoring")
  else
    DRCC.get_crafting_item("tailoring book", bag, bag_items, belt)
    if DRSkill.getrank("Outfitting") == 175 then
      error_log("You will need to upgrade to a journeyman or master book before 176 ranks!")
    end
    DRCC.find_recipe2(chapter, recipe_name)
    DRCC.stow_crafting_item("tailoring book", bag, belt)
  end

  if knit then
    -- Knitting: yarn + knitting needles
    DRCC.get_crafting_item("yarn", bag, bag_items, belt)
    if not DRCI.in_left_hand("yarn") then check_hand("yarn") end
    swap_tool("knitting needles")
    home_tool    = "knitting needles"
    home_command = "knit my needles"
    return "knit my yarn with my knitting needles"

  elseif recipe_name:find("tailored armor", 1, true) then
    -- Enhancement workflow
    stamp = false
    if not DRCI.in_left_hand(noun) then check_hand(noun) end
    if recipe_name:find("sealing", 1, true) then
      swap_tool("sealing wax", true)
      home_tool    = "sealing wax"
      home_command = "apply my wax to my " .. noun
      return "apply my wax to my " .. noun
    else
      swap_tool("scissors")
      home_tool    = "scissors"
      home_command = "cut my " .. noun .. " with my scissors"
      return "cut my " .. noun .. " with my scissors"
    end

  elseif mat_type and CLOTH[mat_type] then
    -- Cloth product
    DRCC.get_crafting_item(mat_type .. " cloth", bag, bag_items, belt)
    if not DRCI.in_left_hand("cloth") then check_hand("cloth") end
    swap_tool("scissors")
    home_tool    = "sewing needles"
    home_command = "push my " .. noun .. " with my needles"
    return "cut my " .. mat_type .. " cloth with my scissors"

  else
    -- Leather product
    DRCC.get_crafting_item((mat_type or "deer") .. " leather", bag, bag_items, belt)
    if not DRCI.in_left_hand("leather") then check_hand("leather") end
    swap_tool("scissors")
    home_tool    = "sewing needles"
    home_command = "push my " .. noun .. " with my needles"
    return "cut my " .. (mat_type or "deer") .. " leather with my scissors"
  end
end

-------------------------------------------------------------------------------
-- Completion
-------------------------------------------------------------------------------

local function complete_crafting()
  _script_done = true

  if stamp then
    swap_tool("stamp", true)
    DRC.bput("mark my " .. noun .. " with my stamp", "Roundtime")
    DRCC.stow_crafting_item("stamp", bag, belt)
  end

  local right  = DRC.right_hand()
  local left   = DRC.left_hand()
  local nplain = noun_plain()
  if right and not right:find(nplain, 1, true) then
    DRCC.stow_crafting_item(right, bag, belt)
  end
  if left and not left:find(nplain, 1, true) then
    DRCC.stow_crafting_item(left, bag, belt)
  end

  if finish:find("log") then
    DRCC.logbook_item("outfitting", noun, bag)
  elseif finish:find("stow") then
    DRCC.stow_crafting_item(noun, bag, belt)
  elseif finish:find("trash") then
    DRCI.dispose_trash(noun, worn_trashcan, worn_trashcan_verb)
  else
    error_log(noun .. " complete — holding in hand.")
  end

  lift_or_stow_feet()
  magic_cleanup()
  info_log("Sew script finished (" .. noun .. ", finish: " .. finish .. ").")
  Script.kill(Script.name)
end

-------------------------------------------------------------------------------
-- Consumable restocking
-------------------------------------------------------------------------------

local function restock_consumables()
  if args.skip or not crafting_info then return end
  if recipe_name:find("sealing", 1, true) then
    DRCC.check_consumables("wax", crafting_info["tool-room"], 10, bag, bag_items, belt)
  elseif chapter ~= 5 and not knit then
    DRCC.check_consumables("pins",   crafting_info["tool-room"],  5, bag, bag_items, belt)
    DRCC.check_consumables("thread", crafting_info["stock-room"], 6, bag, bag_items, belt)
  end
end

-------------------------------------------------------------------------------
-- Main work loop
-------------------------------------------------------------------------------

-- All response patterns for the main work dispatch
local WORK_PATTERNS = {
  "a slip knot in your yarn",
  "A sufficient quantity of wax exists",
  "A buildup of wax on .* must now be rubbed",
  "and could use some pins to",
  "cutting with some scissors",
  "deep crease develops along",
  "Deep creases and wrinkles in the fabric",
  "dimensions appear to have shifted and could benefit from some remeasuring",
  "dimensions changed while working on it",
  "Do you really want to discard",
  "I could not find what you were",
  "Ingredients can be added",
  "is in need of pinning to help arrange the material for further sewing",
  "need to be turned",
  "needs holes punched",
  "New seams must now be sewn to properly fit the lightened material together",
  "Next the needles must be pushed",
  "Nothing obstructs the fabric from continued sewing",
  "now needs some sealing wax applied",
  "Now the needles must be turned",
  "pushing it with a needle and thread",
  "ready to be pushed",
  "requires some holes punched",
  "scissor cuts",
  "Sealing wax now encases the material",
  "Some purl stitching is",
  "Some ribbing should be added",
  "The garment is nearly complete and now must be cast off",
  "The needles need to have thread put on them before they can be used for sewing",
  "What were you referring",
  "With the measuring complete",
  "wrinkles from all the handling and could use",
  "You are already knitting",
  "You carefully thread some cotton thread",
  "You must assemble",
  "You need another",
  "You untie and discard",
  "The .* needles must be cast to finish binding the knit yarn",
  "You need a larger amount of material to continue crafting",
  "Roundtime",
  "You need a free hand to do that",
  "You realize that cannot be repaired, and stop",
}

local function work(command)
  if cube then
    DRC.bput("touch my " .. cube,
      "Warm vapor swirls around your head in a misty halo",
      "A thin cloud of vapor manifests with no particular effect",
      "Touch what",
      "You reach out and touch")
  end

  while not _script_done do
    DRCA.crafting_magic_routine(settings)
    if Flags["sew-rental-warning"] then renew_rental() end
    assemble_part()

    local result = DRC.bput(command, table.unpack(WORK_PATTERNS))

    if result:find("You need a larger amount of material to continue crafting") then
      cleanup_and_exit("Not enough material to continue crafting " .. noun .. ". Exiting.")
      return

    elseif result == "dimensions appear to have shifted and could benefit from some remeasuring"
        or result == "dimensions changed while working on it" then
      swap_tool("yardstick")
      home_tool    = "sewing needles"
      home_command = "push my " .. noun .. " with my sewing needles"
      command = "measure my " .. noun .. " with my yardstick"

    elseif result == "With the measuring complete"
        or result == "cutting with some scissors"
        or result == "scissor cuts" then
      swap_tool("scissors")
      command = "cut my " .. noun .. " with my scissors"

    elseif result == "and could use some pins to"
        or result == "is in need of pinning to help arrange the material for further sewing" then
      swap_tool("pins", true)
      command = "poke my " .. noun .. " with my pins"

    elseif result == "deep crease develops along"
        or result == "wrinkles from all the handling and could use"
        or result == "Deep creases and wrinkles in the fabric" then
      swap_tool("slickstone")
      command = "scrape my " .. noun .. " with my slickstone"

    elseif result == "The needles need to have thread put on them before they can be used for sewing" then
      swap_tool("cotton thread", true)
      command = "put thread on my sewing needles"

    elseif result == "You carefully thread some cotton thread" then
      swap_tool("sewing needles")
      command = "push my " .. noun .. " with my sewing needles"

    elseif result == "What were you referring" or result == "I could not find what you were" then
      list_at_feet()
      lift_or_stow_feet()
      if command:find("wax") then
        if crafting_info then
          DRCC.check_consumables("wax", crafting_info["tool-room"], 10, bag, bag_items, belt)
        end
        swap_tool("wax")
      elseif command:find("pins") then
        if crafting_info then
          DRCC.check_consumables("pins", crafting_info["tool-room"], 5, bag, bag_items, belt)
        end
        swap_tool("pins")
      elseif command:find("thread") then
        if crafting_info then
          DRCC.check_consumables("thread", crafting_info["stock-room"], 6, bag, bag_items, belt)
        end
        swap_tool("thread")
      end

    elseif result == "needs holes punched" or result == "requires some holes punched" then
      home_tool    = "sewing needles"
      home_command = "push my " .. noun .. " with my sewing needles"
      swap_tool("awl")
      command = "poke my " .. noun .. " with my awl"

    elseif result == "New seams must now be sewn to properly fit the lightened material together" then
      stamp        = false
      home_tool    = "scissors"
      home_command = "cut my " .. noun .. " with my scissors"
      swap_tool("sewing needles")
      command = "push my " .. noun .. " with my sewing needles"

    elseif result == "A sufficient quantity of wax exists"
        or result == "Sealing wax now encases the material"
        or result:find("A buildup of wax on .* must now be rubbed") then
      stamp        = false
      home_tool    = "sealing wax"
      home_command = "apply my wax to my " .. noun
      swap_tool("slickstone")
      command = "scrape my " .. noun .. " with my slickstone"

    elseif result == "now needs some sealing wax applied" then
      home_tool    = "sealing wax"
      home_command = "apply my wax to my " .. noun
      swap_tool("sealing wax", true)
      command = "apply my wax to my " .. noun

    elseif result == "Nothing obstructs the fabric from continued sewing"
        or result == "pushing it with a needle and thread" then
      home_tool    = "sewing needles"
      home_command = "push my " .. noun .. " with my sewing needles"
      swap_tool("sewing needles")
      command = "push my " .. noun .. " with my sewing needles"

    elseif result == "Ingredients can be added"
        or result == "You must assemble"
        or result == "You need another" then
      assemble_part()

    elseif result == "a slip knot in your yarn" then
      DRCC.stow_crafting_item("yarn", bag, belt)
      command = "knit my needles"

    elseif result == "Now the needles must be turned"
        or result == "Some ribbing should be added"
        or result == "need to be turned" then
      command = "turn my needles"

    elseif result == "Next the needles must be pushed"
        or result == "ready to be pushed"
        or result == "Some purl stitching is" then
      command = "push my needles"

    elseif result == "The garment is nearly complete and now must be cast off"
        or result:find("The .* needles must be cast to finish binding the knit yarn") then
      command = "cast my needles"

    elseif result == "You are already knitting"
        or result == "Do you really want to discard" then
      command = "pull my needles"

    elseif result == "You untie and discard" then
      command = "knit my yarn with my knitting needles"

    elseif result:find("Roundtime")
        or result:find("You realize that cannot be repaired, and stop")
        or result:find("You need a free hand to do that") then
      waitrt()
      if Flags["sew-done"] then
        complete_crafting()
        return
      end
      if home_tool then swap_tool(home_tool) end
      command = home_command or command
    end
  end
end

-------------------------------------------------------------------------------
-- Register Flags
-------------------------------------------------------------------------------

Flags.add("sew-assembly",
  "ready to be .* with some (small|large) cloth (padding)",
  "another finished %S+ shield (handle)",
  "another finished wooden (hilt|haft)",
  "another finished (long|short|small|large) leather (cord|backing)",
  "another finished (small|large) cloth (padding)",
  "another finished (long|short) wooden (pole)")

Flags.add("sew-done",
  "The .* shows improved",
  "Applying the final touches",
  "The .* shows a slightly reduced weight",
  "You realize that cannot be repaired, and stop")

Flags.add("sew-rental-warning",
  "Your rental time is almost up")

-------------------------------------------------------------------------------
-- Cleanup on script exit
-------------------------------------------------------------------------------

before_dying(function()
  Flags.delete("sew-assembly")
  Flags.delete("sew-done")
  Flags.delete("sew-rental-warning")
end)

-------------------------------------------------------------------------------
-- Main entry point
-------------------------------------------------------------------------------

DRC.wait_for_script_to_complete("buff", {"sew"})

check_rental_status()
restock_consumables()

if use_resume then
  -- Resume mid-craft: determine current state from what's in hand
  local start_cmd
  if DRCI.in_hands("knitting needles") then
    home_command = "knit my needles"
    start_cmd    = "analyze my knitting needles"
  else
    if not DRCI.in_left_hand(noun) then check_hand(noun) end
    home_command = "analyze my " .. noun
    start_cmd    = "analyze my " .. noun
  end
  work(start_cmd)
else
  local start_cmd = prep()
  work(start_cmd)
end
