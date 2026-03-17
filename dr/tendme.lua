--- @revenant-script
--- name: tendme
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-tend your own bleeding wounds.
--- tags: healing, tending, wounds
--- Converted from tendme.lic

local function bind_open_wounds()
    DRC.bput("heal", "^You")
    pause(1)
end

bind_open_wounds()

while true do
    local line = get()
    if line then
        local wound = line:match("The bandages binding your (.-) come loose")
            or line:match("The bandages binding your (.-) soak through")
        if wound then
            DRC.bind_wound(wound)
            bind_open_wounds()
        end
        if Script.vars and Script.vars[0] and Script.vars[0]:find("train") then
            wound = line:match("might be a good time to change the bandages on your (.-)%.")
            if wound then
                DRC.unwrap_wound(wound)
                DRC.bind_wound(wound)
                bind_open_wounds()
            end
        end
    end
end
