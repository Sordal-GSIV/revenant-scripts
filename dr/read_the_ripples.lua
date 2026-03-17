--- @revenant-script
--- name: read_the_ripples
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Moon Mage Read the Ripples spell sequence with cambrinth charging.
--- tags: moonmage, magic, rtr

echo("### PREPARING READ THE RIPPLES ###")
fput("kneel")
fput("prep pg 15")
pause(15)
fput("cast")
pause(0.1)
fput("get orb")
for i = 1, 5 do
    fput("charge my orb 20")
    pause(6)
    waitrt()
end
fput("stow orb in thigh bag")

local armbands = {"armband", "other armband"}
for _, armb in ipairs(armbands) do
    waitrt()
    fput("charge my " .. armb .. " 29")
    pause(6)
    fput("invoke " .. armb)
    pause(2)
    waitrt()
end

fput("hold staff")
fput("prep rtr")
fput("invoke staff")
pause(26)
waitrt()
fput("wear staff")
fput("get orb from th bag")
fput("invoke orb")
waitfor("You feel fully prepared to cast")
pause(10)
fput("cast")
pause(1.5)
waitrt()
fput("put orb in thigh bag")
fput("get tele from tele case")
fput("open tele")
echo("### READ THE RIPPLES ###")
