--- @revenant-script
--- name: shatteredmap
--- version: 1.8.5
--- author: elanthia-online
--- game: gs
--- description: Load GSIV Prime mapdb while playing Shattered, then hot-patch Shattered-specific changes
--- tags: map,shattered,gsf,nexus
--- @lic-certified: complete 2026-03-18
---
--- Changelog (from Lich5):
---   v1.8.5 (2026-01-28): move SG town tag below mast climb
---   v1.8.4 (2025-11-20): bugfix for wayside garret
---   v1.8.3 (2025-11-20): bugfix in nexus WL entrance tracking logic
---   v1.8.2 (2025-11-19): bugfix in graveyard gating logic
---   v1.8.1 (2025-11-19): bugfix in graveyard due to slight difference between prime/shattered crypt
---   v1.8.0 (2025-11-18): add WL graveyard gate fix
---   v1.7.2 (2025-11-07): fix for Teras routing for Nexus
---   v1.7.1 (2025-11-05): fix Darkstone Castle entrance, remove IMT Frozen Brambles link
---   v1.7.0 (2025-10-20): add urchin fixes, additional Ta'Illistim keep corrections
---   v1.6.1 (2025-10-02): fix nexus entrance to new SG location
---   v1.6.0 (2025-10-01): Sailor's Grief nexus logic
---   v1.5.1 (2025-01-20): fix Solhaven locksmith pool link
---   v1.5.0 (2024-10-20): Hinterwilds changes
---   v1.4.0 (2024-09-19): Ta'Illistim bank/dais corrections
---   v1.3.0 (2024-09-13): removal of Talondown missing entrances
---   v1.2.0 (2024-09-13): add Burrow Way avoidance (WL Tunnels)
---   v1.1.4 (2024-09-12): increase Nexus exit timeto's to prevent pathing issues
---   v1.0.0 (2024-09-11): initial release
---
--- Usage:
---   Run via ;autostart add --global shatteredmap
---   ;shatteredmap help   - show help
---
--- NOTE: This is a map-patching script specific to Shattered (GSF) server.
--- It downloads the Prime (GSIV) map database, then patches Shattered-specific
--- room modifications (nexus, portals, player shops, tunnels, etc.) into memory.
---
--- Revenant conversion notes:
---   - Map mutation uses Map.set_wayto/set_timeto/set_tags/etc (direct Rust writes)
---   - Function-valued wayto (StringProc) registered in _FN_WAYTO registry
---   - Map.go2() overridden in Lua to dispatch _FN_WAYTO functions for sentinel edges
---   - Nexus exits: only WL (318) has a static timeto (5.0); all others are nil.
---     This prevents incorrect cross-town routing through the nexus.
---     The pathfinder can route nexus↔WL; non-WL nexus exits are Lua-function-only.
---   - Hinterwilds caravan: timeto-only conditional (nil static = unroutable by default)
---   - Map.load() now accepts relative paths (resolved from scripts_dir)
---   - Map.reload() implemented as Lua wrapper tracking last Map.load() call
---   - landing_graveyard_gate() uses Map.ids_from_uid(18002/18003)

-- Only run on Shattered server
if GameState.game ~= "GSF" then
    echo("This script is only for the Shattered (GSF) server.")
    return
end

-- Handle help
if Script.vars[1] and Script.vars[1]:lower() == "help" then
    respond("Run this script to load your existing Prime mapdb.")
    respond("It will then patch in-memory shattered specific changes.")
    respond("This includes the following:")
    respond("  * Nexus & Wayside Inn Adjustments")
    respond("  * Premium portals and ticket system")
    respond("  * Playershops disconnection and mapping of Mitch's shop")
    respond("  * Removes access to Burrow's Way (WL Tunnels)")
    respond("  * Removal of missing Talondown entrances")
    respond("  * Ta'Illistim bank & dais updates")
    respond("  * Hinterwilds changes")
    respond("  * Landing graveyard gate logic")
    respond("  * Maaghara Tower exit routing")
    respond("")
    respond("Run as ;" .. Script.name .. " and enjoy!")
    respond("")
    respond("If you need to go back to previous Shattered mapdb, use:")
    respond("  ;e Map.reload()")
    return
end

-- Register cleanup on exit (Revenant manages game context internally)
before_dying(function() end)

-- Room ID constants for synthetic rooms unique to Shattered
local NEW_NEXUS   = 66666
local NEW_SMITHY  = 66667
local MITCH_SHOP  = 66668
local MITCH_NORTH = 66669
local MITCH_EAST  = 66670
local BANK_LOBBY  = 66671

