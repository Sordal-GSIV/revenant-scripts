--- @revenant-script
--- name: darkbox
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Play the dark box game - stow prizes, handle tickets and pouches
--- tags: game, dark, prize

while true do
    fput("play dark")
    pause(2)
    -- Check if wounds prevent playing
    if reget(10, "your wounds make it impossible") then
        return
    end
    waitrt()
    local right = checkright()
    local left = checkleft()
    local thing = right or left
    if thing then
        if thing:match("sharkskin") or thing:match("root") or thing:match("rockweed")
           or thing:match("kelp") or thing:match("flowers") or thing:match("apple")
           or thing:match("strawberry") then
            fput("put " .. thing .. " in bin")
        elseif thing:match("pouch") then
            fput("open my pouch")
            fput("get my tickets from my pouch")
            fput("put pouch in bin")
        else
            fput("stow " .. thing)
        end
    end
    waitrt()
end
