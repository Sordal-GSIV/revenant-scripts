--- @revenant-script
--- @lic-audit-source: shoplimitedtreasures.lic
--- @original-authors: Damiza Nihshyde (Discord: kirinartistry)
--- @lic-certified: complete 2026-03-19
--- name: shoplimitedtreasures
--- version: 1.1.0
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
--- EQUALITY FOR EVERYONE! ....at least for the lichers.

local settings = get_settings()
local keeplist = settings.limited_treasures_buy_list

if not keeplist or #keeplist == 0 then
    echo("Error: The limited_treasures_buy_list setting is not set or is empty.")
    return
end

-- Walk to the shop (DR room 10205)
DRCT.walk_to(10205)

-- Wait for the shop to open.
-- Ignore "Merchant Gortik came through a curtained door" — that is Gortik leaving,
-- not opening. Break on everything else (mechanism opening, Gortik arriving, etc.).
while true do
    local trigger = waitfor(
        "disables its defense mechanisms",
        "revealing its opening",
        "Gortik .* curtained doorway%.",
        "Gortik .* through a curtained door%."
    )
    local normalized = trigger:gsub("^%s+", ""):gsub("%s+$", "")
    if not normalized:lower():match("^merchant gortik came through a curtained door%.?$") then
        break
    end
end

fput("go curtain door")

-- Check a line against the keeplist; return the matched noun or nil.
-- Uses word-boundary guards so "dragon" does not match "dragonfly".
local function match_keeplist(line)
    local lower = line:lower()
    for _, item in ipairs(keeplist) do
        local escaped = item:lower():gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
        if lower:find("%f[%a]" .. escaped .. "%f[%A]") then
            return item
        end
    end
    return nil
end

-- Inspect one stand and buy every keeplist item found.
-- Uses put()+get() to collect the full multi-line shop listing instead of
-- DRC.bput(), which returns only the first matched line and would miss
-- additional keeplist items on the same stand.
local function check_stand(stand)
    clear()
    put("shop " .. stand)

    local items_to_buy = {}

    while true do
        local line = get()
        if line then
            local lower = line:lower()
            -- Standard DR shop terminals
            if lower:find("see some details")
                or lower:find("nothing is on display")
                or lower:find("nothing for sale")
                or lower:find("the stand is empty")
            then
                break
            end
            local noun = match_keeplist(line)
            if noun then
                echo("Found keeplist item: " .. noun .. " on " .. stand)
                table.insert(items_to_buy, noun)
            end
        end
    end

    for _, noun in ipairs(items_to_buy) do
        fput("buy " .. noun .. " on " .. stand)
        fput("stow")
    end
end

-- Check all three stands
for _, stand in ipairs({ "stand", "second stand", "third stand" }) do
    check_stand(stand)
end
