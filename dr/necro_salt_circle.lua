--- @revenant-script
--- name: necro_salt_circle
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Necromancer salt circle with bank/navigation.
--- tags: necromancer, salt, ritual
--- Converted from necro-salt-circle.lic

if not DRStats.necromancer then echo("***MUST BE A NECROMANCER!***") return end

local skip_bank = Script.vars[1] and Script.vars[1]:lower():match("^s")

UserVars.salt_circle_last = UserVars.salt_circle_last or (os.time() - 86400)
if os.time() - UserVars.salt_circle_last < 86400 then
    echo("Not enough time has passed!") return
end

DREMgr.empty_hands()
if not skip_bank then
    DRCT.walk_to(get_data("town")["Shard"].deposit.id)
    DRC.bput("withdraw 5000 copper dok", "clerk counts", "count out")
end

wait_for_script_to_complete("go2", {"9668"})
DRC.bput("give Niloa 5000 copper dok", "Niloa smiles", "Niloa frowns")

local colors = {"red", "green", "black"}
for _, color in ipairs(colors) do
    while true do
        local result = DRC.bput("turn my glass vial", "colored salt", "empty", "Turn what")
        if result and result:find(color) then
            DRC.bput("pour my glass vial", "You.*pour") break
        elseif result and (result:find("empty") or result:find("Turn what")) then
            echo("***Something went wrong!***") return
        end
    end
end
DRC.bput("clean circle", "You carefully")
UserVars.salt_circle_last = os.time()
