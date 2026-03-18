--- @revenant-script
--- name: origami
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Origami looper - fold/unfold paper for training
--- tags: origami, training, artisan
---
--- Usage:
---   ;origami [cycles] [design]
---   ;origami help

local DEFAULT_DESIGN = "palace"
local MAX_FOLDS = 5

local max_cycles = nil
local design = DEFAULT_DESIGN
local sack = Vars.lootsack or "knapsack"

for _, token in ipairs(script.vars) do
    if token == "help" or token == "-h" then
        echo("=== ORIGAMI LOOPER ===")
        echo(";origami [cycles] [design]")
        echo(";origami 20 palace")
        echo("Designs: palace, crane, flower, box, star, swan")
        exit()
    elseif token:match("^%d+$") then
        max_cycles = tonumber(token)
    else
        design = token
    end
end

local function has_paper()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    return (rh and rh.name and rh.name:match("paper"))
        or (lh and lh.name and lh.name:match("paper"))
end

local function get_paper()
    if has_paper() then return true end
    fput("get paper from my " .. sack)
    pause(0.3)
    return has_paper()
end

local total = 0
local folds = 0
local start = os.time()

echo("Starting: " .. (max_cycles or "unlimited") .. " cycles | design: " .. design)

if not get_paper() then echo("No paper!"); exit() end

while true do
    if max_cycles and total >= max_cycles then break end

    waitrt(); waitcastrt()
    fput("origami fold " .. design)
    pause(2); waitrt()
    fput("origami unfold")
    pause(1); waitrt()

    folds = folds + 1
    total = total + 1

    if max_cycles then
        echo("Cycle " .. total .. "/" .. max_cycles .. " (" .. folds .. "/" .. MAX_FOLDS .. " on sheet)")
    else
        echo("Cycle " .. total .. " (" .. folds .. "/" .. MAX_FOLDS .. ")")
    end

    if folds >= MAX_FOLDS then
        fput("toss my paper")
        folds = 0
        if max_cycles and total >= max_cycles then break end
        if not get_paper() then echo("No more paper."); break end
    end
end

if has_paper() then fput("put my paper in my " .. sack) end
echo("Complete! " .. total .. " cycles in " .. (os.time() - start) .. "s")
