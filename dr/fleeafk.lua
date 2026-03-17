--- @revenant-script
--- name: fleeafk
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Flee to a safe room when specific players arrive
--- tags: afk, flee, safety
---
--- Usage: Edit the name prefixes and destination room as needed.

while true do
    pause(0.25)
    local pcs = DRRoom.pcs or {}
    for _, name in ipairs(pcs) do
        local first_char = name:sub(1, 1)
        if first_char == "Q" or first_char == "R" then
            DRC.walk_to(793)
            return
        end
    end
end
