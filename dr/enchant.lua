--- @revenant-script
--- name: enchant
--- version: 1.0.0
--- author: Elanthia Online (lic), original author unknown
--- game: dr
--- description: Full DR enchanting workflow — sigil scribing, imbue casting, brazier and fount management.
--- tags: crafting, enchanting, artificing
--- @lic-certified: complete 2026-03-18
---
--- Handles the complete enchanting workflow:
---   - Recipe study (book or master crafting book)
---   - Brazier setup, mana fount waving, cube touch
---   - Iterative sigil scribing with focus/meditate/push/imbue interrupts
---   - Wand-based or spell-based imbue casting
---   - Sigil trace (primary/secondary)
---   - Completion: stamp and stow finished item
---   - Safe-room exit on backlash
---   - Resume mode for in-progress enchants
---
--- Usage:
---   ;enchant <chapter> <recipe_name> <noun> [base_noun]
---   ;enchant resume <noun>
---
--- Arguments:
---   chapter      Chapter number in the artificing book
---   recipe_name  Recipe name (quote multi-word names: "iron brazier")
---   noun         Noun of the finished item
---   base_noun    Optional: noun of the base item if it changes on placement
---   resume       Resume an in-progress enchant

local Flags = require("lib/flags")

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

local function parse_args()
  local argv = split_args(Script.vars and Script.vars[0] or "")
  if #argv == 0 then return nil end

  local args = {}
  local idx = 1

  -- resume mode: ;enchant resume <noun>
  if argv[idx] and argv[idx]:lower() == "resume" then
    args.resume = true
    idx = idx + 1
    args.noun = argv[idx]
    return args
  end

  -- new mode: ;enchant <chapter> <recipe_name> <noun> [base_noun]
  args.chapter  = argv[idx]; idx = idx + 1
  args.recipe   = argv[idx]; idx = idx + 1
  args.noun     = argv[idx]; idx = idx + 1
  args.base_noun = argv[idx]  -- optional

  if not args.chapter or not args.recipe or not args.noun then
    return nil
  end

  return args
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local settings = get_settings()

local bag       = settings.crafting_container
local bag_items = settings.crafting_items_in_container or {}
local belt      = settings.enchanting_belt
local cube      = settings.cube_armor_piece
local stamp     = settings.mark_crafted_goods
local worn_trashcan      = settings.worn_trashcan
local worn_trashcan_verb = settings.worn_trashcan_verb
local book_type = "artificing"

-- Resolve enchanting tools from settings list
local enchanting_tools = settings.enchanting_tools or {}
local brazier_name = "brazier"
local fount_name   = "fount"
local loop_name    = "aug loop"
local imbue_wand   = "rod"
local burin_name   = "burin"

for _, t in ipairs(enchanting_tools) do
  if t:find("brazier") then brazier_name = t end
  if t:find("fount")   then fount_name   = t end
  if t:find("loop")    then loop_name    = t end
  if t:find("wand") or t:find("rod") then imbue_wand = t end
  if t:find("burin")   then burin_name   = t end
end

-- Check if room already has an enchanter's brazier (use it instead of own)
local use_own_brazier = true
if DRRoom and DRRoom.room_objs then
  for _, obj in ipairs(DRRoom.room_objs) do
    if type(obj) == "string" and obj:find("enchanter's brazier") then
      brazier_name    = "enchanter's brazier"
      use_own_brazier = false
    end
  end
end

-------------------------------------------------------------------------------
-- Parse args
-------------------------------------------------------------------------------

local args = parse_args()
if not args then
  respond("Usage: ;enchant <chapter> <recipe_name> <noun> [base_noun]")
  respond("       ;enchant resume <noun>")
  return
end

local item_noun  = args.noun
local base_noun  = args.base_noun or args.noun
local chapter    = args.chapter
local recipe_name = args.recipe
local is_resume  = args.resume

-------------------------------------------------------------------------------
-- Equipment manager
-------------------------------------------------------------------------------

local equip_mgr = DREMgr.EquipmentManager(settings)

-------------------------------------------------------------------------------
-- Flags
-------------------------------------------------------------------------------

local FLAG_NAMES = {
  "enchant-focus", "enchant-imbue", "enchant-meditate", "enchant-push",
  "enchant-sigil", "enchant-complete", "imbue-failed", "imbue-backlash",
}

