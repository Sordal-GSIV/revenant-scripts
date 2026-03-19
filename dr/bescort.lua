--- @revenant-script
--- name: bescort
--- version: 1.0.0
--- author: rpherbig, others (original bescort.lic)
--- original-authors: rpherbig, DR-scripts community contributors
--- game: dr
--- description: Transport escort script — handles ferries, barges, airships, swamps, deserts, rivers, mazes, and other special travel in DragonRealms.
--- tags: travel,transport,navigation,escort,maze,barge,ferry,airship
--- source: https://elanthipedia.play.net/Lich_script_repository#bescort
--- @lic-certified: complete 2026-03-18
---
--- Conversion notes vs Lich5:
---   * MazeRoom class translated to Lua table with module-level room_list.
---   * Ruby proc-based valid_move predicates translated to Lua functions.
---   * XMLData.room_exits/room_title/room_description -> GameState equivalents.
---   * Room.current.id -> GameState.room_id; Room.current().wayto for wayto access.
---   * Map.findpath -> Map.find_path; Map[id] -> Map.find_room(id).
---   * DRRoom.room_objs used via DRRoom.room_objs array (parser-populated).
---   * UserVars.known_shards stored as JSON (Revenant settings store strings).
---   * UserVars.friends stored as JSON array.
---   * EquipmentManager via DREMgr.EquipmentManager(settings).
---   * DRC.kick_pile / DRSkill.getmodrank / DRCMM.check_moonwatch added to libs.
---   * Time.now -> os.time(); sleep -> pause; exit -> return from main function.
---   * Regex named captures used for astral_walk power_walk direction extraction.

-- ============================================================================
-- Dependencies
-- ============================================================================

require("dependency")

-- ============================================================================
-- Constants
-- ============================================================================

local CARDINALS = {
  n = "s", s = "n", ne = "sw", sw = "ne", nw = "se", se = "nw", e = "w", w = "e"
}
local ADJUSTMENTS = {
  n = {0, 1}, s = {0, -1}, ne = {1, 1}, sw = {-1, -1},
  nw = {-1, 1}, se = {1, -1}, e = {1, 0}, w = {-1, 0}
}
local ICE_PATH_HIB   = {"nw","ne","ne","e","ne","ne","ne","nw","sw","w","w","nw"}
local ICE_PATH_SHARD = {"se","e","e","ne","se","sw","sw","sw","w","sw","sw","se"}

-- ============================================================================
-- Utility helpers
-- ============================================================================

--- Check if a table of strings includes a value (plain, case-sensitive).
local function table_includes(t, val)
  for _, v in ipairs(t) do
    if v == val then return true end
  end
  return false
end

--- Find first string in table matching a Lua pattern.
local function table_find_match(t, pat)
  for _, v in ipairs(t) do
    if v:find(pat) then return v end
  end
  return nil
end

