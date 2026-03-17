--- @revenant-script
--- name: debugroomid
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Display current room UID, segment, Lich ID, title, location, and map link.

local room = Room.current()
if not room or not room.uid or #room.uid == 0 then
    echo("Room has no UID")
    return
end

local uid = room.uid[1]
local output = {
    { "UID",        tostring(uid) },
    { "Segment ID", tostring(math.floor(uid / 1000)) },
    { "Room Number", string.format("%03d", uid % 1000) },
    { "Lich ID",    tostring(room.id) },
    { "Title",      room.title[1] or "" },
    { "Location",   room.location or "" },
    { "Map Link",   "https://lich-mapdb-room.ffng.xyz/u" .. tostring(uid) },
}

-- Find longest key for alignment
local max_len = 0
for _, pair in ipairs(output) do
    if #pair[1] + 1 > max_len then max_len = #pair[1] + 1 end
end

for _, pair in ipairs(output) do
    local key = pair[1]
    local padding = string.rep(" ", max_len - #key)
    respond(key .. padding .. ": " .. pair[2])
end
