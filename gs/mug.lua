--- @revenant-script
--- name: mug
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Repeat mugging until target won't fall for it again or stamina runs out.

local function mug_activate()
    if not CMan.affordable("Mug") then
        return
    end

    local result = dothistimeout(
        "cman mug", 5,
        "You feel like you could try that again on|Roundtime|won't fall for that again"
    )

    if not result then
        return
    end

    if result:find("Roundtime") or result:find("won't fall for that again") then
        waitrt()
        return
    elseif result:find("You feel like you could try that again on") then
        waitrt()
        mug_activate()
    end
end

mug_activate()
