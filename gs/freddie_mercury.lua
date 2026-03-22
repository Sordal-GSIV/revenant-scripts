--- @revenant-script
--- name: freddie_mercury
--- version: 0.6.0
--- author: unknown
--- game: gs
--- description: Automated loresinging script - captures enhancive and weapon data to CSV
--- tags: bard, loresing, enhancive, weapon
---
--- Usage: ;freddie_mercury (with item in right hand)

local rh = GameObj.right_hand()
if not rh or rh.name:match("empty") then
    echo("Hold an item in your right hand first!")
    exit()
end

local item_name = checkright() or "unknown"
local item_id = rh.id

echo("Loresinging: " .. item_name)

-- Inspect the item first
fput("inspect " .. item_name)
pause(2)

-- Attempt recall
fput("recall " .. item_name)
local recall_result = matchwait(5, "As you recall", "must reveal")

if recall_result and recall_result:match("As you recall") then
    echo("Recall successful!")
else
    -- Perform loresong
    echo("Attempting loresong...")
    wait_until(function() return checkmana() > 20 end)
    fput("speak bard")
    pause(1)
    fput("loresing " .. item_name .. " it will be helpful for me to know,;What ability within will you now show?")

    local response = {}
    while true do
        local line = get()
        if not line then break end
        table.insert(response, line)
        if line:match("Roundtime") or line:match("already loresang") or line:match("failed to resonate") then
            break
        end
    end

    -- Parse results
    for _, line in ipairs(response) do
        local amt, stat = line:match("provides .- of%s+([+-]?%d+)%s+to%s+(.-)[%.%(]")
        if amt and stat then
            echo("  Enhancive: " .. stat:match("^%s*(.-)%s*$") .. " +" .. amt)
        end
        if line:match("will crumble") then echo("  Persistence: Crumbly") end
        if line:match("will persist") then echo("  Persistence: Permanent") end
    end

    fput("speak common")
end

echo("Loresong complete for " .. item_name)
