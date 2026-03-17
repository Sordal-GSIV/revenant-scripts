--- @revenant-script
--- name: star_nap
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Cast Sleep (501) up to 3 times on every valid target in the room.

for _, target in ipairs(GameObj.targets()) do
    if not Spell[501]:known() then break end
    if not Spell[501]:affordable() then break end
    for _ = 1, 3 do
        if not target.name:find("vvrael") and not target.name:find("construct") then
            if not target.status:find("dead")
                and not target.status:find("gone")
                and not target.status:find("stunned")
                and not target.status:find("sleeping")
                and not target.status:find("calm")
                and not target.status:find("frozen")
            then
                if checkstance() ~= "guarded" and checkstance() ~= "defensive" then
                    fput("stance guarded")
                end
                Spell[501]:force_cast(target)
                waitrt()
                waitcastrt()
            end
        end
    end
end
