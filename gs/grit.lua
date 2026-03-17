--- @revenant-script
--- name: grit
--- version: 1.0.2
--- author: Peggyanne
--- game: gs
--- description: Apply WPS (Weapon Prestige System) service packs to items
--- tags: wps, warrior, guild, service, grit
---
--- Usage:
---   ;grit <amount> <type> <item_noun>
---   Must be holding the item in your right hand.
---   Example: ;grit 8 crit sword

local function help_display()
    respond([[
    Grit Version: 1.0.2 (February 16, 2025)

       Usage:

       Must Be Holding the Item in Your Right Hand and Enter Amount, Type and Item Noun
       IE: ;grit 8 crit <item noun>

     A simple script for applying your WPS. It will run to the nearest bank and get
     silvers for service packs then buy the packs and apply them.

       ~Peggyanne
     PS: feel free to send me any bugs via discord Bait#4376
    ]])
end

local amount_str = Script.vars[1]
local wps_type   = Script.vars[2]
local item_noun  = Script.vars[3]

if not amount_str then
    respond("")
    respond("Must Be Holding the Item in Your Right Hand and Enter Amount, Type and Item Noun IE: ;grit 8 crit <item noun>")
    respond("")
    return
elseif amount_str == "help" or amount_str == "?" then
    help_display()
    return
end

if not wps_type then
    respond("")
    respond("Must Be Holding the Item in Your Right Hand and Enter Amount, Type and Item Noun IE: ;grit 8 crit <item noun>")
    respond("")
    return
end

if not item_noun then
    respond("")
    respond("Must Be Holding the Item in Your Right Hand and Enter Amount, Type and Item Noun IE: ;grit 8 crit <item noun>")
    respond("")
    return
end

local amount = tonumber(amount_str) or 0

fput("stow right")
local return_location = Room.current() and Room.current().id

start_script("go2", {"bank"})
wait_while(function() return running("go2") end)

local withdrawal_amount = 25000 * amount
fput("withdraw " .. withdrawal_amount)

start_script("go2", {"warrior guild shop master"})
wait_while(function() return running("go2") end)

for _ = 1, amount do
    multifput("buy service pack", "buy confirm", "stow pack")
    pause(0.5)
end

fput("get " .. item_noun)

for _ = 1, amount do
    local rh = GameObj.right_hand()
    local rh_noun = rh and rh.noun or item_noun
    multifput("get supply pack", "feat wps assess " .. wps_type .. " " .. rh_noun)
    waitrt()
    pause(1)
    fput("feat wps apply " .. wps_type .. " " .. rh_noun)
    waitrt()
    pause(1)
end

if return_location then
    start_script("go2", {tostring(return_location)})
    wait_while(function() return running("go2") end)
end
