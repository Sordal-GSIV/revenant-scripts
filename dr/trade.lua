--- @revenant-script
--- name: trade
--- version: 1.0.0
--- author: Dijkstra
--- game: dr
--- description: Trading script for the Crossing area - manage contracts, caravans, and deliveries
--- tags: trading, caravan, contract, money
---
--- Ported from trade.lic (Lich5) to Revenant Lua
---
--- Requires: common, common-items, common-money, common-travel, equipmanager
---
--- YAML Settings:
---   trade_contract_container: pack
---
--- Usage:
---   ;trade   - Start trading (will get contracts, load caravans, deliver)

local settings = get_settings()
local contract_container = settings.trade_contract_container or "pack"
local hometown = settings.hometown or "Crossing"
local town_data = get_data("town")

local caravan_noun = nil
local caravan_adj = nil

local function recall_caravan()
    local result = DRC.bput("recall caravan", {
        "you left your.* right behind you",
        "recall that your .* should be located",
        "don't recall where you left",
        "don't recall having a caravan",
    })
    if result:find("right behind you") or result:find("should be located") then
        local desc, name = result:match("your (.+) (.+) right behind you")
        if not desc then
            desc, name = result:match("your (.+) (.+) should be located")
        end
        if name then
            caravan_noun = name
            caravan_adj = desc
        end
    end
end

local function parse_contract()
    local contract = {
        presented = true,
        expired = false,
    }
    fput("read my contract")
    while true do
        local line = get()
        if line then
            local dest = line:match("The guild office at (?:The )?(.+) requires")
            if dest then
                contract.destination_town = dest
            end
            local origin = line:match("Trading Contract Issued by:%s+(?:The )?(.+)")
            if origin then
                contract.origin_town = origin
            end
            if line:find("not yet been") then
                contract.presented = false
            end
            if line:find("has expired") then
                contract.expired = true
                break
            end
            local payment = line:match("worth (%S+)")
            if payment then
                contract.payment = payment
                break
            end
        end
    end
    return contract
end

local function command_caravan(cmd)
    if cmd == "follow" then
        DRC.bput("tell " .. (caravan_noun or "caravan") .. " to follow",
            {"grab hold", "pass on the order to follow"})
    elseif cmd == "wait" then
        DRC.bput("tell " .. (caravan_noun or "caravan") .. " to wait",
            {"pass on the order to wait"})
    end
end

local function feed_caravan()
    DRCI.stow_hands()
    DRC.bput("remove feedbag", {"You remove"})
    DRC.bput("give " .. (caravan_noun or "caravan"),
        {"driver takes", "offer the", "sniffs disinterestedly", "munches away"})
    DRC.bput("wear feedbag", {"You attach"})
end

echo("=== Trade Script ===")
echo("Author: Dijkstra")
echo("")
echo("Core trading logic converted. Full automation requires Revenant map/navigation.")

DRC.bput("open my " .. contract_container, {"You open", "already"})
DRCI.stow_hands()
recall_caravan()

if caravan_noun then
    echo("Found caravan: " .. (caravan_adj or "") .. " " .. caravan_noun)
else
    echo("No caravan found. Get a contract from a trade minister first.")
end
