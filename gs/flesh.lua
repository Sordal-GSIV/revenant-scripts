--- @revenant-script
--- name: flesh
--- version: 1.1
--- author: Brute
--- game: gs
--- description: Keep the Primal flesh effect going; auto flesh-sense near known flesh eaters.
--- tags: flesh,monster

local last_sense = 0
local sense_friends = {
    "Brute", "Yakushi", "Altheren", "Daiyon", "Zenmagic",
    "Warclaidh", "Nordred", "Nalver",
}

while true do
    -- Check if any Primal buff is active
    local has_primal = false
    for name, _ in pairs(Effects.Buffs.to_h()) do
        if tostring(name):find("^Primal ") then
            has_primal = true
            break
        end
    end

    if has_primal then
        -- Sense flesh if a known PC is present and cooldown elapsed (15 min)
        local now = os.time()
        if (now - last_sense) > 900 then
            for _, pc in ipairs(GameObj.pcs()) do
                for _, friend in ipairs(sense_friends) do
                    if pc.name == friend then
                        waitrt()
                        waitcastrt()
                        fput("sense flesh")
                        last_sense = os.time()
                        goto done_sense
                    end
                end
            end
            ::done_sense::
        end
    elseif checkhealth() > 50 then
        fput("eat my flesh")
    end
    pause(0.1)
end
