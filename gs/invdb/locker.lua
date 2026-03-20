-- locker.lua — locker info, manifest parsing, standard/premium locker refresh
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local util       = require("gs/invdb/util")
local containers = require("gs/invdb/containers")
local db_mod     = require("gs/invdb/db")
local inv        = require("gs/invdb/inventory")

-- ---------------------------------------------------------------------------
-- locker_info — detect locker location and whether multi-locker (premium)
-- Returns: locker_location string ("multi" | town_name | "transit")
-- ---------------------------------------------------------------------------
function M.locker_info()
  local cmd   = "locker info"
  local start = GameState.name
    .. ", your locker information is as follows|You possess lockers?|Your locker"

  local result = quiet_command(cmd, start, "^(?:<popBold/>)?<prompt", 5)
  local joined = table.concat(result, "\n")

  local locker_location = nil

  if joined:match("You possess lockers") or joined:match("Your lockers?") then
    -- Check for multi
    if joined:match("lockers?[^%a]") and joined:lower():find("multiple") then
      locker_location = "multi"
    end
    -- Extract town name
    local town = joined:match("currently located in the town of ([^%.\n]+)")
    if town then
      -- special case
      if town:find("Kharag") then town = "Zul Logoth" end
      locker_location = locker_location or town:match("^%s*(.-)%s*$")
    end
  end

  return locker_location or "transit"
end

-- ---------------------------------------------------------------------------
-- parse_manifest — parse `locker manifest <location>` lines
-- Returns: list of item hashes, matched_count
-- ---------------------------------------------------------------------------
local MANIFEST_INSIDE  = "^<?p?o?p?B?o?l?d?/?>>?( *<?d?[^>]*>? *)([^<]+)? ?<a exist=\"(-?%d+)\" noun=\"([^\"]-)\">([^<]-)</a>([^%(]-)?(%(.*)?)"
local MANIFEST_OUTSIDE = "^<?p?o?p?B?o?l?d?/?>>?( *<d[^>]*>[^<]*</d> *|  +)(an? )?([^%(]-)?(containing ([^%(]*))?(%(.*)?)?$"

local function parse_manifest_line(line)
  -- Try inside (with <a exist...>) first
  local depth, pre, exist, noun, name, post, attrs = line:match(MANIFEST_INSIDE)
  if depth and name then
    return {
      depth = depth, pre = pre or "", exist = exist,
      noun = noun, name = name, post = post or "", attrs = attrs or "",
      has_link = true,
    }
  end
  -- Try outside (plain text)
  depth, pre, name, _, post, attrs = line:match(MANIFEST_OUTSIDE)
  if depth and name then
    return {
      depth = depth, pre = pre or "", exist = nil,
      noun = nil, name = name:match("^%s*(.-)%s*$"), post = post or "", attrs = attrs or "",
      has_link = false,
    }
  end
  return nil
end

