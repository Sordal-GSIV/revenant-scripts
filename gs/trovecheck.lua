--- @revenant-script
--- name: trovecheck
--- version: 1.0.1
--- author: elanthia-online
--- game: gs
--- description: Checks for Ebon Gate Trove wins across multiple rooms
--- tags: ebon gate,trove
---
--- Changelog (from Lich5):
---   v1.0.1 (2025-10-27) - check PROPERTY MINE, bypass for Shattered
---   v1.0.0 (2025-10-26) - initial release

--------------------------------------------------------------------------------
-- Default rooms (resolved from UIDs)
--------------------------------------------------------------------------------

local DEFAULT_ROOMS = {
    "u8084732",  -- property trove
    "u8084012",
    "u8084011",
    "u8084019",
    "u8084013",
    "u8084014",
}

local PROPERTY_TROVE_UID = "u8084732"
local SHATTERED_SKIP_UIDS = { "u8084732", "u8084019", "u8084013", "u8084014" }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function go2(dest)
    Script.run("go2", tostring(dest))
    wait_while(function() return running("go2") end)
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if tostring(v) == tostring(val) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Check rack in current room
--------------------------------------------------------------------------------

local function check_rack()
    local result = dothistimeout("look on long rack", 3, {
        "On the", "There is nothing"
    })

    if not result or result:find("There is nothing") then
        return { status = "empty", message = "Rack is empty" }
    end

    -- Try to get the item
    fput("get from rack")
    pause(0.5)

    local lines = {}
    for i = 1, 5 do
        local l = get()
        if l then lines[#lines + 1] = l end
    end

    local text = table.concat(lines, "\n")

    if text:find("doesn't belong to you") or text:find("may want it") then
        return { status = "unavailable", message = "Item belongs to someone else" }
    elseif text:find("You pick up") or text:find("You grab") or text:find("You take") or text:find("You remove") then
        return { status = "won", message = "*** YOU WON THE ITEM! ***" }
    else
        return { status = "error", message = "Unexpected result" }
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local starting_room = Room.current()
local starting_id = starting_room and starting_room.id or nil

-- Get room list
local room_list = {}
if Script.vars[1] and Script.vars[1] ~= "" then
    for i = 1, #Script.vars do
        if Script.vars[i] then
            room_list[#room_list + 1] = Script.vars[i]
        end
    end
else
    room_list = DEFAULT_ROOMS
end

echo("Starting trove check. Will check " .. #room_list .. " rooms.")
echo(string.rep("=", 50))

local results = {}

for _, room in ipairs(room_list) do
    local entry = { room = room, status = "not_checked", message = "" }
    results[#results + 1] = entry

    -- Shattered skip
    if GameState.game == "GSF" and table_contains(SHATTERED_SKIP_UIDS, room) then
        entry.status = "skip"
        entry.message = "Shattered doesn't have all troves"
        echo(entry.message)
        goto continue_room
    end

    -- Property trove check
    if room == PROPERTY_TROVE_UID then
        local resp = dothistimeout("property mine", 2, { "You do not own a private property", "Owner:" })
        if resp and resp:find("You do not own") then
            entry.status = "skip"
            entry.message = "No private property owned"
            echo(entry.message)
            goto continue_room
        end
    end

    echo("Traveling to " .. tostring(room) .. "...")
    go2(room)
    pause(0.5)

    local result = check_rack()
    entry.status = result.status
    entry.message = result.message
    echo(result.message)

    if result.status == "won" then
        echo(string.rep("=", 50))
        echo("YOU WON! Item is in your hands.")
        echo(string.rep("=", 50))
        echo("Pausing script. Unpause when ready to continue.")
        -- In Revenant, we just pause briefly
        pause(5)
        fput("stow all")
    end

    ::continue_room::
    pause(0.5)
end

-- Return to start
if starting_id then
    echo("Returning to starting room...")
    go2(starting_id)
end

-- Summary
echo("")
echo(string.rep("=", 70))
echo("TROVE CHECK SUMMARY")
echo(string.rep("=", 70))

local won = 0
local empty = 0
local unavail = 0

for _, r in ipairs(results) do
    if r.status == "won" then won = won + 1
    elseif r.status == "empty" then empty = empty + 1
    elseif r.status == "unavailable" then unavail = unavail + 1 end
end

echo("Total rooms: " .. #results)
echo("  Won: " .. won)
echo("  Empty: " .. empty)
echo("  Unavailable: " .. unavail)
echo(string.rep("=", 70))
