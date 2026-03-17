--- @revenant-script
--- name: newlooter
--- version: 1.0
--- author: Ofis
--- game: dr
--- description: Simple idle loot - arrange, skin, loot, pickup.
--- tags: looting, skinning, combat
--- Converted from newlooter.lic

pause(2); waitrt()
local righthand = checkright()
if righthand then fput("wear my " .. righthand) end

fput("arrange")
local line = get()
if line and line:find("You begin to arrange") then
    waitfor("You continue arranging", "complete arranging")
end

waitrt(); fput("skin")
waitrt(); fput("loot")

-- Pick up gems
while true do
    waitrt(); fput("stow gem")
    local result = get()
    if result and result:find("Stow what") then break end
end

-- Pick up boxes
waitrt(); fput("stow box")

-- Pick up coins
while true do
    waitrt(); fput("get coin")
    local result = get()
    if result and result:find("What were you referring to") then break end
end

waitrt()
if righthand then fput("get my " .. righthand) end
