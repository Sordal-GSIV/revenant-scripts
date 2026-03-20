--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: trovecheck
--- version: 1.0.1
--- author: elanthia-online
--- game: gs
--- description: Checks for Ebon Gate Trove wins across multiple rooms
--- tags: ebon gate,trove
---
--- Changelog (from Lich5):
---   v1.0.1 (2025-10-27) - check PROPERTY MINE to prevent checking property trove; bypass for Shattered
---   v1.0.0 (2025-10-26) - initial release

--------------------------------------------------------------------------------
-- Default trove UIDs (resolved to room IDs at runtime via Map.ids_from_uid)
--------------------------------------------------------------------------------

local TROVE_UIDS = {
    8084732,  -- property trove
    8084012,  -- trove 1
    8084011,  -- trove 2
    8084019,  -- trove 3 (Shattered: skip)
    8084013,  -- trove 4 (Shattered: skip)
    8084014,  -- trove 5 (Shattered: skip)
}

local PROPERTY_TROVE_UID   = 8084732
local SHATTERED_SKIP_UIDS  = { [8084732]=true, [8084019]=true, [8084013]=true, [8084014]=true }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Resolve a server UID to the local room ID, or nil if not in map DB.
local function resolve_uid(uid)
    local ids = Map.ids_from_uid(uid)
    return ids and ids[1] or nil
end

