--- @revenant-script
--- name: rest
--- version: 0.01
--- author: Crannach
--- game: dr
--- description: Periodically send EXP command (like built-in rest, but won't stop on input)
--- tags: afk, exp, rest

local interval = 120

while true do
    pause(interval)
    put("exp")
end