-- ============================================================
-- Function-valued wayto registry and Map.go2() override
--
-- Lich5 used StringProc objects stored directly in Room.wayto.
-- Revenant's Rust pathfinder only supports string commands, so:
--   1. Register Lua functions in _FN_WAYTO[from_id][to_id_str]
--   2. Store sentinel "__fn:FROM:TO" as the command in the Rust map
--   3. Map.go2() override detects sentinels and dispatches to Lua functions
--
-- The registry is kept alive after script exit via the Map.go2 closure.
-- ============================================================
local _FN_WAYTO = {}   -- [from_id][to_id_str] = lua_function

local _orig_find_path = Map.find_path

-- Override Map.go2 to support function-valued wayto (sentinels).
-- Installed globally in Map table; persists for the session.
Map.go2 = function(dest)
    local dest_id
    if type(dest) == "number" then
        dest_id = math.floor(dest)
    elseif type(dest) == "string" then
        dest_id = tonumber(dest)
        if not dest_id then
            local r = Map.find_room(dest)
            if r then dest_id = r.id end
        end
    end
    if not dest_id then return false end

    local from_id = Map.current_room()
    if not from_id then return false end
    if from_id == dest_id then return true end

    local cmds = _orig_find_path(from_id, dest_id)
    if not cmds or #cmds == 0 then return false end

    for _, cmd in ipairs(cmds) do
        if cmd:match("^__fn:") then
            local from_str, to_str = cmd:match("^__fn:(%d+):(%d+)$")
            local fn_from = tonumber(from_str)
            local fn_to   = tonumber(to_str)
            if fn_from and fn_to then
                local fn_tbl = _FN_WAYTO[fn_from]
                if fn_tbl and fn_tbl[tostring(fn_to)] then
                    fn_tbl[tostring(fn_to)]()
                else
                    echo("[shatteredmap] Map.go2: no fn for __fn:" .. fn_from .. ":" .. fn_to)
                end
            end
        else
            move(cmd)
        end
    end

    return Map.current_room() == dest_id
end

-- Track last Map.load path for Map.reload() support.
local _map_reload_path = nil
local _orig_map_load   = Map.load
Map.load = function(path)
    _map_reload_path = path
    return _orig_map_load(path)
end
Map.reload = function()
    if _map_reload_path then
        echo("[shatteredmap] Reloading map from: " .. _map_reload_path)
        return Map.load(_map_reload_path)
    else
        echo("[shatteredmap] Map.reload(): no path tracked. Load via Map.load(path) first.")
        return false
    end
end

-- ============================================================
-- Helper: register a function-valued wayto edge
--   from_id        — source room ID
--   to_id          — destination room ID
--   fn             — Lua function to call when this edge is traversed by go2
--   static_timeto  — numeric weight for Dijkstra pathfinder (nil = impassable)
-- ============================================================
local function register_fn_wayto(from_id, to_id, fn, static_timeto)
    local to_str = tostring(to_id)
    _FN_WAYTO[from_id] = _FN_WAYTO[from_id] or {}
    _FN_WAYTO[from_id][to_str] = fn
    -- Sentinel command in Rust map so Dijkstra can discover and traverse this edge
    Map.set_wayto(from_id, to_id, "__fn:" .. from_id .. ":" .. to_id)
    if static_timeto ~= nil then
        Map.set_timeto(from_id, to_id, static_timeto)
    end
end

-- ============================================================
-- Route mutation helpers (all use Rust write APIs — mutations persist)
-- ============================================================

local function remove_route(from_id, to_id)
    Map.delete_wayto(from_id, to_id)
end

local function add_route(from_id, to_id, command, time)
    Map.set_wayto(from_id, to_id, command)
    Map.set_timeto(from_id, to_id, time or 0.2)
end

local function remove_tag(room_id, tag)
    local room = Map.find_room(room_id)
    if room and room.tags then
        local new_tags = {}
        for _, t in ipairs(room.tags) do
            if t ~= tag then table.insert(new_tags, t) end
        end
        Map.set_tags(room_id, new_tags)
    end
end

local function add_tag(room_id, tag)
    local room = Map.find_room(room_id)
    local tags = (room and room.tags) or {}
    for _, t in ipairs(tags) do
        if t == tag then return end  -- already present
    end
    local new_tags = {}
    for _, t in ipairs(tags) do table.insert(new_tags, t) end
    table.insert(new_tags, tag)
    Map.set_tags(room_id, new_tags)
end

local function set_tags(room_id, tags)
    Map.set_tags(room_id, tags)
end

local function set_description(room_id, desc)
    Map.set_description(room_id, desc)
end

local function set_paths(room_id, paths)
    Map.set_paths(room_id, paths)
end

local function set_image(room_id, image, coords)
    Map.set_image(room_id, image, coords)
end

-- Fully replace a room's routing table (clears existing, then sets new ones).
-- All values must be strings (use register_fn_wayto for Lua function edges).
local function set_routes(room_id, wayto, timeto)
    Map.clear_routes(room_id)
    for to_str, cmd in pairs(wayto) do
        local to_id = tonumber(to_str)
        if to_id then Map.set_wayto(room_id, to_id, cmd) end
    end
    for to_str, val in pairs(timeto or {}) do
        local to_id = tonumber(to_str)
        if to_id and type(val) == "number" then
            Map.set_timeto(room_id, to_id, val)
        end
    end
