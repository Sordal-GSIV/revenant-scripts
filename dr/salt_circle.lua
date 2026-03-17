--- @revenant-script
--- name: salt_circle
--- version: 1.0
--- author: Raelok/Kalros/Haldrik
--- game: dr
--- description: Necromancer salt circle ritual (24-hour cooldown).
--- tags: necromancer, salt, ritual

local last_circle = UserVars.salt_circle or 0
local elapsed = os.time() - last_circle
local minutes = math.floor(elapsed / 60)
local remaining = math.floor(((86400 - elapsed) / 60) / 60 * 100) / 100

echo("It has been " .. minutes .. " minutes since your last salt circle.")
if elapsed < 86400 then
    echo("Time remaining: " .. remaining .. " hours.")
    return
end

echo("Time to create a salt circle.")
wait_for_script_to_complete("go2", {"9668"})
DRC.bput("give Nil 5000 dokoras", "Niloa smiles")

local function turn_vial(color)
    while true do
        local result = DRC.bput("turn my vial", "colored salt")
        if result and result:find(color) then return end
    end
end

local function salt(color)
    turn_vial(color)
    DRC.bput("pour my vial", "You carefully")
end

salt("red")
salt("green")
salt("black")
DRC.bput("clean circle", "You carefully")
UserVars.salt_circle = os.time()
