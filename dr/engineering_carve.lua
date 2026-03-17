--- @revenant-script
--- name: engineering_carve
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Automated engineering carving with tools.
--- tags: crafting, engineering, carving
--- Usage: ;engineering_carve <item> <tool> <material>

local carve_item = Script.vars[1]
local carve_tool = Script.vars[2]
local carve_material = Script.vars[3]
if not carve_item or not carve_tool or not carve_material then
    echo("Usage: ;engineering_carve <item> <tool> <material>") return
end

fput("get carv book"); fput("study carv book"); waitrt(); pause(0.5)
fput("stow left"); fput("stow right")
fput("get " .. carve_tool); fput("carve " .. carve_material .. " with " .. carve_tool)

while true do
    local line = get()
    if not line then goto continue end
    if line:find("Applying the final touches") then
        echo(carve_item .. " completed."); break
    elseif line:find("jagged shards") then
        waitrt(); fput("stow left"); fput("get riffler")
        fput("rub " .. carve_item .. " with riff"); waitrt()
    elseif line:find("uneven") or line:find("no longer level") then
        waitrt(); fput("stow left"); fput("get rasp")
        fput("rub " .. carve_item .. " with rasp"); waitrt()
    elseif line:find("Roundtime") or line:find("without any mistakes") or line:find("no flaws") or line:find("uniform texture") then
        waitrt(); fput("stow left"); fput("stow right")
        fput("get " .. carve_tool); fput("carve " .. carve_item .. " with " .. carve_tool)
    end
    ::continue::
end
