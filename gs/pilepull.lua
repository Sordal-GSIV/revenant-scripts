--- @revenant-script
--- name: pilepull
--- version: 1.0.1
--- author: Tysong
--- contributors: Shattered community
--- game: gs
--- description: Treasure pile search automation for Shattered (1M silver per search)
--- tags: loot, mania, treasure, pile, shattered
---
--- Usage:
---   ;pilepull          - Search the pile
---   ;pilepull cleanup  - Bundle/organize found items

if script.vars[1] == "cleanup" then
    echo("Cleanup mode - bundling items...")
    -- Bundle common items
    for _, item_name in ipairs({"glowing orb", "potent yellow-green potion", "Elanthian Guilds voucher pack"}) do
        echo("Looking for " .. item_name .. " to bundle...")
    end
    exit()
end

-- Find the pile
local pile = nil
for _, obj in ipairs(GameObj.loot() or {}) do
    if obj.noun == "pile" or obj.noun == "prizes" then
        pile = obj
        break
    end
end

if not pile then
    echo("Could not find a treasure pile! Start in front of one.")
    exit()
end

local function bank_run()
    local current = Room.id
    Script.run("go2", "u8213023")
    fput("deposit all")
    fput("withdraw 100000000 silver")
    Script.run("go2", tostring(current))
end

local function handle_loot()
    waitrt()
    local rh = GameObj.right_hand()
    if rh and rh.name then
        if rh.name:match("booklet") then
            fput("redeem booklet")
        else
            fput("stow all")
        end
    end
    pause(1)
end

-- Main loop
if (Lich.silver_count and Lich.silver_count() or 0) < 1000000 then
    bank_run()
end

while true do
    local result = dothistimeout("search #" .. pile.id, 2, "You hand over 1,000,000|not enough silver|too many items")
    if result and result:match("You hand over") then
        pause(1)
        waitrt()
        handle_loot()
    elseif result and result:match("not enough silver") then
        bank_run()
    elseif result and result:match("too many items") then
        echo("Too many items! Handle that!")
        exit()
    end
end
