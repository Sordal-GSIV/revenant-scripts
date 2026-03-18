-- OSACrew Damage Control / Repair Module
-- Original: osacrew.lic lines 1306-1478
-- Implements ship repair: damage_control dispatcher, room scanning,
-- wood retrieval from cargo hold, and the fix_ship loop.

local M = {}

-- ---------------------------------------------------------------------------
-- Room-name → map tag table used by check_rooms to prune the repair list.
-- The .lic source uses a case/when on the assess output and deletes entries
-- by tag string from @repair_map.
-- ---------------------------------------------------------------------------

local ROOM_TAG_PATTERNS = {
    { pattern = "Main Deck:%s+You cannot seem",          tag = "main_deck"           },
    { pattern = "Helm:%s+You cannot seem",               tag = "helm"                },
    { pattern = "Cargo Hold:%s+You cannot seem",         tag = "cargo_hold"          },
    { pattern = "Captain's Quarters:%s+You cannot seem", tag = "captains_quarters"   },
    { pattern = "Forward Crow's Nest:%s+You cannot seem",tag = "forward_crows_nest"  },
    { pattern = "Crow's Nest:%s+You cannot seem",        tag = "crows_nest"          },
    { pattern = "Mess Hall:%s+You cannot seem",          tag = "mess_hall"           },
    { pattern = "Mid Deck:%s+You cannot seem",           tag = "mid_deck"            },
    { pattern = "Crew Quarters:%s+You cannot seem",      tag = "crew_quarters"       },
    { pattern = "Bow:%s+You cannot seem",                tag = "bow"                 },
    { pattern = "Social Room:%s+You cannot seem",        tag = "social_room"         },
    { pattern = "Forward Deck:%s+You cannot seem",       tag = "forward_deck"        },
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Remove a tag from the repair_map array in-place.
local function remove_tag(repair_map, tag)
    for i = #repair_map, 1, -1 do
        if repair_map[i] == tag then
            table.remove(repair_map, i)
        end
    end
end

-- Test whether the current room has the given tag.
local function in_room_tag(tag)
    local cur = Room.current()
    if not cur or not cur.tags then return false end
    for _, t in ipairs(cur.tags) do
        if t == tag then return true end
    end
    return false
end

-- Navigate to tag if not already there.
local function ensure_room(tag)
    if not in_room_tag(tag) then
        Map.go2(tag)
    end
end

-- ---------------------------------------------------------------------------
-- M.damage_control(osa, navigation_fns, save_fn)
-- Main repair dispatcher.
-- Source: lines 1308-1340
-- ---------------------------------------------------------------------------

function M.damage_control(osa, navigation_fns, save_fn)
    if osa["$osa_osacrewtasks"] then
        -- Stop combat if running
        wait_while(function() return Script.running("osacombat") end)

        -- Stow anything in hands
        local lh = GameObj.left_hand()
        local rh = GameObj.right_hand()
        if lh or rh then
            fput("store both")
        end

        -- Navigate to main deck and build the ship map, then repair
        Map.go2("main_deck")
        M.ship_map(osa)
        M.begin_repairs(osa, navigation_fns)

        -- Stow any remaining wood in cargo hold
        lh = GameObj.left_hand()
        rh = GameObj.right_hand()
        if lh or rh then
            Map.go2("cargo_hold")
            lh = GameObj.left_hand()
            if lh then fput("put left in wood") end
            rh = GameObj.right_hand()
            if rh then fput("put right in wood") end
        end

        -- Return to main deck and report hull status
        Map.go2("main_deck")
        if osa._out_of_wood then
            echo("The Hull Is Repaired As Much As Possible. However, We Are Out Of Shoring Planks Captain!")
        elseif osa._out_of_wood == false then
            echo("The Hull Is Repaired Captain!")
        end
    else
        echo("You Are Not Currently In A Crew Role, Please Standby To Standby!")
    end

    Map.go2("captains_quarters")
    -- Signal crew task completion
    if navigation_fns and navigation_fns.crew_task_complete then
        navigation_fns.crew_task_complete(osa)
    end
end

-- ---------------------------------------------------------------------------
-- M.ship_map(osa)
-- Populate osa._ship_map from osa["$osa_ship_map"].
-- Called before begin_repairs; the Ruby original sets @repair_map from
-- $osa_data["$osa_ship_map"].
-- ---------------------------------------------------------------------------

function M.ship_map(osa)
    -- Clone the configured ship map into a working list for this repair run
    local configured = osa["$osa_ship_map"]
    osa._ship_map = {}
    if type(configured) == "table" then
        for _, v in ipairs(configured) do
            table.insert(osa._ship_map, v)
        end
    end
end

-- ---------------------------------------------------------------------------
-- M.begin_repairs(osa, nav_fns)
-- Iterate ship map rooms: prune already-repaired rooms, then fix each one.
-- Source: lines 1342-1375
-- ---------------------------------------------------------------------------

function M.begin_repairs(osa, nav_fns)
    pause(0.5)
    osa._repairs_complete = false
    osa._out_of_wood      = false

    -- Build working repair list from the ship map populated by ship_map()
    local repair_map = {}
    if type(osa._ship_map) == "table" then
        for _, v in ipairs(osa._ship_map) do
            table.insert(repair_map, v)
        end
    end

    -- Prune rooms that are already at full health
    M.check_rooms(osa, repair_map)

    if osa._repairs_complete then return end

    for _, repair_room in ipairs(repair_map) do
        osa._fixed       = false
        osa._repair_room = repair_room

        if osa._out_of_wood then break end
        if osa._repairs_complete then break end

        -- Navigate to the repair room
        ensure_room(repair_room)

        waitrt()
        local result = dothistimeout(
            "assess",
            3,
            "It appears to be",
            "You cannot seem to find any damage"
        )

        if result and result:find("It appears to be") then
            waitrt()
            M.fix_ship(osa, repair_room, nav_fns)
        elseif result and result:find("You cannot seem to find any damage") then
            -- Check the next line for full-health report
            local health_line = get()
            if health_line then
                local cur, max = health_line:match("%[Health of your ship: (%d+)/(%d+)%]")
                if cur and max and cur == max then
                    waitrt()
                    osa._repairs_complete = true
                    return
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- M.check_rooms(osa, repair_map)
-- Issue a full "assess" and read lines.  Remove rooms that need no repair.
-- If ship health is X/X, set repairs_complete = true.
-- Source: lines 1377-1418
-- ---------------------------------------------------------------------------

function M.check_rooms(osa, repair_map)
    fput("assess")

    while true do
        local line = get()
        if not line then break end

        -- Check for rooms that are already repaired
        local removed = false
        for _, entry in ipairs(ROOM_TAG_PATTERNS) do
            if line:find(entry.pattern) then
                remove_tag(repair_map, entry.tag)
                removed = true
                break
            end
        end

        if not removed then
            -- Full health check: [Health of your ship: X/X]
            local cur, max = line:match("%[Health of your ship: (%d+)/(%d+)%]")
            if cur and max and cur == max then
                waitrt()
                osa._repairs_complete = true
                return
            end

            -- Roundtime line signals end of assess output
            if line:find("Roundtime:") then
                return
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- M.get_wood(osa, repair_room, nav_fns)
-- If both hands full, navigate to repair_room and return.
-- Otherwise go to cargo hold and retrieve wood.
-- Source: lines 1420-1443
-- ---------------------------------------------------------------------------

function M.get_wood(osa, repair_room, nav_fns)
    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if lh and rh then
        -- Hands full; return to repair room
        ensure_room(repair_room)
        return
    end

    Map.go2("cargo_hold")

    local result = dothistimeout(
        "get wood",
        3,
        "You will need a free",
        "You search through the salvaged wood and",
        "You search through the salvaged wood only",
        "...wait"
    )

    if not result then return end

    if result:find("You will need a free") then
        M.get_wood(osa, repair_room, nav_fns)
    elseif result:find("You search through the salvaged wood and") then
        waitrt()
        M.get_wood(osa, repair_room, nav_fns)
    elseif result:find("You search through the salvaged wood only") then
        waitrt()
        osa._out_of_wood = true
    elseif result:find("%.%.%.wait") then
        pause(1)
        waitrt()
        M.get_wood(osa, repair_room, nav_fns)
    end
end

-- ---------------------------------------------------------------------------
-- M.fix_ship(osa, repair_room, nav_fns)
-- Fix damage in current room; recurse until fully fixed or hands empty.
-- Source: lines 1445-1478
-- ---------------------------------------------------------------------------

function M.fix_ship(osa, repair_room, nav_fns)
    if osa._fixed then return end

    local lh = GameObj.left_hand()
    local rh = GameObj.right_hand()
    if not lh and not rh then
        waitrt()
        M.get_wood(osa, repair_room, nav_fns)
        if osa._out_of_wood then return end
        -- Navigate back to repair room after getting wood
        ensure_room(repair_room)
    end

    local result = dothistimeout(
        "fix",
        3,
        "...wait",
        "all the damage",
        "some of the damage",
        "This area does not look"
    )

    if not result then return end

    if result:find("%.%.%.wait") then
        pause(1)
        waitrt()
        M.fix_ship(osa, repair_room, nav_fns)
    elseif result:find("all the damage") then
        osa._fixed = true
        waitrt()
        M.fix_ship(osa, repair_room, nav_fns)
    elseif result:find("some of the damage") then
        osa._fixed = false
        waitrt()
        M.fix_ship(osa, repair_room, nav_fns)
    elseif result:find("This area does not look") then
        osa._fixed = true
        waitrt()
        M.fix_ship(osa, repair_room, nav_fns)
    end
end

return M
