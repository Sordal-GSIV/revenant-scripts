--- @revenant-script
--- name: stepcost
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Show the favor cost for your next Order of Voln step.

if Society.member ~= "Order of Voln" then
    echo("You're not a member of the Order of Voln.")
    echo("What are you thinking?!?")
    return
elseif Society.rank == 26 then
    echo("You're a master already, you don't need this!")
    return
end

local rank = Society.rank
local level = Stats.level
local cost = (rank * 100) + math.floor(((level ^ 2) * (math.ceil(rank / 3.0) * 5)) / 3)
echo("Step " .. (rank + 1) .. " Cost: " .. tostring(cost))
