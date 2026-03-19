--- @revenant-script
--- name: sigilharvest
--- version: 2.0.0
--- author: Elanthia Online (lic), Matt (original)
--- game: dr
--- description: Harvest and scribe sigils using the artificing enchanting minigame.
--- tags: crafting, enchanting, artificing, sigil, scroll
--- @lic-certified: complete 2026-03-19
---
--- Hunts rooms for sigils matching a given type (or random), runs the
--- improvement minigame to maximize precision, then scribes the sigil
--- to a blank scroll.  Implements the full v2.0.0 algorithm from the
--- original Lich5 sigilharvest.lic including:
---   - EXP-18  min difficulty threshold (skip trivial precision actions)
---   - EXP-17  resource-aware tiebreaker
---   - EXP-14r cost equalization (all costs treated as equal)
---   - EXP-9   resource exhaustion coefficient check
---   - C1 fix  @actually_scribed flag (not precision-threshold-based)
---   - Trader speculate luck on iteration 0 with prec >= 14 + circle >= 65
---   - Automatic blank scroll restocking from city shop
---   - Burin validation (belt and bag locations)
---
--- Valid sigil types: abolition congruence induction permutation rarefaction
---   antipode ascension clarification decay evolution integration
---   metamorphosis nurture paradox unity
---
--- Usage:
---   ;sigilharvest <city> <sigil|random> <precision> [minutes] [debug]
---
--- Arguments:
---   city       Shard, Crossing, Riverhaven, Hibarnhvidar (or hib)
---   sigil      Sigil type to hunt, or "random" for a random sigil each loop
---   precision  Target precision (e.g., 80, 90)
---   minutes    Session time limit in minutes (default: 30)
---   debug      Literal word "debug" to enable verbose logging
---
--- Examples:
---   ;sigilharvest Crossing congruence 80
---   ;sigilharvest Shard random 90 45 debug

-------------------------------------------------------------------------------
-- Argument parsing
-------------------------------------------------------------------------------

local SIGIL_LIST = {
  "abolition", "congruence", "induction", "permutation", "rarefaction",
  "antipode", "ascension", "clarification", "decay", "evolution",
  "integration", "metamorphosis", "nurture", "paradox", "unity",
}

