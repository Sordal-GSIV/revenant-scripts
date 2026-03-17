--- @revenant-script
--- name: keepalive
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Respond to idle timeout warnings to stay connected
--- tags: idle, afk, keepalive

local n = 0
while true do
    waitfor("you have been idle too long")
    fput("look")
    n = n + 1
    echo("TIMESTAMP #" .. n .. ": " .. os.date())
end
