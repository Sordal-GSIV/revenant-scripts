--- @revenant-script
--- name: debugroomid
--- version: 1.1
--- author: unknown
--- lic-source: lib/debugroomid.lic
--- lic-certified: complete 2026-03-19
--- game: gs
--- description: Display current room UID, segment, Lich ID, title, location, and map link.

local Messaging = require("lib/messaging")

local room = Room.current()
if not room then
    Messaging.msg("warn", "Room has no UID")
    return
end

-- uid can be a string, a table of strings, or nil
local uid_raw = room.uid
local uid
if type(uid_raw) == "table" then
    if #uid_raw == 0 then
        Messaging.msg("warn", "Room has no UID")
        return
    end
    uid = tonumber(uid_raw[1])
elseif type(uid_raw) == "string" then
    uid = tonumber(uid_raw)
end

if not uid then
    Messaging.msg("warn", "Room has no UID")
    return
end

local output = {
    { "UID",         tostring(uid) },
    { "Segment ID",  tostring(math.floor(uid / 1000)) },
    { "Room Number", string.format("%03d", uid % 1000) },
    { "Lich ID",     tostring(room.id) },
    { "Title",       room.title or "" },
    { "Location",    room.location or "" },
    { "Map Link",    "https://lich-mapdb-room.ffng.xyz/u" .. tostring(uid) },
}

-- Find longest key for alignment (matches original: key length + 1)
local max_len = 0
for _, pair in ipairs(output) do
    if #pair[1] + 1 > max_len then max_len = #pair[1] + 1 end
end

for _, pair in ipairs(output) do
    local key = pair[1]
    local padding = string.rep(" ", max_len - #key)
    respond(key .. padding .. ": " .. pair[2])
end
