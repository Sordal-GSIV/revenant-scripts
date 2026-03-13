-- autostart.lua
-- Runs scripts listed in CharSettings["autostart"] on login.
-- Set: CharSettings["autostart"] = "alias,vars"

local autostart = CharSettings["autostart"]
if not autostart or autostart == "" then return end

for name in autostart:gmatch("[^,]+") do
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then
        local ok, err = pcall(function() Script.run(name) end)
        if not ok then
            respond("[autostart] failed to start '" .. name .. "': " .. tostring(err))
        end
    end
end
