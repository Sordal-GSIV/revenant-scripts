--- @revenant-script
--- name: bandaid
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Auto-fire when already targeting something (combat helper)
--- tags: combat, ranged

while true do
    local line = get()
    if line and line:find("You are already targetting that") then
        fput("fire")
    end
end
