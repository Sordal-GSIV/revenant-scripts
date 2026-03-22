--- @revenant-script
--- name: speechify
--- version: 1.1.0
--- author: unknown
--- @lic-certified: complete 2026-03-20
--- game: gs
--- description: Deliver a speech from a text file, line by line on ";send speechify next"
--- tags: speech,roleplay
---
--- Usage: ;speechify <filename> [-s]
---   filename: name of a text file in your data/ folder (e.g. "myspeech.txt")
---   -s: (optional) SAY each line instead of executing as a command
---
--- Each time you send "next" to this script via ;send, the next line is delivered.
--- Recommended: create an alias or macro for ";send speechify next".

local filename = Script.vars[1]
local speak_only = Script.vars[2]

if not filename or filename == "" then
    echo("Usage: ;speechify <filename> [-s]")
    return
end

-- Enable unique mode so unique_waitfor() reads from the ;send buffer,
-- not the game stream. Without this toggle, unique_waitfor() will error.
toggle_unique()

local content, err = File.read("data/" .. filename)
if not content then
    echo("speechify: could not open data/" .. filename .. ": " .. (err or "unknown error"))
    return
end

echo("opened data/" .. filename)

for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    unique_waitfor("next")
    if speak_only == "-s" then
        put("say " .. line)
    else
        put(line)
    end
end

echo("*** SPEECH COMPLETE ***")
