--- @revenant-script
--- name: shoplimitedtreasures
--- version: 1.0.0
--- author: Damiza Nihshyde
--- game: dr
--- description: Auto-purchase limited treasures from shop based on YAML buy list
--- tags: shop, treasures, limited, buy
---
--- Settings (CharSettings YAML):
---   limited_treasures_buy_list:
---     - wings
---     - dragon
---     - dragons
---
--- Add the nouns of the items you want to purchase to the list.

local settings = get_settings()
local keeplist = settings.limited_treasures_buy_list

if not keeplist or #keeplist == 0 then
    echo("Error: The limited treasures buy list is not set or is empty.")
    return
end

-- Build a pattern from the keeplist
local function matches_keeplist(text)
    local lower = text:lower()
    for _, item in ipairs(keeplist) do
        if lower:find("%f[%a]" .. item:lower() .. "%f[%A]") then
            return item
        end
    end
    return nil
end

-- Walk to the shop (DR room 10205)
DRCT.walk_to(10205)

-- Wait for the shop to open
while true do
    local trigger = waitfor(
        "disables its defense mechanisms",
        "revealing its opening",
        "Gortik .* curtained doorway%.",
        "Gortik .* through a curtained door%."
    )
    local normalized = trigger:match("^%s*(.-)%s*$")
    if not normalized:match("^Merchant Gortik came through a curtained door%.?$") then
        break
    end
end

fput("go curtain door")

-- Check each stand
local stands = {"stand", "second stand", "third stand"}
for _, stand in ipairs(stands) do
    local result = DRC.bput("shop " .. stand, "see some details", ".")
    if result then
        for line in result:gmatch("[^\n]+") do
            local item = matches_keeplist(line)
            if item then
                fput("buy " .. item .. " on " .. stand)
                fput("stow")
            end
        end
    end
end