--- Stow all held items; return a table describing what was held so fill_hands
--- can restore them after the run.  Mirrors Lich5's empty_hands().
local function empty_hands()
    local held = {}
    local right = GameObj.right_hand()
    local left  = GameObj.left_hand()
    if right then
        held[#held + 1] = { id = right.id, noun = right.noun }
        fput("stow right")
    end
    if left then
        held[#held + 1] = { id = left.id, noun = left.noun }
        fput("stow left")
    end
    return held
end

--- Restore previously held items by exist-ID.  Mirrors Lich5's fill_hands().
local function fill_hands(held)
    for _, item in ipairs(held or {}) do
        dothistimeout("get #" .. item.id, 3, {
            "You pick up", "You grab", "You take", "You remove",
            "already holding", "What were",
        })
    end
end

--- Send a game command and capture every raw downstream line (including XML)
--- until one of the supplied plain-text patterns is matched, then return the
--- captured lines.  This is the equivalent of Lich5's Lich::Util.quiet_command_xml.
local function quiet_command_xml(cmd, patterns)
    local captured = {}
    local done     = false

    DownstreamHook.add("__trovecheck_xml", function(line)
        if not done then
            captured[#captured + 1] = line
            for _, pat in ipairs(patterns) do
                if line:find(pat, 1, true) then
                    done = true
                    break
                end
            end
        end
        return line  -- pass through; do not swallow
    end, DownstreamHook.PRIORITY_FIRST)

    clear()
    put(cmd)

    -- Yield in small increments until the hook signals completion or we time out
    local deadline = os.time() + 5
    while not done and os.time() < deadline do
        pause(0.05)
    end

    DownstreamHook.remove("__trovecheck_xml")
    return captured
end

--- Navigate to a room by numeric room ID.  Returns true on success, false if
--- no path exists or we failed to arrive.  Uses Map.find_path to detect
--- unreachable rooms before attempting navigation.
local function navigate_to_room(room_id)
    if GameState.room_id == room_id then return true end

    -- Pre-check: does a path exist at all?
    local path = Map.find_path(GameState.room_id, room_id)
    if not path or #path == 0 then
        echo("Error: no path found from room " .. tostring(GameState.room_id) ..
             " to room " .. tostring(room_id))
        return false
    end

    Map.go2(room_id)

    -- Verify arrival
    return GameState.room_id == room_id
end

--- Inspect the rack in the current room.  Returns a result table:
---   { status, message, item_name, item_id }
--- Statuses: "empty", "won", "unavailable", "error"
local function check_rack(room_id)
    echo("Checking rack in room " .. tostring(room_id) .. "...")

    -- Capture raw XML so we can extract exist-IDs from <a exist="N" noun="X"> tags
    local response      = quiet_command_xml("look on long rack", { "On the", "There is nothing" })
    local response_text = table.concat(response, "\n")

    if response_text:find("There is nothing on the", 1, true) then
        return {
            status    = "empty",
            message   = "Rack is empty in room " .. tostring(room_id),
            item_name = nil,
            item_id   = nil,
        }
    end

    -- Extract all <a exist="ID" noun="NOUN"> items; filter out the rack itself
    local items         = {}
    local exist_pattern = Regex.new([=[<a exist="(\d+)" noun="([^"]+)">]=])
    for _, m in ipairs(exist_pattern:find_all(response_text)) do
        local id   = m[1]
        local noun = m[2]
        if noun ~= "rack" then
            items[#items + 1] = { id = id, noun = noun }
        end
    end

    if #items == 0 then
        return {
            status    = "empty",
            message   = "No items found on rack in room " .. tostring(room_id),
            item_name = nil,
            item_id   = nil,
        }
    end

    local item = items[1]
    echo("Found item: " .. item.noun .. " (ID: " .. item.id .. ")")

    -- Attempt to pick up the item by precise exist-ID (avoids grabbing wrong item
    -- when multiple objects are present, matching original Lich5 behaviour)
    clear()
    fput("get #" .. item.id)
    pause(0.5)

    local result_text = table.concat(reget(10), "\n")

    if result_text:find("doesn't belong to you", 1, true) or
       result_text:find("may want it", 1, true) then
        return {
            status    = "unavailable",
            message   = "Item not available (belongs to someone else)",
            item_name = item.noun,
            item_id   = item.id,
        }
    elseif Regex.test([[You (?:pick up|grab|take|remove)]], result_text) then
        return {
            status    = "won",
            message   = "*** YOU WON THE ITEM! ***",
            item_name = item.noun,
            item_id   = item.id,
        }
    else
        return {
            status    = "error",
            message   = "Unexpected response: " .. result_text:sub(1, 120),
            item_name = item.noun,
            item_id   = item.id,
        }
    end
end

--- Announce a win with bold XML injection, then pause_script so the player can
--- react before the script auto-stows and continues — matching Lich5 behaviour.
local function handle_win(room_id, item_name, item_id)
    _respond('<pushBold/><output class="mono"/>*** YOU WON THE ITEM IN ROOM ' ..
             tostring(room_id) .. '! ***<output class=""/><popBold/>')
    echo(string.rep("=", 50))
    echo("YOU WON! Item is in your hands.")
    echo("  Item: " .. tostring(item_name) .. " (ID: " .. tostring(item_id) .. ")")
    echo(string.rep("=", 50))
    echo("Script paused — unpause when ready to continue.")

    -- Block until the player unpauses the script (mirrors Lich5 pause_script)
    Script.pause(Script.name)
    while Script.is_paused(Script.name) do
        pause(0.5)
    end

    fput("stow all")
    pause(0.5)
end

--- Return to starting room via Map.go2.
local function return_to_start(starting_room_id)
    echo(string.rep("=", 50))
    echo("Returning to starting room " .. tostring(starting_room_id) .. "...")
    Map.go2(starting_room_id)
end

--- Print a tabulated summary matching the original Lich5 output.
local function print_summary(results)
    echo("")
    echo(string.rep("=", 70))
    echo("TROVE CHECK SUMMARY")
    echo(string.rep("=", 70))
    echo("")

    local counts = { won = 0, empty = 0, unavailable = 0, unreachable = 0, error = 0 }
    for _, r in ipairs(results) do
        if counts[r.status] then
            counts[r.status] = counts[r.status] + 1
        end
    end

    echo("Total rooms checked:                  " .. #results)
    echo("  - Items WON:                        " .. counts.won)
    echo("  - Empty racks:                      " .. counts.empty)
    echo("  - Items unavailable (others'):       " .. counts.unavailable)
    echo("  - Unreachable rooms:                 " .. counts.unreachable)
    echo("  - Errors:                            " .. counts.error)
    echo("")

    if counts.won > 0 then
        echo("ITEMS WON:")
        for _, r in ipairs(results) do
            if r.status == "won" then
                echo("  Room " .. tostring(r.room_id) .. ": " ..
                     tostring(r.item_name) .. " (ID: " .. tostring(r.item_id) .. ")")
            end
        end
        echo("")
    end

    if counts.unavailable > 0 then
        echo("ITEMS FOUND (but unavailable):")
        for _, r in ipairs(results) do
            if r.status == "unavailable" then
                echo("  Room " .. tostring(r.room_id) .. ": " .. tostring(r.item_name))
            end
        end
        echo("")
    end

    if counts.unreachable > 0 then
        echo("UNREACHABLE ROOMS:")
        for _, r in ipairs(results) do
            if r.status == "unreachable" then
                echo("  Room " .. tostring(r.room_id) .. ": " .. r.message)
            end
        end
        echo("")
    end

    if counts.error > 0 then
        echo("ERRORS:")
        for _, r in ipairs(results) do
            if r.status == "error" then
                echo("  Room " .. tostring(r.room_id) .. ": " .. r.message)
            end
        end
        echo("")
    end

    echo(string.rep("=", 70))
    echo("Script complete!")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Empty hands before starting navigation (restore at end)
local held_items = empty_hands()

-- Remember where we started
local starting_room_id = GameState.room_id
echo("Starting room: " .. tostring(starting_room_id))

-- Build the room list: user-supplied IDs, or resolve the default UID list
local room_list = {}  -- each entry: { uid=N|nil, id=N }

if Script.vars[1] and Script.vars[1] ~= "" then
    echo("Using provided room list")
    for i = 1, #Script.vars do
        local v = Script.vars[i]
        if v and v ~= "" then
            room_list[#room_list + 1] = { uid = nil, id = tonumber(v) }
        end
    end
else
    echo("Using default room list")
    for _, uid in ipairs(TROVE_UIDS) do
        local id = resolve_uid(uid)
        if id then
            room_list[#room_list + 1] = { uid = uid, id = id }
        else
            echo("Warning: UID " .. tostring(uid) .. " not found in local map database")
        end
    end
end

echo("Will check " .. #room_list .. " rooms: " ..
     table.concat((function()
         local ids = {}
         for _, r in ipairs(room_list) do ids[#ids + 1] = tostring(r.id) end
         return ids
     end)(), ", "))
echo(string.rep("=", 50))

local results = {}

for _, room_entry in ipairs(room_list) do
    local room_id  = room_entry.id
    local room_uid = room_entry.uid

    local result = {
        room_id   = room_id,
        status    = "not_checked",
        item_name = nil,
        item_id   = nil,
        message   = "",
    }
    results[#results + 1] = result

    -- Shattered: property trove and troves 3-5 are unreachable
    if GameState.game == "GSF" and room_uid and SHATTERED_SKIP_UIDS[room_uid] then
        result.status  = "unreachable"
        result.message = "Shattered doesn't have all troves!"
        echo(result.message)
        goto continue_room
    end

    -- Property trove: skip if character owns no private property
    if room_uid == PROPERTY_TROVE_UID then
        local resp = dothistimeout("property mine", 2, {
            "You do not own a private property",
            "Owner:",
        })
        if resp and resp:find("You do not own a private property", 1, true) then
            result.status  = "unreachable"
            result.message = "Could not reach room (no private property)"
            echo(result.message)
            goto continue_room
        end
    end

    echo("Traveling to room " .. tostring(room_id) .. "...")
    if not navigate_to_room(room_id) then
        result.status  = "unreachable"
        result.message = "Could not reach room (no service pass?)"
        echo(result.message)
        goto continue_room
    end

    -- Inspect the rack
    local check    = check_rack(room_id)
    result.status  = check.status
    result.item_name = check.item_name
    result.item_id   = check.item_id
    result.message   = check.message
    echo(result.message)

    if result.status == "won" then
        handle_win(room_id, result.item_name, result.item_id)
    end

    pause(0.5)
    echo("")

    ::continue_room::
end

-- Navigate back to where we started
if starting_room_id then
    return_to_start(starting_room_id)
end

-- Summary table
print_summary(results)

-- Restore originally held items
fill_hands(held_items)