local function setup_flags()
  Flags.add("enchant-focus",
    "material struggles to accept the sigil scribing")
  Flags.add("enchant-meditate",
    "The traced sigil pattern blurs before your eyes")
  Flags.add("enchant-imbue",
    "Once finished you sense an imbue spell will be required to continue enchanting")
  Flags.add("enchant-push",
    "You notice many of the scribed sigils are slowly merging back")
  Flags.add("enchant-sigil",
    "You need another .* sigil to continue the enchanting process")
  Flags.add("enchant-complete",
    "With the enchanting process completed, you believe it is safe to collect your things once more%.",
    "With the enchantment complete",
    "With enchanting complete",
    "^You collect the .+ and place it at your feet")
  Flags.add("imbue-failed",
    "The streams collide, rending the space before you and disrupting the enchantment")
  Flags.add("imbue-backlash",
    "Suddenly the streams slip through your grasp and cascade violently against each other")
end

local function cleanup_flags()
  for _, flag in ipairs(FLAG_NAMES) do
    Flags.remove(flag)
  end
end

-------------------------------------------------------------------------------
-- Response patterns
-------------------------------------------------------------------------------

local ANALYZE_READY_PATTERNS = {
  "scribing additional sigils onto the fount%.",
  "ready for additional scribing%.",
  "free of problems that would impede further sigil scribing%.",
  "You do not see anything that would prevent scribing additional sigils",
}
local ANALYZE_IMBUE_PATTERN = "application of an imbue spell to advance the enchanting process%."

local BRAZIER_HAS_FOUNT_PATTERN = "On the.*brazier you see.*and a.*"

local WAVE_FOUNT_SUCCESS    = "^You slowly wave"
local WAVE_FOUNT_NOT_NEEDED = "The fragile mana fount is not required"

local TOUCH_CUBE_PATTERNS = {
  "^Warm vapor swirls around your head in a misty halo",
  "^A thin cloud of vapor manifests with no particular effect%.",
  "^Touch what",
}

local PUT_BRAZIER_ALREADY_ENCHANTED = "^The totem is already enchanted"
local PUT_BRAZIER_SUCCESS           = { "With a flick", "^You put" }
local PUT_BRAZIER_NEEDS_CLEAN       = "^You must first clean"
local PUT_BRAZIER_GLANCE            = "^You glance down"

local GET_SUCCESS   = "You get"
local GET_DANGEROUS = "That is far too dangerous"

local IMBUE_WAND_SUCCESS      = "^Roundtime"
local IMBUE_WAND_SIGIL_NEEDED = "^You need another .* sigil to continue the enchanting process"
local IMBUE_WAND_FAILED       = "The streams collide, rending the space before you and disrupting the enchantment"

local CLEAN_SUCCESS  = "You prepare to clean off the brazier"
local CLEAN_NOT_LIT  = "The brazier is not currently lit"
local CLEAN_SINGED   = "a massive ball of flame jets forward and singes everything nearby"

local SIGIL_STUDY_SUCCESS = "^You study the sigil%-scroll and commit the design to memory"
local SIGIL_TRACE_SUCCESS = "^Recalling the intricacies of the sigil, you trace its form"

local SCRIBE_RT_PATTERN   = "^Roundtime"
local SCRIBE_SIGIL_NEEDED = "^You need another .* sigil to continue the enchanting process"

local STAMP_PATTERNS = {
  "carefully hammer the stamp",
  "You cannot figure out how to do that",
  "too badly damaged",
  "You lazily wave the stamp over the freshly enchanted",
}

local BOOK_TURN_PATTERNS = { "You turn your", "The book is already" }

-------------------------------------------------------------------------------
-- Utility
-------------------------------------------------------------------------------

local function pat_match(line, patterns)
  if type(patterns) == "string" then
    return line:find(patterns) ~= nil
  end
  for _, pat in ipairs(patterns) do
    if line:find(pat) then return true end
  end
  return false
end

local function cast_result_success(result)
  for _, pat in ipairs(DRCA.CAST_SUCCESS) do
    if result:find(pat) then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Tool get/stow wrappers
-------------------------------------------------------------------------------

local function get_tool(name)
  DRCC.get_crafting_item(name, bag, bag_items, belt)
end

local function stow_tool(name)
  if not name or name == "" then return end
  DRCC.stow_crafting_item(name, bag, belt)
end

-------------------------------------------------------------------------------
-- clean_brazier
-------------------------------------------------------------------------------

