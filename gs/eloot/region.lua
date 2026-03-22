--- ELoot region module
-- Ported from eloot.lic ELoot::Region submodule (lines 2175-2225).
-- Handles regional bounty selling — determines if destinations are reachable
-- without crossing ferry/cart/portmaster boundaries.
--
-- Usage:
--   local Region = require("gs.eloot.region")
--   local furrier_id = Region.furrier(data)

local M = {}

-- ---------------------------------------------------------------------------
-- Forward-declare lazy requires
-- ---------------------------------------------------------------------------

local function Util() return require("gs.eloot.util") end

-- ---------------------------------------------------------------------------
-- Boundary rooms — ferries, mine carts, boots, portmasters, hinterwilds
-- These room UIDs define the edges of travel regions; paths crossing
-- them mean the destination is in a different region.
-- ---------------------------------------------------------------------------

local BOUNDARY_UIDS = {
    14001002,   -- Ta'Vaalor Ferry
    13002021,   -- Western Spine Mine Cart
    13003019,   -- Eastern Spine Mine Cart
    373014,     -- River's Rest Boot
    7503001,    -- Hinterwilds Caravan Dropoff
    13205202,   -- EN Hinterwilds Transport
    4132054,    -- IMT Hinterwilds Transport
    7111,       -- Portmaster - Wehnimer's Landing
    3002033,    -- Portmaster - Teras Isle
    2101030,    -- Portmaster - River's Rest
    4744014,    -- Portmaster - Solhaven
    7118259,    -- Portmaster - Kraken's Fall
    7136032,    -- Portmaster - Ta'Vaalor
    7133026,    -- Portmaster - Icemule Trace
}

--- Resolve boundary UIDs to room IDs (cached after first call).
local boundary_ids_cache = nil
local function get_boundary_ids()
    if boundary_ids_cache then return boundary_ids_cache end
    boundary_ids_cache = {}
    for _, uid in ipairs(BOUNDARY_UIDS) do
        local ids = Map.ids_from_uid and Map.ids_from_uid(uid)
        if ids and ids[1] then
            boundary_ids_cache[#boundary_ids_cache + 1] = ids[1]
        end
    end
    return boundary_ids_cache
end

-- ---------------------------------------------------------------------------
-- 1. by_town (line 2177)
-- Map each known town to a tagged room.
-- ---------------------------------------------------------------------------

--- Build a table mapping town location names to the nearest room with the
-- given tag for each known town.
-- @param tag string room tag to search for (e.g. "furrier", "gemshop")
-- @param data table ELoot data state
-- @return table { [town_location] = Room }
function M.by_town(tag, data)
    Util().msg({ type = "debug", text = "tag: " .. tostring(tag) }, data)

    local result = {}
    local towns = data.towns or {}
    for _, town in ipairs(towns) do
        local nearest_id = Map.find_nearest_by_tag and Map.find_nearest_by_tag(town.id, tag)
        if nearest_id then
            result[town.location] = Room[nearest_id]
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 2. tag_for_town (line 2182)
-- Find a specific town's room by tag.
-- ---------------------------------------------------------------------------

--- Find the room with the given tag nearest to the specified town.
-- @param town string town name (partial match, case-insensitive)
-- @param tag string room tag to find
-- @param data table ELoot data state
-- @return table|nil Room object
function M.tag_for_town(town, tag, data)
    Util().msg({ type = "debug", text = "tag: " .. tostring(tag) .. " | town: " .. tostring(town) }, data)

    local town_map = M.by_town(tag, data)
    local town_lower = town:lower()
    for k, v in pairs(town_map) do
        if k:lower():find(town_lower, 1, true) then
            return v
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 3. in_region (lines 2187-2213)
-- Check reachability without crossing boundaries.
-- ---------------------------------------------------------------------------

--- Determine if the bounty destination is within the current region
-- (reachable without crossing ferry/cart/portmaster boundaries).
-- @param place string room tag (e.g. "furrier", "gemshop")
-- @param data table ELoot data state
-- @return number|nil room ID if reachable, nil otherwise
function M.in_region(place, data)
    Util().msg({ type = "debug", text = "place: " .. tostring(place) }, data)

    if not Bounty or not Bounty.town then return nil end

    local bounty_town = Bounty.town
    if bounty_town == "Cold River" then
        bounty_town = "Hinterwilds"
    end

    local dest_room = M.tag_for_town(bounty_town, place, data)
    if not dest_room then return nil end

    local dest_id = dest_room.id
    local current = Room.current()
    if not current then return nil end

    local path = Map.find_path and Map.find_path(current.id, dest_id)
    if not path then return nil end

    -- Check that no boundary room appears in the path
    local boundaries = get_boundary_ids()
    for _, fence in ipairs(boundaries) do
        for _, step in ipairs(path) do
            if step == fence then
                return nil
            end
        end
    end

    return dest_id
end

-- ---------------------------------------------------------------------------
-- 4. furrier (line 2215-2218)
-- ---------------------------------------------------------------------------

--- Find the regional furrier room ID.
-- @param data table ELoot data state
-- @return number|nil room ID
function M.furrier(data)
    Util().msg({ type = "debug" }, data)
    return M.in_region("furrier", data)
end

-- ---------------------------------------------------------------------------
-- 5. gemshop (line 2220-2223)
-- ---------------------------------------------------------------------------

--- Find the regional gemshop room ID.
-- @param data table ELoot data state
-- @return number|nil room ID
function M.gemshop(data)
    Util().msg({ type = "debug" }, data)
    return M.in_region("gemshop", data)
end

return M
