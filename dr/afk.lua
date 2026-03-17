--- @revenant-script
--- name: afk
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Simple AFK loop - alternates LOOK and EXP with status messages
--- tags: afk, idle

while true do
    fput("look")
    pause(60)
    echo("           ")
    echo("           ")
    echo(" ** AFK ** ")
    echo("           ")
    echo("           ")
    fput("exp")
    pause(60)
    echo("           ")
    echo("           ")
    echo(" ** AFK ** ")
    echo("           ")
    echo("           ")
end
