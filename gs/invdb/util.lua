-- util.lua — formatting helpers, noun detection, item classification
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

-- ---------------------------------------------------------------------------
-- Timestamp helpers
-- ---------------------------------------------------------------------------
function M.now() return os.time() end

function M.int_to_date(ts, fmt)
  if type(ts) ~= "number" then return tostring(ts or "") end
  fmt = fmt or "%m/%d/%y"
  return os.date(fmt, ts)
end

function M.int_to_time(ts)
  if type(ts) ~= "number" then return tostring(ts or "") end
  return os.date("%Y-%m-%d %H:%M", ts)
end

function M.int_to_comma(n)
  if type(n) ~= "number" then return tostring(n or "") end
  local s = tostring(math.floor(n))
  local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  -- Remove leading comma if present
  result = result:gsub("^,", "")
  return result
end

-- ---------------------------------------------------------------------------
-- Deplural — singular form for jar/stack content type detection
-- ---------------------------------------------------------------------------
local DEPLURAL_EXCEPTIONS = {
  blades = "blade", branches = "branch", cabochons = "cabochon",
  essences = "essence", fans = "fan", globes = "globe", motes = "mote",
  pieces = "piece", shards = "shard", slices = "slice", teeth = "tooth",
  ["rose gold fire"] = "rose-gold fire",
}

function M.deplural(str)
  if not str or str == "" then return str end
  str = str:gsub("^containing ", "")
  -- Apply static exceptions
  for k, v in pairs(DEPLURAL_EXCEPTIONS) do
    str = str:gsub("%f[%a]" .. k .. "%f[%A]", v)
  end
  -- Remove trailing -ies → y
  str = str:gsub("ies$", "y")
  -- Remove trailing -s (not after moss, glass, etc.)
  str = str:gsub("([^oaei])s$", "%1")
  return str:match("^%s*(.-)%s*$") -- trim
end

-- ---------------------------------------------------------------------------
-- Noun extraction from item name string
-- Tries to guess the last meaningful noun word from an item's full name.
-- ---------------------------------------------------------------------------
function M.noun_from_name(str)
  if not str or str == "" then return "" end
  str = str:match("^%s*(.-)%s*$") -- trim

  local noun = nil

  if #str > 35 then
    -- Long name: find last non-preposition word before trailing preposition clause
    -- Simplified Lua port of the Ruby regex
    noun = str:match("(%S+)%s+(?:drawn by|of|set with[hi]?n?|in|that|%()")
    if not noun then
      noun = str:match("(%S+)%s+(?:with|an?)%s")
    end
  end

  if not noun then
    -- Short/medium: last word
    noun = str:match("Hammer of Kai$")
    if not noun then
      noun = str:match("%s(%S+)$") or str:match("^(%S+)$")
    end
  end

  if not noun or noun == "" then
    noun = str:match("([^%s]+)$") or str
  end

  -- Lapis lazuli special case
  if str:match("lapis lazuli$") then noun = "lapis" end
  if noun and noun:match("lazuli") then noun = "lapis" end

  return noun or ""
end

-- ---------------------------------------------------------------------------
-- Item type classification using Revenant's GameObj.classify API.
-- Maintains a session-local cache to avoid redundant classify calls.
-- ---------------------------------------------------------------------------
local _type_cache = {}

function M.get_item_type(name, noun)
  if not name or name == "" then return "unknown" end
  local cache_key = (name or "") .. "\0" .. (noun or "")
  if _type_cache[cache_key] then return _type_cache[cache_key] end

  local t = GameObj.classify(noun or M.noun_from_name(name), name) or "unknown"
  -- Strip leading/trailing 'uncommon,' qualifier
  t = t:gsub("^uncommon,", ""):gsub(",uncommon$", "")
  if t == "" then t = "unknown" end
  _type_cache[cache_key] = t
  return t
end

function M.clear_type_cache() _type_cache = {} end

-- ---------------------------------------------------------------------------
-- Output formatting helpers
-- ---------------------------------------------------------------------------

-- Wrap text in monospace output tags
function M.mono(msg) return '<output class="mono" />\n' .. msg .. '\n<output class="" />' end

-- Wrap text in monsterbold
function M.bold(msg) return "<pushBold/>" .. msg .. "<popBold/>" end

-- Wrap in whisper preset
function M.whisper(msg) return '<preset id="whisper">' .. msg .. "</preset>" end

-- Clickable command link
function M.cmd_link(display, cmd)
  return '<d cmd="' .. cmd .. '">' .. display .. "</d>"
end

-- Print to client window (respects frontend type)
function M.gs_print(msg)
  respond(msg)
end

