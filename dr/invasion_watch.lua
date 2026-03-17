--- @revenant-script
--- name: invasion_watch
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Monitor safe rooms for invasion mobs and evacuate.
--- tags: invasion, safety, automated
--- Converted from invasion-watch.lic

no_pause_all()

local safe_rooms = {820, 1034}
local backup_saferoom = 985
local recheck_time = 380
local mobs = {"hafwa", "construct", "malchata", "youngling", "shooter"}

local settings = get_settings()
if settings.safe_room then table.insert(safe_rooms, settings.safe_room) end

local paused = false

local function danger()
    local npcs = DRRoom and DRRoom.npcs or {}
    for _, npc in ipairs(npcs) do
        for _, mob in ipairs(mobs) do
            if npc:lower():find(mob) then return true end
        end
    end
    return false
end

echo("Watching for invasions in safe rooms...")

while true do
    pause(1)
    local room_id = Room.current and Room.current.id
    local in_safe = false
    for _, sr in ipairs(safe_rooms) do
        if room_id == sr then in_safe = true; break end
    end
    if in_safe and danger() then
        echo("***INVASION! Moving to backup saferoom***")
        DRC.fix_standing()
        DRCT.walk_to(backup_saferoom)
        pause(recheck_time)
    end
end
