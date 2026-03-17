--- @revenant-script
--- name: star_autoaccept
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Automatically ACCEPTs any offer from anyone. Stop with ;kill star_autoaccept

echo("[star-autoaccept] Waiting for offers...")

while true do
    local line = get()
    if line and line:find("offers you") then
        waitrt()
        fput("ACCEPT")
    end
end
