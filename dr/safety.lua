--- @revenant-script
--- name: safety
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: AFK safety net - depart on death, retreat on low health, flee on medium
--- tags: safety, afk, death, health

echo("Afk script started - pausing for 30 seconds")
pause(30)

while true do
    local line = get()
    pause(0.1)
    if checkdead() then
        echo("Afk - detected death departing in 1 minute")
        pause(60)
        fput("depart item")
        fput("exit")
    elseif checkhealth() < 40 then
        echo("Afk - detected low health")
        fput("exit")
    elseif checkhealth() < 60 then
        fput("retreat")
        fput("retreat")
        start_script("go2", {"793"})
    end
end
