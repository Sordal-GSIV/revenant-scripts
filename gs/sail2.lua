--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: sail2
--- version: 1.0.1
--- author: Peggyanne
--- game: gs
--- description: Go2-style autopilot for OSA ocean shipboard travel using oceandb
--- tags: ocean,sailing,navigation,osa,autopilot
---
--- Changelog (from Lich5):
---   v1.0.1 (2026-03-14) - Added support for getting ship underway, added update support
---   v1.0.0 (2026-03-07) - Initial release
---
--- Usage:
---   ;sail2 <Port or UID>                    Sail to destination
---   ;sail2 <Port or UID> <Port or UID>      Display step-by-step route
---   ;sail2 update                           Download/update ocean mapdb files
---   ;sail2 list                             Show available ports
---   ;sail2 help                             Show this help
---
--- Available Ports:
---   Brisker's Cove      briskerscove     Glaoveln          glaoveln
---   Icemule Trace        icemule          Kraken's Fall     kraken
---   Wehnimer's Landing   landing          Sleeping Drake    ornath
---   Nielira Harbor       nielira          River's Rest      riversrest
---   Solhaven             solhaven         Teras Isle        teras
---   Ta'Vaalor            vaalor           Talon Isle        talon

no_kill_all()

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PORTS = {
    briskerscove = "7116594",
    glaoveln     = "7116863",
    icemule      = "7116870",
    kraken       = "7116096",
    landing      = "7116500",
    ornath       = "7143512",
    nielira      = "7137145",
    riversrest   = "7116700",
    solhaven     = "7116362",
    teras        = "7116279",
    vaalor       = "7137293",
    talon        = "7116648",
}

local PORT_NAMES = {
    ["7116594"] = "Brisker's Cove",
    ["7116863"] = "Glaoveln",
    ["7116870"] = "Icemule Trace",
    ["7116096"] = "Kraken's Fall",
    ["7116500"] = "Wehnimer's Landing",
    ["7143512"] = "Sleeping Drake Harbor",
    ["7137145"] = "Nielira Harbor",
    ["7116700"] = "River's Rest",
    ["7116362"] = "Solhaven",
    ["7116279"] = "Teras Isle",
    ["7137293"] = "Ta'Vaalor",
    ["7116648"] = "Talon Isle",
}

-- Ship type room ID ranges -> mast count
-- Sloop:       29039-29042  (1 mast)
-- Brigantine:  310145-310147 (2 masts) -- note: also 30142 area for deck tags
-- Carrack:     30119-30127  (2 masts)
-- Galleon:     30176-30185  (2 masts)
-- Frigate:     30166-30175  (2 masts)
-- Man-o-War:   30128-30139  (3 masts)

local SHIP_TYPES = {
    { name = "Sloop",       min = 29039,  max = 29042,  masts = 1 },
    { name = "Brigantine",  min = 310145, max = 310147, masts = 2 },
    { name = "Carrack",     min = 30119,  max = 30127,  masts = 2 },
    { name = "Galleon",     min = 30176,  max = 30185,  masts = 2 },
    { name = "Frigate",     min = 30166,  max = 30175,  masts = 2 },
    { name = "Man-o-War",   min = 30128,  max = 30139,  masts = 3 },
}

-- Sloop room tags
local SLOOP_TAGS = {
    { id = 29039, tags = { "cargo_hold" } },
    { id = 29038, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 29040, tags = { "crows_nest" } },
    { id = 29041, tags = { "helm" } },
    { id = 29042, tags = { "captains_quarters" } },
}

-- Brigantine room tags
local BRIGANTINE_TAGS = {
    { id = 30145, tags = { "cargo_hold" } },
    { id = 30142, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 30144, tags = { "forward_deck", "forward_mast", "forward_cannon" } },
    { id = 30143, tags = { "crows_nest" } },
    { id = 30147, tags = { "mess_hall" } },
    { id = 30146, tags = { "crew_quarters" } },
    { id = 30141, tags = { "helm" } },
    { id = 30140, tags = { "captains_quarters" } },
}

