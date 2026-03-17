--- @revenant-script
--- name: healself
--- version: 1.0
--- author: Relaife
--- game: dr
--- description: Empath self-healing with configurable spell mana.
--- tags: empath, healing, self
--- Converted from healself.lic
local hwmana = 5
local hsmana = 10

local function heal_loop()
    put("heal")
    local line = get()
    if line and line:find("no injuries") then return end
    waitrt()
    put("prep hw " .. hwmana)
    waitfor("fully prepared")
    put("cast")
    waitrt()
    pause(1)
    put("prep hs " .. hsmana)
    waitfor("fully prepared")
    put("cast")
    waitrt()
    heal_loop()
end

heal_loop()
