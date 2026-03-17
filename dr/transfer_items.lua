--- @revenant-script
--- name: transfer_items
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Transfer items between containers.
--- tags: items, container, transfer
---
--- Usage: ;transfer_items <source> <destination>

local source = Script.vars[1]
local destination = Script.vars[2]

if not source or not destination then
    echo("Usage: ;transfer_items <source_container> <destination_container>")
    return
end

fput("look in my " .. source)
while true do
    local line = get()
    if line and line:find("you see") then
        local items_str = line:gsub("^.*you see ", ""):gsub("%.$", "")
        items_str = items_str:gsub(" and ", ",")
        for item in items_str:gmatch("[^,]+") do
            item = item:match("^%s*(.-)%s*$")
            if #item > 0 then
                local parts = {}
                for word in item:gmatch("%S+") do
                    table.insert(parts, word)
                end
                local noun = parts[#parts]:gsub("%.", "")
                fput("get " .. noun .. " from my " .. source)
                fput("put " .. noun .. " in my " .. destination)
            end
        end
        break
    end
end
