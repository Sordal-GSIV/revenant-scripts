-- osacrew/nav.lua
-- Navigation functions: flag checks, destination menu, route execution,
-- course-keeping loop, drift correction, mast unfurling, sail-casting.
-- Original: osacrew.lic (Lich5), lines 1725-2300, 1905-1914, 1951-2091, 2844-2893.
-- Ported to Revenant Lua by osacrew conversion.

local N = {}

-- ---------------------------------------------------------------------------
-- Internal timing helper
-- ---------------------------------------------------------------------------

-- Format a float number of minutes into "HH:MM" style string.
local function format_time(minutes)
    local h = math.floor(minutes / 60)
    local m = math.floor(minutes % 60)
    return string.format("%02d:%02d", h, m)
end

-- Compute total wheel turns from a route table (sum of all count values).
local function total_turns(route)
    local sum = 0
    for _, pair in ipairs(route) do
        sum = sum + pair[1]
    end
    return sum
end

-- ---------------------------------------------------------------------------
-- Leg-timing recorder
-- Called from crew_keep_course to record a leg travel time and update averagetime.
-- osa.{Slooptimes,Brigtimes,...} are arrays of float minutes.
-- ---------------------------------------------------------------------------
local TIMES_KEY = {
    ["sloop"]       = "Slooptimes",
    ["brigantine"]  = "Brigtimes",
    ["carrack"]     = "Cartimes",
    ["galleon"]     = "Galtimes",
    ["frigate"]     = "Fritimes",
    ["man o' war"]  = "Mantimes",
}

local function record_leg_time(osa, elapsed_minutes)
    local k = TIMES_KEY[osa.ship_type]
    if not k then return end
    if not osa[k] then
        osa[k] = { 0.35 }
    end
    table.insert(osa[k], elapsed_minutes)
    -- Cap at 50 entries
    while #osa[k] > 50 do
        table.remove(osa[k], 1)
    end
    local sum = 0
    for _, v in ipairs(osa[k]) do sum = sum + v end
    osa.averagetime = sum / #osa[k]
end

-- ---------------------------------------------------------------------------
-- 1. ship_flag()
-- ---------------------------------------------------------------------------
-- Checks the ship's flag.  If not white, navigates to crow's nest and raises
-- a white flag.
-- Source: .lic lines 1905-1914.

function N.ship_flag(osa, Map)
    fput("ship flag")
    local result = matchtimeout(5,
        "is currently flying",
        "Valid options:")
    if result and string.find(result, "is currently flying") then
        -- Extract what flag is flying: "is currently flying a white flag." etc.
        if not string.find(result, "white") then
            -- Go to crow's nest and raise white flag
            if Map then
                Map.crows_nest(osa)
            end
            fput("ship flag white")
            waitrt()
        end
    end
end

-- ---------------------------------------------------------------------------
-- 2. crew_nav_destination(osa, nearest_town, routes)
-- ---------------------------------------------------------------------------
-- Presents a numbered destination menu replacing the current origin city.
-- Gets user input via get(), sets osa.course and calculates estimated trip time.
-- Returns selected destination name and route table, or nil on quit.
-- Source: .lic lines 1758-1868.

