--- @revenant-script
--- name: birdwatchingwindow
--- version: 1.1.0
--- author: unknown
--- game: gs
--- tags: wrayth, birdwatching, window, spyglass
--- description: Real-time Wrayth window showing birds and feathers in current room
---
--- Original Lich5 authors: unknown (ChatGPT assisted)
--- Ported to Revenant Lua from birdwatchingwindow.lic v1.1.0
---
--- Usage: ;birdwatchingwindow
--- Requires: birdwatching_explore data, bird_fieldguide

put("<closeDialog id='Birdwatching'/><openDialog type='dynamic' id='Birdwatching' title='Birdwatching' target='Birdwatching' scroll='auto' location='main' justify='3' height='300' resident='true'><dialogData id='Birdwatching'></dialogData></openDialog>")

-- In Revenant, YAML data loading is handled via Lua tables or JSON.
-- This is a structural port; the data source would need adaptation.

local function push_bird_room_data_to_window()
    local uid = tostring(Room.current.uid or ""):gsub("[%[%]]", "")
    if uid == "" then return end

    local y = 0
    local output = "<dialogData id='Birdwatching' clear='t'>"
    output = output .. "<label id='uid' value='UID: " .. uid .. "' left='10' top='" .. y .. "' font='font-bold'/>"
    y = y + 20

    -- Placeholder: in full implementation, load bird data from storage
    output = output .. "<label id='info' value='Bird data loading requires birdwatching_explore data file.' left='10' top='" .. y .. "'/>"
    y = y + 20

    output = output .. "</dialogData>"
    put(output)
end

local last_uid = nil

while true do
    local current_uid = tostring(Room.current.uid or ""):gsub("[%[%]]", "")
    if current_uid ~= "" and current_uid ~= last_uid then
        last_uid = current_uid
        push_bird_room_data_to_window()
    end
    wait(0.5)
end
