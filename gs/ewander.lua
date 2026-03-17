--- @revenant-script
--- name: ewander
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Wander by visiting least-recently-seen adjacent rooms; stops for NPCs
--- tags: movement
---
--- Changelog (from Lich5):
---   v1.0.0 (2025-03-19) - initial fork of wander.lic

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_list(key)
    local raw = CharSettings[key]
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_list(key, val)
    CharSettings[key] = Json.encode(val)
end

local boundary    = load_list("boundary")
local untargetable = load_list("untargetable")
local targetable   = load_list("targetable")
local delay        = tonumber(CharSettings["delay"]) or 1.0

local visited_rooms = {}

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if tostring(v) == tostring(val) then return true end
    end
    return false
end

local function table_remove_value(t, val)
    for i = #t, 1, -1 do
        if tostring(t[i]) == tostring(val) then table.remove(t, i) end
    end
end

--------------------------------------------------------------------------------
-- Wander logic
--------------------------------------------------------------------------------

local function wander_step()
    local room = Room.current()
    if not room or not room.wayto then return end

    -- Get next room options, excluding boundaries
    local options = {}
    for room_id, _ in pairs(room.wayto) do
        if not table_contains(boundary, room_id) then
            options[#options + 1] = room_id
        end
    end

    if #options == 0 then return end

    -- Prefer unvisited rooms
    local unvisited = {}
    for _, rid in ipairs(options) do
        if not table_contains(visited_rooms, rid) then
            unvisited[#unvisited + 1] = rid
        end
    end

    local next_room
    if #unvisited > 0 then
        next_room = unvisited[math.random(#unvisited)]
    else
        -- Pick the least recently visited
        for _, rid in ipairs(visited_rooms) do
            if table_contains(options, rid) then
                next_room = rid
                break
            end
        end
        if not next_room then
            next_room = options[math.random(#options)]
        end
    end

    -- Track visit
    table_remove_value(visited_rooms, next_room)
    visited_rooms[#visited_rooms + 1] = next_room

    -- Move
    local way = room.wayto[next_room]
    if type(way) == "string" then
        move(way)
    end
end

--------------------------------------------------------------------------------
-- CLI
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 and arg1:lower() == "help" then
    respond("")
    respond("  ;ewander add              adds the current room to the boundary list")
    respond("  ;ewander add <room id>    adds the given room id to the boundary list")
    respond("  ;ewander rem              deletes the current room from the boundary list")
    respond("  ;ewander rem <room id>    deletes the given room id from the boundary list")
    respond("  ;ewander clear            clears the boundary list and npc info")
    respond("  ;ewander delay <seconds>  sets the delay before moving")
    respond("  ;ewander list             shows saved boundaries and npc info")
    respond("  ;ewander <npc1> <npc2>    stops only for the given npcs")
    respond("  ;ewander                  stops for any targetable npcs")
    respond("")
    return
elseif arg1 and (arg1:lower() == "add" or arg1:lower() == "set") then
    local arg2 = Script.vars[2]
    if arg2 and arg2:match("^%d+$") then
        for i = 2, #Script.vars do
            local v = Script.vars[i]
            if v and v:match("^%d+$") then
                boundary[#boundary + 1] = v
                echo("Room " .. v .. " added to boundary list")
            end
        end
    else
        local room = Room.current()
        if room then
            boundary[#boundary + 1] = tostring(room.id)
            echo("This room (" .. room.id .. ") added to boundary list")
        end
    end
    save_list("boundary", boundary)
    return
elseif arg1 and (arg1:lower():match("^del") or arg1:lower():match("^rem")) then
    local arg2 = Script.vars[2]
    if arg2 and arg2:match("^%d+$") then
        for i = 2, #Script.vars do
            local v = Script.vars[i]
            if v and v:match("^%d+$") then
                table_remove_value(boundary, v)
                echo("Room " .. v .. " removed from boundary list")
            end
        end
    else
        local room = Room.current()
        if room then
            table_remove_value(boundary, tostring(room.id))
            echo("This room (" .. room.id .. ") removed from boundary list")
        end
    end
    save_list("boundary", boundary)
    return
elseif arg1 and arg1:lower() == "delay" then
    local arg2 = Script.vars[2]
    if arg2 and tonumber(arg2) then
        delay = tonumber(arg2)
        CharSettings["delay"] = tostring(delay)
        echo("Movement delay is now " .. delay)
    end
    return
elseif arg1 and arg1:lower() == "list" then
    respond("")
    if #boundary == 0 then
        respond("   boundaries: none")
    else
        respond("   boundaries:")
        for _, b in ipairs(boundary) do
            respond("      " .. tostring(b))
        end
    end
    respond("")
    if #targetable == 0 then
        respond("   targetable npcs: none")
    else
        respond("   targetable npcs: " .. table.concat(targetable, ", "))
    end
    respond("")
    return
elseif arg1 and arg1:lower() == "clear" then
    boundary = {}
    untargetable = {}
    targetable = {}
    save_list("boundary", boundary)
    save_list("untargetable", untargetable)
    save_list("targetable", targetable)
    respond("done")
    return
end

--------------------------------------------------------------------------------
-- Main wander loop
--------------------------------------------------------------------------------

if not arg1 or arg1 == "" then
    -- Wander, stop for targetable NPCs
    while true do
        wander_step()
        local npcs = GameObj.targets()
        local found = false
        for _, npc in ipairs(npcs) do
            if not table_contains(untargetable, npc.name) then
                found = true
                break
            end
        end
        if found then
            break
        end
        pause(delay)
    end
else
    -- Wander, stop for specific NPCs or PCs by name
    local search_names = {}
    for i = 1, #Script.vars do
        if Script.vars[i] then
            search_names[#search_names + 1] = Script.vars[i]:lower()
        end
    end
    local search_rx = Regex.new(table.concat(search_names, "|"))

    while true do
        wander_step()
        local found = false
        -- Check PCs
        local pcs = GameObj.pcs()
        for _, pc in ipairs(pcs) do
            if pc.noun and search_rx:test(pc.noun) then
                found = true
                break
            end
        end
        -- Check NPCs
        if not found then
            local npcs = GameObj.npcs()
            for _, npc in ipairs(npcs) do
                if npc.name and npc.status ~= "dead" and search_rx:test(npc.name) then
                    found = true
                    break
                end
            end
        end
        if found then break end
        pause(delay)
    end
end
