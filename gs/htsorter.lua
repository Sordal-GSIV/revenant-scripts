--- @revenant-script
--- name: htsorter
--- version: 1.0.6
--- author: Ensayn
--- contributors: Tillmen
--- game: gs
--- description: Container contents organized by item categories with color coding
--- tags: utility, organization, containers
---
--- Usage:
---   ;htsorter              - Start the sorter
---   ;htsorter width=80     - Set column width

if script.vars[1] and script.vars[1]:match("^width=") then
    local w = script.vars[1]:match("width=(%d+)")
    CharSettings["screen_width"] = w and tonumber(w) or nil
    echo("Width setting saved.")
    exit()
elseif script.vars[1] then
    respond(";htsorter width=<#>  Set column width")
    respond(";htsorter width=nil  Clear width setting")
    exit()
end

echo("htsorter active - look in containers to see sorted contents")

add_hook("downstream", "htsorter", function(line)
    if not line:match("you see") then return line end

    -- Let the normal display pass through, we echo our sorted version
    local container_match = line:match("^([IO]n the .-) you see")
    if not container_match then return line end

    local container_id = line:match('exist="(%d+)"')
    if not container_id then return line end

    local contents = GameObj.containers and GameObj.containers[container_id]
    if not contents then return line end

    -- Sort by type
    local sorted = {}
    for _, item in ipairs(contents) do
        local cat = item.type or "other"
        sorted[cat] = sorted[cat] or {}
        table.insert(sorted[cat], item)
    end

    local output = container_match .. ":\n"
    local total = 0
    for cat, items in pairs(sorted) do
        output = output .. cat .. " (" .. #items .. "): "
        local names = {}
        for _, item in ipairs(items) do
            table.insert(names, item.full_name or item.name)
            total = total + 1
        end
        output = output .. table.concat(names, ", ") .. ".\n"
    end
    output = output .. "total (" .. total .. ")"
    respond(output)
    return nil -- suppress original
end)

before_dying(function() remove_hook("downstream", "htsorter") end)
while true do get() end
