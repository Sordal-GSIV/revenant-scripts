--- @revenant-script
--- name: tending
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Auto-tend wounds when bandages soak through or come loose
--- tags: healing, tending, first-aid

no_kill_all()
no_pause_all()
silence_me()

while true do
    local line = waitfor("The bandages binding your", "The bandages binding your")
    local wound = line:match("The bandages binding your (%S+)")
    if wound then
        waitrt()
        while true do
            local result = DRC.bput("tend my " .. wound,
                "work carefully at tending your wound",
                "%.%.%.wait")
            if result and result:match("work carefully") then
                break
            end
            pause(1)
        end
    end
end
