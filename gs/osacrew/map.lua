-- osacrew/map.lua
-- Map tag injection, gangplank wayto management, and room navigation helpers.
-- Original: osacrew.lic (Lich5), ship_type/ship_map/crew_map_gangplank/crew_clear_gangplank (lines 159-530)
-- Ported to Revenant Lua by osacrew conversion.

local M = {}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Inject a tag into a room if it doesn't already have it.
-- Map.find_room returns a room table with a .tags field (array of strings).
-- Map.add_tag(id, tag) is used when available; fall back to direct mutation.
local function add_tag(room_id, tag)
    local room = Map.find_room(room_id)
    if not room then
        echo("[osacrew/map] WARNING: room " .. tostring(room_id) .. " not found for tag '" .. tag .. "'")
        return
    end
    -- Check if already tagged
    for _, t in ipairs(room.tags or {}) do
        if t == tag then return end
    end
    if Map.add_tag then
        Map.add_tag(room_id, tag)
    else
        -- Fallback: mutate the live table (may not persist across sessions)
        echo("[osacrew/map] WARNING: Map.add_tag not available — tagging " .. room_id .. " in-memory only")
        room.tags = room.tags or {}
        table.insert(room.tags, tag)
    end
end

-- Add a wayto entry from one room to another.
-- The command is a plain string executed when the map engine traverses the edge.
local function add_wayto(from_id, to_id, cmd)
    local from_key = tostring(from_id)
    local to_key   = tostring(to_id)
    if Map.add_wayto then
        Map.add_wayto(from_id, to_id, cmd)
    else
        echo("[osacrew/map] WARNING: Map.add_wayto not available — injecting into room table in-memory")
        local room = Map.find_room(from_id)
        if room then
            room.wayto = room.wayto or {}
            room.wayto[to_key] = cmd
        end
    end
end

-- Add a timeto entry (seconds) between two rooms.
local function add_timeto(from_id, to_id, secs)
    local to_key = tostring(to_id)
    if Map.add_timeto then
        Map.add_timeto(from_id, to_id, secs)
    else
        local room = Map.find_room(from_id)
        if room then
            room.timeto = room.timeto or {}
            room.timeto[to_key] = secs
        end
    end
end

-- Remove a wayto/timeto entry from a room.
local function del_wayto(from_id, to_id)
    local to_key = tostring(to_id)
    if Map.del_wayto then
        Map.del_wayto(from_id, to_id)
    else
        local room = Map.find_room(from_id)
        if room then
            if room.wayto  then room.wayto[to_key]  = nil end
            if room.timeto then room.timeto[to_key] = nil end
        end
    end
end

-- Enemy main-deck room IDs for all 6 ship types (used for cross-ship wayto injection).
local ENEMY_MAIN_DECKS = { 30787, 30792, 30266, 30798, 30805, 30778 }

-- The push-gang command string used to board an enemy ship from your own main deck.
local PUSH_GANG_CMD = 'fput("push gang"); fput("go gang")'

-- ---------------------------------------------------------------------------
-- 1. ship_type(osa)
-- ---------------------------------------------------------------------------
-- Injects room tags for all 6 ship types and their enemy equivalents.
-- Also injects cross-ship wayto entries from each main deck to all 6 enemy decks.
-- Source: .lic lines 159-380.

