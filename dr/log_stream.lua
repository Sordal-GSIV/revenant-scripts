--- @revenant-script
--- name: log_stream
--- version: 1.0
--- author: unknown
--- contributors: Tarjan
--- game: dr
--- description: Log raw game stream to a file for debugging.
--- tags: debug, logging, stream

local date = os.date("%Y-%m-%d")
local name = Char.name:lower()
local log_file = "logs/stream-" .. name .. "_" .. date .. ".log"

echo("### Logging stream to " .. log_file)

local file = io.open(log_file, "a")
if not file then
    echo("ERROR: Could not open log file!")
    return
end

before_dying(function()
    if file then file:close() end
end)

while true do
    local line = get()
    if line and file then
        file:write(line .. "\n")
        file:flush()
    end
end
