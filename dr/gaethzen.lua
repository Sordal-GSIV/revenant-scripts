--- @revenant-script
--- name: gaethzen
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Charge and activate a gaethzen item for light.
--- tags: gaethzen, utility, light

local settings = get_settings()
local gaethzen_item = settings.gaethzen_item or "orb"

if checkleft() then
    DRC.bput("stow left", "Stow what", "You put")
end
DRC.bput("get my " .. gaethzen_item, "You get", "What were", "You are already")

local function use_gaethzen()
    waitrt()
    local result = DRC.bput("charge my " .. gaethzen_item .. " 36", "I could not find", "You harness")
    if result == "I could not find" then
        echo("COULD NOT FIND YOUR GAETHZEN!")
        return
    end
    DRC.bput("focus my " .. gaethzen_item, "almost magically null", "reach for its center and forge", "Your link")
    local rub_result = DRC.bput("rub my " .. gaethzen_item, "glow", "extinguishes")
    if rub_result and rub_result:find("extinguishes") then
        use_gaethzen()
    end
end

use_gaethzen()
