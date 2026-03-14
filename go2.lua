--- @revenant-script
--- name: go2
--- version: 0.1.0
--- author: Sordal
--- description: Room navigation using map pathfinding

-- go2.lua
-- Navigate to a room by ID or name.
-- Launch via ;go2 <destination>  or  Script.run("go2", "bank")

local vars = Script.vars
local dest = vars and vars[1]
if not dest or dest == "" then
    respond("[go2] Usage: ;go2 <room ID or name>")
    return
end

local room_id = tonumber(dest)
respond("[go2] Navigating to: " .. tostring(dest))

local success = Map.go2(room_id or dest)
if not success then
    respond("[go2] Could not find path to: " .. tostring(dest))
end
