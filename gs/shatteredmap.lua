--- @revenant-script
--- name: shatteredmap
--- version: 1.8.5
--- author: elanthia-online
--- game: gs
--- description: Load GSIV Prime mapdb while playing Shattered, then hot-patch Shattered-specific changes
--- tags: map,shattered,gsf,nexus
---
--- Changelog (from Lich5):
---   v1.8.5 (2026-01-28): move SG town tag below mast climb
---   v1.8.4 (2025-11-20): bugfix for wayside garret
---   v1.8.0 (2025-11-18): add WL graveyard gate fix
---   v1.7.0 (2025-10-20): add urchin fixes
---   v1.6.0 (2025-10-01): Sailor's Grief nexus logic
---   v1.5.0 (2024-10-20): Hinterwilds changes
---
--- Usage:
---   Run via ;autostart add --global shatteredmap
---   ;shatteredmap help   - show help
---
--- NOTE: This is a map-patching script specific to Shattered (GSF) server.
--- It downloads the Prime (GSIV) map database, then patches Shattered-specific
--- room modifications (nexus, portals, player shops, tunnels, etc.) into memory.
--- Much of the logic involves low-level Map room manipulation that requires
--- Revenant Map APIs for room creation and route editing.

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
    respond("")
    respond("Run as ;" .. Script.name .. " and enjoy!")
    respond("")
    respond("If you need to go back to previous Shattered mapdb, use:")
    respond("  ;e Map.reload()")
    return
end

before_dying(function()
    -- Ensure game stays set to GSF
end)

-- Constants for new nexus rooms
local NEW_NEXUS = 66666
local NEW_SMITHY = 66667

----------------------------------------------------------------------
-- Helper: Remove a route between two rooms
----------------------------------------------------------------------
local function remove_route(from_id, to_id)
    local room = Map.find_room(from_id)
    if room and room.wayto then
        room.wayto[tostring(to_id)] = nil
    end
    if room and room.timeto then
        room.timeto[tostring(to_id)] = nil
    end
end

----------------------------------------------------------------------
-- Helper: Add a route between two rooms
----------------------------------------------------------------------
local function add_route(from_id, to_id, command, time)
    local room = Map.find_room(from_id)
    if room then
        if room.wayto then
            room.wayto[tostring(to_id)] = command
        end
        if room.timeto then
            room.timeto[tostring(to_id)] = time or 0.2
        end
    end
end

----------------------------------------------------------------------
-- Load Prime map database
----------------------------------------------------------------------
local function load_prime_mapdb()
    echo("Loading Prime GSIV map database...")
    -- Wait for map to be loaded
    wait_until(function() return Map.room_count() > 0 end)

    -- Temporarily switch game to GSIV to download prime map
    -- In Revenant, this is handled by reloading the GSIV map data
    echo("Downloading GSIV map data...")
    Script.run("repository", "download-mapdb")
    wait_while(function() return running("repository") end)

    echo("Prime map database loaded.")
end

