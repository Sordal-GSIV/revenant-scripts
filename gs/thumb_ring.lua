--- @revenant-script
--- name: thumb_ring
--- version: 1.0
--- author: Brute
--- game: gs
--- description: Keeps your EG urglaes thumb-ring spinning (Crooked/Corrupt Intent buff).

while true do
    local thumb_ring = nil
    for _, obj in ipairs(GameObj.inv()) do
        if obj.name:find("urglaes thumb%-ring") or obj.name:find("thumb%-armor") then
            thumb_ring = obj
            break
        end
    end
    if thumb_ring
        and not Effects.Buffs.active("Crooked Intent")
        and not Effects.Buffs.active("Corrupt Intent")
        and checkspirit() >= 7
    then
        fput("turn my #" .. thumb_ring.id)
    end
    pause(0.1)
end
