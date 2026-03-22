-- inventory.lua — inventory scanning (hands, alongside, body), locker manifest
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local util       = require("gs/invdb/util")
local containers = require("gs/invdb/containers")
local db_mod     = require("gs/invdb/db")

-- ---------------------------------------------------------------------------
-- Pattern for inventory full lines (same as Ruby @patterns[:inv_full])
-- ---------------------------------------------------------------------------
-- Format: "   [<pushBold/>][prename ]<a exist="ID" noun="NOUN">NAME</a>[<popBold/>][postname][(attrs)]"
local INV_FULL_PATTERN =
  "^( +)<?p?u?s?h?B?o?l?d?/?>>?([^<]+)? ?<a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a><?p?o?p?B?o?l?d?/?>>?([^%(]-)? ?(%(.*)?)"

-- ---------------------------------------------------------------------------
-- containers_with_contents_get — get map of container_id→id_path
-- by reading `inventory full` output.
-- ---------------------------------------------------------------------------
function M.containers_with_contents_get()
  local pat_inv = "^(?:<popBold/>)?(?:You are currently (?:wearing and )?(?:carrying)?|^You are carrying nothing|^You are holding)|^You currently have placed alongside you|^You have nothing placed alongside you"

  local lines = quiet_command("inventory full", pat_inv, nil, 10)
  -- also check hands
  if GameObj.right_hand() or GameObj.left_hand() then
    local hand_lines = quiet_command("inventory hands full", pat_inv, nil, 10)
    for _, l in ipairs(hand_lines) do table.insert(lines, l) end
  end

  local containers_with_contents = {}
  local worn_inventory = {}
  local prev_id    = nil
  local prev_level = 0
  local id_stack   = {}

  for _, line in ipairs(lines) do
    local depth, _, exist, noun, name = line:match(INV_FULL_PATTERN)
    if depth and exist then
      local level = math.floor((#depth - 2) / 4)
      if level == 0 and not worn_inventory[exist] then
        worn_inventory[exist] = { name = name, noun = noun }
      end
      if level > prev_level then
        if not containers_with_contents[prev_id] then
          local id_path = #id_stack > 0
            and ("in #" .. table.concat(id_stack, " in #"))
            or ""
          containers_with_contents[prev_id] = id_path
        end
        table.insert(id_stack, prev_id)
      elseif level < prev_level then
        local n_pop = prev_level - level
        for _ = 1, n_pop do table.remove(id_stack) end
      end
      prev_id    = exist
      prev_level = level
    end
  end

  return containers_with_contents, worn_inventory
end

-- ---------------------------------------------------------------------------
-- open_containers — open all inv containers that aren't in the noopen list
-- Returns a list of container IDs that were opened (to close later).
-- ---------------------------------------------------------------------------
function M.open_all_containers(settings, containers_with_contents)
  local containers_to_open  = {}
  local containers_to_close = {}

  -- Get list of worn containers from `inventory container`
  local pat = "^(?:<popBold/>)?You are wearing|^(?:<popBold/>)?You are holding"
  local data = quiet_command("inventory container", pat, "^(<popBold/>)?<prompt", 5)

  local noopen = settings.container_noopen or {}
  local function is_noopen(name)
    for _, pattern in ipairs(noopen) do
      if name:lower():find(pattern:lower(), 1, true) then return true end
    end
    return false
  end

  for _, line in ipairs(data) do
    for exist, noun, name in line:gmatch('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>') do
      if not is_noopen(name) and not containers_with_contents[exist] then
        table.insert(containers_to_open, exist)
      end
    end
  end

  -- Register close-on-death handler
  before_dying(function()
    for i = #containers_to_close, 1, -1 do
      put("close #" .. containers_to_close[i])
    end
  end)

  -- Open each container
  for _, id in ipairs(containers_to_open) do
    local result = quiet_command("open #" .. id,
      id .. "|^<(?:container|clearContainer|exposeContainer)|That is already open|You open",
      "(<popBold/>)?<prompt", 2)
    local opened = false
    for _, l in ipairs(result) do
      if l:find("You open", 1, true) or l:find("exposeContainer", 1, true) then
        opened = true; break
      end
    end
    if opened then table.insert(containers_to_close, id) end
  end

  return containers_to_close
end

-- ---------------------------------------------------------------------------
-- close_containers — close containers that were opened
-- ---------------------------------------------------------------------------
function M.close_containers(containers_to_close)
  for i = #containers_to_close, 1, -1 do
    put("close #" .. containers_to_close[i])
    pause(0.1)
  end
end

-- ---------------------------------------------------------------------------
-- scan_parse_item_lines — parse one inventory scan (hands/alongside/full)
-- Returns: list of item hashes, inventory_count
-- ---------------------------------------------------------------------------
function M.scan_parse_item_lines(scan_command, location_id, settings, js2)
  js2 = js2 or {}
  local pat_start = "^(?:<popBold/>)?(?:You are currently (?:wearing and )?(?:carrying)?(?:(?!, which conceals).)+$|^(?:<popBold/>)?You are carrying nothing|^(?:<popBold/>)?You are holding)|^You currently have placed alongside you|^You have nothing placed alongside you|That's not a valid option|^You are currently mounted on"
  local pat_end   = "^(?:<popBold/>)?<prompt"

  local sp_lines = quiet_command(scan_command, pat_start, pat_end, 8)
  if sp_lines[1] and sp_lines[1]:match("^<popBold/>") then
    _respond("<popBold/>")
  end

  -- Count expected items
  local displayed_count = 0
  for _, line in ipairs(sp_lines) do
    local m = line:match("%(Items: (%d+)%)") or line:match("%((%d+) items? displayed%)")
    if m then displayed_count = tonumber(m) or 0; break end
    if line:find("You have nothing", 1, true) or line:find("You are carrying nothing", 1, true) then
      break
    end
  end

  local temp_items    = {}
  local matched_count = 0
  local prev_noun     = ""
  local prev_id       = ""
  local prev_level    = 0
  local item_path     = {}
  local item_path_ids = {}

  for _, line in ipairs(sp_lines) do
    local depth, prename, exist, noun, name, postname, attrs = line:match(INV_FULL_PATTERN)
    if depth and exist then
      matched_count = matched_count + 1
      noun     = noun:match("^%s*(.-)%s*$")
      prename  = prename and prename:match("^%s*(.-)%s*$") or ""
      postname = postname and postname:match("^%s*(.-)%s*$") or ""
      attrs    = attrs and attrs:match("^%s*(.-)%s*$") or ""

      local registered = attrs:find("registered") and "Y" or ""
      local marked     = attrs:find("marked")     and "Y" or ""
      local hidden     = attrs:find("hidden")     and "Y" or ""
      local amount     = 1

      local level = math.floor((#depth - 2) / 4)
      if level > prev_level then
        table.insert(item_path, prev_noun)
        table.insert(item_path_ids, "#" .. prev_id)
      elseif level < prev_level then
        local n_pop = prev_level - level
        for _ = 1, n_pop do
          table.remove(item_path)
          table.remove(item_path_ids)
        end
      end

      local path  = table.concat(item_path, " > ")
      local item_type = (name == "some blue lapis lazuli") and "gem"
                     or util.get_item_type(name, noun)

      -- Stack detection
      local stack       = ""
      local stack_name  = ""
      local stack_noun  = ""
      local stack_type  = ""
      local stack_amount = 0
      local stack_status = ""

      local stk_kind = item_type:match("^jar") and "jar"
                    or name:match("^stack of .* notes$") and "stack"

      if stk_kind then
        if stk_kind == "jar" then
          -- Check jarserve2 cache first
          local js2_entry = js2[exist]
          if js2_entry and js2_entry.amount > 0 then
            stack_name   = util.deplural(postname)
            stack_noun   = js2_entry.noun:find("lazuli") and "lapis" or js2_entry.noun
            stack_type   = util.get_item_type(stack_name, stack_noun)
            stack_status = js2_entry.stack_status
            stack_amount = js2_entry.amount
            stack        = "jar"
          elseif settings and settings.jar then
            stack_name = util.deplural(postname)
            local sn_parts = {}
            for w in stack_name:gmatch("%S+") do table.insert(sn_parts, w) end
            stack_noun = (sn_parts[#sn_parts] or ""):find("lazuli") and "lapis" or (sn_parts[#sn_parts] or "")
            stack_type = postname ~= "" and util.get_item_type(stack_name, stack_noun) or ""
            stack_status = "empty"
            local stack_path = #item_path_ids > 0 and ("in " .. table.concat(item_path_ids, " in ")) or ""
            stack_amount, stack_status = containers.peek_stack(exist, stack_path, "jar", settings)
            stack_status = (stack_status and stack_status:match("^(full|empty)") and stack_status) or "partial"
            if stack_amount and stack_amount > 0 then stack = "jar" end
          end
        elseif settings and settings[stk_kind] then
          stack_name = util.deplural(name:gsub("^bundle of ", ""):gsub("^stack of ", ""))
          stack_noun = util.deplural(noun)
          stack_type = util.get_item_type(stack_name, stack_noun)
          local stack_path = #item_path_ids > 0 and ("in " .. table.concat(item_path_ids, " in ")) or ""
          stack_amount, stack_status = containers.peek_stack(exist, stack_path, stk_kind, settings)
          if stack_amount and stack_amount > 0 then stack = stk_kind end
        end
      end

      -- Clean up prename
      prename = prename:gsub("^a?n?%s*", ""):match("^%s*(.-)%s*$")
      local some_stripped = name:gsub("^some ", "")
      local clean_postname = postname:gsub(" *containing.*$", "")
      local full_name = (
        (prename ~= "" and (prename .. " ") or "")
        .. some_stripped
        .. (clean_postname ~= "" and (" " .. clean_postname) or "")
      ):match("^%s*(.-)%s*$")

      local containing = stack == "" and "" or ("(" .. stack_name .. ") (" .. stack_amount .. ")")

      -- mark boh items
      if settings and settings.boh then
        for _, boh_name in ipairs(settings.boh) do
          if full_name == boh_name then item_type = "boh"; break end
        end
      end

      prev_id    = exist
      prev_level = level
      prev_noun  = noun

      table.insert(temp_items, {
        id           = exist,
        location_id  = location_id,
        level        = level,
        path         = path,
        type         = item_type,
        name         = full_name,
        link_name    = name,
        containing   = containing,
        noun         = noun,
        amount       = amount,
        stack        = "",
        stack_status = stack_status,
        marked       = marked,
        registered   = registered,
        hidden       = hidden,
        update_noun  = 1,
      })

      if stack ~= "" and stack_amount and stack_amount > 0 then
        table.insert(temp_items, {
          id           = exist,
          location_id  = location_id,
          level        = level + 1,
          path         = path ~= "" and (path .. " > " .. stack) or stack,
          type         = stack_type,
          name         = stack_name,
          link_name    = "",
          containing   = "",
          noun         = stack_noun,
          amount       = stack_amount,
          stack        = stack,
          stack_status = "",
          marked       = "",
          registered   = "",
          hidden       = "",
          update_noun  = 1,
        })
      end

      -- boh items
      if settings and settings.boh then
        local is_boh = false
        for _, bn in ipairs(settings.boh) do
          if full_name == bn then is_boh = true; break end
        end
        if is_boh then
          local boh_verb = full_name:find("tackle") and "gaze" or "look in"
          local id_path_str = #item_path_ids > 0 and table.concat(item_path_ids, " in ") or ""
          local boh_items = containers.peek_boh(exist, location_id, level, path, id_path_str, noun, boh_verb)
          for _, b in ipairs(boh_items) do table.insert(temp_items, b) end
        end
      end
    end
  end

  return temp_items, matched_count, displayed_count
end

-- ---------------------------------------------------------------------------
-- normalize_path_segments — reverse path segments like the original
-- ---------------------------------------------------------------------------
local function normalize_path(path_str)
  if not path_str or path_str == "" then return "" end
  local prepositions = {"in ", "on ", "under ", "behind "}
  local segments = {}
  local function split_path(s)
    for _, prep in ipairs(prepositions) do
      local idx = s:find(prep, 2, true)
      if idx then
        table.insert(segments, s:sub(1, idx-1):match("^%s*(.-)%s*$"))
        split_path(s:sub(idx))
        return
      end
    end
    table.insert(segments, s:match("^%s*(.-)%s*$"))
  end
  split_path(path_str)
  -- reverse and join with " > "
  local reversed = {}
  for i = #segments, 1, -1 do
    local seg = segments[i]
    -- strip leading preposition
    for _, prep in ipairs(prepositions) do
      if seg:sub(1, #prep) == prep then seg = seg:sub(#prep+1); break end
    end
    if seg ~= "" then table.insert(reversed, seg) end
  end
  return table.concat(reversed, " > ")
end

-- ---------------------------------------------------------------------------
-- insert_temp_items — insert items into temp_item table
-- ---------------------------------------------------------------------------
function M.insert_temp_items(conn, character_id, items)
  local ts = db_mod.now()
  local sql = [[
    INSERT INTO temp_item (
        character_id, location_id, level, path
      , name, type, link_name, containing
      , noun, amount, stack, stack_status
      , marked, registered, hidden
      , timestamp, update_noun, gs_id
    ) VALUES (
        :character_id, :location_id, :level, :path
      , :name, :type, :link_name, :containing
      , :noun, :amount, :stack, :stack_status
      , :marked, :registered, :hidden
      , :timestamp, :update_noun, :gs_id
    )]]
  for _, item in ipairs(items) do
    db_mod.exec(conn, sql, {
      character_id = character_id,
      location_id  = item.location_id,
      level        = item.level or 0,
      path         = item.path or "",
      name         = item.name or "",
      type         = item.type or "",
      link_name    = item.link_name or "",
      containing   = item.containing or "",
      noun         = item.noun or "",
      amount       = item.amount or 1,
      stack        = item.stack or "",
      stack_status = item.stack_status or "",
      marked       = item.marked or "",
      registered   = item.registered or "",
      hidden       = item.hidden or "",
      timestamp    = ts,
      update_noun  = item.update_noun or 1,
      gs_id        = item.id,
    })
  end
end

-- ---------------------------------------------------------------------------
-- refresh_inventory — full inventory scan and DB merge
-- location IDs:  1=hands, 2=worn/body, 6=alongside
-- ---------------------------------------------------------------------------
function M.refresh_inventory(conn, character_id, settings, location_type_filter)
  location_type_filter = location_type_filter or "all"

  if not location_type_filter:match("inv|item|all") then return end

  -- optionally open containers first
  local containers_to_close = {}
  if settings.open_containers then
    local cwc, _ = M.containers_with_contents_get()
    containers_to_close = M.open_all_containers(settings, cwc)
  end

  local scans = {
    { command = "inventory hands full",        id = 1, name = "hands"     },
    { command = "inventory full alongside",    id = 6, name = "alongside"  },
    { command = "inventory full",              id = 2, name = "inventory"  },
  }

  local total_count = 0

  for _, scan in ipairs(scans) do
    respond("invdb: scanning " .. scan.name .. "...")
    local items, matched, displayed = M.scan_parse_item_lines(scan.command, scan.id, settings)

    if matched == displayed then
      M.insert_temp_items(conn, character_id, items)
      db_mod.merge_item_by_location(conn, character_id, scan.id, GameState.game)
      total_count = total_count + (displayed > 0 and displayed or 0)
    else
      respond(string.format("invdb: parse mismatch for %s: got %d, expected %d — retrying",
        scan.name, matched, displayed))
      -- retry once
      items, matched, displayed = M.scan_parse_item_lines(scan.command, scan.id, settings)
      if matched == displayed then
        M.insert_temp_items(conn, character_id, items)
        db_mod.merge_item_by_location(conn, character_id, scan.id, GameState.game)
        total_count = total_count + (displayed > 0 and displayed or 0)
      else
        respond("invdb: inventory scan failed after retry — skipping " .. scan.name)
      end
    end
  end

  if settings.open_containers then
    M.close_containers(containers_to_close)
  end

  return total_count
end

return M
