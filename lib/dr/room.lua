--- DRRoom — room text parser for player/NPC tracking.
-- Ported from Lich5 drroom.rb / drdefs.rb
-- @module lib.dr.room
local M = {}

-- Internal state
local state = {
  npcs         = {},
  dead_npcs    = {},
  pcs          = {},
  pcs_prone    = {},
  pcs_sitting  = {},
  room_objs    = {},
}

--- Parse an "Also here:" line into player/NPC lists.
-- Example input: "Also here: Trader Bob, Empath Alice who is lying down, and the body of Thief Carl."
-- @param text string The raw "Also here:" text from game output
function M.parse_also_here(text)
  if not text or text == "" then return end

  -- Reset lists
  state.pcs = {}
  state.pcs_prone = {}
  state.pcs_sitting = {}
  state.dead_npcs = {}

  -- Strip "Also here: " prefix
  local body = text:gsub("^Also here:%s*", "")
  -- Strip trailing period
  body = body:gsub("%.$", "")

  -- Normalize trailing " and X" to ", X" for consistent splitting
  body = body:gsub(" and ([^,]+)$", ", %1")

  -- Split on comma
  local entries = {}
  for entry in body:gmatch("[^,]+") do
    entries[#entries + 1] = entry:match("^%s*(.-)%s*$") -- trim
  end

  for _, entry in ipairs(entries) do
    -- Check for "the body of X" -> dead NPC
    local dead_name = entry:match("the body of%s+(.+)")
    if dead_name then
      -- Extract the last capitalized word as the noun/name
      local noun = dead_name:match("(%u%w+)%s*$")
      if noun then
        state.dead_npcs[#state.dead_npcs + 1] = noun
      end
    else
      -- Check for status suffixes
      local is_prone = entry:match("who is lying") ~= nil
      local is_sitting = entry:match("who is sitting") ~= nil

      -- Strip "who is/has ..." suffixes
      local clean = entry:gsub("%s+who%s+%w+%s+.*$", "")
      -- Strip parenthetical suffixes like "(dead)"
      clean = clean:gsub("%s*%b()%s*$", "")
      -- Trim again
      clean = clean:match("^%s*(.-)%s*$")

      -- Extract the last capitalized word as the character name
      local name = clean:match("(%u%w+)%s*$")
      if name then
        state.pcs[#state.pcs + 1] = name
        if is_prone then
          state.pcs_prone[#state.pcs_prone + 1] = name
        end
        if is_sitting then
          state.pcs_sitting[#state.pcs_sitting + 1] = name
        end
      end
    end
  end
end

--- Clear all tracked room data.
function M.clear()
  state.npcs = {}
  state.dead_npcs = {}
  state.pcs = {}
  state.pcs_prone = {}
  state.pcs_sitting = {}
  state.room_objs = {}
end

-- Metatable: allow M.npcs, M.pcs, etc. as property access
setmetatable(M, {
  __index = function(_, key)
    if state[key] ~= nil then
      return state[key]
    end
    return nil
  end,
})

return M
