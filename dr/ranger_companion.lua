--- @revenant-script
--- name: ranger_companion
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Care for baby ranger companion - feed and pet.
--- tags: ranger, companion, pet
--- Converted from ranger-companion.lic

no_pause_all()

DRC.bput("whistle for companion", "scrambles in", "whistle a merry tune",
    "perks", "whistle loudly", "purse your lips")

before_dying(function()
    DRC.bput("signal companion to sleep", "wanders off", "not", "no companion", "snapping")
end)

while true do
    local line = get()
    if line then
        if line:find("wolf paces back and forth") or line:find("wolf stands up then paces") then
            DRC.bput("pet wolf", "You pet", "Touch what", "shies away")
        end
        if line:find("raccoon paces back and forth") or line:find("raccoon stands up then paces") then
            DRC.bput("pet raccoon", "You pet", "Touch what")
        end
        if line:find("wolf begins to whimper") then
            waitrt()
            DRC.bput("stow left", "Stow what", "You put")
            local result = DRC.bput("get my milk", "You get", "You are already", "What were")
            if result == "What were" then
                DRC.bput("signal companion to sleep", "wanders off", "not", "no companion")
                return
            end
            DRC.bput("feed my milk to wolf", "greedily drinks", "doesn't seem hungry", "shies away")
            DRC.bput("stow my milk", "You put", "Stow what")
        end
        if line:find("raccoon begins to whimper") then
            waitrt()
            DRC.bput("stow left", "Stow what", "You put")
            local result = DRC.bput("get my corn", "You get", "You are already", "What were")
            if result == "What were" then
                DRC.bput("signal companion to sleep", "wanders off")
                return
            end
            DRC.bput("feed my corn to raccoon", "greedily eats")
            DRC.bput("stow my corn", "You put", "Stow what")
        end
    end
end