function N.crew_nav_destination(osa, nearest_town, routes)
    -- Build city list; replace one slot with the current origin so it's absent
    local cities = {
        "Icemule Trace",
        "Wehnimer's Landing",
        "Brisker's Cove",
        "Solhaven",
        "River's Rest",
        "Kharam Dzu",
        "Nielira Harbor",
        "Ta'Vaalor",
    }

    -- Replace the city matching nearest_town with Kraken's Fall
    -- (mirroring the .lic logic: the origin city's slot becomes Kraken's Fall)
    for i, city in ipairs(cities) do
        if city == nearest_town then
            cities[i] = "Kraken's Fall"
            break
        end
    end

    respond("")
    respond("=======================================")
    respond("Please Select A Destination Captain?")
    for i, city in ipairs(cities) do
        respond(string.format("    %d. %s", i, city))
    end
    respond("=======================================")
    respond("Select a destination - ;send <#> or 0 to Quit")
    respond("")

    clear()

    -- Wait for a numeric input
    local line = nil
    repeat
        line = get()
    until line and line:match("^%s*%d+%s*$")

    local choice = tonumber(line:match("%d+"))
    if not choice or choice == 0 then
        echo("[osacrew/nav] Destination selection cancelled.")
        return nil, nil
    end
    if choice < 1 or choice > #cities then
        echo("[osacrew/nav] Those Are Uncharted Waters, Captain!")
        return nil, nil
    end

    local dest = cities[choice]
    echo("Set course to " .. dest .. " from " .. nearest_town)
    osa.dest = dest
    osa.nearest_town = nearest_town
    osa.start_time = os.clock()

    -- Retrieve the route
    local origin_routes = routes[nearest_town]
    if not origin_routes then
        echo("[osacrew/nav] No routes defined from " .. nearest_town)
        return nil, nil
    end
    local route = origin_routes[dest]
    if not route then
        echo("[osacrew/nav] No route from " .. nearest_town .. " to " .. dest)
        return nil, nil
    end

    -- Calculate estimated trip time
    local turns = total_turns(route)
    local avg = osa.averagetime or 0.35
    local est_minutes = turns * avg
    osa.estimated_trip_time = est_minutes
    osa.total_moves = turns

    respond(string.format("Estimated Trip Time: %s", format_time(est_minutes)))
    respond(string.format("Estimated Arrival:   ~%d wheel turns @ %.3f min/turn", turns, avg))

    return dest, route
end

-- ---------------------------------------------------------------------------
-- 3. crew_start_nav(osa, Map, routes)
-- ---------------------------------------------------------------------------
-- Goes to helm, issues "look ocean" to detect nearest port,
-- calls crew_nav_destination.
-- Source: .lic lines 1725-1756.

function N.crew_start_nav(osa, Map, routes)
    N.ship_flag(osa, Map)
    Map.helm(osa)
    pause(1)

    fput("look ocean")
    local check_city = matchtimeout(5,
        "Potential docking options include",
        "Open waters:",
        "Obvious paths:")

    local nearest_town = nil
    if check_city and string.find(check_city, "Potential docking options include") then
        if string.find(check_city, "a bustling port") then
            nearest_town = "Kraken's Fall"
        elseif string.find(check_city, "a diverse port") then
            nearest_town = "Solhaven"
        elseif string.find(check_city, "a lively port") then
            nearest_town = "Wehnimer's Landing"
        elseif string.find(check_city, "an idle port") then
            nearest_town = "River's Rest"
        elseif string.find(check_city, "an ash%-covered port") then
            nearest_town = "Kharam Dzu"
        elseif string.find(check_city, "a sprawling imperial port") then
            nearest_town = "Brisker's Cove"
        elseif string.find(check_city, "a ramshackle port") then
            nearest_town = "Icemule Trace"
        elseif string.find(check_city, "an industrious port") then
            nearest_town = "Ta'Vaalor"
        elseif string.find(check_city, "a naefira and ivy%-draped port") then
            nearest_town = "Nielira Harbor"
        end
    end

    if not nearest_town then
        -- Ship may already be underway; launch osacommander underway handler
        Script.run("osacommander", "underway")
        wait_while(function() return Script.running("osacommander") end)
        -- Recurse after osacommander has resolved our position
        return N.crew_start_nav(osa, Map, routes)
    end

    osa.nearest_town = nearest_town
    return N.crew_nav_destination(osa, nearest_town, routes)
end

-- ---------------------------------------------------------------------------
-- 4. crew_navigation_array(osa, route, Map)
-- ---------------------------------------------------------------------------
-- Executes a route: for each {count, direction} pair, issues "turn wheel
-- {direction}" count times, calling crew_keep_course between each step.
-- Broadcasts LNet arrival message on completion.
-- Source: .lic lines 1871-1903.

