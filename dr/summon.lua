--- @revenant-script
--- name: summon
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Summon familiar and max admittance charge.
--- tags: magic, familiar, summoning
--- Converted from summon.lic

local settings = get_settings()
local fam_type = settings.familiar_type or "leopard"
local container = settings.talisman_store_location or "belt"

DRCI.stow_hands()
DRC.bput("get my " .. fam_type .. " talisman in my " .. container,
    "You get", "What were you referring to")

local result = DRC.bput("summon fam",
    "You hold your talisman tightly", "You already have",
    "too short-lived for your familiar")
if result and result:find("too short-lived") then
    -- Need to build charge first
    while true do
        waitrt()
        local adm = DRC.bput("sum adm",
            "can still gather a much bigger charge",
            "can still gather a bigger charge",
            "you have reached your limit",
            "You so heavily embody")
        if adm and (adm:find("reached your limit") or adm:find("heavily embody")) then
            waitrt(); break
        end
    end
    DRC.bput("summon fam", "You hold your talisman tightly")
end

DRC.bput("tell fam to return", "will now follow you blindly", "no familiar to command")
DRC.bput("put tal in my " .. container, "You put", "What were")
DRCI.stow_hands()
DRC.fix_standing()
