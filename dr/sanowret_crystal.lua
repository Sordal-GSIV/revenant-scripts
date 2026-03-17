--- @revenant-script
--- name: sanowret_crystal
--- version: 0.1
--- author: NBSL
--- game: dr
--- description: Background gaze/exhale sanowret crystal for arcana training.
--- tags: arcana, training, crystal
---
--- Converted from sanowret-crystal.lic

no_kill_all()
no_pause_all()

local invalid_room = nil

while true do
    local line = get()
    if DRStats.concentration == 100 and not hidden() and invalid_room ~= (Room.current and Room.current.id) then
        local response = ""
        if DRSkill.getxp("Arcana") <= 10 then
            response = DRC.bput("gaze sanowret crystal",
                "A soft light blossoms", "lack the concentration", "not a good place")
        elseif DRSkill.getxp("Arcana") <= 25 then
            response = DRC.bput("exhale sanowret crystal",
                "understanding of Arcana", "lack the concentration", "not a good place", "give away your hiding")
        end
        if response and response:find("not a good place") then
            invalid_room = Room.current and Room.current.id
            pause(1)
        elseif response and (response:find("blossoms") or response:find("understanding")) then
            invalid_room = nil
            pause(6)
        end
    end
    if not line then pause(6) end
end