end

-- ============================================================
-- Load Prime GSIV map database
--
-- Lich5: spoofs XMLData.game to "GSIV", runs repository script,
--        restores to "GSF", then scans DATA_DIR/GSIV/ for the
--        downloaded map file and loads it via Map.load_json/dat/xml.
--
-- Revenant: game context is managed internally; we run the repository
--           script directly. The repository script downloads to data/GSIV/
--           (relative to scripts_dir). After it finishes we find and
--           load the map file ourselves using Map.load() (which now
--           accepts relative paths resolved from scripts_dir).
-- ============================================================
local function load_prime_mapdb()
    echo("[shatteredmap] Loading Prime GSIV map database...")
    wait_until(function() return Map.room_count() > 0 end)

    -- Create data/GSIV directory if not present
    if not File.exists("data/GSIV") then
        File.mkdir("data/GSIV")
    end

    echo("[shatteredmap] Downloading GSIV map data via repository script...")
    Script.run("repository", "download-mapdb")
    wait_while(function() return running("repository") end)

    -- Find the downloaded map file and load it.
    -- Files are named map-NNNN.json (preferred), map-NNNN.dat, or map-NNNN.xml.
    local files, err = File.list("data/GSIV")
    if not files then
        respond("[shatteredmap] Error: could not list data/GSIV: " .. (err or "unknown"))
        return
    end

    -- Sort descending (highest map number = newest) and filter to map files
    local map_files = {}
    for _, f in ipairs(files) do
        if f:match("^map%-%d+%.%a+$") then
            table.insert(map_files, f)
        end
    end
    table.sort(map_files, function(a, b) return a > b end)

    -- Prefer JSON, then XML, then DAT
    local loaded = false
    for _, ext in ipairs({"%.json$", "%.xml$", "%.dat$"}) do
        for _, f in ipairs(map_files) do
            if f:match(ext) then
                local path = "data/GSIV/" .. f
                echo("[shatteredmap] Loading map: " .. path)
                if Map.load(path) then
                    loaded = true
                    break
                end
            end
        end
        if loaded then break end
    end

    if not loaded then
        respond("[shatteredmap] Warning: no map file found in data/GSIV. Using existing map.")
    end

    wait_until(function() return Map.room_count() > 0 end)
    echo("[shatteredmap] Prime map loaded (" .. Map.room_count() .. " rooms).")
end

