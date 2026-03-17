--- @revenant-script
--- name: speechify
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Deliver a speech from a text file, line by line on ";send speechify next"
--- tags: speech,roleplay
---
--- Usage: ;speechify <filename> [-s]
---   filename: name of a text file in your data folder
---   -s: (optional) SAY each line instead of executing as a command
---
--- Each time you ";send speechify next", the next line is sent.

local filename = Script.vars[1]
local speak_only = Script.vars[2]

if not filename or filename == "" then
    echo("Usage: ;speechify <filename> [-s]")
    return
end

local filepath = DataDir .. "/" .. filename

local f = io.open(filepath, "r")
if not f then
    echo("speechify: could not open " .. filepath)
    return
end

echo("opened " .. filepath)

before_dying(function()
    if f then f:close() end
end)

for line in f:lines() do
    unique_waitfor("next")
    if speak_only == "-s" then
        put("say " .. line)
    else
        put(line)
    end
end

f:close()
f = nil

echo("*** SPEECH COMPLETE ***")
