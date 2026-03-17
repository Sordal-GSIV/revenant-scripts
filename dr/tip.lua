--- @revenant-script
--- name: tip
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Withdraw money from bank and give it to someone as a tip
--- tags: money, tip, social
---
--- Usage: ;tip <person>
--- Edit townid, bank, amount, and type below to match your setup.

local person = Script.vars[1]
if not person then
    echo("Usage: ;tip <person>")
    return
end

local townid = "764"
local amount = "1"
local coin_type = "gold"
local bank = "1900"

start_script("go2", {bank, "_disable_confirm_"})
wait_while(function() return Script.running("go2") end)
fput("withdraw " .. amount .. " " .. coin_type)

start_script("go2", {townid, "_disable_confirm_"})
wait_while(function() return Script.running("go2") end)
fput("give " .. person .. " " .. amount .. " " .. coin_type)
