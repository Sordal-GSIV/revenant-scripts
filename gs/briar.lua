--- @revenant-script
--- name: briar
--- version: 1.0.0
--- author: Ralkean
--- game: gs
--- description: Auto-raise briar bow to activate buff every 2 minutes when influence is full
--- tags: briar,buff,bow
---
--- Raises bow to activate briar buff every 2 minutes or when influence is available.
--- Modify nouns for briar weapons and/or accessories as needed.

local BRIAR_INFLUENCE_RE = Regex.new("Blood Points: (\\d+)")
local BUFF_ACTIVE_MSG = "the briars imbedded in your flesh release their stored blood in a massive pulse of power that you can feel in the core of your very being.  The vines lose all crimson hues, and strength courses through your blood."
local BUFF_ENDED_MSG = "You no longer look stronger."

local function check_influence()
    local lines = quiet_command("peer my grapevine", { "Blood Points:", "You peer" })
    for _, line in ipairs(lines) do
        local m = BRIAR_INFLUENCE_RE:match(line)
        if m then
            return tonumber(m:match("(%d+)"))
        end
    end
    return 0
end

while true do
    -- Wait for full influence
    while check_influence() ~= 100 do
        pause(3)
    end

    -- Raise bow and wait for activation
    while true do
        waitrt()
        if checkrt() == 0 then
            fput("raise my bow")
        end
        local result = matchtimeout(5, { BUFF_ACTIVE_MSG })
        if result and result:find(BUFF_ACTIVE_MSG, 1, true) then
            break
        end
    end

    -- Wait for buff to end
    matchtimeout(130, { BUFF_ENDED_MSG })
end
