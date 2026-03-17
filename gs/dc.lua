--- @revenant-script
--- name: dc
--- version: 1.1.0
--- author: Zegres
--- game: gs
--- description: Cast Dark Catalyst (719) and display total damage dealt
--- tags: 719,dark catalyst,damage
---
--- Casts dark catalyst and displays the total amount of damage.

local total_damage = 0

fput("incant 719")

local timeout = os.time() + 4

while true do
    local line = get()
    if not line then break end

    local dmg = line:match("(%d+) points? of damage")
    if dmg then
        total_damage = total_damage + tonumber(dmg)
    end

    if line:lower():find("cast roundtime") then break end
    if os.time() > timeout then break end
end

if total_damage == 0 then
    echo("No valid target or hidden enemy. Dark Catalyst cast failed to hit anything.")
else
    echo("Total damage from Dark Catalyst: " .. total_damage)
    if total_damage > 200 then
        echo("========== WOW COOL! ===========")
    end
end
