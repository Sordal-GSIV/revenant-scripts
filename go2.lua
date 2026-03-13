-- go2.lua
-- Navigate to a room by ID or name.
-- Launch via Script.run("go2") after setting Script.args to destination.
-- Usage from another script: Script.args = "bank"; Script.run("go2")

local dest = Script.args
if not dest or dest == "" then
    respond("[go2] Usage: set Script.args to a room ID or name, then Script.run('go2')")
    return
end

local room_id = tonumber(dest)
respond("[go2] Navigating to: " .. tostring(dest))

local success = Map.go2(room_id or dest)
if not success then
    respond("[go2] Could not find path to: " .. tostring(dest))
end
