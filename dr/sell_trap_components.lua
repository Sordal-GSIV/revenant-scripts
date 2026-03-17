--- @revenant-script
--- name: sell_trap_components
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Sell trap harvest components from a container
--- tags: traps, sell, loot

local loot_components = {
    "tiny hammer", "bronze seal", "bronze face", "broken needle",
    "steel pin", "capillary tube", "silver studs",
}
local component_container = "duffel bag"

for _, component in ipairs(loot_components) do
    fput("get " .. component .. " from my " .. component_container)
    fput("sell my " .. component)
end