function N.crew_navigation_array(osa, route, Map)
    local start_trip = os.clock()
    Map.helm(osa)

    -- Announce departure if commander
    if GameState.name == osa.commander then
        local turns = total_turns(route)
        local avg   = osa.averagetime or 0.35
        local est   = turns * avg
        local msg = string.format(
            "%s Expects To Make Way From %s And Will Be Moored In %s In Approx %s",
            osa.commander_ship_name or "The Ship",
            osa.nearest_town or "?",
            osa.dest or "?",
            format_time(est)
        )
        if LNet then
            LNet.send_message({ type = "channel", channel = osa.crew or "osacrew" }, msg)
        end
        waitrt()
        pause(0.2)
        fput("yell " .. msg)
    end

    respond(string.format("Estimated Trip Time: %s", format_time(osa.estimated_trip_time or 0)))

    -- Execute each leg
    for _, pair in ipairs(route) do
        local count     = pair[1]
        local direction = pair[2]
        osa.course = direction
        fput("turn wheel " .. direction)
        for _ = 1, count do
            N.crew_keep_course(osa, Map)
        end
    end

    local end_trip = os.clock()
    local actual_minutes = (end_trip - start_trip) / 60.0

    respond("")
    respond(string.format("Estimated Trip Time Was: %s", format_time(osa.estimated_trip_time or 0)))
    respond(string.format("Actual Trip Time:         %s", format_time(actual_minutes)))
end

-- ---------------------------------------------------------------------------
-- 5. crew_keep_course(osa, Map)
-- ---------------------------------------------------------------------------
-- Main sail-keeping loop.  Waits for ship movement events and handles:
--   - Normal movement: record leg time
--   - Rogue wave: helm + raise_anchor + recurse
--   - Sails furled: yell + kick capstan + unfurl + raise_anchor + recurse
--   - Off-course drift: det_drift + fix_wheel + recurse
--   - Arrival (drifts toward): record time, broadcast, update gangplank, exit
-- Source: .lic lines 2104-2278.

