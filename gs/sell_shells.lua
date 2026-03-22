--- @revenant-script
--- @lic-audit: sell_shells.lic validated 2026-03-18
--- name: sell_shells
--- game: gs
--- description: Sell sea shells from gemsack and overflowsack at the gemshop
--- tags: utility,loot,selling

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local current_rm = tostring(Room.id)

-- Gather shells from gemsack and overflowsack
local gems = {}

local gemsack = GameObj[UserVars.gemsack]
if gemsack and gemsack.contents then
    for _, item in ipairs(gemsack.contents) do
        if item.noun == "shell" then
            table.insert(gems, item)
        end
    end
end

local overflowsack = GameObj[UserVars.overflowsack]
if overflowsack and overflowsack.contents then
    for _, item in ipairs(overflowsack.contents) do
        if item.noun == "shell" then
            table.insert(gems, item)
        end
    end
end

if #gems == 0 then
    return
end

-- Navigate to gemshop
Script.run("go2", "gemshop")
wait_while(function() return running("go2") end)

-- Sell each shell
for _, gem in ipairs(gems) do
    fput("get #" .. gem.id)
    fput("sell #" .. gem.id)
    waitrt()
    pause(0.2)
end

-- Return to starting room
Script.run("go2", current_rm)
wait_while(function() return running("go2") end)
