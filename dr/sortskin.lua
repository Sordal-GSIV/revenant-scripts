--- @revenant-script
--- name: sortskin
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Sort skins by quality between containers.
--- tags: skinning, sorting, crafting
--- Converted from sortskin.lic
--- Usage: ;sortskin <skin> <source> <qdest> <pdest> <quality> [sell]

local skin = Script.vars[1]
local source = Script.vars[2]
local qdest = Script.vars[3]
local pdest = Script.vars[4]
local quality = tonumber(Script.vars[5])
local sell = Script.vars[6]

if not skin or not source or not qdest or not pdest or not quality then
    echo("Usage: ;sortskin <skin> <source> <qdest> <pdest> <quality> [sell]")
    return
end

DRCI.stow_hands()
while DRCI.get_item(skin, source) do
    local result = DRC.bput("appraise my " .. skin .. " careful", "has a quality of %d+")
    local value = 0
    if result then
        local num = result:match("(%d+)")
        if num then value = tonumber(num) end
    end
    if value >= quality then
        DRC.bput("put my " .. skin .. " in my " .. qdest, "You put")
    elseif sell == "sell" then
        DRC.bput("sell my " .. skin, "You ask")
    else
        DRC.bput("put my " .. skin .. " in my " .. pdest, "You put")
    end
end
echo("Done sorting your " .. skin .. "s.")
