--- @revenant-script
--- name: mechanical
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Forage and braid for mechanical lore training.
--- tags: crafting, mechanical, braiding
--- Converted from mechanical.lic

local hands = "gloves"
local trash = "hole"
local mat = "vine"

fput("remove my " .. hands); fput("stow my " .. hands)

while DRSkill.getxp("Mechanical Lore") < 34 do
    waitrt()
    local result = dothistimeout("forage " .. mat, 10, {"you manage", "Roundtime"})
    if result and result:find("Roundtime") and not result:find("manage") then
        mat = "grass"
        fput("forage " .. mat)
    end
    waitrt()
    fput("braid my " .. mat)
    local braid_result = get()
    if braid_result and braid_result:find("mistake") then
        waitrt(); fput("pull my " .. mat)
        waitrt()
    elseif braid_result and braid_result:find("need to have more") then
        -- Need more material
    end
    waitrt()
end

fput("drop my rope"); fput("drop my " .. mat)
fput("get my " .. hands); fput("wear my " .. hands)