local function clean_brazier()
  local result = DRC.bput("clean " .. brazier_name,
    CLEAN_SUCCESS, "There is nothing", CLEAN_NOT_LIT)
  if result:find(CLEAN_SUCCESS, 1, true) then
    DRC.bput("clean " .. brazier_name, CLEAN_SINGED)
  elseif result:find(CLEAN_NOT_LIT, 1, true) then
    local lh = DRC.left_hand()
    if lh then stow_tool(lh) end
  end
end

-------------------------------------------------------------------------------
-- empty_brazier
-------------------------------------------------------------------------------

local function empty_brazier()
  local lh = DRC.left_hand()
  if lh then stow_tool(lh) end

  local result = DRC.bput("look on " .. brazier_name,
    "On the .* brazier you see", "There is nothing")
  local items_str = result:match("On the .* brazier you see (.*)")
  if not items_str then return end

  -- Strip trailing period; split on ", and" / "and" / ","
  items_str = items_str:gsub("%.$", "")
  local parts = {}
  for part in (items_str .. ","):gmatch("([^,]+),?") do
    local clean = part:gsub("^%s*and%s+", ""):match("^%s*(.-)%s*$")
    if clean and clean ~= "" then parts[#parts + 1] = clean end
  end

  for _, desc in ipairs(parts) do
    local noun = desc:match("%S+$")
    if noun then
      if not DRCI.get_item(noun, brazier_name) then
        DRC.message("Enchant: Failed to get " .. noun .. " from " .. brazier_name)
      else
        stow_tool(noun)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- trace_sigil
-------------------------------------------------------------------------------

local function trace_sigil(sigil)
  if not DRCI.get_item(sigil .. " sigil") then
    DRC.message("Enchant: Failed to get " .. sigil .. " sigil.")
    return
  end
  DRC.bput("study my " .. sigil .. " sigil", SIGIL_STUDY_SUCCESS)
  if waitrt then waitrt() end
  DRC.bput("trace " .. item_noun .. " on " .. brazier_name, SIGIL_TRACE_SUCCESS)
end

-------------------------------------------------------------------------------
-- imbue
-------------------------------------------------------------------------------

local function imbue()
  local waggle_imbue = settings.waggle_sets
                   and settings.waggle_sets["imbue"]
                   and settings.waggle_sets["imbue"]["Imbue"]

  if waggle_imbue then
    -- Spell-based imbue — deep-copy to avoid mutating global settings
    local imbue_data = {}
    for k, v in pairs(waggle_imbue) do imbue_data[k] = v end
    imbue_data.cast = "cast " .. item_noun .. " on " .. brazier_name

    local success = false
    while not success do
      local result = DRCA.cast_spell(imbue_data, settings)
      success = cast_result_success(result)
      if not success then
        DRC.message("Enchant: Casting Imbue failed. Retrying.")
      end
    end
  else
    -- Wand-based imbue
    if not DRCI.in_hands(imbue_wand) then
      get_tool(imbue_wand)
    end

    local result = DRC.bput(
      "wave " .. imbue_wand .. " at " .. item_noun .. " on " .. brazier_name,
      IMBUE_WAND_SUCCESS, IMBUE_WAND_SIGIL_NEEDED, IMBUE_WAND_FAILED)

    if result:find(IMBUE_WAND_FAILED, 1, true) then
      DRC.message("Enchant: Imbue wand failed. Retrying.")
      imbue()
      return
    end

    local lh = DRC.left_hand()
    if lh and lh:find(imbue_wand, 1, true) then
      stow_tool(imbue_wand)
    end
  end

  Flags.reset("enchant-imbue")
end

-------------------------------------------------------------------------------
-- cleanup / stamp
-------------------------------------------------------------------------------

local function stamp_item(noun)
  get_tool("stamp")
  DRC.bput("mark my " .. noun .. " with my stamp", table.unpack(STAMP_PATTERNS))
  stow_tool("stamp")
end

local function cleanup()
  local rh = DRC.right_hand()
  local lh = DRC.left_hand()
  if rh then stow_tool(rh) end
  if lh then stow_tool(lh) end
  if item_noun ~= "fount" then
    get_tool(fount_name)
    stow_tool(fount_name)
  end
  if DRCI.get_item(item_noun) then
    stow_tool(item_noun)
    -- Lich5 original calls get_item a second time (dispose extra copy); replicate:
    DRCI.get_item(item_noun)
  end
end

-------------------------------------------------------------------------------
-- Scribe loop
-------------------------------------------------------------------------------

local function scribe_loop()
  while true do
    local sigil_match = Flags["enchant-sigil"]  -- auto-resets on read

    if sigil_match then
      -- Extract sigil type: "You need another <type> primary/secondary sigil..."
      local sigil_type = sigil_match:match("You need another (.-)%s*primary sigil")
                      or sigil_match:match("You need another (.-)%s*secondary sigil")
                      or ""
      sigil_type = sigil_type:match("^%s*(.-)%s*$") or ""
      if sigil_type == "" then sigil_type = "congruence" end

      stow_tool(burin_name)
      trace_sigil(sigil_type)
      get_tool(burin_name)

    elseif Flags["enchant-focus"] then
      DRC.bput("focus " .. item_noun .. " on " .. brazier_name,
        "Once finished you sense an imbue spell will be required to continue enchanting",
        SCRIBE_RT_PATTERN, SCRIBE_SIGIL_NEEDED)
      if waitrt then waitrt() end

    elseif Flags["enchant-meditate"] then
      DRC.bput("meditate fount on " .. brazier_name,
        SCRIBE_RT_PATTERN, SCRIBE_SIGIL_NEEDED)
      if waitrt then waitrt() end

    elseif Flags["enchant-push"] then
      local lh = DRC.left_hand()
      if lh and lh:find("burin", 1, true) then stow_tool(burin_name) end
      get_tool(loop_name)
      DRC.bput("push " .. item_noun .. " on " .. brazier_name .. " with my " .. loop_name,
        SCRIBE_RT_PATTERN, SCRIBE_SIGIL_NEEDED)
      if waitrt then waitrt() end
      stow_tool(loop_name)
      get_tool(burin_name)

    elseif Flags["enchant-imbue"] then
      local lh = DRC.left_hand()
      if lh and lh:find("burin", 1, true) then stow_tool(burin_name) end
      imbue()
      get_tool(burin_name)

    elseif Flags["imbue-backlash"] then
      DRC.message("Enchant: Imbue backlash! Cleaning up and heading to safe room.")
      local rh = DRC.right_hand()
      local lh = DRC.left_hand()
      if rh then stow_tool(rh) end
      if lh then stow_tool(lh) end
      cleanup()
      DRC.wait_for_script_to_complete("safe-room", {"force"})
      return

    elseif Flags["enchant-complete"] then
      DRC.message("Enchant: Enchanting complete!")
      local rh = DRC.right_hand()
      local lh = DRC.left_hand()
      if rh then stow_tool(rh) end
      if lh then stow_tool(lh) end
      cleanup()
      if stamp then stamp_item(item_noun) end
      return

    else
      -- Normal scribe step
      DRC.bput("scribe " .. item_noun .. " on " .. brazier_name .. " with my " .. burin_name,
        SCRIBE_RT_PATTERN, SCRIBE_SIGIL_NEEDED)
      if waitrt then waitrt() end
    end
  end
end

-------------------------------------------------------------------------------
-- place_item_on_brazier (forward declared for mutual recursion with study_recipe)
-------------------------------------------------------------------------------

local study_recipe  -- forward declaration

local function place_item_inner()
  for _ = 1, 2 do
    local all = { PUT_BRAZIER_GLANCE }
    for _, p in ipairs(PUT_BRAZIER_SUCCESS) do all[#all + 1] = p end
    local result = DRC.bput("put my " .. base_noun .. " on " .. brazier_name,
      table.unpack(all))
    if pat_match(result, PUT_BRAZIER_SUCCESS) then
      if waitrt then waitrt() end
      return
    end
  end
end

local function place_item_on_brazier()
  for _ = 1, 2 do
    local all = {
      PUT_BRAZIER_ALREADY_ENCHANTED,
      PUT_BRAZIER_GLANCE,
      PUT_BRAZIER_NEEDS_CLEAN,
    }
    for _, p in ipairs(PUT_BRAZIER_SUCCESS) do all[#all + 1] = p end

    local result = DRC.bput("put my " .. base_noun .. " on " .. brazier_name,
      table.unpack(all))

    if result:find(PUT_BRAZIER_ALREADY_ENCHANTED) then
      DRC.message("Enchant: Totem already enchanted, disposing and retrying.")
      DRCI.dispose_trash("totem", worn_trashcan, worn_trashcan_verb)
      study_recipe()  -- retry from the top
      return
    elseif pat_match(result, PUT_BRAZIER_SUCCESS) then
      if waitrt then waitrt() end
      return
    elseif result:find(PUT_BRAZIER_NEEDS_CLEAN) then
      clean_brazier()
      empty_brazier()
      if not DRCI.get_item(base_noun, bag) then
        DRC.message("Enchant: Failed to get " .. base_noun .. " after cleaning.")
        return
      end
      place_item_inner()
      return
    end
  end
end

study_recipe = function()
  if settings.master_crafting_book then
    DRCC.find_recipe2(chapter, recipe_name, settings.master_crafting_book, book_type)
  else
    get_tool(book_type .. " book")
    DRCC.find_recipe2(chapter, recipe_name)
    stow_tool("book")
  end

  if use_own_brazier then
    get_tool(brazier_name)
  end

  local get_result = DRC.bput("get my " .. base_noun .. " from my " .. bag,
    GET_SUCCESS, GET_DANGEROUS)
  if get_result:find(GET_DANGEROUS, 1, true) then
    clean_brazier()
    empty_brazier()
    if not DRCI.get_item(base_noun, bag) then
      DRC.message("Enchant: Failed to get " .. base_noun .. " from " .. bag)
      return
    end
  end

  place_item_on_brazier()
end

-------------------------------------------------------------------------------
-- Resume mode
-------------------------------------------------------------------------------

local function handle_imbue_resume()
  local look_result = DRC.bput("look on my " .. brazier_name,
    BRAZIER_HAS_FOUNT_PATTERN, "There is nothing")
  if look_result:find(BRAZIER_HAS_FOUNT_PATTERN) then
    imbue()
  else
    get_tool(fount_name)
    local wave_result = DRC.bput(
      "wave my " .. fount_name .. " at " .. item_noun .. " on " .. brazier_name,
      WAVE_FOUNT_SUCCESS, WAVE_FOUNT_NOT_NEEDED)
    if wave_result:find(WAVE_FOUNT_NOT_NEEDED, 1, true) then
      stow_tool(fount_name)
    end
    imbue()
  end
end

local function handle_resume()
  DRCC.get_crafting_item(brazier_name, bag, bag_items, belt)

  local analyze_patterns = {}
  for _, p in ipairs(ANALYZE_READY_PATTERNS) do
    analyze_patterns[#analyze_patterns + 1] = p
  end
  analyze_patterns[#analyze_patterns + 1] = ANALYZE_IMBUE_PATTERN

  local result = DRC.bput("analyze " .. item_noun .. " on my " .. brazier_name,
    table.unpack(analyze_patterns))

  local is_ready = false
  for _, pat in ipairs(ANALYZE_READY_PATTERNS) do
    if result:find(pat) then is_ready = true; break end
  end

  if is_ready then
    get_tool(burin_name)
    scribe_loop()
  elseif result:find(ANALYZE_IMBUE_PATTERN) then
    handle_imbue_resume()
  else
    DRC.message("Enchant: Unexpected analyze result: " .. result)
  end
end

-------------------------------------------------------------------------------
-- New enchant
-------------------------------------------------------------------------------

local function handle_new_enchant()
  study_recipe()

  -- "small sphere" becomes "fount" once placed on the brazier
  if item_noun == "small sphere" then item_noun = "fount" end

  if item_noun ~= "fount" then
    if not DRCI.exists(fount_name) then
      DRC.message("Enchant: " .. fount_name .. " not found in inventory. Cannot proceed.")
      cleanup()
      return
    end

    get_tool(fount_name)
    local wave_result = DRC.bput(
      "wave my " .. fount_name .. " at " .. item_noun .. " on " .. brazier_name,
      WAVE_FOUNT_SUCCESS, WAVE_FOUNT_NOT_NEEDED)
    if wave_result:find(WAVE_FOUNT_NOT_NEEDED, 1, true) then
      stow_tool(fount_name)
    end
  end

  -- Touch cube (optional — assists enchanting if worn)
  if cube then
    DRC.bput("touch my " .. cube, table.unpack(TOUCH_CUBE_PATTERNS))
  end

  imbue()

  get_tool(burin_name)
  scribe_loop()
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local ok, err = pcall(function()
  setup_flags()
  equip_mgr:empty_hands()
  DRC.wait_for_script_to_complete("buff", {"enchant"})

  if is_resume then
    handle_resume()
  else
    handle_new_enchant()
  end
end)

cleanup_flags()

if not ok then
  DRC.message("Enchant: Fatal error: " .. tostring(err))
end