function M.parse_manifest(pm_lines, location_id)
  local temp_items   = {}
  local matched_count = 0
  local prev_noun    = ""
  local prev_level   = 0
  local item_path    = {}
  local base_path    = nil

  for _, line in ipairs(pm_lines) do
    -- Container headers (weapon rack, armor stand, etc.)
    local container_noun = line:match("[IO]n a.-(?:armor|weapon|clothing|deep|magical item) (%w+)")
    if container_noun then
      base_path = container_noun
      item_path = { base_path }
    else
      local m = parse_manifest_line(line)
      if m then
        matched_count = matched_count + 1

        -- compute depth/level from leading spaces or <d> tags
        local raw_depth = m.depth:gsub("<[^>]+>", ""):gsub("<[^>]+>", "")
        local spaces    = raw_depth:gsub("[^ ]", ""):len()
        local level     = math.max(0, math.floor((spaces - 6) / 2))

        -- manage item_path stack
        if level > prev_level then
          table.insert(item_path, prev_noun)
        elseif level < prev_level then
          local n_pop = prev_level - level
          for _ = 1, n_pop do table.remove(item_path) end
          if #item_path == 0 and base_path then item_path = { base_path } end
        end

        local path = table.concat(item_path, " > ")

        -- strip article from prename
        local prename = m.pre:gsub("^%s*a?n?%s*", ""):match("^%s*(.-)%s*$")
        local name_clean = m.name:gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
        local postname   = m.post
        local attrs_str  = m.attrs

        local registered = attrs_str:find("registered") and "Y" or ""
        local marked     = attrs_str:find("marked")     and "Y" or ""
        local hidden     = attrs_str:find("hidden")     and "Y" or ""
        local noun       = m.noun or util.noun_from_name(name_clean)
        local link_name  = m.exist and name_clean or ""
        local item_type  = util.get_item_type(name_clean, noun)

        -- jar stack detection from manifest
        local stack       = ""
        local stack_name  = ""
        local stack_noun  = ""
        local stack_type  = ""
        local stack_amount = 0
        local stack_status = ""

        if item_type:match("^jar") then
          stack_name  = util.deplural(postname):match("^%s*(.-)%s*$")
          stack_noun  = "" -- manifest doesn't provide noun for stack contents
          stack_type  = stack_name ~= "" and util.get_item_type(stack_name, nil) or ""
          -- parse amount from attrs: (N/M)
          local sa = attrs_str:match("%((%d+)/%d+%)")
          stack_amount = sa and tonumber(sa) or nil
          if stack_amount then
            -- full if numerator == denominator
            local sa2, sm = attrs_str:match("%((%d+)/(%d+)%)")
            if sa2 and sm and sa2 == sm then
              stack_status = "full"
            else
              stack_status = "partial"
            end
            stack = "jar"
          else
            stack_status = "empty"
          end
        end

        local containing = (stack == "") and "" or ("(" .. stack_name .. ") (" .. (stack_amount or 0) .. ")")
        local full_name = (
          (prename ~= "" and (prename .. " ") or "")
          .. (name_clean:gsub("^some ", ""))
          .. ((stack == "") and (postname ~= "" and (" " .. postname:match("^%s*(.-)%s*$")) or "") or "")
        ):match("^%s*(.-)%s*$")

        prev_level = level
        prev_noun  = noun or util.noun_from_name(full_name)

        table.insert(temp_items, {
          id           = m.exist,
          location_id  = location_id,
          level        = level + 1,
          path         = path,
          type         = item_type or "",
          name         = full_name,
          link_name    = link_name,
          containing   = containing,
          noun         = noun or "",
          amount       = 1,
          stack        = "",
          stack_status = stack_status,
          marked       = marked,
          registered   = registered,
          hidden       = hidden,
          update_noun  = m.exist and 1 or 0,
        })

        if stack ~= "" and stack_amount and stack_amount > 0 then
          table.insert(temp_items, {
            id           = m.exist,
            location_id  = location_id,
            level        = level + 1,
            path         = path .. " > " .. stack,
            type         = stack_type or "",
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
            update_noun  = 0,
          })
        end
      end
    end
  end

  return temp_items, matched_count
end

-- ---------------------------------------------------------------------------
-- locker_manifest_scrape — run `locker manifest <location>` and parse
-- Returns: item list, displayed_count
-- ---------------------------------------------------------------------------
function M.locker_manifest_scrape(location_name, location_id)
  local cmd   = "locker manifest " .. location_name
  local start = "^Thinking back, you recall|^Looking in front of you|^You must first visit|^You must have a Premium|Unknown town specified|You do not currently have a"
  local ep    = "^(?:<popBold/>)?<prompt"

  local lm_lines = quiet_command(cmd, start, ep, 5)
  -- retry once on nil/empty
  if not lm_lines or #lm_lines == 0 then
    lm_lines = quiet_command(cmd, start, ep, 5)
  end

  -- Check for access denied
  local joined = table.concat(lm_lines or {}, "\n")
  if joined:find("You must have a Premium", 1, true)
  or joined:find("You must first visit", 1, true)
  or joined:find("You do not currently have", 1, true) then
    return {}, 0
  end

  -- Extract displayed count
  local displayed_count = 0
  for _, line in ipairs(lm_lines) do
    local cnt = line:match("Obvious items?: *(%d+)")
    if cnt then displayed_count = tonumber(cnt) or 0; break end
  end

  -- Parse items
  local manifest_retry = 1
  local temp_items, matched_count = M.parse_manifest(lm_lines, location_id)

  while matched_count ~= displayed_count and manifest_retry < 4 do
    respond(string.format("invdb: manifest parse mismatch %d != %d, retry %d",
      matched_count, displayed_count, manifest_retry))
    manifest_retry = manifest_retry + 1
    lm_lines = quiet_command(cmd, start, ep, 5)
    temp_items, matched_count = M.parse_manifest(lm_lines, location_id)
  end

  if matched_count ~= displayed_count then
    respond("invdb: giving up on manifest after 4 retries for " .. location_name)
    return {}, 0
  end

  return temp_items, displayed_count
end

