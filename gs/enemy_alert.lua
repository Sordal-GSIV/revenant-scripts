--- @revenant-script
--- name: enemy_alert
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Background script that highlights whenever a new enemy target enters the room
--- tags: alert,combat,targets
---
--- Run with: ;enemy_alert   Stop with: ;kill enemy_alert

local DEAD_RE = Regex.new("dead|gone")

local function living_target_ids()
    local npcs = GameObj.npcs()
    local ids = {}
    for _, npc in ipairs(npcs) do
        local dominated = false
        if npc.status and DEAD_RE:test(npc.status) then
            dominated = true
        end
        if not dominated and npc.type and npc.type:find("aggressive") then
            ids[npc.id] = npc
        end
    end
    return ids
end

local known_ids = {}
local current_room = nil

while true do
    local room = Room.current()
    local room_id = room and room.id or nil

    if room_id ~= current_room then
        current_room = room_id
        known_ids = {}
    end

    local current = living_target_ids()

    for id, npc in pairs(current) do
        if not known_ids[id] then
            respond("<pushBold/>*** NEW TARGET: " .. npc.name .. " (#" .. id .. ") ***<popBold/>")
        end
    end

    -- Update known: keep only those still present
    local new_known = {}
    for id, _ in pairs(known_ids) do
        if current[id] then new_known[id] = true end
    end
    for id, _ in pairs(current) do
        new_known[id] = true
    end
    known_ids = new_known

    pause(0.3)
end
