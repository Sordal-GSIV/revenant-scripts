--- @revenant-script
--- name: chat
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Route private messages to the talk window
--- tags: chat, private, window

local fam_window_begin = '<pushStream id="talk" ifClosedStyle="watching"/>'
local fam_window_end = "<popStream/>\r\n"

while true do
    local line = get()
    if line and line:match("^%[Private") then
        put(fam_window_begin .. line .. "\r\n" .. fam_window_end)
    end
end