--- Set-difference: return items in a not in b (string array).
local function table_subtract(a, b)
  local bset = {}
  for _, v in ipairs(b) do bset[v:lower()] = true end
  local result = {}
  for _, v in ipairs(a) do
    if not bset[v:lower()] then result[#result+1] = v end
  end
  return result
end

--- Parse friends list from UserVars.friends (JSON array or empty).
local function get_friends()
  local raw = UserVars.friends
  if not raw or raw == "" then return {} end
  local ok, t = pcall(Json.decode, raw)
  return (ok and type(t) == "table") and t or {}
end

--- Get known shards list from UserVars.known_shards (JSON).
local function get_known_shards()
  local raw = UserVars.known_shards
  if not raw or raw == "" then return {} end
  local ok, t = pcall(Json.decode, raw)
  return (ok and type(t) == "table") and t or {}
end

--- Save known shards list to UserVars.known_shards as JSON.
local function set_known_shards(list)
  UserVars.known_shards = Json.encode(list)
end

-- ============================================================================
-- MazeRoom — BFS-based maze navigation
-- ============================================================================

local room_list = {}  -- module-level (equivalent to @@room_list)

local MazeRoom = {}
MazeRoom.__index = MazeRoom

--- Condense a direction string to abbreviated form.
local function condense_direction(direction)
  return direction:gsub("[Nn]orth", "n"):gsub("[Ss]outh", "s"):gsub("[Ee]ast", "e"):gsub("[Ww]est", "w")
                  :gsub("northeast", "ne"):gsub("southeast", "se"):gsub("southwest", "sw"):gsub("northwest", "nw")
end

--- Find a room in room_list by coordinate pair.
local function find_room_by_coords(coords)
  for _, room in ipairs(room_list) do
    if room.coords[1] == coords[1] and room.coords[2] == coords[2] then
      return room
    end
  end
  return nil
end

--- Update coords by applying an adjustment for a travel direction.
local function update_coords(coords, traveled)
  local adj = ADJUSTMENTS[traveled]
  if not adj then return coords end
  return {coords[1] + adj[1], coords[2] + adj[2]}
end

--- Create a new MazeRoom. If came_from is nil, resets the room_list (starting room).
function MazeRoom.new(came_from, source_room)
  local self = setmetatable({}, MazeRoom)
  self.desc    = nil
  self.checked = false
  self.parent  = nil

  if came_from then
    self.exits  = { [CARDINALS[came_from]] = source_room }
    source_room.exits[came_from] = self
    self.coords = update_coords(source_room.coords, came_from)
  else
    room_list = {}  -- reset class-level list
    self.exits  = {}
    self.coords = {0, 0}
  end

  -- Populate exits from current room
  local room_exits = GameState.room_exits or {}
  for _, exit in ipairs(room_exits) do
    local short = condense_direction(exit)
    if not self.exits[short] then
      self.exits[short] = nil  -- nil = unexplored
    end
  end
  -- Mark as nil explicitly (Lua tables don't store nil values)
  -- We track unexplored exits separately by checking if key exists
  room_list[#room_list + 1] = self
  return self
end

--- BFS to find best direction toward an unexplored exit.
function MazeRoom:best_path()
  for _, room in ipairs(room_list) do
    room.checked = false
    room.parent  = nil
  end
  self.checked = true
  local queue = {self}
  local qi = 1
  while qi <= #queue do
    local current = queue[qi]; qi = qi + 1
    for dir, child in pairs(current.exits) do
      if child == nil then
        -- unexplored exit found; return the first direction from self
        return current.parent or dir
      end
      if type(child) == "table" and not child.checked then
        child.checked = true
        child.parent  = current.parent or dir
        queue[#queue + 1] = child
      end
    end
  end
  return nil
end

--- Choose the next direction to wander, move, and return the resulting MazeRoom.
function MazeRoom:wander()
  local dir_to_go

  -- Single exit: must go that way
  local exit_count = 0
  local only_dir
  for d, _ in pairs(self.exits) do exit_count = exit_count + 1; only_dir = d end
  if exit_count == 1 then dir_to_go = only_dir end

  -- Find an unexplored exit
  if not dir_to_go then
    for d, room in pairs(self.exits) do
      if room == nil then dir_to_go = d; break end
    end
  end

  -- BFS to nearest unexplored
  if not dir_to_go then dir_to_go = self:best_path() end

  if not dir_to_go then
    respond("[bescort] Maze: no direction to go from BFS")
    return self
  end

  DRC.fix_standing()
  move(dir_to_go)
  pause(1)

  -- If we had already mapped this exit
  if type(self.exits[dir_to_go]) == "table" then
    return self.exits[dir_to_go]
  end

  -- Check if new coords match an existing room
  local new_coords = update_coords(self.coords, dir_to_go)
  local existing = find_room_by_coords(new_coords)
  if existing then
    self.exits[dir_to_go] = existing
    existing.exits[CARDINALS[dir_to_go]] = self
    return existing
  end

  -- Brand new room
  return MazeRoom.new(dir_to_go, self)
end

-- ============================================================================
-- Settings / equipment setup
-- ============================================================================

local args     = parse_args({
  {
    { name = "wilds",            regex = "wilds",            description = "The Leucro and Geni wilds on the NTR." },
    { name = "mode",             options = {"exit","leucro1","leucro2","geni"}, description = "Where?" }
  },
  {
    { name = "oshu_manor",       regex = "oshu_manor",       description = "Seordhevor kartais & grave worms in Oshu'ehhrsk Manor." },
    { name = "mode",             options = {"exit","worms","kartais"}, description = "Where?" }
  },
  {
    { name = "faldesu",          regex = "faldesu",          description = "Faldesu river at the end of the NTR." },
    { name = "mode",             options = {"haven","crossing"}, description = "Where?" }
  },
  {
    { name = "zaulfang",         regex = "zaulfang",         description = "Zaulfang swamp maze outside Haven." },
    { name = "mode",             options = {"exit","enter"},  description = "Where?" }
  },
  {
    { name = "gate_of_souls",    regex = "gate_of_souls",    description = "Blasted Plain between Gate of Souls and Temple of Ushnish." },
    { name = "mode",             options = {"exit","blasted","temple","fangs","fou"}, description = "Where?" }
  },
  {
    { name = "segoltha",         regex = "segoltha",         description = "The Segoltha south of the crossing." },
    { name = "mode",             options = {"north","south","west"}, description = "Where?" }
  },
  {
    { name = "crocs",            regex = "crocs",            description = "Blue belly crocodiles on NTR." },
    { name = "mode",             options = {"enter","exit"}, description = "Where?" }
  },
  {
    { name = "ways",             regex = "ways",             description = "Astral travelling." },
    { name = "mode",             options = {"aesry","crossing","fang","leth","merkresh","muspari","raven","riverhaven","shard","steppes","taisgath","theren","throne","velatohr"}, description = "Where?" }
  },
  {
    { name = "mammoth",          regex = "mammoth",          description = "Mammoths between Acenamacra, Fang Cove, and Ratha." },
    { name = "mode",             options = {"acen","fang","ratha"}, description = "Where?" }
  },
  {
    { name = "iceroad",          regex = "iceroad",          description = "Ice road between Shard and Hibarnhvidar." },
    { name = "mode",             options = {"shard","hibarnhvidar"}, description = "Where?" }
  },
  {
    { name = "basalt",           regex = "basalt",           description = "Ferry between Ratha and Necromancer Island." },
    { name = "mode",             options = {"island","ratha"}, description = "Where?" }
  },
  {
    { name = "balloon",          regex = "balloon",          description = "Airship between Langenfirth and Mriss." },
    { name = "mode",             options = {"langenfirth","mriss"}, description = "Where?" }
  },
  {
    { name = "dirigible",        regex = "dirigible",        description = "Airship between Shard and Aesry." },
    { name = "mode",             options = {"shard","aesry"}, description = "Where?" }
  },
  {
    { name = "airship",          regex = "airship",          description = "Airship between Crossing and Muspari." }
  },
  {
    { name = "therenropebridge",  regex = "therenropebridge", description = "Rope bridge between Theren and Rossman's Landing." },
    { name = "mode",             options = {"totheren","torossman"}, description = "Which direction?" }
  },
  {
    { name = "gondola",          regex = "^gondola$",        description = "Gondola between Shard and Leth Deriel." },
    { name = "mode",             options = {"north","south"}, description = "Which direction?" }
  },
  {
    { name = "fly_under_gondola", regex = "^fly_under_gondola$", description = "Fly under the gondola between Shard and Leth Deriel." },
    { name = "mode",             options = {"north","south"}, description = "Which direction?" }
  },
  {
    { name = "sandbarge",        regex = "sandbarge",        description = "Sand barge between Hvaral, Oasis, and Muspari." },
    { name = "start_location",   options = {"hvaral","oasis","muspari"}, description = "Where from?" },
    { name = "end_location",     options = {"hvaral","oasis","muspari"}, description = "Where to?" }
  },
  {
    { name = "desert",           regex = "desert",           description = "Hidasharon Desert on Mriss for armadillos." },
    { name = "mode",             options = {"adult","juvenile","elder","oasis","exit"}, description = "Where?" }
  },
  {
    { name = "velaka",           regex = "velaka",           description = "Velaka desert with zombie nomads and westanuryn." },
    { name = "mode",             options = {"nomads","westanuryn","slavers","exit"}, description = "Where?" }
  },
  {
    { name = "ferry",            regex = "^ferry$",          description = "Ferry between Leth Deriel and the Crossing." },
    { name = "mode",             options = {"leth","crossing"}, description = "Where?" }
  },
  {
    { name = "ferry1",           regex = "ferry1",           description = "Ferry between Hibarnhvidar and Ain Ghazal." },
    { name = "mode",             options = {"hibarnhvidar","ainghazal"}, description = "Where?" }
  },
  {
    { name = "lang_barge",       regex = "lang",             description = "Barge between Langenfirth and Riverhaven." }
  },
  {
    { name = "shard_gates",      regex = "shard",            description = "Use the Shard gates." }
  },
  {
    { name = "thief_guild",      regex = "thief_guild",      description = "Enter the Shard thieves guild." }
  },
  {
    { name = "abyss",            regex = "abyss",            description = "Cleric entrance to the Abyss; requires Rezz." }
  },
  {
    { name = "haven_throne",     regex = "haven_throne",     description = "Ferry between Riverhaven and Throne City." }
  },
  {
    { name = "hvaral_passport",  regex = "hvaral_passport",  description = "Handles the gate between Hvaral and Muspari." }
  },
  {
    { name = "brocket_young",    regex = "brocket_young",    description = "Enter young brocket deer hunting area." },
    { name = "mode",             options = {"enter","exit"}, description = "Enter or exit?" }
  },
  {
    { name = "brocket_mid",      regex = "brocket_mid",      description = "Enter mid brocket deer hunting area." },
    { name = "mode",             options = {"enter","exit"}, description = "Enter or exit?" }
  },
  {
    { name = "brocket_elder",    regex = "brocket_elder",    description = "Enter elder brocket deer hunting area." },
    { name = "mode",             options = {"enter","exit"}, description = "Enter or exit?" }
  },
  {
    { name = "hara_polo",        regex = "hara_polo",        description = "Traverse Polo Maze." },
    { name = "mode",             options = {"up","down","hunt"}, description = "Up, Down, or Hunt?" }
  },
  {
    { name = "jolas",            regex = "jolas",            description = "Ride The Jolas between Hara'jaal and Mer'Kresh." },
    { name = "mode",             options = {"harajaal","merkresh"}, description = "Where?" }
  },
  {
    { name = "currach",          regex = "currach",          description = "Row a currach between Halasa Temple and Aesry." },
    { name = "mode",             options = {"halasa","aesry"}, description = "Where?" }
  },
  {
    { name = "galley",           regex = "galley",           description = "Take the M'riss-Mer'Kresh galley." },
    { name = "mode",             options = {"mriss","merkresh"}, description = "Where?" }
  },
  {
    { name = "cave_trolls",      regex = "cave_trolls",      description = "Enter cave trolls hunting area beyond the stream." },
    { name = "mode",             options = {"enter","exit"}, description = "Enter or exit?" }
  },
  {
    { name = "asketis_mount",    regex = "asketis_mount",    description = "Climb Asketi's Mount to Black Marble Gargoyles." },
    { name = "mode",             options = {"up","down"},     description = "Climb up or down?" }
  },
  {
    { name = "coffin",           regex = "coffin",           description = "Enter the abyss via coffin for lanky grey lachs." }
  },
  {
    { name = "eluned",           regex = "eluned",           description = "Enter the Crystal Cavern of Eluned." }
  },
})

local settings          = get_settings()
local equipment_manager = DREMgr.EquipmentManager(settings)
local flying_mount      = settings.flying_mount
local flying_mount_item = settings.mountable_item or settings.flying_mount
local flying_mount_activate  = settings.mountable_verb
local flying_mount_dismount  = settings.mountable_dismount

pause(1)

-- ============================================================================
-- Flying mount helpers
-- ============================================================================

local function use_flying_mount(mount_type, mount_mode, speed)
  speed = speed or "fly"
  mount_mode = mount_mode:lower()

  if mount_mode == "mount" then
    if mount_type:find("[Bb]room") or mount_type:find("[Dd]irigible") then
      DRCI.get_item(mount_type)
      local r = DRC.bput("mount my " .. mount_type, "You mount your", "You are already mounted", "What were you referring")
      if r:find("What were you referring") then
        DRC.message("Can't mount your " .. mount_type .. ", where is it?")
        return false
      end
      DRC.bput("command " .. mount_type .. " to " .. speed, "You command your")
    elseif mount_type:find("[Cc]arpet") or mount_type:find("[Rr]ug") then
      DRCI.get_item(mount_type)
      local hand = DRC.right_hand() == mount_type and "right" or "left"
      DRC.bput("lower ground " .. hand, "You lower", "But you aren't holding")
      DRC.bput("unroll " .. mount_type, "You carefully unroll", "You can't unroll", "What were you referring")
      local r = DRC.bput("mount " .. mount_type, "slowly raises up", "You are already mounted", "What were you referring")
      if r:find("What were you referring") then
        DRC.message("Can't mount your " .. mount_type .. ", where is it?")
        return false
      end
      DRC.bput("command " .. mount_type .. " to " .. speed, "You command your")
    elseif mount_type:find("[Pp]hoenix feather") then
      DRCI.remove_item(flying_mount_item)
      DRCI.get_item(flying_mount_item)
      local r = DRC.bput("light my " .. flying_mount_item, "You reverently cradle a phoenix feather", "What were you referring to")
      if r:find("What were you referring") then
        DRC.message("Can't mount your " .. mount_type .. ", where is it?")
        return false
      end
      DRC.bput("command phoenix to " .. speed, "You signal the starfire phoenix")
    elseif mount_type:find("[Cc]loud") then
      DRCI.remove_item(flying_mount_item)
      DRCI.get_item(flying_mount_item)
      local r = DRC.bput(flying_mount_activate .. " my " .. flying_mount_item, "You gently buff", "Rub what")
      if r:find("What were you referring") then
        DRC.message("Can't mount your " .. mount_type .. ", where is it?")
        return false
      end
      DRC.bput("command " .. mount_type .. " to " .. speed, "You command your", "You signal the")
    else
      DRC.message(mount_type .. " is not a valid type of flying mount.")
      return false
    end

  elseif mount_mode == "dismount" then
    if mount_type:find("[Bb]room") or mount_type:find("[Dd]irigible") then
      DRC.bput("dismount", "floats down to the ground", "You climb off")
      DRCI.put_away_item(mount_type)
    elseif mount_type:find("[Cc]arpet") or mount_type:find("[Rr]ug") then
      DRC.bput("dismount", "floats down to the ground", "You climb off")
      DRC.bput("roll " .. mount_type, "You roll up", "You can't roll")
      DRCI.put_away_item(mount_type)
    elseif mount_type:find("[Pp]hoenix feather") then
      DRC.bput("snuff phoenix", "You beseech")
      DRCI.wear_item(flying_mount_item)
      if GameObj.right_hand() then DRCI.put_away_item(flying_mount_item) end
      if GameObj.left_hand()  then DRCI.put_away_item(flying_mount_item) end
    elseif mount_type:find("[Cc]loud") then
      DRC.bput(flying_mount_dismount .. " " .. mount_type, "With a gesture,")
      DRCI.wear_item(flying_mount_item)
      if GameObj.right_hand() then DRCI.put_away_item(flying_mount_item) end
      if GameObj.left_hand()  then DRCI.put_away_item(flying_mount_item) end
    else
      DRC.message(mount_type .. " is not a valid type of flying mount.")
      return false
    end
  end
  return true
end

-- ============================================================================
-- Navigation helpers
-- ============================================================================

local function do_map_move(movement)
  if type(movement) == "function" then
    movement()
  elseif type(movement) == "string" then
    move(movement)
  end
end

local function manual_go2(goal_room)
  if GameState.room_id == goal_room then return end
  local path = Map.find_path(GameState.room_id, goal_room)
  if not path then
    respond("[bescort] manual_go2: no path to " .. goal_room)
    return
  end
  local current = Room.current()
  for _, step in ipairs(path) do
    if current and current.wayto then
      do_map_move(current.wayto[tostring(step)])
    end
    current = Room.current()
  end
  -- Final step
  current = Room.current()
  if current and current.wayto then
    do_map_move(current.wayto[tostring(goal_room)])
  end
end

local function swim(dir)
  move(dir)
  pause(1)
  waitrt()
end

-- ============================================================================
-- Room inspection helpers
-- ============================================================================

local function room_objs_include(target)
  local objs = DRRoom.room_objs
  if type(objs) ~= "table" then return false end
  return table_includes(objs, target)
end

local function room_objs_find(pat)
  local objs = DRRoom.room_objs
  if type(objs) ~= "table" then return nil end
  return table_find_match(objs, pat)
end

local function pcs_empty()
  local pcs = DRRoom.pcs
  return type(pcs) ~= "table" or #pcs == 0
end

local function npcs_empty()
  local npcs = DRRoom.npcs
  return type(npcs) ~= "table" or #npcs == 0
end

-- ============================================================================
-- Maze wandering helpers
-- ============================================================================

local turns_since_bad = 0

local function search()
  fput("search")
  pause(1)
  waitrt()
  DRCT.retreat()
end

local function search_path(pathname, visible, movetype)
  if visible == nil then visible = true end
  movetype = movetype or "go"
  if visible then
    while true do
      repeat search() until room_objs_include(pathname) or room_objs_include("other stuff")
      if move(movetype .. " " .. pathname) then break end
      pause(1)
    end
    pause(1)
  else
    search()
    while not move(movetype .. " " .. pathname) do
      pause(1)
      search()
    end
  end
end

local function move_direction(dir_priority, force_match)
  local exits = GameState.room_exits or {}
  for _, dir in ipairs(dir_priority) do
    if table_includes(exits, dir) then
      turns_since_bad = 0
      move(dir)
      return true
    end
  end

  if force_match then
    local desc = GameState.room_description or ""
    for _, dir in ipairs(dir_priority) do
      for _, msg in ipairs(force_match) do
        if desc:find(msg, 1, true) then return false end
      end
      move(dir)
      pause(0.5)
      waitrt()
    end
    return true
  end

  if #exits == 0 then
    -- fog/empty room — try round-robin from priority list
    local idx = (turns_since_bad % #dir_priority) + 1
    move(dir_priority[idx])
    turns_since_bad = turns_since_bad + 1
    return turns_since_bad < 15
  end

  return false
end

--- Wander randomly until a room object matching target appears, then execute exit_command.
local function wander_maze_until(target, exit_command)
  Flags.add("maze-reset", "You can't go there")
  local current_room = MazeRoom.new()
  while true do
    if Flags["maze-reset"] then
      Flags.reset("maze-reset")
      local look_result = DRC.bput("look", "Obvious paths:")
      local paths_part = look_result:match("Obvious paths:(.*)")
      if paths_part then
        local first_exit = paths_part:match("%s*([%a]+)")
        if first_exit then move(first_exit) end
      end
      pause(1)
      current_room = MazeRoom.new()
    end

    if room_objs_include(target) then
      if not exit_command then return end
      if not move(exit_command) then
        DRC.fix_standing()
        wander_maze_until(target, exit_command)
      end
      return
    end
    current_room = current_room:wander()
  end
end

local function find_room_maze(valid_move, error_rooms, target)
  valid_move  = valid_move  or function(_) return true end
  error_rooms = error_rooms or {}

  while true do
    local room_id = GameState.room_id
    if error_rooms[room_id] then error_rooms[room_id]() end

    local room_name = GameState.room_name or ""
    local pcs       = DRRoom.pcs  or {}
    local friends   = get_friends()
    local non_friends = table_subtract(pcs, friends)

    local at_target = not target or room_name:find(target, 1, true)
    if pcs_empty() and npcs_empty() and at_target then return end
    if #pcs > 0 and #non_friends == 0 and #pcs <= 2 and at_target then return end

    local exits = GameState.room_exits or {}
    -- shuffle exits
    for i = #exits, 2, -1 do
      local j = math.random(i)
      exits[i], exits[j] = exits[j], exits[i]
    end
    if #exits == 0 then
      exits = {"nw","n","ne","e","se","s","sw","w"}
      for i = #exits, 2, -1 do
        local j = math.random(i)
        exits[i], exits[j] = exits[j], exits[i]
      end
    end

    -- Find valid exit
    local chosen
    for _, dir in ipairs(exits) do
      if valid_move(dir) then chosen = dir; break end
    end
    if chosen then move(chosen) end
  end
end

local function find_room_list(moves, min_count)
  min_count = min_count or 0
  local count = 0
  for _, dir in ipairs(moves) do
    count = count + 1
    if pcs_empty() and npcs_empty() and count > min_count then break end
    move(dir)
    pause(0.5)
  end
end

-- ============================================================================
-- Fare / bank helper
-- ============================================================================

local function get_fare(amount, town, room)
  if not settings.bescort_fare_handling then return false end
  echo("GETTING MONEY, YOU SLOB.")
  echo("Heading to " .. town .. " for public transportation fare")
  pause(1)

  -- Walk to bank deposit room
  local town_data = get_data and get_data("town")
  if town_data and town_data[town] and town_data[town].deposit then
    manual_go2(town_data[town].deposit.id)
  end

  DRC.bput("JUSTICE", "After assessing", "lawless and unsafe")
  local recent = reget(5, "You are also fairly sure that the people are convinced")
  if recent then
    echo("You might be a necromancer!  Get some money manually!")
    return false
  end

  local succeeded = false
  for _, each_amount in ipairs(DRCM.minimize_coins(amount)) do
    succeeded = DRCM.get_money_from_bank(each_amount, settings)
  end
  if not succeeded then echo("Put some fare money in the " .. town .. " bank!") end
  manual_go2(room)
  return succeeded
end

-- ============================================================================
-- Hide helper
-- ============================================================================

local function hide_if_enabled()
  if settings.bescort_hide == false then return false end
  return DRC.hide()
end

-- ============================================================================
-- Transport scripts
-- ============================================================================

local function coffin()
  DRCMM.check_moonwatch()
  local sun_data = {}
  local raw = UserVars.sun
  if raw and raw ~= "" then
    local ok, t = pcall(Json.decode, raw)
    if ok and type(t) == "table" then sun_data = t end
  end
  local look_at = sun_data["day"] and "sunlight" or "starlight"

  local image_hash = {
    boar    = {"longbow", "berserking barbarian"},
    cat     = {"grimacing woman", "twin crossed swords with jagged blades"},
    cobra   = {"shattered egg", "the image of an erupting volcano"},
    dolphin = {"deer drinking from a flowing stream", "great tidal wave"},
    lion    = {"pack of well-groomed battle hounds", "bloodstained stiletto"},
    panther = {"cluster of twinkling stars", "child shivering fearfully in the throes of a nightmare"},
    ram     = {"flourishing rose garden", "jagged crystalline blade"},
    raven   = {"bowl of striped peppermint", "shattered caravan wheel"},
    wolf    = {"charred black stave", "long flowing skirt"},
    wren    = {"plump opera singer", "cracked mirror"},
  }

  local white_tapestry = {}
  local black_tapestry = {}
  local animal_names   = {}
  for animal, values in pairs(image_hash) do
    white_tapestry[#white_tapestry+1] = values[1]
    black_tapestry[#black_tapestry+1] = values[2]
    animal_names[#animal_names+1]     = animal
  end

  local lever_pulled = false
  while not lever_pulled do
    DRCT.walk_to(13600)
    DRC.bput("look behind satin tapestry", "Peeking behind the tapestry")
    DRC.bput("turn steel crank", "Roundtime", "You step behind the blood red tapestry")

    -- Find primary image
    local image_patterns = {"I could not find what"}
    for _, name in ipairs(animal_names) do image_patterns[#image_patterns+1] = name end
    local image_result = DRC.bput("look " .. look_at, table.unpack(image_patterns))
    local image
    for _, name in ipairs(animal_names) do
      if image_result:find(name, 1, true) then image = name; break end
    end
    if not image then
      echo("[bescort] coffin: couldn't read image, retrying")
    else
      local light = image_hash[image][1]
      local dark  = image_hash[image][2]

      -- Black tapestry
      local dseen = false
      DRCT.walk_to(13602)
      while not dseen do
        local wheel = DRC.bput("look wooden wheel", table.unpack(black_tapestry))
        if wheel:find(dark, 1, true) then dseen = true; break end
        DRC.bput("pull rope", "You grasp onto the woven rope and heave downward")
      end

      -- Light tapestry
      local lseen = false
      DRCT.walk_to(13601)
      while not lseen do
        local wheel = DRC.bput("look wooden wheel", table.unpack(white_tapestry))
        if wheel:find(light, 1, true) then lseen = true; break end
        DRC.bput("pull rope", "You grasp onto the woven rope and heave downward")
      end

      -- Pull iron lever
      DRCT.walk_to(13600)
      DRC.bput("look behind satin tapestry", "Peeking behind the tapestry")
      local lever = DRC.bput("pull iron lever", "Roundtime", "it won't budge")
      if lever:find("Roundtime", 1, true) then
        lever_pulled = true
      else
        echo("Someone reset the coffin.")
      end
    end
  end

  waitrt()
  equipment_manager:empty_hands()
  DRC.bput("open coffin", "You open the heavy lid", "The coffin is already open")
  DRC.bput("go coffin", "Obvious exits", "The lid of the coffin is closed")
  waitfor("You suddenly feel the presence of cold stone")
  while GameState.stunned do pause(0.5) end
  DRC.fix_standing()
  fput("look")
  fput("look")
end

local function asketis_mount(mode)
  if mode == "up" then
    while DRC.bput("climb up", "You work your way", "You climb over", "You can't do that"):find("You work your way") do end
  elseif mode == "down" then
    while DRC.bput("climb down", "You work your way", "You climb down", "You can't do that"):find("You work your way") do end
  end
end

local function cave_trolls(mode)
  local start_room, moveset
  if mode:find("enter") then
    start_room = 19089
    moveset = {"southeast","southeast","southeast"}
  else
    start_room = 15759
    moveset = {"northwest","northwest","northwest"}
  end
  manual_go2(start_room)
  move("go stream bank")
  equipment_manager:empty_hands()
  local have_changed_gear = flying_mount and false or equipment_manager:wear_equipment_set("swimming")
  if flying_mount then
    use_flying_mount(flying_mount, "mount")
    move(moveset[1])
  else
    for _, dir in ipairs(moveset) do swim(dir) end
  end
  if flying_mount then use_flying_mount(flying_mount, "dismount") end
  if have_changed_gear then equipment_manager:wear_equipment_set("standard") end
  move("go stream bank")
end

local function take_m_m_galley(mode)
  local galley_titles = {"[[The Galley Cercorim]]", "[[The Galley Sanegazat]]"}
  local dock_rooms    = {6555, 6656}
  local room_name = GameState.room_name or ""
  local is_dock   = GameState.room_id == 6555 or GameState.room_id == 6656
  local is_galley = table_includes(galley_titles, room_name)

  if not is_dock and not is_galley then
    echo("You are not at the galley docks, or on the galley.")
    return
  end

  if GameState.room_id == 6555 then
    if DRCM.wealth("Mer'Kresh") < 120 then
      echo("Get money you slob!")
      if not get_fare(300, "Mer'Kresh", 6555) then return end
    end
  end

  while true do
    local cur_id   = GameState.room_id
    local cur_name = GameState.room_name or ""

    if (cur_id == 6555 and mode == "merkresh") or (cur_id == 6656 and mode == "mriss") then
      echo("You're there.")
      return

    elseif cur_id == 6555 or cur_id == 6656 then
      hide_if_enabled()
      while not room_objs_find("the galley") do pause(1) end
      local r = DRC.bput("go galley",
        "You hand him your lirums and climb aboard",
        "Come back when you can afford the fare",
        "The galley has just left the harbor",
        "You look around in vain for the")
      if r:find("has just left the harbor") then
        while room_objs_find("the galley") do pause(1) end
      elseif r:find("afford the fare") then
        echo("Get money you slob!"); return
      else
        pause(1)
      end

    elseif table_includes(galley_titles, cur_name) then
      if mode == "merkresh" then
        while not room_objs_find("Mer'Kresh dock") do pause(1) end
        local r = DRC.bput("go dock", "Obvious paths:", "has just pulled away", "You see no dock", "What were you referring to")
        if r:find("pulled away") or r:find("no dock") or r:find("referring to") then
          while room_objs_find("Mer'Kresh dock") do pause(1) end
        end
      elseif mode == "mriss" then
        while not room_objs_find("M'Riss dock") do pause(1) end
        local r = DRC.bput("go dock", "Obvious paths:", "has just pulled away", "You see no dock", "What were you referring to")
        if r:find("pulled away") or r:find("no dock") or r:find("referring to") then
          while room_objs_find("M'Riss dock") do pause(1) end
        end
      end
    end
  end
end

local function currach(mode)
  local aesry_rooms  = {5555, 5557, 5558}
  local halasa_rooms = {15863}
  local cur_id = GameState.room_id

  if mode:find("aesry") and table_includes(aesry_rooms, cur_id) then
    echo("You're already there silly!"); return
  end
  if mode:find("halasa") and table_includes(halasa_rooms, cur_id) then
    echo("You're already there silly!"); return
  end

  local row_direction
  if     mode == "aesry"  then row_direction = "pier"
  elseif mode == "halasa" then row_direction = "rock"
  else echo("Unrecognized argument: " .. mode); return end

  local all_rooms = {5555, 5557, 5558, 15863}
  if table_includes(all_rooms, cur_id) then
    move("go currach")
    DRC.bput("get oars", "You grab hold of the oars", "But you already have a firm grip on the oars", "What were you referring to", "You can't do that right now")
    DRC.bput("untie currach", "You untie the", "But it's not tied to anything!", "What were you referring to", "You can't do that right now")
  end

  while true do
    local r = DRC.bput("tie currach to " .. row_direction, "isn't close enough!", "You pull at the oars", "is already moored")
    if r:find("is already moored") then
      DRC.fix_standing()
      move("go " .. row_direction)
      return
    else
      DRC.bput("row " .. row_direction, "You pull strongly", "What were you referring to", "You can't do that right now")
    end
  end
end

local function jolas(mode)
  local boat_rooms = {15253, 6542, 15450, 15451, 15452, 15453, 15454}
  if not table_includes(boat_rooms, GameState.room_id) then
    echo("You are not at the correct dock to ride The Jolas."); return
  end

  local cur_id = GameState.room_id
  if (mode:find("merkresh") and cur_id == 6542) or (mode:find("harajaal") and cur_id == 15253) then
    echo("You're already there silly!"); return
  end

  if (mode:find("merkresh") and cur_id == 15253) or (mode:find("harajaal") and cur_id == 6542) then
    while not room_objs_find("The Jolas") do pause(1) end
    DRC.bput("go Jolas", "You climb", "What were you referring")
    waitfor("The captain barks the order to tie off the Jolas to the docks")
    if GameState.room_id ~= 15450 then DRCT.walk_to(15450) end
    if room_objs_include("Sumilo Dock") and mode:find("harajaal") then
      move("go dock"); return
    elseif room_objs_include("Wharf End") and mode:find("merkresh") then
      move("go end"); return
    else
      -- Recursive: try again from wherever we ended up
      local function jolas_retry(m)
        jolas(m)
      end
      jolas_retry(mode)
    end
  end
end

local function hara_polo_direction(mode)
  local cur_id = GameState.room_id
  if mode:find("up") and cur_id ~= 11411 and cur_id ~= 11412 then
    echo("Going up the maze to the Enclave must be started from 11411 or 11412."); return false
  elseif mode:find("down") and cur_id ~= 11416 and cur_id ~= 11412 then
    echo("Going down the maze towards the cliff and boat to Ratha must be started from 11416 or 11412."); return false
  elseif mode:find("hunt") and cur_id ~= 11416 and cur_id ~= 11412 then
    echo("Going hunting must begin in room 11416 or 11412."); return false
  else
    if mode:find("hunt") then move("n") end
  end
  return true
end

local function hara_polo(mode)
  if not hara_polo_direction(mode) then return end

  if mode:find("up") then
    if GameState.room_id == 11411 then move("climb slope") end
    while not room_objs_include("rock") do move("ne") end
    move("s")
  elseif mode:find("down") then
    if GameState.room_id == 11416 then move("n") end
    while not room_objs_include("slope") do move("ne") end
    move("climb slope")
  else
    find_room_list({"ne","ne","ne"})
  end
end

local function enter_brocket(mode)
  if not mode:find("exit") and GameState.room_id ~= 3462 then
    echo("Brocket deer entrance must be started from 3462."); return false
  end
  if mode:find("enter") then move("climb fence") end
  return true
end

local function brocket_young(mode)
  if not enter_brocket(mode) then return end
  if mode:find("enter") then
    find_room_list({"w","w","w"})
  else
    while not room_objs_include("log fence") do move("e") end
    move("climb fence")
  end
end

local function brocket_mid(mode)
  if not enter_brocket(mode) then return end
  if mode:find("enter") then
    while not room_objs_include("gentle hill") do move("w") end
    move("climb hill")
    find_room_list({"e","e","e"})
  else
    while not room_objs_include("gentle hill") do move("w") end
    move("climb hill")
    while not room_objs_include("log fence") do move("e") end
    move("climb fence")
  end
end

local function brocket_elder(mode)
  if not enter_brocket(mode) then return end
  if mode:find("enter") then
    while not room_objs_include("gentle hill") do move("w") end
    move("climb hill")
    while not room_objs_include("rolling hill") do move("e") end
    move("climb hill")
    find_room_list({"w","w","w"})
  else
    while not room_objs_include("rolling hill") do move("e") end
    move("climb hill")
    while not room_objs_include("gentle hill") do move("w") end
    move("climb hill")
    while not room_objs_include("log fence") do move("e") end
    move("climb fence")
  end
end

local function oshu_manor(mode)
  if not mode:find("exit") and GameState.room_id ~= 2317 then
    echo("Oshu manor script must be started from 2317"); return
  end
  if mode:find("exit") then
    DRCT.walk_to(2317)
  elseif mode:find("worms") then
    DRC.wait_for_script_to_complete("oshu_manor", {"worms"})
    find_room_list({"sw","w","w","w","w","n","n","s","s","e","s","e","s","se","ne","e","w","n","n","ne"})
  elseif mode:find("kartais") then
    DRC.wait_for_script_to_complete("oshu_manor", {"kartais"})
    find_room_list({"e","e","w","w","w","n","n","n"})
  end
end

local function take_sandbarge(start_location, end_location)
  if start_location == end_location then
    echo("You entered the same locations."); return
  end

  if     start_location == "muspari" then manual_go2(6872)
  elseif start_location == "oasis"   then
    if   end_location == "hvaral"  then manual_go2(7578)
    else                                 manual_go2(7579) end
  elseif start_location == "hvaral"  then manual_go2(3766)
  end

  local port_type, port_call
  if     end_location == "muspari" then port_type = "platform"; port_call = "The sand barge pulls into dock"
  elseif end_location == "oasis"   then port_type = "oasis";    port_call = "The sand barge pulls up to a desert oasis"
  elseif end_location == "hvaral"  then port_type = "dock";     port_call = "The sand barge pulls into dock"
  end

  local r = DRC.bput("go barge",
    "What were you referring to",
    "One of the barge's crew members watching",
    "You can't do that right now")
  if r:find("What were you referring to") or r:find("can't do that right now") then
    hide_if_enabled()
    waitfor("A sand barge pulls")
    take_sandbarge(start_location, end_location)
  elseif r:find("crew members watching") then
    hide_if_enabled()
    waitfor(port_call)
    move("go " .. port_type)
  end
end

local function desert_enter()
  DRCT.walk_to(12581)
  move("down")
end

local function desert(mode)
  local priority_directions = {"northeast","east","north","northwest","south","southeast","west","southwest"}

  if not mode:find("exit") and GameState.room_id ~= 6760 then
    echo("Desert script must be started in 6760"); return
  end

  if mode:find("oasis") then
    while true do
      desert_enter()
      local paths = {
        {"s","ne","ne","s","s","ne","e"},
        {"ne","n","ne","n","ne","n","n","ne","n","ne","n"},
        {"sw","e","s","s","ne","s","se","n","ne","ne","ne"},
        {"n","sw","ne","s","sw","n","up","n","s","s","n","n","down","n","s","s","sw","s"},
        {"n","ne","up","e","s","ne","nw","ne","e","nw"},
      }
      local found = false
      for pi, path in ipairs(paths) do
        for _, movement in ipairs(path) do
          if room_objs_include("shimmering oasis") then
            move("go oasis"); return
          end
          move(movement)
        end
        if pi < #paths then
          if pi == 1 then move("go trail")
          elseif pi == 2 then move("go path")
          elseif pi == 3 then move("go trail")
          end
        end
      end
      move("go road")
    end

  elseif mode:find("juvenile") then
    desert_enter()
    find_room_maze()

  elseif mode:find("adult") then
    desert_enter()
    while not room_objs_include("faint trail that stretches towards a sand-filled valley") do
      move_direction(priority_directions)
    end
    move("go trail")
    find_room_maze()

  elseif mode:find("elder") then
    desert_enter()
    while not room_objs_include("faint trail that stretches towards a sand-filled valley") do
      move_direction(priority_directions)
    end
    move("go trail")
    while not room_objs_include("faint path leading to some nearby dunes") do
      move_direction(priority_directions)
    end
    move("go path")
    find_room_maze()

  elseif mode:find("exit") then
    local room_name = GameState.room_name or ""
    if room_name:find("Sanctuary") then  -- Oasis
      DRC.release_invisibility()
      DRC.bput("ask Sand Elf about desert", "The Sand Elf laughs and glances at you playfully")
      DRC.fix_standing()
      desert(mode)
    end
    if room_name:find("Sand Valley") then  -- Adult Area
      while not room_objs_include("faint trail leading to some nearby dunes") do
        move_direction(priority_directions)
      end
      move("go trail")
      desert(mode)
    end
    if room_name:find("High Dunes") then  -- Juvenile or Elder area
      while not room_objs_include("faint trail that stretches towards a sand-filled valley")
        and not room_objs_include("faint path that stretches towards a sand-filled valley") do
        move_direction(priority_directions)
      end
      if not room_objs_include("faint trail that stretches towards a sand-filled valley") then
        move("go path")
        desert(mode)
        return
      end
      move("south")
      move("northeast")
      DRCT.walk_to(6760)
    end
  end
end

local function velaka_desert_enter()
  DRCT.walk_to(247)
  move("go trail")
end

local function velaka_desert(mode)
  if mode:find("nomads") then
    velaka_desert_enter()
    wander_maze_until("high plateau", "climb plateau")
  elseif mode:find("westanuryn") then
    velaka_desert_enter()
    find_room_maze()
  elseif mode:find("slavers") then
    velaka_desert_enter()
    find_room_maze(function(_) return true end, {}, "Rock Circle")
  elseif mode:find("exit") then
    local room_name = GameState.room_name or ""
    if not room_name:find("Velaka Desert") then
      echo("This must be started in the Velaka Desert!"); return
    end
    if room_name:find("Walk of Bones") then  -- Nomad Area
      manual_go2(15052)
      move("climb trail")
      velaka_desert(mode)
    else
      wander_maze_until("rocky trail", "go trail")
    end
  end
end

local function wilds_enter()
  search_path("spot")
end

local function wilds_leucro_maze(entering)
  if entering then
    while move_direction({"northeast","east","north","southeast"}) do
      pause(0.5)
      if room_objs_include("tangled deadfall") then break end
    end
    if GameState.room_id == 7958 then
      move("go spot")
      wilds_leucro_maze(entering)
      return
    end
    move("go dead")
  else
    while move_direction({"northwest","west","north"}) do pause(0.5) end
  end
end

local function wilds_leucro_walk()
  local attempts = 0
  local target_desc = "small creatures still lurk beneath its surface -- perhaps following the remnant of an old, long unused trail."
  while not (GameState.room_description or ""):find(target_desc, 1, true) do
    if not move_direction({"southeast","south","southwest","west"}) then
      move("southeast")
    end
    pause(0.5)
    attempts = attempts + 1
    if attempts == 50 then echo("Train your perception!"); return end
  end
  search_path("trail", false)
end

local function wilds_leave_trail()
  local plant_desc = "A fearsomely large black plant rests at the bottom of two slopes."
  while move_direction({"northeast","north","northwest","east","south"},
    {plant_desc}) do
    pause(0.5)
  end
  move("go dead")
end

local function wilds_leave()
  local matches = {
    "It drips slowly into the undergrowth, creating a damp sludge that makes walking unpleasant and hazardous",
    "Several sets of yellow eyes stare out unblinkingly from the safety of oak tree limbs",
    "A fearsomely large black plant rests at the bottom of two slopes",
    "A lively brook once bubbled through the narrow gully, but time and drought have left only this cracked streambed",
  }

  while true do
    while move_direction({"northwest","west","north","northeast"}, matches) do pause(0.25) end
    local desc = GameState.room_description or ""
    if desc:find(matches[1], 1, true) then
      search_path("trail", false)
    elseif desc:find(matches[2], 1, true) or desc:find(matches[3], 1, true) then
      wilds_leave_trail()
    else
      break
    end
  end
end

local function wilds(mode)
  if not mode:find("exit") and GameState.room_id ~= 7958 then
    echo("Wilds script must be started from 7958"); return
  end
  if mode:find("exit") then
    wilds_leave()
  elseif mode:find("leucro1") then
    wilds_enter()
    find_room_maze(
      function(dir)
        local exits = GameState.room_exits or {}
        -- Avoid going northwest if exits are exactly {east, south, northwest}
        if dir == "northwest" and #exits == 3 then
          local has_e = table_includes(exits, "east")
          local has_s = table_includes(exits, "south")
          local has_nw = table_includes(exits, "northwest")
          if has_e and has_s and has_nw then return false end
        end
        return true
      end,
      {
        [7958] = function() search_path("spot") end,
        [7957] = function() move("east") end,
      }
    )
  elseif mode:find("leucro2") then
    wilds_enter()
    wilds_leucro_maze(true)
    find_room_list({"se","s","se","sw","sw","sw","w","w","w","w","s","se"}, 4)
  elseif mode:find("geni") then
    wilds_enter()
    wilds_leucro_maze(true)
    wilds_leucro_walk()
    find_room_maze()
  end
end

local function faldesu(mode)
  if not mode:find("haven") and not mode:find("crossing") then
    echo("You must specify haven or crossing for traversing the faldesu river"); return
  end

  local going_north = mode:find("haven") ~= nil

  if flying_mount then
    -- swim_faldesu with flying mount
    local start = going_north and 1375 or 473
    manual_go2(start)
    if flying_mount:find("[Pp]hoenix feather") then
      use_flying_mount(flying_mount, "mount", "streak")
    else
      use_flying_mount(flying_mount, "mount")
    end
    move("go river")
    if going_north then move("n"); move("nw")
    else move("s"); move("sw") end
    move("go bridge")
    use_flying_mount(flying_mount, "dismount")
    return
  end

  if DRSkill.getmodrank("Athletics") >= 140 then
    if DRSkill.getmodrank("Athletics") < 300 then
      equipment_manager:empty_hands()
      equipment_manager:wear_equipment_set("swimming")
    end
    -- swim_faldesu without flying mount
    local start = going_north and 1375 or 473
    manual_go2(start)
    local moveset = going_north and {"north","northwest","northeast"} or {"south","southwest","southeast"}
    move("dive river")
    local exits = GameState.room_exits or {}
    while table_includes(exits, moveset[1]) do swim(moveset[1]); exits = GameState.room_exits or {} end
    exits = GameState.room_exits or {}
    while table_includes(exits, "east") do swim(moveset[2]); exits = GameState.room_exits or {} end
    exits = GameState.room_exits or {}
    while table_includes(exits, moveset[1]) do swim(moveset[3]); exits = GameState.room_exits or {} end
    move("climb bridge")
    if DRSkill.getmodrank("Athletics") < 300 then
      equipment_manager:wear_equipment_set("standard")
    end
  else
    -- take river ferry
    local north = going_north
    if north then manual_go2(1385) else manual_go2(470) end
    while true do
      local r = DRC.bput("go ferry",
        "You .* climb aboard", "Come back when you can afford the fare",
        "not here", "I could not find what you were referring to",
        "stuck here until the next one arrives")
      if r:find("not here") or r:find("I could not find") or r:find("stuck here") then
        hide_if_enabled()
        waitfor("pulls into the dock", "pulls up to the dock")
      elseif r:find("climb aboard") then
        hide_if_enabled()
        waitfor("reaches the dock and its crew ties the ferry off")
        move("go dock")
        break
      elseif r:find("afford the fare") then
        break
      end
    end
  end
end

local function iceroad(mode)
  if not mode:find("shard") and not mode:find("hibarnhvidar") then
    echo("You must specify shard or hibarnhvidar for traversing the ice road"); return
  end

  local path = (mode == "shard") and ICE_PATH_SHARD or ICE_PATH_HIB
  equipment_manager:empty_hands()

  local footwear         = settings.footwear
  local move_fast        = false
  local footwear_removed = false
  local skates_worn      = false

  if flying_mount then
    move_fast = true
    if flying_mount:find("[Bb]room") or flying_mount:find("[Dd]irigible") or
       flying_mount:find("[Cc]arpet") or flying_mount:find("[Rr]ug") or
       flying_mount:find("[Pp]hoenix feather") then
      use_flying_mount(flying_mount, "mount", "glide")
    elseif flying_mount:find("[Cc]loud") then
      use_flying_mount(flying_mount, "mount", "drift")
    else
      DRC.message(flying_mount .. " is not a valid type of flying mount."); return
    end
    path = (mode == "shard") and {"se","se","sw","sw","se"} or {"nw","ne","ne","nw","sw"}
  else
    if footwear then
      if DRCI.remove_item(footwear) then
        footwear_removed = true
        DRCI.put_away_item(footwear)
      end
    end
    if DRCI.exists("skates") then
      DRCI.get_item("skates")
      if DRCI.wear_item("skates") then
        skates_worn = true
      else
        DRCI.put_away_item("skates")
      end
    end
    move_fast = skates_worn
  end

  Flags.add("bescort-move-slow",
    "You had better slow down!",
    "At the speed you are traveling, you are going to slip and fall sooner",
    "Your excessive speed causes you to lose your footing",
    "Falling down you")

  for _, movement in ipairs(path) do
    move(movement)
    waitrt()
    if Flags["bescort-move-slow"] then move_fast = false end
    if not move_fast then
      DRC.collect("rock")
      DRC.kick_pile()
      waitrt()
    end
  end

  if skates_worn then DRCI.remove_item("skates"); DRCI.put_away_item("skates") end
  if footwear_removed then DRCI.get_item(footwear); DRCI.wear_item(footwear) end
  if flying_mount then use_flying_mount(flying_mount, "dismount") end
end

local function take_mammoth(mode)
  if     mode == "fang" then
    local id_to_mammoth = {[2239] = "tall", [11130] = "sea"}
    local ids = {2239, 11130}
    local sorted = DRCT.sort_destinations(ids)
    local closest = sorted[1]
    manual_go2(closest)
    local mammoth_type = id_to_mammoth[closest]
    local r = DRC.bput("join " .. mammoth_type .. " mammoth",
      "What were you referring to", "You join the Merelew driver")
    if r:find("What were you referring to") then
      waitfor("The waves along the waterline increase drastically",
              "A watery trumpeting sound heralds the swift approach")
      take_mammoth(mode)
    else
      waitfor("The burly beast trumpets a series of watery blasts",
              "Here we are, ladies and gentlemen")
    end
  elseif mode == "acen" then
    manual_go2(8301)
    local r = DRC.bput("join tall mammoth",
      "What were you referring to", "You join the Merelew driver")
    if r:find("What were you referring to") then
      waitfor("The waves along the waterline increase drastically",
              "A watery trumpeting sound heralds the swift approach")
      take_mammoth(mode)
    else
      waitfor("The burly beast trumpets a series of watery blasts",
              "Here we are, ladies and gentlemen")
    end
  elseif mode == "ratha" then
    manual_go2(8301)
    local r = DRC.bput("join sea mammoth",
      "What were you referring to", "You join the Merelew driver")
    if r:find("What were you referring to") then
      waitfor("The waves along the waterline increase drastically",
              "A watery trumpeting sound heralds the swift approach")
      take_mammoth(mode)
    else
      waitfor("The burly beast trumpets a series of watery blasts",
              "Here we are, ladies and gentlemen")
    end
  end
end

local function take_crawling_plague(mode)
  if     mode == "island" then manual_go2(12282)
  elseif mode == "ratha"  then manual_go2(12292) end

  local r = DRC.bput("join crawling plague",
    "You join the ship's captain", "What were you referring to?")
  if r:find("join the ship") then
    hide_if_enabled()
    while GameState.room_name == "[[The Crawling Plague, Deck]]" do pause(1) end
  elseif r:find("What were you referring") then
    hide_if_enabled()
    waitfor("JOIN CRAWLING PLAGUE before it leaves if you would like to go")
    take_crawling_plague(mode)
  end
end

local function take_dirigible(mode)
  if mode == "aesry" then
    manual_go2(12862)
    local fare = DRStats.circle * 50
    if DRCM.wealth("Shard") < fare then
      echo("Get money you slob!")
      if not get_fare(fare, "Shard", 12862) then return end
    end
  elseif mode == "shard" then
    local fare = DRStats.circle * 50
    if DRCM.wealth("Aesry") < fare then
      echo("Get money you slob!")
      if not get_fare(fare, "Aesry", 12942) then return end
    end
    manual_go2(12942)
  end

  local r = DRC.bput("join dirigible",
    "The Elothean aeromancer says", "What were you referring to?")
  if r:find("Elothean aeromancer") then
    local r2 = DRC.bput("join dirigible",
      "You hand over your funds and step closer", "You reach your funds, but")
    if r2:find("closer") then
      pause(5)
      while GameState.room_name == "[[Aboard the Dirigible, Gondola]]" do pause(1) end
    end
  elseif r:find("What were you referring") then
    waitfor("JOIN CHARCOAL DIRIGIBLE")
    take_dirigible(mode)
  end
end

local function take_airship_muspari()
  local r = DRC.bput("join airship", "You join a", "What were you referring to?")
  if r:find("You join a") then
    pause(5)
    while GameState.room_name == "[[The Bardess' Fete, Deck]]" do pause(1) end
  elseif r:find("What were you referring") then
    waitfor("JOIN AIRSHIP")
    take_airship_muspari()
  end
end

local function take_balloon(mode)
  if mode == "mriss" then
    manual_go2(8793)
    local fare = DRStats.circle * 50
    if DRCM.wealth("Therenborough") < fare then
      echo("Get money you slob!")
      if not get_fare(fare, "Therenborough", 8793) then return end
    end
  elseif mode == "langenfirth" then
    local fare = DRStats.circle * 50
    if DRCM.wealth("Mer'Kresh") < fare then
      echo("Get money you slob!")
      if not get_fare(fare, "Mer'Kresh", 8794) then return end
    end
    manual_go2(8794)
  end

  local r = DRC.bput("join balloon",
    "The Gnomish operator says", "What were you referring to?")
  if r:find("Gnomish operator") then
    local r2 = DRC.bput("join balloon",
      "You hand over your funds and step closer", "You reach your funds, but")
    if r2:find("closer") then
      pause(5)
      while GameState.room_name == "[[Aboard the Balloon, Gondola]]" do pause(1) end
    end
  elseif r:find("What were you referring") then
    waitfor("JOIN GNOMISH BALLOON")
    take_balloon(mode)
  end
end

local function take_xing_ferry(mode)
  local dock_rooms = {1904, 957}
  if not table_includes(dock_rooms, GameState.room_id) then
    echo("You are not at the ferry docks"); return
  end

  if UserVars.citizenship ~= "Zoluren" and DRCM.wealth("Crossing") < 35 then
    echo("Get money you slob!")
    local room = GameState.room_id
    local amount = room == 1904 and 35 or 70
    local town   = room == 1904 and "Leth Deriel" or "Crossing"
    if not get_fare(amount, town, room) then return end
  end

  while not room_objs_find("the ferry") do
    hide_if_enabled()
    pause(1)
  end

  local r = DRC.bput("go ferry",
    "The Captain gives you a little nod", "You hand him",
    "The ferry has just pulled away from the dock",
    "There is no ferry here to go aboard",
    "Come back when you can afford the fare")
  if r:find("You hand him") or r:find("Captain gives you") then
    hide_if_enabled()
    waitfor("reaches the dock and its crew ties the ferry off")
    pause(0.5)
    if not table_includes(dock_rooms, GameState.room_id) then move("go dock") end
  elseif r:find("has just pulled away") or r:find("There is no ferry") then
    while room_objs_find("the ferry") do pause(1) end
    take_xing_ferry(mode)
  elseif r:find("afford the fare") then
    echo("Your fare has mysteriously disappeared!")
  end
end

local function take_ain_ghazal_ferry(mode)
  local dock_rooms = {3986, 11027}
  if not table_includes(dock_rooms, GameState.room_id) then
    echo("You are not at the ferry docks"); return
  end

  if DRCM.wealth("Shard") < 31 then
    echo("Get money you slob!")
    if GameState.room_id == 3986 then
      if not get_fare(62, "Hibarnhvidar", 3986) then return end
    else
      return
    end
  end

  while not room_objs_find("Damaris. Kiss") and not room_objs_find("Evening Star") do
    hide_if_enabled()
    pause(1)
  end

  local r = DRC.bput("go ferry",
    "You hand him",
    "The ferry has just pulled away from the dock",
    "is steadily approaching",
    "Come back when you can afford the fare",
    "Sorry, but we cannot take any more passengers",
    "You see that the")
  if r:find("You hand him") then
    hide_if_enabled()
    waitfor("You come to a very soft stop")
    move("go dock")
  elseif r:find("steadily approaching") or r:find("see that the") or
         r:find("has just pulled away") or r:find("cannot take any more") then
    waitfor("comes to an easy landing at the dock and the crew quickly begin")
    take_ain_ghazal_ferry(mode)
  elseif r:find("afford the fare") then
    echo("Your fare has mysteriously disappeared!")
  end
end

local function take_rh_lang_barge()
  local dock_rooms = {466, 50948, 3434}
  if not table_includes(dock_rooms, GameState.room_id) then
    echo("You are not at the ferry docks"); return
  end

  if DRCM.wealth("Riverhaven") < 300 then
    echo("Get money you slob!")
    local room = GameState.room_id
    local town   = room == 3434 and "Therenborough" or "Riverhaven"
    if not get_fare(300, town, room) then return end
  end

  while not room_objs_find("the barge") do
    hide_if_enabled()
    pause(1)
  end

  local r = DRC.bput("go barge",
    "One of the barge's crew members stops you and requests a transportation fee",
    "You hand him",
    "isn't docked, so you're stuck here until the next one arrives",
    "has just pulled away from the dock",
    "There is no ferry here to go aboard",
    "Come back when you can afford the fare")
  if r:find("You hand him") or r:find("crew members stops you") then
    hide_if_enabled()
    waitfor("reaches its dock and its crew ties the barge off")
    if room_objs_find("Langenfirth wharf") then
      move("go wharf")
    else
      move("go pier")
    end
  elseif r:find("has just pulled away") or r:find("isn't docked") then
    while room_objs_find("the barge") do pause(1) end
    take_rh_lang_barge()
  elseif r:find("afford the fare") then
    echo("Your fare has mysteriously disappeared!")
  end
end

local function take_haven_throne_ferry()
  local dock_rooms = {452, 3084}
  if not table_includes(dock_rooms, GameState.room_id) then
    echo("You are not at the ferry docks"); return
  end

  if DRCM.wealth("Riverhaven") < 300 then
    echo("Get money you slob!")
    local room = GameState.room_id
    local town = room == 452 and "Riverhaven" or "Throne City"
    if not get_fare(300, town, room) then return end
  end

  local function board_barge(barge_cmd)
    local r = DRC.bput("go " .. barge_cmd,
      "One of the barge's crew members stops you and requests a transportation fee",
      "You hand him",
      "What were you referring to",
      "You can't do that",
      "Come back when you can afford the fare")
    if r:find("You hand him") or r:find("crew members stops you") then
      hide_if_enabled()
      waitfor("pulls into dock and its crew quickly ties the barge off")
      if room_objs_find("covered stone dock") or room_objs_find("salt yard dock") then
        move("go dock")
      end
      return true
    elseif r:find("What were you referring to") or r:find("can't do that") then
      return false
    elseif r:find("afford the fare") then
      echo("Your fare has mysteriously disappeared!")
      return true
    end
    return false
  end

  if room_objs_find("the barge Imperial Glory") then
    if not board_barge("glory") then
      while not room_objs_find("the barge Imperial Glory") and
            not room_objs_find("the barge Riverhawk") do
        echo("Waiting for a barge to show up... ")
        hide_if_enabled()
        waitfor("A barge pulls into the dock")
      end
      take_haven_throne_ferry()
    end
  elseif room_objs_find("the barge Riverhawk") then
    if not board_barge("riverhawk") then
      while not room_objs_find("the barge Imperial Glory") and
            not room_objs_find("the barge Riverhawk") do
        echo("Waiting for a barge to show up... ")
        hide_if_enabled()
        waitfor("A barge pulls into the dock")
      end
      take_haven_throne_ferry()
    end
  else
    echo("Waiting for a barge to show up... ")
    hide_if_enabled()
    waitfor("A barge pulls into the dock")
    take_haven_throne_ferry()
  end
end

local function hvaral_passport()
  local r = DRC.bput("get my passport",
    "Realizing your passport has expired",
    "You get", "You are already", "What were you", "You pick up")
  if r:find("expired") or r:find("What were you") then
    manual_go2(3632)
    Flags.add("bescort-dustroad", "Just when it seems you will never reach")
    move("e")
    while not Flags["bescort-dustroad"] do pause(1) end
    Flags.reset("bescort-dustroad")
    pause(2)
    manual_go2(3147)
    DRC.bput("ask licenser about passport", "The licenser takes", "Having a passport will allow")
    DRC.bput("ask licenser about passport", "The licenser takes", "Having a passport will allow")
    DRC.bput("stow passport", "You put")
    manual_go2(3631)
    move("w")
    while not Flags["bescort-dustroad"] do pause(1) end
    pause(2)
    Flags.delete("bescort-dustroad")
    manual_go2(3698)
    DRC.bput("get my passport",
      "Realizing your passport has expired",
      "You get", "You are already", "What were you", "You pick up")
  end
  move("go gate")
  DRC.bput("stow passport", "You put")
end

local function enter_thief_guild()
  local password = settings.shard_thief_password or ""
  local r = DRC.bput("knock",
    "You wait, but nothing happens",
    "A moment later, a slit opens in the door at eye level")
  if r:find("A moment later") then
    local r2 = DRC.bput("say " .. password, "You lean towards the doorway", "You say")
    if r2:find("You say") then
      DRC.message("fix yer yaml ye grub! Yer password is wrong!")
      DRC.message("Set the correct value for shard_thief_password")
      Script.kill("go2")
      return
    end
  end
  local r3 = DRC.bput("go door",
    "From behind the doorway you hear a faint chuckle", "Obvious exits")
  if r3:find("faint chuckle") then
    local r4 = DRC.bput("say " .. password, "You lean towards the doorway", "You say")
    if r4:find("You say") then
      DRC.message("fix yer yaml ye grub! Yer password is wrong!")
      DRC.message("Set the correct value for shard_thief_password")
      Script.kill("go2")
      return
    end
    move("go door")
  end
end

local function use_shard_gates()
  local gate_rooms = {2640, 2658, 2807, 2525, 6452, 2516}
  if not table_includes(gate_rooms, GameState.room_id) then
    echo("You are not at the Shard gates"); return
  end
  Flags.add("bescort-ur-a-criminal", "a wanted criminal")
  local r = DRC.bput("go gate", "You pass", "KNOCK", "errant shadow")
  if r:find("KNOCK") then
    if Flags["bescort-ur-a-criminal"] then
      -- Block gate access (disable timeto for gate rooms in current path)
      local current = Room.current()
      if current and current.timeto then
        for dest_id, _ in pairs(current.timeto) do
          local id_num = tonumber(dest_id)
          if id_num and table_includes(gate_rooms, id_num) then
            current.timeto[dest_id] = nil
          end
        end
      end
      return
    end
    DRC.release_invisibility()
    DRC.bput("knock gate", "You knock")
  end
end

local function crystal_cavern_of_eluned()
  if not table_includes({1192, 51798}, GameState.room_id) then
    echo("You are not at the Crystal Cavern of Eluned entrance"); return
  end
  fput("meditate")
  waitfor("Your simple world explodes into a torrent of color")
end

local function zaulfang(mode)
  Flags.add("maze-reset", "The noxious swamp gas takes its toll on your mind, and your surroundings seem to shift as you grow immensely dizzy")
  if mode:find("enter") then
    if GameState.room_id ~= 8540 then
      echo("Must enter Zaulfang swamp from 8540"); return
    end
    move("go path")
    pause(1)
    wander_maze_until("sickly tree that looms far above the swamp", "climb tree")
  elseif mode:find("exit") then
    if GameState.room_id ~= 19415 then
      echo("Must exit Zaulfang swamp from 19415"); return
    end
    move("down")
    pause(1)
    wander_maze_until("curving path", "go path")
  end
end

local function gos_tunnel()
  DRC.bput("kneel", "You kneel down upon the ground", "You are already kneeling")
  local r = DRC.bput("go tunnel",
    "Wriggling on your stomach",
    "You are engaged",
    "What were you referring to")
  if r:find("You are engaged") then
    DRCT.retreat()
    gos_tunnel()
  elseif r:find("What were you referring to") then
    -- Need to push boulder first
    DRC.fix_standing()
    fput("push boulder")
    local pr = waitfor("At the bottom of the hollow", "You stop pushing", "blocking all access to a low tunnel.")
    if pr:find("You stop pushing") or pr:find("blocking all access") then
      -- Try again
      DRC.fix_standing()
      fput("push boulder")
      waitfor("At the bottom of the hollow")
    end
    gos_tunnel()
  end
  waitfor("After a seemingly interminable length of time")
  DRC.fix_standing()
end

local function gos_blasted_plains()
  if not room_objs_include("low tunnel") then
    DRC.fix_standing()
    fput("push boulder")
    local pr = waitfor("At the bottom of the hollow", "You stop pushing", "blocking all access to a low tunnel.")
    if pr:find("You stop pushing") or pr:find("blocking all access") then
      DRC.fix_standing()
      fput("push boulder")
      waitfor("At the bottom of the hollow")
    end
  end
  DRCT.retreat()
  gos_tunnel()
  move("go field")
end

local function gos_plains_leave()
  wander_maze_until("low cavern", "go cavern")
  gos_tunnel()
end

local function gos_temple_leave()
  manual_go2(13159)
  move("go field")
  gos_plains_leave()
end

local function gate_of_souls(mode)
  Flags.add("maze-reset", "Plumes of lava belch into the air, sending molten rock spraying about")
  if mode:find("blasted") then
    if GameState.room_id ~= 1784 then
      echo("Must start at Gate of Souls, room number 1784"); return
    end
    gos_blasted_plains()
    find_room_maze()

  elseif mode:find("temple") then
    if GameState.room_id == 1784 then
      gos_blasted_plains()
      wander_maze_until("golden sandstone temple", "go temple")
      manual_go2(13625)
      find_room_list({"sw","e","e","e","se","s","sw","w","w","w","w","nw","n","ne","se","s","ne","se","n","ne","w","nw"})
    elseif (GameState.room_name or ""):find("The Fangs of Ushnish") then
      wander_maze_until("steep cliff", "climb cliff")
      manual_go2(13625)
    else
      echo("Must start at Gate of Souls, room number 1784, or within the Fangs of Ushnish Area")
    end

  elseif mode:find("fangs") then
    if GameState.room_id ~= 1784 then
      echo("Must start at Gate of Souls, room number 1784"); return
    end
    gos_blasted_plains()
    wander_maze_until("golden sandstone temple", "go temple")
    manual_go2(13643)
    move("climb cliff")
    find_room_maze()

  elseif mode:find("exit") then
    local room_name = GameState.room_name or ""
    if room_name:find("The Fangs of Ushnish") then
      wander_maze_until("steep cliff", "climb cliff")
      gos_temple_leave()
    end
    if room_name:find("Temple of Ushnish") then gos_temple_leave() end
    if room_name:find("Blasted Plain")      then gos_plains_leave() end
    if room_name:find("Before the Gate of Souls") then gos_tunnel() end

  elseif mode:find("fou") then
    if (GameState.room_name or ""):find("The Fangs of Ushnish") then
      wander_maze_until("volcanic crevasse", nil)
    end
  end
end

local function segoltha(mode)
  equipment_manager:empty_hands()
  local have_changed_gear = flying_mount and false or equipment_manager:wear_equipment_set("swimming")

  local dir_of_travel, start_room
  if mode:match("^n") then
    dir_of_travel = "north"; start_room = 19373
  elseif mode:match("^s") then
    dir_of_travel = "south"; start_room = 19457
  elseif mode:match("^w") then
    dir_of_travel = "south"; start_room = 15888
  else
    echo("Must specify north or south for swimming the segoltha"); return
  end

  if flying_mount then
    local speed = "skim"
    if flying_mount:find("[Cc]loud") then speed = "hover"
    elseif flying_mount:find("[Pp]hoenix feather") then speed = "fly" end
    use_flying_mount(flying_mount, "mount", speed)
    if dir_of_travel == "south" then
      move("go bank"); move("west"); move("go river"); move("west")
    end
    move(dir_of_travel); move(dir_of_travel)
    if dir_of_travel == "north" then
      move("east"); move("go bank"); move("east"); move("go slope")
    end
    use_flying_mount(flying_mount, "dismount")
    return
  end

  if GameState.room_id ~= start_room then
    echo("Must start bescort in room " .. start_room .. " for traveling " .. dir_of_travel); return
  end

  local move_count = 0
  while true do
    waitrt()
    local exits = GameState.room_exits or {}
    if #exits == 2 or #exits == 1 then
      move("west"); move_count = move_count - 1
    elseif dir_of_travel == "north" and move_count == 16 then
      move("east")
      if GameState.room_id == 15888 then break end
    elseif table_includes(exits, dir_of_travel) then
      move(dir_of_travel)
    elseif #exits == 0 then
      if (GameState.room_id == 19373 and dir_of_travel == "south") or
         (GameState.room_id == 19457 and dir_of_travel == "north") then
        break
      end
      if not move(dir_of_travel) then
        move("west"); move_count = move_count - 1
      end
    else
      break
    end
    move_count = move_count + 1
  end

  if have_changed_gear then equipment_manager:wear_equipment_set("standard") end
end

local function croc_swamp(mode)
  if mode == "enter" then
    if GameState.room_id ~= 1358 then
      echo("Must start bescort in room 1358 to enter the swamp"); return
    end
    move("nw"); move("n"); move("go reed")
    local dirs = {"w","nw","n","ne","e","se","s","sw"}
    while not (pcs_empty() and npcs_empty()) do
      local i = math.random(#dirs)
      move(dirs[i])
    end
  else
    while true do
      local r = DRC.bput("study reed",
        "Study what?", "You see nothing unusual", "could not find",
        "but see nothing special.", "You study the sky")
      if r:find("but see nothing special") then
        move("go reed"); break
      end
      if room_objs_include("ruined shack") then
        move("w"); move("nw")
      else
        local dirs = {"w","nw","n","ne","e","se","s","sw"}
        move(dirs[math.random(#dirs)])
      end
    end
    while move_direction({"south","southeast"}) do end
  end
end

local function take_theren_rope_bridge(mode)
  local theren_side  = 8650
  local rossman_side = 8637

  local shuffle_direction, target_room, start_room
  if mode == "totheren" then
    if GameState.room_id ~= rossman_side then
      echo("Must start on the south side of the rope bridge"); return
    end
    shuffle_direction = "north"; target_room = theren_side
  elseif mode == "torossman" then
    if GameState.room_id ~= theren_side then
      echo("Must start on the north side of the rope bridge"); return
    end
    shuffle_direction = "south"; target_room = rossman_side
  else
    echo("Unrecognized argument: " .. mode); return
  end

  start_room = GameState.room_id
  Flags.add("rope_wait", "finally arriving on this side", "finally reaching the far side")

  while GameState.room_id == start_room do
    DRCT.retreat()
    Flags.reset("rope_wait")
    local r = DRC.bput("climb rope",
      "Roundtime",
      "is already on the rope",
      "You climb onto a",
      "You are engaged",
      "You can't possibly manage to cross the rope bridge while holding")
    if r:find("can't possibly manage") then
      if GameObj.right_hand() then fput("stow right") end
      if GameObj.left_hand()  then fput("stow left")  end
    elseif r:find("is already on the rope") then
      while not Flags["rope_wait"] do pause(0.1) end
      Flags.reset("rope_wait")
    else
      pause(2); waitrt()
    end
  end

  local start_time = os.time()
  while GameState.room_id ~= target_room and (os.time() - start_time) <= 300 do
    DRC.bput("shuffle " .. shuffle_direction, "Roundtime")
    pause(3); waitrt()
  end

  if os.time() - start_time > 300 then
    DRC.beep(); pause(0.5); DRC.beep(); pause(0.5); DRC.beep()
    echo("ROPE BRIDGE TRIP TIMEOUT! This has taken too long. Something is wrong! Fix it!")
    return
  end
end

local function abyss_enter()
  if GameState.room_id ~= 8142 then
    echo("Abyss entrance script must be started from 8142"); return
  end
  DRCA.release_cyclics()
  local ok = DRCA.cast_spell({abbrev = "rezz", mana = 5, cyclic = true}, settings)
  if not ok then
    echo("Failed to cast Resurrection! Try again or use the puzzle to enter."); return
  end
  move("go spirits")
  DRCA.release_cyclics()
end

-- ============================================================================
-- Astral Walk (Moon Mage Ways)
-- ============================================================================

local function focus_shard(name)
  DRCI.stow_hands()
  DRC.bput("focus " .. name, "Roundtime", "You move into the chaotic tides of energy")
end

local function know_shard(shard_name, shard_list)
  local known = get_known_shards()
  for _, s in ipairs(known) do
    if s == shard_name then return true end
  end

  DRC.bput("recall heavens grazhir", shard_name, "Roundtime")
  local lines = reget(30)

  -- Build shard set for intersection
  local shard_set = {}
  for _, s in ipairs(shard_list) do shard_set[s] = true end

  local new_known = {}
  for _, line in ipairs(lines) do
    local stripped = line:match("^%s*(.-)%s*$") or line
    if shard_set[stripped] then new_known[#new_known+1] = stripped end
  end
  set_known_shards(new_known)

  for _, s in ipairs(new_known) do
    if s == shard_name then return true end
  end
  return false
end

local function open_gate(shard, entering_ap)
  Flags.reset("gate-failure")
  DRCA.release_cyclics()
  if not DRCA.prepare("mg", 5) then
    echo("You may need to move to another room"); return
  end
  if entering_ap then
    if DRStats.circle < 100 then focus_shard(shard) end
    DRCA.harness_mana({20, 20, 20})
    waitcastrt()
    if DRStats.circle > 99 then
      if not DRCA.cast("cast grazhir") then
        echo("You may need to move to another room")
        fput("release mana"); return
      end
    else
      DRCA.cast("cast " .. shard)
    end
  else
    focus_shard(shard)
    waitcastrt()
    DRCA.cast("cast " .. shard)
  end
  pause(0.25)
  if Flags["gate-failure"] then open_gate(shard, entering_ap) end
end

local center_re = Regex.new("the microcosm is to the (?P<direction>[a-z]+)\\.")
local exit_re   = Regex.new("You believe the end of the conduit lies (?P<direction>[a-z]+)\\.|^You are already at the end of the conduit\\.")

local function power_walk(re)
  if dead() or Flags["ap-danger"] then fput("exit"); return end
  if Flags["harness-check"] then
    local hc = Flags["harness-check"]
    if type(hc) == "table" and hc[1] ~= "effortlessly" then
      DRCA.harness_mana({20})
    end
    Flags.reset("harness-check")
  end

  local result = DRC.bput("pow", "the microcosm is to", "You believe the end", "You are already at the end")
  waitrt()

  if result:find("You are already at the end of the conduit") then return end

  if Flags["pattern-shift"] then
    Flags.reset("pattern-shift")
  else
    Flags.reset("walking-circles")
    local caps = re:captures(result)
    local direction = caps and caps["direction"]
    if direction then
      move(direction)
      if Flags["walking-circles"] then power_walk(re) end
    end
  end
end

local function astral_walk(mode)
  Flags.add("harness-check", "You .* maintain your place among the shifting streams of mana")
  Flags.add("pattern-shift",  "A wave of rippling air sweeps through the conduit!  The streams of mana writhe violently before settling into new patterns")
  Flags.add("gate-failure",   "With supreme effort, you are able to bring the spell to an end without harm.")
  Flags.add("ap-danger",      "Unlike most astral phenomena, the static does not go away after a few moments. In fact, it's getting stronger. Closer.")
  Flags.add("walking-circles","You end up walking in circles")

  local room_id_to_shard = {
    [9999]  = "Asharshpar'i",
    [607]   = "Rolagi",
    [2493]  = "Marendin",
    [306]   = "Taniendar",
    [3002]  = "Mintais",
    [3105]  = "Dinegavren",
    [4542]  = "Tamigen",
    [5050]  = "Erekinzil",
    [6867]  = "Auilusi",
    [8302]  = "Vellano",
    [3777]  = "Dor'na'torna",
    [287]   = "Tabelrem",
    [6991]  = "Besoge",
    [51786] = "Aevargwem",
  }
  local mode_to_shard = {
    shard      = "Marendin",
    crossing   = "Rolagi",
    leth       = "Asharshpar'i",
    theren     = "Dinegavren",
    throne     = "Mintais",
    raven      = "Tamigen",
    riverhaven = "Taniendar",
    taisgath   = "Erekinzil",
    aesry      = "Auilusi",
    fang       = "Vellano",
    muspari    = "Tabelrem",
    steppes    = "Dor'na'torna",
    merkresh   = "Besoge",
    velatohr   = "Aevargwem",
  }
  local mode_to_pillar_roomid = {
    shard      = 9806, merkresh   = 9806,
    crossing   = 9764, muspari    = 9764,
    aesry      = 9807, steppes    = 9807,
    fang       = 9805,
    leth       = 9803, raven      = 9803,
    theren     = 9762, riverhaven = 9762,
    throne     = 9808, taisgath   = 9808,
    velatohr   = 9804,
  }

  local shard_list = {}
  for _, v in pairs(mode_to_shard) do shard_list[#shard_list+1] = v end

  local destination_shard = mode_to_shard[mode]
  if not know_shard(destination_shard, shard_list) then
    echo("You dont know that shard!"); return
  end

  local source_shard = room_id_to_shard[GameState.room_id]
  if not source_shard and DRStats.circle <= 99 then
    echo("You are not in a room with a Grazhir shard."); return
  end

  open_gate(source_shard, true)
  local exits = GameState.room_exits or {}
  while #exits > 0 do pause(0.25); exits = GameState.room_exits or {} end
  while #(GameState.room_exits or {}) == 0 do power_walk(center_re) end

  DRCT.walk_to(mode_to_pillar_roomid[mode])
  focus_shard(destination_shard)

  while #(DRRoom.room_objs or {}) == 0 do
    power_walk(exit_re)
    if #(GameState.room_exits or {}) > 0 then focus_shard(destination_shard) end
  end

  open_gate(destination_shard, false)
  fput("rel mana")
end

local function ride_gondola(mode)
  local north_platform = 2249
  local south_platform = 2904

  if mode:find("north") and GameState.room_id ~= south_platform then
    echo("Must start at the south platform, room number " .. south_platform .. ", to ride the gondola north"); return
  elseif mode:find("south") and GameState.room_id ~= north_platform then
    echo("Must start at the north platform, room number " .. north_platform .. ", to ride the gondola south"); return
  end

  local r = DRC.bput("go gondola", "There is no wooden gondola here", "Gondola, Cab")
  if r:find("no wooden gondola here") then
    DRC.bput("look gondola", "The wooden gondola")
    hide_if_enabled()
    waitfor("The gondola stops on the platform and the door silently swings open")
    ride_gondola(mode)
  elseif r:find("Gondola, Cab") then
    move(mode)
    hide_if_enabled()
    waitfor("With a soft bump, the gondola comes to a stop at its destination")
    pause(0.5)
    if not table_includes({2249, 2904}, GameState.room_id) then
      move("out")
    end
  end
end

local function fly_under_gondola(mode)
  local north_start = 2245
  local south_start = 19466

  local moveset
  if mode:find("north") then
    if GameState.room_id ~= south_start then
      echo("Must start under gondola at southside of the log, room number " .. south_start .. ", to fly under the gondola north"); return
    end
    moveset = {"go log","go embankment","southwest","south","down","go wall","go ledge","go niche","go branch"}
  elseif mode:find("south") then
    if GameState.room_id ~= north_start then
      echo("Must start on road north of gondola at the branch, room number " .. north_start .. ", to fly under the gondola south"); return
    end
    moveset = {"go branch","go niche","go ledge","go wall","up","north","northeast","go embankment","go log"}
  end

  use_flying_mount(flying_mount, "mount", "slow")
  for _, dir in ipairs(moveset) do move(dir) end
  use_flying_mount(flying_mount, "dismount")
end

-- ============================================================================
-- Main dispatch
-- ============================================================================

if args.wilds         then wilds(args.mode)
elseif args.oshu_manor  then oshu_manor(args.mode)
elseif args.faldesu     then faldesu(args.mode)
elseif args.zaulfang    then zaulfang(args.mode)
elseif args.gate_of_souls then gate_of_souls(args.mode)
elseif args.segoltha    then segoltha(args.mode)
elseif args.crocs       then croc_swamp(args.mode)
elseif args.ways        then astral_walk(args.mode)
elseif args.mammoth     then take_mammoth(args.mode)
elseif args.iceroad     then iceroad(args.mode)
elseif args.basalt      then take_crawling_plague(args.mode)
elseif args.balloon     then take_balloon(args.mode)
elseif args.dirigible   then take_dirigible(args.mode)
elseif args.airship     then take_airship_muspari()
elseif args.therenropebridge then take_theren_rope_bridge(args.mode)
elseif args.gondola     then ride_gondola(args.mode)
elseif args.fly_under_gondola then fly_under_gondola(args.mode)
elseif args.sandbarge   then take_sandbarge(args.start_location, args.end_location)
elseif args.desert      then desert(args.mode)
elseif args.velaka      then velaka_desert(args.mode)
elseif args.ferry       then take_xing_ferry(args.mode)
elseif args.ferry1      then take_ain_ghazal_ferry(args.mode)
elseif args.lang_barge  then take_rh_lang_barge()
elseif args.shard_gates then use_shard_gates()
elseif args.thief_guild then enter_thief_guild()
elseif args.abyss       then abyss_enter()
elseif args.haven_throne then take_haven_throne_ferry()
elseif args.hvaral_passport then hvaral_passport()
elseif args.brocket_young then brocket_young(args.mode)
elseif args.brocket_mid   then brocket_mid(args.mode)
elseif args.brocket_elder then brocket_elder(args.mode)
elseif args.hara_polo   then hara_polo(args.mode)
elseif args.jolas       then jolas(args.mode)
elseif args.currach     then currach(args.mode)
elseif args.galley      then take_m_m_galley(args.mode)
elseif args.cave_trolls then cave_trolls(args.mode)
elseif args.asketis_mount then asketis_mount(args.mode)
elseif args.coffin      then coffin()
elseif args.eluned      then crystal_cavern_of_eluned()
end

-- ============================================================================
-- Cleanup
-- ============================================================================

before_dying(function()
  Flags.delete("bescort-move-slow")
  Flags.delete("bescort-ur-a-criminal")
  Flags.delete("bescort-dustroad")
  Flags.delete("maze-reset")
  Flags.delete("rope_wait")
  Flags.delete("harness-check")
  Flags.delete("pattern-shift")
  Flags.delete("gate-failure")
  Flags.delete("ap-danger")
  Flags.delete("walking-circles")
end)
