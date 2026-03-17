--- @revenant-script
--- name: arenawatch
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Watch arena NPCs and perform dodge reactions.
--- tags: arena, training, evasion
---
--- Converted from arenawatch.lic

local reactions = {
    ["pedal"] = "you could try to pedal",
    ["bob"] = "you could try to bob",
    ["duck"] = "you could try to duck",
    ["jump"] = "you could try to jump",
    ["lean"] = "you could try to lean",
    ["cower"] = "you could try to cower",
}

while true do
    local npcs = DRRoom and DRRoom.npcs or {}
    if #npcs > 0 then
        for _, npc in ipairs(npcs) do
            waitrt()
            local result = DRC.bput("watch " .. npc, "you could try to pedal",
                "you could try to bob", "you could try to duck",
                "you could try to jump", "you could try to lean",
                "you could try to cower", ".*")
            for action, pattern in pairs(reactions) do
                if result and result:find(pattern, 1, true) then
                    DRC.bput(action, ".*")
                    break
                end
            end
        end
    end
    pause(1)
end
