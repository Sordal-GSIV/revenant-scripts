--- @revenant-script
--- name: wounds
--- version: 1.0
--- author: Gizmo
--- game: dr
--- description: Automatically LOOK PERSON WOUNDS when new players arrive in the room.
--- tags: wounds, healing, empath
---
--- Usage: ;wounds

no_pause_all()

local last_pcs = {}

local function get_pcs()
    local pcs = {}
    if DRRoom and DRRoom.pcs then
        for _, pc in ipairs(DRRoom.pcs) do
            table.insert(pcs, pc)
        end
    end
    return pcs
end

last_pcs = get_pcs()

while true do
    local line = get()
    if line and line:find("room players") then
        local cur_pcs = get_pcs()
        local seen = {}
        for _, pc in ipairs(last_pcs) do
            seen[pc] = true
        end
        for _, pc in ipairs(cur_pcs) do
            if not seen[pc] then
                fput("look " .. pc .. " wounds")
            end
        end
        last_pcs = cur_pcs
    end
end