-- Encode XML special characters
function M.xml_encode(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub('"', "&quot;")
  return s
end

-- ---------------------------------------------------------------------------
-- Table output formatter
-- Accepts a rows array-of-arrays where rows[1] is the headers.
-- Returns a printable string.
-- ---------------------------------------------------------------------------
function M.format_table(rows, date_format)
  date_format = date_format or "%m/%d/%y"
  if not rows or #rows < 2 then
    return M.whisper("no results found.")
  end

  local headers = rows[1]
  local ncols = #headers

  -- Find timestamp and updated column indices (to format as dates)
  local ts_cols = {}
  local numeric_cols = {}
  for i, h in ipairs(headers) do
    if h == "timestamp" or h == "updated" then ts_cols[i] = true end
    numeric_cols[i] = true -- assume numeric until we find a string
  end

  -- Determine max width per column and whether column is string
  local max_w = {}
  for i, h in ipairs(headers) do max_w[i] = #tostring(h) end

  local data_rows = {}
  local sum_qty = 0
  local qty_col = nil
  for i, h in ipairs(headers) do if h == "qty" then qty_col = i end end

  for ri = 2, #rows do
    local row = {}
    for ci = 1, ncols do
      local v = rows[ri][ci]
      if ts_cols[ci] and type(v) == "number" then
        v = M.int_to_date(v, date_format)
      elseif type(v) == "number" and headers[ci] and not headers[ci]:match("_id$") then
        v = M.int_to_comma(v)
        numeric_cols[ci] = true
      elseif v == nil then
        v = ""
      else
        v = tostring(v)
        if v:match("[a-zA-Z]") then numeric_cols[ci] = false end
      end
      row[ci] = tostring(v)
      if #row[ci] > max_w[ci] then max_w[ci] = #row[ci] end
    end
    if qty_col then sum_qty = sum_qty + (tonumber(rows[ri][qty_col]) or 0) end
    table_insert(data_rows, row)
  end

  -- Build format strings
  local sep_parts = {}
  local fmt_parts = {}
  for i = 1, ncols do
    local w = math.max(max_w[i], #tostring(headers[i]))
    sep_parts[i] = string.rep("-", w + 2)
    if i == ncols then
      fmt_parts[i] = " %-" .. w .. "s"
    else
      fmt_parts[i] = " %-" .. w .. "s |"
    end
  end

  local separator = table.concat(sep_parts, "-")
  local row_fmt   = table.concat(fmt_parts, "")

  local lines = {}
  table.insert(lines, '<output class="mono" />')

  -- Abbreviation legend (only show cols present in output)
  local abbrs = M.get_abbrs()
  local shown_abbrs = {}
  for _, h in ipairs(headers) do
    if abbrs[h] then shown_abbrs[h] = abbrs[h] end
  end
  for k, v in pairs(shown_abbrs) do
    table.insert(lines, string.format("... %5s: %s", k, v))
  end

  table.insert(lines, separator)
  table.insert(lines, string.format(row_fmt, table.unpack(headers)))
  table.insert(lines, separator)
  for _, row in ipairs(data_rows) do
    table.insert(lines, string.format(row_fmt, table.unpack(row)))
  end
  table.insert(lines, separator)

  local row_count = #data_rows
  if sum_qty > 0 then
    table.insert(lines, M.whisper(string.format(
      "matched %s total items in %d row%s.",
      M.int_to_comma(sum_qty), row_count, row_count ~= 1 and "s" or ""
    )))
  else
    table.insert(lines, M.whisper(string.format(
      "matched %d row%s.", row_count, row_count ~= 1 and "s" or ""
    )))
  end
  table.insert(lines, '<output class="" />')
  return table.concat(lines, "\n")
end

-- Compatibility alias used internally
table_insert = table.insert

-- Column abbreviation legend
function M.get_abbrs()
  return {
    loc      = "location of the item (hands|inv|alongside|locker|town abbr)",
    path     = "the path to an item, e.g. `backpack > box` is in a box, in a backpack",
    type     = "object type, per GameObj type data",
    stk      = "stack, a non-standard container, e.g. jar|bundle|voucher pack",
    epf      = "stack status (empty|partial|full) for jars/stacks",
    m        = "marked (Y or blank)",
    r        = "registered (Y or blank)",
    h        = "hidden (Y or blank)",
    pro      = "profession",
    rc       = "race abbreviation",
    lvl      = "level",
    area     = "location character was when last updated",
    sub      = "account type (f2p|standard|premium)",
    lockr    = "town locker is in, multi if multiple",
    inv      = "item count for carried items",
  }
end

-- ---------------------------------------------------------------------------
-- Large output confirmation — pause script if row count exceeds threshold
-- ---------------------------------------------------------------------------
function M.check_output_size(count, limit)
  limit = limit or 100
  if count > limit then
    respond(string.format(
      "invdb: large output (%d rows) requires unpausing the script before printing. " ..
      ';invdb --confirm_large_output=99999 to disable.', count
    ))
    -- Wait for ;u scriptname from user
    local line = get()
    while line and not line:match("^<prompt>") do
      line = get()
    end
  end
end

return M
