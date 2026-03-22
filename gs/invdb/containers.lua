-- containers.lua — client_command, object interaction, sorted_view, traverse_container
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local util = require("gs/invdb/util")

-- ---------------------------------------------------------------------------
-- client_command — send a command, optionally suppress output, collect lines.
-- quiet: if true, lines matching start→end are hidden from the client window.
-- Returns table of collected lines.
-- ---------------------------------------------------------------------------
local _hook_counter = 0

function M.client_command(command, start_pattern, end_pattern, quiet, timeout, silent)
  end_pattern = end_pattern or "^<prompt"
  timeout     = timeout or 5

  local hook_name = nil
  if quiet then
    _hook_counter = _hook_counter + 1
    hook_name = "invdb_quiet_" .. _hook_counter
    local filtering = false
    DownstreamHook.add(hook_name, function(line)
      if filtering then
        if smart_find(line, end_pattern) then
          DownstreamHook.remove(hook_name)
          filtering = false
          return nil -- suppress the end line too
        end
        return nil -- suppress content lines
      elseif smart_find(line, start_pattern) then
        filtering = true
        return nil
      end
      return line
    end)
  end

  local results = quiet_command(command, start_pattern, end_pattern, timeout)

  if hook_name then
    -- Ensure hook is cleaned up even if command timed out
    DownstreamHook.remove(hook_name)
  end

  return results
end

-- ---------------------------------------------------------------------------
-- Sorted-view state (module-level, reset on refresh start)
-- ---------------------------------------------------------------------------
M.sorted_view_saved  = nil
M.sorted_view_status = nil
M.objects_looked     = 0
M.too_many_windows   = nil

function M.reset_state()
  M.sorted_view_saved  = nil
  M.sorted_view_status = nil
  M.objects_looked     = 0
  M.too_many_windows   = nil
end