local function parse_args()
  local raw = Script.vars and Script.vars[0] or ""
  local tokens = {}
  for tok in raw:gmatch("%S+") do
    tokens[#tokens + 1] = tok
  end

  if #tokens < 3 then
    respond("[sigilharvest] Usage: ;sigilharvest <city> <sigil|random> <precision> [minutes] [debug]")
    return nil
  end

  local args = {
    city      = tokens[1],
    sigil     = tokens[2]:lower(),
    precision = tonumber(tokens[3]),
    minutes   = 30,
    debug     = false,
  }

  for i = 4, #tokens do
    local t = tokens[i]:lower()
    if t == "debug" then
      args.debug = true
    elseif tonumber(t) then
      args.minutes = tonumber(t)
    end
  end

  if not args.precision then
    respond("[sigilharvest] Error: precision must be a number (e.g., 80, 90)")
    return nil
  end

  return args
end

-------------------------------------------------------------------------------
-- Pattern tables (Lua string.find compatible — no | alternation)
-------------------------------------------------------------------------------

-- Lines indicating sigil search is in progress but not yet found
local SEARCH_PATTERNS = {
  "^You clear your mind",
  "^Left and right you crane your head",
  "^Back and forth you walk",
  "^You close your eyes and turn to a random direction",
  "^You scour the area looking for hints of sigil lore",
  "^Whorls of dust upon the ground catch your eye",
  "^The sky holds your interest",
  "^The ceiling holds your interest",
}

-- Lines indicating a sigil was found (used as Flags and bput patterns)
local FOUND_PATTERNS = {
  "After much scrutiny",
  "Through the seemingly mundane lighting",
  "Almost obscured by the surroundings",
  "Subtleties in the surroundings",
  "The area contains signs of a sigil",
  "In your mind's eye",
  "Sorting through the imagery",
}

-- Lines indicating improvement failed (used in Flags and result checks)
local MISHAP_PATTERNS = {
  "Chills creep down your spine",
  "About the area you wander",
  "A sudden sneeze",
  "You lose track",
  "You prepare yourself for continued exertion",
  "You are too distracted",
}

-- Helper: check if a string matches any pattern in a table
local function matches_any(str, patterns)
  for _, p in ipairs(patterns) do
    if str:find(p) then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local args = parse_args()
if not args then return end

local settings      = get_settings()
local burin         = "burin"
if settings.enchanting_tools then
  for _, t in ipairs(settings.enchanting_tools) do
    if t:find("burin") then burin = t; break end
  end
end
local bag           = settings.crafting_container
local belt          = settings.enchanting_belt
local bag_items     = settings.crafting_items_in_container
local danger_rooms  = (settings.sigil_harvest_settings or {})["danger_rooms"] or {}
local stock_scrolls = (settings.sigil_harvest_settings or {})["blank_scrolls"] or 25

local burin_belt       = nil
local sigil_count      = 0
local sigil_results    = {}
local start_time       = os.time()
local time_limit       = args.minutes
local rooms_visited    = 0
local enemy_rooms      = {}

-- Per-sigil state (reset in harvest_sigil)
local sigil_precision    = 0
local sigil_clarity      = 0
local danger_lvl         = 0
local sanity_lvl         = 0
local resolve_lvl        = 0
local focus_lvl          = 0
local num_iterations     = 0
local num_aspect_repairs = 0
local actually_scribed   = false
local sigil_start_time   = os.time()
local sigil_improvement  = {}

-- Algorithm constants
local ACTION_COST = { taxing = 1, disrupting = 1, destroying = 1 }
local ACTION_DIFFICULTY = {
  trivial = 1, straightforward = 2, formidable = 3, challenging = 4, difficult = 5,
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function round1(n)
  return math.floor(n * 10 + 0.5) / 10
end

local function elapsed_minutes()
  return (os.time() - start_time) / 60.0
end

local function sigil_elapsed_minutes()
  return (os.time() - sigil_start_time) / 60.0
end

local function time_expired()
  return elapsed_minutes() >= time_limit
end

local function contest_stat_for(resource)
  if resource == "sanity"  then return sanity_lvl  end
  if resource == "resolve" then return resolve_lvl end
  if resource == "focus"   then return focus_lvl   end
  return 0
end

local function precision_action_viable(action, cstat, _precision)
  local difficulty = tonumber(action.difficulty) or 0
  local margin = cstat - difficulty
  -- EXP-18: skip trivial (difficulty=1) precision actions
  if difficulty < 2 then return false end
  -- comfortable margin: accept straightforward+
  if margin > 1 then return true end
  -- tight margin: only challenging+ (difficulty > 2)
  if margin > 0 and difficulty > 2 then return true end
  return false
end

local function select_repair_action(action, cstat, precision, repair_target, current_repair, cb)
  if (tonumber(action.difficulty) or 0) > 3 then return end
  if not repair_target.difficulty then return end
  if (cstat - (tonumber(action.difficulty) or 0)) < 2 then return end
  if sigil_precision < (precision - 15) then return end
  if action.aspect ~= repair_target.resource then return end

  if current_repair.difficulty then
    if (tonumber(current_repair.risk) or 0) > (tonumber(action.risk) or 0) then
      cb(action)
    end
  else
    if args.debug then DRC.message("Storing new verb for aspect repair") end
    cb(action)
  end
end

-------------------------------------------------------------------------------
-- Tool validation
-------------------------------------------------------------------------------

local function resolve_burin(errors)
  local belt_name = type(belt) == "table" and belt["name"] or belt

  -- Attempt 1: settings name from belt
  if belt_name then
    local result = DRC.bput("untie my " .. burin .. " from my " .. belt_name,
      "You untie", "Untie what", "You are not wearing")
    if result:find("You untie") then
      burin_belt = belt
      DRC.bput("tie my " .. burin .. " to my " .. belt_name,
        "You tie", "you attach", "doesn't seem to fit")
      return
    end
  end

  -- Attempt 2: settings name from bag
  local result = DRC.bput("get my " .. burin,
    "You get", "You pick", "What were you", "You are already")
  if result:find("You get") or result:find("You pick") or result:find("already") then
    burin_belt = nil
    fput("stow my " .. burin)
    return
  end

  -- Attempt 3: plain 'burin'
  result = DRC.bput("get my burin",
    "You get", "You pick", "What were you", "You are already",
    "You should untie")
  if result:find("You get") or result:find("You pick") or result:find("already") then
    burin = "burin"
    burin_belt = nil
    fput("stow my burin")
    return
  end

  -- Attempt 4: game told us "You should untie the <name> from the <belt>"
  if result:find("You should untie") and belt_name then
    local real_name = result:match("untie the (.+?) from")
    if real_name then
      local untie_result = DRC.bput("untie my " .. real_name .. " from my " .. belt_name,
        "You untie", "Untie what")
      if untie_result:find("You untie") then
        burin = real_name
        burin_belt = belt
        DRC.bput("tie my " .. real_name .. " to my " .. belt_name,
          "You tie", "you attach", "doesn't seem to fit")
        return
      end
    end
  end

  errors[#errors + 1] = "Could not find any burin in inventory or on belt"
end

local function validate_tools()
  local errors = {}
  if not bag or bag == "" then
    errors[#errors + 1] = "No crafting container configured (crafting_container setting)"
  end
  if not settings.sigil_harvest_settings then
    errors[#errors + 1] = "No sigil_harvest_settings configured"
  end
  if #errors > 0 then return errors end

  DRCI.stow_hands()
  resolve_burin(errors)
  return errors
end

-------------------------------------------------------------------------------
-- Burin get / stow
-------------------------------------------------------------------------------

local function get_burin()
  if burin_belt then
    DRCC.get_crafting_item(burin, bag, bag_items, burin_belt)
  else
    DRC.bput("get my " .. burin,
      "You get", "You pick", "What were you", "You are already")
  end
end

local function stow_burin()
  if burin_belt then
    DRCC.stow_crafting_item(burin, bag, burin_belt)
  else
    fput("stow my " .. burin)
  end
end

-------------------------------------------------------------------------------
-- Season / techniques
-------------------------------------------------------------------------------

local function get_season()
  local result = DRC.bput("time", "^It is currently")
  local s = result:match("^It is currently (%a+) and")
  return s and s:lower() or "spring"
end

local function get_techniques()
  put("craft artificing")
  -- Capture either the technique list line or the "no knowledge" response
  local result = matchtimeout(3,
    "have been trained in",
    "no crafting techniques",
    "You have no knowledge")
  if not result
      or result:find("no crafting techniques")
      or result:find("no knowledge") then
    return {}
  end
  local list_part = result:match("have been trained in (.+)%.%s*$")
  if not list_part then return {} end

  local techniques = {}
  -- Split on ", " and " and "
  local cleaned = list_part:gsub(" and ", ", ")
  for part in cleaned:gmatch("([^,]+)") do
    local t = part:match("^%s*(.-)%s*$")
    if t ~= "" and t:find("Sigil Comprehension") then
      techniques[#techniques + 1] = t
    end
  end
  return techniques
end

local function format_techniques(techniques)
  if not techniques or #techniques == 0 then return "none" end
  local out = {}
  for _, t in ipairs(techniques) do
    out[#out + 1] = t:gsub(" Sigil Comprehension", "")
  end
  return table.concat(out, ", ")
end

-------------------------------------------------------------------------------
-- Scroll restocking
-------------------------------------------------------------------------------

local function get_scrolls()
  local target      = stock_scrolls
  local num_scrolls = DRCI.count_item_parts("blank scroll")
  if args.debug then DRC.message("Scrolls remaining: " .. num_scrolls) end
  if num_scrolls >= target then return end

  local scroll_room, scroll_price
  local city_l = args.city:lower()
  if city_l:find("crossing") then
    scroll_room = 14754; scroll_price = 125
  elseif city_l:find("riverhaven") then
    scroll_room = 14770; scroll_price = 100
  elseif city_l:find("shard") then
    scroll_room = 14772; scroll_price = 90
  elseif city_l:find("hib") then
    scroll_room = 15522; scroll_price = 90
  end

  if not scroll_room then
    DRC.message("[sigilharvest] Unknown city for scroll shop: " .. args.city)
    return
  end

  if args.debug then DRC.message("Buying scrolls from room " .. scroll_room) end
  DRCI.stow_hands()

  local num_to_order   = math.ceil((target - num_scrolls) / 25.0)
  local coppers_needed = num_to_order * scroll_price

  if args.debug then DRC.message("Getting " .. coppers_needed .. " coppers to buy scrolls.") end
  DRCM.ensure_copper_on_hand(coppers_needed, settings)

  if args.debug then DRC.message("Ordering scrolls " .. num_to_order .. " times.") end
  for _ = 1, num_to_order do
    DRCT.order_item(scroll_room, 8)
    DRC.bput("combine", "^You combine", "^You must")
  end

  -- combine any loose stack from bag
  if DRCI.get_item("blank scroll", bag) then
    DRC.bput("combine", "^You combine", "^You must")
  end
  DRCC.stow_crafting_item("blank scroll", bag, belt)
end

-------------------------------------------------------------------------------
-- Scribe
-------------------------------------------------------------------------------

local function scribe_sigils()
  actually_scribed = true
  DRCI.stow_hands()
  DRCI.get_item("blank scrolls")
  get_burin()

  local scribe_count = 0
  while true do
    local result = DRC.bput("scribe sigil", "You carefully", "You should")
    if result:find("You carefully") then
      scribe_count = scribe_count + 1
      DRCC.stow_crafting_item("sigil%-scroll", bag, belt)
      DRC.bput("get blank scroll", "You pick", "You get")
    else
      break
    end
  end

  DRC.message("Scribes: " .. scribe_count)
  stow_burin()
  DRCC.stow_crafting_item("blank scroll", bag, belt)
  fput("stow feet")
  get_scrolls()
end

-------------------------------------------------------------------------------
-- Logging helpers
-------------------------------------------------------------------------------

local function log_sigil_summary(sigil, result)
  local prec     = sigil_precision or 0
  local danger   = danger_lvl or 0
  local iters    = num_iterations or 0
  local sel      = round1(sigil_elapsed_minutes())
  local tel      = round1(elapsed_minutes())
  DRC.message(string.format(
    "[Sigil #%d] type=%s result=%s precision=%d/%s iterations=%d danger=%d room=%d elapsed=%.1fm total=%.1fm",
    sigil_count, sigil, result, prec, tostring(args.precision), iters, danger,
    rooms_visited, sel, tel))
  sigil_results[#sigil_results + 1] = {
    number     = sigil_count,
    sigil_type = sigil,
    result     = result,
    precision  = prec,
    target     = args.precision,
    iterations = iters,
    danger     = danger,
    room       = rooms_visited,
    elapsed    = sel,
  }
end

local function log_startup_banner(season, techniques)
  DRC.message("== SigilHarvest v2.0.0 ==")
  DRC.message("  City:             " .. args.city)
  DRC.message("  Sigil:            " .. args.sigil)
  DRC.message("  Target prec:      " .. tostring(args.precision))
  DRC.message("  Time limit:       " .. time_limit .. " minutes")
  DRC.message("  Debug:            " .. (args.debug and "true" or "false"))
  DRC.message("  Season:           " .. season)
  DRC.message("  Techniques:       " .. format_techniques(techniques))
  DRC.message("  Burin:            " .. burin)
  DRC.message("  Bag:              " .. tostring(bag))
  DRC.message("  Danger rooms:     " .. (function()
    local t = {}
    for _, r in ipairs(danger_rooms) do t[#t+1] = tostring(r) end
    return table.concat(t, ", ")
  end)())
  DRC.message("  Stock scrolls:    " .. stock_scrolls)
  DRC.message("========================")
end

local function log_exit_summary()
  local total    = #sigil_results
  local scribed  = 0
  local failed   = 0
  local skipped  = 0
  local attempted = {}

  for _, r in ipairs(sigil_results) do
    if     r.result == "SCRIBED" then scribed = scribed + 1
    elseif r.result == "FAILED"  then failed  = failed  + 1
    elseif r.result == "SKIPPED" then skipped = skipped + 1
    end
    if r.result ~= "SKIPPED" then
      attempted[#attempted + 1] = r
    end
  end

  local avg_prec, avg_iters = 0, 0
  local best = nil
  if #attempted > 0 then
    local sp, si = 0, 0
    for _, r in ipairs(attempted) do
      sp = sp + r.precision
      si = si + r.iterations
      if not best or r.precision > best.precision then best = r end
    end
    avg_prec  = round1(sp / #attempted)
    avg_iters = round1(si / #attempted)
  end

  local rate = total > 0 and round1((scribed / total) * 100) or 0.0

  DRC.message("== Session Summary ==")
  DRC.message("  City:             " .. args.city)
  DRC.message("  Sigil:            " .. args.sigil)
  DRC.message("  Target prec:      " .. tostring(args.precision))
  DRC.message("  Time limit:       " .. time_limit .. " minutes")
  DRC.message("  Run time:         " .. round1(elapsed_minutes()) .. " minutes")
  DRC.message("  Rooms visited:    " .. rooms_visited)
  DRC.message("  ---")
  DRC.message("  Sigils total:     " .. total)
  DRC.message("  Scribed:          " .. scribed)
  DRC.message("  Failed:           " .. failed)
  DRC.message("  Skipped:          " .. skipped)
  DRC.message(string.format("  Success rate:     %.1f%%", rate))
  DRC.message("  Avg precision:    " .. avg_prec .. " (non-skipped)")
  DRC.message("  Avg iterations:   " .. avg_iters .. " (non-skipped)")
  if best then
    DRC.message(string.format("  Best sigil:       #%d precision=%d/%d iterations=%d",
      best.number, best.precision, best.target, best.iterations))
  end
  DRC.message("== End SigilHarvest v2.0.0 ==")
end

-------------------------------------------------------------------------------
-- sigil_info — issue a perc sigil command, parse minigame state
-------------------------------------------------------------------------------

local function do_sigil_info(command)
  -- Build pattern list: found-result pattern + all mishap patterns
  local pat_args = { "^You have perceived a" }
  for _, p in ipairs(MISHAP_PATTERNS) do pat_args[#pat_args + 1] = p end

  local results = DRC.bput("perc sigil " .. command, unpack(pat_args))

  if matches_any(results, MISHAP_PATTERNS) then
    DRC.message("Final precision: " .. sigil_precision)
    if args.debug then DRC.message("Sigil harvesting failed") end
    return false
  end

  -- Parse clarity and precision from "...(Clarity:5)...(Precision:23)..."
  local c_str, p_str = results:match("%(Clarity:(%d+)%).-%(Precision:(%d+)%)")
  if c_str then sigil_clarity   = tonumber(c_str) end
  if p_str then sigil_precision = tonumber(p_str) end

  -- Early skip: target >= 80 and starting precision < 13
  if args.precision >= 80 and sigil_precision < 13 then
    DRC.message("Target precision >= 80, moving on as starting precision is below 13")
    return false
  end

  -- No-actions flag check
  if Flags["sigilharvest-noactions"] then
    if args.debug then DRC.message("No actions remain. Generating new actions...") end
    return true
  end

  -- Capture improvement action lines until terminal line
  local improvements = {}
  if args.debug then DRC.message("Entering improvement capture loop...") end
  while true do
    local line = waitfor(
      "^%.",
      "^You also take the opportunity to take stock of your mental health",
      "^You are unable to perceive any opportunities for improving the sigil")
    if line:find("^You also take") or line:find("^You are unable to perceive") then
      break
    end
    improvements[#improvements + 1] = line
  end

  -- Parse action lines: "...a <diff>, <resource> <impact> <verb> ... your|sigil <aspect>."
  -- Ruby original: /^\.\.\.a (\w+), (\w+) (\w+) (\w+).*(your|sigil) (\w+)\.?$/
  -- Capture groups: diff, resource, impact, verb, (your|sigil), aspect
  sigil_improvement = {}
  for _, x in ipairs(improvements) do
    -- Use a 6-capture Lua pattern mirroring the Ruby regex.
    -- Lua's .* is greedy so (your) or (sigil) matches the LAST occurrence before aspect.
    local diff, res, imp, verb, _tgt, asp =
      x:match("^%.%.%.a (%a+), (%a+) (%a+) (%a+).-(your) (%a+)%.?$")
    if not diff then
      diff, res, imp, verb, _tgt, asp =
        x:match("^%.%.%.a (%a+), (%a+) (%a+) (%a+).-(sigil) (%a+)%.?$")
    end
    if diff then
      local difficulty_val = ACTION_DIFFICULTY[diff]
      local cost_val       = ACTION_COST[imp]
      if difficulty_val and cost_val then
        sigil_improvement[#sigil_improvement + 1] = {
          difficulty = difficulty_val,
          resource   = res,
          impact     = cost_val,
          verb       = verb,
          aspect     = asp,
          risk       = difficulty_val + cost_val,
        }
      end
    end
  end

  -- Parse resource gauges: lines like "Danger: *****  Sanity: ****"
  local danger_str  = waitfor("Danger:")
  local sanity_str  = waitfor("Sanity:")
  local resolve_str = waitfor("Resolve:")
  local focus_str   = waitfor("Focus:")

  local function count_stars(s)
    if not s then return 0 end
    local _, n = s:gsub("%*", "")
    return n
  end
  danger_lvl  = count_stars(danger_str)
  sanity_lvl  = count_stars(sanity_str)
  resolve_lvl = count_stars(resolve_str)
  focus_lvl   = count_stars(focus_str)

  -- EXP-9: resource exhaustion check (coefficient 1.75)
  local available = (sanity_lvl + resolve_lvl + focus_lvl) * 1.75 + sigil_precision
  if available < (args.precision - 5) then
    DRC.message("Exiting: available resources (" .. available .. ") below target precision - 5")
    DRC.message("Final precision: " .. sigil_precision)
    return false
  end

  -- Trader luck speculation on first iteration with prec >= 14 and circle >= 65
  if sigil_precision >= 14 and num_iterations == 0 then
    if DRStats.trader() and (DRStats.circle or 0) >= 65 then
      waitrt()
      fput("speculate luck")
    end
  end

  num_iterations = num_iterations + 1
  return true
end

-------------------------------------------------------------------------------
-- improve_sigil — one iteration of the minigame decision loop
-------------------------------------------------------------------------------

local function improve_sigil(precision)
  waitrt()

  local sigil_action       = {}
  local aspect_repair      = {}
  local best_repair_aspect = {}
  local second_best_repair = {}
  local repair_override    = false

  -- Phase 1: identify too-difficult precision actions as repair candidates
  for _, x in ipairs(sigil_improvement) do
    local cstat = contest_stat_for(x.resource)
    if x.aspect == "precision"
        and (cstat - (tonumber(x.difficulty) or 0) < 2)
        and ((tonumber(x.difficulty) or 0) >= 3) then
      if best_repair_aspect.difficulty then
        if (tonumber(x.difficulty) or 0) > (tonumber(best_repair_aspect.difficulty) or 0) then
          second_best_repair = best_repair_aspect
          best_repair_aspect = x
        end
      else
        best_repair_aspect = x
        if args.debug then DRC.message("Best repair option selected") end
      end
    end
  end

  -- Phase 2: select precision action and repair opportunities
  for _, x in ipairs(sigil_improvement) do
    local cstat = contest_stat_for(x.resource)

    if args.debug then
      DRC.message(string.format(
        "Aspect: %s -> Precision Comparison %d|%d -> Risk|Stat: %s|%d",
        x.aspect, sigil_precision, precision, tostring(x.risk), cstat))
    end

    -- EXP-7 + EXP-17: select precision action by difficulty, tiebreak cost then resource
    if x.aspect == "precision"
        and (x.verb or ""):upper() ~= "ACTION"
        and precision_action_viable(x, cstat, precision) then
      if args.debug then DRC.message("Potential precision upgrade found... ") end

      if sigil_action.difficulty then
        local xd  = tonumber(x.difficulty)  or 0
        local sad = tonumber(sigil_action.difficulty) or 0
        local xi  = tonumber(x.impact)  or 0
        local sai = tonumber(sigil_action.impact) or 0
        if xd > sad then
          sigil_action = x
        elseif xd == sad and xi < sai then
          sigil_action = x
        elseif xd == sad and xi == sai then
          -- EXP-17: prefer action on most-available resource
          if contest_stat_for(x.resource) > contest_stat_for(sigil_action.resource) then
            sigil_action = x
          end
        end
      else
        sigil_action = x
        if args.debug then DRC.message("Storing new verb for precision improvement") end
      end
    end

    -- Repair selection for best and second-best repair targets
    select_repair_action(x, cstat, precision, best_repair_aspect, aspect_repair, function(sel)
      aspect_repair = sel; repair_override = true
    end)
    select_repair_action(x, cstat, precision, second_best_repair, aspect_repair, function(sel)
      aspect_repair = sel; repair_override = true
    end)
  end

  if args.debug then DRC.message("Iteration #: " .. num_iterations) end

  -- Phase 3: early bail-out

  -- Hard iteration cap (15 iterations)
  if num_iterations >= 15 then
    if sigil_precision >= (precision - 5) then
      if args.debug then
        DRC.message("Current Precision: " .. sigil_precision ..
          " | Target Precision: " .. args.precision)
      end
      DRC.message("Final precision: " .. sigil_precision .. ", scribing (iteration cap)")
      scribe_sigils()
    else
      DRC.message("Exiting: iteration cap reached at precision " .. sigil_precision)
      DRC.message("Final precision: " .. sigil_precision)
    end
    return false
  end

  -- Move budget check: (14-used)*13 < remaining_gap
  if (14 - num_iterations) * 13 < (precision - sigil_precision - 5) then
    DRC.message("Exiting: insufficient moves to reach target")
    DRC.message("Final precision: " .. sigil_precision)
    return false
  end

  -- Scribe if precision target reached
  if sigil_precision >= precision then
    if args.debug then
      DRC.message("Current Precision: " .. sigil_precision ..
        " | Target Precision: " .. args.precision)
    end
    DRC.message("Final precision: " .. sigil_precision .. ", scribing")
    scribe_sigils()
    return false
  elseif args.debug then
    DRC.message("Current Precision: " .. sigil_precision ..
      " | Target Precision: " .. args.precision)
  end

  -- Phase 4: apply repair if no precision action available
  if (num_aspect_repairs < 2 or repair_override) and not sigil_action.difficulty then
    if danger_lvl <= 18 and aspect_repair.difficulty then
      DRC.message("Executing aspect repair")
      sigil_action = aspect_repair
      num_aspect_repairs = num_aspect_repairs + 1
    end
  end

  -- Execute chosen action or refresh the action list
  if sigil_action.difficulty then
    return do_sigil_info(sigil_action.verb)
  else
    return do_sigil_info("improve")
  end
end

-------------------------------------------------------------------------------
-- harvest_sigil — process one room
-------------------------------------------------------------------------------

local function harvest_sigil(sigil)
  sigil_count      = sigil_count + 1
  sigil_start_time = os.time()
  sigil_precision    = 0
  sigil_clarity      = 0
  danger_lvl         = 0
  num_iterations     = 0
  num_aspect_repairs = 0
  actually_scribed   = false
  sigil_improvement  = {}
  local sigil_result = "FAILED"

  -- Build bput pattern list for the finding loop
  local find_pats = {}
  for _, p in ipairs(FOUND_PATTERNS)   do find_pats[#find_pats + 1] = p end
  for _, p in ipairs(SEARCH_PATTERNS)  do find_pats[#find_pats + 1] = p end
  find_pats[#find_pats + 1] = "You are too distracted"
  find_pats[#find_pats + 1] = "You recall"
  find_pats[#find_pats + 1] = "Having recently been searched"
  find_pats[#find_pats + 1] = "You are already"

  -- Sigil finding loop
  while true do
    local r = DRC.bput("perc sigil", unpack(find_pats))

    if r:find("You are too distracted") then
      local rid = tostring(Room.id or "?")
      DRC.message("Enemies detected. Consider adding room " .. rid ..
        " to personal no-go list in your character-setup YAML.")
      enemy_rooms[#enemy_rooms + 1] = Room.id
      log_sigil_summary(sigil, "SKIPPED")
      return false
    end

    if r:find("You recall") or r:find("Having recently been searched") or r:find("You are already") then
      if args.debug then
        DRC.message("This room does not contain the desired sigil or has been searched too recently.")
      end
      log_sigil_summary(sigil, "SKIPPED")
      return false
    end

    waitrt()

    -- Check if a sigil was found via the downstream flag
    local found_line = Flags["sigilharvest-found"]
    if found_line then
      -- Extract sigil type from flag line or from sigilharvest-type flag
      local type_line  = Flags["sigilharvest-type"] or found_line
      local found_type = nil
      for _, stype in ipairs(SIGIL_LIST) do
        if type_line:find(stype, 1, true) then
          found_type = stype; break
        end
      end
      if args.debug then DRC.message("Sigil found: " .. tostring(found_type)) end
      if found_type == sigil then break end
    else
      pause(0.2)
    end
  end

  -- Kick off the improvement loop
  if do_sigil_info("improve") then
    while improve_sigil(args.precision) do
      if args.debug then
        DRC.message(string.format(
          "Current Precision: %d | Target Precision: %s | Danger Modifier: %d",
          sigil_precision, tostring(args.precision), math.floor(danger_lvl * 0.5)))
      end
    end
    -- C1 fix: use actually_scribed flag, not precision check
    if actually_scribed then sigil_result = "SCRIBED" end
  else
    log_sigil_summary(sigil, sigil_result)
    return false
  end

  log_sigil_summary(sigil, sigil_result)
  return true
end

-------------------------------------------------------------------------------
-- find_sigils — outer city / room-walking loop
-------------------------------------------------------------------------------

local function find_sigils(city, sigil_type)
  local data   = get_data("sigils")
  local season = get_season()

  while true do
    local active_sigil = sigil_type
    if args.sigil == "random" then
      active_sigil = SIGIL_LIST[math.random(#SIGIL_LIST)]
    end

    local sigil_data = data["SigilInfo"]
    if not sigil_data then
      DRC.message("[sigilharvest] No SigilInfo in data/dr/base-sigils.json")
      return
    end

    local city_data = sigil_data[city]
    if not city_data then
      DRC.message("[sigilharvest] No data for city: " .. city)
      return
    end

    local roomlist = city_data[active_sigil] and city_data[active_sigil][season]
    if not roomlist or #roomlist == 0 then
      DRC.message("[sigilharvest] No rooms for " .. active_sigil ..
        " in " .. city .. " during " .. season)
      pause(5)
    else
      if args.debug then
        DRC.message(string.format(
          "Harvesting %s sigils from %d known rooms in the vicinity of %s.",
          active_sigil, #roomlist, city))
      end

      for _, room in ipairs(roomlist) do
        -- Skip danger rooms
        local is_danger = false
        for _, dr in ipairs(danger_rooms) do
          if dr == room then is_danger = true; break end
        end
        if not is_danger then
          if time_expired() then return end
          DRCA.do_buffs(settings, "outdoors")
          DRCT.walk_to(room)
          rooms_visited = rooms_visited + 1
          harvest_sigil(active_sigil)
        end
      end
    end

    if time_expired() then return end
  end
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

-- Register Flags before any game output starts
Flags.add("sigilharvest-found",     unpack(FOUND_PATTERNS))
Flags.add("sigilharvest-type",
  "abolition sigil", "congruence sigil", "induction sigil", "permutation sigil",
  "rarefaction sigil", "antipode sigil", "ascension sigil", "clarification sigil",
  "decay sigil", "evolution sigil", "integration sigil", "metamorphosis sigil",
  "nurture sigil", "paradox sigil", "unity sigil")
Flags.add("sigilharvest-noactions",
  "You are unable to perceive any opportunities for improving the sigil")

before_dying(function()
  Flags.delete("sigilharvest-found")
  Flags.delete("sigilharvest-type")
  Flags.delete("sigilharvest-noactions")
end)

local season     = get_season()
local techniques = get_techniques()
log_startup_banner(season, techniques)

local tool_errors = validate_tools()
if #tool_errors > 0 then
  for _, e in ipairs(tool_errors) do DRC.message("  ERROR: " .. e) end
  log_exit_summary()
  return
end
DRC.message("  Burin resolved:   '" .. burin .. "' (" ..
  (burin_belt and "belt" or "pack") .. ")")

DRCA.do_buffs(settings, "outdoors")

local startroom = Room.id
get_scrolls()

-- Normalize city capitalization for data lookup (e.g. "crossing" → "Crossing")
local lookup_city = args.city:sub(1,1):upper() .. args.city:sub(2):lower()
find_sigils(lookup_city, args.sigil)

if startroom then DRCT.walk_to(startroom) end

if #enemy_rooms > 0 then
  local rids = {}
  for _, r in ipairs(enemy_rooms) do rids[#rids+1] = tostring(r) end
  DRC.message("Enemies were encountered in the following rooms: " ..
    table.concat(rids, ", "))
  DRC.message("Consider adding them to danger_rooms under sigil_harvest_settings in your YAML.")
end

log_exit_summary()
