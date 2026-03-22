--- @revenant-script
--- name: carve
--- version: 1.0.0
--- author: Elanthia Online (lic)
--- game: dr
--- description: Engineering carving automation for stone and bone items.
--- tags: crafting, engineering, carving
--- @lic-certified: complete 2026-03-19
---
--- Handles the complete carving workflow:
---   - Crafting new items from book recipes
---   - Resuming interrupted carving sessions
---   - Automatic tool switching (chisel/saw → rifflers → rasp → polish)
---   - Assembly of multi-part items (hilts, hafts, poles, cords)
---   - Optional item stamping on completion
---   - Spell release cleanup when using crafting_training_spells
---
--- Usage:
---   ;carve <chapter> <recipe_name> <material> <type> <noun> [debug]
---   ;carve resume <type> <noun> [debug]
---
--- Arguments:
---   chapter      Chapter number in the carving book
---   recipe_name  Recipe name (quote multi-word: "stone wolf figurine")
---   material     Type of stone/bone material (e.g., obsidian, femur)
---   type         Material noun: stack|rock|stone|pebble|boulder|deed
---   noun         Target item noun for tool operations
---   debug        Show debug output
---
--- Resume arguments:
---   type         bone|stone (determines which tool to restore)
---   noun         Noun of partially-carved item to resume
---
--- Settings (from profiles/<char>-setup.json):
---   crafting_container            Noun of the crafting bag
---   crafting_items_in_container   Items stored inside the bag (not on belt)
---   engineering_belt              Noun of the engineering tool belt
---   mark_crafted_goods            true/false — stamp finished items
---   carving_tools                 List of tools; first saw used for stacks/bone,
---                                 first chisel used for all other types
---   master_crafting_book          Optional master book noun (skips per-recipe retrieval)
---   crafting_training_spells      Spells to maintain; released on finish
---
--- Examples:
---   ;carve 1 "stone wolf figurine" obsidian stone figurine
---   ;carve 3 "leg bone club" femur stack club
---   ;carve resume stone figurine
---   ;carve resume bone club

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

local MATERIAL_TYPES = {
  stack = true, rock = true, stone = true,
  pebble = true, boulder = true, deed = true,
}
local RESUME_TYPES = { bone = true, stack = true, rock = true, stone = true,
                       pebble = true, boulder = true, deed = true }

local function parse_args()
  local argv = split_args(Script.vars and Script.vars[0] or "")
  if #argv == 0 then return nil end
  local args = {}
  local idx  = 1

  -- Resume mode: ;carve resume <type> <noun> [debug]
  if argv[idx] and argv[idx]:lower() == "resume" then
    args.resume = true
    idx = idx + 1
    local t = argv[idx] and argv[idx]:lower()
    if t and RESUME_TYPES[t] then
      args.type = t
      idx = idx + 1
    end
    args.noun = argv[idx]; idx = idx + 1
    while argv[idx] do
      if argv[idx]:lower() == "debug" then args.debug = true end
      idx = idx + 1
    end
    return (args.noun) and args or nil
  end

  -- Normal mode: ;carve <chapter> <recipe_name> <material> <type> <noun> [debug]
  args.chapter     = argv[idx]; idx = idx + 1
  args.recipe_name = argv[idx]; idx = idx + 1
  args.material    = argv[idx]; idx = idx + 1
  local t = argv[idx] and argv[idx]:lower()
  if t and MATERIAL_TYPES[t] then
    args.type = t
    idx = idx + 1
  end
  args.noun = argv[idx]; idx = idx + 1
  while argv[idx] do
    if argv[idx]:lower() == "debug" then args.debug = true end
    idx = idx + 1
  end
  return (args.chapter and args.recipe_name and args.noun) and args or nil
end

-------------------------------------------------------------------------------
-- Validate and parse args
-------------------------------------------------------------------------------

local args = parse_args()
if not args then
  echo("Usage:")
  echo("  ;carve <chapter> <recipe_name> <material> <stack|rock|stone|pebble|boulder|deed> <noun> [debug]")
  echo("  ;carve resume <bone|stone|stack|rock|pebble|boulder|deed> <noun> [debug]")
  return
end

-------------------------------------------------------------------------------
-- Load settings
-------------------------------------------------------------------------------

local settings        = get_settings()
local bag             = settings.crafting_container
local bag_items       = settings.crafting_items_in_container or {}
local belt            = settings.engineering_belt
local stamp           = settings.mark_crafted_goods
local training_spells = settings.crafting_training_spells or {}
local debug_mode      = args.debug or settings.debug_mode

