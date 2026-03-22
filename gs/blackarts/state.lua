--- @module blackarts.state
-- Shared runtime state singleton — initialized in init.lua, shared by all modules.
-- Maps to BlackArts::Data from BlackArts.lic v3.12.x

local M = {}

-- Container sacks indexed by role: "herb", "reagent", "default"
M.sacks = {}

-- Cauldron/alembic object currently in use
M.cauldron = nil

-- Bank note object (promissory note / scrip / chit)
M.note = nil

-- Shadow illusion state
M.shadow_item      = nil
M.shadow_container = nil

-- Demon illusion state (minor demon NPC id string)
M.demon_id = nil

-- Flags
M.need_empty_flask = false
M.mortar_check     = true   -- first grind checks for old-style mortar

-- Navigation state
M.start_room   = nil        -- room to return to after distill/extract detour
M.start_town   = nil        -- town we started in
M.visited_towns = {}        -- towns visited this cycle

-- Hunting / foraging state
M.skin        = nil
M.skin_number = 0
M.creature    = nil
M.guild_skill = nil
M.ranks       = nil         -- current guild ranks for active skill

-- Ingredient tracking
M.ingredient_count = {}     -- {obj_id -> remaining_uses}
M.locations        = {}     -- cached {starting_room, item, room, travel} entries

-- Banking
M.note_withdrawal = 50000
M.note_refresh    = 5000

-- Timers
M.last_alchemy_buy = 0      -- os.time() when we last bought elusive reagents

-- Guild travel groups (room IDs for nearest-town lookup)
-- west: FWI(3668), Landing(228), Solhaven(1438), Icemule(2300)
M.west_guilds = {3668, 228, 1438, 2300}
-- east: FWI(3668), Ta'Illistim(188), Ta'Vaalor(3519)
M.east_guilds = {3668, 188, 3519}

-- Boundary room IDs — path must not cross these (no mine-cart rides)
M.boundaries = {1014, 991, 20239}

-- Rooms where foraging is disabled
M.no_forage = {13918, 13923, 23525, 13227}

-- Regex patterns (initialised in init.lua after Regex is available)
M.get_regex      = nil
M.put_regex      = nil
M.forage_result  = nil
M.forage_injury  = nil
M.sea_water_flask = nil
M.sea_water_vial  = nil
M.bundled_herb    = nil

-- Bigshot profile directory path
M.profile_dir = nil

return M