function M.ship_type(osa)
    -- Sloop
    if not Map.find_room(29038) or not (function()
        for _, t in ipairs(Map.find_room(29038).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(29039, "cargo_hold")
        add_tag(29038, "main_deck")
        add_tag(29040, "crows_nest")
        add_tag(29041, "helm")
        add_tag(29042, "captains_quarters")
        add_tag(29038, "main_cannon")
    end
    if not Map.find_room(30787) or not (function()
        for _, t in ipairs(Map.find_room(30787).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30790, "enemy_cargo_hold")
        add_tag(30787, "enemy_main_deck")
        add_tag(30791, "enemy_crows_nest")
        add_tag(30788, "enemy_helm")
        add_tag(30789, "enemy_quarters")
    end
    -- Sloop cross-ship wayto (only inject once)
    local sloop_room = Map.find_room(29038)
    if sloop_room and not (sloop_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(29038, eid, PUSH_GANG_CMD)
            add_timeto(29038, eid, 0.2)
        end
    end

    -- Brigantine
    if not Map.find_room(30142) or not (function()
        for _, t in ipairs(Map.find_room(30142).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30145, "cargo_hold")
        add_tag(30142, "main_deck")
        add_tag(30144, "forward_deck")
        add_tag(30143, "crows_nest")
        add_tag(30147, "mess_hall")
        add_tag(30146, "crew_quarters")
        add_tag(30141, "helm")
        add_tag(30140, "captains_quarters")
        add_tag(30142, "main_cannon")
        add_tag(30144, "forward_cannon")
    end
    if not Map.find_room(30792) or not (function()
        for _, t in ipairs(Map.find_room(30792).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30795, "enemy_cargo_hold")
        add_tag(30792, "enemy_main_deck")
        add_tag(30797, "enemy_forward_deck")
        add_tag(30796, "enemy_crows_nest")
        add_tag(30793, "enemy_helm")
        add_tag(30794, "enemy_quarters")
    end
    local brig_room = Map.find_room(30142)
    if brig_room and not (brig_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(30142, eid, PUSH_GANG_CMD)
            add_timeto(30142, eid, 0.2)
        end
    end

    -- Carrack
    if not Map.find_room(30119) or not (function()
        for _, t in ipairs(Map.find_room(30119).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30125, "cargo_hold")
        add_tag(30119, "main_deck")
        add_tag(30121, "forward_deck")
        add_tag(30122, "bow")
        add_tag(30123, "crows_nest")
        add_tag(30127, "mess_hall")
        add_tag(30126, "crew_quarters")
        add_tag(30120, "helm")
        add_tag(30124, "captains_quarters")
        add_tag(30119, "main_cannon")
        add_tag(30121, "forward_cannon")
    end
    if not Map.find_room(30266) or not (function()
        for _, t in ipairs(Map.find_room(30266).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30269, "enemy_cargo_hold")
        add_tag(30266, "enemy_main_deck")
        add_tag(30271, "enemy_forward_deck")
        add_tag(30272, "enemy_bow")
        add_tag(30270, "enemy_crows_nest")
        add_tag(30267, "enemy_helm")
        add_tag(30268, "enemy_quarters")
    end
    local car_room = Map.find_room(30119)
    if car_room and not (car_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(30119, eid, PUSH_GANG_CMD)
            add_timeto(30119, eid, 0.2)
        end
    end

    -- Galleon
    if not Map.find_room(30176) or not (function()
        for _, t in ipairs(Map.find_room(30176).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30182, "cargo_hold")
        add_tag(30176, "main_deck")
        add_tag(30177, "forward_deck")
        add_tag(30178, "bow")
        add_tag(30181, "crows_nest")
        add_tag(30185, "social_room")
        add_tag(30184, "mess_hall")
        add_tag(30183, "crew_quarters")
        add_tag(30179, "helm")
        add_tag(30180, "captains_quarters")
        add_tag(30176, "main_cannon")
        add_tag(30177, "forward_cannon")
    end
    if not Map.find_room(30798) or not (function()
        for _, t in ipairs(Map.find_room(30798).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30801, "enemy_cargo_hold")
        add_tag(30798, "enemy_main_deck")
        add_tag(30803, "enemy_forward_deck")
        add_tag(30804, "enemy_bow")
        add_tag(30802, "enemy_crows_nest")
        add_tag(30799, "enemy_helm")
        add_tag(30800, "enemy_quarters")
    end
    local gal_room = Map.find_room(30176)
    if gal_room and not (gal_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(30176, eid, PUSH_GANG_CMD)
            add_timeto(30176, eid, 0.2)
        end
    end

    -- Frigate
    if not Map.find_room(30166) or not (function()
        for _, t in ipairs(Map.find_room(30166).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30167, "cargo_hold")
        add_tag(30166, "main_deck")
        add_tag(30171, "forward_deck")
        add_tag(30172, "bow")
        add_tag(30173, "crows_nest")
        add_tag(30170, "social_room")
        add_tag(30169, "mess_hall")
        add_tag(30168, "crew_quarters")
        add_tag(30174, "helm")
        add_tag(30175, "captains_quarters")
        add_tag(30166, "main_cannon")
        add_tag(30171, "forward_cannon")
    end
    if not Map.find_room(30805) or not (function()
        for _, t in ipairs(Map.find_room(30805).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30808, "enemy_cargo_hold")
        add_tag(30805, "enemy_main_deck")
        add_tag(30810, "enemy_forward_deck")
        add_tag(30809, "enemy_crows_nest")
        add_tag(30806, "enemy_helm")
        add_tag(30807, "enemy_quarters")
    end
    local fri_room = Map.find_room(30166)
    if fri_room and not (fri_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(30166, eid, PUSH_GANG_CMD)
            add_timeto(30166, eid, 0.2)
        end
    end

    -- Man O' War
    if not Map.find_room(30130) or not (function()
        for _, t in ipairs(Map.find_room(30130).tags or {}) do
            if t == "main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30136, "cargo_hold")
        add_tag(30130, "main_deck")
        add_tag(30131, "mid_deck")
        add_tag(30132, "forward_deck")
        add_tag(30133, "bow")
        add_tag(30135, "crows_nest")
        add_tag(30134, "forward_crows_nest")
        add_tag(30139, "social_room")
        add_tag(30138, "mess_hall")
        add_tag(30137, "crew_quarters")
        add_tag(30128, "helm")
        add_tag(30129, "captains_quarters")
        add_tag(30130, "main_cannon")
        add_tag(30131, "mid_cannon")
        add_tag(30132, "forward_cannon")
    end
    if not Map.find_room(30778) or not (function()
        for _, t in ipairs(Map.find_room(30778).tags or {}) do
            if t == "enemy_main_deck" then return true end
        end
        return false
    end)() then
        add_tag(30781, "enemy_cargo_hold")
        add_tag(30778, "enemy_main_deck")
        add_tag(30783, "enemy_mid_deck")
        add_tag(30786, "enemy_forward_deck")
        add_tag(30784, "enemy_bow")
        add_tag(30782, "enemy_crows_nest")
        add_tag(30785, "enemy_forward_crows_nest")
        add_tag(30779, "enemy_helm")
        add_tag(30780, "enemy_quarters")
    end
    local mow_room = Map.find_room(30130)
    if mow_room and not (mow_room.wayto or {})["30787"] then
        for _, eid in ipairs(ENEMY_MAIN_DECKS) do
            add_wayto(30130, eid, PUSH_GANG_CMD)
            add_timeto(30130, eid, 0.2)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 2. ship_map(osa)
-- ---------------------------------------------------------------------------
-- Detects ship type from current room ID range, sets osa.ship_type and
-- osa.ship_map.  Maintains per-ship leg-time arrays (capped at 50) and
-- recalculates osa.averagetime.
-- Source: .lic lines 472-529.

local function times_key(ship)
    local keys = {
        ["sloop"]       = "Slooptimes",
        ["brigantine"]  = "Brigtimes",
        ["carrack"]     = "Cartimes",
        ["galleon"]     = "Galtimes",
        ["frigate"]     = "Fritimes",
        ["man o' war"]  = "Mantimes",
    }
    return keys[ship]
end

local function update_averagetime(osa, ship)
    local k = times_key(ship)
    if not k then return end
    if not osa[k] then
        osa[k] = { 0.35 }
    end
    -- Cap at 50 entries
    while #osa[k] > 50 do
        table.remove(osa[k], 1)
    end
    local sum = 0
    for _, v in ipairs(osa[k]) do sum = sum + v end
    osa.averagetime = sum / #osa[k]
end

function M.ship_map(osa)
    local room_id = Map.current_room()
    if not room_id then
        echo("[osacrew/map] ship_map: current room unknown")
        return
    end

    if room_id >= 29038 and room_id <= 29042 then
        osa.ship_type = "sloop"
        osa.ship_map  = { "main_deck", "cargo_hold", "crows_nest", "helm", "captains_quarters" }

    elseif room_id >= 30140 and room_id <= 30147 then
        osa.ship_type = "brigantine"
        osa.ship_map  = { "forward_deck", "main_deck", "crows_nest", "cargo_hold", "mess_hall", "crew_quarters", "helm", "captains_quarters" }

    elseif room_id >= 30119 and room_id <= 30127 then
        osa.ship_type = "carrack"
        osa.ship_map  = { "bow", "forward_deck", "crows_nest", "main_deck", "mess_hall", "cargo_hold", "crew_quarters", "helm", "captains_quarters" }

    elseif room_id >= 30176 and room_id <= 30186 then
        osa.ship_type = "galleon"
        osa.ship_map  = { "bow", "forward_deck", "crows_nest", "main_deck", "social_room", "mess_hall", "cargo_hold", "crew_quarters", "helm", "captains_quarters" }

    elseif room_id >= 30166 and room_id <= 30175 then
        osa.ship_type = "frigate"
        osa.ship_map  = { "bow", "forward_deck", "crows_nest", "main_deck", "social_room", "mess_hall", "cargo_hold", "crew_quarters", "helm", "captains_quarters" }

    elseif room_id >= 30128 and room_id <= 30139 then
        osa.ship_type = "man o' war"
        osa.ship_map  = { "bow", "forward_crows_nest", "forward_deck", "mid_deck", "crows_nest", "main_deck", "social_room", "mess_hall", "cargo_hold", "crew_quarters", "helm", "captains_quarters" }

    else
        echo("[osacrew/map] ship_map: room " .. tostring(room_id) .. " not recognized as a ship room")
        return
    end

    update_averagetime(osa, osa.ship_type)
end

-- ---------------------------------------------------------------------------
-- 3. crew_map_gangplank(osa)
-- ---------------------------------------------------------------------------
-- Injects bidirectional wayto entries for the gangplank room.
-- Gangplank → ship: Lua command that finds the gangplank GameObj by noun.
-- Ship → gangplank: push gang / go gang.
-- Source: .lic lines 382-424.

-- Build the gangplank-boarding command for a given destination room ID.
local function gangplank_board_cmd(ship_room_id)
    -- Executes: find gangplank object, board it; fallback to ship object.
    return string.format(
        'local gp = nil; for _, o in ipairs(GameObj.loot()) do if o.noun == "gangplank" then gp = o break end end; ' ..
        'if gp then fput("go #" .. gp.id) else ' ..
        'for _, o in ipairs(GameObj.loot()) do if o.noun:match("sloop|brigantine|carrack|frigate|galleon|man") then fput("go #" .. o.id) break end end end',
        ship_room_id
    )
end

-- Ship → gangplank direction command.
local GANG_EXIT_CMD = 'fput("push gang"); fput("go gang")'

-- Map from ship_type string to main deck room ID.
local MAIN_DECK_IDS = {
    ["man o' war"]  = 30130,
    ["frigate"]     = 30166,
    ["galleon"]     = 30176,
    ["carrack"]     = 30119,
    ["brigantine"]  = 30142,
    ["sloop"]       = 29038,
}

function M.crew_map_gangplank(osa)
    local gp = osa.gangplank
    if not gp then
        echo("[osacrew/map] crew_map_gangplank: no gangplank room ID set")
        return
    end
    local st = osa.ship_type
    local deck_id = MAIN_DECK_IDS[st]
    if not deck_id then
        echo("[osacrew/map] crew_map_gangplank: unknown ship type '" .. tostring(st) .. "'")
        return
    end

    -- gangplank room → ship main deck
    add_wayto(gp, deck_id, gangplank_board_cmd(deck_id))
    add_timeto(gp, deck_id, 0.2)

    -- ship main deck → gangplank room
    add_wayto(deck_id, gp, GANG_EXIT_CMD)
    add_timeto(deck_id, gp, 0.2)
end

-- ---------------------------------------------------------------------------
-- 4. crew_clear_gangplank(osa)
-- ---------------------------------------------------------------------------
-- Removes all injected gangplank wayto/timeto entries for all ship types.
-- Source: .lic lines 427-452.

function M.crew_clear_gangplank(osa)
    local gp = osa.gangplank
    if not gp then return end

    for _, deck_id in pairs(MAIN_DECK_IDS) do
        del_wayto(gp, deck_id)
        del_wayto(deck_id, gp)
    end
end

-- ---------------------------------------------------------------------------
-- 5. go_to_tag(tag)
-- ---------------------------------------------------------------------------
-- Navigate to the nearest room with the given tag.
-- Calls ship_type first to ensure tags are injected, then uses Map.go2.

function M.go_to_tag(osa, tag)
    M.ship_type(osa)
    local result = Room.find_nearest_by_tag(tag)
    if not result then
        echo("[osacrew/map] go_to_tag: no room found with tag '" .. tag .. "'")
        return
    end
    if Map.current_room() ~= result.id then
        Map.go2(result.id)
    end
end

-- ---------------------------------------------------------------------------
-- 6. determine_enemy_type(osa)
-- ---------------------------------------------------------------------------
-- Issues "look ocean" and sets osa.enemy_type based on response.
-- Source: .lic lines 454-470.

function M.determine_enemy_type(osa)
    fput("look ocean")
    local result = matchtimeout(3,
        "You notice .* approaching",
        "Open waters:",
        "Obvious paths:")
    if result then
        if string.find(result, "ethereal") then
            osa.enemy_type = "undead"
        elseif string.find(result, "krolvin") then
            osa.enemy_type = "krolvin"
        elseif string.find(result, "dark") then
            osa.enemy_type = "pirate"
        else
            echo("[osacrew/map] Unable to determine enemy type, defaulting to pirate")
            osa.enemy_type = "pirate"
        end
    else
        echo("[osacrew/map] Unable to determine enemy type, defaulting to pirate")
        osa.enemy_type = "pirate"
    end
end

-- ---------------------------------------------------------------------------
-- 7. Room navigation helpers
-- ---------------------------------------------------------------------------
-- Each helper calls go_to_tag with the appropriate tag string after
-- ensuring ship_type has been called (go_to_tag handles this).

local NAV_TAGS = {
    "main_deck", "mid_deck", "forward_deck", "bow", "crows_nest",
    "forward_crows_nest", "social_room", "mess_hall", "crew_quarters",
    "helm", "captains_quarters",
    "enemy_cargo_hold", "enemy_main_deck", "enemy_mid_deck",
    "enemy_forward_deck", "enemy_bow", "enemy_crows_nest",
    "enemy_forward_crows_nest", "enemy_helm", "enemy_quarters",
}

for _, tag in ipairs(NAV_TAGS) do
    local captured_tag = tag
    M[tag] = function(osa)
        M.go_to_tag(osa, captured_tag)
    end
end

-- Convenience alias used throughout the script ecosystem.
M.enemy_cargo_hold         = function(osa) M.go_to_tag(osa, "enemy_cargo_hold") end
M.enemy_main_deck          = function(osa) M.go_to_tag(osa, "enemy_main_deck") end
M.enemy_mid_deck           = function(osa) M.go_to_tag(osa, "enemy_mid_deck") end
M.enemy_forward_deck       = function(osa) M.go_to_tag(osa, "enemy_forward_deck") end
M.enemy_bow                = function(osa) M.go_to_tag(osa, "enemy_bow") end
M.enemy_crows_nest         = function(osa) M.go_to_tag(osa, "enemy_crows_nest") end
M.enemy_forward_crows_nest = function(osa) M.go_to_tag(osa, "enemy_forward_crows_nest") end
M.enemy_helm               = function(osa) M.go_to_tag(osa, "enemy_helm") end
M.enemy_quarters           = function(osa) M.go_to_tag(osa, "enemy_quarters") end

return M
