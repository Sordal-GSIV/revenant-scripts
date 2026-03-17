--- @revenant-script
--- name: timer
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Simple elapsed-time counter displayed every second.

local count = 0

while true do
    count = count + 1
    pause(1)
    local minutes = math.floor(count / 60)
    local seconds = count - minutes * 60
    echo(string.format("(%ds = (%dm%ds)", count, minutes, seconds))
end
