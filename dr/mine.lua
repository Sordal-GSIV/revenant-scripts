--- @revenant-script
--- name: mine
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Hands-free mining - pickaxe/shovel management.
--- tags: mining, crafting, resources
--- Usage: ;mine [nograb|shovel]
--- Converted from mine.lic
local mode = Script.vars[1] or ""
fput("stow left"); fput("stow right")
if mode:lower() == "shovel" then
    fput("get my shovel")
else
    fput("get my pickaxe")
end
echo("=== mine ===")
echo("Mining in current room. Use ;kill mine to stop.")
while true do
    waitrt()
    fput("mine")
    local line = get()
    if line and line:find("roundtime") then waitrt() end
    if line and line:find("cannot mine") then echo("Cannot mine here."); break end
end
