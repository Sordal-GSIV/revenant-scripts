--- @revenant-script
--- name: hummer
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-continue humming at appropriate difficulty.
--- tags: music, performance, training
--- Converted from hummer.lic
local diff = "reel"
echo("=== hummer ===")
echo("Waiting for humming to begin...")
while true do
    local line = get()
    if line and (line:find("You hum to yourself") or line:find("You finish humming")) then
        fput("hum " .. diff)
    end
end