-- Carrack room tags
local CARRACK_TAGS = {
    { id = 30125, tags = { "cargo_hold" } },
    { id = 30119, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 30121, tags = { "forward_deck", "forward_mast", "forward_cannon" } },
    { id = 30122, tags = { "bow" } },
    { id = 30123, tags = { "crows_nest" } },
    { id = 30127, tags = { "mess_hall" } },
    { id = 30126, tags = { "crew_quarters" } },
    { id = 30120, tags = { "helm" } },
    { id = 30124, tags = { "captains_quarters" } },
}

-- Galleon room tags
local GALLEON_TAGS = {
    { id = 30182, tags = { "cargo_hold" } },
    { id = 30176, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 30177, tags = { "forward_deck", "forward_mast", "forward_cannon" } },
    { id = 30178, tags = { "bow" } },
    { id = 30181, tags = { "crows_nest" } },
    { id = 30185, tags = { "social_room" } },
    { id = 30184, tags = { "mess_hall" } },
    { id = 30183, tags = { "crew_quarters" } },
    { id = 30179, tags = { "helm" } },
    { id = 30180, tags = { "captains_quarters" } },
}

-- Frigate room tags
local FRIGATE_TAGS = {
    { id = 30167, tags = { "cargo_hold" } },
    { id = 30166, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 30171, tags = { "forward_deck", "forward_mast", "forward_cannon" } },
    { id = 30172, tags = { "bow" } },
    { id = 30173, tags = { "crows_nest" } },
    { id = 30170, tags = { "social_room" } },
    { id = 30169, tags = { "mess_hall" } },
    { id = 30168, tags = { "crew_quarters" } },
    { id = 30174, tags = { "helm" } },
    { id = 30175, tags = { "captains_quarters" } },
}

-- Man-o-War room tags
local MAN_O_WAR_TAGS = {
    { id = 30136, tags = { "cargo_hold" } },
    { id = 30130, tags = { "main_deck", "main_mast", "main_cannon" } },
    { id = 30131, tags = { "mid_deck", "mid_mast", "mid_cannon" } },
    { id = 30132, tags = { "forward_deck", "forward_mast", "forward_cannon" } },
    { id = 30133, tags = { "bow" } },
    { id = 30135, tags = { "crows_nest" } },
    { id = 30134, tags = { "forward_crows_nest" } },
    { id = 30139, tags = { "social_room" } },
    { id = 30138, tags = { "mess_hall" } },
    { id = 30137, tags = { "crew_quarters" } },
    { id = 30128, tags = { "helm" } },
    { id = 30129, tags = { "captains_quarters" } },
}

-- Enemy ship tags (shared across ship types encountering each enemy)
local ENEMY_SLOOP_TAGS = {
    { id = 30790, tags = { "enemy_cargo_hold" } },
    { id = 30787, tags = { "enemy_main_deck" } },
    { id = 30791, tags = { "enemy_crows_nest" } },
    { id = 30788, tags = { "enemy_helm" } },
    { id = 30789, tags = { "enemy_quarters" } },
}

local ENEMY_BRIGANTINE_TAGS = {
    { id = 30795, tags = { "enemy_cargo_hold" } },
    { id = 30792, tags = { "enemy_main_deck" } },
    { id = 30797, tags = { "enemy_forward_deck" } },
    { id = 30796, tags = { "enemy_crows_nest" } },
    { id = 30793, tags = { "enemy_helm" } },
    { id = 30794, tags = { "enemy_quarters" } },
}

local ENEMY_CARRACK_TAGS = {
    { id = 30269, tags = { "enemy_cargo_hold" } },
    { id = 30266, tags = { "enemy_main_deck" } },
    { id = 30271, tags = { "enemy_forward_deck" } },
    { id = 30272, tags = { "enemy_bow" } },
    { id = 30270, tags = { "enemy_crows_nest" } },
    { id = 30267, tags = { "enemy_helm" } },
    { id = 30268, tags = { "enemy_quarters" } },
}