function N.crew_keep_course(osa, Map)
    local sail_begin = os.clock()

    local result = matchtimeout(300,
        "cuts through the ocean, heading",
        "drifts slowly",
        "A large swell crashes into the side of the",
        "The sound of ropes coming free of the rigging",
        "suddenly drifts from its course as the",
        "drifts steadily toward the")

    if not result then
        echo("[osacrew/nav] crew_keep_course: timed out waiting for ship event")
        return
    end

    -- ── Normal movement (ship is moving on course) ──────────────────────────
    if string.find(result, "cuts through the ocean, heading") or
       string.find(result, "drifts slowly") then
        local sail_end      = os.clock()
        local elapsed_min   = (sail_end - sail_begin) / 60.0
        record_leg_time(osa, elapsed_min)
        waitrt()
        return
    end

    -- ── Rogue wave ───────────────────────────────────────────────────────────
    if string.find(result, "A large swell crashes into the side of the") then
        waitrt()
        fput("yell Rogue Wave! Secure the Anchor!")
        Map.helm(osa)
        waitrt()
        waitcastrt()
        N.raise_anchor()
        N.crew_keep_course(osa, Map)
        return
    end

    -- ── Sails furled ─────────────────────────────────────────────────────────
    if string.find(result, "The sound of ropes coming free of the rigging") then
        waitrt()
        fput("yell The Sails Have Furled, Let Go the Halyard, Sheets, and Braces!")
        Map.helm(osa)
        waitrt()
        fput("kick capstan")
        waitrt()
        Map.main_deck(osa)
        N.crew_how_many_masts(osa, function(count)
            if count == 1 then
                N.one_mast(osa, Map)
            elseif count == 2 then
                N.two_masts(osa, Map)
            else
                N.three_masts(osa, Map)
            end
        end)
        N.raise_anchor()
        N.crew_keep_course(osa, Map)
        return
    end

    -- ── Off-course drift ─────────────────────────────────────────────────────
    if string.find(result, "suddenly drifts from its course as the") then
        echo("[osacrew/nav] The Ship Has Gone Off Course")
        waitrt()
        Map.helm(osa)
        waitcastrt()
        N.crew_det_drift(osa)
        echo("[osacrew/nav] Corrective Course Determined")
        N.crew_fix_wheel(osa, Map)
        waitrt()
        if osa.ph_corrected ~= "None" then
            N.crew_keep_course(osa, Map)
        end
        return
    end

    -- ── Arrival: drifts toward port ──────────────────────────────────────────
    if string.find(result, "drifts steadily toward the") then
        local sail_end    = os.clock()
        local elapsed_min = (sail_end - sail_begin) / 60.0
        record_leg_time(osa, elapsed_min)
        waitrt()

        respond("Liberty Call! Liberty Call!")

        local start_trip    = osa.start_time or sail_begin
        local actual_min    = (sail_end - start_trip) / 60.0
        respond(string.format("Estimated Trip Time Was: %s", format_time(osa.estimated_trip_time or 0)))
        respond(string.format("Actual Trip Time:         %s", format_time(actual_min)))

        Map.main_deck(osa)

        -- Detect gangplank room from "look ocean"
        fput("look ocean")
        local ocean_result = matchtimeout(5,
            "%([0-9,]+%)",
            "Open waters:",
            "Obvious paths:")
        if ocean_result then
            local uid_str = ocean_result:match("%(([0-9,]+)%)")
            if uid_str then
                -- Remove commas from UID, look up room
                local uid = "u" .. uid_str:gsub(",", "")
                local gp_room = Map.find_room(uid)
                if gp_room then
                    osa.gangplank_id    = gp_room.id
                    osa.gangplank_title = (gp_room.title or "")
                    osa.gangplank_city  = (gp_room.location or osa.dest or "")
                end
            end
        end

        -- Disembark and re-map gangplank
        fput("push gang")
        if GameState.name == osa.commander then
            local msg = string.format(
                "The Ship Is Now Moored In %s. Room: %s %s. Trip Was ~%s, Actual: %s",
                osa.gangplank_city or osa.dest or "?",
                tostring(osa.gangplank_id or "?"),
                osa.gangplank_title or "",
                format_time(osa.estimated_trip_time or 0),
                format_time(actual_min)
            )
            if LNet then
                LNet.send_message({ type = "channel", channel = osa.crew or "osacrew" }, msg)
            end
        end

        -- Clear old gangplank tags and set new ones
        if osa.gangplank then
            local old_room = Map.find_room(osa.gangplank)
            if old_room and old_room.tags then
                for i, t in ipairs(old_room.tags) do
                    if t == "myship" then
                        table.remove(old_room.tags, i)
                        break
                    end
                end
            end
        end

        -- Import Map module functions for gangplank management
        local ok, MapMod = pcall(require, "gs/osacrew/map")
        if ok and osa.gangplank_id then
            osa.gangplank = osa.gangplank_id
            MapMod.crew_clear_gangplank(osa)
            -- Tag new gangplank room
            local new_room = Map.find_room(osa.gangplank)
            if new_room then
                new_room.tags = new_room.tags or {}
                local has_tag = false
                for _, t in ipairs(new_room.tags) do
                    if t == "myship" then has_tag = true break end
                end
                if not has_tag then table.insert(new_room.tags, "myship") end
            end
            MapMod.crew_map_gangplank(osa)
        end

        -- Signal arrival to main script (set a flag that the main loop checks)
        osa.arrived = true
        return
    end
end

-- ---------------------------------------------------------------------------
-- 6. crew_det_drift(osa)
-- ---------------------------------------------------------------------------
-- Determines the corrective course by reading the drift direction message.
-- Sets osa.ph_corrected to the opposite cardinal direction, or "None".
-- Source: .lic lines 2029-2065.

local OPPOSITE = {
    northeast = "southwest",
    northwest = "southeast",
    southwest = "northeast",
    southeast = "northwest",
    north     = "south",
    south     = "north",
    west      = "east",
    east      = "west",
}

function N.crew_det_drift(osa)
    echo("[osacrew/nav] Determining Corrective Course")
    local result = matchtimeout(300,
        "wheel slowly turns off course",
        "cuts through the ocean, heading",
        "drifts slowly")
    if not result then
        osa.ph_corrected = "None"
        return
    end

    if string.find(result, "wheel slowly turns off course") then
        osa.ph_corrected = "None"
        echo("[osacrew/nav] Corrective: None (wheel off course)")
        return
    end

    -- Extract direction from: "The <ship> cuts through the ocean, heading <dir>"
    -- or: "The <ship> drifts slowly <dir>"
    local dir = result:match("heading (%a+)") or result:match("drifts slowly (%a+)")
    if not dir then
        osa.ph_corrected = "None"
        return
    end

    if dir == osa.course then
        osa.ph_corrected = "None"
    else
        osa.ph_corrected = OPPOSITE[dir] or "None"
    end
    echo("[osacrew/nav] Corrective course: " .. osa.ph_corrected)