-- ============================================================
-- Create synthetic rooms unique to Shattered
-- ============================================================
local function create_nexus_rooms()
    echo("[shatteredmap] Creating Shattered Nexus rooms...")

    local nexus_image = "GSF-Shattered-Nexus-1609037072.png"

    -- Shattered Nexus (GSF LichID# 20239) — room 66666
    Map.new(NEW_NEXUS, {
        title = "[Shattered Nexus]",
        description = "The vastness of space stretches in all directions, with no hope to find any escape other than the rift that lies outward.  The frigid rough terrain on this patch of land is the only stable ground that can be settled on.",
        paths = {"Obvious paths: out"},
        uid = {7199},
        tags = {"nexus"},
        image = nexus_image,
        image_coords = {350, 285, 386, 322},
        location = "the town of Wehnimer's Landing",
    })

    -- The Mobile Smithy (GSF LichID# 20254) — room 66667
    Map.new(NEW_SMITHY, {
        title = "[The Mobile Smithy]",
        description = "At the back of the wagon is a small hearth filled with brightly burning charcoal.  A large bellow hangs out an opening in the side which is controlled by a mechanical chain overhead.  Standing near a wide cooling tank is an invar anvil with a number of tongs and forging hammers leaning against it.  Slabs of rhimar are placed throughout the wagon to help with the immense heat in the cramped space.",
        paths = {"Obvious exits: out"},
        uid = {9181317},
        tags = {},
        image_coords = {574, 287, 610, 323},
        location = "Elanthia",
    })
    add_route(NEW_SMITHY, NEW_NEXUS, "out", 0.2)

    echo("[shatteredmap] Nexus rooms created.")
end

-- ============================================================
-- Patch Shattered Nexus wayto/timeto
--
-- Nexus design on Shattered:
--   - Each town has a rift that leads to the nexus ("go rift")
--   - From the nexus, "out" returns you to the town you entered from
--   - The nexus also has a smithy wagon and the Wayside Inn lodge
--
-- Routing approach in Revenant:
--   - Town→nexus: function wayto ("go rift") that records origin in UserVars
--   - Nexus→WL (318): static timeto 5.0 so Dijkstra can route nexus↔WL area
--   - Nexus→other towns: nil timeto (impassable via Dijkstra).
--     This is correct: you CANNOT exit the nexus to a different town than you
--     entered from. The Lua function handles the actual "out" command at runtime.
--   - Nexus→smithy, nexus→wayside-inn: plain static routes
-- ============================================================
local function create_nexus_routes()
    echo("[shatteredmap] Patching Shattered Nexus routes...")

    -- Nexus exits: all use the game command "out".
    -- Only WL (318) gets a static timeto — it is the default exit.
    -- All other town exits are nil (impassable via Dijkstra) because you can
    -- only exit to the town you entered from. The Lua function handles navigation.
    local nexus_towns = {
        {id = 27,    name = "Ta'Illistim"},
        {id = 318,   name = "Wehnimer's Landing", is_default = true},
        {id = 1453,  name = "Solhaven"},
        {id = 1933,  name = "Kharam-Dzu"},
        {id = 2302,  name = "Icemule Trace"},
        {id = 3542,  name = "Ta'Vaalor"},
        {id = 9403,  name = "Zul Logoth"},
        {id = 10852, name = "River's Rest"},
        {id = 28813, name = "Kraken's Fall"},
        {id = 29870, name = "Hinterwilds"},
        {id = 35593, name = "Sailor's Grief"},
    }

    for _, town in ipairs(nexus_towns) do
        local town_id   = town.id
        local to_str    = tostring(town_id)
        -- Static timeto: 5.0 for WL (default exit); nil for all others
        local s_timeto  = town.is_default and 5.0 or nil

        -- Nexus → town: Lua function calls move("out") and clears tracking variable
        register_fn_wayto(NEW_NEXUS, town_id, function()
            move("out")
            UserVars.shattered_nexus_exit = nil
        end, s_timeto)

        -- Town → nexus: Lua function calls move("go rift") and records which town
        register_fn_wayto(town_id, NEW_NEXUS, function()
            move("go rift")
            UserVars.shattered_nexus_exit = to_str
        end, 0.2)
    end

    -- Nexus → smithy (plain static route)
    add_route(NEW_NEXUS, NEW_SMITHY, "go wagon", 0.2)

    -- Nexus → Wayside Inn dining room (room 3619)
    add_route(NEW_NEXUS, 3619, "go lodge", 0.2)

    -- Teras routing fix (room 1932): set correct static timeto for Teras adjacents
    Map.set_timeto(1932, 1933, 0.2)
    Map.set_timeto(1932, 1898, 0.2)
    Map.set_timeto(1932, 1931, 0.2)
    Map.set_timeto(1932, 1944, 0.2)

    echo("[shatteredmap] Nexus routes patched.")
end

-- ============================================================
-- Wayside Inn tag/route patching (rooms 3619, 9652, 14627)
-- ============================================================
local function wayside_inn_modifications()
    echo("[shatteredmap] Patching Wayside Inn rooms...")
    local nexus_image = "GSF-Shattered-Nexus-1609037072.png"

    -- Wayside Inn, Dining Room (GSF LichID# 20726) — room 3619
    add_route(3619, NEW_NEXUS, "out", 0.2)
    remove_route(3619, 221)
    remove_route(3619, 30708)
    set_image(3619, nexus_image, {135, 287, 173, 322})
    set_tags(3619, {"nexus room", "no forageables"})

    -- Wayside Inn, Chamber (GSF LichID# 20728) — room 9652
    remove_route(9652, 26905)
    remove_route(9652, 31558)
    set_description(9652, "Tables and chairs of all shapes, sizes and states of disrepair fill this large, undecorated chamber.")
    set_image(9652, nexus_image, {135, 381, 173, 417})
    set_tags(9652, {"nexus room"})

    -- Wayside Inn, Garret (GSF LichID# 20727) — room 14627
    remove_route(14627, 30708)
    remove_route(14627, 223)
    set_image(14627, nexus_image, {136, 99, 172, 135})
    set_tags(14627, {"locksmith pool", "meta:boxpool:npc:pale halfling worker", "meta:boxpool:table:sturdy wooden table", "meta:trashcan:simple modwir wastebasket", "nexus room"})

    -- Wehnimer's Outside Gate — disconnect from wayside
    remove_route(221, 3619)

    echo("[shatteredmap] Wayside Inn patching complete.")
end

-- ============================================================
-- Premium Portals system
-- Lich5: StringProc buying ticket + going through portal.
-- Revenant: Lua closure for ticket purchase; nil static timeto (opt-in routing).
-- ============================================================
local function premium_portals()
    echo("[shatteredmap] Patching Premium Portal routes...")
    local portal_main = 30595

    local function premium_ticket_wayto()
        -- Check for existing transport ticket in hands
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_ticket  = false
        local ticket_container = nil

        if rh and rh.name and rh.name:find("transport ticket") then
            has_ticket = true
        elseif lh and lh.name and lh.name:find("transport ticket") then
            has_ticket = true
        end

        if not has_ticket then
            local inv = GameObj.inv()
            for _, item in ipairs(inv) do
                if item.contents then
                    for _, sub in ipairs(item.contents) do
                        if sub.name and sub.name:find("transport ticket") then
                            has_ticket      = true
                            ticket_container = item
                            fput("get #" .. sub.id)
                            waitrt()
                            break
                        end
                    end
                end
                if has_ticket then break end
            end
        end

        if not has_ticket then
            -- Buy a ticket
            local line = dothistimeout("get ticket", 5,
                "young attendant hands you",
                "what%?",
                "remove a silver%-sheened transport ticket",
                "already have a valid",
                "for the %d+ cost")
            if line and line:find("already have") then
                fput("get my transport ticket")
                waitrt()
            end
        end

        move("go portal")

        if ticket_container then
            fput("put my ticket in #" .. ticket_container.id)
            waitrt()
        end
    end

    local portal_rooms = {
        {transport = 20779, portal_exit = 30601, name = "Teras Isle"},
        {transport = 20768, portal_exit = 30604, name = "River's Rest"},
        {transport = 20720, portal_exit = 30602, name = "Solhaven"},
        {transport = 20759, portal_exit = 30597, name = "Icemule"},
        {transport = 20699, portal_exit = 30598, name = "Ta'Illistim"},
        {transport = 20688, portal_exit = 30600, name = "Zul Logoth"},
        {transport = 20709, portal_exit = 30599, name = "Ta'Vaalor"},
        {transport = 20736, portal_exit = 30603, name = "Wehnimer's Landing"},
        {transport = 28989, portal_exit = 30596, name = "Kraken's Fall"},
    }

    for _, p in ipairs(portal_rooms) do
        -- nil static timeto: portals not Dijkstra-routed by default (opt-in via UserVars)
        register_fn_wayto(p.transport, portal_main, premium_ticket_wayto, nil)
        -- Reverse: portal exit → transport room
        add_route(p.portal_exit, p.transport, "go portal", 0.2)
    end

    echo("[shatteredmap] Premium portal routes patched.")
end

-- ============================================================
-- Player shop disconnection + Mitch's Outfitting (WL)
-- ============================================================
local function playershop_modifications()
    echo("[shatteredmap] Patching player shop routes...")

    local shop_disconnects = {
        {3520, 10441},   -- Ta'Vaalor
        {22196, 10458},  -- Ta'Vaalor
        {20747, 10444},  -- Ta'Vaalor
        {33, 641},       -- Ta'Illistim
        {1001, 9423},    -- Zul Logoth
        {3655, 3868},    -- Mist Harbor
        {1963, 1973},    -- Teras
        {10868, 10873},  -- River's Rest
        {2360, 2371},    -- Icemule Trace
        {2380, 2378},
        {2391, 3445},
        {2396, 3439},
        {2418, 2483},
        {2459, 2476},
        {2307, 2309},
        {1441, 9008},    -- Solhaven
    }

    for _, pair in ipairs(shop_disconnects) do
        remove_route(pair[1], pair[2])
    end

    -- Create Mitch's Outfitting (3-room WL player shop)
    Map.new(MITCH_SHOP, {
        title = "[Mitch's Outfitting]",
        description = "Beneath an uneven wooden ceiling, a rainbow colored flag hangs on one of the plain wooden walls.  A gold-leafed mistwood cabinet sits in one corner while a worn rug rests on the wooden floor.",
        paths = {"Obvious exits: north, east, out"},
        uid = {632089},
        tags = {"mitch"},
        location = "Wehnimer's Landing",
    })
    add_route(MITCH_SHOP, 337,         "out",   0.2)
    add_route(MITCH_SHOP, MITCH_NORTH, "north", 0.2)
    add_route(MITCH_SHOP, MITCH_EAST,  "east",  0.2)

    Map.new(MITCH_NORTH, {
        title = "[Mitch's Outfitting]",
        description = "Beneath an uneven wooden ceiling, a tattered merchant permit hangs on one of the plain wooden walls.  A gold-leafed mistwood cabinet sits in one corner while a worn rug rests on the wooden floor.",
        paths = {"Obvious exits: south"},
        uid = {632091},
        tags = {},
        location = "Wehnimer's Landing",
    })
    add_route(MITCH_NORTH, MITCH_SHOP, "south", 0.2)

    Map.new(MITCH_EAST, {
        title = "[Mitch's Outfitting]",
        description = "Beneath an uneven wooden ceiling, a tattered merchant permit hangs on one of the plain wooden walls.  A gold-leafed mistwood cabinet sits in one corner while a worn rug rests on the wooden floor.",
        paths = {"Obvious exits: west"},
        uid = {632090},
        tags = {},
        location = "Wehnimer's Landing",
    })
    add_route(MITCH_EAST, MITCH_SHOP, "west", 0.2)

    -- Connect room 337 (WL alley) to Mitch's entrance
    add_route(337, MITCH_SHOP, "go fieldstone shop", 0.2)
    add_tag(337, "shop")
    add_tag(337, "shops")

    echo("[shatteredmap] Player shop routes patched.")
end

-- ============================================================
-- Landing tunnels — remove Burrow Way (WL underground network)
-- ============================================================
local function landing_tunnels()
    echo("[shatteredmap] Patching Landing tunnel routes...")

    local tunnel_disconnects = {
        {8860, 20622}, {20622, 8860},     -- Helga's
        {20639, 20631}, {20631, 20639},   -- Fishing Shack
        {20641, 20627}, {20627, 20641},   -- Begetting Besiegers
        {20057, 20638}, {20638, 20057},   -- Museum
        {20645, 460},                      -- Upper Trollfang
        {7625, 20619}, {20619, 7625},     -- Black Sands
        {20604, 434},                      -- Lower Dragonsclaw
        {290, 29559}, {29559, 290},       -- West Ring Rd
        {291, 13245}, {13245, 291},       -- West Ring Rd Gate
        {20588, 20590}, {20590, 20588},   -- Scribe
        {7497, 20594}, {20594, 7497},     -- Catacombs
        {19946, 20600}, {20600, 19946},   -- Cholgar's Cavern
        {6929, 23337}, {23337, 6929},     -- Land Tower West
        {3807, 23335}, {23335, 3807},     -- Land Tower East
    }

    for _, pair in ipairs(tunnel_disconnects) do
        remove_route(pair[1], pair[2])
    end

    echo("[shatteredmap] Landing tunnels patched.")
end

-- ============================================================
-- Urchin runner path fixes
-- ============================================================
local function urchin_fixes()
    remove_route(30710, 32600)  -- Solhaven grocer
    remove_route(30708, 3619)   -- WL Wayside Inn
end

-- ============================================================
-- Miscellaneous corrections
-- ============================================================
local function misc_corrections()
    echo("[shatteredmap] Applying misc corrections...")

    -- Remove Talondown entrances (Talondown does not exist on Shattered)
    local talondown_disconnects = {
        {417, 23281}, {23281, 417},       -- WL
        {1005, 23281}, {23281, 1005},     -- Zul Logoth
        {13920, 23281}, {23281, 13920},   -- Ravelin
        {3660, 23281}, {23281, 3660},     -- Mist Harbor
        -- IMT removed below then re-added with tracking
        {3158, 23281}, {23281, 3158},     -- ICT (full removal)
    }
    for _, pair in ipairs(talondown_disconnects) do
        remove_route(pair[1], pair[2])
    end

    -- Add Icemule Talondown entrance with origin tracking (function wayto)
    register_fn_wayto(2302, 23281, function()
        move("go doorframe")
        UserVars.mapdb_talondown_origin = 2302
    end, 0.4)

    -- Exit from Talondown back to Icemule (only valid if we entered from IMT)
    -- nil static timeto: Dijkstra won't route here (correct — conditional exit)
    register_fn_wayto(23281, 2302, function()
        move("go exit passage")
        UserVars.mapdb_talondown_origin = nil
    end, nil)

    -- Hinterwilds — caravan conditional timeto (Lich5: StringProc on timeto only)
    -- The Lich5 source only patches room.timeto (no wayto StringProc); there is
    -- no traversal function — the wayto command already exists in the Prime mapdb.
    -- We set nil static timeto (impassable by Dijkstra). The caravan cannot be
    -- Dijkstra-routed without dynamic timeto evaluation (a known limitation).
    -- Users can navigate manually; go2 will not route through the caravan.
    Map.set_timeto(29865, 31069, nil)  -- EN caravan
    Map.set_timeto(29865, 2487,  nil)  -- IM caravan

    -- Darkstone Castle fix
    remove_route(7927, 34489)
    remove_route(6997, 34516)
    add_route(6997, 6995, "west", 0.2)

    -- Frozen Bramble — no access from Icemule
    remove_route(3111, 24519)

    -- Sailor's Grief town tag: move from room 35603 to 35593
    remove_tag(35603, "town")
    add_tag(35593, "town")

    echo("[shatteredmap] Misc corrections applied.")
end

-- ============================================================
-- Ta'Illistim corrections
-- ============================================================
local function illistim_corrections()
    echo("[shatteredmap] Applying Ta'Illistim corrections...")

    -- Bank: add route from street (room 13) → bank interior (room 12)
    add_route(13, 12, "go bank", 0.2)

    -- Create Bank of Ta'Illistim, Lobby (room 66671)
    Map.new(BANK_LOBBY, {
        title = "[Bank of Ta'Illistim, Lobby]",
        description = "The stained glaes rosette windows, capturing just enough moonlight from the night sky, cast a rainbow of shimmering color across the bank's pure white marble floors.  A richly hued Loenthran carpet, vibrant in shades of wine, sapphire and emerald, rests in front of the bank's entrance.",
        paths = {"Obvious exits: south, out"},
        uid = {13103001},
        tags = {},
        location = "Ta'Illistim",
    })
    add_route(BANK_LOBBY, 8, "out",   0.2)
    add_route(BANK_LOBBY, 9, "south", 0.2)

    -- Room 8: old direct 8→9 replaced by 8→BANK_LOBBY→9
    add_route(8, BANK_LOBBY, "go bank", 0.2)
    remove_route(8, 9)

    -- Room 9: disconnect from 8, route via bank lobby north
    remove_route(9, 8)
    set_routes(9,
        { [tostring(BANK_LOBBY)] = "north", ["12"] = "south", ["11"] = "go arch" },
        { [tostring(BANK_LOBBY)] = 0.2,     ["12"] = 0.2,     ["11"] = 0.2 }
    )
    set_paths(9, {"Obvious exits: north, south"})

    -- Dais: remove broken routes to room 188 and 186
    remove_route(28,    188)
    remove_route(184,   188)
    remove_route(27,    188)
    remove_route(529,   188)
    remove_route(528,   188)
    remove_route(13262, 186)

    -- Bridge corrections
    add_route(706, 13262, "go bridge", 0.2)
    add_route(608, 607,   "go bridge", 0.2)
    add_route(606, 607,   "go arch",   0.2)

    -- Illistim Keep: remove inaccessible routes
    remove_route(742,   16961)
    remove_route(623,   16961)
    remove_route(8,     24555)
    remove_route(608,   24555)
    remove_route(13231, 24555)

    -- Keep: add staircase and cottage routes
    add_route(623, 17841, "climb staircase", 0.2)
    add_route(26,  1439,  "go cottage",      0.2)

    -- Room 18139: rewire (go mistwood door → 18137 instead of 18138/28478)
    remove_route(18139, 18138)
    remove_route(18139, 28478)
    add_route(18139, 18137, "go mistwood door", 0.2)

    -- Room 18137: complete route replacement (matches Lich5 full hash replacement)
    set_routes(18137,
        { ["18138"] = "go westerly door",
          ["18139"] = "go easterly door",
          ["17841"] = "go ogee arch" },
        { ["18138"] = 0.2, ["18139"] = 0.2, ["17841"] = 0.2 }
    )

    -- Room 18138: complete route replacement
    set_routes(18138,
        { ["18137"] = "go mistwood door",
          ["18140"] = "go silver staircase",
          ["18146"] = "go cerulean-tiled arch",
          ["18147"] = "go azure-tiled arch",
          ["18148"] = "go lapis-tiled arch",
          ["18149"] = "go sapphire-tiled arch" },
        { ["18137"] = 0.2, ["18140"] = 0.2, ["18146"] = 0.2,
          ["18147"] = 0.2, ["18148"] = 0.2, ["18149"] = 0.2 }
    )

    -- Room 17841: complete route replacement
    set_routes(17841,
        { ["623"]   = "climb westerly staircase",
          ["742"]   = "climb easterly staircase",
          ["18137"] = "go ogee arch" },
        { ["623"] = 0.2, ["742"] = 0.2, ["18137"] = 0.2 }
    )

    -- Room 18140: remove bad route, add correct staircase
    remove_route(18140, 18144)
    add_route(18140, 18138, "go silver staircase", 0.2)

    -- Pig & Whistle cottage
    add_route(613, 13311, "go cottage", 0.2)

    echo("[shatteredmap] Ta'Illistim corrections applied.")
end

-- ============================================================
-- Maaghara Tower exit routing
-- Five tower rooms each have a complex multi-step path to the
-- Refuse Heap (room 9734). Lich5 used StringProc; Revenant uses
-- Lua closures registered via register_fn_wayto.
-- ============================================================
local function maaghara_tower_exits()
    echo("[shatteredmap] Patching Maaghara Tower exit routes...")

    -- Direction sequences for navigating from each stranded room to the root
    -- when "go root" is blocked.
    local next_exit = {
        [9823] = {"southeast", "southwest", "southwest", "east", "southwest", "southeast", "south"},
        [9818] = {"east", "southwest", "west", "west", "northeast", "northeast", "northwest"},
        [9808] = {"east", "east", "east", "northeast", "west"},
        [9788] = {"southwest", "southeast", "southwest"},
        [9784] = {"southeast", "south", "northeast", "north", "west", "west", "west"},
    }

    local tower_rooms = {9823, 9818, 9808, 9788, 9784}

    for _, room_id in ipairs(tower_rooms) do
        register_fn_wayto(room_id, 9734, function()
            while true do
                local result = dothistimeout("go root", 5,
                    "Obvious paths",
                    "Obvious exits",
                    "Refuse Heap",
                    "You can't go there")

                if result and (result:find("Obvious") or result:find("Refuse Heap")) then
                    wait_until(function()
                        return GameState.room_name == "[Maaghara Tower, Refuse Heap]"
                    end)
                    if not GameState.standing then fput("stand") end
                    waitrt()
                    return
                else
                    local cur_id = Map.current_room()
                    local dirs   = next_exit[cur_id]
                    if dirs then
                        for _, dir in ipairs(dirs) do move(dir) end
                    else
                        echo("[shatteredmap] Maaghara: unexpected room " .. tostring(cur_id))
                        return
                    end
                end
            end
        end, 0.2)
    end

    echo("[shatteredmap] Maaghara Tower exits patched.")
end

-- ============================================================
-- Landing graveyard gate (UID-based, spell + push)
-- Lich5: Room.ids_from_uid(18002/18003) + StringProc wayto
-- Revenant: Map.ids_from_uid(18002/18003) + register_fn_wayto
--
-- The gate requires either a spell cast (407/1604/304/1207) or
-- repeated pushing to open. Lich5's empty_hand/fill_hand for the
-- push path is implemented inline here.
-- ============================================================
local function landing_graveyard_gate()
    echo("[shatteredmap] Patching graveyard gate routes...")

    local ids_outside = Map.ids_from_uid(18002)
    local ids_inside  = Map.ids_from_uid(18003)

    if not ids_outside or #ids_outside == 0 then
        echo("[shatteredmap] Warning: graveyard gate UID 18002 not found — skipping.")
        return
    end
    if not ids_inside or #ids_inside == 0 then
        echo("[shatteredmap] Warning: graveyard gate UID 18003 not found — skipping.")
        return
    end

    local room_outside = ids_outside[1]
    local room_inside  = ids_inside[1]

    -- Guard: skip if already patched (timeto == 30.0 signals this)
    local snap = Map.find_room(room_outside)
    if snap and snap.timeto then
        local existing = snap.timeto[tostring(room_inside)]
        if existing and math.abs(existing - 30.0) < 0.01 then
            echo("[shatteredmap] Graveyard gate already patched, skipping.")
            return
        end
    end

    -- Remove any direct-bypass route to room 16392 (skips the gate)
    remove_route(room_outside, 16392)

    -- Spell list for gate opening (first known spell is tried once before pushing)
    local spell_list = {407, 1604, 304, 1207}

    -- Gate traversal factory (both directions use the same logic)
    local function make_gate_fn()
        return function()
            local cast_attempted = false

            while true do
                local result = dothistimeout("go bronze gate", 5,
                    "The bronze gate appears to be closed",
                    "Obvious paths",
                    "Obvious exits")

                if result and result:find("Obvious") then
                    return  -- Made it through
                end

                if not cast_attempted then
                    cast_attempted = true
                    local cast_spell = nil
                    for _, num in ipairs(spell_list) do
                        local sp = Spell[num]
                        -- Spell[num].known is a boolean; also check affordable (mana)
                        if sp and sp.known and sp.mana_cost and
                           (GameState.mana or 0) >= (sp.mana_cost or 999) then
                            cast_spell = sp
                            break
                        end
                    end
                    if cast_spell then
                        fput("prep " .. cast_spell.num)
                        waitcastrt()
                        fput("cast bronze gate")
                        waitrt()
                    end
                else
                    -- Empty hands before pushing (items in hands block the push)
                    local rh_id, lh_id
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if rh and rh.id then rh_id = rh.id; fput("stow right"); waitrt() end
                    if lh and lh.id then lh_id = lh.id; fput("stow left");  waitrt() end

                    dothistimeout("push bronze gate", 16,
                        "gate .* open",
                        "hinges of the gate creak",
                        "gate opens",
                        "bronze gate pops open",
                        "slip through now",
                        "just came through a massive bronze gate",
                        "just went through a massive bronze gate")
                    pause(0.5)

                    -- Restore hands
                    if lh_id then fput("get #" .. lh_id); waitrt() end
                    if rh_id then fput("get #" .. rh_id); waitrt() end
                end
            end
        end
    end

    -- 30.0 second timeto (pushing takes a while; matches Lich5 value)
    register_fn_wayto(room_outside, room_inside,  make_gate_fn(), 30.0)
    register_fn_wayto(room_inside,  room_outside, make_gate_fn(), 30.0)

    echo("[shatteredmap] Graveyard gate patched (rooms " .. room_outside .. " <-> " .. room_inside .. ").")
end

-- ============================================================
-- Execute all patches
-- ============================================================
load_prime_mapdb()
create_nexus_rooms()
create_nexus_routes()
wayside_inn_modifications()
playershop_modifications()
premium_portals()
landing_tunnels()
urchin_fixes()
misc_corrections()
illistim_corrections()
maaghara_tower_exits()
landing_graveyard_gate()

echo("[shatteredmap] Shattered map patching complete! All modifications applied.")
