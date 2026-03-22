--- @revenant-script
--- name: banditpatrol
--- version: 1.0.0
--- author: elanthia-online
--- contributors: Brute, Ryjex
--- game: gs
--- tags: bandits, bounty, utility
--- description: Patrol the bounty bandit area, sniff out hidden bandits, and wait for attacks — does not attack
---
--- Original Lich5 authors: Ryjex (original), elanthia-online (migration 2024-05-13)
--- Ported to Revenant Lua from banditpatrol.lic v1.0.0
---
--- This script walks you through the bandit area and sniffs out any hidden bandits,
--- but DOES NOT run any attack scripts. For use with attack scripts running in the
--- background, or for players who prefer to attack manually.
---
--- Usage:
---   ;banditpatrol
---
--- Changelog (from Lich5):
---   v1.0.0 (2024-05-13) — migration from Ryjex author to EO, rubocop cleanup
---   v1.0.0 (Revenant port) — Lua conversion, upstream hook for hidden bandit detection

-------------------------------------------------------------------------------
-- Shared timestamps for throttling movement decisions
-------------------------------------------------------------------------------
local hidden_bandits_t = 0  -- last time a hidden bandit was detected
local seen_bandits_t   = 0  -- last time we saw a live bandit in the room
local new_room_t       = 0  -- last time we moved to a new room

-------------------------------------------------------------------------------
-- Bandit regex (matches noun-level words in combat target names)
-------------------------------------------------------------------------------
local bandit_re = Regex.new("\\b(?:thief|rogue|bandit|mugger|outlaw|highwayman|marauder|brigand|thug|robber)\\b")

-------------------------------------------------------------------------------
-- Hidden-bandit detector via DownstreamHook
-- Watches <dialogData id='combat'> XML for new NPCs entering the combat window.
-- New bandit-type NPCs suggest one emerged from hiding.
-------------------------------------------------------------------------------
local old_ids = {}

