--- @revenant-script
--- name: tcdeath
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Auto-cast Symbol of Preservation and Symbol of Recall on death. Add to autostart.

while true do
    wait_until(function() return dead() end)
    echo("You have died! Preserving you and recalling your spells. Don't forget your chrism!")
    fput("symbol of preservation")
    fput("symbol of recall")
    wait_while(function() return dead() end)
end