local ENEMY_GALLEON_TAGS = {
    { id = 30801, tags = { "enemy_cargo_hold" } },
    { id = 30798, tags = { "enemy_main_deck" } },
    { id = 30803, tags = { "enemy_forward_deck" } },
    { id = 30804, tags = { "enemy_bow" } },
    { id = 30802, tags = { "enemy_crows_nest" } },
    { id = 30799, tags = { "enemy_helm" } },
    { id = 30800, tags = { "enemy_quarters" } },
}

local ENEMY_FRIGATE_TAGS = {
    { id = 30808, tags = { "enemy_cargo_hold" } },
    { id = 30805, tags = { "enemy_main_deck" } },
    { id = 30810, tags = { "enemy_forward_deck" } },
    { id = 30809, tags = { "enemy_crows_nest" } },
    { id = 30806, tags = { "enemy_helm" } },
    { id = 30807, tags = { "enemy_quarters" } },
}

local ENEMY_MAN_O_WAR_TAGS = {
    { id = 30781, tags = { "enemy_cargo_hold" } },
    { id = 30778, tags = { "enemy_main_deck" } },
    { id = 30783, tags = { "enemy_mid_deck" } },
    { id = 30786, tags = { "enemy_forward_deck" } },
    { id = 30784, tags = { "enemy_bow" } },
    { id = 30782, tags = { "enemy_crows_nest" } },
    { id = 30785, tags = { "enemy_forward_crows_nest" } },
    { id = 30779, tags = { "enemy_helm" } },
    { id = 30780, tags = { "enemy_quarters" } },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local current_room_id  = nil
local ocean_watch_started = false
local current_heading  = nil
local mast_count       = 0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function strip(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function lower(s)
    return s and string.lower(s) or ""
end

local function fatal(msg)
    echo("--- ERROR: " .. msg)
    -- Script exits naturally at end of file after fatal
    error(msg, 0)
end

local function valid_room_id(s)
    return tostring(s):match("^%d%d%d%d%d%d%d$") ~= nil
end

local function normalize_input(raw)
    local s = lower(strip(tostring(raw or "")))
    if s == "" then return "" end
    if PORTS[s] then return PORTS[s] end
    if valid_room_id(s) then return s end
    return ""
end

local function port_destination(room_id)
    local rid = tostring(room_id)
    for _, v in pairs(PORTS) do
        if v == rid then return true end
    end
    return false
end

local function table_has(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- go2 helper
--------------------------------------------------------------------------------

local function wait_for_go2()
    local deadline = os.time() + 30
    while running("go2") do
        if os.time() > deadline then
            echo("--- WARNING: go2 did not finish within 30 seconds.")
            return
        end
        pause(0.2)
    end
end

local function go2_tag(tag)
    Script.run("go2", tag)
    wait_for_go2()
    waitrt()
end

local function ensure_at_helm()
    local room = Room.current()
    if room and room.tags and table_has(room.tags, "helm") then return end

    echo("--- Moving to helm")
    go2_tag("helm")
end

--------------------------------------------------------------------------------
-- Ship type detection and room tagging
--------------------------------------------------------------------------------

local function detect_mast_count()
    local room_id = Room.id or 0
    for _, ship in ipairs(SHIP_TYPES) do
        if room_id >= ship.min and room_id <= ship.max then
            mast_count = ship.masts
            echo("--- Detected ship type: " .. ship.name .. " (" .. mast_count .. " mast(s))")
            return ship.name
        end
    end
    -- If not on a known room, try checking location
    local room = Room.current()
    if room and room.location == "Ships" then
        echo("--- On a ship but could not determine type from room ID " .. tostring(room_id))
    end
    return nil
end

-- Note: In Revenant, room tag manipulation would be handled by the map system.
-- These tag definitions are preserved for reference and can be applied when
-- the engine supports runtime tag injection. For now, go2 navigation within
-- ships relies on existing map data.

--------------------------------------------------------------------------------
-- Sail management
--------------------------------------------------------------------------------

local function lower_sail()
    while true do
        waitrt()
        local result = fput("lower sail",
            "you slowly lower the", "far as it can go")

        if not result then return end

        if string.find(result, "far as it can go") then
            return
        elseif string.find(result, "fully open") then
            waitrt()
            return
        elseif string.find(result, "half mast") then
            waitrt()
            -- Continue to lower further
        else
            return
        end
    end
end

local function raise_anchor()
    while true do
        waitrt()
        local result = fput("push capstan",
            "begin to push", "one final push", "anchor is already up")

        if not result then return end

        if string.find(result, "anchor is already up") then
            return
        elseif string.find(result, "one final push") then
            waitrt()
            return
        elseif string.find(result, "begin to push") then
            waitrt()
            -- Continue pushing
        else
            return
        end
    end
end

local function go2_mast(mast_tag)
    go2_tag(mast_tag)
end

local function ship_flag()
    fput("ship flag white")
    waitrt()
end

local function start_nav()
    ensure_at_helm()

    -- Check if we're already at sea or need to depart
    clear()
    fput("look ocean")
    pause(1)

    local at_sea = false
    local in_port = false

    for _ = 1, 20 do
        local line = get_noblock()
        if not line then break end
        if string.find(line, "Open waters:") or string.find(line, "Potential docking options") then
            at_sea = true
        elseif string.find(line, "Obvious paths:") then
            in_port = true
        end
    end

    if at_sea then
        ship_flag()
        return
    end

    if in_port then
        detect_mast_count()

        -- Lower sails on all masts
        if mast_count >= 1 then
            go2_mast("main_mast")
            fput("pull gang")
            lower_sail()
        end
        if mast_count >= 2 then
            go2_mast("forward_mast")
            lower_sail()
        end
        if mast_count == 3 then
            go2_mast("mid_mast")
            lower_sail()
        end

        ensure_at_helm()
        raise_anchor()
        waitrt()
        fput("depart")
        fput("depart")
        return
    end

    fatal("Please get your ship underway, then restart sail2.")
end

--------------------------------------------------------------------------------
-- Ocean map loading and BFS pathfinding
--------------------------------------------------------------------------------

local function load_ocean_map()
    local path = "data/gs/OSAMaps/Database/oceandb.json"

    if not File.exists(path) then
        fatal("Missing oceandb.json. Run ;sail2 update first.")
    end

    local raw_json = File.read(path)
    if not raw_json or raw_json == "" then
        fatal("oceandb.json is empty or unreadable.")
    end

    local ok, raw = pcall(Json.decode, raw_json)
    if not ok or type(raw) ~= "table" then
        fatal("Failed to parse oceandb.json.")
    end

    -- Flatten the map: support both flat { "7116500": {...} } and nested { zone: { "7116500": {...} } }
    local flat = {}

    -- Check if top-level keys are room IDs
    local has_room_keys = false
    for k, _ in pairs(raw) do
        if valid_room_id(k) then
            has_room_keys = true
            break
        end
    end

    if has_room_keys then
        for rid, exits in pairs(raw) do
            if valid_room_id(rid) and type(exits) == "table" then
                flat[tostring(rid)] = exits
            end
        end
    else
        for _, rooms in pairs(raw) do
            if type(rooms) == "table" then
                for rid, exits in pairs(rooms) do
                    if valid_room_id(rid) and type(exits) == "table" then
                        flat[tostring(rid)] = exits
                    end
                end
            end
        end
    end

    if not next(flat) then
        fatal("oceandb.json contains no valid room entries.")
    end

    return flat
end

local function bfs(ocean_map, start_id, goal_id)
    local visited = { [start_id] = true }
    local queue = { { id = start_id, path = {} } }
    local front = 1

    while front <= #queue do
        local cur = queue[front]
        front = front + 1

        if cur.id == goal_id then
            return cur.path
        end

        local exits = ocean_map[cur.id]
        if type(exits) == "table" then
            for dir, nxt in pairs(exits) do
                local nid = strip(tostring(nxt))
                if valid_room_id(nid) and not visited[nid] then
                    visited[nid] = true
                    local new_path = {}
                    for _, step in ipairs(cur.path) do
                        table.insert(new_path, step)
                    end
                    table.insert(new_path, { dir = lower(tostring(dir)), room = nid })
                    table.insert(queue, { id = nid, path = new_path })
                end
            end
        end
    end

    return nil -- no path found
end

local function compress_route(path)
    if not path or #path == 0 then return {} end

    local legs = {}
    local current_dir = path[1].dir
    local expected_rooms = { path[1].room }

    for i = 2, #path do
        local step = path[i]
        if step.dir == current_dir then
            table.insert(expected_rooms, step.room)
        else
            table.insert(legs, { dir = current_dir, rooms = expected_rooms })
            current_dir = step.dir
            expected_rooms = { step.room }
        end
    end

    table.insert(legs, { dir = current_dir, rooms = expected_rooms })
    return legs
end

--------------------------------------------------------------------------------
-- Ocean watch: track current room from XML stream
--------------------------------------------------------------------------------

local function update_current_room_from_line(line)
    if not line then return false end
    local text = tostring(line)

    -- Match room ID from roomName or parenthetical UID
    local rid = text:match("roomName.*%((%d%d%d%d%d%d%d)%)")
    if not rid then
        rid = text:match("%((%d%d%d%d%d%d%d)%)")
    end

    if rid and valid_room_id(rid) then
        current_room_id = rid
        return true
    end

    return false
end

local function ensure_ocean_watch()
    if ocean_watch_started then return end
    fput("watch ocean")
    waitrt()
    ocean_watch_started = true
end

local function wait_for_current_room(timeout)
    timeout = timeout or 8
    local deadline = os.time() + timeout

    while os.time() <= deadline do
        if current_room_id and current_room_id ~= "" then
            return current_room_id
        end

        local line = get_noblock()
        if line then
            update_current_room_from_line(line)
        else
            pause(0.1)
        end
    end

    return current_room_id or ""
end

local function wait_for_room_change(previous_room, timeout)
    timeout = timeout or 8
    previous_room = tostring(previous_room or "")
    local deadline = os.time() + timeout

    while os.time() <= deadline do
        local current = tostring(current_room_id or "")
        if current ~= "" and current ~= previous_room then
            return current
        end

        local line = get_noblock()
        if line then
            update_current_room_from_line(line)
        else
            pause(0.1)
        end
    end

    return tostring(current_room_id or "")
end

local function current_sea_room()
    return tostring(current_room_id or "")
end

--------------------------------------------------------------------------------
-- Helm control
--------------------------------------------------------------------------------

local function set_heading(dir)
    dir = lower(strip(dir))
    if lower(strip(current_heading or "")) == dir then
        echo("--- Wheel already set to " .. string.upper(dir))
        return
    end

    ensure_at_helm()
    fput("turn wheel " .. dir)
    waitrt()
    current_heading = dir
end

local function wait_for_sailing_result(timeout)
    timeout = timeout or 300
    local deadline = os.time() + timeout

    while os.time() <= deadline do
        local line = get_noblock()
        if not line then
            pause(0.1)
        else
            update_current_room_from_line(line)

            if string.find(line, "cuts through the ocean, heading") or
               string.find(line, "drifts slowly") then
                return "moved"
            elseif string.find(line, "A large swell crashes into the side of the") then
                return "rogue_wave"
            elseif string.find(line, "The sound of ropes coming free of the rigging") then
                return "rigging"
            elseif string.find(line, "suddenly drifts from its course as the") then
                return "off_course"
            elseif string.find(line, "drifts steadily toward the") then
                return "arrival"
            elseif string.find(line, "wheel slowly turns off course") then
                return "invalid_heading"
            elseif string.find(line, "rocks idly in the ocean waters") then
                return "aimless"
            end
        end
    end

    return "timeout"
end

--------------------------------------------------------------------------------
-- Sailing: leg execution
--------------------------------------------------------------------------------

local function sail_leg(dir, expected_rooms)
    echo("--- Heading " .. string.upper(dir) .. " for " .. #expected_rooms .. " move(s)")
    set_heading(dir)

    local moved = 0

    while moved < #expected_rooms do
        local previous_room = current_sea_room()
        local result = wait_for_sailing_result()

        if result == "moved" then
            local actual_room = wait_for_room_change(previous_room, 8)
            local expected_room = expected_rooms[moved + 1]

            if actual_room == "" then
                echo("--- WARNING: Could not confirm current room after movement.")
                return "reroute", actual_room
            end

            if actual_room == previous_room then
                echo("--- WARNING: Room did not update after movement. Still showing " .. actual_room .. ".")
                return "reroute", actual_room
            end

            if actual_room ~= expected_room then
                echo("--- Course deviation: expected " .. expected_room .. ", got " .. actual_room)
                return "reroute", actual_room
            end

            moved = moved + 1
            echo("--- Move " .. moved .. "/" .. #expected_rooms .. ": now at " .. actual_room)

        elseif result == "rogue_wave" then
            waitrt()
            fput("yell Rogue Wave! Secure the Anchor!")
            ensure_at_helm()
            waitrt()
            waitcastrt()
            raise_anchor()
            current_heading = nil
            echo("--- Rogue wave handled. Resuming travel...")
            return "reroute", current_sea_room()

        elseif result == "rigging" then
            echo("The Sails Have Been Furled")
            if mast_count >= 1 then
                go2_mast("main_mast")
                lower_sail()
            end
            if mast_count >= 2 then
                go2_mast("forward_mast")
                lower_sail()
            end
            if mast_count == 3 then
                go2_mast("mid_mast")
                lower_sail()
            end
            ensure_at_helm()
            current_heading = nil
            echo("--- Rigging secured. Resuming travel...")
            return "reroute", current_sea_room()

        elseif result == "invalid_heading" or result == "aimless" or result == "off_course" then
            current_heading = nil
            local actual_room = wait_for_current_room(5)
            echo("--- Sailing interrupted (" .. result .. "). Current room: " ..
                (actual_room ~= "" and actual_room or "UNKNOWN"))
            return "reroute", actual_room

        else
            local actual_room = wait_for_current_room(5)
            echo("--- Sailing interrupted (" .. result .. "). Current room: " ..
                (actual_room ~= "" and actual_room or "UNKNOWN"))
            return "reroute", actual_room
        end
    end

    return "ok", current_sea_room()
end

local function sail_into_port()
    echo("--- Final approach: turning wheel PORT")
    current_heading = nil
    ensure_at_helm()
    fput("turn wheel port")
    waitrt()

    while true do
        local result = wait_for_sailing_result()

        if result == "arrival" then
            echo("--- Port approach confirmed.")
            return "arrived"
        elseif result == "moved" then
            -- Keep going
        elseif result == "invalid_heading" or result == "aimless" or result == "off_course" then
            current_heading = nil
            return "reroute"
        else
            return "reroute"
        end
    end
end

--------------------------------------------------------------------------------
-- Autopilot
--------------------------------------------------------------------------------

local function autopilot_to(ocean_map, start_id, goal_id)
    local cur_id = tostring(start_id)
    local goal_is_port = port_destination(goal_id)

    while true do
        local path = bfs(ocean_map, cur_id, goal_id)
        if not path then
            fatal("No path found from " .. cur_id .. " to " .. goal_id .. ".")
        end

        local legs = compress_route(path)

        local port_hint = goal_is_port and " + port entry" or ""
        echo("--- ROUTE FOUND (" .. #path .. " moves / " .. #legs .. " heading changes" ..
            port_hint .. ") ---")

        for i, leg in ipairs(legs) do
            echo(i .. ". " .. string.upper(leg.dir) ..
                string.rep(" ", 3 - #leg.dir) .. " x " .. #leg.rooms ..
                " -> " .. leg.rooms[#leg.rooms])
        end
        if goal_is_port then
            echo(#legs + 1 .. ". PORT entry from " .. goal_id)
        end

        local reroute_needed = false

        for _, leg in ipairs(legs) do
            local status, new_room = sail_leg(leg.dir, leg.rooms)

            if status == "reroute" then
                if not new_room or new_room == "" then
                    new_room = wait_for_current_room(5)
                end
                if not new_room or new_room == "" then
                    fatal("Unable to determine current room for reroute.")
                end

                if tostring(new_room) == tostring(goal_id) and not goal_is_port then
                    echo("--- ARRIVED AT " .. goal_id)
                    return
                end

                echo("--- Re-routing from " .. new_room .. " to " .. goal_id)
                cur_id = tostring(new_room)
                reroute_needed = true
                break
            end
        end

        if reroute_needed then
            -- Loop back to recalculate route
        else
            local actual = wait_for_current_room(5)

            if actual ~= tostring(goal_id) then
                if actual ~= "" then cur_id = actual end
                echo("--- Route exhausted but destination not confirmed. Re-routing from " .. cur_id)
            else
                -- We are at the goal room
                if goal_is_port then
                    local port_result = sail_into_port()

                    if port_result == "arrived" then
                        echo("--- ARRIVED AT PORT " .. goal_id)
                        local port_name = PORT_NAMES[goal_id]
                        if port_name then
                            echo("--- Welcome to " .. port_name .. "!")
                        end
                        return
                    end

                    cur_id = wait_for_current_room(5)
                    if cur_id == "" then
                        fatal("Unable to determine current room after failed port entry.")
                    end
                    echo("--- Re-routing from " .. cur_id .. " to " .. goal_id)
                else
                    echo("--- ARRIVED AT " .. goal_id)
                    return
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Map update / sync
--------------------------------------------------------------------------------

local function sync_ocean_maps()
    echo("--- Connecting to GitHub to update ocean database...")

    local api_url = "https://api.github.com/repos/jmbreitfeld/OSA-Ocean-Database/contents/"

    local ok_fetch, response = pcall(Http.get_json, api_url)
    if not ok_fetch or type(response) ~= "table" then
        echo("--- ERROR: Failed to fetch file listing from GitHub.")
        return
    end

    -- Ensure local directory exists
    local local_dir = "data/gs/OSAMaps/Database"
    if not File.is_dir(local_dir) then
        File.mkdir(local_dir)
    end

    local count = 0
    for _, file in ipairs(response) do
        if type(file) == "table" and file.type == "file" and file.download_url then
            local file_name = file.name
            local local_path = local_dir .. "/" .. file_name
            local remote_size = file.size or 0

            local needs_download = false
            if not File.exists(local_path) then
                needs_download = true
            else
                -- Simple size check
                local content = File.read(local_path)
                if not content or #content ~= remote_size then
                    needs_download = true
                end
            end

            if needs_download then
                echo("--- Downloading: " .. file_name)
                local dl_ok, dl_resp = pcall(Http.get, file.download_url)
                if dl_ok and dl_resp and dl_resp.body then
                    File.write(local_path, dl_resp.body)
                    count = count + 1
                else
                    echo("--- ERROR: Failed to download " .. file_name)
                end
            end
        end
    end

    if count > 0 then
        echo("--- Success! Updated " .. count .. " file(s).")
    else
        echo("--- All files are up to date.")
    end
end

--------------------------------------------------------------------------------
-- Help / list
--------------------------------------------------------------------------------

local function show_help()
    echo("sail2 - Ocean autopilot for OSA shipboard travel")
    echo("")
    echo("Usage:")
    echo("  ;sail2 <destination>                   Sail to port or room UID")
    echo("  ;sail2 <start> <end>                   Display route (no sailing)")
    echo("  ;sail2 update                          Download/update ocean mapdb")
    echo("  ;sail2 list                            Show available ports")
    echo("  ;sail2 help                            Show this help")
    echo("")
    echo("Destinations can be port aliases or 7-digit room UIDs.")
    echo("Use ;sail2 list to see available port aliases.")
end

local function show_port_list()
    echo("Available ports:")
    echo("")
    local sorted = {}
    for alias, uid in pairs(PORTS) do
        local name = PORT_NAMES[uid] or alias
        table.insert(sorted, { alias = alias, name = name, uid = uid })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(sorted) do
        echo(string.format("  %-24s %-16s %s", entry.name, entry.alias, entry.uid))
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local arg1 = Script.vars[1] or ""
local arg2 = Script.vars[2] or ""

-- Handle special commands
if lower(strip(arg1)) == "update" then
    sync_ocean_maps()
    return
end

if lower(strip(arg1)) == "help" or lower(strip(arg1)) == "--help" or lower(strip(arg1)) == "-h" then
    show_help()
    return
end

if lower(strip(arg1)) == "list" then
    show_port_list()
    return
end

if strip(arg1) == "" then
    show_help()
    return
end

-- Detect ship type
detect_mast_count()

-- Ensure ship is underway
start_nav()

-- Load ocean map
local ocean_map = load_ocean_map()

if strip(arg2) == "" then
    -- Single argument: sail to destination
    ensure_ocean_watch()

    local start_id = wait_for_current_room(8)
    local goal_id  = normalize_input(arg1)

    if start_id == "" then
        fatal("Could not determine current ocean room from watch ocean.")
    end
    if goal_id == "" then
        fatal("End must be a known port or 7-digit room id. Use ;sail2 list to see ports.")
    end
    if not ocean_map[start_id] then
        fatal("Start room " .. start_id .. " not found in oceandb.json.")
    end
    if not ocean_map[goal_id] then
        fatal("End room " .. goal_id .. " not found in oceandb.json.")
    end

    current_room_id = start_id

    local goal_name = PORT_NAMES[goal_id]
    echo("--- Voyage: " .. start_id .. " -> " .. goal_id ..
        (goal_name and (" (" .. goal_name .. ")") or ""))
    autopilot_to(ocean_map, start_id, goal_id)

else
    -- Two arguments: display route only
    local start_id = normalize_input(arg1)
    local goal_id  = normalize_input(arg2)

    if start_id == "" then
        fatal("Start must be a known port or 7-digit room id.")
    end
    if goal_id == "" then
        fatal("End must be a known port or 7-digit room id.")
    end
    if not ocean_map[start_id] then
        fatal("Start room " .. start_id .. " not found in oceandb.json.")
    end
    if not ocean_map[goal_id] then
        fatal("End room " .. goal_id .. " not found in oceandb.json.")
    end

    local start_name = PORT_NAMES[start_id]
    local goal_name  = PORT_NAMES[goal_id]
    echo("--- Voyage: " .. start_id ..
        (start_name and (" (" .. start_name .. ")") or "") ..
        " -> " .. goal_id ..
        (goal_name and (" (" .. goal_name .. ")") or ""))

    local path = bfs(ocean_map, start_id, goal_id)

    if path then
        echo("--- ROUTE FOUND (" .. #path .. " moves) ---")
        for i, step in ipairs(path) do
            echo(i .. ". Steer " .. string.upper(step.dir) ..
                string.rep(" ", 3 - #step.dir) .. " -> " .. step.room)
        end
    else
        echo("--- ERROR: No path found.")
    end
end
