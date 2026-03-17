--- @revenant-script
--- name: getwork
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Ask an NPC for crafting work until you get the right item and quantity
--- tags: crafting, work orders
---
--- Usage: ;getwork <npc> <difficulty> <discipline> <name> <count>
--- Example: ;getwork clerk challenging forging sword 5

local npc = Script.vars[1]
local difficulty = Script.vars[2]
local discipline = Script.vars[3]
local name = Script.vars[4]
local count = tonumber(Script.vars[5]) or 0

if not npc or not difficulty or not discipline or not name then
    echo("Usage: ;getwork <npc> <difficulty> <discipline> <name> <count>")
    return
end

fput("ask " .. npc .. " for " .. difficulty .. " " .. discipline .. " work")
while true do
    local line = get()
    if line then
        if line:match("^To whom") or line:match("^You realize you have") then
            break
        end
        local needed = line:match("order for.*" .. name .. ".*I need (%d+) of .* quality")
        if needed then
            if tonumber(needed) <= count then
                break
            end
            fput("ask " .. npc .. " for " .. difficulty .. " " .. discipline .. " work")
        elseif line:match("order for .* quality") then
            fput("ask " .. npc .. " for " .. difficulty .. " " .. discipline .. " work")
        end
    end
end