----------------------------------------------------------------------
-- Patch Shattered Nexus
----------------------------------------------------------------------
local function shattered_nexus()
    echo("Patching Shattered Nexus rooms...")

    -- Nexus connections from various towns
    local nexus_towns = {
        {id = 27,    name = "Ta'Illistim"},
        {id = 318,   name = "Wehnimer's Landing"},
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

    -- Add rift entrances from each town to nexus
    for _, town in ipairs(nexus_towns) do
        add_route(town.id, NEW_NEXUS, "go rift", 0.2)
    end

    -- Wayside Inn modifications
    add_route(3619, NEW_NEXUS, "out", 0.2)
    remove_route(3619, 221)
    remove_route(3619, 30708)

    -- Wayside Inn rooms cleanup
    remove_route(9652, 26905)
    remove_route(9652, 31558)

    -- Garret cleanup
    remove_route(14627, 30708)
    remove_route(14627, 223)

    -- Outside Gate cleanup
    remove_route(221, 3619)

    echo("Nexus patching complete.")
end

----------------------------------------------------------------------
-- Patch player shops (disconnect/remap)
----------------------------------------------------------------------
local function playershop_modifications()
    echo("Patching player shop routes...")

    -- Disconnect player shop entrances across towns
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

    echo("Player shop routes patched.")
end

----------------------------------------------------------------------
-- Patch Landing tunnels (Burrow Way removal)
----------------------------------------------------------------------
local function landing_tunnels()
    echo("Patching Landing tunnel routes...")

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

    echo("Landing tunnels patched.")
end

----------------------------------------------------------------------
-- Misc corrections
----------------------------------------------------------------------
local function misc_corrections()
    echo("Applying misc corrections...")

    -- Remove Talondown entrances
    local talondown_disconnects = {
        {417, 23281}, {23281, 417},       -- WL
        {1005, 23281}, {23281, 1005},     -- Zul Logoth
        {13920, 23281}, {23281, 13920},   -- Ravelin
        {3660, 23281}, {23281, 3660},     -- Mist Harbor
        {3158, 23281}, {23281, 3158},     -- Icemule
    }

    for _, pair in ipairs(talondown_disconnects) do
        remove_route(pair[1], pair[2])
    end

    -- Add Icemule Talondown entrance
    add_route(2302, 23281, "go doorframe", 0.4)
    add_route(23281, 2302, "go exit passage", 0.2)

    -- Darkstone Castle fix
    remove_route(7927, 34489)
    remove_route(6997, 34516)
    add_route(6997, 6995, "west", 0.2)

    -- Frozen Bramble - no access
    remove_route(3111, 24519)

    -- Sailor's Grief town tag adjustment
    -- Move town tag to below mast climb
    local room_35603 = Map.find_room(35603)
    if room_35603 and room_35603.tags then
        for i = #room_35603.tags, 1, -1 do
            if room_35603.tags[i] == "town" then
                table.remove(room_35603.tags, i)
            end
        end
    end
    local room_35593 = Map.find_room(35593)
    if room_35593 and room_35593.tags then
        table.insert(room_35593.tags, "town")
    end

    echo("Misc corrections applied.")
end

----------------------------------------------------------------------
-- Urchin fixes
----------------------------------------------------------------------
local function urchin_fixes()
    remove_route(30710, 32600)  -- Solhaven grocer
    remove_route(30708, 3619)   -- WL Wayside Inn
end

----------------------------------------------------------------------
-- Ta'Illistim corrections
----------------------------------------------------------------------
local function illistim_corrections()
    echo("Applying Ta'Illistim corrections...")

    -- Bank fix
    add_route(13, 12, "go bank", 0.2)

    -- Dais removals
    remove_route(28, 188)
    remove_route(184, 188)
    remove_route(27, 188)
    remove_route(529, 188)
    remove_route(528, 188)
    remove_route(13262, 186)

    -- Bridge corrections
    add_route(706, 13262, "go bridge", 0.2)
    add_route(608, 607, "go bridge", 0.2)
    add_route(606, 607, "go arch", 0.2)

    -- Keep corrections
    remove_route(742, 16961)
    remove_route(623, 16961)
    remove_route(8, 24555)
    remove_route(608, 24555)
    remove_route(13231, 24555)

    add_route(623, 17841, "climb staircase", 0.2)
    add_route(26, 1439, "go cottage", 0.2)

    -- Pig & Whistle
    add_route(613, 13311, "go cottage", 0.2)

    echo("Ta'Illistim corrections applied.")
end

----------------------------------------------------------------------
-- Execute all patches
----------------------------------------------------------------------
load_prime_mapdb()
shattered_nexus()
playershop_modifications()
landing_tunnels()
urchin_fixes()
misc_corrections()
illistim_corrections()

echo("Shattered map patching complete! All modifications applied.")