-- ---------------------------------------------------------------------------
-- refresh_standard_locker — traverse the standard locker in the current room
-- ---------------------------------------------------------------------------
function M.refresh_standard_locker(conn, character_id, settings, account_name, subscription, locations)
  -- Find the locker GameObj
  local locker = nil
  for _, o in ipairs(GameObj.loot()) do
    if o.name and o.name:lower():find("your locker") then locker = o; break end
  end
  if not locker then
    for _, o in ipairs(GameObj.loot()) do
      if o.noun and o.noun:lower() == "locker" then locker = o; break end
    end
  end

  if not locker then
    -- Try by interaction
    quiet_command("close locker", "You close|What were you|already closed", nil, 2)
    local open_result = quiet_command("open locker",
      "^<(?:container|clearContainer|exposeContainer)|That is already open|You open",
      "(<popBold/>)?<prompt", 2)
    for _, l in ipairs(open_result) do
      local ex_id, ex_noun, ex_name = l:match('<a exist="(-?%d+)" noun="(locker)">([^<]+)</a>')
      if ex_id then
        locker = { id = ex_id, noun = ex_noun, name = ex_name }; break
      end
    end
  end

  if not locker then
    respond("invdb: couldn't find locker")
    return
  end

  -- Open the locker
  local open_result = quiet_command("open #" .. locker.id,
    locker.id .. "|That is already open|Your locker is currently|You open",
    "(<popBold/>)?<prompt", 3)

  -- Extract locker capacity info
  local locker_count, locker_max = nil, nil
  for _, l in ipairs(open_result) do
    local c, mx = l:match("Your locker is currently holding (%d+) items? out of a maximum of (%d+)")
    if c then locker_count = tonumber(c); locker_max = tonumber(mx); break end
  end

  -- Traverse
  local locker_items, item_categories, _, _ =
    containers.traverse_container(locker, "in", "", "", -1, settings.open_containers, 9, false, settings, conn)

  db_mod.item_category_merge(conn, item_categories)

  -- Set location_id = 10 (standard locker)
  for _, item in ipairs(locker_items) do
    item.location_id = 10
    -- normalize path
    if item.path and item.path ~= "" then
      local segs = {}
      for prep, rest in item.path:gmatch("(in ) (%S+)") do
        table.insert(segs, rest)
      end
      if #segs > 0 then
        local reversed = {}
        for i = #segs, 1, -1 do table.insert(reversed, segs[i]) end
        item.path = table.concat(reversed, " > ")
      else
        item.path = item.path:gsub("^ *in ", ""):gsub(" in ", " > ")
      end
    end
  end

  if #locker_items > 0 then
    inv.insert_temp_items(conn, character_id, locker_items)
  end
  db_mod.merge_item_by_location(conn, character_id, 10, GameState.game)

  -- Premium: also scan family vault via locker manifest
  if subscription and subscription ~= "f2p" then
    respond("invdb: scanning family vault manifest...")
    local fv_items, _ = M.locker_manifest_scrape("family vault", 40)
    if #fv_items > 0 then
      -- family vault uses fake character_id
      local fake_char_id = db_mod.insert_fake_character(conn, account_name, subscription)
      for _, item in ipairs(fv_items) do item.location_id = 40 end
      inv.insert_temp_items(conn, fake_char_id, fv_items)
      db_mod.merge_item_by_location(conn, fake_char_id, 40, GameState.game)
    end
  end
end

-- ---------------------------------------------------------------------------
-- refresh_premium_lockers — scan each non-standard locker via manifest
-- ---------------------------------------------------------------------------
function M.refresh_premium_lockers(conn, character_id, settings, subscription, locations)
  if not locations then return end
  for loc_id_str, loc_info in pairs(locations) do
    local loc_id = tonumber(loc_id_str)
    if loc_id and loc_id > 10 and loc_info.type == "locker" then
      respond("invdb: scanning locker manifest for " .. (loc_info.name or loc_id_str) .. "...")
      local items, _ = M.locker_manifest_scrape(loc_info.name or "", loc_id)
      if #items > 0 then
        for _, item in ipairs(items) do item.location_id = loc_id end
        inv.insert_temp_items(conn, character_id, items)
        db_mod.merge_item_by_location(conn, character_id, loc_id, GameState.game)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- refresh_locker — dispatch standard vs premium
-- ---------------------------------------------------------------------------
function M.refresh_locker(conn, character_id, settings, account_name, subscription, locker_location, locations)
  -- fetch locker info if not already done
  if not locker_location or locker_location == "" then
    locker_location = M.locker_info()
  end

  if subscription == "premium" then
    M.refresh_premium_lockers(conn, character_id, settings, subscription, locations)
  else
    M.refresh_standard_locker(conn, character_id, settings, account_name, subscription, locations)
  end
end

return M
