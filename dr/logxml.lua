--- @revenant-script
--- name: logxml
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Log downstream XML to file for debugging.
--- tags: debug, logging, xml
--- Converted from logxml.lic

local date = os.date("%Y-%m-%d")
local name = Char.name
local log_file = "logs/" .. name .. "-" .. date .. "-xml.log"
echo("### Logging XML to " .. log_file)
local file = io.open(log_file, "a")
if not file then echo("ERROR: Could not open log file!") return end
file:write(os.date("%Y-%m-%d %I:%M%p") .. "\n")
before_dying(function() if file then file:close() end end)
while true do
    local line = get()
    if line and file then file:write(line .. "\n"); file:flush() end
end