function M.sorted_view_status_update(status)
  M.sorted_view_status = status
  if M.sorted_view_saved == nil then
    M.sorted_view_saved = status
    before_dying(function()
      if M.sorted_view_status ~= M.sorted_view_saved then
        M.client_command("flag sorted " .. M.sorted_view_saved, "You will")
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- View patterns (compiled once)
-- ---------------------------------------------------------------------------
local VP = {
  start              = "^<exposeContainer id='[^']+'|<container",
  adjective_noun     = 'noun="([^"]+)">([^<]-)</a>:$',
  closed             = "^That is closed%.",
  empty_sorted       = 'There is nothing.-<a exist="(-?%d+)"',
  empty_not_sorted   = "^There is nothing [^%d]+%.",
  category           = "^<pushBold/>(.-)%s%[(%d+)%]:<popBold/>",
  category_item      = '([^<]+)? ?<a exist="(-?%d+)" noun="([^"]-)">(.-)</a>([^%(]-)? ?%((%d+)%)?',
  total              = "^Total items: (%d+)",
  end_pat            = "^<prompt>",
  link_pattern       = '<a exist="(-?%d+)" noun="([^"]+)">([^<]+)</a>',
  split_inv          = "</inv>",
  preposition_inv    = "<inv id='.-'>(%a+) .-<a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>:</inv>(.*)",
  preposition_unsorted = "^(%a+) .- <a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a> you see (.*)",
  preposition_sorted = "(%a+) [^<>]- <a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>:$",
  inv_item           = "<inv id='.-'>([^<]-)? ?<a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>([^%(]-)?"
}

-- ---------------------------------------------------------------------------
-- object_open — open a container by GameObj-style id string or noun
-- ---------------------------------------------------------------------------
function M.object_open(o, path, settings)
  -- Check containers_noopen list
  if settings then
    local noopen = settings.container_noopen or {}
    local obj_name = type(o) == "table" and o.name or ""
    for _, pattern in ipairs(noopen) do
      if obj_name:lower():find(pattern:lower(), 1, true) then
        return {}
      end
    end
  end

  local ref    = type(o) == "string" and o or ("#" .. tostring(o.id))
  local cmd    = "open " .. ref .. (path and (" " .. path) or "")
  local start  = ref == "string" and "" or (tostring(o.id) .. "|")
  local sp     = start .. "^<(?:container|clearContainer|exposeContainer)|That is already open|You open|What were you|Try holding"
  local ep     = "(<popBold/>)?<prompt"
  return M.client_command(cmd, sp, ep, false, 2)
end

-- ---------------------------------------------------------------------------
-- object_close
-- ---------------------------------------------------------------------------
function M.object_close(o, path)
  local ref   = type(o) == "string" and o or ("#" .. tostring(o.id))
  local cmd   = "close " .. ref .. (path and (" " .. path) or "")
  local start = "You close|That is already closed|What were you|seem to be any way|You tie"
  local ep    = "(<popBold/>)?<prompt"
  return M.client_command(cmd, start, ep, false, 2)
end

-- ---------------------------------------------------------------------------
-- object_look — look in/on/under/behind a container
-- ---------------------------------------------------------------------------
function M.object_look(o, preposition, path, quiet)
  preposition = preposition or "in"
  local ref   = type(o) == "string" and o or ("#" .. tostring(o.id))
  local idstr = type(o) == "string" and "" or (tostring(o.id) .. "|")
  local cmd   = "look " .. preposition .. " " .. ref .. (path and (" " .. path) or "")
  local start = idstr .. "^<(?:container|clearContainer|exposeContainer)|That is closed|There is nothing|I could not find|You see nothing unusual|Try holding|Too many container windows"
  local ep    = "(<popBold/>)?<prompt"
  return M.client_command(cmd, start, ep, quiet or false, 3)
end

-- ---------------------------------------------------------------------------
-- sorted_view_parse — extract id/adjective/noun/categories from sorted lines
-- ---------------------------------------------------------------------------
function M.sorted_view_parse(sorted_lines, preposition)
  local id           = nil
  local adjective    = nil
  local noun         = nil
  local item_categories = {}
  local contents     = {}

  for _, line in ipairs(sorted_lines) do
    -- preposition header e.g. "In a backpack:"
    local prep_str, ex_id, ex_noun, ex_name = line:match(
      "(%a+) [^<>]- <a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>:$"
    )
    if prep_str and ex_id then
      local parts = {}
      for w in ex_name:gmatch("%S+") do table.insert(parts, w) end
      if #parts > 1 then adjective = parts[1] end
      noun = ex_noun
      id   = ex_id
    else
      -- category line: "<pushBold/>Containers [3]:<popBold/> ..."
      local cat = line:match("^<pushBold/>(.-) %[%d+%]:<popBold/>")
      if cat then
        -- parse items within category line
        for before, exist, item_noun, item_name, after, qty in line:gmatch(
          '([^<]-)? ?<a exist="(-?%d+)" noun="([^"]-)">(.-)</a>([^%(]-)? ?%((%d*)%)?'
        ) do
          local full_name = (
            (before and before:gsub("^%s*a?n?%s*", "") or "")
            .. item_name
            .. (after and after:gsub(" containing.*$", "") or "")
          ):match("^%s*(.-)%s*$")
          item_categories[full_name] = cat
          if preposition ~= "in" and preposition ~= "on" then
            table.insert(contents, {
              id = exist, noun = item_noun, name = item_name,
              before_name = before or "", after_name = after or "",
              qty = tonumber(qty) or 1
            })
          end
        end
      end
    end
  end

  return id, adjective, noun, item_categories, contents, sorted_lines
end

-- ---------------------------------------------------------------------------
-- sorted_view — look at an object and parse the sorted view response
-- ---------------------------------------------------------------------------
function M.sorted_view(o, preposition, path, open_closed, settings)
  path         = path or ""
  open_closed  = open_closed ~= false  -- default true

  local id, adjective, noun, item_categories, contents = nil, nil, nil, {}, {}

  if type(o) == "table" and o.id then
    id   = tostring(o.id)
    noun = o.noun
  end

  preposition = preposition:lower()
  local sorted_lines = M.object_look(o, preposition, path ~= "" and path or nil)

  -- too many container windows
  if sorted_lines[1] and sorted_lines[1]:find("Too many container windows", 1, true) then
    if M.too_many_windows == tostring(o) or (settings and not settings.move_rooms) then
      respond("invdb: encountered 'Too many container windows'. Enable move_rooms to retry.")
      return id, adjective, noun, item_categories, contents, sorted_lines
    else
      -- Move rooms to clear windows
      M.move_rooms()
      M.too_many_windows = nil
      M.objects_looked   = 0
      return M.sorted_view(o, preposition, path, open_closed, settings)
    end
  end

  -- not found
  if sorted_lines[1] and sorted_lines[1]:find("I could not find", 1, true) then
    return id, adjective, noun, item_categories, contents, sorted_lines
  end

  -- closed container
  if sorted_lines[1] and sorted_lines[1]:match("^That is closed%.") then
    if open_closed then
      M.object_open(o, path ~= "" and path or nil, settings)
      sorted_lines = M.object_look(o, preposition, path ~= "" and path or nil)
    else
      return id, adjective, noun, item_categories, contents, sorted_lines
    end
  end

  -- empty container
  if sorted_lines[1] and sorted_lines[1]:find("There is nothing", 1, true) then
    local empty_id = sorted_lines[1]:match('<a exist="(-?%d+)"')
    if empty_id then
      M.sorted_view_status_update("on")
      id = empty_id
    else
      M.sorted_view_status_update("off")
    end
    return id, adjective, noun, item_categories, contents, sorted_lines
  end

  if sorted_lines[1] and sorted_lines[1]:find("You see nothing unusual", 1, true) then
    return id, adjective, noun, item_categories, contents, sorted_lines
  end

  if sorted_lines[1] and not sorted_lines[1]:find('<a exist=', 1, true) then
    return id, adjective, noun, item_categories, contents, sorted_lines
  end

  -- detect and set sorted view state
  local has_categories = false
  for _, line in ipairs(sorted_lines) do
    if line:match("^<pushBold/>") and line:match("%[%d+%]:<popBold/>") then
      has_categories = true; break
    end
  end
  if has_categories then
    M.sorted_view_status_update("on")
  else
    M.sorted_view_status_update("off")
  end

  -- enable sorted view if not on
  if M.sorted_view_status ~= "on" then
    M.client_command("flag sorted on", "You will")
    M.sorted_view_status_update("on")
    sorted_lines = M.object_look(o, preposition, path ~= "" and path or nil)
  end

  return M.sorted_view_parse(sorted_lines, preposition)
end

-- ---------------------------------------------------------------------------
-- move_rooms — move to an adjacent room and back to clear windows
-- ---------------------------------------------------------------------------
function M.move_rooms()
  respond("invdb: moving rooms to clear inventory windows")
  if Room and Room.current then
    local start_id = Room.current.id
    local wiggle_id = nil
    if Room.current.wayto then
      for dest_id, _ in pairs(Room.current.wayto) do
        local dest = Room[tonumber(dest_id)]
        if dest and dest.wayto and dest.wayto[tostring(start_id)] then
          wiggle_id = tonumber(dest_id)
          break
        end
      end
    end
    if wiggle_id then
      Script.run("go2", tostring(wiggle_id))
      Script.run("go2", tostring(start_id))
    end
  end
  M.objects_looked = 0
end

-- ---------------------------------------------------------------------------
-- object_contents — get items from an object for a given preposition
-- ---------------------------------------------------------------------------
function M.object_contents(o, preposition, id_path, open_containers, settings)
  preposition = preposition:lower()
  local contents = {}
  local has_in = false
  local has_on = false

  local id, adjective, noun, item_categories, sorted_contents, sorted_lines =
    M.sorted_view(o, preposition, id_path or "", open_containers, settings)

  -- Parse <inv>-tagged lines for "in" or "on" prepositions
  local joined = table.concat(sorted_lines, "\n")

  -- Split on </inv><inv> boundaries
  local segments = {}
  for seg in (joined .. "</inv>"):gmatch("(.-)</inv>") do
    table.insert(segments, seg)
  end

  for _, seg in ipairs(segments) do
    -- Match preposition header
    local inv_prep, inv_id, inv_noun, inv_name, inv_contents =
      seg:match("<inv id='.-'>(%a+) .- <a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>:</inv>(.*)")
    if inv_prep then
      inv_prep = inv_prep:lower()
      if inv_prep == "in" then has_in = true end
      if inv_prep == "on" then has_on = true end
      if inv_prep == preposition then
        -- Extract items from this inv section
        for item_str in (inv_contents or ""):gmatch("<inv id='.-'>(.-)</inv>") do
          local b4, ex_id, ex_noun, ex_name, after =
            item_str:match("([^<]-)? ?<a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>([^%(]*)?")
          if ex_id then
            table.insert(contents, {
              before_name = b4 or "", id = ex_id, noun = ex_noun,
              name = ex_name, after_name = after or "", qty = 1
            })
          end
        end
        break
      end
    end
  end

  -- For "behind" and "under" we need unsorted look too
  if preposition == "behind" or preposition == "under" then
    if M.sorted_view_status ~= "off" then
      M.client_command("flag sorted off", "You will")
      M.sorted_view_status_update("off")
    end
    local unsorted = M.object_look(o, preposition, id_path ~= "" and id_path or nil)
    for _, line in ipairs(unsorted) do
      local prep2, _, _, _, line_contents =
        line:match("^(%a+) .- <a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a> you see (.*)")
      if prep2 and prep2:lower() == preposition then
        for ex_id, ex_noun, ex_name in line_contents:gmatch('<a exist="(-?%d+)" noun="([^"]+)">([^<]+)</a>') do
          -- Find before/after_name from sorted_contents
          local b4, after = "", ""
          for _, sc in ipairs(sorted_contents or {}) do
            if sc.id == ex_id then b4 = sc.before_name or ""; after = sc.after_name or ""; break end
          end
          table.insert(contents, {
            before_name = b4, id = ex_id, noun = ex_noun,
            name = ex_name, after_name = after, qty = 1
          })
        end
        break
      end
    end
  end

  M.objects_looked = M.objects_looked + 1
  return id, adjective, noun, item_categories, contents, has_in, has_on
end

-- ---------------------------------------------------------------------------
-- peek_stack — look in a jar/read a note stack/measure a bundle
-- Returns amount, stack_status
-- ---------------------------------------------------------------------------
local STACK_TYPES = {
  jar    = { command = "look in",  pattern = 'Inside the <a exist="(%d+)"[^>]*>.-</a> you see (%d+) portions? of .-%.  It is (.-) ?%.' },
  bundle = { command = "measure",  pattern = 'You glance through your bundle and count a total of (%d+) <a exist="(%d+)' },
  stack  = { command = "read",     pattern = 'This <a exist="(%d+)"[^>]*>.-</a> has (%d[%d,]*) uses?%.' },
  pack   = { command = "read",     pattern = 'This <a exist="(%d+)"[^>]*>.-pack</a> entitles the presenter to (%d+)' },
}

function M.peek_stack(id, id_path, stack_type, settings)
  local s = STACK_TYPES[stack_type]
  if not s then return 0, "" end

  local cmd     = s.command .. " #" .. id .. (id_path ~= "" and (" " .. id_path) or "")
  local start_p = "In the Common language|^(?:The|This|Inside the|Your|There is.-) <a exist=\"" .. id
                  .. "\"|A quick peek|Constructed of.-" .. id
                  .. "|You see nothing unusual|There is nothing|Try holding it first"
  local quiet = settings and settings.silence_stack or false
  local peek = M.client_command(cmd, start_p, "^<output class=\"\"/>|(<popBold/>)?<prompt", quiet, 5)
  local joined = table.concat(peek, "\n")

  if joined:find("You see nothing unusual", 1, true) then return nil, nil end

  local stack_amount = 0
  local stack_status = (stack_type == "jar") and "empty" or ""

  if stack_type == "jar" then
    local ex_id, amount, status = joined:match(s.pattern)
    if amount then
      stack_amount = tonumber(amount) or 0
      stack_status = status or "partial"
    end
  elseif stack_type == "bundle" then
    local amount = joined:match(s.pattern)
    if amount then stack_amount = tonumber(amount) or 0 end
  elseif stack_type == "stack" then
    local _, amount = joined:match(s.pattern)
    if amount then stack_amount = tonumber(amount:gsub(",", "")) or 0 end
  elseif stack_type == "pack" then
    local _, amount = joined:match(s.pattern)
    if amount then stack_amount = tonumber(amount) or 0 end
  end

  return stack_amount, stack_status
end

-- ---------------------------------------------------------------------------
-- peek_boh — look inside a bag of holding, return item list
-- ---------------------------------------------------------------------------
function M.peek_boh(id, location_id, level, path, id_path, boh_noun, verb, conn)
  verb = verb or "look in"
  local cmd   = verb .. " #" .. id .. (id_path and id_path ~= "" and (" " .. id_path) or "")
  local start = "^This <a exist=\"" .. id .. "\" noun.->.- has multiple pockets"
             .. "|^Fashioned (?:from|of)"
             .. "|^Crafted from"
             .. "|^(?:<popBold/>)?%d+%. +(?:an? )?"
             .. "|^There is nothing in there%."
             .. "|^You realize"
             .. "|^Sifting through"
             .. "|^Glancing over your"
  local ep    = "^(?:<popBold/>)?<prompt"
  local peek  = M.client_command(cmd, start, ep, false, 5)

  if peek[#peek] and peek[#peek]:find("popBold", 1, true) then
    _respond("<popBold/>")
    table.remove(peek)
  end

  local boh_items = {}
  local boh_path = (not path or path == "") and boh_noun or (path .. " > " .. boh_noun)
  local intro = peek[1] or ""
  local is_oremonger = intro:find("ores you have stored", 1, true)

  for _, r in ipairs(peek) do
    local name, amount = nil, nil
    if is_oremonger then
      -- format: "1.  <N> pieces of <name>"
      local n, nm = r:match("^%d+%. +(%d+) pieces? of (.*)")
      if n then amount = tonumber(n); name = nm and nm:match("^%s*(.-)%s*$") end
    else
      -- general format: "N. [a ](name) (amount[extra])"
      local nm, amt = r:match("^<?%-?p?o?p?B?o?l?d?/?>>?%d+%. +(?:an? )?(.-) %((%d+)[%)%s]")
      if not nm then
        nm, amt = r:match("^%d+%. +(?:an? )?(.-) %((%d+)[%)%s]")
      end
      if nm then name = nm:match("^%s*(.-)%s*$"); amount = tonumber(amt) end
    end

    if name and amount then
      local item_noun = util.noun_from_name(name)
      local item_type = util.get_item_type(name, item_noun)

      -- classify special content types from context
      if intro:find("gemstones", 1, true) then item_type = "gemstone"
      elseif is_oremonger then item_type = "ore"
      end

      table.insert(boh_items, {
        id           = nil,
        location_id  = location_id,
        level        = level + 1,
        path         = boh_path,
        type         = item_type,
        name         = name,
        noun         = item_noun,
        amount       = amount,
        stack        = "boh",
        stack_status = "",
        marked       = "",
        registered   = "",
        hidden       = "",
        link_name    = "",
        containing   = "",
        update_noun  = 0,
      })
    end
  end

  return boh_items
end

-- ---------------------------------------------------------------------------
-- traverse_container — recursively enumerate items in a container
-- Returns: items_list, item_categories, has_in, has_on
-- ---------------------------------------------------------------------------
function M.traverse_container(child, preposition, path, id_path, level, open_containers, max_depth, swclose, settings, conn)
  preposition    = (preposition or "in"):lower()
  path           = path or ""
  id_path        = id_path or ""
  level          = level or -1
  max_depth      = max_depth or 9
  open_containers = open_containers ~= false
  swclose        = swclose or false

  level = level + 1

  local obj_id, obj_adjective, obj_noun, item_categories, contents, has_in, has_on =
    M.object_contents(child, preposition, id_path, open_containers, settings)

  if level == 0 then
    if type(child) == "string" then
      path = preposition .. " " .. child
    else
      path = preposition .. " " .. (obj_noun or "")
    end
    if obj_id then
      id_path = (preposition .. " #" .. obj_id .. " " .. id_path):match("^%s*(.-)%s*$")
    end
  else
    local adj_part = obj_adjective and (obj_adjective .. " ") or ""
    path = (preposition .. " " .. adj_part .. (obj_noun or "") .. " " .. path):match("^%s*(.-)%s*$")
    if obj_id then
      id_path = (preposition .. " #" .. obj_id .. " " .. id_path):match("^%s*(.-)%s*$")
    end
  end

  local traverse_items = {}
  local boh_setting = settings and settings.boh or {}

  for _, i in ipairs(contents) do
    local prename = i.before_name and i.before_name:gsub("^%s*a?n?%s*", "") or ""
    prename = prename:match("^%s*(.-)%s*$")
    if prename:match("^a?n?%s*$") then prename = "" end

    local id       = i.id
    local name_raw = i.name
    local noun     = (i.noun or ""):match("^%s*(.-)%s*$")
    local item_type = util.get_item_type(name_raw, noun)
    local link_name = name_raw
    local after_name = i.after_name or ""
    local amount     = i.qty or 1

    -- strip "containing ..." from after_name
    local containing = (after_name:match("containing (.-)[%(%)%s]*$") or ""):match("^%s*(.-)%s*$")
    local postname   = after_name:gsub(" *containing.*$", "")

    -- build full name
    local some_stripped = name_raw:gsub("^some ", "")
    local full_name = (prename ~= "" and (prename .. " ") or "")
                   .. some_stripped
                   .. (postname ~= "" and (" " .. postname:match("^%s*(.-)%s*$")) or "")
    full_name = full_name:match("^%s*(.-)%s*$")

    -- stack detection
    local stack       = ""
    local stack_name  = ""
    local stack_noun  = ""
    local stack_type  = ""
    local stack_amount = 0
    local stack_status = ""

    local stk_match = item_type:match("^jar") and "jar"
                   or (full_name:match("^stack of .* notes$") and "stack")

    if stk_match and settings and settings[stk_match] then
      if stk_match == "jar" then
        stack_name   = util.deplural(postname):match("^%s*(.-)%s*$")
        local sn_parts = {}
        for w in stack_name:gmatch("%S+") do table.insert(sn_parts, w) end
        stack_noun  = (sn_parts[#sn_parts] or ""):gsub("lazuli", "lapis")
        if stack_noun:find("lazuli") then stack_noun = "lapis" end
        stack_type  = postname ~= "" and util.get_item_type(stack_name, stack_noun) or ""
        stack_status = "empty"
        if id then
          stack_amount, stack_status = M.peek_stack(id, id_path, "jar", settings)
          stack_status = (stack_status and stack_status:match("^(full|empty)") and stack_status) or "partial"
          if stack_amount and stack_amount > 0 then stack = "jar" end
        end
      else
        stack_name   = util.deplural(full_name:gsub("^bundle of ", ""):gsub("^stack of ", ""))
        stack_noun   = util.deplural(noun)
        stack_type   = util.get_item_type(stack_name, stack_noun)
        stack_amount, stack_status = M.peek_stack(id, id_path, stk_match, settings)
        if stack_amount and stack_amount > 0 then stack = stk_match end
      end
    end

    -- main item record
    local clean_path = path:gsub(" *in locker *$", ""):match("^%s*(.-)%s*$")
    table.insert(traverse_items, {
      id           = id,
      level        = level,
      path         = clean_path,
      type         = item_type,
      name         = full_name,
      link_name    = link_name,
      containing   = containing,
      noun         = noun,
      amount       = amount,
      stack        = "",
      stack_status = stack_status,
      update_noun  = 1,
    })

    -- stack content record
    if stack ~= "" and stack_amount and stack_amount > 0 then
      table.insert(traverse_items, {
        id           = id,
        level        = level + 1,
        path         = clean_path .. " > " .. noun,
        type         = stack_type,
        name         = stack_name,
        link_name    = "",
        containing   = "",
        noun         = stack_noun,
        amount       = stack_amount,
        stack        = stack,
        stack_status = "",
        update_noun  = 0,
      })
    end

    -- bags of holding
    local is_boh = false
    for _, boh_name in ipairs(boh_setting) do
      if full_name == boh_name then is_boh = true; break end
    end
    if is_boh and id then
      local boh_verb = full_name:find("tackle") and "gaze" or "look in"
      local boh_items = M.peek_boh(id, nil, level, clean_path, id_path, noun, boh_verb, conn)
      if #boh_items > 0 then
        for _, b in ipairs(boh_items) do
          b.location_id = nil -- will be set by caller
          table.insert(traverse_items, b)
        end
      end
    elseif item_categories[full_name] == "Containers" then
      -- recurse into containers
      local child_items, child_cats, child_has_in, child_has_on =
        M.traverse_container(i, "in", path, id_path, level, open_containers, max_depth, swclose, settings, conn)
      for k, v in pairs(child_cats) do item_categories[k] = v end
      for _, ci in ipairs(child_items) do table.insert(traverse_items, ci) end

      if child_has_on then
        local on_items, on_cats, _, _ =
          M.traverse_container(i, "on", path, id_path, level, open_containers, max_depth, swclose, settings, conn)
        for k, v in pairs(on_cats) do item_categories[k] = v end
        for _, ci in ipairs(on_items) do table.insert(traverse_items, ci) end
      end
    end
  end

  -- swclose the container window
  if swclose then
    if obj_id then
      put("_swclose c" .. obj_id)
    elseif type(child) == "table" and child.id then
      put("_swclose c" .. child.id)
    end
  end

  return traverse_items, item_categories, has_in, has_on
end

return M