end

-- ---------------------------------------------------------------------------
-- 7. crew_fix_wheel(osa, Map)
-- ---------------------------------------------------------------------------
-- Issues corrective wheel turn and resumes course-keeping.
-- Source: .lic lines 2067-2091.

function N.crew_fix_wheel(osa, Map)
    echo("[osacrew/nav] Taking Corrective Course")
    if osa.ph_corrected == "None" then
        fput("turn wheel " .. (osa.course or "north"))
        N.crew_keep_course(osa, Map)
        return
    end

    local result = dothistimeout(
        "turn wheel " .. osa.ph_corrected,
        300,
        "cuts through the ocean, heading",
        "drifts slowly",
        "The sound of ropes coming free of the rigging",
        "A large swell crashes into the side of the",
        "suddenly drifts from its course as the"
    )

    if not result then return end

    if string.find(result, "cuts through the ocean, heading") or
       string.find(result, "drifts slowly") then
        waitrt()
        echo("[osacrew/nav] Resuming Original Course")
        waitrt()
        return
    end

    if string.find(result, "The sound of ropes coming free of the rigging") then
        echo("[osacrew/nav] The Sails Have Been Furled")
        N.crew_how_many_masts(osa, function(count)
            if count == 1 then
                N.one_mast(osa, Map)
            elseif count == 2 then
                N.two_masts(osa, Map)
            else
                N.three_masts(osa, Map)
            end
        end)
        return
    end

    if string.find(result, "A large swell crashes into the side of the") then
        echo("[osacrew/nav] Rogue Wave! Secure that Anchor!")
        N.raise_anchor()
        return
    end

    if string.find(result, "suddenly drifts from its course as the") then
        respond("[osacrew/nav] The Ship's Gone Off Course Captain!")
        N.crew_det_drift(osa)
        echo("[osacrew/nav] Corrective Course Determined")
        N.crew_fix_wheel(osa, Map)
        return
    end
end

-- ---------------------------------------------------------------------------
-- 8. crew_how_many_masts(osa, unfurl_masts_fn)
-- ---------------------------------------------------------------------------
-- Determines mast count from ship type and calls unfurl_masts_fn(count).
-- Source: .lic lines 2281-2290 (crew_get_underway mast selection logic).

function N.crew_how_many_masts(osa, unfurl_masts_fn)
    local st = osa.ship_type
    if st == "sloop" then
        unfurl_masts_fn(1)
    elseif st == "brigantine" or st == "carrack" or
           st == "galleon"    or st == "frigate" then
        unfurl_masts_fn(2)
    elseif st == "man o' war" then
        unfurl_masts_fn(3)
    else
        echo("[osacrew/nav] crew_how_many_masts: unknown ship type '" .. tostring(st) .. "'")
        unfurl_masts_fn(1)
    end
end

-- ---------------------------------------------------------------------------
-- Mast-unfurling helpers
-- These correspond to one_mast / two_masts / three_masts in the .lic.
-- They navigate between deck rooms to lower each sail, yelling status.
-- Source: .lic lines 1951-2027.
-- ---------------------------------------------------------------------------

-- lower_sail: issues "lower sail" until sail is fully open.
function N.lower_sail(osa)
    local result = dothistimeout("lower sail", 3,
        "you slowly lower the .* sail until it is at half mast",
        "you slowly lower the .* sail until it is fully open",
        "far as it can go!")
    waitrt()
    if not result then return end
    if string.find(result, "wait") then
        waitrt()
        N.lower_sail(osa)
    elseif string.find(result, "at half mast") then
        waitrt()
        N.lower_sail(osa)
    elseif string.find(result, "fully open") then
        osa.lowered_sail = true
        waitrt()
    end
    -- "far as it can go" = already open, no state change needed
end

-- raise_anchor: pushes capstan until anchor is up.
function N.raise_anchor()
    local result = dothistimeout("push capstan", 3,
        "begin to push",
        "one final push",
        "anchor is already up")
    waitrt()
    if not result then return end
    if string.find(result, "wait") then
        waitrt()
        N.raise_anchor()
    elseif string.find(result, "begin to push") then
        waitrt()
        N.raise_anchor()
    elseif string.find(result, "one final push") then
        -- anchor is aweigh
        waitrt()
    end
    -- "anchor is already up" → return immediately