DownstreamHook.add("banditpatrol_combat", function(line)
    -- Match the combat dialogData XML: extract content_text (names) and content_value (IDs)
    local text_str, value_str = line:match(
        "<dialogData id='combat'>[^>]*content_text=\"([^\"]*)\"[^>]*content_value=\"([^\"]+)\"")
    if not text_str or not value_str then return line end

    -- Build id→name map from this update
    local names = {}
    for s in text_str:gmatch("[^,]+") do names[#names + 1] = s end
    local ids = {}
    for s in value_str:gmatch("[^,]+") do ids[#ids + 1] = s end

    local current_map = {}
    for i, id in ipairs(ids) do
        current_map[id] = names[i] or ""
    end

    -- Check for IDs that are new since last update
    for id, npc_name in pairs(current_map) do
        if not old_ids[id] then
            -- New combat target — check if it's a bandit type
            if bandit_re:test(npc_name) then
                -- Skip dark-clad variants
                if not npc_name:find("dark%-clad") then
                    -- Skip animated variants (check live NPC list)
                    local is_animated = false
                    for _, npc in ipairs(GameObj.npcs()) do
                        if npc.name:find(npc_name, 1, true) and npc.name:find("animated") then
                            is_animated = true
                            break
                        end
                    end
                    if not is_animated then
                        -- Announce if not in Warcamp
                        local cur = Map.find_room(Map.current_room())
                        local area = cur and cur.location or ""
                        if not area:find("Warcamp") then
                            echo("new " .. npc_name .. " detected! ***")
                        end
                        hidden_bandits_t = os.time()
                    end
                end
            end
        end
    end

    -- Update tracked IDs
    old_ids = {}
    for id in pairs(current_map) do
        old_ids[id] = true
    end

    return line
end)

before_dying(function()
    DownstreamHook.remove("banditpatrol_combat")
end)

-------------------------------------------------------------------------------
-- Bounty validation
-------------------------------------------------------------------------------
local bounty = Bounty.parse()
if not bounty or bounty.type ~= "bandits" then
    echo("You do not have a bandit bounty!")
    return
end

local bounty_area = bounty.area
if not bounty_area or bounty_area == "" then
    echo("Could not determine bounty area from task. Aborting.")
    return
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
fput("flag GroupMovement on")
echo("Bandit patrol will begin in 5 seconds...")
echo(" ")
pause(5)

-------------------------------------------------------------------------------
-- Bad locations / bad rooms (Kharam-Dzu conflict rooms)
-------------------------------------------------------------------------------
local BAD_LOCATION = "the town of Kharam%-Dzu"
local bad_rooms = {
    [10815]=true, [10816]=true, [10817]=true, [10818]=true, [10819]=true,
    [10820]=true, [10821]=true, [10832]=true, [10833]=true, [10834]=true,
    [10835]=true,
}

-------------------------------------------------------------------------------
-- Build room list: all rooms whose location matches the bounty area,
-- excluding Kharam-Dzu and the hard-coded bad room IDs.
-------------------------------------------------------------------------------
local location_re = Regex.new("(?i)" .. bounty_area)

local function build_rooms_list()
    local all_ids = Map.list()
    local result = {}
    for _, id in ipairs(all_ids) do
        if not bad_rooms[id] then
            local room = Map.find_room(id)
            if room and type(room.location) == "string"
                    and location_re:test(room.location)
                    and not room.location:find(BAD_LOCATION) then
                result[#result + 1] = id
            end
        end
    end
    return result
end

local rooms_list = build_rooms_list()

-- Convert to set for O(1) deletion
local function list_to_set(t)
    local s = {}
    for _, v in ipairs(t) do s[v] = true end
    return s
end

local function set_to_list(s)
    local t = {}
    for v in pairs(s) do t[#t + 1] = v end
    return t
end

local rooms_set = list_to_set(rooms_list)

-------------------------------------------------------------------------------
-- Navigate to starting room for certain special areas
-------------------------------------------------------------------------------
if bounty_area:find("Fhorian Village") then
    Script.run("go2", "2066")
elseif bounty_area:find("Greymist Woods") then
    Script.run("go2", "1998")
elseif bounty_area:find("old Logging Road") then
    Script.run("go2", "1995")
end

-------------------------------------------------------------------------------
-- Main patrol loop
-------------------------------------------------------------------------------
while true do
    local b = Bounty.parse()
    if not b or b.done then
        break
    end

    -- Wait while live bandits are in the room (let attack scripts work)
    local npcs = GameObj.npcs()
    local has_bandits = false
    for _, npc in ipairs(npcs) do
        if npc:type_p("bandit") then
            has_bandits = true
            break
        end
    end
    if has_bandits then
        seen_bandits_t = os.time()
        pause(0.1)
        goto continue
    end

    waitrt()
    waitcastrt()

    -- Decide whether to move to the next room
    local shouldgo = true
    local reason = nil

    local now = os.time()

    if now - new_room_t < 1 then
        shouldgo = false
    end
    if now - seen_bandits_t < 3 then
        shouldgo = false
    end
    if now - hidden_bandits_t < 5 then
        shouldgo = false
    end

    -- Don't move if a group member is in distress (stunned, dead, webbed, etc.)
    if shouldgo then
        local cur = Map.find_room(Map.current_room())
        if cur and type(cur.location) == "string"
                and location_re:test(cur.location) then
            for _, pc in ipairs(GameObj.pcs()) do
                if pc.status and Regex.test(
                        "stunned|dead|sitting|kneeling|prone|lying down|webbed|calmed",
                        pc.status) then
                    shouldgo = false
                    break
                end
            end
        end
    end

    -- Don't move if there are gems or coins on the ground
    if shouldgo then
        for _, item in ipairs(GameObj.loot()) do
            if item:type_p("gem") or (item.name and item.name:find("coins")) then
                shouldgo = false
                reason = "gems or coins on the ground"
                break
            end
        end
    end

    if shouldgo then
        local current_id = Map.current_room()
        local rooms_arr = set_to_list(rooms_set)

        local nearest = Map.find_nearest_room(current_id, rooms_arr)

        -- If no nearest found, or path is longer than 1 step, rebuild the list
        if not nearest then
            rooms_set = list_to_set(build_rooms_list())
            rooms_arr = set_to_list(rooms_set)
            nearest = Map.find_nearest_room(current_id, rooms_arr)
        else
            -- Check path length: if more than 1 step away, rebuild
            local path = Map.find_path(current_id, nearest.id)
            if path and #path > 1 then
                rooms_set = list_to_set(build_rooms_list())
                rooms_arr = set_to_list(rooms_set)
                nearest = Map.find_nearest_room(current_id, rooms_arr)
            end
        end

        if nearest then
            -- Remove this room from the patrol set
            rooms_set[nearest.id] = nil
            Script.run("go2", tostring(nearest.id))
            new_room_t = os.time()
        end
    else
        if reason then
            echo(reason)
            pause(3)
        else
            pause(0.1)
        end
    end

    ::continue::
end

echo("You're done with your task!")
