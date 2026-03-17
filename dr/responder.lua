--- @revenant-script
--- name: responder
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Auto-respond to people who talk to you with random emotes
--- tags: social, emote, afk

local emotes = {"glare", "gasp", "gawk", "gaze", "ponder", "shrug", "tease", "flail"}

while true do
    local line = get()
    if line then
        local sayer = line:match("^(%S+).-(says to you|exclaims to you|asks you)")
        if sayer then
            fput("glance " .. sayer)
            pause(3)
            fput(emotes[math.random(#emotes)] .. " " .. sayer)
        end
    end
end