end

-- one_mast: unfurl main mast sail (sloop).
function N.one_mast(osa, Map)
    fput("pull gangplank")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        if GameState.name == osa.commander then
            fput("yell Main Mast Unfurled, She's Ready to Sail!")
        else
            fput("yell Main Mast Unfurled, She's Ready to Sail Captain!")
        end
        osa.lowered_sail = false
    end
    pause(0.5)
    move("west")
end

-- two_masts: unfurl main then fore mast (brigantine/carrack/galleon/frigate).
function N.two_masts(osa, Map)
    fput("pull gangplank")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        fput("yell Main Mast Unfurled")
        osa.lowered_sail = false
    end
    pause(0.5)
    move("east")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        if GameState.name == osa.commander then
            fput("yell Fore Mast Unfurled, She's Ready to Sail!")
        else
            fput("yell Fore Mast Unfurled, She's Ready to Sail Captain!")
        end
        osa.lowered_sail = false
    end
    pause(0.5)
    move("west")
    pause(0.5)
    move("west")
end

-- three_masts: unfurl mizzen, main, then fore mast (man o' war).
function N.three_masts(osa, Map)
    fput("pull gangplank")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        fput("yell Mizzen Mast Unfurled")
        osa.lowered_sail = false
    end
    pause(0.5)
    move("east")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        fput("yell Main Mast Unfurled")
        osa.lowered_sail = false
    end
    pause(0.5)
    move("east")
    N.lower_sail(osa)
    if osa.lowered_sail then
        waitrt()
        if GameState.name == osa.commander then
            fput("yell Fore Mast Unfurled, She's Ready to Sail!")
        else
            fput("yell Fore Mast Unfurled, She's Ready to Sail Captain!")
        end
        osa.lowered_sail = false
    end
    pause(0.5)
    move("west")
    pause(0.5)
    move("west")
    pause(0.5)
    move("west")
end

-- ---------------------------------------------------------------------------
-- 9. cast_sails()
-- ---------------------------------------------------------------------------
-- Casts Spell 912 or 612 on the sail if the character knows either spell.
-- Source: .lic lines 2844-2853.

function N.cast_sails()
    if Spell[912] and Spell[912].known then
        Spell[912]:cast("sail")
    end
    if Spell[612] and Spell[612].known then
        Spell[612]:cast("sail")
    end
    waitrt()
    waitcastrt()
end

-- ---------------------------------------------------------------------------
-- 10. winded_sails(osa, Map)
-- ---------------------------------------------------------------------------
-- While osa.winded is truthy, visits each deck that has a sail and casts the
-- winded spell (cast_sails).  Loops 10 times checking, then recurses.
-- Source: .lic lines 2865-2893.

function N.check_winded(osa, Map)
    if osa.winded then
        pause(5)
    else
        Map.main_deck(osa)
    end
end

function N.winded_sails(osa, Map)
    if not osa.winded then
        Map.main_deck(osa)
        return
    end

    -- Main deck sail
    Map.main_deck(osa)
    N.cast_sails()

    if not osa.winded then
        Map.main_deck(osa)
        return
    end

    -- Mid deck sail (man o' war only)
    local has_mid = false
    if osa.ship_map then
        for _, tag in ipairs(osa.ship_map) do
            if tag == "mid_deck" then has_mid = true break end
        end
    end
    if has_mid then
        Map.mid_deck(osa)
        N.cast_sails()
    end

    if not osa.winded then
        Map.main_deck(osa)
        return
    end

    -- Forward deck sail
    local has_fwd = false
    if osa.ship_map then
        for _, tag in ipairs(osa.ship_map) do
            if tag == "forward_deck" then has_fwd = true break end
        end
    end
    if has_fwd then
        Map.forward_deck(osa)
        N.cast_sails()
    end

    -- Poll 10 times then recurse
    for _ = 1, 10 do
        N.check_winded(osa, Map)
    end
    N.winded_sails(osa, Map)
end

return N
