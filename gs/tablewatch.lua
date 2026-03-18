--- @revenant-script
--- name: tablewatch
--- version: 2.0
--- author: Fulmen
--- game: gs
--- description: Table protection - blocks exit while table is deployed, tracks location
--- tags: merchant, table, protection
---
--- Usage:
---   ;tablewatch         - Start monitoring
---   ;tablewatch help    - Show help

if script.vars[1] == "help" then
    respond("Tablewatch - Table Protection Script")
    respond("Blocks EXIT while your table is deployed.")
    respond("Tracks your location and warns if you leave.")
    respond("TINKER your table to pack it up and restore exit.")
    exit()
end

local table_room = Room.id
local table_room_name = Room.title or "Unknown"
local away = false
local start_time = os.time()

echo("Tablewatch active. Table at " .. table_room_name)
echo("Exit blocked until table is packed.")

add_hook("downstream", "tablewatch_detect", function(line)
    if line:match("trigger the transformation") or line:match("pick.*basket.*up") or line:match("table.*folds.*into") then
        echo("Table packed! Shutting down.")
        remove_hook("downstream", "tablewatch_detect")
        exit()
    end
    return line
end)

before_dying(function()
    remove_hook("downstream", "tablewatch_detect")
    echo("Tablewatch stopped. Exit restored.")
end)

while true do
    local current = Room.id
    if current ~= table_room and not away then
        away = true
        echo("WARNING: You left your table at " .. table_room_name .. "!")
    elseif current == table_room and away then
        away = false
        echo("Back at your table.")
    end

    local remaining = 7200 - (os.time() - start_time)
    if remaining <= 900 and remaining > 0 then
        echo("WARNING: " .. math.floor(remaining / 60) .. " minutes left on table!")
    end

    pause(30)
end
