--- @revenant-script
--- name: drag2
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Drag corpses for empaths or burial - enhanced drag with path following
--- tags: drag, corpse, empath, body
---
--- Ported from drag2.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;drag2 <person>          - Drag a person to the nearest healer
---   ;drag2 <person> <room>   - Drag a person to a specific room

local target = Script.vars[1]
local dest_room = Script.vars[2]

if not target then
    echo("Usage: ;drag2 <person> [room_id]")
    echo("  Drags a person (dead or alive) to the nearest healer or specified room.")
    return
end

local settings = get_settings and get_settings() or {}
local town_data = get_data and get_data("town") or {}

-- Find healer room
local healer_room = nil
if dest_room then
    healer_room = tonumber(dest_room)
elseif settings.hometown and town_data[settings.hometown] then
    local ht = town_data[settings.hometown]
    if ht.npc_empath then
        healer_room = ht.npc_empath.id
    elseif ht.npc_healer then
        healer_room = ht.npc_healer.id
    end
end

echo("=== Drag2 ===")
echo("Dragging " .. target .. " to " .. (healer_room and ("room " .. healer_room) or "nearest healer"))

-- Try to drag
local result = DRC.bput("drag " .. target, {
    "You grab", "You begin",
    "You can't", "Drag what",
    "is already standing",
})

if result:find("can't") or result:find("Drag what") then
    echo("Cannot drag " .. target .. "!")
    return
end

if result:find("standing") then
    echo(target .. " is standing. No need to drag!")
    return
end

echo("Got " .. target .. ". Moving to destination...")

if healer_room then
    -- Use go2 navigation if available
    DRCT.walk_to(healer_room)
else
    echo("No healer room configured. Drag " .. target .. " manually.")
    echo("Set hometown in YAML settings for auto-navigation.")
end

echo("Arrived! Releasing " .. target)
fput("release " .. target)
