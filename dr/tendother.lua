--- @revenant-script
--- name: tendother
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-tend another player's bleeding wounds.
--- tags: healing, tending, wounds
--- Usage: ;tendother <name>

local target = Script.vars[1]
if not target then echo("Usage: ;tendother <name>") return end

local function bind_open_wounds(tgt)
    fput("look " .. tgt)
    pause(2)
end

bind_open_wounds(target)

while true do
    local line = get()
    if line then
        local wound = line:match("The bandages binding " .. target .. "'s (.-) come loose")
            or line:match("The bandages binding " .. target .. "'s (.-) soak through")
        if wound then
            DRC.bind_wound(wound, target)
        end
    end
end