-- Select main tool based on material type.
-- Stacks and bone materials use a saw; all stone-type materials use a chisel.
local function find_main_tool(type_hint)
  if not settings.carving_tools then return nil end
  local need_saw = (type_hint == "stack" or type_hint == "bone")
  for _, t in ipairs(settings.carving_tools) do
    if need_saw and t:lower():find("saw")    then return t end
    if (not need_saw) and t:lower():find("chisel") then return t end
  end
  return nil
end

local main_tool = find_main_tool(args.type)
local item      = args.noun       -- finished item noun used in tool commands
local mat_type  = args.type       -- raw material type (may change after deed tap)
local my        = "my "           -- reference prefix; "" for items too heavy to carry
local _done     = false

-------------------------------------------------------------------------------
-- Logging
-------------------------------------------------------------------------------

local function debug_log(msg)
  if debug_mode then respond("[carve] " .. tostring(msg)) end
end

local function error_log(msg)
  respond("\27[1m[carve] " .. tostring(msg) .. "\27[0m")
end

local function info_log(msg)
  respond("[carve] " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Validation
-------------------------------------------------------------------------------

local function validate_setup()
  if not bag then
    error_log("No crafting_container configured in settings.")
    Script.kill(Script.name)
    return
  end
  if not main_tool then
    if not args.resume then
      error_log("No matching carving tool found in carving_tools.")
      error_log("Need a saw (for stack/bone) or chisel (for rock/stone/pebble/boulder/deed).")
    else
      error_log("No matching carving tool found in carving_tools for resume mode.")
      error_log("Configure a saw (for bone) or chisel (for stone) in carving_tools.")
    end
    Script.kill(Script.name)
    return
  end
end

-------------------------------------------------------------------------------
-- Magic cleanup
-------------------------------------------------------------------------------

local function magic_cleanup()
  if #training_spells == 0 then return end
  DRC.bput("release spell", "You let your concentration lapse", "You aren't preparing a spell")
  DRC.bput("release mana",  "You release all",                  "You aren't harnessing any mana")
  DRC.bput("release symb",  "But you haven't",                  "You release", "Repeat this command")
end

-------------------------------------------------------------------------------
-- Assembly
-------------------------------------------------------------------------------

--- Extract the assembly part noun from a matched game line.
-- Handles known carving assembly parts: hilt, haft, pole, cord.
local function extract_assembly_part(line)
  if not line then return nil end
  if line:find("hilt") then return "hilt" end
  if line:find("haft") then return "haft" end
  if line:find("pole") then
    if line:find("long") then return "long wooden pole"
    elseif line:find("short") then return "short wooden pole"
    else return "wooden pole" end
  end
  if line:find("cord") then
    if line:find("long") then return "long leather cord"
    elseif line:find("short") then return "short leather cord"
    else return "leather cord" end
  end
  -- Fallback: grab last word
  return line:match("(%w+)%s*$")
end

local function assemble_part()
  local asm_line = Flags["carve-assembly"]
  if not asm_line then return end

  local tool = DRC.right_hand()
  DRCC.stow_crafting_item(tool, bag, belt)

  local part = extract_assembly_part(asm_line)
  Flags.reset("carve-assembly")

  if not part then
    error_log("Could not determine assembly part from: " .. tostring(asm_line))
    if tool then DRCC.get_crafting_item(tool, bag, bag_items, belt) end
    return
  end

  debug_log("Assembling part: " .. part)
  DRCC.get_crafting_item(part, bag, bag_items, belt)
  DRC.bput("assemble " .. my .. item .. " with my " .. part,
    "affix it securely in place",
    "carefully mark where it will attach when you continue crafting",
    "add several marks indicating optimal locations")
  DRCC.get_crafting_item(tool, bag, bag_items, belt)
end

-------------------------------------------------------------------------------
-- Completion
-------------------------------------------------------------------------------

local function finish()
  _done = true
  DRCC.stow_crafting_item(DRC.right_hand(), bag, belt)

  if stamp then
    DRCC.get_crafting_item("stamp", bag, bag_items, belt)
    DRC.bput("mark my " .. item .. " with my stamp",
      "carefully hammer the stamp",
      "You cannot figure out how to do that",
      "too badly damaged")
    DRCC.stow_crafting_item("stamp", bag, belt)
  end

  waitrt()
  magic_cleanup()

  -- Ensure finished item is in hand
  if not DRCI.in_left_hand(item) and not DRCI.in_right_hand(item) then
    fput("get " .. item)
  end

  info_log(item .. " complete.")
  Script.kill(Script.name)
end

-------------------------------------------------------------------------------
-- Main carve loop
--
-- Executes `command`, dispatches on game response, updates command for next
-- iteration. All rub/apply/cut operations after the first use `item` as the
-- noun (the game renames the raw material once you begin working it).
-------------------------------------------------------------------------------

local CARVE_PATTERNS = {
  "rough, jagged",
  "determine",
  "developed an uneven texture along its surface",
  "You cannot figure out how to do that",
  "you see some discolored areas",
  "Roundtime",
}

local function carve_loop(command)
  while not _done do
    waitrt()
    DRCA.crafting_magic_routine(settings)
    assemble_part()
    debug_log("Carve command: " .. tostring(command))

    local result = DRC.bput(command, table.unpack(CARVE_PATTERNS))
    debug_log("Carve result: " .. tostring(result))

    if result:find("rough, jagged") then
      -- Switch to rifflers to smooth rough/jagged edges
      waitrt()
      DRCC.stow_crafting_item(DRC.right_hand(), bag, belt)
      DRCC.get_crafting_item("rifflers", bag, bag_items, belt)
      command = "rub " .. my .. item .. " with my rifflers"

    elseif result:find("determine") or
           result:find("developed an uneven texture along its surface") then
      -- Switch to rasp for uneven texture / grain determination
      waitrt()
      DRCC.stow_crafting_item(DRC.right_hand(), bag, belt)
      DRCC.get_crafting_item("rasp", bag, bag_items, belt)
      command = "rub " .. my .. item .. " with my rasp"

    elseif result:find("you see some discolored areas") then
      -- Switch to polish for discoloration
      waitrt()
      DRCC.stow_crafting_item(DRC.right_hand(), bag, belt)
      DRCC.get_crafting_item("polish", bag, bag_items, belt)
      command = "apply my polish to " .. my .. item

    elseif result:find("You cannot figure out how to do that") then
      -- Item is finished
      finish()

    else
      -- Roundtime or unexpected response: ensure main tool is in hand and continue cutting
      waitrt()
      if not DRCI.in_hands(main_tool) then
        DRCC.stow_crafting_item(DRC.right_hand(), bag, belt)
        DRCC.get_crafting_item(main_tool, bag, bag_items, belt)
      end
      command = "cut " .. my .. item .. " with my " .. main_tool
    end

    waitrt()
    DRCA.crafting_magic_routine(settings)
  end
end

-------------------------------------------------------------------------------
-- Normal mode: carve a new item from raw material
-------------------------------------------------------------------------------

local function carve_item()
  DRCA.crafting_magic_routine(settings)

  -- Find the recipe in the carving book
  if settings.master_crafting_book then
    DRCC.find_recipe2(args.chapter, args.recipe_name,
      settings.master_crafting_book, "carving")
  else
    DRCC.get_crafting_item("carving book", bag, bag_items, belt)
    if DRSkill.getrank("Engineering") == 175 then
      echo("*** You will need to upgrade to a journeyman or master book before 176 ranks! ***")
    end
    DRCC.find_recipe2(args.chapter, args.recipe_name)
    DRCC.stow_crafting_item("book", bag, belt)
  end

  -- Get the primary carving tool
  DRCC.get_crafting_item(main_tool, bag, bag_items, belt)

  -- Pick up raw material (boulders stay in place; use without 'my')
  if mat_type ~= "boulder" then
    local result = DRC.bput("get my " .. args.material .. " " .. mat_type,
      "You get",
      "You carefully remove",
      "You are already",
      "What do you",
      "What were you",
      "You pick up",
      "can't quite lift it")

    if result:find("What do you") or result:find("What were you") then
      DRC.beep()
      error_log("Missing: " .. args.material .. " " .. mat_type)
      Script.kill(Script.name)
      return
    elseif result:find("can't quite lift it") then
      my = ""
    else
      -- You get / You pick up / You are already holding
      my = "my "
    end

    -- Deed: tap to discover actual material type
    if mat_type == "deed" then
      local deed_line = DRC.bput("tap deed", "onto a sled", "What were you")
      local actual_type = deed_line:match("(%w+) onto a sled")
      local left_held = DRC.left_hand()
      if left_held and left_held ~= "" then
        -- Lighter material ended up in hand automatically
        mat_type = left_held
        my = "my "
      elseif actual_type then
        -- Heavy material placed on a sled; reference without 'my'
        mat_type = actual_type
        my = ""
      end
    end
  else
    my = ""
  end

  carve_loop("cut " .. my .. mat_type .. " with my " .. main_tool)
end

-------------------------------------------------------------------------------
-- Resume mode: continue a partially-carved item
-------------------------------------------------------------------------------

local ANALYZE_PATTERNS = {
  "You do not see anything that would prevent carving",
  "You do not see anything that would obstruct carving",
  "free of defects that would impede further carving",
  "ready for further carving",
  "corrected by rubbing the .+ with a riffler set",
  "corrected by scraping the .+ with a rasp",
  "angle of cut will improve if scraped with a rasp",
  "by applying some polish to",
  "This appears to be a type of finished",
  "Roundtime",
}

local function resume_carve()
  waitrt()

  -- Pick up the item
  local pick_result = DRC.bput("get " .. item,
    "You get",
    "You are already holding",
    "You pick up",
    "You are not strong enough",
    "What were you referring to")

  if pick_result:find("You get") or
     pick_result:find("You are already holding") or
     pick_result:find("You pick up") then
    my = "my "
    -- Move item to left hand so right hand is free for tools
    if not DRCI.in_left_hand(item) then
      DRC.bput("swap", "to your left hand", "You have nothing")
    end
  elseif pick_result:find("You are not strong enough") then
    my = ""
  else
    error_log("*** ITEM NOT FOUND: " .. item .. " ***")
    Script.kill(Script.name)
    return
  end

  -- Stow anything currently in right hand
  local rh = DRC.right_hand()
  if rh then DRCC.stow_crafting_item(rh, bag, belt) end

  -- Analyze to determine what step to resume from
  local analyze_result = DRC.bput("analyze my " .. item,
    table.unpack(ANALYZE_PATTERNS))
  debug_log("Analyze result: " .. tostring(analyze_result))

  local command
  if analyze_result:find("You do not see anything that would") or
     analyze_result:find("free of defects that would impede further carving") or
     analyze_result:find("ready for further carving") then
    -- No defects: resume cutting with main tool
    waitrt()
    DRCC.get_crafting_item(main_tool, bag, bag_items, belt)
    command = "cut " .. my .. item .. " with my " .. main_tool

  elseif analyze_result:find("corrected by rubbing the .+ with a riffler set") then
    -- Rough/jagged: resume with rifflers
    waitrt()
    DRCC.get_crafting_item("rifflers", bag, bag_items, belt)
    command = "rub " .. my .. item .. " with my rifflers"

  elseif analyze_result:find("corrected by scraping the .+ with a rasp") or
         analyze_result:find("angle of cut will improve if scraped with a rasp") then
    -- Uneven texture: resume with rasp
    waitrt()
    DRCC.get_crafting_item("rasp", bag, bag_items, belt)
    command = "rub " .. my .. item .. " with my rasp"

  elseif analyze_result:find("by applying some polish to") then
    -- Discoloration: resume with polish
    waitrt()
    DRCC.get_crafting_item("polish", bag, bag_items, belt)
    command = "apply my polish to " .. my .. item

  elseif analyze_result:find("This appears to be a type of finished") then
    error_log("*** THIS ITEM IS ALREADY FINISHED ***")
    Script.kill(Script.name)
    return

  else
    error_log("*** UNKNOWN NEXT COMMAND WHEN TRYING TO RESUME ***")
    Script.kill(Script.name)
    return
  end

  carve_loop(command)
end

-------------------------------------------------------------------------------
-- Register Flags
-- Watches the game stream for assembly triggers without blocking the carve loop.
-------------------------------------------------------------------------------

Flags.add("carve-assembly",
  "another finished wooden hilt",
  "another finished wooden haft",
  "another finished %a+ wooden pole",
  "another finished %a+ leather cord")

-------------------------------------------------------------------------------
-- Cleanup on script exit
-------------------------------------------------------------------------------

before_dying(function()
  Flags.delete("carve-assembly")
end)

-------------------------------------------------------------------------------
-- Main entry point
-------------------------------------------------------------------------------

validate_setup()
DRC.wait_for_script_to_complete("buff", {"carve"})

if args.resume then
  resume_carve()
else
  carve_item()
end
